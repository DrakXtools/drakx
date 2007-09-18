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
    (map { [ 'yaboot', 0, "PM", 0x200 * $_ + 0x10, "bootstrap\0" ] } 0 .. 61), #- "PM" is a Partition Map
    [ 'yaboot', 0x400, "BD", 0x424, "\011bootstrap" ], #- "BD" is a HFS filesystem
),
    [ 'empty', 0, "\0\0\0\0" ],
    [ 'grub', 0, "\xEBG", 0x17d, "stage1 \0" ],
    [ 'grub', 0, "\xEBH", 0x17e, "stage1 \0" ],
    [ 'grub', 0, "\xEBH", 0x18a, "stage1 \0" ],
    sub { my ($F) = @_;
	  #- standard grub has no good magic (Mandriva's grub is patched to have "GRUB" at offset 6)
	  #- so scanning a range of possible places where grub can have its string
	  #- 0x176 found on Conectiva 10
	  my ($min, $max, $magic) = (0x176, 0x181, "GRUB \0");
	  my $tmp;
	  sysseek($F, 0, 0) && sysread($F, $tmp, $max + length($magic)) or return;
	  substr($tmp, 0, 2) eq "\xEBH" or return;
	  index($tmp, $magic, $min) >= 0 && "grub";
      },
    [ 'lilo', 0x2,  "LILO" ],
    [ 'lilo', 0x6,  "LILO" ],
    [ 'lilo', 0x6 + 0x40,  "LILO" ], #- when relocated in lilo's bsect_update(), variable "space" on paragraph boundary gives 0x40
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

sub use_pt_type { 0 }
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
    if ($geom->{heads} && $geom->{sectors}) {
	$geom->{cylinders} = int $totalsectors / $geom->{heads} / $geom->{sectors};
    }
}

sub keep_non_duplicates {
    my %l;
    $l{$_->[0]}++ foreach @_;
    map { @$_ } grep { $l{$_->[0]} == 1 } @_;
}

sub get_geometries {
    my (@hds) = @_;

    @hds = grep {
	if (my $h = get_geometry($_->{file})) {
	    add2hash_($_, $h);
	    1;
	} else {
	    log::l("An error occurred while getting the geometry of block device $_->{file}: $!");
	    0;
	}
    } @hds;

    my %id2hd = keep_non_duplicates(map {
	my $F = openit($_) or log::l("failed to open device $_->{device}");
	my $tmp;
	if ($F && c::lseek_sector(fileno($F), 0, 0x1b8) && sysread($F, $tmp, 4)) {
	    [ sprintf('0x%08x', unpack('V', $tmp)), $_ ];
	} else {
	    ();
	}
    } @hds);


    my %id2edd = keep_non_duplicates(map { [ chomp_(cat_("$_/mbr_signature")), $_ ] } glob("/sys/firmware/edd/int13_dev*"));

    log::l("id2hd: " . join(' ', map_each { "$::a=>$::b->{device}" } %id2hd));
    log::l("id2edd: " . join(' ', map_each { "$::a=>$::b" } %id2edd));

    foreach my $id (keys %id2hd) {
	my $hd = $id2hd{$id};
	$hd->{volume_id} = $id;

	if (my $edd_dir = $id2edd{$id}) {
	    $hd->{bios_from_edd} = $1 if $edd_dir =~ /int13_dev(.*)/;

	    require partition_table::dos;
	    my $geom = partition_table::dos::geometry_from_edd($hd, $edd_dir);
	    $hd->{geom} = $geom if $geom;
	}
    }

    @hds;
}

sub get_geometry {
    my ($dev) = @_;
    sysopen(my $F, $dev, 0) or return;

    my $total = c::total_sectors(fileno $F);

    my $g = "";
    my %geom;
    if (ioctl($F, c::HDIO_GETGEO(), $g)) {
	@geom{qw(heads sectors cylinders start)} = unpack "CCSL", $g;
	log::l("HDIO_GETGEO on $dev succeeded: heads=$geom{heads} sectors=$geom{sectors} cylinders=$geom{cylinders} start=$geom{start}");
	$geom{totalcylinders} = $geom{cylinders};

	#- $geom{cylinders} is no good (only a ushort, that means less than 2^16 => at best 512MB)
	if ($total) {
	    compute_nb_cylinders(\%geom, $total);
	} else {
	    $total = $geom{heads} * $geom{sectors} * $geom{cylinders};
	}
    }

    { totalsectors => $total, if_($geom{heads}, geom => \%geom) };
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

sub default_type {
    my $type = arch() =~ /ia64/ ? 'gpt' : arch() eq "alpha" ? "bsd" : arch() =~ /^sparc/ ? "sun" : arch() eq "ppc" ? "mac" : "dos";
    #- override standard mac type on PPC for IBM machines to dos
    $type = "dos" if arch() =~ /ppc/ && detect_devices::get_mac_model() =~ /^IBM/;
    require "partition_table/$type.pm";
    "partition_table::$type";
}

sub zero_MBR {
    my ($hd) = @_;
    #- force the standard partition type for the architecture
    my $type = default_type();
    $type->initialize($hd);
    delete $hd->{extended};
    if (detect_devices::is_xbox()) {
        my $part = { start => 1, size => 15632048, pt_type => 0x0bf, isFormatted => 1 };
        partition_table::dos::compute_CHS($hd, $part);
	$hd->{primary}{raw}[0] = $part;
    }
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
#- return false if the device can not be written to (especially for Smartmedia)
sub test_for_bad_drives {
    my ($hd) = @_;

    log::l("test_for_bad_drives($hd->{file})");
    my $sector = $hd->{geom} ? $hd->{geom}{sectors} - 1 : 0;
    
    sub error { die "$_[0] error: $_[1]" }

    my $F = openit($hd, $::testing ? 0 : 2) or error(openit($hd) ? 'write' : 'read', "can not open device");

    my $seek = sub {
	c::lseek_sector(fileno($F), $sector, 0) or error('read', "seeking to sector $sector failed");
    };
    my $tmp;

    &$seek; sysread $F, $tmp, $SECTORSIZE or error('read', "can not even read ($!)");
    return if $hd->{readonly} || $::testing;
    &$seek; syswrite $F, $tmp or error('write', "can not even write ($!)");

    my $tmp2;
    &$seek; sysread $F, $tmp2, $SECTORSIZE or die "test_for_bad_drives: can not even read again ($!)";
    $tmp eq $tmp2 or die
N("Something bad is happening on your drive. 
A test to check the integrity of data has failed. 
It means writing anything on the disk will end up with random, corrupted data.");
}

1;
