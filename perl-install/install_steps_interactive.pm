package install_steps_interactive; # $Id$


use diagnostics;
use strict;
use vars qw(@ISA $new_bootstrap $com_license);

@ISA = qw(install_steps);

$com_license = _("
Warning

Please read carefully the terms below. If you disagree with any
portion, you are not allowed to install the next CD media. Press 'Refuse' 
to continue the installation without using these media.


Some components contained in the next CD media are not governed
by the GPL License or similar agreements. Each such component is then
governed by the terms and conditions of its own specific license. 
Please read carefully and comply with such specific licenses before 
you use or redistribute the said components. 
Such licenses will in general prevent the transfer,  duplication 
(except for backup purposes), redistribution, reverse engineering, 
de-assembly, de-compilation or modification of the component. 
Any breach of agreement will immediately terminate your rights under 
the specific license. Unless the specific license terms grant you such
rights, you usually cannot install the programs on more than one
system, or adapt it to be used on a network. In doubt, please contact 
directly the distributor or editor of the component. 
Transfer to third parties or copying of such components including the 
documentation is usually forbidden.


All rights to the components of the next CD media belong to their 
respective authors and are protected by intellectual property and 
copyright laws applicable to software programs.
");

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table qw(:types);
use partition_table::raw;
use install_steps;
use install_interactive;
use install_any;
use detect_devices;
use run_program;
use devices;
use fsedit;
use loopback;
use mouse;
use modules;
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
    $o->ask_warn(_("Error"), [ _("An error occurred"), formatError($err) ]);
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

    $o->{lang} = any::selectLanguage($o, $o->{lang}, $o->{langs} ||= {})
      || return $o->ask_yesorno('', _("Do you really want to leave the installation?")) ? $o->exit : &selectLanguage;
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
varies from language to language).")) if $o->{lang} !~ /^en/ && !lang::load_mo();
    } else {
	#- don't use _( ) for this, as it is never translated
	$o->ask_warn('', "The characters of your language can't be displayed in console,
so the messages will be displayed in english during installation") if $ENV{LANGUAGE} eq 'C';
    }
}
    
sub acceptLicence {
    my ($o) = @_;
    return if $o->{useless_thing_accepted};

    $o->set_help('license');
    $o->{useless_thing_accepted} = $o->ask_from_list_(_("License agreement"), formatAlaTeX(
_("Introduction

The operating system and the different components available in the Mandrake Linux distribution 
shall be called the \"Software Products\" hereafter. The Software Products include, but are not 
restricted to, the set of programs, methods, rules and documentation related to the operating 
system and the different components of the Mandrake Linux distribution.


1. License Agreement

Please read this document carefully. This document is a license agreement between you and  
MandrakeSoft S.A. which applies to the Software Products.
By installing, duplicating or using the Software Products in any manner, you explicitly 
accept and fully agree to conform to the terms and conditions of this License. 
If you disagree with any portion of the License, you are not allowed to install, duplicate or use 
the Software Products. 
Any attempt to install, duplicate or use the Software Products in a manner which does not comply 
with the terms and conditions of this License is void and will terminate your rights under this 
License. Upon termination of the License,  you must immediately destroy all copies of the 
Software Products.


2. Limited Warranty

The Software Products and attached documentation are provided \"as is\", with no warranty, to the 
extent permitted by law.
MandrakeSoft S.A. will, in no circumstances and to the extent permitted by law, be liable for any special,
incidental, direct or indirect damages whatsoever (including without limitation damages for loss of 
business, interruption of business, financial loss, legal fees and penalties resulting from a court 
judgment, or any other consequential loss) arising out of  the use or inability to use the Software 
Products, even if MandrakeSoft S.A. has been advised of the possibility or occurence of such 
damages.

LIMITED LIABILITY LINKED TO POSSESSING OR USING PROHIBITED SOFTWARE IN SOME COUNTRIES

To the extent permitted by law, MandrakeSoft S.A. or its distributors will, in no circumstances, be 
liable for any special, incidental, direct or indirect damages whatsoever (including without 
limitation damages for loss of business, interruption of business, financial loss, legal fees 
and penalties resulting from a court judgment, or any other consequential loss) arising out 
of the possession and use of software components or arising out of  downloading software components 
from one of Mandrake Linux sites  which are prohibited or restricted in some countries by local laws.
This limited liability applies to, but is not restricted to, the strong cryptography components 
included in the Software Products.


3. The GPL License and Related Licenses

The Software Products consist of components created by different persons or entities.  Most 
of these components are governed under the terms and conditions of the GNU General Public 
Licence, hereafter called \"GPL\", or of similar licenses. Most of these licenses allow you to use, 
duplicate, adapt or redistribute the components which they cover. Please read carefully the terms 
and conditions of the license agreement for each component before using any component. Any question 
on a component license should be addressed to the component author and not to MandrakeSoft.
The programs developed by MandrakeSoft S.A. are governed by the GPL License. Documentation written 
by MandrakeSoft S.A. is governed by a specific license. Please refer to the documentation for 
further details.


4. Intellectual Property Rights

All rights to the components of the Software Products belong to their respective authors and are 
protected by intellectual property and copyright laws applicable to software programs.
MandrakeSoft S.A. reserves its rights to modify or adapt the Software Products, as a whole or in 
parts, by all means and for all purposes.
\"Mandrake\", \"Mandrake Linux\" and associated logos are trademarks of MandrakeSoft S.A.  


5. Governing Laws 

If any portion of this agreement is held void, illegal or inapplicable by a court judgment, this 
portion is excluded from this contract. You remain bound by the other applicable sections of the 
agreement.
The terms and conditions of this License are governed by the Laws of France.
All disputes on the terms of this license will preferably be settled out of court. As a last 
resort, the dispute will be referred to the appropriate Courts of Law of Paris - France.
For any question on this document, please contact MandrakeSoft S.A.  
")), [ __("Accept"), __("Refuse") ], "Refuse") eq "Accept" and return;

    $o->ask_yesorno('', _("Are you sure you refuse the licence?"), 1) and $o->exit;

    &acceptLicence;
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o, $clicked) = @_;

    my $from_usb = keyboard::from_usb();
    my $l = keyboard::lang2keyboards(lang::langs($o->{langs}));

    if ($::expert || $clicked || !($from_usb || @$l && $l->[0][1] >= 90) || listlength(lang::langs($o->{langs})) > 1) {
	add2hash($o->{keyboard}, $from_usb);
	my @best = uniq($from_usb ? $from_usb->{KEYBOARD} : (), (map { $_->[0] } @$l), 'us_intl');

	my $format = sub { translate(keyboard::KEYBOARD2text($_[0])) };
	my $other;
	my $ext_keyboard = my $KEYBOARD = $o->{keyboard}{KEYBOARD};
	$o->ask_from_(
		      { title => _("Keyboard"), 
			messages => _("Please choose your keyboard layout."),
			advanced_messages => _("Here is the full list of keyboards available"),
			advanced_label => _("More"),
			callbacks => { changed => sub { $other = $_[0]==1 } },
		      },
		      [ if_(@best > 1, { val => \$KEYBOARD, type => 'list', format => $format, sort => 1,
					 list => [ @best ] }),
			{ val => \$ext_keyboard, type => 'list', format => $format,
			  list => [ difference2([ keyboard::KEYBOARDs() ], \@best) ], advanced => @best > 1 }
		      ]);
	$o->{keyboard}{KEYBOARD} = $other ? $ext_keyboard : $KEYBOARD;
	delete $o->{keyboard}{unsafe};
    }
    any::keyboard_group_toggle_choose($o, $o->{keyboard}) or goto &selectKeyboard;
    install_steps::selectKeyboard($o);
}
#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $verif->($o->ask_from_list(_("Install Class"), _("Which installation class do you want?"), $l, $def) || die 'already displayed');

    return if !@$l2;

    $::live ? 'Update' : $o->ask_from_list_(_("Install/Update"), _("Is this an install or an update?"), $l2, $def2);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($o, $clicked) = @_;

    my %c = my @c = (
      if_(!$::corporate,
	_("Recommended") => "beginner",
      ),
      if_($o->{meta_class} ne 'desktop',
	_("Expert")	 => "expert",
      ),
    );
    %c = @c = (_("Expert") => "expert") if $::expert && !$clicked;

    $o->set_help('selectInstallClassCorpo') if $::corporate;

    my $verifInstallClass = sub { $::expert = $c{$_[0]} eq "expert" };
    my $installMode = $o->{isUpgrade} ? $o->{keepConfiguration} ? __("Upgrade packages only") : __("Upgrade") : __("Install");

    if ($installMode = $o->selectInstallClass1($verifInstallClass,
					       first(list2kv(@c)), ${{reverse %c}}{$::expert ? "expert" : "beginner"},
					       exists $o->{isUpgrade} ? [] : [ __("Install"), __("Upgrade"), __("Upgrade packages only") ], $installMode)) {
	$o->{isUpgrade} = $installMode =~ /Upgrade/;
	$o->{keepConfiguration} = $installMode =~ /packages only/;
    }

    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    $force ||= $o->{mouse}{unsafe} || $::expert;

    my $prev = $o->{mouse}{type} . '|' . $o->{mouse}{name};
    $o->{mouse} = mouse::fullname2mouse(
	$o->ask_from_treelist_('', _("Please choose the type of your mouse."), 
			       '|', [ mouse::fullnames ], $prev) || return) if $force;

    if ($force && $o->{mouse}{type} eq 'serial') {
	$o->set_help('selectSerialPort');
	$o->{mouse}{device} = 
	  $o->ask_from_listf(_("Mouse Port"),
			    _("Please choose on which serial port your mouse is connected to."),
			    \&mouse::serial_port2text,
			    [ mouse::serial_ports ]) or return;
    }
    if (arch() =~ /ppc/ && $o->{mouse}{nbuttons} == 1) {
	#- set a sane default F11/F12
	$o->{mouse}{button2_key} = 87;
	$o->{mouse}{button3_key} = 88;
	$o->ask_from('', _("Buttons emulation"),
		[
		{ label => _("Button 2 Emulation"), val => \$o->{mouse}{button2_key}, list => [ mouse::ppc_one_button_keys() ], format => \&mouse::ppc_one_button_key2text },
		{ label => _("Button 3 Emulation"), val => \$o->{mouse}{button3_key}, list => [ mouse::ppc_one_button_keys() ], format => \&mouse::ppc_one_button_key2text },
		]) or return;
    }
    
    if ($o->{mouse}{device} eq "usbmouse") {
	any::load_category($o, 'bus/usb', 1, 1);
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
    my ($o, $clicked) = @_;

    if (!$::noauto && arch() =~ /i.86/) {
	if ($o->{pcmcia} ||= !$::testing && c::pcmcia_probe()) {
	    my $w = $o->wait_message(_("PCMCIA"), _("Configuring PCMCIA cards..."));
	    my $results = modules::configure_pcmcia($o->{pcmcia});
	    $w = undef;
	    $results and $o->ask_warn('', $results);
	}
    }
    { 
	my $w = $o->wait_message(_("IDE"), _("Configuring IDE"));
	modules::load(modules::category2modules('disk/cdrom'));
    }
    any::load_category($o, 'bus/firewire', 1);

    any::load_category($o, 'disk/scsi|hardware_raid', !$::expert && !$clicked, 0);

    install_interactive::tellAboutProprietaryModules($o) if !$clicked;
}

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;
    $o->set_help('ask_mntpoint_s');

    my @fstab = grep { isTrueFS($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
    die _("No partition available") if @fstab == 0;

    {
	my $w = $o->wait_message('', _("Scanning partitions to find mount points"));
	install_any::suggest_mount_points($fstab, $o->{prefix}, 'uniq');
	log::l("default mntpoint $_->{mntpoint} $_->{device}") foreach @fstab;
    }
    if (@fstab == 1) {
	$fstab[0]{mntpoint} = '/';
    } else {
	$o->ask_from('', 
				  _("Choose the mount points"),
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

    install_any::getHds($o, $o);

    if (arch() =~ /ppc/ && detect_devices::get_mac_generation =~ /NewWorld/) { #- need to make bootstrap part if NewWorld machine - thx Pixel ;^)
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
		$o->ask_warn('',_("No free space for 1MB bootstrap! Install will continue, but to boot your system, you'll need to create the bootstrap partition in DiskDrake"));
	    }
	}
    }

    if ($o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = fsedit::get_root_($o->{fstab});
        if (!$p) {
            my @l = install_any::find_root_parts($o->{fstab}, $o->{prefix}) or die _("No root partition found to perform an upgrade");
	    $p = $o->ask_from_listf(_("Root Partition"),
			            _("What is the root partition (/) of your system?"),
			            \&partition_table::description, \@l) or die "setstep exitInstall\n";
        }
	install_any::use_root_part($o->{all_hds}, $p, $o->{prefix});
    } elsif ($::expert && $o->isa('interactive::gtk')) {
        install_interactive::partition_with_diskdrake($o, $o->{all_hds});
    } else {
        install_interactive::partitionWizard($o);
    }
}

#------------------------------------------------------------------------------
sub rebootNeeded {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));

    install_steps::rebootNeeded($o);
}

#------------------------------------------------------------------------------
sub choosePartitionsToFormat {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab);

    my @l = grep { !$_->{isMounted} && $_->{mntpoint} && 
		   (!isSwap($_) || $::expert) &&
		   (!isFat($_) || $_->{notFormatted} || $::expert) &&
		   (!isOtherAvailableFS($_) || $::expert || $_->{toFormat})
	       } @$fstab;
    $_->{toFormat} = 1 foreach grep { isSwap($_) && !$::expert } @$fstab;

    return if @l == 0 || !$::expert && 0 == grep { ! $_->{toFormat} } @l;

    #- keep it temporary until the guy has accepted
    $_->{toFormatTmp} = $_->{toFormat} || $_->{toFormatUnsure} foreach @l;

    $o->ask_from_(
        { messages => _("Choose the partitions you want to format"),
          advanced_messages => _("Check bad blocks?"),
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
    my ($o, $fstab) = @_;
    my $w;
    catch_cdie {
        fs::formatMount_all($o->{all_hds}{raids}, $o->{fstab}, $o->{prefix}, sub {
        	my ($part) = @_;
        	$w ||= $o->wait_message('', _("Formatting partitions"));
        	$w->set(isLoopback($part) ?
        		_("Creating and formatting file %s", $part->{loopback_file}) :
        		_("Formatting partition %s", $part->{device}));
        });
    } sub { 
	$@ =~ /fsck failed on (\S+)/ or return;
	$o->ask_yesorno('', _("Failed to check filesystem %s. Do you want to repair the errors? (beware, you can loose data)", $1), 1);
    };
    die _("Not enough swap space to fulfill installation, please add some") if availableMemory < 40 * 1024;
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o, $rebuild_needed) = @_;

    my $w = $o->wait_message('', $rebuild_needed ? _("Looking for available packages and rebuilding rpm database...") :
			     _("Looking for available packages..."));
    install_any::setPackages($o, $rebuild_needed);

    $w->set(_("Looking at packages already installed..."));
    pkgs::selectPackagesAlreadyInstalled($o->{packages}, $o->{prefix});

    if ($rebuild_needed) {
	$w->set(_("Finding packages to upgrade..."));
	pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix});
    }
}
#------------------------------------------------------------------------------
sub choosePackages {
    my ($o, $packages, $compssUsers, $first_time) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user if using a cdrom.
    $o->chooseCD($packages) if $o->{method} eq 'cdrom' && !$::oem;

    my $availableC = install_steps::choosePackages(@_);
    my $individual = $::expert;

    require pkgs;

    my $min_size = pkgs::selectedSize($packages);
    $min_size < $availableC or die _("Your system does not have enough space left for installation or upgrade (%d > %d)", $min_size, $availableC);

    my $min_mark = $::expert ? 3 : 4;

    my $b = pkgs::saveSelected($packages);
    my $level = pkgs::setSelectedFromCompssList($packages, { map { $_ => 1 } map { @{$compssUsers->{$_}{flags}} } @{$o->{compssUsersSorted}} }, $min_mark, 0);
    my $max_size = pkgs::selectedSize($packages) + 1; #- avoid division by zero.
    log::l("max size (level $min_mark) is : " . formatXiB($max_size));
    pkgs::restoreSelected($b);

    $o->chooseGroups($packages, $compssUsers, $min_mark, \$individual, $max_size) if !$::corporate;

    ($o->{packages_}{ind}) =
      pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $min_mark, $availableC);

    $o->choosePackagesTree($packages) if $individual;

    install_any::warnAboutRemovedPackages($o, $o->{packages});
    install_any::warnAboutNaughtyServers($o);
}

sub choosePackagesTree {
    my ($o, $packages, $limit_to_medium) = @_;

    $o->ask_many_from_list('', _("Choose the packages you want to install"),
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
_("Please choose load or save package selection on floppy.
The format is the same as auto_install generated floppies."),
		 [ { val => \ (my $choice), list => [ __("Load from floppy"), __("Save on floppy") ], format => \&translate, type => 'list' } ]) or return;

    if ($choice eq 'Load from floppy') {
	while (1) {
	    my $w = $o->wait_message(_("Package selection"), _("Loading from floppy"));
	    log::l("load package selection from floppy");
	    my $O = eval { install_any::loadO(undef, 'floppy') };
	    if ($@) {
		$w = undef;	#- close wait message.
		$o->ask_okcancel('', _("Insert a floppy containing package selection"))
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
	$_ => ! grep { ! $o->{compssUsersChoice}{$_} } @{$compssUsers->{$_}{flags}}
    } @groups;

#    @groups = grep { $size{$_} = round_down($size{$_} / sqr(1024), 10) } @groups; #- don't display the empty or small one (eg: because all packages are below $min_level)
    my ($all, $size, $unselect_all);
    my $available_size = install_any::getAvailableSpace($o) / sqr(1024);
    my $size_to_display = sub { 
	my $lsize = $system_size + $compute_size->(map { @{$compssUsers->{$_}{flags}} } grep { $val{$_} } @groups);

	#- if a profile is deselected, deselect everything (easier than deselecting the profile packages)
	$unselect_all ||= $size > $lsize;
	$size = $lsize;
	_("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available_size);
    };

    while (1) {
	if ($available_size < 140) {
	    # too small to choose anything. Defaulting to no group chosen
	    $val{$_} = 0 foreach %val;
	    last;
	}

	$o->reallyChooseGroups($size_to_display, $individual, \%val) or return;
	last if pkgs::correctSize($size / sqr(1024)) < $available_size;
       
	$o->ask_warn('', _("Selected size is larger than available space"));	
    }

    $o->{compssUsersChoice}{$_} = 0 foreach map { @{$compssUsers->{$_}{flags}} } grep { !$val{$_} } keys %val;
    $o->{compssUsersChoice}{$_} = 1 foreach map { @{$compssUsers->{$_}{flags}} } grep {  $val{$_} } keys %val;

    log::l("compssUsersChoice: " . (!$val{$_} && "not ") . "selected [$_] as [$o->{compssUsers}{$_}{label}]") foreach keys %val;

    #- do not try to deselect package (by default no groups are selected).
    $o->{isUpgrade} or $unselect_all and install_any::unselectMostPackages($o);
    #- if no group have been chosen, ask for using base system only, or no X, or normal.
    unless ($o->{isUpgrade} || grep { $val{$_} } keys %val) {
	my $docs = !$o->{excludedocs};	
	my $minimal = !grep { $_ } values %{$o->{compssUsersChoice}};

	$o->ask_from(_("Type of install"), 
		     _("You haven't selected any group of packages.
Please choose the minimal installation you want:"),
		     [
		      { val => \$o->{compssUsersChoice}{X}, type => 'bool', text => _("With X"), disabled => sub { $minimal } },
		        if_($::expert || $minimal,
		      { val => \$docs, type => 'bool', text => _("With basic documentation (recommended!)"), disabled => sub { $minimal } },
		      { val => \$minimal, type => 'bool', text => _("Truly minimal install (especially no urpmi)") },
			),
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
    $o->ask_from('', _("Package Group Selection"), [
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
	 if_($o->{meta_class} eq 'desktop', { text => _("All"), val => \$all, type => 'bool' }),
	 if_($individual, { text => _("Individual package selection"), val => $individual, advanced => 1, type => 'bool' }),
    ], changed => sub { $size_text = &$size_to_display }) or return;

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

    $o->set_help('chooseCD');
    $o->ask_many_from_list('',
_("If you have all the CDs in the list below, click Ok.
If you have none of those CDs, click Cancel.
If only some CDs are missing, unselect them, then click Ok."),
			   {
			    list => \@mediumsDescr,
			    label => sub { _("Cd-Rom labeled \"%s\"", $_[0]) },
			    val => sub { \$mediumsDescr{$_[0]} },
			   }) or do {
			       $mediumsDescr{$_} = 0 foreach @mediumsDescr; #- force unselection of other CDs.
			   };
    $o->set_help('choosePackages');

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

    my $w = $o->wait_message(_("Installing"), _("Preparing installation"));

    my $old = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my ($data, $type, $id, $subtype, $_amount, $_total) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    $total = $_total;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    my $p = $data->{depslist}[$id];
	    $w->set(_("Installing package %s\n%d%%", $p->name, $total && 100 * $current / $total));
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
	    my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX($com_license), [ __("Accept"), __("Refuse") ], "Accept") eq "Accept");
            $r &&= $o->ask_okcancel('', _("Change your Cd-Rom!

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
_("There was an error ordering packages:"), $1, _("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  } elsif ($@ =~ /^error installing package list: (.*)/) {
	      $o->ask_yesorno('', [
_("There was an error installing packages:"), $1, _("Go on anyway?") ], 1) and return 1;
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
    my $w = $o->wait_message('', _("Post-install configuration"));
    $o->SUPER::afterInstallPackages($o);
}

sub copyKernelFromFloppy {
    my ($o) = @_;
    $o->ask_okcancel('', _("Please insert the Boot floppy used in drive %s", $o->{blank}), 1) or return;
    $o->SUPER::copyKernelFromFloppy();
}

sub updateModulesFromFloppy {
    my ($o) = @_;
    $o->ask_okcancel('', _("Please insert the Update Modules floppy in drive %s", $o->{updatemodules}), 1) or return;
    $o->SUPER::updateModulesFromFloppy();
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o, $first_time, $noauto) = @_;
    require network::netconnect;
    network::netconnect::main($o->{prefix}, $o->{netcnx} ||= {}, $o->{netc}, $o->{mouse}, $o, $o->{intf},
			      $first_time, $o->{lang} eq "fr_FR" && $o->{keyboard}{KEYBOARD} eq "fr", $noauto);
}

#-configureNetworkIntf moved to network

#-configureNetworkNet moved to network
#------------------------------------------------------------------------------
#-pppConfig moved to any.pm
#------------------------------------------------------------------------------
sub installCrypto {
    my $license =
_("You now have the opportunity to download encryption software.

WARNING:

Due to different general requirements applicable to these software and imposed
by various jurisdictions, customer and/or end user of theses software should
ensure that the laws of his/their jurisdiction allow him/them to download, stock
and/or use these software.

In addition customer and/or end user shall particularly be aware to not infringe
the laws of his/their jurisdiction. Should customer and/or end user not
respect the provision of these applicable laws, he/they will incure serious
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
USA");
    goto &installUpdates; #- remove old code, keep this one ok though by transfering to installUpdates.
}

sub installUpdates {
    my ($o) = @_;
    my $u = $o->{updates} ||= {};
    
    $o->hasNetwork or return;

    is_empty_hash_ref($u) and $o->ask_yesorno('', 
formatAlaTeX(
_("You now have the opportunity to download updated packages. These packages
have been released after the distribution was released. They may
contain security or bug fixes.

To download these packages, you will need to have a working Internet 
connection.

Do you want to install the updates ?"))) || return;

    #- bring all interface up for installing crypto packages.
    install_interactive::upNetwork($o);

    require crypto;
    eval {
	my @mirrors = do { my $w = $o->wait_message('',
						    _("Contacting Mandrake Linux web site to get the list of available mirrors..."));
			   crypto::mirrors() };
	#- if no mirror have been found, use current time zone and propose among available.
	$u->{mirror} ||= crypto::bestMirror($o->{timezone}{timezone});
	$u->{mirror} = $o->ask_from_treelistf('', 
					      _("Choose a mirror from which to get the packages"), 
					      '|',
					      \&crypto::mirror2text,
					      \@mirrors,
					      $u->{mirror});
    };
    return if $@ || !$u->{mirror};

    my $update_medium = do {
	my $w = $o->wait_message('', _("Contacting the mirror to get the list of available packages..."));
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
    $o->{timezone}{timezone} = $o->ask_from_treelist('', _("Which is your timezone?"), '/', [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone}) || return;
    $o->set_help('configureTimezoneGMT');

    my $ntp = to_bool($o->{timezone}{ntp});
    $o->ask_from('', '', [
	  { text => _("Hardware clock set to GMT"), val => \$o->{timezone}{UTC}, type => 'bool' },
	  { text => _("Automatic time synchronization (using NTP)"), val => \$ntp, type => 'bool' },
    ]) or goto &configureTimezone
	    if $::expert || $clicked;
    if ($ntp) {
	my @servers = split("\n", timezone::ntp_servers());

	$o->ask_from('', '',
	    [ { label => _("NTP Server"), val => \$o->{timezone}{ntp}, list => \@servers, not_edit => 0 } ]
        ) or goto &configureTimezone;
	$o->{timezone}{ntp} =~ s/.*\((.+)\)/$1/;
    } else {
	$o->{timezone}{ntp} = '';
    }
    install_steps::configureTimezone($o);
}

#------------------------------------------------------------------------------
sub configureServices { 
    my ($o, $clicked) = @_;
    require services;
    $o->{services} = services::ask($o, $o->{prefix}) if $::expert || $clicked;
    install_steps::configureServices($o);
}

sub summary {
    my ($o, $first_time) = @_;
    require pkgs;

    if ($first_time) {
	#- auto-detection
	$o->configurePrinter(0) if !$::expert;
	install_any::preConfigureTimezone($o);
    }
    my $mouse_name;
    my $format_mouse = sub { $mouse_name = translate($o->{mouse}{type}) . ' ' . translate($o->{mouse}{name}) };
    &$format_mouse;

    #- format printer description in a better way
    my $format_printers = sub {
	my $printer = $o->{printer};
	if (is_empty_hash_ref($printer->{configured})) {
	    pkgs::packageByName($o->{packages}, 'cups')->flag_installed and return _("Remote CUPS server");
	    return _("No printer");
	}
	my $entry;
	foreach ($printer->{currentqueue},
		 map { $_->{queuedata} } ($printer->{configured}{$printer->{DEFAULT}}, values %{$printer->{configured}})) {
	    $_ && ($_->{make} || $_->{model}) and return "$_->{make} $_->{model}";
	}
	return _("Remote CUPS server"); #- fall back in case of something wrong.
    };

    my @sound_cards = (arch() =~ /ppc/ ? \&modules::load_category : \&modules::probe_category)->('multimedia/sound');

    #- if no sound card are detected AND the user selected things needing a sound card,
    #- propose a special case for ISA cards
    my $isa_sound_card = 
      !@sound_cards && ($o->{compssUsersChoice}{GAMES} || $o->{compssUsersChoice}{AUDIO}) &&
	sub {
	    if ($o->ask_yesorno('', _("Do you have an ISA sound card?"))) {
		$o->do_pkgs->install('sndconfig');
		$o->ask_warn('', _("Run \"sndconfig\" after installation to configure your sound card"));
	    } else {
		$o->ask_warn('', _("No sound card detected. Try \"harddrake\" after installation"));
	    }
	};

    $o->ask_from_({
		   messages => _("Summary"),
		   cancel   => '',
		  }, [
{ label => _("Mouse"), val => \$mouse_name, clicked => sub { $o->selectMouse(1); mouse::write($o, $o->{mouse}); &$format_mouse } },
{ label => _("Keyboard"), val => \$o->{keyboard}, clicked => sub { $o->selectKeyboard(1) }, format => sub { translate(keyboard::keyboard2text($_[0])) } },
{ label => _("Timezone"), val => \$o->{timezone}{timezone}, clicked => sub { $o->configureTimezone(1) } },
{ label => _("Printer"), val => \$o->{printer}, clicked => sub { $o->configurePrinter(1) }, format => $format_printers },
    (map {
{ label => _("ISDN card"), val => $_->{description}, clicked => sub { $o->configureNetwork } }
     } grep { $_->{driver} eq 'hisax' } detect_devices::probeall()),
    (map { 
{ label => _("Sound card"), val => $_->{description} } 
     } @sound_cards),
    if_($isa_sound_card, { label => _("Sound card"), clicked => $isa_sound_card }), 
    (map {
{ label => _("TV card"), val => $_->{description}, clicked => sub { 
      require harddrake::v4l; 
      harddrake::v4l::config($o, $_->{driver});
} } } grep { $_->{driver} =~ '(bttv|saa7134)' } detect_devices::probeall()),
]);
    install_steps::configureTimezone($o);  #- do not forget it.
}

#------------------------------------------------------------------------------
sub configurePrinter {
    my ($o, $clicked) = @_;
    $::corporate && !$clicked and return;

    require printer;
    require printerdrake;

    #- try to determine if a question should be asked to the user or
    #- if he is autorized to configure multiple queues.
    my $ask_multiple_printer = ($::expert || $clicked) && 2 || scalar(printerdrake::auto_detect($o));
    $ask_multiple_printer-- or return;

    #- install packages needed for printer::getinfo()
    $::testing or $o->do_pkgs->install('foomatic');

    #- take default configuration, this include choosing the right system
    #- currently used by the system.
    my $printer = $o->{printer} ||= {};
    eval { add2hash($printer, printer::getinfo($o->{prefix})) };

    $printer->{PAPERSIZE} = (($o->{lang} =~ /^en_US/) || 
                             ($o->{lang} =~ /^en_CA/) || 
                             ($o->{lang} =~ /^fr_CA/)) ? 'Letter' : 'A4';
    printerdrake::main($printer, $o, $ask_multiple_printer, sub { install_interactive::upNetwork($o, 'pppAvoided') });

}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    my $auth = ($o->{authentication}{LDAP} && __("LDAP") ||
		$o->{authentication}{NIS} && __("NIS") ||
		$o->{authentication}{winbind} && __("Windows Domain") ||
		__("Local files"));
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $::isInstall and $o->set_help("setRootPassword", if_($::expert, "setRootPasswordAuth"));

    $o->ask_from_(
        {
	 title => _("Set root password"), 
	 messages => _("Set root password"),
	 cancel => ($o->{security} <= 2 && !$::corporate ? _("No password") : ''),
	 callbacks => { 
	     complete => sub {
		 $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,0);
		 length $sup->{password} < 2 * $o->{security}
		   and $o->ask_warn('', _("This password is too short (it must be at least %d characters long)", 2 * $o->{security})), return (1,0);
		 return 0
        } } }, [
{ label => _("Password"), val => \$sup->{password},  hidden => 1 },
{ label => _("Password (again)"), val => \$sup->{password2}, hidden => 1 },
  if_($::expert,
{ label => _("Authentication"), val => \$auth, list => [ __("Local files"), __("LDAP"), __("NIS"), __("Windows Domain") ], format => \&translate },
  ),
			 ]) or return;

    if ($auth eq __("LDAP")) {
	$o->{authentication}{LDAP} ||= 'ldap.' . $o->{netc}{DOMAINNAME};
	$o->{netc}{LDAPDOMAIN} ||= join (',', map { "dc=$_" } split /\./, $o->{netc}{DOMAINNAME});
	$o->ask_from('',
		     _("Authentication LDAP"),
		     [ { label => _("LDAP Base dn"), val => \$o->{netc}{LDAPDOMAIN} },
		       { label => _("LDAP Server"), val => \$o->{authentication}{LDAP} },
		     ]) or goto &setRootPassword;
    } else { $o->{authentication}{LDAP} = '' }
    if ($auth eq __("NIS")) { 
	$o->{authentication}{NIS} ||= 'broadcast';
	$o->ask_from('',
		     _("Authentication NIS"),
		     [ { label => _("NIS Domain"), val => \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}) },
		       { label => _("NIS Server"), val => \$o->{authentication}{NIS}, list => ["broadcast"], not_edit => 0 },
		     ]) or goto &setRootPassword;
    } else { $o->{authentication}{NIS} = '' }
    if ($auth eq __("Windows Domain")) {
	#- maybe we should browse the network like diskdrake --smb and get the 'doze server names in a list 
	#- but networking isn't setup yet necessarily
	$o->ask_warn('', _("For this to work for a W2K PDC, you will probably need to have the admin run: C:\>net localgroup \"Pre-Windows 2000 Compatible Access\" everyone /add and reboot the server.\nYou will also need the username/password of a Domain Admin to join the machine to the Windows(TM) domain.\nIf networking is not yet enabled, Drakx will attempt to join the domain after the network setup step.\nShould this setup fail for some reason and domain authentication is not working, run 'smbpasswd -j DOMAIN -U USER%PASSWORD' using your Windows(tm) Domain, and Admin Username/Password, after system boot.\nThe command 'wbinfo -t' will test whether your authentication secrets are good."));
	$o->ask_from('',
			_("Authentication Windows Domain"),
			[ { label => _("Windows Domain"), val => \ ($o->{netc}{WINDOMAIN} ||= $o->{netc}{DOMAINNAME}) },
			  { label => _("Domain Admin User Name"), val => \$o->{authentication}{winbind} },
			  { label => _("Domain Admin Password"), val => \$o->{authentication}{winpass}, hidden => 1  },
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
    if (($o->{security} >= 1 || $clicked)) {
	any::ask_users($o->{prefix}, $o, $o->{users}, $o->{security});
    }
    any::get_autologin($o->{prefix}, $o);
    any::autologin($o->{prefix}, $o, $o);

    install_steps::addUser($o);
}

#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time, $noauto) = @_;

    return if !$noauto && $first_time && !$::expert;

    if (arch() =~ /sparc/) {
	#- as probing floppies is a bit more different on sparc, assume always /dev/fd0.
	$o->ask_okcancel('',
			 _("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
SILO on your system, or another operating system removes SILO, or SILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures.

If you want to create a bootdisk for your system, insert a floppy in the first
drive and press \"Ok\"."),
			 $o->{mkbootdisk}) or return $o->{mkbootdisk} = '';
	my @l = detect_devices::floppies_dev();
	$o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
	$o->{mkbootdisk} or return;
    } else {
	my @l = detect_devices::floppies_dev();
	my %l = (
		 'fd0'  => _("First floppy drive"),
		 'fd1'  => _("Second floppy drive"),
		 'Skip' => _("Skip"),
		 );

	if ($first_time || @l == 1) {
	    $o->ask_yesorno('', formatAlaTeX(
			    _("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
LILO (or grub) on your system, or another operating system removes LILO, or LILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?
%s", isThisFs('xfs', fsedit::get_root($o->{fstab})) ? _("

(WARNING! You're using XFS for your root partition,
creating a bootdisk on a 1.44 Mb floppy will probably fail,
because XFS needs a very large driver).") : '')), 
			    $o->{mkbootdisk}) or return $o->{mkbootdisk} = '';
	    $o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
	} else {
	    @l or die _("Sorry, no floppy drive available");

	    $o->ask_from_(
              {
	       messages => _("Choose the floppy drive you want to use to make the bootdisk"),
	      }, [ { val => \$o->{mkbootdisk}, list => \@l, format => sub { $l{$_[0]} || $_[0] } } ]
            ) or return;
        }
        $o->ask_warn('', _("Insert a floppy in %s", $l{$o->{mkbootdisk}} || $o->{mkbootdisk}));
    }

    my $w = $o->wait_message('', _("Creating bootdisk..."));
    install_steps::createBootdisk($o);
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Preparing bootloader..."));
    $o->set_help('empty');
    $o->SUPER::setupBootloaderBefore($o);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o, $more) = @_;
    if (arch() =~ /ppc/) {
	my $machtype = detect_devices::get_mac_generation();
	if ($machtype !~ /NewWorld/) {
	    $o->ask_warn('', _("You appear to have an OldWorld or Unknown\n machine, the yaboot bootloader will not work for you.\nThe install will continue, but you'll\n need to use BootX to boot your machine"));
	    log::l("OldWorld or Unknown Machine - no yaboot setup");
	    return;
	}
    }
    if (arch() =~ /^alpha/) {
	$o->ask_yesorno('', _("Do you want to use aboot?"), 1) or return;
	catch_cdie { $o->SUPER::setupBootloader } sub {
	    $o->ask_yesorno('', 
_("Error installing aboot, 
try to force installation even if that destroys the first partition?"));
	};
    } else {
	any::setupBootloader($o, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{security}, $o->{prefix}, $more) or return;

	{
	    my $w = $o->wait_message('', _("Installing bootloader"));
	    eval { $o->SUPER::setupBootloader };
	}
	if (my $err = $@) {
	    $err =~ /failed$/ or die;
	    $o->ask_warn('', 
			 [ _("Installation of bootloader failed. The following error occured:"),
			   grep { !/^Warning:/ } cat_("$o->{prefix}/tmp/.error") ]);
	    unlink "$o->{prefix}/tmp/.error";
	    die "already displayed";
	} elsif (arch() =~ /ppc/) {
	    my $of_boot = cat_("$o->{prefix}/tmp/of_boot_dev") || die "Can't open $o->{prefix}/tmp/of_boot_dev";
	    chop($of_boot);
	    unlink "$o->{prefix}/tmp/.error";
	    $o->ask_warn('', _("You may need to change your Open Firmware boot-device to\n enable the bootloader.  If you don't see the bootloader prompt at\n reboot, hold down Command-Option-O-F at reboot and enter:\n setenv boot-device %s,\\\\:tbxi\n Then type: shut-down\nAt your next boot you should see the bootloader prompt.", $of_boot));
	}
    }
}

sub miscellaneous {
    my ($o, $clicked) = @_;

    if ($::expert) {
	any::choose_security_level($o, \$o->{security}, \$o->{libsafe}, \$o->{security_user}) or return;
    }
    install_steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o, $clicked) = @_;
    $o->configureXBefore;

    symlink "$o->{prefix}/etc/gtk", "/etc/gtk";
    require Xconfig::main;
    Xconfig::main::configure_everything($o, $o->{raw_X}, $o->do_pkgs, !$::expert && !$clicked,
			  { allowFB          => $o->{allowFB},
			    allowNVIDIA_rpms => install_any::allowNVIDIA_rpms($o->{packages}),
			  });
    $o->configureXAfter;
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy {
    my ($o, $replay) = @_;

    my $floppy = detect_devices::floppy();

    $o->ask_okcancel('', _("Insert a blank floppy in drive %s", $floppy), 1) or return;

    my $dev = devices::make($floppy);
    {
	my $w = $o->wait_message('', _("Creating auto install floppy..."));
	install_any::getAndSaveAutoInstallFloppy($o, $replay, $dev) or return;
    }
    common::sync();         #- if you shall remove the floppy right after the LED switches off
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' unless $alldone || $o->ask_yesorno('', 
_("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_steps::exitInstall($o);

    $o->exit unless $alldone;

    $o->ask_from_no_check(
	{
	 messages => formatAlaTeX(
_("Congratulations, installation is complete.
Remove the boot media and press return to reboot.


For information on fixes which are available for this release of Mandrake Linux,
consult the Errata available from:


%s


Information on configuring your system is available in the post
install chapter of the Official Mandrake Linux User's Guide.",
_("http://www.mandrakelinux.com/en/90errata.php3"))),
	 cancel => '',
	},      
	[
	 if_($::expert,
	     { val => \ (my $t1 = _("Generate auto install floppy")), clicked => sub {
		   my $t = $o->ask_from_list_('', 
_("The auto install can be fully automated if wanted,
in that case it will take over the hard drive!!
(this is meant for installing on another box).

You may prefer to replay the installation.
"), [ __("Replay"), __("Automated") ]);
		   $t and $o->generateAutoInstFloppy($t eq 'Replay');
	       }, advanced => 1 },
	     { val => \ (my $t2 = _("Save packages selection")), clicked => sub { install_any::g_default_packages($o) }, advanced => 1 },
	 ),
	]
	) if $alldone && !$::g_auto_install;
}


#-######################################################################################
#- Misc Steps Functions
#-######################################################################################

1;
