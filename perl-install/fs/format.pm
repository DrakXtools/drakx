package fs::format;

use run_program;
use common;
use log;
use partition_table qw(:types);

my %cmds = (
    ext2     => 'mke2fs -F',
    ext3     => 'mke2fs -F -j',
    reiserfs => 'mkreiserfs -ff',
    xfs      => 'mkfs.xfs -f -q',
    jfs      => 'mkfs.jfs -f',
    hfs      => 'hformat',
    dos      => 'mkdosfs',
    vfat     => 'mkdosfs -F 32',
    swap     => 'mkswap',
);

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
	fs::set_loop($part);
    }

    my $dev = $part->{real_device} || $part->{device};

    my @options = if_($part->{toFormatCheck}, "-c");
    log::l("formatting device $dev (type ", part2name($part), ")");

    my $fs_type = type2fs($part);

    if ($fs_type eq 'ext2' || $fs_type eq 'ext3') {
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
    } elsif (isDos($part)) {
	$fs_type = 'dos';
    } elsif ($fs_type eq 'hfs') {
        push @options, '-l', "Untitled";
    } elsif (isAppleBootstrap($part)) {
	push @options, '-l', 'bootstrap';
    }

    my $cmd = $cmds{$fs_type} or die N("I don't know how to format %s in type %s", $part->{device}, part2name($part));

    run_program::raw({ timeout => 60 * 60 }, $cmd, @options, devices::make($dev)) or die N("%s formatting of %s failed", $fs_type, $dev);

    if ($fs_type eq 'ext3') {
	disable_forced_fsck($dev);
    }

    $part->{isFormatted} = 1;
}

sub disable_forced_fsck {
    my ($dev) = @_;
    run_program::run("tune2fs", "-c0", "-i0", devices::make($dev));
}

1;
