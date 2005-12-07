package install_steps_interactive; # $Id$


use strict;
use vars qw(@ISA $new_bootstrap);

@ISA = qw(install_steps);


#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table;
use fs::type;
use install_steps;
use install_interactive;
use install_any;
use install_messages;
use detect_devices;
use run_program;
use devices;
use fsedit;
use mouse;
use modules;
use modules::interactive;
use lang;
use keyboard;
use any;
use log;

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub errorInStep {
    my ($o, $err) = @_;
    $o->ask_warn(N("Error"), [ N("An error occurred"), formatError($err) ]);
}

sub kill_action {
    my ($o) = @_;
    $o->kill;
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;

    any::selectLanguage_install($o, $o->{locale});
    install_steps::selectLanguage($o);

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
	$o->ask_warn('', "The characters of your language can not be displayed in console,
so the messages will be displayed in english during installation") if $ENV{LANGUAGE} eq 'C';
    }
}
    
sub acceptLicense {
    my ($o) = @_;

    $o->{release_notes} = join("\n\n", map { 
	my $f = install_any::getFile($_);
	$f && cat__($f);
    } 'release-notes.txt', 'release-notes.' . arch() . '.txt');

    return if $o->{useless_thing_accepted};

    my $r = $::testing ? 'Accept' : 'Refuse';

    $o->ask_from_({ title => N("License agreement"), 
                    icon => 'banner-license',
		     cancel => N("Quit"),
		     messages => formatAlaTeX(install_messages::main_license() . "\n\n\n" . install_messages::warning_about_patents()),
		     interactive_help_id => 'acceptLicense',
		     if_(!$::globetrotter, more_buttons => [ [ N("Release Notes"), sub { $o->ask_warn(N("Release Notes"), $o->{release_notes}) }, 1 ] ]),
		     callbacks => { ok_disabled => sub { $r eq 'Refuse' } },
		   },
		   [ { list => [ N_("Accept"), N_("Refuse") ], val => \$r, type => 'list', format => sub { translate($_[0]) } } ])
      or do {
	  if ($::globetrotter) {
           run_program::run('killall', 'Xorg');
	      exec("/sbin/reboot");
	  }
	  install_any::ejectCdrom();
	  $o->exit;
      };
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o, $clicked) = @_;

    my $from_usb = keyboard::from_usb();
    my $l = keyboard::lang2keyboards(lang::langs($o->{locale}{langs}));

    if ($::expert || $clicked || !($from_usb || @$l && $l->[0][1] >= 90) || listlength(lang::langs($o->{locale}{langs})) > 1) {
	add2hash($o->{keyboard}, $from_usb);
	my @best = uniq($from_usb ? $from_usb->{KEYBOARD} : (), map { $_->[0] } @$l);
	@best = () if @best == 1;

	my $format = sub { translate(keyboard::KEYBOARD2text($_[0])) };
	my $other;
	my $ext_keyboard = my $KEYBOARD = $o->{keyboard}{KEYBOARD};
	$o->ask_from_(
		      { title => N("Keyboard"), 
			messages => N("Please choose your keyboard layout."),
			interactive_help_id => 'selectKeyboard',
			advanced_messages => N("Here is the full list of available keyboards"),
			advanced_label => N("More"),
			callbacks => { changed => sub { $other = $_[0] == 1 } },
		      },
		      [ if_(@best, { val => \$KEYBOARD, type => 'list', format => $format, sort => 1,
				     list => [ @best ] }),
			{ val => \$ext_keyboard, type => 'list', format => $format,
			  list => [ difference2([ keyboard::KEYBOARDs() ], \@best) ], advanced => @best > 1 }
		      ]);
	$o->{keyboard}{KEYBOARD} = !@best || $other ? $ext_keyboard : $KEYBOARD;
	delete $o->{keyboard}{unsafe};
    }
    keyboard::group_toggle_choose($o, $o->{keyboard}) or goto &selectKeyboard;
    install_steps::selectKeyboard($o);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($o) = @_;

    if (my @l = install_any::find_root_parts($o->{fstab}, $o->{prefix})) {
	log::l("proposing to upgrade partitions " . join(" ", map { $_->{part} && $_->{part}{device} } @l));

	my @releases = uniq(map { $_->{release} } @l);
	if (@releases != @l) {
	    #- same release name so adding the device to differentiate them:
	    $_->{release} .= " ($_->{part}{device})" foreach @l;
	}

	my $p;
	$o->ask_from_({ title => N("Install/Upgrade"),
			messages => N("Is this an install or an upgrade?"),
			interactive_help_id => 'selectInstallClass',
		      },
		      [ { val => \$p,
			  list => [ @l, N_("Install") ], 
			  type => 'list',
			  format => sub { ref($_[0]) ? N("Upgrade %s", $_[0]{release}) : translate($_[0]) }
			} ]);
	if (ref $p) {
	    if ($p->{part}) {
		log::l("choosing to upgrade partition $p->{part}{device}");
		$o->{migrate_device_names} = install_any::use_root_part($o->{all_hds}, $p->{part}, $o);
	    }

	    #- handle encrypted partitions (esp. /home)
	    foreach (grep { $_->{mntpoint} } @{$o->{fstab}}) {
		my ($options, $_unknown) = fs::mount_options::unpack($_);
		$options->{encrypted} or next;
		$o->ask_from_({ focus_first => 1 },
			      [ { label => N("Encryption key for %s", $_->{mntpoint}),
				  hidden => 1, val => \$_->{encrypt_key} } ]);
	    }

	    $o->{isUpgrade} = (find { $p->{release_file} =~ /$_/ } 'mandriva', 'mandrake', 'conectiva', 'redhat') || 'unknown';
	    $o->{upgrade_by_removing_pkgs_matching} ||= {
		conectiva => 'cl',
		redhat => '.', #- everything!
	    }->{$o->{isUpgrade}};
	    log::l("upgrading $o->{isUpgrade} distribution" . ($o->{upgrade_by_removing_pkgs_matching} ? " (upgrade_by_removing_pkgs_matching $o->{upgrade_by_removing_pkgs_matching})" : ''));
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
			title => N("Mouse choice"),
			interactive_help_id => 'selectMouse',
		      },
		     [ { list => [ mouse::fullnames() ], separator => '|', val => \$prev, format => sub { join('|', map { translate($_) } split('\|', $_[0])) } } ]);
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
	modules::interactive::load_category($o, $o->{modules_conf}, 'bus/usb', 1, 1);
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
	if ($o->{pcmcia} ||= detect_devices::real_pcmcia_probe()) {
	    my $w = $o->wait_message(N("PCMCIA"), N("Configuring PCMCIA cards..."));
	    my $results = install_any::configure_pcmcia($o->{modules_conf}, $o->{pcmcia});
	    undef $w;
	    $results and $o->ask_warn('', $results);
	}
    }
    { 
	my $_w = $o->wait_message(N("IDE"), N("Configuring IDE"));
	modules::load(modules::category2modules('disk/cdrom'));
    }
    modules::interactive::load_category($o, $o->{modules_conf}, 'bus/firewire', 1);

    my $have_non_scsi = detect_devices::hds(); #- at_least_one scsi device if we have no disks
    modules::interactive::load_category($o, $o->{modules_conf}, 'disk/ide|scsi|hardware_raid|sata|firewire', 1, !$have_non_scsi);
    modules::interactive::load_category($o, $o->{modules_conf}, 'disk/ide|scsi|hardware_raid|sata|firewire') if !detect_devices::hds(); #- we really want a disk!

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
			title => N("Partitioning"),
			icon => 'banner-part',
			interactive_help_id => 'ask_mntpoint_s',
			callbacks => {
			    complete => sub {
				require diskdrake::interactive;
				eval { 1, find_index {
				    !diskdrake::interactive::check_mntpoint($o, $_->{mntpoint}, $_, $o->{all_hds});
				} @fstab };
			    },
			},
		      },
		      [ map { 
			  { 
			      label => partition_table::description($_), 
			      val => \$_->{mntpoint},
			      not_edit => 0,
			      list => [ '', fsedit::suggestions_mntpoint(fs::get::empty_all_hds()) ],
			  };
		        } @fstab ]) or return;
    }
    $o->SUPER::ask_mntpoint_s($fstab);
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    if (arch() =~ /ppc/) {
	my $generation = detect_devices::get_mac_generation();
	if ($generation =~ /NewWorld/) {
	    #- mac partition table
	    if (defined $partition_table::mac::bootstrap_part) {
    		#- do not do anything if we've got the bootstrap setup
    		#- otherwise, go ahead and create one somewhere in the drive free space
	    } else {
		my $freepart = $partition_table::mac::freepart;
		if ($freepart && $freepart->{size} >= 1) {
		    log::l("creating bootstrap partition on drive /dev/$freepart->{hd}{device}, block $freepart->{start}");
		    $partition_table::mac::bootstrap_part = $freepart->{part};
		    log::l("bootstrap now at $partition_table::mac::bootstrap_part");
		    my $p = { start => $freepart->{start}, size => 1 << 11, mntpoint => '' };
		    fs::type::set_pt_type($p, 0x401);
		    fsedit::add($freepart->{hd}, $p, $o->{all_hds}, { force => 1, primaryOrExtended => 'Primary' });
		    $new_bootstrap = 1;

    		} else {
		    $o->ask_warn('', N("No free space for 1MB bootstrap! Install will continue, but to boot your system, you'll need to create the bootstrap partition in DiskDrake"));
    		}
	    }
	} elsif ($generation =~ /IBM/) {
	    #- dos partition table
	    $o->ask_warn('', N("You'll need to create a PPC PReP Boot bootstrap! Install will continue, but to boot your system, you'll need to create the bootstrap partition in DiskDrake"));
	}
    }

    if (!$o->{isUpgrade}) {
        install_interactive::partitionWizard($o);
    }
}

#------------------------------------------------------------------------------
sub rebootNeeded {
    my ($o) = @_;
    $o->ask_warn(N("Partitioning"), N("You need to reboot for the partition table modifications to take place"), icon => 'banner-part');

    install_steps::rebootNeeded($o);
}

#------------------------------------------------------------------------------
sub choosePartitionsToFormat {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab);

    my @l = grep { !$_->{isMounted} && $_->{mntpoint} && 
		   (!isSwap($_) || $::expert) &&
		   (!isFat_or_NTFS($_) || $_->{notFormatted} || $::expert) &&
		   (!isOtherAvailableFS($_) || $::expert || $_->{toFormat});
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
	     }, if_(!isLoopback($_) && !member($_->{fs_type}, 'reiserfs', 'xfs', 'jfs'), {
	      text => partition_table::description($e), type => 'bool', advanced => 1, 
	      disabled => sub { !$e->{toFormatTmp} },
	      val => \$e->{toFormatCheck}
        })) } @l ]
    ) or die 'already displayed';
    #- ok now we can really set toFormat
    foreach (@l) {
	$_->{toFormat} = delete $_->{toFormatTmp};
	set_isFormatted($_, 0);
    }
}


sub formatMountPartitions {
    my ($o, $_fstab) = @_;
    my ($w, $wait_message) = $o->wait_message_with_progress_bar;
    catch_cdie {
        fs::format::formatMount_all($o->{all_hds}, $o->{fstab}, $wait_message);
    } sub { 
	$@ =~ /fsck failed on (\S+)/ or return;
	$o->ask_yesorno('', N("Failed to check filesystem %s. Do you want to repair the errors? (beware, you can lose data)", $1), 1);
    };
    undef $w; #- help perl (otherwise wait_message stays forever in newt)
    die N("Not enough swap space to fulfill installation, please add some") if availableMemory() < 40 * 1024;
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;

    my ($w, $wait_message) = $o->wait_message_with_progress_bar;

    $wait_message->($o->{isUpgrade} ? N("Looking for available packages and rebuilding rpm database...") :
			              N("Looking for available packages..."));
    install_any::setPackages($o, $wait_message);

    undef $w; #- help perl
}

sub mirror2text { $crypto::mirrors{$_[0]} ? $crypto::mirrors{$_[0]}[0] . '|' . $_[0] : "-|URL" }
sub askSupplMirror {
    my ($o, $message) = @_;
    my $u = $o->{updates} ||= {};
    require crypto;
    my @mirrors = do {
	#- Direct the user to the community mirror tree for an install from a mini-iso
	$o->{distro_type} ||= 'community';
	#- get the list of mirrors locally, to avoid weird bugs with making an
	#- http request before ftp at this point of the install
	crypto::mirrors($o->{distro_type}, 1);
    };
    push @mirrors, '-';
    $o->ask_from_(
	{
	    messages => N("Choose a mirror from which to get the packages"),
	    cancel => N("Cancel"),
	},
	[ { separator => '|',
	    format => \&mirror2text,
	    list => \@mirrors,
	    val => \$u->{mirror},
	}, ],
    ) or $u->{mirror} = '';
    delete $o->{updates};
    if ($u->{mirror} eq '-') {
	return $o->ask_from_entry('', $message) || '';
    }
    my $url = "ftp://$u->{mirror}$crypto::mirrors{$u->{mirror}}[1]";
    $url =~ s!/(?:media/)?main/?\z!!;
    log::l("mirror chosen [$url]");
    return $url;
}

sub selectSupplMedia {
    my ($o, $suppl_method) = @_;
    install_any::selectSupplMedia($o, $suppl_method);
}
#------------------------------------------------------------------------------
sub choosePackages {
    my ($o) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user if using a cdrom.
    $o->chooseCD($o->{packages}) if install_any::method_allows_medium_change($o->{method});

    my $w = $o->wait_message('', N("Looking for available packages..."));
    my $availableC = &install_steps::choosePackages;
    my $individual;

    require pkgs;

    my $min_size = pkgs::selectedSize($o->{packages});
    undef $w;
    if ($min_size >= $availableC) {
	$o->ask_warn('', N("Your system does not have enough space left for installation or upgrade (%d > %d)",
			   $min_size / sqr(1024), $availableC / sqr(1024)));
	install_steps::rebootNeeded($o);
    }

    my $min_mark = 4;

  chooseGroups:
    $o->chooseGroups($o->{packages}, $o->{compssUsers}, $min_mark, \$individual) if !$o->{isUpgrade} && $o->{meta_class} ne 'desktop';

    ($o->{packages_}{ind}) =
      pkgs::setSelectedFromCompssList($o->{packages}, $o->{rpmsrate_flags_chosen}, $min_mark, $availableC);

    $o->choosePackagesTree($o->{packages}) or goto chooseGroups if $individual;

    install_any::warnAboutRemovedPackages($o, $o->{packages});
    install_any::warnAboutNaughtyServers($o) or goto chooseGroups if !$o->{isUpgrade} && $o->{meta_class} ne 'firewall';
}

sub choosePackagesTree {
    my ($o, $packages, $o_limit_to_medium) = @_;

    $o->ask_many_from_list('', N("Choose the packages you want to install"),
			   {
			    list => [ grep { !$o_limit_to_medium || pkgs::packageMedium($packages, $_) == $o_limit_to_medium }
				      @{$packages->{depslist}} ],
			    value => \&URPM::Package::flag_selected,
			    label => \&URPM::Package::name,
			    sort => 1,
			   });
}
sub loadSavePackagesOnFloppy {
    my ($o, $packages) = @_;
    $o->ask_from('', 
N("Please choose load or save package selection.
The format is the same as auto_install generated files."),
		 [ { val => \ (my $choice), list => [ N_("Load"), N_("Save") ], format => \&translate, type => 'list' } ]) or return;

    if ($choice eq 'Load') {
	while (1) {
	    log::l("load package selection");
	    my ($_h, $fh) = install_any::media_browser($o, '', 'package_list.pl') or return;
	    my $O = eval { install_any::loadO(undef, $fh) };
	    if ($@) {
		$o->ask_okcancel('', N("Bad file")) or return;
	    } else {
		install_any::unselectMostPackages($o);
		pkgs::select_by_package_names($packages, $O->{default_packages} || []);
		return 1;
	    }
	}
    } else {
	log::l("save package selection");
	install_any::g_default_packages($o);
    }
}
sub chooseGroups {
    my ($o, $packages, $compssUsers, $min_level, $individual) = @_;

    #- for all groups available, determine package which belongs to each one.
    #- this will enable getting the size of each groups more quickly due to
    #- limitation of current implementation.
    #- use an empty state for each one (no flag update should be propagated).
    
    my $b = pkgs::saveSelected($packages);
    install_any::unselectMostPackages($o);
    pkgs::setSelectedFromCompssList($packages, { CAT_SYSTEM => 1 }, $min_level, 0);
    my $system_size = pkgs::selectedSize($packages);
    my ($sizes, $pkgs) = pkgs::computeGroupSize($packages, $min_level);
    pkgs::restoreSelected($b);
    log::l("system_size: $system_size");

    my %stable_flags = grep_each { $::b } %{$o->{rpmsrate_flags_chosen}};
    delete $stable_flags{"CAT_$_"} foreach map { @{$_->{flags}} } @{$o->{compssUsers}};

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
	log::l("computed size $total_size (flags " . join(' ', keys %flags) . ")");
	log::l("chooseGroups: ", join(" ", sort keys %pkgs));

	int $total_size;
    };

    my ($size, $unselect_all);
    my $available_size = install_any::getAvailableSpace($o) / sqr(1024);
    my $size_to_display = sub { 
	my $lsize = $system_size + $compute_size->(map { "CAT_$_" } map { @{$_->{flags}} } grep { $_->{selected} } @$compssUsers);

	#- if a profile is deselected, deselect everything (easier than deselecting the profile packages)
	$unselect_all ||= $size > $lsize;
	$size = $lsize;
	N("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available_size);
    };

    while (1) {
	if ($available_size < 200) {
	    # too small to choose anything. Defaulting to no group chosen
	    $_->{selected} = 0 foreach @$compssUsers;
	    last;
	}

	$o->reallyChooseGroups($size_to_display, $individual, $compssUsers) or return;

	last if $::testing || pkgs::correctSize($size / sqr(1024)) < $available_size || every { !$_->{selected} } @$compssUsers;
       
	$o->ask_warn('', N("Selected size is larger than available space"));	
    }
    install_any::set_rpmsrate_category_flags($o, $compssUsers);

    log::l("compssUsersChoice selected: ", join(', ', map { qq("$_->{path}|$_->{label}") } grep { $_->{selected} } @$compssUsers));

    #- do not try to deselect package (by default no groups are selected).
    if (!$o->{isUpgrade}) {
	install_any::unselectMostPackages($o) if $unselect_all;
    }
    #- if no group have been chosen, ask for using base system only, or no X, or normal.
    if (!$o->{isUpgrade} && !any { $_->{selected} } @$compssUsers) {
	my $docs = !$o->{excludedocs};	
	my $minimal;

	$o->ask_from(N("Type of install"), 
		     N("You have not selected any group of packages.
Please choose the minimal installation you want:"),
		     [
		      { val => \$o->{rpmsrate_flags_chosen}{CAT_X}, type => 'bool', text => N("With X"), disabled => sub { $minimal } },
		      { val => \$docs, type => 'bool', text => N("With basic documentation (recommended!)"), disabled => sub { $minimal } },
		      { val => \$minimal, type => 'bool', text => N("Truly minimal install (especially no urpmi)") },
		     ],
		     changed => sub { $o->{rpmsrate_flags_chosen}{CAT_X} = $docs = 0 if $minimal },
	) or return &chooseGroups;

	if ($minimal) {
	    $o->{rpmsrate_flags_chosen}{CAT_X} = $docs = 0; #- redo it in "changed" was not called
	    $o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 0;
	}
	$o->{excludedocs} = !$docs;

	install_any::unselectMostPackages($o);
    }
    1;
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $compssUsers) = @_;

    my $size_text = &$size_to_display;

    my ($path, $all);
    $o->ask_from_({ messages => N("Package Group Selection"),
		    interactive_help_id => 'choosePackages',
		    callbacks => { changed => sub { $size_text = &$size_to_display } },
		  }, [
        { val => \$size_text, type => 'label' }, {},
	 (map { 
	       my $old = $path;
	       $path = $_->{path};
	       if_($old ne $path, { val => translate($path) }),
		 {
		  val => \$_->{selected},
		  type => 'bool',
		  disabled => sub { $all },
		  text => translate($_->{label}),
		  help => translate($_->{descr}),
		 };
	   } @$compssUsers),
	 if_($o->{meta_class} eq 'desktop', { text => N("All"), val => \$all, type => 'bool' }),
	 if_($individual, { text => N("Individual package selection"), val => $individual, advanced => 1, type => 'bool' }),
    ]);

    if ($all) {
	$_->{selected} = 1 foreach @$compssUsers;
    }
    1;    
}

sub chooseCD {
    my ($o, $packages) = @_;
    my @mediums = grep { $_ != $install_any::boot_medium } pkgs::allMediums($packages);
    my @mediumsDescr;
    my %mediumsDescr;

    #- the boot medium is already selected.
    $mediumsDescr{install_medium::by_id($install_any::boot_medium, $packages)->{descr}} = 1;

    #- build mediumsDescr according to mediums, this avoids asking multiple times
    #- all the media grouped together on only one CD.
    foreach (@mediums) {
	my $descr = install_medium::by_id($_, $packages)->{descr};
	$packages->{mediums}{$_}->ignored and next;
	exists $mediumsDescr{$descr} or push @mediumsDescr, $descr;
	$mediumsDescr{$descr} ||= $packages->{mediums}{$_}->selected;
    }

    if (install_any::method_is_from_ISO_images($o->{method})) {
        $mediumsDescr{$_} = install_any::method_is_from_ISO_images($packages->{mediums}{$_}{method})
	    ? to_bool(install_any::find_ISO_image_labelled($_)) : 1
	    foreach @mediumsDescr;
    } elsif ($o->{method} eq "cdrom") {
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
    }

    #- restore true selection of medium (which may have been grouped together)
    foreach (@mediums) {
	$packages->{mediums}{$_}->ignored and next;
	my $descr = install_medium::by_id($_, $packages)->{descr};
	if ($mediumsDescr{$descr}) {
	    $packages->{mediums}{$_}->select;
	} else {
	    $packages->{mediums}{$_}->refuse;
	}
	log::l("select status of medium $_ is $packages->{mediums}{$_}{selected}");
    }
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;
    my ($current, $total) = (0, 0);

    my $w = $o->wait_message(N("Installing"), N("Preparing installation"));

    local *install_steps::installCallback = sub {
	my ($packages, $type, $id, $subtype, $_amount, $total_) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    $total = $total_;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    my $p = $packages->{depslist}[$id];
	    $w->set(N("Installing package %s\n%d%%", $p->name, $total && 100 * $current / $total));
	    $current += $p->size;
	}
    };

    #- the modification is not local as the box should be living for other package installation.
    #- BEWARE this is somewhat duplicated (but not exactly from gtk code).
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;

	#- if not using a cdrom medium or an iso image, always abort.
	return if !install_any::method_allows_medium_change($method);

	my $name = install_medium::by_id($medium, $o->{packages})->{descr};
	local $| = 1; print "\a";
	my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX(install_messages::com_license()), [ N_("Accept"), N_("Refuse") ], "Accept") eq "Accept");
	if ($method =~ /-iso$/) {
	    $r = install_any::changeIso($name);
	} else {
            $r &&= $o->ask_okcancel('', N("Change your Cd-Rom!
Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you do not have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
	}
	return $r;
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
    my $_w = $o->wait_message('toto', N("Post-install configuration"));
    $o->SUPER::afterInstallPackages;
}

sub updatemodules {
    my ($o, $dev, $rel_dir) = @_;

    $o->ask_okcancel('', N("Please ensure the Update Modules media is in drive %s", $dev), 1) or return;
    $o->SUPER::updatemodules($dev, $rel_dir);
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o) = @_;
    if ($o->{meta_class} eq 'firewall') {
	require network::netconnect;
	network::netconnect::real_main($o->{net}, $o, $o->{modules_conf});
    } else {
	#- don't overwrite configuration in a network install
	if (!install_any::is_network_install($o)) {
	    require network::network;
	    network::network::easy_dhcp($o->{net}, $o->{modules_conf});
	}
	$o->SUPER::configureNetwork;
    }
}

#------------------------------------------------------------------------------
sub installUpdates {
    my ($o) = @_;
    my $u = $o->{updates} ||= {};
    
    $o->hasNetwork or return;

    if (is_empty_hash_ref($u)) {
	$o->ask_yesorno_({ title => N("Updates"), icon => 'banner-update', messages => formatAlaTeX(
N("You now have the opportunity to download updated packages. These packages
have been updated after the distribution was released. They may
contain security or bug fixes.

To download these packages, you will need to have a working Internet 
connection.

Do you want to install the updates?")),
			   interactive_help_id => 'installUpdates',
					       }) or return;
    }

    #- bring all interface up for installing crypto packages.
    install_interactive::upNetwork($o);

    #- update medium available and working.
    my $update_medium;
    do {
	require crypto;
	eval {
	    my @mirrors = do {
		my $_w = $o->wait_message('', N("Contacting Mandriva Linux web site to get the list of available mirrors..."));
		crypto::mirrors($o->{distro_type});
	    };
	    #- if no mirror have been found, use current time zone and propose among available.
	    $u->{mirror} ||= crypto::bestMirror($o->{timezone}{timezone}, $o->{distro_type});
	    $o->ask_from_({ messages => N("Choose a mirror from which to get the packages"),
			    cancel => N("Cancel"),
			  }, [ { separator => '|',
				 format => \&crypto::mirror2text,
				 list => \@mirrors,
				 val => \$u->{mirror},
			       },
			     ],
			 ) or $u->{mirror} = '';
	};
	return if $@ || !$u->{mirror};

	eval {
	    if ($u->{mirror}) {
		my $_w = $o->wait_message('', N("Contacting the mirror to get the list of available packages..."));
		$update_medium = crypto::getPackages($o->{packages}, $u->{mirror});
	    }
	};
    } while $@ || !$update_medium && $o->ask_yesorno('', N("Unable to contact mirror %s", $u->{mirror}) . ($@ ? " :\n$@" : "") . "\n\n" . N("Would you like to try again?"));

    if ($update_medium) {
	if ($o->choosePackagesTree($o->{packages}, $update_medium)) {
	    $o->{isUpgrade} = 1; #- now force upgrade mode, else update will be installed instead of upgraded.
	    $o->pkg_install;
	} else {
	    #- make sure to not try to install the packages (which are automatically selected by getPackage above).
	    #- this is possible by deselecting the medium (which can be re-selected above).
	    #- delete $update_medium->{selected};
	    $update_medium->refuse;
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
    $o->{timezone}{timezone} = $o->ask_from_treelist(N("Timezone"), N("Which is your timezone?"), '/', [ timezone::getTimeZones() ], $o->{timezone}{timezone}) || return;

    my $ntp = to_bool($o->{timezone}{ntp});
    $o->ask_from_({ interactive_help_id => 'configureTimezoneGMT' }, [
	  { text => N("Hardware clock set to GMT"), val => \$o->{timezone}{UTC}, type => 'bool' },
	  { text => N("Automatic time synchronization (using NTP)"), val => \$ntp, type => 'bool' },
    ]) or goto &configureTimezone
	    if $::expert || $clicked;
    if ($ntp) {
	my $servers = timezone::ntp_servers();
	$o->{timezone}{ntp} ||= 'pool.ntp.org';

	$o->ask_from_({},
	    [ { label => N("NTP Server"), val => \$o->{timezone}{ntp}, list => [ keys %$servers ], not_edit => 0,
		format => sub { $servers->{$_[0]} ? "$servers->{$_[0]} ($_[0])" : $_[0] } } ]
        ) or goto &configureTimezone;
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
    #- get back network configuration.
    require network::network;
    eval {
	network::network::read_net_conf($o->{net});
    };
    log::l("summaryBefore: network configuration: ", formatError($@)) if $@;
}

sub summary_prompt {
    my ($o, $l, $check_complete) = @_;

    foreach (@$l) {
	my $val = $_->{val};
	($_->{format}, $_->{val}) = (sub { $val->() || N("not configured") }, '');
    }
    
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

    push @l, {
	group => N("System"), 
	label => N("Keyboard"), 
	val => sub { $o->{keyboard} && translate(keyboard::keyboard2text($o->{keyboard})) },
	clicked => sub { $o->selectKeyboard(1) },
    };

    my $timezone_manually_set;  
    push @l, {
	group => N("System"),
	label => N("Country / Region"),
	val => sub { lang::c2name($o->{locale}{country}) },
	clicked => sub {
	    any::selectCountry($o, $o->{locale}) or return;

	    my $pkg_locale = lang::locale_to_main_locale(lang::getlocale_for_country($o->{locale}{lang}, $o->{locale}{country}));
	    my @pkgs = pkgs::packagesProviding($o->{packages}, "locales-$pkg_locale");
	    $o->pkg_install(map { $_->name } @pkgs) if @pkgs;

	    lang::write_and_install($o->{locale}, $o->do_pkgs);
	    if (!$timezone_manually_set) {
		delete $o->{timezone};
		install_any::preConfigureTimezone($o); #- now we can precise the timezone thanks to the country
	    }
	},
    };
    push @l, {
	group => N("System"),
	label => N("Timezone"),
	val => sub { $o->{timezone}{timezone} },
	clicked => sub { $timezone_manually_set = $o->configureTimezone(1) || $timezone_manually_set },
    };

    push @l, {
	group => N("System"),
	label => N("Mouse"),
	val => sub { translate($o->{mouse}{type}) . ' ' . translate($o->{mouse}{name}) },
	clicked => sub { $o->selectMouse(1); mouse::write($o->do_pkgs, $o->{mouse}) },
    };

    push @l, {
	group => N("Hardware"),
	label => N("Printer"),
	val => sub {
	    if (is_empty_hash_ref($o->{printer}{configured})) {
		require pkgs;
		my $p = pkgs::packageByName($o->{packages}, 'cups');
		$p && $p->flag_installed ? N("Remote CUPS server") : N("No printer");
	    } elsif (defined($o->{printer}{configured}{$o->{printer}{DEFAULT}})  &&
		     (my $p = find { $_ && ($_->{make} || $_->{model}) }
		      $o->{printer}{configured}{$o->{printer}{DEFAULT}}{queuedata})) {
		"$p->{make} $p->{model}";
	    } elsif ($p = find { $_ && ($_->{make} || $_->{model}) }
		      map { $_->{queuedata} } (values %{$o->{printer}{configured}})) {
		"$p->{make} $p->{model}";
	    } else {
		N("Remote CUPS server"); #- fall back in case of something wrong.
	    }
	},
	clicked => sub { $o->configurePrinter(1) },
    };
  
    my @sound_cards = detect_devices::getSoundDevices();

    my $sound_index = 0;
    foreach my $device (@sound_cards) {
	$device->{sound_slot_index} = $sound_index;
	push @l, {
	    group => N("Hardware"),
	    label => N("Sound card"),
	    val => sub { 
		$device->{driver} && modules::module2description($device->{driver}) || $device->{description};
	    },
	    clicked => sub {
	        require harddrake::sound; 
	        harddrake::sound::config($o, $o->{modules_conf}, $device);
	    },
	};
     $sound_index++;
    }

    if (!@sound_cards && ($o->{rpmsrate_flags_chosen}{CAT_GAMES} || $o->{rpmsrate_flags_chosen}{CAT_AUDIO})) {
	#- if no sound card are detected AND the user selected things needing a sound card,
	#- propose a special case for ISA cards
	push @l, {
	    group => N("Hardware"),
	    label => N("Sound card"),
	    val => sub {},
	    clicked => sub {
	        if ($o->ask_yesorno('', N("Do you have an ISA sound card?"))) {
	    	  $o->do_pkgs->install(qw(alsa-utils sndconfig aoss));
	    	  $o->ask_warn('', N("Run \"alsaconf\" or \"sndconfig\" after installation to configure your sound card"));
	        } else {
	    	  $o->ask_warn('', N("No sound card detected. Try \"harddrake\" after installation"));
	        }
	    },
	};
    }

    foreach my $tv (detect_devices::getTVcards()) {
	push @l, {
	    group => N("Hardware"),
	    label => N("TV card"),
	    val => sub { $tv->{description} }, 
	    clicked => sub { 
	        require harddrake::v4l; 
	        harddrake::v4l::config($o, $o->{modules_conf}, $tv->{driver});
	    }
	};
    }

    push @l, {
	group => N("Hardware"),
	label => N("Graphical interface"),
	val => sub { $o->{raw_X} ? Xconfig::various::to_string($o->{raw_X}) : '' },
	clicked => sub { configureX($o, 'expert') }, 
    };

    push @l, {
	group => N("Network & Internet"),
	label => N("Network"),
	val => sub { $o->{net}{type} },
	clicked => sub { 
	    local $::expert = $::expert;
	    require network::netconnect;
	    network::netconnect::real_main($o->{net}, $o, $o->{modules_conf});
	},
    };

    $o->{miscellaneous} ||= {};
    push @l, {
	group => N("Network & Internet"),
	label => N("Proxies"),
	val => sub { $o->{miscellaneous}{http_proxy} || $o->{miscellaneous}{ftp_proxy} ? N("configured") : N("not configured") },
	clicked => sub { 
	    require network::network;
	    network::network::miscellaneous_choose($o, $o->{miscellaneous});
	    network::network::proxy_configure($o->{miscellaneous}) if !$::testing;
	},
    };

    push @l, {
	group => N("Security"),
	label => N("Security Level"),
	val => sub { 
	    require security::level;
	    security::level::to_string($o->{security});
	},
	clicked => sub {
	    require security::level;
	    security::level::level_choose($o, \$o->{security}, \$o->{libsafe}, \$o->{security_user})
		and install_any::set_security($o);
	},
    };

    push @l, {
	group => N("Security"),
	label => N("Firewall"),
	val => sub { 
	    require network::shorewall;
	    my $shorewall = network::shorewall::read();
	    $shorewall && !$shorewall->{disabled} ? N("activated") : N("disabled");
	},
	clicked => sub { 
	    require network::drakfirewall;
	    if (my @rc = network::drakfirewall::main($o, $o->{security} <= 3)) {
		$o->{firewall_ports} = !$rc[0] && $rc[1];
	    }
	},
    } if detect_devices::getNet();

    push @l, {
	group => N("Boot"),
	label => N("Bootloader"),
	val => sub { 
	    #-PO: example: lilo-graphic on /dev/hda1
	    N("%s on %s", $o->{bootloader}{method}, $o->{bootloader}{boot});
	},
	clicked => sub { 
	    any::setupBootloader($o, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{security}) or return;
	    any::installBootloader($o, $o->{bootloader}, $o->{all_hds});
	},
    };

    push @l, {
	group => N("System"),
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
	require pkgs;
	my $p = pkgs::packageByName($o->{packages}, 'xorg-x11');
	$o->{raw_X} || !$::testing && $p && !$p->flag_installed ||
	$o->ask_yesorno('', N("You have not configured X. Are you sure you really want this?"));
    };

    $o->summary_prompt(\@l, $check_complete);

    if ($o->{printer}) {
	#- Clean up $o->{printer} so that the records for an auto-installation
	#- contain only the important stuff
	require printer::printerdrake;
	printer::printerdrake::final_cleanup($o->{printer});
    }
    install_steps::configureTimezone($o) if !$timezone_manually_set;  #- do not forget it.
}

#------------------------------------------------------------------------------
sub configurePrinter {
    my ($o, $clicked) = @_;

    require printer::main;
    require printer::printerdrake;
    require printer::detect;

    #- $clicked = 0: Preparation of "Summary" step, check whether there are
    #- are local printers. Continue for automatically setting up print
    #- queues if so, return otherwise
    #- $clicked = 1: User clicked "Configure" button in "Summary", enter
    #- Printerdrake for manual configuration
    my $go_on = $clicked ? 2 : $o && printer::detect::local_detect();
    $go_on-- or return;

    #- install packages needed for printer::getinfo()
    $::testing or $o->do_pkgs->install('foomatic-db-engine');

    #- take default configuration, this include choosing the right spooler
    #- currently used by the system.
    my $printer = $o->{printer} ||= {};
    eval { add2hash($printer, printer::main::getinfo($o->{prefix})) };

    $printer->{PAPERSIZE} = $o->{locale}{country} eq 'US' || $o->{locale}{country} eq 'CA' ? 'Letter' : 'A4';
    printer::printerdrake::main($printer, $o->{security}, $o, $clicked, sub { install_interactive::upNetwork($o, 'pppAvoided') });

}
    
#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    $sup->{password2} ||= $sup->{password} ||= "";

    if ($o->{security} >= 1 || $clicked) {
	require authentication;
	authentication::ask_root_password_and_authentication($o, $o->{net}, $sup, $o->{authentication} ||= {}, $o->{meta_class}, $o->{security});
    }
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
	my @suggested_names = @{$o->{users}} ? () : grep { !/lost\+found/ } all("$::prefix/home");
	any::ask_users($o, $o->{users}, $o->{security}, \@suggested_names);
    }
    add2hash($o, any::get_autologin());
    any::autologin($o, $o);
    any::set_autologin($o->{autologin}, $o->{desktop}) if $::globetrotter;

    install_steps::addUser($o);
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $_w = $o->wait_message('', N("Preparing bootloader..."));
    $o->SUPER::setupBootloaderBefore;
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o) = @_;
    if (arch() =~ /ppc/) {
	if (detect_devices::get_mac_generation() !~ /NewWorld/ && 
	    detect_devices::get_mac_model() !~ /IBM/) {
	    $o->ask_warn('', N("You appear to have an OldWorld or Unknown machine, the yaboot bootloader will not work for you. The install will continue, but you'll need to use BootX or some other means to boot your machine. The kernel argument for the root fs is: root=%s", '/dev/' . fs::get::root_($o->{fstab})->{device}));
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
	any::installBootloader($o, $o->{bootloader}, $o->{all_hds}) or die "already displayed";
    }
}

sub miscellaneous {
    my ($o, $_clicked) = @_;

    if ($o->{meta_class} ne 'desktop' && $o->{meta_class} ne 'firewall' && !$o->{isUpgrade}) {
	require security::level;
	security::level::level_choose($o, \$o->{security}, \$o->{libsafe}, \$o->{security_user});

	if ($o->{security} > 2 && find { $_->{fs_type} eq 'vfat' } @{$o->{fstab}}) {
	    $o->ask_okcancel('', N("In this security level, access to the files in the Windows partition is restricted to the administrator."))
	      or goto &miscellaneous;
	}
    }

    install_steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o, $expert) = @_;

    install_steps::configureXBefore($o);
    symlink "$o->{prefix}/etc/gtk", "/etc/gtk";

    require Xconfig::main;
    my ($raw_X) = Xconfig::main::configure_everything_or_configure_chooser($o, install_any::X_options_from_o($o), !$expert, $o->{keyboard}, $o->{mouse});
    if ($raw_X) {
	$o->{raw_X} = $raw_X;
	install_steps::configureXAfter($o);
    }
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy {
    my ($o, $replay) = @_;
    my @imgs = install_any::getAndSaveAutoInstallFloppies($o, $replay) or return;

    my $floppy = detect_devices::floppy();
    $o->ask_okcancel('', N("Insert a blank floppy in drive %s", $floppy), 1) or return;

    my $i;
    foreach (@imgs) {
	if ($i++) {
	    $o->ask_okcancel('', N("Please insert another floppy for drivers disk"), 1) or return;
	}
	my $_w = $o->wait_message('', N("Creating auto install floppy..."));
	require commands;
	commands::dd("if=$_", 'of=' . devices::make($floppy));
	common::sync();
    }	
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' if !$alldone && !$o->ask_yesorno(N("Warning"), 
N("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_steps::exitInstall($o);

    $o->exit unless $alldone;

    $o->ask_from_no_check(
	{
	 title => N("Congratulations"),
	 icon => 'banner-exit',
	 messages => formatAlaTeX(install_messages::install_completed()),
	 interactive_help_id => 'exitInstall',
	 ok => $::local_install ? N("Quit") : N("Reboot"),
	},      
	[
	 if_(arch() !~ /^ppc/,
	     { val => \ (my $_t1 = N("Generate auto install floppy")), clicked => sub {
		   my $t = $o->ask_from_list_(N("Generate auto install floppy"), 
N("The auto install can be fully automated if wanted,
in that case it will take over the hard drive!!
(this is meant for installing on another box).

You may prefer to replay the installation.
"), [ N_("Replay"), N_("Automated") ]);
		   $t and $o->generateAutoInstFloppy($t eq 'Replay');
	       }, advanced => 1 }),
	 { val => \ (my $_t2 = N("Save packages selection")), clicked => sub { install_any::g_default_packages($o) }, advanced => 1 },
	]
	) if $alldone;
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################

1;
