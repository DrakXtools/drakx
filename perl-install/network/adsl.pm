package network::adsl;

use common;
use run_program;
use network::tools;
use network::ethernet;

use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix $install $connect_file $disconnect_file);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_ask_info adsl_detect adsl_conf adsl_conf_backend);

sub configure{
    my ($netcnx, $netc, $intf, $first_time) = @_;
    $::isInstall and $in->set_help('configureNetworkADSL');
  conf_adsl_step1:
    my $type = $in->ask_from_list_(_("Connect to the Internet"),
				   _("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few ones use dhcp.
If you don't know, choose 'use pppoe'"), [__("use pppoe"), __("use pptp"), __("use dhcp")]) or return;
    $type =~ s/use //;
    if ($type eq 'pppoe') {
	$install->("rp-$type");
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
	#-network::configureNetwork($prefix, $netc, $in, $intf, $first_time);
	if ($::isStandalone and $netc->{NET_DEVICE}) {
	    $in->ask_yesorno(_("Network interface"),
			     _("I'm about to restart the network device %s. Do you agree?", $netc->{NET_DEVICE}), 1)
	      and system("$prefix/sbin/ifdown $netc->{NET_DEVICE}; $prefix/sbin/ifup $netc->{NET_DEVICE}");
	}
    }
    if ($type eq 'dhcp') {
	$install->(qw(dhcpcd));
	go_ethernet($netc, $intf, 'dhcp', '', '', $first_time) or goto conf_adsl_step1;
    }
    if ($type eq 'pptp') {
	$install->(qw(pptp-adsl-fr));
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
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
    return;
    my ($interface) = @_;
    run_program::rooted($prefix, "ifconfig $interface 10.0.0.10 netmask 255.255.255.0");
    my $ret=run_program::rooted($prefix, "/bin/ping -c 1 10.0.0.138  2> /dev/null");
    run_program::rooted($prefix, "ifconfig $interface 0.0.0.0 netmask 255.255.255.0");
    $ret;
}

sub adsl_conf {
    my ($adsl, $netc, $intf, $adsl_type) = @_;

  adsl_conf_step_1:
    adsl_ask_info ($adsl, $netc, $intf) or return;
  adsl_conf_step_2:
    conf_network_card ($in, $netc, $intf, 'static' , '10.0.0.10' ) or goto adsl_conf_step_1;
    adsl_conf_backend($adsl, $netc, $adsl_type);

  adsl_conf_step_3:
    $adsl->{atboot} = $in->ask_yesorno(_("ADSL configuration"),
					  _("Do you want to start your connection at boot?")
				      );
    1;
}

sub adsl_conf_backend {
    my ($adsl, $netc, $adsl_type) = @_;

    output("$prefix/etc/ppp/options", 
      $adsl_type eq 'pptp' ?
"lock
noipdefault
noauth
usepeerdns
defaultroute
" :
"noipdefault
usepeerdns
hide-password
defaultroute
persist
lock
") if $adsl_type =~ /pptp|pppoe/;

    write_secret_backend($adsl->{login}, $adsl->{passwd});

    if ($adsl_type eq 'pppoe') {
	substInFile {
	    s/ETH=.*\n/ETH=$netc->{NET_DEVICE}\n/;
	    s/USER=.*\n/USER=$adsl->{login}\n/;
	} "$prefix/etc/ppp/pppoe.conf";
    }

    write_cnx_script($netc, "adsl",
		      $adsl_type eq 'pptp' ?
"#!/bin/bash
/sbin/route del default
/usr/bin/pptp 10.0.0.138 name $adsl->{login}
"
:
"#!/bin/bash
/sbin/route del default
LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C /usr/sbin/adsl-start $netc->{NET_DEVICE} $adsl->{login}
",
		      $adsl_type eq 'pptp' ?
"#!/bin/bash
/usr/bin/killall pptp pppd
"
:
"#!/bin/bash
/usr/sbin/adsl-stop
/usr/bin/killall pppoe pppd
");

    if ($adsl->{atboot}) {
	output ("$prefix/etc/rc.d/init.d/adsl",
	qq{
#!/bin/bash
#
# adsl       Bring up/down adsl connection
#
# chkconfig: 2345 11 89
# description: Activates/Deactivates the adsl interfaces
	case "$1" in
		start)
		echo -n "Starting adsl connection: "
		$connect_file
		touch /var/lock/subsys/adsl
		echo -n adsl
		echo
		;;
	stop)
		echo -n "Stopping adsl connection: "
		$disconnect_file
		echo -n adsl
		echo
		rm -f /var/lock/subsys/adsl
		;;
	restart)
		$0 stop
		echo -n "Waiting 10 sec before restarting adsl."
		sleep 10
		$0 start
		;;
	status)
		;;
	*)
	echo "Usage: adsl {start|stop|status|restart}"
	exit 1
esac
exit 0
 });
	chmod 0755, "$prefix/etc/rc.d/init.d/adsl";
	$::isStandalone ? system("/sbin/chkconfig --add adsl") : do {
	    symlinkf ("../init.d/adsl", "$prefix/etc/rc.d/rc$_") foreach
	      '0.d/K11adsl', '1.d/K11adsl', '2.d/K11adsl', '3.d/S89adsl', '5.d/S89adsl', '6.d/K11adsl';
	};
    }
    else {
	-e "$prefix/etc/rc.d/init.d/adsl" and do{
	    system("/sbin/chkconfig --del adsl");
	    unlink "$prefix/etc/rc.d/init.d/adsl";
	};
    }
    $netc->{NET_INTERFACE}="ppp0";
}

1;
