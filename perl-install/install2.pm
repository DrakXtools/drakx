package install2;

use diagnostics;
use strict;
use vars qw($o);

use common qw(:common :file :system);
use install_any qw(:all);
use log;
use network;
use keyboard;
use fs;
use fsedit;
use install_steps_graphical;
use modules;
use partition_table qw(:types);
use detect_devices;
use pkgs;
use smp;
use lang;
use run_program;

my @installStepsFields = qw(text help redoable onError needs);
my @installSteps = (
  selectLanguage => [ __("Choose your language"), "help", 1, 1 ],
  selectPath => [ __("Choose install or upgrade"), __("help"), 0, 0 ],
  selectInstallClass => [ __("Select installation class"), __("help"), 1, 1 ],
  setupSCSI => [ __("Setup SCSI"), __("help"), 1, 0 ],	
  partitionDisks => [ __("Setup filesystems"), __("help"), 1, 0 ],
  formatPartitions => [ __("Format partitions"), __("help"), 1, -1, "partitionDisks" ],
  choosePackages => [ __("Choose packages to install"), __("help"), 1, 1 ],
  doInstallStep => [ __("Install system"), __("help"), 1, -1, ["formatPartitions", "selectPath"] ],
#  configureMouse => [ __("Configure mouse"), __("help"), 0, 0 ],
  finishNetworking => [ __("Configure networking"), __("help"), 1, 1, "formatPartitions" ],
#  configureTimezone => [ __("Configure timezone"), __("help"), 0, 0 ],
#  configureServices => [ __("Configure services"), __("help"), 0, 0 ],
#  configurePrinter => [ __("Configure printer"), __("help"), 0, 0 ],
  setRootPassword => [ __("Set root password"), __("help"), 1, 0, "formatPartitions" ],
  addUser => [ __("Add a user"), __("help"), 1, 0, "formatPartitions" ],
  createBootdisk => [ __("Create bootdisk"), __("help"), 1, 0, "doInstallStep" ],
  setupBootloader => [ __("Install bootloader"), __("help"), 1, 1, "doInstallStep" ],
  configureX => [ __("Configure X"), __("help"), 1, 0, "formatPartitions" ],
  exitInstall => [ __("Exit install"), __("help"), 0, 0, "alldone" ],
);
my (%installSteps, %upgradeSteps, @orderedInstallSteps, @orderedUpgradeSteps);
for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{next} = $installSteps[$i + 2];
    $h{onError} = $installSteps[$i + 2 * $h{onError}];
    $installSteps{ $installSteps[$i] } = \%h;
    push @orderedInstallSteps, $installSteps[$i];
}
$installSteps{first} = $installSteps[0];


my @install_classes = (__("beginner"), __("developer"), __("server"), __("expert"));

# partition layout for a server
my @serverPartitioning = (
		     { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		     { mntpoint => "/",     size => 256 << 11, type => 0x83 }, 
		     { mntpoint => "/usr",  size => 512 << 11, type => 0x83, growable => 1 }, 
		     { mntpoint => "/var",  size => 256 << 11, type => 0x83 }, 
		     { mntpoint => "/home", size => 512 << 11, type => 0x83, growable => 1 }, 
		     { mntpoint => "swap",  size =>  64 << 11, type => 0x82 }
);

my $default = {
#    display => "192.168.1.9:0",

    # for the list of fields available for user and superuser, see @etc_pass_fields in install_steps.pm
#    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },
#    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },

#    lang => 'fr',
#    isUpgrade => 0,
#    installClass => 'beginner',
    bootloader => { onmbr => 1, linear => 0 },
    autoSCSI => 0,
    mkbootdisk => 0,
    base => [ qw(basesystem initscripts console-tools mkbootdisk linuxconf anacron linux_logo rhs-hwdiag utempter ldconfig chkconfig ntsysv mktemp setup setuptool filesystem MAKEDEV SysVinit ash at authconfig bash bdflush binutils console-tools crontabs dev e2fsprogs ed etcskel file fileutils findutils getty_ps gpm grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time timeconfig tmpwatch util-linux vim-minimal vixie-cron which) ],
    packages => [ qw() ],
    partitionning => { clearall => $::testing, eraseBadPartitions => 1, auto_allocate => 0, autoformat => 1 },
    partitions => [
		   { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		   { mntpoint => "/",     size => 300 << 11, type => 0x83 }, 
		   { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 }, 
	     ],
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash) ],
};
$o = $::o = { default => $default, steps => \%installSteps, orderedSteps => \@orderedInstallSteps };


sub selectLanguage {
    $o->{lang} = $o->chooseLanguage;
    lang::set($o->{lang});
    $o->{keyboard} = keyboard::setup();

    addToBeDone {
	unless ($o->{isUpgrade}) {
	    keyboard::write($o->{prefix}, $o->{keyboard});
	    lang::write($o->{prefix});
	} 
    } 'doInstallStep';
}

sub selectPath {
    $o->{isUpgrade} = $o->selectInstallOrUpgrade;
    $o->{steps}        = $o->{isUpgrade} ? \%upgradeSteps : \%installSteps;
    $o->{orderedSteps} = $o->{isUpgrade} ? \@orderedUpgradeSteps : \@orderedInstallSteps;
}

sub selectInstallClass {
    $o->{installClass} = $o->selectInstallClass(@install_classes);
    $::expert = $o->{installClass} eq "expert";
    $o->{autoSCSI} = $o->default("autoSCSI") || $o->{installClass} eq "beginner";
}

sub setupSCSI { $o->setupSCSI }

sub partitionDisks {
    $o->{drives} = [ detect_devices::hds() ];
    $o->{hds} = fsedit::hds($o->{drives}, $o->{default}{partitionning});
    unless (@{$o->{hds}} > 0) {
	$o->setupSCSI if $o->{autoSCSI}; # ask for an unautodetected scsi card
    }
    unless (@{$o->{hds}} > 0) { # no way
	die _("An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    unless ($o->{isUpgrade}) {
	eval { fsedit::auto_allocate($o->{hds}, $o->{partitions}) } if $o->{default}{partitionning}{auto_allocate};
	$o->doPartitionDisks($o->{hds});

	unless ($::testing) {
	    # Write partitions to disk 
	    my $need_reboot = 0;
	    foreach (@{$o->{hds}}) { 
		eval { partition_table::write($_); };
		$need_reboot ||= $@;
	    }
	    $need_reboot and $o->rebootNeeded;
	}
    }

    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}) ];

    my $root_fs; map { $_->{mntpoint} eq '/' and $root_fs = $_ } @{$o->{fstab}};
    $root_fs or die _("partitionning failed: no root filesystem");

}

sub formatPartitions {
    $o->choosePartitionsToFormat($o->{fstab});

    $::testing and return;

    $o->formatPartitions(@{$o->{fstab}});

    fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
}

sub choosePackages {
    $o->{packages} = pkgs::psUsingDirectory();
    pkgs::getDeps($o->{packages});

    $o->{compss} = pkgs::readCompss($o->{packages});

    my @p = @{$o->{default}{base}};
    push @p, "kernel-smp" if smp::detect();

    foreach (@p) { $o->{packages}{$_}{base} = 1 }

    pkgs::setCompssSelected($o->{compss}, $o->{packages}, $o->{installClass});
    $o->choosePackages($o->{packages}, $o->{compss}); 

    foreach (@p) { $o->{packages}{$_}{selected} = 1 }
}

sub doInstallStep {
    $o->beforeInstallPackages;
    $o->installPackages($o->{packages});
    $o->afterInstallPackages;
}

sub configureMouse { $o->mouseConfig }
sub finishNetworking { $o->finishNetworking }
sub configureTimezone { $o->timeConfig }
sub configureServices { $o->servicesConfig }
sub setRootPassword { $o->setRootPassword }
sub addUser { 
    $o->addUser;
    run_program::rooted($o->{prefix}, "pwconv") or log::l("pwconv failed"); # use shadow passwords
}

sub createBootdisk {
    fs::write($o->{prefix}, $o->{fstab}) unless $o->{isUpgrade};
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');
    $o->createBootdisk;
}

sub setupBootloader {
    $o->{isUpgrade} or modules::read_conf("$o->{prefix}/etc/conf.modules");
    $o->setupBootloader;
}
sub configureX { $o->setupXfree if $o->{packages}{XFree86}{installed} }
sub exitInstall { $o->exitInstall }


sub main {
    $SIG{__DIE__} = sub { chomp $_[0]; log::l("ERROR: $_[0]") };

    #  if this fails, it's okay -- it might help with free space though 
    unlink "/sbin/install" unless $::testing;
    unlink "/sbin/insmod" unless $::testing;

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running");
    log::ld("extra log messages are enabled");

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;

    #  make sure we don't pick up any gunk from the outside world 
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{LD_LIBRARY_PATH} = "";

    spawnSync();
    eval { spawnShell() };

    # needed very early for install_steps_graphical
    @{$o->{mouse}}{"xtype", "device"} = install_any::mouse_detect() unless $::testing;

    $o = install_steps_graphical->new($o);

    $o->{netc} = network::read_conf("/tmp/network");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	$o->{intf} = network::read_interface_conf($file);
    }

    modules::load_deps("/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->enteringStep($o->{step});
	$o->{steps}{$o->{step}}{entered} = 1;
	eval { 
	    &{$install2::{$o->{step}}}();
	};
	$@ =~ /^setstep (.*)/ and $o->{step} = $1, redo;
	$@ =~ /^theme_changed$/ and redo;
	if ($@) {
	    $o->errorInStep($@);
	    $o->{step} = $o->{steps}{$o->{step}}{onError};
	    redo;
	}
	$o->leavingStep($o->{step});
	$o->{steps}{$o->{step}}{done} = 1;

	last if $o->{step} eq 'exitInstall';
    }
    killCardServices();

    log::l("installation complete, leaving");
}

sub killCardServices { 
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); # send SIGTERM
}
