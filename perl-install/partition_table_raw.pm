package partition_table_raw;

use diagnostics;
use strict;

use common qw(:common :system :file);
use devices;
use c;

my @fields = qw(active start_head start_sec start_cyl type end_head end_sec end_cyl start size);
my $format = "C8 I2";
my $magic = "\x55\xAA";
my $nb_primary = 4;

my $offset = $common::SECTORSIZE - length($magic) - $nb_primary * common::psizeof($format);

my @MBR_signatures = (
    [ 'empty', 0, "\0\0\0\0" ],
    [ 'lilo', 0x6,  "LILO" ],
    [ 'osbs', 0x2,  "OSBS" ], #- http://www.prz.tu-berlin.de/~wolf/os-bs.html
    [ 'pqmagic', 0xef, "PQV" ],
    [ 'BootStar', 0x130, "BootStar:" ],
    [ 'DocsBoot', 0x148, 'DocsBoot' ],
    [ 'system_commander', 0x1ad, "SYSCMNDRSYS" ],
    [ 'os2', 0x1c2, "\xA" ],
    [ 'dos', 0xa0, "\x25\x03\x4E\x02\xCD\x13" ],
    [ 'dos', 0x60, "\xBB\x00\x7C\xB8\x01\x02\x57\xCD\x13\x5F\x73\x0C\x33\xC0\xCD\x13" ], #- nt's
    [ 'freebsd', 0xC0, "\x00\x30\xE4\xCD\x16\xCD\x19\xBB\x07\x00\xB4" ],
    [ 'dummy', 0xAC, "\x0E\xB3\x07\x56\xCD\x10\x5E\xEB" ], #- caldera?
    [ 'ranish', 0x100, "\x6A\x10\xB4\x42\x8B\xF4\xCD\x13\x8B\xE5\x73" ],
);

sub typeOfMBR($) { typeFromMagic(devices::make($_[0]), @MBR_signatures) }
sub typeOfMBR_($) { typeFromMagic($_[0], @MBR_signatures) }

sub compute_CHS($$) {
    my ($hd, $e) = @_;
    my @l = qw(cyl head sec);
    @$e{map { "start_$_" } @l} = $e->{start} || $e->{type} ? CHS2rawCHS(sector2CHS($hd, $e->{start})) : (0,0,0);
    @$e{map { "end_$_"   } @l} = $e->{start} || $e->{type} ? CHS2rawCHS(sector2CHS($hd, $e->{start} + $e->{size} - 1)) : (0,0,0);
    1;
}

sub CHS2rawCHS($$$) {
    my ($c, $h, $s) = @_;
    $c = min($c, 1023); #- no way to have a #cylinder >= 1024
    ($c & 0xff, $h, $s | ($c >> 2 & 0xc0));
}

# returns (cylinder, head, sector)
sub sector2CHS($$) {
    my ($hd, $start) = @_;
    my ($s, $h);
    ($start, $s) = divide($start, $hd->{geom}{sectors});
    ($start, $h) = divide($start, $hd->{geom}{heads});
    ($start, $h, $s + 1);
}

sub get_geometry($) {
    my ($dev) = @_;
    my $g = "";

    local *F; sysopen F, $dev, 0 or return;
    ioctl(F, c::HDIO_GETGEO(), $g) or return;

    my %geom; @geom{qw(heads sectors cylinders start)} = unpack "CCSL", $g;

    { geom => \%geom, totalsectors => $geom{heads} * $geom{sectors} * $geom{cylinders} };
}

sub openit($$;$) { sysopen $_[1], $_[0]{file}, $_[2] || 0; }

# cause kernel to re-read partition table
sub kernel_read($) {
    my ($hd) = @_;
    local *F; openit($hd, *F) or return 0;
    $hd->{rebootNeeded} = !ioctl(F, c::BLKRRPART(), 0);
}

sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    local *F; openit($hd, *F) or return;
    c::lseek_sector(fileno(F), $sector, $offset) or die "reading of partition in sector $sector failed";

    my @pt = map {
	sysread F, $tmp, psizeof($format) or return "error while reading partition table in sector $sector";
	my %h; @h{@fields} = unpack $format, $tmp;
	\%h;
    } (1..$nb_primary);

    #- check magic number
    sysread F, $tmp, length $magic or die "error reading magic number";
    $tmp eq $magic or die "bad magic number";

    [ @pt ];
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, type, active
sub write($$$) {
    my ($hd, $sector, $pt) = @_;

    local *F; openit($hd, *F, 2) or die "error opening device $hd->{device} for writing";
    c::lseek_sector(fileno(F), $sector, $offset) or return 0;

    @$pt == $nb_primary or die "partition table does not have $nb_primary entries";
    foreach (@$pt) {
	compute_CHS($hd, $_);
	local $_->{start} = $_->{local_start} || 0;
	$_->{active} ||= 0; $_->{type} ||= 0; $_->{size} ||= 0; #- for no warning
	syswrite F, pack($format, @$_{@fields}), psizeof($format) or return 0;
    }
    syswrite F, $magic, length $magic or return 0;
    1;
}

sub clear_raw { { raw => [ ({}) x $nb_primary ] } }

sub zero_MBR($) {
    my ($hd) = @_;
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    $hd->{primary} = clear_raw();
    delete $hd->{extended};
}

1;
