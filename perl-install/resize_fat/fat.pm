package resize_fat::fat;

use diagnostics;
use strict;

use resize_fat::any;
use resize_fat::io;

1;

sub read($) {
    my ($fs) = @_;

    @{$fs->{fats}} = map {
	my $fat = eval { resize_fat::io::read($fs, $fs->{fat_offset} + $_ * $fs->{fat_size}, $fs->{fat_size}) };
	$@ and die "reading fat #$_ failed";
	vec($fat, 0, 8) == $fs->{media} or die "FAT $_ has invalid signature";
	$fat;
    } (0 .. $fs->{nb_fats} - 1);

    $fs->{fat} = $fs->{fats}[0];

    my ($free, $bad, $used) = (0, 0, 0);

    for (my $i = 2; $i < $fs->{nb_clusters} + 2; $i++) {
	my $cluster = &next($fs, $i);
	if ($cluster == 0) { $free++; }
	elsif ($cluster == $resize_fat::bad_cluster_value) { $bad++; }
	else { $used++; }
    }
    @{$fs->{clusters}{count}}{qw(free bad used)} = ($free, $bad, $used);
}

sub write($) {
    my ($fs) = @_;

    sysseek $fs->{fd}, $fs->{fat_offset}, 0 or die "write_fat: seek failed";
    foreach (1..$fs->{nb_fats}) {
	syswrite $fs->{fd}, $fs->{fat} or die "write_fat: write failed";
    }
}



#- allocates where all the clusters will be moved to. Clusters before cut_point
#- remain in the same position, however cluster that are part of a directory are
#- moved regardless (this is a mechanism to prevent data loss) (cut_point is the
#- first cluster that won't occur in the new fs)
sub allocate_remap {
    my ($fs, $cut_point) = @_;
    my ($cluster, $new_cluster);
    my $remap = sub { $fs->{fat_remap}[$cluster] = $new_cluster; };
    my $get_new = sub {
	$new_cluster = get_free($fs);
	0 < $new_cluster && $new_cluster < $cut_point or die "no free clusters";
	set_eof($fs, $new_cluster); #- mark as used
	#-log::ld("resize_fat: [$cluster,", &next($fs, $cluster), "...]->$new_cluster...");
    };

    $fs->{fat_remap}[0] = 0;
    $fs->{last_free_cluster} = 2;
    for ($cluster = 2; $cluster < $fs->{nb_clusters} + 2; $cluster++) {
	if ($cluster < $cut_point) {
	    if ($fs->{fat_flag_map}[$cluster] == $resize_fat::any::DIRECTORY) {
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
	 if ($fs->{fat_flag_map}[$cluster]) {
	     my $old_next = &next($fs, $cluster);
	     my $new      = $fs->{fat_remap}[$cluster];
	     my $new_next = $fs->{fat_remap}[$old_next];

	     set_available($fs, $cluster);

	     is_eof($old_next) ?
		 set_eof($fs, $new) :
		 set_next($fs, $new, $new_next);
	 }
    }
}


#- - compares the two FATs (one's a backup that should match) - skips first entry
#- - its just a signature (already checked above) NOTE: checks for cross-linking
#- are done in count.c
sub check($) {
    my ($fs) = @_;
    foreach (@{$fs->{fats}}) {
	$_ eq $fs->{fats}[0] or die "FAT tables do not match";
    }
}

sub endianness16($) { (($_[0] & 0xff) << 8) + ($_[0] >> 8); }
sub endianness($$) {
    my ($val, $nb_bits) = @_;
    my $r = 0;
    for (; $nb_bits > 0; $nb_bits -= 8) {
	$r <<= 8;
	$r += $val & 0xff;
	$val >>= 8;
    }
    $nb_bits < 0 and die "error: endianness only handle numbers divisible by 8";
    $r;
}

sub next($$) {
    my ($fs, $cluster) = @_;
    $cluster > $fs->{nb_clusters} + 2 and die "fat::next: cluster $cluster outside filesystem";
    endianness(vec($fs->{fat}, $cluster, $fs->{fs_type_size}), $fs->{fs_type_size});

}
sub set_next($$$) {
    my ($fs, $cluster, $new_v) = @_;
    $cluster > $fs->{nb_clusters} + 2 and die "fat::set_next: cluster $cluster outside filesystem";
    vec($fs->{fat}, $cluster, $fs->{fs_type_size}) = endianness($new_v, $fs->{fs_type_size});
}


sub get_free($) {
    my ($fs) = @_;
    foreach (my $i = 0; $i < $fs->{nb_clusters}; $i++) {
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
    set_next($fs, $cluster, $resize_fat::bad_cluster_value + 1);
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
    set_next($fs, $cluster, 0);
}
