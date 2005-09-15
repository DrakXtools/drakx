package network::thirdparty;

use strict;
use common;
use detect_devices;
use run_program;
use services;
use fs::get;
use fs;
use log;

#- network_settings is an hash of categories (rtc, dsl, wireless, ...)
#- each category is an hash of device settings

#- a device settings element must have the following fields:
#- o matching:
#-     specify if this settings element matches a driver
#-     can be a regexp, array ref or Perl code (parameters: driver)
#- o description:
#-     full name of the device
#- o name: name used by the packages

#- the following fields are optional:
#- o url:
#-     url where the user can find tools/drivers/firmwares for this device
#- o device:
#-     device in /dev to be configured
#- o post:
#-     command to be run after all packages are installed
#-     can be a shell command or Perl code
#- o restart_service:
#-     if exists but not 1, name of the service to be restarted
#-     if 1, specify that the service named by the name field should be restarted
#- o tools:
#-     hash of the tools settings
#-     test_file field required
#-     if package field doesn't exist, 'name' is used
#- o kernel_module:
#-     if exists but not 1, hash of the module settings
#-     if 1, kernel modules are needed and use the name field
#-         (name-kernel or dkms-name)
#- o firmware:
#-     hash of the firmware settings
#-     test_file field required
#-     if package field doesn't exist, 'name-firmware' is used

#- hash of package settings structure:
#- o package:
#-     name of the package to be installed for these device
#- o test_file:
#-     file used to test if the package is installed
#- o prefix:
#-     path of the files that are tested
#- o links:
#-     useful links for this device
#-     can be a single link or array ref
#- o user_install:
#-     function to call if the package installation fails
#- o explanations:
#-     additionnal text to display if the installation fails
#- o no_club:
#-     1 if the package isn't available on Mandriva club

my $firmware_directory = "/lib/hotplug/firmware";

my %network_settings = (
  rtc =>
  [
   {
    matching => qr/^Hcf:/,
    description => 'HCF 56k Modem',
    url => 'http://www.linuxant.com/drivers/hcf/',
    name => 'hcfpcimodem',
    kernel_module => {
        test_file => 'hcfpciengine',
    },
    tools =>
    {
     test_file => '/usr/sbin/hcfpciconfig',
    },
    device => '/dev/ttySHCF0',
    post => '/usr/sbin/hcfpciconfig --auto',
   },

   {
    matching => qr/^Hsf:/,
    description => 'HSF 56k Modem',
    url => 'http://www.linuxant.com/drivers/hsf/',
    name => 'hsfmodem',
    kernel_module => {
        test_file => 'hsfengine',
    },
    tools =>
    {
     test_file => '/usr/sbin/hsfconfig',
    },
    device => '/dev/ttySHSF0',
    post => '/usr/sbin/hsfconfig --auto',
   },

   {
    matching => qr/^LT:/,
    description => 'LT WinModem',
    url => 'http://www.heby.de/ltmodem/',
    name => 'ltmodem',
    kernel_module => 1,
    tools =>
    {
     test_file => '/etc/devfs/conf.d/ltmodem.conf',
    },
    device => '/dev/ttyS14',
    links =>
    [
     'http://linmodems.technion.ac.il/Ltmodem.html',
     'http://linmodems.technion.ac.il/packages/ltmodem/',
    ],
   },

   {
    matching => [ list_modules::category2modules('network/slmodem') ],
    description => 'Smartlink WinModem',
    url => 'http://www.smlink.com/content.aspx?id=135/',
    name => 'slmodem',
    kernel_module => 1,
    tools =>
    {
     test_file => '/usr/sbin/slmodemd',
    },
    device => '/dev/ttySL0',
    post => sub {
	my ($driver) = @_;
	addVarsInSh("$::prefix/etc/sysconfig/slmodemd", { SLMODEMD_MODULE => $driver });
    },
    restart_service => "slmodemd",
   },

   {
    matching => 'sm56',
    description => 'Motorola SM56 WinModem',
    url => 'http://www.motorola.com/softmodem/driver.htm#linux',
    name => 'sm56',
    kernel_module =>
    {
        package => 'sm56',
    },
    no_club => 1,
    device => '/dev/sm56',
   },
  ],

  wireless =>
  [
   {
    matching => 'zd1201',
    description => 'ZyDAS ZD1201',
    url => 'http://linux-lc100020.sourceforge.net/',
    firmware =>
    {
     test_file => 'zd1201*.fw',
    },
   },

   (map {
       {
           matching => "ipw${_}",
           description => "Intel(R) PRO/Wireless ${_}",
           url => "http://ipw${_}.sourceforge.net/",
	   name => "ipw${_}",
           firmware =>
	   {
               url => "http://ipw${_}.sourceforge.net/firmware.php",
               test_file => ($_ == 2100 ? "ipw2100-*.fw" :  "ipw-2.3-*.fw"),
           },
       };
   } (2100, 2200)),

   {
    matching => 'prism54',
    description => 'Prism GT / Prism Duette / Prism Indigo Chipsets',
    url => 'http://prism54.org/',
    name => 'prism54',
    firmware =>
    {
     url => 'http://prism54.org/~mcgrof/firmware/',
     test_file => "isl38*",
    },
   },

   {
    matching => qr/^at76c50/,
    description => 'Atmel at76c50x cards',
    url => 'http://thekelleys.org.uk/atmel/',
    name => 'atmel',
    firmware =>
    {
     test_file => 'atmel_at76c50*',
    },
    links => 'http://at76c503a.berlios.de/',
   },

   {
    matching => 'ath_pci',
    description => 'Multiband Atheros Driver for WiFi',
    url => 'http://madwifi.sourceforge.net/',
    name => 'madwifi',
    kernel_module => 1,
    tools => {
	test_file => '/usr/bin/athstats',
    },
   },
  ],

  dsl =>
  [
   {
    matching => 'speedtouch',
    description => N_("Alcatel speedtouch USB modem"),
    url => "http://www.speedtouch.com/supuser.htm",
    name => 'speedtouch',
    tools =>
    {
     test_file => '/usr/sbin/modem_run',
    },
    firmware =>
    {
     package => 'speedtouch_mgmt',
     prefix => '/usr/share/speedtouch',
     test_file => 'mgmt*.o',
     explanations => N_("Copy the Alcatel microcode as mgmt.o in /usr/share/speedtouch/"),
     user_install => \&install_speedtouch_microcode,
    },
    links => 'http://linux-usb.sourceforge.net/SpeedTouch/mandrake/index.html',
   },

   {
    matching => 'eciadsl',
    name => 'eciadsl',
    explanations => N_("The ECI Hi-Focus modem cannot be supported due to binary driver distribution problem.

You can find a driver on http://eciadsl.flashtux.org/"),
    no_club => 1,
    tools => {
	test_file => '/usr/sbin/pppoeci',
    },
   },

   {
    matching => 'sagem',
    description => 'Eagle chipset (from Analog Devices), e.g. Sagem F@st 800/840/908',
    url => 'http://www.eagle-usb.org/',
    name => 'eagle-usb',
    tools =>
    {
     test_file => '/sbin/eaglectrl',
    },
   },

   {
    matching => 'bewan',
    description => 'Bewan Adsl (Unicorn)',
    url => 'http://www.bewan.com/bewan/users/downloads/',
    name => 'unicorn',
    kernel_module => {
        test_file => 'unicorn_.*_atm',
    },
    tools => {
	test_file => '/usr/bin/bewan_adsl_status',
    },
   },
  ],
);

sub device_get_package {
    my ($settings, $option, $o_default) = @_;
    $settings->{$option} or return;
    my $package;
    if (ref $settings->{$option} eq 'HASH') {
	$package = $settings->{$option}{package} || 1;
    } else {
	$package = $settings->{$option};
    }
    $package == 1 ? $o_default || $settings->{name} : $package;
}

sub device_get_option {
    my ($settings, $option) = @_;
    $settings->{$option} or return;
    my $value = $settings->{$option};
    $value == 1 ? $settings->{name} : $value;
}

sub find_settings {
    my ($category, $driver) = @_;
    find {
	my $type = ref $_->{matching};
        $type eq 'Regexp' && $driver =~ $_->{matching} ||
	$type eq 'CODE'   && $_->{matching}->($driver) ||
        $type eq 'ARRAY'  && member($driver, @{$_->{matching}}) ||
	$driver eq $_->{matching};
    } @{$network_settings{$category}};
}

sub device_run_command {
    my ($settings, $driver, $option) = @_;
    my $command = $settings->{$option} or return;

    if (ref $command eq 'CODE') {
        $command->($driver);
    } else {
        log::explanations("Running $option command $command");
        run_program::rooted($::prefix, $command);
    }
}

sub warn_not_installed {
    my ($in, @packages) = @_;
    $in->ask_warn(N("Error"), N("Could not install the packages (%s)!", @packages));
}

sub warn_not_found {
    my ($in, $settings, $option, @packages) = @_;
    my %opt;
    $opt{$_} = $settings->{$option}{$_} || $settings->{$_} foreach qw(url explanations no_club);
    $in->ask_warn(N("Error"),
		  N("Some packages (%s) are required but aren't available.", @packages) .
		  (!$opt{no_club} && "\n" . N("These packages can be found in Mandriva Club or in Mandriva commercial releases.")) .
		  ($option eq 'firmware' && "\n\n" . N("Info: ") . "\n" . N("due to missing %s", get_firmware_path($settings))) .
		  ($opt{url} && "\n\n" . N("The required files can also be installed from this URL:
%s", $opt{url})) .
		  ($opt{explanations} && "\n\n" . translate($opt{explanations})));
}

sub is_file_installed {
    my ($settings, $option) = @_;
    my $file = exists $settings->{$option} && $settings->{$option}{test_file};
    $file && -e "$::prefix$file";
}

sub is_module_installed {
    my ($settings, $driver) = @_;
    my $module = ref $settings->{kernel_module} eq 'HASH' && $settings->{kernel_module}{test_file} || $driver;
    find { m!/$module\.k?o! } cat_("$::prefix/lib/modules/" . c::kernel_version() . '/modules.dep');
}

sub get_firmware_path {
    my ($settings) = @_;
    my $wildcard = exists $settings->{firmware} && $settings->{firmware}{test_file} or return;
    my $path = $settings->{firmware}{prefix} || $firmware_directory;
    "$::prefix$path/$wildcard";
}

sub is_firmware_installed {
    my ($settings) = @_;
    my $pattern = get_firmware_path($settings) or return;
    scalar glob_($pattern);
}

sub find_file_on_windows_system {
    my ($in, $file) = @_;
    my $source;
    require fsedit;
    my $all_hds = fsedit::get_hds();
    fs::get_info_from_fstab($all_hds);
    if (my $part = find { $_->{device_windobe} eq 'C' } fs::get::fstab($all_hds)) {
	foreach (qw(windows/system winnt/system windows/system32/drivers winnt/system32/drivers)) {
	    -d $_ and $source = first(glob_("$part->{mntpoint}/$_/$file")) and last;
	}
	$source or $in->ask_warn(N("Error"), N("Unable to find \"%s\" on your Windows system!", $file));
    } else {
	$in->ask_warn(N("Error"), N("No Windows system has been detected!"));
    }
    { file => $source };
}

sub find_file_on_floppy {
    my ($in, $file) = @_;
    my $floppy = detect_devices::floppy();
    my $mountpoint = '/mnt/floppy';
    my $h;
    $in->ask_okcancel(N("Insert floppy"),
		      N("Insert a FAT formatted floppy in drive %s with %s in root directory and press %s", $floppy, $file, N("Next"))) or return;
    if (eval { fs::mount::mount(devices::make($floppy), $mountpoint, 'vfat', 'readonly'); 1 }) {
	log::explanations("Mounting floppy device $floppy in $mountpoint");
	$h = before_leaving { fs::mount::umount($mountpoint) };
	if ($h->{file} = first(glob("$mountpoint/$file"))) {
	    log::explanations("Found $h->{file} on floppy device");
	} else {
	    log::explanations("Unabled to find $file on floppy device");
	}
    } else {
	$in->ask_warn(N("Error"), N("Floppy access error, unable to mount device %s", $floppy));
	log::explanations("Unable to mount floppy device $floppy");
    }
    $h;
}

sub install_speedtouch_microcode {
    my ($in) = @_;
    my $choice;
    $in->ask_from('',
		  N("You need the Alcatel microcode.
You can provide it now via a floppy or your windows partition,
or skip and do it later."),
		  [ { type => "list", val => \$choice, format => \&translate,
		      list => [ N_("Use a floppy"), N_("Use my Windows partition") ] } ]) or return;
    my ($h, $source);
    if ($choice eq N_("Use a floppy")) {
	$source = 'mgmt*.o';
	$h = find_file_on_floppy($in, $source);
    } else {
	$source = 'alcaudsl.sys';
	$h = find_file_on_windows_system($in, $source);
    }
    unless (-e $h->{file} && cp_f($h->{file}, "$::prefix/usr/share/speedtouch/mgmt.o")) {
	$in->ask_warn(N("Error"), N("Firmware copy failed, file %s not found", $source));
	log::explanations("Firmware copy of $source ($h->{file}) failed");
	return;
    }
    log::explanations("Firmware copy of $h->{file} succeeded");
    $in->ask_warn(N("Congratulations!"), N("Firmware copy succeeded"));
    1;
}

sub install_packages {
    my ($in, $settings, $driver, @options) = @_;

    foreach my $option (@options) {
	my %methods =
	  (
	   default =>
	   {
	    find_package_name => sub { device_get_package($settings, $option) },
	    check_installed => sub { is_file_installed($settings, $option) },
	    get_packages => sub { my ($name) = @_; $in->do_pkgs->is_available($name) },
	    user_install => sub { my $f = $settings->{$option}{user_install}; $f && $f->($in) },
	   },
	   kernel_module =>
	   {
	    find_package_name => sub { device_get_package($settings, $option, "$settings->{name}-kernel") },
	    check_installed => sub { is_module_installed($settings, $driver) },
	    get_packages => sub { my ($name) = @_; my $l = $in->do_pkgs->check_kernel_module_packages($name); $l ? @$l : () }
	   },
	   firmware =>
	   {
	    find_package_name => sub { device_get_package($settings, $option, "$settings->{name}-firmware") },
	    check_installed => sub { is_firmware_installed($settings) },
	   },
	  );
	my $get_method = sub { my ($method) = @_; exists $methods{$option} && $methods{$option}{$method} || $methods{default}{$method} };

	my $name = $get_method->('find_package_name')->();
	unless ($name) {
	    log::explanations(qq(No $option package for module "$driver" is required, skipping));
	    next;
	}

	if ($get_method->('check_installed')->()) {
	    log::explanations(qq(Required $option package for module "$driver" is already installed, skipping));
	    next;
	}

	if (my @packages = $get_method->('get_packages')->($name)) {
	    log::explanations("Installing thirdparty packages ($option) " . join(', ', @packages));
	    if (!$in->do_pkgs->install(@packages)) {
		warn_not_installed($in, @packages);
	    } elsif ($get_method->('check_installed')->()) {
		next;
	    }
	}
	log::explanations("Thirdparty package $name ($option) is required but not available");

	unless ($get_method->('user_install')->($in)) {
	    warn_not_found($in, $settings, $option, $name);
	    return;
	}
    }

    1;
}

sub setup_device {
    my ($in, $category, $driver, $o_config, @o_fields) = @_;

    my $settings = find_settings($category, $driver);
    if ($settings) {
	log::explanations(qq(Found settings for driver "$driver" in category "$category"));

	my $wait = $in->wait_message('', N("Looking for required software and drivers..."));

	install_packages($in, $settings, $driver, qw(kernel_module firmware tools)) or return;

        undef $wait;
        $wait = $in->wait_message('', N("Please wait, running device configuration commands..."));
        device_run_command($settings, $driver, 'post');

	if (my $service = device_get_option($settings, 'restart_service')) {
	    log::explanations("Restarting service $service");
	    services::restart_or_start($service);
	}

	log::explanations(qq(Settings for driver "$driver" applied));
    } else {
	log::explanations(qq(No settings found for driver "$driver" in category "$category"));
    }

    #- assign requested settings, erase with undef if no settings have been found
    $o_config->{$_} = $settings->{$_} foreach @o_fields;

    1;
}

1;
