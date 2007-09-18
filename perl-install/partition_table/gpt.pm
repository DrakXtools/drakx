package partition_table::gpt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use partition_table::dos;
use partition_table;
use fs::type;
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

my ($guid_format, $guid_fields) = list2kv(
  N     => 'time_low',
  n     => 'time_mid',
  n     => 'time_hi_and_version',
  n     => 'clock_seq',
  a6    => 'node',
);

$_ = join('', @$_) foreach $main_format, $partitionEntry_format, $guid_format;

my $magic = "EFI PART";

sub generate_guid() {
    my $tmp;
    open(my $F, devices::make("random")) or die "Could not open /dev/random for GUID generation";
    read $F, $tmp, psizeof($guid_format);
	
    my %guid; @guid{@$guid_fields} = unpack $guid_format, $tmp;
    $guid{clock_seq} = ($guid{clock_seq} & 0x3fff) | 0x8000;
    $guid{time_hi_and_version} = ($guid{time_hi_and_version} & 0x0fff) | 0x4000;
    pack($guid_format, @guid{@$guid_fields});
}

sub crc32 {
    my ($buffer) = @_;

    my $crc = 0xFFFFFFFF;
    foreach (unpack "C*", $buffer) {
	my $subcrc = ($crc ^ $_) & 0xFF;
        for (my $j = 8; $j > 0; $j--) {
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

sub read_header {
    my ($sector, $F) = @_;
    my $tmp;

    c::lseek_sector(fileno($F), $sector, 0) or die "reading of partition in sector $sector failed";

    sysread $F, $tmp, psizeof($main_format) or die "error while reading partition table in sector $sector";
    my %info; @info{@$main_fields} = unpack $main_format, $tmp;
    
    $info{magic} eq $magic or die "bad magic number";
    $info{myLBA} == $sector or die "myLBA is not the same";
    $info{headerSize} == psizeof($main_format) or die "bad partition table header size";
    $info{partitionEntrySize} == psizeof($partitionEntry_format) or die "bad partitionEntrySize";
    $info{revision} <= $current_revision or log::l("oops, this is a new GPT revision ($info{revision} > $current_revision)");

    $info{headerCRC32} == compute_headerCRC32(\%info) or die "bad partition table checksum";
    \%info;
}

sub read_partitionEntries {
    my ($info, $F) = @_;
    my $tmp;

    c::lseek_sector(fileno($F), $info->{partitionEntriesLBA}, 0) or die "can not seek to sector partitionEntriesLBA";
    sysread $F, $tmp, psizeof($partitionEntry_format) * $info->{nbPartitions} or die "error while reading partition table in sector $info->{partitionEntriesLBA}";
    $info->{partitionEntriesCRC32} == crc32($tmp) or die "bad partition entries checksum";

    c::lseek_sector(fileno($F), $info->{partitionEntriesLBA}, 0) or die "can not seek to sector partitionEntriesLBA";
    my %gpt_types_rev = reverse %gpt_types;
    my @pt = 
      map {
	sysread $F, $tmp, psizeof($partitionEntry_format) or die "error while reading partition table in sector $info->{partitionEntriesLBA}";
	my %h; @h{@$partitionEntry_fields} = unpack $partitionEntry_format, $tmp;
	$h{size} = $h{ending} - $h{start} + 1;
	my $pt_type = $gpt_types_rev{$h{gpt_type}};
	fs::type::set_pt_type(\%h, defined $pt_type ? $pt_type : 0x100);
	\%h;
    } (1 .. $info->{nbPartitions});
    \@pt;
}

sub read_one {
    my ($hd, $sector) = @_;

    my $l = partition_table::dos::read($hd, $sector);
    my @l = grep { $_->{size} && $_->{pt_type} && !partition_table::isExtended($_) } @$l;
    @l == 1 or die "bad PMBR";
    $l[0]{pt_type} == 0xee or die "bad PMBR";
    my $myLBA = $l[0]{start};

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    my $info1 = eval { read_header($myLBA, $F) };
    my $info2 = eval { read_header($info1->{alternateLBA} || $l[0]{start} + $l[0]{size} - 1, $F) }; #- what about using $hd->{totalsectors} ???
    my $info = $info1 || { %$info2, myLBA => $info2->{alternateLBA}, alternateLBA => $info2->{myLBA}, partitionEntriesLBA => $info2->{alternateLBA} + 1 } or die;
    my $pt = $info1 && $info2 ? 
	eval { $info1 && read_partitionEntries($info1, $F) } || read_partitionEntries($info2, $F) :
	read_partitionEntries($info, $F);
    $hd->raw_removed($pt);

    $pt, $info;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, pt_type, active
sub write {
    my ($hd, $sector, $pt, $info) = @_;

    foreach (@$pt) {
	$_->{ending} = $_->{start} + $_->{size} - 1;
	$_->{guid} ||= generate_guid();
	$_->{gpt_type} = $gpt_types{$_->{pt_type}} || $_->{gpt_type} || $gpt_types{0x83};
    }
    my $partitionEntries = join('', map {
	pack($partitionEntry_format, @$_{@$partitionEntry_fields});	
    } (@$pt, ({}) x ($info->{nbPartitions} - @$pt)));

    $info->{partitionEntriesCRC32} = crc32($partitionEntries);
    $info->{headerCRC32} = compute_headerCRC32($info);

    my $info2 = { %$info, 
		  myLBA => $info->{alternateLBA}, alternateLBA => $info->{myLBA}, 
		  partitionEntriesLBA => $info->{alternateLBA} - psizeof($partitionEntry_format) * $info->{nbPartitions} / 512,
		};
    $info2->{headerCRC32} = compute_headerCRC32($info2);

    {
	# write the PMBR
	my $pmbr = partition_table::dos::empty_raw();
	$pmbr->{raw}[0] = { pt_type => 0xee, local_start => $info->{myLBA}, size => $info->{alternateLBA} - $info->{myLBA} + 1 };
	partition_table::dos::write($hd, $sector, $pmbr->{raw});
    }

    my $F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
    
    c::lseek_sector(fileno($F), $info->{myLBA}, 0) or return 0;
    #- pad with 0's
    syswrite $F, pack($main_format, @$info{@$main_fields}) . "\0" x 512, 512 or return 0;

    c::lseek_sector(fileno($F), $info->{alternateLBA}, 0) or return 0;
    #- pad with 0's
    syswrite $F, pack($main_format, @$info2{@$main_fields}) . "\0" x 512, 512 or return 0;

    c::lseek_sector(fileno($F), $info->{partitionEntriesLBA}, 0) or return 0;
    syswrite $F, $partitionEntries or return 0;
    
    c::lseek_sector(fileno($F), $info2->{partitionEntriesLBA}, 0) or return 0;
    syswrite $F, $partitionEntries or return 0;

    common::sync();
    1;
}

sub raw_removed {
    my ($_hd, $raw) = @_;
    @$raw = grep { $_->{size} && $_->{pt_type} } @$raw;
}
sub can_raw_add {
    my ($hd) = @_;
    @{$hd->{primary}{raw}} < $hd->{primary}{info}{nbPartitions};
}
sub raw_add {
    my ($hd, $raw, $part) = @_;
    $hd->can_raw_add or die "raw_add: partition table already full";
    push @$raw, $part;
}

sub use_pt_type { 1 }

sub adjustStart {}
sub adjustEnd {}

sub first_usable_sector {
    my ($hd) = @_;
    $hd->{primary}{info}{firstUsableLBA};
}
sub last_usable_sector { 
    my ($hd) = @_;
    $hd->{primary}{info}{lastUsableLBA} + 1;
}

sub info {
    my ($hd) = @_;
    my $nb_sect = 32;

    #- build a default suitable partition table,
    #- checksum will be built when writing on disk.
    {
	magic => $magic,
	revision => $current_revision,
	headerSize => psizeof($main_format),
	myLBA => 1,
	alternateLBA => $hd->{totalsectors} - 1,
	firstUsableLBA => $nb_sect + 2,
	lastUsableLBA => $hd->{totalsectors} - $nb_sect - 2,
	guid => generate_guid(),
	partitionEntriesLBA => 2,
	nbPartitions => $nb_sect * 512 / psizeof($partitionEntry_format),
	partitionEntrySize => psizeof($partitionEntry_format),
    };
}

sub initialize {
    my ($class, $hd) = @_;
    $hd->{primary} = { raw => [], info => info($hd) };
    bless $hd, $class;
}

1;
