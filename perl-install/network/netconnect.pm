package network::netconnect;

use strict;
use common;
use log;
use detect_devices;
use run_program;
use modules;
use any;
use mouse;
use network;
use network::tools;
use MDK::Common::Globals "network", qw($in $prefix $connect_file $disconnect_file $connect_prog);

my	%conf;
#- intro is called only in standalone.
sub intro {
    my ($prefix, $netcnx, $in) = @_;
    my ($netc, $mouse, $intf) = ({}, {}, {});
    my $text;
    my $connected;
    my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";
    my $disconnect_file = "/etc/sysconfig/network-scripts/net_cnx_down";
    my $connect_prog = "/etc/sysconfig/network-scripts/net_cnx_pg";
    read_net_conf($prefix, $netcnx, $netc);
    if (!$::isWizard) {
	if (connected()) {
	    $text = N("You are currently connected to the Internet.") . (-e $disconnect_file ? N("\nYou can disconnect or reconfigure your connection.") : N("\nYou can reconfigure your connection."));
	    $connected = 1;
	} else {
	    $text = N("You are not currently connected to the Internet.") . (-e $connect_file ? N("\nYou can connect to the Internet or reconfigure your connection.") : N("\nYou can reconfigure your connection."));
	    $connected = 0;
	}
	my @l = (
	       if_(!$connected && -e $connect_file, { description => N("Connect"), c => 1 }),
	       if_($connected && -e $disconnect_file, { description => N("Disconnect"), c => 2 }),
	       { description => N("Configure the connection"), c => 3 },
	       { description => N("Cancel"), c => 4 },
	      );
	my $e = $in->ask_from_listf(N("Internet connection & configuration"),
				    translate($text),
				    sub { $_[0]{description} },
				    \@l);
	run_program::rooted($prefix, $connect_prog) if $e->{c} == 1;
	run_program::rooted($prefix, $disconnect_file) if $e->{c} == 2;
	main($prefix, $netcnx, $netc, $mouse, $in, $intf, 0, 0) if $e->{c} == 3;
	$in->exit(0) if $e->{c} == 4;
    } else {
	main($prefix, $netcnx, $netc, $mouse, $in, $intf, 0, 0);
    }
}

sub detect {
    my ($auto_detect, $net_install) = @_;
    my $isdn = {};
    require network::isdn;
    network::isdn->import;
    isdn_detect_backend($isdn);
    $auto_detect->{isdn}{$_} = $isdn->{$_} foreach qw(description vendor id driver card_type type);
    $auto_detect->{isdn}{description} =~ s/.*\|//;

    modules::load_category('network/main|gigabit|usb');
    require network::ethernet;
    network::ethernet->import;
    my @all_cards = conf_network_card_backend(undef, undef, undef, undef, undef, undef);
    map { $auto_detect->{lan}{$_->[0]} = $_->[1] } @all_cards if !$net_install;

    my $adsl = {};
    require network::adsl;
    network::adsl->import;
    $auto_detect->{adsl} = adsl_detect($adsl);

    require network::modem;
    network::modem->import;
    my ($modem, @pci_modems) = detect_devices::getModem();
    $modem->{device} and $auto_detect->{modem} = $modem->{device};
    @pci_modems and $auto_detect->{winmodem}{$_->{driver}} = $_->{description} foreach @pci_modems;
}

sub pre_func {
    my ($text) = @_;
    $in->isa('interactive_gtk') or return;
    $::Wizard_no_previous = 1;
    if ($::isStandalone) {
	$::Wizard_splash = 1;
	require ugtk2;
	ugtk2->import(qw(:wrappers));
	my $W = ugtk2->new(N("Network Configuration Wizard"));
	gtkadd($W->{window},
	       gtkpack_(new Gtk2::VBox(0, 0),
			1, write_on_pixmap(gtkcreate_img("drakconnect_step"),
					   20,200,
					   N("We are now going to configure the %s connection.", translate($text)),
					  ),
			0, $W->create_okcancel(N("OK"))
		       )
	      );
	$W->main;
	$::Wizard_splash = 0;
    } else {
	#- for i18n : %s is the type of connection of the list: (modem, isdn, adsl, cable, local network);
	$in->ask_okcancel(N("Network Configuration Wizard"), N("\n\n\nWe are now going to configure the %s connection.\n\n\nPress OK to continue.", translate($_[0])), 1);
    }
    undef $::Wizard_no_previous;
}

sub init_globals {
    my ($in, $prefix) = @_;
    MDK::Common::Globals::init(
			       in => $in,
			       prefix => $prefix,
			       connect_file => "/etc/sysconfig/network-scripts/net_cnx_up",
			       disconnect_file => "/etc/sysconfig/network-scripts/net_cnx_down",
			       connect_prog => "/etc/sysconfig/network-scripts/net_cnx_pg");
}

sub main {
    my ($prefix, $netcnx, $netc, $mouse, $in, $intf, $first_time, $_direct_fr, $noauto) = @_;
    init_globals($in, $prefix);
    $netc->{minus_one} = 0; #When one configure an eth in dhcp without gateway
    $::isInstall and $in->set_help('configureNetwork');
    $::isStandalone and read_net_conf($prefix, $netcnx, $netc); # REDONDANCE with intro. FIXME
    $netc->{NET_DEVICE} = $netcnx->{NET_DEVICE} if $netcnx->{NET_DEVICE}; # REDONDANCE with read_conf. FIXME
    $netc->{NET_INTERFACE} = $netcnx->{NET_INTERFACE} if $netcnx->{NET_INTERFACE}; # REDONDANCE with read_conf. FIXME
    network::network::read_all_conf($prefix, $netc ||= {}, $intf ||= {});

    modules::mergein_conf("$prefix/etc/modules.conf");

    my $direct_net_install;
    if ($first_time && $::isInstall && ($in->{method} eq "ftp" || $in->{method} eq "http" || $in->{method} eq "nfs")) {
	(!($::expert || $noauto) or $in->ask_okcancel(N("Network Configuration"),
						      N("Because you are doing a network installation, your network is already configured.
Click on Ok to keep your configuration, or cancel to reconfigure your Internet & Network connection.
"), 1)) and do {
    $netcnx->{type} = 'lan';
    output_with_perm("$prefix$connect_file", 0755,
      qq(
ifup eth0
));
    output("$prefix$disconnect_file", 0755,
      qq(
ifdown eth0
));
    $direct_net_install = 1;
    goto step_5;
};
    }

    $netc->{autodetection} = 1;
    $netc->{autodetect} = {};

  step_1:
    $::Wizard_no_previous = 1;
    my @profiles = get_profiles();
    eval { $in->ask_from(N("Network Configuration Wizard"),
			 N("Welcome to The Network Configuration Wizard.

We are about to configure your internet/network connection.
If you don't want to use the auto detection, deselect the checkbox.
"),
			 [
			  if_(@profiles > 1, { label => N("Choose the profile to configure"), val => \$netcnx->{PROFILE}, list => \@profiles }),
			  { label => N("Use auto detection"), val => \$netc->{autodetection}, type => 'bool' },
			  if_($::isStandalone, { label => N("Expert Mode"), val => \$::expert, type => 'bool' }),
			 ]
			) or goto step_5 }; $in->exit(0) if $@ =~ /wizcancel/;
    undef $::Wizard_no_previous;
    set_profile($netcnx);
    if ($netc->{autodetection}) {
	my $_w = $in->wait_message(N("Network Configuration Wizard"), N("Detecting devices..."));
	detect($netc->{autodetect}, $::isInstall && ($in->{method} eq "ftp" || $in->{method} eq "http" || $in->{method} eq "nfs"));
    }

  step_2:
    $conf{$_} = $netc->{autodetect}{$_} ? 1 : 0 foreach 'modem', 'winmodem', 'adsl', 'cable', 'lan';
    $conf{isdn} = $netc->{autodetect}{isdn}{description} ? 1 : 0;

    $::isInstall and $in->set_help('configureNetwork');
    my @l = (
	  [N("Normal modem connection") . if_($netc->{autodetect}{modem}, " - " . N("detected on port %s", $netc->{autodetect}{modem})), \$conf{modem}],
	  [N("Winmodem connection") . if_($netc->{autodetect}{winmodem}, " - " . N("detected")), \$conf{winmodem}],
	  [N("ISDN connection") . if_($netc->{autodetect}{isdn}{description}, " - " . N("detected %s", $netc->{autodetect}{isdn}{description})), \$conf{isdn}],
	  [N("ADSL connection") . if_($netc->{autodetect}{adsl}, " - " . N("detected")), \$conf{adsl}],
	  [N("Cable connection") . if_($netc->{autodetect}{cable}, " - " . N("cable connection detected")), \$conf{cable}],
	  [N("LAN connection") . if_($netc->{autodetect}{lan}, " - " . N("ethernet card(s) detected")), \$conf{lan}]
	 );
    $::isInstall and $in->set_help('configureNetwork');
    eval { $in->ask_from(N("Network Configuration Wizard"), N("Choose the connection you want to configure"),
			 [ map { { label => $_->[0], val => $_->[1], type => 'bool' } } @l ],
			 changed => sub {
			     return if !$netc->{autodetection};
			     my $c = 0;
			     #-      $conf{adsl} and $c++;
			     $conf{cable} and $c++;
			     my $a = keys(%{$netc->{autodetect}{lan}});
			     0 < $a && $a <= $c and $conf{lan} = undef;
			 }
			) or goto step_1;
	   load_conf($netcnx, $netc, $intf);
	   $conf{modem} and do { pre_func("modem"); require network::modem; network::modem::configure($in, $netcnx, $mouse, $netc, $intf) or goto step_2 };
	   $conf{winmodem} and do { pre_func("winmodem"); require network::modem; network::modem::winmodemConfigure($in, $netc) or goto step_2 }; 
	   $conf{isdn} and do { pre_func("isdn"); require network::isdn; network::isdn::configure($netcnx, $netc, undef) or goto step_2 };
	   $conf{adsl} and do { pre_func("adsl"); require network::adsl; network::adsl::configure($netcnx, $netc, $intf, $first_time) or goto step_2 };
	   $conf{cable} and do { pre_func("cable"); require network::ethernet; network::ethernet::configure_cable($netcnx, $netc, $intf, $first_time) or goto step_2; $netconnect::need_restart_network = 1 };
	   $conf{lan} and do { pre_func("local network"); require network::ethernet; network::ethernet::configure_lan($netcnx, $netc, $intf, $first_time) or goto step_2; $netconnect::need_restart_network = 1 };
       }; $in->exit(0) if $@ =~ /wizcancel/;
  
  step_2_1:
    my $nb = keys %{$netc->{internet_cnx}};
    if ($nb < 1) {
    } elsif ($nb > 1) {
	eval { $in->ask_from(N("Network Configuration Wizard"),
			     N("You have configured multiple ways to connect to the Internet.\nChoose the one you want to use.\n\n") . if_(!$::isStandalone, "You may want to configure some profiles after the installation, in the Mandrake Control Center"),
			     [ { label => N("Internet connection"), val => \$netc->{internet_cnx_choice}, list => [ keys %{$netc->{internet_cnx}} ] } ]
			    ) or goto step_2 }; $in->exit(0) if $@ =~ /wizcancel/;
    } elsif ($nb == 1) {
	$netc->{internet_cnx_choice} = (keys %{$netc->{internet_cnx}})[0];
    }
    member($netc->{internet_cnx_choice}, ('adsl', 'isdn')) and
      $netc->{at_boot} = $in->ask_yesorno(N("Network Configuration Wizard"), N("Do you want to start the connection at boot?"));
    if ($netc->{internet_cnx_choice}) {
	write_cnx_script($netc);
	$netcnx->{type} = $netc->{internet_cnx}{$netc->{internet_cnx_choice}}{type};
    } else {
	unlink "$prefix/etc/sysconfig/network-scripts/net_cnx_up";
	unlink "$prefix/etc/sysconfig/network-scripts/net_cnx_down";
	undef $netc->{NET_DEVICE};
    }

    my $success = 1;
    network::configureNetwork2($in, $prefix, $netc, $intf);
    my $network_configured = 1;
    
    eval { if ($netconnect::need_restart_network && $::isStandalone and ($::expert or $in->ask_yesorno(N("Network configuration"),
												       N("The network needs to be restarted"), 1) or goto step_2)) {
	if (!run_program::rooted($prefix, "/etc/rc.d/init.d/network restart")) {
	    $success = 0;
	    $in->ask_okcancel(N("Network Configuration"), 
			      N("A problem occured while restarting the network: \n\n%s", `/etc/rc.d/init.d/network restart`), 0);
	}
    }
       }; $in->exit(0) if $@ =~ /wizcancel/;

    write_initscript();
    $::isStandalone && member($netc->{internet_cnx_choice}, ('modem', 'adsl', 'isdn')) and
      $success = ask_connect_now($netc->{internet_cnx_choice});

  step_3:
    my $m = $success ? N("Congratulations, the network and Internet configuration is finished.
The configuration will now be applied to your system.

") . if_($::isStandalone && $in->isa('interactive_gtk'),
N("After this is done, we recommend that you restart your X environment to avoid any hostname-related problems.")) : 
      N("Problems occured during configuration.
Test your connection via net_monitor or mcc. If your connection doesn't work, you might want to relaunch the configuration.");
    if ($::isWizard) {
	$::Wizard_no_previous = 1;
	$::Wizard_finished = 1;
	eval { $in->ask_okcancel(N("Network Configuration"), $m, 1) }; $in->exit(0) if $@ =~ /wizcancel/;
	undef $::Wizard_no_previous;
	undef $::Wizard_finished;
    } else { $::isStandalone and $in->ask_warn('', $m) }

  step_5:
    $network_configured or network::configureNetwork2($in, $prefix, $netc, $intf);

    my $connect_cmd;
    if ($netcnx->{type} =~ /modem/ || $netcnx->{type} =~ /isdn_external/) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
if [ -e /usr/bin/kppp ]; then
/sbin/route del default
/usr/bin/kppp &
else
/usr/sbin/net_monitor --connect
fi
else
$connect_file
fi
);
    } elsif ($netcnx->{type}) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
/usr/sbin/net_monitor --connect
else
$connect_file
fi
);
    } else {
	$connect_cmd = qq(
#!/bin/bash
/usr/sbin/drakconnect
);
    }
    if ($direct_net_install) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
/usr/sbin/net_monitor --connect
else
$connect_file
fi
);
    }
    output_with_perm("$prefix$connect_prog", 0755, $connect_cmd) if $connect_cmd;
    $netcnx->{$_} = $netc->{$_} foreach qw(NET_DEVICE NET_INTERFACE);

    $netcnx->{NET_INTERFACE} and set_net_conf($netcnx, $netc);
    $netcnx->{type} =~ /adsl/ or system("/sbin/chkconfig --del adsl 2> /dev/null");
    save_conf($netcnx, $netc, $intf);

    if ($::isInstall && $::o->{security} >= 3) {
	require network::drakfirewall;
	network::drakfirewall::main($in, $::o->{security} <= 3);
    }
}

sub save_conf {
    my ($netcnx, $netc, $intf) = @_;
    my $adsl;
    my $modem;
    my $isdn;
    $netcnx->{type} =~ /adsl/ and $adsl = $netcnx->{$netcnx->{type}};
    $netcnx->{type} eq 'isdn_external' || $netcnx->{type} eq 'modem' and $modem = $netcnx->{$netcnx->{type}};
    $netcnx->{type} eq 'isdn_internal' and $isdn = $netcnx->{$netcnx->{type}};
    modules::load_category('network/main|gigabit|usb');
    require network::ethernet;
    network::ethernet->import;
    my @_all_cards = conf_network_card_backend($netc, $intf, undef, undef, undef, undef);

    $intf = { %$intf };
    my $str;
    $str .= "
PPPDevice=$modem->{device}
PPPDeviceSpeed=
PPPConnectionName=$modem->{connection}
PPPProviderDomain=$modem->{domain}
PPPLogin=$modem->{login}
PPPAuthentication=$modem->{auth}
PPPSpecialCommand=" . ($netcnx->{type} eq 'isdn_external' ? $netcnx->{isdn_external}{special_command} : '') if $conf{modem};

    $str .= "
ADSLInterfacesList=
ADSLModem=" .  q( # Obsolete information. Please don't use it.) . "
ADSLType=" . ($netcnx->{type} =~ /adsl/ ? $netcnx->{type} : '') . "
ADSLProviderDomain=$netc->{DOMAINNAME2}
ADSLLogin=$adsl->{login}
" . #ADSLPassword=$adsl->{passwd}
"DOMAINNAME2=$netc->{DOMAINNAME2}" if $conf{adsl};

    output_with_perm("$prefix/etc/sysconfig/network-scripts/drakconnect_conf", 0600, $str);
    my $a = $netcnx->{PROFILE} || "default";
    cp_af("$prefix/etc/sysconfig/network-scripts/drakconnect_conf", "$prefix/etc/sysconfig/network-scripts/drakconnect_conf." . $a);
    chmod 0600, "$prefix/etc/sysconfig/network-scripts/drakconnect_conf";
    chmod 0600, "$prefix/etc/sysconfig/network-scripts/drakconnect_conf." . $a;
    foreach (["$prefix$connect_file", "up"],
	      ["$prefix$disconnect_file", "down"],
	      ["$prefix$connect_prog", "prog"],
	      ["$prefix/etc/ppp/ioptions1B", "iop1B"],
	      ["$prefix/etc/ppp/ioptions2B", "iop2B"],
	      ["$prefix/etc/isdn/isdn1B.conf", "isdn1B"],
	      ["$prefix/etc/isdn/isdn2B.conf", "isdn2B"],
	      ["$prefix/etc/resolv.conf", "resolv"],
	      ["$prefix/etc/ppp/peers/adsl", "speedtouch"],
	      ["$prefix/etc/ppp/peers/adsl", "eci"],
	    ) {
	my $file = "$prefix/etc/sysconfig/network-scripts/net_" . $_->[1] . "." . $a;
	-e ($_->[0]) and cp_af($_->[0], $file) and chmod 0755, $file;
    }
}

sub set_profile {
    my ($netcnx, $profile) = @_;
    $profile ||= $netcnx->{PROFILE};
    $profile or return;
    my $f = "$prefix/etc/sysconfig/network-scripts/drakconnect_conf";
    -e ($f . "." . $profile) or return;
    $netcnx->{PROFILE} = $profile;
    cp_af($f . "." . $profile, $f);
    foreach (["$prefix$connect_file", "up"],
	      ["$prefix$disconnect_file", "down"],
	      ["$prefix$connect_prog", "prog"],
	      ["$prefix/etc/ppp/ioptions1B", "iop1B"],
	      ["$prefix/etc/ppp/ioptions2B", "iop2B"],
	      ["$prefix/etc/isdn/isdn1B.conf", "isdn1B"],
	      ["$prefix/etc/isdn/isdn2B.conf", "isdn2B"],
	      ["$prefix/etc/resolv.conf", "resolv"],
	      ["$prefix/etc/ppp/peers/adsl", "speedtouch"],
	      ["$prefix/etc/ppp/peers/adsl", "eci"],
	    ) {
	my $c = "$prefix/etc/sysconfig/network-scripts/net_" . $_->[1] . "." . $profile;
	-e ($c) and cp_af($c, $_->[0]);
    }
}

sub del_profile {
    my ($_netcnx, $profile) = @_;
    $profile or return;
    $profile eq "default" and return;
    rm_rf("$prefix/etc/sysconfig/network-scripts/drakconnect_conf." . $profile);
    rm_rf(glob_("$prefix/etc/sysconfig/network-scripts/net_{up,down,prog,iop1B,iop2B,isdn1B,isdn2B,resolv,speedtouch}." . $profile));
}

sub add_profile {
    my ($netcnx, $profile) = @_;
    $profile or return;
    $profile eq "default" and return;
    my $cmd1 = "$prefix/etc/sysconfig/network-scripts/drakconnect_conf." . ($netcnx->{PROFILE} || "default");
    my $cmd2 = "$prefix/etc/sysconfig/network-scripts/drakconnect_conf." . $profile;
    cp_af($cmd1, $cmd2);
}

sub get_profiles {
    map { if_(/drakconnect_conf\.(.*)/, $1) } all("$::prefix/etc/sysconfig/network-scripts");
}

sub load_conf {
    my ($netcnx, $netc, $intf) = @_;
    my $adsl_pptp = {};
    my $adsl_pppoe = {};
    my $modem = {};
    my $isdn_external = {};
    my $isdn = {};

    if (-e "$prefix/etc/sysconfig/network-scripts/drakconnect_conf") {
	foreach (cat_("$prefix/etc/sysconfig/network-scripts/drakconnect_conf")) {

	    /^PPPConnectionName=(.*)$/ and $modem->{connection} = $1; # Keep this for futur multiple cnx support
	    /^PPPProviderDomain=(.*)$/ and $modem->{domain} = $1; # used only for kppp
	    /^PPPLogin=(.*)$/ and $modem->{login} = $1;
	    /^PPPAuthentication=(.*)$/ and $modem->{auth} = $1; # We keep this because system is configured the same for both PAP and CHAP.
	    
	    if (/^PPPSpecialCommand=(.*)$/) {
		$netcnx->{type} eq 'isdn_external' and $netcnx->{$netcnx->{type}}{special_command} = $1;
	    }

	    /^DOMAINNAME2=(.*)$/ and $netc->{DOMAINNAME2} = $1;
	}
    }

    $adsl_pptp->{$_} = $adsl_pppoe->{$_} foreach 'login', 'passwd', 'passwd2';
    $isdn_external->{$_} = $modem->{$_} foreach 'device', 'connection', 'phone', 'domain', 'dns1', 'dns2', 'login', 'passwd', 'auth';
    $netcnx->{adsl_pptp} = $adsl_pptp;
    $netcnx->{adsl_pppoe} = $adsl_pppoe;
    $netcnx->{modem} = $modem;
    $netcnx->{modem} = $isdn_external;
    $netcnx->{isdn_internal} = $isdn;

    network::read_all_conf($prefix, $netc, $intf);
}

#- ensures the migration from old config files
sub read_raw_net_conf {
    my ($suffix) = @_;
    my $dir = "$::prefix/etc/sysconfig/network-scripts";
#    $suffix = $suffix ? ".$suffix" : '';
my $file = "$dir/draknet$suffix";
    rename $file, "$dir/drakconnect$suffix" if -e $file;
    getVarsFromSh("$dir/drakconnect_conf");
}

sub get_net_device {
	#${{ read_raw_net_conf() }}{InternetInterface};
	my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";
	my $network_file = "/etc/sysconfig/network";
	if (cat_("$prefix$connect_file") =~ /network/) {
		${ {getVarsFromSh("$prefix$network_file")} }{GATEWAYDEV};
	} else {
		"ppp+";
	};
}

sub read_net_conf {
    my ($_prefix, $netcnx, $netc) = @_;
    add2hash($netcnx, { read_raw_net_conf('_conf') });
    $netc->{$_} = $netcnx->{$_} foreach 'NET_DEVICE', 'NET_INTERFACE';
    $netcnx->{$netcnx->{type}} ||= {};
    add2hash($netcnx->{$netcnx->{type}}, { read_raw_net_conf($netcnx->{type}) });
}

sub set_net_conf {
    my ($netcnx, $netc) = @_;
    setVarsInShMode("$prefix/etc/sysconfig/drakconnect", 0600, $netcnx, "NET_DEVICE", "NET_INTERFACE", "type", "PROFILE");
    setVarsInShMode("$prefix/etc/sysconfig/drakconnect." . $netcnx->{type}, 0600, $netcnx->{$netcnx->{type}}); #- doesn't work, don't know why
    setVarsInShMode("$prefix/etc/sysconfig/drakconnect.netc", 0600, $netc); #- doesn't work, don't know why
}

sub start_internet {
    my ($o) = @_;
    init_globals($o, $o->{prefix});
    run_program::rooted($prefix, $connect_file);
}

sub stop_internet {
    my ($o) = @_;
    init_globals($o, $o->{prefix});
    run_program::rooted($prefix, $disconnect_file);
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;

=head1 network::netconnect::detect()

=head2 example of usage

use lib qw(/usr/lib/libDrakX);
use network::netconnect;
use Data::Dumper;

use class_discard;

local $in = class_discard->new;

network::netconnect::init_globals($in);
my %i;
&network::netconnect::detect(\%i);
print Dumper(\%i),"\n";

=cut
