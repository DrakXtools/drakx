package partition_table::bsd; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use partition_table;
use c;

#- very bad and rough handling :(
my %pt_typeToDos = (
  8 => 0x83,
  1 => 0x82,
);
my %pt_typeFromDos = reverse %pt_typeToDos;

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
  a128 => 'partitions',
  a236 => 'blank',
);
$main_format = join '', @$main_format;

my @fields = qw(size start fsize pt_type frag cpg);
my $format = "I I I C C S";
my $magic = 0x82564557;
my $nb_primary = 8;
my $offset = 0x40;


sub use_pt_type { 1 }

sub read_one {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, $offset) or die "reading of partition in sector $sector failed";

    sysread $F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;

    #- TODO verify checksum

    my $size = psizeof($format);
    my @pt = map {
	my %h; @h{@fields} = unpack $format, $_;
	fs::type::set_pt_type(\%h, $pt_typeToDos{$h{pt_type}} || $h{pt_type});
	\%h;
    } $info{partitions} =~ /(.{$size})/g;

    #- check magic number
    $info{magic}  == $magic or die "bad magic number on disk $hd->{device}";
    $info{magic2} == $magic or die "bad magic number on disk $hd->{device}";

    [ @pt ], \%info;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, pt_type, active
sub write($$$;$) {
    my ($hd, $sector, $pt, $info) = @_;

    #- handle testing for writing partition table on file only!
    my $F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open $F, ">$file" or die "error opening test file $file";
    } else {
	$F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno($F), $sector, $offset) or return 0;
    }

    #- TODO compute checksum

    $info->{npartitions} = $nb_primary; #- is it ok?

    @$pt == $nb_primary or die "partition table does not have $nb_primary entries";
    $info->{partitions} = join '', map {
	local $_->{pt_type} = $pt_typeFromDos{$_->{pt_type}} || $_->{pt_type};
	pack $format, @$_{@fields};
    } @$pt;

    syswrite $F, pack($main_format, @$info{@$main_fields}), psizeof($main_format) or return 0;
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
      secpercyl => $hd->cylinder_size,
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

sub initialize {
    my ($class, $hd) = @_;
    $hd->{primary} = { raw => [ ({}) x $nb_primary ], info => info($hd) };
    bless $hd, $class;
;
}

sub first_usable_sector { 2048 }

1;
