package resize_fat::any;

use diagnostics;
use strict;
use vars qw($FREE $FILE $DIRECTORY);

use common qw(:common :constant);
use resize_fat::fat;
use resize_fat::directory;
use resize_fat::dir_entry;


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
    my ($cluster, $entry, $type);

    my $f = sub {
	($entry) = @_;
	$cluster = resize_fat::dir_entry::get_cluster($entry);

	if (resize_fat::dir_entry::is_file($entry)) {
	    $type = $FILE;
	} elsif (resize_fat::dir_entry::is_directory($entry)) {
	    $type = $DIRECTORY;
	} else { return }

	for (; !resize_fat::fat::is_eof($cluster); $cluster = resize_fat::fat::next($fs, $cluster)) {
	    $cluster == 0 and die "Bad FAT: unterminated chain for $entry->{name}\n";
	    $fs->{fat_flag_map}[$cluster] and die "Bad FAT: cluster $cluster is cross-linked for $entry->{name}\n";
	    $fs->{fat_flag_map}[$cluster] = $type;
	    $fs->{clusters}{count}{dirs}++ if $type == $DIRECTORY;
	}
    };
    $fs->{fat_flag_map} = [ ($FREE) x ($fs->{nb_clusters} + 2) ];
    $fs->{clusters}{count}{dirs} = 0;
    resize_fat::directory::traverse_all($fs, $f);
}
