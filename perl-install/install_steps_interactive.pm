package install_steps_interactive; # $Id$


use diagnostics;
use strict;
use vars qw(@ISA $new_bootstrap);

@ISA = qw(install_steps);


#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table qw(:types);
use partition_table::raw;
use install_steps;
use install_interactive;
use install_any;
use install_messages;
use detect_devices;
use run_program;
use devices;
use fsedit;
use loopback;
use mouse;
use modules;
use modules::interactive;
use lang;
use keyboard;
use any;
use fs;
use log;

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub errorInStep($$) {
    my ($o, $err) = @_;
    $o->ask_warn(N("Error"), [ N("An error occurred"), formatError($err) ]);
}

sub kill_action {
    my ($o) = @_;
    $o->kill;
}

sub charsetChanged {}

#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;

    $o->{locale}{lang} = any::selectLanguage($o, $o->{locale}{lang}, $o->{locale}{langs} ||= {});
    install_steps::selectLanguage($o);

    $o->charsetChanged;

    if ($o->isa('interactive::gtk')) {
	$o->ask_warn('', formatAlaTeX(
"If you see this message it is because you chose a language for
which DrakX does not include a translation yet; however the fact
that it is listed means there is some support for it anyway.

That is, once GNU/Linux will be installed, you will be able to at
least read and write in that language; and possibly more (various
fonts, spell checkers, various programs translated etc. that
varies from language to language).")) if $o->{locale}{lang} !~ /^en/ && !lang::load_mo();
    } else {
	#- no need to have this in po since it is never translated
	$o->ask_warn('', "The characters of your language can't be displayed in console,
so the messages will be displayed in english during installation") if $ENV{LANGUAGE} eq 'C';
    }
}
    
sub acceptLicense {
    my ($o) = @_;

    my $r = 'Refuse';

    $o->ask_from_({ title => N("License agreement"), 
		    messages => formatAlaTeX(install_messages::main_license() . "\n\n\n" . install_messages::warning_about_patents()), 
		    interactive_help_id => 'acceptLicense',
		    callbacks => { ok_disabled => sub { $r eq 'Refuse' } },
		  },
		  [ { list => [ N_("Accept"), N_("Refuse") ], val => \$r, type => 'list', format => sub { translate($_[0]) } } ]);
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o, $clicked) = @_;

    my $from_usb = keyboard::from_usb();
    my $l = keyboard::lang2keyboards(lang::langs($o->{locale}{langs}));

    if ($::expert || $clicked || !($from_usb || @$l && $l->[0][1] >= 90) || listlength(lang::langs($o->{locale}{langs})) > 1) {
	add2hash($o->{keyboard}, $from_usb);
	my @best = uniq($from_usb ? $from_usb->{KEYBOARD} : (), (map { $_->[0] } @$l), 'us_intl');

	my $format = sub { translate(keyboard::KEYBOARD2text($_[0])) };
	my $other;
	my $ext_keyboard = my $KEYBOARD = $o->{keyboard}{KEYBOARD};
	$o->ask_from_(
		      { title => N("Keyboard"), 
			messages => N("Please choose your keyboard layout."),
			interactive_help_id => 'selectKeyboard',
			advanced_messages => N("Here is the full list of keyboards available"),
			advanced_label => N("More"),
			callbacks => { changed => sub { $other = $_[0] == 1 } },
		      },
		      [ if_(@best > 1, { val => \$KEYBOARD, type => 'list', format => $format, sort => 1,
					 list => [ @best ] }),
			{ val => \$ext_keyboard, type => 'list', format => $format,
			  list => [ difference2([ keyboard::KEYBOARDs() ], \@best) ], advanced => @best > 1 }
		      ]);
	$o->{keyboard}{KEYBOARD} = $other ? $ext_keyboard : $KEYBOARD;
	delete $o->{keyboard}{unsafe};
    }
    keyboard::group_toggle_choose($o, $o->{keyboard}) or goto &selectKeyboard;
    install_steps::selectKeyboard($o);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($o) = @_;

    if (my @l = install_any::find_root_parts($o->{fstab}, $o->{prefix})) {
	log::l("proposing to upgrade partitions " . join(" ", map { $_->{part}{device} } @l));

	my @releases = uniq(map { $_->{release} } @l);
	if (@releases != @l) {
	    #- same release name so adding the device to differentiate them:
	    $_->{release} .= " ($_->{part}{device})" foreach @l;
	}

	my $p = $o->ask_from_listf_raw({ title => N("Install/Upgrade"),
					 messages => N("Is this an install or an upgrade?"),
					 interactive_help_id => 'selectInstallClass',
					 },
				   sub {
				       ref($_[0]) ? (@l > 1 ? 
						     N("Upgrade %s", $_[0]{release}) : 
						     N("Upgrade")) : 
						    translate($_[0]);
				   }, [ @l, N_("Install") ]);
	if (ref $p) {
	    my $part = $p->{part};
	    log::l("choosing to upgrade partition $part->{device}");
	    install_any::use_root_part($o->{all_hds}, $part, $o->{prefix});
	    $o->{isUpgrade} = 1;
	}
    }
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    $force ||= $o->{mouse}{unsafe};

    if ($force) {
	my $prev = $o->{mouse}{type} . '|' . $o->{mouse}{name};

	$o->ask_from_({ messages => N("Please choose your type of mouse."),
			interactive_help_id => 'selectMouse',
		      },
		     [ { list => [ mouse::fullnames() ], separator => '|', val => \$prev } ]);
	$o->{mouse} = mouse::fullname2mouse($prev);
    }

    if ($force && $o->{mouse}{type} eq 'serial') {
	$o->{mouse}{device} = 
	  $o->ask_from_listf_raw({ title => N("Mouse Port"),
				   messages => N("Please choose which serial port your mouse is connected to."),
				   interactive_help_id => 'selectSerialPort',
				 },
			    \&mouse::serial_port2text,
			    [ mouse::serial_ports() ]) or return &selectMouse;
    }
    if (arch() =~ /ppc/ && $o->{mouse}{nbuttons} == 1) {
	#- set a sane default F11/F12
	$o->{mouse}{button2_key} = 87;
	$o->{mouse}{button3_key} = 88;
	$o->ask_from('', N("Buttons emulation"),
		[
		{ label => N("Button 2 Emulation"), val => \$o->{mouse}{button2_key}, list => [ mouse::ppc_one_button_keys() ], format => \&mouse::ppc_one_button_key2text },
		{ label => N("Button 3 Emulation"), val => \$o->{mouse}{button3_key}, list => [ mouse::ppc_one_button_keys() ], format => \&mouse::ppc_one_button_key2text },
		]) or return;
    }
    
    if ($o->{mouse}{device} eq "usbmouse") {
	modules::interactive::load_category($o, 'bus/usb', 1, 1);
	eval { 
	    devices::make("usbmouse");
	    modules::load(qw(hid mousedev usbmouse));
	};
    }

    $o->SUPER::selectMouse;
    1;
}
#------------------------------------------------------------------------------
sub setupSCSI {
    my ($o) = @_;

    if (!$::noauto && arch() =~ /i.86/) {
	if ($o->{pcmcia} ||= !$::testing && c::pcmcia_probe()) {
	    my $w = $o->wait_message(N("PCMCIA"), N("Configuring PCMCIA cards..."));
	    my $results = modules::configure_pcmcia($o->{pcmcia});
	    $w = undef;
	    $results and $o->ask_warn('', $results);
	}
    }
    { 
	my $_w = $o->wait_message(N("IDE"), N("Configuring IDE"));
	modules::load(modules::category2modules('disk/cdrom'));
    }
    modules::interactive::load_category($o, 'bus/firewire', 1);

    my $have_non_scsi = detect_devices::hds(); #- at_least_one scsi device if we have no disks
    modules::interactive::load_category($o, 'disk/scsi|hardware_raid', 1, !$have_non_scsi);
    modules::interactive::load_category($o, 'disk/scsi|hardware_raid') if !detect_devices::hds(); #- we really want a disk!

    install_interactive::tellAboutProprietaryModules($o);

    install_any::getHds($o, $o);
}

sub ask_mntpoint_s { #- }{}
    my ($o, $fstab) = @_;

    my @fstab = grep { isTrueFS($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
    die N("No partition available") if @fstab == 0;

    {
	my $_w = $o->wait_message('', N("Scanning partitions to find mount points"));
	install_any::suggest_mount_points($fstab, $o->{prefix}, 'uniq');
	log::l("default mntpoint $_->{mntpoint} $_->{device}") foreach @fstab;
    }
    if (@fstab == 1) {
	$fstab[0]{mntpoint} = '/';
    } else {
	$o->ask_from_({ messages => N("Choose the mount points"),
			interactive_help_id => 'ask_mntpoint_s',
		      },
		      [ map { { label => partition_table::description($_), 
				  val => \$_->{mntpoint},
				    not_edit => 0,
				      list => [ '', fsedit::suggestions_mntpoint(fsedit::empty_all_hds()) ] }
			  } grep { !$_->{real_mntpoint} || common::usingRamdisk() } @fstab ]) or return;
    }
    $o->SUPER::ask_mntpoint_s($fstab);
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    if (arch() =~ /ppc/ && detect_devices::get_mac_generation() =~ /NewWorld/) { #- need to make bootstrap part if NewWorld machine - thx Pixel ;^)
	if (defined $partition_table::mac::bootstrap_part) {
	    #- don't do anything if we've got the bootstrap setup
	    #- otherwise, go ahead and create one somewhere in the drive free space
	} else {
            undef = $partition_table::mac::freepart; #- please "perl -w"
            my $freepart = $partition_table::mac::freepart;
	    if ($freepart && $freepart->{size} >= 1) {	        
		log::l("creating bootstrap partition on drive /dev/$freepart->{hd}{device}, block $freepart->{start}");
		$partition_table::mac::bootstrap_part = $freepart->{part};	
		log::l("bootstrap now at $partition_table::mac::bootstrap_part");
		fsedit::add($freepart->{hd}, { start => $freepart->{start}, size => 1 << 11, type => 0x401, mntpoint => '' }, $o->{all_hds}, { force => 1, primaryOrExtended => 'Primary' });
		$new_bootstrap = 1;    
	    } else {
		$o->ask_warn('', N("No free space for 1MB bootstrap! Install will continue, but to boot your system, you'll need to create the bootstrap partition in DiskDrake"));
	    }
	}
    }

    if (!$o->{isUpgrade}) {
        install_interactive::partitionWizard($o);
    }
}

#------------------------------------------------------------------------------
sub rebootNeeded {
    my ($o) = @_;
    $o->ask_warn('', N("You need to reboot for the partition table modifications to take place"));

    install_steps::rebootNeeded($o);
}

#------------------------------------------------------------------------------
sub choosePartitionsToFormat {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab);

    my @l = grep { !$_->{isMounted} && $_->{mntpoint} && 
		   (!isSwap($_) || $::expert) &&
		   (!isFat_or_NTFS($_) || $_->{notFormatted} || $::expert) &&
		   (!isOtherAvailableFS($_) || $::expert || $_->{toFormat})
	       } @$fstab;
    $_->{toFormat} = 1 foreach grep { isSwap($_) && !$::expert } @$fstab;

    return if @l == 0 || !$::expert && every { $_->{toFormat} } @l;

    #- keep it temporary until the guy has accepted
    $_->{toFormatTmp} = $_->{toFormat} || $_->{toFormatUnsure} foreach @l;

    $o->ask_from_(
        { messages => N("Choose the partitions you want to format"),
	  interactive_help_id => 'formatPartitions',
          advanced_messages => N("Check bad blocks?"),
        },
        [ map { 
	    my $e = $_;
	    ({
	      text => partition_table::description($e), type => 'bool',
	      val => \$e->{toFormatTmp}
	     }, if_(!isLoopback($_) && !isThisFs("reiserfs", $_) && !isThisFs("xfs", $_) && !isThisFs("jfs", $_), {
	      text => partition_table::description($e), type => 'bool', advanced => 1, 
	      disabled => sub { !$e->{toFormatTmp} },
	      val => \$e->{toFormatCheck}
        })) } @l ]
    ) or die 'already displayed';
    #- ok now we can really set toFormat
    foreach (@l) {
	$_->{toFormat} = delete $_->{toFormatTmp};
	$_->{isFormatted} = 0;
    }
}


sub formatMountPartitions {
    my ($o, $_fstab) = @_;
    my $w;
    catch_cdie {
        fs::formatMount_all($o->{all_hds}{raids}, $o->{fstab}, $o->{prefix}, sub {
        	my ($msg) = @_;
        	$w ||= $o->wait_message('', $msg);
        	$w->set($msg);
        });
    } sub { 
	$@ =~ /fsck failed on (\S+)/ or return;
	$o->ask_yesorno('', N("Failed to check filesystem %s. Do you want to repair the errors? (beware, you can loose data)", $1), 1);
    };
    undef $w; #- help perl (otherwise wait_message stays forever in newt)
    die N("Not enough swap space to fulfill installation, please add some") if availableMemory() < 40 * 1024;
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o, $rebuild_needed) = @_;

    my $w = $o->wait_message('', $rebuild_needed ? N("Looking for available packages and rebuilding rpm database...") :
			     N("Looking for available packages..."));
    install_any::setPackages($o, $rebuild_needed);

    $w->set(N("Looking at packages already installed..."));
    pkgs::selectPackagesAlreadyInstalled($o->{packages}, $o->{prefix});

    if ($rebuild_needed) {
	$w->set(N("Finding packages to upgrade..."));
	pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix});
    }
}
#------------------------------------------------------------------------------
sub choosePackages {
    my ($o, $packages, $compssUsers, $_first_time) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user if using a cdrom.
    $o->chooseCD($packages) if $o->{method} eq 'cdrom' && !$::oem;

    my $availableC = install_steps::choosePackages(@_);
    my $individual;

    require pkgs;

    my $min_size = pkgs::selectedSize($packages);
    $min_size < $availableC or die N("Your system does not have enough space left for installation or upgrade (%d > %d)", $min_size, $availableC);

    my $min_mark = 4;

    my $b = pkgs::saveSelected($packages);
    my $_level = pkgs::setSelectedFromCompssList($packages, { map { $_ => 1 } map { @{$compssUsers->{$_}{flags}} } @{$o->{compssUsersSorted}} }, $min_mark, 0);
    my $max_size = pkgs::selectedSize($packages) + 1; #- avoid division by zero.
    log::l("max size (level $min_mark) is : " . formatXiB($max_size));
    pkgs::restoreSelected($b);

  chooseGroups:
    $o->chooseGroups($packages, $compssUsers, $min_mark, \$individual, $max_size) if !$o->{isUpgrade} && !$::corporate;

    ($o->{packages_}{ind}) =
      pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $min_mark, $availableC);

    $o->choosePackagesTree($packages) or goto chooseGroups if $individual;

    install_any::warnAboutRemovedPackages($o, $o->{packages});
    install_any::warnAboutNaughtyServers($o) or goto chooseGroups;
}

sub choosePackagesTree {
    my ($o, $packages, $limit_to_medium) = @_;

    $o->ask_many_from_list('', N("Choose the packages you want to install"),
			   {
			    list => [ grep { !$limit_to_medium || pkgs::packageMedium($packages, $_) == $limit_to_medium }
				      @{$packages->{depslist}} ],
			    value => \&URPM::Package::flag_selected,
			    label => \&URPM::Package::name,
			    sort => 1,
			   });
}
sub loadSavePackagesOnFloppy {
    my ($o, $packages) = @_;
    $o->ask_from('', 
N("Please choose load or save package selection on floppy.
The format is the same as auto_install generated floppies."),
		 [ { val => \ (my $choice), list => [ N_("Load from floppy"), N_("Save on floppy") ], format => \&translate, type => 'list' } ]) or return;

    if ($choice eq 'Load from floppy') {
	while (1) {
	    my $w = $o->wait_message(N("Package selection"), N("Loading from floppy"));
	    log::l("load package selection from floppy");
	    my $O = eval { install_any::loadO(undef, 'floppy') };
	    if ($@) {
		$w = undef;	#- close wait message.
		$o->ask_okcancel('', N("Insert a floppy containing package selection"))
		  or return;
	    } else {
		install_any::unselectMostPackages($o);
		foreach (@{$O->{default_packages} || []}) {
		    my $pkg = pkgs::packageByName($packages, $_);
		    pkgs::selectPackage($packages, $pkg) if $pkg;
		}
		return 1;
	    }
	}
    } else {
	log::l("save package selection to floppy");
	install_any::g_default_packages($o, 'quiet');
    }
}
sub chooseGroups {
    my ($o, $packages, $compssUsers, $min_level, $individual, $max_size) = @_;

    #- for all groups available, determine package which belongs to each one.
    #- this will enable getting the size of each groups more quickly due to
    #- limitation of current implementation.
    #- use an empty state for each one (no flag update should be propagated).
    
#- OLD VERSION
    my $b = pkgs::saveSelected($packages);
    install_any::unselectMostPackages($o);
    pkgs::setSelectedFromCompssList($packages, {}, $min_level, $max_size);
    my $system_size = pkgs::selectedSize($packages);
    my ($sizes, $pkgs) = pkgs::computeGroupSize($packages, $min_level);
    pkgs::restoreSelected($b);
    log::l("system_size: $system_size");

    my @groups = @{$o->{compssUsersSorted}};
    my %stable_flags = grep_each { $::b } %{$o->{compssUsersChoice}};
    delete $stable_flags{$_} foreach map { @{$compssUsers->{$_}{flags}} } @groups;

    my $compute_size = sub {
	my %pkgs;
	my %flags = %stable_flags; @flags{@_} = ();
	my $total_size;
	A: while (my ($k, $size) = each %$sizes) {
	    Or: foreach (split "\t", $k) {
		  foreach (split "&&") {
		      exists $flags{$_} or next Or;
		  }
		  $total_size += $size;
		  $pkgs{$_} = 1 foreach @{$pkgs->{$k}};
		  next A;
	      }
	  }
	log::l("computed size $total_size");
	log::l("chooseGroups: ", join(" ", sort keys %pkgs));

	int $total_size;
    };
    my %val = map {
	$_ => every { $o->{compssUsersChoice}{$_} } @{$compssUsers->{$_}{flags}}
    } @groups;

#    @groups = grep { $size{$_} = round_down($size{$_} / sqr(1024), 10) } @groups; #- don't display the empty or small one (eg: because all packages are below $min_level)
    my ($size, $unselect_all);
    my $available_size = install_any::getAvailableSpace($o) / sqr(1024);
    my $size_to_display = sub { 
	my $lsize = $system_size + $compute_size->(map { @{$compssUsers->{$_}{flags}} } grep { $val{$_} } @groups);

	#- if a profile is deselected, deselect everything (easier than deselecting the profile packages)
	$unselect_all ||= $size > $lsize;
	$size = $lsize;
	N("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available_size);
    };

    while (1) {
	if ($available_size < 140) {
	    # too small to choose anything. Defaulting to no group chosen
	    $val{$_} = 0 foreach %val;
	    last;
	}

	$o->reallyChooseGroups($size_to_display, $individual, \%val) or return;
	last if pkgs::correctSize($size / sqr(1024)) < $available_size;
       
	$o->ask_warn('', N("Selected size is larger than available space"));	
    }

    $o->{compssUsersChoice}{$_} = 0 foreach map { @{$compssUsers->{$_}{flags}} } grep { !$val{$_} } keys %val;
    $o->{compssUsersChoice}{$_} = 1 foreach map { @{$compssUsers->{$_}{flags}} } grep {  $val{$_} } keys %val;

    log::l("compssUsersChoice: " . (!$val{$_} && "not ") . "selected [$_] as [$o->{compssUsers}{$_}{label}]") foreach keys %val;

    #- do not try to deselect package (by default no groups are selected).
    $o->{isUpgrade} or $unselect_all and install_any::unselectMostPackages($o);
    #- if no group have been chosen, ask for using base system only, or no X, or normal.
    if (!$o->{isUpgrade} && !any { $_ } values %val) {
	my $docs = !$o->{excludedocs};	
	my $minimal = !any { $_ } values %{$o->{compssUsersChoice}};

	$o->ask_from(N("Type of install"), 
		     N("You haven't selected any group of packages.
Please choose the minimal installation you want:"),
		     [
		      { val => \$o->{compssUsersChoice}{X}, type => 'bool', text => N("With X"), disabled => sub { $minimal } },
		      { val => \$docs, type => 'bool', text => N("With basic documentation (recommended!)"), disabled => sub { $minimal } },
		      { val => \$minimal, type => 'bool', text => N("Truly minimal install (especially no urpmi)") },
		     ],
		     changed => sub { $o->{compssUsersChoice}{X} = $docs = 0 if $minimal },
	) or return &chooseGroups;

	$o->{excludedocs} = !$docs || $minimal;

	#- reselect according to user selection.
	if ($minimal) {
	    $o->{compssUsersChoice}{$_} = 0 foreach keys %{$o->{compssUsersChoice}};
	} else {
	    my $X = $o->{compssUsersChoice}{X}; #- don't let setDefaultPackages modify this one
	    install_any::setDefaultPackages($o, 'clean');
	    $o->{compssUsersChoice}{X} = $X;
	}
	install_any::unselectMostPackages($o);
    }
    1;
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $val) = @_;

    my $size_text = &$size_to_display;

    my ($path, $all);
    $o->ask_from_({ messages => N("Package Group Selection"),
		    interactive_help_id => 'choosePackages',
		  }, [
        { val => \$size_text, type => 'label' }, {},
	 (map { 
	       my $old = $path;
	       $path = $o->{compssUsers}{$_}{path};
	       if_($old ne $path, { val => translate($path) }),
		 {
		  val => \$val->{$_},
		  type => 'bool',
		  disabled => sub { $all },
		  text => translate($o->{compssUsers}{$_}{label}),
		  help => translate($o->{compssUsers}{$_}{descr}),
		 }
	   } @{$o->{compssUsersSorted}}),
	 if_($o->{meta_class} eq 'desktop', { text => N("All"), val => \$all, type => 'bool' }),
	 if_($individual, { text => N("Individual package selection"), val => $individual, advanced => 1, type => 'bool' }),
    ], changed => sub { $size_text = &$size_to_display });

    if ($all) {
	$val->{$_} = 1 foreach keys %$val;
    }
    1;    
}

sub chooseCD {
    my ($o, $packages) = @_;
    my @mediums = grep { $_ != $install_any::boot_medium } pkgs::allMediums($packages);
    my @mediumsDescr;
    my %mediumsDescr;

    if (!common::usingRamdisk()) {
	#- mono-cd in case of no ramdisk
	foreach (@mediums) {
	    pkgs::mediumDescr($packages, $install_any::boot_medium) eq pkgs::mediumDescr($packages, $_) and next;
	    undef $packages->{mediums}{$_}{selected};
	}
	log::l("low memory install, using single CD installation (as it is not ejectable)");
	return;
    }

    #- the boot medium is already selected.
    $mediumsDescr{pkgs::mediumDescr($packages, $install_any::boot_medium)} = 1;

    #- build mediumDescr according to mediums, this avoid asking multiple times
    #- all the medium grouped together on only one CD.
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	$packages->{mediums}{$_}{ignored} and next;
	exists $mediumsDescr{$descr} or push @mediumsDescr, $descr;
	$mediumsDescr{$descr} ||= $packages->{mediums}{$_}{selected};
    }

    #- if no other medium available or a poor beginner, we are choosing for him!
    #- note first CD is always selected and should not be unselected!
    return if @mediumsDescr == () || !$::expert;

#    $o->set_help('chooseCD');
    $o->ask_many_from_list('',
N("If you have all the CDs in the list below, click Ok.
If you have none of those CDs, click Cancel.
If only some CDs are missing, unselect them, then click Ok."),
			   {
			    list => \@mediumsDescr,
			    label => sub { N("Cd-Rom labeled \"%s\"", $_[0]) },
			    val => sub { \$mediumsDescr{$_[0]} },
			   }) or do {
			       $mediumsDescr{$_} = 0 foreach @mediumsDescr; #- force unselection of other CDs.
			   };

    #- restore true selection of medium (which may have been grouped together)
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	$packages->{mediums}{$_}{ignored} and next;
	$packages->{mediums}{$_}{selected} = $mediumsDescr{$descr};
	log::l("select status of medium $_ is $packages->{mediums}{$_}{selected}");
    }
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;
    my ($current, $total) = (0, 0);

    my $w = $o->wait_message(N("Installing"), N("Preparing installation"));

    my $old = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my ($data, $type, $id, $subtype, $_amount, $total_) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    $total = $total_;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    my $p = $data->{depslist}[$id];
	    $w->set(N("Installing package %s\n%d%%", $p->name, $total && 100 * $current / $total));
	    $current += $p->size;
	} else { goto $old }
    };

    #- the modification is not local as the box should be living for other package installation.
    #- BEWARE this is somewhat duplicated (but not exactly from gtk code).
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;

	#- if not using a cdrom medium, always abort.
	$method eq 'cdrom' && !$::oem and do {
	    my $name = pkgs::mediumDescr($o->{packages}, $medium);
	    local $| = 1; print "\a";
	    my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX(install_messages::com_license()), [ N_("Accept"), N_("Refuse") ], "Accept") eq "Accept");
            $r &&= $o->ask_okcancel('', N("Change your Cd-Rom!

Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
            return $r;
	};
    };
    my $install_result;
    catch_cdie { $install_result = $o->install_steps::installPackages($packages) }
      sub {
	  if ($@ =~ /^error ordering package list: (.*)/) {
	      $o->ask_yesorno('', [
N("There was an error ordering packages:"), $1, N("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  } elsif ($@ =~ /^error installing package list: (.*)/) {
	      $o->ask_yesorno('', [
N("There was an error installing packages:"), $1, N("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  }
	  0;
      };
    if ($pkgs::cancel_install) {
	$pkgs::cancel_install = 0;
	die "setstep choosePackages\n";
    }
    $install_result;
}

sub afterInstallPackages($) {
    my ($o) = @_;
    my $_w = $o->wait_message('', N("Post-install configuration"));
    $o->SUPER::afterInstallPackages($o);
}

sub copyKernelFromFloppy {
    my ($o) = @_;
    $o->ask_okcancel('', N("Please insert the Boot floppy used in drive %s", $o->{blank}), 1) or return;
    $o->SUPER::copyKernelFromFloppy();
}

sub updateModulesFromFloppy {
    my ($o) = @_;
    $o->ask_okcancel('', N("Please insert the Update Modules floppy in drive %s", $o->{updatemodules}), 1) or return;
    $o->SUPER::updateModulesFromFloppy();
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o) = @_;
    require network::network;
    network::network::easy_dhcp($o->{netc}, $o->{intf}) and $o->{netcnx}{type} = 'lan';
    $o->SUPER::configureNetwork();
}

#------------------------------------------------------------------------------
sub installUpdates {
    my ($o) = @_;
    my $u = $o->{updates} ||= {};
    
    $o->hasNetwork or return;

    is_empty_hash_ref($u) and $o->ask_yesorno_({ messages => formatAlaTeX(
N("You now have the opportunity to download updated packages. These packages
have been updated after the distribution was released. They may
contain security or bug fixes.

To download these packages, you will need to have a working Internet 
connection.

Do you want to install the updates ?")),
						interactive_help_id => 'installUpdates',
					       }) || return;

    #- bring all interface up for installing crypto packages.
    install_interactive::upNetwork($o);

    require crypto;
    eval {
	my @mirrors = do { my $_w = $o->wait_message('',
						    N("Contacting Mandrake Linux web site to get the list of available mirrors..."));
			   crypto::mirrors() };
	#- if no mirror have been found, use current time zone and propose among available.
	$u->{mirror} ||= crypto::bestMirror($o->{timezone}{timezone});
	$u->{mirror} = $o->ask_from_treelistf('', 
					      N("Choose a mirror from which to get the packages"), 
					      '|',
					      \&crypto::mirror2text,
					      \@mirrors,
					      $u->{mirror});
    };
    return if $@ || !$u->{mirror};

    my $update_medium = do {
	my $_w = $o->wait_message('', N("Contacting the mirror to get the list of available packages..."));
	crypto::getPackages($o->{prefix}, $o->{packages}, $u->{mirror});
    };

    if ($update_medium) {
	if ($o->choosePackagesTree($o->{packages}, $update_medium)) {
	    $o->{isUpgrade} = 1; #- now force upgrade mode, else update will be installed instead of upgraded.
	    $o->pkg_install;
	} else {
	    #- make sure to not try to install the packages (which are automatically selected by getPackage above).
	    #- this is possible by deselecting the medium (which can be re-selected above).
	    delete $update_medium->{selected};
	}
	#- update urpmi even, because there is an hdlist available and everything is good,
	#- this will allow user to update the medium but update his machine later.
	$o->install_urpmi;
    }
 
    #- stop interface using ppp only. FIXME REALLY TOCHECK isdn (costly network) ?
    # FIXME damien install_interactive::downNetwork($o, 'pppOnly');
}


#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o, $clicked) = @_;

    require timezone;
    $o->{timezone}{timezone} = $o->ask_from_treelist('', N("Which is your timezone?"), '/', [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone}) || return;

    my $ntp = to_bool($o->{timezone}{ntp});
    $o->ask_from_({ interactive_help_id => 'configureTimezoneGMT' }, [
	  { text => N("Hardware clock set to GMT"), val => \$o->{timezone}{UTC}, type => 'bool' },
	  { text => N("Automatic time synchronization (using NTP)"), val => \$ntp, type => 'bool' },
    ]) or goto &configureTimezone
	    if $::expert || $clicked;
    if ($ntp) {
	my @servers = split("\n", timezone::ntp_servers());

	$o->ask_from_({},
	    [ { label => N("NTP Server"), val => \$o->{timezone}{ntp}, list => \@servers, not_edit => 0 } ]
        ) or goto &configureTimezone;
	$o->{timezone}{ntp} =~ s/.*\((.+)\)/$1/;
    } else {
	$o->{timezone}{ntp} = '';
    }
    install_steps::configureTimezone($o);
    1;
}

#------------------------------------------------------------------------------
sub configureServices { 
    my ($o, $clicked) = @_;
    require services;
    $o->{services} = services::ask($o) if $::expert || $clicked;
    install_steps::configureServices($o);
}


sub summaryBefore {
    my ($o) = @_;

    #- auto-detection
    $o->configurePrinter(0);
    install_any::preConfigureTimezone($o);
}

sub summary_prompt {
    my ($o, $l, $check_complete) = @_;

    ($_->{format}, $_->{val}) = ($_->{val}, '') foreach @$l;
    
    $o->ask_from_({
		   messages => N("Summary"),
		   interactive_help_id => 'summary',
		   cancel   => '',
		   callbacks => { complete => sub { !$check_complete->() } },
		  }, $l);
}

sub summary {
    my ($o) = @_;

    my @l;

    my $timezone_manually_set;  
    push @l, { 
	      label => N("Country"),
	      val => sub { lang::c2name($o->{locale}{country}) },
	      clicked => sub {
		  any::selectCountry($o, $o->{locale}) or return;
		  lang::write($o->{prefix}, $o->{locale});
		  if (!$timezone_manually_set) {
		      delete $o->{timezone};
		      install_any::preConfigureTimezone($o); #- now we can precise the timezone thanks to the country
		  }
	      },
	     };
    push @l, { 
	      label => N("Timezone"),
	      val => sub { $o->{timezone}{timezone} },
	      clicked => sub { $timezone_manually_set = $o->configureTimezone(1) || $timezone_manually_set },
	     };

    push @l, { 
	      label => N("Keyboard"), 
	      val => sub { $o->{keyboard} && translate(keyboard::keyboard2text($o->{keyboard})) },
	      clicked => sub { $o->selectKeyboard(1) },
	     };
    push @l, { 
	      label => N("Mouse"),
	      val => sub { translate($o->{mouse}{type}) . ' ' . translate($o->{mouse}{name}) },
	      clicked => sub { $o->selectMouse(1); mouse::write($o, $o->{mouse}) },
	     };

    push @l, {
	      label => N("Printer"),
	      val => sub {
		  if (is_empty_hash_ref($o->{printer}{configured})) {
		      require pkgs;
		      my $p = pkgs::packageByName($o->{packages}, 'cups');
		      $p && $p->flag_installed ? N("Remote CUPS server") : N("No printer");
		  } elsif (my $p = find { $_ && ($_->{make} || $_->{model}) }
			     $o->{printer}{currentqueue},
			     map { $_->{queuedata} } ($o->{printer}{configured}{$o->{printer}{DEFAULT}}, values %{$o->{printer}{configured}})) {
		      "$p->{make} $p->{model}";
		  } else {
		      N("Remote CUPS server"); #- fall back in case of something wrong.
		  }
	      },
	      clicked => sub { $o->configurePrinter(1) },
	     };
  
    my @sound_cards = detect_devices::getSoundDevices();

    foreach my $device (@sound_cards) {
	push @l, { 
		  label => N("Sound card"),
		  val => sub { $device->{description} },
		  clicked => sub {
		      require harddrake::sound; 
		      harddrake::sound::config($o, $device)
		    },
		 };
    }

    if (!@sound_cards && ($o->{compssUsersChoice}{GAMES} || $o->{compssUsersChoice}{AUDIO})) {
	#- if no sound card are detected AND the user selected things needing a sound card,
	#- propose a special case for ISA cards
	push @l, {
		  label => N("Sound card"),
		  clicked => sub {
		      if ($o->ask_yesorno('', N("Do you have an ISA sound card?"))) {
			  $o->do_pkgs->install('sndconfig');
			  $o->ask_warn('', N("Run \"sndconfig\" after installation to configure your sound card"));
		      } else {
			  $o->ask_warn('', N("No sound card detected. Try \"harddrake\" after installation"));
		      }
		  },
		 };
    }

    foreach (grep { $_->{driver} =~ /(bttv|saa7134)/ } detect_devices::probeall()) {
	my $driver = $_->{driver};
	push @l, {
		  label => N("TV card"),
		  val => sub { $_->{description} }, 
		  clicked => sub { 
		      require harddrake::v4l; 
		      harddrake::v4l::config($o, $driver);
		  }
		 };
    }

    push @l, { 
	      label => N("Bootloader"),
	      val => sub { "$o->{bootloader}{method} on $o->{bootloader}{boot}" },
	      clicked => sub { any::setupBootloader($o, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{security}) },
	     };

    push @l, {
	      label => N("Graphical interface"),
	      val => sub { $o->{raw_X} ? Xconfig::various::to_string($o->{raw_X}) : N("not configured") },
	      clicked => sub { configureX($o, 'expert') }, 
	     };

    push @l, {
	      label => N("Network"),
	      val => sub { $o->{netcnx}{type} || N("not configured") },
	      clicked => sub { 
		  require network::netconnect;
		  network::netconnect::main($o->{prefix}, $o->{netcnx} ||= {}, $o->{netc}, $o->{mouse}, $o, $o->{intf}, 0, 0, 1);
	      },
	     };

    push @l, {
	      label => N("Firewall"),
	      val => sub { 
		  require network::shorewall;
		  my $shorewall = network::shorewall::read();
		  $shorewall && !$shorewall->{disabled} ? N("activated") : N("disabled");
	      },
	      clicked => sub { 
		  require network::drakfirewall;
		  network::drakfirewall::main($o, $o->{security} <= 3);
	      },
	     } if detect_devices::getNet();

    push @l, {
	      label => N("Services"),
	      val => sub {
		  require services;
		  my ($l, $activated) = services::services();
		  N("Services: %d activated for %d registered", int(@$activated), int(@$l));
	      },
	      clicked => sub { 
		  require services;
		  $o->{services} = services::ask($o) and services::doit($o, $o->{services});
	      },
	     };

    my $check_complete = sub {
	$o->{raw_X} || !pkgs::packageByName($o->{packages}, 'XFree86')->flag_installed ||
	$o->ask_yesorno('', N("You have not configured X. Are you sure you really want this?"));
    };

    $o->summary_prompt(\@l, $check_complete);

    install_steps::configureTimezone($o) if !$timezone_manually_set;  #- do not forget it.
}

#------------------------------------------------------------------------------
sub configurePrinter {
    my ($o, $clicked) = @_;

    require printer::main;
    require printer::printerdrake;
    require printer::detect;

    #- try to determine if a question should be asked to the user or
    #- if he is autorized to configure multiple queues.
    my $ask_multiple_printer = $clicked ? 2 : $o && printer::detect::local_detect();
    $ask_multiple_printer-- or return;

    #- install packages needed for printer::getinfo()
    $::testing or $o->do_pkgs->install('foomatic-db-engine');

    #- take default configuration, this include choosing the right system
    #- currently used by the system.
    my $printer = $o->{printer} ||= {};
    eval { add2hash($printer, printer::main::getinfo($o->{prefix})) };

    $printer->{PAPERSIZE} = $o->{locale}{lang} eq 'en_US' || $o->{locale}{country} eq 'CA' ? 'Letter' : 'A4';
    printer::printerdrake::main($printer, $o, $ask_multiple_printer, sub { install_interactive::upNetwork($o, 'pppAvoided') });

}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    my $auth = ($o->{authentication}{LDAP} && N_("LDAP") ||
		$o->{authentication}{NIS} && N_("NIS") ||
		$o->{authentication}{winbind} && N_("Windows Domain") ||
		N_("Local files"));
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $o->ask_from_(
        {
	 title => N("Set root password"), 
	 messages => N("Set root password"),
	 interactive_help_id => "setRootPassword",
	 cancel => ($o->{security} <= 2 && !$::corporate ? N("No password") : ''),
	 focus_first => 1,
	 callbacks => { 
	     complete => sub {
		 $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]), return (1,0);
		 length $sup->{password} < 2 * $o->{security}
		   and $o->ask_warn('', N("This password is too short (it must be at least %d characters long)", 2 * $o->{security})), return (1,0);
		 return 0
        } } }, [
{ label => N("Password"), val => \$sup->{password},  hidden => 1 },
{ label => N("Password (again)"), val => \$sup->{password2}, hidden => 1 },
  if_($::expert,
{ label => N("Authentication"), val => \$auth, list => [ N_("Local files"), N_("LDAP"), N_("NIS"), N_("Windows Domain") ], format => \&translate },
  ),
			 ]) or return;

    if ($auth eq N_("LDAP")) {
	$o->{authentication}{LDAP} ||= 'ldap.' . $o->{netc}{DOMAINNAME};
	$o->{netc}{LDAPDOMAIN} ||= join(',', map { "dc=$_" } split /\./, $o->{netc}{DOMAINNAME});
	$o->ask_from('',
		     N("Authentication LDAP"),
		     [ { label => N("LDAP Base dn"), val => \$o->{netc}{LDAPDOMAIN} },
		       { label => N("LDAP Server"), val => \$o->{authentication}{LDAP} },
		     ]) or goto &setRootPassword;
    } else { $o->{authentication}{LDAP} = '' }
    if ($auth eq N_("NIS")) { 
	$o->{authentication}{NIS} ||= 'broadcast';
	$o->ask_from('',
		     N("Authentication NIS"),
		     [ { label => N("NIS Domain"), val => \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}) },
		       { label => N("NIS Server"), val => \$o->{authentication}{NIS}, list => ["broadcast"], not_edit => 0 },
		     ]) or goto &setRootPassword;
    } else { $o->{authentication}{NIS} = '' }
    if ($auth eq N_("Windows Domain")) {
	#- maybe we should browse the network like diskdrake --smb and get the 'doze server names in a list 
	#- but networking isn't setup yet necessarily
	$o->ask_warn('', N("For this to work for a W2K PDC, you will probably need to have the admin run: C:\>net localgroup \"Pre-Windows 2000 Compatible Access\" everyone /add and reboot the server.\nYou will also need the username/password of a Domain Admin to join the machine to the Windows(TM) domain.\nIf networking is not yet enabled, Drakx will attempt to join the domain after the network setup step.\nShould this setup fail for some reason and domain authentication is not working, run 'smbpasswd -j DOMAIN -U USER%%PASSWORD' using your Windows(tm) Domain, and Admin Username/Password, after system boot.\nThe command 'wbinfo -t' will test whether your authentication secrets are good."));
	$o->ask_from('',
			N("Authentication Windows Domain"),
			[ { label => N("Windows Domain"), val => \ ($o->{netc}{WINDOMAIN} ||= $o->{netc}{DOMAINNAME}) },
			  { label => N("Domain Admin User Name"), val => \$o->{authentication}{winbind} },
			  { label => N("Domain Admin Password"), val => \$o->{authentication}{winpass}, hidden => 1  },
			]) or goto &setRootPassword;
    } else { $o->{authentication}{winbind} = '' }
    install_steps::setRootPassword($o);
}

#------------------------------------------------------------------------------
#-addUser
#------------------------------------------------------------------------------
sub addUser {
    my ($o, $clicked) = @_;
    $o->{users} ||= [];

    if ($o->{security} < 1) {
	push @{$o->{users}}, { password => 'mandrake', realname => 'default', icon => 'automagic' } 
	  if !member('mandrake', map { $_->{name} } @{$o->{users}});
    }
    if ($o->{security} >= 1 || $clicked) {
	any::ask_users($o->{prefix}, $o, $o->{users}, $o->{security});
    }
    add2hash($o, any::get_autologin());
    any::autologin($o, $o);

    install_steps::addUser($o);
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $_w = $o->wait_message('', N("Preparing bootloader..."));
    $o->SUPER::setupBootloaderBefore($o);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o) = @_;
    if (arch() =~ /ppc/) {
	my $machtype = detect_devices::get_mac_generation();
	if ($machtype !~ /NewWorld/) {
	    $o->ask_warn('', N("You appear to have an OldWorld or Unknown\n machine, the yaboot bootloader will not work for you.\nThe install will continue, but you'll\n need to use BootX or some other means to boot your machine"));
	    log::l("OldWorld or Unknown Machine - no yaboot setup");
	    return;
	}
    }
    if (arch() =~ /^alpha/) {
	$o->ask_yesorno('', N("Do you want to use aboot?"), 1) or return;
	catch_cdie { $o->SUPER::setupBootloader } sub {
	    $o->ask_yesorno('', 
N("Error installing aboot, 
try to force installation even if that destroys the first partition?"));
	};
    } else {
	any::setupBootloader_simple($o, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{security}) or return;

	{
	    my $_w = $o->wait_message('', N("Installing bootloader"));
	    eval { $o->SUPER::setupBootloader };
	}
	if (my $err = $@) {
	    $err =~ s/^\w+ failed// or die;
            $err = formatError($err);
            while ($err =~ s/^Warning:.*//m) {}
	    $o->ask_warn('', [ N("Installation of bootloader failed. The following error occured:"), $err ]);
	    die "already displayed";
	} elsif (arch() =~ /ppc/) {
	    my $of_boot = cat_("$o->{prefix}/tmp/of_boot_dev") || die "Can't open $o->{prefix}/tmp/of_boot_dev";
	    chop($of_boot);
	    $o->ask_warn('', N("You may need to change your Open Firmware boot-device to\n enable the bootloader.  If you don't see the bootloader prompt at\n reboot, hold down Command-Option-O-F at reboot and enter:\n setenv boot-device %s,\\\\:tbxi\n Then type: shut-down\nAt your next boot you should see the bootloader prompt.", $of_boot));
	}
    }
}

sub miscellaneous {
    my ($o, $_clicked) = @_;

    require security::level;
    security::level::level_choose($o, \$o->{security}, \$o->{libsafe}, \$o->{security_user});

    install_steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o, $expert) = @_;

    install_steps::configureXBefore($o);
    symlink "$o->{prefix}/etc/gtk", "/etc/gtk";

    my $options = { 
	allowFB => $o->{allowFB},
	allowNVIDIA_rpms => install_any::allowNVIDIA_rpms($o->{packages}),
    };

    require Xconfig::main;
    if ($o->{raw_X} = Xconfig::main::configure_everything_or_configure_chooser($o, $options, !$expert, $o->{keyboard}, $o->{mouse})) {
	install_steps::configureXAfter($o);
    }
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy {
    my ($o, $replay) = @_;

    my $floppy = detect_devices::floppy();

    $o->ask_okcancel('', N("Insert a blank floppy in drive %s", $floppy), 1) or return;

    my $dev = devices::make($floppy);
    {
	my $_w = $o->wait_message('', N("Creating auto install floppy..."));
	install_any::getAndSaveAutoInstallFloppy($o, $replay, $dev) or return;
    }
    common::sync();         #- if you shall remove the floppy right after the LED switches off
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' if !$alldone && !$o->ask_yesorno('', 
N("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_steps::exitInstall($o);

    $o->exit unless $alldone;

    $o->ask_from_no_check(
	{
	 messages => formatAlaTeX(install_messages::install_completed()),
	 interactive_help_id => 'exitInstall',
	 ok => N("Reboot"),
	},      
	[
	 if_($::expert,
	     { val => \ (my $_t1 = N("Generate auto install floppy")), clicked => sub {
		   my $t = $o->ask_from_list_('', 
N("The auto install can be fully automated if wanted,
in that case it will take over the hard drive!!
(this is meant for installing on another box).

You may prefer to replay the installation.
"), [ N_("Replay"), N_("Automated") ]);
		   $t and $o->generateAutoInstFloppy($t eq 'Replay');
	       }, advanced => 1 },
	     { val => \ (my $_t2 = N("Save packages selection")), clicked => sub { install_any::g_default_packages($o) }, advanced => 1 },
	 ),
	]
	) if $alldone && !$::g_auto_install;
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################

1;
