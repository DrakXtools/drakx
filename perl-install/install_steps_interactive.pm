package install_steps_interactive;


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

use common qw(:common);
use partition_table qw(:types);
use install_steps;
use install_any;
use detect_devices;
use network;
use modules;
use lang;
use keyboard;
use fs;
use log;

1;

sub errorInStep($$) {
    my ($o, $err) = @_;
    $o->ask_warn(_("Error"), [ _("An error occurred"), $err ]);
}


sub chooseLanguage($) {
    my ($o) = @_;
    lang::text2lang($o->ask_from_list("Language",
		__("Which language do you want?"), # the translation may be used for the help
                [ lang::list() ], 
		lang::lang2text($o->default("lang"))));
}

sub chooseKeyboard($) {
    my ($o) = @_;
    keyboard::text2keyboard($o->ask_from_list_("Keyboard",
               _("Which keyboard do you have?"),
               [ keyboard::list() ],
               keyboard::keyboard2text($o->default("keyboard"))));
}

sub selectInstallOrUpgrade($) {
    my ($o) = @_;
    $o->ask_from_list_(_("Install/Upgrade"), 
		       _("Is this an install or an upgrade?"),
		       [ __("Install"), __("Upgrade") ], 
		       $o->default("isUpgrade") ? "Upgrade" : "Install") eq "Upgrade";
}

sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    $o->ask_from_list_(_("Install Class"),
		       _("What type of user will you have?"),
		       [ @classes ], $o->default("installClass"));
}

sub setupSCSI { setup_thiskind($_[0], 'scsi', $_[1]) }

sub rebootNeeded($) {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));
    $o->SUPER::rebootNeeded;
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab);

    my @l = grep { $_->{mntpoint} && isExt2($_) || isSwap($_) } @$fstab;
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
	$o->setup_thiskind('net', 1, 1);
	my @l = detect_devices::getNet() or die _("no network card found");

	my $last; foreach ($::expert ? @l : $l[0]) {
	    my $intf = network::findIntf($o->{intf} ||= [], $_);
	    add2hash($intf, $last);
	    add2hash($intf, { NETMASK => '255.255.255.0' });
	    $o->configureNetworkIntf($intf);
	    $last = $intf;
	}
#	 { 
#	     my $wait = $o->wait_message(_("Hostname"), _("Determining host name and domain..."));
#	     network::guessHostname($o->{prefix}, $o->{netc}, $o->{intf});
#	 }
	$o->configureNetworkNet($o->{netc} ||= {}, @l);
    }
    $o->SUPER::configureNetwork;
}
	
sub timeConfig {
    my ($o, $f) = @_;
    add2hash($o->{timezone} ||= {}, $o->default("timezone"));

    $o->{timezone}{GMT} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{GMT});
    $o->{timezone}{timezone} = $o->ask_from_list('', _("In which timezone are you"), [ install_any::getTimeZones() ], $o->{timezone}{timezone});
    $o->SUPER::timeConfig($f);
}

sub printerConfig($) {
    my($o) = @_;
    $o->{printer}{want} = 
      $o->ask_yesorno(_("Printer"),
		      _("Would you like to configure a printer?"),
		      $o->{printer}{want});
    return if !$o->{printer}{want};

    $o->{printer}{complete} = 0;
    #std info
    #Don't wait, if the user enter something, you must remember it
    #($o->{default}{printer}{QUEUE}, $o->{default}{printer}{SPOOLDIR}) =
    $o->{printer}{QUEUE}    ||= $o->{default}{printer}{QUEUE};
    $o->{printer}{SPOOLDIR} ||= $o->{default}{printer}{SPOOLDIR};
    $o->ask_from_entries_ref(_("Standard Printer Options"),
			 _("Every print queue (which print jobs are directed to) needs a 
			   name (often lp) and a spool directory associated with it. What 
			   name and directory should be used for this queue?"),
			 [_("Name of queue:"), _("Spool directory:")],
			 [\$o->{printer}{QUEUE}, \$o->{printer}{SPOOLDIR}],
			);

    $o->{printer}{str_type} = 
      $o->ask_from_list_(_("Select Printer Connection"),
			 _("How is the printer connected?"),
			 [keys %printer::printer_type],
			 ${$o->default("printer")}{str_type},
			);
    $o->{printer}{TYPE} = $printer::printer_type{$o->{printer}{str_type}};

    if ($o->{printer}{TYPE} eq "LOCAL") {
	eval { modules::load("lp"); };
	my @port = ();
	foreach ("lp0", "lp1", "lp2") {
	    local *LP;
	    push @port, "/dev/$_" if open LP, ">/dev/$_"
	    }
	eval { modules::unload("lp") };
	
	my $string = _("What device is your printer connected to 
			    (note that /dev/lp0 is equivalent to LPT1:)?\n");
	$string .= _("I detect :");
	$string .= join(", ", @port);

	$o->{printer}{DEVICE}    ||= $o->{default}{printer}{DEVICE};
	

	$o->ask_from_entries_ref(_("Local Printer Device"),
				 $string,
				 [_("Printer Device:")],
				 [\$o->{printer}{DEVICE}],
				);

    } elsif ($o->{printer}{TYPE} eq "REMOTE") {
	
    } elsif ($o->{printer}{TYPE} eq "SMB") {
    } elsif ($o->{printer}{TYPE} eq "NCP") {
    }
    
 
#    printer::set_prefix($o->{prefix});
    printer::read_printer_db();
    my @entries_db_short     = sort keys %printer::thedb;
    my @entry_db_description = map { $printer::thedb{$_}{DESCR} } @entries_db_short;
    my %descr_to_db          = map { $printer::thedb{$_}{DESCR}, $_ } @entries_db_short;
    my %db_to_descr          = reverse %descr_to_db;
    
    $o->{printer}{DBENTRY} ||= $o->{default}{printer}{DBENTRY};
    $o->{printer}{DBENTRY} = 
      $descr_to_db{
		   $o->ask_from_list_(_("Configure Printer"),
				      _("What type of printer do you have?"),
				      [@entry_db_description],
				      $db_to_descr{$o->{printer}{DBENTRY}},
				     )
		  };

    my %db_entry = %{$printer::thedb{$o->{printer}{DBENTRY}}};


    #paper size conf
    $o->{printer}{PAPERSIZE} ||= $o->{default}{printer}{PAPERSIZE};
    $o->{printer}{PAPERSIZE} = 
      $o->ask_from_list_(_("Paper Size"),
			 _("Paper Size"),
			 \@printer::papersize_type,
			 $o->{printer}{PAPERSIZE}
			);

    #resolution size conf
    $o->{printer}{RESOLUTION} ||= $o->{default}{printer}{RESOLUTION};
    
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

    
    #Fix ster stepping
    # MAJOR HACK 
    # if the printer is an HP, let's do stairstep correction 
    $o->{printer}{CRLF} = $db_entry{DESCR} =~ /HP/;

    $o->{printer}{CRLF} ||= $o->{default}{printer}{CRLF};
    $o->{printer}{CRLF}= $o->ask_yesorno(_("CRLF"),
					 _("Fix stair-stepping of text?"),
					 $o->{printer}{CRLF});

    #color_depth
    $o->{printer}{BITSPERPIXEL} ||= $o->{default}{printer}{BITSPERPIXEL};
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
	$o->{default}{printer}{BITSPERPIXEL} = "Default";
    }
    
    

    #    $o->{printer}{complete} = 1;
    $o->SUPER::printerConfig;
    
}


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
failures. Would you like to create a bootdisk for your system?"), !$o->default("mkbootdisk")) or return;

	$o->{mkbootdisk} = $o->default("mkbootdisk") || 1;
    } else {
	@l or die _("Sorry, no floppy drive available");

	$o->{mkbootdisk} = $o->ask_from_list('', 
_("Choose the floppy drive you want to use to make the bootdisk"), 
					     \@l, $o->default("mkbootdisk"));
    }

    $o->ask_warn('', _("Insert a floppy in drive %s", $o->{mkbootdisk}));
    my $w = $o->wait_message('', _("Creating bootdisk"));
    $o->SUPER::createBootdisk;
}

sub setupBootloader($) {
    my ($o) = @_;
    my @l = (__("First sector of drive"), __("First sector of boot partition"));

    $o->{bootloader}{onmbr} = 
      $o->ask_from_list_(_("Lilo Installation"), 
			 _("Where do you want to install the bootloader?"), 
			 \@l, 
			 $l[!$o->default("bootloader")->{onmbr}]
			) eq $l[0];
    $o->SUPER::setupBootloader;
}

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

sub loadModule {
    my ($o, $type) = @_;
    my @options;
    
    my $l = $o->ask_from_list('', 
			      _("What %s card have you?", $type), 
			      [ modules::text_of_type($type) ]) or return;
    my $m = modules::text2driver($l);
    if ($o->ask_from_list('', 
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $l),
			  [ __("Autoprobe"), __("Specify options") ], "Autoprobe") ne "Autoprobe") {
	@options = split ' ',
	                 $o->ask_from_entry('',
_("Here must give the different options for the module %s.
Options are in format ``name=value name2=value2 ...''.
For example you can have ``io=0x300 irq=7''", $l),
					    _("Module options:"),
					   );
    }
    modules::load($m, $type, @options);
    $l, $m;
}

sub load_thiskind {
    my ($o, $type) = @_;
    my $w;
    modules::load_thiskind($type, sub { 
        $w = $o->wait_message('', 
			      [ _("Installing driver for %s card %s", $type, $_->[0]),
				$o->{installClass} ne "beginner" ? _("(module %s)", $_->[1]) : () 
			      ]);
    });
}

sub setup_thiskind {
    my ($o, $type, $auto, $at_least_one) = @_;
    my @l = $o->load_thiskind($type);

    return if $auto && (@l || !$at_least_one);
    while (1) {
	@l ?
	  $o->ask_yesorno('', 
			  [ _("Found %s %s interfaces", join(", ", map { $_->[0] } @l), $type),
			    _("Do you have another one?") ], "No") :
	  $o->ask_yesorno('', _("Do you have an %s interface?", $type), "No") or return;

	push @l, [ $o->loadModule($type) ];
    }
}
