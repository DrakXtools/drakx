package partition_table::sun; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use partition_table;
use fs::type;
use c;

my ($main_format, $main_fields) = list2kv(
  a128  => 'info',
  a14   => 'spare0',
  a32   => 'infos',
  a246  => 'spare1',
  n     => 'rspeed',
  n     => 'pcylcount',
  n     => 'sparecyl',
  a4    => 'spare2',
  n     => 'ilfact',
  n     => 'ncyl',
  n     => 'nacyl',
  n     => 'ntrks',
  n     => 'nsect',
  a4    => 'spare3',
  a64   => 'partitions',
  n     => 'magic',
  n     => 'csum',
);
$main_format = join '', @$main_format;

my ($fields1, $fields2) = ([ qw(pt_type flags) ], [ qw(start_cylinder size) ]);
my ($format1, $format2) = ("xCxC", "N2");
my $magic = 0xDABE;
my $nb_primary = 8;
my $offset = 0;

sub use_pt_type { 1 }

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    #- since partition must always start on cylinders boundaries on sparc,
    #- note that if start sector is on the first cylinder, it is adjusted
    #- to 0 and it is valid, cylinder 0 bug is from bad define for sparc
    #- compilation of mke2fs combined with a blind kernel...
    $part->{start} = round_down($part->{start}, $hd->cylinder_size);
    $part->{size} = $end - $part->{start};
    $part->{size} = $hd->cylinder_size if $part->{size} <= 0;
}
sub adjustEnd($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};
    my $end2 = round_up($end, $hd->cylinder_size);
    $end2 = $hd->{geom}{cylinders} * $hd->cylinder_size if $end2 > $hd->{geom}{cylinders} * $hd->cylinder_size;
    $part->{size} = $end2 - $part->{start};
}

#- compute crc checksum used for Sun Label partition, expect
#- $tmp to be the 512 bytes buffer to be read/written to MBR.
sub compute_crc($) {
    my ($tmp) = @_;
    my @l2b = unpack "n256", $tmp;
    my $crc = 0;

    $crc ^= $_ foreach @l2b;

    $crc;
}

sub read_one {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, $offset) or die "reading of partition in sector $sector failed";

    sysread $F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;

    #- check magic number
    $info{magic}  == $magic or die "bad magic number on disk $hd->{device}";

    #- check crc, csum contains the crc so result should be 0.
    compute_crc($tmp) == 0 or die "bad checksum";

    @{$hd->{geom}}{qw(cylinders heads sectors)} = @info{qw(ncyl ntrks nsect)};

    my @pt;
    my @infos_up = unpack $format1 x $nb_primary, $info{infos};
    my @partitions_up = unpack $format2 x $nb_primary, $info{partitions};
    foreach (0..$nb_primary-1) {
	my $h = { flag => $infos_up[1 + 2 * $_],
		  start_cylinder => $partitions_up[2 * $_], size => $partitions_up[1 + 2 * $_] };
	fs::type::set_pt_type($h, $infos_up[2 * $_]);
	$h->{start} = $sector + $h->{start_cylinder} * $hd->cylinder_size;
	$h->{pt_type} && $h->{size} or $h->{$_} = 0 foreach keys %$h;
	push @pt, $h;
    }

#- this code is completely broken by null char inside strings, it gets completely crazy :-)
#    my @pt = mapn {
#	my %h; 
#	@h{@$fields1} = unpack $format1, $_[0];
#	@h{@$fields2} = unpack $format2, $_[1];
#	$h{start} = $sector + $h{start_cylinder} * $hd->cylinder_size();
#	$h{pt_type} && $h{size} or $h{$_} = 0 foreach keys %h;
#	\%h;
#    } [ grep { $_ } split /(.{$size1})/o, $info{infos} ], [ grep { $_ } split /(.{$size2})/o, $info{partitions} ];

    [ @pt ], \%info;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, pt_type, active
sub write($$$;$) {
    my ($hd, $sector, $pt, $info) = @_;
#    my ($csize, $wdsize) = (0, 0);

    #- handle testing for writing partition table on file only!
    my $F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open $F, ">$file" or die "error opening test file $file";
    } else {
	$F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno($F), $sector, $offset) or return 0;
    }

    ($info->{infos}, $info->{partitions}) = map { join '', @$_ } list2kv map {
	$_->{start} % $hd->cylinder_size == 0 or die "partition not at beginning of cylinder";
#	$csize += $_->{size} if $_->{pt_type} != 5;
#	$wdsize += $_->{size} if $_->{pt_type} == 5;
	$_->{flags} |= 0x10 if $_->{mntpoint} eq '/';
	$_->{flags} |= 0x01 if !isSwap($_);
	local $_->{start_cylinder} = $_->{start} / $hd->cylinder_size - $sector;
	pack($format1, @$_{@$fields1}), pack($format2, @$_{@$fields2});
    } @$pt;
#    $csize == $wdsize or die "partitions are not using whole disk space";

    #- compute the checksum by building the buffer to write and call compute_crc.
    #- set csum to 0 so compute_crc will give the right csum value.
    $info->{csum} = 0;
    $info->{csum} = compute_crc(pack($main_format, @$info{@$main_fields}));

    syswrite $F, pack($main_format, @$info{@$main_fields}), psizeof($main_format) or return 0;

    common::sync();

    1;
}

sub info {
    my ($hd) = @_;

    #- take care of reduction of the number of cylinders, avoid loop of reduction!
    unless ($hd->{geom}{totalcylinders} > $hd->{geom}{cylinders}) {
	$hd->{geom}{totalcylinders} = $hd->{geom}{cylinders};
	$hd->{geom}{cylinders} -= 2;

	#- rebuild some constants according to number of cylinders.
	$hd->{totalsectors} = $hd->{geom}{heads} * $hd->{geom}{sectors} * $hd->{geom}{cylinders};
    }

    #- build a default suitable partition table,
    #- checksum will be built when writing on disk.
    #- note third partition is ALWAYS of type Whole disk.
    my $info = {
	info => "DiskDrake partition table",
	rspeed => 5400,
	pcylcount => $hd->{geom}{totalcylinders},
	sparecyl => 0,
	ilfact => 1,
	ncyl => $hd->{geom}{cylinders},
	nacyl => $hd->{geom}{totalcylinders} - $hd->{geom}{cylinders},
	ntrks => $hd->{geom}{heads},
	nsect => $hd->{geom}{sectors},
	magic => $magic,
    };

    $info;
}

sub initialize {
    my ($hd) = @_;
    my $pt = { raw => [ ({}) x $nb_primary ], info => info($hd) };

    #- handle special case for partition 2 which is whole disk.
    $pt->{raw}[2] = {
	pt_type => 5, #- the whole disk type.
	flags => 0,
	start_cylinder => 0,
	size => $hd->{geom}{cylinders} * $hd->cylinder_size,
    };

    $hd->{primary} = $pt;
    bless $hd, 'partition::sun';
}

1;
