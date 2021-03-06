package fs::mount;

use diagnostics;
use strict;

use run_program;
use common;
use fs::type;
use log;


sub set_loop {
    my ($part) = @_;
    $part->{device} ||= fs::get::mntpoint_prefixed($part->{loopback_device}) . $part->{loopback_file};
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

sub mount {
    my ($dev, $where, $fs, $b_rdonly, $o_options, $o_wait_message) = @_;
    log::l("mounting $dev on $where as type $fs, options $o_options");

    mkdir_p($where);

    $fs or log::l("not mounting $dev partition"), return;

    {
	my @fs_modules = qw(btrfs f2fs ext3 ext4 hfs jfs nilfs2 nfs ntfs romfs reiserfs ufs xfs vfat);
	my @types = (qw(ext2 proc sysfs iso9660 devpts auto ntfs-3g), @fs_modules);

	push @types, 'smb', 'cifs', 'davfs2' if !$::isInstall;

	if (!member($fs, @types)) {
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

    if ($::isInstall) {
	#- those options need nls_XXX modules, and we don't this at install
	@mount_opt = grep { $_ ne 'utf8' && !/^iocharset=/ } @mount_opt;
    }

    if ($fs eq 'vfat') {
	@mount_opt = 'check=relaxed';
    } elsif ($fs eq 'ntfs') {
	@mount_opt = () if $::isInstall; # esp. drop nls=xxx option so that we don't need kernel module nls_xxx
    } elsif ($fs eq 'nfs') {
	push @mount_opt, 'nolock', 'soft', 'intr' if $::isInstall;
    } elsif ($fs eq 'jfs' && !$b_rdonly) {
	fsck_jfs($dev, $o_wait_message);
    } elsif ($fs eq 'ext2' && !$b_rdonly) {
	fsck_ext2($dev, $o_wait_message);
    } elsif ($fs eq 'davfs2') {
	require fs::remote::davfs;
	# We have to store credentials in davfs2 secret file before mounting
	fs::remote::davfs::mountpoint_credentials_save($where, \@mount_opt);
	# username and password options should be handled by /etc/davfs2/secrets file
	@mount_opt = grep { !/^(username|password)=/ } @mount_opt;
    }

    push @mount_opt, 'ro' if $b_rdonly;

    $o_wait_message->(N("Mounting partition %s", $dev)) if $o_wait_message;
    modules::load("fuse") if $::isInstall && $fs eq 'ntfs-3g' && ! -e '/dev/fuse';
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

    run_program::run('umount', $mntpoint) or do {
	kill 15, fuzzy_pidofs('^fam\b');
	my $err;
	run_program::run('umount', '2>', \$err, $mntpoint) or die N("error unmounting %s: %s", $mntpoint, common::to_utf8($err));
    };

    substInFile { $_ = '' if /(^|\s)$mntpoint\s/ } '/etc/mtab'; #- do not care about error, if we cannot read, we will not manage to write... (and mess mtab)
}

sub part {
    my ($part, $b_rdonly, $o_wait_message) = @_;

    log::l("mount_part: " . join(' ', map { "$_=$part->{$_}" } 'device', 'mntpoint', 'isMounted', 'real_mntpoint', 'device_UUID'));

    return if $part->{isMounted} && !($part->{real_mntpoint} && $part->{mntpoint});

    unless ($::testing) {
	if (isSwap($part)) {
	    $o_wait_message->(N("Enabling swap partition %s", $part->{device})) if $o_wait_message;
	    swapon($part->{device});
	} elsif ($part->{real_mntpoint}) {
	    my $mntpoint = fs::get::mntpoint_prefixed($part);

	    mkdir_p($mntpoint);
	    run_program::run_or_die('mount', '--move', $part->{real_mntpoint}, $mntpoint);

	    rmdir $part->{real_mntpoint};
	    symlinkf $mntpoint, $part->{real_mntpoint};
	    delete $part->{real_mntpoint};

	    my $dev = $part->{real_device} || fs::wild_device::from_part('', $part);
	    run_program::run_or_die('mount', $dev, $mntpoint, '-o', join(',', 'remount', $b_rdonly ? 'ro' : 'rw'));
	} else {
	    $part->{mntpoint} or die "missing mount point for partition $part->{device}";

	    my $mntpoint = fs::get::mntpoint_prefixed($part);
	    my $options = $part->{options};
	    if ($part->{encrypt_key}) {
		set_loop($part);
		$options = join(',', grep { !/^(encryption=|encrypted$|loop$)/ } split(',', $options)); #- we take care of this, don't let it mount see it
	    } elsif (isLoopback($part)) {
		$options = join(',', uniq('loop', split(',', $options))); #- ensure the loop options is used
	    } elsif ($part->{options} =~ /encrypted/) {
		log::l("skip mounting $part->{device} since we do not have the encrypt_key");
		return;
	    } elsif (fs::type::carry_root_loopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    my $dev = $part->{real_device} || fs::wild_device::from_part('', $part);
	    my $fs_type = $part->{fs_type};
	    if ($fs_type eq 'auto' && $part->{media_type} eq 'cdrom' && $::isInstall) {
		$fs_type = 'iso9660';
	    } elsif ($fs_type eq 'ntfs-3g' && $::isInstall) {
		$fs_type = 'ntfs';
	    }
	    mount($dev, $mntpoint, $fs_type, $b_rdonly, $options, $o_wait_message);

	    if ($options =~ /usrquota|grpquota/ && member($part->{fs_type}, qw(ext3 ext4))) {
		if (! find { -e "$mntpoint/$_" } qw(aquota.user aquota.group quota.user quota.group)) {
		    #- quotacheck will create aquota.user and/or aquota.group,
		    #- needed for quotas on ext3/ext4.
		    run_program::run('quotacheck', $mntpoint);
		}		
	    }
	    if (isLoopback($part) && $::isInstall) {
		#- since /etc/mtab is symlinked to /proc/mounts, umount will
		#- not be able to know it needs to do losetup -d
		#- TODO: drop this and have a real /etc/mtab
		$part->{real_device} = cat_("/proc/mounts") =~ m!(/dev/\S+)\s+\Q$mntpoint\E\s! && $1;
		log::l("XXX $part->{real_device}");
	    }
	}
    }
    $part->{isMounted} = 1;
    set_isFormatted($part, 1); #- assume that if mount works, partition is formatted
}

sub umount_part {
    my ($part) = @_;

    $part->{isMounted} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swapoff($part->{device});
	} elsif (fs::type::carry_root_loopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount($part->{real_mntpoint} || fs::get::mntpoint_prefixed($part) || devices::make($part->{device}));
	    devices::del_loop(delete $part->{real_device}) if $part->{real_device};
	}
    }
    $part->{isMounted} = 0;
}

sub umount_all {
    my ($fstab) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } 
	       grep { $_->{mntpoint} && !$_->{real_mntpoint} || isSwap($_) } @$fstab) {
	umount_part($_);
    }
}

sub sys_kernel_debug {
    my ($prefix) = @_;

    mount('none', "$prefix/sys/kernel/debug", 'debugfs');
}

1;
