
package network::netconnect;

use diagnostics;
use strict;
use vars qw($isdn_init @isdndata);

use common;
use log;
use detect_devices;
use run_program;
use modules;
use any;
use mouse;
use network;
use commands;
#require Data::Dumper;

use network::tools;
use MDK::Common::Globals "network", qw($in $prefix $install $connect_file $disconnect_file $connect_prog);


#- intro is called only in standalone.
sub intro {
    my ($prefix, $netcnx, $in, $install) = @_;
    my ($netc, $mouse, $intf) = ({}, {}, {});
    my $text;
    my $connected;
    my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";
    my $disconnect_file = "/etc/sysconfig/network-scripts/net_cnx_down";
    my $connect_prog = "/etc/sysconfig/network-scripts/net_cnx_pg";
    read_net_conf($prefix, $netcnx, $netc);
    if (!$::isWizard) {
	if (connected($netc)) {
	    $text=_("You are currently connected to internet.") . (-e $disconnect_file ? _("\nYou can disconnect or reconfigure your connection.") : _("\nYou can reconfigure your connection."));
	    $connected=1;
	} else {
	    $text=_("You are not currently connected to Internet.") . (-e $connect_file ? _("\nYou can connect to Internet or reconfigure your connection.") : _("\nYou can reconfigure your connection."));
	    $connected=0;
	}
	my @l=(
	       !$connected && -e $connect_file ? { description => _("Connect to Internet"),
						   c => 1} : (),
	       $connected && -e $disconnect_file ? { description => _("Disconnect from Internet"),
						     c => 2} : (),
	       { description => _("Configure network connection (LAN or Internet)"),
		 c => 3},
	      );
	my $e = $in->ask_from_listf(_("Internet connection & configuration"),
				    _($text),
				    sub { $_[0]{description} },
				    \@l );
	run_program::rooted($prefix, $connect_prog) if ($e->{c}==1);
	run_program::rooted($prefix, $disconnect_file) if ($e->{c}==2);
	main($prefix, $netcnx, $netc, $mouse, $in, $intf, $install, 0, 0) if ($e->{c}==3);
    } else {
	main($prefix, $netcnx, $netc, $mouse, $in, $intf, $install, 0, 0);
    }
}

sub detect {
    my ($auto_detect, $net_install) = @_;
    my $isdn={};
    require network::isdn;
    network::isdn->import;
    isdn_detect_backend($isdn);
    $auto_detect->{isdn}{$_}=$isdn->{$_} foreach qw(description vendor id driver card_type type);
    $auto_detect->{isdn}{description} =~ s/.*\|//;

    any::setup_thiskind_backend('net', undef);
    require network::ethernet;
    network::ethernet->import;
    my @all_cards = conf_network_card_backend (undef, undef, undef, undef, undef, undef);
    require network::adsl;
    network::adsl->import;
    map {
	( !$net_install and adsl_detect("", $_->[0]) ) ? $auto_detect->{adsl}=$_->[0] : $auto_detect->{lan}{$_->[0]}=$_->[1]; } @all_cards;
    my $modem={};
    require network::modem;
    network::modem->import;
    modem_detect_backend($modem);#, $mouse);
    $modem->{device} and $auto_detect->{modem}=$modem->{device};
}

sub main {
    my ($prefix, $netcnx, $netc, $mouse, $in, $intf, $install, $first_time, $direct_fr) = @_;
    MDK::Common::Globals::init(
		  in => $in,
		  prefix => $prefix,
		  install => $install,
		  connect_file => "/etc/sysconfig/network-scripts/net_cnx_up",
		  disconnect_file => "/etc/sysconfig/network-scripts/net_cnx_down",
		  connect_prog => "/etc/sysconfig/network-scripts/net_cnx_pg" );
    $netc->{minus_one}=0; #When one configure an eth in dhcp without gateway
    $::isInstall and $in->set_help('configureNetwork');
    $::isStandalone and read_net_conf($prefix, $netcnx, $netc); # REDONDANCE with intro. FIXME
    $netc->{NET_DEVICE}=$netcnx->{NET_DEVICE} if $netcnx->{NET_DEVICE}; # REDONDANCE with read_conf. FIXME
    $netc->{NET_INTERFACE}=$netcnx->{NET_INTERFACE} if $netcnx->{NET_INTERFACE}; # REDONDANCE with read_conf. FIXME
    network::read_all_conf($prefix, $netc ||= {}, $intf ||= {});

    modules::mergein_conf("$prefix/etc/modules.conf");

    my $direct_net_install;
    if ($first_time && $::isInstall && ($in->{method} eq "ftp" || $in->{method} eq "http" || $in->{method} eq "nfs")) {
	(!$::expert or $in->ask_okcancel(_("Network Configuration"),
					 _("Because you are doing a network installation, your network is already configured.
Click on Ok to keep your configuration, or cancel to reconfigure your Internet & Network connection.
"), 1)) and do {
    output "$prefix$connect_file",
      qq(
#!/bin/bash
ifup eth0
);
    output "$prefix$disconnect_file",
      qq(
#!/bin/bash
ifdown eth0
);
    chmod 0755, "$prefix$disconnect_file";
    chmod 0755, "$prefix$connect_file";
    $direct_net_install = 1;
    goto step_5;
};
    }

    $netc->{autodetection}=1;
    $netc->{autodetect}={};

  step_1:
    $::Wizard_no_previous=1;
    my @profiles=get_profiles();
    $in->ask_from_entries_refH(_("Network Configuration Wizard"),
		       _("Welcome to The Network Configuration Wizard\n\nWe are about to configure your internet/network connection.\nIf you don't want to use the auto detection, deselect the checkbox.\n"),
			       [
				if_(@profiles > 1, { label => _("Choose the profile to configure"), val => \$netcnx->{PROFILE}, list => \@profiles }),
				{ label => _("Use auto detection"), val => \$netc->{autodetection}, type => 'bool' },
			       ]
			      ) or goto step_5;
    undef $::Wizard_no_previous;
    set_profile($netcnx);
    if ($netc->{autodetection}) {
	my $w = $in->wait_message(_("Network Configuration Wizard"), _("Detecting devices..."));
	detect($netc->{autodetect}, $::isInstall && ($in->{method} eq "ftp" || $in->{method} eq "http" || $in->{method} eq "nfs"));
    }

  step_2:

    my $set_default;
    my %conf;
    $conf{$_} = $netc->{autodetect}{$_} ? 1 : 0 foreach qw(modem adsl cable lan);
    $conf{isdn} = $netc->{autodetect}{isdn}{description} ? 1: 0;
    my @l = (
	     [_("Normal modem connection"), $netc->{autodetect}{modem}, __("detected on port %s"), \$conf{modem}],
	     [_("ISDN connection"), $netc->{autodetect}{isdn}{description}, __("detected %s"), \$conf{isdn}],
	     [_("ADSL connection"), $netc->{autodetect}{adsl}, __("detected on interface %s"), \$conf{adsl}],
	     [_("Cable connection"), $netc->{autodetect}{cable}, __("cable connection detected"), \$conf{cable}],
	     [_("LAN connection"), $netc->{autodetect}{lan}, __("ethernet card(s) detected"), \$conf{lan}]
	);
    my $i=0;
    map { defined $set_default or do { $_->[1] and $set_default=$i; }; $i++; } @l;
    my $e = $in->ask_from_entries_refH(_("Network Configuration Wizard"),
				       _("Choose"),
				       [
					map { {
					    label => $_->[0] . if_($_->[1], " - " . _ ($_->[2], $_->[1])),
					      val => $_->[3], type => 'bool'} } @l 
				       ]
				      ) or goto step_1;

#    load_conf ($netcnx, $netc, $intf);

    $conf{modem} and do { require network::modem; network::modem::configure($netcnx, $mouse, $netc) or goto step_2 };
    $conf{isdn} and do { require network::isdn; network::isdn::configure($netcnx, $netc) or goto step_2 };
    $conf{adsl} and do { require network::adsl; network::adsl::configure($netcnx, $netc, $intf, $first_time) or goto step_2 };
    $conf{cable} and do { require network::ethernet; network::ethernet::configure_cable($netcnx, $netc, $intf, $first_time) or goto step_2 };
    $conf{lan} and do { require network::ethernet; network::ethernet::configure_lan($netcnx, $netc, $intf, $first_time) or goto step_2 };

  step_2_1:
    if (keys %{$netc->{internet_cnx}} > 1) {
	$in->ask_from_entries_refH(_("Network Configuration Wizard"),
  				   _("You have configured multiple ways to connect to the Internet.\nChoose the one you want to use.\n\n" . if_(!$::isStandalone, "You may want to configure some profiles after the installation, in the Mandrake Control Center")),
  				   [
  				    { label => _("Internet connection"), val => \$netc->{internet_cnx_choice}, list => [ keys %{$netc->{internet_cnx}} ]}
  				   ]
  				  ) or goto step_2;
    } elsif (keys %{$netc->{internet_cnx}} == 1) {
	$netc->{internet_cnx_choice} = $netc->{internet_cnx}[1];
    }
    $netc->{internet_cnx_choice} and write_cnx_script($netc);

    $::isStandalone and ask_connect_now() or goto step_2_1;

  step_3:

    my $m = _("Congratulation, The network and internet configuration is finished.

The configuration will now be applied to your system.") . if_($::isStandalone,
_("After that is done, we recommend you to restart your X
environnement to avoid hostname changing problem."));
    if ($::isWizard) {
	$::Wizard_no_previous=1;
	$::Wizard_finished=1;
	$in->ask_okcancel(_("Network Configuration"), $m, 1);
	undef $::Wizard_no_previous;
	undef $::Wizard_finished;
    } else {  $in->ask_warn('', $m ); }

  step_5:

    network::configureNetwork2($in, $prefix, $netc, $intf, $install);

    if ($netcnx->{type} =~ /modem/ || $netcnx->{type} =~ /isdn_external/) {
	output "$prefix$connect_prog",
	  qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
if [ -e /usr/bin/kppp ]; then
/usr/bin/kppp &
else
/usr/sbin/net_monitor --connect
fi
else
$connect_file
fi
);
    } elsif ($netcnx->{type}) {
	output "$prefix$connect_prog",
	  qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
/usr/sbin/net_monitor --connect
else
$connect_file
fi
);
    } else {
	output "$prefix$connect_prog",
	  qq(
#!/bin/bash
/usr/sbin/draknet
);
    }
    if ($direct_net_install) {
	output "$prefix$connect_prog",
	  qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
/usr/sbin/net_monitor --connect
else
$connect_file
fi
);
    }
    chmod 0755, "$prefix$connect_prog";
    $netcnx->{$_}=$netc->{$_} foreach qw(NET_DEVICE NET_INTERFACE);

    $netcnx->{NET_INTERFACE} and set_net_conf($netcnx, $netc);
    $netcnx->{type} =~ /adsl/ or system("/sbin/chkconfig --del adsl 2> /dev/null");
    save_conf($netcnx, $netc, $intf);

#-    if ($netc->{NET_DEVICE} and $netc->{NETWORKING} ne 'no' and $::isStandalone and $::expert) {
#-	  exists $netc->{nb_cards} or do {
#-	      any::setup_thiskind($in, 'net', !$::expert, 1);
#-	      $netc->{nb_cards} = listlength(detect_devices::getNet());
#-	  };
#-	  ($netc->{nb_cards} - $netc->{minus_one} - (get_net_device($prefix) =~ /eth.+/ ? 1 : 0) > 0) and $in->ask_okcancel(_("Network Configuration"),
#-_("Now that your Internet connection is configured,
#-your computer can be configured to share its Internet connection.
#-Note: you need a dedicated Network Adapter to set up a Local Area Network (LAN).
#-
#-Would you like to setup the Internet Connection Sharing?
#-"), 1) and system("/usr/sbin/drakgw --direct");
#-    }
}

sub save_conf {
    my ($netcnx, $netc, $intf)=@_;
    my $adsl;
    my $modem;
    my $isdn;
    $netcnx->{type} =~ /adsl/ and $adsl=$netcnx->{$netcnx->{type}};
    $netcnx->{type} eq 'isdn_external' || $netcnx->{type} eq 'modem' and $modem=$netcnx->{$netcnx->{type}};
    $netcnx->{type} eq 'isdn_internal' and $isdn=$netcnx->{$netcnx->{type}};
    any::setup_thiskind_backend('net', undef);
    require network::ethernet;
    network::ethernet->import;
    my @all_cards = conf_network_card_backend ($netc, $intf, undef, undef, undef, undef);

    $intf = { %$intf };

    output("$prefix/etc/sysconfig/network-scripts/draknet_conf",
      "SystemName=" . do { $netc->{HOSTNAME} =~ /([^\.]*)\./; $1 } . "
DomainName=" . do { $netc->{HOSTNAME} =~ /\.(.*)/; $1 } . "
InternetAccessType=" . do { if ($netcnx->{type}) { $netcnx->{type}; } else { $netc->{GATEWAY} ? "lan" : ""; } } . "
InternetInterface=" . ($netc->{GATEWAY} && (!$netcnx->{type} || $netcnx->{type} eq 'lan') ? $netc->{NET_DEVICE} : $netcnx->{NET_INTERFACE}) . "
InternetGateway=$netc->{GATEWAY}
DNSPrimaryIP=$netc->{dnsServer}
DNSSecondaryIP=$netc->{dnsServer2}
DNSThirdIP=$netc->{dnsServer3}
AdminInterface=

" . join ('', map {
"Eth${_}Known=" . ($intf->{"eth$_"}->{DEVICE} eq "eth$_" ? 'true' : 'false') . "
Eth${_}IP=" . $intf->{"eth$_"}{IPADDR} . "
Eth${_}Mask=" . $intf->{"eth$_"}{NETMASK} . "
Eth${_}Mac=
Eth${_}BootProto=" . $intf->{"eth$_"}{BOOTPROTO} . "
Eth${_}OnBoot=" . $intf->{"eth$_"}{ONBOOT} . "
Eth${_}Hostname=$netc->{HOSTNAME}
Eth${_}HostAlias=" . do { $netc->{HOSTNAME} =~ /([^\.]*)\./; $1 } . "
Eth${_}Driver=$all_cards[$_]->[1]
Eth${_}Irq=
Eth${_}Port=
Eth${_}DHCPClient=" . ($intf->{"eth$_"}{BOOTPROTO} eq 'dhcp' ? $netcnx->{dhcp_client} : '') . "
Eth${_}DHCPServerName=" . ($intf->{"eth$_"}{BOOTPROTO} eq 'dhcp' ? $netc->{HOSTNAME} : '') . "\n"
 } (0..9)) .
"

ISDNDriver=$isdn->{driver}
ISDNDeviceType=$isdn->{type}
ISDNIrq=$isdn->{irq}
ISDNMem=$isdn->{mem}
ISDNIo=$isdn->{io}
ISDNIo0=$isdn->{io0}
ISDNIo1=$isdn->{io1}
ISDNProtocol=$isdn->{protocol}
ISDNCardDescription=$isdn->{description}
ISDNCardVendor=$isdn->{vendor}
ISDNId=$isdn->{id}
ISDNProvider=$netc->{DOMAINNAME2}
ISDNProviderPhone=$isdn->{phone_out}
ISDNProviderDomain=" . do { $netc->{DOMAINNAME2} =~ /\.(.*)/; $1} . "
ISDNProviderDNS1=$netc->{dnsServer2}
ISDNProviderDNS2=$netc->{dnsServer3}
ISDNDialing=$isdn->{dialing_mode}
ISDNHomePhone=$isdn->{phone_in}
ISDNLogin=$isdn->{login}
ISDNPassword=$isdn->{passwd}
ISDNConfirmPassword=$isdn->{passwd2}

PPPInterfacesList=
PPPDevice=$modem->{device}
PPPDeviceSpeed=
PPPConnectionName=$modem->{connection}
PPPProviderPhone=$modem->{phone}
PPPProviderDomain=$modem->{domain}
PPPProviderDNS1=$modem->{dns1}
PPPProviderDNS2=$modem->{dns2}
PPPLogin=$modem->{connection}
PPPPassword=$modem->{login}
PPPConfirmPassword=$modem->{passwd}
PPPAuthentication=$modem->{auth}
PPPSpecialCommand=" . ($netcnx->{type} eq 'isdn_external' ? $netcnx->{isdn_external}{special_command} : '' ) . "

ADSLInterfacesList=
ADSLModem=" .  q(# Obsolete information. Please don't use it.) . "
ADSLType=" . ($netcnx->{type} =~ /adsl/ ? $netcnx->{type} : '') . "
ADSLProviderDomain=$netc->{DOMAINNAME2}
ADSLProviderDNS1=$netc->{dnsServer2}
ADSLProviderDNS2=$netc->{dnsServer3}
ADSLLogin=$adsl->{login}
ADSLPassword=$adsl->{passwd}
DOMAINNAME2=$netc->{DOMAINNAME2}"
	  );
    chmod 0600, "$prefix/etc/sysconfig/network-scripts/draknet_conf";
    my $a = $netcnx->{PROFILE} ? $netcnx->{PROFILE} : "default";
    commands::cp("-f", "$prefix/etc/sysconfig/network-scripts/draknet_conf", "$prefix/etc/sysconfig/network-scripts/draknet_conf." . $a);
    chmod 0600, "$prefix/etc/sysconfig/network-scripts/draknet_conf";
    chmod 0600, "$prefix/etc/sysconfig/network-scripts/draknet_conf." . $a;
    foreach ( ["$prefix$connect_file", "up"], ["$prefix$disconnect_file", "down"], ["$prefix$connect_prog", "prog"] ) {
	my $file = "$prefix/etc/sysconfig/network-scripts/net_" . $_->[1] . "." . $a;
	-e ($_->[0]) and commands::cp("-f", $_->[0], $file) and chmod 0755, $file;
    }
}

sub set_profile {
    my ($netcnx, $profile) = @_;
    $profile ||= $netcnx->{PROFILE};
    $profile or return;
    my $f = "$prefix/etc/sysconfig/network-scripts/draknet_conf";
    -e ($f . "." . $profile) or return;
    $netcnx->{PROFILE}=$profile;
    print "changing to $profile\n";
    commands::cp("-f", $f . "." . $profile, $f);
    foreach ( ["up", "$prefix$connect_file"], ["down", "$prefix$disconnect_file"], ["prog", "$prefix$connect_prog"]) {
	my $c = "$prefix/etc/sysconfig/network-scripts/net_" . $_->[0] . "." . $profile;
	-e ($c) and commands::cp("-f", $c, $_->[1]);
    }
}

sub del_profile {
    my ($netcnx, $profile) = @_;
    $profile or return;
    $profile eq "default" and return;
    print "deleting $profile\n";
    commands::rm("-f", "$prefix/etc/sysconfig/network-scripts/draknet_conf." . $profile);
    commands::rm("-f", glob_("$prefix/etc/sysconfig/network-scripts/net_{up,down,prog}." . $profile));
}

sub add_profile {
    my ($netcnx, $profile) = @_;
    $profile or return;
    $profile eq "default" and return;
    print "creating $profile\n";
    my $cmd1 = "$prefix/etc/sysconfig/network-scripts/draknet_conf." . ($netcnx->{PROFILE} ? $netcnx->{PROFILE} : "default");
    my $cmd2 = "$prefix/etc/sysconfig/network-scripts/draknet_conf." . $profile;
    commands::cp("-f", $cmd1, $cmd2);
}

sub get_profiles {
    my @a;
    my $i=0;
    foreach (glob("/etc/sysconfig/network-scripts/draknet_conf.*")) {
	s/.*\.//;
	$a[$i] = $_;
	$i++;
    }
    @a;
}

sub load_conf {
    my ($netcnx, $netc, $intf)=@_;
    my $adsl_pptp={};
    my $adsl_pppoe={};
    my $modem={};
    my $isdn_external={};
    my $isdn={};
    my $system_name;
    my $domain_name;

    if (-e "$prefix/etc/sysconfig/network-scripts/draknet_conf") {
	foreach (cat_("$prefix/etc/sysconfig/network-scripts/draknet_conf")) {
	    /^DNSPrimaryIP=(.*)$/ and $netc->{dnsServer} = $1;
	    /^DNSSecondaryIP=(.*)$/ and $netc->{dnsServer2} = $1;
	    /^DNSThirdIP=(.*)$/ and $netc->{dnsServer3} = $1;
	    /^InternetAccessType=(.*)$/ and $netcnx->{type} = $1;
	    /^InternetInterface=(.*)$/ and $netcnx->{NET_INTERFACE} = $1;
	    /^InternetGateway=(.*)$/ and $netc->{GATEWAY} = $1;
	    /^SystemName=(.*)$/ and $system_name = $1;
	    /^DomainName=(.*)$/ and $domain_name = $1;
	    /^Eth([0-9])Known=true$/ and $intf->{"eth$1"}->{DEVICE} = "eth$1";
	    /^Eth([0-9])IP=(.*)$/ && $intf->{"eth$1"}->{DEVICE} and $intf->{"eth$1"}{IPADDR} = $2;
	    /^Eth([0-9])Mask=(.*)\n/ && $intf->{"eth$1"}->{DEVICE} and $intf->{"eth$1"}{NETMASK} = $2;
	    /^Eth([0-9])BootProto=(.*)\n/ && $intf->{"eth$1"}->{DEVICE} and $intf->{"eth$1"}{BOOTPROTO} = $2;
	    /^Eth([0-9])OnBoot=(.*)\n/ && $intf->{"eth$1"}->{DEVICE} and $intf->{"eth$1"}{ONBOOT} = $2;
	    /^Eth([0-9])Hostname=(.*)\n/ && $intf->{"eth$1"}->{DEVICE} and $netc->{HOSTNAME} = $2;
	    /^Eth([0-9])Driver=(.*)\n/ && $intf->{"eth$1"}->{DEVICE} and $intf->{"eth$1"}{driver} = $2;
	    /^ISDNDriver=(.*)$/ and $isdn->{driver} = $1;
	    /^ISDNDeviceType=(.*)$/ and $isdn->{type} = $1;
	    /^ISDNIrq=(.*)/ and $isdn->{irq} = $1;
	    /^ISDNMem=(.*)$/ and $isdn->{mem} = $1;
	    /^ISDNIo=(.*)$/ and $isdn->{io} = $1;
	    /^ISDNIo0=(.*)$/ and $isdn->{io0} = $1;
	    /^ISDNIo1=(.*)$/ and $isdn->{io1} = $1;
	    /^ISDNProtocol=(.*)$/ and $isdn->{protocol} = $1;
	    /^ISDNCardDescription=(.*)$/ and $isdn->{description} = $1;
	    /^ISDNCardVendor=(.*)$/ and $isdn->{vendor} = $1;
	    /^ISDNId=(.*)$/ and $isdn->{id} = $1;
	    /^ISDNProviderPhone=(.*)$/ and $isdn->{phone_out} = $1;
	    /^ISDNDialing=(.*)$/ and $isdn->{dialing_mode} = $1;
	    /^ISDNHomePhone=(.*)$/ and $isdn->{phone_in} = $1;
	    /^ISDNLogin=(.*)$/ and $isdn->{login} = $1;
	    /^ISDNPassword=(.*)$/ and $isdn->{passwd} = $1;
	    /^ISDNConfirmPassword=(.*)$/ and $isdn->{passwd2} = $1;

	    /^PPPDevice=(.*)$/ and $modem->{device} = $1;
	    /^PPPConnectionName=(.*)$/ and $modem->{connection} = $1;
	    /^PPPProviderPhone=(.*)$/ and $modem->{phone} = $1;
	    /^PPPProviderDomain=(.*)$/ and $modem->{domain} = $1;
	    /^PPPProviderDNS1=(.*)$/ and $modem->{dns1} = $1;
	    /^PPPProviderDNS2=(.*)$/ and $modem->{dns2} = $1;
	    /^PPPLogin=(.*)$/ and $modem->{login} = $1;
	    /^PPPPassword=(.*)$/ and $modem->{passwd} = $1;
	    /^PPPAuthentication=(.*)$/ and $modem->{auth} = $1;
	    if (/^PPPSpecialCommand=(.*)$/) {
		$netcnx->{type} eq 'isdn_external' and $netcnx->{$netcnx->{type}}{special_command} = $1;
	    }
	    /^ADSLLogin=(.*)$/ and $adsl_pppoe->{login} = $1;
	    /^ADSLPassword=(.*)$/ and $adsl_pppoe->{passwd} = $1;
	    /^DOMAINNAME2=(.*)$/ and $netc->{DOMAINNAME2} = $1;
	}
    }
    $system_name && $domain_name and $netc->{HOSTNAME}=join ('.', $system_name, $domain_name);
    $adsl_pptp->{$_}=$adsl_pppoe->{$_} foreach ('login', 'passwd', 'passwd2');
    $isdn_external->{$_}=$modem->{$_} foreach ('device', 'connection', 'phone', 'domain', 'dns1', 'dns2', 'login', 'passwd', 'auth');
    $netcnx->{adsl_pptp}=$adsl_pptp;
    $netcnx->{adsl_pppoe}=$adsl_pppoe;
    $netcnx->{modem}=$modem;
    $netcnx->{modem}=$isdn_external;
    $netcnx->{isdn_internal}=$isdn;
    -e "$prefix/etc/sysconfig/network" and put_in_hash($netc,network::read_conf("$prefix/etc/sysconfig/network"));
    foreach (glob_("$prefix/etc/sysconfig/ifcfg-*")) {
	my $l = network::read_interface_conf($_);
	$intf->{$l->{DEVICE}} = $l;
    }
    my $file = "$prefix/etc/resolv.conf";
    if (-e $file) {
	put_in_hash($netc, network::read_resolv_conf($file));
    }
}

sub get_net_device {
    ${{ getVarsFromSh("/etc/sysconfig/draknet") }}{NET_DEVICE};
}

sub read_net_conf {
    my ($prefix, $netcnx, $netc)=@_;
    add2hash($netcnx, { getVarsFromSh("$prefix/etc/sysconfig/draknet") });
    $netc->{$_} = $netcnx->{$_} foreach 'NET_DEVICE', 'NET_INTERFACE';
    $netcnx->{$netcnx->{type}}||={};
    add2hash($netcnx->{$netcnx->{type}}, { getVarsFromSh("$prefix/etc/sysconfig/draknet." . $netcnx->{type}) });
}

sub set_net_conf {
    my ($netcnx, $netc)=@_;
    setVarsInShMode("$prefix/etc/sysconfig/draknet", 0600, $netcnx, "NET_DEVICE", "NET_INTERFACE", "type", "PROFILE" );
    setVarsInShMode("$prefix/etc/sysconfig/draknet." . $netcnx->{type}, 0600, $netcnx->{$netcnx->{type}}); #- doesn't work, don't know why
    setVarsInShMode("$prefix/etc/sysconfig/draknet.netc", 0600, $netc); #- doesn't work, don't know why
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;
