package install2;

use diagnostics;
use strict;
use Data::Dumper;

use vars qw($o);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system :functional);
use install_any qw(:all);
use log;
use help;
use network;
use lang;
use keyboard;
use lilo;
use mouse;
use fs;
use timezone;
use fsedit;
use devices;
use partition_table qw(:types);
use pkgs;
use printer;
use modules;
use detect_devices;
use modparm;
use install_steps_graphical;
use run_program;

#-######################################################################################
#- Steps table
#-######################################################################################
my @installStepsFields = qw(text redoable onError needs entered reachable toBeDone help next done);
my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1 ],
  selectInstallClass => [ __("Select installation class"), 1, 1 ],
  setupSCSI          => [ __("Setup SCSI"), 1, 0 ],
  selectPath         => [ __("Choose install or upgrade"), 0, 0, "selectInstallClass" ],
  selectMouse        => [ __("Configure mouse"), 1, 1 ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1 ],
  partitionDisks     => [ __("Setup filesystems"), 1, 0 ],
  formatPartitions   => [ __("Format partitions"), 1, -1, "partitionDisks" ],
  choosePackages     => [ __("Choose packages to install"), 1, 1, "selectInstallClass" ],
  doInstallStep      => [ __("Install system"), 1, -1, ["formatPartitions", "selectPath"] ],
  configureNetwork   => [ __("Configure networking"), 1, 1, "formatPartitions" ],
  configureTimezone  => [ __("Configure timezone"), 1, 1, "doInstallStep" ],
#-  configureServices => [ __("Configure services"), 0, 0 ],
  configurePrinter   => [ __("Configure printer"), 1, 0, "doInstallStep" ],
  setRootPassword    => [ __("Set root password"), 1, 1, "formatPartitions" ],
  addUser            => [ __("Add a user"), 1, 1, "doInstallStep" ],
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, "doInstallStep" ],
  setupBootloader    => [ __("Install bootloader"), 1, 1, "doInstallStep" ],
  configureX         => [ __("Configure X"), 1, 0, "formatPartitions" ],
  exitInstall        => [ __("Exit install"), 0, 0 ],
);

my (%installSteps, %upgradeSteps, @orderedInstallSteps, @orderedUpgradeSteps);

for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{help}    = $help::steps{$installSteps[$i]} || __("Help");
    $h{next}    = $installSteps[$i + 2];
    $h{entered} = 0;
    $h{onError} = $installSteps[$i + 2 * $h{onError}];
    $installSteps{ $installSteps[$i] } = \%h;
    push @orderedInstallSteps, $installSteps[$i];
}

$installSteps{first} = $installSteps[0];

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################

#- these strings are used in quite a lot of places and must not be changed!!!!!
my @install_classes = (__("beginner"), __("developer"), __("server"), __("expert"));

#-#####################################################################################
#-Default value
#-#####################################################################################
#- partition layout
my %suggestedPartitions = (
  beginner => [
    { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82 },
    { mntpoint => "/",     size => 700 << 11, type => 0x83 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83 },
  ],
  developer => [
    { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82 },
    { mntpoint => "/",     size => 200 << 11, type => 0x83 },
    { mntpoint => "/usr",  size => 600 << 11, type => 0x83 },
    { mntpoint => "/home", size => 500 << 11, type => 0x83 },
  ],
  server => [
    { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
    { mntpoint => "swap",  size => 512 << 11, type => 0x82 },
    { mntpoint => "/",     size => 200 << 11, type => 0x83 },
    { mntpoint => "/usr",  size => 600 << 11, type => 0x83 },
    { mntpoint => "/var",  size => 600 << 11, type => 0x83 },
    { mntpoint => "/home", size => 500 << 11, type => 0x83 },
  ],
  expert => [
    { mntpoint => "/",     size => 200 << 11, type => 0x83 },
  ],
);

#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, message => 1, timeout => 5, restricted => 0 },
    autoSCSI   => 0,
    mkbootdisk => 1, #- no mkbootdisk if 0 or undef,   find a floppy with 1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0, autoformat => 0, readonly => 0 },
#-    partitions => [
#-		      { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
#-		      { mntpoint => "/",     size => 256 << 11, type => 0x83 },
#-		      { mntpoint => "/usr",  size => 512 << 11, type => 0x83, growable => 1 },
#-		      { mntpoint => "/var",  size => 256 << 11, type => 0x83 },
#-		      { mntpoint => "/home", size => 512 << 11, type => 0x83, growable => 1 },
#-		      { mntpoint => "swap",  size =>  64 << 11, type => 0x82 }
#-		    { mntpoint => "/boot", size =>  16 << 11, type => 0x83 },
#-		    { mntpoint => "/",     size => 300 << 11, type => 0x83 },
#-		    { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#-		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 },
#-	     ],
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash ksh) ],
    lang         => 'en',
    isUpgrade    => 0,
    installClass => "beginner",

    timezone => {
#-                   timezone => "Europe/Paris",
#-                   GMT      => 1,
                },
    printer => {
                 want     => 0,
                 complete => 0,
                 str_type => $printer::printer_type_default,
                 QUEUE    => "lp",
                 SPOOLDIR => "/var/spool/lpd/lp",
                 DBENTRY  => "DeskJet670",
                 PAPERSIZE => "legal",
                 CRLF      => 0,

                 DEVICE    => "/dev/lp",

                 REMOTEHOST => "",
                 REMOTEQUEUE => "",

                 NCPHOST   => "printerservername",
                 NCPQUEUE  => "queuename",
                 NCPUSER   => "user",
                 NCPPASSWD => "pass",

                 SMBHOST   => "hostname",
                 SMBHOSTIP => "1.2.3.4",
                 SMBSHARE  => "printername",
                 SMBUSER   => "user",
                 SMBPASSWD => "passowrd",
                 SMBWORKGROUP => "AS3",
               },
#-    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },
#-    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },

#-    keyboard => 'de',
#-    display => "192.168.1.19:1",
    steps        => \%installSteps,
    orderedSteps => \@orderedInstallSteps,

    base => [ qw(basesystem initscripts console-tools mkbootdisk anacron rhs-hwdiag utempter ldconfig chkconfig ntsysv mktemp setup filesystem SysVinit bdflush crontabs dev e2fsprogs etcskel fileutils findutils getty_ps grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time timeconfig tmpwatch util-linux vim-minimal vixie-cron which cpio perl) ],
#- for the list of fields available for user and superuser, see @etc_pass_fields in install_steps.pm
#-    intf => [ { DEVICE => "eth0", IPADDR => '1.2.3.4', NETMASK => '255.255.255.128' } ],

#-step : the current one
#-prefix
#-mouse
#-keyboard
#-netc
#-autoSCSI drives hds  fstab
#-methods
#-packages compss
#-printer haveone entry(cf printer.pm)

};

#-######################################################################################
#- Steps Functions
#- each step function are called with two arguments : clicked(because if you are a
#- beginner you can force the the step) and the entered number
#-######################################################################################

#------------------------------------------------------------------------------
sub selectLanguage {
    $o->selectLanguage;

    addToBeDone {
	lang::write($o->{prefix});
	keyboard::write($o->{prefix}, $o->{keyboard});
    } 'doInstallStep' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($clicked) = $_[0];

    $o->{mouse} ||= {};
    add2hash($o->{mouse}, { mouse::read($o->{prefix}) }) if $o->{isUpgrade} && !$clicked;

    $o->selectMouse($clicked);
    addToBeDone { mouse::write($o->{prefix}, $o->{mouse}); } 'formatPartitions';
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($clicked) = $_[0];

    return unless $o->{isUpgrade} || !$::beginner || $clicked;

    $o->{keyboard} = (keyboard::read($o->{prefix}))[0] if $o->{isUpgrade} && !$clicked && !$o->{keyboard};
    $o->selectKeyboard if !$::beginner || $clicked;

    #- if we go back to the selectKeyboard, you must rewrite
    addToBeDone {
	keyboard::write($o->{prefix}, $o->{keyboard});
    } 'doInstallStep' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectPath {
    $o->selectPath;
    install_any::searchAndMount4Upgrade($o) if $o->{isUpgrade};
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    $o->selectInstallClass(@install_classes);

    $::expert   = $o->{installClass} eq "expert";
    $::beginner = $o->{installClass} eq "beginner";
    $o->{partitions} ||= $suggestedPartitions{$o->{installClass}};

    if ($o->{steps}{choosePackages}{entered} >= 1 && !$o->{steps}{doInstallStep}{done}) {
        $o->setPackages(\@install_classes);
        $o->selectPackagesToUpgrade() if $o->{isUpgrade};
    }
}

#------------------------------------------------------------------------------
sub setupSCSI {
    my ($clicked) = $_[0];
    $o->{autoSCSI} ||= $::beginner;

    $o->setupSCSI($o->{autoSCSI} && !$clicked, $clicked);
}

#------------------------------------------------------------------------------
sub partitionDisks {
    return if ($o->{isUpgrade});

    $::o->{steps}{formatPartitions}{done} = 0;
    eval { fs::umount_all($o->{fstab}, $o->{prefix}) } if $o->{fstab} && !$::testing;

    my $ok = is_empty_array_ref($o->{hds}) ? install_any::getHds($o) : 1;
    my $auto = $ok && !$o->{partitioning}{readonly} &&
	($o->{partitioning}{auto_allocate} || $::beginner && fsedit::get_fstab(@{$o->{hds}}) < 4);

    eval { fsedit::auto_allocate($o->{hds}, $o->{partitions}) } if $auto;

    if ($auto && fsedit::get_root_($o->{hds}) && $_[1] == 1) {
	#- we have a root partition, that's enough :)
	$o->install_steps::doPartitionDisks($o->{hds});	
    } elsif ($o->{partitioning}{readonly}) {
	$o->ask_mntpoint_s($o->{fstab});
    } else {
	$o->doPartitionDisks($o->{hds});
    }
    unless ($::testing) {
	$o->rebootNeeded foreach grep { $_->{rebootNeeded} } @{$o->{hds}};
    }
    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}) ];
    fsedit::get_root($o->{fstab}) or die _("Partitioning failed: no root filesystem");
}

sub formatPartitions {
    return if ($o->{isUpgrade});

    $o->choosePartitionsToFormat($o->{fstab});

    unless ($::testing) {
	$o->formatPartitions(@{$o->{fstab}});
	fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
    }
    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/sysconfig etc/sysconfig/console etc/sysconfig/network-scripts
	etc/sysconfig/network-scripts
	home mnt root tmp var var/tmp var/lib var/lib/rpm);
}

#------------------------------------------------------------------------------
#-PADTODO
sub choosePackages {
    $o->setPackages($o, \@install_classes) if $_[1] == 1;
    $o->selectPackagesToUpgrade($o) if $o->{isUpgrade} && $_[1] == 1;
    $o->choosePackages($o->{packages}, $o->{compss});
    $o->{packages}{$_}{selected} = 1 foreach @{$o->{base}};
}

#------------------------------------------------------------------------------
sub doInstallStep {
    $o->readBootloaderConfigBeforeInstall if $_[1] == 1;

    $o->beforeInstallPackages;
    $o->installPackages($o->{packages});
    $o->afterInstallPackages;
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($clicked, $entered) = @_;

    if ($o->{isUpgrade} && !$clicked) {
	$o->{netc} or $o->{netc} = {};
	add2hash($o->{netc}, { network::read_conf("$o->{prefix}/etc/sysconfig/network") }) if -r "$o->{prefix}/etc/sysconfig/network";;
	add2hash($o->{netc}, { network::read_resolv_conf("$o->{prefix}/etc/resolv.conf") }) if -r "$o->{prefix}/etc/resolv.conf";
	foreach (all("$o->{prefix}/etc/sysconfig/network-scripts")) {
	    if (/ifcfg-(\w*)/) {
		push @{$o->{intf}}, { network::read_conf("$o->{prefix}/etc/sysconfig/network-scripts/$_") };
	    }
	}
    }

    $o->configureNetwork($entered == 1 && !$clicked)
}
#------------------------------------------------------------------------------
#-PADTODO
sub configureTimezone {
    my ($clicked) = $_[0];
    my $f = "$o->{prefix}/etc/sysconfig/clock";
    return if ((-s $f) || 0) > 0 && $_[1] == 1 && !$clicked && !$::testing;

    add2hash($o->{timezone}, { timezone::read($f) }) if $o->{isUpgrade} && !$clicked;
    $o->{timezone}{GMT} = 1 unless exists $o->{timezone}{GMT}; #- take GMT by default if nothing else.

    $o->timeConfig($f);
}
#------------------------------------------------------------------------------
sub configureServices { $o->servicesConfig  }
#------------------------------------------------------------------------------
sub configurePrinter  { $o->printerConfig   }
#------------------------------------------------------------------------------
sub setRootPassword {
    return if ($o->{isUpgrade});

    $o->setRootPassword;
}
#------------------------------------------------------------------------------
sub addUser {
    return if ($o->{isUpgrade});

    $o->addUser;

    addToBeDone {
	run_program::rooted($o->{prefix}, "pwconv") or log::l("pwconv failed"); #- use shadow passwords
    } 'doInstallStep';
}

#------------------------------------------------------------------------------
#-PADTODO
sub createBootdisk {
    fs::write($o->{prefix}, $o->{fstab});
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');
    $o->createBootdisk($_[1] == 1);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    $o->setupBootloaderBefore if $_[1] == 1;
    $o->setupBootloader($_[1] > 1);
}
#------------------------------------------------------------------------------
sub configureX {
    my ($clicked) = $_[0];
    $o->setupXfree if $o->{packages}{XFree86}{installed} || $clicked;
}
#------------------------------------------------------------------------------
sub exitInstall { $o->exitInstall(getNextStep() eq "exitInstall") }


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
    $SIG{__DIE__} = sub { chomp $_[0]; log::l("ERROR: $_[0]") };

    $::beginner = $::expert = $::g_auto_install = 0;
    while (@_) {
	local $_ = shift;
	if (/--method/) {
	    $o->{method} = shift;
	} elsif (/--step/) {
	    $o->{steps}{first} = shift;
	} elsif (/--expert/) {
	    $::expert = 1;
	} elsif (/--beginner/) {
	    $::beginner = 1;
	#} elsif (/--ks/ || /--kickstart/) {
	#    $::auto_install = 1;
	} elsif (/--g_auto_install/) {
	    $::testing = $::g_auto_install = 1;
	    $o->{partitioning}{auto_allocate} = 1;
	} elsif (/--pcmcia/) {
	    $o->{pcmcia} = shift;
	} elsif (/--readonly/) {
	    $o->{partitioning}{readonly} = 1;
	}
    }

    unlink "/sbin/insmod"  unless $::testing;

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running");
    log::ld("extra log messages are enabled");

    #-really needed ??
    #-spawnSync();
    eval { spawnShell() };

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    $o->{root}   = $::testing ? "/tmp/root-perl-install" : "/";
    mkdir $o->{prefix}, 0755;
    mkdir $o->{root}, 0755;

    #-  make sure we don't pick up any gunk from the outside world
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin" unless $::g_auto_install;
    $ENV{LD_LIBRARY_PATH} = "";

    if ($::auto_install) {
	require 'install_steps.pm';
	fs::mount(devices::make("fd0"), "/mnt", "vfat", 0);

	my $O = $o;
	my $f = "/mnt/auto_inst.cfg";
	{
	    local *F;
	    open F, $f or die _("Error reading file $f");

	    local $/ = "\0";
	    eval <F>;
	}
	$@ and die _("Bad kickstart file %s (failed %s)", $f, $@);
	fs::umount("/mnt");
	add2hash($o, $O);
    } else {
	require 'install_steps_graphical.pm';
    }

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;

    #-  make sure we don't pick up any gunk from the outside world
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{LD_LIBRARY_PATH} = "";

    #- needed very early for install_steps_graphical
    eval { $o->{mouse} ||= mouse::detect() };

    $::o = $o = $::auto_install ?
      install_steps->new($o) :
      install_steps_graphical->new($o);

    $o->{netc} = network::read_conf("/tmp/network");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	my $l = network::read_interface_conf($file);
	add2hash(network::findIntf($o->{intf} ||= [], $l->{DEVICE}), $l);
    }

    modules::load_deps("/modules/modules.dep");
    $o->{modules} = modules::get_stage1_conf($o->{modules}, "/tmp/conf.modules");
    modules::read_already_loaded();
    modparm::read_modparm_file(-e "modparm.lst" ? "modparm.lst" : "/usr/share/modparm.lst");

    #-the main cycle
    my $clicked = 0;
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	eval {
	    &{$install2::{$o->{step}}}($clicked, $o->{steps}{$o->{step}}{entered});
	};
	$o->kill_action;
	$clicked = 0;
	while ($@) {
	    local $_ = $@;
	    $o->kill_action;
	    /^setstep (.*)/ and $o->{step} = $1, $clicked = 1, redo MAIN;
	    /^theme_changed$/ and redo MAIN;
	    eval { $o->errorInStep($_) } unless /^already displayed/;
	    $@ and next;
	    $o->{step} = $o->{steps}{$o->{step}}{onError};
	    redo MAIN;
	}
	$o->leavingStep($o->{step});
	$o->{steps}{$o->{step}}{done} = 1;

	last if $o->{step} eq 'exitInstall';
    }

    fs::write($o->{prefix}, $o->{fstab});
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');

    killCardServices();

    log::l("installation complete, leaving");

    if ($::g_auto_install) {
	my $h = $o; $o = {};
	$h->{$_} and $o->{$_} = $h->{$_} foreach qw(lang autoSCSI printer mouse netc timezone bootloader superuser intf keyboard mkbootdisk base user modules installClass partitions);

	delete $o->{user}{password2};
	delete $o->{superuser}{password2};

	print Data::Dumper->Dump([$o], ['$o']), "\0";
    }
}

sub killCardServices {
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
