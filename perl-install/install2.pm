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


my %stepsHelp = (

selectLanguage => 
 __("Choose preferred language for install and system usage."),

selectPath => 
 __("Choose \"Installation\" if there are no previous versions of Linux
installed, or if you wish use to multiple distributions or versions.

Choose \"Update\" if you wish to update a previous version of Mandrake
Linux: 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or 6.0 (Venus)."),

selectInstallClass => 
 __("Select:
  - Beginner: If you have not installed Linux before, or wish to install
the distribution elected \"Product of the year\" for 1999, click here.
  - Developer: If you are familiar with Linux and will be using the
computer primarily for software development, you will find happiness
here.
  - Server: If you wish to install a general purpose server, or the
Linux distribution elected \"Distribution/Server\" for 1999, select
this.
  - Expert: If you know GNU/Linux and want to perform a highly
customized installation, this Install Class is for you."),

setupSCSI => 
 __("The system did not detect a SCSI card. If you have one (or several)
click on \"Yes\" and choose the module(s) to be tested. Otherwise, 
select \"No\".

If you don't know if your computer has SCSI interfaces, consult the
original documentation delivered with the computer, or if you use
Microsoft Windows 95/98, inspect the information available via the \"Control
panel\", \"System's icon, \"Device Manager\" tab."),

partitionDisks => 
 __("At this point, hard drive partitions must be defined. (Unless you
are overwriting a previous install of Linux and have already defined
your hard drives partitions as desired.) This operation consists of
logically dividing the computer's hard drive capacity into separate
areas for use. Two common partition are: \"root\" which is the point at
which the filesystem's directory structure starts, and \"boot\", which
contains those files necessary to start the operating system when the
computer is first turned on. Because the effects of this process are
usually irreversible, partitioning can be intimidating and stressful to
the inexperienced. DiskDrake simplifies the process so that it need not
be. Consult the documentation and take your time before proceeding."),

formatPartitions => 
 __("Any partitions that have been newly defined must be formatted for
use. At this time, you may wish to re-format some pre-existing
partitions to erase the data they contain. Note: it is not necessary to
re-format pre-existing partitions, particularly if they contain files or
data you wish to keep. Typically retained are: /home and /usr/local."),

choosePackages => 
 __("You may now select the packages you wish to install.

Please note that some packages require the installation of others. These
are referred to as package dependencies. The packages you select, and
the packages they require will automatically be added to the
installation configuration. It is impossible to install a package
without installing all of its dependencies.

Information on each category and specific package is available in the
area titled \"Info\". This is located above the buttons: [confirmation]
[selection] [unselection]."),

doInstallStep => 
 __("The packages selected are now being installed. This operation
should only take a few minutes."),

configureMouse => 
 __("Help"),

configureNetwork =>
 __("Help"),

configureTimezone =>
 __("Help"),

configureServices =>
 __("Help"),

configurePrinter =>
 __("Help"),

setRootPassword => 
 __("An administrator password for your Linux system must now be
assigned. The password must be entered twice to verify that both
password entries are identical.

Choose this password carefully. Only persons with access to an
administrator account can maintain and administer the system.
Alternatively, unauthorized use of an administrator account can be
extremely dangerous to the integrity of the system, the data upon it,
and other systems with which it is interfaced. The password should be a
mixture of alphanumeric characters and a least 8 characters long. It
should never be written down. Do not make the password too long or
complicated that it will be difficult to remember.

When you login as Administrator, at \"login\" type \"root\" and at
\"password\", type the password that was created here."),

addUser =>
 __("You can now authorize one or more people to use your Linux
system. Each user account will have their own customizable environment.

It is very important that you create a regular user account, even if 
there will only be one principle user of the system. The administrative
\"root\" account should not be used for day to day operation of the
computer.  It is a security risk.  The use of a regular user account
protects you and the system from yourself. The root account should only
be used for administrative and maintenance tasks that can not be
accomplished from a regular user account."),

createBootdisk =>
 __("Help"),

setupBootloader =>
 __("You need to indicate where you wish
to place the information required to boot to Linux.

Unless you know exactly what you are doing, choose \"First sector of
drive\"."),

configureX => 
 __("It is now time to configure the video card and monitor
configuration for the X windows Graphic User Interface (GUI). First
select your monitor. Next, you may test the configuration and change
your selections if necessary."),
exitInstall =>
 __("Help"),
);


my @installStepsFields = qw(text redoable onError needs);
my @installSteps = (
  selectLanguage => [ __("Choose your language"), 1, 1 ],
  selectPath => [ __("Choose install or upgrade"), 0, 0 ],
  selectInstallClass => [ __("Select installation class"), 1, 1, "selectPath" ],
  setupSCSI => [ __("Setup SCSI"), 1, 0 ],	
  partitionDisks => [ __("Setup filesystems"), 1, 0 ],
  formatPartitions => [ __("Format partitions"), 1, -1, "partitionDisks" ],
  choosePackages => [ __("Choose packages to install"), 1, 1, "selectInstallClass" ],
  doInstallStep => [ __("Install system"), 1, -1, ["formatPartitions", "selectPath"] ],
  configureMouse => [ __("Configure mouse"), 1, 1, "formatPartitions" ],
  configureNetwork => [ __("Configure networking"), 1, 1, "formatPartitions" ],
  configureTimezone => [ __("Configure timezone"), 0, 0 ],
  configureServices => [ __("Configure services"), 0, 0 ],
  configurePrinter => [ __("Configure printer"), 0, 0 ],
  setRootPassword => [ __("Set root password"), 1, 1, "formatPartitions" ],
  addUser => [ __("Add a user"), 1, 1, "formatPartitions" ],
  createBootdisk => [ __("Create bootdisk"), 1, 0, "doInstallStep" ],
  setupBootloader => [ __("Install bootloader"), 1, 1, "doInstallStep" ],
  configureX => [ __("Configure X"), 1, 0, "doInstallStep" ],
  exitInstall => [ __("Exit install"), 0, 0, "alldone" ],
);
my (%installSteps, %upgradeSteps, @orderedInstallSteps, @orderedUpgradeSteps);
for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{help} = $stepsHelp{$installSteps[$i]} || __("Help");
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

    bootloader => { onmbr => 1, linear => 0 },
    autoSCSI => 0,
    mkbootdisk => "fd0", # no mkbootdisk if 0 or undef,   find a floppy with 1
    packages => [ qw() ],
    partitioning => { clearall => $::testing, eraseBadPartitions => 0, auto_allocate => 0, autoformat => 0 },
    partitions => [
		   { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		   { mntpoint => "/",     size => 300 << 11, type => 0x83 }, 
		   { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 }, 
	     ],
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash ksh) ],
};
$o = $::o = { 
    lang => 'us',
    isUpgrade => 0,
    installClass => 'beginner',

#    intf => [ { DEVICE => "eth0", IPADDR => '1.2.3.4', NETMASK => '255.255.255.128' } ],
    default => $default, 
    steps => \%installSteps, 
    orderedSteps => \@orderedInstallSteps,

    # for the list of fields available for user and superuser, see @etc_pass_fields in install_steps.pm
#    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },
#    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },

    base => [ qw(basesystem initscripts console-tools mkbootdisk linuxconf anacron linux_logo rhs-hwdiag utempter ldconfig chkconfig ntsysv mktemp setup setuptool filesystem MAKEDEV SysVinit ash at authconfig bash bdflush binutils console-tools crontabs dev e2fsprogs ed etcskel file fileutils findutils getty_ps gpm grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time timeconfig tmpwatch util-linux vim-minimal vixie-cron which) ],
};


sub selectLanguage {
    lang::set($o->{lang} = $o->chooseLanguage);
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
}

sub setupSCSI {
    $o->{autoSCSI} ||= $o->{installClass} eq "beginner";
    $o->setupSCSI($o->{autoSCSI} && !$_[0]);
}

sub partitionDisks {
    $o->{drives} = [ detect_devices::hds() ];
    $o->{hds} = fsedit::hds($o->{drives}, $o->{default}{partitioning});
    unless (@{$o->{hds}} > 0) {
	$o->setupSCSI if $o->{autoSCSI}; # ask for an unautodetected scsi card
    }
    unless (@{$o->{hds}} > 0) { # no way
	die _("An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    unless ($o->{isUpgrade}) {
	eval { fsedit::auto_allocate($o->{hds}, $o->{partitions}) } if $o->{default}{partitioning}{auto_allocate};
	$o->doPartitionDisks($o->{hds});

	unless ($::testing) {
	    $o->rebootNeeded foreach grep { $_->{rebootNeeded} } @{$o->{hds}};
	}
    }

    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}) ];

    my $root_fs; map { $_->{mntpoint} eq '/' and $root_fs = $_ } @{$o->{fstab}};
    $root_fs or die _("partitioning failed: no root filesystem");

}

sub formatPartitions {
    $o->choosePartitionsToFormat($o->{fstab});

    unless ($::testing) {
	$o->formatPartitions(@{$o->{fstab}});
	fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
    }
    mkdir "$o->{prefix}/$_", 0755 foreach qw(dev etc etc/sysconfig etc/sysconfig/network-scripts 
                                             home mnt tmp var var/tmp var/lib var/lib/rpm); #)
}

sub choosePackages {
    install_any::setPackages($o) if $o->{steps}{$o->{step}}{entered} == 1;
    $o->choosePackages($o->{packages}, $o->{compss}); 
    $o->{packages}{$_}{base} = 1 foreach @{$o->{base}};
}

sub doInstallStep {
    install_any::setPackages($o) unless $o->{steps}{choosePackages}{entered};
    $o->beforeInstallPackages;
    $o->installPackages($o->{packages});
    $o->afterInstallPackages;
}

sub configureMouse { $o->mouseConfig }
sub configureNetwork { $o->configureNetwork($o->{steps}{$o->{step}}{entered} == 1 && !$_[0]) }
sub configureTimezone { $o->timeConfig }
sub configureServices { $o->servicesConfig }
sub setRootPassword { $o->setRootPassword }
sub addUser { 
    $o->addUser;
    addToBeDone {
	run_program::rooted($o->{prefix}, "pwconv") or log::l("pwconv failed"); # use shadow passwords
    } 'doInstallStep';
}

sub createBootdisk {
    fs::write($o->{prefix}, $o->{fstab}) unless $o->{isUpgrade};
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');
    $o->createBootdisk($o->{steps}{$o->{step}}{entered} == 1);
}

sub setupBootloader {
    $o->{isUpgrade} or modules::read_conf("$o->{prefix}/etc/conf.modules");
    $o->setupBootloader;
}
sub configureX {
    $o->setupXfree if $o->{packages}{XFree86}{installed} || $_[0];
}
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
    $o->{mouse} = install_any::mouse_detect() unless $::testing || $o->{mouse};

    $o = install_steps_graphical->new($o);

    $o->{netc} = network::read_conf("/tmp/network");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	my $l = network::read_interface_conf($file);
	add2hash(network::findIntf($o->{intf} ||= [], $l->{DEVICE}), $l);
    }

    modules::load_deps("/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    while (@_) {
	local $_ = shift;
	if (/--method/) {
	    $_ = shift;
	    if (/ftp/) {
		require 'ftp.pm';
		local $^W = 0;
		*install_any::getFile = \&ftp::getFile;
	    }
	}
    }

    my $clicked = 0;
    for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->enteringStep($o->{step});
	$o->{steps}{$o->{step}}{entered}++;
	eval { 
	    &{$install2::{$o->{step}}}($clicked);
	};
	$clicked = 0;
	$@ =~ /^setstep (.*)/ and $o->{step} = $1, $clicked = 1, redo;
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
