package resize_fat::any; # $Id$

use diagnostics;
use strict;
use vars qw($FREE $FILE $DIRECTORY $UNMOVEABLE);

use common;
use resize_fat::fat;
use resize_fat::directory;
use resize_fat::dir_entry;
use resize_fat::c_rewritten;


$FREE       = 0;
$FILE       = 1;
$DIRECTORY  = 2;
$UNMOVEABLE = 8;


1;


#- returns the number of clusters for a given filesystem type
sub min_cluster_count($) {
    my ($fs) = @_;
    (1 << ${{ FAT16 => 12, FAT32 => 12 }}{$fs->{fs_type}}) - 12;
}
sub max_cluster_count($) {
    my ($fs) = @_;
    (1 << ${{ FAT16 => 16, FAT32 => 28 }}{$fs->{fs_type}}) - 11;
}



#- patch to get the function last_used that return the last used cluster of a fs.
sub last_used($) {
    my ($fs) = @_;

    #- count in negative so absolute value count back to 2.
    foreach (-($fs->{nb_clusters}+1)..-2) { return -$_ if resize_fat::c_rewritten::flag(-$_) }
    die "any: empty FAT table of $fs->{nb_clusters} clusters";
}
#- patch to get the function last_unmoveable that return the last unmoveable cluster of a fs.
sub last_unmoveable($) {
    my ($fs) = @_;

    #- count in negative so absolute value count back to 2.
    foreach (-($fs->{nb_clusters}+1)..-2) { return -$_ if 0x8 & resize_fat::c_rewritten::flag(-$_) }

    #- Oh at this point there are no unmoveable blocks!
    2;
}

#- calculates the minimum size of a partition, in physical sectors
sub min_size($) {
    my ($fs) = @_;
    my $count = $fs->{clusters}{count};

    #- directories are both in `used' and `dirs', so are counted twice
    #- It's done on purpose since we're moving all directories. So at the worse
    #- moment, 2 directories are there, but that way nothing wrong can happen :)
    my $min_cluster_count = max(2 + $count->{used} + $count->{bad} + $count->{dirs}, min_cluster_count($fs));
    $min_cluster_count = max($min_cluster_count, last_unmoveable($fs));

    my $size = $min_cluster_count * divide($fs->{cluster_size}, $SECTORSIZE) +
      divide($fs->{cluster_offset}, $SECTORSIZE) +
    64*1024*1024 / $SECTORSIZE; #- help with such more sectors (ie 64Mb).
    
    #- help zindozs again with 512Mb+ at least else partition is ignored.
    if ($resize_fat::isFAT32) {
        $size = max($size, 524*1024*1024 / $SECTORSIZE);
    }
    $size;

}
#- calculates the maximum size of a partition, in physical sectors
sub max_size($) {
    my ($fs) = @_;

    my $max_cluster_count = min($fs->{nb_fat_entries} - 2, max_cluster_count($fs));

    $max_cluster_count * divide($fs->{cluster_size}, $SECTORSIZE) +
	divide($fs->{cluster_offset}, $SECTORSIZE);
}
#- calculates used size in order to avoid modifying anything.
sub used_size($) {
    my ($fs) = @_;

    my $used_cluster_count = max(last_used($fs), min_cluster_count($fs));

    $used_cluster_count * divide($fs->{cluster_size}, $SECTORSIZE) +
	divide($fs->{cluster_offset}, $SECTORSIZE);
}

#- fills in fat_flag_map in c_rewritten.
#- Each FAT entry is flagged as either FREE, FILE or DIRECTORY.
sub flag_clusters {
    my ($fs) = @_;
    my ($cluster, $curr_dir_name, $entry, $type, $nb_dirs);

    my $f = sub {
	($curr_dir_name, $entry) = @_;
	$cluster = resize_fat::dir_entry::get_cluster($entry);

	if (resize_fat::dir_entry::is_file($entry)) {
	    $type = $FILE;
	    $type |= $UNMOVEABLE if resize_fat::dir_entry::is_unmoveable($entry);
	} elsif (resize_fat::dir_entry::is_directory($entry)) {
	    $type = $DIRECTORY;
	} else { return }

	my $nb = resize_fat::c_rewritten::checkFat($cluster, $type, "$curr_dir_name/$entry->{name}");
	print "resize_fat:flag_clusters: check fat returned $nb of type $type for $curr_dir_name/$entry->{name}\n";
	$nb_dirs += $nb if $type == $DIRECTORY;
	0;
    };

    #- this must call allocate_fat_flag that zeroes the buffer allocated.
    resize_fat::c_rewritten::allocate_fat_flag($fs->{nb_clusters} + 2);

    resize_fat::directory::traverse_all($fs, $f);
    $fs->{clusters}{count}{dirs} = $nb_dirs;
}
