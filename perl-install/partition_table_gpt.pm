package partition_table_gpt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table_raw);

use common;
use partition_table_raw;
use partition_table_dos;
use partition_table;
use c;

my %gpt_types = (
  0x00 => "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  0x82 => "\x6d\xfd\x57\x06\xab\xa4\xc4\x43\x84\xe5\x09\x33\xc8\x4b\x4f\x4f",
  0x83 => "\xA2\xA0\xD0\xEB\xE5\xB9\x33\x44\x87\xC0\x68\xB6\xB7\x26\x99\xC7",
  0x8e => "\x79\xd3\xd6\xe6\x07\xf5\xc2\x44\xa2\x3c\x23\x8f\x2a\x3d\xf9\x28",
  0xfd => "\x0f\x88\x9d\xa1\xfc\x05\x3b\x4d\xa0\x06\x74\x3f\x0f\x84\x91\x1e",
  0xef => "\x28\x73\x2A\xC1\x1F\xF8\xd2\x11\xBA\x4B\x00\xA0\xC9\x3E\xC9\x3B",
  # legacy_partition_table => "\x41\xEE\x4D\x02\xE7\x33\xd3\x11\x9D\x69\x00\x08\xC7\x81\xF3\x9F"
  # PARTITION_MSFT_RESERVED_GUID "\x16\xE3\xC9\xE3\x5C\x0B\xB8\x4D\x81\x7D\xF9\x2D\xF0\x02\x15\xAE"
  #PARTITION_RESERVED_GUID "\x39\x33\xa6\x8d\x07\x00\xc0\x60\xc4\x36\x08\x3a\xc8\x23\x09\x08"
);

my $current_revision = 0x00010200;
my ($main_format, $main_fields) = list2kv(
  a8    => 'magic',
  V     => 'revision',
  V     => 'headerSize',
  V     => 'headerCRC32',
  a4    => 'blank1',
  Q     => 'myLBA',
  Q     => 'alternateLBA',
  Q     => 'firstUsableLBA',
  Q     => 'lastUsableLBA',
  a16   => 'guid',
  Q     => 'partitionEntriesLBA',
  V     => 'nbPartitions',
  V     => 'partitionEntrySize',
  V     => 'partitionEntriesCRC32',
);

my ($partitionEntry_format, $partitionEntry_fields) = list2kv(
  a16   => 'gpt_type',
  a16   => 'guid',
  Q     => 'start',
  Q     => 'ending',
  a8    => 'efi_attributes',
  a72   => 'name',
);

$_ = join('', @$_) foreach $main_format, $partitionEntry_format;

my $magic = "EFI PART";

sub crc32 {
    my ($buffer) = @_;

    my $crc = 0xFFFFFFFF;
    foreach (unpack "C*", $buffer) {
	my $subcrc = ($crc ^ $_) & 0xFF;
        for (my $j = 8; $j > 0; $j--){
	    my $b = $subcrc & 1;
	    $subcrc = ($subcrc >> 1) & 0x7FFFFFFF;
	    $subcrc = $subcrc ^ 0xEDB88320 if $b;
        }
        $crc = ($crc >> 8) ^ $subcrc;
    }
    $crc ^ 0xFFFFFFFF;
}

sub compute_headerCRC32 {
    my ($info) = @_;
    local $info->{headerCRC32} = 0;
    crc32(pack($main_format, @$info{@$main_fields}));
}

sub read {
    my ($hd, $sector) = @_;
    my $tmp;

    my $l = partition_table_dos::read($hd, $sector);
    my @l = grep { $_->{size} && $_->{type} && !partition_table::isExtended($_) } @$l;
    @l == 1 or die "bad PMBR";
    $l[0]{type} == 0xee or die "bad PMBR";
    my $myLBA = $l[0]{start};

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $myLBA, 0) or die "reading of partition in sector $sector failed";

    sysread F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;
    
    $info{magic} eq $magic or die "bad magic number";
    $info{myLBA} == $myLBA or die "myLBA is not the same";
    $info{headerSize} == psizeof($main_format) or die "bad partition table header size";
    $info{partitionEntrySize} == psizeof($partitionEntry_format) or die "bad partitionEntrySize";
    $info{revision} <= $current_revision or log::l("oops, this is a new GPT revision ($info{revision} > $current_revision)");

    $info{headerCRC32} == compute_headerCRC32(\%info) or die "bad partition table checksum";

    c::lseek_sector(fileno(F), $info{partitionEntriesLBA}, 0) or die "can't seek to sector partitionEntriesLBA";
    sysread F, $tmp, psizeof($partitionEntry_format) * $info{nbPartitions} or die "error while reading partition table in sector $sector";
    $info{partitionEntriesCRC32} == crc32($tmp) or die "bad partition entries checksum";

    c::lseek_sector(fileno(F), $info{partitionEntriesLBA}, 0) or die "can't seek to sector partitionEntriesLBA";
    my %gpt_types_rev = reverse %gpt_types;
    my @pt = 
      grep { $_->{size} && $_->{type} } #- compress empty partitions as kernel skip them
      map {
	sysread F, $tmp, psizeof($partitionEntry_format) or die "error while reading partition table in sector $sector";
	my %h; @h{@$partitionEntry_fields} = unpack $partitionEntry_format, $tmp;
	$h{size} = $h{ending} - $h{start};
	$h{type} = $gpt_types_rev{$h{gpt_type}};
	$h{type} = 0x100 if !defined $h{type};
	\%h;
    } (1 .. $info{nbPartitions});

    [ @pt ], \%info;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, type, active
sub write {
    my ($hd, undef, $pt, $info) = @_;

    local *F;
    partition_table_raw::openit($hd, *F, 2) or die "error opening device $hd->{device} for writing";
    
    foreach (@$pt) {
	$_->{ending} = $_->{start} + $_->{size};
	$_->{gpt_type} = $gpt_types{$_->{type}} || $_->{gpt_type} || $gpt_types{0x83};
    }

    $info->{csum} = compute_crc($info);

    c::lseek_sector(fileno(F), $info->{myLBA}, 0) or return 0;
    #- pad with 0's
    syswrite F, pack($main_format, @$info{@$main_fields}) . "\0" x 512, 512 or return 0;

    c::lseek_sector(fileno(F), $info->{myLBA}, 0) or return 0;
    

    common::sync();
    1;
}

sub info {
    my ($hd) = @_;

    #- build a default suitable partition table,
    #- checksum will be built when writing on disk.
    my $info = {
	magic => $magic,
	revision => $current_revision
    };

    $info;
}

sub clear_raw {
    my ($hd) = @_;
    my $pt = { raw => [ ({}) x 128 ], info => info($hd) };

    #- handle special case for partition 2 which is whole disk.
    $pt->{raw}[2] = {
	type => 5, #- the whole disk type.
	flags => 0,
	start_cylinder => 0,
	size => $hd->{geom}{cylinders} * $hd->cylinder_size(),
    };

    $pt;
}

1;
