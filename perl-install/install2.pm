package install2;

use diagnostics;
use strict;
use vars qw($o);

use common qw(:common :file :system);
use install_any qw(:all);
use log;
use net;
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

my @installStepsFields = qw(text help skipOnCancel skipOnLocal prev next);
my @installSteps = (
  selectLanguage => [ __("Choose your language"), "help", 0, 0 ],
  selectPath => [ __("Choose install or upgrade"), __("help"), 0, 0 ],
  selectInstallClass => [ __("Select installation class"), __("help"), 0, 0 ],
  setupSCSI => [ __("Setup SCSI"), __("help"), 0, 1 ],	
  partitionDisks => [ __("Setup filesystems"), __("help"), 0, 1 ],
  formatPartitions => [ __("Format partitions"), __("help"), 0, 1 ],
  findInstallFiles => [ __("Find installation files"), __("help"), 1, 0 ],
  choosePackages => [ __("Choose packages to install"), __("help"), 0, 0 ],
  doInstallStep => [ __("Install system"), __("help"), 0, 0 ],
#  configureMouse => [ __("Configure mouse"), __("help"), 0, 0 ],
  finishNetworking => [ __("Configure networking"), __("help"), 0, 0 ],
#  configureTimezone => [ __("Configure timezone"), __("help"), 0, 0 ],
#  configureServices => [ __("Configure services"), __("help"), 0, 0 ],
#  configurePrinter => [ __("Configure printer"), __("help"), 0, 0 ],
  setRootPassword => [ __("Set root password"), __("help"), 0, 0 ],
  addUser => [ __("Add a user"), __("help"), 0, 0 ],
  createBootdisk => [ __("Create bootdisk"), __("help"), 0, 1 ],
  setupBootloader => [ __("Install bootloader"), __("help"), 0, 1 ],
  configureX => [ __("Configure X"), __("help"), 0, 0 ],
  exitInstall => [ __("Exit install"), __("help"), 0, 0, undef, 'done' ],
);

# this table is translated at run time
my @upgradeSteps = (
  selectLanguage => [ "Choose your language", "help", 0, 0 ],
  selectPath => [ __("Choose install or upgrade"), __("help"), 0, 0 ],
  selectInstallClass => [ __("Select installation class"), __("help"), 0, 0 ],
  setupSCSI => [ __("Setup SCSI"), __("help"), 0, 0 ],
  upgrFindInstall => [ __("Find current installation"), __("help"), 0, 0 ],
  findInstallFiles => [ __("Find installation files"), __("help"), 1, 0 ],
  upgrChoosePackages => [ __("Choose packages to upgrade"), __("help"), 0, 0 ],
  doInstallStep => [ __("Upgrade system"), __("help"), 0, 0 ],
  createBootdisk => [ __("Create bootdisk"), __("help"), 0, 0 , 'none' ],
  setupBootloader => [ __("Install bootloader"), __("help"), 0, 0 ],
  exitInstall => [ __("Exit install"), __("help"), 0, 0 , undef, 'done' ],
);
my (%installSteps, %upgradeSteps, @orderedInstallSteps, @orderedUpgradeSteps);
for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{prev} ||= $installSteps[$i - 2];
    $h{next} ||= $installSteps[$i + 2];
    $installSteps{ $installSteps[$i] } = \%h;
    push @orderedInstallSteps, $installSteps[$i];
}
$installSteps{first} = $installSteps[0];
for (my $i = 0; $i < @upgradeSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $upgradeSteps[$i + 1] };
    $h{prev} ||= $upgradeSteps[$i - 2];
    $h{next} ||= $upgradeSteps[$i + 2];
    $upgradeSteps{ $upgradeSteps[$i] } = \%h;
    push @orderedUpgradeSteps, $installSteps[$i];
}
$upgradeSteps{first} = $upgradeSteps[0];


my @install_classes = (__("newbie"), __("developer"), __("server"), __("expert"));

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
    user => { name => 'foo', password => 'foo', shell => '/bin/bash', realname => 'really, it is foo' },
    rootPassword => 'toto',
    lang => 'fr',
    isUpgrade => 0,
    installClass => 'newbie',
    bootloader => { onmbr => 1, linear => 0 },
    mkbootdisk => 0,
    base => [ qw(basesystem initscripts console-tools mkbootdisk linuxconf anacron linux_logo rhs-hwdiag utempter ldconfig chkconfig ntsysv mktemp setup setuptool filesystem MAKEDEV SysVinit ash at authconfig bash bdflush binutils console-tools crontabs dev e2fsprogs ed etcskel file fileutils findutils getty_ps gpm grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time timeconfig tmpwatch util-linux vim-minimal vixie-cron which) ],
    packages => [ qw() ],
    partitionning => { clearall => $::testing, eraseBadPartitions => 1, autoformat => 1 },
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
}

sub selectPath {
    $o->{isUpgrade} = $o->selectInstallOrUpgrade;
    $o->{steps}        = $o->{isUpgrade} ? \%upgradeSteps : \%installSteps;
    $o->{orderedSteps} = $o->{isUpgrade} ? \@orderedUpgradeSteps : \@orderedInstallSteps;
}

sub selectInstallClass {
    $o->{installClass} = $o->selectInstallClass(@install_classes);
    $::expert = $o->{installClass} eq "expert";
}

sub setupSCSI { $o->setupSCSI }

sub partitionDisks {
    $o->{drives} = [ detect_devices::hds() ];
    $o->{hds} = fsedit::hds($o->{drives}, $o->{default}->{partitionning});
    @{$o->{hds}} > 0 or die _("An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");

    unless ($o->{isUpgrade}) {
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

    foreach (@{$o->{fstab}}) {
	fs::format_part($_) if $_->{toFormat};
    }
    fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
}

sub findInstallFiles {
    $o->{packages} = pkgs::psUsingDirectory();
    pkgs::getDeps($o->{packages});

    $o->{compss} = pkgs::readCompss($o->{packages});
}
 
sub choosePackages {
    my @p = @{$o->{default}->{base}};
    push @p, "kernel-smp" if smp::detect();

    foreach (@p) { $o->{packages}->{$_}->{base} = 1 }

    pkgs::setCompssSelected($o->{compss}, $o->{packages}, $o->{installClass});
    $o->choosePackages($o->{packages}, $o->{compss}); 

    foreach (@p) { $o->{packages}->{$_}->{selected} = 1 }
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
sub configureX { $o->setupXfree if $o->{packages}->{XFree86}->{installed} }
sub exitInstall { $o->exitInstall }


sub main {
    $SIG{__DIE__} = sub { chomp $_[0]; log::l("ERROR: $_[0]") };

    #  if this fails, it's okay -- it might help with free space though 
    unlink "/sbin/install";
    unlink "/sbin/insmod";

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

    $o->{netc} = net::readNetConfig("/tmp");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	$o->{intf} = net::readNetInterfaceConfig($file);
    }

    modules::load_deps("/lib/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    for (my $step = $o->{steps}->{first}; $step ne 'done'; $step = getNextStep($step)) {
	$o->enteringStep($step);
	eval { 
	    &{$install2::{$step}}();
	};
	$o->errorInStep($@), redo if $@;
	$o->leavingStep($step);
    }
    killCardServices();

    log::l("installation complete, leaving");
}

sub killCardServices { 
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); # send SIGTERM
}
