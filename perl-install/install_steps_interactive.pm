package install_steps_interactive; # $Id$


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :functional :system);
use partition_table qw(:types);
use partition_table_raw;
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
    $err =~ s/ at .*?$/\./ unless $::testing; #- avoid error message.
    $o->ask_warn(_("Error"), [ _("An error occurred"), $err ]);
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

    $o->ask_from_entries_refH_powered(
	{ messages => _("Please, choose a language to use."),
	  advanced_messages => _("You can choose other languages that will be available after install"),
	  callbacks => {
	      focus_out => sub { $o->{langs}{$o->{lang}} = 1 },
	  },
	},
	[ { val => \$o->{lang}, separator => '|', 
	    format => \&lang::lang2text, list => [ lang::list() ] },
	  (map {;
	       { val => \$o->{langs}{$_->[0]}, type => 'bool', disabled => sub { $o->{langs}{all} },
		 text => $_->[1], advanced => 1,
	       } 
	   } sort { $a->[1] cmp $b->[1] } map { [ $_, lang::lang2text($_) ] } lang::list()),
	  { val => \$o->{langs}{all}, type => 'bool', text => _("All"), advanced => 1 }
	]);

    install_steps::selectLanguage($o);

    $o->charsetChanged;

    $o->ask_warn('', 
"If you see this message it is because you choose a language for " .
"which DrakX does not include a translation yet; however the fact " .
"that it is listed means there is some support for it anyway.\n" .
"That is, once GNU/Linux will be installed, you will be able to at " .
"least read and write in that language; and possibly more (various " .
"fonts, spell checkers, various programs translated etc. that " .
"varies from language to language).") if $o->{lang} !~ /^en/ && translate("_I18N_");
    
    unless ($o->{useless_thing_accepted}) {
	$o->set_help('license');
	$o->{useless_thing_accepted} = $o->ask_from_list_(_("License agreement"), formatAlaTeX(
_("Introduction

The operating system and the different components available in the Linux-Mandrake distribution 
shall be called the \"Software Products\" hereafter. The Software Products include, but are not 
restricted to, the set of programs, methods, rules and documentation related to the operating 
system and the different components of the Linux-Mandrake distribution.


1. License Agreement

Please read carefully this document. This document is a license agreement between you and  
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
Products, even if MandrakeSoft S.A. has been advised of the possibility or occurance of such 
damages.

LIMITED LIABILITY LINKED TO POSSESSING OR USING PROHIBITED SOFTWARE IN SOME COUNTRIES

To the extent permitted by law, MandrakeSoft S.A. or its distributors will, in no circumstances, be 
liable for any special, incidental, direct or indirect damages whatsoever (including without 
limitation damages for loss of business, interruption of business, financial loss, legal fees 
and penalties resulting from a court judgment, or any other consequential loss) arising out 
of the possession and use of software components or arising out of  downloading software components 
from one of Linux-Mandrake sites  which are prohibited or restricted in some countries by local laws.
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
\"Mandrake\", \"Linux-Mandrake\" and associated logos are trademarks of MandrakeSoft S.A.  


5. Governing Laws 

If any portion of this agreement is held void, illegal or inapplicable by a court judgment, this 
portion is excluded from this contract. You remain bound by the other applicable sections of the 
agreement.
The terms and conditions of this License are governed by the Laws of France.
All disputes on the terms of this license will preferably be settled out of court. As a last 
resort, the dispute will be referred to the appropriate Courts of Law of Paris - France.
For any question on this document, please contact MandrakeSoft S.A.  
")), [ __("Accept"), __("Refuse") ], "Accept") eq "Accept" or $o->exit;
    }
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o, $clicked) = @_;

    my $l = keyboard::lang2keyboards($o->{lang});

    #- good guess, don't ask
    return if !$::expert && !$clicked && $l->[0][1] > 90;

    my @best = map { $_->[0] } @$l;
    push @best, 'us_intl' if !member('us_intl', @best);

    my $format = sub { translate(keyboard::keyboard2text($_[0])) };
    my $other;
    my $ext_keyboard = $o->{keyboard};
    $o->ask_from_entries_refH_powered(
	{ title => _("Keyboard"), 
	  messages => _("Please, choose your keyboard layout."),
	  advanced_messages => _("Here is the full list of keyboards available"),
	  advanced_label => _("More"),
	  callbacks => { changed => sub { $other = $_[0]==1 } },
	},
	  [ if_(@best > 1, { val => \$o->{keyboard}, type => 'list', format => $format,
	      list => [ @best ] }),
	    { val => \$ext_keyboard, type => 'list', format => $format,
	      list => [ keyboard::keyboards ], advanced => @best > 1 }
	  ]);
    delete $o->{keyboard_unsafe};

    $o->{keyboard} = $ext_keyboard if $other;
    install_steps::selectKeyboard($o);
}
#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $verif->($o->ask_from_list(_("Install Class"), _("Which installation class do you want?"), $l, $def) || die 'already displayed');

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

    $o->{isUpgrade} = $o->selectInstallClass1($verifInstallClass,
					      first(list2kv(@c)), ${{reverse %c}}{$::expert ? "expert" : "beginner"},
					      [ __("Install"), __("Update") ], $o->{isUpgrade} ? "Update" : "Install") eq "Update";
    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    $force ||= $o->{mouse}{unsafe} || $::expert;

    my $prev = $o->{mouse}{type} . '|' . $o->{mouse}{name};
    $o->{mouse} = mouse::fullname2mouse(
	$o->ask_from_treelist_('', _("Please, choose the type of your mouse."), 
			       '|', [ mouse::fullnames ], $prev)) if $force;

    if ($force && $o->{mouse}{type} eq 'serial') {
	$o->set_help('selectSerialPort');
	$o->{mouse}{device} = 
	  $o->ask_from_listf(_("Mouse Port"),
			    _("Please choose on which serial port your mouse is connected to."),
			    \&mouse::serial_port2text,
			    [ mouse::serial_ports ]) or return;
    }

    any::setup_thiskind($o, 'usb', !$::expert, 0, $o->{pcmcia}) if $o->{mouse}{device} eq "usbmouse";
    eval { 
	devices::make("usbmouse");
	modules::load("usbmouse");
	modules::load("mousedev");
    } if $o->{mouse}{device} eq "usbmouse";

    $o->SUPER::selectMouse;
}
#------------------------------------------------------------------------------
sub setupSCSI {
    my ($o, $auto, $at_least_one) = @_;

    if ($o->{pcmcia} && !$::noauto) {
	my $w = $o->wait_message(_("PCMCIA"), _("Configuring PCMCIA cards..."));
	modules::configure_pcmcia($o->{pcmcia});
    }
    { 
	my $w = $o->wait_message(_("IDE"), _("Configuring IDE"));
	modules::load_ide();
    }
    any::setup_thiskind($o, 'scsi|disk', $auto, $at_least_one, $o->{pcmcia});
}

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;
    $o->set_help('ask_mntpoint_s');

    my @fstab = grep { isTrueFS($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
    die _("no available partitions") if @fstab == 0;

    {
	my $w = $o->wait_message('', _("Scanning partitions to find mount points"));
	install_any::suggest_mount_points($fstab, $o->{prefix}, 'uniq');
	log::l("default mntpoint $_->{mntpoint} $_->{device}") foreach @fstab;
    }
    if (@fstab == 1) {
	$fstab[0]{mntpoint} = '/';
    } else {
	$o->ask_from_entries_refH('', 
				  _("Choose the mount points"),
				  [ map { { label => partition_table_raw::description($_), 
					    val => \$_->{mntpoint}, not_edit => 0, list => [ '', fsedit::suggestions_mntpoint([]) ] }
					} @fstab ]) or return;
    }
    $o->SUPER::ask_mntpoint_s($fstab);
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    my $warned;
    install_any::getHds($o, sub {
	my ($err) = @_;
	$warned = 1;
	if ($o->ask_yesorno(_("Error"), 
_("I can't read your partition table, it's too corrupted for me :(
I can try to go on blanking bad partitions (ALL DATA will be lost!).
The other solution is to disallow DrakX to modify the partition table.
(the error is %s)

Do you agree to loose all the partitions?
", $err))) {
            0;
        } else {
            $o->{partitioning}{readonly} = 1;
            1;
        }
    }) or $warned or $o->ask_warn('', 
_("DiskDrake failed to read correctly the partition table.
Continue at your own risk!"));

	if (arch() =~ /ppc/ && !$::expert) {	#- need to make bootstrap part if recommended install - thx Pixel ;^)
		if (defined $partition_table_mac::bootstrap_part) {
			#- don't do anything if we've got the bootstrap setup
			#- otherwise, go ahead and create one somewhere in the drive free space
		} else {
			if (defined $partition_table_mac::freepart_start && $partition_table_mac::freepart_size >= 1) {
				my ($hd) = $partition_table_mac::freepart_device;
				log::l("creating bootstrap partition on drive /dev/$hd->{device}, block $partition_table_mac::freepart_start");
    			fsedit::add($hd, { start => $partition_table_mac::freepart_start, size => 1 << 11, type => 0x401, mntpoint => '' }, $o->{hds}, { force => 1, primaryOrExtended => 'Primary' });    
			} else {
				die "no free space for 1MB bootstrap";
			}
		}
	}

    if ($o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = 
	  fsedit::get_root_($o->{fstab}) ||
	  $o->ask_from_listf(_("Root Partition"),
			     _("What is the root partition (/) of your system?"),
			     \&partition_table_raw::description, 
			     [ install_any::find_root_parts($o->{fstab}, $o->{prefix}) ]) or die "setstep exitInstall\n";
	install_any::use_root_part($o->{fstab}, $p, $o->{prefix});
    } elsif ($::expert && ref($o) =~ /gtk/) {
        install_interactive::partition_with_diskdrake($o, $o->{hds});
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

    my @l = grep { !$_->{isMounted} && !$_->{isFormatted} && $_->{mntpoint} && (!isSwap($_) || $::expert) &&
		    (!isOtherAvailableFS($_) || $::expert || $_->{toFormat})
	       } @$fstab;
    $_->{toFormat} = 1 foreach grep { isSwap($_) && !$::expert } @$fstab;

    return if @l == 0 || !$::expert && 0 == grep { ! $_->{toFormat} } @l;

    my $name2label = sub { 
        sprintf("%s   %s", isSwap($_) ? type2name($_->{type}) : $_->{mntpoint},
			   isLoopback($_) ? $::expert && loopback::file($_) : partition_table_raw::description($_));
    };

    #- keep it temporary until the guy has accepted
    $_->{toFormatTmp} = $_->{toFormat} || $_->{toFormatUnsure} foreach @l;

    $o->ask_from_entries_refH_powered(
        { messages => _("Choose the partitions you want to format"),
          advanced_messages => _("Check bad blocks?"),
        },
        [ map { 
	    my $e = $_;
	    ({
	      text => $name2label->($e), type => 'bool',
	      val => \$e->{toFormatTmp}
	     }, if_(!isLoopback($_) && !isReiserfs($_), {
	      text => $name2label->($e), type => 'bool', advanced => 1, 
	      disabled => sub { !$e->{toFormatTmp} },
	      val => \$e->{toFormatCheck}
        })) } @l ]
    ) or die 'already displayed';
    #- ok now we can really set toFormat
    $_->{toFormat} = delete $_->{toFormatTmp} foreach @l;
}


sub formatMountPartitions {
    my ($o, $fstab) = @_;
    my $w;
    fs::formatMount_all($o->{raid}, $o->{fstab}, $o->{prefix}, sub {
	my ($part) = @_;
	$w ||= $o->wait_message('', _("Formatting partitions"));
	$w->set(isLoopback($part) ?
		_("Creating and formatting file %s", loopback::file($part)) :
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
    my ($o, $packages, $compssUsers, $first_time) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user if using a cdrom.
    $o->chooseCD($packages) if $o->{method} eq 'cdrom';

    my $availableC = install_steps::choosePackages(@_);
    my $individual = $::expert;

    require pkgs;

    my $min_size = pkgs::selectedSize($packages);
    $min_size < $availableC or die _("Your system has not enough space left for installation or upgrade (%d > %d)", $min_size, $availableC);

    my $min_mark = $::expert ? 3 : 4;
    my $def_mark = 4; #-TODO: was 59, 59 is for packages that need gl hw acceleration.

    my $b = pkgs::saveSelected($packages);
    pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $def_mark, 0);
    my $def_size = pkgs::selectedSize($packages) + 1; #- avoid division by zero.
    my $level = pkgs::setSelectedFromCompssList($packages, { map { $_ => 1 } map { @{$compssUsers->{$_}{flags}} } @{$o->{compssUsersSorted}} }, $min_mark, 0);
    my $max_size = pkgs::selectedSize($packages) + 1; #- avoid division by zero.
    pkgs::restoreSelected($b);

    $o->chooseGroups($packages, $compssUsers, $min_mark, \$individual, $max_size) if !$::corporate;

    my $size2install = min($availableC, do {
	my $max = round_up(min($max_size, $availableC) / sqr(1024), 100);
	
	if (1) {
	    if ($o->{isUpgrade}) {
		min($def_size, $max);
	    } else {
		my (@l);
		my @text = (__("Minimum (%dMB)"), __("Recommended (%dMB)"), __("Complete (%dMB)"));
		if ($o->{meta_class} eq 'desktop') {
		    @l = (300, 500, 800, 0);
		    $max > $l[2] or splice(@l, 2, 1);
		    $max > $l[1] or splice(@l, 1, 1);
		    $max > $l[0] or @l = $max;
		    $text[$#l] = __("Custom");
		} else {
		    @l = (300, 700, $max);
		    $l[2] > $l[1] + 200 or splice(@l, 1, 1); #- not worth proposing too alike stuff
		    $l[1] > $l[0] + 100 or splice(@l, 0, 1);
		}
		$o->set_help('empty');
#		$o->ask_from_listf('', _("Select the size you want to install"),
#				   sub { _ ($text[$_[0]], $_[0]) }, \@l, $l[1]) * sqr(1024);
		$max * sqr(1024);
	    }
	} else {
	    $o->chooseSizeToInstall($packages, $min_size, $def_size, $max_size, $availableC, $individual) || goto &choosePackages;
	}
    });
    if (!$size2install) { #- special case for desktop
	$o->chooseGroups($packages, $compssUsers, $min_mark) or goto &choosePackages;
	$size2install = $availableC;
    }

    ($o->{packages_}{ind}) =
      pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $min_mark, $size2install);

    $o->choosePackagesTree($packages) if $individual;
}

sub chooseSizeToInstall {
    my ($o, $packages, $min, $def, $max, $availableC) = @_;
    min($def, $availableC * 0.7);
}
sub choosePackagesTree {
    my ($o, $packages) = @_;

    $o->ask_many_from_list('', _("Choose the packages you want to install"),
			   {
			    list => [ #grep { pkgs::packageMedium($_)->{selected} } 
				      map { pkgs::packageByName($packages, $_) }
				      keys %{$packages->{names}} ],
			    value => \&pkgs::packageFlagSelected,
			    label => \&pkgs::packageName,
			    sort => 1,
			   });
}

sub chooseGroups {
    my ($o, $packages, $compssUsers, $min_level, $individual, $max_size) = @_;

    my $system_size = pkgs::selectedSize($packages);
    my $sizes = pkgs::computeGroupSize($packages, $min_level);
    my $compute_size = sub {
	my %flags; @flags{@_} = ();
	my $total_size;
	A: while (my ($k, $size) = each %$sizes) {
	    Or: foreach (split "\t", $k) {
		  foreach (split "&&") {
		      exists $flags{$_} or next Or;
		  }
		  $total_size += $size;
		  next A;
	      }
	  }
	int $total_size;
    };
    my @groups = @{$o->{compssUsersSorted}};
    my %val;
    foreach (@groups) {
	$val{$_} = ! grep { ! $o->{compssUsersChoice}{$_} } @{$compssUsers->{$_}{flags}};
    }
#    @groups = grep { $size{$_} = round_down($size{$_} / sqr(1024), 10) } @groups; #- don't display the empty or small one (eg: because all packages are below $min_level)
    my ($all, $size_text);
    my $update_size = sub { 
	my $size = $system_size + $compute_size->(map { @{$compssUsers->{$_}{flags}} } grep { $val{$_} } @groups);
	$size_text = _("Selected size %d%s", pkgs::correctSize($size / sqr(1024)), _("MB"));
    }; &$update_size;
    $o->ask_from_entries_refH('', _("Package Group Selection"), [
                           { val => \$size_text, type => 'label' },
			   (map {; {
			     help => translate($o->{compssUsers}{$_}{descr}),
			     val => \$val{$_},
			     type => 'bool',
			     icon => do {
				 my $f = "/usr/share/icons/" . ($o->{compssUsers}{$_}{icons} || 'default');
				 -e "$f.png" or $f .= "_section";
				 -e "$f.png" or $f = '/usr/share/icons/default_section';
				 "$f.png";
			     },
			     disabled => sub { $all },
			     text => translate($_) . sprintf(" (%d%s)", $compute_size->(@{$compssUsers->{$_}{flags}}) / sqr(1024), _("MB")),
			   } } @groups),
			   if_($o->{meta_class} eq 'desktop', { text => _("All"), val => \$all, type => 'bool' }),
			   if_($individual, { text => _("Individual package selection"), val => $individual, advanced => 1, type => 'bool' }),
			  ], changed => $update_size) or return;
    if ($all) {
	$o->{compssUsersChoice}{$_} = 1 foreach map { @{$compssUsers->{$_}{flags}} } @{$o->{compssUsersSorted}};
    } else {
	$o->{compssUsersChoice}{$_} = 0 foreach map { @{$compssUsers->{$_}{flags}} } grep { !$val{$_} } keys %val;
	$o->{compssUsersChoice}{$_} = 1 foreach map { @{$compssUsers->{$_}{flags}} } grep {  $val{$_} } keys %val;
    }
    1;
}

sub chooseCD {
    my ($o, $packages) = @_;
    my @mediums = grep { $_ != $install_any::boot_medium } pkgs::allMediums($packages);
    my @mediumsDescr = ();
    my %mediumsDescr = ();

    if (isCdNotEjectable()) {
	#- mono-cd in case of no ramdisk
	undef $packages->{mediums}{$_}{selected} foreach @mediums;
	log::l("low memory install, using single CD installation (as it is not ejectable)");
	return;
    }

    #- if no other medium available or a poor beginner, we are choosing for him!
    #- note first CD is always selected and should not be unselected!
    return if @mediums == () || !$::expert;

    #- build mediumDescr according to mediums, this avoid asking multiple times
    #- all the medium grouped together on only one CD.
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	exists $mediumsDescr{$descr} or push @mediumsDescr, $descr;
	$mediumsDescr{$descr} ||= $packages->{mediums}{$_}{selected};
    }

    $o->set_help('chooseCD');
    $o->ask_many_from_list('',
_("If you have all the CDs in the list below, click Ok.
If you have none of those CDs, click Cancel.
If only some CDs are missing, unselect them, then click Ok."),
			   {
			    list => \@mediumsDescr,
			    label => sub { _("Cd-Rom labeled \"%s\"", $_) },
			    ref => sub { \$mediumsDescr{$_} },
			   }) or do {
			       map { $mediumsDescr{$_} = 0 } @mediumsDescr; #- force unselection of other CDs.
			   };
    $o->set_help('choosePackages');

    #- restore true selection of medium (which may have been grouped together)
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	$packages->{mediums}{$_}{selected} = $mediumsDescr{$descr};
    }
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
    my $w = $o->wait_message('', _("Post-install configuration"));
    $o->SUPER::afterInstallPackages($o);
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o, $first_time) = @_;
    require netconnect;
    netconnect::main($o->{prefix}, $o->{netcnx} ||= {}, $o->{netc}, $o->{mouse}, $o, $o->{intf},
		     sub { $o->pkg_install(@_) }, $first_time, $o->{lang} eq "fr_FR" && $o->{keyboard} eq "fr");
}

#-configureNetworkIntf moved to network

#-configureNetworkNet moved to network
#------------------------------------------------------------------------------
#-pppConfig moved to any.pm
#------------------------------------------------------------------------------
sub installCrypto {
    my ($o) = @_;
    my $u = $o->{crypto} ||= {};
    
    $::expert and $o->hasNetwork or return;

    is_empty_hash_ref($u) and $o->ask_yesorno('', 
_("You have now the possibility to download software aimed for encryption.

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
USA")) || return;

    require crypto;
    eval {
      $u->{mirror} = $o->ask_from_listf('', 
					_("Choose a mirror from which to get the packages"), 
					\&crypto::mirror2text, 
					[ crypto::mirrors() ], 
					$u->{mirror});
    };
    return if $@;

    #- bring all interface up for installing crypto packages.
    install_interactive::upNetwork($o);

    my @packages = do {
      my $w = $o->wait_message('', _("Contacting the mirror to get the list of available packages"));
      crypto::getPackages($o->{prefix}, $o->{packages}, $u->{mirror}); #- make sure $o->{packages} is defined when testing
    };
    $u->{packages} = $o->ask_many_from_list('', _("Please choose the packages you want to install."), { list => \@packages, values => $u->{packages} }) or return;
    $o->pkg_install(@{$u->{packages}});

    #- stop interface using ppp only.
    install_interactive::downNetwork($o, 'pppOnly');
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o, $clicked) = @_;

    require timezone;
    $o->{timezone}{timezone} = $o->ask_from_treelist('', _("Which is your timezone?"), '/', [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone});
    $o->set_help('configureTimezoneGMT');
    $o->{timezone}{UTC} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{UTC}) if $::expert || $clicked;
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

    if ($first_time) {
	#- auto-detection
	$o->configurePrinter(0) if !$::expert;
	install_any::preConfigureTimezone($o);
    }
    my $mouse_name;
    my $format_mouse = sub { $mouse_name = translate($o->{mouse}{type}) . ' ' . translate($o->{mouse}{name}) };
    &$format_mouse;

    $o->ask_from_entries_refH('', _("Summary"),
    [
{ label => _("Mouse"), val => \$mouse_name, clicked => sub { $o->selectMouse(1); &$format_mouse },
{ label => _("Keyboard"), val => \$o->{keyboard}, clicked => sub { $o->selectKeyboard(1) }, format => sub { translate(keyboard::keyboard2text($_[0])) } } },
{ label => _("Timezone"), val => \$o->{timezone}{timezone}, clicked => sub { $o->configureTimezone(1) } },
{ label => _("Printer"), val => \$o->{printer}{mode}, clicked => sub { $o->configurePrinter(1) }, format => sub { $_[0] || _("No printer") } },
    (map {
{ label => _("ISDN card"), val => $_->{description}, clicked => sub { $o->configureNetwork } }
     } grep { $_->{driver} eq 'hisax' } detect_devices::probeall()),
    (map { 
{ label => _("Sound card"), val => $_->{description} } 
     } modules::get_that_type('sound')),
    (map {
{ label => _("TV card"), val => $_->{description} } 
     } grep { $_->{driver} eq 'bttv' } detect_devices::probeall()),
]);
}

#------------------------------------------------------------------------------
sub configurePrinter {
    my ($o, $clicked) = @_;
    $::corporate && !$clicked and return;

    require printer;
    require printerdrake;

    if (!$::expert && !$clicked) {
        printerdrake::auto_detect($o) or return;
    }

    my $printer = $o->{printer} ||= {};

    #- bring interface up for installing ethernet packages but avoid ppp by default,
    #- else the guy know what he is doing...
    #install_interactive::upNetwork($o, 'pppAvoided');

    #- take default configuration, this include choosing the right system
    #- currently used by the system.
    eval { add2hash($printer, printer::getinfo($o->{prefix})) };

    #- figure out what printing system to use, currently are suported cups and lpr,
    #- in case this has not be detected above.
    $::expert or $printer->{mode} ||= 'CUPS';
    if ($::expert || !$printer->{mode}) {
	$o->set_help('configurePrinterSystem');
	$o->ask_from_entries_refH_powered(
              {
	       messages => _("Which printing system do you want to use?"),
	       }, [ { val => \$printer->{mode}, list => [ 'CUPS', 'lpr' ] } ]
        ) or $printer->{mode} = undef, $printer->{want} = undef, return;
	$printer->{want} = 1;
	$o->set_help('configurePrinter');
    }

    $printer->{PAPERSIZE} = $o->{lang} eq 'en' ? 'letter' : 'a4';
    printerdrake::main($printer, $o, sub { $o->pkg_install(@_) }, sub { install_interactive::upNetwork($o, 'pppAvoided') });

    $o->pkg_install_if_requires_satisfied('xpp', 'qtcups', 'kups') if %{$printer->{configured} || {}} == ();
}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    my $nis = $o->{authentication}{NIS};
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $::isInstall and $o->set_help("setRootPassword", 
				  if_($::expert, "setRootPasswordMd5"),
				  if_($::expert, "setRootPasswordNIS"));

    $o->ask_from_entries_refH_powered(
        {
	 title => _("Set root password"), 
	 messages => _("Set root password"),
	 cancel => ($o->{security} <= 2 && !$::corporate ? _("No password") : ''),
	 callbacks => { 
	     complete => sub {
		 $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,1);
		 length $sup->{password} < 2 * $o->{security}
		   and $o->ask_warn('', _("This password is too simple (must be at least %d characters long)", 2 * $o->{security})), return (1,0);
		 return 0
        } } }, [
{ label => _("Password"), val => \$sup->{password},  hidden => 1 },
{ label => _("Password (again)"), val => \$sup->{password2}, hidden => 1 },
  if_($::expert,
{ label => _("Use NIS"), val => \$nis, type => 'bool', text => _("yellow pages") },
  ),
			 ]) or return;

    if ($nis) { $o->ask_from_entries_refH('',
				     _("Authentification NIS"),
				     [ { label => _("NIS Domain"), val => \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}) },
				       { label => _("NIS Server"), val => \$o->{authentication}{NIS}, list => ["broadcast"], not_edit => 0 },
				     ]); } else { $o->{authentication}{NIS} = ''; }
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
    install_steps::addUser($o);
}

#    any::get_autologin($o->{prefix}, $o);



#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time) = @_;

    return if $first_time && !$::expert;

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
	my @l = detect_devices::floppies();
	$o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
	$o->{mkbootdisk} or return;
    } else {
	my @l = detect_devices::floppies();
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
failures. Would you like to create a bootdisk for your system?")), 
			    $o->{mkbootdisk}) or return $o->{mkbootdisk} = '';
	    $o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
	} else {
	    @l or die _("Sorry, no floppy drive available");

	    $o->ask_from_entries_refH_powered(
              {
	       messages => _("Choose the floppy drive you want to use to make the bootdisk"),
	      }, [ { val => \$o->{mkbootdisk}, list => \@l, format => sub { $l{$_[0]} || $_[0] } } ]
            ) or return;
        }
        $o->ask_warn('', _("Insert a floppy in drive %s", $l{$o->{mkbootdisk}} || $o->{mkbootdisk}));
    }

    my $w = $o->wait_message('', _("Creating bootdisk"));
    install_steps::createBootdisk($o);
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    my $w = $o->wait_message('', _("Preparing bootloader"));
    $o->set_help('empty');
    $o->SUPER::setupBootloaderBefore($o);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($o, $more) = @_;
    if (arch() =~ /^alpha/) {
	$o->ask_yesorno('', _("Do you want to use aboot?"), 1) or return;
	catch_cdie { $o->SUPER::setupBootloader } sub {
	    $o->ask_yesorno('', 
_("Error installing aboot, 
try to force installation even if that destroys the first partition?"));
	};
    } else {
	any::setupBootloader($o, $o->{bootloader}, $o->{hds}, $o->{fstab}, $o->{security}, $o->{prefix}, $more) or return;

	eval { $o->SUPER::setupBootloader };
	if ($@) {
	    $o->ask_warn('', 
			 [ _("Installation of bootloader failed. The following error occured:"),
			   grep { !/^Warning:/ } cat_("$o->{prefix}/tmp/.error") ]);
	    unlink "$o->{prefix}/tmp/.error";
	    die "already displayed";
	}
    }
}

#- deprecated
sub __deprecated__miscellaneous {
    return; 

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

    my $u = $o->{miscellaneous} ||= {};
    my $s = $o->{security};

    install_interactive::tellAboutProprietaryModules($o) unless $clicked;

    add2hash_ $o, { useSupermount => $s < 4 && arch() !~ /^sparc/ };
    $s = $l{$s} || $s;

    $::expert || $clicked and $o->ask_from_entries_refH('',
	_("Miscellaneous questions"), [
{ label => _("Choose security level"), val => \$s, list => [ map { $l{$_} } ikeys %l ] },
     ], complete => sub {
	    my %m = reverse %l; $ENV{SECURE_LEVEL} = $o->{security} = $m{$s};
	    $o->{useSupermount} && $o->{security} > 3 and $o->ask_warn('', _("Can't use supermount in high security level")), return 1;
	    $o->{security} == 5 and $o->ask_okcancel('',
_("beware: IN THIS SECURITY LEVEL, ROOT LOGIN AT CONSOLE IS NOT ALLOWED!
If you want to be root, you have to login as a user and then use \"su\".
More generally, do not expect to use your machine for anything but as a server.
You have been warned.")) || return;

	    #- message below kept in case it is of any use again. (otherwise removed from po and pablo is not happy ;p)
_("Be carefull, having numlock enabled causes a lot of keystrokes to
give digits instead of normal letters (eg: pressing `p' gives `6')");
	    0; }
    ) || return;

    install_steps::miscellaneous($o);
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o, $clicked) = @_;
    $o->configureXBefore;

    #- strange, xfs must not be started twice...
    #- trying to stop and restart it does nothing good too...
    my $xfs_started if 0;
    run_program::rooted($o->{prefix}, "/etc/rc.d/init.d/xfs", "start") unless $::live || $xfs_started;
    $xfs_started = 1;

    require Xconfigurator;
    { local $::testing = 0; #- unset testing
      local $::auto = !$::expert && !$clicked;

      Xconfigurator::main($o->{prefix}, $o->{X}, $o, $o->{allowFB}, sub {
	  $o->pkg_install(@_);
      });
    }
    $o->configureXAfter;
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy {
    my ($o, $replay) = @_;

    my $floppy = detect_devices::floppy();
#+    $o->ask_yesorno('', 
#+_("Do you want to generate an auto install floppy for linux replication?"), $floppy) or return;

    $o->ask_okcancel('', _("Insert a blank floppy in drive %s", $floppy), 1) or return;

    my $dev = devices::make($floppy);

    my $image = $o->{pcmcia} ? "pcmcia" :
      ${{ hd => 'hd', cdrom => 'cdrom', ftp => 'network', nfs => 'network', http => 'network' }}{$o->{method}};

    if (arch() =~ /sparc/) {
	$image .= arch() =~ /sparc64/ && "64"; #- for sparc64 there are a specific set of image.

	my $imagefile = "$o->{prefix}/tmp/autoinst.img";
	my $mountdir = "$o->{prefix}/tmp/mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $workdir = "$o->{prefix}/tmp/work"; -d $workdir or rmdir $workdir;

	my $w = $o->wait_message('', _("Creating auto install floppy"));
        install_any::getAndSaveFile("images/$image.img", $imagefile) or log::l("failed to write $dev"), return;
        devices::make($_) foreach qw(/dev/loop6 /dev/ram);

	require commands;
        run_program::run("losetup", "/dev/loop6", $imagefile);
        fs::mount("/dev/loop6", $mountdir, "romfs", 'readonly');
        commands::cp("-f", $mountdir, $workdir);
        fs::umount($mountdir);
        run_program::run("losetup", "-d", "/dev/loop6");

	substInFile { s/timeout.*//; s/^(\s*append\s*=\s*\".*)\"/$1 kickstart=floppy\"/ } "$workdir/silo.conf"; #" for po
#-TODO	output "$workdir/ks.cfg", install_any::generate_ks_cfg($o);
	output "$workdir/boot.msg", "\n7m",
"!! If you press enter, an auto-install is going to start.
    ALL data on this computer is going to be lost,
    including any Windows partitions !!
", "7m\n";

	local $o->{partitioning}{clearall} = 1;
	install_any::g_auto_install("$workdir/auto_inst.cfg");

        run_program::run("genromfs", "-d", $workdir, "-f", "/dev/ram", "-A", "2048,/..", "-a", "512", "-V", "DrakX autoinst");
        fs::mount("/dev/ram", $mountdir, 'romfs', 0);
        run_program::run("silo", "-r", $mountdir, "-F", "-i", "/fd.b", "-b", "/second.b", "-C", "/silo.conf");
        fs::umount($mountdir);
        commands::dd("if=/dev/ram", "of=$dev", "bs=1440", "count=1024");

        commands::rm("-rf", $workdir, $mountdir, $imagefile);
    } else {
	my $param = 'kickstart=floppy ' . install_any::generate_automatic_stage1_params($o);
	{
	    my $w = $o->wait_message('', _("Creating auto install floppy"));
	    install_any::getAndSaveFile("images/$image.img", $dev) or log::l("failed to write $dev"), return;
	}
        fs::mount($dev, "/floppy", "vfat", 0);
	substInFile { 
	    s/timeout.*/$replay ? 'timeout 1' : ''/e;
	    s/^(\s*append)/$1 $param/ 
	} "/floppy/syslinux.cfg";

	unlink "/floppy/help.msg";
	output "/floppy/boot.msg", "\n0c",
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost !!
", "07\n" if !$replay;

	local $o->{partitioning}{clearall} = !$replay;
	install_any::g_auto_install("/floppy/auto_inst.cfg", $replay);

	fs::umount("/floppy");
    }
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' unless $alldone || $o->ask_yesorno('', 
_("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_steps::exitInstall($o);

    $o->exit unless $alldone;

    $o->ask_from_entries_refH_powered_no_check(
	{
	 messages =>
_("Congratulations, installation is complete.
Remove the boot media and press return to reboot.

For information on fixes which are available for this release of Linux-Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.

Information on configuring your system is available in the post
install chapter of the Official Linux-Mandrake User's Guide.")
	},
	[
	 if_($::expert,
	     { val => \ (my $t1 = _("Generate auto install floppy")), clicked => sub {
		   my $t = $o->ask_from_list_('', 
_("The auto install can be fully automated if wanted,
in that case it will take over the hard drive!!
(this is meant for installing on another box).

You may prefer to replay the installation.
"), [ _("Replay"), _("Automated") ]);
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

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
