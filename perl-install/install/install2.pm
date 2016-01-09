package install::install2;

use diagnostics;
use strict;
use vars qw($o);
use Getopt::Long qw(GetOptionsFromArray :config no_ignore_case no_auto_abbrev no_getopt_compat);

BEGIN { $::isInstall = 1 }

=head1 SYNOPSYS

The installer stage2 real entry point

=cut

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
use fs::mount;

#-#######################################################################################
=head1 Data Structure

=head2 $O;

$o (or $::o in other modules) is the big struct which contain, well everything:

=over 4

=item * globals

=item * the interactive methods

=item * ...

=back

if you want to do a kickstart file, you just have to add all the required fields (see for example
the variable $default)

=cut
#-#######################################################################################
$o = $::o = {
#    bootloader => { linear => 0, message => 1, timeout => 5, restricted => 0 },
#-    packages   => [ qw() ],
    partitioning => { clearall => 0, eraseBadPartitions => 0, auto_allocate => 0 }, #-, readonly => 0 },
    authentication => { blowfish => 1, shadow => 1 },
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

=head1 Steps Navigation

=over

=cut

sub installStepsCall {
    my ($o, $auto, $fun, @args) = @_;
    $fun = "install::steps::$fun" if $auto;
    $o->$fun(@args);
}

=item getNextStep($o)

Returns next step

=cut

sub getNextStep {
    my ($o) = @_;
    find { !$o->{steps}{$_}{done} && $o->{steps}{$_}{reachable} } @{$o->{orderedSteps}};
}

#-######################################################################################

=back

=head1 Steps Functions

Each step function are called with two arguments : clicked(because if you are a
beginner you can force the the step) and the entered number

=cut

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

    fs::any::prepare_minimal_root();

    install::any::screenshot_dir__and_move();
    # we no longer use squashfs
    #install::any::move_compressed_image_to_disk($o);

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
    my $base_pkg = install::pkgs::packageByName($o->{packages}, 'basesystem');
    $base_pkg->flag_available or $base_pkg->flag_installed or die "basesystem package not selected";

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
    install::any::write_fstab($o);

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

=head1 Udev Functions

=over

=cut

#-######################################################################################

=item start_udev()

=cut

sub start_udev() {
    return if fuzzy_pidofs('udevd');

    # Start up udev:
    mkdir_p("/run/udev/rules.d");
    $ENV{UDEVRULESD} = "/run/udev/rules.d";
    run_program::run("/usr/lib/systemd/systemd-udevd", "--daemon", "--resolve-names=never");
    # Coldplug all devices:
    run_program::run("udevadm", "trigger", "--type=subsystems", "--action=add");
    run_program::run("udevadm", "trigger", "--type=devices", "--action=add");
}

=item stop_udev()

=cut

sub stop_udev() {
    kill 15, fuzzy_pidofs('udevd');
    sleep(2);
    fs::mount::umount($_) foreach '/dev/pts', '/dev/shm';
}

#-######################################################################################

=back

=head1 Other Functions

=over

=cut

#-######################################################################################

sub init_local_install {
    my ($o) = @_;
    push @::auto_steps, 
#      'selectLanguage', 'selectKeyboard', 'miscellaneous', 'selectInstallClass',
      'doPartitionDisks', 'formatPartitions';
	fs::mount::sys_kernel_debug('');  #- do it now so that when_load doesn't do it
	$o->{nomouseprobe} = 1;
	$o->{mouse} = mouse::fullname2mouse('Universal|Any PS/2 & USB mice');
}

sub pre_init_brltty() {
    if (my ($s) = cat_("/proc/cmdline") =~ /brltty=(\S*)/) {
	my ($driver, $device, $table) = split(',', $s);
	$table = "text.$table.tbl" if $table !~ /\.tbl$/;
	log::l("brltty option $driver $device $table");
	$o->{brltty} = { driver => $driver, device => $device, table => $table };
	$o->{interactive} = 'curses';
	$o->{nomouseprobe} = 1;
    }
}

sub init_brltty() {
    symlink "/tmp/stage2/$_", $_ foreach "/etc/brltty";
    devices::make($_) foreach $o->{brltty}{device};
    run_program::run("brltty");
}

sub init_auto_install() {
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

sub step_init {
  my ($o) = @_;
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
  $o;
}

sub read_product_id() {
    my $product_id = cat__(install::any::getFile_($o->{stage2_phys_medium}, "product.id"));
    log::l('product_id: ' . chomp_($product_id));
    $o->{product_id} = common::parse_LDAP_namespace_structure($product_id);
 
    $o->{meta_class} ||= {
        LXDE         => 'light',
        One          => 'desktop',
        Free         => 'download',
        Powerpack    => 'powerpack',
    }->{$o->{product_id}{product}} || 'download';
}

sub sig_segv_handler() {
    my $msg = "segmentation fault: install crashed (maybe memory is missing?)\n" . backtrace();
    log::l("$msg\n");
    # perl_checker: require UNIVERSAL
    UNIVERSAL::can($o, 'ask_warn') and $o->ask_warn('', $msg);
    setVirtual(1);
    require install::steps_auto_install;
    install::steps_auto_install_non_interactive::errorInStep($o, $msg);
}

=item read_stage1_net_conf() {

Reads back netork configuration done by stage1 (see L<stages>).

=cut

sub read_stage1_net_conf() {
    require network::network;
    #- get stage1 network configuration if any.
    log::l('found /tmp/network');
    add2hash($o->{net}{network} ||= {}, network::network::read_conf('/tmp/network'));
    if (my ($file) = grep { -f $_ } glob_('/tmp/ifcfg-*')) {
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

=item parse_args($cfg, $patch)

Parse arguments (which came from either the boot loader command line or its configuration file).

=cut

sub parse_args {
    my ($cfg, $patch);
    my @cmdline = (@_, map { "--$_" } split ' ', cat_("/proc/cmdline"));

    #- from stage1
    put_in_hash(\%ENV, { getVarsFromSh('/tmp/env') });
    exists $ENV{$_} and push @cmdline, sprintf("--%s=%s", lc($_), $ENV{$_}) foreach qw(METHOD PCMCIA KICKSTART);

    GetOptionsFromArray(\@cmdline,
	    'keyboard=s'   => sub { $o->{keyboard} = $_[1]; push @::auto_steps, 'selectKeyboard' },
	    'lang=s'       => \$o->{lang},
	    'flang=s'      => sub { $o->{lang} = $_[1]; push @::auto_steps, 'selectLanguage' },
	    'langs=s'      => sub { $o->{locale}{langs} = +{ map { $_ => 1 } split(':', $_[1]) } },
	    'method=s'     => \$o->{method},
	    'pcmcia=s'     => \$o->{pcmcia},
	    'step=s'       => \$o->{steps}{first},
	    'meta_class=s' => \$o->{meta_class},
	    'freedriver=s' => \$o->{freedriver},

	    # fs/block options:
	    no_bad_drives  => \$o->{partitioning}{no_bad_drives},
	    nodmraid       => \$o->{partitioning}{nodmraid},
	    'readonly=s'   => sub { $o->{partitioning}{readonly} = $_[1] ne "0" },
	    'use_uuid=s'   => sub { $::no_uuid_by_default = !$_[1] },

	    # urpmi options:
	    justdb    => sub { $o->{justdb} = 1 },
	    debug_urpmi  => \$o->{debug_urpmi},
	    deploops     => \$o->{deploops},
	    justdb    => \$o->{justdb},
	    'tune-rpm' => sub { $o->{'tune-rpm'} = 'all' },

	    # GUI options:
	    'vga16=s'      => \$o->{vga16},
	    'vga=s'        => sub { $o->{vga} = $_[1] =~ /0x/ ? hex($_[1]) : $_[1] },
	    'display=s'    => \$o->{display},
	    askdisplay     => sub { print "Please enter the X11 display to perform the install on ? "; $o->{display} = chomp_(scalar(<STDIN>)) },
	    'newt|text'    => sub { $o->{interactive} = "curses" },
	    stdio          => sub { $o->{interactive} = "stdio" },
	    simple_themes  => \$o->{simple_themes},
	    'theme=s'      => \$o->{theme},
	    doc            => \$o->{doc},        #- will be used to know that we're running for the doc team,
	                                         #- e.g. we want screenshots with a good B&W contrast

	    'security=s'   => \$o->{security},

	    # auto install options:
	    noauto         => \$::noauto,
	    testing        => \$::testing,
	    patch          => \$patch,
	    'defcfg=s'     => \$cfg,
	    'auto_install|kickstart=s' => \$::auto_install,

	    local_install  => \$::local_install,
	    uml_install    => sub { $::uml_install = $::local_install = 1 },

	    # debugging options:
	    useless_thing_accepted => \$o->{useless_thing_accepted},
	    alawindows => sub { $o->{security} = 0; $o->{partitioning}{clearall} = 1; $o->{bootloader}{crushMbr} = 1 },
	    fdisk          => \$o->{partitioning}{fdisk},
	    'nomouseprobe=s' => \$o->{nomouseprobe},
	    updatemodules  => \$o->{updatemodules},

	    'suppl=s'      => \$o->{supplmedia},
	    askmedia       => \$o->{askmedia},
	    restore        => \$::isRestore,
	    'compsslistlevel=s' => \$o->{compssListLevel},

	    # to ignore:
	    'BOOT_IMAGE|quiet|resume|root|splash' => sub {},
	);

    ($cfg, $patch);
}

sub init_env_share() {
    if ($::testing) {
	$ENV{SHARE_PATH} ||= "/export/install/stage2/live/usr/share";
	$ENV{SHARE_PATH} = "/usr/share" if !-e $ENV{SHARE_PATH};
    } else {
	$ENV{SHARE_PATH} ||= "/usr/share";
    }
}

sub init_path() {
    #-  make sure we do not pick up any gunk from the outside world
    my $remote_path = "$::prefix/sbin:$::prefix/bin:$::prefix/usr/sbin:$::prefix/usr/bin";
    $ENV{PATH} = "/usr/bin:/bin:/sbin:/usr/sbin:$remote_path";
}

sub init_mouse() {
    eval { $o->{mouse} = mouse::detect($o->{modules_conf}) } if !$o->{mouse} && !$o->{nomouseprobe};
    mouse::load_modules($o->{mouse});
}

sub init_modules_conf() {
    list_modules::load_default_moddeps();
    require modules::any_conf;
    require modules::modules_conf;
    # read back config from stage1:
    $o->{modules_conf} = modules::modules_conf::read(modules::any_conf::vnew(), '/tmp/modules.conf');
    modules::read_already_loaded($o->{modules_conf});
}

sub process_auto_steps() {
    foreach (@::auto_steps) {
	if (my $s = $o->{steps}{/::(.*)/ ? $1 : $_}) {
	    $s->{auto} = $s->{hidden} = 1;
	} else {
	    log::l("ERROR: unknown step $_ in auto_steps");
	}
    }
}

=item process_patch($cfg, $patch)

Handle installer live patches:

=over 4

=item * OEM patch (C<install/patch-oem.pl>)

=item * defcfg (the file indicated by the defcfg option)

=item * patch (C<patch> file)

=back

=cut

sub process_patch {
    my ($cfg, $patch) = @_;
    #- oem patch should be read before to still allow patch or defcfg.
    eval { $o = $::o = install::any::loadO($o, "install/patch-oem.pl"); log::l("successfully read oem patch") };
    #- patch should be read after defcfg in order to take precedence.
    eval { $o = $::o = install::any::loadO($o, $cfg); log::l("successfully read default configuration: $cfg") } if $cfg;
    eval { $o = $::o = install::any::loadO($o, "patch"); log::l("successfully read patch") } if $patch;
}

#-######################################################################################

=item main()

This is the main function, the installer entry point called by runinstall2:

=over 4

=item * initialization

=item * steps

=back

=cut
#-######################################################################################
sub main {
    $SIG{SEGV} = \&sig_segv_handler;
    $ENV{PERL_BADLANG} = 1;
    delete $ENV{TERMINFO};
    umask 022;

    $::isWizard = 1;
    $::no_ugtk_init = 1;

    push @::textdomains, 'DrakX', 'drakx-net', 'drakx-kbd-mouse-x11';

    my ($cfg, $patch) = parse_args(@_);

    init_env_share();

    undef $::auto_install if $cfg;

    $o->{stage2_phys_medium} = install::media::stage2_phys_medium($o->{method});

    log::l("second stage install running (", install::any::drakx_version($o), ")");

    eval { touch('/root/non-chrooted-marker.DrakX') }; #- helps distinguishing /root and /mnt/root when we don't know if we are chrooted

    if ($::local_install) {
        init_local_install($o);
    } else {
        # load some modules early but asynchronously:
        run_program::raw({ detach => 1 }, 'modprobe', 'microcode');
    }

    $o->{prefix} = $::prefix = $::testing ? "/tmp/test-perl-install" : "/mnt";
    mkdir $::prefix, 0755;

    init_path();

    init_modules_conf();

    #- done before auto_install is called to allow the -IP feature on auto_install file name
    read_stage1_net_conf() if -e '/tmp/network';

    #- done after module dependencies are loaded for "vfat depends on fat"
    if ($::auto_install) {
        init_auto_install();
    } else {
        $o->{interactive} ||= 'gtk';
    }
 
    if ($o->{interactive} eq "gtk" && availableMemory() < 22 * 1024) {
 	log::l("switching to curses install cuz not enough memory");
 	$o->{interactive} = "curses";
    }

    pre_init_brltty();

    #- needed very early for install::steps_gtk
    init_mouse() if !$::testing;

    # perl_checker: require install::steps_gtk
    # perl_checker: require install::steps_curses
    # perl_checker: require install::steps_stdio
    require "install/steps_$o->{interactive}.pm" if $o->{interactive};

    #- needed before accessing floppy (in case of usb floppy)
    modules::load_category($o->{modules_conf}, 'bus/usb'); 

    process_patch($cfg, $patch);

    eval { modules::load("af_packet") };

    require harddrake::sound;
    harddrake::sound::configure_sound_slots($o->{modules_conf});

    #- need to be after oo-izing $o
    init_brltty() if $o->{brltty};

    #- for auto_install compatibility with old $o->{lang},
    #- and also for --lang and --flang
    if ($o->{lang}) {
	put_in_hash($o->{locale}, lang::lang_to_ourlocale($o->{lang}));
    }
    lang::set($o->{locale});

    # keep the result otherwise monitor-edid does not return good results afterwards
    eval { any::monitor_full_edid() };

    $o->{allowFB} = listlength(cat_("/proc/fb"));

    read_product_id() if !$::testing;

    log::l("META_CLASS=$o->{meta_class}");

    process_auto_steps();

    $ENV{COLUMNS} ||= 80;
    $ENV{LINES}   ||= 25;
    $::o = $o = step_init($o);

    eval { output('/proc/splash', "verbose\n") };
  
    real_main();
    finish_install();
}

=item real_main() {

Go through the steps cycle

=cut

sub real_main() {
    MAIN: for ($o->{step} = $o->{steps}{first};; $o->{step} = getNextStep($o)) {
	$o->{steps}{$o->{step}}{entered}++;
	$o->enteringStep($o->{step});
	my $time = time();
	eval {
	    &{$install::install2::{$o->{step}}}($o->{steps}{$o->{step}}{auto});
	};
	my $err = $@;
	log::l("step \"$o->{step}\" took: ", formatTimeRaw(time() - $time));
	$o->kill_action;
	if ($err) {
	    log::l("step \"$o->{step}\" failed with error: $err");
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
}

=item finish_install() {

Clean up the installer before the final reboot.

=cut

sub finish_install() {
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

    #- drop urpmi DB if urpmi is not installed:
    -e "$::prefix/usr/sbin/urpmi" or eval { rm_rf("$::prefix/var/lib/urpmi") };

    system("chroot", $::prefix, "bash", "-c", $o->{postInstallBeforeReboot}) if $o->{postInstallBeforeReboot};

    #- copy latest log files
    eval { cp_af("/tmp/$_", "$::prefix/root/drakx") foreach qw(ddebug.log stage1.log) };

    #- ala pixel? :-) [fpons]
    common::sync(); common::sync();

    log::l("installation complete, leaving");
    log::l("files still open by install2: ", readlink($_)) foreach glob_("/proc/self/fd/*");
    print "\n" x 80 if !$::local_install;
}

=back

=cut

1;
