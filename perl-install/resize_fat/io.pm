package resize_fat::io;

use diagnostics;
use strict;

use resize_fat::fat;

1;


sub read($$$) {
    my ($fs, $pos, $size) = @_;
    my $buf;
    sysseek $fs->{fd}, $pos, 0 or die "seeking to byte #$pos failed on device $fs->{fs_name}";
    sysread $fs->{fd}, $buf, $size or die "reading at byte #$pos failed on device $fs->{fs_name}";
    $buf;
}
sub write($$$$) {
    my ($fs, $pos, $size, $buf) = @_;
    sysseek $fs->{fd}, $pos, 0 or die "seeking to byte #$pos failed on device $fs->{fs_name}";
    syswrite $fs->{fd}, $buf, $size or die "writing at byte #$pos failed on device $fs->{fs_name}";
}

sub read_cluster($$) {
    my ($fs, $cluster) = @_;
    my $buf;

    eval {
	$buf = &read($fs, 
		     $fs->{cluster_offset} + $cluster * $fs->{cluster_size},
		     $fs->{cluster_size});
    }; @$ and die "reading cluster #$cluster failed on device $fs->{fs_name}";
    $buf;
}
sub write_cluster($$$) {
    my ($fs, $cluster, $buf) = @_;

    eval {
    &write($fs, 
	   $fs->{cluster_offset} + $cluster * $fs->{cluster_size},
	   $fs->{cluster_size}, 
	   $buf);
    }; @$ and die "writing cluster #$cluster failed on device $fs->{fs_name}";
}

sub read_file($$) {
    my ($fs, $cluster) = @_;
    my $buf = '';

    for (; !resize_fat::fat::is_eof($cluster); $cluster = resize_fat::fat::next($fs, $cluster)) {
	$cluster == 0 and die "Bad FAT: unterminated chain\n";
	$buf .= read_cluster($fs, $cluster);
    }
    $buf;
}

sub check_mounted($) {
    my ($f) = @_;

    local *F;
    open F, "/proc/mounts" or die "error opening /proc/mounts\n";
    foreach (<F>) {
	/^$f\s/ and die "device is mounted";
    }
}

sub open($) {
    my ($fs) = @_;

    check_mounted($fs->{device});

    sysopen F, $fs->{fs_name}, 2 or sysopen F, $fs->{fs_name}, 0 or die "error opening device $fs->{fs_name} for writing\n";
    $fs->{fd} = \*F;
}
