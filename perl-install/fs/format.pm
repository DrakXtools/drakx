package fs::format; # $Id$

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

sub known_type {
    my ($part) = @_;
    to_bool($cmds{$part->{fs_type}});
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
	part_raw($part, $wait_message);
    }
}

sub part_raw {
    my ($part, $wait_message) = @_;

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

    my ($_pkg, $cmd, @first_options) = @{$cmds{$fs_type} || die N("I do not know how to format %s in type %s", $part->{device}, $part->{fs_type})};

    my @args = ($cmd, @first_options, @options, devices::make($dev));

    if ($cmd eq 'mke2fs' && $wait_message) {
	mke2fs($wait_message, @args) or die N("%s formatting of %s failed", $fs_type, $dev);
    } else {
	run_program::raw({ timeout => 60 * 60 }, @args) or die N("%s formatting of %s failed", $fs_type, $dev);
    }

    if ($fs_type eq 'ext3') {
	disable_forced_fsck($dev);
    }
    if ($part->{device_LABEL}) {
	if (member($fs_type, qw(ext2 ext3))) {
	    run_program::run("tune2fs", "-L", $part->{device_LABEL}, devices::make($dev));
	} else {
	    log::l("dropping LABEL=$part->{device_LABEL} since we don't know how to set labels for fs_type $part->{fs_type}");
	    delete $part->{device_LABEL};
	    delete $part->{prefer_device_LABEL};
	}
    }

    set_isFormatted($part, 1);
}

sub mke2fs {
    my ($wait_message, @args) = @_;

    open(my $F, "@args |");

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

sub wait_message {
    my ($in) = @_;

    my ($w, $progress, $last_msg, $displayed);
    my $on_expose = sub { $displayed = 1; 0 }; #- declared here to workaround perl limitation
    $w, sub {
	my ($msg, $current, $total) = @_;
	if ($msg) {
	    $last_msg = $msg;
	    if (!$w) {
		$progress = Gtk2::ProgressBar->new if $in->isa('interactive::gtk');
		$w = $in->wait_message('', [ '', if_($progress, $progress) ]);
		if ($progress) {
		    #- don't show by default, only if we are given progress information
		    $progress->hide;
		    $progress->signal_connect(expose_event => $on_expose);
		}
	    }
	    $w->set($msg);
	} elsif ($total) {
	    if ($progress) {
		$progress->set_fraction($current / $total);
		$progress->show;
		$displayed = 0;
		mygtk2::flush() while !$displayed;
	    } else {
		$w->set([ $last_msg, "$current / $total" ]);
	    }
	}
    };
}

1;
