package resize_fat::main; # $Id$

# This is mainly a perl rewrite of the work of Andrew Clausen (libresize)

use diagnostics;
use strict;

use log;
use common;
use resize_fat::boot_sector;
use resize_fat::info_sector;
use resize_fat::directory;
use resize_fat::io;
use resize_fat::fat;
use resize_fat::any;


1;

#- - reads in the boot sector/partition info., and tries to make some sense of it
sub new($$$) {
    my ($type, $device, $fs_name) = @_;
    my $fs = { device => $device, fs_name => $fs_name };

    eval {
	resize_fat::io::open($fs);
	resize_fat::boot_sector::read($fs);
	$resize_fat::isFAT32 and eval { resize_fat::info_sector::read($fs) };
	resize_fat::fat::read($fs);
	resize_fat::any::flag_clusters($fs);
    };
    if ($@) {
	close $fs->{fd};
	die;
    }
    bless $fs, $type;
}

sub DESTROY {
    my ($fs) = @_;
    close $fs->{fd};
    resize_fat::c_rewritten::free_all();
}

#- copy all clusters >= <start_cluster> to a new place on the partition, less
#- than <start_cluster>. Only copies files, not directories.
#- (use of buffer needed because the seeks slow like hell the hard drive)
sub copy_clusters {
    my ($fs, $cluster) = @_;
    my @buffer;
    my $flush = sub {
	while (@buffer) {
	    my $cluster = shift @buffer;
	    resize_fat::io::write_cluster($fs, $cluster, shift @buffer);
	}
    };
    for (; $cluster < $fs->{nb_clusters} + 2; $cluster++) {
	resize_fat::c_rewritten::flag($cluster) == $resize_fat::any::FILE or next;
	push @buffer, 
	  resize_fat::c_rewritten::fat_remap($cluster), 
	  resize_fat::io::read_cluster($fs, $cluster);
	@buffer > 50 and &$flush();
    }
    &$flush();
}

#- Constructs the new directory tree to match the new file locations.
sub construct_dir_tree {
    my ($fs) = @_;

    if ($resize_fat::isFAT32) {
	#- fat32's root must remain in the first 64k clusters
	#- so do not set it as DIRECTORY, it will be specially handled
	resize_fat::c_rewritten::set_flag($fs->{fat32_root_dir_cluster}, $resize_fat::any::FREE);
    }

    for (my $cluster = 2; $cluster < $fs->{nb_clusters} + 2; $cluster++) {
	resize_fat::c_rewritten::flag($cluster) == $resize_fat::any::DIRECTORY or next;

      resize_fat::io::write_cluster($fs,
				    resize_fat::c_rewritten::fat_remap($cluster),
				    resize_fat::directory::remap($fs, resize_fat::io::read_cluster($fs, $cluster)));
    }

    MDK::Common::System::sync();

    #- until now, only free clusters have been written. it's a null operation if we stop here.
    #- it means no corruption :)
    #
    #- now we must be as fast as possible!

    #- remapping non movable root directory
    if ($resize_fat::isFAT32) {
	my $cluster = $fs->{fat32_root_dir_cluster};

	resize_fat::io::write_cluster($fs,
		      resize_fat::c_rewritten::fat_remap($cluster),
		      resize_fat::directory::remap($fs, resize_fat::io::read_cluster($fs, $cluster)));
    } else {
	resize_fat::io::write($fs, $fs->{root_dir_offset}, $fs->{root_dir_size},
			      resize_fat::directory::remap($fs, resize_fat::io::read($fs, $fs->{root_dir_offset}, $fs->{root_dir_size})));
    }
}

sub min_size($) { &resize_fat::any::min_size }
sub max_size($) { &resize_fat::any::max_size }
sub used_size($) { &resize_fat::any::used_size }

#- resize
#- - size is in sectors
#- - checks boundaries before starting
#- - copies all data beyond new_cluster_count behind the frontier
sub resize {
    my ($fs, $size) = @_;

    my ($min, $max) = (min_size($fs), max_size($fs));

    $size += $min if $size =~ /^\+/;

    $size >= $min or die "Minimum filesystem size is $min sectors";
    $size <= $max or die "Maximum filesystem size is $max sectors";

    log::l("resize_fat: Partition size will be " . (($size * $SECTORSIZE) >> 20) . "Mb (well exactly ${size} sectors)");

    my $new_data_size = $size * $SECTORSIZE - $fs->{cluster_offset};
    my $new_nb_clusters = divide($new_data_size, $fs->{cluster_size});
    my $used_size = used_size($fs);

    log::l("resize_fat: Break point for moving files is " . (($used_size * $SECTORSIZE) >> 20) . " Mb ($used_size sectors)");
    if ($size < $used_size) {
	log::l("resize_fat: Allocating new clusters");
	resize_fat::fat::allocate_remap($fs, $new_nb_clusters);

	log::l("resize_fat: Copying files");
	copy_clusters($fs, $new_nb_clusters);

	log::l("resize_fat: Copying directories");
	construct_dir_tree($fs);

	log::l("Writing new FAT...");
	resize_fat::fat::update($fs);
	resize_fat::fat::write($fs);
    } else {
	log::l("resize_fat: Nothing need to be moved");
    }

    $fs->{nb_sectors} = $size;
    $fs->{nb_clusters} = $new_nb_clusters;
    $fs->{clusters}{count}{free} =
      $fs->{nb_clusters} - $fs->{clusters}{count}{used} - $fs->{clusters}{count}{bad} - 2;

    $fs->{system_id} = 'was here!';
    $fs->{small_nb_sectors} = 0;
    $fs->{big_nb_sectors} = $size;

    log::l("resize_fat: Writing new boot sector...");

    resize_fat::boot_sector::write($fs);

    $resize_fat::isFAT32 and eval { resize_fat::info_sector::write($fs) }; #- does not matter if this fails - its pretty useless!

    MDK::Common::System::sync();
    close $fs->{fd};
    log::l("resize_fat: done");
}

