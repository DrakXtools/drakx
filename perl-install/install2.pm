#!/usr/bin/perl

# $o->{hints}->{component} *was* 'Workstation' or 'Server' or NULL

use diagnostics;
use strict;
use vars qw($testing $error $cancel $INSTALL_VERSION);

use lib qw(/usr/bin/perl-install . c/blib/arch);
use c;
use common qw(:common :file :system);
use devices;
use log;
use net;
use keyboard;
use pkgs;
use smp;
use fs;
use setup;
use fsedit;
use install_methods;
use lilo;
use swap;
use install_steps_graphical;
use modules;
use partition_table qw(:types);
use detect_devices;
use commands;

$error = 0;
$cancel = 0;
$testing = $ENV{PERL_INSTALL_TEST};
$INSTALL_VERSION = 0;

my @installStepsFields = qw(text skipOnCancel skipOnLocal prev next);
my @installSteps = (
  selectPath => [ "Select installation path", 0, 0, 'none' ],
  selectInstallClass => [ "Select installation class", 0, 0 ],
  setupSCSI => [ "Setup SCSI", 0, 1 ],	
  partitionDisks => [ "Setup filesystems", 0, 1 ],
  findInstallFiles => [ "Find installation files", 1, 0 ],
  choosePackages => [ "Choose packages to install", 0, 0 ],
  doInstallStep => [ "Install system", 0, 0 ],
#  configureMouse => [ "Configure mouse", 0, 0 ],
  finishNetworking => [ "Configure networking", 0, 0 ],
#  configureTimezone => [ "Configure timezone", 0, 0 ],
#  configureServices => [ "Configure services", 0, 0 ],
#  configurePrinter => [ "Configure printer", 0, 0 ],
  setRootPassword => [ "Set root password", 0, 0 ],
  addUser => [ "Add a user", 0, 0 ],
  configureAuth => [ "Configure authentication", 0, 0 ],
  createBootdisk => [ "Create bootdisk", 0, 1 ],
  setupBootloader => [ "Install bootloader", 0, 1 ],
#  configureX => [ "Configure X", 0, 0 ],
  exitInstall => [ "Exit install", 0, 0, undef, 'done' ],
);

# this table is translated at run time
my %upgradeSteps = (
  selectPath => [ "Select installation path", 0, 0 , 'none' ],
  setupSCSI => [ "Setup SCSI", 0, 0 ],
  upgrFindInstall => [ "Find current installation", 0, 0 ],
  findInstallFiles => [ "Find installation files", 1, 0 ],
  upgrChoosePackages => [ "Choose packages to upgrade", 0, 0 ],
  doInstallStep => [ "Upgrade system", 0, 0 ],
  createBootdisk => [ "Create bootdisk", 0, 0 , 'none' ],
  setupBootloader => [ "Install bootloader", 0, 0 ],
  exitInstall => [ "Exit install", 0, 0 , undef, 'done' ],
);

for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{prev} ||= $installSteps[$i - 2];
    $h{next} ||= $installSteps[$i + 2];
    $installSteps{ $installSteps[$i] } = \%h;
}
$installSteps{first} = $installSteps[0];
for (my $i = 0; $i < @upgradeSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $upgradeSteps[$i + 1] };
    $h{prev} ||= $upgradeSteps[$i - 2];
    $h{next} ||= $upgradeSteps[$i + 2];
    $upgradeSteps{ $upgradeSteps[$i] } = \%h;
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

my $o = {};
my $default = {
    display => "129.104.42.9:0",
    user => { name => 'foo', password => 'foo', shell => '/bin/bash', realname => 'really, it is foo' },
    rootPassword => 'toto',
    keyboard => 'us',
    isUpgrade => 0,
    installClass => 'Server',
    bootloader => { onmbr => 1,
		    linear => 1,
		},
    mkbootdisk => 0,
    comps => [ qw() ],
    packages => [ qw() ],
    partitions => [
		   { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		   { mntpoint => "/",     size => 300 << 11, type => 0x83 }, 
		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 }, 
		   { mntpoint => "swap",  size =>  64 << 11, type => 0x82 }
	     ],
};



sub selectPath {
    $o->{steps} = $o->{isUpgrade} ? \%upgradeSteps : \%installSteps;
}

sub selectInstallClass {
#    my @choices = qw(Workstation Server Custom);

    $o->{installClass} eq 'Custom' and return;

    $o->{bootloader}->{onmbr} = 1;
    $o->{bootloader}->{uselinear} = 1;

    foreach (qw(skipntsysv autoformat nologmessage auth autoswap skipbootloader forceddruid)) {
	$o->{hints}->{flags}->{$_} = 1;
    }
    $o->{hints}->{auth}->{shadow} = 1;
    $o->{hints}->{auth}->{md5} = 1;

    if ($o->{installClass} eq 'Server') {
	$o->{hints}->{flags}->{skipprinter} = 1;
	$o->{hints}->{flags}->{skipresize} = 1;
	$o->{hints}->{partitioning}->{flags}->{clearall} = 1; 
	$o->{hints}->{partitioning}->{attempts} = 'serverPartitioning';
    } else { #  workstation 
	$o->{hints}->{flags}->{autoscsi} = 1;
	$o->{hints}->{partitioning}->{flags}->{clearlinux} = 1; 
    }
}

sub setupSCSI {
    $o->{direction} < 0 && detect_devices::hasSCSI() and return cancel();

    # If we have any scsi adapters configured from earlier, then don't bother asking again
    while (my ($k, $v) = each %modules::loaded) {
	$v->{type} eq 'scsi' and return;
    }
    #setupSCSIInterfaces(0, \%modules::loaded, $o->{hints}->{flags}->{autoscsi}, $o->{direction});
}

sub partitionDisks {
    $o->{drives} = [ detect_devices::hds() ];
    $o->{hds} = fsedit::hds($o->{drives}, $o->{hints}->{partitioning}->{flags});
    @{$o->{hds}} > 0 or die "An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem";

    unless ($o->{isUpgrade}) {
	$o->{install}->doPartitionDisks($o->{hds}, $o->{fstab_wanted});

	# Write partitions to disk 
	foreach (@{$o->{hds}}) { partition_table::write($_); }
    }

    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}) ];

    my $root_fs; map { $_->{mntpoint} eq '/' and $root_fs = $_ } @{$o->{fstab}};                  
    $root_fs or die "partitionning failed: no root filesystem";

    if ($o->{hints}->{flags}->{autoformat}) {
	log::l("formatting all filesystems");

	foreach (@{$o->{fstab}}) {
	    fs::format_part($_) if $_->{mntpoint} && isExt2($_) || isSwap($_);
	}
    }
    fs::mount_all($o->{fstab}, '/mnt');
}

sub findInstallFiles {
    $o->{packages} = $o->{method}->getPackageSet() and
	$o->{comps} = $o->{method}->getComponentSet($o->{packages});
}
 
sub choosePackages {
#    $o->{hints}->{component} && $o->{direction} < 0 and return cancel();

    $o->{install}->choosePackages($o->{packages}, $o->{comps}, $o->{isUpgrade});
}

sub doInstallStep {
    $testing and return 0;

    $o->{install}->beforeInstallPackages($o->{method}, $o->{fstab});
    $o->{install}->installPackages($o->{rootPath}, $o->{method}, $o->{packages}, $o->{isUpgrade});
    $o->{install}->afterInstallPackages($o->{rootPath}, $o->{keyboard}, $o->{isUpgrade});
}

sub configureMouse { setup::mouseConfig($o->{rootPath}); }

sub finishNetworking {
#
#    rc = checkNetConfig(&$o->{intf}, &$o->{netc}, &$o->{intfFinal},
#			 &$o->{netcFinal}, &$o->{driversLoaded}, $o->{direction});
#
#    if (rc) return rc;
#
#    sprintf(path, "%s/etc/sysconfig", $o->{rootPath});
#    writeNetConfig(path, &$o->{netcFinal}, 
#		    &$o->{intfFinal}, 0);
#    strcat(path, "/network-scripts");
#    writeNetInterfaceConfig(path, &$o->{intfFinal});
#    sprintf(path, "%s/etc", $o->{rootPath});
#    writeResolvConf(path, &$o->{netcFinal});
#
#    #  this is a bit of a hack 
#    writeHosts(path, &$o->{netcFinal}, 
#		&$o->{intfFinal}, !$o->{isUpgrade});
#
#    return 0;
}

sub configureTimezone { setup::timeConfig($o->{rootPath}) }
sub configureServices { setup::servicesConfig($o->{rootPath}) }

sub setRootPassword {
    $testing and return 0;

    $o->{install}->setRootPassword($o->{rootPath});
}

sub addUser {
    $o->{install}->addUser($o->{rootPath});
}

sub createBootdisk {
    $o->{isUpgrade} or fs::write('mnt', $o->{fstab});
    modules::write_conf("/mnt/etc/conf.modules", 'append');

    $o->{mkbootdisk} and lilo::mkbootdisk("/mnt", versionString());
}

sub setupBootloader {
    my $versionString = versionString();
    log::l("installed kernel version $versionString");
    
    $o->{isUpgrade} or modules::read_conf("/mnt/etc/conf.modules");
   
    lilo::install("/mnt", $o->{hds}, $o->{fstab}, $versionString, $o->{bootloader});
}

sub configureX { $o->{install}->setupXfree($o->{method}, $o->{rootPath}, $o->{packages}); }

sub exitInstall { 1 }

sub upgrFindInstall {
#    int rc;
#
#    if (!$o->{table}.parts) { 
#	 rc = findAllPartitions(NULL, &$o->{table});
#	 if (rc) return rc;
#    }
#
#    umountFilesystems(&$o->{fstab});
#    
#    #  rootpath upgrade support 
#    if (strcmp($o->{rootPath} ,"/mnt"))
#	 return INST_OKAY;
#    
#    #  this also turns on swap for us 
#    rc = readMountTable($o->{table}, &$o->{fstab});
#    if (rc) return rc;
#
#    if (!testing) {
#	 mountFilesystems(&$o->{fstab});
#
#	 if ($o->{method}->prepareMedia) {
#	     rc = $o->{method}->prepareMedia($o->{method}, &$o->{fstab});
#	     if (rc) {
#		 umountFilesystems(&$o->{fstab});
#		 return rc;
#	     }
#	 }
#    }
#
#    return 0;
}

sub upgrChoosePackages {
#    static int firstTime = 1;
#    char * rpmconvertbin;
#    int rc;
#    char * path;
#    char * argv[] = { NULL, NULL };
#    char buf[128];
#
#    if (testing)
#	 path = "/";
#    else
#	 path = $o->{rootPath};
#
#    if (firstTime) {
#	 snprintf(buf, sizeof(buf), "%s%s", $o->{rootPath},
#		  "/var/lib/rpm/packages.rpm");
#	 if (access(buf, R_OK)) {
#	 snprintf(buf, sizeof(buf), "%s%s", $o->{rootPath},
#		  "/var/lib/rpm/packages");
#	     if (access(buf, R_OK)) {
#		 errorWindow("No RPM database exists!");
#		 return INST_ERROR;
#	     }
#
#	     if ($o->{method}->getFile($o->{method}, "rpmconvert", 
#		     &rpmconvertbin)) {
#		 return INST_ERROR;
#	     }
#
#	     symlink("/mnt/var", "/var");
#	     winStatus(35, 3, _("Upgrade"), _("Converting RPM database..."));
#	     chmod(rpmconvertbin, 0755);
#	     argv[0] = rpmconvertbin;
#	     rc = runProgram(RUN_LOG, rpmconvertbin, argv);
#	     if ($o->{method}->rmFiles)
#		 unlink(rpmconvertbin);
#
#	     newtPopWindow();
#	     if (rc) return INST_ERROR;
#	 }
#	 winStatus(35, 3, "Upgrade", _("Finding packages to upgrade..."));
#	 rc = ugFindUpgradePackages(&$o->{packages}, path);
#	 newtPopWindow();
#	 if (rc) return rc;
#	 firstTime = 0;
#	 psVerifyDependencies(&$o->{packages}, 1);
#    }
#
#    return psSelectPackages(&$o->{packages}, &$o->{comps}, NULL, 0, 1);
}


sub versionString {
    my $kernel = $o->{packages}->{kernel} or die "I couldn't find the kernel package!";
    
    c::headerGetEntry($kernel->{header}, 'version') . "-" .
    c::headerGetEntry($kernel->{header}, 'release');
}

sub getNextStep {
    my ($lastStep) = @_;

    $error and die "an error occured in step $lastStep";
    $cancel and die "cancel called in step $lastStep";

    $o->{direction} = 1;

    return $o->{lastChoice} = $o->{steps}->{$lastStep}->{next};
}

sub doSuspend {
    $o->{exitOnSuspend} and exit(1);

    if (my $pid = fork) {
	waitpid $pid, 0;
    } else {
	print "\n\nType <exit> to return to the install program.\n\n";
	exec {"/bin/sh"} "-/bin/sh";
	warn "error execing /bin/sh";
	sleep 5;
	exit 1;
    }
}


sub spawnShell {
    $testing and return;

    -x "/bin/sh" or log::l("cannot open shell - /usr/bin/sh doesn't exist"), return;

    fork and return;

    local *F;
    sysopen F, "/dev/tty2", 2 or log::l("cannot open /dev/tty2 -- no shell will be provided"), return;

    open STDIN, "<&F" or die;
    open STDOUT, ">&F" or die;
    open STDERR, ">&F" or die;
    close F;

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    exec {"/bin/sh"} "-/bin/sh" or log::l("exec of /bin/sh failed: $!");
}

sub main {

    #  if this fails, it's okay -- it might help with free space though 
    unlink "/sbin/install";

    print STDERR "in second stage install\n";

    $o->{rootPath} = "/mnt";

    $o->{method} = install_methods->new('cdrom');
    $o->{install} = install_steps_graphical->new($o);

    unless ($testing || $o->{localInstall}) {
	if (fork == 0) {
	    while (1) { sleep(30); sync(); }
	}
    }
    $o->{exitOnSuspend} = $o->{localInstall} || $testing;

    log::openLog(($testing || $o->{localInstall}) && 'debug.log');

    log::l("second stage install running (version $INSTALL_VERSION)");

    log::ld("extra log messages are enabled");

    $o->{rootPath} eq '/mnt' and spawnShell();

#    chooseLanguage('fr');

    $o->{netc} = net::readNetConfig("/tmp");

    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	$o->{intf} = net::readNetInterfaceConfig($file);
    }

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles_();
    log::l("\tdone");

    modules::load_deps("/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    #  make sure we don't pick up any gunk from the outside world 
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin";
    $ENV{LD_LIBRARY_PATH} = "";

    $o->{keyboard} = keyboard::read("/tmp/keyboard") || $default->{keyboard};

    for (my $step = $o->{steps}->{first}; $step ne 'done'; $step = getNextStep($step)) {
	log::l("entering step $step");
	&{$main::{$step}}() and $o->{steps}->{completed} = 1;
	log::l("step $step finished");
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
