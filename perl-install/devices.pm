package devices;

use diagnostics;
use strict;

use common qw(:system :file);
use run_program;
use log;
use c;

1;


sub size($) {
    local *F;
    sysopen F, $_[0], 0 or log::l("open $_[0]: $!"), return 0;

    my $valid_offset = sub { sysseek(F, $_[0], 0) && sysread(F, my $a, 1) };

    # first try getting the size nicely
    my $size = 0;
    ioctl(F, c::BLKGETSIZE(), $size) and return unpack("i", $size) * $common::SECTORSIZE;

    # sad it didn't work, well searching the size using the dichotomy algorithm!
    my $low = 0;
    my ($high, $mid);

    # first find n where 2^n < size <= 2^n+1
    for ($high = 1; $high > 0 && &$valid_offset($high); $high *= 2) { $low = $high; }

    while ($low < $high - 1) {
	$mid = int ($low + $high) / 2;
	&$valid_offset($mid) ? $low : $high = $mid;
    }
    $low + 1;
}

sub make($) {
    local $_ = my $file = $_[0];
    my ($type, $major, $minor);
    my ($prefix);

    unless (s,^(.*)/(dev|tmp)/,,) {
	$prefix = $1;
	$file = -e "$prefix/dev/$file" ? "$prefix/dev/$file" : "$prefix/tmp/$file";
    }

    -e $file and return $file; # assume nobody takes fun at creating files named as device

    if (/^sd(.)(\d\d)/) {
	$type = c::S_IFBLK();
	$major = 8;
	$minor = ord($1) - ord('a') + $2;
    } elsif (/^hd(.)(\d{0,2})/) {
	$type = c::S_IFBLK();
	($major, $minor) = 
	    @{ $ {{'a' => [3, 0], 'b' => [3, 64],
		   'c' => [22,0], 'd' => [22,64],
		   'e' => [33,0], 'f' => [33,64],
		   'g' => [34,0], 'h' => [34,64],
	       }}{$1} or die "unknown device $_" };
	$minor += $2 || 0;
    } elsif (/^ram(.)/) {
	$type = c::S_IFBLK();
	$major = 1;
	$minor = $1 eq '' ? 1 : $1;
    } elsif (m|^rd/c(\d+)d(\d+)(p(\d+))?|) {
	# dac 960 "/rd/cXdXXpX"
        $type = c::S_IFBLK();
	$major = 48 + $1;
	$minor = 8 * $2 + $4;
    } elsif (m|ida/c(\d+)d(\d+)(p(\d+))|) {
	# Compaq Smart Array "ida/c0d0{p1}"
	$type = c::S_IFBLK();
	$major = 72 + $1;
	$minor = 16 * $2 + $4;
    } else {
	($type, $major, $minor) = 
	    @{ $ {{"aztcd"   => [ c::S_IFBLK(), 29, 0 ],
		   "bpcd"    => [ c::S_IFBLK(), 41, 0 ],
		   "cdu31a"  => [ c::S_IFBLK(), 15, 0 ],
		   "cdu535"  => [ c::S_IFBLK(), 24, 0 ],
		   "cm206cd" => [ c::S_IFBLK(), 32, 0 ],
		   "tty"     => [ c::S_IFCHR(), 5, 0 ],
		   "fd0"     => [ c::S_IFBLK(), 2, 0 ],
		   "fd1"     => [ c::S_IFBLK(), 2, 1 ],
		   "gscd"    => [ c::S_IFBLK(), 16, 0 ],
		   "lp0"     => [ c::S_IFCHR(), 6, 0 ],
		   "lp1"     => [ c::S_IFCHR(), 6, 1 ],
		   "lp2"     => [ c::S_IFCHR(), 6, 2 ],
		   "mcd"     => [ c::S_IFBLK(), 23, 0 ],
		   "mcdx"    => [ c::S_IFBLK(), 20, 0 ],
		   "nst0"    => [ c::S_IFCHR(), 9, 128 ],
		   "optcd"   => [ c::S_IFBLK(), 17, 0 ],
		   "sbpcd"   => [ c::S_IFBLK(), 25, 0 ],
		   "scd0"    => [ c::S_IFBLK(), 11, 0 ],
		   "scd1"    => [ c::S_IFBLK(), 11, 1 ],
		   "sjcd"    => [ c::S_IFBLK(), 18, 0 ],
	       }}{$_} or die "unknown device $_" };
    }
    
    # make a directory for this inode if needed.
    mkdir dirname($file), 0755;   
    
    syscall_('mknod', $file, $type | 0600, makedev($major, $minor)) or die "mknod failed (dev:$_): $!";

    $file;
}

