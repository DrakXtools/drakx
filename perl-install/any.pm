package any; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use detect_devices;
use partition_table qw(:types);
use fsedit;
use fs;
use lang;
use run_program;
use keyboard;
use devices;
use modules;
use log;
use c;

sub drakx_version { 
    sprintf "DrakX v%s built %s", $::testing ? ('TEST', scalar gmtime()) : (split('/', cat_("$ENV{SHARE_PATH}/VERSION")))[2,3];
}

sub facesdir {
    my ($prefix) = @_;
    "$prefix/usr/share/mdk/faces/";
}
sub face2png {
    my ($face, $prefix) = @_;
    facesdir($prefix) . $face . ".png";
}
sub facesnames {
    my ($prefix) = @_;
    my $dir = facesdir($prefix);
    my @l = grep { /^[A-Z]/ } all($dir);
    map { if_(/(.*)\.png/, $1) } (@l ? @l : all($dir));
}

sub addKdmIcon {
    my ($prefix, $user, $icon) = @_;
    my $dest = "$prefix/usr/share/faces/$user.png";
    eval { cp_af(facesdir($prefix) . $icon . ".png", $dest) } if $icon;
}

sub allocUsers {
    my ($prefix, $users) = @_;
    my @m = my @l = facesnames($prefix);
    foreach (grep { !$_->{icon} || $_->{icon} eq "automagic" } @$users) {
	$_->{auto_icon} = splice(@m, rand(@m), 1); #- known biased (see cookbook for better)
	log::l("auto_icon is $_->{auto_icon}");
	@m = @l unless @m;
    }
}

sub addUsers {
    my ($prefix, $users) = @_;

    allocUsers($prefix, $users);
    foreach my $u (@$users) {
	run_program::rooted($prefix, "usermod", "-G", join(",", @{$u->{groups}}), $u->{name}) if !is_empty_array_ref($u->{groups});
	addKdmIcon($prefix, $u->{name}, delete $u->{auto_icon} || $u->{icon});
    }
}

sub crypt {
    my ($password, $md5) = @_;
    crypt($password, $md5 ? '$1$' . salt(8) : salt(2));
}
sub enableShadow {
    my ($prefix) = @_;
    run_program::rooted($prefix, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($prefix, "grpconv") or log::l("grpconv failed");
}

sub kernelVersion {
    my $kernel = readlink "$::prefix/boot/vmlinuz" || first(all("$::prefix/boot"));
    first($kernel =~ /vmlinuz-(.*)/);
}

sub mkbootdisk {
    my ($in, $bootloader, $fstab) = @_;

    if (arch() =~ /sparc/) {
	#- as probing floppies is a bit more different on sparc, assume always /dev/fd0.
	#- [pixel] uh, but in that case it would be better to change detect_devices::floppies, no?
	$in->ask_okcancel('',
			 N("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
SILO on your system, or another operating system removes SILO, or SILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures.

If you want to create a bootdisk for your system, insert a floppy in the first
drive and press \"Ok\".")) or return;
    } else {
	$in->ask_yesorno('', formatAlaTeX(
			    N("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
LILO (or grub) on your system, or another operating system removes LILO, or LILO doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?
%s", isThisFs('xfs', fsedit::get_root($fstab)) ? N("

(WARNING! You're using XFS for your root partition,
creating a bootdisk on a 1.44 Mb floppy will probably fail,
because XFS needs a very large driver).") : ''))) or return;
    }

    my $floppy_dev;
    my @l = detect_devices::floppies_dev() or die N("Sorry, no floppy drive available");
    my %l = (
	     'fd0'  => N("First floppy drive"),
	     'fd1'  => N("Second floppy drive"),
	     'Skip' => N("Skip"),
	    );
    my $format = sub { $l{$_[0]} || $_[0] };

    $in->ask_from_({
	       messages => N("Choose the floppy drive you want to use to make the bootdisk"),
	      }, [ { val => \$floppy_dev, list => \@l, format => $format } ]
        ) or return;

    $in->ask_warn('', N("Insert a floppy in %s", $format->($floppy_dev)));

    my $_w = $in->wait_message('', N("Creating bootdisk..."));

    require bootloader;
    bootloader::mkbootdisk(kernelVersion(), $floppy_dev, $bootloader->{perImageAppend});
    1;
}

sub setupBootloader {
    my ($in, $b, $all_hds, $fstab, $security) = @_;
    my $hds = $all_hds->{hds};

    require bootloader;
  general:
    setupBootloader__general($in, $b, $all_hds, $fstab, $security) or return 0;
    setupBootloader__boot_bios_drive($in, $b, $hds) or goto general;

    setupBootloader__entries($in, $b, $all_hds, $fstab); #- need to add a goto general here ? or Add, Modify, Remove is different ?

    #- somewhere should bootloader really installed ?
    bootloader::install($b, $fstab, $hds);
}


sub setupBootloader_simple {
    my ($in, $b, $all_hds, $fstab, $security) = @_;
    my $hds = $all_hds->{hds};

    require bootloader;
    my $mixed_kind_of_disks = bootloader::mixed_kind_of_disks($hds);
    #- full expert questions when there is 2 kind of disks
    #- it would need a semi_auto asking on which drive the bios boots...

    $mixed_kind_of_disks || $b->{bootUnsafe} || arch() =~ /ppc/ or return 1; #- default is good enough
    
    if (!$mixed_kind_of_disks && arch() !~ /ia64/) {
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

    bootloader::mixed_kind_of_disks($hds) && 
      $b->{boot} =~ /\d$/ && #- on a partition
	is_empty_hash_ref($b->{bios}) && #- some bios mapping already there
	  arch() !~ /ppc/ or return 1;

    log::l("mixed_kind_of_disks");
    my $hd = $in->ask_from_listf('', N("You decided to install the bootloader on a partition.
This implies you already have a bootloader on the hard drive you boot (eg: System Commander).

On which drive are you booting?"), \&partition_table::description, $hds) or return 0;
    log::l("mixed_kind_of_disks chosen $hd->{device}");
    $b->{first_hd_device} = "/dev/$hd->{device}";
    1;
}

sub setupBootloader__mbr_or_not {
    my ($in, $b, $hds, $fstab) = @_;

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
		 [ N("First sector of drive (MBR)") => '/dev/' . $hds->[0]{device} ],
		 [ N("First sector of the root partition") => '/dev/' . fsedit::get_root($fstab, 'boot')->{device} ],
		     if_($floppy, 
                 [ N("On Floppy") => "/dev/$floppy" ],
		     ),
		 [ N("Skip") => '' ],
		);

	my $default = arch() =~ /sparc/ ? ($b->{use_partition} ? $l[1] : $l[0]) : 
	                                  find { $_->[1] eq $b->{boot} } @l;
	$in->ask_from_({ title => arch() =~ /sparc/ ? N("SILO Installation") : N("LILO/grub Installation"),
			 messages => N("Where do you want to install the bootloader?"),
			 interactive_help_id => 'setupBootloaderBeginner',
		       },
		      [ { val => \$default, list => \@l, format => sub { $_[0][0] }, type => 'list' } ]);
	my $new_boot = $default->[1] or return;

	if (arch() =~ /sparc/) {
	    $b->{use_partition} = $new_boot eq $l[1][1];
	}  else {
	    #- remove bios mapping if the user changed the boot device
	    delete $b->{bios} if $new_boot ne $b->{boot};

	    $b->{boot} = $new_boot;
	}
    }
    1;
}

sub setupBootloader__general {
    my ($in, $b, $all_hds, $fstab, $security) = @_;

    my @silo_install_lang = (N("First sector of drive (MBR)"), N("First sector of boot partition"));

    ($b->{method}, my $method_choices) = bootloader::method_choices($fstab);
    my $profiles = bootloader::has_profiles($b);
    my $previous_acpi_val = bootloader::get_append($b, 'acpi');
    my $force_acpi = $previous_acpi_val eq 'on';
    my $memsize = bootloader::get_append($b, 'mem');
    my $prev_clean_tmp = my $clean_tmp = any { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special} ||= []};
    my $prev_boot = $b->{boot};
    my $mkbootdisk;

    $b->{password2} ||= $b->{password} ||= '';
    $b->{vga} ||= 'normal';
    if (arch() !~ /ppc/) {
	$in->ask_from_({ messages => N("Bootloader main options"),
			 interactive_help_id => 'setupBootloader',
		       }, [
            { label => N("Bootloader to use"), val => \$b->{method}, list => [ keys %$method_choices ], format => sub { $method_choices->{$_[0]} } },
                arch() =~ /sparc/ ? (
            { label => N("Bootloader installation"), val => \$b->{use_partition}, list => [ 0, 1 ], format => sub { $silo_install_lang[$_[0]] } },
		) : if_(arch() !~ /ia64/,
            { label => N("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (@{$all_hds->{hds}}, grep { !isFat_or_NTFS($_) } @$fstab)), detect_devices::floppies_dev() ], not_edit => !$::expert },
            { label => N("Compact"), val => \$b->{compact}, type => "bool", text => N("compact"), advanced => 1 },
            { label => N("Video mode"), val => \$b->{vga}, list => [ keys %bootloader::vga_modes ], not_edit => !$::expert, format => sub { $bootloader::vga_modes{$_[0]} }, advanced => 1 },
		),
            { label => N("Delay before booting default image"), val => \$b->{timeout} },
	        if_($previous_acpi_val,
            { label => N("Force ACPI"), val => \$force_acpi, type => 'bool' },
		),
		if_($security >= 4 || $b->{password} || $b->{restricted},
            { label => N("Password"), val => \$b->{password}, hidden => 1 },
            { label => N("Password (again)"), val => \$b->{password2}, hidden => 1 },
            { label => N("Restrict command line options"), val => \$b->{restricted}, type => "bool", text => N("restrict") },
		),
                if_(arch() !~ /alpha/ && arch() !~ /ppc/,
            { label => N("Create a bootdisk"), val => \$mkbootdisk, type => 'bool', advanced => 1 },
		),
            { label => N("Clean /tmp at each boot"), val => \$clean_tmp, type => 'bool', advanced => 1 },
            { label => N("Precise RAM size if needed (found %d MB)", availableRamMB()), val => \$memsize, advanced => 1 },
		if_(detect_devices::isLaptop(),
            { label => N("Enable multiple profiles"), val => \$profiles, type => 'bool', advanced => 1 },
		),
        ],
        complete => sub {
	    !$memsize || $memsize =~ /K$/ || $memsize =~ s/^(\d+)M?$/$1M/i or $in->ask_warn('', N("Give the ram size in MB")), return 1;
	    #-				     $security > 4 && length($b->{password}) < 6 and $in->ask_warn('', N("At this level of security, a password (and a good one) in lilo is requested")), return 1;
	    $b->{restricted} && !$b->{password} and $in->ask_warn('', N("Option ``Restrict command line options'' is of no use without a password")), return 1;
	    $b->{password} eq $b->{password2} or !$b->{restricted} or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]), return 1;
	    0;
	}) or return 0;
    } else {
	$b->{boot} = $partition_table::mac::bootstrap_part;	
	$in->ask_from_({ messages => N("Bootloader main options"),
			 interactive_help_id => 'setupYabootGeneral',
		       }, [
            { label => N("Bootloader to use"), val => \$b->{method}, list => [ keys %$method_choices ], format => sub { $method_choices->{$_[0]} } },
            { label => N("Init Message"), val => \$b->{'init-message'} },
            { label => N("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (grep { isAppleBootstrap($_) } @$fstab)) ], not_edit => !$::expert },
            { label => N("Open Firmware Delay"), val => \$b->{delay} },
            { label => N("Kernel Boot Timeout"), val => \$b->{timeout} },
            { label => N("Enable CD Boot?"), val => \$b->{enablecdboot}, type => "bool" },
            { label => N("Enable OF Boot?"), val => \$b->{enableofboot}, type => "bool" },
            { label => N("Default OS?"), val => \$b->{defaultos}, list => [ 'linux', 'macos', 'macosx', 'darwin' ] },
        ]) or return 0;				
    }

    #- remove bios mapping if the user changed the boot device
    delete $b->{bios} if $b->{boot} ne $prev_boot;

    if ($b->{method} eq 'grub') {
	$in->do_pkgs->ensure_is_installed('grub', "/usr/sbin/grub", 1) or return 0;
    }

    bootloader::set_profiles($b, $profiles);
    bootloader::add_append($b, "mem", $memsize);
    if ($previous_acpi_val) {
	my $s = $force_acpi ? 'on' : 'off';
	bootloader::add_append($b, acpi => $s) if $s ne $previous_acpi_val;
    }

    if ($prev_clean_tmp != $clean_tmp) {
	if ($clean_tmp && !fsedit::has_mntpoint('/tmp', $all_hds)) {
	    push @{$all_hds->{special}}, { device => 'none', mntpoint => '/tmp', type => 'tmpfs' };
	} else {
	    @{$all_hds->{special}} = grep { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special}};
	}
    }
    mkbootdisk($in, $b, $fstab) or return &setupBootloader__general if $mkbootdisk;

    1;
}

sub setupBootloader__entries {
    my ($in, $b, $all_hds, $fstab) = @_;

    my $Modify = sub {
	my ($e) = @_;
	my $default = my $old_default = $e->{label} eq $b->{default};

	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
{ label => N("Image"), val => \$e->{kernel_or_dev}, list => [ map { s/$::prefix//; $_ } glob_("$::prefix/boot/vmlinuz*") ], not_edit => 0 },
{ label => N("Root"), val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
{ label => N("Append"), val => \$e->{append} },
  if_(arch() !~ /ppc|ia64/,
{ label => N("Video mode"), val => \$e->{vga}, list => [ keys %bootloader::vga_modes ], format => sub { $bootloader::vga_modes{$_[0]} }, not_edit => !$::expert },
),
{ label => N("Initrd"), val => \$e->{initrd}, list => [ map { s/$::prefix//; $_ } glob_("$::prefix/boot/initrd*") ], not_edit => 0 },
{ label => N("Read-write"), val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..2] unless $::expert;
	} else {
	    @l = ( 
{ label => N("Root"), val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
if_(arch() !~ /sparc|ppc|ia64/,
{ label => N("Table"), val => \$e->{table}, list => [ '', map { "/dev/$_->{device}" } @{$all_hds->{hds}} ], not_edit => !$::expert },
{ label => N("Unsafe"), val => \$e->{unsafe}, type => 'bool' }
),
	    );
	    @l = $l[0] unless $::expert;
	}
	if (arch() !~ /ppc/) {
	    @l = (
		  { label => N("Label"), val => \$e->{label} },
		  @l,
		  { label => N("Default"), val => \$default, type => 'bool' },
		 );
	} else {
	    unshift @l, { label => N("Label"), val => \$e->{label}, list => ['macos', 'macosx', 'darwin'] };
	    if ($e->{type} eq "image") {
		@l = ({ label => N("Label"), val => \$e->{label} },
		$::expert ? @l[1..4] : (@l[1..2], { label => N("Append"), val => \$e->{append} }),
		if_($::expert, { label => N("Initrd-size"), val => \$e->{initrdsize}, list => [ '', '4096', '8192', '16384', '24576' ] }),
		if_($::expert, $l[5]),
		{ label => N("NoVideo"), val => \$e->{novideo}, type => 'bool' },
		{ label => N("Default"), val => \$default, type => 'bool' }
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
	bootloader::configure_entry($e); #- hack to make sure initrd file are built.
	1;
    };

    my $Add = sub {
	my @labels = map { $_->{label} } @{$b->{entries}};
	my ($e, $prefix);
	if ($in->ask_from_list_('', N("Which type of entry do you want to add?"),
				[ N_("Linux"), arch() =~ /sparc/ ? N_("Other OS (SunOS...)") : arch() =~ /ppc/ ? 
				  N_("Other OS (MacOS...)") : N_("Other OS (windows...)") ]
			       ) eq "Linux") {
	    $e = { type => 'image',
		   root => '/dev/' . fsedit::get_root($fstab)->{device}, #- assume a good default.
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
	push @{$b->{entries}}, $e;
	$e;
    };

    my $Remove = sub {
	my ($e) = @_;
	delete $b->{default} if $b->{default} eq $e->{label};
	@{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	1;
    };

    $in->ask_from__add_modify_remove('',
N("Here are the entries on your boot menu so far.
You can create additional entries or change the existing ones."), [ { 
        format => sub {
	    my ($e) = @_;
	    ref($e) ? 
	      "$e->{label} ($e->{kernel_or_dev})" . ($b->{default} eq $e->{label} && "  *") : 
		translate($e);
	}, list => $b->{entries},
    } ], Add => $Add, Modify => $Modify, Remove => $Remove);
}

my @etc_pass_fields = qw(name pw uid gid realname home shell);
sub unpack_passwd {
    my ($l) = @_;
    my %l; @l{@etc_pass_fields} = split ':', chomp_($l);
    \%l;
}
sub pack_passwd {
    my ($l) = @_;
    join(':', @$l{@etc_pass_fields}) . "\n";
}

sub get_autologin {
    my ($_o) = @_;
    my %l = getVarsFromSh("$::prefix/etc/sysconfig/autologin");
    my %desktop = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
    { autologin => text2bool($l{AUTOLOGIN}) && $l{USER}, desktop => $desktop{DESKTOP} };
}

sub set_autologin {
  my ($user, $desktop) = @_;

  if ($user) {
      my %l = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
      $l{DESKTOP} = $desktop;
      setVarsInSh("$::prefix/etc/sysconfig/desktop", \%l);
      log::l("cat $::prefix/etc/sysconfig/desktop ($desktop):\n", cat_("$::prefix/etc/sysconfig/desktop"));
  }
  setVarsInSh("$::prefix/etc/sysconfig/autologin",
	      { USER => $user, AUTOLOGIN => bool2yesno($user), EXEC => "/usr/X11R6/bin/startx" });
  log::l("cat $::prefix/etc/sysconfig/autologin ($user):\n", cat_("$::prefix/etc/sysconfig/autologin"));
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
    output $file,
      grep { !m|^(/usr)?/lib$| } #- no need to have /lib and /usr/lib in ld.so.conf
	uniq cat_($file), "/usr/X11R6/lib\n";
}

sub shells {
    my ($prefix) = @_;
    grep { -x "$prefix$_" } chomp_(cat_("$prefix/etc/shells"));
}

sub inspect {
    my ($part, $prefix, $rw) = @_;

    isMountableRW($part) or return;

    my $dir = $::isInstall ? "/tmp/inspect_tmp_dir" : "/root/.inspect_tmp_dir";

    if ($part->{isMounted}) {
	$dir = ($prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	eval { fs::mount($part->{device}, $dir, type2fs($part), !$rw) };
	$@ and return;
    }
    my $h = before_leaving {
	if (!$part->{isMounted} && $dir) {
	    fs::umount($dir);
	    unlink($dir)
	}
    };
    $h->{dir} = $dir;
    $h;
}

sub ask_users {
    my ($prefix, $in, $users, $security) = @_;

    my $u if 0; $u ||= {};

    my @icons = facesnames($prefix);

    my %high_security_groups = (
        xgrp => N("access to X programs"),
	rpm => N("access to rpm tools"),
	wheel => N("allow \"su\""),
	adm => N("access to administrative files"),
	ntools => N("access to network tools"),
	ctools => N("access to compilation tools"),
    );
    while (1) {
	$u->{password2} ||= $u->{password} ||= '';
	$u->{shell} ||= '/bin/bash';
	my $names = @$users ? N("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @$users)) : '';

	my %groups;
	my $verif = sub {
	    $u->{password} eq $u->{password2} or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]), return (1,2);
	    $security > 3 && length($u->{password}) < 6 and $in->ask_warn('', N("This password is too simple")), return (1,2);
	    $u->{name} or $in->ask_warn('', N("Please give a user name")), return (1,0);
	    $u->{name} =~ /^[a-z0-9_-]+$/ or $in->ask_warn('', N("The user name must contain only lower cased letters, numbers, `-' and `_'")), return (1,0);
	    length($u->{name}) <= 32 or $in->ask_warn('', N("The user name is too long")), return (1,0);
	    member($u->{name}, 'root', map { $_->{name} } @$users) and $in->ask_warn('', N("This user name has already been added")), return (1,0);
	    return 0;
	};
	my $ret = $in->ask_from_(
	    { title => N("Add user"),
	      messages => N("Enter a user\n%s", $names),
	      interactive_help_id => 'addUser',
	      focus_first => 1,
	      if_(!$::isInstall, ok => N("Done")),
	      cancel => N("Accept user"),
	      callbacks => {
	          focus_out => sub {
		      if ($_[0] eq 0) {
			  $u->{name} ||= lc first($u->{realname} =~ /([\w-]+)/);
		      }
		  },
	          complete => sub { $u->{name} ? &$verif : 0 },
                  canceled => $verif,
                  ok_disabled => sub { $security >= 4 && !@$users },
	    } }, [ 
	    { label => N("Real name"), val => \$u->{realname} },
	    { label => N("User name"), val => \$u->{name} },
            { label => N("Password"),val => \$u->{password}, hidden => 1 },
            { label => N("Password (again)"), val => \$u->{password2}, hidden => 1 },
            { label => N("Shell"), val => \$u->{shell}, list => [ shells($prefix) ], not_edit => !$::expert, advanced => 1 },
	      if_($security <= 3 && @icons,
	    { label => N("Icon"), val => \ ($u->{icon} ||= 'man'), list => \@icons, icon2f => sub { face2png($_[0], $prefix) }, format => \&translate },
	      ),
	      if_($security > 3,
		  map {
            { label => $_, val => \$groups{$_}, text => $high_security_groups{$_}, type => 'bool' }
		  } keys %high_security_groups,
	      ),
           ],
        );
	$u->{groups} = [ grep { $groups{$_} } keys %groups ];

	push @$users, $u if $u->{name};
	$u = {};
	$ret and return;
    }
}

sub autologin {
    my ($o, $in) = @_;

    my @wm = split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-l'));
    my @users = map { $_->{name} } @{$o->{users} || []};

    if (@wm > 1 && @users && !$o->{authentication}{NIS} && $o->{security} <= 2) {
	my $use_autologin = 1;

	$in->ask_from_(
		       { title => N("Autologin"),
			 messages => N("I can set up your computer to automatically log on one user.") },
		       [ { label => N("Do you want to use this feature?"), val => \$use_autologin, type => 'bool' },
			 { label => N("Choose the default user:"), val => \$o->{autologin}, list => \@users, disabled => sub { !$use_autologin } },
			 { label => N("Choose the window manager to run:"), val => \$o->{desktop}, list => \@wm, disabled => sub { !$use_autologin } } ]
		      );
	delete $o->{autologin} if !$use_autologin;
    } else {
	delete $o->{autologin};
    }
}

sub selectLanguage {
    my ($in, $lang, $langs_) = @_;
    my $langs = $langs_ || {};
    #- can't use images after install since the install theme is inverse video :/
    my $using_images = $in->isa('interactive::gtk') && $::isInstall;

    #- to create the default value, use the first location for that value :/
    $lang = first(lang::l2location($lang))."|$lang";

    my %name2l = map { lang::l2name($_) => $_ } lang::list_langs();
    my $listval2val = sub { $_[0] =~ /\|(.*)/; $1 };

    my @langs = map { my $l = $_; map { [ "$_|$l", $_, $l ] } lang::l2location($l) } lang::list_langs(exclude_non_installed => !$::isInstall);
    #- since gtk version will use images (function image2f) we need to sort differently
    my $sort_func = $using_images ? \&lang::l2transliterated : \&lang::l2name;
    @langs = map { $_->[0] } sort { $a->[1] cmp $b->[1] || $sort_func->($a->[2]) cmp $sort_func->($b->[2]) } @langs;

    $in->ask_from_(
	{ messages => N("Please choose a language to use."),
	  title => 'language choice',
	  interactive_help_id => 'selectLanguage',
	  if_($::isInstall, cancel => ''),
	  advanced_messages => formatAlaTeX(N("Mandrake Linux can support multiple languages. Select
the languages you would like to install. They will be available
when your installation is complete and you restart your system.")),
	  callbacks => { advanced => sub { $langs->{$listval2val->($lang)} = 1 } }
	},
	[ { val => \$lang, separator => '|', 
	    if_($using_images, image2f => sub { $name2l{$_[0]} =~ /^[a-z]/ ? ('', "langs/lang-$name2l{$_[0]}") : $_[0] }),
	    format => sub { $_[0] =~ /(.*\|)(.*)/; $1.lang::l2name($2) },
	    list => \@langs, sort => 0 },
	    if_($langs_, (map {
		{ val => \$langs->{$_->[0]}, type => 'bool', disabled => sub { $langs->{all} },
		  text => $_->[1], advanced => 1,
		  image => "langs/lang-$_->[0]",
		} 
	    } sort { $a->[1] cmp $b->[1] } map { [ $_, $sort_func->($_) ] } lang::list_langs()),
		{ val => \$langs->{all}, type => 'bool', text => N("All"), advanced => 1 },
		if_($::isInstall,
		    { val => \$in->{locale}{utf8}, type => 'bool', text => N("Use Unicode by default"), advanced => 1 }))
	]) or return;
    $langs->{$listval2val->($lang)} = 1;
    $langs->{$_} or delete $langs->{$_} foreach keys %$langs;  #- clean hash

    #- convert to the default locale for asked language
    $listval2val->($lang);
}

sub selectCountry {
    my ($o, $locale) = @_;

    my $country = $locale->{country};
    my @countries = lang::list_countries(exclude_non_installed => !$::isInstall);
    my @best = uniq map { if_((/^\Q$locale->{lang}/ || substr($_, 0, 2) eq substr($locale->{lang}, 0, 2))
			      && /.._(..)/, $1) } @lang::locales;
    @best == 1 and @best = ();

    my ($other, $ext_country);
    member($country, @best) or ($ext_country, $country) = ($country, $ext_country);
    $o->ask_from_(
		  { title => N("Country"), 
		    messages => N("Please choose your country."),
		    interactive_help_id => 'selectCountry',
		    advanced_messages => N("Here is the full list of available countries"),
		    advanced_label => N("More"),
		    advanced_state => $ext_country && scalar(@best),
		    callbacks => { changed => sub { $other = $_[0] == 1 } },
		  },
		  [ if_(@best, { val => \$country, type => 'list', format => \&lang::c2name,
				 list => \@best, sort => 1 }),
		    { val => \$ext_country, type => 'list', format => \&lang::c2name,
		      list => [ difference2(\@countries, \@best) ], advanced => @best }
		  ]) or return;

    $locale->{country} = $other || !@best ? $ext_country : $country;
}

sub write_passwd_user {
    my ($prefix, $u, $isMD5) = @_;

    $u->{pw} = $u->{password} ? &crypt($u->{password}, $isMD5) : $u->{pw} || '';
    $u->{shell} ||= '/bin/bash';

    substInFile {
	my $l = unpack_passwd($_);
	if ($l->{name} eq $u->{name}) {
	    add2hash_($u, $l);
	    $_ = pack_passwd($u);
	    $u = {};
	}
	if (eof && $u->{name}) {
	    $_ .= pack_passwd($u);
	}
    } "$prefix/etc/passwd";
}

sub set_login_serial_console {
    my ($port, $speed) = @_;

    my $line = "s$port:12345:respawn:/sbin/getty ttyS$port DT$speed ansi\n";
    substInFile { s/^s$port:.*//; $_ = $line if eof } "$::prefix/etc/inittab";
}

sub report_bug {
    my ($prefix, @other) = @_;

    sub header { "
********************************************************************************
* $_[0]
********************************************************************************";
    }

    join '', map { chomp; "$_\n" }
      header("lspci"), detect_devices::stringlist(),
      header("pci_devices"), cat_("/proc/bus/pci/devices"),
      header("fdisk"), arch() =~ /ppc/ ? `$ENV{LD_LOADER} pdisk -l` : `$ENV{LD_LOADER} fdisk -l`,
      header("scsi"), cat_("/proc/scsi/scsi"),
      header("lsmod"), cat_("/proc/modules"),
      header("cmdline"), cat_("/proc/cmdline"),
      header("pcmcia: stab"), cat_("$prefix/var/lib/pcmcia/stab") || cat_("$prefix/var/run/stab"),
      header("usb"), cat_("/proc/bus/usb/devices"),
      header("partitions"), cat_("/proc/partitions"),
      header("cpuinfo"), cat_("/proc/cpuinfo"),
      header("syslog"), cat_("/tmp/syslog") || cat_("$prefix/var/log/syslog"),
      header("ddcxinfos"), ddcxinfos(),
      header("stage1.log"), cat_("/tmp/stage1.log") || cat_("$prefix/root/drakx/stage1.log"),
      header("ddebug.log"), cat_("/tmp/ddebug.log") || cat_("$prefix/root/drakx/ddebug.log"),
      header("install.log"), cat_("$prefix/root/drakx/install.log"),
      header("fstab"), cat_("$prefix/etc/fstab"),
      header("modules.conf"), cat_("$prefix/etc/modules.conf"),
      header("lilo.conf"), cat_("$prefix/etc/lilo.conf"),
      header("menu.lst"), cat_("$prefix/boot/grub/menu.lst"),
      header("/etc/modules"), cat_("$prefix/etc/modules"),
      map_index { even($::i) ? header($_) : $_ } @other;
}

sub devfssymlinkf {
    my ($o_if, $of) = @_;
    my $if = $o_if->{device};

    my $devfs_if = $o_if->{devfs_device};
    $devfs_if ||= devices::to_devfs($if);
    $devfs_if ||= $if;

    #- example: $of is mouse, $if is usbmouse, $devfs_if is input/mouse0

    output_p("$::prefix/etc/devfs/conf.d/$of.conf", 
"REGISTER	^$devfs_if\$	CFUNCTION GLOBAL mksymlink $devfs_if $of
UNREGISTER	^$devfs_if\$	CFUNCTION GLOBAL unlink $of
");

    output_p("$::prefix/etc/devfs/conf.d/$if.conf", 
"REGISTER	^$devfs_if\$	CFUNCTION GLOBAL mksymlink $devfs_if $if
UNREGISTER	^$devfs_if\$	CFUNCTION GLOBAL unlink $if
") if $devfs_if ne $if;

    #- when creating a symlink on the system, use devfs name if devfs is mounted
    symlinkf($devfs_if, "$::prefix/dev/$if") if $devfs_if ne $if && detect_devices::dev_is_devfs();
    symlinkf($if, "$::prefix/dev/$of");
}
sub devfs_rawdevice {
    my ($o_if, $of) = @_;

    my $devfs_if = $o_if->{devfs_device};
    $devfs_if ||= devices::to_devfs($o_if->{device});
    $devfs_if ||= $o_if->{device};

    output_p("$::prefix/etc/devfs/conf.d/$of.conf", 
"REGISTER	^$devfs_if\$	EXECUTE /etc/dynamic/scripts/rawdevice.script add /dev/$devfs_if /dev/$of
UNREGISTER	^$devfs_if\$	EXECUTE /etc/dynamic/scripts/rawdevice.script del /dev/$of
");
}


sub fileshare_config {
    my ($in, $type) = @_; #- $type is 'nfs', 'smb' or ''

    my $file = '/etc/security/fileshare.conf';
    my %conf = getVarsFromSh($file);

    my @l = (N_("No sharing"), N_("Allow all users"), N_("Custom"));
    my $restrict = exists $conf{RESTRICT} ? text2bool($conf{RESTRICT}) : 1;

    if ($restrict) {
	#- verify we can export in $type
	my %type2file = (nfs => [ '/etc/init.d/nfs', 'nfs-utils' ], smb => [ '/etc/init.d/smb', 'samba' ]);
	my @wanted = $type ? $type : keys %type2file;
	my @have = grep { -e $type2file{$_}[0] } @wanted;
	if (!@have) {
	    if (@wanted == 1) {
		$in->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $type2file{$wanted[0]}[1]), 1) or return;
	    } else {
		my $wanted = $in->ask_many_from_list('', N("You can export using NFS or Samba. Please select which you'd like to use."),
						  { list => \@wanted }) or return;
		@wanted = @$wanted or return;
	    }
	    $in->do_pkgs->install(map { $type2file{$_}[1] } @wanted);
	    @have = grep { -e $type2file{$_}[0] } @wanted;
	}
	if (!@have) {
	    $in->ask_warn('', N("Mandatory package %s is missing", $wanted[0]));
	    return;
	}
    }

    my $r = $in->ask_from_list_('fileshare',
N("Would you like to allow users to share some of their directories?
Allowing this will permit users to simply click on \"Share\" in konqueror and nautilus.

\"Custom\" permit a per-user granularity.
"),
				\@l, $l[$restrict ? 0 : 1]) or return;
    $restrict = $r ne $l[1];
    $conf{RESTRICT} = bool2yesno($restrict);

    setVarsInSh($file, \%conf);
    if ($r eq $l[2]) {
	# custom
	if ($in->ask_from_no_check(
	{
	 -e '/usr/bin/userdrake' ? (ok => N("Launch userdrake"), cancel => N("Cancel")) : (cancel => ''),
	 messages =>
N("The per-user sharing uses the group \"fileshare\". 
You can use userdrake to add a user to this group.")
	}, [])) {
	    if (!fork()) { exec "userdrake" or c::_exit(0) }
	}
    }
}

sub ddcxinfos {
    return if $::noauto;

    my @l;
    run_program::raw({ timeout => 20 }, 'ddcxinfos', '>', \@l);
    if ($::isInstall && -e "/tmp/ddcxinfos") {
	my @l_old = cat_("/tmp/ddcxinfos");
	if (@l < @l_old) {
	    log::l("new ddcxinfos is worse, keeping the previous one");
	    @l = @l_old;
	} elsif (@l > @l_old) {
	    log::l("new ddcxinfos is better, dropping the previous one");
	}
    }
    output("/tmp/ddcxinfos", @l) if $::isInstall;
    @l;
}

sub running_window_manager {
    my @window_managers = qw(kwin gnome-session icewm wmaker afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce blackbox sawfish olvwm);

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
	'gnome-session' => "gnome-session-save -kill",
	'icewm' => "killall -QUIT icewm",
	'wmaker' => "killall -USR1 wmaker",
    );
    my $cmd = $h{$wm} or return;
    $cmd = "su $ENV{USER} -c '$cmd'" if $wm eq 'kwin' && $> == 0;
    system($cmd);
    1;
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

sub config_dvd {
    my ($prefix, $have_devfsd) = @_;

    #- can't have both a devfs and a non-devfs config
    #- the /etc/sysconfig/rawdevices solution gives errors with devfs

    my @dvds = grep { detect_devices::isDvdDrive($_) } detect_devices::cdroms__faking_ide_scsi() or return;

    log::l("configuring DVD: " . join(" ", map { $_->{device} } @dvds));
    #- create /dev/dvd symlink
    each_index {
	devfssymlinkf($_, 'dvd' . ($::i ? $::i + 1 : ''));
	devfs_rawdevice($_, 'rdvd' . ($::i ? $::i + 1 : '')) if $have_devfsd;
    } @dvds;

    if (!$have_devfsd) {
	my $raw_dev = alloc_raw_device($prefix, 'dvd');
	symlink($raw_dev, "$prefix/dev/rdvd");
    }
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

1;
