package network::modem;	# $Id$

use strict;
use common;
use any;
use modules;
use detect_devices;
use mouse;
use network::tools;


#-----modem conf
sub ppp_configure {
    my ($in, $modem) = @_;
    $modem or return;
    $in->do_pkgs->install('ppp') if !$::testing;
    $in->do_pkgs->install('kdenetwork-kppp') if !$::testing &&$in->do_pkgs->is_installed('kdebase');

    any::devfssymlinkf($modem, 'modem') if $modem->{device} ne "/dev/modem";

    my %toreplace = map { $_ => $modem->{$_} } qw(auth AutoName connection dns1 dns2 domain IPAddr login passwd phone SubnetMask);
    $toreplace{kpppauth} = ${{ N('Script-based') => 0, N('PAP') => 1, N('Terminal-based') => 2, N('CHAP') => 3, N('PAP/CHAP') => 4 }}{$modem->{auth}};
    $toreplace{phone} =~ s/[a-zA-Z]//g;
    if ($modem->{auto_dns} ne N("Automatic")) {
        $toreplace{dnsserver} = join ',', map { $modem->{$_} } "dns1", "dns2";
        $toreplace{dnsserver} .= $toreplace{dnsserver} && ',';
    }

    #- using peerdns or dns1,dns2 avoid writing a /etc/resolv.conf file.
    $toreplace{peerdns} = "yes";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{intf} ||= 'ppp0';
    $toreplace{papname} = ($modem->{auth} eq 'PAP' || $modem->{auth} eq 'CHAP') && $toreplace{login};

    # handle static/dynamic settings:
    if ($modem->{auto_ip} eq N("Automatic")) {
        $toreplace{$_} = '0.0.0.0' foreach qw(IPAddr SubnetMask) ;
    } else {
        $toreplace{$_} = $modem->{$_} foreach qw(IPAddr SubnetMask) ;
    }
    $toreplace{Gateway} = $modem->{auto_gateway} eq N("Automatic") ? '0.0.0.0' : $modem->{Gateway};


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
           if_($modem->{auto_dns} ne N("Automatic"), map { qq(DNS$_=$toreplace{"dns$_"}\n) } grep { $toreplace{"dns$_"} } 1..2));

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
	    append_to_file($secrets, qq($toreplace{login}  ppp0  "$toreplace{passwd}"\n));
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
AutoName=$toreplace{AutoName}
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
SubnetMask=$toreplace{SubnetMask}
AccountingFile=
DefaultRoute=1
Username=$toreplace{login}
Gateway=$toreplace{Gateway}
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

1;
