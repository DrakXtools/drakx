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
 __("Choose the language which you approved. This one govern the language's system."),
selectPath => 
 __("Choose \"Installation\" if you never have installed Linux system on this computer or if you wish
to install several of them on this machine.

Choose \"Update\" if you wish to update a Linux system Mandrake 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or
 6.0 (Venus)."),
selectInstallClass => 
 __("Select:
  - Beginer: if you have never installed Linux system and wish to install the system elected 
\"Product of the year\" for 1999, click here.
  - Developer: if wish to use your Linux system to build software, you will find your happiness here.
  - Server: if you wish to install the operating system elected \"Distribution/Server\" for 1999,
choose this installation class.
  - Expert: if you alway know very fine GNU/Linux and that you wish to preserve the whole
control of the installation, this class is for you."),
setupSCSI => 
 __("The system did not detect a SCSI card. If you have one (or several) click on \"Yes\" and choose the module
to be tested. In the contrary case, cliquez on \"Not\".

If you don't know if you have interfaces SCSI, consult the documentation delivered with your computer
or, if you use Microsoft Windows 95/98, consult the file \"Peripheral manager\" of the item \"System\"
 of the \"Control panel\"."),
partitionDisks => 
 __("In this stage, you will must partion your hard disk. It consists in cutting your disk in several zones
(which are not equal). This operation, for spectacular and intimidating that it is,
 is not hardly if you be carrefull so that you do. 
Also, take your time, are sure you before click on \"Finishing\" and READ the handbook of DiskDrake
before use them."),

#"In this stage, you must partition your hard disk. Partitioning is the
#division of space on the hard disk into zones (which need not be equal) and
#certain types of software are installed in certain partitions. This
#operation, while both spectacular and intimidating, is not difficult to do
#if you understand what your system needs and what you need to do in the
#process. If you are uncertain, read the DiskDrake handbook and the
#Partitioning HOWTO before you proceed. Be cautious during this step. If you
#make an error, consult the DiskDrake handbook as to how to go about
#correcting it."

formatPartitions => 
 __("The partitions lately created must be formatted so that the system can use them.
You can also format partitions before created and used if you wish to remove all the data which
contain. Note that it is not necessary to format the partitions created before used if they contain data to
which you want to keep (typical cases: / home and / usr/local)."),
choosePackages => 
 __("You now have the possibility of choosing the software which you wish to install.

Please note that packages manage the dependences: that means that if you wish to install
a software requiring the presence of another software, this last will be automatically selected
and that it will be impossible for you to install the first without installing the second.

Information on each category of packages and each one of enter of them are available in zone \"Infos\"
located above buttons of confirmation/selection/deselection."),
doInstallStep => 
 __("Selected packages are now getting installed on your system. This operation take only a few minutes."),
setRootPassword => 
 __("The system now requires an administrator password for your Linux system.
This passwd is required of you by twice in order to being certain of its spelling.

Choose it carefully because it mainly conditions the good functioning of your system.
Indeed, only the administrator (also named \"root\") is able to configure the computer.
The password should not be too simple so that whoever cannot be connected under this account.
It should not be either too sophisticated under penalty of being difficult to retain and, finally, forgotten.

When you wish to connect yourselves on your Linux system as an administrator, the \"login\" 
is \"root\" and the \"passswrd\", this one which you now will indicate."),
addUser => 
 __("You can now authorize one or more people to be connected on your Linux system. Each one of
them will profit from his own environment will be able to configure.

It is very important that you create at least one user even if you are the only person who will connect
herself on this machine. Indeed, if runnig the system as \"root\" is attractive, that 
is a very bad idea. This last having all the rights it is certain that at one time you will broke all.
This is highly preferable you connect as simple user and that you use the account \"root\" only when
that is essential."),
doInstallStep => 
 __("The system being now copied on your disk, he is now time to indicate to him from where he will have to start.
With less than you know exactly what you do, always choose \"First sector of drive\"."),

configureX => 
 __("It is now time to configure the graphic server. First of all, choose your monitor. You have then
the possibility of testing your configuration and of reconsidering your choices if the latter are not
appropriate to you."),
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
#  configureTimezone => [ __("Configure timezone"), 0, 0 ],
#  configureServices => [ __("Configure services"), 0, 0 ],
#  configurePrinter => [ __("Configure printer"), 0, 0 ],
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
    lang => 'us',
    isUpgrade => 0,
    installClass => 'beginner',
#    display => "192.168.1.9:0",

    bootloader => { onmbr => 1, linear => 0 },
    autoSCSI => 0,
    mkbootdisk => 0,
    packages => [ qw() ],
    partitionning => { clearall => $::testing, eraseBadPartitions => 1, auto_allocate => 0, autoformat => 0 },
    partitions => [
		   { mntpoint => "/boot", size =>  16 << 11, type => 0x83 }, 
		   { mntpoint => "/",     size => 300 << 11, type => 0x83 }, 
		   { mntpoint => "swap",  size =>  64 << 11, type => 0x82 },
#		   { mntpoint => "/usr",  size => 400 << 11, type => 0x83, growable => 1 }, 
	     ],
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash) ],
};
$o = $::o = { 
#    lang => 'fr',
#    isUpgrade => 0,
#    installClass => 'beginner',

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
    $o->createBootdisk;
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
