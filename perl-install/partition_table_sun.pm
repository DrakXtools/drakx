package partition_table_sun;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table_raw);

use common qw(:common :system :file :functional);
use partition_table_raw;
use partition_table;
use c;

#- very bad and rough handling :(
my %typeToDos = (
  5 => 0,
);
my %typeFromDos = reverse %typeToDos;

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

my ($fields1, $fields2) = ([ qw(type flags) ], [ qw(start_cylinder size) ]);
my ($format1, $format2) = ("x C x C", "N N");
my ($size1, $size2) = map { psizeof($_) } ($format1, $format2);
my $magic = 0xDABE;
my $nb_primary = 8;
my $offset = 0;

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    #- since partition must always start on cylinders boundaries on sparc,
    #- note that if start sector is on the first cylinder, it is adjusted
    #- to 0 and it is valid.
    $part->{start} = $part->{start} >= partition_table::cylinder_size() ? round_up($part->{start}, partition_table::cylinder_size($hd)) : 0;
    $part->{size} = $end - $part->{start};
}
sub adjustEnd($$) {
    &partition_table::adjustEnd;
}

#- compute crc checksum used for Sun Label partition, expect
#- $tmp to be the 512 bytes buffer to be read/written to MBR.
sub compute_crc($) {
    my ($tmp) = @_;
    my @l2b = unpack "n256", $tmp;
    my $crc = 0;

    map { $crc ^= $_ } @l2b;

    $crc;
}

sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $sector, $offset) or die "reading of partition in sector $sector failed";

    sysread F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;

    #- check magic number
    $info{magic}  == $magic or die "bad magic number";

    #- check crc, csum contains the crc so result should be 0.
    compute_crc($tmp) == 0 or die "bad checksum";

    @{$hd->{geom}}{qw(cylinders heads sectors)} = @info{qw(ncyl nsect ntrks)};

    my @pt = mapn {
	my %h; 
	@h{@$fields1} = unpack $format1, $_[0];
	@h{@$fields2} = unpack $format2, $_[1];
	$h{start} = $sector + $h{start_cylinder} * partition_table::cylinder_size($hd);
#	$h{type} = $typeToDos{$h{type}} || $h{type}; #- for rewrite it ?
	$h{size} or $h{$_} = 0 foreach keys %h;
	\%h;
    } [ $info{infos} =~ /(.{$size1})/g ], [ $info{partitions} =~ /(.{$size2})/g ];

    [ @pt ], \%info;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, type, active
sub write($$$;$) {
    my ($hd, $sector, $pt, $info) = @_;

    #- handle testing for writing partition table on file only!
    local *F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open F, ">$file" or die "error opening test file $file";
    } else {
	partition_table_raw::openit($hd, *F, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno(F), $sector, $offset) or return 0;
    }

    ($info->{infos}, $info->{partitions}) = map { join '', @$_ } list2kv map {
	$_->{start} % partition_table::cylinder_size($hd) == 0 or die "partition not at beginning of cylinder";
#	local $_->{type} = $typeFromDos{$_->{type}} || $_->{type};
	local $_->{start_cylinder} = $_->{start} / partition_table::cylinder_size($hd) - $sector;
	pack($format1, @$_{@$fields1}), pack($format2, @$_{@$fields2});
    } @$pt;

    #- compute the checksum by building the buffer to write and call compute_crc.
    #- set csum to 0 so compute_crc will give the right csum value.
    $info->{csum} = 0;
    $info->{csum} = compute_crc(pack($main_format, @$info{@$main_fields}));

    syswrite F, pack($main_format, @$info{@$main_fields}), psizeof($main_format) or return 0;

    1;
}

sub info {
    my ($hd) = @_;

    #- build a default suitable partition table,
    #- checksum will be built when writing on disk.
    #- note third partition is ALWAYS of type Whole disk.
    my $info = {
	info => "DiskDrake partition table",
	rspeed => 5400,
	pcylcount => $hd->{geom}{total_cylinders},
	sparecyl => 0,
	ilfact => 1,
	ncyl => $hd->{geom}{cylinders},
	nacyl => $hd->{geom}{total_cylinders} - $hd->{geom}{cylinders},
	ntrks => $hd->{geom}{heads},
	nsect => $hd->{geom}{sectors},
	magic => $magic,
    };

    $info;
#    my $dtype_scsi  = 4; #- taken from fdisk, removed unused one,
#    my $dtype_ST506 = 6; #- see fdisk for more
#    {
#      magic => $magic,
#      magic2 => $magic,
#      dtype => $hd->{device} =~ /^sd/ ? $dtype_scsi : $dtype_ST506,
#      secsize => $common::SECTORSIZE,
#      ncylinders => $hd->{geom}{cylinders},
#      secpercyl => partition_table::cylinder_size($hd),
#      secprtunit => $hd->{geom}{totalsectors},
#      rpm => 3600,
#      interleave => 1,
#      trackskew => 0,
#      cylskew => 0,
#      headswitch => 0,
#      trkseek => 0,
#      bbsize => 8192, #- size of boot area, with label
#      sbsize => 8192, #- max size of fs superblock
#    };
}

sub clear_raw {
    my ($hd) = @_;
    my $pt = { raw => [ ({}) x $nb_primary ], info => info($hd) };

    #- handle special case for partition 2 which is whole disk.
    $pt->{raw}[2] = {
	type => 5, #- the whole disk type.
	flags => 0,
	start_cylinder => 0,
	size => $hd->{geom}{cylinders} * partition_table::cylinder_size($hd),
    };

    $pt;
}

1;
