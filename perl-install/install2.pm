
package install2; # $Id$

use diagnostics;
use strict;
use vars qw($o $version);

#-######################################################################################
#- misc imports
#-######################################################################################
use steps;
use common;
use install_any qw(:all);
use install_steps;
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


#-#######################################################################################
#-$O
#-the big struct which contain, well everything (globals + the interactive methods ...)
#-if you want to do a kickstart file, you just have to add all the required fields (see for example
#-the variable $default)
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, lba32 => 1, message => 1, timeout => 5, restricted => 0 },
    mkbootdisk => 0, #- no mkbootdisk if 0 or undef, find a floppy with 1, or fd1
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0 }, #-, readonly => 0 },
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
    steps        => \%steps::installSteps,
    orderedSteps => \@steps::orderedInstallSteps,

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
    my ($clicked, $ent_number, $auto) = @_;

    installStepsCall($o, $auto, 'selectLanguage', $ent_number == 1);

    $o->acceptLicence;
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($clicked, $ent_number, $auto) = @_;

    require pkgs;
    my ($first_time) = $ent_number == 1;

    add2hash($o->{mouse} ||= {}, mouse::read($o->{prefix})) if $o->{isUpgrade} && $first_time;

    installStepsCall($o, $auto, 'selectMouse', !$first_time || $clicked);

    addToBeDone { mouse::write($o->{prefix}, $o->{mouse}) } 'installPackages';
}

#------------------------------------------------------------------------------
sub setupSCSI {
    my ($clicked, $ent_number, $auto) = @_;

    if (!$::live && !$::g_auto_install && !$o->{blank} && !$::testing) {
	-s modules::cz_file() or die _("Can't access kernel modules corresponding to your kernel (file %s is missing), this generally means your boot floppy in not in sync with the Installation medium (please create a newer boot floppy)", modules::cz_file());
    }

    installStepsCall($o, $auto, 'setupSCSI', $clicked);
}

#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($clicked, $first_time, $auto) = ($_[0], $_[1] == 1, $_[2]);

    if ($o->{isUpgrade} && $first_time && $o->{keyboard_unsafe}) {
	my $keyboard = keyboard::read($o->{prefix});
	$keyboard and $o->{keyboard} = $keyboard;
    }
    installStepsCall($o, $auto, 'selectKeyboard', $clicked);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($clicked, $ent_number, $auto) = @_;

    installStepsCall($o, $auto, 'selectInstallClass', $clicked);

    if ($o->{steps}{choosePackages}{entered} >= 1 && !$o->{steps}{installPackages}{done}) {
	installStepsCall($o, $auto, 'setPackages');
	installStepsCall($o, $auto, 'selectPackagesToUpgrade') if $o->{isUpgrade};
    }
    if ($o->{isUpgrade}) {
	@{$o->{orderedSteps}} = map { /setupSCSI/ ? ($_, "doPartitionDisks") : $_ }
	                        grep { !/doPartitionDisks/ } @{$o->{orderedSteps}};
	$o->{keepConfiguration} and @{$o->{orderedSteps}} = grep { !/selectMouse|selectKeyboard|miscellaneous|setRootPassword|addUser|configureNetwork|installUpdates|summary|configureServices|configureX/ } @{$o->{orderedSteps}};
	my $s; foreach (@{$o->{orderedSteps}}) {
	    $s->{next} = $_ if $s;
	    $s = $o->{steps}{$_};
	}
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($clicked, $ent_number, $auto) = @_;
    $o->{steps}{formatPartitions}{done} = 0;
    installStepsCall($o, $auto, 'doPartitionDisksBefore');
    installStepsCall($o, $auto, 'doPartitionDisks');
    installStepsCall($o, $auto, 'doPartitionDisksAfter');
}

sub formatPartitions {
    my ($clicked, $ent_number, $auto) = @_;

    $o->{steps}{choosePackages}{done} = 0;
    installStepsCall($o, $auto, 'choosePartitionsToFormat', $o->{fstab}) if !$o->{isUpgrade};
    my $want_root_formated = fsedit::get_root($o->{fstab})->{toFormat};
    if ($want_root_formated) {
	foreach ('/usr') {
	    my $part = fsedit::mntpoint2part($_, $o->{fstab}) or next;
	    $part->{toFormat} or die _("You must also format %s", $_);
	}
    }
    installStepsCall($o, $auto, 'formatMountPartitions', $o->{fstab}) if !$::testing;

    if ($want_root_formated) {
	#- we formatted /, ensure /var/lib/rpm is cleaned otherwise bad things can happen
	#- (especially when /var is *not* formatted)
	eval { rm_rf("$o->{prefix}/var/lib/rpm") };
    }

    mkdir "$o->{prefix}/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/rpm etc/sysconfig etc/sysconfig/console 
	etc/sysconfig/network-scripts etc/sysconfig/console/consolefonts 
	etc/sysconfig/console/consoletrans
	home mnt tmp var var/tmp var/lib var/lib/rpm var/lib/urpmi);
    mkdir "$o->{prefix}/$_", 0700 foreach qw(root root/tmp root/drakx);

    common::screenshot_dir__and_move();

    any::rotate_logs($o->{prefix});

    require raid;
    raid::prepare_prefixed($o->{all_hds}{raids}, $o->{prefix});
}

#------------------------------------------------------------------------------
sub choosePackages {
    my ($clicked, $ent_number, $auto) = @_;
    require pkgs;

    #- always setPackages as it may have to copy hdlist files and depslist file.
    installStepsCall($o, $auto, 'setPackages');
    installStepsCall($o, $auto, 'selectPackagesToUpgrade') if $o->{isUpgrade} && $ent_number == 1;

    installStepsCall($o, $auto, 'choosePackages', $o->{packages}, $o->{compssUsers}, $ent_number == 1);
    log::l("compssUsersChoice's: ", join(" ", grep { $o->{compssUsersChoice}{$_} } keys %{$o->{compssUsersChoice}}));

    #- check pre-condition where base backage has to be selected.
    pkgs::packageFlagSelected(pkgs::packageByName($o->{packages}, 'basesystem')) or die "basesystem package not selected";

    #- check if there are package that need installation.
    $o->{steps}{installPackages}{done} = 0 if $o->{steps}{installPackages}{done} && pkgs::packagesToInstall($o->{packages}) > 0;
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($clicked, $ent_number, $auto) = @_;

    installStepsCall($o, $auto, 'readBootloaderConfigBeforeInstall') if $ent_number == 1;

    installStepsCall($o, $auto, 'beforeInstallPackages');
    installStepsCall($o, $auto, 'installPackages');
    installStepsCall($o, $auto, 'afterInstallPackages');
}
#------------------------------------------------------------------------------
sub miscellaneous {
    my ($clicked, $ent_number, $auto) = @_;

    installStepsCall($o, $auto, 'miscellaneousBefore', $clicked);
    installStepsCall($o, $auto, 'miscellaneous', $clicked);
    installStepsCall($o, $auto, 'miscellaneousAfter', $clicked);
}

#------------------------------------------------------------------------------
sub summary {
    my ($clicked, $ent_number, $auto) = @_;
    installStepsCall($o, $auto, 'summary', $ent_number == 1);
}
#------------------------------------------------------------------------------
sub configureNetwork {
    my ($clicked, $ent_number, $auto) = @_;
    #- get current configuration of network device.
    require network;
    eval { network::read_all_conf($o->{prefix}, $o->{netc} ||= {}, $o->{intf} ||= {}) };
    installStepsCall($o, $auto, 'configureNetwork', $ent_number == 1, $clicked);
}
#------------------------------------------------------------------------------
sub installCrypto {
    my ($clicked, $ent_number, $auto) = @_;
    installStepsCall($o, $auto, 'installCrypto');
}
#------------------------------------------------------------------------------
sub installUpdates {
    my ($clicked, $ent_number, $auto) = @_;
    installStepsCall($o, $auto, 'installUpdates');
}
#------------------------------------------------------------------------------
sub configureServices {
    my ($clicked, $ent_number, $auto) = @_;
    installStepsCall($o, $auto, 'configureServices', $clicked);
}
#------------------------------------------------------------------------------
sub setRootPassword {
    my ($clicked, $ent_number, $auto) = @_;
    return if $o->{isUpgrade};

    installStepsCall($o, $auto, 'setRootPassword', $clicked);
    addToBeDone { install_any::setAuthentication($o) } 'installPackages';
}
#------------------------------------------------------------------------------
sub addUser {
    my ($clicked, $ent_number, $auto) = @_;
    return if $o->{isUpgrade} && !$clicked;

    installStepsCall($o, $auto, 'addUser', $clicked);
}

#------------------------------------------------------------------------------
sub createBootdisk {
    my ($clicked, $ent_number, $auto) = @_;
    modules::write_conf($o->{prefix});
    installStepsCall($o, $auto, 'createBootdisk', $ent_number == 1, $clicked);
}

#------------------------------------------------------------------------------
sub setupBootloader {
    my ($clicked, $ent_number, $auto) = @_;
    return if $::g_auto_install;

    modules::write_conf($o->{prefix});

    installStepsCall($o, $auto, 'setupBootloaderBefore') if $ent_number == 1;
    installStepsCall($o, $auto, 'setupBootloader', $ent_number-1 + $clicked*2); #- gore :-(

    local $ENV{DRAKX_PASSWORD} = $o->{bootloader}{password};
    local $ENV{DURING_INSTALL} = 1;
    run_program::rooted($o->{prefix}, "/usr/sbin/msec", "-o", "run_commands=0", "-o", "log=stderr", $o->{security});
    any::config_libsafe($o->{prefix}, $o->{libsafe});
}
#------------------------------------------------------------------------------
sub configureX {
    my ($clicked, $ent_number, $auto) = @_;

    #- done here and also at the end of install2.pm, just in case...
    install_any::write_fstab($o);
    modules::write_conf($o->{prefix});

    require pkgs;
    installStepsCall($o, $auto, 'configureX', $clicked) if pkgs::packageFlagInstalled(pkgs::packageByName($o->{packages}, 'XFree86')) && !$o->{X}{disabled} || $clicked || $::testing;
}
#------------------------------------------------------------------------------
sub exitInstall {
    my ($clicked, $ent_number, $auto) = @_;
    installStepsCall($o, $auto, 'exitInstall', getNextStep() eq 'exitInstall');
}


sub start_i810fb {

    my ($vga) = cat_('/proc/cmdline') =~ /vga=(\S+)/;
    return if !$vga || listlength(cat_('/proc/fb'));

    my %vga_to_xres = (0x311 => '640', 0x314 => '800', 0x317 => '1024');
    my $xres = $vga_to_xres{$vga} || '800';

    log::l("trying to load i810fb module with xres <$xres> (vga was <$vga>)");
    eval {
	any::ddcxinfos(); # keep the result otherwise ddcxinfos doesn't return good results afterwards
	modules::load('i810fb', undef,
		      ("xres=$xres", 'hsync1=32', 'hsync2=48', 'vsync1=50', 'vsync2=70',  #- this sucking i810fb does not accept floating point numbers in hsync!
		       'vram=2', 'bpp=16', 'accel=1', 'mtrr=1', 'hwcur=1', 'xcon=4'));
    };
}


#-######################################################################################
#- MAIN
#-######################################################################################
sub main {
    $SIG{__DIE__} = sub { chomp(my $err = $_[0]); log::l("warning: $err") };
    $SIG{SEGV} = sub { 
	my $msg = "segmentation fault: seems like memory is missing as the install crashes"; print "$msg\n"; log::l($msg);
	$o->ask_warn('', $msg);
	setVirtual(1);
	require install_steps_auto_install;
	install_steps_auto_install_non_interactive::errorInStep ();
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
	    askdisplay => sub { print "Please enter the X11 display to perform the install on ? "; $o->{display} = chomp_(scalar(<STDIN>)) },
	    security  => sub { $o->{security} = $v },
	    live      => sub { $::live = 1 },
	    noauto    => sub { $::noauto = 1 },
	    test      => sub { $::testing = 1 },
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
	    blank         => sub { $o->{blank} = 1},
	    updatemodules => sub { $o->{updatemodules} = 1},
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

    #- done before auto_install is called to allow the -IP feature on auto_install file name
    if (-e '/tmp/network') {
	require network;
	#- get stage1 network configuration if any.
	log::l('found /tmp/network');
	$o->{netc} ||= {};
	add2hash($o->{netc}, network::read_conf('/tmp/network'));
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

    #- done after module dependencies are loaded for "vfat depends on fat"
    if ($::auto_install) {
	if ($::auto_install =~ /-IP(\.pl)?$/) {
	    my $ip = join('', map { sprintf "%02X", $_ } split '\.', $o->{intf}{IPADDR});
	    $::auto_install =~ s/-IP(\.pl)?$/-$ip$1/;
	}
	require install_steps_auto_install;
	eval { $o = $::o = install_any::loadO($o, $::auto_install) };
	if ($@) {
	    if ($o->{useless_thing_accepted}) { #- Pixel's hack to be able to fail through
		log::l("error using auto_install, continuing");
		undef $::auto_install;
	    } else {
		print "Error using auto_install\n$@\n";
		install_steps_auto_install_non_interactive::errorInStep ();
	    }
	} else {
	    log::l("auto install config file loaded successfully");
	}
    }
    $o->{interactive} ||= 'gtk' if !$::auto_install;
 
    if ($o->{interactive} eq "gtk" && availableMemory < 22 * 1024) {
 	log::l("switching to newt install cuz not enough memory");
 	$o->{interactive} = "newt";
    }
    require"install_steps_$o->{interactive}.pm" if $o->{interactive}; #- no space to skip perl2fcalls

    #- needed before accessing floppy (in case of usb floppy)
    $::noauto or modules::load_thiskind("usb"); 

    #- patch should be read after defcfg in order to take precedance.
    eval { $o = $::o = install_any::loadO($o, $cfg) } if $cfg;
    eval { $o = $::o = install_any::loadO($o, "patch") } if $patch;

    eval { modules::load("af_packet") };

    map_index {
	modules::add_alias("sound-slot-$::i", $_->{driver});
    } modules::get_that_type('sound');

    #- needed very early for install_steps_gtk
    eval { ($o->{mouse}, @{$o->{wacom} = []}) = mouse::detect() } unless $o->{nomouseprobe} || $o->{mouse};

    $o->{lang} = lang::set($o->{lang}) if $o->{lang} ne 'en_US'; #- mainly for defcfg

    start_i810fb();

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    my $VERSION = cat__(install_any::getFile("VERSION")) or do { print "VERSION file missing\n"; sleep 5 };
    $o->{lnx4win} = 1 if $VERSION =~ /lnx4win/i;
    $o->{meta_class} = 'desktop' if $VERSION =~ /desktop/i;
    $o->{meta_class} = 'firewall' if $VERSION =~ /firewall/i;
    $o->{meta_class} = 'server' if $VERSION =~ /server/i;
    if ($::oem) {
	$o->{partitioning}{use_existing_root} = 1;
	$o->{compssListLevel} = 4;
	push @auto, 'selectInstallClass', 'doPartitionDisks', 'choosePackages', 'configureTimezone', 'exitInstall';
    }

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

    install_any::remove_unused() if common::usingRamdisk();

    #-the main cycle
    my $clicked = 0;
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep()) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	if ($o->{steps}{$o->{step}}{icon}) { $o->{icon} = $o->{steps}{$o->{step}}{icon} } else { undef $o->{icon} }
	eval {
	    &{$install2::{$o->{step}}}($clicked || $o->{steps}{$o->{step}}{noauto},
				       $o->{steps}{$o->{step}}{entered},
				       $clicked ? 0 : $o->{steps}{$o->{step}}{auto});
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
    install_any::clean_postinstall_rpms();
    install_any::log_sizes($o);
    install_any::remove_advertising($o);
    install_any::write_fstab($o);
    modules::write_conf($o->{prefix});

    #- mainly for auto_install's
    #- do not use run_program::xxx because it doesn't leave stdin/stdout unchanged
    system("bash", "-c", $o->{postInstallNonRooted}) if $o->{postInstallNonRooted};
    system("chroot", $o->{prefix}, "bash", "-c", $o->{postInstall}) if $o->{postInstall};

    install_any::ejectCdrom();

    #- to ensure linuxconf doesn't cry against those files being in the future
    foreach ('/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config') {
	my $now = time - 24 * 60 * 60;
	utime $now, $now, "$o->{prefix}/$_";
    }
    $::live or install_any::killCardServices();

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

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
