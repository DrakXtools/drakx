package resize_fat::any;

use diagnostics;
use strict;
use vars qw($FREE $FILE $DIRECTORY);

use common qw(:common :constant);
use resize_fat::fat;
use resize_fat::directory;
use resize_fat::dir_entry;
use resize_fat::c_rewritten;


$FREE      = 0;
$FILE      = 1;
$DIRECTORY = 2;


1;


#- returns the number of clusters for a given filesystem type
sub min_cluster_count($) {
    my ($fs) = @_;
    (1 << $ {{ FAT16 => 12, FAT32 => 12 }}{$fs->{fs_type}}) - 12;
}
sub max_cluster_count($) {
    my ($fs) = @_;
    2 ** $fs->{fs_type_size} - 11;
}



#- calculates the minimum size of a partition, in physical sectors
sub min_size($) {
    my ($fs) = @_;
    my $count = $fs->{clusters}{count};

    #- directories are both in `used' and `dirs', so are counted twice
    #- It's done on purpose since we're moving all directories. So at the worse
    #- moment, 2 directories are there, but that way nothing wrong can happen :)
    my $min_cluster_count = max(2 + $count->{used} + $count->{bad} + $count->{dirs}, min_cluster_count($fs));

    $min_cluster_count * divide($fs->{cluster_size}, $SECTORSIZE) +
	divide($fs->{cluster_offset}, $SECTORSIZE);
}
#- calculates the maximum size of a partition, in physical sectors
sub max_size($) {
    my ($fs) = @_;

    my $max_cluster_count = min($fs->{nb_fat_entries} - 2, max_cluster_count($fs));

    $max_cluster_count * divide($fs->{cluster_size}, $SECTORSIZE) +
	divide($fs->{cluster_offset}, $SECTORSIZE);
}

#- fills in $fs->{fat_flag_map}.
#- Each FAT entry is flagged as either FREE, FILE or DIRECTORY.
sub flag_clusters {
    my ($fs) = @_;
    my ($cluster, $entry, $type, $nb_dirs);
    my $fat_flag_map = "\0" x ($fs->{nb_clusters} + 2);

    my $f = sub {
	($entry) = @_;
	$cluster = resize_fat::dir_entry::get_cluster($entry);

	if (resize_fat::dir_entry::is_file($entry)) {
	    $type = $FILE;
	} elsif (resize_fat::dir_entry::is_directory($entry)) {
	    $type = $DIRECTORY;
	} else { return }

	my $nb = resize_fat::c_rewritten::checkFat($fat_flag_map, $cluster, $type, $entry->{name});
	$nb_dirs += $nb if $type == $DIRECTORY;
	0;
    };
    resize_fat::directory::traverse_all($fs, $f);
    $fs->{fat_flag_map} = $fat_flag_map;
    $fs->{clusters}{count}{dirs} = $nb_dirs;
}
