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
use partition_table_raw;
use install_steps;
use install_interactive;
use install_any;
use detect_devices;
use netconnect;
use run_program;
use commands;
use devices;
use fsedit;
use network;
use raid;
use mouse;
use modules;
use lang;
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

    $o->{lang} = $o->ask_from_listf("Language",
				    _("Please, choose a language to use."),
				    \&lang::lang2text,
				    [ lang::list() ],
				    $o->{lang});
    install_steps::selectLanguage($o);

    $o->ask_warn('', 
"If you see this message it is because you choose a language for which
DrakX does not include a translation yet; however the fact that it is
listed means there is some support for it anyway. That is, once GNU/Linux
will be installed, you will be able to at least read and write in that
language; and possibly more (various fonts, spell checkers, various programs
translated etc. that varies from language to language).") if $o->{lang} !~ /^en/ && translate("_I18N_");

#-    $o->{useless_thing_accepted} = $o->ask_from_list_('', 
#-"Warning no warranty", 
#-			 [ __("Accept"), __("Refuse") ], "Accept") eq "Accept" or _exit(1) unless $o->{useless_thing_accepted};
}
#------------------------------------------------------------------------------
sub selectKeyboard($) {
    my ($o, $clicked) = @_;
    if (!$::beginner || $clicked) {
	$o->{keyboard} = $o->ask_from_listf_(_("Keyboard"),
					     _("Please, choose your keyboard layout."),
					     \&keyboard::keyboard2text,
					     [ keyboard::xmodmaps() ],
					     $o->{keyboard});
	delete $o->{keyboard_unsafe};
    }
    if ($::expert && ref($o) !~ /newt/) { #- newt is buggy with big windows :-(
	my %langs; $langs{$_} = 1 foreach @{$o->{langs}};
	$o->ask_many_from_list_ref('', 
		_("You can choose other languages that will be available after install"),
		[ (map { lang::lang2text($_) } lang::list()), 'All' ], [ map { \$langs{$_} } lang::list(), 'all' ] ) or goto &selectKeyboard;
	$o->{langs} = $langs{all} ? [ 'all' ] : [ grep { $langs{$_} } keys %langs ];
    }
    install_steps::selectKeyboard($o);
}
#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $verif->($o->ask_from_list(_("Install Class"), _("Which installation class do you want?"), $l, $def));

    $o->ask_from_list_(_("Install/Rescue"), _("Is this an install or a rescue?"), $l2, $def2);
}

#------------------------------------------------------------------------------
sub selectInstallClass($@) {
    my ($o, @classes) = @_;

    my %c = my @c = (
      $::corporate ? () : (
	_("Recommended") => "beginner",
      ),
	_("Customized")  => "specific",
	_("Expert")	 => "expert",
    );

    $o->set_help('selectInstallClassCorpo') if $::corporate;

    my $verifInstallClass = sub {
	$::beginner = $c{$_[0]} eq "beginner";
	$::expert   = $c{$_[0]} eq "expert" &&
	  $o->ask_from_list_('',
_("Are you sure you are an expert? 
You will be allowed to make powerful but dangerous things here.

You will be asked questions such as: ``Use shadow file for passwords?'',
are you ready to answer that kind of questions?"), 
			 [ _("Customized"), _("Expert") ]) ne "Customized";
    };      

    $o->{isUpgrade} = $o->selectInstallClass1($verifInstallClass,
					      first(list2kv(@c)), ${{reverse %c}}{$::beginner ? "beginner" : $::expert ? "expert" : "specific"},
					      [ __("Install"), __("Rescue") ], $o->{isUpgrade} ? "Rescue" : "Install") eq "Rescue";

    if ($::corporate || $::beginner) {
	delete $o->{installClass};
    } else {
	my %c = (
		 normal    => _("Workstation"),
		 developer => _("Development"),
		 server    => _("Server"),
		);
	$o->set_help('selectInstallClass2');
	$o->{installClass} = $o->ask_from_listf(_("Install Class"),
						_("Which usage is your system used for ?"),
						sub { $c{$_[0]} },
						[ keys %c ],
						$o->{installClass});
    }
    install_steps::selectInstallClass($o);
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    $force ||= $o->{mouse}{unsafe} || $::expert;
    
    $o->{mouse} = $o->ask_from_listf_('', _("Please, choose the type of your mouse."), 
				      sub { $_[0]{FULLNAME} }, [ mouse::list ], $o->{mouse}) if $force;
    $o->{mouse}{XEMU3} = 'yes' if $o->{mouse}{nbuttons} < 3;

    if ($force && $o->{mouse}{device} eq "ttyS") {
	$o->set_help('selectSerialPort');
	$o->{mouse}{device} = 
	  $o->ask_from_listf(_("Mouse Port"),
			    _("Please choose on which serial port your mouse is connected to."),
			    \&mouse::serial_port2text,
			    [ mouse::serial_ports ]);
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
    my ($o) = @_;
    { 
	my $w = $o->wait_message(_("IDE"), _("Configuring IDE"));
	modules::load_ide();
    }
    any::setup_thiskind($o, 'scsi|disk', $_[1], $_[2], $o->{pcmcia});
}

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;
    my @fstab = grep { isTrueFS($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
    die _("no available partitions") if @fstab == 0;


    if (@fstab == 1) {
	$fstab[0]{mntpoint} = '/';
    } else {
	install_any::suggest_mount_points($o->{hds}, $o->{prefix}, 'uniq');

	log::l("default mntpoint $_->{mntpoint}") foreach @fstab;

	$o->ask_from_entries_refH('', 
				  _("Choose the mount points"),
				  [ map { partition_table_raw::description($_) => 
				            { val => \$_->{mntpoint}, not_edit => 0, list => [ '', fsedit::suggestions_mntpoint([]) ] }
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


    if ($o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = 
	  fsedit::get_root($o->{fstab}) ||
	  $o->ask_from_listf(_("Root Partition"),
			     _("What is the root partition (/) of your system?"),
			     \&partition_table_raw::description, 
			     [ install_any::find_root_parts($o->{hds}, $o->{prefix}) ]) or die "setstep exitInstall\n";
	install_any::use_root_part($o->{fstab}, $p, $o->{prefix});
    } elsif ($::expert) {
        install_interactive::partition_with_diskdrake($o, $o->{hds});
    } else {
        install_interactive::partitionWizard($o);
    }
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

    my @l = grep { !$_->{isFormatted} && $_->{mntpoint} && !($::beginner && isSwap($_)) &&
		    (!isOtherAvailableFS($_) || $::expert || $_->{toFormat})
	       } @$fstab;
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
    @l = grep { $_->{toFormat} && !isLoopback($_) && !isReiserfs($_) } @l;
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
    my ($o, $packages, $compss, $compssUsers, $compssUsersSorted, $first_time) = @_;

    #- this is done at the very beginning to take into account
    #- selection of CD by user if using a cdrom.
    $o->chooseCD($packages) if $o->{method} eq 'cdrom';

    my $availableC = install_steps::choosePackages(@_);
    my $individual = $::expert;

    require pkgs;

    my $min_size = pkgs::selectedSize($packages);
    $min_size < $availableC or die _("Your system has not enough space left for installation or upgrade (%d > %d)", $min_size, $availableC);

    $o->chooseGroups($packages, $compssUsers, $compssUsersSorted, \$individual) unless $::beginner || $::corporate;

    #- avoid reselection of package if individual selection is requested and this is not the first time.
    if (1 || $first_time || !$individual) {
	my $min_mark = $::beginner ? 10 : $::expert ? 0 : 1;
	my ($size, $level) = pkgs::fakeSetSelectedFromCompssList($o->{compssListLevels}, $packages, $min_mark, 0, $o->{installClass});
	my $max_size = 1 + $size; #- avoid division by zero.
	
	my $size2install = min($availableC, do {
	    if ($::beginner) {
		my @l = (300, 700, round_up(min($max_size, $availableC) / sqr(1024), 100));
		$l[2] > $l[1] + 200 or splice(@l, 1, 1); #- not worth proposing too alike stuff
		$l[1] > $l[0] + 100 or splice(@l, 0, 1);
		my @text = (__("Minimum (%dMB)"), __("Recommended (%dMB)"), __("Complete (%dMB)"));
		$o->ask_from_listf('', _("Select the size you want to install"), sub { _ ($text[$_[1]], $_[0]) }, \@l) * sqr(1024);
	    } else {
		$o->chooseSizeToInstall($packages, $min_size, $max_size, $availableC, $individual) || goto &choosePackages;
	    }
	});
	($o->{packages_}{ind}) =
	  pkgs::setSelectedFromCompssList($o->{compssListLevels}, $packages, $min_mark, $size2install, $o->{installClass});
    }

    $o->choosePackagesTree($packages, $compss) if $individual;
}

sub chooseSizeToInstall {
    my ($o, $packages, $min, $max, $availableC) = @_;
    $availableC * 0.7;
}
sub choosePackagesTree {}

sub chooseGroups {
    my ($o, $packages, $compssUsers, $compssUsersSorted, $individual) = @_;

    $o->ask_many_from_list_ref('',
			       _("Package Group Selection"),
			       [ @$compssUsersSorted, _("Miscellaneous") ],
			       [ map { \$o->{compssUsersChoice}{$_} } @$compssUsersSorted, "Miscellaneous" ],
			       [  _("Individual package selection") ], [ $individual ],			       
			       ) or goto &chooseGroups;

    unless ($o->{compssUsersChoice}{Miscellaneous}) {
	my %l;
	$l{@{$compssUsers->{$_}}} = () foreach @$compssUsersSorted;
	exists $l{$_} or pkgs::packageSetFlagSkip($_, 1) foreach values %{$packages->[0]};
    }
    foreach (@$compssUsersSorted) {
	$o->{compssUsersChoice}{$_} or pkgs::skipSetWithProvides($packages, @{$compssUsers->{$_}});
    }
    foreach (@$compssUsersSorted) {
	$o->{compssUsersChoice}{$_} or next;
	foreach (@{$compssUsers->{$_}}) {
	    pkgs::packageSetFlagUnskip($_, 1);
	    pkgs::packageSetFlagSkip($_, 0);
	}
    }
}

sub chooseCD {
    my ($o, $packages) = @_;
    my @mediums = grep { $_ > 1 } pkgs::allMediums($packages);
    my @mediumsDescr = ();
    my %mediumsDescr = ();

    unless (grep { /ram3/ } cat_("/proc/mounts")) {
	#- mono-cd in case of no ramdisk
	undef $packages->[2]{$_}{selected} foreach @mediums;
	return;
    }

    #- if no other medium available or a poor beginner, we are choosing for him!
    #- note first CD is always selected and should not be unselected!
    return if scalar(@mediums) == 0 || $::beginner;

    #- build mediumDescr according to mediums, this avoid asking multiple times
    #- all the medium grouped together on only one CD.
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	exists $mediumsDescr{$descr} or push @mediumsDescr, $descr;
	$mediumsDescr{$descr} ||= $packages->[2]{$_}{selected};
    }

    $o->set_help('chooseCD');
    $o->ask_many_from_list_ref('',
			       _("If you have all the CDs in the list below, click Ok.
If you have none of those CDs, click Cancel.
If only some CDs are missing, unselect them, then click Ok."),
			       [ map { _("Cd-Rom labeled \"%s\"", $_) } @mediumsDescr ],
			       [ map { \$mediumsDescr{$_} } @mediumsDescr ]
			      ) or do {
				  map { $mediumsDescr{$_} = 0 } @mediumsDescr; #- force unselection of other CDs.
			      };
    $o->set_help('choosePackages');

    #- restore true selection of medium (which may have been grouped together)
    foreach (@mediums) {
	my $descr = pkgs::mediumDescr($packages, $_);
	$packages->[2]{$_}{selected} = $mediumsDescr{$descr};
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
    $o->{netcnx}||={};
    netconnect::net_connect($o->{prefix}, $o->{netcnx}, $o->{netc}, $o->{modem}, $o->{mouse},  $o, $o->{pcmcia}, $o->{intf}, $first_time);
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
      $u->{mirror} = $o->ask_from_listf('', _("Choose a mirror from which to get the packages"), \&crypto::mirror2text, [ crypto::mirrors() ], $u->{mirror});
    };
    return if $@;

    #- bring all interface up for installing crypto packages.
    install_interactive::upNetwork($o);

    my @packages = do {
      my $w = $o->wait_message('', _("Contacting the mirror to get the list of available packages"));
      crypto::getPackages($o->{prefix}, $o->{packages}, $u->{mirror}); #- make sure $o->{packages} is defined when testing
    };
    my %h; $h{$_} = 1 foreach @{$u->{packages} || []};
    $o->ask_many_from_list_ref('', _("Please choose the packages you want to install."), 
			       \@packages, [ map { \$h{$_} } @packages ]) or return;
    $o->pkg_install(@{$u->{packages} = [ grep { $h{$_} } @packages ]});

    #- stop interface using ppp only.
    install_interactive::downNetwork($o, 'pppOnly');
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o, $f, $clicked) = @_;

    require timezone;
    $o->{timezone}{timezone} = $o->ask_from_treelist('', _("Which is your timezone?"), '/', [ timezone::getTimeZones($::g_auto_install ? '' : $o->{prefix}) ], $o->{timezone}{timezone});
    $o->{timezone}{UTC} = $o->ask_yesorno('', _("Is your hardware clock set to GMT?"), $o->{timezone}{UTC}) if $::expert || $clicked;
    install_steps::configureTimezone($o, $f);
}

#------------------------------------------------------------------------------
sub configureServices { 
    my ($o) = @_;
    require services;
    $o->{services} = services::ask($o, $o->{prefix});
    install_steps::configureServices($o);
}

#------------------------------------------------------------------------------
sub configurePrinter {
    my ($o, $clicked) = @_;

    $::corporate and return;

    require printer;
    require printerdrake;

    if ($::beginner && !$clicked) {
        printerdrake::auto_detect($o) or return;
    }

    #- bring interface up for installing ethernet packages but avoid ppp by default,
    #- else the guy know what he is doing...
    #install_interactive::upNetwork($o, 'pppAvoided');

    #- take default configuration, this include choosing the right system
    #- currently used by the system.
    eval { add2hash($o->{printer} ||= {}, printer::getinfo($o->{prefix})) };

    #- figure out what printing system to use, currently are suported cups and lpr,
    #- in case this has not be detected above.
    $::beginner and $o->{printer}{mode} ||= 'cups'; #'lpr';
    if (!$o->{printer}{mode}) {
	$o->{printer}{mode} = $o->ask_from_list_([''], _("What printing system do you want to use?"),
						 [ 'cups', 'lpr', __("Cancel") ],
						);
	$o->{printer}{want} = $o->{printer}{mode} ne 'Cancel';
	$o->{printer}{want} or $o->{printer}{mode} = undef, return;
    }

    $o->{printer}{PAPERSIZE} = $o->{lang} eq 'en' ? 'letter' : 'a4';
    printerdrake::main($o->{printer}, $o, sub { $o->pkg_install(@_) }, sub { install_interactive::upNetwork($o, 'pppAvoided') });

    $o->pkg_install_if_requires_satisfied('xpp', 'kups');
}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o, $clicked) = @_;
    my $sup = $o->{superuser} ||= {};
    my $nis = $o->{authentication}{NIS};
    $sup->{password2} ||= $sup->{password} ||= "";

    return if $o->{security} < 1 && !$clicked;

    $o->set_help("setRootPassword", 
		 $o->{installClass} =~ "server" || $::expert ? "setRootPasswordMd5" : (),
		 $::beginner ? () : "setRootPasswordNIS");

    $o->ask_from_entries_refH([_("Set root password"), _("Ok"), $o->{security} > 2 || $::corporate ? () : _("No password")],
			 [ _("Set root password"), "\n" ], [
_("Password") => { val => \$sup->{password},  hidden => 1 },
_("Password (again)") => { val => \$sup->{password2}, hidden => 1 },
  $o->{installClass} eq "server" || $::expert ? (
_("Use shadow file") => { val => \$o->{authentication}{shadow}, type => 'bool', text => _("shadow") },
_("Use MD5 passwords") => { val => \$o->{authentication}{md5}, type => 'bool', text => _("MD5") },
  ) : (), $::beginner ? () : (
_("Use NIS") => { val => \$nis, type => 'bool', text => _("yellow pages") },
  )
			 ],
			 complete => sub {
			     $sup->{password} eq $sup->{password2} or $o->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,1);
			     length $sup->{password} < 2 * $o->{security}
			       and $o->ask_warn('', _("This password is too simple (must be at least %d characters long)", 2 * $o->{security})), return (1,0);
			     return 0
			 }
    ) or return;

    $o->{authentication}{NIS} &&= $nis;
    $o->ask_from_entries_ref('',
			     _("Authentification NIS"),
			     [ _("NIS Domain"), _("NIS Server") ],
			     [ \ ($o->{netc}{NISDOMAIN} ||= $o->{netc}{DOMAINNAME}),
			       { val => \$o->{authentication}{NIS}, list => ["broadcast"] },
			     ]) if $nis;
    install_steps::setRootPassword($o);
}

#------------------------------------------------------------------------------
#-addUser
#------------------------------------------------------------------------------
sub addUser {
    my ($o, $clicked) = @_;
    my $u = $o->{user} ||= {};
    if ($o->{security} < 1) {
	add2hash_($u, { name => "mandrake", password => "mandrake", realname => "default", icon => 'automagic' });
	$o->{users} ||= [ $u ];
    }
    $u->{password2} ||= $u->{password} ||= "";
    $u->{shell} ||= "/bin/bash";
    my @fields = qw(realname name password password2);
    my @shells = map { chomp; $_ } cat_("$o->{prefix}/etc/shells");

    if (($o->{security} >= 1 || $clicked)) {
	$u->{icon} = translate($u->{icon});
	if ($o->ask_from_entries_refH(
        [ _("Add user"), _("Accept user"), $o->{security} >= 4 && !@{$o->{users}} ? () : _("Done") ],
        _("Enter a user\n%s", $o->{users} ? _("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @{$o->{users}})) : ''),
        [ 
	 _("Real name") => \$u->{realname},
	 _("User name") => \$u->{name},
	   $o->{security} < 2 ? () : (
         _("Password") => {val => \$u->{password}, hidden => 1},
         _("Password (again)") => {val => \$u->{password2}, hidden => 1},
	   ), $::beginner ? () : (
         _("Shell") => {val => \$u->{shell}, list => [ any::shells($o->{prefix}) ], not_edit => !$::expert} 
	   ), $o->{security} > 3 ? () : (
	 _("Icon") => {val => \$u->{icon}, list => [ any::facesnames() ], icon2f => sub { any::face2xpm($_[0], $o->{prefix}) } },
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
	    goto &addUser;
	}
    }
    install_steps::addUser($o);
}




#------------------------------------------------------------------------------
sub createBootdisk {
    my ($o, $first_time) = @_;

    return if $first_time && $::beginner || $o->{lnx4win};

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
	    $o->ask_yesorno('',
			    _("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
LILO (or grub) on your system, or another operating system removes LILO, or LILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?"), 
			    $o->{mkbootdisk}) or return $o->{mkbootdisk} = '';
	    $o->{mkbootdisk} = $l[0] if !$o->{mkbootdisk} || $o->{mkbootdisk} eq "1";
	} else {
	    @l or die _("Sorry, no floppy drive available");

	    $o->{mkbootdisk} = $o->ask_from_listf('',
						  _("Choose the floppy drive you want to use to make the bootdisk"),
						  sub { $l{$_[0]} || $_[0] },
						  [ @l, "Skip" ], 
						  $o->{mkbootdisk});
	    return $o->{mkbootdisk} = '' if $o->{mkbootdisk} eq 'Skip';
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
	$o->{lnx4win} or any::setupBootloader($o, $o->{bootloader}, $o->{hds}, $o->{fstab}, $o->{security}, $o->{prefix}, $more) or return;

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

#------------------------------------------------------------------------------
#- miscellaneousNetwork moved to network.pm
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

    add2hash_ $o, { useSupermount => $s < 4 && arch() !~ /^sparc/ };
    $s = $l{$s} || $s;

    !$::beginner || $clicked and $o->ask_from_entries_refH('',
	_("Miscellaneous questions"), [
_("Use hard drive optimisations?") => { val => \$u->{HDPARM}, type => 'bool', text => _("(may cause data corruption)") },
_("Choose security level") => { val => \$s, list => [ map { $l{$_} } ikeys %l ], not_edit => 1 },
_("Precise RAM size if needed (found %d MB)", availableRam / 1024 + 3) => \$u->{memsize}, #- add three for correction.
arch() !~ /^sparc/ ? (
_("Removable media automounting") => { val => \$o->{useSupermount}, type => 'bool', text => 'supermount' }, ) : (),
     $::expert ? (
_("Clean /tmp at each boot") => { val => \$u->{CLEAN_TMP}, type => 'bool' },
     ) : (),
     $o->{pcmcia} && $::expert ? (
_("Enable multi profiles") => { val => \$u->{profiles}, type => 'bool' },
     ) : (
_("Enable num lock at startup") => { val => \$u->{numlock}, type => 'bool' },
     ),
     ], complete => sub {
	    !$u->{memsize} || $u->{memsize} =~ s/^(\d+)M?$/$1M/i or $o->ask_warn('', _("Give the ram size in MB")), return 1;
	    my %m = reverse %l; $ENV{SECURE_LEVEL} = $o->{security} = $m{$s};
	    $o->{useSupermount} && $o->{security} > 3 and $o->ask_warn('', _("Can't use supermount in high security level")), return 1;
	    $o->{security} == 5 and $o->ask_okcancel('',
_("beware: IN THIS SECURITY LEVEL, ROOT LOGIN AT CONSOLE IS NOT ALLOWED!
If you want to be root, you have to login as a user and then use \"su\".
More generally, do not expect to use your machine for anything but as a server.
You have been warned.")) || return;
	    $u->{numlock} && $o->{pcmcia} and $o->ask_okcancel('',
_("Be carefull, having numlock enabled causes a lot of keystrokes to
give digits instead of normal letters (eg: pressing `p' gives `6')")) || return;
	    0; }
    ) || return;
}

#------------------------------------------------------------------------------
sub configureX {
    my ($o) = @_;
    $o->configureXBefore;

    require Xconfig;
    require Xconfigurator;
    #- by default do not use existing configuration, so new card will be detected.
    if ($o->{isUpgrade} && -r "$o->{prefix}/etc/X11/XF86Config") {
	if ($::beginner || $o->ask_yesorno('', _("Use existing configuration for X11?"), 1)) {
	    Xconfig::getinfoFromXF86Config($o->{X}, $o->{prefix});
	}
    }
    $::force_xf3 = $::force_xf3; #- for no warning
    $::force_xf3 = $o->ask_yesorno('', 
_("DrakX will generate config files for both XFree 3.3 and XFree 4.0.
By default, the 4.0 server is used unless your card is not supported.

Do you want to keep XFree 3.3?"), 0) if $::expert;

    #- strange, xfs must not be started twice...
    #- trying to stop and restart it does nothing good too...
    my $xfs_started if 0;
    run_program::rooted($o->{prefix}, "/etc/rc.d/init.d/xfs", "start") unless $xfs_started;
    $xfs_started = 1;

    { local $::testing = 0; #- unset testing
      local $::auto = $::beginner;

      Xconfigurator::main($o->{prefix}, $o->{X}, $o, $o->{allowFB}, bool($o->{pcmcia}), sub {
	  my ($server, @l) = @_;
	  $o->pkg_install("XFree86-$server", @l);
      });
    }
    $o->configureXAfter;
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy($) {
    my ($o) = @_;

    $::expert || $::g_auto_install or return;

    my ($floppy) = detect_devices::floppies();

    $o->ask_yesorno('', 
_("Do you want to generate an auto install floppy for linux replication?"), $floppy) or return;

    $o->ask_warn('', _("Insert a blank floppy in drive %s", $floppy));

    my $dev = devices::make($floppy);

    my $image = $o->{pcmcia} ? "pcmcia" :
      ${{ hd => 'hd', cdrom => 'cdrom', ftp => 'network', nfs => 'network', http => 'network' }}{$o->{method}};

    if (arch() =~ /sparc/) {
	$image .= arch() =~ /sparc64/ && "64"; #- for sparc64 there are a specific set of image.

	my $imagefile = "$o->{prefix}/tmp/autoinst.img";
	my $mountdir = "$o->{prefix}/tmp/mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $workdir = "$o->{prefix}/tmp/work"; -d $workdir or rmdir $workdir;

	my $w = $o->wait_message('', _("Creating auto install floppy"));
        install_any::getAndSaveFile("$image.img", $imagefile) or log::l("failed to write $dev"), return;
        devices::make($_) foreach qw(/dev/loop6 /dev/ram);

        run_program::run("losetup", "/dev/loop6", $imagefile);
        fs::mount("/dev/loop6", $mountdir, "romfs", 'readonly');
        commands::cp("-f", $mountdir, $workdir);
        fs::umount($mountdir);
        run_program::run("losetup", "-d", "/dev/loop6");

	substInFile { s/timeout.*//; s/^(\s*append\s*=\s*\".*)\"/$1 kickstart=floppy\"/ } "$workdir/silo.conf";
	output "$workdir/ks.cfg", install_any::generate_ks_cfg($o);
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
	{
	    my $w = $o->wait_message('', _("Creating auto install floppy"));
	    install_any::getAndSaveFile("$image.img", $dev) or log::l("failed to write $dev"), return;
	}
        fs::mount($dev, "/floppy", "vfat", 0);
	substInFile { s/timeout.*//; s/^(\s*append)/$1 kickstart=floppy/ } "/floppy/syslinux.cfg";

	unlink "/floppy/help.msg";
	output "/floppy/ks.cfg", install_any::generate_ks_cfg($o);
	output "/floppy/boot.msg", "\n0c",
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost !!
", "07\n";

	local $o->{partitioning}{clearall} = 1;
	install_any::g_auto_install("/floppy/auto_inst.cfg");

	fs::umount("/floppy");
    }
}

#------------------------------------------------------------------------------
sub exitInstall {
    my ($o, $alldone) = @_;

    return $o->{step} = '' unless $alldone || $o->ask_yesorno('', 
_("Some steps are not completed.

Do you really want to quit now?"), 0);

    install_steps::exitInstall;

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

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
