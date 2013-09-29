package fs::format; # $Id$

use diagnostics;
use strict;
use String::ShellQuote;

use run_program;
use common;
use fs::type;
use fs::loopback;
use log;

my %cmds = (
    ext2     => [ 'e2fsprogs', 'mkfs.ext2', '-F' ],
    ext3     => [ 'e2fsprogs', 'mkfs.ext3', '-F' ],
    ext4     => [ 'e2fsprogs', 'mkfs.ext4', '-F' ],
    reiserfs => [ 'reiserfsprogs', 'mkfs.reiserfs', '-ff' ],
    xfs      => [ 'xfsprogs', 'mkfs.xfs', '-f', '-q' ],
    jfs      => [ 'jfsutils', 'mkfs.jfs', '-f' ],
    hfs      => [ 'hfsutils', 'hformat' ],
    dos      => [ 'dosfstools', 'mkdosfs' ],
    vfat     => [ 'dosfstools', 'mkdosfs', '-F', '32' ],
    swap     => [ 'util-linux', 'mkswap' ],
    ntfs     => [ 'ntfsprogs', 'mkntfs', '--fast' ],
   'ntfs-3g' => [ 'ntfsprogs', 'mkntfs', '--fast' ],
    btrfs    => [ 'btrfs-progs', 'mkfs.btrfs', '-f' ],
    nilfs2   => [ 'nilfs-utils', 'mkfs.nilfs2' ],
);

my %LABELs = ( #- option, length, handled_by_mount
    ext2     => [ '-L', 16, 1 ],
    ext3     => [ '-L', 16, 1 ],
    ext4     => [ '-L', 16, 1 ],
    reiserfs => [ '-l', 16, 1 ],
    xfs      => [ '-L', 12, 1 ],
    jfs      => [ '-L', 16, 1 ],
    hfs      => [ '-l', 27, 0 ],
    dos      => [ '-n', 11, 0 ],
    vfat     => [ '-n', 11, 0 ],
    swap     => [ '-L', 15, 1 ],
    ntfs     => [ '-L', 128, 0 ],
   'ntfs-3g' => [ '-L', 128, 0 ],
    btrfs    => [ '-L', 256, 1 ],
    nilfs2   => [ '-L', 16, 1],
);

my %edit_LABEL = ( # package, command, option
# If option is defined, run <command> <option> <label> <device>
# If no option, run <command> <device> <label>
    ext2     => [ 'e2fsprogs', 'tune2fs', '-L' ],
    ext3     => [ 'e2fsprogs', 'tune2fs', '-L' ],
    ext4     => [ 'e2fsprogs', 'tune2fs', '-L' ],
    reiserfs => [ 'reiserfsprogs', 'reiserfstune', '-l' ],
    xfs      => [ 'xfsprogs', 'xfs_admin', '-L' ],
    jfs      => [ 'jfsutils', 'jfs_tune', '-L' ],
#    hfs
    dos      => [ 'mtools', 'mlabel', '-i' ],
    vfat     => [ 'mtools', 'mlabel', '-i' ],
    swap     => [ 'util-linux', 'swaplabel', '-L' ],
    ntfs     => [ 'ntfsprogs', 'ntfslabel' ],
   'ntfs-3g' => [ 'ntfsprogs', 'ntfslabel' ],
    btrfs => [ 'btrfs-progs', 'btrfs', 'filesystem', 'label' ],
    nilfs2 => [ 'nilfs-utils', 'nilfs-tune', '-L' ],
);

# Preserve UUID on fs where we couldn't enforce it while formatting
my %preserve_UUID = ( # package, command
    #btrfs    => [ 'btrfs-progs', 'FIXME' ],
    jfs      => [ 'jfsutils', 'jfs_tune', ],
    xfs      => [ 'xfsprogs', 'xfs_admin' ],
    nilfs2   => [ 'nilfs-utils', 'nilfs-tune' ],
);
 
sub package_needed_for_partition_type {
    my ($part) = @_;
    my $l = $cmds{$part->{fs_type}} or return;
    $l->[0];
}

sub known_type {
    my ($part) = @_;
    to_bool($cmds{$part->{fs_type}});
}

sub check_package_is_installed_format {
    my ($do_pkgs, $fs_type) = @_;

    my ($pkg, $binary) = @{$cmds{$fs_type} || return};
    whereis_binary($binary) || $do_pkgs->ensure_binary_is_installed($pkg, $binary); #- ensure_binary_is_installed checks binary chrooted, whereas we run the binary non-chrooted (pb for Mandriva One)
}

sub check_package_is_installed_label {
    my ($do_pkgs, $fs_type) = @_;

    my ($pkg, $binary) = @{$edit_LABEL{$fs_type} || return};
    whereis_binary($binary) || $do_pkgs->ensure_binary_is_installed($pkg, $binary); #- ensure_binary_is_installed checks binary chrooted, whereas we run the binary non-chrooted (pb for Mandriva One)
}

sub canEditLabel {
    my ($part) = @_;
    to_bool($edit_LABEL{$part->{fs_type}});
}

sub part {
    my ($all_hds, $part, $wait_message) = @_;
    if (isRAID($part)) {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	require raid;
	raid::format_part($all_hds->{raids}, $part);
    } elsif (isLoopback($part)) {
	$wait_message->(N("Creating and formatting file %s", $part->{loopback_file})) if $wait_message;
	fs::loopback::format_part($part);
    } else {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	part_raw($part, $wait_message);
    }
    undef $part->{toFormat};
}

sub write_label {
    my ($part) = @_;

    $part->{device_LABEL_changed} or return;
    maybeFormatted($part) or return;

    if ($part->{encrypt_key}) {
	fs::mount::set_loop($part);
    }

    my $dev = $part->{real_device} || $part->{device};
    my ($_pkg, $cmd, @first_options) = @{$edit_LABEL{$part->{fs_type}} || die N("I do not know how to set label on %s with type %s", $part->{device}, $part->{fs_type})};
    my @args;
    if ($cmd eq 'mlabel') {
      @args = ($cmd, @first_options, devices::make($dev), '::' . $part->{device_LABEL});
    } elsif ($cmd eq 'btrfs') {
      # btrfs needs reverse ordering
      @args = ($cmd, @first_options, devices::make($dev), $part->{device_LABEL});
    } elsif (defined $first_options[0]) {
      @args = ($cmd, @first_options, $part->{device_LABEL}, devices::make($dev));
    } else {
      @args = ($cmd, devices::make($dev), $part->{device_LABEL});
    }
    run_program::raw({ timeout => 'never' }, @args) or die N("setting label on %s failed, is it formatted?", $dev);
    delete $part->{device_LABEL_changed};
}

sub part_raw {
    my ($part, $wait_message) = @_;

    $part->{isFormatted} and return;

    if ($part->{encrypt_key}) {
	fs::mount::set_loop($part);
    }

    my $dev = $part->{real_device} || $part->{device};

    my @options = if_($part->{toFormatCheck}, "-c");
    log::l("formatting device $dev (type $part->{fs_type})");

    my $fs_type = $part->{fs_type};

    if (member($fs_type, qw(ext2 ext3 ext4))) {
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
    } elsif (isDos($part)) {
	$fs_type = 'dos';
    } elsif ($fs_type eq 'hfs') {
        push @options, '-l', "Untitled";
    } elsif (isAppleBootstrap($part)) {
	push @options, '-l', 'bootstrap';
    }

    # Preserve UUID
    if (member($fs_type, 'swap', 'ext2', 'ext3', 'ext4')) {
	push @options, '-U', $part->{device_UUID} if $part->{device_UUID};
    } elsif ($fs_type eq 'reiserfs') {
	push @options, '-u', $part->{device_UUID} if $part->{device_UUID};
    }

    if ($part->{device_LABEL}) {
	push @options, @{$LABELs{$fs_type}}[0], $part->{device_LABEL};
    }

    my ($_pkg, $cmd, @first_options) = @{$cmds{$fs_type} || die N("I do not know how to format %s in type %s", $part->{device}, $part->{fs_type})};

    my @args = ($cmd, @first_options, @options, devices::make($dev));

    if ($cmd =~ /^mkfs.ext[34]$/ && $wait_message) {
	mkfs_ext3($wait_message, @args) or die N("%s formatting of %s failed", $fs_type, $dev);
    } else {
	run_program::raw({ timeout => 'never' }, @args) or die N("%s formatting of %s failed", $fs_type, $dev);
    }

    delete $part->{device_LABEL_changed};

    # Preserve UUID on fs where we couldn't enforce it while formatting
    (undef, $cmd) = @{$preserve_UUID{$fs_type}};
    run_program::raw({}, $cmd, '-U', devices::make($dev)) if $cmd;
    
    if (member($fs_type, qw(ext3 ext4))) {
	disable_forced_fsck($dev);
    }

    after_formatting($part);
}

sub after_formatting {
    my ($part) = @_;

    my $p = fs::type::type_subpart_from_magic($part);
    $part->{device_UUID} = $p && $p->{device_UUID};

    set_isFormatted($part, 1);
}

sub mkfs_ext3 {
    my ($wait_message, @args) = @_;

    my $cmd = shell_quote_best_effort(@args);
    log::l("running: $cmd");
    open(my $F, "$cmd |");

    local $/ = "\b";
    local $_;
    while (<$F>) {
	#- even if it still takes some time when format is over, we don't want the progress bar to stay at 85%
	$wait_message->('', $1, $2) if m!^\s*(\d+)/(\d+)\b!;
    }
    return close($F);
}

sub disable_forced_fsck {
    my ($dev) = @_;
    run_program::run("tune2fs", "-c0", "-i0", devices::make($dev));
}

sub clean_label {
    my ($part) = @_;
    if ($part->{device_LABEL}) {
	my $fs_type = $part->{fs_type};
	if ($LABELs{$fs_type}) {
	    my ($_option, $length, $handled_by_mount) = @{$LABELs{$fs_type}};
	    if (length $part->{device_LABEL} > $length) {
		my $short = substr($part->{device_LABEL}, 0, $length);
		log::l("shortening LABEL $part->{device_LABEL} to $short");
		$part->{device_LABEL} = $short;
	    }
	    delete $part->{prefer_device_LABEL}
	      if !$handled_by_mount || $part->{mntpoint} eq '/' && !member($fs_type, qw(ext2 ext3 ext4));
	} else {
	    log::l("dropping LABEL=$part->{device_LABEL} since we don't know how to set labels for fs_type $fs_type");
	    delete $part->{device_LABEL};
	    delete $part->{prefer_device_LABEL};
	    delete $part->{device_LABEL_changed};
	}
    }
}

sub formatMount_part {
    my ($part, $all_hds, $fstab, $wait_message) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{loopback_device}, $all_hds, $fstab, $wait_message);
    }
    if (my $p = fs::get::up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $all_hds, $fstab, $wait_message) if !fs::type::carry_root_loopback($part);
    }

    clean_label($part);

    if ($part->{toFormat}) {
	fs::format::part($all_hds, $part, $wait_message);
    } else {
	fs::format::write_label($part);
    }

    #- setting user_xattr on /home (or "/" if no /home)
    if (!$part->{isMounted} && member($part->{fs_type}, qw(ext2 ext3 ext4))
	  && ($part->{mntpoint} eq '/home' ||
		!fs::get::has_mntpoint('/home', $all_hds) && $part->{mntpoint} eq '/')) {
	run_program::run('tune2fs', '-o', 'user_xattr', devices::make($part->{real_device} || $part->{device}));
    }

    fs::mount::part($part, 0, $wait_message);
}

sub formatMount_all {
    my ($all_hds, $fstab, $wait_message) = @_;
    formatMount_part($_, $all_hds, $fstab, $wait_message)
      foreach sort { isLoopback($a) ? 1 : isSwap($a) ? -1 : 0 } grep { $_->{mntpoint} } @$fstab;

    #- ensure the link is there
    fs::loopback::carryRootCreateSymlink($_) foreach @$fstab;

    #- for fun :)
    #- that way, when install exits via ctrl-c, it gives hand to partition
    eval {
	my ($_type, $major, $minor) = devices::entry(fs::get::root($fstab)->{device});
	output "/proc/sys/kernel/real-root-dev", makedev($major, $minor);
    };
}


1;
