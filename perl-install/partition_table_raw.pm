package partition_table_raw; # $Id$

use diagnostics;
use strict;

use common;
use devices;
use detect_devices;
use log;
use c;

my @MBR_signatures = (
if_(arch() =~ /ppc/,
    map { [ 'yaboot', 0, "PM", 0x200 * $_ + 0x10, "bootstrap\0" ] } 0 .. 61
),
    [ 'empty', 0, "\0\0\0\0" ],
    [ 'grub', 0, "\xEBG", 0x17d, "stage1 \0" ],
    [ 'grub', 0, "\xEBH", 0x17e, "stage1 \0" ],
    [ 'grub', 0, "\xEBH", 0x18a, "stage1 \0" ],
    [ 'grub', 0, "\xEBH", 0x181, "GRUB \0" ],
    [ 'lilo', 0x2,  "LILO" ],
    [ 'lilo', 0x6,  "LILO" ],
    [ 'osbs', 0x2,  "OSBS" ], #- http://www.prz.tu-berlin.de/~wolf/os-bs.html
    [ 'pqmagic', 0xef, "PQV" ],
    [ 'BootStar', 0x130, "BootStar:" ],
    [ 'DocsBoot', 0x148, 'DocsBoot' ],
    [ 'system_commander', 0x1ad, "SYSCMNDRSYS" ],
    [ 'Be Os', 0x24, 'Boot Manager' ],
    [ 'TimO', 0, 'IBM Thinkpad hibernation partition' ],
    [ 'dos', 0xa0, "\x25\x03\x4E\x02\xCD\x13" ],
    [ 'dos', 0xa0, "\x00\xB4\x08\xCD\x13\x72" ], #- nt2k's
    [ 'dos', 0x60, "\xBB\x00\x7C\xB8\x01\x02\x57\xCD\x13\x5F\x73\x0C\x33\xC0\xCD\x13" ], #- nt's
    [ 'dos', 0x70, "\x0C\x33\xC0\xCD\x13\x4F\x75\xED\xBE\xA3" ],
    [ 'freebsd', 0xC0, "\x00\x30\xE4\xCD\x16\xCD\x19\xBB\x07\x00\xB4" ],
    [ 'freebsd', 0x160, "\x6A\x10\x89\xE6\x48\x80\xCC\x40\xCD\x13" ],
    [ 'dummy', 0xAC, "\x0E\xB3\x07\x56\xCD\x10\x5E\xEB" ], #- caldera?
    [ 'ranish', 0x100, "\x6A\x10\xB4\x42\x8B\xF4\xCD\x13\x8B\xE5\x73" ],
    [ 'os2', 0x1c2, "\xA" ],
);

sub typeOfMBR($) { typeFromMagic(devices::make($_[0]), @MBR_signatures) }
sub typeOfMBR_($) { typeFromMagic($_[0], @MBR_signatures) }

sub hasExtended { 0 }

sub cylinder_size($) {
    my ($hd) = @_;
    $hd->{geom}{sectors} * $hd->{geom}{heads};
}

#- default method for starting a partition, only head size or twice
#- is allowed for starting a partition after a cylinder boundarie.
sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    $part->{start} = round_up($part->{start},
			      $part->{start} % cylinder_size($hd) < 2 * $hd->{geom}{sectors} ?
   			      $hd->{geom}{sectors} : cylinder_size($hd));
    $part->{size} = $end - $part->{start};
    $part->{size} > 0 or die "adjustStart get a too small partition to handle correctly";
}
#- adjusting end to match a cylinder boundary, two methods are used and must
#- match at the end, else something is wrong and nothing will be done on
#- partition table.
#- $end2 is computed by removing 2 (or only 1 if only 2 heads on drive) groups
#- of sectors, this is necessary to handle extended partition where logical
#- partition start after 1 (or 2 accepted) groups of sectors (typically 63).
#- $end is floating (is not on cylinder boudary) so we have to choice a good
#- candidate, $end1 or $end2 should always be good except $end1 for small
#- partition size.
sub adjustEnd($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};
    my $end1 = round_down($end, cylinder_size($hd));
    my $end2 = round_up($end - ($hd->{geom}{heads} > 2 ? 2 : 1) * $hd->{geom}{sectors}, cylinder_size($hd));
    $end2 <= $hd->{geom}{cylinders} * cylinder_size($hd) or die "adjustEnd go beyond end of device geometry ($end2 > $hd->{totalsectors})";
    $part->{size} = ($end1 - $part->{start} > cylinder_size($hd) ? $end1 : $end2) - $part->{start};
    $part->{size} > 0 or die "adjustEnd get a too small partition to handle correctly";
}

sub get_geometry($) {
    my ($dev) = @_;
    my $g = "";

    local *F; sysopen F, $dev, 0 or return;
    ioctl(F, c::HDIO_GETGEO(), $g) or return;
    my %geom; @geom{qw(heads sectors cylinders start)} = unpack "CCSL", $g;
    $geom{totalcylinders} = $geom{cylinders};

    #- $geom{cylinders} is no good (only a ushort, that means less than 2^16 => at best 512MB)
    if (my $total = c::total_sectors(fileno F)) {
	$geom{cylinders} = int $total / $geom{heads} / $geom{sectors};
    }

    { geom => \%geom, totalsectors => $geom{heads} * $geom{sectors} * $geom{cylinders} };
}

sub openit($$;$) { sysopen $_[1], $_[0]{file}, $_[2] || 0; }

# cause kernel to re-read partition table
sub kernel_read($) {
    my ($hd) = @_;
    common::sync();
    local *F; openit($hd, *F) or return 0;
    common::sync(); sleep(1);
    $hd->{rebootNeeded} = !ioctl(F, c::BLKRRPART(), 0);
    common::sync();
    close F;
    common::sync(); sleep(1);
}

sub zero_MBR {
    my ($hd) = @_;
    #- force the standard partition type for the architecture
    my $type = arch() eq "alpha" ? "bsd" : arch() =~ /^sparc/ ? "sun" : arch() eq "ppc" ? "mac" : "dos";
    #- override standard mac type on PPC for IBM machines to dos
    $type = "dos" if (arch() =~ /ppc/ && detect_devices::get_mac_model() =~ /^IBM/);
    require("partition_table_$type.pm");
    bless $hd, "partition_table_$type";
    $hd->{primary} = $hd->clear_raw();
    delete $hd->{extended};
}

sub zero_MBR_and_dirty {
    my ($hd) = @_;
    zero_MBR($hd);
    $hd->{isDirty} = $hd->{needKernelReread} = 1;

}

#- ugly stuff needed mainly for Western Digital IDE drives
#- try writing what we've just read, yells if it fails
#- testing on last sector of head #0 (unused in 99% cases)
#-
#- return false if the device can't be written to (especially for Smartmedia)
sub test_for_bad_drives {
    my ($hd) = @_;

    log::l("test_for_bad_drives($hd->{file})");
    my $sector = $hd->{geom}{sectors} - 1;
    

    local *F; openit($hd, *F, 2) or return;

    my $seek = sub {
	c::lseek_sector(fileno(F), $sector, 0) or die "seeking to sector $sector failed";
    };
    my $tmp;

    &$seek; sysread F, $tmp, $SECTORSIZE or die "test_for_bad_drives: can't even read ($!)";
    &$seek; syswrite F, $tmp or die "test_for_bad_drives: can't even write ($!)";

    my $tmp2;
    &$seek; sysread F, $tmp2, $SECTORSIZE or die "test_for_bad_drives: can't even read again ($!)";
    $tmp eq $tmp2 or die
_("Something bad is happening on your drive. 
A test to check the integrity of data has failed. 
It means writing anything on the disk will end up with random trash");
    1;
}

1;
