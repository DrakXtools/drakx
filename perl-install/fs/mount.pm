package fs::mount; # $Id$

use diagnostics;
use strict;

use run_program;
use common;
use fs::type;
use log;


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

sub part {
    my ($part, $b_rdonly, $o_wait_message) = @_;

    log::l("mount_part: " . join(' ', map { "$_=$part->{$_}" } 'device', 'mntpoint', 'isMounted', 'real_mntpoint'));
    if ($part->{isMounted} && $part->{real_mntpoint} && $part->{mntpoint}) {
	log::l("remounting partition on " . fs::get::mntpoint_prefixed($part) . " instead of $part->{real_mntpoint}");
	if ($::isInstall) { #- ensure partition will not be busy.
	    require install_any;
	    install_any::getFile('XXX');
	}
	eval {
	    umount($part->{real_mntpoint});
	    rmdir $part->{real_mntpoint};
	    symlinkf fs::get::mntpoint_prefixed($part), $part->{real_mntpoint};
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

	    my $mntpoint = fs::get::mntpoint_prefixed($part);
	    if (isLoopback($part) || $part->{encrypt_key}) {
		set_loop($part);
	    } elsif ($part->{options} =~ /encrypted/) {
		log::l("skip mounting $part->{device} since we do not have the encrypt_key");
		return;
	    } elsif (fs::type::carry_root_loopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    my $dev = $part->{real_device} || fs::wild_device::from_part('', $part);
	    mount($dev, $mntpoint, $part->{fs_type}, $b_rdonly, $part->{options}, $o_wait_message);
	}
    }
    $part->{isMounted} = 1;
    set_isFormatted($part, 1); #- assume that if mount works, partition is formatted
}

sub umount_part {
    my ($part) = @_;

    $part->{isMounted} || $part->{real_mntpoint} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swapoff($part->{device});
	} elsif (fs::type::carry_root_loopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount(fs::get::mntpoint_prefixed($part) || devices::make($part->{device}));
	    devices::del_loop(delete $part->{real_device}) if $part->{real_device};
	}
    }
    $part->{isMounted} = 0;
}

sub umount_all {
    my ($fstab) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } @$fstab) {
	$_->{mntpoint} and umount_part($_);
    }
}

sub usbfs {
    my ($prefix) = @_;
    
    my $fs = cat_('/proc/filesystems') =~ /usbfs/ ? 'usbfs' : 'usbdevfs';
    mount('none', "$prefix/proc/bus/usb", $fs);
}

1;
