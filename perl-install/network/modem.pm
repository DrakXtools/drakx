package network::modem;

use common;
use any;
use modules;
use detect_devices;
use mouse;
use network::tools;
use Data::Dumper;

sub configure {
    my ($in, $netcnx, $mouse, $netc, $_intf) = @_;
    $netcnx->{type} = 'modem';
    my $modem = $netcnx->{$netcnx->{type}};
#    $netcnx->{$netcnx->{type}} = {};
    $modem->{device} = $netc->{autodetect}{modem};
#  modem_step_1:
#    $modem->{login} = ($modem->{auth} eq 'PAP' ||$modem->{auth} eq 'CHAP') && $intf->{ppp0}{PAPNAME};
#    $netcnx->{$netcnx->{type}}->{connection} = ($netcnx->{$netcnx->{type}}->{auth} eq 'PAP' || $netcnx->{$netcnx->{type}}->{auth} eq 'CHAP') && $intf->{ppp0}{PAPNAME};
#    $modem->{device} = readlink "$::prefix/dev/modem";
    foreach (cat_("/usr/share/config/kppprc")) {
	/^DNS=(.*)$/ and ($modem->{dns1}, $modem->{dns2}) = split(',', $1);
    }
    my $secret = network::tools::read_secret_backend();
    foreach (@$secret) {
	$modem->{passwd} = $_->{passwd} if $_->{login} eq $modem->{login};
    }

    foreach (cat_("/etc/sysconfig/network-scripts/chat-ppp0")) {
	if (/.*ATDT(\d*).*/) {
	    $modem->{phone} = $1;
	    last;
	}
    }
    ppp_choose($in, $netc, $modem, $mouse) or return;
    write_cnx_script($netc, "modem",
q(
/sbin/route del default
ifup ppp0
),
q(ifdown ppp0
killall pppd
), $netcnx->{type});
    1;
}

#-----modem conf
sub ppp_configure {
    my ($in, $modem) = @_;
    $modem or return;
    $in->do_pkgs->install('ppp') if !$::testing;
    ppp_configure_raw($modem);
}

sub ppp_configure_raw {
    my ($modem) = @_;
    any::devfssymlinkf($modem, 'modem') if $modem->{device} ne "/dev/modem";

    my %toreplace;
    $toreplace{$_} = $modem->{$_} foreach qw(connection phone login passwd auth domain dns1 dns2);
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, 'PAP' => 1, 'Terminal-based' => 2, }}{$modem->{auth}};
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, 'PAP' => 1, 'Terminal-based' => 2, 'CHAP' => 3 }}{$modem->{auth}};
    $toreplace{phone} =~ s/[a-zA-Z]//g;
    $toreplace{dnsserver} = join ',', map { $modem->{$_} } "dns1", "dns2";
    $toreplace{dnsserver} .= $toreplace{dnsserver} && ',';

    #- using peerdns or dns1,dns2 avoid writing a /etc/resolv.conf file.
    $toreplace{peerdns} = "yes";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{intf} ||= 'ppp0';
    $toreplace{papname} = ($modem->{auth} eq 'PAP' || $modem->{auth} eq 'CHAP') && $toreplace{login};

    #- build ifcfg-ppp0.
    my $various = <<END;
DEVICE="$toreplace{intf}"
ONBOOT="no"
USERCTL="no"
MODEMPORT="/dev/modem"
LINESPEED="115200"
PERSIST="yes"
DEFABORT="yes"
DEBUG="yes"
INITSTRING="ATZ"
DEFROUTE="yes"
HARDFLOWCTL="yes"
ESCAPECHARS="no"
PPPOPTIONS=""
PAPNAME="$toreplace{papname}"
REMIP=""
NETMASK=""
IPADDR=""
MRU=""
MTU=""
DISCONNECTTIMEOUT="5"
RETRYTIMEOUT="60"
BOOTPROTO="none"
PEERDNS="$toreplace{peerdns}"
END
    output("$::prefix/etc/sysconfig/network-scripts/ifcfg-ppp0", 
	   $various,
	   map { qq(DNS$_=$toreplace{"dns$_"}\n) } grep { $toreplace{"dns$_"} } 1..2);

    #- build chat-ppp0.
    my @chat = <<END;
'ABORT' 'BUSY'
'ABORT' 'ERROR'
'ABORT' 'NO CARRIER'
'ABORT' 'NO DIALTONE'
'ABORT' 'Invalid Login'
'ABORT' 'Login incorrect'
'' 'ATZ'
END
    if ($modem->{special_command}) {
	push @chat, <<END;
'OK' '$modem->{special_command}'
END
    }
    push @chat, <<END;
'OK' 'ATDT$toreplace{phone}'
'CONNECT' ''
END
    if ($modem->{auth} eq 'Terminal-based' || $modem->{auth} eq 'Script-based') {
	push @chat, <<END;
'ogin:--ogin:' '$toreplace{login}'
'ord:' '$toreplace{passwd}'
END
    }
    push @chat, <<END;
'TIMEOUT' '5'
'~--' ''
END
    my $chat_file = "$::prefix/etc/sysconfig/network-scripts/chat-ppp0";
    output_with_perm($chat_file, 0600, @chat);

    if ($modem->{auth} eq 'PAP' || $modem->{auth} eq 'CHAP') {
	#- need to create a secrets file for the connection.
	my $secrets = "$::prefix/etc/ppp/" . lc($modem->{auth}) . "-secrets";
	my @l = cat_($secrets);
	my $replaced = 0;
	do { $replaced ||= 1
	       if s/^\s*"?$toreplace{login}"?\s+ppp0\s+(\S+)/"$toreplace{login}"  ppp0  "$toreplace{passwd}"/ } foreach @l;
	if ($replaced) {
	    output($secrets, @l);
        } else {
	    append_to_file($secrets, "$toreplace{login}  ppp0  \"$toreplace{passwd}\"\n");
	}
	#- restore access right to secrets file, just in case.
	chmod 0600, $secrets;
    }

    #- install kppprc file according to used configuration.
    mkdir_p("$::prefix/usr/share/config");

    output("$::prefix/usr/share/config/kppprc", c::to_utf8(<<END));
# KDE Config File
[Account0]
ExDNSDisabled=0
AutoName=0
ScriptArguments=
AccountingEnabled=0
DialString=ATDT
Phonenumber=$toreplace{phone}
IPAddr=0.0.0.0
Domain=$toreplace{domain}
Name=$toreplace{connection}
VolumeAccountingEnabled=0
pppdArguments=
Password=$toreplace{passwd}
BeforeDisconnect=
Command=
ScriptCommands=
Authentication=$toreplace{kpppauth}
DNS=$toreplace{dnsserver}
SubnetMask=0.0.0.0
AccountingFile=
DefaultRoute=1
Username=$toreplace{login}
Gateway=0.0.0.0
StorePassword=1
DisconnectCommand=
[Modem]
BusyWait=0
Enter=CR
FlowControl=CRTSCTS
Volume=0
Timeout=60
UseCDLine=0
UseLockFile=1
Device=/dev/modem
Speed=115200
[Graph]
InBytes=0,0,255
Text=0,0,0
Background=255,255,255
Enabled=true
OutBytes=255,0,0
[General]
QuitOnDisconnect=0
ShowLogWindow=0
DisconnectOnXServerExit=1
DefaultAccount=$toreplace{connection}
iconifyOnConnect=1
Hint_QuickHelp=0
AutomaticRedial=0
PPPDebug=0
NumberOfAccounts=1
ShowClock=1
DockIntoPanel=0
pppdTimeout=30
END
    network::network::proxy_configure($::o->{miscellaneous});
}

sub ppp_choose {
    my ($in, $netc, $modem, $mouse) = @_;
    $mouse ||= {};

    $mouse->{device} ||= readlink "$::prefix/dev/mouse";
    $::isInstall and $in->set_help('selectSerialPort');
    $modem->{device} ||= $in->ask_from_listf('', N("Please choose which serial port your modem is connected to."),
					     \&mouse::serial_port2text,
					     [ grep { $_ ne $mouse->{device} } (mouse::serial_ports(), if_(-e '/dev/modem', '/dev/modem')) ]) || return;

    my @cnx_list;
    my $secret = network::tools::read_secret_backend();
    foreach (@$secret) {
	push @cnx_list, $_->{server};
    }
    $::isStandalone || $in->set_help('configureNetworkISP');
    $in->ask_from('', N("Dialup options"), [
{ label => N("Connection name"), val => \$modem->{connection} },
{ label => N("Phone number"), val => \$modem->{phone} },
{ label => N("Login ID"), val => \$modem->{login} },
{ label => N("Password"), val => \$modem->{passwd}, hidden => 1 },
{ label => N("Authentication"), val => \$modem->{auth}, list => [ N_("PAP"), N_("Terminal-based"), N_("Script-based"), N_("CHAP") ] },
{ label => N("Domain name"), val => \$modem->{domain} },
{ label => N("First DNS Server (optional)"), val => \$modem->{dns1} },
{ label => N("Second DNS Server (optional)"), val => \$modem->{dns2} },
    ]) or return;
    $netc->{DOMAINNAME2} = $modem->{domain};
    ppp_configure($in, $modem);
    $netc->{$_} = 'ppp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
    1;
}

#- TODO: add choice between hcf/hsf
sub winmodemConfigure {
    my ($in, $netc) = @_;
    my $type;
    
    foreach (keys %{$netc->{autodetect}{winmodem}}) {
    	my $temp;
    	/Hcf/ and $temp = "hcf";
    	/Hsf/ and $temp = "hsf";
    	$temp and $in->do_pkgs->what_provides("${temp}linmodem") and $type = "${temp}linmodem";
    }
    
    $type || $in->ask_warn(N("Warning"), N("Your modem isn't supported by the system.
Take a look at http://www.linmodems.org")) && return 1;
    my $e = $in->ask_from_list(N("Title"), N("\"%s\" based winmodem detected, do you want to install needed software ?", $type), [N("Install rpm"), N("Do nothing")]) or return 0;
    $e =~ /rpm/ ? $in->do_pkgs->install($type) : return 1;
    1;
}

1;
