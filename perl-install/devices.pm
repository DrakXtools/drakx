package devices; # $Id$

use diagnostics;
use strict;

use common;
use run_program;
use log;
use c;

sub size($) {
    local *F;
    sysopen F, $_[0], 0 or log::l("open $_[0]: $!"), return 0;

    my $valid_offset = sub { sysseek(F, $_[0], 0) && sysread(F, my $a, 1) };

    #- first try getting the size nicely
    if (my $size = c::total_sectors(fileno F)) {
	return $size * $common::SECTORSIZE;
    }

    #- sad it didn't work, well searching the size using the dichotomy algorithm!
    my $low = 0;
    my ($high, $mid);

    #- first find n where 2^n < size <= 2^n+1
    for ($high = 1; $high > 0 && &$valid_offset($high); $high *= 2) { $low = $high }

    while ($low < $high - 1) {
	$mid = int ($low + $high) / 2;
	&$valid_offset($mid) ? $low : $high = $mid;
    }
    $low + 1;
}

sub del_loop {
    my ($dev) = @_;
    run_program::run("losetup", "-d", $dev);
}
sub find_free_loop {
    foreach (0..7) {
	my $dev = make("loop$_");
	local *F;
	sysopen F, $dev, 2 or next;
	!ioctl(F, c::LOOP_GET_STATUS(), my $tmp) && $! == 6 or next; #- 6 == ENXIO
	close F;
	return $dev;
    }
    die "no free loop found";
}
sub set_loop {
    my ($file, $encrypt_key, $encryption) = @_;
    my $dev = find_free_loop();

    if ($encrypt_key && $encryption) {
	my $cmd = "losetup -p 0 -e $encryption $dev $file";
	log::l("calling $cmd");
	local *F;
	open F, "|$cmd";
	print F $encrypt_key;
	close F or die "losetup failed";
    } else {
	run_program::run("losetup", $dev, $file) or return;
    }
    $dev;
}

sub entry {
    my ($type, $major, $minor);
    local ($_) = @_;

    if (/^0x([\da-f]{3,4})$/i) {
	$type = c::S_IFBLK();
	($major, $minor) = unmakedev(hex $1);
    } elsif (/^sd(.)(\d{0,2})/) {
	$type = c::S_IFBLK();
	$major = 8;
	$minor = 16 * (ord($1) - ord('a')) + ($2 || 0);
    } elsif (/^hd(.)(\d{0,2})/) {
	$type = c::S_IFBLK();
	($major, $minor) =
	    @{ $ {{'a' => [3, 0], 'b' => [3, 64],
		   'c' => [22,0], 'd' => [22,64],
		   'e' => [33,0], 'f' => [33,64],
		   'g' => [34,0], 'h' => [34,64],
		   'i' => [56,0], 'j' => [56,64],
		   'k' => [57,0], 'l' => [57,64],
                   'm' => [88,0], 'n' => [88,64],
                   'o' => [89,0], 'p' => [89,64],
                   'q' => [90,0], 'r' => [90,64],
                   's' => [91,0], 't' => [91,64],
	       }}{$1} or die "unknown device $_" };
	$minor += $2 || 0;
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
    } elsif (m,(ataraid)/d(\d+)(?:p(\d+))?,) {
	# ATA raid "ataraid/d0{p1}"
	$type = c::S_IFBLK();
	$major = 114;
	$minor = 16 * $1 + ($2 || 0);
    } elsif (/(.*?)(\d+)$/) {
	    ($type, $major, $minor) =
	     @{ ${{"fd"          => [ c::S_IFBLK(), 2,  0 ],
		   "hidbp-mse-"  => [ c::S_IFCHR(), 10, 32 ],
		   "lp"          => [ c::S_IFCHR(), 6,  0 ],
		   "usb/lp"      => [ c::S_IFCHR(), 180, 0 ],
		   "input/event" => [ c::S_IFCHR(), 13, 64 ],
		   "loop"        => [ c::S_IFBLK(), 7,  0 ],
		   "md"          => [ c::S_IFBLK(), 9,  0 ],
		   "nst"         => [ c::S_IFCHR(), 9, 128],
		   "scd"         => [ c::S_IFBLK(), 11, 0 ],
		   "ttyS"        => [ c::S_IFCHR(), 4, 64 ],
	       }}{$1}};
	    $minor += $2;
    }
    unless ($type) {
	($type, $major, $minor) =
	     @{ ${{"aztcd"   => [ c::S_IFBLK(), 29, 0 ],
		   "bpcd"    => [ c::S_IFBLK(), 41, 0 ],
		   "cdu31a"  => [ c::S_IFBLK(), 15, 0 ],
		   "cdu535"  => [ c::S_IFBLK(), 24, 0 ],
		   "cm206cd" => [ c::S_IFBLK(), 32, 0 ],
		   "gscd"    => [ c::S_IFBLK(), 16, 0 ],
		   "mcd"     => [ c::S_IFBLK(), 23, 0 ],
		   "mcdx"    => [ c::S_IFBLK(), 20, 0 ],
		   "mem"     => [ c::S_IFCHR(), 1,  1 ],
		   "optcd"   => [ c::S_IFBLK(), 17, 0 ],
		   "kbd"     => [ c::S_IFCHR(), 11, 0 ],
		   "psaux"   => [ c::S_IFCHR(), 10, 1 ],
		   "atibm"   => [ c::S_IFCHR(), 10, 3 ],
		   "random"  => [ c::S_IFCHR(), 1,  8 ],
		   "sbpcd"   => [ c::S_IFBLK(), 25, 0 ],
		   "sjcd"    => [ c::S_IFBLK(), 18, 0 ],
		   "tty"     => [ c::S_IFCHR(),  5, 0 ],
		   "usbmouse"=> [ c::S_IFCHR(), 13, 63], #- aka /dev/input/mice
		   "adbmouse"=> [ c::S_IFCHR(), 10, 10], #- PPC
		   "zero"    => [ c::S_IFCHR(), 1,  5 ],		     
	       }}{$_} or die "unknown device $_ (caller is " . join(":", caller()) . ")" };
    }
    ($type, $major, $minor);
}


sub make($) {
    local $_ = my $file = $_[0];

    if (m,^(.*/(?:dev|tmp))/(.*),) {
	$_ = $2;
    } else {
	$file =~ m|^/| && -e $file or $file = "/tmp/$_";
	$file =~ m|^/| && -e $file or $file = "/dev/$_";
    }
    -e $file and return $file; #- assume nobody takes fun at creating files named as device

    my ($type, $major, $minor) = eval { entry($_) };
    $@ and die "unknown device $_ (caller is " . join(":", caller()) . ")";

    if ($file =~ m|/dev/| && -e '/dev/.devfsd') {
	#- argh, creating devices is no good with devfs...
	#- return the file even if the device file doesn't exist
	#- the caller will fail or not, better compatibility than raising an exception here
	return $file;
    }

    #- make a directory for this inode if needed.
    mkdir dirname($file), 0755;

    syscall_('mknod', $file, $type | 0600, makedev($major, $minor)) or die "mknod failed (dev $_): $!";

    $file;
}


#- only isomorphic entries are allowed, 
#- i.e. entries which can go devfs -> normal and normal -> devfs
my %to_devfs = (
    psaux => 'misc/psaux',
    usbmouse => 'input/mice',
);
my %to_devfs_prefix = (
    ttyS => 'tts/',
);

sub to_devfs {
    my ($dev) = @_;
    if (my $r = $to_devfs{$dev}) { 
	return $r;
    } elsif ($dev =~ /(.*?)(\d+)$/) {
	my $r = $to_devfs_prefix{$1};
	return "$r$2" if $r;
    }
    undef;
}

sub from_devfs {
    my ($dev) = @_;
    my %from_devfs = reverse %to_devfs;
    if (my $r = $from_devfs{$dev}) { 
	return $r;
    } elsif ($dev =~ /(.*?)(\d+)$/) {
	my %from_devfs_prefix = reverse %to_devfs_prefix;
	my $r = $from_devfs_prefix{$1};
	return "$r$2" if $r;
    }
    undef;
}

1;
