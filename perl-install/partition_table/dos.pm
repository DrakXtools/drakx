package partition_table::dos; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use partition_table;
use c;

my @fields = qw(active start_head start_sec start_cyl type end_head end_sec end_cyl start size);
my $format = "C8 V2";
my $magic = "\x55\xAA";
my $nb_primary = 4;

my $offset = $common::SECTORSIZE - length($magic) - $nb_primary * common::psizeof($format);

sub hasExtended { 1 }

sub last_usable_sector { 
    my ($hd) = @_;
    #- do not use totalsectors, see gi/docs/Partition-ends-after-end-of-disk.txt for more
    $hd->{geom}{sectors} * $hd->{geom}{heads} * $hd->{geom}{cylinders};
}

sub compute_CHS($$) {
    my ($hd, $e) = @_;
    my @l = qw(cyl head sec);
    @$e{map { "start_$_" } @l} = $e->{start} || $e->{type} ? CHS2rawCHS($hd, sector2CHS($hd, $e->{start})) : (0,0,0);
    @$e{map { "end_$_"   } @l} = $e->{start} || $e->{type} ? CHS2rawCHS($hd, sector2CHS($hd, $e->{start} + $e->{size} - 1)) : (0,0,0);
    1;
}

sub CHS2rawCHS {
    my ($hd, $chs) = @_;
    my ($c, $h, $s) = @$chs;
    if ($c > 1023) {
	#- no way to have a #cylinder >= 1024
	$c = 1023;
	$h = $hd->{geom}{heads} - 1;
	$s = $hd->{geom}{sectors} - 1;
    }
    ($c & 0xff, $h, ($s + 1) | (($c >> 2) & 0xc0));
}

# returns (cylinder, head, sector)
sub sector2CHS {
    my ($hd, $start) = @_;
    my ($s, $h);
    ($start, $s) = divide($start, $hd->{geom}{sectors});
    ($start, $h) = divide($start, $hd->{geom}{heads});
    [ $start, $h, $s ];
}

sub read {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, $offset) or die "reading of partition in sector $sector failed";

    my @pt = map {
	sysread $F, $tmp, psizeof($format) or die "error while reading partition table in sector $sector";
	my %h; @h{@fields} = unpack $format, $tmp;
	\%h;
    } (1..$nb_primary);

    #- check magic number
    sysread $F, $tmp, length $magic or die "error reading magic number on disk $hd->{device}";
    $tmp eq $magic or die "bad magic number on disk $hd->{device}";

    [ @pt ];
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, type, active
sub write($$$;$) {
    my ($hd, $sector, $pt) = @_;

    #- handle testing for writing partition table on file only!
    my $F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open $F, ">$file" or die "error opening test file $file";
    } else {
	$F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno($F), $sector, $offset) or return 0;
    }

    @$pt == $nb_primary or die "partition table does not have $nb_primary entries";
    foreach (@$pt) {
	compute_CHS($hd, $_);
	local $_->{start} = $_->{local_start} || 0;
	$_->{active} ||= 0; $_->{type} ||= 0; $_->{size} ||= 0; #- for no warning
	syswrite $F, pack($format, @$_{@fields}), psizeof($format) or return 0;
    }
    syswrite $F, $magic, length $magic or return 0;
    1;
}

sub clear_raw { { raw => [ ({}) x $nb_primary ] } }

1;
