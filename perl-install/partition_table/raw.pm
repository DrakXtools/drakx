package partition_table::raw; # $Id$

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
    [ 'grub', 0x6,  "GRUB" ],
    [ 'osbs', 0x2,  "OSBS" ], #- http://www.prz.tu-berlin.de/~wolf/os-bs.html
    [ 'pqmagic', 0xef, "PQV" ],
    [ 'BootStar', 0x130, "BootStar:" ],
    [ 'DocsBoot', 0x148, 'DocsBoot' ],
    [ 'system_commander', 0x1ad, "SYSCMNDRSYS" ],
    [ 'Be Os', 0x24, 'Boot Manager' ],
    [ 'os2', 0, "\xFA\xB8\x30\x00", 0xfA, "OS/2" ],
    [ 'TimO', 0, 'IBM Thinkpad hibernation partition' ],
    [ 'dos', 0xa0, "\x25\x03\x4E\x02\xCD\x13" ],
    [ 'dos', 0xa0, "\x00\xB4\x08\xCD\x13\x72" ], #- nt2k's
    [ 'dos', 0x60, "\xBB\x00\x7C\xB8\x01\x02\x57\xCD\x13\x5F\x73\x0C\x33\xC0\xCD\x13" ], #- nt's
    [ 'dos', 0x70, "\x0C\x33\xC0\xCD\x13\x4F\x75\xED\xBE\xA3" ],
    [ 'freebsd', 0xC0, "\x00\x30\xE4\xCD\x16\xCD\x19\xBB\x07\x00\xB4" ],
    [ 'freebsd', 0x160, "\x6A\x10\x89\xE6\x48\x80\xCC\x40\xCD\x13" ],
    [ 'dummy', 0xAC, "\x0E\xB3\x07\x56\xCD\x10\x5E\xEB" ], #- caldera?
    [ 'ranish', 0x100, "\x6A\x10\xB4\x42\x8B\xF4\xCD\x13\x8B\xE5\x73" ],
    [ 'os2', 0x1c2, "\x0A" ],
    [ 'Acronis', 0, "\xE8\x12\x01" ],
);

sub typeOfMBR($) { typeFromMagic(devices::make($_[0]), @MBR_signatures) }
sub typeOfMBR_($) { typeFromMagic($_[0], @MBR_signatures) }

sub hasExtended { 0 }
sub set_best_geometry_for_the_partition_table {}

sub cylinder_size($) {
    my ($hd) = @_;
    $hd->{geom}{sectors} * $hd->{geom}{heads};
}
sub first_usable_sector { 1 }
sub last_usable_sector { 
    my ($hd) = @_;
    $hd->{totalsectors};
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
    $end > $hd->{geom}{cylinders} * cylinder_size($hd) && $end <= $hd->{totalsectors} and return;
    my $end1 = round_down($end, cylinder_size($hd));
    my $end2 = round_up($end - ($hd->{geom}{heads} > 2 ? 2 : 1) * $hd->{geom}{sectors}, cylinder_size($hd));
    $end2 <= $hd->{geom}{cylinders} * cylinder_size($hd) or die "adjustEnd go beyond end of device geometry ($end2 > $hd->{totalsectors})";
    $part->{size} = ($end1 - $part->{start} > cylinder_size($hd) ? $end1 : $end2) - $part->{start};
    $part->{size} > 0 or internal_error("adjustEnd get a too small partition to handle correctly");
}

sub compute_nb_cylinders {
    my ($geom, $totalsectors) = @_;
    $geom->{cylinders} = int $totalsectors / $geom->{heads} / $geom->{sectors};
}

sub get_geometry($) {
    my ($dev) = @_;
    my $g = "";

    sysopen(my $F, $dev, 0) or return;
    ioctl($F, c::HDIO_GETGEO(), $g) or return;
    my %geom; @geom{qw(heads sectors cylinders start)} = unpack "CCSL", $g;
    $geom{totalcylinders} = $geom{cylinders};

    my $total;
    #- $geom{cylinders} is no good (only a ushort, that means less than 2^16 => at best 512MB)
    if ($total = c::total_sectors(fileno $F)) {
	compute_nb_cylinders(\%geom, $total);
    } else {
	$total = $geom{heads} * $geom{sectors} * $geom{cylinders}
    }

    { geom => \%geom, totalsectors => $total };
}

sub openit { 
    my ($hd, $o_mode) = @_;
    my $F; sysopen($F, $hd->{file}, $o_mode || 0) && $F;
}

sub raw_removed {
    my ($_hd, $_raw) = @_;
}
sub can_raw_add {
    my ($hd) = @_;
    $_->{size} || $_->{pt_type} or return 1 foreach @{$hd->{primary}{raw}};
    0;
}
sub raw_add {
    my ($_hd, $raw, $part) = @_;

    foreach (@$raw) {
	$_->{size} || $_->{pt_type} and next;
	$_ = $part;
	return;
    }
    die "raw_add: partition table already full";
}

sub zero_MBR {
    my ($hd) = @_;
    #- force the standard partition type for the architecture
    my $type = arch() =~ /ia64/ ? 'gpt' : arch() eq "alpha" ? "bsd" : arch() =~ /^sparc/ ? "sun" : arch() eq "ppc" ? "mac" : "dos";
    #- override standard mac type on PPC for IBM machines to dos
    $type = "dos" if arch() =~ /ppc/ && detect_devices::get_mac_model() =~ /^IBM/;
    require "partition_table/$type.pm";
    bless $hd, "partition_table::$type";
    $hd->{primary} = $hd->clear_raw;
    delete $hd->{extended};
}

sub zero_MBR_and_dirty {
    my ($hd) = @_;    
    my @parts = (partition_table::get_normal_parts($hd), if_($hd->{primary}{extended}, $hd->{primary}{extended}));
    partition_table::will_tell_kernel($hd, del => $_) foreach @parts;
    zero_MBR($hd);
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
    
    sub error { die "$_[0] error: $_[1]" }

    my $F = openit($hd, $::testing ? 0 : 2) or error(openit($hd) ? 'write' : 'read', "can't open device");

    my $seek = sub {
	c::lseek_sector(fileno($F), $sector, 0) or error('read', "seeking to sector $sector failed");
    };
    my $tmp;

    &$seek; sysread $F, $tmp, $SECTORSIZE or error('read', "can't even read ($!)");
    return if $hd->{readonly} || $::testing;
    &$seek; syswrite $F, $tmp or error('write', "can't even write ($!)");

    my $tmp2;
    &$seek; sysread $F, $tmp2, $SECTORSIZE or die "test_for_bad_drives: can't even read again ($!)";
    $tmp eq $tmp2 or die
N("Something bad is happening on your drive. 
A test to check the integrity of data has failed. 
It means writing anything on the disk will end up with random, corrupted data.");
}

1;
