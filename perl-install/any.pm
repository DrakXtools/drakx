package any;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use detect_devices;
use partition_table;
use fs::type;
use lang;
use run_program;
use devices;
use modules;
use log;
use fs;
use c;

sub facesdir() {
	"$::prefix/usr/share/mdk/faces/";
}
sub face2png {
	my ($face) = @_;
	facesdir() . $face . ".png";
}
sub facesnames() {
	my $dir = facesdir();
	my @l = grep { /^[A-Z]/ } all_files_rec($dir);
	map { if_(/$dir\/(.*)\.png/, $1) } (@l ? @l : all_files_rec($dir));
}

sub addKdmIcon {
	my ($user, $icon) = @_;
	my $dest = "$::prefix/usr/share/faces/$user.png";
	eval { cp_af(facesdir() . $icon . ".png", $dest) } if $icon;
}

sub addGdmIcon {
	my ($user, $icon) = @_;
	if ($icon) {
		my $dest = "$::prefix/var/lib/AccountsService/icons/$user";
		eval {
			mkdir_p("$::prefix/var/lib/AccountsService/icons");
			run_program::run('convert', '-resize', '64x64', facesdir() . $icon . ".png", $dest);
			output_p("$::prefix/var/lib/AccountsService/users/$user", "[User]\nXSession=\nIcon=/var/lib/AccountsService/icons/$user");
		};
	}
}

sub addUserFaceIcon {
	my ($user, $icon) = @_;
	my $dest = "$::prefix/home/$user/.face.icon";
	eval { cp_af(facesdir() . $icon . ".png", $dest) } if $icon;
}

sub alloc_user_faces {
	my ($users) = @_;
	my @m = my @l = facesnames();
	foreach (grep { !$_->{icon} || $_->{icon} eq "automagic" } @$users) {
		$_->{auto_icon} = splice(@m, rand(@m), 1); #- known biased (see cookbook for better)
		log::l("auto_icon is $_->{auto_icon}");
		@m = @l unless @m;
	}
}

sub create_user {
	my ($u, $authentication) = @_;

	my @existing = stat("$::prefix/home/$u->{name}");

	if (!getpwnam($u->{name})) {
		my $uid = $u->{uid} || $existing[4];
		if ($uid && getpwuid($uid)) {
			undef $uid; #- suggested uid already in use
		}
		my $gid = $u->{gid} || $existing[5] || int getgrnam($u->{name});
		if ($gid) {
			if (getgrgid($gid)) {
				undef $gid if getgrgid($gid) ne $u->{name};
			} else {
				run_program::rooted($::prefix, 'groupadd', '-g', $gid, $u->{name});
			}
		} elsif ($u->{rename_from}) {
			run_program::rooted($::prefix, 'groupmod', '-n', $u->{name}, $u->{rename_from});
		}

		require authentication;
		my $symlink_home_from = $u->{rename_from} && (getpwnam($u->{rename_from}))[7];
		run_program::raw({ root => $::prefix, sensitive_arguments => 1 },
			($u->{rename_from} ? 'usermod' : 'adduser'), 
			'-p', authentication::user_crypted_passwd($u, $authentication),
			if_($uid, '-u', $uid), if_($gid, '-g', $gid), 
			if_($u->{realname}, '-c', $u->{realname}),
			if_($u->{home}, '-d', $u->{home}, if_($u->{rename_from}, '-m')),
			if_($u->{shell}, '-s', $u->{shell}), 
			($u->{rename_from}
				? ('-l', $u->{name}, $u->{rename_from})
				: $u->{name}));
		symlink($u->{home}, $symlink_home_from) if $symlink_home_from;
		eval { run_program::rooted($::prefix, 'systemctl', 'try-restart', 'accounts-daemon.service') };
	}

	my (undef, undef, $uid, $gid, undef, undef, undef, $home) = getpwnam($u->{name});

	if (@existing && $::isInstall && ($uid != $existing[4] || $gid != $existing[5])) {
		log::l("chown'ing $home from $existing[4].$existing[5] to $uid.$gid");
		eval { common::chown_('recursive', $uid, $gid, "$::prefix$home") };
	}
}

sub add_users {
	my ($users, $authentication) = @_;

	alloc_user_faces($users);

	foreach (@$users) {
		create_user($_, $authentication);
		run_program::rooted($::prefix, "usermod", "-G", join(",", @{$_->{groups}}), $_->{name}) if !is_empty_array_ref($_->{groups});
		my $icon = (delete $_->{auto_icon} || $_->{icon});
		my %desktop = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
		if ($desktop{DESKTOP} eq 'GNOME') {
			addGdmIcon($_->{name}, $icon);
		}
		else {
			addKdmIcon($_->{name}, $icon);
			addUserFaceIcon($_->{name}, $icon);
		}
	}
}

sub install_bootloader_pkgs {
	my ($do_pkgs, $b) = @_;

	bootloader::ensure_pkg_is_installed($do_pkgs, $b);
	install_acpi_pkgs($do_pkgs, $b);
}

sub install_acpi_pkgs {
	my ($do_pkgs, $b) = @_;

	my $acpi = bootloader::get_append_with_key($b, 'acpi');
	my $use_acpi = !member($acpi, 'off', 'ht');
	if ($use_acpi) {
		$do_pkgs->ensure_files_are_installed([ [ qw(acpi acpi) ], [ qw(acpid acpid) ] ], $::isInstall);
	}
	require services;
	services::set_status($_, $use_acpi, $::isInstall) foreach qw(acpi acpid);
}

sub setupBootloaderBeforeStandalone {
	my ($do_pkgs, $b, $all_hds, $fstab) = @_;
	require keyboard;
	my $keyboard = keyboard::read_or_default();
	my $allow_fb = listlength(cat_("/proc/fb"));
	my $cmdline = cat_('/proc/cmdline');
	my $vga_fb = first($cmdline =~ /\bvga=(\S+)/);
	my $splash = $cmdline =~ /\bsplash\b/;
	my $quiet = $cmdline =~ /\bquiet\b/;
	setupBootloaderBefore($do_pkgs, $b, $all_hds, $fstab, $keyboard, $allow_fb, $vga_fb, $splash, $quiet);
}

sub setupBootloaderBefore {
	my ($_do_pkgs, $bootloader, $all_hds, $fstab, $keyboard, $allow_fb, $vga_fb, $splash, $quiet) = @_;
	require bootloader;

	#- auto_install backward compatibility
	#- one should now use {message_text}
	if ($bootloader->{message} =~ m!^[^/]!) {
		$bootloader->{message_text} = delete $bootloader->{message};
	}

	if (cat_("/proc/cmdline") =~ /mem=nopentium/) {
		bootloader::set_append_with_key($bootloader, mem => 'nopentium');
	}
	if (cat_("/proc/cmdline") =~ /\b(pci)=(\S+)/) {
		bootloader::set_append_with_key($bootloader, $1, $2);
	}
	if (my ($acpi) = cat_("/proc/cmdline") =~ /\bacpi=(\w+)/) {
		if ($acpi eq 'ht') {
			#- the user is using the default, which may not be the best
			my $year = detect_devices::computer_info()->{BIOS_Year};
			if ($year >= 2002) {
				log::l("forcing ACPI on recent bios ($year)");
				$acpi = '';
			}
		}
		bootloader::set_append_with_key($bootloader, acpi => $acpi);
	}
	if (cat_("/proc/cmdline") =~ /\bnoapic/) {
		bootloader::set_append_simple($bootloader, 'noapic');
	}
	if (cat_("/proc/cmdline") =~ /\bnoresume/) {
		bootloader::set_append_simple($bootloader, 'noresume');
	} elsif (bootloader::get_append_simple($bootloader, 'noresume')) {
	} else {
		if (my ($biggest_swap) = sort { $b->{size} <=> $a->{size} } grep { isSwap($_) } @$fstab) {
			my $biggest_swap_dev = fs::wild_device::from_part('', $biggest_swap);
			bootloader::set_append_with_key($bootloader, resume => $biggest_swap_dev);
			mkdir_p("$::prefix/etc/dracut.conf.d");
			output("$::prefix/etc/dracut.conf.d/51-local-resume.conf", qq(add_device+="$biggest_swap_dev"\n));
		}
	}

	#- set nokmsboot if a conflicting driver is configured.
	if (-x "$::prefix/sbin/display_driver_helper" && !run_program::rooted($::prefix, "/sbin/display_driver_helper", "--is-kms-allowed")) {
		bootloader::set_append_simple($bootloader, 'nokmsboot');
	}

	#- check for valid fb mode to enable a default boot with frame buffer.
	my $vga = $allow_fb && (!detect_devices::matching_desc__regexp('3D Rage LT') &&
		!detect_devices::matching_desc__regexp('Rage Mobility [PL]') &&
		!detect_devices::matching_desc__regexp('i740') &&
		!detect_devices::matching_desc__regexp('Matrox') &&
		!detect_devices::matching_desc__regexp('Tseng.*ET6\d00') &&
		!detect_devices::matching_desc__regexp('SiS.*SG86C2.5') &&
		!detect_devices::matching_desc__regexp('SiS.*559[78]') &&
		!detect_devices::matching_desc__regexp('SiS.*300') &&
		!detect_devices::matching_desc__regexp('SiS.*540') &&
		!detect_devices::matching_desc__regexp('SiS.*6C?326') &&
		!detect_devices::matching_desc__regexp('SiS.*6C?236') &&
		!detect_devices::matching_desc__regexp('Voodoo [35]|Voodoo Banshee') && #- 3d acceleration seems to bug in fb mode
		!detect_devices::matching_desc__regexp('828[14][05].* CGC') #- i810 & i845 now have FB support during install but we disable it afterwards
	);
	my $force_vga = $allow_fb && (detect_devices::matching_desc__regexp('SiS.*630') || #- SiS 630 need frame buffer.
		detect_devices::matching_desc__regexp('GeForce.*Integrated') #- needed for fbdev driver (hack).
	);

	#- propose the default fb mode for kernel fb, if bootsplash is installed.
	my $need_fb = -e "$::prefix/usr/share/bootsplash/scripts/make-boot-splash";
	bootloader::suggest($bootloader, $all_hds,
		vga_fb => ($force_vga || $vga && $need_fb) && $vga_fb,
		splash => $splash,
		quiet => $quiet);

	$bootloader->{keytable} ||= keyboard::keyboard2kmap($keyboard);
	log::l("setupBootloaderBefore end");
}

sub setupBootloader {
	my ($in, $b, $all_hds, $fstab, $security) = @_;

	require bootloader;
	general:
	{
		local $::Wizard_no_previous = 1 if $::isStandalone;
		setupBootloader__general($in, $b, $all_hds, $fstab, $security) or return 0;
	}
	setupBootloader__boot_bios_drive($in, $b, $all_hds->{hds}) or goto general;
	{
		local $::Wizard_finished = 1 if $::isStandalone;
		setupBootloader__entries($in, $b, $all_hds, $fstab) or goto general;
	}
	1;
}

sub setupBootloaderUntilInstalled {
	my ($in, $b, $all_hds, $fstab, $security) = @_;
	do {
		my $before = fs::fstab_to_string($all_hds);
		setupBootloader($in, $b, $all_hds, $fstab, $security) or $in->exit;
		if ($before ne fs::fstab_to_string($all_hds)) {
			#- ovitters: This fstab comparison was needed for optionally
			#- setting up /tmp using tmpfs. That code was removed. Not removing
			#- this code as I'm not sure if something still relies on this
			fs::write_fstab($all_hds);
		}
	} while !installBootloader($in, $b, $all_hds);
}

sub installBootloader {
	my ($in, $b, $all_hds) = @_;
	return if detect_devices::is_xbox();

	return 1 if arch() =~ /mips|arm/;

	install_bootloader_pkgs($in->do_pkgs, $b);

	eval { run_program::rooted($::prefix, 'echo | lilo -u') } if $::isInstall && !$::o->{isUpgrade} && -e "$::prefix/etc/lilo.conf" && glob("$::prefix/boot/boot.*");

	retry:
	eval { 
		my $_w = $in->wait_message(N("Please wait"), N("Bootloader installation in progress"));
		bootloader::install($b, $all_hds);
	};

	if (my $err = $@) {
		$err =~ /wizcancel/ and return;
		$err =~ s/^\w+ failed// or die;
		$err = formatError($err);
		while ($err =~ s/^Warning:.*//m) {}
		if (my ($dev) = $err =~ /^Reference:\s+disk\s+"(.*?)".*^Is the above disk an NT boot disk?/ms) {
			if ($in->ask_yesorno('',
					formatAlaTeX(N("LILO wants to assign a new Volume ID to drive %s.  However, changing
							the Volume ID of a Windows NT, 2000, or XP boot disk is a fatal Windows error.
							This caution does not apply to Windows 95 or 98, or to NT data disks.

							Assign a new Volume ID?", $dev)))) {
				$b->{force_lilo_answer} = 'n';
			} else {
				$b->{'static-bios-codes'} = 1;
			}
			goto retry;
		} else {
			$in->ask_warn('', [ N("Installation of bootloader failed. The following error occurred:"), $err ]);
			return;
		}
	}
	1;
}


sub setupBootloader_simple {
	my ($in, $b, $all_hds, $fstab, $security) = @_;
	my $hds = $all_hds->{hds};

	require bootloader;
	bootloader::ensafe_first_bios_drive($hds)
	|| $b->{bootUnsafe} or return 1; #- default is good enough

	if (arch() !~ /ia64/) {
		setupBootloader__mbr_or_not($in, $b, $hds, $fstab) or return 0;
	} else {
		general:
		setupBootloader__general($in, $b, $all_hds, $fstab, $security) or return 0;
	}
	setupBootloader__boot_bios_drive($in, $b, $hds) or goto general;
	1;
}


sub setupBootloader__boot_bios_drive {
	my ($in, $b, $hds) = @_;

	if (!is_empty_hash_ref($b->{bios})) {
		#- some bios mapping already there
		return 1;
	} elsif (bootloader::mixed_kind_of_disks($hds) && $b->{boot} =~ /\d$/) { #- on a partition
		# see below
	} else {
		return 1;
	}

	log::l("_ask_boot_bios_drive");
	my $hd = $in->ask_from_listf('', N("You decided to install the bootloader on a partition.
			This implies you already have a bootloader on the hard disk drive you boot (eg: System Commander).

			On which drive are you booting?"), \&partition_table::description, $hds) or return 0;
	log::l("mixed_kind_of_disks chosen $hd->{device}");
	$b->{first_hd_device} = "/dev/$hd->{device}";
	1;
}

sub _ask_mbr_or_not {
	my ($in, $default, @l) = @_;
	$in->ask_from_({ title => N("Bootloader Installation"),
			interactive_help_id => 'setupBootloaderBeginner',
		},
		[
			{ label => N("Where do you want to install the bootloader?"), title => 1 },
			{ val => \$default, list => \@l, format => sub { $_[0][0] }, type => 'list' },
		]
	);
	$default;
}

sub setupBootloader__mbr_or_not {
	my ($in, $b, $hds, $fstab) = @_;

	log::l("setupBootloader__mbr_or_not");

	my $floppy = detect_devices::floppy();

	my @l = (
		bootloader::ensafe_first_bios_drive($hds) ?
		(map { [ N("First sector (MBR) of drive %s", partition_table::description($_)) => '/dev/' . $_->{device} ] } @$hds)
		:
		[ N("First sector of drive (MBR)") => '/dev/' . $hds->[0]{device} ],

		[ N("First sector of the root partition") => '/dev/' . fs::get::root($fstab, 'boot')->{device} ],
		if_($floppy, 
			[ N("On Floppy") => "/dev/$floppy" ],
		),
		[ N("Skip") => '' ],
	);

	my $default = find { $_->[1] eq $b->{boot} } @l;
	if (!$::isInstall) {
		$default = _ask_mbr_or_not($in, $default, @l);
	}
	my $new_boot = $default->[1];

	#- remove bios mapping if the user changed the boot device
	delete $b->{bios} if $new_boot && $new_boot ne $b->{boot};
	$b->{boot} = $new_boot or return;
	1;
}

sub setupBootloader__general {
    my ($in, $b, $all_hds, $_fstab, $_security) = @_;

    return if detect_devices::is_xbox();
    my @method_choices = bootloader::method_choices($all_hds);
    my $prev_force_acpi = my $force_acpi = bootloader::get_append_with_key($b, 'acpi') !~ /off|ht/;
    my $prev_enable_apic = my $enable_apic = !bootloader::get_append_simple($b, 'noapic');
    my $prev_enable_lapic = my $enable_lapic = !bootloader::get_append_simple($b, 'nolapic');
    my $prev_enable_smp = my $enable_smp = !bootloader::get_append_simple($b, 'nosmp');
    my $prev_boot = $b->{boot};
    my $prev_method = $b->{method};

    $b->{password2} ||= $b->{password} ||= '';
    $::Wizard_title = N("Boot Style Configuration");
	my (@boot_devices, %boot_devices);
	foreach (bootloader::allowed_boot_parts($b, $all_hds)) {
		my $dev = "/dev/$_->{device}";
		push @boot_devices, $dev;
		my $name = $_->{mntpoint} || $_->{info} || $_->{device_LABEL};
		unless ($name) {
			$name = formatXiB($_->{size}*512) . " " if $_->{size};
			$name .= $_->{fs_type};
		}
		$boot_devices{$dev} = $name ? "$dev ($name)" : $dev;
	}

	$in->ask_from_({ #messages => N("Bootloader main options"),
			title => N("Bootloader main options"),
			interactive_help_id => 'setupBootloader',
		}, [
			#title => N("Bootloader main options"),
			{ label => N("Bootloader"), title => 1 },
			{ label => N("Bootloader to use"), val => \$b->{method},
				list => \@method_choices, format => \&bootloader::method2text },
			if_(arch() !~ /ia64/,
				{ label => N("Boot device"), val => \$b->{boot}, list => \@boot_devices,
					format => sub { $boot_devices{$_[0]} } },
			),
			{ label => N("Main options"), title => 1 },
			{ label => N("Delay before booting default image"), val => \$b->{timeout} },
			{ text => N("Enable ACPI"), val => \$force_acpi, type => 'bool', advanced => 1 },
			{ text => N("Enable SMP"), val => \$enable_smp, type => 'bool', advanced => 1 },
			{ text => N("Enable APIC"), val => \$enable_apic, type => 'bool', advanced => 1,
				disabled => sub { !$enable_lapic } }, 
			{ text => N("Enable Local APIC"), val => \$enable_lapic, type => 'bool', advanced => 1 },
			{ label => N("Security"), title => 1 },
			{ label => N("Password"), val => \$b->{password}, hidden => 1,
				validate => sub { 
					my $ok = $b->{password} eq $b->{password2}
						or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]);
					my $ok2 = !($b->{password} && $b->{method} eq 'grub-graphic')
						or $in->ask_warn('', N("You cannot use a password with %s",
							bootloader::method2text($b->{method})));
					$ok && $ok2;
				} },
			{ label => N("Password (again)"), val => \$b->{password2}, hidden => 1 },
		]) or return 0;

	#- remove bios mapping if the user changed the boot device
	delete $b->{bios} if $b->{boot} ne $prev_boot;

	if ($b->{boot} =~ m!/dev/md\d+$!) {
		$b->{'raid-extra-boot'} = 'mbr';
	} else {
		delete $b->{'raid-extra-boot'} if $b->{'raid-extra-boot'} eq 'mbr';
	}

	bootloader::ensure_pkg_is_installed($in->do_pkgs, $b) or goto &setupBootloader__general;

	bootloader::suggest_message_text($b) if ! -e "$::prefix/boot/message-text"; #- in case we switch from grub to lilo

	if ($prev_force_acpi != $force_acpi) {
		bootloader::set_append_with_key($b, acpi => ($force_acpi ? '' : 'ht'));
	}

	if ($prev_enable_smp != $enable_smp) {
		($enable_smp ? \&bootloader::remove_append_simple : \&bootloader::set_append_simple)->($b, 'nosmp');
	}

	if ($prev_enable_apic != $enable_apic) {
		($enable_apic ? \&bootloader::remove_append_simple : \&bootloader::set_append_simple)->($b, 'noapic');
		($enable_apic ? \&bootloader::set_append_simple : \&bootloader::remove_append_simple)->($b, 'apic');
	}
	if ($prev_enable_lapic != $enable_lapic) {
		($enable_lapic ? \&bootloader::remove_append_simple : \&bootloader::set_append_simple)->($b, 'nolapic');
		($enable_lapic ? \&bootloader::set_append_simple : \&bootloader::remove_append_simple)->($b, 'lapic');
	}

	if (bootloader::main_method($prev_method) eq 'lilo' && 
		bootloader::main_method($b->{method}) eq 'grub') {
		log::l("switching for lilo to grub, ensure we don't read lilo.conf anymore");
		renamef("$::prefix/etc/lilo.conf", "$::prefix/etc/lilo.conf.unused");
	}
	1;
}

sub setupBootloader__entries {
	my ($in, $b, $all_hds, $fstab) = @_;

	require Xconfig::resolution_and_depth;

	my $Modify = sub {
		require network::network; #- to list network profiles
		my ($e) = @_;
		my $default = my $old_default = $e->{label} eq $b->{default};
		my $vga = Xconfig::resolution_and_depth::from_bios($e->{vga});
		my ($append, $netprofile) = bootloader::get_append_netprofile($e);

		my %hd_infos = map { $_->{device} => $_->{info} } fs::get::hds($all_hds);
		my %root_descr = map { 
		my $info = delete $hd_infos{$_->{rootDevice}};
		my $dev = "/dev/$_->{device}";
		my $hint = $info || $_->{info} || $_->{device_LABEL};
		my $info_ = $hint ? "$dev ($hint)" : $dev;
		($dev => $info_, fs::wild_device::from_part('', $_) => $info_);
		} @$fstab;

		my @l;
		if ($e->{type} eq "image") { 
			@l = (
				{ label => N("Image"), val => \$e->{kernel_or_dev}, list => [ map { "/boot/$_" } bootloader::installed_vmlinuz() ], not_edit => 0 },
				{ label => N("Root"), val => \$e->{root}, list => [ map { fs::wild_device::from_part('', $_) } @$fstab ], format => sub { $root_descr{$_[0]} }  },
				{ label => N("Append"), val => \$append },
				if_($e->{xen}, 
					{ label => N("Xen append"), val => \$e->{xen_append} }
				),
  if_($b->{password}, { label => N("Requires password to boot"), val => \$e->{lock}, type => "bool" }),
{ label => N("Video mode"), val => \$vga, list => [ '', Xconfig::resolution_and_depth::bios_vga_modes() ], format => \&Xconfig::resolution_and_depth::to_string, advanced => 1 },
{ label => N("Initrd"), val => \$e->{initrd}, list => [ map { if_(/^initrd/, "/boot/$_") } all("$::prefix/boot") ], not_edit => 0, advanced => 1 },
{ label => N("Network profile"), val => \$netprofile, list => [ sort(uniq('', $netprofile, network::network::netprofile_list())) ], advanced => 1 },
	    );
	} else {
	    @l = ( 
{ label => N("Root"), val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab, detect_devices::floppies() ] },
	    );
	}
	    @l = (
		  { label => N("Label"), val => \$e->{label} },
		  @l,
		  { text => N("Default"), val => \$default, type => 'bool' },
		 );

	$in->ask_from_(
	    {
	     interactive_help_id => 'setupBootloaderAddEntry',
	     callbacks => {
	       complete => sub {
		   $e->{label} or $in->ask_warn('', N("Empty label not allowed")), return 1;
		   $e->{kernel_or_dev} or $in->ask_warn('', $e->{type} eq 'image' ? N("You must specify a kernel image") : N("You must specify a root partition")), return 1;
		   member(lc $e->{label}, map { lc $_->{label} } grep { $_ != $e } @{$b->{entries}}) and $in->ask_warn('', N("This label is already used")), return 1;
		   0;
	       } } }, \@l) or return;

	$b->{default} = $old_default || $default ? $default && $e->{label} : $b->{default};
	my $new_vga = ref($vga) ? $vga->{bios} : $vga;
	if ($new_vga ne $e->{vga}) {
	    $e->{vga} = $new_vga;
	    $e->{initrd} and bootloader::add_boot_splash($e->{initrd}, $e->{vga});
	}
	bootloader::set_append_netprofile($e, $append, $netprofile);
	bootloader::configure_entry($b, $e); #- hack to make sure initrd file are built.
	1;
    };

    my $Add = sub {
	my @labels = map { $_->{label} } @{$b->{entries}};
	my ($e, $prefix);
	if ($in->ask_from_list_('', N("Which type of entry do you want to add?"),
				[ N_("Linux"), N_("Other OS (Windows...)") ]
			       ) eq "Linux") {
	    $e = { type => 'image',
		   root => '/dev/' . fs::get::root($fstab)->{device}, #- assume a good default.
		 };
	    $prefix = "linux";
	} else {
	    $e = { type => 'other' };
	    $prefix = "windows";
	}
	$e->{label} = $prefix;
	for (my $nb = 0; member($e->{label}, @labels); $nb++) {
	    $e->{label} = "$prefix-$nb";
	}
	$Modify->($e) or return;
	bootloader::add_entry($b, $e);
	$e;
    };

    my $Remove = sub {
	my ($e) = @_;
	delete $b->{default} if $b->{default} eq $e->{label};
	@{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	1;
    };

    my $Up = sub {
	my ($e) = @_;
	my @entries = @{$b->{entries}};
	my ($index) = grep { $entries[$_]{label} eq $e->{label} } 0..$#entries;
	if ($index > 0) {
	  ($b->{entries}->[$index - 1], $b->{entries}->[$index]) = ($b->{entries}->[$index], $b->{entries}->[$index - 1]);
	}
	1;
    };
    
    my $Down = sub {
	my ($e) = @_;
	my @entries = @{$b->{entries}};
	my ($index) = grep { $entries[$_]{label} eq $e->{label} } 0..$#entries;
	if ($index < $#entries) {
	  ($b->{entries}->[$index + 1], $b->{entries}->[$index]) = ($b->{entries}->[$index], $b->{entries}->[$index + 1]);
	}
	1;
    };

    my @prev_entries = @{$b->{entries}};
    if ($in->ask_from__add_modify_remove(N("Bootloader Configuration"),
N("Here are the entries on your boot menu so far.
You can create additional entries or change the existing ones."), [ { 
        format => sub {
	    my ($e) = @_;
	    ref($e) ? 
	      ($b->{default} eq $e->{label} ? "  *  " : "     ") . "$e->{label} ($e->{kernel_or_dev})" : 
		translate($e);
	}, list => $b->{entries},
    } ], Add => $Add, Modify => $Modify, Remove => $Remove, Up => $Up, Down => $Down)) {
	1;
    } else {
	@{$b->{entries}} = @prev_entries;
	'';
    }
}

sub setupBootloader__grub2 {
    my ($in, $b, $_all_hds, $_fstab) = @_;

    # update entries (so that we can display their list below):
    my $error;
    run_program::rooted($::prefix, 'update-grub2', '2>', \$error) or die "update-grub2 failed: $error";

    # read grub2 auto-generated entries (instead of keeping eg: grub/lilo ones):
    my $b2 = bootloader::read_grub2();

    # get default parameters:
    my $append = $b->{entries}[0]{append} ||= bootloader::get_grub2_append($b2);
    my $default = $b2->{default};

    require Xconfig::resolution_and_depth;

    require network::network; #- to list network profiles
    my $vga = Xconfig::resolution_and_depth::from_bios($b->{vga});

    my $res = $in->ask_from_(
	{
	    title => N("Bootloader Configuration"),
	},
	[
	 { label => N("Default"), val => \$default,
	   list => [ map { $_->{label} } @{$b2->{entries}} ] },
	 { label => N("Append"), val => \$append },
	 { label => N("Video mode"), val => \$vga, list => [ '', Xconfig::resolution_and_depth::bios_vga_modes() ],
	   format => \&Xconfig::resolution_and_depth::to_string, advanced => 1 },
	]);
    if ($res) {
	$b->{entries} = $b2->{entries};
	$b->{default} = $default;
	$b->{vga} = ref($vga) ? $vga->{bios} : $vga;
	first(@{$b->{entries}})->{append} = $append;
	1;
    } else {
	'';
    }
}

sub get_autologin() {
    my %desktop = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
    my $gdm_file = "$::prefix/etc/X11/gdm/custom.conf";
    my $kdm_file = common::read_alternative('kdm4-config');
    my $sddm_file = "$::prefix/etc/sddm.conf";
    my $lightdm_conffile = "$::prefix/etc/lightdm/lightdm.conf.d/50-openmandriva-autologin.conf";
    my $autologin_file = "$::prefix/etc/sysconfig/autologin";
    my $desktop = $desktop{DESKTOP} || first(sessions());
    my %desktop_to_dm = (
        GNOME => 'gdm',
        KDE4 => 'kdm',
        xfce4 => 'slim',
        LXDE => 'lxdm',
        LXQt => 'sddm',
        MATE => 'lightdm',
    );
    my %dm_canonical = (
        gnome => 'gdm',
        kde => 'kdm',
        lxqt => 'sddm',
    );
    my $dm =
      lc($desktop{DISPLAYMANAGER}) ||
      $desktop_to_dm{$desktop} ||
      basename(chomp_(run_program::rooted_get_stdout($::prefix, "/etc/X11/lookupdm")));
    $dm = $dm_canonical{$dm} if exists $dm_canonical{$dm};

    my $autologin_user;
    if ($dm eq "gdm") {
        my %conf = read_gnomekderc($gdm_file, 'daemon');
        $autologin_user = text2bool($conf{AutomaticLoginEnable}) && $conf{AutomaticLogin};
    } elsif ($dm eq "kdm") {
        my %conf = read_gnomekderc($kdm_file, 'X-:0-Core');
        $autologin_user = text2bool($conf{AutoLoginEnable}) && $conf{AutoLoginUser};
    } elsif ($dm eq "sddm") {
        my %conf = read_gnomekderc($sddm_file, 'Autologin');
        $autologin_user = $conf{User} && $conf{Session};
    } elsif ($dm eq "lightdm") {
        my %conf = read_gnomekderc($lightdm_conffile, 'Seat:*');
        $autologin_user = text2bool($conf{'#dummy-autologin'}) && $conf{"autologin-user"};
    } else {
        my %conf = getVarsFromSh($autologin_file);
        $autologin_user = text2bool($conf{AUTOLOGIN}) && $conf{USER};
    }

    { user => $autologin_user, desktop => $desktop, dm => $dm };
}

sub is_standalone_autologin_needed {
    my ($dm) = @_;
    return member($dm, qw(lxdm slim xdm));
}

sub set_autologin {
    my ($do_pkgs, $autologin, $o_auto) = @_;
    log::l("set_autologin $autologin->{user} $autologin->{desktop}");
    my $do_autologin = bool2text($autologin->{user});

    $autologin->{dm} ||= 'xdm';
    $do_pkgs->ensure_is_installed($autologin->{dm}, undef, $o_auto)
      or return;
    if ($autologin->{user} && is_standalone_autologin_needed($autologin->{dm})) {
        $do_pkgs->ensure_is_installed('autologin', '/usr/bin/startx.autologin', $o_auto)
          or return;
    }

    #- Configure KDM / MDKKDM
    my $kdm_conffile = common::read_alternative('kdm4-config');
    eval { common::update_gnomekderc_no_create($kdm_conffile, 'X-:0-Core' => (
	AutoLoginEnable => $do_autologin,
	AutoLoginUser => $autologin->{user},
    )) } if -e $kdm_conffile;

    #- Configure SDDM
    my $sddm_conffile = "$::prefix/etc/sddm.conf";
    eval { common::update_gnomekderc_no_create($sddm_conffile, 'Autologin' => (
	Session => $autologin->{desktop},
	User => $autologin->{user},
    )) } if -e $sddm_conffile;

    #- Configure GDM
    my $gdm_conffile = "$::prefix/etc/X11/gdm/custom.conf";
    eval { update_gnomekderc($gdm_conffile, daemon => (
	AutomaticLoginEnable => $do_autologin,
	AutomaticLogin => $autologin->{user},
    )) } if -e $gdm_conffile;
    
    #- Configure LIGHTDM
    my $lightdm_conffile = "$::prefix/etc/lightdm/lightdm.conf.d/50-openmandriva-autologin.conf";
    eval { update_gnomekderc($lightdm_conffile, 'Seat:*' => (
    '#dummy-autologin' => $do_autologin,
    'autologin-user' => $autologin->{user}
    )) } if -e $lightdm_conffile;

    my $xdm_autologin_cfg = "$::prefix/etc/sysconfig/autologin";
    # TODO: configure lxdm in /etx/lxdm/lxdm.conf
    if (is_standalone_autologin_needed($autologin->{dm})) {
	setVarsInShMode($xdm_autologin_cfg, 0644,
			{ USER => $autologin->{user}, AUTOLOGIN => bool2yesno($autologin->{user}), EXEC => '/usr/bin/startx.autologin' });
    } else {
	unlink $xdm_autologin_cfg;
    }

    my $sys_conffile = "$::prefix/etc/sysconfig/desktop";
    my %desktop = getVarsFromSh($sys_conffile);
    $desktop{DESKTOP} = $autologin->{desktop};
    $desktop{DISPLAYMANAGER} = $autologin->{dm};
    setVarsInSh($sys_conffile, \%desktop);

    if ($autologin->{user}) {
	my $home = (getpwnam($autologin->{user}))[7];
	set_window_manager($home, $autologin->{desktop});
    }
}
sub set_window_manager {
    my ($home, $wm) = @_;
    log::l("set_window_manager $home $wm");
    my $p_home = "$::prefix$home";

    #- for KDM/GDM
    my $wm_number = sessions_with_order()->{$wm} || '';
    update_gnomekderc("$p_home/.dmrc", 'Desktop', Session => "$wm_number$wm");
    my $user = find { $home eq $_->[7] } list_passwd();
    chown($user->[2], $user->[3], "$p_home/.dmrc");
    chmod(0644, "$p_home/.dmrc");

    #- for startx/autologin
    {
	my %l = getVarsFromSh("$p_home/.desktop");
	$l{DESKTOP} = $wm;
	setVarsInSh("$p_home/.desktop", \%l);
    }
}

sub rotate_log {
    my ($f) = @_;
    if (-e $f) {
	my $i = 1;
	for (; -e "$f$i" || -e "$f$i.gz"; $i++) {}
	rename $f, "$f$i";
    }
}
sub rotate_logs {
    my ($prefix) = @_;
    rotate_log("$prefix/root/drakx/$_") foreach qw(stage1.log ddebug.log install.log updates.log);
}

sub writeandclean_ldsoconf {
    my ($prefix) = @_;
    my $file = "$prefix/etc/ld.so.conf";
    my @l = chomp_(cat_($file));

    my @default = ('/lib', '/usr/lib'); #- no need to have /lib and /usr/lib in ld.so.conf
    my @suggest = ('/usr/lib/qt3/lib'); #- needed for upgrade where package renaming can cause this to disappear

    if (arch() =~ /x86_64/) {
	@default = map { $_, $_ . '64' } @default;
	@suggest = map { $_, $_ . '64' } @suggest;
    }
    push @l, grep { -d "$::prefix$_" } @suggest;
    @l = difference2(\@l, \@default);

    log::l("writeandclean_ldsoconf");
    output($file, map { "$_\n" } uniq(@l));
}

sub shells() {
    grep { -x "$::prefix$_" } chomp_(cat_("$::prefix/etc/shells"));
}

sub inspect {
    my ($part, $o_prefix, $b_rw) = @_;

    isMountableRW($part) || !$b_rw && isOtherAvailableFS($part) or return;

    my $dir = $::isInstall ? "/tmp/inspect_tmp_dir" : "/root/.inspect_tmp_dir";

    if ($part->{isMounted}) {
	$dir = ($o_prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	eval { fs::mount::mount(fs::wild_device::from_part('', $part), $dir, $part->{fs_type}, !$b_rw) };
	$@ and return;
    }
    my $h = before_leaving {
	if (!$part->{isMounted} && $dir) {
	    fs::mount::umount($dir);
	    unlink($dir);
	}
    };
    $h->{dir} = $dir;
    $h;
}

sub ask_user {
    my ($in, $users, $security, %options) = @_;

    ask_user_and_root($in, undef, $users, $security, %options);
}

sub is_xguest_installed() {
    -e "$::prefix/etc/security/namespace.d/xguest.conf";
}

sub ask_user_and_root {
    my ($in, $superuser, $users, $security, %options) = @_;

    my $xguest = is_xguest_installed();

    $options{needauser} ||= $security >= 3;

    my @icons = facesnames();
    my @suggested_names = $::isInstall ? do {
	my @l = grep { !/^\./ && $_ ne 'lost+found' && -d "$::prefix/home/$_" } all("$::prefix/home");
	grep { ! defined getpwnam($_) } @l;
    } : ();

    my %high_security_groups = (
        xgrp => N("access to X programs"),
	rpm => N("access to rpm tools"),
	wheel => N("allow \"su\""),
	adm => N("access to administrative files"),
	ntools => N("access to network tools"),
	ctools => N("access to compilation tools"),
    );

    my $u = {};
    $u->{password2} ||= $u->{password} ||= '';
    $u->{shell} ||= '/bin/bash';
    my $names = @$users ? N("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @$users)) : '';
    
    my %groups;

    require authentication;
    my $validate_name = sub {
	$u->{name} or $in->ask_warn('', N("Please give a user name")), return;
        $u->{name} =~ /^[a-z]+[a-z0-9_-]*$/ or $in->ask_warn('', N("The user name must start with a lower case letter followed by only lower cased letters, numbers, `-' and `_'")), return;
        length($u->{name}) <= 32 or $in->ask_warn('', N("The user name is too long")), return;
        defined getpwnam($u->{name}) || member($u->{name}, map { $_->{name} } @$users) and $in->ask_warn('', N("This user name has already been added")), return;
	'ok';
    };
    my $validate_uid_gid = sub {
	my ($field) = @_;
	my $id = $u->{$field} or return 'ok';
	my $name = $field eq 'uid' ? N("User ID") : N("Group ID");
	$id =~ /^\d+$/ or $in->ask_warn('', N("%s must be a number", $name)), return;
	$id >= 1000 or $in->ask_yesorno('', N("%s should be above 1000. Accept anyway?", $name)) or return;
	'ok';
    };
    
    my $rootret = 0;
    if ($superuser) {
    $rootret = $in->ask_from_(
        { title => N("User management"),
          interactive_help_id => 'addUser',
	  if_($::isInstall && $superuser, cancel => ''),
        }, [ 
	      $superuser ? (
	  if_(0,
	  { text => N("Enable guest account"), val => \$xguest, type => 'bool', advanced => 1 },
	  ),
	  { label => N("Set administrator (root) password"), title => 1 },
	  { label => N("Password"), val => \$superuser->{password},  hidden => 1, alignment => 'right', weakness_check => 1,
	    focus => sub { 1 },
	    validate => sub { authentication::check_given_password($in, $superuser, 2 * $security) } },
	  { label => N("Password (again)"), val => \$superuser->{password2}, hidden => 1, alignment => 'right' },
              ) : (),
	  ],
      );
      } else {
        $rootret = 1;
      }
      
    my $userret = 0;
    
    if ($rootret){
    
    $userret = $in->ask_from_(
        { title => N("User management"),
          interactive_help_id => 'addUser',
	  if_($::isInstall && $superuser, cancel => ''),
        }, [ 
	  { label => N("Enter a user"), title => 1 }, if_($names, { label => $names }),
           if_($security <= 3 && !$options{noicons} && @icons,
	  { label => N("Icon"), val => \ ($u->{icon} ||= 'default'), list => \@icons, icon2f => \&face2png,
            alignment => 'right', format => \&translate },
           ),
	  { label => N("Real name"), val => \$u->{realname}, alignment => 'right', focus_out => sub {
		$u->{name} ||= lc(Locale::gettext::iconv($u->{realname}, "utf-8", "ascii//TRANSLIT"));
                $u->{name} =~ s/[^a-zA-Z0-9_-]//g; # drop any character that would break login program
	    },
	    focus => sub { !$superuser },
          },

          { label => N("Login name"), val => \$u->{name}, list => \@suggested_names, alignment => 'right',
            not_edit => 0, validate => $validate_name },
          { label => N("Password"),val => \$u->{password}, hidden => 1, alignment => 'right', weakness_check => 1,
	    validate => sub { authentication::check_given_password($in, $u, $security > 3 ? 6 : 0) } },
          { label => N("Password (again)"), val => \$u->{password2}, hidden => 1, alignment => 'right' },
          { label => N("Shell"), val => \$u->{shell}, list => [ shells() ], advanced => 1 },
	  { label => N("User ID"), val => \$u->{uid}, advanced => 1, validate => sub { $validate_uid_gid->('uid') } },
	  { label => N("Group ID"), val => \$u->{gid}, advanced => 1, validate => sub { $validate_uid_gid->('gid') } },
	    if_($security > 3,
                map {
                    { label => $_, val => \$groups{$_}, text => $high_security_groups{$_}, type => 'bool' };
                } keys %high_security_groups,
               ),
	  ],
    );
    }

    if ($xguest && !is_xguest_installed()) {
        $in->do_pkgs->ensure_is_installed('xguest', '/etc/security/namespace.d/xguest.conf');
    } elsif (!$xguest && is_xguest_installed()) {
        $in->do_pkgs->remove('xguest') or return;
    }

    $u->{groups} = [ grep { $groups{$_} } keys %groups ];

    push @$users, $u if $u->{name};

    $rootret && $userret && $u;
}

sub sessions() {
    split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-l'));
}
sub sessions_with_order() {
    my %h = map { /(.*)=(.*)/ } split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-L'));
    \%h;
}

sub urpmi_add_all_media {
    my ($in, $o_previous_release) = @_;

    my $binary = find { whereis_binary($_, $::prefix) } if_(check_for_xserver(), 'gurpmi.addmedia'), 'urpmi.addmedia';
    if (!$binary) {
	log::l("urpmi.addmedia not found!");
	return;
    }
    
    #- configure urpmi media if network is up
    require network::tools;
    if (!network::tools::has_network_connection()) {
	log::l("no network connexion!");
	return;
    }
    my $wait;
    my @options = ('--distrib', '--mirrorlist', '$MIRRORLIST');
    if ($binary eq 'urpmi.addmedia') {
	$wait = $in->wait_message(N("Please wait"), N("Please wait, adding media..."));
    } elsif ($in->isa('interactive::gtk')) {
	push @options, '--silent-success';
	mygtk3::flush();
    }

    my $reason = join(',', $o_previous_release ? 
      ('reason=upgrade', 'upgrade_by=drakx', "upgrade_from=$o_previous_release->{version}") :
       'reason=install');
    log::l("URPMI_ADDMEDIA_REASON $reason");
    local $ENV{URPMI_ADDMEDIA_REASON} = $reason;

    my $log_file = '/root/drakx/updates.log';
    my $val = run_program::rooted($::prefix, $binary, '>>', $log_file, '2>>', $log_file, @options);

    undef $wait;
    $val;
}

sub autologin {
    my ($o, $in) = @_;

    my @wm = sessions();
    my @users = map { $_->{name} } @{$o->{users} || []};

    my $kde_desktop = find { member($_, 'KDE', 'KDE4') } @wm;
    if ($kde_desktop && @users == 1 && $o->{meta_class} eq 'desktop') {
	$o->{desktop} = $kde_desktop;
	$o->{autologin} = $users[0];
    } elsif (@wm > 1 && @users && !$o->{authentication}{NIS} && $o->{security} <= 2) {
	my $use_autologin = @users == 1;

	$in->ask_from_(
		       { title => N("Autologin"),
			 messages => N("I can set up your computer to automatically log on one user.") },
		       [ { text => N("Use this feature"), val => \$use_autologin, type => 'bool' },
			 { label => N("Choose the default user:"), val => \$o->{autologin}, list => \@users, disabled => sub { !$use_autologin } },
			 { label => N("Choose the window manager to run:"), val => \$o->{desktop}, list => \@wm, disabled => sub { !$use_autologin } } ]
		      );
	delete $o->{autologin} if !$use_autologin;
    } else {
	delete $o->{autologin};
    }
}

sub display_release_notes {
    my ($in, $release_notes) = @_;
    if (!$in->isa('interactive::gtk')) {
        $in->ask_from_({ title => N("Release Notes"), 
                        messages => $release_notes, #formatAlaTeX(messages::main_license()),
                    }, [ {} ]);
        return;
    }

    require Gtk3::WebKit;
    require ugtk3;
    ugtk3->import(':all');
    require mygtk3;
    mygtk3->import('gtknew');
    my $view = gtknew('WebKit_View', no_popup_menu => 1);
    $view->load_html_string($release_notes, '/');
                               
    my $w = ugtk3->new(N("Release Notes"), transient => $::main_window, modal => 1, pop_it => 1);
    gtkadd($w->{rwindow},
           gtkpack_(Gtk3::VBox->new,
                    1, create_scrolled_window(ugtk3::gtkset_border_width($view, 5),
                                              [ 'never', 'automatic' ],
                                          ),
                    0, gtkpack(create_hbox('end'),
                               gtknew('Button', text => N("Close"),
                                      clicked => sub { Gtk3->main_quit })
                           ),
                ),
       );
    mygtk3::set_main_window_size($w->{rwindow});
    $w->{real_window}->grab_focus;
    $w->{real_window}->show_all;
    $w->main;
    return;
}

sub get_release_notes {
    my ($in) = @_;
    my $ext = $in->isa('interactive::gtk') ? '.html' : '.txt';
    my $separator = $in->isa('interactive::gtk') ? "\n\n" : '';
    my $lang = (($ENV{'LC_MESSAGES'} =~ m/ru_RU/) ? 'ru' : 'en');

    my $release_notes = join($separator, grep { $_ } map {
        if ($::isInstall) {
            my $f = install::any::getFile_($::o->{stage2_phys_medium}, $_);
            $f && cat__($f);
        } else {
            my $file = $_;
            my $d = find { -e "$_/$file" } glob_("/usr/share/doc/*-release-*");
            $d && cat_("$d/$file");
        }
    } "release-notes$ext", 'release-notes.' . $ext);

    # we do not handle links:
    $release_notes =~ s!<a href=".*?">(.*?)</a>!$1!g;
    $release_notes;
}

sub run_display_release_notes {
    my ($release_notes) = @_;
    output('/tmp/release_notes.html', $release_notes);
    local $ENV{LC_ALL} = $::o->{locale}{lang} || 'C';
    run_program::raw({ detach => 1 }, '/usr/bin/display_release_notes.pl');
}

sub acceptLicense {
    my ($in, $google) = @_;
    require messages;

    my $release_notes = get_release_notes($in);

    my $r = $::testing ? 'Accept' : 'Refuse';

    my $license = join("\n\n\n",
		       messages::main_license($google, $google),
		       messages::warning_about_patents(),
		       if_($google, messages::google_provisions()));

    $in->ask_from_({ title => N("License agreement"), 
		    focus_first => 1,
		     cancel => N("Quit"),
		     messages => formatAlaTeX($license),
		     interactive_help_id => 'acceptLicense',
		     callbacks => { ok_disabled => sub { $r eq 'Refuse' } },
		   },

		   [
                       { label => N("Do you accept this license ?"), title => 1, alignment => 'right' },
                       { list => [ N_("Accept"), N_("Refuse") ], val => \$r, type => 'list', alignment => 'right',
                         format => sub { translate($_[0]) } },
                       if_($release_notes,
                           { clicked => sub { run_display_release_notes($release_notes) }, do_not_expand => 1,
                             val => \ (my $_t1 = N("Release Notes")), install_button => 1, no_indent => 1 }
                       ), 
                   ])
      or reboot();
}

sub reboot() {
    if ($::isInstall) {
	my $o = $::o;
	install::media::umount_phys_medium($o->{stage2_phys_medium});
	install::media::openCdromTray($o->{stage2_phys_medium}{device}) if !detect_devices::is_xbox() && $o->{method} eq 'cdrom';
	$o->exit;
    } else {
	# when refusing license in finish-install:
	exec("/bin/reboot");
    }
}

sub selectLanguage_install {
    my ($in, $locale) = @_;

    my $common = { 
		   title => N("Please choose a language to use"),
		   interactive_help_id => 'selectLanguage' };

    my $lang = $locale->{lang};
    my $langs = $locale->{langs} ||= {};
    my $using_images = $in->isa('interactive::gtk') && !$::o->{vga16};
	
    my %name2l = map { lang::l2name($_) => $_ } lang::list_langs();
    my $listval2val = sub { $_[0] =~ /\|(.*)/ ? $1 : $_[0] };

    #- since gtk version will use images (function image2f) we need to sort differently
    my $sort_func = $using_images ? \&lang::l2transliterated : \&lang::l2name;
    my @langs = sort { $sort_func->($a) cmp $sort_func->($b) } lang::list_langs();

    if (@langs > 15) {
	my $add_location = sub {
	    my ($l) = @_;
	    map { "$_|$l" } lang::l2location($l);
	};
	@langs = map { $add_location->($_) } @langs;

	#- to create the default value, use the first location for that value :/
	$lang = first($add_location->($lang));
    }

    my $non_utf8 = 0;
    add2hash($common, { cancel => '',
			focus_first => 1,
			advanced_messages => formatAlaTeX(N("%s can support multiple languages. Select
the languages you would like to install. They will be available
when your installation is complete and you restart your system.", "Moondrake GNU/Linux")),
			advanced_label => N("Multiple languages"),
			advanced_title => N("Select Additional Languages"),
		    });
			    
    $in->ask_from_($common, [
	{ val => \$lang, separator => '|', 
	  if_($using_images, image2f => sub { $name2l{$_[0]} =~ /^[a-z]/ && "langs/lang-$name2l{$_[0]}" }),
	  format => sub { $_[0] =~ /(.*\|)(.*)/ ? $1 . lang::l2name($2) : lang::l2name($_[0]) },
	  list => \@langs, sort => !$in->isa('interactive::gtk'),
	  focus_out => sub { $langs->{$listval2val->($lang)} = 1 } },
	  { val => \$non_utf8, type => 'bool', text => N("Old compatibility (non UTF-8) encoding"), advanced => 1 },
	  { val => \$langs->{all}, type => 'bool', text => N("All languages"), advanced => 1 },
	map {
	    { val => \$langs->{$_->[0]}, type => 'bool', disabled => sub { $langs->{all} },
	      text => $_->[1], advanced => 1,
	      image => "langs/lang-$_->[0]",
	  };
	} sort { $a->[1] cmp $b->[1] } map { [ $_, $sort_func->($_) ] } lang::list_langs(),
    ]) or return;
    $locale->{utf8} = !$non_utf8;
    %$langs = grep_each { $::b } %$langs;  #- clean hash
    $langs->{$listval2val->($lang)} = 1;
	
    #- convert to the default locale for asked language
    $locale->{lang} = $listval2val->($lang);
    lang::lang_changed($locale);
}

sub selectLanguage_standalone {
    my ($in, $locale) = @_;

    my $old_lang = $locale->{lang};
    my $common = { messages => N("Please choose a language to use"),
		   title => N("Language choice"),
		   interactive_help_id => 'selectLanguage' };

    my @langs = sort { lang::l2name($a) cmp lang::l2name($b) } lang::list_langs(exclude_non_installed => 1);
    my $non_utf8 = !$locale->{utf8};
    $in->ask_from_($common, [ 
	{ val => \$locale->{lang}, type => 'list',
	  format => sub { lang::l2name($_[0]) }, list => \@langs, allow_empty_list => 1 },
	{ val => \$non_utf8, type => 'bool', text => N("Old compatibility (non UTF-8) encoding"), advanced => 1 },
    ]);
    $locale->{utf8} = !$non_utf8;
    lang::set($locale);
    c::init_setlocale() if $in->isa('interactive::gtk');
    lang::lang_changed($locale) if $old_lang ne $locale->{lang};
}

sub selectLanguage_and_more_standalone {
    my ($in, $locale) = @_;
    eval {
	local $::isWizard = 1;
      language:
	# keep around previous settings so that selectLanguage can keep UTF-8 flag:
	local $::Wizard_no_previous = 1;
	selectLanguage_standalone($in, $locale);
	undef $::Wizard_no_previous;
	selectCountry($in, $locale) or goto language;
    };
    if ($@) {
	if ($@ !~ /wizcancel/) {
	    die;
	} else {
	    $in->exit(0);
	}
    }
}

sub selectCountry {
    my ($in, $locale) = @_;

    my $country = $locale->{country};
    my $country2locales = lang::countries_to_locales(exclude_non_installed => !$::isInstall);
    my @countries = keys %$country2locales;
    my @best = grep {
	find { 
	    $_->{main} eq lang::locale_to_main_locale($locale->{lang});
	} @{$country2locales->{$_}};
    } @countries;
    @best == 1 and @best = ();

    my $other = !member($country, @best);
    my $ext_country = $country;
    $other and @best = ();

    $in->ask_from_(
		  { title => N("Country / Region"), 
		    messages => N("Please choose your country"),
		    interactive_help_id => 'selectCountry.html',
		    if_(@best, advanced_messages => N("Here is the full list of available countries")),
		    advanced_label => @best ? N("Other Countries") : N("Advanced"),
		  },
		  [ if_(@best, { val => \$country, type => 'list', format => \&lang::c2name,
				 list => \@best, sort => 1, changed => sub { $other = 0 }  }),
		    { val => \$ext_country, type => 'list', format => \&lang::c2name,
		      list => [ @countries ], advanced => scalar(@best), changed => sub { $other = 1 } },
		    { val => \$locale->{IM}, type => 'combo', label => N("Input method:"), 
		      sort => 0, separator => '|',
		      list => [ '', lang::get_ims($locale->{lang}) ], 
		      format => sub { $_[0] ? uc($_[0] =~ /(.*)\+(.*)/ ? "$1|$1+$2" : $_[0]) : N("None") },
		      advanced => !$locale->{IM},
		    },
		]) or return;

    $locale->{country} = $other || !@best ? $ext_country : $country;
}

sub set_login_serial_console {
    my ($port, $speed) = @_;

    my $line = "s$port:12345:respawn:/sbin/agetty ttyS$port $speed ansi\n";
    substInFile { s/^s$port:.*//; $_ = $line if eof } "$::prefix/etc/inittab";
}

sub header { "
********************************************************************************
* $_[0]
********************************************************************************";
}

sub report_bug {
    my (@other) = @_;

    join '', map { chomp; "$_\n" }
      header("lspci"), detect_devices::stringlist(),
      header("pci_devices"), cat_("/proc/bus/pci/devices"),
      header("dmidecode"), arch() =~ /86/ ? `dmidecode` : (),
      header("fdisk"), `fdisk -l`,
      header("scsi"), cat_("/proc/scsi/scsi"),
      header("/sys/bus/scsi/devices"), -d '/sys/bus/scsi/devices' ? `ls -l /sys/bus/scsi/devices` : (),
      header("lsmod"), cat_("/proc/modules"),
      header("cmdline"), cat_("/proc/cmdline"),
      header("pcmcia: stab"), cat_("$::prefix/var/lib/pcmcia/stab") || cat_("$::prefix/var/run/stab"),
      header("usb"), cat_("/sys/kernel/debug/usb/devices"),
      header("partitions"), cat_("/proc/partitions"),
      header("cpuinfo"), cat_("/proc/cpuinfo"),
      header("syslog"), cat_("/tmp/syslog") || cat_("$::prefix/var/log/syslog"),
      header("Xorg.log"), cat_("/var/log/Xorg.0.log"),
      header("monitor_full_edid"), monitor_full_edid(),
      header("stage1.log"), cat_("/tmp/stage1.log") || cat_("$::prefix/root/drakx/stage1.log"),
      header("ddebug.log"), cat_("/tmp/ddebug.log") || cat_("$::prefix/root/drakx/ddebug.log"),
      header("install.log"), cat_("$::prefix/root/drakx/install.log"),
      header("fstab"), cat_("$::prefix/etc/fstab"),
      header("modprobe.conf"), cat_("$::prefix/etc/modprobe.conf"),
      header("lilo.conf"), cat_("$::prefix/etc/lilo.conf"),
      header("grub: menu.lst"), join('', map { s/^(\s*password)\s+(.*)/$1 xxx/; $_ } cat_("$::prefix/boot/grub/menu.lst")),
      header("grub: install.sh"), cat_("$::prefix/boot/grub/install.sh"),
      header("grub: device.map"), cat_("$::prefix/boot/grub/device.map"),
      header("grub2: drakboot.conf"), cat_("$::prefix/boot/grub/drakboot.conf"),
      header("grub2: grub"), cat_("$::prefix/etc/default/grub"),
      header("grub2: grub.cfg"), cat_("$::prefix/boot/grub2/grub.cfg"),
      header("xorg.conf"), cat_("$::prefix/etc/X11/xorg.conf"),
      header("urpmi.cfg"), cat_("$::prefix/etc/urpmi/urpmi.cfg"),
      header("modprobe.preload"), cat_("$::prefix/etc/modprobe.preload"),
      header("sysconfig/i18n"), cat_("$::prefix/etc/sysconfig/i18n"),
      header("locale.conf"), cat_("$::prefix/etc/locale.conf"),
      header("/proc/iomem"), cat_("/proc/iomem"),
      header("/proc/ioport"), cat_("/proc/ioports"),
      map_index { even($::i) ? header($_) : $_ } @other;
}

sub fix_broken_alternatives {
    my ($force_default) = @_;
    #- fix bad update-alternatives that may occurs after upgrade (and sometimes for install too).
    -d "$::prefix/etc/alternatives" or return;

    foreach (all("$::prefix/etc/alternatives")) {
	if ($force_default) {
	    log::l("setting alternative $_");
	} else {
	    next if run_program::rooted($::prefix, 'test', '-e', "/etc/alternatives/$_");
	    log::l("fixing broken alternative $_");
	}
	run_program::rooted($::prefix, 'update-alternatives', '--auto', $_);
    }
}


sub fileshare_config {
    my ($in, $type) = @_; #- $type is 'nfs', 'smb' or ''

    my $file = '/etc/security/fileshare.conf';
    my %conf = getVarsFromSh($file);

    my @l = (N_("No sharing"), N_("Allow all users"), N_("Custom"));
    my $restrict = exists $conf{RESTRICT} ? text2bool($conf{RESTRICT}) : 1;

    my $r = $in->ask_from_list_('fileshare',
N("Would you like to allow users to share some of their directories?
Allowing this will permit users to simply click on \"Share\" in konqueror and nautilus.

\"Custom\" permit a per-user granularity.
"),
				\@l, $l[$restrict ? (getgrnam('fileshare') ? 2 : 0) : 1]) or return;
    $restrict = $r ne $l[1];
    my $custom = $r eq $l[2];
    if ($r ne $l[0]) {
	require services;
	my %types = (
	    nfs => [ 'nfs-utils', 'nfs-server',
		     N("NFS: the traditional Unix file sharing system, with less support on Mac and Windows.")
		   ],
	    smb => [ 'samba-server', 'smb',
		     N("SMB: a file sharing system used by Windows, Mac OS X and many modern Linux systems.")
		   ],
       );
	my %l;
	if ($type) {
	    %l = ($type => 1);
	} else {
	    %l = map_each { $::a => services::starts_on_boot($::b->[1]) } %types;
	    $in->ask_from_({ messages => N("You can export using NFS or SMB. Please select which you would like to use."),
			     callbacks => { ok_disabled => sub { !any { $_ } values %l } },
			   },
			   [ map { { text => $types{$_}[2], val => \$l{$_}, type => 'bool' } } keys %l ]) or return;
	}
	foreach (keys %types) {
	    my ($pkg, $service, $_descr) = @{$types{$_}};
	    my $file = "/lib/systemd/system/$service.service";
	    if ($l{$_}) {
		$in->do_pkgs->ensure_is_installed($pkg, $file) or return;
		services::start($service);
		services::start_service_on_boot($service);
	    } elsif (-e $file) {
		services::stop($service);
		services::do_not_start_service_on_boot($service);
	    }
	}
	if ($in->do_pkgs->is_installed('nautilus')) {
	    $in->do_pkgs->ensure_is_installed('nautilus-filesharing') or return;
	}
    }
    $conf{RESTRICT} = bool2yesno($restrict);
    setVarsInSh($file, \%conf);

    if ($custom) {
	run_program::rooted($::prefix, 'groupadd', '-r', 'fileshare');
	if ($in->ask_from_no_check(
	{
	 -e '/usr/sbin/userdrake' ? (ok => N("Launch userdrake"), cancel => N("Close")) : (cancel => ''),
	 messages =>
N("The per-user sharing uses the group \"fileshare\". 
You can use userdrake to add a user to this group.")
	}, [])) {
	    run_program::run('userdrake');
	}
    }
}

sub monitor_full_edid() {
    return if $::noauto;

    my ($vbe, $edid);
    {
        # prevent warnings in install's logs:
        local $ENV{LC_ALL} = 'C';
        run_program::raw({ timeout => 20 }, 
                         'monitor-edid', '>', \$edid, '2>', \$vbe, 
                         '-v', '--perl', if_($::isStandalone, '--try-in-console'));
    }
    if ($::isInstall) {
	foreach (['edid', \$edid], ['vbe', \$vbe]) {
	    my ($name, $val) = @$_;
	    if (-e "/tmp/$name") {
		my $old = cat_("/tmp/$name");
		if (length($$val) < length($old)) {
		    log::l("new $name is worse, keeping the previous one");
		    $$val = $old;
		} elsif (length($$val) > length($old)) {
		    log::l("new $name is better, dropping the previous one");
		}
	    }
	    output("/tmp/$name", $$val);
	}
    }
    ($edid, $vbe);
}

# FIXME: is buggy regarding multiple sessions
sub running_window_manager() {
    my @window_managers = qw(drakx-matchbox-window-manager ksmserver kwin gnome-session icewm wmaker afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce4-session blackbox sawfish olvwm fluxbox compiz lxsession);

    foreach (@window_managers) {
	my @pids = fuzzy_pidofs(qr/\b$_\b/) or next;
	return wantarray() ? ($_, @pids) : $_;
    }
    undef;
}

sub set_wm_hints_if_needed {
    my ($o_in) = @_;
    my $wm = any::running_window_manager();
    $o_in->{no_Window_Manager} = !$wm if $o_in;
    $::set_dialog_hint = $wm eq 'drakx-matchbox-window-manager';
}

sub ask_window_manager_to_logout {
    my ($wm) = @_;
    
    my %h = (
	'ksmserver' => '/usr/lib/qt4/bin/qdbus org.kde.ksmserver /KSMServer logout 1 0 0',
	'kwin' => "dcop kdesktop default logout",
	'gnome-session' => "gnome-session-save --kill",
	'icewm' => "killall -QUIT icewm",
	'xfce4-session' => "xfce4-session-logout --logout",
	'lxsession' => "lxde-logout",
    );
    my $cmd = $h{$wm} or return;
    if (member($wm, 'ksmserver', 'kwin', 'gnome-session') && $> == 0) {	
	#- we cannot use dcop when we are root
	if (my $user = $ENV{USERHELPER_UID} && getpwuid($ENV{USERHELPER_UID})) {
	    $cmd = "su $user -c '$cmd'";
	} else {
	    log::l('missing or unknown $USERHELPER_UID');
	}
    }
    system($cmd);
    1;
}

sub ask_window_manager_to_logout_then_do {
    my ($wm, $pid, $action) = @_;
    if (fork()) {
	ask_window_manager_to_logout($wm);
	return;
    }
    
    open STDIN, "</dev/zero";
    open STDOUT, ">/dev/null";
    open STDERR, ">&STDERR";
    c::setsid();
    exec 'perl', '-e', q(
	my ($wm, $pid, $action) = @ARGV;
	my $nb;
	for ($nb = 30; $nb && -e "/proc/$pid"; $nb--) { sleep 1 }
	system($action) if $nb;
    ), $wm, $pid, $action;
}

sub ask_for_X_restart {
    my ($in) = @_;

    $::isStandalone && $in->isa('interactive::gtk') or return;

    my ($wm, $pid) = running_window_manager();

    if (!$wm) {
        # no window manager, ctrl-alt-del may not be supported, but we still have to restart X..
        $in->ask_okcancel('', N("You need to logout and back in again for changes to take effect. Press OK to logout now."), 1) or return;
        system('killall', 'Xorg');
    }
    else {
        $in->ask_okcancel('', N("You need to log out and back in again for changes to take effect"), 1) or return;
        ask_window_manager_to_logout_then_do($wm, $pid, 'killall Xorg');
    }
}

sub alloc_raw_device {
    my ($prefix, $device) = @_;
    my $used = 0;
    my $raw_dev;
    substInFile {
	$used = max($used, $1) if m|^\s*/dev/raw/raw(\d+)|;
	if (eof) {
	    $raw_dev = "raw/raw" . ($used + 1);
	    $_ .= "/dev/$raw_dev /dev/$device\n";
	}
    } "$prefix/etc/sysconfig/rawdevices";
    $raw_dev;
}

sub config_mtools {
    my ($prefix) = @_;
    my $file = "$prefix/etc/mtools.conf";
    -e $file or return;

    my ($f1, $f2) = detect_devices::floppies_dev();
    substInFile {
	s|drive a: file="(.*?)"|drive a: file="/dev/$f1"|;
	s|drive b: file="(.*?)"|drive b: file="/dev/$f2"| if $f2;
    } $file;
}

sub configure_timezone {
    my ($in, $timezone, $ask_gmt, $o_hide_ntp) = @_;

    require timezone;
    my $selected_timezone = $in->ask_from_treelist(N("Timezone"), N("Which is your timezone?"), '/', [ timezone::getTimeZones() ], $timezone->{timezone}) or return;
    $timezone->{timezone} = $selected_timezone;

    configure_time_more($in, $timezone, $o_hide_ntp)
	or goto &configure_timezone if $ask_gmt || to_bool($timezone->{ntp});

    1;
}

sub configure_time_more {
    my ($in, $timezone, $o_hide_ntp) = @_;

    my $ntp = to_bool($timezone->{ntp});
    my $servers = timezone::ntp_servers();
    $timezone->{ntp} ||= 'pool.ntp.org';

    require POSIX;
    use POSIX qw(strftime);
    my $time_format = "%H:%M:%S";
    my $tz_prefix = timezone::get_timezone_prefix();
    local $ENV{TZ} = ':' . $tz_prefix . '/' . $timezone->{timezone};

    $in->ask_from_({ interactive_help_id => 'configureTimezoneUTC',
                       title => N("Date, Clock & Time Zone Settings"), 
                 }, [
	  { label => N("Date, Clock & Time Zone Settings"), title => 1 },
	  { label => N("What is the best time?") },
	  { val => \$timezone->{UTC},
            type => 'list', list => [ 1, 0 ], format => sub {
                $_[0] ?
                  N("%s (hardware clock set to UTC)", POSIX::strftime($time_format, localtime())) :
                  N("%s (hardware clock set to local time)", POSIX::strftime($time_format, gmtime()));
            } },
          { label => N("NTP Server"), title => 1, advanced => $o_hide_ntp },
          { text => N("Automatic time synchronization (using NTP)"), val => \$ntp, type => 'bool',
            advanced => $o_hide_ntp },
          { val => \$timezone->{ntp}, disabled => sub { !$ntp }, advanced => $o_hide_ntp,
            type => "list", separator => '|',
            list => [ keys %$servers ], format => sub { $servers->{$_[0]} } },
    ]) or return;

    $timezone->{ntp} = '' if !$ntp;

    1;
}

sub disable_x_screensaver() {
    run_program::run("xset", "s", "off");
    run_program::run("xset", "-dpms");
}

sub enable_x_screensaver() {
    run_program::run("xset", "+dpms");
    run_program::run("xset", "s", "on");
    run_program::run("xset", "s", "reset");
}

1;
