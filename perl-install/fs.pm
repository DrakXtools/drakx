package fs; # $Id$

use diagnostics;
use strict;

use common;
use log;
use devices;
use fs::type;
use fs::get;
use fs::format;
use fs::mount_options;
use fs::loopback;
use run_program;
use detect_devices;
use modules;
use fsedit;


sub read_fstab {
    my ($prefix, $file, @reading_options) = @_;

    if (member('keep_default', @reading_options)) {
	push @reading_options, 'freq_passno', 'keep_devfs_name', 'keep_device_LABEL';
    }

    my %comments;
    my $comment;
    my @l = grep {
	if (/^Filename\s*Type\s*Size/) {
	    0; #- when reading /proc/swaps
	} elsif (/^\s*#/) {
	    $comment .= chomp_($_) . "\n";
	    0;
	} else {
	    $comments{$_} = $comment if $comment;
	    $comment = '';
	    1;
	}
    } cat_("$prefix$file");

    #- attach comments at the end of fstab to the previous line
    $comments{$l[-1]} = $comment if $comment;

    map {
	my ($dev, $mntpoint, $fs_type, $options, $freq, $passno) = split;
	my $comment = $comments{$_};

	$options = 'defaults' if $options eq 'rw'; # clean-up for mtab read

	if ($fs_type eq 'supermount') {
	    # normalize this bloody supermount
	    $options = join(",", 'supermount', grep {
		if (/fs=(.*)/) {
		    $fs_type = $1;
		    0;
		} elsif (/dev=(.*)/) {
		    $dev = $1;
		    0;
		} elsif ($_ eq '--') {
		    0;
		} else {
		    1;
		}
	    } split(',', $options));
	} elsif ($fs_type eq 'smb') {
	    # prefering type "smbfs" over "smb"
	    $fs_type = 'smbfs';
	}
	s/\\040/ /g foreach $mntpoint, $dev, $options;

	my $h = { 
		 mntpoint => $mntpoint, fs_type => $fs_type,
		 options => $options, comment => $comment,
		 if_(member('keep_freq_passno', @reading_options), freq => $freq, passno => $passno),
		};

	put_in_hash($h, subpart_from_wild_device_name($dev));

	if ($h->{device_LABEL} && member('keep_device_LABEL', @reading_options)) {
	    $h->{prefer_device_LABEL} = 1;
        } elsif ($h->{devfs_device} && member('keep_devfs_name', @reading_options)) {
	    $h->{prefer_devfs_name} = 1;
	}

	if ($h->{options} =~ /credentials=/ && !member('verbatim_credentials', @reading_options)) {
	    require network::smb;
	    #- remove credentials=file with username=foo,password=bar,domain=zoo
	    #- the other way is done in fstab_to_string
	    my ($options, $unknown) = fs::mount_options::unpack($h);
	    my $file = delete $options->{'credentials='};
	    my $credentials = network::smb::read_credentials_raw($file);
	    if ($credentials->{username}) {
		$options->{"$_="} = $credentials->{$_} foreach qw(username password domain);
		fs::mount_options::pack($h, $options, $unknown);
	    }
	}

	$h;
    } @l;
}

sub merge_fstabs {
    my ($loose, $fstab, @l) = @_;

    foreach my $p (@$fstab) {
	my ($l1, $l2) = partition { fsedit::is_same_hd($_, $p) } @l;
	my ($p2) = @$l1 or next;
	@l = @$l2;

	$p->{mntpoint} = $p2->{mntpoint} if delete $p->{unsafeMntpoint};

	if (!$loose) {
	    $p->{fs_type} = $p2->{fs_type} if $p2->{fs_type};
	    $p->{options} = $p2->{options} if $p2->{options};
	    add2hash($p, $p2);
	} else {
	    $p->{isMounted} ||= $p2->{isMounted};
	}
	$p->{device_alias} ||= $p2->{device_alias} || $p2->{device} if $p->{device} ne $p2->{device} && $p2->{device} !~ m|/|;

	$p->{fs_type} && $p2->{fs_type} && $p->{fs_type} ne $p2->{fs_type}
	  && $p->{fs_type} ne 'auto' && $p2->{fs_type} ne 'auto' and
	    log::l("err, fstab and partition table do not agree for $p->{device} type: $p->{fs_type} vs $p2->{fs_type}");
    }
    @l;
}

sub analyze_wild_device_name {
    my ($dev) = @_;

    if ($dev =~ m!^/u?dev/(.*)!) {
	'dev', $dev;
    } elsif ($dev !~ m!^/! && (-e "/dev/$dev" || -e "$::prefix/dev/$dev")) {
	'dev', "/dev/$dev";
    } elsif ($dev =~ /^LABEL=(.*)/) {
	'label', $1;
    } elsif ($dev eq 'none' || $dev eq 'rootfs') {
	'virtual';
    } elsif ($dev =~ m!^(\S+):/\w!) {
	'nfs';
    } elsif ($dev =~ m!^//\w!) {
	'smb';
    } elsif ($dev =~ m!^http://!) {
	'dav';
    }
}

sub subpart_from_wild_device_name {
    my ($dev) = @_;

    my $part = { device => $dev, faked_device => 1 }; #- default

    if (my ($kind, $val) = analyze_wild_device_name($dev)) {
	if ($kind eq 'label') {	    
	    $part->{device_LABEL} = $val;
	} elsif ($kind eq 'dev') {
	    my %part = (faked_device => 0);
	    if (my $rdev = (stat "$::prefix$dev")[6]) {
		($part{major}, $part{minor}) = unmakedev($rdev);
	    }

	    my $symlink = readlink("$::prefix$dev");
	    $dev =~ s!/u?dev/!!;

	    if ($symlink && $symlink =~ m|^[^/]+$|) {
		$part{device_alias} = $dev;
		$dev = $symlink;
	    }

	    if (my (undef, $part_number) = $dev =~ m!/(disc|part(\d+))$!) {
		$part{part_number} = $part_number if $part_number;
		$part{devfs_device} = $dev;
	    } else {
		my $part_number = devices::part_number(\%part);
		$part{part_number} = $part_number if $part_number;
	    }
	    $part{device} = $dev;
	    return \%part;
	}
    } else {
	if ($dev =~ m!^/! && -f "$::prefix$dev") {
	    #- it must be a loopback file or directory to bind
	} else {
	    log::l("part_from_wild_device_name: unknown device $dev");
	}
    }
    $part;
}

sub part2wild_device_name {
    my ($prefix, $part) = @_;

    if ($part->{prefer_device_LABEL}) {
	'LABEL=' . $part->{device_LABEL};
    } elsif ($part->{prefer_devfs_name}) {
	"/dev/$part->{devfs_device}";
    } elsif ($part->{device_alias}) {
	"/dev/$part->{device_alias}";
    } else {
	my $faked_device = exists $part->{faked_device} ? 
	    $part->{faked_device} : 
	    do {
		#- in case $part has been created without using subpart_from_wild_device_name()
		my ($kind) = analyze_wild_device_name($part->{device});
		$kind ? $kind ne 'dev' : $part->{device} =~ m!^/!;
	    };
	if ($faked_device) {
	    $part->{device};
	} elsif ($part->{device} =~ m!^/dev/!) {
	    log::l("ERROR: i have a full device $part->{device}, this should not happen. use subpart_from_wild_device_name() instead of creating bad part data-structures!");
	    $part->{device};
	} else {
	    my $dev = "/dev/$part->{device}";
	    eval { devices::make("$prefix$dev") };
	    $dev;
	}
    }
}

sub add2all_hds {
    my ($all_hds, @l) = @_;

    @l = merge_fstabs('', [ fs::get::really_all_fstab($all_hds) ], @l);

    foreach (@l) {
	my $s = 
	    $_->{fs_type} eq 'nfs' ? 'nfss' :
	    $_->{fs_type} eq 'smbfs' ? 'smbs' :
	    $_->{fs_type} eq 'davfs' ? 'davs' :
	    isTrueLocalFS($_) || isSwap($_) || isOtherAvailableFS($_) ? '' :
	    'special';
	push @{$all_hds->{$s}}, $_ if $s;
    }
}

sub get_major_minor {
    eval {
	my (undef, $major, $minor) = devices::entry($_->{device});
	($_->{major}, $_->{minor}) = ($major, $minor);
    } foreach @_;
}

sub merge_info_from_mtab {
    my ($fstab) = @_;

    my @l1 = map { my $l = $_; 
		   my $h = fs::type::fs_type2subpart('swap');
		   $h->{$_} = $l->{$_} foreach qw(device major minor); 
		   $h;
	       } read_fstab('', '/proc/swaps');
    
    my @l2 = map { read_fstab('', $_) } '/etc/mtab', '/proc/mounts';

    foreach (@l1, @l2) {
	log::l("found mounted partition on $_->{device} with $_->{mntpoint}");
	if ($::isInstall && $_->{mntpoint} =~ m!/tmp/(image|hdimage)!) {
	    $_->{real_mntpoint} = delete $_->{mntpoint};
	    if ($_->{real_mntpoint} eq '/tmp/hdimage') {
		log::l("found hdimage on $_->{device}");
		$_->{mntpoint} = "/mnt/hd"; #- remap for hd install.
	    }
	}
	$_->{isMounted} = 1;
	set_isFormatted($_, 1);
    } 
    merge_fstabs('loose', $fstab, @l1, @l2);
}

# - when using "$loose", it does not merge in type&options from the fstab
sub merge_info_from_fstab {
    my ($fstab, $prefix, $uniq, $loose) = @_;

    my @l = grep { 
	if ($uniq) {
	    my $part = fs::get::mntpoint2part($_->{mntpoint}, $fstab);
	    !$part || fsedit::is_same_hd($part, $_); #- keep it only if it is the mountpoint AND the same device
	} else {
	    1;
	}
    } read_fstab($prefix, '/etc/fstab', 'keep_default');

    merge_fstabs($loose, $fstab, @l);
}

sub get_info_from_fstab {
    my ($all_hds) = @_;
    my @l = read_fstab($::prefix, '/etc/fstab', 'keep_default');
    add2all_hds($all_hds, @l);
}

sub prepare_write_fstab {
    my ($fstab, $o_prefix, $b_keep_smb_credentials) = @_;
    $o_prefix ||= '';

    my %new;
    my @smb_credentials;
    my @l = map { 
	my $device = 
	  isLoopback($_) ? 
	      ($_->{mntpoint} eq '/' ? "/initrd/loopfs" : $_->{loopback_device}{mntpoint}) . $_->{loopback_file} :
	  part2wild_device_name($o_prefix, $_);

	my $real_mntpoint = $_->{mntpoint} || ${{ '/tmp/hdimage' => '/mnt/hd' }}{$_->{real_mntpoint}};
	mkdir_p("$o_prefix$real_mntpoint") if $real_mntpoint =~ m|^/|;
	my $mntpoint = fs::loopback::carryRootLoopback($_) ? '/initrd/loopfs' : $real_mntpoint;

	my ($freq, $passno) =
	  exists $_->{freq} ?
	    ($_->{freq}, $_->{passno}) :
	  isTrueLocalFS($_) && $_->{options} !~ /encryption=/ && (!$_->{is_removable} || member($_->{mntpoint}, fs::type::directories_needed_to_boot())) ? 
	    (1, $_->{mntpoint} eq '/' ? 1 : fs::loopback::carryRootLoopback($_) ? 0 : 2) : 
	    (0, 0);

	if (($device eq 'none' || !$new{$device}) && ($mntpoint eq 'swap' || !$new{$mntpoint})) {
	    #- keep in mind the new line for fstab.
	    $new{$device} = 1;
	    $new{$mntpoint} = 1;

	    my $options = $_->{options};

	    if ($_->{fs_type} eq 'smbfs' && $options =~ /password=/ && !$b_keep_smb_credentials) {
		require network::smb;
		if (my ($opts, $smb_credentials) = network::smb::fstab_entry_to_credentials($_)) {
		    $options = $opts;
		    push @smb_credentials, $smb_credentials;
		}
	    }

	    my $fs_type = $_->{fs_type} || 'auto';

	    s/ /\\040/g foreach $mntpoint, $device, $options;

	    # handle bloody supermount special case
	    if ($options =~ /supermount/) {
		my @l = grep { $_ ne 'supermount' } split(',', $options);
		my ($l1, $l2) = partition { member($_, 'ro', 'exec') } @l;
		$options = join(",", "dev=$device", "fs=$fs_type", @$l1, if_(@$l2, '--', @$l2));
		($device, $fs_type) = ('none', 'supermount');
	    } else {
		#- if we were using supermount, the type could be something like ext2:vfat
		#- but this can not be done without supermount, so switching to "auto"
		$fs_type = 'auto' if $fs_type =~ /:/;
	    }

	    my $file_dep = $options =~ /\b(loop|bind)\b/ ? $device : '';

	    [ $file_dep, $mntpoint, $_->{comment} . join(' ', $device, $mntpoint, $fs_type, $options || 'defaults', $freq, $passno) . "\n" ];
	} else {
	    ();
	}
    } grep { $_->{device} && ($_->{mntpoint} || $_->{real_mntpoint}) && $_->{fs_type} && ($_->{isFormatted} || !$_->{notFormatted}) } @$fstab;

    sub sort_it {
	my (@l) = @_;

	if (my $file_based = find { $_->[0] } @l) {
	    my ($before, $other) = partition { $file_based->[0] =~ /^\Q$_->[1]/ } @l;
	    $file_based->[0] = ''; #- all dependencies are now in before
	    if (@$other && @$before) {
		sort_it(@$before), sort_it(@$other);
	    } else {
		sort_it(@l);
	    }
	} else {
	    sort { $a->[1] cmp $b->[1] } @l;
	}	
    }
    @l = sort_it(@l);

    join('', map { $_->[2] } @l), \@smb_credentials;
}

sub fstab_to_string {
    my ($all_hds, $o_prefix) = @_;
    my $fstab = [ fs::get::really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, undef) = prepare_write_fstab($fstab, $o_prefix, 'keep_smb_credentials');
    $s;
}

sub write_fstab {
    my ($all_hds, $o_prefix) = @_;
    log::l("writing $o_prefix/etc/fstab");
    my $fstab = [ fs::get::really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, $smb_credentials) = prepare_write_fstab($fstab, $o_prefix, '');
    output("$o_prefix/etc/fstab", $s);
    network::smb::save_credentials($_) foreach @$smb_credentials;
}

sub auto_fs() {
    grep { chop; $_ && !/nodev/ } cat_("/etc/filesystems");
}

sub set_removable_mntpoints {
    my ($all_hds) = @_;

    my %names;
    foreach (@{$all_hds->{raw_hds}}) {
	my $name = detect_devices::suggest_mount_point($_) or next;
	$name eq 'zip' and next;
	
	my $s = ++$names{$name};
	$_->{mntpoint} ||= "/mnt/$name" . ($s == 1 ? '' : $s);
    }
}

sub get_raw_hds {
    my ($prefix, $all_hds) = @_;

    push @{$all_hds->{raw_hds}}, detect_devices::removables();
    $_->{is_removable} = 1 foreach @{$all_hds->{raw_hds}};

    get_major_minor(@{$all_hds->{raw_hds}});

    my @fstab = read_fstab($prefix, '/etc/fstab', 'keep_default');
    $all_hds->{nfss} = [ grep { $_->{fs_type} eq 'nfs' } @fstab ];
    $all_hds->{smbs} = [ grep { $_->{fs_type} eq 'smbfs' } @fstab ];
    $all_hds->{davs} = [ grep { $_->{fs_type} eq 'davfs' } @fstab ];
    $all_hds->{special} = [
       (grep { $_->{fs_type} eq 'tmpfs' } @fstab),
       { device => 'none', mntpoint => '/proc', fs_type => 'proc' },
    ];
}


################################################################################
# mounting functions
################################################################################
sub set_loop {
    my ($part) = @_;
    $part->{real_device} ||= devices::set_loop(devices::make($part->{device}), $part->{encrypt_key}, $part->{options} =~ /encryption=(\w+)/);
}

sub swapon {
    my ($dev) = @_;
    log::l("swapon called with $dev");
    syscall_('swapon', devices::make($dev), 0) or die "swapon($dev) failed: $!";
}

sub swapoff {
    my ($dev) = @_;
    syscall_('swapoff', devices::make($dev)) or die "swapoff($dev) failed: $!";
}

sub formatMount_part {
    my ($part, $raids, $fstab, $prefix, $wait_message) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{loopback_device}, $raids, $fstab, $prefix, $wait_message);
    }
    if (my $p = fs::get::up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $raids, $fstab, $prefix, $wait_message) if !fs::loopback::carryRootLoopback($part);
    }
    if ($part->{toFormat}) {
	fs::format::part($raids, $part, $prefix, $wait_message);
    }
    mount_part($part, $prefix, 0, $wait_message);
}

sub formatMount_all {
    my ($raids, $fstab, $prefix, $wait_message) = @_;
    formatMount_part($_, $raids, $fstab, $prefix, $wait_message) 
      foreach sort { isLoopback($a) ? 1 : isSwap($a) ? -1 : 0 } grep { $_->{mntpoint} } @$fstab;

    #- ensure the link is there
    fs::loopback::carryRootCreateSymlink($_, $prefix) foreach @$fstab;

    #- for fun :)
    #- that way, when install exits via ctrl-c, it gives hand to partition
    eval {
	my ($_type, $major, $minor) = devices::entry(fs::get::root($fstab)->{device});
	output "/proc/sys/kernel/real-root-dev", makedev($major, $minor);
    };
}

sub mount {
    my ($dev, $where, $fs, $b_rdonly, $o_options, $o_wait_message) = @_;
    log::l("mounting $dev on $where as type $fs, options $o_options");

    mkdir_p($where);

    $fs or log::l("not mounting $dev partition"), return;

    {
	my @fs_modules = qw(ext3 hfs jfs nfs ntfs romfs reiserfs ufs xfs vfat);
	my @types = (qw(ext2 proc sysfs usbfs usbdevfs iso9660 devfs devpts), @fs_modules);

	push @types, 'smb', 'smbfs', 'davfs' if !$::isInstall;

	if (!member($fs, @types) && !$::move) {
	    log::l("skipping mounting $dev partition ($fs)");
	    return;
	}
	if ($::isInstall) {
	    if (member($fs, @fs_modules)) {
		eval { modules::load($fs) };
	    } elsif ($fs eq 'iso9660') {
		eval { modules::load('isofs') };
	    }
	}
    }

    $where =~ s|/$||;

    my @mount_opt = split(',', $o_options || '');

    if ($fs eq 'vfat') {
	@mount_opt = 'check=relaxed';
    } elsif ($fs eq 'nfs') {
	push @mount_opt, 'nolock', 'soft', 'intr' if $::isInstall;
    } elsif ($fs eq 'jfs' && !$b_rdonly) {
	fsck_jfs($dev, $o_wait_message);
    } elsif ($fs eq 'ext2' && !$b_rdonly) {
	fsck_ext2($dev, $o_wait_message);
    }

    push @mount_opt, 'ro' if $b_rdonly;

    log::l("calling mount -t $fs $dev $where @mount_opt");
    $o_wait_message->(N("Mounting partition %s", $dev)) if $o_wait_message;
    run_program::run('mount', '-t', $fs, $dev, $where, if_(@mount_opt, '-o', join(',', @mount_opt))) or die N("mounting partition %s in directory %s failed", $dev, $where);
}

sub fsck_ext2 {
    my ($dev, $o_wait_message) = @_;
    $o_wait_message->(N("Checking %s", $dev)) if $o_wait_message;
    foreach ('-a', '-y') {
	run_program::raw({ timeout => 60 * 60 }, "fsck.ext2", $_, $dev);
	my $err = $?;
	if ($err & 0x0100) {
	    log::l("fsck corrected partition $dev");
	}
	if ($err & 0xfeff) {
	    my $txt = sprintf("fsck failed on %s with exit code %d or signal %d", $dev, $err >> 8, $err & 255);
	    $_ eq '-y' ? die($txt) : cdie($txt);
	} else {
	    last;
	}
    }
}
sub fsck_jfs {
    my ($dev, $o_wait_message) = @_;
    $o_wait_message->(N("Checking %s", $dev)) if $o_wait_message;
    #- needed if the system is dirty otherwise mounting read-write simply fails
    run_program::raw({ timeout => 60 * 60 }, "fsck.jfs", $dev) or do {
	my $err = $?;
	die "fsck.jfs failed" if $err & 0xfc00;
    };
}

#- takes the mount point to umount (can also be the device)
sub umount {
    my ($mntpoint) = @_;
    $mntpoint =~ s|/$||;
    log::l("calling umount($mntpoint)");

    syscall_('umount2', $mntpoint, 0) or do {
	kill 15, fuzzy_pidofs('^fam\b');
	syscall_('umount2', $mntpoint, 0) or die N("error unmounting %s: %s", $mntpoint, $!);
    };

    substInFile { $_ = '' if /(^|\s)$mntpoint\s/ } '/etc/mtab'; #- do not care about error, if we can not read, we will not manage to write... (and mess mtab)
}

sub mount_part {
    my ($part, $o_prefix, $b_rdonly, $o_wait_message) = @_;

    #- root carrier's link can not be mounted
    fs::loopback::carryRootCreateSymlink($part, $o_prefix);

    log::l("mount_part: " . join(' ', map { "$_=$part->{$_}" } 'device', 'mntpoint', 'isMounted', 'real_mntpoint'));
    if ($part->{isMounted} && $part->{real_mntpoint} && $part->{mntpoint}) {
	log::l("remounting partition on $o_prefix$part->{mntpoint} instead of $part->{real_mntpoint}");
	if ($::isInstall) { #- ensure partition will not be busy.
	    require install_any;
	    install_any::getFile('XXX');
	}
	eval {
	    umount($part->{real_mntpoint});
	    rmdir $part->{real_mntpoint};
	    symlinkf "$o_prefix$part->{mntpoint}", $part->{real_mntpoint};
	    delete $part->{real_mntpoint};
	    $part->{isMounted} = 0;
	};
    }

    return if $part->{isMounted};

    unless ($::testing) {
	if (isSwap($part)) {
	    $o_wait_message->(N("Enabling swap partition %s", $part->{device})) if $o_wait_message;
	    swapon($part->{device});
	} else {
	    $part->{mntpoint} or die "missing mount point for partition $part->{device}";

	    my $mntpoint = ($o_prefix || '') . $part->{mntpoint};
	    if (isLoopback($part) || $part->{encrypt_key}) {
		set_loop($part);
	    } elsif ($part->{options} =~ /encrypted/) {
		log::l("skip mounting $part->{device} since we do not have the encrypt_key");
		return;
	    } elsif (fs::loopback::carryRootLoopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    my $dev = $part->{real_device} || part2wild_device_name('', $part);
	    mount($dev, $mntpoint, $part->{fs_type}, $b_rdonly, $part->{options}, $o_wait_message);
	}
    }
    $part->{isMounted} = 1;
    set_isFormatted($part, 1); #- assume that if mount works, partition is formatted
}

sub umount_part {
    my ($part, $o_prefix) = @_;

    $part->{isMounted} || $part->{real_mntpoint} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swapoff($part->{device});
	} elsif (fs::loopback::carryRootLoopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount(($o_prefix || '') . $part->{mntpoint} || devices::make($part->{device}));
	    devices::del_loop(delete $part->{real_device}) if $part->{real_device};
	}
    }
    $part->{isMounted} = 0;
}

sub umount_all($;$) {
    my ($fstab, $prefix) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } @$fstab) {
	$_->{mntpoint} and umount_part($_, $prefix);
    }
}

################################################################################
# various functions
################################################################################
sub df {
    my ($part, $o_prefix) = @_;
    my $dir = "/tmp/tmp_fs_df";

    return $part->{free} if exists $part->{free};

    if ($part->{isMounted}) {
	$dir = ($o_prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	return; #- will not even try!
    } else {
	mkdir_p($dir);
	eval { mount(devices::make($part->{device}), $dir, $part->{fs_type}, 'readonly') };
	if ($@) {
	    set_isFormatted($part, 0);
	    unlink $dir;
	    return;
	}
    }
    my (undef, $free) = MDK::Common::System::df($dir);

    if (!$part->{isMounted}) {
	umount($dir);
	unlink($dir);
    }

    $part->{free} = 2 * $free if defined $free;
    $part->{free};
}

sub mount_usbfs {
    my ($prefix) = @_;
    
    my $fs = cat_('/proc/filesystems') =~ /usbfs/ ? 'usbfs' : 'usbdevfs';
    mount('none', "$prefix/proc/bus/usb", $fs);
}

1;
