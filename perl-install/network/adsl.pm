package network::adsl; # $Id$

use common;
use run_program;
use network::tools;
use network::ethernet;
use modules;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_conf_backend);


sub get_wizard {
    my ($wiz) = @_;
    my $netc = $wiz->{var}{netc};

    my %l = (
	     'pppoe' =>  N("use pppoe"),
	     'pptp'  =>  N("use pptp"),
	     'dhcp'  =>  N("use dhcp"),
	     'speedtouch' => N("Alcatel speedtouch usb") . if_($netc->{autodetect}{adsl}{speedtouch}, N(" - detected")),
	     'sagem' =>  N("Sagem (using pppoa) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
	     'sagem_dhcp' =>  N("Sagem (using dhcp) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
          # 'eci' => N("ECI Hi-Focus"), # this one needs eci agreement
	    );
    
    $wiz->{var}{adsl} = {
                         connection_list => \%l,
                         type => "",
                        };
    add2hash($wiz->{pages},
             {
              adsl_old => {
                       name => N("Connect to the Internet") . "\n\n" .
                       N("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few use dhcp.
If you don't know, choose 'use pppoe'"),
                       data =>  [
                                 {
                                  label => N("ADSL connection type :"), val => \$wiz->{var}{adsl}{type}, list => [ sort values %l ] },
                                ],
                       pre => sub {
                           $wiz->{var}{adsl}{type} = $l{sagem}; # debug
                           $wiz->{var}{adsl}{type} ||= find { $netc->{autodetect}{adsl}{$_} } keys %l;
                           print "\n\ntype is «$wiz->{var}{adsl}{type}»\n\n";
                       },
                       post => sub {
                           $wiz->{var}{adsl}{type} = find { $l{$_} eq $wiz->{var}{adsl}{type} } keys %l;
                           my $adsl   = $wiz->{var}{adsl}{connection};
                           my $type   = $wiz->{var}{adsl}{type};
                           my $netcnx = $wiz->{var}{netcnx};
                           $netcnx->{type} = "adsl_$type";
                                         
                           my %packages = (
                                           'dhcp'  => [ 'dhcpcd' ],
                                           'eci'   => [ 'eciadsl' ],
                                           'pppoe' => [ 'rp-pppoe' ],
                                           'pptp'  => [ 'pptp-adsl' ],
                                           'sagem' => [ 'adiusbadsl' ],
                                           'sagem_dhcp' => [ qw(adiusbadsl dhcpcd) ],
                                           'speedtouch' => [ 'speedtouch' ],
                                          );
                           $in->do_pkgs->install(@{$packages{$type}});
                           $netcnx->{"adsl_$type"} = {};
                           $netcnx->{"adsl_$type"}{vpivci} = '' if $type =~ /eci|speedtouch/;
                           return 'ethernet' if $type eq 'dhcp';
                           adsl_probe_info($adsl, $netc, $type);
                           # my ($adsl, $netc, $intf, $adsl_type) = @_;
                           # ask_info2($adsl, $netc);
                           return "hw_account";
                       },
                      },
              adsl_conf2 => {
                             #$adsl_type =~ /sagem|speedtouch|eci/ or conf_network_card($netc, $intf, 'static', '10.0.0.10') or goto adsl_conf_step_1;
                             #adsl_conf_backend($adsl, $netc, $adsl_type) or goto adsl_conf_step_1;
                             #1;
                            },
              ethernet => {
                           #go_ethernet($netc, $intf, 'dhcp', '', '', $first_time);
                          },
              adsl_old_end => {
                      post => sub {
                          $wiz->{var}{adsl}{type} =~ /speedtouch|eci/ or $netconnect::need_restart_network = 1;
                      },
                     },
             });
};

sub adsl_probe_info {
    my ($adsl, $netc, $adsl_type, $adsl_modem) = @_;
    my $pppoe_file = "$::prefix/etc/ppp/pppoe.conf";
    my $pptp_file = "$::prefix/etc/sysconfig/network-scripts/net_cnx_up";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (! defined $adsl_type || $adsl_type =~ /pppoe/) && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/adsl /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+"([^"]+)"/, $1) } cat_("$::prefix/$_") if !$login && -r "$::prefix/$_";
    }
    ($login) = map { if_(/\sname\s+([^ \n]+)/, $1) } cat_($pptp_file) if (! defined $adsl_type || $adsl_type =~ /pptp/) && -r $pptp_file;
    my $passwd = passwd_by_login($login);
    ($netc->{vpivci}) = 
      map { if_(/^.*-vpi\s+(\d+)\s+-vci\s+(\d+)/, "$1_$2") } cat_("$::prefix/etc/ppp/peers/adsl") if $adsl_modem eq 'speedtouch';
    $pppoe_conf{DNS1} ||= '';
    $pppoe_conf{DNS2} ||= '';
    add2hash($netc, { dnsServer2 => $pppoe_conf{DNS1}, dnsServer3 => $pppoe_conf{DNS2}, DOMAINNAME2 => '' });
    add2hash($adsl, { login => $login, passwd => $passwd, passwd2 => '' });
}

sub adsl_detect() {
    my $adsl = {};
    require detect_devices;
    $adsl->{speedtouch} = detect_devices::getSpeedtouch();
    $adsl->{sagem} = detect_devices::getSagem();
    $adsl->{eci} = detect_devices::getECI();
    return $adsl;
}

sub adsl_conf_backend {
    my ($adsl, $netc, $adsl_type, $o_netcnx) = @_;
    defined $o_netcnx and $netc->{adsltype} = $o_netcnx->{type};
    $netc->{adsltype} ||= "adsl_$adsl_type";
    mkdir_p("$::prefix/etc/ppp");
    output("$::prefix/etc/ppp/options",
'lock
noipdefault
persist
noauth
usepeerdns
defaultroute
') if $adsl_type =~ /pptp|pppoe|speedtouch|eci/;

    write_secret_backend($adsl->{login}, $adsl->{passwd});

    if ($adsl_type eq 'pppoe') {
	substInFile {
	    s/ETH=.*\n/ETH=$netc->{NET_DEVICE}\n/;
	    s/USER=.*\n/USER=$adsl->{login}\n/;
	    s/DNS1=.*\n/DNS1=$netc->{dnsServer2}\n/;
	    s/DNS2=.*\n/DNS2=$netc->{dnsServer3}\n/;
	} "$::prefix/etc/ppp/pppoe.conf";
    }

    if ($adsl_type eq 'sagem') {
	substInFile {
	    s/VCI=.*\n/VCI=00000023\n/;
	    s/Encapsulation=.*\n/Encapsulation=00000006\n/;
	} "$::prefix/etc/analog/adiusbadsl";
	output("$::prefix/etc/ppp/peers/adsl",
qq(noauth
noipdefault
pty "/usr/sbin/pppoa -I `/usr/sbin/adictrl -s; /usr/sbin/adictrl -i`"
mru 1492
mtu 1492
kdebug 1
nobsdcomp
nodeflate
noaccomp -am
nopcomp
noccp
novj
novjccomp
holdoff 4
maxfail 25
persist
usepeerdns
defaultroute
user "$adsl->{login}"
));
    }

    if ($adsl_type eq 'sagem_dhcp') {
	substInFile {
	    s/VCI=.*\n/VCI=00000024\n/;
	    s/Encapsulation=.*\n/Encapsulation=00000004\n/;
	} "$::prefix/etc/analog/adiusbadsl";
    }

    if ($adsl_type eq 'speedtouch') {
	my ($vpi, $vci) = $netc->{vpivci} =~ /(\d+)_(\d+)/ or return;
	output("$::prefix/etc/ppp/peers/adsl", 
qq(noauth
noipdefault
pty "/usr/sbin/pppoa3 -e 1 -c -vpi $vpi -vci $vci"
sync
kdebug 1
noaccomp
nopcomp
noccp
novj
holdoff 4
maxfail 25
persist
usepeerdns
defaultroute
user "$adsl->{login}"
));
	modules::add_alias($_->[0], $_->[1]) foreach  ['speedtch', 'off'],
	                                              ['char-major-108', 'ppp_generic'],
						      ['tty-ldisc-3', 'ppp_async'],
						      ['tty-ldisc-13', 'n_hdlc'],
						      ['tty-ldisc-14', 'ppp_synctty'],
						      ['ppp-compress-21', 'bsd_comp'],
						      ['ppp-compress-24', 'ppp_deflate'],
						      ['ppp-compress-26', 'ppp_deflate'];
	$::isStandalone and modules::write_conf();
    }
    
    if ($adsl_type eq 'eci') {
	my ($vpi, $vci) = $netc->{vpivci} =~ /(\d+)_(\d+)/ or return;
	output("$::prefix/etc/ppp/peers/adsl", 
qq(debug
kdebug 1
noipdefault
defaultroute
pty "/usr/bin/pppoeci -v 1 -vpi $vpi -vci $vci"
sync
noaccomp
nopcomp
noccp
novj
holdoff 10
user "$adsl->{login}"
linkname eciadsl
maxfail 10
usepeerdns
noauth
lcp-echo-interval 0
));
	modules::add_alias($_->[0], $_->[1]) foreach  ['char-major-108', 'ppp_generic'],
						      ['tty-ldisc-14', 'ppp_synctty'],
						      ['tty-ldisc-13', 'n_hdlc'];
	$::isStandalone and modules::write_conf();
    }

    if ($adsl_type eq 'pptp') {
	write_cnx_script($netc, "adsl",
"/sbin/route del default
/usr/bin/pptp 10.0.0.138 name $adsl->{login}
",
'/usr/bin/killall pptp pppd
', $netc->{adsltype}) } elsif ($adsl_type eq 'pppoe') {
    write_cnx_script($netc, "adsl",
"/sbin/route del default
LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C /usr/sbin/adsl-start $netc->{NET_DEVICE} $adsl->{login}
",
'/usr/sbin/adsl-stop
/usr/bin/killall pppoe pppd
', $netc->{adsltype}) } elsif ($adsl_type eq 'speedtouch') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/share/speedtouch/speedtouch.sh start
',
'/usr/share/speedtouch/speedtouch.sh stop
', $netc->{adsltype}) } elsif ($adsl_type eq 'sagem') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/sbin/adictrl -w
#INTERFACE=`/usr/sbin/adictrl -i`
#/sbin/ifconfig $INTERFACE 192.168.60.30 netmask 255.255.255.0 up
/usr/sbin/pppd file /etc/ppp/peers/adsl
',
'/usr/sbin/stopadsl
', $netc->{adsltype}) } elsif ($adsl_type eq 'sagem_dhcp') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/sbin/adictrl -w
INTERFACE=`/usr/sbin/adictrl -i`
/sbin/dhcpcd $INTERFACE
',
'INTERFACE=`/usr/sbin/adictrl -i`
/sbin/ifdown $INTERFACE
', $netc->{adsltype}) } elsif ($adsl_type eq 'eci') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/bin/startmodem
',
"# stop is still beta...
echo 'not yet implemented, still beta software'
", $netc->{adsltype}) }

    $netc->{NET_INTERFACE} = 'ppp0';
}

1;
