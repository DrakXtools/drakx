
package install2; # $Id$

use diagnostics;
use strict;
use vars qw($o $version);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system :functional);
use install_any qw(:all);
use install_steps;
use commands;
use lang;
use keyboard;
use mouse;
use fsedit;
use devices;
use partition_table qw(:types);
use modules;
use detect_devices;
use run_program;
use any;
use log;
use fs;
#-$::corporate=1;

#-######################################################################################
#- Steps table
#-######################################################################################
my (%installSteps, @orderedInstallSteps);
{    
    my @installStepsFields = qw(text redoable onError hidden needs icon); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1, '', '', 'default' ],
  selectInstallClass => [ __("Select installation class"), 1, 1, '', '', 'default' ],
  setupSCSI          => [ __("Hard drive detection"), 1, 0, '', '', 'harddrive' ],
  selectMouse        => [ __("Configure mouse"), 1, 1, '', "selectInstallClass", 'mouse' ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1, '', "selectInstallClass", 'keyboard' ],
  miscellaneous      => [ __("Security"), 1, 1, '!$::expert', '', 'security' ],
  doPartitionDisks   => [ __("Setup filesystems"), 1, 0, '', "selectInstallClass", 'default' ],
  formatPartitions   => [ __("Format partitions"), 1, -1, '', "doPartitionDisks", 'default' ],
  choosePackages     => [ __("Choose packages to install"), 1, -2, '!$::expert', "formatPartitions", 'default' ],
  installPackages    => [ __("Install system"), 1, -1, '', ["formatPartitions", "selectInstallClass"], '' ],
  setRootPassword    => [ __("Set root password"), 1, 1, '', "installPackages", 'rootpasswd' ],
  addUser            => [ __("Add a user"), 1, 1, '', "installPackages", 'user' ],
  configureNetwork   => [ __("Configure networking"), 1, 1, '', "formatPartitions", 'network' ],
#-  installCrypto      => [ __("Cryptographic"), 1, 1, '!$::expert', "configureNetwork" ],
  summary            => [ __("Summary"), 1, 0, '', "installPackages", 'default' ],
  configureServices  => [ __("Configure services"), 1, 1, '!$::expert', "installPackages", 'services' ],
if_((arch() !~ /alpha/) && (arch() !~ /ppc/),
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, '', "installPackages", 'bootdisk' ],
),
  setupBootloader    => [ __("Install bootloader"), 1, 1, '', "installPackages", 'bootloader' ],
  configureX         => [ __("Configure X"), 1, 1, '', ["formatPartitions", "setupBootloader"], 'X' ],
  exitInstall        => [ __("Exit install"), 0, 0, '!$::expert && !$::live', '', 'default' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
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

my @install_classes = qw(normal developer server);

#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, lba32 => 1, message => 1, timeout => 5, restricted => 0 },
    mkbootdisk => 1, #- no mkbootdisk if 0 or undef, find a floppy with 1, or fd1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0 }, #-, readonly => 0 },
    security => 2,
    authentication => { md5 => 1, shadow => 1 },
    lang         => 'en_US',
    isUpgrade    => 0,
    toRemove     => [],
    toSave       => [],
#-    simple_themes => 1,

    timezone => {
#-                   timezone => "Europe/Paris",
#-                   UTC      => 1,
                },
#-    superuser => { password => 'a', shell => '/bin/bash', realname => 'God' },
#-    user => { name => 'foo', password => 'bar', home => '/home/foo', shell => '/bin/bash', realname => 'really, it is foo' },

#-    keyboard => 'de',
#-    display => "192.168.1.19:1",
    steps        => \%installSteps,
    orderedSteps => \@orderedInstallSteps,

#- for the list of fields available for user and superuser, see @etc_pass_fields in install_steps.pm
#-    intf => { eth0 => { DEVICE => "eth0", IPADDR => '1.2.3.4', NETMASK => '255.255.255.128' } },

#-step : the current one
#-prefix
#-mouse
#-keyboard
#-netc
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
	lang::write_langs($o->{prefix}, $o->{langs});
    } 'formatPartitions' unless $::g_auto_install;
    addToBeDone {
	lang::write($o->{prefix}, $o->{lang});
	keyboard::write($o->{prefix}, $o->{keyboard}, lang::lang2charset($o->{lang}));
    } 'installPackages' unless $::g_auto_install;
}

#------------------------------------------------------------------------------
sub selectMouse {
    require pkgs;
    my ($first_time) = $_[1] == 1;

    add2hash($o->{mouse} ||= {}, mouse::read($o->{prefix})) if $o->{isUpgrade} && $first_time;

    $o->selectMouse(!$first_time);
    addToBeDone { mouse::write($o->{prefix}, $o->{mouse}) } 'installPackages';
}

#------------------------------------------------------------------------------
sub setupSCSI {
    my ($clicked) = @_;
    $o->setupSCSI($clicked);
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($clicked, $first_time) = ($_[0], $_[1] == 1);

    if ($o->{isUpgrade} && $first_time && $o->{keyboard_unsafe}) {
	my $keyboard = keyboard::read($o->{prefix});
	$keyboard and $o->{keyboard} = $keyboard;
    }
    return if !$::expert && !$clicked;

    $o->selectKeyboard($clicked);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($clicked) = @_;

    $o->selectInstallClass($clicked);
   
    if ($o->{steps}{choosePackages}{entered} >= 1 && !$o->{steps}{installPackages}{done}) {
        $o->setPackages(\@install_classes);
        $o->selectPackagesToUpgrade if $o->{isUpgrade};
    }
    if ($o->{isUpgrade}) {
	@{$o->{orderedSteps}} = map { /setupSCSI/ ? ($_, "doPartitionDisks") : $_ }
	                        grep { !/doPartitionDisks/ } @{$o->{orderedSteps}};
	my $s; foreach (@{$o->{orderedSteps}}) {
	    $s->{next} = $_ if $s;
	    $s = $o->{steps}{$_};
	}
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    $o->{steps}{formatPartitions}{done} = 0;
    $o->doPartitionDisksBefore;
    $o->doPartitionDisks;
    $o->doPartitionDisksAfter;
}

sub formatPartitions {
    $o->{steps}{choosePackages}{done} = 0;
    $o->choosePartitionsToFormat($o->{fstab}) unless $o->{isUpgrade};
    $o->formatMountPartitions($o->{fstab}) unless $::testing;

    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/rpm etc/sysconfig etc/sysconfig/console 
	etc/sysconfig/network-scripts etc/sysconfig/console/consolefonts 
	etc/sysconfig/console/consoletrans
	home mnt tmp var var/tmp var/lib var/lib/rpm var/lib/urpmi);
    mkdir "$o->{prefix}/$_", 0700 foreach qw(root root/tmp);

    any::rotate_logs($o->{prefix});

    require raid;
    raid::prepare_prefixed($o->{raid}, $o->{prefix});

    my $d = "/initrd/loopfs/lnx4win";
    if (-d $d) {
#-	install_any::useMedium(0);
	install_any::getAndSaveFile("lnx4win/$_", "$d/$_") foreach qw(ctl3d32.dll loadlin.exe linux.pif lnx4win.exe lnx4win.ico rm.exe uninstall.bat uninstall.pif);
    }

#-    chdir "$o->{prefix}"; was for core dumps

    #-noatime option for ext2 fs on laptops (do not wake up the hd)
    #-	 Do  not  update  inode  access times on this
    #-	 file system (e.g, for faster access  on  the
    #-	 news spool to speed up news servers).
    $o->{pcmcia} and $_->{options} = "noatime" foreach grep { isTrueFS($_) } @{$o->{fstab}};
}

#------------------------------------------------------------------------------
sub choosePackages {
    require pkgs;

    #- always setPackages as it may have to copy hdlist files and depslist file.
    $o->setPackages;
    $o->selectPackagesToUpgrade if $o->{isUpgrade} && $_[1] == 1;

    $o->choosePackages($o->{packages}, $o->{compssUsers}, $_[1] == 1);
    log::l("compssUsersChoice's: ", join(" ", grep { $o->{compssUsersChoice}{$_} } keys %{$o->{compssUsersChoice}}));

    #- check pre-condition where base backage has to be selected.
    pkgs::packageFlagSelected(pkgs::packageByName($o->{packages}, 'basesystem')) or die "basesystem package not selected";

    #- check if there are package that need installation.
    $o->{steps}{installPackages}{done} = 0 if $o->{steps}{installPackages}{done} && pkgs::packagesToInstall($o->{packages}) > 0;
}

#------------------------------------------------------------------------------
sub installPackages {
    $o->readBootloaderConfigBeforeInstall if $_[1] == 1;

    $o->beforeInstallPackages;
    $o->installPackages;
    $o->afterInstallPackages;
}
#------------------------------------------------------------------------------
sub miscellaneous {
    $o->miscellaneousBefore($_[0]);
    $o->miscellaneous($_[0]);

    addToBeDone {
	setVarsInSh("$o->{prefix}/etc/sysconfig/system", { 
            CLEAN_TMP => $o->{miscellaneous}{CLEAN_TMP},
            CLASS => $::expert && 'expert' || 'beginner',
            SECURITY => $o->{security},
	    META_CLASS => $o->{meta_class} || 'PowerPack',
        });
	substInFile { s/KEYBOARD_AT_BOOT=.*/KEYBOARD_AT_BOOT=yes/ } "$o->{prefix}/etc/sysconfig/usb" if detect_devices::usbKeyboards();

    } 'installPackages';
}

#------------------------------------------------------------------------------
sub summary { $o->summary($_[1] == 1) }
#------------------------------------------------------------------------------
sub configureNetwork {
    #- get current configuration of network device.
    require network;
    eval { network::read_all_conf($o->{prefix}, $o->{netc} ||= {}, $o->{intf} ||= {}) };
    $o->configureNetwork($_[1] == 1);
}
#------------------------------------------------------------------------------
sub installCrypto { $o->installCrypto }
#------------------------------------------------------------------------------
sub configureServices { $o->configureServices($_[0]) }
#------------------------------------------------------------------------------
sub setRootPassword {
    return if $o->{isUpgrade};

    $o->setRootPassword($_[0]);
    addToBeDone { install_any::setAuthentication($o) } 'installPackages';
}
#------------------------------------------------------------------------------
sub addUser {
    return if $o->{isUpgrade} && !$_[0];

    $o->addUser($_[0]);
}

#------------------------------------------------------------------------------
sub createBootdisk {
    modules::write_conf($o->{prefix});
    $o->createBootdisk($_[1] == 1);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    return if $::g_auto_install;

    modules::write_conf($o->{prefix});

    $o->setupBootloaderBefore if $_[1] == 1;
    $o->setupBootloader($_[1] - 1);
    
    local $ENV{DRAKX_PASSWORD} = $o->{bootloader}{password};
    local $ENV{DURING_INSTALL} = 1;
    run_program::rooted($o->{prefix}, "/usr/sbin/msec", $o->{security});
}
#------------------------------------------------------------------------------
sub configureX {
    my ($clicked) = @_;

    #- done here and also at the end of install2.pm, just in case...
    install_any::write_fstab($o);
    modules::write_conf($o->{prefix});

    require pkgs;
    $o->configureX($clicked) if pkgs::packageFlagInstalled(pkgs::packageByName($o->{packages}, 'XFree86')) && !$o->{X}{disabled} || $clicked || $::testing;
}
#------------------------------------------------------------------------------
sub exitInstall { $o->exitInstall(getNextStep() eq "exitInstall") }


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
    $SIG{__DIE__} = sub { chomp(my $err = $_[0]); log::l("warning: $err") };
    $SIG{SEGV} = sub { my $msg = "segmentation fault: seems like memory is missing as the install crashes"; print "$msg\n"; log::l($msg);
		       $o->ask_warn('', $msg);
		       setVirtual(1);
		       require install_steps_auto_install;
		       install_steps_auto_install::errorInStep();
		   };
    $ENV{PERL_BADLANG} = 1;
    umask 022;

    $::isInstall = 1;
    $::expert = $::g_auto_install = 0;

#-    c::unlimit_core() unless $::testing;

    my ($cfg, $patch, @auto);
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
	    oem       => sub { $::oem = $v },
	    lang      => sub { $o->{lang} = $v },
	    flang     => sub { $o->{lang} = $v ; push @auto, 'selectLanguage' },
	    method    => sub { $o->{method} = $v },
	    pcmcia    => sub { $o->{pcmcia} = $v },
	    vga16     => sub { $o->{vga16} = $v },
	    vga       => sub { $o->{vga} = $v },
	    step      => sub { $o->{steps}{first} = $v },
	    expert    => sub { $::expert = $v },
	    fbeginner => sub { $::expert = 0; push @auto, 'selectInstallClass' },
	    fexpert   => sub { $::expert = 1; push @auto, 'selectInstallClass' },
	    desktop   => sub { $o->{meta_class} = 'desktop' },
	    firewall  => sub { $o->{meta_class} = 'firewall'; push @auto, 'selectInstallClass'},
	    lnx4win   => sub { $o->{lnx4win} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = $v ne "0" },
	    display   => sub { $o->{display} = $v },
	    security  => sub { $o->{security} = $v },
	    live      => sub { $::live = 1 },
	    noauto    => sub { $::noauto = 1 },
	    test      => sub { $::testing = 1 },
            nopci     => sub { $::nopci = 1 },
	    patch     => sub { $patch = 1 },
	    defcfg    => sub { $cfg = $v },
	    newt      => sub { $o->{interactive} = "newt" },
	    text      => sub { $o->{interactive} = "newt" },
	    stdio     => sub { $o->{interactive} = "stdio"},
	    corporate => sub { $::corporate = 1 },
	    kickstart => sub { $::auto_install = $v },
	    auto_install => sub { $::auto_install = $v },
	    simple_themes => sub { $o->{simple_themes} = 1 },
	    useless_thing_accepted => sub { $o->{useless_thing_accepted} = 1 },
	    alawindows => sub { $o->{security} = 0; $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    fdisk => sub { $o->{partitioning}{fdisk} = 1 },
	    g_auto_install => sub { $::testing = $::g_auto_install = 1; $o->{partitioning}{auto_allocate} = 1 },
	    nomouseprobe => sub { $o->{nomouseprobe} = $v },
	}}{lc $n}; &$f if $f;
    } %cmdline;

    if ($::testing) {
	$ENV{SHARE_PATH} ||= "/export/Mandrake/mdkinst/usr/share";
	$ENV{SHARE_PATH} = "/usr/share" if !-e $ENV{SHARE_PATH};
    } else {
	$ENV{SHARE_PATH} ||= "/usr/share";
    }

    undef $::auto_install if $cfg;
    if ($::g_auto_install) {
	(my $root = `/bin/pwd`) =~ s|(/[^/]*){5}$||;
	symlinkf $root, "/tmp/image" or die "unable to create link /tmp/image";
	$o->{method} ||= "cdrom";
	$o->{mkbootdisk} = 0;
    }
    unless ($::testing || $::live) {
	symlink "rhimage", "/tmp/image"; #- for compatibility with old stage1
	unlink $_ foreach "/modules/modules.mar", "/sbin/stage1";
    }

    print STDERR "in second stage install\n";
    log::openLog(($::testing || $o->{localInstall}) && 'debug.log');
    log::l("second stage install running (", any::drakx_version(), ")");

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : $::live ? "" : "/mnt";
    $o->{root}   = $::testing ? "/tmp/root-perl-install" : "/";
    $o->{isUpgrade} = 1 if $::live;
    mkdir $o->{prefix}, 0755;
    mkdir $o->{root}, 0755;
    devices::make("/dev/zero"); #- needed by ddcxinfos

    #-  make sure we don't pick up any gunk from the outside world
    my $remote_path = "$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$remote_path" unless $::g_auto_install;

    eval { spawnShell() };

    $o->{prefix} = $::testing ? "/tmp/test-perl-install" : $::live ? "" : "/mnt";
    mkdir $o->{prefix}, 0755;

    modules::load_deps(($::testing ? ".." : "") . "/modules/modules.dep");
    modules::read_stage1_conf($_) foreach "/tmp/conf.modules", "/etc/modules.conf";
    modules::read_already_loaded();

    $o->{interactive} ||= 'gtk';
    if ($o->{interactive} eq "gtk" && availableMemory < 22 * 1024) {
	log::l("switching to newt install cuz not enough memory");
	$o->{interactive} = "newt";
    }

    #- done after module dependencies are loaded for "vfat depends on fat"
    if ($::auto_install) {
	require install_steps_auto_install;
	eval { $o = $::o = install_any::loadO($o, $::auto_install) };
	if ($@) {
	    log::l("error using auto_install, continuing");
	    undef $::auto_install;
	} else {
	    log::l("auto install config file loaded successfully");
	}
    }
    unless ($::auto_install) {
	$o->{interactive} ||= 'gtk';
	require"install_steps_$o->{interactive}.pm";
    }

    eval { $o = $::o = install_any::loadO($o, "patch") } if $patch;
    eval { $o = $::o = install_any::loadO($o, $cfg) } if $cfg;

    eval { modules::load("af_packet") };

    map_index {
	modules::add_alias("sound-slot-$::i", $_->{driver});
    } modules::get_that_type('sound');

    #- needed very early for install_steps_gtk
    modules::load_thiskind("usb"); 
    eval { ($o->{mouse}, @{$o->{wacom} = []}) = mouse::detect() } unless $o->{nomouseprobe} || $o->{mouse};

    lang::set($o->{lang}); #- mainly for defcfg

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    my $VERSION = cat__(install_any::getFile("VERSION")) or do { print "VERSION file missing\n"; sleep 5 };
    $o->{lnx4win} = 1 if $VERSION =~ /lnx4win/i;
    $o->{meta_class} = 'desktop' if $VERSION =~ /desktop/i;
    $o->{meta_class} = 'firewall' if $VERSION =~ /firewall/i;
    if ($::oem) {
	$o->{partitioning}{use_existing_root} = 1;
	$o->{partitioning}{auto_allocate} = 1;
	$o->{compssListLevel} = 50;
	push @auto, 'selectInstallClass', 'doPartitionDisks', 'choosePackages', 'configureTimezone', 'exitInstall';
    }

    foreach (@auto) {
	eval "undef *" . (!/::/ && "install_steps_interactive::") . $_;
	my $s = $o->{steps}{/::(.*)/ ? $1 : $_} or next;
	$s->{hidden} = 1;
    }

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

    if (-e '/tmp/network') {
	require network;
	#- get stage1 network configuration if any.
	log::l('found /tmp/network');
	$o->{netc} ||= network::read_conf('/tmp/network');
	if (my ($file) = glob_('/tmp/ifcfg-*')) {
	    log::l("found network config file $file");
	    my $l = network::read_interface_conf($file);
	    $o->{intf} ||= { $l->{DEVICE} => $l };
	}
	if (-e '/etc/resolv.conf') {
	    my $file ='/etc/resolv.conf';
	    log::l("found network config file $file");
	    add2hash($o->{netc}, network::read_resolv_conf($file));
	}
    }

    #-the main cycle
    my $clicked = 0;
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	$o->{steps}{$o->{step}}{icon} and $o->{icon} = $o->{steps}{$o->{step}}{icon};
	eval {
	    &{$install2::{$o->{step}}}($clicked, $o->{steps}{$o->{step}}{entered});
	};
	my $err = $@;
	$o->kill_action;
	$clicked = 0;
	if ($err) {
	    local $_ = $err;
	    $o->kill_action;
	    if (/^setstep (.*)/) {
		$o->{step} = $1;
		$o->{steps}{$1}{done} = 0;
		$clicked = 1;
		redo MAIN;
	    }
	    /^theme_changed$/ and redo MAIN;
	    unless (/^already displayed/) {
		eval { $o->errorInStep($_) };
		$err = $@;
		$err and next;
	    }
	    $o->{step} = $o->{steps}{$o->{step}}{onError};
	    next MAIN unless $o->{steps}{$o->{step}}{reachable}; #- sanity check: avoid a step not reachable on error.
	    redo MAIN;
	}
	$o->{steps}{$o->{step}}{done} = 1;
	$o->leavingStep($o->{step});

	last if $o->{step} eq 'exitInstall';
    }
    install_any::clean_postinstall_rpms();
    install_any::log_sizes($o);
    install_any::ejectCdrom();
    install_any::remove_advertising($o);

    install_any::write_fstab($o);
    modules::write_conf($o->{prefix});

    #- to ensure linuxconf doesn't cry against those files being in the future
    foreach ('/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config') {
	my $now = time - 24 * 60 * 60;
	utime $now, $now, "$o->{prefix}/$_";
    }
    $::live or install_any::killCardServices();

    #- make sure failed upgrade will not hurt too much.
    install_steps::cleanIfFailedUpgrade($o);

    -e "$o->{prefix}/usr/bin/urpmi" or eval { commands::rm("-rf", "$o->{prefix}/var/lib/urpmi") };

    #- mainly for auto_install's
    run_program::run("bash", "-c", $o->{postInstallNonRooted}) if $o->{postInstallNonRooted};
    run_program::rooted($o->{prefix}, "sh", "-c", $o->{postInstall}) if $o->{postInstall};

    #- have the really bleeding edge ddebug.log
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
