
package install2;

use diagnostics;
use strict;
use Data::Dumper;

use vars qw($o $version);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system :functional);
use install_any qw(:all);
use log;
use commands;
use network;
use lang;
use keyboard;
use mouse;
use fs;
use raid;
use fsedit;
use devices;
use partition_table qw(:types);
use modules;
use detect_devices;
use run_program;

use install_steps;
#use install_steps_interactive;

#-######################################################################################
#- Steps table
#-######################################################################################
$::VERSION = "7.0";

my (%installSteps, @orderedInstallSteps);
{    
    my @installStepsFields = qw(text redoable onError hidden needs); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1, '' ],
  selectInstallClass => [ __("Select installation class"), 1, 1, '' ],
  setupSCSI          => [ __("Setup SCSI"), 1, 0, '' ],
  selectPath         => [ __("Choose install or upgrade"), 0, 0, '', "selectInstallClass" ],
  selectMouse        => [ __("Configure mouse"), 1, 1, 'beginner', "selectPath" ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1, '', "selectPath" ],
  miscellaneous      => [ __("Miscellaneous"), 1, 1, 'beginner' ],
  partitionDisks     => [ __("Setup filesystems"), 1, 0, '', "selectPath" ],
  formatPartitions   => [ __("Format partitions"), 1, -1, '', "partitionDisks" ],
  choosePackages     => [ __("Choose packages to install"), 1, 1, 'beginner', "selectPath" ],
  doInstallStep      => [ __("Install system"), 1, -1, '', ["formatPartitions", "selectPath"] ],
  configureNetwork   => [ __("Configure networking"), 1, 1, 'beginner', "formatPartitions" ],
  installCrypto      => [ __("Cryptographic"), 1, 1, '!expert', "configureNetwork" ],
  configureTimezone  => [ __("Configure timezone"), 1, 1, '', "doInstallStep" ],
  configureServices  => [ __("Configure services"), 1, 1, '!expert', "doInstallStep" ],
  configurePrinter   => [ __("Configure printer"), 1, 0, '', "doInstallStep" ],
  setRootPassword    => [ __("Set root password"), 1, 1, '', "formatPartitions" ],
  addUser            => [ __("Add a user"), 1, 1, '', "doInstallStep" ],
arch() =~ /alpha/ ? (
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, '', "doInstallStep" ],
) : (),
  setupBootloader    => [ __("Install bootloader"), 1, 1, '', "doInstallStep" ],
  configureX         => [ __("Configure X"), 1, 0, '', ["formatPartitions", "setupBootloader"] ],
  exitInstall        => [ __("Exit install"), 0, 0, 'beginner' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
	$h{previous}= $installSteps[$i - 2] if $i >= 2;
	$h{next}    = $installSteps[$i + 2];
	$h{entered} = 0;
	$h{onError} = $installSteps[$i + 2 * $h{onError}];
	$h{reachable} = !$h{needs};
	$installSteps{ $installSteps[$i] } = \%h;
	push @orderedInstallSteps, $installSteps[$i];
    }
    $installSteps{first} = $installSteps[0];
}
#-#####################################################################################
#-INTERNAL CONSTANT
#-#####################################################################################

#- these strings are used in quite a lot of places and must not be changed!!!!!
my @install_classes = (__("beginner"), __("developer"), __("server"), __("expert"));

#-#####################################################################################
#-Default value
#-#####################################################################################
#- partition layout
my %suggestedPartitions = (
arch() =~ /^sparc/ ? (
  normal => [
    { mntpoint => "/",     size => 600 << 11, type => 0x83, ratio => 5, maxsize =>1000 << 11 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82, ratio => 1, maxsize => 400 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>1500 << 11 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 2 },
  ],
  developer => [
    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 1, maxsize =>1000 << 11 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82, ratio => 1, maxsize => 400 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>1500 << 11 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
  server => [
    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 1, maxsize =>1000 << 11 },
    { mntpoint => "swap",  size => 128 << 11, type => 0x82, ratio => 2, maxsize => 800 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 3, maxsize =>1500 << 11 },
    { mntpoint => "/var",  size => 100 << 11, type => 0x83, ratio => 4 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
) : (
  normal => [
    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 5, maxsize => 2500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 2 },
  ],
  developer => [
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 300 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>1500 << 11 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
  server => [
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 2, maxsize => 400 << 11 },
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 3, maxsize =>1500 << 11 },
    { mntpoint => "/var",  size => 100 << 11, type => 0x83, ratio => 4 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
),
);

#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, lba32 => 1, message => 1, timeout => 5, restricted => 0 },
    autoSCSI   => 0,
    mkbootdisk => 1, #- no mkbootdisk if 0 or undef, find a floppy with 1, or fd1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0, autoformat => 0 }, #-, readonly => 0 },
#-    security => 2,
    shells => [ map { "/bin/$_" } qw(bash tcsh zsh ash ksh) ],
    authentication => { md5 => 1, shadow => 1 },
    lang         => 'en',
    isUpgrade    => 0,
    toRemove     => [],
    toSave       => [],
#-    simple_themes => 1,
#-    installClass => "normal",

    timezone => {
#-                   timezone => "Europe/Paris",
#-                   UTC      => 1,
                },
    printer => {
                 want         => 0,
                 complete     => 0,
                 str_type     => $printer::printer_type_default,
                 QUEUE        => "lp",
                 SPOOLDIR     => "/var/spool/lpd/lp",
                 DBENTRY      => "PostScript",
                 PAPERSIZE    => "letter",
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
#-    display => "192.168.1.19:1",
    steps        => \%installSteps,
    orderedSteps => \@orderedInstallSteps,
    base => [ qw(basesystem sed initscripts console-tools utempter ldconfig chkconfig ntsysv setup filesystem SysVinit bdflush crontabs dev e2fsprogs etcskel fileutils findutils getty_ps grep gzip hdparm info initscripts kernel less ldconfig logrotate losetup man mingetty modutils mount net-tools passwd procmail procps psmisc mandrake-release rootfiles rpm sash ash setserial shadow-utils sh-utils stat sysklogd tar termcap textutils time tmpwatch util-linux vim-minimal vixie-cron which perl-base msec) ],
    base_i386 => [ "lilo", "mkbootdisk", "isapnptools" ],
    base_alpha => [ "aboot", "isapnptools" ],
    base_sparc => [ "silo", "mkbootdisk" ],
    base_ppc => [ "kernel-pmac", "pdisk", "hfsutils" ],

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
    addToBeDone { mouse::write($o->{prefix}, $o->{mouse}) } 'doInstallStep';
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($clicked) = $_[0];

    return unless $o->{isUpgrade} || !$::beginner || $clicked;

    $o->{keyboard} = (keyboard::read($o->{prefix}))[0] if $o->{isUpgrade} && !$clicked && $o->{keyboard_unsafe};
    $o->selectKeyboard if !$::beginner || $clicked;

    #- if we go back to the selectKeyboard, you must rewrite
    addToBeDone {
	lang::write($o->{prefix});
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
	{ device => "loop7", type => 0x83, size => 2048 * cat_('/dos/lnx4win/size.txt'), mntpoint => "/", isFormatted => 1, isMounted => 1 },
	{ device => "/initrd/dos/lnx4win/swapfile", type => 0x82, mntpoint => "swap", isFormatted => 1, isMounted => 1 },
      ] if $o->{lnx4win};
    return if $o->{isUpgrade};

    ($o->{hd_dev}) = cat_("/proc/mounts") =~ m|/tmp/(\S+)\s+/tmp/hdimage|;

    $::o->{steps}{formatPartitions}{done} = 0;
    eval { fs::umount_all($o->{fstab}, $o->{prefix}) } if $o->{fstab} && !$::testing;

    my $ok = fsedit::get_root($o->{fstab} || []) ? 1 : install_any::getHds($o);
    my $auto = $ok && !$o->{partitioning}{readonly} &&
	($o->{partitioning}{auto_allocate} || $::beginner && fsedit::get_fstab(@{$o->{hds}}) < 3);

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
    fsedit::get_root($o->{fstab}) or die 
_("You must have a root partition.
For this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'");

    cat_("/proc/mounts") =~ m|(\S+)\s+/tmp/rhimage nfs| &&
      !grep { $_->{mntpoint} eq "/mnt/nfs" } @{$o->{manualFstab} || []} and
	push @{$o->{manualFstab}}, { type => "nfs", mntpoint => "/mnt/nfs", device => $1, options => "noauto,ro,nosuid,rsize=8192,wsize=8192" };
}

sub formatPartitions {
    unless ($o->{lnx4win} || $o->{isUpgrade}) {
	$o->choosePartitionsToFormat($o->{fstab});

	unless ($::testing) {
	    $o->formatPartitions(@{$o->{fstab}});
	    fs::mount_all([ grep { isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
	    die _("Not enough swap to fulfill installation, please add some") if availableMemory < 40 * 1024;
	    fs::mount_all([ grep { isExt2($_) } @{$o->{fstab}} ], $o->{prefix}, $o->{hd_dev});
	}
	eval { $o = $::o = install_any::loadO($o) } if $_[1] == 1;

    }
    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/sysconfig etc/sysconfig/console etc/sysconfig/network-scripts
	home mnt tmp var var/tmp var/lib var/lib/rpm);
    mkdir "$o->{prefix}/$_", 0700 foreach qw(root);

    raid::prepare_prefixed($o->{raid}, $o->{prefix});

    #-noatime option for ext2 fs on laptops (do not wake up the hd)
    #-	 Do  not  update  inode  access times on this
    #-	 file system (e.g, for faster access  on  the
    #-	 news spool to speed up news servers).
    $o->{pcmcia} and $_->{options} = "noatime" foreach grep { isExt2($_) } @{$o->{fstab}};
}

#------------------------------------------------------------------------------
sub choosePackages {
    require pkgs;
    $o->setPackages if $_[1] == 1;
    $o->selectPackagesToUpgrade($o) if $o->{isUpgrade} && $_[1] == 1;
    if ($_[1] > 1 || !$o->{isUpgrade} || $::expert) {
	if ($_[1] == 1) { 
	    $o->{compssUsersChoice}{$_} = 1 foreach @{$o->{compssUsersSorted}}, 'Miscellaneous';
	    $o->{compssUsersChoice}{KDE} = 0 if $o->{lang} =~ /ja|el|ko|th|vi|zh/; #- gnome handles much this fonts much better
	}
	$o->choosePackages($o->{packages}, $o->{compss}, 
			   $o->{compssUsers}, $o->{compssUsersSorted}, $_[1] == 1);
	pkgs::unselect($o->{packages}, $o->{packages}{kdesu}) if $o->{packages}{kdesu} && $o->{security} > 3;
	$o->{packages}{$_}{selected} = 1 foreach @{$o->{base}}; #- already done by selectPackagesToUpgrade.
    }
}

#------------------------------------------------------------------------------
sub doInstallStep {
    $o->readBootloaderConfigBeforeInstall if $_[1] == 1;

    $o->beforeInstallPackages;
    $o->installPackages($o->{packages});
    $o->afterInstallPackages;
}
#------------------------------------------------------------------------------
sub miscellaneous {
    $o->miscellaneous($_[0]); 

    addToBeDone {
	setVarsInSh("$o->{prefix}/etc/sysconfig/system", { 
            HDPARM => $o->{miscellaneous}{HDPARM},
            CLEAN_TMP => $o->{miscellaneous}{CLEAN_TMP},
            CLASS => $::expert && "expert" || $::beginner && "beginner" || "medium",
            TYPE => $o->{installClass},
            SECURITY => $o->{security},
        });
	install_any::fsck_option();

	local $ENV{LILO_PASSWORD} = $o->{lilo}{password};
	run_program::rooted($o->{prefix}, "/etc/security/msec/init.sh", $o->{security});
    } 'doInstallStep';
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($clicked) = @_;

    if ($o->{isUpgrade} && !$clicked) {
	$o->{netc} or $o->{netc} = {};
	add2hash($o->{netc}, network::read_conf("$o->{prefix}/etc/sysconfig/network")) if -r "$o->{prefix}/etc/sysconfig/network";
	add2hash($o->{netc}, network::read_resolv_conf("$o->{prefix}/etc/resolv.conf")) if -r "$o->{prefix}/etc/resolv.conf";
	foreach (all("$o->{prefix}/etc/sysconfig/network-scripts")) {
	    if (/ifcfg-(\w+)/) {
		push @{$o->{intf}}, { getVarsFromSh("$o->{prefix}/etc/sysconfig/network-scripts/$_") };
	    }
	}
    }
    $o->configureNetwork($_[1] == 1);
}
#------------------------------------------------------------------------------
sub installCrypto { $o->installCrypto }

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($clicked) = @_;
    my $f = "$o->{prefix}/etc/sysconfig/clock";

    require timezone;
    if ($o->{isUpgrade} && -r $f && -s $f > 0) {
	return if $_[1] == 1 && !$clicked;
	#- can't be done in install cuz' timeconfig %post creates funny things
	add2hash($o->{timezone}, { timezone::read($f) });
    }
    $o->{timezone}{UTC} = !$::beginner && !grep { isFat($_) } @{$o->{fstab}} unless exists $o->{timezone}{UTC};
    $o->timeConfig($f, $clicked);
}
#------------------------------------------------------------------------------
sub configureServices { $::expert and $o->servicesConfig }
#------------------------------------------------------------------------------
sub configurePrinter  { $o->printerConfig }
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
    modules::write_conf("$o->{prefix}/etc/conf.modules");

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

    #- done here and also at the end of install2.pm, just in case...
    fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});
    modules::write_conf("$o->{prefix}/etc/conf.modules");

    $o->setupXfree if $o->{packages}{XFree86}{installed} || $clicked;
}
#------------------------------------------------------------------------------
sub exitInstall { $o->exitInstall(getNextStep() eq "exitInstall") }


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
    $SIG{__DIE__} = sub { chomp(my $err = $_[0]); log::l("warning: $err") };
    $SIG{SEGV} = sub { my $msg = "segmentation fault: seems like memory is missing as the install crashes"; print "$msg\n"; log::l($msg);
		       require install_steps_auto_install;
		       install_steps_auto_install::errorInStep();
		   };

    $::beginner = $::expert = $::g_auto_install = 0;

    my ($cfg, $patch);
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
	    vga       => sub { $o->{vga16} = $v },
	    step      => sub { $o->{steps}{first} = $v },
	    expert    => sub { $::expert = 1 },
	    beginner  => sub { $::beginner = 1 },
	    class     => sub { $o->{installClass} = $v },
	    lnx4win   => sub { $o->{lnx4win} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = $v ne "0" },
	    display   => sub { $o->{display} = $v },
	    security  => sub { $o->{security} = $v },
	    test      => sub { $::testing = 1 },
	    patch     => sub { $patch = 1 },
	    defcfg    => sub { $cfg = $v },
	    newt      => sub { $o->{interactive} = "newt" },
	    text      => sub { $o->{interactive} = "newt" },
	    stdio     => sub { $o->{interactive} = "stdio"},
	    ks        => sub { $::auto_install = 1 },
	    kickstart => sub { $::auto_install = 1 },
	    auto_install => sub { $::auto_install = 1 },
	    simple_themes => sub { $o->{simple_themes} = 1 },
	    alawindows => sub { $o->{security} = 0; $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    g_auto_install => sub { $::testing = $::g_auto_install = 1; $o->{partitioning}{auto_allocate} = 1 },
	    nomouseprobe => sub { $o->{nomouseprobe} = $v },
	}}{lc $n}; &$f if $f;
    } %cmdline;    

    if ($::g_auto_install) {
	(my $root = `/bin/pwd`) =~ s|(/[^/]*){5}$||;
	symlinkf $root, "/tmp/rhimage" or die "unable to create link /tmp/rhimage";
    }

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

    $o->{interactive} ||= 'gtk';
    if ($o->{interactive} eq "gtk" && availableMemory < 22 * 1024) {
	log::l("switching to newt install cuz not enough memory");
	$o->{interactive} = "newt";
    }

    if ($::auto_install) {
	require install_steps_auto_install;
	eval { $o = $::o = install_any::loadO($o, "floppy") };
	if ($@) {
	    log::l("error using auto_install, continuing");
	    undef $::auto_install;
	}
    }
    unless ($::auto_install) {
	$o->{interactive} ||= 'gtk';
	require"install_steps_$o->{interactive}.pm";
    }
    eval { $o = $::o = install_any::loadO($o, "patch") } if $patch;
    eval { $o = $::o = install_any::loadO($o, $cfg) } if $cfg;

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $o->{prefix}, 0755;

#-    #- needed very early to switch bad cards in VGA16
#-    foreach (pci_probing::main::probe('')) {
#-	  log::l("Here: $_->[0]");
#-	  $_->[0] =~ /i740|ViRGE/ and add2hash_($o, { vga16 => 1 }), log::l("switching to VGA16 as bad graphic card");
#-    }

    #- needed very early for install_steps_gtk
    eval { ($o->{mouse}, $o->{wacom}) = mouse::detect() } unless $o->{nomouseprobe} || $o->{mouse};

    my $o_;
    while (1) {
	require"install_steps_$o->{interactive}.pm";
    	$o_ = $::auto_install ?
    	  install_steps_auto_install->new($o) :
    	    $o->{interactive} eq "stdio" ?
    	  install_steps_stdio->new($o) :
    	    $o->{interactive} eq "newt" ?
    	  install_steps_newt->new($o) :
    	    $o->{interactive} eq "gtk" ?
    	  install_steps_gtk->new($o) :
    	    die "unknown install type";
	$o_ and last;

	$o->{interactive} = "newt";
	require install_steps_newt;
    }
    $::o = $o = $o_;

    $o->{netc} = network::read_conf("/tmp/network");
    if (my ($file) = glob_('/tmp/ifcfg-*')) {
	log::l("found network config file $file");
	my $l = network::read_interface_conf($file);
	add2hash(network::findIntf($o->{intf} ||= [], $l->{DEVICE}), $l);
    }

    modules::unload($_) foreach qw(vfat msdos fat);
    modules::load_deps(($::testing ? ".." : "") . "/modules/modules.dep");
    modules::read_stage1_conf("/tmp/conf.modules");
    modules::read_already_loaded();

    modules::load_multi(qw(ide-probe ide-disk ide-cd sd_mod af_packet));
    install_any::lnx4win_preinstall() if $o->{lnx4win};

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
    install_any::ejectCdrom();

    fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});
    modules::write_conf("$o->{prefix}/etc/conf.modules");

    install_any::lnx4win_postinstall($o->{prefix}) if $o->{lnx4win};
    install_any::killCardServices();

    #- make sure failed upgrade will not hurt too much.
    install_steps::cleanIfFailedUpgrade($o);

    #- have the really bleeding edge ddebug.log for this f*cking msec :-/
    eval { commands::cp('-f', "/tmp/ddebug.log", "$o->{prefix}/root") };

    #- ala pixel? :-) [fpons]
    sync(); sync();

    log::l("installation complete, leaving");
    print "\n" x 80;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
