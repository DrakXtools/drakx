package fs::format;

use diagnostics;
use strict;

use run_program;
use common;
use fs::type;
use log;

my %cmds = (
    ext2     => [ 'e2fsprogs', 'mke2fs', '-F' ],
    ext3     => [ 'e2fsprogs', 'mke2fs', '-F', '-j' ],
    reiserfs => [ 'reiserfsprogs', 'mkreiserfs', '-ff' ],
    xfs      => [ 'xfsprogs', 'mkfs.xfs', '-f', '-q' ],
    jfs      => [ 'jfsprogs', 'mkfs.jfs', '-f' ],
    hfs      => [ 'hfsutils', 'hformat' ],
    dos      => [ 'dosfstools', 'mkdosfs' ],
    vfat     => [ 'dosfstools', 'mkdosfs', '-F', '32' ],
    swap     => [ 'util-linux', 'mkswap' ],
);

sub package_needed_for_partition_type {
    my ($part) = @_;
    my $l = $cmds{$part->{fs_type}} or return;
    $l->[0];
}

sub check_package_is_installed {
    my ($do_pkgs, $fs_type) = @_;

    my ($pkg, $binary) = @{$cmds{$fs_type} || return};
    $do_pkgs->ensure_binary_is_installed($pkg, $binary);
}

sub part {
    my ($raids, $part, $prefix, $wait_message) = @_;
    if (isRAID($part)) {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	require raid;
	raid::format_part($raids, $part);
    } elsif (isLoopback($part)) {
	$wait_message->(N("Creating and formatting file %s", $part->{loopback_file})) if $wait_message;
	loopback::format_part($part, $prefix);
    } else {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	part_raw($part);
    }
}

sub part_raw {
    my ($part) = @_;

    $part->{isFormatted} and return;

    if ($part->{encrypt_key}) {
	require fs;
	fs::set_loop($part);
    }

    my $dev = $part->{real_device} || $part->{device};

    my @options = if_($part->{toFormatCheck}, "-c");
    log::l("formatting device $dev (type $part->{fs_type})");

    my $fs_type = $part->{fs_type};

    if ($fs_type eq 'ext2' || $fs_type eq 'ext3') {
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
    } elsif (isDos($part)) {
	$fs_type = 'dos';
    } elsif ($fs_type eq 'hfs') {
        push @options, '-l', "Untitled";
    } elsif (isAppleBootstrap($part)) {
	push @options, '-l', 'bootstrap';
    }

    my ($_pkg, $cmd, @first_options) = @{$cmds{$fs_type} || die N("I don't know how to format %s in type %s", $part->{device}, $part->{fs_type})};

    run_program::raw({ timeout => 60 * 60 }, $cmd, @first_options, @options, devices::make($dev)) or die N("%s formatting of %s failed", $fs_type, $dev);

    if ($fs_type eq 'ext3') {
	disable_forced_fsck($dev);
    }

    set_isFormatted($part, 1);
}

sub disable_forced_fsck {
    my ($dev) = @_;
    run_program::run("tune2fs", "-c0", "-i0", devices::make($dev));
}

1;
