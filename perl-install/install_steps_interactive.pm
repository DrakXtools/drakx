package install_steps_interactive;


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :functional :system);
use partition_table qw(:types);
use install_steps;
use install_any;
use detect_devices;
use run_program;
use commands;
use devices;
use fsedit;
use network;
use raid;
use mouse;
use modules;
use lang;
use services;
use loopback;
use keyboard;
use any;
use fs;
use log;

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub errorInStep($$) {
    my ($o, $err) = @_;
    $err =~ s/ at .*?$/\./ unless $::testing; #- avoid error message.
    $o->ask_warn(_("Error"), [ _("An error occurred"), $err ]);
}

sub kill_action {
    my ($o) = @_;
    $o->kill;
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage($) {
    my ($o) = @_;

    $o->{lang} =
      lang::text2lang($o->ask_from_list("Language",
					_("Which language do you want?"),
					# the translation may be used for the help
					[ lang::list() ],
					lang::lang2text($o->{lang})));
    install_steps::selectLanguage($o);

#-    $o->{useless_thing_accepted} = $o->ask_from_list_('', 
#-"Warning no warranty", 
#-			 [ __("Accept"), __("Refuse") ], "Accept") eq "Accept" or _exit(1) unless $o->{useless_thing_accepted};
}
#------------------------------------------------------------------------------
sub selectKeyboard($) {
    my ($o) = @_;
    $o->{keyboard} =
      keyboard::text2keyboard($o->ask_from_list_(_("Keyboard"),
						 _("What is your keyboard layout?"),
						 [ keyboard::list() ],
						 keyboard::keyboard2text($o->{keyboard})));
    delete $o->{keyboard_unsafe};
    install_steps::selectKeyboard($o);


    if ($::expert) {
	my $langs = $o->ask_many_from_list('', 
		_("You can choose other languages that will be available after install"),
		[ sort lang::list() ]) or goto &selectLanguage if $::expert;
	$o->{langs} = [ $o->{lang}, grep_index { $langs->[$::i] } lang::list() ];
    }
}
#------------------------------------------------------------------------------
sub selectRootPartition($@) {
    my ($o, @parts) = @_;
    $o->{upgradeRootPartition} =
      $o->ask_from_list(_("Root Partition"),
			_("What is the root partition (/) of your system?"),
			[ @parts ], $o->{upgradeRootPartition});
#- TODO check choice, then mount partition in $o->{prefix} and autodetect.
#-    install_steps::selectRootPartition($o);
}

sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $verif->($o->ask_from_list(_("Install Class"), _("Which installation class do you want?"), $l, $def));

    $o->ask_from_list_(_("Install/Upgrade"), _("Is this an install or an upgrade?"), $l2, $def2);
}

#------------------------------------------------------------------------------
sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    my %c = my @c = (
	_("Recommended") => "beginner",
	_("Customized")  => "specific",
	_("Expert")	 => "expert",
    );

    my $verifInstallClass = sub {
	$::beginner = $c{$_[0]} eq "beginner";
	$::expert   = $c{$_[0]} eq "expert" &&
	  $o->ask_from_list_('',
_("Are you sure you are an expert? 
Hey no kidding, you will be allowed powerfull but dangerous things here."), 
			 [ _("Hurt me plenty"), _("Normal") ]) ne "Normal";
    };      

    $o->{isUpgrade} = $o->selectInstallClass1($verifInstallClass,
					      first(list2kv(@c)), ${{reverse %c}}{$o->{installClass}},
					      [ __("Install"), __("Upgrade") ], $o->{isUpgrade} ? "Upgrade" : "Install") eq "Upgrade";

    if ($::corporate || $::beginner || $o->{isUpgrade}) {
	$o->{installClass} = "normal";
    } else {
	my %c = (
		 normal    => _("Normal"),
		 developer => _("Development"),
		 server    => _("Server"),
		);
	$o->{installClass} = ${{reverse %c}}{$o->ask_from_list(_("Install Class"),
							       _("Which usage do you want?"),
							       [ values %c ], $c{$o->{installClass}})};
    }
    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    if ($o->{mouse}{unsafe} || !$::beginner || $force) {
	my $name = $o->ask_from_list_('', _("What is the type of your mouse?"), [ mouse::names() ], $o->{mouse}{FULLNAME});
	$o->{mouse} = mouse::name2mouse($name);
    }
    $o->{mouse}{XEMU3} = 'yes' if $o->{mouse}{nbuttons} < 3; #- if $o->{mouse}{nbuttons} < 3 && $o->ask_yesorno('', _("Emulate third button?"), 1);

    if ($o->{mouse}{device} eq "ttyS") {
	$o->set_help('selectSerialPort');
	$o->{mouse}{device} = mouse::serial_ports_names2dev(
	  $o->ask_from_list(_("Mouse Port"),
			    _("Which serial port is your mouse connected to?"),
			    [ mouse::serial_ports_names() ]));
    }

    $o->setup_thiskind('SERIAL_USB', !$::expert, 0) if $o->{mouse}{device} eq "usbmouse";

    $o->SUPER::selectMouse;
}
#------------------------------------------------------------------------------
sub setupSCSI { 
    my ($o) = @_;
    { my $w = $o->wait_message(_("IDE"), _("Configuring IDE"));
      modules::load_ide() }
    setup_thiskind($_[0], 'scsi', $_[1], $_[2]);
}

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;
    my @fstab = grep { isExt2($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
#    @fstab = @$fstab if @fstab == 0;
    die _("no available partitions") if @fstab == 0;

    my $msg = sub { "$_->{device} " . _("(%dMb)", $_->{size} / 1024 / 2) };
    
    if (@fstab == 1) {
	$fstab[0]->{mntpoint} = '/';
    } elsif ($::beginner) {
	my %l; $l{&$msg} = $_ foreach @fstab;
	my $e = $o->ask_from_list('', 
				  _("Which partition do you want to use as your root partition"), 
				  [ sort keys %l ]);
	(fsedit::get_root($fstab) || {})->{mntpoint} = '';
	$l{$e}{mntpoint} = '/';
    } else {
	$o->ask_from_entries_ref
	  ('', 
	   _("Choose the mount points"),
	   [ map { &$msg } @fstab ],
	   [ map { +{ val => \$_->{mntpoint}, 
		      list => [ '', fsedit::suggestions_mntpoint([]) ]
		    } } @fstab ]);
    }
    $o->SUPER::ask_mntpoint_s($fstab);
}

#------------------------------------------------------------------------------
sub rebootNeeded($) {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));

    install_steps::rebootNeeded($o);
}

#------------------------------------------------------------------------------
sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab);

    my @l = grep { !$_->{isFormatted} && $_->{mntpoint} && !($::beginner && isSwap($_)) } @$fstab;
    $_->{toFormat} = 1 foreach grep {  $::beginner && isSwap($_) } @$fstab;

    return if $::beginner && 0 == grep { ! $_->{toFormat} } @l;

    $_->{toFormat} ||= $_->{toFormatUnsure} foreach @l;
    log::l("preparing to format $_->{mntpoint}") foreach grep { $_->{toFormat} } @l;

    my %label;
    $label{$_} = sprintf("%s   (%s)", 
			 isSwap($_) ? type2name($_->{type}) : $_->{mntpoint}, 
			 isLoopback($_) ? loopback::file($_) : $_->{device}) foreach @l;

    $o->ask_many_from_list_ref('', _("Choose the partitions you want to format"),
			       [ map { $label{$_} } @l ],
			       [ map { \$_->{toFormat} } @l ]) or die "cancel";
    @l = grep { $_->{toFormat} && !isLoopback($_) } @l;
    $o->ask_many_from_list_ref('', _("Check bad blocks?"),
			       [ map { $label{$_} } @l ],
			       [ map { \$_->{toFormatCheck} } @l ]) or goto &choosePartitionsToFormat if $::expert;
}


sub formatMountPartitions {
    my ($o, $fstab) = @_;
    my $w = $o->wait_message('', _("Formatting partitions"));
    fs::formatMount_all($o->{raid}, $o->{fstab}, $o->{prefix}, sub {
	my ($part) = @_;
	$w->set(isLoopback($part) ?
		_("Creating and formatting loopback file %s", loopback::file($part)) :
		_("Formatting partition %s", $part->{device}));
    });
    die _("Not enough swap to fulfill installation, please add some") if availableMemory < 40 * 1024;
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Looking for available packages"));
    $o->SUPER::setPackages;
}
#------------------------------------------------------------------------------
sub selectPackagesToUpgrade {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Finding packages to upgrade"));
    $o->SUPER::selectPackagesToUpgrade();
}
#------------------------------------------------------------------------------
sub choosePackages {
    my ($o, $packages, $compss, $compssUsers, $compssUsersSorted, $first_time) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user.
    $o->chooseCD($packages);

    require pkgs;
    unless ($o->{isUpgrade}) {
	my $available = pkgs::invCorrectSize(install_any::getAvailableSpace($o) / sqr(1024)) * sqr(1024);
	
	foreach (values %{$packages->[0]}) {
	    pkgs::packageSetFlagSkip($_, 0);
	    pkgs::packageSetFlagUnskip($_, 0);
	}
	pkgs::unselectAllPackages($packages);
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};

	pkgs::setSelectedFromCompssList($o->{compssListLevels}, $packages, $::expert ? 90 : 80, $available, $o->{installClass});
	my $min_size = pkgs::selectedSize($packages);

	$o->chooseGroups($packages, $compssUsers, $compssUsersSorted);

	my $max_size = int (sum map { pkgs::packageSize($_) } values %{$packages->[0]});

	 if (!$::beginner && $max_size > $available) {
	     $o->ask_okcancel('', 
_("You need %dMB for a full install of the groups you selected.
You can go on anyway, but be warned that you won't get all packages", $max_size / sqr(1024)), 1) or goto &choosePackages
	 }

	 my $size2install = $::beginner && $first_time ? $available * 0.7 : $o->chooseSizeToInstall($packages, $min_size, min($max_size, $available * 0.9)) or goto &choosePackages;

	 ($o->{packages_}{ind}) = 
	   pkgs::setSelectedFromCompssList($o->{compssListLevels}, $packages, 1, $size2install, $o->{installClass});
    }
    $o->choosePackagesTree($packages, $compss) if $o->{compssUsersChoice}{Individual} || $::expert && $o->{isUpgrade};
}

sub chooseSizeToInstall {
    my ($o, $packages, $min, $max) = @_;
    install_any::getAvailableSpace($o) * 0.7;
}
sub choosePackagesTree {}

sub chooseGroups {
    my ($o, $packages, $compssUsers, $compssUsersSorted) = @_;

    add2hash_($o->{compssUsersChoice}, { Individual => $::expert });
    $o->ask_many_from_list_ref('',
			       _("Package Group Selection"),
			       [ @$compssUsersSorted, _("Miscellaneous"), _("Individual package selection") ],
			       [ map { \$o->{compssUsersChoice}{$_} } @$compssUsersSorted, "Miscellaneous", "Individual" ]
			       ) or goto &chooseGroups unless $::beginner;

    unless ($o->{compssUsersChoice}{Miscellaneous}) {
	my %l;
	$l{@{$compssUsers->{$_}}} = () foreach @$compssUsersSorted;
	exists $l{$_} or pkgs::packageSetFlagSkip(pkgs::packageByName($packages, $_), 1) foreach keys %$packages;
    }
    foreach (@$compssUsersSorted) {
	$o->{compssUsersChoice}{$_} or pkgs::skipSetWithProvides($packages, @{$compssUsers->{$_}});
    }
    foreach (@$compssUsersSorted) {
	$o->{compssUsersChoice}{$_} or next;
	foreach (@{$compssUsers->{$_}}) {
	    $_->{unskip} = 1;
	    delete $_->{skip};
	}
    }
}

sub chooseCD {
    my ($o, $packages) = @_;

    #- get default values according to method, always skip empty medium
    #- which is the default (or current) CD which is always available...
    map { $packages->[2]{$_}{selected} = $o->{method} ne 'cdrom' } grep { $_ } keys %{$packages->[2]};

    $o->ask_many_from_list_ref('',
			       _("Choose other CD to install"),
			       [ map { $packages->[2]{$_}{descr} || _("Cd-Rom Nr %s", $_) } grep { $_ } keys %{$packages->[2]} ],
			       [ map { \$packages->[2]{$_}{selected} } grep { $_ } keys %{$packages->[2]} ]
			      ) or goto &chooseCD unless $::beginner;
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;
    my ($current, $total) = 0;

    my $w = $o->wait_message(_("Installing"), _("Preparing installation"));

    my $old = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my $m = shift;
	if ($m =~ /^Starting installation/) {
	    $total = $_[1];
	} elsif ($m =~ /^Starting installing package/) {
	    my $name = $_[0];
	    $w->set(_("Installing package %s\n%d%%", $name, $total && 100 * $current / $total));
	    $current += pkgs::packageSize(pkgs::packageByName($o->{packages}, $name));
	} else { unshift @_, $m; goto $old }
    };
    $o->SUPER::installPackages($packages);
}

sub afterInstallPackages($) {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Post install configuration"));
    $o->SUPER::afterInstallPackages($o);
}

#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o, $first_time) = @_;
    local $_;
    if ($o->{intf} && $first_time) {
	my @l = (
		 __("Keep the current IP configuration"),
		 __("Reconfigure network now"),
		 __("Do not set up networking"),
		);
	$_ = $::beginner ? "Keep" : 
	  $o->ask_from_list_([ _("Network Configuration") ],
			       _("Local networking has already been configured. Do you want to:"),
			     [ @l ]) || "Do not";
    } else {
	$_ = $::beginner ? "Do not" :
	  ($o->ask_yesorno([ _("Network Configuration") ],
			   _("Do you want to configure Local LAN networking for your system?"), 0) ? "Local LAN" : "Do not");
    }
    if (/^Do not/) {
	$o->{netc}{NETWORKING} = "false";
    } elsif (!/^Keep/) {
	$o->setup_thiskind('net', !$::expert, 1);
	my @l = detect_devices::getNet() or die _("no network card found");

	my $last; foreach ($::beginner ? $l[0] : @l) {
	    my $intf = network::findIntf($o->{intf} ||= [], $_);
	    add2hash($intf, $last);
	    add2hash($intf, { NETMASK => '255.255.255.0' });
	    $o->configureNetworkIntf($intf) or return;

	    $o->{netc} ||= {};
	    delete $o->{netc}{dnsServer};
	    delete $o->{netc}{GATEWAY};
	    $last = $intf;
	}
	#-	  {
	#-	      my $wait = $o->wait_message(_("Hostname"), _("Determining host name and domain..."));
	#-	      network::guessHostname($o->{prefix}, $o->{netc}, $o->{intf});
	#-	  }
	$last->{BOOTPROTO} =~ /^(dhcp|bootp)$/ ||
	  $o->configureNetworkNet($o->{netc}, $last ||= {}, @l) or return;
    }
    install_steps::configureNetwork($o);

    #- added ppp configuration after ethernet one.
    if (!$::beginner && $o->ask_yesorno([ _("Modem Configuration") ],
			_("Do you want to configure Dialup with modem networking for your system?"), 0)) {
	$o->pppConfig;
    }
}

sub configureNetworkIntf {
    my ($o, $intf) = @_;
    my $pump = $intf->{BOOTPROTO} =~ /^(dhcp|bootp)$/;
    delete $intf->{NETWORK};
    delete $intf->{BROADCAST};
    my @fields = qw(IPADDR NETMASK);
    $o->set_help('configureNetworkIP');
    $o->ask_from_entries_ref(_("Configuring network device %s", $intf->{DEVICE}),
($::isStandalone ? '' : _("Configuring network device %s", $intf->{DEVICE}) . "\n\n") .
_("Please enter the IP configuration for this machine.
Each item should be entered as an IP address in dotted-decimal
notation (for example, 1.2.3.4)."),
			     [ _("IP address:"), _("Netmask:"), _("Automatic IP") ],
			     [ \$intf->{IPADDR}, \$intf->{NETMASK}, { val => \$pump, type => "bool", text => _("(bootp/dhcp)") } ],
			     complete => sub {
				 $intf->{BOOTPROTO} = $pump ? "dhcp" : "static";
				 return 0 if $pump;
				 for (my $i = 0; $i < @fields; $i++) {
				     unless (network::is_ip($intf->{$fields[$i]})) {
					 $o->ask_warn('', _("IP address should be in format 1.2.3.4"));
					 return (1,$i);
				     }
				     return 0;
				 }
			     },
			     focus_out => sub {
				 $intf->{NETMASK} = network::netmask($intf->{IPADDR}) unless $_[0]
			     }
			    );
}

sub configureNetworkNet {
    my ($o, $netc, $intf, @devices) = @_;

    $netc->{dnsServer} ||= network::dns($intf->{IPADDR});
    $netc->{GATEWAY}   ||= network::gateway($intf->{IPADDR});

    $o->ask_from_entries_ref(_("Configuring network"),
_("Please enter your host name.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''.
You may also enter the IP address of the gateway if you have one"),
			     [_("Host name:"), _("DNS server:"), _("Gateway:"), $::expert ? _("Gateway device:") : ()],
			     [(map { \$netc->{$_}} qw(HOSTNAME dnsServer GATEWAY)),
			      {val => \$netc->{GATEWAYDEV}, list => \@devices}]
			    );

    $o->miscellaneousNetwork();
}

#------------------------------------------------------------------------------
sub pppConfig {
    my ($o) = @_;
    my $m = $o->{modem} ||= {};

    unless ($m->{device} || $::expert && !$o->ask_yesorno('', _("Try to find a modem?"), 1)) {
	foreach (0..3) {
	    next if $o->{mouse}{device} =~ /ttyS$_/;
	    detect_devices::hasModem("$o->{prefix}/dev/ttyS$_")
		and $m->{device} = "ttyS$_", last;
	}
    }

    $m->{device} ||= $o->set_help('selectSerialPort') && 
                     mouse::serial_ports_names2dev(
	$o->ask_from_list('', _("Which serial port is your modem connected to?"),
			  [ mouse::serial_ports_names ]));

    $o->set_help('configureNetworkISP');
    install_steps::pppConfig($o) if $o->ask_from_entries_refH('',
							      _("Dialup options"), [
_("Connection name") => \$m->{connection},
_("Phone number") => \$m->{phone},
_("Login ID") => \$m->{login},
_("Password") => { val => \$m->{passwd}, hidden => 1 },
_("Authentication") => { val => \$m->{auth}, list => [ __("PAP"), __("CHAP"), __("Terminal-based"), __("Script-based") ] },
_("Domain name") => \$m->{domain},
_("First DNS Server") => \$m->{dns1},
_("Second DNS Server") => \$m->{dns2},
    ]);
}

#------------------------------------------------------------------------------
sub installCrypto {
    my ($o) = @_;
    my $u = $o->{crypto} ||= {};
    
    $::expert or return;
    if ($o->{intf} && $o->{netc}{NETWORKING} ne 'false') {
	my $w = $o->wait_message('', _("Bringing up the network"));
	network::up_it($o->{prefix}, $o->{intf});
    } elsif ($o->{modem}) {
	run_program::rooted($o->{prefix}, "ifup", "ppp0");
    } else {
	return;
    }
    
    is_empty_hash_ref($u) and $o->ask_yesorno('', 
_("You have now the possibility to download software aimed for encryption.

WARNING:

Due to different general requirements applicable to these software and imposed
by various jurisdictions, customer and/or end user of theses software should
ensure that the laws of his/their jurisdiction allow him/them to download, stock
and/or use these software.

In addition customer and/or end user shall particularly be aware to not infringe
the laws of his/their jurisdiction. Should customer and/or end user do not
respect the provision of these applicable laws, he/they will incur serious
sanctions.

In no event shall Mandrakesoft nor its manufacturers and/or suppliers be liable
for special, indirect or incidental damages whatsoever (including, but not
limited to loss of profits, business interruption, loss of commercial data and
other pecuniary losses, and eventual liabilities and indemnification to be paid
pursuant to a court decision) arising out of use, possession, or the sole
downloading of these software, to which customer and/or end user could
eventually have access after having sign up the present agreement.


For any queries relating to these agreement, please contact 
Mandrakesoft, Inc.
2400 N. Lincoln Avenue Suite 243
Altadena California 91001
USA")) || return;

    require crypto;
    eval {
      $u->{mirror} = crypto::text2mirror($o->ask_from_list('', _("Choose a mirror from which to get the packages"), [ crypto::mirrorstext() ], crypto::mirror2text($u->{mirror})));
    };
    return if $@;
    
    my @packages = do {
      my $w = $o->wait_message('', _("Contacting the mirror to get the list of available packages"));
      crypto::packages($u->{mirror});
    };

    $o->ask_many_from_list_ref('', _("Which packages do you want to install"), \@packages, [ map { \$u->{packages}{$_} } @packages ]) or return;

    my $w = $o->wait_message('', _("Downloading cryptographic packages"));
    install_steps::installCrypto($o);
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f, $clicked) = @_;

    require timezone;
    $o->{timezone}{timezone} = $o->ask_from_treelist('', _("Which is your timezone?"), '/', [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone});
    $o->{timezone}{UTC} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{UTC}) if $::expert || $clicked;
    install_steps::timeConfig($o, $f);
}

#------------------------------------------------------------------------------
sub servicesConfig { 
    my ($o) = @_;
    services::drakxservices($o, $o->{prefix});
}

#------------------------------------------------------------------------------
sub printerConfig {
    my ($o, $clicked) = @_;

    return if $::corporate && $::beginner && !$clicked;

    require printer;
    eval { add2hash($o->{printer} ||= {}, printer::getinfo($o->{prefix})) };
    require printerdrake;
    printerdrake::main($o->{printer}, $o, sub { install_any::pkg_install($o, $_[0]) });
}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $o->set_help("setRootPassword", 
		 $o->{installClass} eq "server" || $::expert ? "setRootPasswordMd5" : (),
		 $::beginner ? () : "setRootPasswordNIS");

    $o->ask_from_entries_refH([_("Set root password"), _("Ok"), $o->{security} > 2 ? () : _("No password")],
			 [ _("Set root password"), 
			   $::beginner ? "\n" .
_("(an user ``mandrake'' with password ``mandrake'' has been automatically added)") : ()
			 ], [
_("Password") => { val => \$sup->{password},  hidden => 1 },
_("Password (again)") => { val => \$sup->{password2}, hidden => 1 },
  $o->{installClass} eq "server" || $::expert ? (
_("Use shadow file") => { val => \$o->{authentication}{shadow}, type => 'bool', text => _("shadow") },
_("Use MD5 passwords") => { val => \$o->{authentication}{md5}, type => 'bool', text => _("MD5") },
  ) : (), $::beginner ? () : (
_("Use NIS") => { val => \$o->{authentication}{NIS}, type => 'bool', text => _("yellow pages") },
  )
			 ],
			 complete => sub {
			     $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,1);
			     length $sup->{password} < 2 * $o->{security}
			       and $o->ask_warn('', _("This password is too simple (must be at least %d characters long)", 2 * $o->{security})), return (1,0);
			     return 0
			 }
    ) or return;

    if ($o->{authentication}{NIS}) {
	$o->ask_from_entries_ref('',
				 _("Authentification NIS"),
				 [ _("NIS Domain"), _("NIS Server") ],
				 [ \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}),
				   { val => \$o->{authentication}{NIS_server}, list => ["broadcast"] },
				 ]);
    }
    install_steps::setRootPassword($o);
}

#------------------------------------------------------------------------------
#-addUser
#------------------------------------------------------------------------------
sub addUser {
    my ($o, $clicked) = @_;
    my $u = $o->{user} ||= $o->{security} < 1 ? { name => "mandrake", password => "mandrake", realname => "default" } : {};
    $u->{password2} ||= $u->{password} ||= "";
    $u->{shell} ||= "/bin/bash";
    $u->{icon} ||= translate('default');
    my @fields = qw(realname name password password2);
    my @shells = install_any::shells($o);

    if (($o->{security} >= 2 && !$::beginner || $clicked) && $o->ask_from_entries_refH(
        [ _("Add user"), _("Accept user"), $o->{security} >= 4 && !@{$o->{users}} ? () : _("Done") ],
        _("Enter a user\n%s", $o->{users} ? _("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @{$o->{users}})) : ''),
        [ 
	 _("Real name") => \$u->{realname},
	 _("User name") => \$u->{name},
	   $o->{security} < 2 ? () : (
         _("Password") => {val => \$u->{password}, hidden => 1},
         _("Password (again)") => {val => \$u->{password2}, hidden => 1},
	   ), $::beginner ? () : (
         _("Shell") => {val => \$u->{shell}, list => \@shells, not_edit => !$::expert} 
	   ), $o->{security} > 3 || $::beginner ? () : (
	 _("Icon") => {val => \$u->{icon}, list => [ map { translate($_) } @any::users ], not_edit => 1 },
	   ),
        ],
        focus_out => sub {
	    if ($_[0] eq 0) {
		$u->{name} ||= lc first($u->{realname} =~ /((\w|-)+)/);
	    }
	},
        complete => sub {
	    $u->{password} eq $u->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,3);
	    $o->{security} > 3 && length($u->{password}) < 6 and $o->ask_warn('', _("This password is too simple")), return (1,2);
	    $u->{name} or $o->ask_warn('', _("Please give a user name")), return (1,0);
	    $u->{name} =~ /^[a-z0-9_-]+$/ or $o->ask_warn('', _("The user name must contain only lower cased letters, numbers, `-' and `_'")), return (1,0);
	    member($u->{name}, map { $_->{name} } @{$o->{users}}) and $o->ask_warn('', _("This user name is already added")), return (1,0);
	    $u->{icon} = untranslate($u->{icon}, @any::users);
	    return 0;
	},
    )) {
	push @{$o->{users}}, $o->{user};
	$o->{user} = {};
	goto &addUser;
    }
    install_steps::addUser($o);
}




#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time) = @_;

    return if $first_time && $::beginner;

    my @l = detect_devices::floppies();
    my %l = (
	     'fd0'  => __("First floppy drive"),
	     'fd1'  => __("Second floppy drive"),
	     'Skip' => __("Skip"),
	    );
    $l{$_} ||= $_ foreach @l;

    if ($first_time || @l == 1) {
	$o->ask_yesorno('',
			_("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
LILO on your system, or another operating system removes LILO, or LILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?"), 
			$o->{mkbootdisk}) or return $o->{mkbootdisk} = '';
	$o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
    } else {
	@l or die _("Sorry, no floppy drive available");

	$o->{mkbootdisk} = ${{reverse %l}}{$o->ask_from_list_('',
							      _("Choose the floppy drive you want to use to make the bootdisk"),
							      [ @l{@l, "Skip"} ], $o->{mkbootdisk})};
	return $o->{mkbootdisk} = '' if $o->{mkbootdisk} eq 'Skip';
    }

    $o->ask_warn('', _("Insert a floppy in drive %s", $l{$o->{mkbootdisk}}));
    my $w = $o->wait_message('', _("Creating bootdisk"));
    install_steps::createBootdisk($o);
}

#------------------------------------------------------------------------------
sub setupLILO {
    my ($o, $more) = @_;
    any::setupBootloader($o, $o->{bootloader}, $o->{hds}, $o->{fstab}, $o->{security}, $o->{prefix}, $more);

    eval { $o->SUPER::setupBootloader };
    if ($@) {
	$o->ask_warn('', 
		     [ _("Installation of LILO failed. The following error occured:"),
		       grep { !/^Warning:/ } cat_("$o->{prefix}/tmp/.error") ]);
	unlink "$o->{prefix}/tmp/.error";
	die "already displayed";
    }
}

#------------------------------------------------------------------------------
sub setupSILO {
    my ($o, $more) = @_;
    my $b = $o->{bootloader};

    #- assume this default parameters.
    $b->{root} = "/dev/" . fsedit::get_root($o->{fstab})->{device};
    $b->{partition} = ($b->{root} =~ /\D*(\d*)/)[0] || '1';

    if ($::beginner && $more == 1) {
	#- nothing more to do here.
    } elsif ($more || !$::beginner) {
	$o->set_help("setupBootloaderGeneral");

	$::expert and $o->ask_yesorno('', _("Do you want to use SILO?"), 1) || return;

	my @l = (
_("Delay before booting default image") => \$b->{timeout},
$o->{security} < 4 ? () : (
_("Password") => { val => \$b->{password}, hidden => 1 },
_("Password (again)") => { val => \$b->{password2}, hidden => 1 },
_("Restrict command line options") => { val => \$b->{restricted}, type => "bool", text => _("restrict") },
)
	);

	$o->ask_from_entries_refH('', _("SILO main options"), \@l,
				 complete => sub {
#-				     $o->{security} > 4 && length($b->{password}) < 6 and $o->ask_warn('', _("At this level of security, a password (and a good one) in silo is requested")), return 1;
				     $b->{restricted} && !$b->{password} and $o->ask_warn('', _("Option ``Restrict command line options'' is of no use without a password")), return 1;
				     $b->{password} eq $b->{password2} or !$b->{restricted} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return 1;
				     0;
				 }
				) or return;
    }

    until ($::beginner && $more <= 1) {
	$o->set_help('setupBootloaderAddEntry');
	my $c = $o->ask_from_list_([''], 
_("Here are the following entries in SILO.
You can add some more or change the existing ones."),
		[ (sort @{[map { "$_->{label} ($_->{kernel_or_dev})" . ($b->{default} eq $_->{label} && "  *") } @{$b->{entries}}]}), __("Add"), __("Done") ],
	);
	$c eq "Done" and last;

	my ($e);

	if ($c eq "Add") {
	    my @labels = map { $_->{label} } @{$b->{entries}};
	    my $prefix;

	    $e = { type => 'image' };
	    $prefix = "linux";

	    $e->{label} = $prefix;
	    for (my $nb = 0; member($e->{label}, @labels); $nb++) { $e->{label} = "$prefix-$nb" }
	} else {
	    $c =~ /(\S+)/;
	    ($e) = grep { $_->{label} eq $1 } @{$b->{entries}};
	}
	my %old_e = %$e;
	my $default = my $old_default = $e->{label} eq $b->{default};
	    
	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
_("Image") => { val => \$e->{kernel_or_dev}, list => [ eval { glob_("/boot/vmlinuz*") } ] },
_("Partition") => { val => \$e->{partition}, list => [ map { ("/dev/$_->{device}" =~ /\D*(\d*)/)[0] || 1} @{$o->{fstab}} ], not_edit => !$::expert },
_("Root") => { val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @{$o->{fstab}} ], not_edit => !$::expert },
_("Append") => \$e->{append},
_("Initrd") => { val => \$e->{initrd}, list => [ eval { glob_("/boot/initrd*") } ] },
_("Read-write") => { val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..7] unless $::expert;
	} else {
	    die "Other SILO entries not supported at the moment";
	}
	@l = (
_("Label") => \$e->{label},
@l,
_("Default") => { val => \$default, type => 'bool' },
	);

	if ($o->ask_from_entries_refH($c eq "Add" ? '' : ['', _("Ok"), _("Remove entry")], 
	    '', \@l,
	    complete => sub {
		$e->{label} or $o->ask_warn('', _("Empty label not allowed")), return 1;
		member($e->{label}, map { $_->{label} } grep { $_ != $e } @{$b->{entries}}) and $o->ask_warn('', _("This label is already in use")), return 1;
		0;
	    })) {
	    $b->{default} = $old_default || $default ? $default && $e->{label} : $b->{default};
	    
	    push @{$b->{entries}}, $e if $c eq "Add";
	} else {
	    @{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	}
    }
    eval { $o->SUPER::setupBootloader };
    if ($@) {
	$o->ask_warn('', 
		     [ _("Installation of SILO failed. The following error occured:"),
		       grep { !/^Warning:/ } cat_("$o->{prefix}/tmp/.error") ]);
	unlink "$o->{prefix}/tmp/.error";
	die "already displayed";
    }
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Preparing bootloader"));
    $o->SUPER::setupBootloaderBefore($o);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o) = @_;
    if (arch() =~ /^alpha/) {
	$o->ask_yesorno('', _("Do you want to use aboot?"), 1) or return;
	$o->SUPER::setupBootloader;	
    } elsif (arch() =~ /^sparc/) {
	&setupSILO;
    } else {
	&setupLILO;
    }
}

#------------------------------------------------------------------------------
sub miscellaneousNetwork {
    my ($o, $clicked) = @_;
    my $u = $o->{miscellaneous} ||= {};

    $o->set_help('configureNetworkProxy');
    !$::beginner || $clicked and $o->ask_from_entries_ref('',
       _("Proxies configuration"),
       [ _("HTTP proxy"),
         _("FTP proxy"),
       ],
       [ \$u->{http_proxy},
         \$u->{ftp_proxy},
       ],
       complete => sub {
	   $u->{http_proxy} =~ m,^($|http://), or $o->ask_warn('', _("Proxy should be http://...")), return 1,3;
	   $u->{ftp_proxy} =~ m,^($|ftp://), or $o->ask_warn('', _("Proxy should be ftp://...")), return 1,4;
	   0;
       }
    ) || return;
}

#------------------------------------------------------------------------------
sub miscellaneous {
    my ($o, $clicked) = @_;
    my %l = (
	0 => _("Welcome To Crackers"),
	1 => _("Poor"),
	2 => _("Low"),
	3 => _("Medium"),
	4 => _("High"),
	5 => _("Paranoid"),
    );
    delete @l{0,1,5} unless $::expert;

    install_steps::miscellaneous($o);
    my $u = $o->{miscellaneous} ||= {};
    exists $u->{LAPTOP} or $u->{LAPTOP} = 1;
    my $s = $o->{security};

    add2hash_ $o, { useSupermount => $s < 4 };
    $s = $l{$s} || $s;

    !$::beginner || $clicked and $o->ask_from_entries_refH('',
	_("Miscellaneous questions"), [
_("Use hard drive optimisations?") => { val => \$u->{HDPARM}, type => 'bool', text => _("(may cause data corruption)") },
_("Choose security level") => { val => \$s, list => [ map { $l{$_} } ikeys %l ], not_edit => 1 },
_("Precise RAM size if needed (found %d MB)", availableRam / 1024 + 3) => \$u->{memsize}, #- add three for correction.
_("Removable media automounting") => { val => \$o->{useSupermount}, type => 'bool', text => 'supermount' },
     $::expert ? (
_("Clean /tmp at each boot") => { val => \$u->{CLEAN_TMP}, type => 'bool' },
     ) : (),
     $u->{numlock} ? (
_("Enable num lock at startup") => { val => \$u->{numlock}, type => 'bool' },
     ) : (),
     ], complete => sub {
	    !$u->{memsize} || $u->{memsize} =~ s/^(\d+)M?$/$1M/i or $o->ask_warn('', _("Give the ram size in Mb")), return 1;
	    my %m = reverse %l; $ENV{SECURE_LEVEL} = $o->{security} = $m{$s};
	    $o->{useSupermount} && $o->{security} > 3 and $o->ask_warn('', _("Can't use supermount in high security level")), return 1;
	    0;
	}
    ) || return;
}

#------------------------------------------------------------------------------
sub setupXfree {
    my ($o) = @_;
    $o->setupXfreeBefore;

    require Xconfig;
    require Xconfigurator;
    #- by default do not use existing configuration, so new card will be detected.
    if ($o->{isUpgrade} && -r "$o->{prefix}/etc/X11/XF86Config") {
	if ($::beginner || $o->ask_yesorno('', _("Use existing configuration for X11?"), 1)) {
	    Xconfig::getinfoFromXF86Config($o->{X}, $o->{prefix});
	}
    }
    #- strange, xfs must not be started twice...
    #- trying to stop and restart it does nothing good too...
    my $xfs_started if 0;
    run_program::rooted($o->{prefix}, "/etc/rc.d/init.d/xfs", "start") unless $xfs_started;
    $xfs_started = 1;

    { local $::testing = 0; #- unset testing
      local $::auto = $::beginner;
      local $::noauto = $::expert && !$o->ask_yesorno('', _("Try to find PCI devices?"), 1);
      $::noauto = $::noauto; #- no warning

      Xconfigurator::main($o->{prefix}, $o->{X}, $o, $o->{allowFB}, bool($o->{pcmcia}), sub {
	  install_any::pkg_install($o, "XFree86-$_[0]");
      });
    }
    $o->setupXfreeAfter;
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy($) {
    my ($o) = @_;

    $::expert && $::corporate || $::g_auto_install or return;

    my ($floppy) = detect_devices::floppies();

    $o->ask_yesorno('', 
"Do you want to generate an auto install floppy for linux replication?", $floppy) or return;

    $o->ask_warn('', _("Insert a blank floppy in drive %s", $floppy));

    my $dev = devices::make($floppy);

    my $image = $o->{pcmcia} ? "pcmcia" :
      ${{ hd => 'hd', cdrom => 'cdrom', ftp => 'network', nfs => 'network', http => 'network' }}{$o->{method}};
	
    if (my $fd = install_any::getFile("$image.img")) {
	 my $w = $o->wait_message('', _("Creating auto install floppy"));
	 local *OUT;
	 open OUT, ">$dev" or log::l("failed to write $dev"), return;
	 local $/ = \ (16 * 1024);
	 print OUT foreach <$fd>;
    }
    fs::mount($dev, "/floppy", "vfat", 0);
    substInFile { s/timeout.*//; s/^(\s*append)/$1 kickstart=floppy/ } "/floppy/syslinux.cfg";

    output "/floppy/ks.cfg", install_any::generate_ks_cfg($o);
    output "/floppy/boot.msg", "\n0c",
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost !!
", "07\n";

    local $o->{partitioning}{clearall} = 1;
    install_any::g_auto_install("/floppy/auto_inst.cfg");

    fs::umount("/floppy");
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' unless $alldone || $o->ask_yesorno('', 
_("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_any::unlockCdrom;

    $o->ask_warn('',
_("Congratulations, installation is complete.
Remove the boot media and press return to reboot.

For information on fixes which are available for this release of Linux-Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.

Information on configuring your system is available in the post
install chapter of the Official Linux-Mandrake User's Guide.")) if $alldone && !$::g_auto_install;

    $::global_wait = $o->wait_message('', _("Shutting down"));
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################

#--------------------------------------------------------------------------------
sub wait_load_module {
    my ($o, $type, $text, $module) = @_;
    $o->wait_message('',
		     [ _("Installing driver for %s card %s", $type, $text),
		       $::beginner ? () : _("(module %s)", $module)
		     ]);
}


sub load_module {
    my ($o, $type) = @_;
    my @options;

    my $l = $o->ask_from_list('',
			      _("Which %s driver should I try?", $type),
			      [ modules::text_of_type($type) ]) or return;
    my $m = modules::text2driver($l);

    require modparm;
    my @names = modparm::get_options_name($m);

    if ((@names != 0) && $o->ask_from_list_('',
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $l),
			      [ __("Autoprobe"), __("Specify options") ], "Autoprobe") ne "Autoprobe") {
      ASK:
	if (@names >= 0) {
	    my @l = $o->ask_from_entries('',
_("You may now provide its options to module %s.", $l),
					 \@names) or return;
	    @options = modparm::get_options_result($m, @l);
	} else {
	    @options = split ' ',
	      $o->ask_from_entry('',
_("You may now provide its options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $l),
				 _("Module options:"),
				);
	}
    }
    eval { 
	my $w = wait_load_module($o, $type, $l, $m);
	modules::load($m, $type, @options);
    };
    if ($@) {
	$o->ask_yesorno('',
_("Loading module %s failed.
Do you want to try again with other parameters?", $l), 1) or return;
	goto ASK;
    }
    $l, $m;
}

#------------------------------------------------------------------------------
sub load_thiskind {
    my ($o, $type) = @_;
    my $w; #- needed to make the wait_message stay alive
    my $pcmcia = $o->{pcmcia}
      unless !$::beginner && modules::pcmcia_need_config($o->{pcmcia}) && 
	     !$o->ask_yesorno('', _("Try to find PCMCIA cards?"), 1);
    $w = $o->wait_message(_("PCMCIA"), _("Configuring PCMCIA cards...")) if modules::pcmcia_need_config($pcmcia);

    modules::load_thiskind($type, sub { $w = wait_load_module($o, $type, @_) }, $pcmcia);
}

#------------------------------------------------------------------------------
sub setup_thiskind {
    my ($o, $type, $auto, $at_least_one) = @_;

    my @l;
    my $allow_probe = !$::expert || $o->ask_yesorno('', _("Try to find PCI devices?"), 1);

    if ($allow_probe && $type =~ /scsi/i) {
	#- hey, we're allowed to pci probe :)   let's do a lot of probing!
	require pci_probing::main;
	if (my ($c) = pci_probing::main::probe('AUDIO')) {
	    modules::add_alias("sound", $c->[1]) if pci_probing::main::check($c->[1]);
	}
    }
    if ($allow_probe) {
	eval { @l = $o->load_thiskind($type) };
	if ($@) {
	    $o->errorInStep($@);
	} else {
	    return if $auto && (@l || !$at_least_one);
	}
    }
    while (1) {
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", map { $_->[0] } @l), $type),
	    _("Do you have another one?") ] :
	  _("Do you have any %s interface?", $type);

	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = "Yes";
	$r = $o->ask_from_list_('', $msg, $opt, "No") unless $at_least_one && @l == 0;
	if ($r eq "No") { return }
	elsif ($r eq "Yes") {
	    my @r = $o->load_module($type) or return;
	    push @l, \@r;
	} else {
	    #-eval { commands::modprobe("isapnp") };
	    require pci_probing::main;
	    $o->ask_warn('', [ pci_probing::main::list() ]); #-, scalar cat_("/proc/isapnp") ]);
	}
    }
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
