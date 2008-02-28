package install::install2; # $Id$

use diagnostics;
use strict;
use vars qw($o);

BEGIN { $::isInstall = 1 }

#-######################################################################################
#- misc imports
#-######################################################################################
use install::steps_list;
use common;
use install::any 'addToBeDone';
use install::steps;
use install::any;
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
use fs::any;


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
    uuid_by_default => 1,
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
    steps        => \%install::steps_list::installSteps,
    orderedSteps => \@install::steps_list::orderedInstallSteps,

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

};


sub installStepsCall {
    my ($o, $auto, $fun, @args) = @_;
    $fun = "install::steps::$fun" if $auto;
    $o->$fun(@args);
}
sub getNextStep {
    my ($o) = @_;
    find { !$o->{steps}{$_}{done} && $o->{steps}{$_}{reachable} } @{$o->{orderedSteps}};
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
    installStepsCall($o, $auto, 'choosePartitionsToFormat') if !$o->{isUpgrade} && !$::local_install;
    my $want_root_formated = fs::get::root($o->{fstab})->{toFormat};
    if ($want_root_formated) {
	foreach ('/usr') {
	    my $part = fs::get::mntpoint2part($_, $o->{fstab}) or next;
	    $part->{toFormat} or die N("You must also format %s", $_);
	}
    }
    installStepsCall($o, $auto, 'formatMountPartitions') if !$::testing;

    if ($want_root_formated) {
	#- we formatted /, ensure /var/lib/rpm is cleaned otherwise bad things can happen
	#- (especially when /var is *not* formatted)
	eval { rm_rf("$::prefix/var/lib/rpm") };
    }

    fs::any::prepare_minimal_root($o->{all_hds});

    install::any::screenshot_dir__and_move();
    install::any::move_compressed_image_to_disk($o);

    any::rotate_logs($::prefix);

    require raid;
    raid::write_conf($o->{all_hds}{raids});
}

#------------------------------------------------------------------------------
sub choosePackages {
    my ($auto) = @_;
    require install::pkgs;

    #- always setPackages as it may have to copy hdlist and synthesis files.
    installStepsCall($o, $auto, 'setPackages');
    installStepsCall($o, $auto, 'choosePackages');
    my @flags = map_each { if_($::b, $::a) } %{$o->{rpmsrate_flags_chosen}};
    log::l("rpmsrate_flags_chosen's: ", join(' ', sort @flags));

    #- check pre-condition that basesystem package must be selected.
    install::pkgs::packageByName($o->{packages}, 'basesystem')->flag_available or die "basesystem package not selected";

    #- check if there are packages that need installation.
    $o->{steps}{installPackages}{done} = 0 if $o->{steps}{installPackages}{done} && install::pkgs::packagesToInstall($o->{packages}) > 0;
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
    modules::load_category($o->{modules_conf}, list_modules::ethernet_categories());
    require network::connection::ethernet;
    if (!$o->{isUpgrade}) {
        installStepsCall($o, $auto, 'configureNetwork');
    } else {
        network::connection::ethernet::configure_eth_aliases($o->{modules_conf});
    }
}
#------------------------------------------------------------------------------
sub installUpdates {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'installUpdates');
}
#------------------------------------------------------------------------------
sub configureServices {
    my ($auto) = @_;
    installStepsCall($o, $auto, 'configureServices');
}
#------------------------------------------------------------------------------
sub setRootPassword_addUser {
    my ($auto) = @_;

    installStepsCall($o, $auto, 'setRootPassword_addUser') if !$o->{isUpgrade};
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
    install::any::write_fstab($o);
    $o->{modules_conf}->write;

    require install::pkgs;
    installStepsCall($o, $auto, 'configureX') if !$::testing && eval { install::pkgs::packageByName($o->{packages}, 'task-x11')->flag_installed } && !$o->{X}{disabled};
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
	my $msg = "segmentation fault: install crashed (maybe memory is missing?)"; log::l($msg);
	$o->ask_warn('', $msg);
	setVirtual(1);
	require install::steps_auto_install;
	install::steps_auto_install_non_interactive::errorInStep($o, $msg);
    };
    $ENV{PERL_BADLANG} = 1;
    delete $ENV{TERMINFO};
    umask 022;

    $::isWizard = 1;
    $::no_ugtk_init = 1;

    push @::textdomains, 'DrakX', 'drakx-net', 'drakx-kbd-mouse-x11';

    my ($cfg, $patch);
    my %cmdline = map { 
	my ($n, $v) = split /=/;
	$n => defined($v) ? $v : 1;
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
	    flang     => sub { $o->{locale}{lang} = $v; push @::auto_steps, 'selectLanguage' },
	    langs     => sub { $o->{locale}{langs} = +{ map { $_ => 1 } split(':', $v) } },
	    method    => sub { $o->{method} = $v },
	    pcmcia    => sub { $o->{pcmcia} = $v },
	    vga16     => sub { $o->{vga16} = $v },
	    vga       => sub { $o->{vga} = $v =~ /0x/ ? hex($v) : $v },
	    step      => sub { $o->{steps}{first} = $v },
	    meta_class => sub { $o->{meta_class} = $v },
	    freedriver => sub { $o->{freedriver} = $v },
	    no_bad_drives => sub { $o->{partitioning}{no_bad_drives} = 1 },
	    nodmraid  => sub { $o->{partitioning}{nodmraid} = 1 },
	    readonly  => sub { $o->{partitioning}{readonly} = $v ne "0" },
	    display   => sub { $o->{display} = $v },
	    askdisplay => sub { print "Please enter the X11 display to perform the install on ? "; $o->{display} = chomp_(scalar(<STDIN>)) },
	    security  => sub { $o->{security} = $v },
	    noauto    => sub { $::noauto = 1 },
	    testing   => sub { $::testing = 1 },
	    patch     => sub { $patch = 1 },
	    defcfg    => sub { $cfg = $v },
	    newt      => sub { $o->{interactive} = "curses" },
	    text      => sub { $o->{interactive} = "curses" },
	    stdio     => sub { $o->{interactive} = "stdio" },
	    use_uuid  => sub { $o->{uuid_by_default} = $v },
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
	    rpm_dbapi => sub { $o->{rpm_dbapi} = $v },
	    nomouseprobe => sub { $o->{nomouseprobe} = $v },
	    updatemodules => sub { $o->{updatemodules} = 1 },
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

    $o->{stage2_phys_medium} = install::media::stage2_phys_medium($o->{method});

    log::l("second stage install running (", install::any::drakx_version($o), ")");

    eval { output('/proc/sys/kernel/modprobe', "\n") } if !$::local_install && !$::testing; #- disable kmod
    eval { fs::mount::mount('none', '/sys', 'sysfs', 1) };
    eval { touch('/root/non-chrooted-marker.DrakX') }; #- helps distinguishing /root and /mnt/root when we don't know if we are chrooted

    if ($::local_install) {
	push @::auto_steps, 
#	  'selectLanguage', 'selectKeyboard', 'miscellaneous', 'selectInstallClass',
	  'doPartitionDisks', 'formatPartitions';
	fs::mount::usbfs(''); #- do it now so that when_load doesn't do it
	$o->{nomouseprobe} = 1;
	$o->{mouse} = mouse::fullname2mouse('Universal|Any PS/2 & USB mice');
    }

    $o->{prefix} = $::prefix = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $::prefix, 0755;

    #-  make sure we do not pick up any gunk from the outside world
    my $remote_path = "$::prefix/sbin:$::prefix/bin:$::prefix/usr/sbin:$::prefix/usr/bin:$::prefix/usr/X11R6/bin";
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:/usr/X11R6/bin:$remote_path";

    eval { install::any::spawnShell() };

    list_modules::load_default_moddeps();
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
	require install::steps_auto_install;
	eval { $o = $::o = install::any::loadO($o, $::auto_install) };
	if ($@) {
	    if ($o->{useless_thing_accepted}) { #- Pixel's hack to be able to fail through
		log::l("error using auto_install, continuing");
		undef $::auto_install;
	    } else {
		install::steps_auto_install_non_interactive::errorInStep($o, "Error using auto_install\n" . formatError($@));
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
 	log::l("switching to curses install cuz not enough memory");
 	$o->{interactive} = "curses";
    }

    if (my ($s) = cat_("/proc/cmdline") =~ /brltty=(\S*)/) {
	my ($driver, $device, $table) = split(',', $s);
	$table = "text.$table.tbl" if $table !~ /\.tbl$/;
	log::l("brltty option $driver $device $table");
	$o->{brltty} = { driver => $driver, device => $device, table => $table };
	$o->{interactive} = 'curses';
	$o->{nomouseprobe} = 1;
    }

    # perl_checker: require install::steps_gtk
    # perl_checker: require install::steps_curses
    # perl_checker: require install::steps_stdio
    require "install/steps_$o->{interactive}.pm" if $o->{interactive};

    #- needed before accessing floppy (in case of usb floppy)
    modules::load_category($o->{modules_conf}, 'bus/usb'); 

    #- oem patch should be read before to still allow patch or defcfg.
    eval { $o = $::o = install::any::loadO($o, "install/patch-oem.pl"); log::l("successfully read oem patch") };
    #- patch should be read after defcfg in order to take precedance.
    eval { $o = $::o = install::any::loadO($o, $cfg); log::l("successfully read default configuration: $cfg") } if $cfg;
    eval { $o = $::o = install::any::loadO($o, "patch"); log::l("successfully read patch") } if $patch;

    eval { modules::load("af_packet") };

    require harddrake::sound;
    harddrake::sound::configure_sound_slots($o->{modules_conf});

    #- need to be after oo-izing $o
    if ($o->{brltty}) {
	symlink "/tmp/stage2/$_", $_ foreach "/etc/brltty";
	devices::make($_) foreach $o->{brltty}{device} ? $o->{brltty}{device} : qw(ttyS0 ttyS1);
	devices::make("vcsa");
	run_program::run("brltty");
    }

    #- needed very early for install::steps_gtk
    if (!$::testing) {
	eval { $o->{mouse} = mouse::detect($o->{modules_conf}) } if !$o->{mouse} && !$o->{nomouseprobe};
	mouse::load_modules($o->{mouse});
    }

    lang::set($o->{locale});

    # keep the result otherwise monitor-edid does not return good results afterwards
    eval { any::monitor_full_edid() };

    install::any::start_i810fb();

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    if (!$::testing) {
	my $product_id = cat__(install::any::getFile_($o->{stage2_phys_medium}, "product.id"));
	log::l('product_id: ' . chomp_($product_id));
	$o->{product_id} = common::parse_LDAP_namespace_structure($product_id);

	$o->{meta_class} ||= {
	    One          => 'desktop',
	    Free         => 'download',
	    Powerpack    => 'powerpack',
	}->{$o->{product_id}{product}} || 'download';
    }

    log::l("META_CLASS=$o->{meta_class}");
    $ENV{META_CLASS} = $o->{meta_class}; #- for Ia Ora

    foreach (@::auto_steps) {
	if (my $s = $o->{steps}{/::(.*)/ ? $1 : $_}) {
	    $s->{auto} = $s->{hidden} = 1;
	} else {
	    log::l("ERROR: unknown step $_ in auto_steps");
	}
    }

    my $o_;
    while (1) {
    	$o_ = $::auto_install ?
    	  install::steps_auto_install->new($o) :
    	    $o->{interactive} eq "stdio" ?
    	  install::steps_stdio->new($o) :
    	    $o->{interactive} eq "curses" ?
    	  install::steps_curses->new($o) :
    	    $o->{interactive} eq "gtk" ?
    	  install::steps_gtk->new($o) :
    	    die "unknown install type";
	$o_ and last;

	log::l("$o->{interactive} failed, trying again with curses");
	$o->{interactive} = "curses";
	require install::steps_curses;
    }
    $::o = $o = $o_;

    eval { output('/proc/splash', "verbose\n") };
  
    #-the main cycle
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep($o)) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	eval {
	    &{$install::install2::{$o->{step}}}($o->{steps}{$o->{step}}{auto});
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
    unlink $install::any::compressed_image_on_disk;
    install::media::clean_postinstall_rpms();
    install::media::log_sizes();
    install::any::remove_advertising();
    install::any::write_fstab($o);
    $o->{modules_conf}->write;
    detect_devices::install_addons($::prefix);

    install::any::adjust_files_mtime_to_timezone();

    #- make sure failed upgrade will not hurt too much.
    install::steps::cleanIfFailedUpgrade($o);

    -e "$::prefix/usr/sbin/urpmi.update" or eval { rm_rf("$::prefix/var/lib/urpmi") };

    system("chroot", $::prefix, "bash", "-c", $o->{postInstallBeforeReboot}) if $o->{postInstallBeforeReboot};

    #- copy latest log files
    eval { cp_af("/tmp/$_", "$::prefix/root/drakx") foreach qw(ddebug.log stage1.log) };

    #- ala pixel? :-) [fpons]
    common::sync(); common::sync();

    log::l("installation complete, leaving");
    log::l("files still open by install2: ", readlink($_)) foreach glob_("/proc/self/fd/*");
    print "\n" x 80 if !$::local_install;
}

1;
