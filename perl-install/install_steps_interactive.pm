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
use pci_probing::main;
use install_any;
use detect_devices;
use timezone;
use run_program;
use commands;
use fsedit;
use network;
use raid;
use mouse;
use modules;
use lang;
use pkgs;
use keyboard;
use fs;
use modparm;
use log;
use printer;
use lilo;
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
#-			 [ __("Accept"), __("Refuse") ], "Accept") eq "Accept" or exit(1) unless $o->{useless_thing_accepted};
}
#------------------------------------------------------------------------------
sub selectKeyboard($) {
    my ($o) = @_;
    $o->{keyboard} =
      keyboard::text2keyboard($o->ask_from_list_("Keyboard",
						 _("What is your keyboard layout?"),
						 [ keyboard::list() ],
						 keyboard::keyboard2text($o->{keyboard})));
    delete $o->{keyboard_unsafe};
    install_steps::selectKeyboard($o);
}
#------------------------------------------------------------------------------
sub selectPath($) {
    my ($o) = @_;
    $o->{isUpgrade} =
      $o->ask_from_list_(_("Install/Upgrade"),
			 _("Is this an install or an upgrade?"),
			 [ __("Install"), __("Upgrade") ],
			 $o->{isUpgrade} ? "Upgrade" : "Install") eq "Upgrade";
    install_steps::selectPath($o);
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
#------------------------------------------------------------------------------
sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    my @c = qw(beginner specific expert);
    my %c = (
	     beginner  => _("Recommended"),
	     specific  => _("Customized"),
	     expert    => _("Expert"),
	    );
    my $installClass = ${{reverse %c}}{$o->ask_from_list(_("Install Class"),
							 _("What installation class do you want?"),
							 [ map { $c{$_} } @c ], $c{$o->{installClass}} || $c{beginner})};
    $::expert   = $installClass eq "expert";
    $::beginner = $installClass eq "beginner";

    if ($::beginner) {
	$o->{installClass} = "normal";
    } else {
	my %c = (
		 normal    => _("Normal"),
		 developer => _("Developement"),
		 server    => _("Server"),
		);
	$o->{installClass} = ${{reverse %c}}{$o->ask_from_list(_("Install Class"),
							       _("What usage do you want?"),
							       [ values %c ], $c{$o->{installClass}})};
    }
    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    my $name = $o->{mouse}{FULLNAME};
    if (!$name || $::expert || $force) {
	$name ||= "Generic Mouse (serial)";
	$name = $o->ask_from_list_('', _("What is the type of your mouse?"), [ mouse::names() ], $name);
	$o->{mouse} = mouse::name2mouse($name);
    }
    my $b = $o->{mouse}{nbuttons} < 3;
    $o->{mouse}{XEMU3} = 'yes' if $::expert && $o->ask_yesorno('', _("Emulate third button?"), $b) || $b;

    $o->{mouse}{device} = mouse::serial_ports_names2dev(
	$o->ask_from_list(_("Mouse Port"),
			  _("Which serial port is your mouse connected to?"),
			  [ mouse::serial_ports_names() ])) if $o->{mouse}{device} eq "ttyS";

    $o->SUPER::selectMouse;
}
#------------------------------------------------------------------------------
sub setupSCSI { setup_thiskind($_[0], 'scsi', $_[1], $_[2]) }

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;
    my @fstab = grep { isExt2($_) } @$fstab;
    @fstab = grep { !isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
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

    my @l = grep { $_->{mntpoint} && !($::beginner && isSwap($_)) } @$fstab;
    $_->{toFormat} = 1 foreach grep {  $::beginner && isSwap($_) } @$fstab;

    return if $::beginner && 0 == grep { ! $_->{toFormat} } @l;

    $_->{toFormat} ||= $_->{toFormatUnsure} foreach @l;
    log::l("preparing to format $_->{mntpoint}") foreach grep { $_->{toFormat} } @l;

    $o->ask_many_from_list_ref('', _("Choose the partitions you want to format"),
			       [ map { isSwap($_) ? type2name($_->{type}) . " ($_->{device})" : $_->{mntpoint} } @l ],
			       [ map { \$_->{toFormat} } @l ]) or die "cancel";
}

sub formatPartitions {
    my $o = shift;
    my $w = $o->wait_message('', '');
    foreach (@_) {
	if ($_->{toFormat}) {
	    $w->set(_("Formatting partition %s", $_->{device}));
	    raid::format_part($o->{raid}, $_);
	}
    }
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
    my ($o, $packages, $compss, $compssUsers) = @_;
    my %s;

    $o->ask_many_from_list_ref('',
			       _("Package Group Selection"),
			       [ keys %$compssUsers ],
			       [ map { \$o->{compssUsersChoice}{$_} } keys %$compssUsers ]
			       );
}
#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o, $first_time) = @_;
    local $_;
    if ($o->{intf} && $o->{netc}{NETWORKING} ne 'false') {
	if (!$::beginner && $first_time || $::expert) {
	    my @l = (
		     __("Keep the current IP configuration"),
		     __("Reconfigure network now"),
		     __("Do not set up networking"),
		    );
	    $_ = $o->ask_from_list_([ _("Network Configuration") ],
				    _("Local networking has already been configured. Do you want to:"),
				    [ @l ]) || "Do not";
	} else { $_ = "Keep"; } 
    } elsif ($o->{modem}) {
	$_ = "Dialup";
    } else {
	$_ = $::beginner ? "Do not" :
	  $o->ask_from_list_([ _("Network Configuration") ],
			     _("Do you want to configure networking for yout system?"),
			     [ __("Local LAN"), __("Dialup with modem"), __("Do not set up networking") ]);
    }

    if (/^Dialup/) {
	$o->pppConfig;
    } elsif (/^Do not/) {
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
}

sub configureNetworkIntf {
    my ($o, $intf) = @_;
    my $pump = $intf->{BOOTPROTO} =~ /^(dhcp|bootp)$/;
    delete $intf->{NETWORK};
    delete $intf->{BROADCAST};
    my @fields = qw(IPADDR NETMASK);
    $o->ask_from_entries_ref(_("Configuring network device %s", $intf->{DEVICE}),
_("Please enter the IP configuration for this machine.
Each item should be entered as an IP address in dotted-decimal
notation (for example, 1.2.3.4)."),
			     [ _("IP address:"), _("Netmask:"), _("Automatic IP") ],
			     [ \$intf->{IPADDR}, \$intf->{NETMASK}, { val => \$pump, type => "bool", text => _("(bootp/dhcp)") } ],
			     complete => sub {
				 $intf->{BOOTPROTO} = $pump ? "bootp" : "static";
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
			     [_("Host name:"), _("DNS server:"), _("Gateway:"), !$::beginner ? _("Gateway device:") : ()],
			     [(map { \$netc->{$_}} qw(HOSTNAME dnsServer GATEWAY)),
			      {val => \$netc->{GATEWAYDEV}, list => \@devices}]
			    );

    $o->miscellaneousNetwork();
}

#------------------------------------------------------------------------------
sub pppConfig {
    my ($o) = @_;
    my $m = $o->{modem} ||= {};

    unless ($m->{device} || $::expert && $o->ask_yesorno('', _("Try to find a modem?"), 1)) {
	foreach (0..3) {
	    next if readlink("$o->{prefix}/dev/mouse") =~ /ttyS$_/;
	    detect_devices::hasModem("$o->{prefix}/dev/ttyS$_")
		and $m->{device} = "ttyS$_", last;
	}
    }

    $m->{device} ||= mouse::serial_ports_names2dev(
	$o->ask_from_list('', _("Which serial port is your modem connected to?"),
			  [ mouse::serial_ports_names ]));

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

    $o->miscellaneousNetwork();
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f, $clicked) = @_;

    $o->{timezone}{timezone} ||= timezone::bestTimezone(lang::lang2text($o->{lang}));
    $o->{timezone}{timezone} = $o->ask_from_list('', _("Which is your timezone?"), [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone});
    $o->{timezone}{GMT} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{GMT}) if $::expert || $clicked;
    install_steps::timeConfig($o,$f);
}

#------------------------------------------------------------------------------
#-sub servicesConfig {}
#------------------------------------------------------------------------------
sub printerConfig($) {
    my ($o) = @_;
    $o->{printer}{want} =
      $o->ask_yesorno(_("Printer"),
		      _("Would you like to configure a printer?"),
		      $o->{printer}{want});
    return if !$o->{printer}{want};

    unless (($::testing)) {
	printer::set_prefix($o->{prefix});
	install_any::pkg_install($o, 'rhs-printfilters');
    }
    printer::read_printer_db();

    $o->{printer}{complete} = 0;
    if ($::expert) {
	$o->ask_from_entries_ref(_("Local Printer Options"),
				 _("Every print queue (which print jobs are directed to) needs a
name (often lp) and a spool directory associated with it. What
name and directory should be used for this queue?"),
				 [_("Name of queue:"), _("Spool directory:")],
				 [\$o->{printer}{QUEUE}, \$o->{printer}{SPOOLDIR}],
				 changed => sub
				 {
				     $o->{printer}{SPOOLDIR}
				       = "$printer::spooldir/$o->{printer}{QUEUE}" unless $_[0];
				 },
				);
    }

    $o->{printer}{str_type} =
      $o->ask_from_list_(_("Select Printer Connection"),
			 _("How is the printer connected?"),
			 [ keys %printer::printer_type ],
			 ${$o->{printer}}{str_type},
			);
    $o->{printer}{TYPE} = $printer::printer_type{$o->{printer}{str_type}};

    if ($o->{printer}{TYPE} eq "LOCAL") {
	{
	    my $w = $o->wait_message(_("Test ports"), _("Detecting devices..."));
	    eval { modules::load("parport_pc"); modules::load("parport_probe"); modules::load("lp"); };
	}

	my @port = ();
	my @parport = detect_devices::whatPrinter();
	eval { modules::unload("parport_probe") };
	my $str;
	if ($parport[0]) {
	    my $port = $parport[0]{port};
	    $o->{printer}{DEVICE}    = $port;
	    my $descr = common::bestMatchSentence2($parport[0]{val}{DESCRIPTION}, @printer::entry_db_description);
	    $o->{printer}{DBENTRY} = $printer::descr_to_db{$descr};
	    $str = _("A printer, model \"%s\", has been detected on ", $parport[0]{val}{DESCRIPTION}) . $port;
	    @port = map { $_->{port}} @parport;
	} else {
	    @port = detect_devices::whatPrinterPort();
	}
	$o->{printer}{DEVICE}    = $port[0] if $port[0];

	return if !$o->ask_from_entries_ref(_("Local Printer Device"),
					    _("What device is your printer connected to  \n(note that /dev/lp0 is equivalent to LPT1:)?\n") . $str ,
					    [_("Printer Device:")],
					    [{val => \$o->{printer}{DEVICE}, list => \@port }],
					   );
    } elsif ($o->{printer}{TYPE} eq "REMOTE") {
	return if !$o->ask_from_entries_ref(_("Remote lpd Printer Options"),
					    _("To use a remote lpd print queue, you need to supply
the hostname of the printer server and the queue name
on that server which jobs should be placed in."),
					    [_("Remote hostname:"), _("Remote queue")],
					    [\$o->{printer}{REMOTEHOST}, \$o->{printer}{REMOTEQUEUE}],
					   );
    } elsif ($o->{printer}{TYPE} eq "SMB") {
	return if !$o->ask_from_entries_ref(
	    _("SMB (Windows 9x/NT) Printer Options"),
	    _("To print to a SMB printer, you need to provide the
SMB host name (Note! It may be different from its
TCP/IP hostname!) and possibly the IP address of the print server, as
well as the share name for the printer you wish to access and any
applicable user name, password, and workgroup information."),
	    [_("SMB server host:"), _("SMB server IP:"),
	     _("Share name:"), _("User name:"), _("Password:"),
	     _("Workgroup:")],
	    [\$o->{printer}{SMBHOST}, \$o->{printer}{SMBHOSTIP},
	     \$o->{printer}{SMBSHARE}, \$o->{printer}{SMBUSER},
	     {val => \$o->{printer}{SMBPASSWD}, hidden => 1}, \$o->{printer}{SMBWORKGROUP}
	    ],
	     complete => sub {
		 unless (network::is_ip($o->{printer}{SMBHOSTIP})) {
		     $o->ask_warn('', _("IP address should be in format 1.2.3.4"));
		     return (1,1);
		 }
		 return 0;
	     },
					   );
	install_any::pkg_install($o, 'samba');
    } elsif ($o->{printer}{TYPE} eq "NCP") {
	return if !$o->ask_from_entries_ref(_("NetWare Printer Options"),
	    _("To print to a NetWare printer, you need to provide the
NetWare print server name (Note! it may be different from its
TCP/IP hostname!) as well as the print queue name for the printer you
wish to access and any applicable user name and password."),
	    [_("Printer Server:"), _("Print Queue Name:"),
	     _("User name:"), _("Password:")],
	    [\$o->{printer}{NCPHOST}, \$o->{printer}{NCPQUEUE},
	     \$o->{printer}{NCPUSER}, {val => \$o->{printer}{NCPPASSWD}, hidden => 1}],
					   );
	install_any::pkg_install($o, 'ncpfs');
    }

    my $action;
    my @action = qw(ascii ps both done);
    my %action = (
		  ascii  => _("Yes, print ascii test page"),
		  ps     => _("Yes, print postscript test page"),
		  both   => _("Yes, print both test pages"),
		  done   => _("No"),
		 );

    do {
	$o->{printer}{DBENTRY} =
	  $printer::descr_to_db{
				$o->ask_from_list_(_("Configure Printer"),
						   _("What type of printer do you have?"),
						   [@printer::entry_db_description],
						   $printer::db_to_descr{$o->{printer}{DBENTRY}},
						  )
			       };

	my %db_entry = %{$printer::thedb{$o->{printer}{DBENTRY}}};

	my @list_res = @{$db_entry{RESOLUTION} || []};
	my @res = map { "$_->{XDPI}x$_->{YDPI}" } @list_res;
	my @list_col      = @{$db_entry{BITSPERPIXEL} || []};
	my @col           = map { "$_->{DEPTH} $_->{DESCR}" } @list_col;
	my %col_to_depth  = map { ("$_->{DEPTH} $_->{DESCR}", $_->{DEPTH}) } @list_col;
	my %depth_to_col  = reverse %col_to_depth;
	my $is_uniprint = $db_entry{GSDRIVER} eq "uniprint";

	$o->{printer}{RESOLUTION} = "Default" unless @list_res;
	$o->{printer}{CRLF} = $db_entry{DESCR} =~ /HP/;
	$o->{printer}{BITSPERPIXEL} = "Default" unless @list_col;

	$o->{printer}{BITSPERPIXEL} = $depth_to_col{$o->{printer}{BITSPERPIXEL}} || $o->{printer}{BITSPERPIXEL}; #- translate.

	$o->ask_from_entries_refH('', _("Printer options"), [
_("Paper Size") => { val => \$o->{printer}{PAPERSIZE}, type => 'list', , not_edit => !$::expert, list => \@printer::papersize_type },
_("Eject page after job?") => { val => \$o->{printer}{AUTOSENDEOF}, type => 'bool' },
@list_res > 1 ? (
_("Resolution") => { val => \$o->{printer}{RESOLUTION}, type => 'list', , not_edit => !$::expert, list => \@res } ) : (),
_("Fix stair-stepping text?") => { val => \$o->{printer}{CRLF}, type => "bool" },
@list_col > 1 ? (
$is_uniprint ? (
_("Uniprint driver options") => { val => \$o->{printer}{BITSPERPIXEL}, type => 'list', , not_edit => !$::expert, list => \@col } ) : (
_("Color depth options") => { val => \$o->{printer}{BITSPERPIXEL}, type => 'list', , not_edit => !$::expert, list => \@col } ), ) : ()
]);;

	$o->{printer}{BITSPERPIXEL} = $col_to_depth{$o->{printer}{BITSPERPIXEL}} || $o->{printer}{BITSPERPIXEL}; #- translate.

	$o->{printer}{complete} = 1;
	install_steps::printerConfig($o);
	$o->{printer}{complete} = 0;
	
	$action = ${{reverse %action}}{$o->ask_from_list('', _("Do you want to test printing?"),
							 [ map { $action{$_} } @action ], $action{'done'})};

	my $pidlpd;
	my @testpages;
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage.asc"
	  if $action eq "ascii" || $action eq "both";
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage". ($o->{printer}{PAPERSIZE} eq 'a4' && '-a4') .".ps"
	  if $action eq "ps" || $action eq "both";

	if (@testpages) {
	    #- restart lpd with blank spool queue.
	    foreach (("/var/spool/lpd/$o->{printer}{QUEUE}/lock", "/var/spool/lpd/lpd.lock")) {
		$pidlpd = (cat_("$o->{prefix}$_"))[0]; kill 'TERM', $pidlpd if $pidlpd;
		unlink "$o->{prefix}$_";
	    }
	    run_program::rooted($o->{prefix}, "lprm", "-P$o->{printer}{QUEUE}", "-"); sleep 1;
	    run_program::rooted($o->{prefix}, "lpd"); sleep 1;

	    run_program::rooted($o->{prefix}, "lpr", "-P$o->{printer}{QUEUE}", $_) foreach @testpages;

	    $action = $o->ask_yesorno('', _("Is this correct?"), 1) ? 'done' : 'change';
	}
    } while ($action ne 'done');
    $o->{printer}{complete} = 1;
}


#------------------------------------------------------------------------------
sub setRootPassword($) {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $o->ask_from_entries_refH([_("Set root password"), _("Ok"), $o->{security} > 2 ? () : _("No password")],
			 _("Set root password"), [
_("Password") => { val => \$sup->{password},  hidden => 1 },
_("Password (again)") => { val => \$sup->{password2}, hidden => 1 },
  $o->{installClass} eq "server" || $::expert ? (
_("Use shadow file") => { val => \$o->{authentification}{shadow}, type => 'bool', text => _("shadow") },
_("Use MD5 passwords") => { val => \$o->{authentification}{md5}, type => 'bool', text => _("MD5") },
  ) : (), $::beginner ? () : (
_("Use NIS") => { val => \$o->{authentification}{NIS}, type => 'bool', text => _("yellow pages") },
  )
			 ], 
			 complete => sub {
			     $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,1);
			     length $sup->{password} < 2 * $o->{security}
			       and $o->ask_warn('', _("This password is too simple")), return (1,0);
			     return 0
			 }
    ) or return;

    if ($o->{authentification}{NIS}) {
	$o->ask_from_entries_ref('',
				 _("Authentification NIS"),
				 [ _("NIS Domain"), _("NIS Server") ],
				 [ \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}),
				   { val => \$o->{authentification}{NIS_server}, list => ["broadcast"] },
				 ]);
    }
    install_steps::setRootPassword($o);
}

#------------------------------------------------------------------------------
#-addUser
#------------------------------------------------------------------------------
sub addUser($) {
    my ($o, $clicked) = @_;
    my $u = $o->{user} ||= $o->{security} < 1 ? { name => "mandrake", realname => "default" } : {};
    $u->{password2} ||= $u->{password} ||= "";
    $u->{shell} ||= "/bin/bash";
    my @fields = qw(realname name password password2);
    my @shells = install_any::shells($o);

    if ($o->{security} < 2 && !$clicked || $o->ask_from_entries_refH(
        [ _("Add user"), _("Accept user"), _("Done") ],
        _("Enter a user\n%s", $o->{users} ? _("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @{$o->{users}})) : ''),
        [ 
	 _("Real name") => \$u->{realname},
	 _("User name") => \$u->{name},
	   $o->{security} < 2 ? () : (
         _("Password") => {val => \$u->{password}, hidden => 1},
         _("Password (again)") => {val => \$u->{password2}, hidden => 1},
	   ), $::beginner ? () : (
         _("Shell") => {val => \$u->{shell}, list => \@shells, not_edit => !$::expert} 
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
	    return 0;
	},
    )) {
	push @{$o->{users}}, $o->{user};
	$o->{user} = {};
	goto &addUser unless $o->{security} < 1 && !$clicked;
    }
    install_steps::addUser($o);
}




#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time) = @_;
    my @l = detect_devices::floppies();

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

	$o->{mkbootdisk} = $o->ask_from_list_('',
					      _("Choose the floppy drive you want to use to make the bootdisk"),
					      [ @l, __("Skip") ], $o->{mkbootdisk});
	return $o->{mkbootdisk} = '' if $o->{mkbootdisk} eq 'Skip';
    }

    $o->ask_warn('', _("Insert a floppy in drive %s", $o->{mkbootdisk}));
    my $w = $o->wait_message('', _("Creating bootdisk"));
    install_steps::createBootdisk($o);
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Preparing bootloader"));
    $o->SUPER::setupBootloaderBefore($o);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o, $more) = @_;
    my $b = $o->{bootloader};

    $more++ if $b->{bootUnsafe};

    if ($::beginner && $more == 1) {
	my @l = (__("First sector of drive (MBR)"), __("First sector of boot partition"));

	my $boot = $o->{hds}[0]{device};
	my $onmbr = "/dev/$boot" eq $b->{boot};
	$b->{boot} = "/dev/$boot" if $o->ask_from_list_(_("LILO Installation"),
			     _("Where do you want to install the bootloader?"),
			     \@l, $l[!$onmbr]) eq $l[0];
    } elsif ($more || !$::beginner) {
	$::expert and $o->ask_yesorno('', _("Do you want to use LILO?"), 1) || return;
    
	my @l = (
_("Boot device") => { val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } @{$o->{hds}}, @{$o->{fstab}}), detect_devices::floppies ], not_edit => !$::expert },
_("Linear (needed for some SCSI drives)") => { val => \$b->{linear}, type => "bool", text => _("linear") },
_("Compact") => { val => \$b->{compact}, type => "bool", text => _("compact") },
_("Delay before booting default image") => \$b->{timeout},
_("Video mode") => { val => \$b->{vga}, list => [ keys %lilo::vga_modes ], not_edit => $::beginner },
$o->{security} < 2 ? () : (
_("Password") => { val => \$b->{password}, hidden => 1 },
_("Restrict command line options") => { val => \$b->{restricted}, type => "bool", text => _("restrict") },
)
	);
	@l = @l[0..3] if $::beginner;

	$b->{vga} ||= 'Normal';
	$o->ask_from_entries_refH('', _("LILO main options"), \@l,
				 complete => sub {
				     $o->{security} > 4 && length($b->{password}) < 6 and $o->ask_warn('', _("At this level of security, a password (and a good one) in lilo is requested")), return 1;
				     $b->{restricted} && !$b->{password} and $o->ask_warn('', _("Option ``Restrict command line options'' is of no use without a password")), return 1;
				     0;
				 }
				) or return;
	$b->{vga} = $lilo::vga_modes{$b->{vga}} || $b->{vga};
    }

    until ($::beginner && $more <= 1) {
	my $c = $o->ask_from_list_([''], 
_("Here are the following entries in LILO.
You can add some more or change the existent ones."),
		[ (sort @{[map_each { "$::b->{label} ($::a)" . ($b->{default} eq $::b->{label} && "  *") } %{$b->{entries}}]}), __("Add"), __("Done") ],
	);
	$c eq "Done" and last;

	my ($e, $name);

	if ($c eq "Add") {
	    my @labels = map { $_->{label} } values %{$b->{entries}};
	    my $prefix;
	    if ($o->ask_from_list_('', _("Which type of entry do you want to add"), [ __("Linux"), __("Other OS (windows...)") ]) eq "Linux") {
		$e = { type => 'image' };
		$prefix = "linux";
	    } else {
		$e = { type => 'other' };
		$prefix = "windows";
	    }
	    $e->{label} = $prefix;
	    for (my $nb = 0; member($e->{label}, @labels); $nb++) { $e->{label} = "$prefix-$nb" }
	} else {
	    ($name) = $c =~ /\((.*?)\)/;
	    $e = $b->{entries}{$name};
	}
	my $old_name = $name;
	my %old_e = %$e;
	my $default = my $old_default = $e->{label} eq $b->{default};
	    
	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
_("Image") => { val => \$name, list => [ eval { glob_("/boot/vmlinuz*") } ] },
_("Root") => { val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @{$o->{fstab}} ], not_edit => !$::expert },
_("Append") => \$e->{append},
_("Initrd") => { val => \$e->{initrd}, list => [ eval { glob_("/boot/initrd*") } ] },
_("Read-write") => { val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..5] unless $::expert;
	} else {
	    @l = ( 
_("Root") => { val => \$name, list => [ map { "/dev/$_->{device}" } @{$o->{fstab}} ], not_edit => !$::expert },
_("Table") => { val => \$e->{table}, list => [ '', map { "/dev/$_->{device}" } @{$o->{hds}} ], not_edit => !$::expert },
_("Unsafe") => { val => \$e->{unsafe}, type => 'bool' }
	    );
	    @l = @l[0..1] unless $::expert;
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
		member($e->{label}, map { $_->{label} } grep { $_ != $e } values %{$b->{entries}}) and $o->ask_warn('', _("This label is already in use")), return 1;
			    $name ne $old_name && $b->{entries}{$name} and $o->ask_warn('', _("A entry %s already exists", $name)), return 1;
			   }
		)) {
	    $b->{default} = $old_default ^ $default ? $default && $e->{label} : $b->{default};
	    
	    delete $b->{entries}{$old_name};
	    $b->{entries}{$name} = $e;
	} else {
	    delete $b->{entries}{$old_name};	    
	}
    }
    eval { $o->SUPER::setupBootloader };
    if ($@) {
	$o->ask_warn('', 
		     [ _("Installation of LILO failed. The following error occured:"),
		       grep { !/^Warning:/ } cat_("$o->{prefix}/tmp/.error") ]);
	die "already displayed";
    }
}

#------------------------------------------------------------------------------
sub miscellaneousNetwork {
    my ($o, $clicked) = @_;
    my $u = $o->{miscellaneous} ||= {};

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
	#- abusive 0 => _("Windows(TM)"),
	#- unused 1 => _("Poor"),
	2 => _("Low"),
	3 => _("Medium"),
	4 => _("High"),
	#- unused 5 => _("Paranoid"),
    );
    my $u = $o->{miscellaneous} ||= {};
    exists $u->{LAPTOP} or $u->{LAPTOP} = 1;
    my $s = $o->{security};
    $s = $l{$s} || $s;

    !$::beginner || $clicked and $o->ask_from_entries_ref('',
	_("Miscellaneous questions"),
	[ _("Do you have a laptop?"), 
	  _("Use hard drive optimizations?"), 
	  _("Choose security level"),
#-GOLD	  _("Use kudzu"),
	  _("Precise ram size if needed (found %d MB)", availableRam / 1024),
	],
	[ { val => \$u->{LAPTOP}, type => 'bool' },
	  { val => \$u->{HDPARM}, type => 'bool', text => _("(may cause disk problems)") },
	  { val => \$s, list => [ map { $l{$_} } ikeys %l ] },
#-GOLD	  { val => \$u->{kudzu}, type => 'bool' },
	  \$u->{memsize},
	],
        complete => sub {
	    !$u->{memsize} || $u->{memsize} =~ s/^(\d+)M?$/$1M/i or $o->ask_warn('', _("Give the ram size in Mb")), return 1;
	    0;
	}
    ) || return;
    my %m = reverse %l; $o->{security} = $m{$s};
    install_steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' unless $alldone || $o->ask_yesorno('', 
_("Some steps are not completed.

Do you really want to quit now?"), 0);

    $o->SUPER::exitInstall;

    $o->ask_warn('',
_("Congratulations, installation is complete.
Remove the boot media and press return to reboot.

For information on fixes which are available for this release of Linux-Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.

Information on configuring your system is available in the post
install chapter of the Official Linux-Mandrake User's Guide.")) if $alldone && !$::g_auto_install;
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
			      _("What %s card do you have?", $type),
			      [ modules::text_of_type($type) ]) or return;
    my $m = modules::text2driver($l);

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
	     $o->ask_yesorno('', _("Skip %s PCMCIA probing", $type), 1);
    $w = $o->wait_message(_("PCMCIA"), _("Configuring PCMCIA cards...")) if modules::pcmcia_need_config($pcmcia);
    modules::load_thiskind($type, sub { $w = wait_load_module($o, $type, @_) }, $pcmcia);
}

#------------------------------------------------------------------------------
sub setup_thiskind {
    my ($o, $type, $auto, $at_least_one) = @_;
    my @l = $o->load_thiskind($type) unless $::expert && !$o->ask_yesorno('', _("Try to find PCI devices?"), 1);
    return if $auto && (@l || !$at_least_one);
    while (1) {
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", map { $_->[0] } @l), $type),
	    _("Do you have another one?") ] :
	  _("Do you have an %s interface?", $type);

	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = "Yes";
	$r = $o->ask_from_list_('', $msg, $opt, "No") unless $at_least_one && @l == 0;
	if ($r eq "No") { return }
	elsif ($r eq "Yes") {
	    my @r = $o->load_module($type) or return;
	    push @l, \@r;
	} else {
	    eval { commands::modprobe("isapnp") };
	    $o->ask_warn('', [ pci_probing::main::list(), scalar cat_("/proc/isapnp") ]);
	}
    }
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
