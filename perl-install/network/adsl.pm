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
    my $l = [ N_("use pppoe"),
	      N_("use pptp"), 
	      N_("use dhcp"), 
	      N_("Alcatel speedtouch usb") . if_($netc->{autodetect}{adsl}{speedtouch}, " - detected"),
	      N_("Sagem (using pppoa) usb") . if_($netc->{autodetect}{adsl}{sagem}, " - detected"),
	     ];
    my $type = $in->ask_from_list_(N("Connect to the Internet"),
				   N("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few use dhcp.
If you don't know, choose 'use pppoe'"), $l) or return;
    $type =~ s/use //;
    if ($type eq 'pppoe') {
	$in->do_pkgs->install("rp-$type");
	$netcnx->{type} = "adsl_$type";
	adsl_conf($netcnx->{"adsl_$type"}, $netc, $intf, $type) or goto conf_adsl_step1;
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
    if ($type =~ /Sagem/) {
	$type = 'sagem';
	$in->do_pkgs->install(qw(adiusbadsl));
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

sub adsl_probe_info {
    my ($adsl, $netc, $adsl_type) = @_;
    my $pppoe_file = "$prefix/etc/ppp/pppoe.conf";
    my $pptp_file = "$prefix/etc/sysconfig/network-scripts/net_cnx_up";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (! defined $adsl_type || $adsl_type =~ /pppoe/) && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/adsl /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+\"([^\"]+)\"/, $1) } cat_("$prefix/$_") if !$login && -r "$prefix/$_";
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
    adsl_ask_info($adsl, $netc, $adsl_type) or return;
  adsl_conf_step_2:
    $adsl_type =~ /sagem|speedtouch|eci/ or conf_network_card($netc, $intf, 'static', '10.0.0.10') or goto adsl_conf_step_1;
    adsl_conf_backend($adsl, $netc, $adsl_type) or goto adsl_conf_step_1;
    1;
}

sub load_firmware_floppy {
    my ($file, $destination) = @_;
    my $floppy = detect_devices::floppy();
    my $failed;
    
    $in->ask_okcancel(N("Insert floppy"), 
		      N("Insert a FAT formatted floppy in drive %s with %s in root directory and press %s", $floppy, $file, N("Next"))) or return;
    
    eval { fs::mount(devices::make($floppy), "/mnt", "vfat", 'readonly'); 1 } or $failed = N("Floppy access error, unable to mount device %s", $floppy);
    my $_b = before_leaving { fs::umount("/mnt") };
    
    if (-e "/mnt/$file") {
	cp_af("/mnt/$file");
	system("cp /mnt/$file $destination");
    } else { $failed ||= N("Firmware copy failed, file %s not found", $file) }
    
    eval { $in->ask_warn('', $failed || N("Firmware copy succeed")) }; $in->exit if $@ =~ /wizcancel/;
    $failed and log::l($failed) && return;
    
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
	modules::add_alias($_->[0], $_->[1]) foreach  ['char-major-108', 'ppp_generic'],
						      ['tty-ldisc-3', 'ppp_async'],
						      ['tty-ldisc-13', 'n_hdlc'],
						      ['tty-ldisc-14', 'ppp_synctty'],
						      ['ppp-compress-21', 'bsd_comp'],
						      ['ppp-compress-24', 'ppp_deflate'],
						      ['ppp-compress-26', 'ppp_deflate'];
	$::isStandalone and modules::write_conf($prefix);
	$in->do_pkgs->what_provides("speedtouch_mgmt") and $in->do_pkgs->install('speedtouch_mgmt');
	-e "/usr/share/speedtouch/mgmt.o" and return 1;
	
      firmware:
	
	my $l = [ N_("Use a floppy"),
		  N_("Use my Windows partition"),
		  N_("Do it later"),
		];
	
	my $answer = $in->ask_from_list_(N("Firmware needed"),
					 N("You need the Alcatel microcode.
You can provide it now via a floppy or your windows partition,
or skip and do it later."), $l) or return;
	
	$answer eq "Use a floppy" and load_firmware_floppy("boot.msg", "/usr/share/speedtouch/") || goto firmware;
	$answer eq "Use my Windows partition" and goto firmware; # to be done
	$answer eq "Do it later" and $in->ask_warn('', N("You need the Alcatel microcode.
Download it at:
%s
and copy the mgmt.o in /usr/share/speedtouch", 'http://prdownloads.sourceforge.net/speedtouch/speedtouch-20011007.tar.bz2'));
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
