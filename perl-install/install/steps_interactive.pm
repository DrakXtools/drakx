package install::steps_interactive; # $Id$


use strict;

our @ISA = qw(install::steps);


#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table;
use fs::type;
use fs::partitioning;
use fs::partitioning_wizard;
use install::steps;
use install::interactive;
use install::any;
use messages;
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

sub acceptLicense {
    my ($o) = @_;
    any::acceptLicense($o);
}

sub selectLanguage {
    my ($o) = @_;

    any::selectLanguage_install($o, $o->{locale});
    install::steps::selectLanguage($o);

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

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o, $clicked) = @_;

    my $from_usb = keyboard::from_usb();
    my $l = keyboard::lang2keyboards(lang::langs($o->{locale}{langs}));

    if ($clicked || !($from_usb || @$l && $l->[0][1] >= 90) || listlength(lang::langs($o->{locale}{langs})) > 1) {
	add2hash($o->{keyboard}, $from_usb);
	my @best = uniq($from_usb ? $from_usb->{KEYBOARD} : (), map { $_->[0] } @$l);
	@best = () if @best == 1;

	my $format = sub { translate(keyboard::KEYBOARD2text($_[0])) };
	my $other;
	my $ext_keyboard = my $KEYBOARD = $o->{keyboard}{KEYBOARD};
	$o->ask_from_(
		      { title => N("Keyboard"), 
			icon => 'banner-languages',
			messages => N("Please choose your keyboard layout."),
			interactive_help_id => 'selectKeyboard',
			advanced_messages => N("Here is the full list of available keyboards"),
			advanced_label => N("More"),
		      },
		      [ if_(@best, { val => \$KEYBOARD, type => 'list', format => $format, sort => 1,
				     list => [ @best ], changed => sub { $other = 0 } }),
			{ val => \$ext_keyboard, type => 'list', format => $format, changed => sub { $other = 1 },
			  list => [ difference2([ keyboard::KEYBOARDs() ], \@best) ], advanced => @best > 1 }
		      ]);
	$o->{keyboard}{KEYBOARD} = !@best || $other ? $ext_keyboard : $KEYBOARD;
	delete $o->{keyboard}{unsafe};
    }
    keyboard::group_toggle_choose($o, $o->{keyboard}) or goto &selectKeyboard;
    install::steps::selectKeyboard($o);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($o) = @_;

    if (my @l = install::any::find_root_parts($o->{fstab}, $::prefix)) {
	log::l("proposing to upgrade partitions " . join(" ", map { $_->{part} && $_->{part}{device} } @l));

	my @releases = uniq(map { $_->{release} } @l);
	if (@releases != @l) {
	    #- same release name so adding the device to differentiate them:
	    $_->{release} .= " ($_->{part}{device})" foreach @l;
	}

      askInstallClass:
	my $p;
	$o->ask_from_({ title => N("Install/Upgrade"),
			messages => N("Is this an install or an upgrade?"),
			interactive_help_id => 'selectInstallClass',
		      },
		      [ { val => \$p,
			  list => [ @l, N_("_: This is a noun:\nInstall") ], 
			  type => 'list',
			  format => sub { ref($_[0]) ? N("Upgrade %s", $_[0]{release}) : translate($_[0]) }
			} ]);
	if (ref $p) {
	    if (arch() =~ /x86_64/ && $p->{arch} eq 'i586') {
		$o->ask_warn('', N("Upgrade from a 32bit to a 64bit distribution is not supported"));
		goto askInstallClass;
	    }
	    if (arch() =~ /i.86/ && $p->{arch} eq 'x86_64') {
		$o->ask_warn('', N("Upgrade from a 64bit to a 32bit distribution is not supported"));
		goto askInstallClass;
	    }

	    if ($p->{part}) {
		log::l("choosing to upgrade partition $p->{part}{device}");
		$o->{migrate_device_names} = install::any::use_root_part($o->{all_hds}, $p->{part}, $o);
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

    $force || $o->{mouse}{unsafe} or return;

    mouse::select($o, $o->{mouse}) or return;
   
    if ($o->{mouse}{device} eq "input/mice") {
	modules::interactive::load_category($o, $o->{modules_conf}, 'bus/usb', 1, 0);
	eval { 
	    devices::make("usbmouse");
	    modules::load(qw(usbhid mousedev usbmouse));
	};
    }
}
#------------------------------------------------------------------------------
sub setupSCSI {
    my ($o) = @_;

    install::any::configure_pcmcia($o);
    { 
	my $_w = $o->wait_message(N("IDE"), N("Configuring IDE"));
	modules::load(modules::category2modules('disk/cdrom'));
    }
    modules::interactive::load_category($o, $o->{modules_conf}, 'bus/firewire', 1);

    my $have_non_scsi = detect_devices::hds(); #- at_least_one scsi device if we have no disks
    modules::interactive::load_category($o, $o->{modules_conf}, 'disk/card_reader|ide|scsi|hardware_raid|sata|firewire', 1, !$have_non_scsi);
    modules::interactive::load_category($o, $o->{modules_conf}, 'disk/card_reader|ide|scsi|hardware_raid|sata|firewire') if !detect_devices::hds(); #- we really want a disk!

    install::interactive::tellAboutProprietaryModules($o);

    install::any::getHds($o, $o);
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
		    my $p = { start => $freepart->{start}, size => MB(1), mntpoint => '' };
		    fs::type::set_pt_type($p, 0x401);
		    fsedit::add($freepart->{hd}, $p, $o->{all_hds}, { force => 1, primaryOrExtended => 'Primary' });
		    $partition_table::mac::new_bootstrap = 1;

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
        fs::partitioning_wizard::main($o, $o->{all_hds}, $o->{fstab}, $o->{manualFstab}, $o->{partitions}, $o->{partitioning}, $::local_install);
    }
}

#------------------------------------------------------------------------------
sub rebootNeeded {
    my ($o) = @_;
    fs::partitioning_wizard::warn_reboot_needed($o);
    install::steps::rebootNeeded($o);
}

#------------------------------------------------------------------------------
sub choosePartitionsToFormat {
    my ($o) = @_;
    fs::partitioning::choose_partitions_to_format($o, $o->{fstab});
}

sub formatMountPartitions {
    my ($o, $_fstab) = @_;
    fs::partitioning::format_mount_partitions($o, $o->{all_hds}, $o->{fstab});
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;
    install::any::setPackages($o);
}

#- group by CD
sub ask_deselect_media__copy_on_disk {
    my ($o, $hdlists, $o_copy_rpms_on_disk) = @_;

    log::l("ask_deselect_media__copy_on_disk");

    my @names = uniq(map { $_->{name} } @$hdlists);
    my %selection = map { $_ => 1 } @names;

    $o->ask_from_({ messages => formatAlaTeX(N("The following installation media have been found.
If you want to skip some of them, you can unselect them now.")) },
		[ (map { { type => 'bool', text => $_, val => \$selection{$_}, 
			    if_($_ eq $names[0], disabled => sub { 1 }),
			} } @names),
		  if_($o_copy_rpms_on_disk,
		    { type => 'label', val => \(formatAlaTeX(N("You have the option to copy the contents of the CDs onto the hard drive before installation.
It will then continue from the hard drive and the packages will remain available once the system is fully installed."))) },
		    { type => 'bool', text => N("Copy whole CDs"), val => $o_copy_rpms_on_disk },
		  ),
		]);
    $_->{selected} = $selection{$_->{name}} foreach @$hdlists;
    log::l("keeping media " . join ',', map { $_->{rpmsdir} } grep { $_->{selected} } @$hdlists);
}

sub while_suspending_time {
    my ($o, $f) = @_;

    my $time = time();

    my $r = $f->();

    #- add the elapsed time (otherwise the predicted time will be rubbish)
    $o->{install_start_time} += time() - $time;

    $r;
}

# nb: $file can be a directory
sub ask_change_cd {
    my ($o, $phys_m, $o_rel_file) = @_;

    while_suspending_time($o, sub { ask_change_cd_($o, $phys_m, $o_rel_file) });
}

sub ask_change_cd_ {
    my ($o, $phys_m, $o_rel_file) = @_;

    local $| = 1; print "\a";

    if ($phys_m->{name} =~ /commercial/i) {
	$o->{useless_thing_accepted2} ||= 
	  $o->ask_from_list_('', formatAlaTeX(messages::com_license()), 
			     [ N_("Accept"), N_("Refuse") ], "Accept") eq "Accept" or return;
    }

    foreach (1 .. 32) {
	install::media::umount_phys_medium($phys_m);
	install::media::openCdromTray($phys_m->{device});

	$o->ask_okcancel('', N("Change your Cd-Rom!
Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you do not have it, press Cancel to avoid installation from this Cd-Rom.", $phys_m->{name}), 1) or return;

	eval { fs::mount::part($phys_m) };

	#- it can be a directory, so don't use -f
	!$o_rel_file || -e install::media::path($phys_m, $o_rel_file) and return 1;

	log::l("file " . install::media::path($phys_m, $o_rel_file) . " not found");
    }
    undef;
}

sub selectSupplMedia {
    my ($o) = @_;
    install::any::selectSupplMedia($o);
}
#------------------------------------------------------------------------------
sub choosePackages {
    my ($o) = @_;

    my $w = $o->wait_message('', N("Looking for available packages..."));
    my $availableC = &install::steps::choosePackages;

    require install::pkgs;

    my $min_size = install::pkgs::selectedSize($o->{packages});
    undef $w;
    if ($min_size >= $availableC) {
	my $msg = N("Your system does not have enough space left for installation or upgrade (%dMB > %dMB)",
		    $min_size / sqr(1024), $availableC / sqr(1024));
	log::l($msg);
	$o->ask_warn('', $msg);
	install::steps::rebootNeeded($o);
    }

    my $min_mark = 4;
    my ($individual, $chooseGroups);

    if (!$o->{isUpgrade}) {
	if (install::pkgs::packageByName($o->{packages}, 'task-kde') &&
	    install::pkgs::packageByName($o->{packages}, 'task-gnome-minimal') &&
		$availableC >= 2_500_000_000) { # don't chooseDesktop if not enough place
	    _chooseDesktop($o, $o->{rpmsrate_flags_chosen}, \$chooseGroups);
	} else {
	    # don't ask for desktop if kde and gnome are not available on media (useful for mini iso)
	    $chooseGroups = 1;
	}
    }

  chooseGroups:
    $o->chooseGroups($o->{packages}, $o->{compssUsers}, $min_mark, \$individual) if $chooseGroups;

    ($o->{packages_}{ind}) =
      install::pkgs::setSelectedFromCompssList($o->{packages}, $o->{rpmsrate_flags_chosen}, $min_mark, $availableC);

    $o->choosePackagesTree($o->{packages}) or goto chooseGroups if $individual;

    install::any::warnAboutRemovedPackages($o, $o->{packages});
    install::any::warnAboutNaughtyServers($o) or goto chooseGroups if !$o->{isUpgrade};
}

sub choosePackagesTree {
    my ($o, $packages, $o_limit_to_medium) = @_;

    $o->ask_many_from_list('', N("Choose the packages you want to install"),
			   {
			    list => [ grep { !$o_limit_to_medium || install::pkgs::packageMedium($packages, $_) == $o_limit_to_medium }
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
	    my ($_h, $fh) = install::any::media_browser($o, '', 'package_list.pl') or return;
	    my $O = eval { install::any::loadO(undef, $fh) };
	    if ($@) {
		$o->ask_okcancel('', N("Bad file")) or return;
	    } else {
		install::any::unselectMostPackages($o);
		install::pkgs::select_by_package_names($packages, $O->{default_packages} || []);
		return 1;
	    }
	}
    } else {
	log::l("save package selection");
	install::any::g_default_packages($o);
    }
}
sub _chooseDesktop {
    my ($o, $rpmsrate_flags_chosen, $chooseGroups) = @_;

    my @l = group_by2(
	KDE    => N("Install Mandriva KDE Desktop"),
	GNOME  => N("Install Mandriva GNOME Desktop"),
	Custom => N("Custom install"),
    );
    my $title = N("Package Group Selection");
    my $message = N("You can choose your workstation desktop profile: KDE, GNOME or Custom");

    my $choice;
    if ($o->isa('interactive::gtk')) {
	$choice = install::steps_gtk::reallyChooseDesktop($o, $title, $message, \@l);
    } else {
	$o->ask_from_({ title => $title, message => $message }, [
	    { val => \$choice, list => \@l, type => 'list', format => sub { $_[0][1] } }, 
	]);
    }
    my $desktop = $choice->[0];
    log::l("chosen Desktop: $desktop");
    my @desktops = ('KDE', 'GNOME');
    if (member($desktop, @desktops)) {
	my ($want, $dontwant) = ($desktop, grep { $desktop ne $_ } @desktops);
	$rpmsrate_flags_chosen->{"CAT_$want"} = 1;
	$rpmsrate_flags_chosen->{"CAT_$dontwant"} = 0;
	my @flags = map_each { if_($::b, $::a) } %$rpmsrate_flags_chosen;
	log::l("flags ", join(' ', sort @flags));
	install::any::unselectMostPackages($o);
    } else {
	$$chooseGroups = 1;
    }
}
sub chooseGroups {
    my ($o, $packages, $compssUsers, $min_level, $individual) = @_;

    #- for all groups available, determine package which belongs to each one.
    #- this will enable getting the size of each groups more quickly due to
    #- limitation of current implementation.
    #- use an empty state for each one (no flag update should be propagated).
    
    my $b = install::pkgs::saveSelected($packages);
    install::any::unselectMostPackages($o);
    install::pkgs::setSelectedFromCompssList($packages, { CAT_SYSTEM => 1 }, $min_level, 0);
    my $system_size = install::pkgs::selectedSize($packages);
    my ($sizes, $pkgs) = install::pkgs::computeGroupSize($packages, $min_level);
    install::pkgs::restoreSelected($b);
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
    my $available_size = install::any::getAvailableSpace($o) / sqr(1024);
    my $size_to_display = sub { 
	my $lsize = $system_size + $compute_size->(map { "CAT_$_" } map { @{$_->{flags}} } grep { $_->{selected} } @$compssUsers);

	#- if a profile is deselected, deselect everything (easier than deselecting the profile packages)
	$unselect_all ||= $size > $lsize;
	$size = $lsize;
	N("Total size: %d / %d MB", install::pkgs::correctSize($size / sqr(1024)), $available_size);
    };

    while (1) {
	if ($available_size < 200) {
	    # too small to choose anything. Defaulting to no group chosen
	    $_->{selected} = 0 foreach @$compssUsers;
	    last;
	}

	$o->reallyChooseGroups($size_to_display, $individual, $compssUsers) or return;

	last if $::testing || install::pkgs::correctSize($size / sqr(1024)) < $available_size || every { !$_->{selected} } @$compssUsers;
       
	$o->ask_warn('', N("Selected size is larger than available space"));	
    }
    install::any::set_rpmsrate_category_flags($o, $compssUsers);

    log::l("compssUsersChoice selected: ", join(', ', map { qq("$_->{path}|$_->{label}") } grep { $_->{selected} } @$compssUsers));

    #- do not try to deselect package (by default no groups are selected).
    if (!$o->{isUpgrade}) {
	install::any::unselectMostPackages($o) if $unselect_all;
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
	) or return &chooseGroups;

	if ($minimal) {
	    $o->{rpmsrate_flags_chosen}{CAT_X} = $docs = 0;
	    $o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 0;
	}
	$o->{excludedocs} = !$docs;
	$o->{rpmsrate_flags_chosen}{CAT_MINIMAL_DOCS} = $docs;

	install::any::unselectMostPackages($o);
    }
    1;
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $compssUsers) = @_;

    my $size_text = &$size_to_display;

    my ($path, $all);
    $o->ask_from_({ messages => N("Package Group Selection"),
		    interactive_help_id => 'choosePackages',
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
		  changed => sub { $size_text = &$size_to_display },
		 };
	   } @$compssUsers),
	 if_($individual, { text => N("Individual package selection"), val => $individual, advanced => 1, type => 'bool' }),
    ]);

    if ($all) {
	$_->{selected} = 1 foreach @$compssUsers;
    }
    1;    
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;
    my ($current, $total) = (0, 0);

    my ($_w, $wait_message) = $o->wait_message_with_progress_bar(N("Installing"));
    $wait_message->(N("Preparing installation"), 0, 100); #- beware, interactive::curses::wait_message_with_progress_bar need to create the Dialog::Progress here because in installCallback we are chrooted

    local *install::steps::installCallback = sub {
	my ($packages, $type, $id, $subtype, $_amount, $total_) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    $total = $total_;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    my $p = $packages->{depslist}[$id];
	    $wait_message->(N("Installing package %s", $p->name), $current, $total);
	    $current += $p->size;
	}
    };

    my $install_result;
    catch_cdie { $install_result = $o->install::steps::installPackages($packages) }
      sub { installPackages__handle_error($o, $_[0]) };

    if ($install::pkgs::cancel_install) {
	$install::pkgs::cancel_install = 0;
	die "setstep choosePackages\n";
    }
    $install_result;
}

sub installPackages__handle_error {
    my ($o, $err_ref) = @_;

    log::l("catch_cdie: $$err_ref");
    my $time = time();
    my $go_on;
    if ($$err_ref =~ /^error ordering package list: (.*)/) {
	$go_on = $o->ask_yesorno('', [
	    N("There was an error ordering packages:"), $1, N("Go on anyway?") ], 1);
    } elsif ($$err_ref =~ /^error installing package list: (\S+)\s*(.*)/) {
	my ($pkg_name, $medium_name) = ($1, $2);
	my @choices = (
	    [ 'retry', N("Retry") ],
	    [ 'skip_one', N("Skip this package") ],
	    [ 'disable_media', N("Skip all packages from medium \"%s\"", $medium_name) ],
	    [ '', N("Go back to media and packages selection") ],
	);
	my $choice;
	$o->ask_from_({ messages => N("There was an error installing package %s.", $pkg_name) },
		      [ { val => \$choice, type => 'list', list => \@choices, format => sub { $_[0][1] } } ]);
	$go_on = $choice->[0];
    }
    if ($go_on) {
	#- add the elapsed time (otherwise the predicted time will be rubbish)
	$o->{install_start_time} += time() - $time;
	$go_on;
    } else {
	$o->{askmedia} = 1;
	$$err_ref = "already displayed";
	0;
    }
}


sub afterInstallPackages($) {
    my ($o) = @_;
    my $_w = $o->wait_message('', N("Post-install configuration"));
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
	#- don't overwrite configuration in a network install
	if (!install::any::is_network_install($o)) {
	    require network::network;
	    network::network::easy_dhcp($o->{net}, $o->{modules_conf});
	}
	$o->SUPER::configureNetwork;
}

#------------------------------------------------------------------------------
sub installUpdates {
    my ($o) = @_;
    my $u = $o->{updates} ||= {};
    
    $o->hasNetwork or return;

    if (install::any::is_network_install($o) &&
	find { $_->{update} } install::media::allMediums($o->{packages})) {
	log::l("installUpdates: skipping since updates were already available during install");
	return;
    }

    $o->ask_yesorno_({ title => N("Updates"), icon => 'banner-update', messages => formatAlaTeX(
N("You now have the opportunity to download updated packages. These packages
have been updated after the distribution was released. They may
contain security or bug fixes.

To download these packages, you will need to have a working Internet 
connection.

Do you want to install the updates?")),
			   interactive_help_id => 'installUpdates',
					       }) or return;

    #- bring all interface up for installing updates packages.
    install::interactive::upNetwork($o);

    #- update medium available and working.
    my $update_medium;
    do {
	$u->{url} = install::any::ask_mirror($o, 'updates', $u->{url}) or goto &installUpdates;
	# FIXME: install all update media
	my $phys_medium = install::media::url2mounted_phys_medium($o, $u->{url} . '/media/main/updates');

	eval {
	    my $_w = $o->wait_message('', N("Contacting the mirror to get the list of available packages..."));
	    $update_medium = { name => "Updates for Mandriva Linux " . $o->{product_id}{version}, update => 1 };
	    install::media::get_standalone_medium($o, $phys_medium, $o->{packages}, $update_medium);
	};
	if ($@) {
	    undef $update_medium;
	    $o->ask_warn('', N("Unable to contact mirror %s", $u->{mirror}));
	}
    } until $update_medium;

    if ($update_medium) {
	if ($o->choosePackagesTree($o->{packages}, $update_medium)) {
	    $o->{isUpgrade} = 1; #- now force upgrade mode, else update will be installed instead of upgraded.
	    $o->pkg_install;
	} else {
	    #- make sure to not try to install the packages (which are automatically selected by getPackage above).
	    #- this is possible by deselecting the medium (which can be re-selected above).
	    $update_medium->{selected} = 0;
	    goto &installUpdates;
	}
	#- update urpmi even, because there is an hdlist available and everything is good,
	#- this will allow user to update the medium but update his machine later.
	install::steps::install_urpmi($o);
    }

    #- not downing network, even ppp. We don't care much since it is the end of install :)
}


#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o, $clicked) = @_;

    any::configure_timezone($o, $o->{timezone}, $clicked) or return;

    install::steps::configureTimezone($o);
    1;
}

#------------------------------------------------------------------------------
sub configureServices { 
    my ($o, $clicked) = @_;
    require services;
    $o->{services} = services::ask($o) if $clicked;
    install::steps::configureServices($o);
}


sub summaryBefore {
    my ($o) = @_;

    install::any::preConfigureTimezone($o);
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
	($_->{format}, $_->{val}) = (sub { $val && $val->() || N("not configured") }, '');
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

    my $timezone_manually_set;  
    push @l, {
	group => N("System"),
	label => N("Timezone"),
	banner_icon => 'banner-languages',
	val => sub { $o->{timezone}{timezone} },
	clicked => sub { $timezone_manually_set = $o->configureTimezone(1) || $timezone_manually_set },
    };
    push @l, {
	group => N("System"),
	label => N("Country / Region"),
	val => sub { lang::c2name($o->{locale}{country}) },
	clicked => sub {
	    any::selectCountry($o, $o->{locale}) or return;

	    my $pkg_locale = lang::locale_to_main_locale(lang::getlocale_for_country($o->{locale}{lang}, $o->{locale}{country}));
	    my @pkgs = URPM::packages_providing($o->{packages}, "locales-$pkg_locale");
	    $o->pkg_install(map { $_->name } @pkgs) if @pkgs;

	    lang::write_and_install($o->{locale}, $o->do_pkgs);
	    if (!$timezone_manually_set) {
		delete $o->{timezone};
		install::any::preConfigureTimezone($o); #- now we can precise the timezone thanks to the country
	    }
	},
    };
    push @l, {
	group => N("System"),
	label => N("Bootloader"),
	val => sub { 
	    #-PO: example: lilo-graphic on /dev/hda1
	    N("%s on %s", $o->{bootloader}{method}, $o->{bootloader}{boot});
	},
	clicked => sub { 
	    any::setupBootloader($o, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{security}) or return;
	    any::installBootloader($o, $o->{bootloader}, $o->{all_hds});
	},
    } if !$::local_install;

    push @l, {
	group => N("System"),
	label => N("User management"),
	clicked => sub { 
	    if (my $u = any::ask_user($o, $o->{users}, $o->{security}, needauser => 1)) {
		any::add_users([$u], $o->{authentication});
	    }
	},
    };

    push @l, {
	group => N("System"),
	label => N("Services"),
	banner_icon => 'banner-generic-ad',
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

    push @l, {
	group => N("Hardware"), 
	label => N("Keyboard"), 
	val => sub { $o->{keyboard} && translate(keyboard::keyboard2text($o->{keyboard})) },
	clicked => sub { $o->selectKeyboard(1) },
    };

    push @l, {
	group => N("Hardware"),
	label => N("Mouse"),
	banner_icon => 'banner-bootL',
	val => sub { translate($o->{mouse}{type}) . ' ' . translate($o->{mouse}{name}) },
	clicked => sub { selectMouse($o, 1); mouse::write($o->do_pkgs, $o->{mouse}) },
    };


    my @sound_cards = detect_devices::getSoundDevices();

    my $sound_index = 0;
    foreach my $device (@sound_cards) {
	$device->{sound_slot_index} = $sound_index;
	push @l, {
	    group => N("Hardware"),
	    label => N("Sound card"),
	    banner_icon => 'banner-generic-ad',
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

    push @l, {
	group => N("Hardware"),
	label => N("Graphical interface"),
	banner_icon => 'banner-bootL',
	val => sub { $o->{raw_X} ? Xconfig::various::to_string($o->{raw_X}) : '' },
	clicked => sub { configureX($o, 'expert') }, 
    };

    push @l, {
	group => N("Network & Internet"),
	label => N("Network"),
	val => sub { $o->{net}{type} },
	clicked => sub { 
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
	    my $security = $o->{security};
       set_sec_level:
	    if (security::level::level_choose($o, \$security, \$o->{libsafe}, \$o->{security_user})) {
             check_security_level($o, $security) or goto set_sec_level;
	     $o->{security} = $security;
             install::any::set_security($o);
         }
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
    } if detect_devices::get_net_interfaces();

    my $check_complete = sub {
	require install::pkgs;
	my $p = install::pkgs::packageByName($o->{packages}, 'task-x11');
	$o->{raw_X} || !$::testing && $p && !$p->flag_installed ||
	$o->ask_yesorno('', N("You have not configured X. Are you sure you really want this?"));
    };

    $o->summary_prompt(\@l, $check_complete);

    install::steps::configureTimezone($o) if !$timezone_manually_set;  #- do not forget it.
}

#------------------------------------------------------------------------------
#-setRootPassword_addUser
#------------------------------------------------------------------------------
sub setRootPassword_addUser {
    my ($o) = @_;
    $o->{users} ||= [];

    my $sup = $o->{superuser} ||= {};
    $sup->{password2} ||= $sup->{password} ||= "";

    any::ask_user_and_root($o, $sup, $o->{users}, $o->{security});

    install::steps::setRootPassword($o);
    install::steps::addUser($o);
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

sub check_security_level {
    my ($o, $security) = @_;
	if ($security > 2 && find { $_->{fs_type} eq 'vfat' } @{$o->{fstab}}) {
	    $o->ask_okcancel('', N("In this security level, access to the files in the Windows partition is restricted to the administrator.")) or return 0;
     }
     return 1;
}

sub miscellaneous {
    my ($o, $_clicked) = @_;

    install::steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o, $expert) = @_;

    install::steps::configureXBefore($o);
    symlink "$::prefix/etc/gtk", "/etc/gtk";

    require Xconfig::main;
    my ($raw_X) = Xconfig::main::configure_everything_or_configure_chooser($o, install::any::X_options_from_o($o), !$expert, $o->{keyboard}, $o->{mouse});
    if ($raw_X) {
	$o->{raw_X} = $raw_X;
	install::steps::configureXAfter($o);
    }
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy {
    my ($o, $replay) = @_;
    my $img = install::any::getAndSaveAutoInstallFloppies($o, $replay) or return;

    my $floppy = detect_devices::floppy();
    $o->ask_okcancel('', N("Insert a blank floppy in drive %s", $floppy), 1) or return;

	my $_w = $o->wait_message('', N("Creating auto install floppy..."));
	require install::commands;
	install::commands::dd("if=$img", 'of=' . devices::make($floppy));
	common::sync();
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' if !$alldone && !$o->ask_yesorno(N("Warning"), 
N("Some steps are not completed.

Do you really want to quit now?"), 0);

    install::steps::exitInstall($o);

    $o->exit unless $alldone;

    $o->ask_from_no_check(
	{
	 title => N("Congratulations"),
	 icon => 'banner-exit',
	 messages => formatAlaTeX(messages::install_completed()),
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
	 { val => \ (my $_t2 = N("Save packages selection")), clicked => sub { install::any::g_default_packages($o) }, advanced => 1 },
	]
	) if $alldone;
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################

1;
