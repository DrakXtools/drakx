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

sub drakx_version() { 
    $::move ? sprintf "DrakX-move v%s", cat_('/usr/bin/stage2/move.pm') =~ /move\.pm,v (\S+ \S+ \S+)/
            : sprintf "DrakX v%s built %s", $::testing ? ('TEST', scalar gmtime()) : (split('/', cat_("$ENV{SHARE_PATH}/VERSION")))[2,3];
}

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

sub allocUsers {
    my ($users) = @_;
    my @m = my @l = facesnames();
    foreach (grep { !$_->{icon} || $_->{icon} eq "automagic" } @$users) {
	$_->{auto_icon} = splice(@m, rand(@m), 1); #- known biased (see cookbook for better)
	log::l("auto_icon is $_->{auto_icon}");
	@m = @l unless @m;
    }
}

sub addUsers {
    my ($users) = @_;

    allocUsers($users);
    foreach my $u (@$users) {
	run_program::rooted($::prefix, "usermod", "-G", join(",", @{$u->{groups}}), $u->{name}) if !is_empty_array_ref($u->{groups});
	addKdmIcon($u->{name}, delete $u->{auto_icon} || $u->{icon});
    }
}

sub crypt {
    my ($password, $md5) = @_;
    crypt($password, $md5 ? '$1$' . salt(8) : salt(2));
}
sub enableShadow() {
    run_program::rooted($::prefix, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($::prefix, "grpconv") or log::l("grpconv failed");
}

sub hdInstallPath() {
    my $tail = first(readlink("/tmp/image") =~ m|^/tmp/hdimage/?(.*)|);
    my $head = first(readlink("/tmp/hdimage") =~ m|$::prefix(.*)|);
    defined $tail && ($head ? "$head/$tail" : "/mnt/hd/$tail");
}

sub setupBootloader {
    my ($in, $b, $all_hds, $fstab, $security) = @_;
    my $hds = $all_hds->{hds};

    require bootloader;
  general:
    {
	local $::Wizard_no_previous = 1 if $::isStandalone;
	setupBootloader__general($in, $b, $all_hds, $fstab, $security) or return 0;
    }
    setupBootloader__boot_bios_drive($in, $b, $hds) or goto general;
    {
	local $::Wizard_finished = 1 if $::isStandalone;
	setupBootloader__entries($in, $b, $all_hds, $fstab) or goto general;
    }

    #- somewhere should bootloader really installed ?
    $::isStandalone and my $_w = $in->wait_message(N("Please wait"), N("Bootloader installation in progress"));

    eval { run_program::rooted($::prefix, 'lilo', '-u') } if $::isInstall && !$::o->{isUpgrade} && -e "$::prefix/etc/lilo.conf" && glob("$::prefix/boot/boot.*");

    bootloader::install($b, $hds);
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

	my $default = find { $_->[1] eq $b->{boot} } @l;
	$in->ask_from_({ title => N("LILO/grub Installation"),
			 messages => N("Where do you want to install the bootloader?"),
			 interactive_help_id => 'setupBootloaderBeginner',
		       },
		      [ { val => \$default, list => \@l, format => sub { $_[0][0] }, type => 'list' } ]);
	my $new_boot = $default->[1] or return;

	#- remove bios mapping if the user changed the boot device
	delete $b->{bios} if $new_boot ne $b->{boot};
	$b->{boot} = $new_boot;
    }
    1;
}

sub setupBootloader__general {
    my ($in, $b, $all_hds, $fstab, $security) = @_;

    my @method_choices = bootloader::method_choices($fstab);
    my $profiles = bootloader::has_profiles($b);
    my $prev_force_acpi = my $force_acpi = bootloader::get_append($b, 'acpi') !~ /off|ht/;
    my $prev_force_noapic = my $force_noapic = bootloader::get_append($b, 'noapic');
    my $prev_force_nolapic = my $force_nolapic = bootloader::get_append($b, 'nolapic');
    my $memsize = bootloader::get_append($b, 'mem');
    my $prev_clean_tmp = my $clean_tmp = any { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special} ||= []};
    my $prev_boot = $b->{boot};

    $b->{password2} ||= $b->{password} ||= '';
    $::Wizard_title = N("Boot Style Configuration");
    if (arch() !~ /ppc/) {
	$in->ask_from_({ messages => N("Bootloader main options"),
			 interactive_help_id => 'setupBootloader',
			 callbacks => {
			     complete => sub {
				 !$memsize || $memsize =~ /^\d+K$/ || $memsize =~ s/^(\d+)M?$/$1M/i or $in->ask_warn('', N("Give the ram size in MB")), return 1;
				 #- $security > 4 && length($b->{password}) < 6 and $in->ask_warn('', N("At this level of security, a password (and a good one) in lilo is requested")), return 1;
				 $b->{restricted} && !$b->{password} and $in->ask_warn('', N("Option ``Restrict command line options'' is of no use without a password")), return 1;
				 $b->{password} eq $b->{password2} or !$b->{restricted} or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]), return 1;
				 0;
			     },
			 },
		       }, [
            { label => N("Bootloader to use"), val => \$b->{method}, list => \@method_choices, format => \&bootloader::method2text },
                if_(arch() !~ /ia64/,
            { label => N("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (@{$all_hds->{hds}}, grep { !isFat_or_NTFS($_) } @$fstab)), detect_devices::floppies_dev() ], not_edit => !$::expert },
		),
            { label => N("Delay before booting default image"), val => \$b->{timeout} },
            { text => N("Enable ACPI"), val => \$force_acpi, type => 'bool' },
		if_(!$force_nolapic,
            { text => N("Force no APIC"), val => \$force_noapic, type => 'bool' }, 
	        ),
            { text => N("Force No Local APIC"), val => \$force_nolapic, type => 'bool' },
		if_($security >= 4 || $b->{password} || $b->{restricted},
            { label => N("Password"), val => \$b->{password}, hidden => 1 },
            { label => N("Password (again)"), val => \$b->{password2}, hidden => 1 },
            { text => N("Restrict command line options"), val => \$b->{restricted}, type => "bool", text => N("restrict") },
		),
            { text => N("Clean /tmp at each boot"), val => \$clean_tmp, type => 'bool', advanced => 1 },
            { label => N("Precise RAM size if needed (found %d MB)", availableRamMB()), val => \$memsize, advanced => 1 },
		if_(detect_devices::isLaptop(),
            { text => N("Enable multiple profiles"), val => \$profiles, type => 'bool', advanced => 1 },
		),
        ]) or return 0;
    } else {
	$b->{boot} = $partition_table::mac::bootstrap_part;	
	$in->ask_from_({ messages => N("Bootloader main options"),
			 interactive_help_id => 'setupYabootGeneral',
		       }, [
            { label => N("Bootloader to use"), val => \$b->{method}, list => \@method_choices, format => \&bootloader::method2text },
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
    bootloader::set_append($b, "mem", $memsize || 0);
    if ($prev_force_acpi != $force_acpi) {
	bootloader::set_append($b, acpi => ($force_acpi ? '' : 'ht'));
    }
    if ($prev_force_noapic != $force_noapic) {
	($force_noapic ? \&bootloader::set_append : \&bootloader::remove_append_simple)->($b, 'noapic');
    }
    if ($prev_force_nolapic != $force_nolapic) {
	($force_nolapic ? \&bootloader::set_append : \&bootloader::remove_append_simple)->($b, 'nolapic');
    }

    if ($prev_clean_tmp != $clean_tmp) {
	if ($clean_tmp && !fsedit::has_mntpoint('/tmp', $all_hds)) {
	    push @{$all_hds->{special}}, { device => 'none', mntpoint => '/tmp', pt_type => 'tmpfs' };
	} else {
	    @{$all_hds->{special}} = grep { $_->{mntpoint} ne '/tmp' } @{$all_hds->{special}};
	}
    }
    1;
}

sub setupBootloader__entries {
    my ($in, $b, $_all_hds, $fstab) = @_;

    require Xconfig::resolution_and_depth;

    my $Modify = sub {
	my ($e) = @_;
	my $default = my $old_default = $e->{label} eq $b->{default};
	my $vga = Xconfig::resolution_and_depth::from_bios($e->{vga});

	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
{ label => N("Image"), val => \$e->{kernel_or_dev}, list => [ map { "/boot/$_" } bootloader::installed_vmlinuz() ], not_edit => 0 },
{ label => N("Root"), val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
{ label => N("Append"), val => \$e->{append} },
  if_(arch() !~ /ppc|ia64/,
{ label => N("Video mode"), val => \$vga, list => [ '', Xconfig::resolution_and_depth::bios_vga_modes() ], format => \&Xconfig::resolution_and_depth::to_string, advanced => 1 },
),
{ label => N("Initrd"), val => \$e->{initrd}, list => [ map { if_(/^initrd/, "/boot/$_") } all("$::prefix/boot") ], not_edit => 0, advanced => 1 },
	    );
	} else {
	    @l = ( 
{ label => N("Root"), val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab, detect_devices::floppies() ], not_edit => !$::expert },
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
		$::expert ? @l[1..4] : (@l[1..2], { label => N("Append"), val => \$e->{append} }),
		if_($::expert, { label => N("Initrd-size"), val => \$e->{initrdsize}, list => [ '', '4096', '8192', '16384', '24576' ] }),
		if_($::expert, $l[5]),
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
	$e->{vga} = ref($vga) ? $vga->{bios} : $vga;
	bootloader::configure_entry($e); #- hack to make sure initrd file are built.
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
	      "$e->{label} ($e->{kernel_or_dev})" . ($b->{default} eq $e->{label} && "  *") : 
		translate($e);
	}, list => $b->{entries},
    } ], Add => $Add, Modify => $Modify, Remove => $Remove)) {
	1;
    } else {
	@{$b->{entries}} = @prev_entries;
	'';
    }
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

sub get_autologin() {
    my %desktop = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
    my $desktop = $desktop{DESKTOP} || 'KDE';
    my $autologin = do {
	if (($desktop{DISPLAYMANAGER} || $desktop) eq 'GNOME') {
	    my %conf = read_gnomekderc("$::prefix/etc/X11/gdm/gdm.conf", 'daemon');
	    text2bool($conf{AutomaticLoginEnable}) && $conf{AutomaticLogin};
	} else { # KDM / MdkKDM
	    my %conf = read_gnomekderc("$::prefix/usr/share/config/kdm/kdmrc", 'X-:0-Core');
	    text2bool($conf{AutoLoginEnable}) && $conf{AutoLoginUser};
	}
    };
    { autologin => $autologin, desktop => $desktop };
}

sub set_autologin {
    my ($user, $desktop) = @_;
    my $autologin = bool2text($user);

    #- Configure KDM / MDKKDM
    eval { update_gnomekderc("$::prefix/usr/share/config/kdm/kdmrc", 'X-:0-Core' => (
	AutoLoginEnable => $autologin,
	AutoLoginUser => $user,
    )) };

    #- Configure GDM
    eval { update_gnomekderc("$::prefix/etc/X11/gdm/gdm.conf", daemon => (
	AutomaticLoginEnable => $autologin,
	AutomaticLogin => $user,
    )) };
  
    if ($user) {
	my %l = getVarsFromSh("$::prefix/etc/sysconfig/desktop");
	$l{DESKTOP} = $desktop;
	setVarsInSh("$::prefix/etc/sysconfig/desktop", \%l);
	log::l("cat $::prefix/etc/sysconfig/desktop ($desktop):\n", cat_("$::prefix/etc/sysconfig/desktop"));
    }
    my $xdm_autologin_cfg = "$::prefix/etc/sysconfig/autologin";
    if (member($desktop, 'KDE', 'GNOME')) {
	unlink $xdm_autologin_cfg;
    } else {
	setVarsInShMode($xdm_autologin_cfg, 0644,
			{ USER => $user, AUTOLOGIN => bool2yesno($user), EXEC => '/usr/X11R6/bin/startx.autologin' });
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
    @l = grep { !m|^(/usr)?/lib(64)?$| } @l; #- no need to have /lib and /usr/lib in ld.so.conf
    push @l, '/usr/X11R6/lib', if_(arch() =~ /x86_64/, '/usr/X11R6/lib64');
    push @l, grep { -d "$::prefix$_" } '/usr/lib/qt3/lib', if_(arch() =~ /x86_64/, '/usr/lib/qt3/lib64'); #- needed for upgrade where package renaming can cause this to disappear
    output($file, map { "$_\n" } uniq(@l));
}

sub shells() {
    grep { -x "$::prefix$_" } chomp_(cat_("$::prefix/etc/shells"));
}

sub inspect {
    my ($part, $o_prefix, $b_rw) = @_;

    isMountableRW($part) or return;

    my $dir = $::isInstall ? "/tmp/inspect_tmp_dir" : "/root/.inspect_tmp_dir";

    if ($part->{isMounted}) {
	$dir = ($o_prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	eval { fs::mount($part->{device}, $dir, type2fs($part, 'skip'), !$b_rw) };
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

sub ask_user_one {
    my ($in, $users, $security, $u, %options) = @_;

    my @icons = facesnames();

    my %high_security_groups = (
        xgrp => N("access to X programs"),
	rpm => N("access to rpm tools"),
	wheel => N("allow \"su\""),
	adm => N("access to administrative files"),
	ntools => N("access to network tools"),
	ctools => N("access to compilation tools"),
    );

    $u->{password2} ||= $u->{password} ||= '';
    $u->{shell} ||= '/bin/bash';
    my $names = @$users ? N("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @$users)) : '';
    
    my %groups;
    my $verif = sub {
        $u->{password} eq $u->{password2} or $in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]), return 1,2;
        $security > 3 && length($u->{password}) < 6 and $in->ask_warn('', N("This password is too simple")), return 1,2;
	    $u->{name} or $in->ask_warn('', N("Please give a user name")), return 1,0;
        $u->{name} =~ /^[a-z]+?[a-z0-9_-]*?$/ or $in->ask_warn('', N("The user name must contain only lower cased letters, numbers, `-' and `_'")), return 1,0;
        length($u->{name}) <= 32 or $in->ask_warn('', N("The user name is too long")), return 1,0;
        member($u->{name}, 'root', map { $_->{name} } @$users) and $in->ask_warn('', N("This user name has already been added")), return 1,0;
        return 0;
    };
    my $ret = $in->ask_from_(
        { title => N("Add user"),
          messages => N("Enter a user\n%s", $options{additional_msg} || $names),
          interactive_help_id => 'addUser',
          focus_first => 1,
          if_(!$::isInstall, ok => N("Done")),
          cancel => $options{noaccept} ? '' : N("Accept user"),
          callbacks => {
	          focus_out => sub {
		      if ($_[0] eq '0') {
			  $u->{name} ||= lc first($u->{realname} =~ /([\w-]+)/);
		      }
		  },
	          complete => sub { $u->{name} ? &$verif : 0 },
                  canceled => $verif,
                  ok_disabled => sub { $security >= 4 && !@$users || $options{needauser} && !$u->{name} },
	  } }, [ 
	  { label => N("Real name"), val => \$u->{realname} },
          { label => N("User name"), val => \$u->{name} },
          { label => N("Password"),val => \$u->{password}, hidden => 1 },
          { label => N("Password (again)"), val => \$u->{password2}, hidden => 1 },
          { label => N("Shell"), val => \$u->{shell}, list => [ shells() ], not_edit => !$::expert, advanced => 1 },
	    if_($security <= 3 && !$options{noicons} && @icons,
	  { label => N("Icon"), val => \ ($u->{icon} ||= 'default'), list => \@icons, icon2f => \&face2png, format => \&translate },
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

    return $ret;
}

sub ask_users {
    my ($in, $users, $security, $suggested_names) = @_;

    while (1) {
	my $u = {};
	$u->{name} = shift @$suggested_names;
        ask_user_one($in, $users, $security, $u) and return;
    }
}

sub sessions() {
    split(' ', run_program::rooted_get_stdout($::prefix, '/usr/sbin/chksession', '-l'));
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
    my ($in, $lang, $o_langs_) = @_;

    my $common = { messages => N("Please choose a language to use."),
		   title => 'language choice',
		   interactive_help_id => 'selectLanguage' };

    if ($::isInstall) {
	my $langs = $o_langs_ || {};
	my $using_images = $in->isa('interactive::gtk') && !$in->{vga16};

	#- to create the default value, use the first location for that value :/
	$lang = if_(!$::move, first(lang::l2location($lang)).'|').$lang;
	
	my %name2l = map { lang::l2name($_) => $_ } lang::list_langs();
	my $listval2val = sub { $_[0] =~ /\|(.*)/ ? $1 : $_[0] };

	my @langs = map { my $l = $_; uniq_ { $_->[0] } map { [ $::move ? $l : "$_|$l", $_, $l ] } lang::l2location($l) } lang::list_langs();
	#- since gtk version will use images (function image2f) we need to sort differently
	my $sort_func = $using_images ? \&lang::l2transliterated : \&lang::l2name;
	@langs = map { $_->[0] } sort { $sort_func->($a->[2]) cmp $sort_func->($b->[2]) } @langs;

        my $last_utf8 = $in->{locale}{utf8};
	add2hash($common, { cancel => '',
			    advanced_messages => formatAlaTeX(N("Mandrakelinux can support multiple languages. Select
the languages you would like to install. They will be available
when your installation is complete and you restart your system.")),
			    callbacks => { advanced => sub { $langs->{$listval2val->($lang)} = 1 },
                                           changed => sub {
                                               if ($last_utf8 == $in->{locale}{utf8}) {
                                                   $last_utf8 = $in->{locale}{utf8} = lang::utf8_should_be_needed({ lang => $listval2val->($lang), langs => $langs });
                                               } else {
                                                   $last_utf8 = -1;  #- disable auto utf8 once touched
                                               }
                                           } } });
			    
	$in->ask_from_($common,
	[ { val => \$lang, separator => '|', 
	    if_($using_images, image2f => sub { $name2l{$_[0]} =~ /^[a-z]/ ? ('', "langs/lang-$name2l{$_[0]}") : $_[0] }),
	    format => sub { $_[0] =~ /(.*\|)(.*)/ ? $1.lang::l2name($2) : lang::l2name($_[0]) },
	    list => \@langs, sort => 0 },
	    if_($o_langs_ && !$::move,
                { val => \$in->{locale}{utf8}, type => 'bool', text => N("Use Unicode by default"), advanced => 1 },
		{ val => \$langs->{all}, type => 'bool', text => N("All languages"), advanced => 1 },
	        map {
		  { val => \$langs->{$_->[0]}, type => 'bool', disabled => sub { $langs->{all} },
		    text => $_->[1], advanced => 1,
		    image => "langs/lang-$_->[0]",
		  } 
	      } sort { $a->[1] cmp $b->[1] } map { [ $_, $sort_func->($_) ] } lang::list_langs())
	]) or return;
	$langs->{$listval2val->($lang)} = 1;
	$langs->{$_} or delete $langs->{$_} foreach keys %$langs;  #- clean hash
	
	#- convert to the default locale for asked language
	$listval2val->($lang);

    } else {
	my @langs = sort { lang::l2name($a) cmp lang::l2name($b) } lang::list_langs(exclude_non_installed => 1);
	die 'one lang only' if @langs == 1;
	$in->ask_from_($common,
		       [ { val => \$lang, type => 'list',
			   format => sub { lang::l2name($_[0]) }, list => \@langs } ]) or return;
	$lang;
    }
}

sub selectCountry {
    my ($o, $locale) = @_;

    my $country = $locale->{country};
    my @countries = lang::list_countries(exclude_non_installed => !$::isInstall);
    my @best = uniq grep {
	my $h = lang::analyse_locale_name($_);
	if_($h->{main} eq lang::locale_to_main_locale($locale->{lang}) && $h->{country},
	    $h->{country});
    } @lang::locales;
    @best == 1 and @best = ();

    my ($other, $ext_country);
    member($country, @best) or ($ext_country, $country) = ($country, $ext_country);
    $o->ask_from_(
		  { title => N("Country / Region"), 
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
		      list => [ difference2(\@countries, \@best) ], advanced => scalar(@best) }
		  ]) or return;

    $locale->{country} = $other || !@best ? $ext_country : $country;
}

sub write_passwd_user {
    my ($u, $isMD5) = @_;

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
    } "$::prefix/etc/passwd";
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
      header("dmidecode"), `$ENV{LD_LOADER} dmidecode`,
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
      header("XF86Config"), cat_("$prefix/etc/X11/XF86Config"),
      header("XF86Config-4"), cat_("$prefix/etc/X11/XF86Config-4"),
      header("/etc/modules"), cat_("$prefix/etc/modules"),
      header("sysconfig/i18n"), cat_("$prefix/etc/sysconfig/i18n"),
      map_index { even($::i) ? header($_) : $_ } @other;
}

sub devfssymlinkf {
    my ($if_struct, $of) = @_;
    my $if = $if_struct->{device};

    my $devfs_if = $if_struct->{devfs_device};
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
") if $devfs_if ne $if && $if !~ /^hd[a-z]/ && $if !~ /^sr/ && $if !~ /^sd[a-z]/;

    #- when creating a symlink on the system, use devfs name if devfs is mounted
    symlinkf($devfs_if, "$::prefix/dev/$if") if $devfs_if ne $if && detect_devices::dev_is_devfs();
    symlinkf($if, "$::prefix/dev/$of");
}
sub devfs_rawdevice {
    my ($if_struct, $of) = @_;

    my $devfs_if = $if_struct->{devfs_device};
    $devfs_if ||= devices::to_devfs($if_struct->{device});
    $devfs_if ||= $if_struct->{device};

    output_p("$::prefix/etc/devfs/conf.d/$of.conf", 
"REGISTER	^$devfs_if\$	EXECUTE /etc/dynamic/scripts/rawdevice.script add /dev/$devfs_if /dev/$of
UNREGISTER	^$devfs_if\$	EXECUTE /etc/dynamic/scripts/rawdevice.script del /dev/$of
");
}

sub fix_broken_alternatives() {
    #- fix bad update-alternatives that may occurs after upgrade (and sometimes for install too).
    -d "$::prefix/etc/alternatives" or return;

    foreach (all("$::prefix/etc/alternatives")) {
	next if run_program::rooted($::prefix, 'test', '-e', "/etc/alternatives/$_");
	log::l("fixing broken alternative $_");
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
				\@l, $l[$restrict ? 0 : 1]) or return;
    $restrict = $r ne $l[1];
    my $custom = $r eq $l[2];
    if ($r ne $l[0]) {
	require services;
	my %types = (
	    nfs => [ 'nfs-utils', 'nfs',
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
	    $in->ask_from('', N("You can export using NFS or SMB. Please select which you would like to use."),
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
    }
    $conf{RESTRICT} = bool2yesno($restrict);
    setVarsInSh($file, \%conf);

    if ($custom) {
	run_program::rooted($::prefix, 'groupadd', '-r', 'fileshare');
	if ($in->ask_from_no_check(
	{
	 -e '/usr/sbin/userdrake' ? (ok => N("Launch userdrake"), cancel => N("Cancel")) : (cancel => ''),
	 messages =>
N("The per-user sharing uses the group \"fileshare\". 
You can use userdrake to add a user to this group.")
	}, [])) {
	    run_program::run('userdrake');
	}
    }
}

sub ddcxinfos() {
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

sub running_window_manager() {
    my @window_managers = qw(kwin gnome-session icewm wmaker afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce blackbox sawfish olvwm fluxbox);

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
	'wmaker' => "killall -USR1 wmaker",
    );
    my $cmd = $h{$wm} or return;
    if ($wm eq 'gnome-session') {
	#- NB: consolehelper doesn't destroy $HOME whereas kdesu does
	#- for gnome, we use consolehelper, so below works
	$ENV{ICEAUTHORITY} ||= "$ENV{HOME}/.ICEauthority";
    } elsif ($wm eq 'kwin' && $> == 0) {
	#- we can't use dcop when we are root
	$cmd = "su $ENV{USER} -c '$cmd'";
    }
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

    my @dvds = grep { detect_devices::isDvdDrive($_) } detect_devices::cdroms() or return;

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
