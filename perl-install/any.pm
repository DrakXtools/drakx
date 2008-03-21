package any; # $Id$

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
    my @l = grep { /^[A-Z]/ } all($dir);
    map { if_(/(.*)\.png/, $1) } (@l ? @l : all($dir));
}

sub addKdmIcon {
    my ($user, $icon) = @_;
    my $dest = "$::prefix/usr/share/faces/$user.png";
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
    my ($u, $isMD5) = @_;

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
			    '-p', authentication::user_crypted_passwd($u, $isMD5),
			    if_($uid, '-u', $uid), if_($gid, '-g', $gid), 
			    if_($u->{realname}, '-c', $u->{realname}),
			    if_($u->{home}, '-d', $u->{home}, if_($u->{rename_from}, '-m')),
			    if_($u->{shell}, '-s', $u->{shell}), 
			    ($u->{rename_from}
			     ? ('-l', $u->{name}, $u->{rename_from})
			     : $u->{name}));
	symlink($u->{home}, $symlink_home_from) if $symlink_home_from;
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
	create_user($_, $authentication->{md5});
	run_program::rooted($::prefix, "usermod", "-G", join(",", @{$_->{groups}}), $_->{name}) if !is_empty_array_ref($_->{groups});
	addKdmIcon($_->{name}, delete $_->{auto_icon} || $_->{icon});
    }
}

sub install_acpi_pkgs {
    my ($do_pkgs, $b) = @_;

    my $acpi = bootloader::get_append_with_key($b, 'acpi');
    my $use_acpi = !member($acpi, 'off', 'ht');
    if ($use_acpi) {
	$do_pkgs->ensure_is_installed('acpi', '/usr/bin/acpi', $::isInstall);
	$do_pkgs->ensure_is_installed('acpid', '/usr/sbin/acpid', $::isInstall);
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
    my $quiet = $cmdline =~ /\bsplash=silent\b/;
    setupBootloaderBefore($do_pkgs, $b, $all_hds, $fstab, $keyboard, $allow_fb, $vga_fb, $quiet);
}

sub setupBootloaderBefore {
    my ($do_pkgs, $bootloader, $all_hds, $fstab, $keyboard, $allow_fb, $vga_fb, $quiet) = @_;
    require bootloader;

    #- auto_install backward compatibility
    #- one should now use {message_text}
    if ($bootloader->{message} =~ m!^[^/]!) {
	$bootloader->{message_text} = delete $bootloader->{message};
    }

    #- remove previous ide-scsi lines
    bootloader::modify_append($bootloader, sub {
	my ($_simple, $dict) = @_;
	@$dict = grep { $_->[1] ne 'ide-scsi' } @$dict;
    });

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
	my ($MemTotal) = cat_("/proc/meminfo") =~ /^MemTotal:\s*(\d+)/m;
	if (my ($biggest_swap) = sort { $b->{size} <=> $a->{size} } grep { isSwap($_) } @$fstab) {
	    log::l("MemTotal: $MemTotal < ", $biggest_swap->{size} / 2);
	    if ($MemTotal < $biggest_swap->{size} / 2) {
		bootloader::set_append_with_key($bootloader, resume => devices::make($biggest_swap->{device}));
	    }
	}
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

    #- propose the default fb mode for kernel fb, if aurora or bootsplash is installed.
    my $need_fb = $do_pkgs->are_installed('bootsplash');
    bootloader::suggest($bootloader, $all_hds,
                        vga_fb => ($force_vga || $vga && $need_fb) && $vga_fb,
                        quiet => $quiet);

    $bootloader->{keytable} ||= keyboard::keyboard2kmap($keyboard);
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
            #- for /tmp using tmpfs when "clean /tmp" is chosen
            fs::write_fstab($all_hds);
        }
    } while !installBootloader($in, $b, $all_hds);
}

sub installBootloader {
    my ($in, $b, $all_hds) = @_;
    return if detect_devices::is_xbox();
    install_acpi_pkgs($in->do_pkgs, $b);

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
    } elsif (arch() =~ /ppc/) {
	if (detect_devices::get_mac_model() !~ /IBM/) {
            my $of_boot = bootloader::dev2yaboot($b->{boot});
	    $in->ask_warn('', N("You may need to change your Open Firmware boot-device to\n enable the bootloader.  If you do not see the bootloader prompt at\n reboot, hold down Command-Option-O-F at reboot and enter:\n setenv boot-device %s,\\\\:tbxi\n Then type: shut-down\nAt your next boot you should see the bootloader prompt.", $of_boot));
	}
    }
    1;
}


sub setupBootloader_simple {
    my ($in, $b, $all_hds, $fstab, $security) = @_;
    my $hds = $all_hds->{hds};

    require bootloader;
    bootloader::ensafe_first_bios_drive($hds)
	|| $b->{bootUnsafe} || arch() =~ /ppc/ or return 1; #- default is good enough
    
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

    if (arch() =~ /ppc/ ||
	  !is_empty_hash_ref($b->{bios})) {
	#- some bios mapping already there
	return 1;
    } elsif (bootloader::mixed_kind_of_disks($hds) && $b->{boot} =~ /\d$/) { #- on a partition
	# see below
    } else {
	return 1;
    }

    log::l("_ask_boot_bios_drive");
    my $hd = $in->ask_from_listf('', N("You decided to install the bootloader on a partition.
This implies you already have a bootloader on the hard drive you boot (eg: System Commander).

On which drive are you booting?"), \&partition_table::description, $hds) or return 0;
    log::l("mixed_kind_of_disks chosen $hd->{device}");
    $b->{first_hd_device} = "/dev/$hd->{device}";
    1;
}

sub setupBootloader__mbr_or_not {
    my ($in, $b, $hds, $fstab) = @_;

    log::l("setupBootloader__mbr_or_not");

    if (arch() =~ /ppc/) {
	if (defined $partition_table::mac::bootstrap_part) {
	    $b->{boot} = $partition_table::mac::bootstrap_part;
	    log::l("set bootstrap to $b->{boot}"); 
	} else {
	    die "no bootstrap partition - yaboot.conf creation failed";
	}
    } else {
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
	$in->ask_from_({ title => N("LILO/grub Installation"),
			 icon => 'banner-bootL',
			 messages => N("Where do you want to install the bootloader?"),
			 interactive_help_id => 'setupBootloaderBeginner',
		       },
		      [ { val => \$default, list => \@l, format => sub { $_[0][0] }, type => 'list' } ]);
	my $new_boot = $default->[1];

	#- remove bios mapping if the user changed the boot device
	delete $b->{bios} if $new_boot && $new_boot ne $b->{boot};
	$b->{boot} = $new_boot or return;
    }
    1;
}

sub setupBootloader__general {
    my ($in, $b, $all_hds, $fstab, $security) = @_;

    return if detect_devices::is_xbox();
    my @method_choices = bootloader::method_choices($all_hds);
    my $prev_force_acpi = my $force_acpi = bootloader::get_append_with_key($b, 'acpi') !~ /off|ht/;
    my $prev_enable_apic = my $enable_apic = !bootloader::get_append_simple($b, 'noapic');
    my $prev_enable_lapic = my $enable_lapic = !bootloader::get_append_simple($b, 'nolapic');
    my $memsize = bootloader::get_append_memsize($b);
    my $prev_clean_tmp = my $clean_tmp = any { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special} ||= []};
    my $prev_boot = $b->{boot};
    my $prev_method = $b->{method};

    $b->{password2} ||= $b->{password} ||= '';
    $::Wizard_title = N("Boot Style Configuration");
    if (arch() !~ /ppc/) {
	my (@boot_devices, %boot_devices);
	foreach (bootloader::allowed_boot_parts($b, $all_hds)) {
	    my $dev = "/dev/$_->{device}";
	    push @boot_devices, $dev;
	    $boot_devices{$dev} = $_->{info} ? "$dev ($_->{info})" : $dev;
	}

	$in->ask_from_({ #messages => N("Bootloader main options"),
			 title => N("Bootloader main options"),
			 icon => 'banner-bootL',
			 interactive_help_id => 'setupBootloader',
		       }, [
			 #title => N("Bootloader main options"),
            { label => N("Bootloader"), title => 1 },
            { label => N("Bootloader to use"), val => \$b->{method}, list => \@method_choices, format => \&bootloader::method2text },
                if_(arch() !~ /ia64/,
            { label => N("Boot device"), val => \$b->{boot}, list => \@boot_devices, format => sub { $boot_devices{$_[0]} } },
		),
            { label => N("Main options"), title => 1 },
            { label => N("Delay before booting default image"), val => \$b->{timeout} },
            { text => N("Enable ACPI"), val => \$force_acpi, type => 'bool' },
            { text => N("Enable APIC"), val => \$enable_apic, type => 'bool', advanced => 1, disabled => sub { !$enable_lapic } }, 
            { text => N("Enable Local APIC"), val => \$enable_lapic, type => 'bool', advanced => 1 },
		if_($security >= 4 || $b->{password} || $b->{restricted},
	    { label => N("Password"), val => \$b->{password}, hidden => 1,
	      validate => sub { 
		  my $ok = $b->{password} eq $b->{password2} or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]);
		  my $ok2 = !($b->{password} && $b->{method} eq 'grub-graphic') or $in->ask_warn('', N("You can not use a password with %s", bootloader::method2text($b->{method})));
		  $ok && $ok2;
	      } },
            { label => N("Password (again)"), val => \$b->{password2}, hidden => 1 },
            { text => N("Restrict command line options"), val => \$b->{restricted}, type => "bool", text => N("restrict"),
	      validate => sub { my $ok = !$b->{restricted} || $b->{password} or $in->ask_warn('', N("Option ``Restrict command line options'' is of no use without a password")); $ok } },
		),
            { text => N("Clean /tmp at each boot"), val => \$clean_tmp, type => 'bool', advanced => 1 },
            { label => N("Precise RAM size if needed (found %d MB)", availableRamMB()), val => \$memsize, advanced => 1,
	      validate => sub { my $ok = !$memsize || $memsize =~ /^\d+K$/ || $memsize =~ s/^(\d+)M?$/$1M/i or $in->ask_warn('', N("Give the ram size in MB")); $ok } },
        ]) or return 0;
    } else {
	$b->{boot} = $partition_table::mac::bootstrap_part;	
	$in->ask_from_({ messages => N("Bootloader main options"),
			 title => N("Bootloader main options"),
			 icon => 'banner-bootL',
			 interactive_help_id => 'setupYabootGeneral',
		       }, [
            { label => N("Bootloader to use"), val => \$b->{method}, list => \@method_choices, format => \&bootloader::method2text },
            { label => N("Init Message"), val => \$b->{'init-message'} },
            { label => N("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (grep { isAppleBootstrap($_) } @$fstab)) ] },
            { label => N("Open Firmware Delay"), val => \$b->{delay} },
            { label => N("Kernel Boot Timeout"), val => \$b->{timeout} },
            { label => N("Enable CD Boot?"), val => \$b->{enablecdboot}, type => "bool" },
            { label => N("Enable OF Boot?"), val => \$b->{enableofboot}, type => "bool" },
            { label => N("Default OS?"), val => \$b->{defaultos}, list => [ 'linux', 'macos', 'macosx', 'darwin' ] },
        ]) or return 0;				
    }

    #- remove bios mapping if the user changed the boot device
    delete $b->{bios} if $b->{boot} ne $prev_boot;

    if ($b->{boot} =~ m!/dev/md\d+$!) {
	$b->{'raid-extra-boot'} = 'mbr';
    } else {
	delete $b->{'raid-extra-boot'} if $b->{'raid-extra-boot'} eq 'mbr';
    }

    bootloader::ensure_pkg_is_installed($in->do_pkgs, $b) or goto &setupBootloader__general;

    bootloader::suggest_message_text($b) if ! -e "$::prefix/boot/message-text"; #- in case we switch from grub to lilo

    bootloader::set_append_memsize($b, $memsize);
    if ($prev_force_acpi != $force_acpi) {
	bootloader::set_append_with_key($b, acpi => ($force_acpi ? '' : 'ht'));
    }
    if ($prev_enable_apic != $enable_apic) {
	($enable_apic ? \&bootloader::remove_append_simple : \&bootloader::set_append_simple)->($b, 'noapic');
    }
    if ($prev_enable_lapic != $enable_lapic) {
	($enable_lapic ? \&bootloader::remove_append_simple : \&bootloader::set_append_simple)->($b, 'nolapic');
    }

    if ($prev_clean_tmp != $clean_tmp) {
	if ($clean_tmp && !fs::get::has_mntpoint('/tmp', $all_hds)) {
	    push @{$all_hds->{special}}, { device => 'none', mntpoint => '/tmp', fs_type => 'tmpfs' };
	} else {
	    @{$all_hds->{special}} = grep { $_->{mntpoint} ne '/tmp' } @{$all_hds->{special}};
	}
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
	    my $info_ = $info ? "$dev ($info)" : $dev;
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
  if_(arch() !~ /ppc|ia64/,
{ label => N("Video mode"), val => \$vga, list => [ '', Xconfig::resolution_and_depth::bios_vga_modes() ], format => \&Xconfig::resolution_and_depth::to_string, advanced => 1 },
),
{ label => N("Initrd"), val => \$e->{initrd}, list => [ map { if_(/^initrd/, "/boot/$_") } all("$::prefix/boot") ], not_edit => 0, advanced => 1 },
{ label => N("Network profile"), val => \$netprofile, list => [ sort(uniq('', $netprofile, network::network::netprofile_list())) ], advanced => 1 },
	    );
	} else {
	    @l = ( 
{ label => N("Root"), val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab, detect_devices::floppies() ] },
	    );
	}
	if (arch() !~ /ppc/) {
	    @l = (
		  { label => N("Label"), val => \$e->{label} },
		  @l,
		  { text => N("Default"), val => \$default, type => 'bool' },
		 );
	} else {
	    unshift @l, { label => N("Label"), val => \$e->{label}, list => ['macos', 'macosx', 'darwin'] };
	    if ($e->{type} eq "image") {
		@l = ({ label => N("Label"), val => \$e->{label} },
		(@l[1..2], { label => N("Append"), val => \$append }),
		{ label => N("NoVideo"), val => \$e->{novideo}, type => 'bool' },
		{ text => N("Default"), val => \$default, type => 'bool' }
		);
	    }
	}

	$in->ask_from_(
	    {
	     interactive_help_id => arch() =~ /ppc/ ? 'setupYabootAddEntry' : 'setupBootloaderAddEntry',
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
				[ N_("Linux"), arch() =~ /sparc/ ? N_("Other OS (SunOS...)") : arch() =~ /ppc/ ? 
				  N_("Other OS (MacOS...)") : N_("Other OS (Windows...)") ]
			       ) eq "Linux") {
	    $e = { type => 'image',
		   root => '/dev/' . fs::get::root($fstab)->{device}, #- assume a good default.
		 };
	    $prefix = "linux";
	} else {
	    $e = { type => 'other' };
	    $prefix = arch() =~ /sparc/ ? "sunos" : arch() =~ /ppc/ ? "macos" : "windows";
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

    my @prev_entries = @{$b->{entries}};
    if ($in->ask_from__add_modify_remove('',
N("Here are the entries on your boot menu so far.
You can create additional entries or change the existing ones."), [ { 
        format => sub {
	    my ($e) = @_;
	    ref($e) ? 
	      ($b->{default} eq $e->{label} ? "  *  " : "     ") . "$e->{label} ($e->{kernel_or_dev})" : 
		translate($e);
	}, list => $b->{entries},
    } ], Add => $Add, Modify => $Modify, Remove => $Remove)) {
	1;
    } else {
	@{$b->{entries}} = @prev_entries;
	'';
    }
}

sub get_autologin() {
    my %desktop = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
    my $gdm_file = "$::prefix/etc/X11/gdm/custom.conf";
    my $kdm_file = "$::prefix/etc/kde/kdm/kdmrc";
    my $desktop = $desktop{DESKTOP} || (! -e $kdm_file && -e $gdm_file ? 'GNOME' : 'KDE');
    my $autologin = do {
	if (($desktop{DISPLAYMANAGER} || $desktop) eq 'GNOME') {
	    my %conf = read_gnomekderc($gdm_file, 'daemon');
	    text2bool($conf{AutomaticLoginEnable}) && $conf{AutomaticLogin};
	} else { # KDM / MdkKDM
	    my %conf = read_gnomekderc($kdm_file, 'X-:0-Core');
	    text2bool($conf{AutoLoginEnable}) && $conf{AutoLoginUser};
	}
    };
    { autologin => $autologin, desktop => $desktop };
}

sub set_autologin {
    my ($do_pkgs, $o_user, $o_wm) = @_;
    log::l("set_autologin $o_user $o_wm");
    my $autologin = bool2text($o_user);

    #- Configure KDM / MDKKDM
    eval { common::update_gnomekderc_no_create("$::prefix/etc/kde/kdm/kdmrc", 'X-:0-Core' => (
	AutoLoginEnable => $autologin,
	AutoLoginUser => $o_user,
    )) };

    #- Configure GDM
    eval { update_gnomekderc("$::prefix/etc/X11/gdm/custom.conf", daemon => (
	AutomaticLoginEnable => $autologin,
	AutomaticLogin => $o_user,
    )) };
  
    my $xdm_autologin_cfg = "$::prefix/etc/sysconfig/autologin";
    if (member($o_wm, 'KDE', 'GNOME')) {
	unlink $xdm_autologin_cfg;
    } else {
	$do_pkgs->ensure_is_installed('autologin', '/usr/bin/startx.autologin') if $o_user;
	setVarsInShMode($xdm_autologin_cfg, 0644,
			{ USER => $o_user, AUTOLOGIN => bool2yesno($o_user), EXEC => '/usr/bin/startx.autologin' });
    }

    if ($o_user) {
	my $home = (getpwnam($o_user))[7];
	set_window_manager($home, $o_wm);
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
    rotate_log("$prefix/root/drakx/$_") foreach qw(ddebug.log install.log);
}

sub writeandclean_ldsoconf {
    my ($prefix) = @_;
    my $file = "$prefix/etc/ld.so.conf";
    my @l = chomp_(cat_($file));

    my @default = ('/lib', '/usr/lib'); #- no need to have /lib and /usr/lib in ld.so.conf
    my @suggest = ('/usr/X11R6/lib', '/usr/lib/qt3/lib'); #- needed for upgrade where package renaming can cause this to disappear

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

sub ask_user_and_root {
    my ($in, $superuser, $users, $security, %options) = @_;

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
        $u->{name} =~ /^[a-z]+?[a-z0-9_-]*?$/ or $in->ask_warn('', N("The user name must contain only lower cased letters, numbers, `-' and `_'")), return;
        length($u->{name}) <= 32 or $in->ask_warn('', N("The user name is too long")), return;
        defined getpwnam($u->{name}) || member($u->{name}, map { $_->{name} } @$users) and $in->ask_warn('', N("This user name has already been added")), return;
	'ok';
    };
    my $validate_uid_gid = sub {
	my ($field) = @_;
	my $id = $u->{$field} or return 'ok';
	my $name = $field eq 'uid' ? N("User ID") : N("Group ID");
	$id =~ /^\d+$/ or $in->ask_warn('', N("%s must be a number", $name)), return;
	$id >= 500 or $in->ask_yesorno('', N("%s should be above 500. Accept anyway?", $name)) or return;
	'ok';
    };
    my $ret = $in->ask_from_(
        { title => N("User management"),
          icon => 'banner-adduser',
          interactive_help_id => 'addUser',
	  if_($::isInstall && $superuser, cancel => ''),
          focus_first => 1,
        }, [ 
	      $superuser ? (
	  { label => N("Set administrator (root) password"), title => 1 },
	  { label => N("Password"), val => \$superuser->{password},  hidden => 1,
	    validate => sub { authentication::check_given_password($in, $superuser, 2 * $security) } },
	  { label => N("Password (again)"), val => \$superuser->{password2}, hidden => 1 },
              ) : (),
	  { label => N("Enter a user"), title => 1 }, if_($names, { label => $names }),
	  { label => N("Real name"), val => \$u->{realname}, focus_out => sub {
		$u->{name} ||= lc first($u->{realname} =~ /([a-zA-Z0-9_-]+)/);
	    } },
          { label => N("Login name"), val => \$u->{name}, list => \@suggested_names, not_edit => 0, validate => $validate_name },
          { label => N("Password"),val => \$u->{password}, hidden => 1,
	    validate => sub { authentication::check_given_password($in, $u, $security > 3 ? 6 : 0) } },
          { label => N("Password (again)"), val => \$u->{password2}, hidden => 1 },
          { label => N("Shell"), val => \$u->{shell}, list => [ shells() ], advanced => 1 },
	  { label => N("User ID"), val => \$u->{uid}, advanced => 1, validate => sub { $validate_uid_gid->('uid') } },
	  { label => N("Group ID"), val => \$u->{gid}, advanced => 1, validate => sub { $validate_uid_gid->('gid') } },
           if_($security <= 3 && !$options{noicons} && @icons,
	  { label => N("Icon"), val => \ ($u->{icon} ||= 'default'), list => \@icons, icon2f => \&face2png, format => \&translate },
           ),
	    if_($security > 3,
                map {
                    { label => $_, val => \$groups{$_}, text => $high_security_groups{$_}, type => 'bool' };
                } keys %high_security_groups,
               ),
	  ],
    );
    $u->{groups} = [ grep { $groups{$_} } keys %groups ];

    push @$users, $u if $u->{name};

    $ret && $u;
}

sub sessions() {
    split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-l'));
}
sub sessions_with_order() {
    my %h = map { /(.*)=(.*)/ } split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-L'));
    \%h;
}

sub autologin {
    my ($o, $in) = @_;

    my @wm = sessions();
    my @users = map { $_->{name} } @{$o->{users} || []};

    if (member('KDE', @wm) && @users == 1 && $o->{meta_class} eq 'desktop') {
	$o->{desktop} = 'KDE';
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
    my ($o) = @_;
    require Gtk2::Html2;
    require ugtk2;
    ugtk2->import(':all');
    require mygtk2;
    mygtk2->import('gtknew');
    my $view     = Gtk2::Html2::View->new;
    my $document = Gtk2::Html2::Document->new;
    $view->set_document($document);
                               
    $document->clear;
    $document->open_stream("text/html");
    $document->write_stream($o->{release_notes});
                               
    my $w = ugtk2->new(N("Release Notes"), transient => $::main_window, modal => 1);
    gtkadd($w->{rwindow},
           gtkpack_(Gtk2::VBox->new,
                    1, create_scrolled_window(ugtk2::gtkset_border_width($view, 5),
                                              [ 'never', 'automatic' ],
                                          ),
                    0, gtkpack(create_hbox('edge'),
                               gtknew('Button', text => N("Close"),
                                      clicked => sub { Gtk2->main_quit })
                           ),
                ),
       );
    # make parent visible still visible:
    local ($::real_windowwidth, $::real_windowheight) = ($::real_windowwidth - 50, $::real_windowheight - 50) if $::isInstall;
    mygtk2::set_main_window_size($w->{rwindow});
    $w->{real_window}->grab_focus;
    $w->{real_window}->show_all;
    $w->main;
    return;
}

sub acceptLicense {
    my ($o) = @_;
    require messages;

    $o->{release_notes} = join("\n\n", grep { $_ } map {
        if ($::isInstall) {
            my $f = install::any::getFile_($o->{stage2_phys_medium}, $_);
            $f && cat__($f);
        } else {
            my $file = $_;
            my $d = find { -e "$_/$file" } glob_("/usr/share/doc/*-release-*");
            $d && cat_("$d/$file");
        }
    } 'release-notes.html', 'release-notes.' . arch() . '.html');

    # we do not handle links:
    $o->{release_notes} =~ s!<a href=".*?">(.*?)</a>!$1!g;

    return if $o->{useless_thing_accepted};

    my $r = $::testing ? 'Accept' : 'Refuse';

    $o->ask_from_({ title => N("License agreement"), 
                    icon => 'banner-license',
		    focus_first => 1,
		     cancel => N("Quit"),
		     messages => formatAlaTeX(messages::main_license() . "\n\n\n" . messages::warning_about_patents()),
		     interactive_help_id => 'acceptLicense',
		     if_($o->{release_notes},
                   more_buttons => [ [ N("Release Notes"), sub { display_release_notes($o) }, 1 ] ]),
		     callbacks => { ok_disabled => sub { $r eq 'Refuse' } },
		   },
		   [ { list => [ N_("Accept"), N_("Refuse") ], val => \$r, type => 'list', format => sub { translate($_[0]) } } ])
      or do {
	  # when refusing license in finish-install:
	  exec("/sbin/reboot") if !$::isInstall;

	      install::media::umount_phys_medium($o->{stage2_phys_medium});
	      install::media::openCdromTray($o->{stage2_phys_medium}{device}) if !detect_devices::is_xbox() && $o->{method} eq 'cdrom';
	      $o->exit;
      };
}


sub selectLanguage_install {
    my ($in, $locale) = @_;

    my $common = { messages => N("Please choose a language to use."),
		   title => N("Language choice"),
		   icon => 'banner-languages.png',
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
    my $utf8_forced;
    add2hash($common, { cancel => '',
			focus_first => 1,
			advanced_messages => formatAlaTeX(N("Mandriva Linux can support multiple languages. Select
the languages you would like to install. They will be available
when your installation is complete and you restart your system.")),
			advanced_label => N("Multi languages"),
		    });
			    
    $in->ask_from_($common, [
	{ val => \$lang, separator => '|', 
	  if_($using_images, image2f => sub { $name2l{$_[0]} =~ /^[a-z]/ && "langs/lang-$name2l{$_[0]}" }),
	  format => sub { $_[0] =~ /(.*\|)(.*)/ ? $1 . lang::l2name($2) : lang::l2name($_[0]) },
	  list => \@langs, sort => !$in->isa('interactive::gtk'), changed => sub { 
	      #- very special cases for langs which do not like UTF-8
	      $non_utf8 = $lang =~ /\bzh/ if !$utf8_forced;
	  }, focus_out => sub { $langs->{$listval2val->($lang)} = 1 } },
	  { val => \$non_utf8, type => 'bool', text => N("Old compatibility (non UTF-8) encoding"), 
	    advanced => 1, changed => sub { $utf8_forced = 1 } },
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

    my $common = { messages => N("Please choose a language to use."),
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
    Gtk2->set_locale if $in->isa('interactive::gtk');
}

sub selectLanguage_and_more_standalone {
    my ($in, $locale) = @_;
    eval {
	local $::isWizard = 1;
      language:
	# keep around previous settings so that selectLanguage can keep UTF-8 flag:
	local $::Wizard_no_previous = 1;
	my $old_lang = $locale->{lang};
	selectLanguage_standalone($in, $locale);
	lang::lang_changed($locale) if $old_lang ne $locale->{lang};
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
		    icon => 'banner-languages',
		    messages => N("Please choose your country."),
		    interactive_help_id => 'selectCountry',
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

sub report_bug {
    my (@other) = @_;

    sub header { "
********************************************************************************
* $_[0]
********************************************************************************";
    }

    join '', map { chomp; "$_\n" }
      header("lspci"), detect_devices::stringlist(),
      header("pci_devices"), cat_("/proc/bus/pci/devices"),
      header("dmidecode"), `dmidecode`,
      header("fdisk"), arch() =~ /ppc/ ? `pdisk -l` : `fdisk -l`,
      header("scsi"), cat_("/proc/scsi/scsi"),
      header("/sys/bus/scsi/devices"), -d '/sys/bus/scsi/devices' ? `ls -l /sys/bus/scsi/devices` : (),
      header("lsmod"), cat_("/proc/modules"),
      header("cmdline"), cat_("/proc/cmdline"),
      header("pcmcia: stab"), cat_("$::prefix/var/lib/pcmcia/stab") || cat_("$::prefix/var/run/stab"),
      header("usb"), cat_("/proc/bus/usb/devices"),
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
      header("xorg.conf"), cat_("$::prefix/etc/X11/xorg.conf"),
      header("urpmi.cfg"), cat_("$::prefix/etc/urpmi/urpmi.cfg"),
      header("modprobe.preload"), cat_("$::prefix/etc/modprobe.preload"),
      header("sysconfig/i18n"), cat_("$::prefix/etc/sysconfig/i18n"),
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
	    my $file = "/etc/init.d/$service";
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

    devices::make('zero');
    my ($vbe, $edid);
    run_program::raw({ timeout => 20 }, 
		     'monitor-edid', '>', \$edid, '2>', \$vbe, 
		     '-v', '--perl', if_($::isStandalone, '--try-in-console'));
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

sub running_window_manager() {
    my @window_managers = qw(kwin gnome-session icewm wmaker afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce blackbox sawfish olvwm fluxbox compiz);

    foreach (@window_managers) {
	my @pids = fuzzy_pidofs(qr/\b$_\b/) or next;
	return wantarray() ? ($_, @pids) : $_;
    }
    undef;
}

sub ask_window_manager_to_logout {
    my ($wm) = @_;
    
    my %h = (
	'kwin' => "dcop kdesktop default logout",
	'gnome-session' => "gnome-session-save --kill",
	'icewm' => "killall -QUIT icewm",
    );
    my $cmd = $h{$wm} or return;
    if ($wm eq 'gnome-session') {
	#- NB: consolehelper does not destroy $HOME whereas kdesu does
	#- for gnome, we use consolehelper, so below works
	$ENV{ICEAUTHORITY} ||= "$ENV{HOME}/.ICEauthority";
    } elsif ($wm eq 'kwin' && $> == 0) {
	#- we can not use dcop when we are root
	$cmd = "su $ENV{USER} -c '$cmd'";
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
    	$in->ask_warn('', N("Please log out and then use Ctrl-Alt-BackSpace"));
	return;
    }

    $in->ask_okcancel('', N("You need to log out and back in again for changes to take effect"), 1) or return;

    ask_window_manager_to_logout_then_do($wm, $pid, 'killall X');
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
    my ($in, $timezone, $ask_gmt) = @_;

    require timezone;
    my $selected_timezone = $in->ask_from_treelist(N("Timezone"), N("Which is your timezone?"), '/', [ timezone::getTimeZones() ], $timezone->{timezone}) or return;
    $timezone->{timezone} = $selected_timezone;

    configure_time_more($in, $timezone, undef)
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
    local $ENV{TZ} = $timezone->{timezone};

    $in->ask_from_({ interactive_help_id => 'configureTimezoneGMT',
                       title => N("Date, Clock & Time Zone Settings"), 
                 }, [
	  { label => N("Date, Clock & Time Zone Settings"), title => 1 },
	  { label => N("What is the best time?") },
	  { val => \$timezone->{UTC},
            type => 'list', list => [ 0, 1 ], format => sub {
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
