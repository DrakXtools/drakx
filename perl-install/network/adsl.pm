package network::adsl;

use common;
use run_program;
use network::tools;
use network::ethernet;
use modules;

use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix $connect_file $disconnect_file);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_ask_info adsl_detect adsl_conf adsl_conf_backend);

sub configure {
    my ($netcnx, $netc, $intf, $first_time) = @_;
    $::isInstall and $in->set_help('configureNetworkADSL');
  conf_adsl_step1:
    my $type = $in->ask_from_list_(_("Connect to the Internet"),
				   _("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few ones use dhcp.
If you don't know, choose 'use pppoe'"), [__("use pppoe"), __("use pptp"), __("use dhcp"), __("Alcatel speedtouch usb")]) or return;
    $type =~ s/use //;
    if ($type eq 'pppoe') {
	$in->do_pkgs->install("rp-$type");
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
	#-network::configureNetwork($prefix, $netc, $in, $intf, $first_time);
#  	if ($::isStandalone and $netc->{NET_DEVICE}) {
#  	    $in->ask_yesorno(_("Network interface"),
#  			     _("I'm about to restart the network device %s. Do you agree?", $netc->{NET_DEVICE}), 1)
#  	      and system("$prefix/sbin/ifdown $netc->{NET_DEVICE}; $prefix/sbin/ifup $netc->{NET_DEVICE}");
#  	}
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
    $type =~ /speedtouch/ or $netconnect::need_restart_network = 1;
    1;
}

sub adsl_ask_info {
    my ($adsl, $netc, $intf) = @_;
    add2hash($netc, { dnsServer2 => '', dnsServer3 => '', DOMAINNAME2 => '' });
    add2hash($adsl, { login => '', passwd => '', passwd2 => '' });
    ask_info2($adsl, $netc);
}

#- adsl_detect : detect adsl modem on a given interface
#- input :
#-  $interface : interface where the modem is supposed to be connected : should be "ethx"
#- output:
#-  true/false : success|failed
sub adsl_detect {
    return 0;
    my ($interface) = @_;
    run_program::rooted($prefix, "ifconfig $interface 10.0.0.10 netmask 255.255.255.0");
    my $ret=run_program::rooted($prefix, "/bin/ping -c 1 10.0.0.138  2> /dev/null");
    run_program::rooted($prefix, "ifconfig $interface 0.0.0.0 netmask 255.255.255.0");
    run_program::rooted($prefix, "/etc/init.d/network restart");
    $ret;
}

sub adsl_conf {
    my ($adsl, $netc, $intf, $adsl_type) = @_;

  adsl_conf_step_1:
    adsl_ask_info ($adsl, $netc, $intf) or return;
  adsl_conf_step_2:
    $adsl_type eq 'speedtouch' or conf_network_card($netc, $intf, 'static' , '10.0.0.10' ) or goto adsl_conf_step_1;
    adsl_conf_backend($adsl, $netc, $adsl_type);
    1;
}

sub adsl_conf_backend {
    my ($adsl, $netc, $adsl_type) = @_;

    mkdir_p("$prefix/etc/ppp");
    output("$prefix/etc/ppp/options",
'lock
noipdefault
persist
noauth
usepeerdns
defaultroute
') if $adsl_type =~ /pptp|pppoe|speedtouch/;

    write_secret_backend($adsl->{login}, $adsl->{passwd});

    if ($adsl_type eq 'pppoe') {
	substInFile {
	    s/ETH=.*\n/ETH=$netc->{NET_DEVICE}\n/;
	    s/USER=.*\n/USER=$adsl->{login}\n/;
	} "$prefix/etc/ppp/pppoe.conf";
    }

    if ($adsl_type eq 'speedtouch') {
	$netc->{vpivci} =~ /(\d+)_(\d+)/;
	output("$prefix/etc/ppp/peers/adsl", 
qq{noauth
noipdefault
pty "/usr/bin/pppoa2 -vpi $1 -vci $2"
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
});
	modules::add_alias($_->[0], $_->[1]) foreach (['char-major-108', 'ppp_generic'],
						      ['tty-ldisc-3', 'ppp_async'],
						      ['tty-ldisc-13', 'n_hdlc'],
						      ['tty-ldisc-14', 'ppp_synctty'],
						      ['ppp-compress-21', 'bsd_comp'],
						      ['ppp-compress-24', 'ppp_deflate'],
						      ['ppp-compress-26', 'ppp_deflate']);
	$::isStandalone and modules::write_conf($prefix);
	my $mgmtrpm;
	if ($::isStandalone) {
	    $mgmtrpm = `grep speedtouch_mgmt /var/lib/urpmi/depslist.ordered` ? 1 : 0;
	} else {
	    require pkgs;
	    $mgmtrpm = pkgs::packageByName($in->{package}, "speedtouch_mgmt");
	}
	if($mgmtrpm) {
	    $in->do_pkgs->install('speedtouch_mgmt')
	} else {
	    -e "$prefix/usr/share/speedtouch/mgmt.o" or $in->ask_warn('', _('You need the alcatel microcode.
Download it at
http://www.alcatel.com/consumer/dsl/dvrreg_lx.htm
and copy the mgmt.o in /usr/share/speedtouch'));
    }

    if ($adsl_type eq 'pptp') {
	write_cnx_script($netc, "adsl",
"/sbin/route del default
/usr/bin/pptp 10.0.0.138 name $adsl->{login}
",
'/usr/bin/killall pptp pppd
', $netcnx->{type}) } elsif ($adsl_type eq 'pppoe') {
    write_cnx_script($netc, "adsl",
"/sbin/route del default
LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C /usr/sbin/adsl-start $netc->{NET_DEVICE} $adsl->{login}
",
'/usr/sbin/adsl-stop
/usr/bin/killall pppoe pppd
', $netcnx->{type}) } elsif ($adsl_type eq 'speedtouch') {
    write_cnx_script($netc, 'adsl',
'/usr/share/speedtouch/speedtouch.sh start
',
'/usr/share/speedtouch/speedtouch.sh stop
', $netcnx->{type}) }

    $netc->{NET_INTERFACE}='ppp0';
}

1;
