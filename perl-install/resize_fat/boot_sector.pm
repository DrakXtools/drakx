package resize_fat::boot_sector; # $Id$

use diagnostics;
use strict;

use common;
use resize_fat::io;
use resize_fat::any;
use resize_fat::directory;


#- Oops, this will be unresizable on big-endian machine. trapped by signature.
my $format = "a3 a8 S C S C S S C S S S I I I S S I S S a458 S";
my @fields = (
    'boot_jump',		#- boot strap short or near jump
    'system_id',		#- Name - can be used to special case partition manager volumes
    'sector_size',		#- bytes per logical sector
    'cluster_size_in_sectors',	#- sectors/cluster
    'nb_reserved',		#- reserved sectors
    'nb_fats',			#- number of FATs
    'nb_root_dir_entries',	#- number of root directory entries
    'small_nb_sectors',		#- number of sectors: big_nb_sectors supersedes
    'media',			#- media code
    'fat16_fat_length',		#- sectors/FAT for FAT12/16
    'sectors_per_track',
    'nb_heads',
    'nb_hidden',		#- (unused)
    'big_nb_sectors',		#- number of sectors (if small_nb_sectors == 0)

#- FAT32-only entries
    'fat32_fat_length',		#- size of FAT in sectors
    'fat32_flags',		#- bit8: fat mirroring,
				#- low4: active fat
    'fat32_version',		#- minor * 256 + major
    'fat32_root_dir_cluster',
    'info_offset_in_sectors',
    'fat32_backup_sector',

#- Common again...
    'boot_code',		#- Boot code (or message)
    'boot_sign',		#- 0xAA55
);

1;


#- trimfs_init_boot_sector() - reads in the boot sector - gets important info out
#- of boot sector, and puts in main structure - performs sanity checks - returns 1
#- on success, 0 on failureparameters: filesystem an empty structure to fill.
sub read($) {
    my ($fs) = @_;

    my $boot = eval { resize_fat::io::read($fs, 0, $SECTORSIZE) }; $@ and die "reading boot sector failed on device $fs->{fs_name}";
    @$fs{@fields} = unpack $format, $boot;

    $fs->{nb_sectors} = $fs->{small_nb_sectors} || $fs->{big_nb_sectors};
    $fs->{cluster_size} = $fs->{cluster_size_in_sectors} * $fs->{sector_size};

    $fs->{boot_sign} == 0xAA55 or die "Invalid signature for a MS-based filesystem.\n";
    $fs->{nb_sectors} < 32 and die "Too few sectors for viable file system\n";
    $fs->{nb_fats} == 2 or cdie "Weird number of FATs: $fs->{nb_fats}, not 2.\n";
    $fs->{sector_size} == 512 or cdie "Strange sector_size != 512\n";

    if ($fs->{fat16_fat_length}) {
	#- asserting FAT16, will be verified later on
	$resize_fat::isFAT32 = 0;
        $fs->{fs_type} = 'FAT16';
	$fs->{fs_type_size} = 16;
	$fs->{fat_length} = $fs->{fat16_fat_length};
	$resize_fat::bad_cluster_value = 0xfff7; #- 2**16 - 1
    } else {
	$resize_fat::isFAT32 = 1;
        $fs->{fs_type} = 'FAT32';
        $fs->{fs_type_size} = 32;
	$fs->{fat_length} = $fs->{fat32_fat_length};

	$fs->{nb_root_dir_entries} = 0;
	$fs->{info_offset} = $fs->{info_offset_in_sectors} * $fs->{sector_size};
	$resize_fat::bad_cluster_value = 0x0ffffff7;
    }

    $fs->{fat_offset} = $fs->{nb_reserved} * $fs->{sector_size};
    $fs->{fat_size} = $fs->{fat_length} * $fs->{sector_size};
    $fs->{root_dir_offset} = $fs->{fat_offset} + $fs->{fat_size} * $fs->{nb_fats};
    $fs->{root_dir_size} = $fs->{nb_root_dir_entries} * resize_fat::directory::entry_size();
    $fs->{cluster_offset} = $fs->{root_dir_offset} + $fs->{root_dir_size} - 2 * $fs->{cluster_size};

    $fs->{nb_fat_entries} = divide($fs->{fat_size}, $fs->{fs_type_size} / 8);

    #- - 2 because clusters 0 & 1 does not exist
    $fs->{nb_clusters} = divide($fs->{nb_sectors} * $fs->{sector_size} - $fs->{cluster_offset}, $fs->{cluster_size}) - 2;

    $fs->{dir_entries_per_cluster} = divide($fs->{cluster_size}, psizeof($format));

#-    $fs->{nb_clusters} >= resize_fat::any::min_cluster_count($fs) or die "error: not enough sectors for a $fs->{fs_type}\n";
    $fs->{nb_clusters} <  resize_fat::any::max_cluster_count($fs) or die "error: too many sectors for a $fs->{fs_type}\n";
}

sub write($) {
    my ($fs) = @_;
    my $boot = pack($format, @$fs{@fields});

    eval { resize_fat::io::write($fs, 0, $SECTORSIZE, $boot) }; $@ and die "writing the boot sector failed on device $fs->{fs_name}";

    if ($resize_fat::isFAT32) {
	#- write backup
	eval { resize_fat::io::write($fs, $fs->{fat32_backup_sector} * $SECTORSIZE, $SECTORSIZE, $boot) };
	$@ and die "writing the backup boot sector (#$fs->{fat32_backup_sector}) failed on device $fs->{fs_name}";
    }
}
