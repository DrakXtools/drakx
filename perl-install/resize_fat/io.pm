package resize_fat::io; # $Id$

use diagnostics;
use strict;

use resize_fat::fat;
use c;

1;


sub read($$$) {
    my ($fs, $pos, $size) = @_;
    my $buf = "\0" x $size;
    sysseek $fs->{fd}, $pos, 0 or die "seeking to byte #$pos failed on device $fs->{fs_name}";
    sysread $fs->{fd}, $buf, $size or die "reading at byte #$pos failed on device $fs->{fs_name}";
    $buf;
}
sub write($$$$) {
    my ($fs, $pos, $_size, $buf) = @_;
    sysseek $fs->{fd}, $pos, 0 or die "seeking to byte #$pos failed on device $fs->{fs_name}";
    syswrite $fs->{fd}, $buf or die "writing at byte #$pos failed on device $fs->{fs_name}";
}

sub read_cluster($$) {
    my ($fs, $cluster) = @_;
    my $buf;
    my $pos = $fs->{cluster_offset} / 512 + $cluster * ($fs->{cluster_size} / 512);

    c::lseek_sector(fileno $fs->{fd}, $pos, 0) or die "seeking to sector #$pos failed on device $fs->{fs_name}";
    sysread $fs->{fd}, $buf, $fs->{cluster_size} or die "reading at sector #$pos failed on device $fs->{fs_name}";
    $buf;
}
sub write_cluster($$$) {
    my ($fs, $cluster, $buf) = @_;
    my $pos = $fs->{cluster_offset} / 512 + $cluster * ($fs->{cluster_size} / 512);

    c::lseek_sector(fileno $fs->{fd}, $pos, 0) or die "seeking to sector #$pos failed on device $fs->{fs_name}";
    syswrite $fs->{fd}, $buf or die "writing at sector #$pos failed on device $fs->{fs_name}";
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

sub open {
    my ($fs) = @_;

    check_mounted($fs->{device});

    sysopen $fs->{fd}, $fs->{fs_name}, 2 or
      sysopen $fs->{fd}, $fs->{fs_name}, 0 or die "error opening device $fs->{fs_name} for writing\n";
}
