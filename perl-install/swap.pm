package swap; # $Id$

use diagnostics;
use strict;

use MDK::Common::DataStructure;
use common;
use log;
use devices;
use c;


my $pagesize = c::getpagesize();
my $signature_page = "\0" x $pagesize;

# Maximum allowable number of pages in one swap.
# From 2.2.0 onwards, this depends on how many offset bits
# the architectures can actually store into the page tables
# and on 32bit architectures it is limited to 2GB at the
# same time.
# Old swap format keeps the limit of 8*pagesize*(pagesize - 10)

my $V0_MAX_PAGES = 8 * $pagesize - 10;
my $V1_OLD_MAX_PAGES = int 0x7fffffff / $pagesize - 1;
my $V1_MAX_PAGES = $V1_OLD_MAX_PAGES; #- (1 << 24) - 1;
my $MAX_BADPAGES = int(($pagesize - 1024 - 128 * $sizeof_int - 10) / $sizeof_int);
my $signature_format_v1 = "x1024 I I I I125"; #- bootbits, version, last_page, nr_badpages, padding

1;

sub kernel_greater_or_equal($$$) {
    c::kernel_version() =~ /(\d*)\.(\d*)\.(\d*)/;
    ($1 <=> $_[0] || $2 <=> $_[1] || $3 <=> $_[2]) >= 0;
}

sub check_blocks {
    my ($fd, $version, $nbpages) = @_;
    my ($last_read_ok, $badpages) = (0, 0);
    my ($buffer);
    my $badpages_field_v1 = \substr($signature_page, psizeof($signature_format_v1));

    for (my $i = 0; $i < $nbpages; $i++) {

	$last_read_ok || sysseek($fd, $i * $pagesize, 0) or die "seek failed";

	unless ($last_read_ok = sysread($fd, $buffer, $pagesize)) {
	    if ($version == 1) {
		$badpages == $MAX_BADPAGES and die "too many bad pages";
		vec($$badpages_field_v1, $badpages, $bitof_int) = $i;
	    }
	    $badpages++;
	}
	vec($signature_page, $i, 1) = to_bool($last_read_ok) if $version == 0;
    }

    #- TODO: add interface

    $badpages and log::l("$badpages bad pages\n");
    return $badpages;
}

sub make($;$) {
    my ($devicename, $checkBlocks) = @_;
    my $badpages = 0;
    my ($version, $maxpages);

    $devicename = devices::make($devicename);

    my $nbpages = divide(devices::size($devicename), $pagesize);

    if ($nbpages <= $V0_MAX_PAGES || !kernel_greater_or_equal(2,1,117) || $pagesize < 2048) {
	$version = 0;
    } else {
	$version = 1;
    }

    $nbpages >= 10 or die "swap area needs to be at least " . 10 * $pagesize / 1024 . "kB";

    -b $devicename or $checkBlocks = 0;
    my $rdev = (stat $devicename)[6];
    $rdev == 0x300 || $rdev == 0x340 and die "$devicename is not a good device for swap";

    local *F;
    sysopen F, $devicename, 2 or die "opening $devicename for writing failed: $!";

    if ($version == 0) { $maxpages = $V0_MAX_PAGES }
    elsif (kernel_greater_or_equal(2,2,1)) { $maxpages = $V1_MAX_PAGES }
    else { $maxpages = min($V1_OLD_MAX_PAGES, $V1_MAX_PAGES) }

    if ($nbpages > $maxpages) {
	$nbpages = $maxpages;
	log::l("warning: truncating swap area to " . $nbpages * $pagesize / 1024 . "kB");
    }

    if ($checkBlocks) {
	$badpages = check_blocks(*F, $version, $nbpages);
    } elsif ($version == 0) {
	for (my $i = 0; $i < $nbpages; $i++) { vec($signature_page, $i, 1) = 1 }
    }

    $version == 0 and !vec($signature_page, 0, 1) and die "bad block on first page";
    vec($signature_page, 0, 1) = 0;

    $version == 1 and MDK::Common::DataStructure::strcpy($signature_page, pack($signature_format_v1, $version, $nbpages - 1, $badpages));

    my $goodpages = $nbpages - $badpages - 1;
    $goodpages > 0 or die "all blocks are bad";

    log::l("Setting up swapspace on $devicename version $version, size = " . $goodpages * $pagesize . " bytes");

    MDK::Common::DataStructure::strcpy($signature_page, $version == 0 ? "SWAP-SPACE" : "SWAPSPACE2", $pagesize - 10);

    my $offset = $version == 0 ? 0 : 1024;
    sysseek(F, $offset, 0) or die "unable to rewind swap-device: $!";

    syswrite(F, substr($signature_page, $offset)) or die "unable to write signature page: $!";

    #- A subsequent swapon() will fail if the signature is not actually on disk. (This is a kernel bug.)
    syscall_('fsync', fileno(F)) or die "fsync failed: $!";
    close F;
}

sub enable($;$) {
    my ($devicename, $checkBlocks) = @_;
    make($devicename, $checkBlocks);
    swapon($devicename);
}

sub swapon($) {
    log::l("swapon called with $_[0]");
    syscall_('swapon', devices::make($_[0]), 0) or die "swapon($_[0]) failed: $!";
}

sub swapoff($) {
    syscall_('swapoff', devices::make($_[0])) or die "swapoff($_[0]) failed: $!";
}
