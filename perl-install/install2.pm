package install2; # $Id$

use diagnostics;
use strict;
use vars qw($o);

#-######################################################################################
#- misc imports
#-######################################################################################
use steps;
use common;
use install_any qw(:all);
use install_steps;
use install_any;
use lang;
use keyboard;
use mouse;
use devices;
use partition_table;
use modules;
use detect_devices;
use run_program;
use any;
use log;
use fs;


#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, message => 1, timeout => 5, restricted => 0 },
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0 }, #-, readonly => 0 },
    authentication => { md5 => 1, shadow => 1 },
    locale         => { lang => 'en_US' },
#-    isUpgrade    => 0,
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
    steps        => \%steps::installSteps,
    orderedSteps => \@steps::orderedInstallSteps,

    #- for the list of fields available, see network/network.pm
    net => {
	    #- network => { HOSTNAME => 'abcd' },
	    #- resolv => { DOMAINNAME => 'foo.xyz' },
	    #- ifcfg => {
	    #-   eth0 => { DEVICE => "eth0", IPADDR => '1.2.3.4', NETMASK => '255.255.255.128' }
	    #- },
	    },

#-step : the current one
#-prefix
#-mouse
#-keyboard
#-netc
#-methods
#-packages compss
#-printer haveone entry(cf printer.pm)

};


sub installStepsCall {
    my ($o, $auto, $fun, @args) = @_;
    $fun = "install_steps::$fun" if $auto;
    $o->$fun(@args);
}

#-######################################################################################
#- Steps Functions
#- each step function are called with two arguments : clicked(because if you are a
#- beginner you can force the the step) and the entered number
#-######################################################################################

#------------------------------------------------------------------------------
sub selectLanguage {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'selectLanguage');
}

sub acceptLicense {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'acceptLicense');
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'selectMouse');

    addToBeDone { mouse::write($o->do_pkgs, $o->{mouse}) if !$o->{isUpgrade} } 'installPackages';
}

#------------------------------------------------------------------------------
sub setupSCSI {
    my ($auto) = @_;

    if (!$::testing && !$::local_install) {
	-d '/lib/modules/' . c::kernel_version() ||
	  -s modules::cz_file() or die N("Can not access kernel modules corresponding to your kernel (file %s is missing), this generally means your boot floppy in not in sync with the Installation medium (please create a newer boot floppy)", modules::cz_file());
    }

    installStepsCall($o, $auto, 'setupSCSI');
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($auto) = @_;

    my $force;
    if (my $keyboard = keyboard::read()) {
	$o->{keyboard} = $keyboard; #- for uprade
    } elsif ($o->{isUpgrade}) {
	#- oops, the keyboard config is wrong, forcing prompt and writing
	$force = 1;
    }

    installStepsCall($o, $auto, 'selectKeyboard', $force);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($auto) = @_;

    installStepsCall($o, $auto, 'selectInstallClass');

    if ($o->{isUpgrade}) {
	@{$o->{orderedSteps}} = uniq(map {
	    $_ eq 'selectInstallClass' ? ($_, 'doPartitionDisks', 'formatPartitions') : $_;
	} @{$o->{orderedSteps}});

	$o->{modules_conf}->merge_into(modules::any_conf->read);
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($auto) = @_;
    $o->{steps}{formatPartitions}{done} = 0;
    installStepsCall($o, $auto, 'doPartitionDisksBefore');
    installStepsCall($o, $auto, 'doPartitionDisks');
    installStepsCall($o, $auto, 'doPartitionDisksAfter');
}

sub formatPartitions {
    my ($auto) = @_;

    $o->{steps}{choosePackages}{done} = 0;
    installStepsCall($o, $auto, 'choosePartitionsToFormat', $o->{fstab}) if !$o->{isUpgrade};
    my $want_root_formated = fs::get::root($o->{fstab})->{toFormat};
    if ($want_root_formated) {
	foreach ('/usr') {
	    my $part = fs::get::mntpoint2part($_, $o->{fstab}) or next;
	    $part->{toFormat} or die N("You must also format %s", $_);
	}
    }
    installStepsCall($o, $auto, 'formatMountPartitions', $o->{fstab}) if !$::testing;

    if ($want_root_formated) {
	#- we formatted /, ensure /var/lib/rpm is cleaned otherwise bad things can happen
	#- (especially when /var is *not* formatted)
	eval { rm_rf("$o->{prefix}/var/lib/rpm") };
    }

    install_any::create_minimal_files();

    eval { fs::mount::mount('none', "$::prefix/proc", 'proc') };
    eval { fs::mount::mount('none', "$::prefix/sys", 'sysfs') };
    eval { fs::mount::usbfs($::prefix) };

    install_any::screenshot_dir__and_move();
    install_any::move_clp_to_disk($o);

    any::rotate_logs($o->{prefix});

    if (any { $_->{usb_media_type} && any { $_->{mntpoint} } partition_table::get_normal_parts($_) } @{$o->{all_hds}{hds}}) {
	log::l("we use a usb-storage based drive, so keep it as a normal scsi_hostadapter");
    } else {
	log::l("we do not need usb-storage for booting system, rely on hotplug");
	#- when usb-storage is in scsi_hostadapter, 
	#- hotplug + scsimon do not load sd_mod/sr_mod when needed
	#- (eg: when plugging a usb key)
	$o->{modules_conf}->remove_probeall('scsi_hostadapter', 'usb-storage');
    }

    require raid;
    raid::write_conf($o->{all_hds}{raids});

    #- needed by lilo
    if (-d '/dev/mapper') {
	my @vgs = map { $_->{VG_name} } @{$o->{all_hds}{lvms}};
	cp_af("/dev/$_", "$::prefix/dev") foreach 'mapper', @vgs;
    }
}

#------------------------------------------------------------------------------
sub choosePackages {
    my ($auto) = @_;
    require pkgs;

    #- always setPackages as it may have to copy hdlist and synthesis files.
    installStepsCall($o, $auto, 'setPackages');
    installStepsCall($o, $auto, 'choosePackages');
    my @flags = map_each { if_($::b, $::a) } %{$o->{rpmsrate_flags_chosen}};
    log::l("rpmsrate_flags_chosen's: ", join(' ', sort @flags));

    #- check pre-condition that basesystem package must be selected.
    pkgs::packageByName($o->{packages}, 'basesystem')->flag_available or die "basesystem package not selected";

    #- check if there are packages that need installation.
    $o->{steps}{installPackages}{done} = 0 if $o->{steps}{installPackages}{done} && pkgs::packagesToInstall($o->{packages}) > 0;
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($auto) = @_;

    installStepsCall($o, $auto, 'beforeInstallPackages');
    installStepsCall($o, $auto, 'installPackages');
    installStepsCall($o, $auto, 'afterInstallPackages');
}
#------------------------------------------------------------------------------
sub miscellaneous {
    my ($auto) = @_;

    installStepsCall($o, $auto, 'miscellaneousBefore');
    installStepsCall($o, $auto, 'miscellaneous');
    installStepsCall($o, $auto, 'miscellaneousAfter');
}

#------------------------------------------------------------------------------
sub summary {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'summaryBefore') if $o->{steps}{summary}{entered} == 1;
    installStepsCall($o, $auto, 'summary');
    installStepsCall($o, $auto, 'summaryAfter');
}
#------------------------------------------------------------------------------
sub configureNetwork {
    my ($auto) = @_;
    #- get current configuration of network device.
    require network::network;
    eval { network::network::read_net_conf($o->{net}) };
    if (!$o->{isUpgrade}) {
        installStepsCall($o, $auto, 'configureNetwork');
    } else {
        require network::ethernet;
        network::ethernet::configure_eth_aliases($o->{modules_conf});
    }
}
#------------------------------------------------------------------------------
sub installUpdates {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'installUpdates') if $o->{meta_class} ne 'firewall';
}
#------------------------------------------------------------------------------
sub configureServices {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'configureServices');
}
#------------------------------------------------------------------------------
sub setRootPassword {
    my ($auto) = @_;
    return if $o->{isUpgrade};

    installStepsCall($o, $auto, 'setRootPassword');
}
#------------------------------------------------------------------------------
sub addUser {
    my ($auto) = @_;

    installStepsCall($o, $auto, 'addUser') if !$o->{isUpgrade};
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($auto) = @_;
    return if $::local_install;

    $o->{modules_conf}->write;

    installStepsCall($o, $auto, 'setupBootloaderBefore');
    installStepsCall($o, $auto, 'setupBootloader');
}
#------------------------------------------------------------------------------
sub configureX {
    my ($auto) = @_;

    #- done here and also at the end of install2.pm, just in case...
    install_any::write_fstab($o);
    $o->{modules_conf}->write;

    require pkgs;
    installStepsCall($o, $auto, 'configureX') if !$::testing && eval { pkgs::packageByName($o->{packages}, 'xorg-x11')->flag_installed } && !$o->{X}{disabled};
}
#------------------------------------------------------------------------------
sub exitInstall {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'exitInstall', getNextStep($::o) eq 'exitInstall');
}


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
#-    $SIG{__DIE__} = sub { warn "DIE " . backtrace() . "\n" };
    $SIG{SEGV} = sub { 
	my $msg = "segmentation fault: seems like memory is missing as the install crashes"; log::l($msg);
	$o->ask_warn('', $msg);
	setVirtual(1);
	require install_steps_auto_install;
	install_steps_auto_install_non_interactive::errorInStep($o, $msg);
    };
    $ENV{PERL_BADLANG} = 1;
    delete $ENV{TERMINFO};
    umask 022;

    $::isInstall = 1;
    $::isWizard = 1;
    $::no_ugtk_init = 1;
    $::expert = 0;

#-    c::unlimit_core() unless $::testing;

    my ($cfg, $patch, @auto);
    my %cmdline = map { 
	my ($n, $v) = split /=/;
	$n => $v || 1;
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

    #- from stage1
    put_in_hash(\%ENV, { getVarsFromSh('/tmp/env') });
    exists $ENV{$_} and $cmdline{lc($_)} = $ENV{$_} foreach qw(METHOD PCMCIA KICKSTART);

    map_each {
	my ($n, $v) = @_;
	my $f = ${{
	    lang      => sub { $o->{locale}{lang} = $v },
	    flang     => sub { $o->{locale}{lang} = $v; push @auto, 'selectLanguage' },
	    method    => sub { $o->{method} = $v },
	    pcmcia    => sub { $o->{pcmcia} = $v },
	    vga16     => sub { $o->{vga16} = $v },
	    vga       => sub { $o->{vga} = $v },
	    step      => sub { $o->{steps}{first} = $v },
	    meta_class => sub { $o->{meta_class} = $v },
	    freedriver => sub { $o->{freedriver} = $v },
	    no_bad_drives => sub { $o->{partitioning}{no_bad_drives} = 1 },
	    nodmraid  => sub { $o->{partitioning}{no_dmraid} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = $v ne "0" },
	    display   => sub { $o->{display} = $v },
	    askdisplay => sub { print "Please enter the X11 display to perform the install on ? "; $o->{display} = chomp_(scalar(<STDIN>)) },
	    security  => sub { $o->{security} = $v },
	    noauto    => sub { $::noauto = 1 },
	    testing   => sub { $::testing = 1 },
	    patch     => sub { $patch = 1 },
	    defcfg    => sub { $cfg = $v },
	    newt      => sub { $o->{interactive} = "newt" },
	    text      => sub { $o->{interactive} = "newt" },
	    stdio     => sub { $o->{interactive} = "stdio" },
	    kickstart => sub { $::auto_install = $v },
	    local_install => sub { $::local_install = 1 },
	    uml_install => sub { $::uml_install = $::local_install = 1 },
	    auto_install => sub { $::auto_install = $v },
	    simple_themes => sub { $o->{simple_themes} = 1 },
	    theme     => sub { $o->{theme} = $v },
	    doc       => sub { $o->{doc} = 1 },  #- will be used to know that we're running for the doc team,
	                                         #- e.g. we want screenshots with a good B&W contrast
	    useless_thing_accepted => sub { $o->{useless_thing_accepted} = 1 },
	    alawindows => sub { $o->{security} = 0; $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    fdisk => sub { $o->{partitioning}{fdisk} = 1 },
	    nomouseprobe => sub { $o->{nomouseprobe} = $v },
	    updatemodules => sub { $o->{updatemodules} = 1 },
	    move  => sub { $::move = 1 },
	    globetrotter  => sub { $::move = 1; $::globetrotter = 1 },
	    suppl => sub { $o->{supplmedia} = 1 },
	    askmedia => sub { $o->{askmedia} = 1 },
	}}{lc $n}; &$f if $f;
    } %cmdline;

    if ($::testing) {
	$ENV{SHARE_PATH} ||= "/export/install/stage2/live/usr/share";
	$ENV{SHARE_PATH} = "/usr/share" if !-e $ENV{SHARE_PATH};
    } else {
	$ENV{SHARE_PATH} ||= "/usr/share";
    }

    undef $::auto_install if $cfg;
    if (!$::testing) {
	unlink $_ foreach "/modules/modules.mar", "/sbin/stage1";
    }

    log::openLog($::testing && 'debug.log');
    log::l("second stage install running (", install_any::drakx_version(), ")");

    eval { output('/proc/sys/kernel/modprobe', "\n") } if !$::local_install && !$::testing; #- disable kmod, otherwise we get a different behaviour in kernel vs kernel-BOOT
    eval { fs::mount::mount('none', '/sys', 'sysfs', 1) };

    if ($::move) {
        require move;
        move::init($o);
    }
    if ($::local_install) {
	push @auto, 
#	  'selectLanguage', 'selectKeyboard', 'miscellaneous', 'selectInstallClass',
	  'doPartitionDisks', 'formatPartitions';
	fs::mount::usbfs(''); #- do it now so that when_load doesn't do it
    }

    cp_f(glob('/stage1/tmp/*'), '/tmp');

    #- free up stage1 memory
    eval { fs::mount::umount($_) } foreach qw(/stage1/proc/bus/usb /stage1/proc /stage1);

    $o->{prefix} = $::prefix = $::testing ? "/tmp/test-perl-install" : $::move ? "" : "/mnt";
    mkdir $o->{prefix}, 0755;

    #-  make sure we do not pick up any gunk from the outside world
    my $remote_path = "$o->{prefix}/sbin:$o->{prefix}/bin:$o->{prefix}/usr/sbin:$o->{prefix}/usr/bin:$o->{prefix}/usr/X11R6/bin";
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$remote_path";

    eval { spawnShell() };

    modules::load_dependencies(($::testing ? ".." : "") . "/modules/modules.dep");
    require modules::any_conf;
    require modules::modules_conf;
    $o->{modules_conf} = modules::modules_conf::read(modules::any_conf::vnew(), '/tmp/modules.conf');
    modules::read_already_loaded($o->{modules_conf});

    #- done before auto_install is called to allow the -IP feature on auto_install file name
    if (-e '/tmp/network') {
	require network::network;
	#- get stage1 network configuration if any.
	log::l('found /tmp/network');
	add2hash($o->{net}{network} ||= {}, network::network::read_conf('/tmp/network'));
	if (my ($file) = glob_('/tmp/ifcfg-*')) {
	    log::l("found network config file $file");
	    my $l = network::network::read_interface_conf($file);
	    $o->{net}{ifcfg}{$l->{DEVICE}} ||= $l;
	}
	if (-e '/etc/resolv.conf') {
	    my $file = '/etc/resolv.conf';
	    log::l("found network config file $file");
	    add2hash($o->{net}{resolv} ||= {}, network::network::read_resolv_conf($file));
	}
	my $dsl_device = find { $_->{BOOTPROTO} eq 'adsl_pppoe' } values %{$o->{net}{ifcfg}};
	if ($dsl_device) {
	    $o->{net}{type} = 'adsl';
	    $o->{net}{net_interface} = $dsl_device->{DEVICE};
	    $o->{net}{adsl} = {
		method => 'pppoe',
		device => $dsl_device->{DEVICE},
		ethernet_device => $dsl_device->{DEVICE},
		login => $dsl_device->{USER},
		password => $dsl_device->{PASS},
	    };
	    %$dsl_device = ();
	} else {
	    $o->{net}{type} = 'lan';
	    $o->{net}{net_interface} = first(values %{$o->{net}{ifcfg}});
	}
    }

    #- done after module dependencies are loaded for "vfat depends on fat"
    if ($::auto_install) {
	if ($::auto_install =~ /-IP(\.pl)?$/) {
	    my ($ip) = cat_('/tmp/stage1.log') =~ /configuring device (?!lo)\S+ ip: (\S+)/;
	    my $normalized_ip = join('', map { sprintf "%02X", $_ } split('\.', $ip)); 
	    $::auto_install =~ s/-IP(\.pl)?$/-$normalized_ip$1/;
	}
	require install_steps_auto_install;
	eval { $o = $::o = install_any::loadO($o, $::auto_install) };
	if ($@) {
	    if ($o->{useless_thing_accepted}) { #- Pixel's hack to be able to fail through
		log::l("error using auto_install, continuing");
		undef $::auto_install;
	    } else {
		install_steps_auto_install_non_interactive::errorInStep($o, "Error using auto_install\n" . formatError($@));
	    }
	} else {
	    log::l("auto install config file loaded successfully");

	    #- normalize for people not using our special scheme
	    foreach (@{$o->{manualFstab} || []}) {
		$_->{device} =~ s!^/dev/!!;
	    }
	}
    }
    $o->{interactive} ||= 'gtk' if !$::auto_install;
 
    if ($o->{interactive} eq "gtk" && availableMemory() < 22 * 1024) {
 	log::l("switching to newt install cuz not enough memory");
 	$o->{interactive} = "newt";
    }

    if (my ($s) = cat_("/proc/cmdline") =~ /brltty=(\S*)/) {
	my ($driver, $device, $table) = split(',', $s);
	$table = "text.$table.tbl" if $table !~ /\.tbl$/;
	log::l("brltty option $driver $device $table");
	$o->{brltty} = { driver => $driver, device => $device, table => $table };
	$o->{interactive} = 'newt';
	$o->{nomouseprobe} = 1;
    }

    # perl_checker: require install_steps_gtk
    # perl_checker: require install_steps_newt
    # perl_checker: require install_steps_stdio
    require "install_steps_$o->{interactive}.pm" if $o->{interactive};

    #- needed before accessing floppy (in case of usb floppy)
    modules::load_category($o->{modules_conf}, 'bus/usb'); 

    #- oem patch should be read before to still allow patch or defcfg.
    eval { $o = $::o = install_any::loadO($o, "install/patch-oem.pl"); log::l("successfully read oem patch") };
    #- patch should be read after defcfg in order to take precedance.
    eval { $o = $::o = install_any::loadO($o, $cfg); log::l("successfully read default configuration: $cfg") } if $cfg;
    eval { $o = $::o = install_any::loadO($o, "patch"); log::l("successfully read patch") } if $patch;

    eval { modules::load("af_packet") };

    require harddrake::sound;
    harddrake::sound::configure_sound_slots($o->{modules_conf});

    #- need to be after oo-izing $o
    if ($o->{brltty}) {
	symlink "/tmp/stage2/$_", $_ foreach "/etc/brltty";
	eval { modules::load("serial") };
	devices::make($_) foreach $o->{brltty}{device} ? $o->{brltty}{device} : qw(ttyS0 ttyS1);
	devices::make("vcsa");
	run_program::run("brltty");
    }

    #- needed very early for install_steps_gtk
    if (!$::testing) {
	eval { $o->{mouse} = mouse::detect($o->{modules_conf}) } if !$o->{mouse} && !$o->{nomouseprobe};
	mouse::load_modules($o->{mouse});
    }

    $o->{locale}{lang} = lang::set($o->{locale}) if $o->{locale}{lang} ne 'en_US' && !$::move; #- mainly for defcfg

    # keep the result otherwise monitor-edid does not return good results afterwards
    eval { any::monitor_full_edid() };

    install_any::start_i810fb();

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    if (!$::move && !$::testing && !$o->{meta_class}) {
	my $VERSION = cat__(install_any::getFile("VERSION")) or do { print "VERSION file missing\n"; sleep 5 };
	my @classes = qw(powerpackplus powerpack desktop download server firewall);
	if (my $meta_class = find { $VERSION =~ /$_/i } @classes) {
	    $o->{meta_class} = $meta_class;
	}
	$o->{distro_type} = 'community' if $VERSION =~ /community/i;
	$o->{distro_type} = 'cooker' if $VERSION =~ /cooker/i;
    }
    $o->{meta_class} eq 'discovery' and $o->{meta_class} = 'desktop';
    $o->{meta_class} eq 'powerpackplus' and $o->{meta_class} = 'server';

    log::l("meta_class $o->{meta_class}");

    foreach (@auto) {
	my $s = $o->{steps}{/::(.*)/ ? $1 : $_} or next;
	$s->{auto} = $s->{hidden} = 1;
    }

    my $o_;
    while (1) {
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

    eval { output('/proc/splash', "verbose\n") } if !$::globetrotter;
  
    #-the main cycle
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep($o)) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	eval {
	    &{$install2::{$o->{step}}}($o->{steps}{$o->{step}}{auto});
	};
	my $err = $@;
	$o->kill_action;
	if ($err) {
	    local $_ = $err;
	    $o->kill_action;
	    if (!/^already displayed/) {
		eval { $o->errorInStep($_) };
		$o->{steps}{$o->{step}}{auto} = 0;
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
    unlink $install_any::clp_on_disk;
    install_any::clean_postinstall_rpms();
    install_any::log_sizes($o);
    install_any::remove_advertising($o);
    install_any::write_fstab($o);
    $o->{modules_conf}->write;
    detect_devices::install_addons($o->{prefix});

    #- mainly for auto_install's
    #- do not use run_program::xxx because it does not leave stdin/stdout unchanged
    system("bash", "-c", $o->{postInstallNonRooted}) if $o->{postInstallNonRooted};
    system("chroot", $o->{prefix}, "bash", "-c", $o->{postInstall}) if $o->{postInstall};

    install_any::ejectCdrom();

    #- to ensure linuxconf does not cry against those files being in the future
    foreach ('/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config') {
	my $now = time() - 24 * 60 * 60;
	utime $now, $now, "$o->{prefix}/$_";
    }
    install_any::killCardServices();

    #- make sure failed upgrade will not hurt too much.
    install_steps::cleanIfFailedUpgrade($o);

    -e "$o->{prefix}/usr/sbin/urpmi.update" or eval { rm_rf("$o->{prefix}/var/lib/urpmi") };

    #- copy latest log files
    eval { cp_af("/tmp/$_", "$o->{prefix}/root/drakx") foreach qw(ddebug.log stage1.log) };

    #- ala pixel? :-) [fpons]
    common::sync(); common::sync();

    log::l("installation complete, leaving");
    log::l("files still open by install2: ", readlink($_)) foreach glob_("/proc/self/fd/*");
    print "\n" x 80;
}

1;
