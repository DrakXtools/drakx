package network::adsl; # $Id$

use common;
use run_program;
use network::tools;
use network::ethernet;
use modules;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_ask_info adsl_detect adsl_conf adsl_conf_backend);

sub configure {
    my ($netcnx, $netc, $intf, $first_time) = @_;

  conf_adsl_step1:
    my %l = (
	     'pppoe' =>  N("use pppoe"),
	     'pptp'  =>  N("use pptp"),
	     'dhcp'  =>  N("use dhcp"),
	     'speedtouch' => N("Alcatel speedtouch usb") . if_($netc->{autodetect}{adsl}{speedtouch}, N(" - detected")),
	     'sagem' =>  N("Sagem (using pppoa) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
	     'sagem_dhcp' =>  N("Sagem (using dhcp) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
	    );
    
    my $type = $in->ask_from_list(N("Connect to the Internet"),
				   N("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few use dhcp.
If you don't know, choose 'use pppoe'"),
				   [ sort values %l ],
				   $l{ find { $netc->{autodetect}{adsl}{$_} } keys %l }
				  ) or return;
    $type = find { $l{$_} eq $type } keys %l;
    if ($type eq 'pppoe') {
	$in->do_pkgs->install("rp-$type");
	$netcnx->{type} = "adsl_$type";
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    } elsif ($type eq 'dhcp') {
	$in->do_pkgs->ensure_is_installed('dhcpcd', '/sbin/dhcpcd', 'auto');
	go_ethernet($netc, $intf, 'dhcp', '', '', $first_time) or goto conf_adsl_step1;
    } elsif ($type eq 'pptp') {
	$in->do_pkgs->ensure_is_installed('pptp-adsl', '/usr/bin/pptp', 'auto');
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    } elsif ($type =~ /sagem/) {
	$type = 'sagem' . ($type =~ /dhcp/ ? "_dhcp" : "");
	$in->do_pkgs->ensure_is_installed('adiusbadsl', '/usr/sbin/adictrl', 'auto');
	$in->do_pkgs->ensure_is_installed('dhcpcd', '/sbin/dhcpcd', 'auto') if $type =~ /dhcp/;
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    } elsif ($type =~ /speedtouch/) {
	$type = 'speedtouch';
	$in->do_pkgs->ensure_is_installed('speedtouch', '/usr/sbin/pppoa3', 'auto');
	$netcnx->{type} = "adsl_$type";
	$netcnx->{"adsl_$type"} = {};
	$netcnx->{"adsl_$type"}{vpivci} = '';
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
    }
    # elsif ($type =~ /ECI/) {
# 	$type = 'eci';
# 	$in->do_pkgs->install(qw(eciadsl)) if !$::testing;
# 	$netcnx->{type} = "adsl_$type";
# 	$netcnx->{"adsl_$type"} = {};
# 	$netcnx->{"adsl_$type"}{vpivci} = '';
# 	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
#     }
    else {
        die "unknown adsl connection type !!!";
    }
    $type =~ /speedtouch|eci/ or $netconnect::need_restart_network = 1;
    1;
}

sub adsl_probe_info {
    my ($adsl, $netc, $adsl_type) = @_;
    my $pppoe_file = "$prefix/etc/ppp/pppoe.conf";
    my $pptp_file = "$prefix/etc/sysconfig/network-scripts/net_cnx_up";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (! defined $adsl_type || $adsl_type =~ /pppoe/) && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/adsl /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+"([^"]+)"/, $1) } cat_("$prefix/$_") if !$login && -r "$prefix/$_";
    }
    ($login) = map { if_(/\sname\s+([^ \n]+)/, $1) } cat_($pptp_file) if (! defined $adsl_type || $adsl_type =~ /pptp/) && -r $pptp_file;
    my $passwd = passwd_by_login($login);
    $pppoe_conf{DNS1} ||= '';
    $pppoe_conf{DNS2} ||= '';
    add2hash($netc, { dnsServer2 => $pppoe_conf{DNS1}, dnsServer3 => $pppoe_conf{DNS2}, DOMAINNAME2 => '' });
    add2hash($adsl, { login => $login, passwd => $passwd, passwd2 => '' });
}

sub adsl_ask_info {
    my ($adsl, $netc, $adsl_type) = @_;
    adsl_probe_info($adsl, $netc, $adsl_type);
    ask_info2($adsl, $netc);
}

sub adsl_detect() {
    my ($adsl) = {};
    require detect_devices;
    $adsl->{speedtouch} = detect_devices::getSpeedtouch();
    $adsl->{sagem} = detect_devices::getSagem();
    return $adsl if $adsl->{speedtouch} || $adsl->{sagem};
}

sub adsl_conf {
    my ($adsl, $netc, $intf, $adsl_type) = @_;
    $adsl ||= {};

  adsl_conf_step_1:
    adsl_ask_info($adsl, $netc, $adsl_type) or return;
  adsl_conf_step_2:
    $adsl_type =~ /sagem|speedtouch|eci/ or conf_network_card($netc, $intf, 'static', '10.0.0.10') or goto adsl_conf_step_1;
    adsl_conf_backend($adsl, $netc, $adsl_type) or goto adsl_conf_step_1;
    1;
}

sub adsl_conf_backend {
    my ($adsl, $netc, $adsl_type, $o_netcnx) = @_;
    defined $o_netcnx and $netc->{adsltype} = $o_netcnx->{type};
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

    if ($adsl_type eq 'sagem') {
	substInFile {
	    s/VCI=.*\n/VCI=00000023\n/;
	    s/Encapsulation=.*\n/Encapsulation=00000006\n/;
	} "$prefix/etc/analog/adiusbadsl";
	output("$prefix/etc/ppp/peers/adsl",
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
	} "$prefix/etc/analog/adiusbadsl";
    }

    if ($adsl_type eq 'speedtouch') {
	my ($vpi, $vci) = $netc->{vpivci} =~ /(\d+)_(\d+)/ or return;
	output("$prefix/etc/ppp/peers/adsl", 
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
	$::isStandalone and modules::write_conf($prefix);
	$in->do_pkgs->what_provides("speedtouch_mgmt") and $in->do_pkgs->ensure_is_installed('speedtouch_mgmt', '/usr/share/speedtouch/mgmt.o', 'auto');
	-e "$prefix/usr/share/speedtouch/mgmt.o" and goto end_firmware;
	
      firmware:
	
	my $l = [ N_("Use a floppy"),
		  N_("Use my Windows partition"),
		  N_("Do it later"),
		];
	
	my $answer = $in->ask_from_list_(N("Firmware needed"),
					 N("You need the Alcatel microcode.
You can provide it now via a floppy or your windows partition,
or skip and do it later."), $l) or return;
	
	my $destination = "$prefix/usr/share/speedtouch/";
	$answer eq 'Use a floppy' and network::tools::copy_firmware('floppy', $destination, 'mgmt.o') || goto firmware;
	$answer eq 'Use my Windows partition' and network::tools::copy_firmware('windows', $destination, 'alcaudsl.sys') || goto firmware;
	$answer eq 'Do it later' and $in->ask_warn('', N("You need the Alcatel microcode.
Download it at:
%s
and copy the mgmt.o in /usr/share/speedtouch", 'http://prdownloads.sourceforge.net/speedtouch/speedtouch-20011007.tar.bz2'));
	
	-e "$destination/alcaudsl.sys" and rename "$destination/alcaudsl.sys", "$destination/mgmt.o";
      end_firmware:
    }
    
    if ($adsl_type eq 'eci') {
	my ($vpi, $vci) = $netc->{vpivci} =~ /(\d+)_(\d+)/ or return;
	output("$prefix/etc/ppp/peers/adsl", 
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
', $netc->{adsltype}) } elsif ($adsl_type eq 'sagem') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/sbin/adictrl -s
INTERFACE=`/usr/sbin/adictrl -i`
/sbin/ifconfig $INTERFACE 192.168.60.30 netmask 255.255.255.0 up
/usr/sbin/pppd file /etc/ppp/peers/adsl
',
'/usr/sbin/stopadsl
', $netc->{adsltype}) } elsif ($adsl_type eq 'sagem_dhcp') {
    write_cnx_script($netc, 'adsl',
'/sbin/route del default
/usr/sbin/adictrl -s
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
