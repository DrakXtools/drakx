package partition_table_raw;

use diagnostics;
use strict;

use common qw(:common :system :file);
use devices;
use c;

my @MBR_signatures = (
    [ 'empty', 0, "\0\0\0\0" ],
    [ 'lilo', 0x2,  "LILO" ],
    [ 'lilo', 0x6,  "LILO" ],
    [ 'osbs', 0x2,  "OSBS" ], #- http://www.prz.tu-berlin.de/~wolf/os-bs.html
    [ 'pqmagic', 0xef, "PQV" ],
    [ 'BootStar', 0x130, "BootStar:" ],
    [ 'DocsBoot', 0x148, 'DocsBoot' ],
    [ 'system_commander', 0x1ad, "SYSCMNDRSYS" ],
    [ 'Be Os', 0x24, 'Boot Manager' ],
    [ 'TimO', 0, 'IBM Thinkpad hibernation partition' ],
    [ 'os2', 0x1c2, "\xA" ],
    [ 'dos', 0xa0, "\x25\x03\x4E\x02\xCD\x13" ],
    [ 'dos', 0x60, "\xBB\x00\x7C\xB8\x01\x02\x57\xCD\x13\x5F\x73\x0C\x33\xC0\xCD\x13" ], #- nt's
    [ 'freebsd', 0xC0, "\x00\x30\xE4\xCD\x16\xCD\x19\xBB\x07\x00\xB4" ],
    [ 'dummy', 0xAC, "\x0E\xB3\x07\x56\xCD\x10\x5E\xEB" ], #- caldera?
    [ 'ranish', 0x100, "\x6A\x10\xB4\x42\x8B\xF4\xCD\x13\x8B\xE5\x73" ],
);

sub typeOfMBR($) { typeFromMagic(devices::make($_[0]), @MBR_signatures) }
sub typeOfMBR_($) { typeFromMagic($_[0], @MBR_signatures) }

sub hasExtended { 0 }

sub cylinder_size($) {
    my ($hd) = @_;
    $hd->{geom}{sectors} * $hd->{geom}{heads};
}

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    $part->{start} = round_up($part->{start},
			       $part->{start} % cylinder_size($hd) < 2 * $hd->{geom}{sectors} ?
			       $hd->{geom}{sectors} : cylinder_size($hd));
    $part->{size} = $end - $part->{start};
}
sub adjustEnd($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};
    my $end2 = round_down($end, cylinder_size($hd));
    unless ($part->{start} < $end2) {
	$end2 = round_up($end, cylinder_size($hd));
    }
    $part->{size} = $end2 - $part->{start};
}

sub get_geometry($) {
    my ($dev) = @_;
    my $g = "";

    local *F; sysopen F, $dev, 0 or return;
    ioctl(F, c::HDIO_GETGEO(), $g) or return;

    my %geom; @geom{qw(heads sectors cylinders start)} = unpack "CCSL", $g;
    $geom{totalcylinders} = $geom{cylinders};

    { geom => \%geom, totalsectors => $geom{heads} * $geom{sectors} * $geom{cylinders} };
}

sub openit($$;$) { sysopen $_[1], $_[0]{file}, $_[2] || 0; }

# cause kernel to re-read partition table
sub kernel_read($) {
    my ($hd) = @_;
    sync();
    local *F; openit($hd, *F) or return 0;
    sync(); sleep(1);
    $hd->{rebootNeeded} = !ioctl(F, c::BLKRRPART(), 0);
    sync(); sleep(1);
    $hd->{rebootNeeded} = !ioctl(F, c::BLKRRPART(), 0);
    sync();
    close F;
    sync(); sleep(1);
}

sub zero_MBR($) {
    my ($hd) = @_;
#    unless (ref($hd) =~ /partition_table/) {
	my $type = arch() eq "alpha" ? "bsd" : arch() =~ /^sparc/ ? "sun" : "dos";
	bless $hd, "partition_table_$type";
#    }
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    $hd->{primary} = $hd->clear_raw();
    delete $hd->{extended};
}

1;
