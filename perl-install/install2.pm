
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
use commands;
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
my @installStepsFields = qw(text redoable onError beginnerHidden needs entered reachable toBeDone help next done);
my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1, 0 ],
  selectInstallClass => [ __("Select installation class"), 1, 1, 0 ],
  setupSCSI          => [ __("Setup SCSI"), 1, 0, 0 ],
  selectPath         => [ __("Choose install or upgrade"), 0, 0, 0, "selectInstallClass" ],
  selectMouse        => [ __("Configure mouse"), 1, 1, 1, "selectPath" ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1, 0, "selectPath" ],
  partitionDisks     => [ __("Setup filesystems"), 1, 0, 0, "selectPath" ],
  formatPartitions   => [ __("Format partitions"), 1, -1, 0, "partitionDisks" ],
  choosePackages     => [ __("Choose packages to install"), 1, 1, 1, "selectPath" ],
  doInstallStep      => [ __("Install system"), 1, -1, 0, ["formatPartitions", "selectPath"] ],
  miscellaneous      => [ __("Miscellaneous"), 1, 1, 1 ],
  configureNetwork   => [ __("Configure networking"), 1, 1, 1, "formatPartitions" ],
  configureTimezone  => [ __("Configure timezone"), 1, 1, 0, "doInstallStep" ],
#-  configureServices => [ __("Configure services"), 0, 0, 0 ],
  configurePrinter   => [ __("Configure printer"), 1, 0, 0, "doInstallStep" ],
  setRootPassword    => [ __("Set root password"), 1, 1, 0, "formatPartitions" ],
  addUser            => [ __("Add a user"), 1, 1, 0, "doInstallStep" ],
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, 0, "doInstallStep" ],
  setupBootloader    => [ __("Install bootloader"), 1, 1, 0, "doInstallStep" ],
  configureX         => [ __("Configure X"), 1, 0, 0, ["formatPartitions", "setupBootloader"] ],
  exitInstall        => [ __("Exit install"), 0, 0, 1 ],
);

my (%installSteps, %upgradeSteps, @orderedInstallSteps, @orderedUpgradeSteps);

for (my $i = 0; $i < @installSteps; $i += 2) {
    my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
    $h{help}    = $help::steps{$installSteps[$i]} || __("Help");
    $h{previous}= $installSteps[$i - 2] if $i >= 2;
    $h{next}    = $installSteps[$i + 2];
    $h{entered} = 0;
    $h{onError} = $installSteps[$i + 2 * $h{onError}];
    $h{reachable} = !$h{needs};
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
  normal => my $b = [
    { mntpoint => "/",     size => 700 << 11, type => 0x83 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82 },
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
    mkbootdisk => 1, #- no mkbootdisk if 0 or undef, find a floppy with 1, or fd1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0, autoformat => 0 }, #- , readonly => 0
#-    security => 2,
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
    authentification => { md5 => 1, shadow => 1 },
    lang         => 'en',
    isUpgrade    => 0,
#-    installClass => "normal",

    timezone => {
#-                   timezone => "Europe/Paris",
#-                   GMT      => 1,
                },
    printer => {
                 want         => 0,
                 complete     => 0,
                 str_type     => $printer::printer_type_default,
                 QUEUE        => "lp",
                 SPOOLDIR     => "/var/spool/lpd/lp",
                 DBENTRY      => "PostScript",
                 PAPERSIZE    => "legal",
                 CRLF         => 0,
                 AUTOSENDEOF  => 1,

                 DEVICE       => "/dev/lp0",

                 REMOTEHOST   => "",
                 REMOTEQUEUE  => "",

                 NCPHOST      => "", #-"printerservername",
                 NCPQUEUE     => "", #-"queuename",
                 NCPUSER      => "", #-"user",
                 NCPPASSWD    => "", #-"pass",

                 SMBHOST      => "", #-"hostname",
                 SMBHOSTIP    => "", #-"1.2.3.4",
                 SMBSHARE     => "", #-"printername",
                 SMBUSER      => "", #-"user",
                 SMBPASSWD    => "", #-"passowrd",
                 SMBWORKGROUP => "", #-"AS3",
               },
#-    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },
#-    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },

#-    keyboard => 'de',
#-    display => "192.168.1.15:0",
    steps        => \%installSteps,
    orderedSteps => \@orderedInstallSteps,

#-GOLD    base => [ qw(basesystem sed initscripts console-tools mkbootdisk anacron utempter ldconfig chkconfig ntsysv mktemp setup filesystem SysVinit bdflush crontabs dev e2fsprogs etcskel fileutils findutils getty_ps grep groff gzip hdparm info initscripts isapnptools kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time tmpwatch util-linux vim-minimal vixie-cron which perl-base) ],
    base => [ qw(basesystem sed initscripts console-tools mkbootdisk anacron utempter ldconfig chkconfig ntsysv mktemp setup filesystem SysVinit bdflush crontabs dev e2fsprogs etcskel fileutils findutils getty_ps grep groff gzip hdparm info initscripts isapnptools kbdconfig kernel less ldconfig lilo logrotate losetup man mkinitrd mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash sed setconsole setserial shadow-utils sh-utils slocate stat sysklogd tar termcap textutils time tmpwatch util-linux vim-minimal vixie-cron which cpio perl) ],

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
    $o->selectLanguage($_[1] == 1);

    addToBeDone {
	lang::write($o->{prefix});
	keyboard::write($o->{prefix}, $o->{keyboard});
    } 'doInstallStep' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($clicked) = $_[0];

    add2hash($o->{mouse} ||= {}, { mouse::read($o->{prefix}) }) if $o->{isUpgrade} && !$clicked;

    $o->selectMouse($clicked);
    addToBeDone { 
	mouse::write($o->{prefix}, $o->{mouse});
	my $t = "modprobe usbmouse\n";
	substInFile { 
	    s/$t//;
	    $_ .= $t if eof;
	} "$o->{prefix}/etc/rc.d/rc.local" if $o->{mouse}{FULLNAME} =~ /USB/i;
    } 'doInstallStep';
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($clicked) = $_[0];

    return unless $o->{isUpgrade} || !$::beginner || $clicked;

    $o->{keyboard} = (keyboard::read($o->{prefix}))[0] if $o->{isUpgrade} && !$clicked && $o->{keyboard_unsafe};
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
    return
      $o->{fstab} = [
	{ device => "loop7", type => 0x83, mntpoint => "/", isFormatted => 1, isMounted => 1 },
	{ device => "/initrd/dos/lnx4win/swapfile", type => 0x82, mntpoint => "swap", isFormatted => 1, isMounted => 1 },
      ] if $o->{lnx4win};
    return if $o->{isUpgrade};

    $::o->{steps}{formatPartitions}{done} = 0;
    eval { fs::umount_all($o->{fstab}, $o->{prefix}) } if $o->{fstab} && !$::testing;

    my $ok = fsedit::get_root($o->{fstab} || []) ? 1 : install_any::getHds($o);
    my $auto = $ok && !$o->{partitioning}{readonly} &&
	($o->{partitioning}{auto_allocate} || $::beginner && fsedit::get_fstab(@{$o->{hds}}) < 4);

    eval { fsedit::auto_allocate($o->{hds}, $o->{partitions}) } if $auto;

    if ($auto && fsedit::get_root_($o->{hds}) && $_[1] == 1) {
	#- we have a root partition, that's enough :)
	$o->install_steps::doPartitionDisks($o->{hds});	
    } elsif ($o->{partitioning}{readonly}) {
	$o->ask_mntpoint_s($o->{fstab});
    } else {
	$o->doPartitionDisks($o->{hds}, $o->{raid} ||= {});
    }
    unless ($::testing) {
	$o->rebootNeeded foreach grep { $_->{rebootNeeded} } @{$o->{hds}};
    }
    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}, $o->{raid}) ];
    fsedit::get_root($o->{fstab}) or die _("Partitioning failed: no root filesystem");
}

sub formatPartitions {
    unless ($o->{lnx4win} || $o->{isUpgrade}) {
	$o->choosePartitionsToFormat($o->{fstab});

	unless ($::testing) {
	    $o->formatPartitions(@{$o->{fstab}});
	    fs::mount_all([ grep { isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
	    die _("Not enough swap to fulfill installation, please add some") if availableMemory < 40 * 1024;
	    fs::mount_all([ grep { isExt2($_) } @{$o->{fstab}} ], $o->{prefix});
	}
	eval { $o = $::o = install_any::loadO($o) } if $_[1] == 1;

    }
    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/sysconfig etc/sysconfig/console etc/sysconfig/network-scripts
	home mnt tmp var var/tmp var/lib var/lib/rpm);
    mkdir "$o->{prefix}/$_", 0700 foreach qw(root);

    eval { commands::cp("-f", "/etc/raidtab", "$o->{prefix}/etc/raidtab") } if !is_empty_hash_ref($o->{raid});
}

#------------------------------------------------------------------------------
sub choosePackages {
    $o->setPackages if $_[1] == 1;
    $o->selectPackagesToUpgrade($o) if $o->{isUpgrade} && $_[1] == 1;
    $o->choosePackages($o->{packages}, $o->{compss}, $o->{compssUsers}, $_[1] == 1);
    $o->{packages}{$_}{selected} = 1 foreach @{$o->{base}};
}

#------------------------------------------------------------------------------
sub doInstallStep {
    $o->readBootloaderConfigBeforeInstall if $_[1] == 1;

    #- some packages need such files for proper installation.
    install_any::write_ldsoconf($o->{prefix});
    fs::write($o->{prefix}, $o->{fstab});

    $o->beforeInstallPackages;
    $o->installPackages($o->{packages});
    $o->afterInstallPackages;
}
#------------------------------------------------------------------------------
sub miscellaneous {
    $o->{miscellaneous}{memsize} ||= $1 if first(cat_("/proc/cmdline")) =~ /mem=(\S+)/;
    $o->miscellaneous($_[0]); 
    addToBeDone { 
	install_any::fsck_option();
#-GOLD	run_program::rooted($o->{prefix}, "chkconfig --del kudzu") unless $o->{miscellaneous}{kudzu};
    } 'doInstallStep';
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($clicked) = @_;

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

    $o->configureNetwork;
}
#------------------------------------------------------------------------------
sub configureTimezone {
    my ($clicked) = @_;
    my $f = "$o->{prefix}/etc/sysconfig/clock";

    if ($o->{isUpgrade} && -r $f && -s $f > 0) {
	return if $_[1] == 1 && !$clicked;
	#- can't be done in install cuz' timeconfig %post creates funny things
	add2hash($o->{timezone}, { timezone::read($f) });
    }
    $o->{timezone}{GMT} = !$::beginner && !grep { isFat($_) } @{$o->{fstab}} unless exists $o->{timezone}{GMT};
    $o->timeConfig($f, $clicked);
}
#------------------------------------------------------------------------------
sub configureServices {
    return if $o->{lnx4win};

    $o->servicesConfig;
}
#------------------------------------------------------------------------------
sub configurePrinter  { $o->printerConfig   }
#------------------------------------------------------------------------------
sub setRootPassword {
    return if $o->{isUpgrade};

    $o->setRootPassword($_[0]);
    addToBeDone { install_any::setAuthentication() } 'doInstallStep';
}
#------------------------------------------------------------------------------
sub addUser {
    return if $o->{isUpgrade};

    $o->addUser($_[0]);
    install_any::setAuthentication();
}

#------------------------------------------------------------------------------
#-PADTODO
sub createBootdisk {
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');

    return if $o->{lnx4win};
    $o->createBootdisk($_[1] == 1);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    return if $o->{lnx4win} || $::g_auto_install;

    $o->setupBootloaderBefore if $_[1] == 1;
    $o->setupBootloader($_[1] - 1);
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

    my $cfg;
    my %cmdline; map { 
	my ($n, $v) = split '=';
	$cmdline{$n} = $v || 1;
    } split ' ', cat_("/proc/cmdline");

    my $opt; foreach (@_) {
	if (/^--?(.*)/) {
	    $cmdline{$opt} = 1 if $opt;
	    $opt = $1;
	} else {
	    $cmdline{$opt} = $_ if $opt;
	    $opt = '';
	}
    } $cmdline{$opt} = 1 if $opt;
    
    map_each {
	my ($n, $v) = @_;
	my $f = ${{
	    method    => sub { $o->{method} = $v },
	    pcmcia    => sub { $o->{pcmcia} = $v },
	    step      => sub { $o->{steps}{first} = $v },
	    expert    => sub { $o->{installClass} = 'expert'; $::expert = 1 },
	    beginner  => sub { $o->{installClass} = 'normal'; $::beginner = 1 },
	    lnx4win   => sub { $o->{lnx4win} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = 1 },
	    display   => sub { $o->{display} = $v },
	    security  => sub { $o->{security} = $v },
	    test      => sub { $::testing = 1 },
	    defcfg    => sub { $cfg = $v },
#	    ks        => sub { $::auto_install = 1; $cfg = $v; },
#	    kickstart => sub { $::auto_install = 1; $cfg = $v; },
	    auto_install => sub { $::auto_install = 1; $cfg = $v; },
	    simple_themes => sub { $o->{simple_themes} = 1 },
	    alawindows => sub { $o->{security} = $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    g_auto_install => sub { $::testing = $::g_auto_install = 1; $o->{partitioning}{auto_allocate} = 1 },
	}}{lc $n}; &$f if $f;
    } %cmdline;

    unlink "/sbin/insmod"  unless $::testing;
    unlink "/modules/pcmcia_core.o" unless $::testing; #- always use module from archive.
    unlink "/modules/i82365.o" unless $::testing;
    unlink "/modules/tcic.o" unless $::testing;
    unlink "/modules/ds.o" unless $::testing;

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running");
    log::ld("extra log messages are enabled");

    eval { spawnShell() };

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    $o->{root}   = $::testing ? "/tmp/root-perl-install" : "/";
    mkdir $o->{prefix}, 0755;
    mkdir $o->{root}, 0755;

    #-  make sure we don't pick up any gunk from the outside world
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin" unless $::g_auto_install;
    $ENV{LD_LIBRARY_PATH} = "";

    if ($::auto_install) {
	require 'install_steps_auto_install.pm';
    } else {
	require 'install_steps_graphical.pm';
    }
    eval { $o = $::o = install_any::loadO($o, $cfg) } if $cfg;

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;

    #-  make sure we don't pick up any gunk from the outside world
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{LD_LIBRARY_PATH} = "";

    #- needed very early for install_steps_graphical
    eval { $o->{mouse} ||= mouse::detect() };

    $::o = $o = $::auto_install ?
      install_steps_auto_install->new($o) :
      install_steps_graphical->new($o);

    $o->{netc} = network::read_conf("/tmp/network");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	my $l = network::read_interface_conf($file);
	add2hash(network::findIntf($o->{intf} ||= [], $l->{DEVICE}), $l);
    }

    modules::load_deps("/modules/modules.dep");
    modules::read_stage1_conf("/tmp/conf.modules");
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
	    unless (/^already displayed/ || /^ask_from_list cancel/) {
		eval { $o->errorInStep($_) };
		$@ and next;
	    }
	    $o->{step} = $o->{steps}{$o->{step}}{onError};
	    next MAIN unless $o->{steps}{$o->{step}}{reachable}; #- sanity check: avoid a step not reachable on error.
	    redo MAIN;
	}
	$o->{steps}{$o->{step}}{done} = 1;
	$o->leavingStep($o->{step});

	last if $o->{step} eq 'exitInstall';
    }
    substInFile { s|/sbin/mingetty tty1.*|/bin/bash --login| } "$o->{prefix}/etc/inittab" if $o->{security} < 1;

    fs::write($o->{prefix}, $o->{fstab});
    modules::write_conf("$o->{prefix}/etc/conf.modules", 'append');

    install_any::lnx4win_postinstall($o->{prefix}) if $o->{lnx4win};
    install_any::killCardServices();

    #- ala pixel? :-) [fpons]
    sync(); sync();

    #- remounting read-only may avoid error if kernel is unable to umount fs.
    install_any::remount_readonly($o, $o->{prefix});

    log::l("installation complete, leaving");
    print "\n" x 30;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
