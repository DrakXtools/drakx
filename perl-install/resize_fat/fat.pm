package resize_fat::fat; # $Id$

use diagnostics;
use strict;

use resize_fat::any;
use resize_fat::io;
use resize_fat::c_rewritten;

1;

sub read($) {
    my ($fs) = @_;

    resize_fat::c_rewritten::read_fat(fileno $fs->{fd}, $fs->{fat_offset}, $fs->{fat_size}, $fs->{media});

    @{$fs->{clusters}{count}}{qw(free bad used)} =
      resize_fat::c_rewritten::scan_fat($fs->{nb_clusters}, $fs->{fs_type_size});
}

sub write($) {
    my ($fs) = @_;

    sysseek $fs->{fd}, $fs->{fat_offset}, 0 or die "write_fat: seek failed";
    foreach (1..$fs->{nb_fats}) {
	resize_fat::c_rewritten::write_fat(fileno $fs->{fd}, $fs->{fat_size});
    }
}



#- allocates where all the clusters will be moved to. Clusters before cut_point
#- remain in the same position, however cluster that are part of a directory are
#- moved regardless (this is a mechanism to prevent data loss) (cut_point is the
#- first cluster that won't occur in the new fs)
sub allocate_remap {
    my ($fs, $cut_point) = @_;
    my ($cluster, $new_cluster);
    my $remap = sub { resize_fat::c_rewritten::set_fat_remap($cluster, $new_cluster) };
    my $get_new = sub {
	$new_cluster = get_free($fs);
	0 < $new_cluster && $new_cluster < $cut_point or die "no free clusters";
	set_eof($fs, $new_cluster); #- mark as used
	#-log::ld("resize_fat: [$cluster,", &next($fs, $cluster), "...]->$new_cluster...");
    };

    #- this must call allocate_fat_remap that zeroes the buffer allocated.
    resize_fat::c_rewritten::allocate_fat_remap($fs->{nb_clusters} + 2);

    $fs->{last_free_cluster} = 2;
    for ($cluster = 2; $cluster < $fs->{nb_clusters} + 2; $cluster++) {
	if ($cluster < $cut_point) {
	    if (resize_fat::c_rewritten::flag($cluster) == $resize_fat::any::DIRECTORY) {
		&$get_new();
	    } else {
		$new_cluster = $cluster;
	    }
	    &$remap();
	} elsif (!is_empty(&next($fs, $cluster))) {
	    &$get_new();
	    &$remap();
	 }
    }
}


#- updates the fat for the resized filesystem
sub update {
    my ($fs) = @_;

    for (my $cluster = 2; $cluster < $fs->{nb_clusters} + 2; $cluster++) {
	 if (resize_fat::c_rewritten::flag($cluster)) {
	     my $old_next = &next($fs, $cluster);
	     my $new      = resize_fat::c_rewritten::fat_remap($cluster);
	     my $new_next = resize_fat::c_rewritten::fat_remap($old_next);

	     set_available($fs, $cluster);

	     is_eof($old_next) ?
		 set_eof($fs, $new) :
		 set_next ($fs, $new, $new_next);
	 }
    }
}


sub endianness16($) { (($_[0] & 0xff) << 8) + ($_[0] >> 8) }
sub endianness($$) {
    my ($val, $nb_bits) = @_;
    my $r = 0;
    for (; $nb_bits > 0; $nb_bits -= 8) {
	$r = $r << 8;
	$r += $val & 0xff;
	$val = $val >> 8;
    }
    $nb_bits < 0 and die "error: endianness only handle numbers divisible by 8";
    $r;
}

*next = \&resize_fat::c_rewritten::next;
*set_next = \&resize_fat::c_rewritten::set_next;



sub get_free($) {
    my ($fs) = @_;
    for (my $i = 0; $i < $fs->{nb_clusters}; $i++) {
        my $cluster = ($i + $fs->{last_free_cluster} - 2) % $fs->{nb_clusters} + 2;
        is_available(&next($fs, $cluster)) and return $fs->{last_free_cluster} = $cluster;
    }
    die "no free clusters";
}

#-    returns true if <cluster> represents an EOF marker
sub is_eof($) {
    my ($cluster) = @_;
    $cluster >= $resize_fat::bad_cluster_value;
}
sub set_eof($$) {
    my ($fs, $cluster) = @_;
    set_next ($fs, $cluster, $resize_fat::bad_cluster_value + 1);
}

#-    returns true if <cluster> is empty.  Note that this includes bad clusters.
sub is_empty($) {
    my ($cluster) = @_;
    $cluster == 0 || $cluster == $resize_fat::bad_cluster_value;
}

#-    returns true if <cluster> is available.
sub is_available($) {
    my ($cluster) = @_;
    $cluster == 0;
}
sub set_available($$) {
    my ($fs, $cluster) = @_;
    set_next ($fs, $cluster, 0);
}
