package partition_table_bsd;

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
  8 => 0x83,
  1 => 0x82,
);
my %typeFromDos = reverse %typeToDos;

my ($main_format, $main_fields) = list2kv(
  I   => 'magic',
  S   => 'type',
  S   => 'subtype',
  a16 => 'typename',
  a16 => 'packname',
  I   => 'secsize',
  I   => 'nsectors',
  I   => 'ntracks',
  I   => 'ncylinders',
  I   => 'secpercyl',
  I   => 'secprtunit',
  S   => 'sparespertrack',
  S   => 'sparespercyl',
  I   => 'acylinders',
  S   => 'rpm',
  S   => 'interleave',
  S   => 'trackskew',
  S   => 'cylskew',
  I   => 'headswitch',
  I   => 'trkseek',
  I   => 'flags',
  a20 => 'drivedata',
  a20 => 'spare',
  I   => 'magic2',
  S   => 'checksum',
  S   => 'npartitions',
  I   => 'bbsize',
  I   => 'sbsize',
);
$main_format = join '', @$main_format;

my @fields = qw(size start fsize type frag cpg);
my $format = "I I I C C S";
my $magic = 0x82564557;
my $nb_primary = 8;
my $offset = 0x40;

#- use default partition table adust functions.
sub adjustStart($$) {
    &partition_table::adjustStart;
}
sub adjustEnd($$) {
    &partition_table::adjustEnd;
}

sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $sector, $offset) or die "reading of partition in sector $sector failed";

    sysread F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;

    $info{npartitions} <= $nb_primary or die "too many partitions ($info{npartitions} > $nb_primary) for a bsd disklabel";

    #- check magic number
    $info{magic}  == $magic or die "bad magic number";
    $info{magic2} == $magic or die "bad magic number";

    #- TODO verify checksum

    my @pt = map {
	sysread F, $tmp, psizeof($format) or die "error while reading partition table in sector $sector";
	my %h; @h{@fields} = unpack $format, $tmp;
	$h{type} = $typeToDos{$h{type}} || $h{type};
	\%h;
    } (1..$info{npartitions});

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

    #- TODO compute checksum

    $info->{npartitions} = $nb_primary; #- is it ok?

    syswrite F, pack($main_format, @$info{@$main_fields}), psizeof($main_format) or return 0;

    @$pt == $nb_primary or die "partition table does not have $nb_primary entries";
    foreach (@$pt) {
	local $_->{type} = $typeFromDos{$_->{type}} || $_->{type};
	syswrite F, pack($format, @$_{@fields}), psizeof($format) or return 0;
    }
    1;
}

sub info {
    my ($hd) = @_;
    my $dtype_scsi  = 4; #- taken from fdisk, removed unused one,
    my $dtype_ST506 = 6; #- see fdisk for more

    {
      magic => $magic,
      magic2 => $magic,
      dtype => $hd->{device} =~ /^sd/ ? $dtype_scsi : $dtype_ST506,
      secsize => $common::SECTORSIZE,
      ncylinders => $hd->{geom}{cylinders},
      secpercyl => partition_table::cylinder_size($hd),
      secprtunit => $hd->{geom}{totalsectors},
      rpm => 3600,
      interleave => 1,
      trackskew => 0,
      cylskew => 0,
      headswitch => 0,
      trkseek => 0,
      bbsize => 8192, #- size of boot area, with label
      sbsize => 8192, #- max size of fs superblock
    };
}

sub clear_raw {
    my ($hd) = @_;
    { raw => [ ({}) x $nb_primary ], info => info($hd) };
}

1;
