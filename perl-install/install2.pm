#!/usr/bin/perl

# $o->{hints}->{component} *was* 'Workstation' or 'Server' or NULL

use diagnostics;
use strict;
use vars qw($testing $INSTALL_VERSION $o);

use lib qw(/usr/bin/perl-install . c c/blib/arch);
use common qw(:common :file :system);
use install_any qw(:all);
use log;
use net;
use keyboard;
use fs;
use fsedit;
use install_steps_graphical;
use install_methods;
use modules;
use partition_table qw(:types);
use detect_devices;
use smp;

$testing = 1;#$ENV{PERL_INSTALL_TEST};
$INSTALL_VERSION = 0;

my @installStepsFields = qw(text help skipOnCancel skipOnLocal prev next);
my @installSteps = (
  selectLanguage => [ "Choose your language", "aide", 0, 0 ],
  selectPath => [ "Choose install or upgrade", "aide", 0, 0 ],
  selectInstallClass => [ "Select installation class", "aide", 0, 0 ],
  setupSCSI => [ "Setup SCSI", "aide", 0, 1 ],	
  partitionDisks => [ "Setup filesystems", "aide", 0, 1 ],
  findInstallFiles => [ "Find installation files", "aide", 1, 0 ],
  choosePackages => [ "Choose packages to install", "aide", 0, 0 ],
  doInstallStep => [ "Install system", "aide", 0, 0 ],
#  configureMouse => [ "Configure mouse", "aide", 0, 0 ],
  finishNetworking => [ "Configure networking", "aide", 0, 0 ],
#  configureTimezone => [ "Configure timezone", "aide", 0, 0 ],
#  configureServices => [ "Configure services", "aide", 0, 0 ],
#  configurePrinter => [ "Configure printer", "aide", 0, 0 ],
  setRootPassword => [ "Set root password", "aide", 0, 0 ],
  addUser => [ "Add a user", "aide", 0, 0 ],
  createBootdisk => [ "Create bootdisk", "aide", 0, 1 ],
  setupBootloader => [ "Install bootloader", "aide", 0, 1 ],
#  configureX => [ "Configure X", "aide", 0, 0 ],
  exitInstall => [ "Exit install", "aide", 0, 0, undef, 'done' ],
);

# this table is translated at run time
my @upgradeSteps = (
  selectLanguage => [ "Choose your language", "aide", 0, 0 ],
  selectPath => [ "Choose install or upgrade", "aide", 0, 0 ],
  selectInstallClass => [ "Select installation class", "aide", 0, 0 ],
  setupSCSI => [ "Setup SCSI", "aide", 0, 0 ],
  upgrFindInstall => [ "Find current installation", "aide", 0, 0 ],
  findInstallFiles => [ "Find installation files", "aide", 1, 0 ],
  upgrChoosePackages => [ "Choose packages to upgrade", "aide", 0, 0 ],
  doInstallStep => [ "Upgrade system", "aide", 0, 0 ],
  createBootdisk => [ "Create bootdisk", "aide", 0, 0 , 'none' ],
  setupBootloader => [ "Install bootloader", "aide", 0, 0 ],
  exitInstall => [ "Exit install", "aide", 0, 0 , undef, 'done' ],
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
#    display => "jaba:1",
    user => { name => 'foo', password => 'foo', shell => '/bin/bash', realname => 'really, it is foo' },
    rootPassword => 'toto',
    lang => 'us',
    isUpgrade => 0,
    installClass => 'Server',
    bootloader => { onmbr => 1, linear => 0 },
    mkbootdisk => 0,
    comps => [ qw() ],
    packages => [ qw() ],
    partitionning => { clearall => 0, eraseBadPartitions => 1, autoformat => 1 },
    partitions => [
		   { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		   { mntpoint => "/",     size => 300 << 11, type => 0x83 }, 
		   { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 }, 
	     ],
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash) ],
};
$o = { default => $default, steps => \%installSteps, orderedSteps => \@orderedInstallSteps };


sub selectLanguage {
    $o->{lang} = $o->chooseLanguage;
}

sub selectPath {
    $o->{isUpgrade} = $o->selectInstallOrUpgrade;
    $o->{steps}        = $o->{isUpgrade} ? \%upgradeSteps : \%installSteps;
    $o->{orderedSteps} = $o->{isUpgrade} ? \@orderedUpgradeSteps : \@orderedInstallSteps;
}

sub selectInstallClass {
    $o->{installClass} = $o->selectInstallClass;

    $testing and $o->{default}->{partitionning}->{clearall} = 1;

    if ($o->{installClass} eq 'Server') {
	#TODO
    }
}

sub setupSCSI {
    $o->{direction} < 0 && detect_devices::hasSCSI() and return;

    # If we have any scsi adapters configured from earlier, then don't bother asking again
    while (my ($k, $v) = each %modules::loaded) {
	$v->{type} eq 'scsi' and return;
    }
#    $o->setupSCSIInterfaces(0, \%modules::loaded, $o->{hints}->{flags}->{autoscsi}, $o->{direction});
}

sub partitionDisks {
    $o->{drives} = [ detect_devices::hds() ];
    $o->{hds} = fsedit::hds($o->{drives}, $o->{default}->{partitionning});
    @{$o->{hds}} > 0 or die "An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem";

    unless ($o->{isUpgrade}) {
	$o->doPartitionDisks($o->{hds});

	unless ($testing) {
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
    $root_fs or die "partitionning failed: no root filesystem";

    $o->choosePartitionsToFormat($o->{fstab});

    $testing and return;

    foreach (@{$o->{fstab}}) {
	fs::format_part($_) if $_->{toFormat};
    }
    fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
}

sub findInstallFiles {
    $o->{packages} = $o->{method}->getPackageSet;
    $o->{comps} = $o->{method}->getComponentSet($o->{packages});
}
 
sub choosePackages {
    # remove Base from comps so that it's hidden
    my $base = $o->{comps}->{Base};
    delete $o->{comps}->{Base};

    $o->choosePackages($o->{packages}, $o->{comps}); 

    #restore Base
    $o->{comps}->{Base} = $base;
    $o->{comps}->{Base}->{selected} = 1;

    foreach (grep { $_->{selected} } values %{$o->{comps}}) {
	foreach (@{$_->{packages}}) { $_->{selected} = 1 }
    }
    smp::detect() and $o->{packages}->{"kernel-smp"}->{selected} = 1;
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
sub addUser { $o->addUser }

sub createBootdisk {
    $testing and return;
    $o->{isUpgrade} or fs::write($o->{prefix}, $o->{fstab});
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');
    $o->createBootdisk;
}

sub setupBootloader {
    $o->{isUpgrade} or modules::read_conf("$o->{prefix}/etc/conf.modules");
    $o->setupBootloader;
}

sub configureX { $o->setupXfree; }

sub exitInstall { 
    $o->warn( 
"Congratulations, installation is complete.
Remove the boot media and press return to reboot.
For information on fixes which are available for this release of Linux Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.
Information on configuring your system is available in the post
install chapter of the Official Linux Mandrake User's Guide.");
}

sub main {
    $SIG{__DIE__} = sub { chomp $_[0]; log::l("ERROR: $_[0]") };

    #  if this fails, it's okay -- it might help with free space though 
    unlink "/sbin/install";
    symlink '/tmp/rhimage/usr/X11R6', '/usr/X11R6';

    print STDERR "in second stage install\n";
    log::openLog(($testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running (version $INSTALL_VERSION)");
    log::ld("extra log messages are enabled");

    #  make sure we don't pick up any gunk from the outside world 
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{LD_LIBRARY_PATH} = "";

    spawnSync();
    eval { spawnShell() };

    $o->{prefix} = $testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;
    $o->{method} = install_methods->new('cdrom');

    $o = install_steps_graphical->new($o);

    $o->{netc} = net::readNetConfig("/tmp");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	$o->{intf} = net::readNetInterfaceConfig($file);
    }

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    modules::load_deps("/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    $o->{keyboard} = eval { keyboard::read("/tmp/keyboard") } || $default->{keyboard};

    for (my $step = $o->{steps}->{first}; $step ne 'done'; $step = getNextStep($step)) {
	$o->enteringStep($step);
	&{$main::{$step}}() and $o->{steps}->{$step}->{completed} = 1;
	$o->leavingStep($step);
    }
    killCardServices();

    log::l("installation complete, leaving");

    <STDIN> unless $testing;
}

sub killCardServices { 
    my $pid = cat_("/tmp/cardmgr.pid");
    $pid and kill(15, chop_($pid)); # send SIGTERM
}

main(@ARGV);
