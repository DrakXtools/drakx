package install2;

use diagnostics;
use strict;
use vars qw($testing $INSTALL_VERSION $o);

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

$::testing = $ENV{PERL_INSTALL_TEST};
$INSTALL_VERSION = 0;

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
#  configureX => [ __("Configure X"), __("help"), 0, 0 ],
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
    lang => 'fr',
    isUpgrade => 0,
    installClass => 'Server',
    bootloader => { onmbr => 1, linear => 0 },
    mkbootdisk => 0,
    base => [ qw(basesystem console-tools mkbootdisk linuxconf anacron linux_logo rhs-hwdiag utempter ldconfig chkconfig ntsysv mktemp setup setuptool filesystem MAKEDEV SysVinit ash at authconfig bash bdflush binutils console-tools crontabs dev e2fsprogs ed etcskel file fileutils findutils getty_ps gpm grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time timeconfig tmpwatch util-linux vim-minimal vixie-cron which) ],
    comps => [ 
	      [ 0, __('X Window System') => qw(XFree86 XFree86-xfs XFree86-75dpi-fonts) ],
	      [ 0, __('KDE') => qw(kdeadmin kdebase kthememgr kdegames kjumpingcube kdegraphics kdelibs kdemultimedia kdenetwork kdesupport kdeutils kBeroFTPD kdesu kdetoys kpilot kcmlaptop kdpms kpppload kmpg) ],
	      [ 0, __('Console Multimedia') => qw(aumix audiofile esound sndconfig awesfx rhsound cdp mpg123 svgalib playmidi sox mikmod) ],
	      [ 0, __('CD-R burning and utilities') => qw(mkisofs cdrecord cdrecord-cdda2wav cdparanoia xcdroast) ],
	      [ 0, __('Games') => qw(xbill xboard xboing xfishtank xgammon xjewel xpat2 xpilot xpuzzles xtrojka xkobo freeciv) ],
	     ],
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
    keyboard::setup();
}

sub selectPath {
    $o->{isUpgrade} = $o->selectInstallOrUpgrade;
    $o->{steps}        = $o->{isUpgrade} ? \%upgradeSteps : \%installSteps;
    $o->{orderedSteps} = $o->{isUpgrade} ? \@orderedUpgradeSteps : \@orderedInstallSteps;

    $o->{comps} = [ @{$o->{default}->{comps}} ];
    foreach (@{$o->{comps}}) {
	my ($selected, $name, @packages) = @$_;
	$_ = { selected => $selected, name => $name, packages => \@packages };
    }
}

sub selectInstallClass {
    $o->{installClass} = $o->selectInstallClass;

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
    @{$o->{hds}} > 0 or die _"An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem";

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
    $root_fs or die _"partitionning failed: no root filesystem";

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
    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    $o->{packages} = pkgs::psUsingDirectory();
    pkgs::getDeps($o->{packages});
}
 
sub choosePackages {
    foreach (@{$o->{default}->{base}}) { pkgs::select($o->{packages}, $_) }
    $o->choosePackages($o->{packages}, $o->{comps}); 

    my @p = @{$o->{default}->{base}}, grep { $_->{selected} } @{$o->{comps}};
    push @p, "kernel-smp" if smp::detect();

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
sub addUser { $o->addUser }

sub createBootdisk {
    $::testing and return;
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
_"Congratulations, installation is complete.
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

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running (version $INSTALL_VERSION)");
    log::ld("extra log messages are enabled");

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;

    #  make sure we don't pick up any gunk from the outside world 
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{LD_LIBRARY_PATH} = "";

    spawnSync();
    eval { spawnShell() };

    $o = install_steps_graphical->new($o);

    $o->{netc} = net::readNetConfig("/tmp");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	$o->{intf} = net::readNetInterfaceConfig($file);
    }

    modules::load_deps("/modules/modules.dep");
    modules::read_conf("/tmp/conf.modules");

    for (my $step = $o->{steps}->{first}; $step ne 'done'; $step = getNextStep($step)) {
	$o->enteringStep($step);
	eval { &{$install2::{$step}}() };
	$@ and $o->warn($@);
	$o->leavingStep($step);
    }
    killCardServices();

    log::l("installation complete, leaving");

    <STDIN> unless $::testing;
}

sub killCardServices { 
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); # send SIGTERM
}
