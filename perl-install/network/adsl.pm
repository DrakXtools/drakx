package network::adsl;

use common;
use run_program;
use network::tools;
use network::ethernet;
use modules;
use Data::Dumper;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_ask_info adsl_detect adsl_conf adsl_conf_backend);

sub configure {
    my ($netcnx, $netc, $intf, $first_time) = @_;
    $::isInstall and $in->set_help('configureNetworkADSL');

  conf_adsl_step1:
    my $l = [ N_("use pppoe"),
	      N_("use pptp"), 
	      N_("use dhcp"), 
	      N_("Alcatel speedtouch usb") . if_($netc->{autodetect}{adsl}{speedtouch}, " - detected"),
	      N_("Sagem (using pppoe) usb") . if_($netc->{autodetect}{adsl}{sagem}, " - detected"),
	     ];
    my $type = $in->ask_from_list_(N("Connect to the Internet"),
				   N("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few ones use dhcp.
If you don't know, choose 'use pppoe'"), $l) or return;
    $type =~ s/use //;
    if ($type eq 'pppoe') {
	$in->do_pkgs->install("rp-$type");
	$netcnx->{type} = "adsl_$type";
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
    #- use pppoe for Sagem modem, but NET_DEVICE is now ADIModem instead of ethx.
    if ($type =~ /Sagem/) {
	$in->do_pkgs->install(qw(rp-pppoe adiusbadsl));
	$netcnx->{type} = "adsl_pppoe";
	$netcnx->{adsl_pppoe} = {};
	modules::add_alias('ADIModem', 'adiusbadsl');
	$netc->{$_} = 'ADIModem' foreach qw(NET_DEVICE NET_INTERFACE);
	adsl_conf($netcnx->{adsl_pppoe}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
    if ($type eq 'dhcp') {
	$in->do_pkgs->install(qw(dhcpcd));
	go_ethernet($netc, $intf, 'dhcp', '', '', $first_time) or goto conf_adsl_step1;
    }
    if ($type eq 'pptp') {
	$in->do_pkgs->install(qw(pptp-adsl));
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
    if ($type =~ /speedtouch/) {
	$type = 'speedtouch';
	$in->do_pkgs->install(qw(speedtouch));
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	$netcnx->{"adsl_$type"}{vpivci} = '';
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
    # if ($type =~ /ECI/) {
# 	$type = 'eci';
# 	$in->do_pkgs->install(qw(eciadsl));
# 	$netcnx->{type} = "adsl_$type";
# 	$netcnx->{"adsl_$type"} = {};
# 	$netcnx->{"adsl_$type"}{vpivci} = '';
# 	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
#     }
    $type =~ /speedtouch|eci/ or $netconnect::need_restart_network = 1;
    1;
}

sub adsl_ask_info {
    my ($adsl, $netc, $_intf, $adsl_type) = @_;
    my $pppoe_file = "/etc/ppp/pppoe.conf";
    my $pppoe_conf = { getVarsFromSh($pppoe_file) } if $adsl_type =~ /pppoe/ && -f $pppoe_file;
    $pppoe_conf->{DNS1} ||= '';
    $pppoe_conf->{DNS2} ||= '';
    add2hash($netc, { dnsServer2 => $pppoe_conf->{DNS1}, dnsServer3 => $pppoe_conf->{DNS2}, DOMAINNAME2 => '' });
    add2hash($adsl, { login => $pppoe_conf->{USER}, passwd => passwd_by_login($pppoe_conf->{USER}), passwd2 => '' });
    ask_info2($adsl, $netc);
}

sub adsl_detect {
    my ($adsl) = @_;
    require detect_devices;
    $adsl->{speedtouch} = detect_devices::getSpeedtouch();
    $adsl->{sagem} = detect_devices::getSagem();
    return $adsl if $adsl->{speedtouch} || $adsl->{sagem};
}

sub adsl_conf {
    my ($adsl, $netc, $intf, $adsl_type) = @_;

  adsl_conf_step_1:
    adsl_ask_info($adsl, $netc, $intf, $adsl_type) or return;
  adsl_conf_step_2:
    $adsl_type =~ /speedtouch|eci/ or conf_network_card($netc, $intf, 'static', '10.0.0.10') or goto adsl_conf_step_1;
    adsl_conf_backend($adsl, $netc, $adsl_type);
    1;
}

sub adsl_conf_backend {
    my ($adsl, $netc, $adsl_type, $netcnx) = @_;
    defined $netcnx and $netc->{adsltype} = $netcnx->{type};
    $netc->{adsltype} ||= "adsl_$adsl_type";
    mkdir_p("$prefix/etc/ppp");
    output("$prefix/etc/ppp/options",
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
	} "$prefix/etc/ppp/pppoe.conf";
    }

    if ($adsl_type eq 'speedtouch') {
	$netc->{vpivci} =~ /(\d+)_(\d+)/;
	output("$prefix/etc/ppp/peers/adsl", 
qq(noauth
noipdefault
pty "/usr/bin/pppoa3 -vpi $1 -vci $2"
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
	modules::add_alias($_->[0], $_->[1]) foreach  ['char-major-108', 'ppp_generic'],
						      ['tty-ldisc-3', 'ppp_async'],
						      ['tty-ldisc-13', 'n_hdlc'],
						      ['tty-ldisc-14', 'ppp_synctty'],
						      ['ppp-compress-21', 'bsd_comp'],
						      ['ppp-compress-24', 'ppp_deflate'],
						      ['ppp-compress-26', 'ppp_deflate'];
	$::isStandalone and modules::write_conf($prefix);
	$in->do_pkgs->what_provides("speedtouch_mgmt") and $in->do_pkgs->install('speedtouch_mgmt');
	-e "$prefix/usr/share/speedtouch/mgmt.o" or $in->ask_warn('', N("You need the alcatel microcode.
Download it at
http://www.speedtouchdsl.com/dvrreg_lx.htm
and copy the mgmt.o in /usr/share/speedtouch"));
    }

if ($adsl_type eq 'eci') {
    $netc->{vpivci} =~ /(\d+)_(\d+)/;
    output("$prefix/etc/ppp/peers/adsl", 
qq(debug
kdebug 1
noipdefault
defaultroute
pty "/usr/bin/pppoeci -v 1 -vpi $1 -vci $2"
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
    $::isStandalone and modules::write_conf($prefix);
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
', $netc->{adsltype}) } elsif ($adsl_type eq 'eci') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/bin/startmodem
',
"# et pour le stop on se touche c'est du beta...
echo 'not yet implemented, still beta software'
", $netc->{adsltype}) }

    $netc->{NET_INTERFACE} = 'ppp0';
}

1;
