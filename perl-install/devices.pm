package devices;

use diagnostics;
use strict;

use common;
use run_program;
use log;
use c;

sub del_loop {
    my ($dev) = @_;
    run_program::run("losetup", "-d", $dev);
}
sub find_free_loop() {
    foreach (0..255) {
	my $dev = make("loop$_");
	sysopen(my $F, $dev, 2) or next;
	!ioctl($F, c::LOOP_GET_STATUS(), my $_tmp) && $! == 6 or next; #- 6 == ENXIO
	return $dev;
    }
    die "no free loop found";
}
sub set_loop {
    my ($file, $o_encrypt_key, $o_encryption) = @_;
    require modules;
    eval { modules::load('loop') };
    my $dev = find_free_loop();

    if ($o_encrypt_key && $o_encryption) {
	eval { modules::load('cryptoloop', list_modules::category2modules('various/crypto')) };
	my $cmd = "losetup -p 0 -e $o_encryption $dev $file";
	log::l("calling $cmd");
	open(my $F, "|$cmd");
	print $F $o_encrypt_key;
	close $F or die "losetup failed";
    } else {
	run_program::run("losetup", $dev, $file)
	    || run_program::run("losetup", "-r", $dev, $file) or return;
    }
    $dev;
}

sub find_compressed_image {
    my ($name) = @_;
    foreach (0..255) {
	my $dev = make("loop$_");
	my ($file) = `losetup $dev 2>/dev/null` =~ m!\((.*?)\)! or return;
	$file =~ s!^/sysroot/!/!;
	basename($file) eq $name and return $dev, $file;
    }
    undef;
}

sub init_device_mapper() {
    require modules;
    eval { modules::load('dm-mod') };
}

sub entry {
    my ($type, $major, $minor);
    local ($_) = @_;

    if (/^0x([\da-f]{3,4})$/i) {
	$type = c::S_IFBLK();
	($major, $minor) = unmakedev(hex $1);
    } elsif (/^ram(.*)/) {
	$type = c::S_IFBLK();
	$major = 1;
	$minor = $1 eq '' ? 1 : $1;
    } elsif (m|^rd/c(\d+)d(\d+)(p(\d+))?|) {
	# dac 960 "rd/cXdXXpX"
        $type = c::S_IFBLK();
	$major = 48 + $1;
	$minor = 8 * $2 + $4;
    } elsif (m,(ida|cciss)/c(\d+)d(\d+)(?:p(\d+))?,) {
	# Compaq Smart Array "ida/c0d0{p1}"
	$type = c::S_IFBLK();
	$major = ($1 eq 'ida' ? 72 : 104) + $2;
	$minor = 16 * $3 + ($4 || 0);
    } elsif (my ($prefix, $nb) = /(.*?)(\d+)$/) {	
	my $f = ${{
		   "md"          => sub { c::S_IFBLK(), 9,  0  },
		   "ubd/"        => sub { c::S_IFBLK(), 98, 0  },
	       }}{$prefix};
	if ($f) {
	    ($type, $major, $minor) = $f->();
	    $minor += $nb;
        }
    }
    unless ($type) {
	($type, $major, $minor) =
	     @{ ${{
		   "atibm"    => [ c::S_IFCHR(), 10, 3  ],
	       }}{$_} || [] };
    }
    # Lookup non listed devices in /sys
    unless ($type) {
	my $sysdev;
        if (m!input/(.*)! && -e "/sys/class/input/$1/dev") {
	    $sysdev = "/sys/class/input/$1/dev";
	    $type = c::S_IFCHR();
	} elsif (-e "/sys/block/$_/dev") {
	    $sysdev = "/sys/block/$_/dev";
	    $type = c::S_IFBLK();
        } elsif (/^(.+)(\d+)$/ && -e "/sys/block/$1/$_/dev") {
	    $sysdev = "/sys/block/$1/$_/dev";
	    $type = c::S_IFBLK();
        }
        ($major, $minor) = split(':', chomp_(cat_($sysdev)));
    }
    # Lookup partitions in /proc/partitions in case /sys was not available
    unless ($type) {
       	if (-e "/proc/partitions") {
	    if (cat_("/proc/partitions") =~ /^\s*(\d+)\s+(\d+)\s+\d+\s+$_$/m) { 
		($major, $minor) = ($1, $2);
		$type = c::S_IFBLK();
	    }
	}
    }
    # Try to access directly the device
    # Now device mapper devices are links and do not appear in /proc or /sys
    unless ($type) {
	if (-e "/dev/$_") {
	    my (undef, undef, $mode, undef, undef, undef, $rdev, undef) = stat("/dev/$_");
	    ($major, $minor) = unmakedev($rdev);
	    $type = $mode & c::S_IFMT();
	}
    }

    $type or internal_error("unknown device $_");
    ($type, $major, $minor);
}


sub make($) {
    local $_ = my $file = $_[0];

    if (m!^(.*/dev)/(.*)!) {
	$_ = $2;
    } else {
	$file =~ m|^/| && -e $file or $file = "/dev/$_";
    }
    -e $file and return $file; #- assume nobody takes fun at creating files named as device

    my ($type, $major, $minor) = entry($_);

    #- make a directory for this inode if needed.
    mkdir_p(dirname($file));

    syscall_('mknod', $file, $type | 0600, makedev($major, $minor)) or do {
        die "mknod failed (dev $_): $!" if ! -e $file; # we may have raced with udev
    };

    $file;
}

sub simple_partition_scan {
    my ($part) = @_;
    $part->{device} =~ /((?:[hsv]|xv)d[a-z]|mmcblk|nvme\d+p)(\d+)$/;
}
sub part_number {
    my ($part) = @_;
    (simple_partition_scan($part))[1];
}
sub part_prefix {
    my ($part) = @_;
    (simple_partition_scan($part))[0];
}

sub prefix_for_dev {
    my ($dev) = @_;
    $dev . ($dev =~ /\d$/ ? 'p' : '');
}

sub should_prefer_UUID {
    my ($dev) = @_;
    $dev =~ /^((?:[hsvm]|xv)d)/;
}

sub symlink_now_and_register {
    my ($if_struct, $of) = @_;
    my $if = $if_struct->{device};

    #- add a static udev device node, we can't do it with a udev rule,
    #- eg, ttySL0 is a symlink created by a daemon
    symlinkf($if, "$::prefix/lib/udev/devices/$of");

    symlinkf($if, "/dev/$of");
}


1;
