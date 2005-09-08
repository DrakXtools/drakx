package network::modem;	# $Id$

use strict;
use common;
use any;
use modules;
use detect_devices;
use network::network;
use network::tools;

sub get_user_home() {
    my $home;
    if ($ENV{USER} ne "root") {
        #- kdesu case
        my $user = find { $_->[0] eq $ENV{USER} } list_passwd();
        $home = $user->[7] if $user;
    }
    $home ||= $ENV{HOME}; #- consolehelper case
    $home;
}

sub ppp_read_conf() {
    my $modem = {};
    my %l = getVarsFromSh(get_user_home() . "/.kde/share/config/kppprc");
    add2hash(\%l, getVarsFromSh("$::prefix/usr/share/config/kppprc"));
    $l{Authentication} = 4 if $l{Authentication} !~ /\d/;
    $modem->{$_} ||= $l{$_} foreach qw(Authentication Gateway IPAddr SubnetMask);
    $modem->{connection} ||= $l{Name};
    $modem->{domain} ||= $l{Domain};
    ($modem->{dns1}, $modem->{dns2}) = split(',', $l{DNS});
    
    foreach (cat_("/etc/sysconfig/network-scripts/chat-ppp0")) {
        /.*ATDT([\d#*]*)/ and $modem->{phone} ||= $1;
    }
    foreach (cat_("/etc/sysconfig/network-scripts/ifcfg-ppp0")) {
        /NAME=(['"]?)(.*)\1/ and $modem->{login} ||= $2;
        /^METRIC=(.*)/ and $modem->{METRIC} = $1;
    }
    $modem->{login} ||= $l{Username};
    my $secret = network::tools::read_secret_backend();
    foreach (@$secret) {
        $modem->{passwd} ||= $_->{passwd} if $_->{login} eq $modem->{login};
    }
    #my $secret = network::tools::read_secret_backend();
    #my @cnx_list = map { $_->{server} } @$secret;
    $modem->{$_} ||= '' foreach qw(connection phone login passwd auth domain dns1 dns2);
    $modem->{auto_gateway} ||= defined $modem->{Gateway} && $modem->{Gateway} ne '0.0.0.0' ? N("Manual") : N("Automatic");
    $modem->{auto_ip} ||=  defined $modem->{IPAddr} && $modem->{IPAddr} ne '0.0.0.0' ? N("Manual") : N("Automatic");
    $modem->{auto_dns} ||= $modem->{dns1} || $modem->{dns2} ? N("Manual") : N("Automatic");
    $modem->{device} ||= '/dev/modem';
    $modem;
}

#-----modem conf
sub ppp_configure {
    my ($net, $in, $modem) = @_;
    $in->do_pkgs->install('ppp') if !$::testing;
    $in->do_pkgs->install('kdenetwork-kppp') if !$::testing && $in->do_pkgs->is_installed('kdebase');

    if ($modem->{device} ne "/dev/modem") {
        my $dev = $modem->{device};
        $dev =~ s!^/dev/!!;
        any::devfssymlinkf({ device => $dev }, 'modem');
    }

    my %toreplace = map { $_ => $modem->{$_} } qw(Authentication AutoName connection dns1 dns2 domain IPAddr login passwd phone SubnetMask);
    $toreplace{phone} =~ s/[^\d#*]//g;
    if ($modem->{auto_dns} ne N("Automatic")) {
        $toreplace{dnsserver} = join ',', map { $modem->{$_} } "dns1", "dns2";
        $toreplace{dnsserver} .= $toreplace{dnsserver} && ',';
    }

    #- using peerdns or dns1,dns2 avoid writing a /etc/resolv.conf file.
    $toreplace{peerdns} = "yes";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{papname} = $toreplace{login} if member($modem->{Authentication}, 1, 3, 4);

    # handle static/dynamic settings:
    if ($modem->{auto_ip} eq N("Automatic")) {
        $toreplace{$_} = '0.0.0.0' foreach qw(IPAddr SubnetMask);
    } else {
        $toreplace{$_} = $modem->{$_} foreach qw(IPAddr SubnetMask);
    }
    $toreplace{Gateway} = $modem->{auto_gateway} eq N("Automatic") ? '0.0.0.0' : $modem->{Gateway};

    $toreplace{METRIC} = defined($modem->{METRIC}) ? $modem->{METRIC} : network::tools::get_default_metric("modem");

    $net->{ifcfg}{ppp0} = {
        DEVICE => "ppp0",
        ONBOOT => "no",
        USERCTL => "no",
        MODEMPORT => "/dev/modem",
        LINESPEED => "115200",
        PERSIST => "yes",
        DEFABORT => "yes",
        DEBUG => "yes",
        INITSTRING => "ATZ",
        DEFROUTE => "yes",
        HARDFLOWCTL => "yes",
        ESCAPECHARS => "no",
        PPPOPTIONS => "",
        PAPNAME => $toreplace{papname},
        REMIP => "",
        NETMASK => "",
        IPADDR => "",
        MRU => "",
        MTU => "",
        DISCONNECTTIMEOUT => "5",
        RETRYTIMEOUT => "60",
        BOOTPROTO => "none",
        PEERDNS => $toreplace{peerdns},
        METRIC => $toreplace{METRIC},
        if_($modem->{auto_dns} ne N("Automatic"),
            map { qq(DNS$_=$toreplace{"dns$_"}\n) } grep { $toreplace{"dns$_"} } 1..2),
    };

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
'TIMEOUT' '120'
'CONNECT' ''
END
    if (member($modem->{Authentication}, 0, 2)) {
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

    network::tools::write_secret_backend($toreplace{login}, $toreplace{passwd});

    #- install kppprc file according to used configuration.
    mkdir_p("$::prefix/usr/share/config");

    $toreplace{$_->[0]} = $modem->{$_->[0]} || $_->[1] foreach [ 'Timeout', 60 ], [ 'UseLockFile', 1 ], [ 'Enter', 'CR' ], [ 'Volume', 0 ],
                                                               [ 'BusyWait', 0 ], [ 'FlowControl', 'CRTSCTS' ], [ 'Speed', 115200 ];
    output($modem->{kppprc} || "$::prefix/usr/share/config/kppprc", c::to_utf8(<<END));
# KDE Config File

[Account0]
ExDNSDisabled=0
AutoName=$toreplace{AutoName}
ScriptArguments=
AccountingEnabled=0
DialString=ATDT
Phonenumber=$toreplace{phone}
IPAddr=$toreplace{IPAddr}
Domain=$toreplace{domain}
Name=$toreplace{connection}
VolumeAccountingEnabled=0
pppdArguments=
Password=$toreplace{passwd}
BeforeDisconnect=
Command=
ScriptCommands=
Authentication=$toreplace{Authentication}
DNS=$toreplace{dnsserver}
SubnetMask=$toreplace{SubnetMask}
AccountingFile=
DefaultRoute=1
Username=$toreplace{login}
Gateway=$toreplace{Gateway}
StorePassword=1
DisconnectCommand=

[Modem]
BusyWait=$toreplace{BusyWait}
Enter=$toreplace{Enter}
FlowControl=$toreplace{FlowControl}
Volume=$toreplace{Volume}
Timeout=$toreplace{Timeout}
UseCDLine=0
UseLockFile=$toreplace{UseLockFile}
Device=/dev/modem
Speed=$toreplace{Speed}

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
