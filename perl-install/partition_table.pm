package partition_table;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @important_types);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    types => [ qw(type2name type2fs name2type fs2type isExtended isExt2 isSwap isDos isWin isPrimary isNfs) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


use common qw(:common :system);
use partition_table_raw;


@important_types = ("Linux native", "Linux swap", "DOS FAT16", "Win98 FAT32");

my %types = (
  0 => "Empty",
  1 => "DOS 12-bit FAT",
  2 => "XENIX root",
  3 => "XENIX usr",
  4 => "DOS 16-bit <32M",
  5 => "Extended",
  6 => "DOS FAT16",
  7 => "OS/2 HPFS",               # or QNX? 
  8 => "AIX",
  9 => "AIX bootable",
  10 => "OS/2 Boot Manager",
  0xb => "Win98 FAT32 0xb",
  0xc => "Win98 FAT32",
  0xe => "Win98 FAT32 0xd",
  0x12 => "Compaq setup",
  0x40 => "Venix 80286",
  0x51 => "Novell?",
  0x52 => "Microport",            # or CPM? 
  0x63 => "GNU HURD",             # or System V/386? 
  0x64 => "Novell Netware 286",
  0x65 => "Novell Netware 386",
  0x75 => "PC/IX",
  0x80 => "Old MINIX",            # Minix 1.4a and earlier 
  
  0x81 => "Linux/MINIX", # Minix 1.4b and later 
  0x82 => "Linux swap",
  0x83 => "Linux native",
  
  0x93 => "Amoeba",
  0x94 => "Amoeba BBT",           # (bad block table) 
  0xa5 => "BSD/386",
  0xb7 => "BSDI fs",
  0xb8 => "BSDI swap",
  0xc7 => "Syrinx",
  0xdb => "CP/M",                 # or Concurrent DOS? 
  0xe1 => "DOS access",
  0xe3 => "DOS R/O",
  0xf2 => "DOS secondary",
  0xff => "BBT"                   # (bad track table) 
);

my %type2fs = (
  0x01 => 'vfat',
  0x04 => 'vfat',
  0x05 => 'ignore',
  0x06 => 'vfat',
  0x07 => 'hpfs',
  0x0b => 'vfat',
  0x0c => 'vfat',
  0x0e => 'vfat',
  0x82 => 'swap',
  0x83 => 'ext2',
  nfs  => 'nfs', # hack
);
my %types_rev = reverse %types;
my %fs2type = reverse %type2fs;


1;

sub type2name($) { $types{$_[0]} }
sub type2fs($) { $type2fs{$_[0]} }
sub name2type($) { $types_rev{$_[0]} }
sub fs2type($) { $fs2type{$_[0]} }

sub isExtended($) { $_[0]->{type} == 5 }
sub isSwap($) { $type2fs{$_[0]->{type}} eq 'swap' }
sub isExt2($) { $type2fs{$_[0]->{type}} eq 'ext2' }
sub isDos($) { $ {{ 1=>1, 4=>1, 6=>1 }}{$_[0]->{type}} }
sub isWin($) { $ {{ 0xb=>1, 0xc=>1, 0xe=>1 }}{$_[0]->{type}} }
sub isNfs($) { $_[0]->{type} eq 'nfs' } # small hack

sub isPrimary($$) {
    my ($part, $hd) = @_;
    foreach (@{$hd->{primary}->{raw}}) { $part eq $_ and return 1; }
    0;
}

sub cylinder_size($) { 
    my ($hd) = @_;
    $hd->{geom}->{sectors} * $hd->{geom}->{heads};
}

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    $part->{start} = round_up($part->{start}, 
			       $part->{start} % cylinder_size($hd) < 2 * $hd->{geom}->{sectors} ?
			       $hd->{geom}->{sectors} : cylinder_size($hd));
    $part->{size} = $end - $part->{start};
}
sub adjustEnd($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    $end = round_down($end, cylinder_size($hd));
    $part->{size} = $end - $part->{start};
}
sub adjustStartAndEnd($$) {
    &adjustStart;
    &adjustEnd;
}

sub verifyNotOverlap($$) {
    my ($a, $b) = @_;
    $a->{start} + $a->{size} <= $b->{start} || $b->{start} + $b->{size} <= $a->{start};
}
sub verifyInside($$) {
    my ($a, $b) = @_;
    $b->{start} <= $a->{start} && $a->{start} + $a->{size} <= $b->{start} + $b->{size};
}

sub assign_device_numbers($) {
    my ($hd) = @_;

    my $i = 1; foreach (@{$hd->{primary}->{raw}}, map { $_->{normal} } @{$hd->{extended}}) { 
	$_->{device} = $hd->{prefix} . $i++;
    }
}

sub get_normal_parts($) {
    my ($hd) = @_;

    @{$hd->{primary}->{normal} || []}, map { $_->{normal} } @{$hd->{extended} || []}
}


sub read_one($$) {
    my ($hd, $sector) = @_;

    my $pt = partition_table_raw::read($hd, $sector) or return;

    my @extended = grep { isExtended($_) } @$pt;
    my @normal = grep { $_->{size} && $_->{type} && !isExtended($_) } @$pt;

    @extended > 1 and die "more than one extended partition";

    foreach (@normal, @extended) {
	$_->{rootDevice} = $hd->{device};
    }
    { raw => $pt, extended => $extended[0], normal => \@normal };
}

sub read($;$) {
    my ($hd, $clearall) = @_;
    my $pt = $clearall ? { raw => [ {}, {}, {}, {} ] } : read_one($hd, 0) || return 0;

    $hd->{primary} = $pt;
    $hd->{extended} = undef;
    $clearall and return $hd->{isDirty} = $hd->{needKernelReread} = 1;

    my @l = (@{$pt->{normal}}, $pt->{extended});
    foreach my $i (@l) { foreach (@l) {
	$i != $_ and verifyNotOverlap($i, $_) || die "partitions $i->{device} and $_->{device} are overlapping!";
    }}

    eval {
	$pt->{extended} and read_extended($hd, $pt->{extended}) || return 0;
    }; die "extended partition: $@" if $@;
    assign_device_numbers($hd);
    1;
}

sub read_extended($$) {
    my ($hd, $extended) = @_;

    my $pt = read_one($hd, $extended->{start}) or return 0;
    $pt = { %$extended, %$pt };

    push @{$hd->{extended}}, $pt;
    @{$hd->{extended}} > 100 and die "oops, seems like we're looping here :(  (or you have more than 100 extended partitions!)";

    @{$pt->{normal}} <= 1 or die "more than one normal partition in extended partition";
    @{$pt->{normal}} >= 1 or die "no normal partition in extended partition";
    $pt->{normal} = $pt->{normal}->[0];
    # in case of extended partitions, the start sector is local to the partition or to the first extended_part!
    $pt->{normal}->{start} += $pt->{start};

    verifyInside($pt->{normal}, $extended) or die "partition $pt->{normal}->{device} is not inside its extended partition";

    if ($pt->{extended}) {
	$pt->{extended}->{start} += $hd->{primary}->{extended}->{start};
	read_extended($hd, $pt->{extended}) or return 0;
    }
    1;
}

# give a hard drive hd, write the partition data 
sub write($) {
    my ($hd) = @_;

    # set first primary partition active if no primary partitions are marked as active.
    for ($hd->{primary}->{raw}) {
	(grep { $_->{local_start} = $_->{start}; $_->{active} ||= 0 } @$_) or $_->[0]->{active} = 0x80;
    }
    partition_table_raw::write($hd, 0, $hd->{primary}->{raw}) or die "writing of partition table failed";

    foreach (@{$hd->{extended}}) {
	# in case of extended partitions, the start sector must be local to the partition
	$_->{normal}->{local_start} = $_->{normal}->{start} - $_->{start};
	$_->{extended} and $_->{extended}->{local_start} = $_->{extended}->{start} - $hd->{primary}->{extended}->{start};

	partition_table_raw::write($hd, $_->{start}, $_->{raw}) or die "writing of partition table failed";
    }
    $hd->{isDirty} = 0;

    # now sync disk and re-read the partition table 
    if ($hd->{needKernelReread}) {
	sync();
	partition_table_raw::kernel_read($hd);
	$hd->{needKernelReread} = 0;
    }
}

sub active($$) {
    my ($hd, $part) = @_;

    foreach (@{$hd->{primary}->{normal}}) { $_->{active} = 0; }
    $part->{active} = 0x80;   
}


# remove a normal partition from hard drive hd
sub remove($$) {
    my ($hd, $part) = @_;
    my $i;

    # first search it in the primary partitions
    $i = 0; foreach (@{$hd->{primary}->{normal}}) {
	if ($_ eq $part) {
	    splice(@{$hd->{primary}->{normal}}, $i, 1);
	    %$_ = ();

	    return $hd->{isDirty} = $hd->{needKernelReread} = 1;
	}
	$i++;
    }
    # otherwise search it in extended partitions
    my $last = $hd->{primary}->{extended};
    $i = 0; foreach (@{$hd->{extended}}) {
	if ($_->{normal} eq $part) {
	    %{$last->{extended}} = $_->{extended} ? %{$_->{extended}} : ();
	    splice(@{$hd->{extended}}, $i, 1);
	    
	    return $hd->{isDirty} = $hd->{needKernelReread} = 1;
	}
	$last = $_;
	$i++;
    }
    0;
}

# create of partition at starting at `start', of size `size' and of type `type' (nice comment, uh?)
# !be carefull!, no verification is done (start -> start+size must be free)
sub add($$) {
    my ($hd, $part) = @_;

    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;
    $part->{rootDevice} = $hd->{device};
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    adjustStartAndEnd($hd, $part);

    if (is_empty_array_ref($hd->{primary}->{normal})) {
	raw_add($hd->{primary}->{raw}, $part);
	@{$hd->{primary}->{normal}} = $part;
    } else {
	$hd->{primary}->{extended} && !verifyInside($part, $hd->{primary}->{extended})
	  and die "sorry, can't add outside the main extended partition";

	foreach (@{$hd->{extended}}) {
	    $_->{normal} and next;
	    raw_add($_->{raw}, $part);
	    $_->{normal} = $part;
	    return;
	}
	my ($ext, $ext_size) = is_empty_array_ref($hd->{extended}) ?
	  ($hd->{primary}, $hd->{totalsectors} - $part->{start}) :
	  (top(@{$hd->{extended}}), $part->{size});
	my %ext = ( type => 5, start => $part->{start}, size => $ext_size );
	
	raw_add($ext->{raw}, \%ext);
	$ext->{extended} = \%ext;
	push @{$hd->{extended}}, { %ext, raw => [ $part, {}, {}, {} ], normal => $part };

	$part->{start}++; $part->{size}--; # let it start after the extended partition sector
	adjustStartAndEnd($hd, $part);
    }
}

# search for the next partition
sub next($$) {
    my ($hd, $part) = @_;

    first(
	  sort { $a->{start} <=> $b->{start} } 
	  grep { $_->{start} >= $part->{start} + $part->{size} }
	  get_normal_parts($hd)
	 );
}
sub next_start($$) {
    my ($hd, $part) = @_;
    my $next = &next($hd, $part);
    $next ? $next->{start} : $hd->{totalsectors};
}


sub raw_add($$) {
    my ($raw, $part) = @_;

    foreach (@$raw) {
	$_->{size} || $_->{type} and next;
	$_ = $part;
	return;
    }
    die "raw_add: partition table already full";
}

