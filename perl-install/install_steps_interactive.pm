package install_steps_interactive;


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common);
use partition_table qw(:types);
use install_steps;
use pci_probing::main;
use install_any;
use detect_devices;
use timezone;
use network;
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
}
#------------------------------------------------------------------------------
sub selectKeyboard($) {
    my ($o) = @_;
    $o->{keyboard} = 
      keyboard::text2keyboard($o->ask_from_list_("Keyboard",
						 _("Which keyboard do you have?"),
						 [ keyboard::list() ],
						 keyboard::keyboard2text($o->{keyboard})));
    $o->{keyboard_force} = 1;
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
sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    $o->{installClass} =
      $o->ask_from_list_(_("Install Class"),
			 _("What type of user will you have?"),
			 [ @classes ], $o->{installClass});
    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub setupSCSI { setup_thiskind($_[0], 'scsi', $_[1]) }
#------------------------------------------------------------------------------
sub rebootNeeded($) {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));

    install_steps::rebootNeeded($o);
}
sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    install_steps::choosePartitionsToFormat($o, $fstab);

    my @l = grep { $_->{mntpoint} && isExt2($_) || isSwap($_) && !$::beginner } @$fstab;
    my @r = $o->ask_many_from_list_ref('', _("Choose the partitions you want to format"), 
				       [ map { $_->{mntpoint} || type2name($_->{type}) . " ($_->{device})" } @l ],
				       [ map { \$_->{toFormat} } @l ]);
    defined @r or die "cancel";
}

sub formatPartitions {
    my $o = shift;
    my $w = $o->wait_message('', '');
    foreach (@_) {
	if ($_->{toFormat}) {
	    $w->set(_("Formatting partition %s", $_->{device}));
	    fs::format_part($_);
	}
    }
}
#------------------------------------------------------------------------------
#-choosePackage
#------------------------------------------------------------------------------
#-mouse

#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o, $first_time) = @_;
    my $r = '';
    if ($o->{intf}) {
	if ($first_time) {
	    my @l = (
		     __("Keep the current IP configuration"),
		     __("Reconfigure network now"),
		     __("Don't set up networking"),
		    );
	    $r = $o->ask_from_list_(_("Network Configuration"), 
				    _("LAN networking has already been configured. Do you want to:"),
				    [ @l ]);
	    $r ||= "Don't";
	}
    } else {
	$o->ask_yesorno(_("Network Configuration"),
			_("Do you want to configure LAN (not dialup) networking for your installed system?")) or $r = "Don't";
    }
    
    if ($r =~ /^Don't/) {
	$o->{netc}{NETWORKING} = "false";
    } elsif ($r !~ /^Keep/) {
	$o->setup_thiskind('net', !$::expert, 1);
	my @l = detect_devices::getNet() or die _("no network card found");

	my $last; foreach ($::beginner ? $l[0] : @l) {
	    my $intf = network::findIntf($o->{intf} ||= [], $_);
	    add2hash($intf, $last);
	    add2hash($intf, { NETMASK => '255.255.255.0' });
	    $o->configureNetworkIntf($intf);

	    $o->{netc} ||= {};
	    delete $o->{netc}{dnsServer};
	    delete $o->{netc}{GATEWAY};
	    $last = $intf;
	}
	#	 { 
	#	     my $wait = $o->wait_message(_("Hostname"), _("Determining host name and domain..."));
	#	     network::guessHostname($o->{prefix}, $o->{netc}, $o->{intf});
	#	 }
	$o->configureNetworkNet($o->{netc}, $last ||= {}, @l);
    }
    install_steps::configureNetwork($o);
}

sub configureNetworkIntf {
    my ($o, $intf) = @_;
    delete $intf->{NETWORK};
    delete $intf->{BROADCAST};
    my @fields = qw(IPADDR NETMASK);
    $o->ask_from_entries_ref(_("Configuring network device %s", $intf->{DEVICE}),
_("Please enter the IP configuration for this machine.
Each item should be entered as an IP address in dotted-decimal
notation (for example, 1.2.3.4)."),
			     [ _("IP address:"), _("Netmask:")],
			     [ \$intf->{IPADDR}, \$intf->{NETMASK} ],
			     complete => sub {
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
Also give the gateway if you have one"),
			     [_("Host name:"), _("DNS server:"), _("Gateway:"), !$::beginner ? _("Gateway device:") : ()],
			     [(map { \$netc->{$_}} qw(HOSTNAME dnsServer GATEWAY)), 
				      {val => \$netc->{GATEWAYDEV}, list => \@devices}]
			    );
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f) = @_;

    $o->{timezone}{GMT} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{GMT});
    $o->{timezone}{timezone} ||= timezone::bestTimezone(lang::lang2text($o->{lang}));
    $o->{timezone}{timezone} = $o->ask_from_list('', _("In which timezone are you"), [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone});
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
	pkgs::select($o->{packages}, $o->{packages}{'rhs-printfilters'});
	$o->installPackages($o->{packages});

    }
    printer::read_printer_db();
    
    $o->{printer}{complete} = 0;
    if ($::expert) {
	#std info
	#Don't wait, if the user enter something, you must remember it
	$o->ask_from_entries_ref(_("Standard Printer Options"),
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
			 [keys %printer::printer_type],
			 ${$o->{printer}}{str_type},
			);
    $o->{printer}{TYPE} = $printer::printer_type{$o->{printer}{str_type}};
    
    if ($o->{printer}{TYPE} eq "LOCAL") {
	{
	    my $w = $o->wait_message(_("Test ports"), _("Detecting devices..."));
	    eval { modules::load("lp");modules::load("parport_probe"); };
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
	    $str = _("I have detected a %s on ", $parport[0]{val}{DESCRIPTION}) . $port;
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
	#-TAKE A GOODDEFAULT TODO

    } elsif ($o->{printer}{TYPE} eq "REMOTE") {
	return if !$o->ask_from_entries_ref(_("Remote lpd Printer Options"), 
					    _("To use a remote lpd print queue, you need to supply 
the hostname of the printer server and the queue name 
on that server which jobs should be placed in."),
					    [_("Remote hostname:"), _("Remote queue:")],
					    [\$o->{printer}{REMOTEHOST}, \$o->{printer}{REMOTEQUEUE}],
					   );
	
    } elsif ($o->{printer}{TYPE} eq "SMB") {
	return if !$o->ask_from_entries_ref(
	    _("SMB/Windows 95/NT Printer Options"),
	    _("To print to a SMB printer, you need to provide the 
SMB host name (this is not always the same as the machines 
TCP/IP hostname) and possibly the IP address of the print server, as 
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
    } else {#($o->{printer}{TYPE} eq "NCP") {
	return if !$o->ask_from_entries_ref(_("NetWare Printer Options"),
	    _("To print to a NetWare printer, you need to provide the 
NetWare print server name (this is not always the same as the machines 
TCP/IP hostname) as well as the print queue name for the printer you 
wish to access and any applicable user name and password."),
	    [_("Printer Server:"), _("Print Queue Name:"), 
	     _("User name:"), _("Password:")],
	    [\$o->{printer}{NCPHOST}, \$o->{printer}{NCPQUEUE},
	     \$o->{printer}{NCPUSER}, {val => \$o->{printer}{NCPPASSWD}, hidden => 1}],
					   );
    }
    

    
    $o->{printer}{DBENTRY} = 
      $printer::descr_to_db{
		   $o->ask_from_list_(_("Configure Printer"),
				      _("What type of printer do you have?"),
				      [@printer::entry_db_description],
				      $printer::db_to_descr{$o->{printer}{DBENTRY}},
				     )
		  };

    my %db_entry = %{$printer::thedb{$o->{printer}{DBENTRY}}};


    #-paper size conf
    $o->{printer}{PAPERSIZE} = 
      $o->ask_from_list_(_("Paper Size"),
			 _("Paper Size"),
			 \@printer::papersize_type,
			 $o->{printer}{PAPERSIZE}
			);

    #-resolution size conf
    my @list_res = @{$db_entry{RESOLUTION}};
    my @res = map { "${$_}{XDPI}x${$_}{YDPI}" } @list_res;
    if (@list_res) {
	$o->{printer}{RESOLUTION} = $o->ask_from_list_(_("Resolution"),
						       _("Resolution"),
						       \@res,
						       $o->{printer}{RESOLUTION},
						      );
    } else {
	$o->{printer}{RESOLUTION} = "Default";
    }

    $o->{printer}{CRLF} = $db_entry{DESCR} =~ /HP/;
    $o->{printer}{CRLF}= $o->ask_yesorno(_("CRLF"),
					 _("Fix stair-stepping of text?"),
					 $o->{printer}{CRLF});


    #-color_depth
    if ($db_entry{BITSPERPIXEL}) {
	my @list_col      = @{$db_entry{BITSPERPIXEL}};
	my @col           = map { "$_->{DEPTH} $_->{DESCR}" } @list_col;
	my %col_to_depth  = map { ("$_->{DEPTH} $_->{DESCR}", $_->{DEPTH}) } @list_col;
	my %depth_to_col  = reverse %col_to_depth;
	
	if (@list_col) {
	    my $is_uniprint = $db_entry{GSDRIVER} eq "uniprint";
	    if ($is_uniprint) {
		$o->{printer}{BITSPERPIXEL} = 
		  $col_to_depth{$o->ask_from_list_
				(_("Configure Uniprint Driver"),
				 _("You may now configure the uniprint options for this printer."),
				 \@col,
				 $depth_to_col{$o->{printer}{BITSPERPIXEL}},
				)};
	    
	    } else {
		$o->{printer}{BITSPERPIXEL} = 
		  $col_to_depth{$o->ask_from_list_
				(_("Configure Color Depth"),
				 _("You may now configure the color options for this printer."),
				 \@col,
				 $depth_to_col{$o->{printer}{BITSPERPIXEL}},
				)};
	    }
	} else {
	    $o->{printer}{BITSPERPIXEL} = "Default";
	}
    }
    $o->{printer}{complete} = 1;

    install_steps::printerConfig($o);
}


#------------------------------------------------------------------------------
sub setRootPassword($) {
    my ($o) = @_;
    $o->{superuser}{password2} ||= $o->{user}{password} ||= "";
    my $sup = $o->{superuser};

    $o->ask_from_entries_ref(_("Set root password"),
			 _("Set root password"),
			 [_("Password"), _("Password (again)")],
			 [{ val => \$sup->{password},  hidden => 1}, 
			  { val => \$sup->{password2}, hidden => 1}],
			 complete => sub {
			     $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("You must enter the same password"), _("Please try again") ]), return (1,1);
			     (length $sup->{password} < 6) and $o->ask_warn('', _("This password is too simple")), return (1,0);
			     return 0
			 }
			);
    install_steps::setRootPassword($o);
}

#------------------------------------------------------------------------------
#-addUser	
#------------------------------------------------------------------------------
sub addUser($) {
    my ($o) = @_;
    $o->{user}{password2} ||= $o->{user}{password} ||= "";
    my $u = $o->{user};
    my @fields = qw(realname name password password2);
    my @shells = install_any::shells($o);

    $o->ask_from_entries_ref(
        _("Add user"),
        _("Enter a user"),
        [ _("Real name"), _("User name"), _("Password"), _("Password (again)"), _("Shell") ],
        [ \$u->{realname}, \$u->{name}, 
	  {val => \$u->{password}, hidden => 1}, {val => \$u->{password2}, hidden => 1},
	  {val => \$u->{shell}, list => \@shells, not_edit => !$::expert},
        ],
        focus_out => sub {
	    if ($_[0] eq 0) {
		$u->{name} = lc first($u->{realname} =~ /((\w|-)+)/);
	    }
	},
        complete => sub {
	    $u->{password} eq $u->{password2} or $o->ask_warn('', [ _("You must enter the same password"), _("Please try again") ]), return (1,3);
	    #(length $u->{password} < 6) and $o->ask_warn('', _("This password is too simple")), return (1,2);
	    $u->{name} or $o->ask_warn('', _("Please give a user name")), return (1,0);
	    $u->{name} =~ /^[a-z0-9_-]+$/ or $o->ask_warn('', _("The user name must contain only lower cased letters, numbers, `-' and `_'")), return (1,0);
	    return 0;
	},
    ) or return;
    install_steps::addUser($o);
    $o->{user} = {};
    goto &addUser if $::expert;
}




#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time) = @_;
    my @l = detect_devices::floppies();
 
    if ($first_time || @l == 1) {
	$o->ask_yesorno('',
			_("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
lilo on your system, or another operating system removes lilo, or lilo doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?"), !$o->{mkbootdisk}) or return;
	$o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
    } else {
	@l or die _("Sorry, no floppy drive available");

	$o->{mkbootdisk} = $o->ask_from_list('', 
					     _("Choose the floppy drive you want to use to make the bootdisk"), 
					     [ @l, "Cancel" ], $o->{mkbootdisk});
	return if $o->{mkbootdisk} eq "Cancel";
    }

    $o->ask_warn('', _("Insert a floppy in drive %s", $o->{mkbootdisk}));
    my $w = $o->wait_message('', _("Creating bootdisk"));
    install_steps::createBootdisk($o);
}

#------------------------------------------------------------------------------
sub setupBootloader($) {
    my ($o) = @_;
    my @l = (__("First sector of drive"), __("First sector of boot partition"));

    $o->{bootloader}{onmbr} = 
      $o->ask_from_list_(_("Lilo Installation"), 
			 _("Where do you want to install the bootloader?"), 
			 \@l, 
			 $l[!$o->{bootloader}{onmbr}]
			) eq $l[0];

    lilo::proposition($o->{hds}, $o->{fstab});

    my @entries = grep { $_->{liloLabel} } @{$o->{fstab}};

    $o->ask_from_entries_ref('',
    		       _("The boot manager Mandrake uses can boot other 
                         operating systems as well. You need to tell me  
                         what partitions you would like to be able to boot 
                         and what label you want to use for each of them."),
			 [map {"$_->{device}" . type2name($_->{type})} @entries],
			 [map {\$_->{liloLabel}} @entries],
			 );

    install_steps::setupBootloader($o);
}

#------------------------------------------------------------------------------
sub exitInstall { 
    my ($o) = @_;
    $o->ask_warn('',
		 _("Congratulations, installation is complete.
Remove the boot media and press return to reboot.
For information on fixes which are available for this release of Linux Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.
Information on configuring your system is available in the post
install chapter of the Official Linux Mandrake User's Guide."));
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################
sub loadModule {
    my ($o, $type) = @_;
    my @options;
    
    my $l = $o->ask_from_list('', 
			      _("What %s card have you?", $type), 
			      [ modules::text_of_type($type) ]) or return;
    my $m = modules::text2driver($l);

    my @names = modparm::get_options_name($m);

    if ((!defined @names || @names > 0) && $o->ask_from_list('', 
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $l),
			      [ __("Autoprobe"), __("Specify options") ], "Autoprobe") ne "Autoprobe") {
      ASK:
	if (defined @names) {
	    my @l = $o->ask_from_entries('',
_("Here must give the different options for the module %s.", $l),
					 \@names) or return;
	    @options = modparm::get_options_result($m, @l);
	} else {
	    @options = split ' ',
	      $o->ask_from_entry('',
_("Here must give the different options for the module %s.
Options are in format ``name=value name2=value2 ...''.
For example you can have ``io=0x300 irq=7''", $l),
				 _("Module options:"),
				);
	}
    }
    eval { modules::load($m, $type, @options) };
    if ($@) {
	$o->ask_yesorno('', 
_("Loading of module %s failed
Do you want to try again with other parameters?", $l)) or return;
	goto ASK;
    }
    $l, $m;
}

#------------------------------------------------------------------------------
sub load_thiskind {
    my ($o, $type) = @_;
    my $w;
    modules::load_thiskind($type, sub { 
			       $w = $o->wait_message('', 
						     [ _("Installing driver for %s card %s", $type, $_->[0]),
						       $::beginner ? () : _("(module %s)", $_->[1])
						     ]);
			   });
}

#------------------------------------------------------------------------------
sub setup_thiskind {
    my ($o, $type, $auto, $at_least_one) = @_;
    my @l = $o->load_thiskind($type);
    return if $auto && (@l || !$at_least_one);
    while (1) {
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", map { $_->[0] } @l), $type), 
	    _("Do you have another one?") ] :
	  _("Do you have an %s interface?", $type);
	    
	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = $o->ask_from_list_('', $msg, $opt);
	$r eq "No" and return;
	if ($r eq "Yes") {
	    my @r = $o->loadModule($type) or return;
	    push @l, \@r;
	} else {
	     $o->ask_warn('', [ pci_probing::main::list() ]);
	 }
    }
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
