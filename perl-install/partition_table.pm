package partition_table;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @important_types @fields2save);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    types => [ qw(type2name type2fs name2type fs2type isExtended isExt2 isSwap isDos isWin isFat isPrimary isNfs) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


use common qw(:common :system :functional);
use partition_table_raw;
use Data::Dumper;


@important_types = ("Linux native", "Linux swap", "DOS FAT16", "Win98 FAT32");

@fields2save = qw(primary extended totalsectors);


my %types = (
  0 => "Empty",
  1 => "DOS 12-bit FAT",
  2 => "XENIX root",
  3 => "XENIX usr",
  4 => "DOS 16-bit <32M",
  5 => "Extended",
  6 => "DOS FAT16",
  7 => "OS/2 HPFS",               #- or QNX?
  8 => "AIX",
  9 => "AIX bootable",
  10 => "OS/2 Boot Manager",
  0xb => "Win98 FAT32 0xb",
  0xc => "Win98 FAT32",
  0xe => "Win95 FAT16",
  0xf => "Win95 Ext'd (LBA)",
  0x12 => "Compaq setup",
  0x40 => "Venix 80286",
  0x51 => "Novell?",
  0x52 => "Microport",            #- or CPM?
  0x63 => "GNU HURD",             #- or System V/386?
  0x64 => "Novell Netware 286",
  0x65 => "Novell Netware 386",
  0x75 => "PC/IX",
  0x80 => "Old MINIX",            #- Minix 1.4a and earlier

  0x81 => "Linux/MINIX", #- Minix 1.4b and later
  0x82 => "Linux swap",
  0x83 => "Linux native",

  0x93 => "Amoeba",
  0x94 => "Amoeba BBT",           #- (bad block table)
  0xa5 => "BSD/386",
  0xb7 => "BSDI fs",
  0xb8 => "BSDI swap",
  0xc7 => "Syrinx",
  0xdb => "CP/M",                 #- or Concurrent DOS?
  0xe1 => "DOS access",
  0xe3 => "DOS R/O",
  0xf2 => "DOS secondary",
  0xff => "BBT"                   #- (bad track table)
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
  nfs  => 'nfs', #- hack
);
my %types_rev = reverse %types;
my %fs2type = reverse %type2fs;


1;

sub important_types { $_[0] and return sort values %types; @important_types }

sub type2name($) { $types{$_[0]} || $_[0] }
sub type2fs($) { $type2fs{$_[0]} }
sub fs2type($) { $fs2type{$_[0]} }
sub name2type($) { 
    local ($_) = @_;
    /0x(.*)/ ? hex $1 : $types_rev{$_} || $_;
}

sub isExtended($) { $_[0]{type} == 5 || $_[0]{type} == 0xf }
sub isSwap($) { $type2fs{$_[0]{type}} eq 'swap' }
sub isExt2($) { $type2fs{$_[0]{type}} eq 'ext2' }
sub isDos($) { $ {{ 1=>1, 4=>1, 6=>1 }}{$_[0]{type}} }
sub isWin($) { $ {{ 0xb=>1, 0xc=>1, 0xe=>1 }}{$_[0]{type}} }
sub isFat($) { isDos($_[0]) || isWin($_[0]) }
sub isNfs($) { $_[0]{type} eq 'nfs' } #- small hack

sub isPrimary($$) {
    my ($part, $hd) = @_;
    foreach (@{$hd->{primary}{raw}}) { $part eq $_ and return 1; }
    0;
}

sub cylinder_size($) {
    my ($hd) = @_;
    $hd->{geom}{sectors} * $hd->{geom}{heads};
}

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};

    $part->{start} = round_up($part->{start},
			       $part->{start} % cylinder_size($hd) < 2 * $hd->{geom}{sectors} ?
			       $hd->{geom}{sectors} : cylinder_size($hd));
    $part->{size} = $end - $part->{start};
}
sub adjustEnd($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};
    my $end2 = round_down($end, cylinder_size($hd));
    unless ($part->{start} < $end2) {
	$end2 = round_up($end, cylinder_size($hd));
    }
    $part->{size} = $end2 - $part->{start};
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

sub verifyParts_ {
    foreach my $i (@_) { foreach (@_) {
	$i != $_ and verifyNotOverlap($i, $_) || die "partitions $i->{start} $i->{size} and $_->{start} $_->{size} are overlapping!";
    }}
}
sub verifyParts($) {
    my ($hd) = @_;
    verifyParts_(get_normal_parts($hd));
}
sub verifyPrimary($) {
    my ($pt) = @_;
    verifyParts_(@{$pt->{normal}}, $pt->{extended});
}

sub assign_device_numbers($) {
    my ($hd) = @_;

    my $i = 1;
    $_->{device} = $hd->{prefix} . $i++ foreach @{$hd->{primary}{raw}},
                                                map { $_->{normal} } @{$hd->{extended} || []};

    #- try to figure what the windobe drive letter could be!
    #
    #- first verify there's at least one primary dos partition, otherwise it
    #- means it is a secondary disk and all will be false :(
    my ($c, @others) = grep { isFat($_) } @{$hd->{primary}{normal}};
    $c or return;

    $i = ord 'D';
    foreach (grep { isFat($_) } map { $_->{normal} } @{$hd->{extended}}) {
	$_->{device_windobe} = chr($i++);
    }
    $c->{device_windobe} = 'C';
    $_->{device_windobe} = chr($i++) foreach @others;
}

sub remove_empty_extended($) {
    my ($hd) = @_;
    my $last = $hd->{primary}{extended} or return;
    @{$hd->{extended}} = grep {
	if ($_->{normal}) {
	    $last = $_;
	} else {
	    %{$last->{extended}} = $_->{extended} ? %{$_->{extended}} : ();
	}
	$_->{normal};
    } @{$hd->{extended}};
    adjust_main_extended($hd);
}

sub adjust_main_extended($) {
    my ($hd) = @_;

    if (!is_empty_array_ref $hd->{extended}) {
	my ($l, @l) = @{$hd->{extended}};

	# the first is a special case, must recompute its real size
	my $start = round_down($l->{normal}{start} - 1, $hd->{geom}{sectors});
	my $end = $l->{normal}{start} + $l->{normal}{size};
	foreach (map $_->{normal}, @l) {
	    $start = min($start, $_->{start});
	    $end = max($end, $_->{start} + $_->{size});
	}
	$l->{start} = $hd->{primary}{extended}{start} = $start;
	$l->{size} = $hd->{primary}{extended}{size} = $end - $start;
    }
    unless (@{$hd->{extended} || []} || !$hd->{primary}{extended}) {
	%{$hd->{primary}{extended}} = (); #- modify the raw entry
	delete $hd->{primary}{extended};
    }
    verifyParts($hd); #- verify everything is all right
}


sub get_normal_parts($) {
    my ($hd) = @_;

    @{$hd->{primary}{normal} || []}, map { $_->{normal} } @{$hd->{extended} || []}
}


sub read_one($$) {
    my ($hd, $sector) = @_;

    my $pt = partition_table_raw::read($hd, $sector) or return;

    my @extended = grep { isExtended($_) } @$pt;
    my @normal = grep { $_->{size} && $_->{type} && !isExtended($_) } @$pt;

    @extended > 1 and die "more than one extended partition";

    $_->{rootDevice} = $hd->{device} foreach @normal, @extended;
    { raw => $pt, extended => $extended[0], normal => \@normal };
}

sub read($;$) {
    my ($hd, $clearall) = @_;
    my $pt = $clearall ?
      partition_table_raw::clear_raw() :
      read_one($hd, 0) || return 0;

    $hd->{primary} = $pt;
    $hd->{extended} = undef;
    $clearall and return $hd->{isDirty} = $hd->{needKernelReread} = 1;
    verifyPrimary($pt);

    eval {
	$pt->{extended} and read_extended($hd, $pt->{extended}) || return 0;
    }; die "extended partition: $@" if $@;
    assign_device_numbers($hd);
    remove_empty_extended($hd);
    1;
}

sub read_extended {
    my ($hd, $extended) = @_;

    my $pt = read_one($hd, $extended->{start}) or return 0;
    $pt = { %$extended, %$pt };

    push @{$hd->{extended}}, $pt;
    @{$hd->{extended}} > 100 and die "oops, seems like we're looping here :(  (or you have more than 100 extended partitions!)";

    @{$pt->{normal}} <= 1 or die "more than one normal partition in extended partition";
    @{$pt->{normal}} >= 1 or die "no normal partition in extended partition";
    $pt->{normal} = $pt->{normal}[0];
    #- in case of extended partitions, the start sector is local to the partition or to the first extended_part!
    $pt->{normal}{start} += $pt->{start};

    verifyInside($pt->{normal}, $extended) or die "partition $pt->{normal}{device} is not inside its extended partition";

    if ($pt->{extended}) {
	$pt->{extended}{start} += $hd->{primary}{extended}{start};
	read_extended($hd, $pt->{extended}) or return 0;
    }
    1;
}

# write the partition table
sub write($) {
    my ($hd) = @_;

    #- set first primary partition active if no primary partitions are marked as active.
    for ($hd->{primary}{raw}) {
	(grep { $_->{local_start} = $_->{start}; $_->{active} ||= 0 } @$_) or $_->[0]{active} = 0x80;
    }
    partition_table_raw::write($hd, 0, $hd->{primary}{raw}) or die "writing of partition table failed";

    foreach (@{$hd->{extended}}) {
	# in case of extended partitions, the start sector must be local to the partition
	$_->{normal}{local_start} = $_->{normal}{start} - $_->{start};
	$_->{extended} and $_->{extended}{local_start} = $_->{extended}{start} - $hd->{primary}{extended}{start};

	partition_table_raw::write($hd, $_->{start}, $_->{raw}) or die "writing of partition table failed";
    }
    $hd->{isDirty} = 0;

    #- now sync disk and re-read the partition table
    if ($hd->{needKernelReread}) {
	sync();
	partition_table_raw::kernel_read($hd);
	$hd->{needKernelReread} = 0;
    }
}

sub active($$) {
    my ($hd, $part) = @_;

    $_->{active} = 0 foreach @{$hd->{primary}{normal}};
    $part->{active} = 0x80;
}


# remove a normal partition from hard drive hd
sub remove($$) {
    my ($hd, $part) = @_;
    my $i;

    #- first search it in the primary partitions
    $i = 0; foreach (@{$hd->{primary}{normal}}) {
	if ($_ eq $part) {
	    splice(@{$hd->{primary}{normal}}, $i, 1);
	    %$_ = (); #- blank it

	    return $hd->{isDirty} = $hd->{needKernelReread} = 1;
	}
	$i++;
    }
    #- otherwise search it in extended partitions
    foreach (@{$hd->{extended}}) {
	$_->{normal} eq $part or next;

	delete $_->{normal}; #- remove it
	remove_empty_extended($hd);

	return $hd->{isDirty} = $hd->{needKernelReread} = 1;
    }
    0;
}

# create of partition at starting at `start', of size `size' and of type `type' (nice comment, uh?)
sub add_primary($$) {
    my ($hd, $part) = @_;

    {
	local $hd->{primary}{normal}; #- save it to fake an addition of $part, that way add_primary do not modify $hd if it fails
	push @{$hd->{primary}{normal}}, $part;
	adjust_main_extended($hd); #- verify
	raw_add($hd->{primary}{raw}, $part);
    }
    push @{$hd->{primary}{normal}}, $part; #- really do it
}

sub add_extended($$) {
    my ($hd, $part) = @_;

    my $e = $hd->{primary}{extended};

    if ($e && !verifyInside($part, $e)) {
	#-die "sorry, can't add outside the main extended partition" unless $::unsafe;
	my $end = $e->{start} + $e->{size};
	my $start = min($e->{start}, $part->{start});
	$end = max($end, $part->{start} + $part->{size}) - $start;

	{ #- faking a resizing of the main extended partition to test for problems
	    local $e->{start} = $start;
	    local $e->{size} = $end - $start;
	    eval { verifyPrimary($hd->{primary}) };
	    $@ and die
_("You have a hole in your partition table but I can't use it.
The only solution is to move your primary partitions to have the hole next to the extended partitions");
	}
    }

    if ($e && $part->{start} < $e->{start}) {
	my $l = first (@{$hd->{extended}});

	#- the first is a special case, must recompute its real size
	$l->{start} = round_down($l->{normal}{start} - 1, cylinder_size($hd));
	$l->{size} = $l->{normal}{start} + $l->{normal}{size} - $l->{start};
	my $ext = { %$l };
	unshift @{$hd->{extended}}, { type => 5, raw => [ $part, $ext, {}, {} ], normal => $part, extended => $ext };
	#- size will be autocalculated :)
    } else {
	my ($ext, $ext_size) = is_empty_array_ref($hd->{extended}) ?
	  ($hd->{primary}, -1) : #- -1 size will be computed by adjust_main_extended
	  (top(@{$hd->{extended}}), $part->{size});
	my %ext = ( type => 5, start => $part->{start}, size => $ext_size );

	raw_add($ext->{raw}, \%ext);
	$ext->{extended} = \%ext;
	push @{$hd->{extended}}, { %ext, raw => [ $part, {}, {}, {} ], normal => $part };
    }
    $part->{start}++; $part->{size}--; #- let it start after the extended partition sector
    adjustStartAndEnd($hd, $part);

    adjust_main_extended($hd);
}

sub add($$;$$) {
    my ($hd, $part, $primaryOrExtended, $forceNoAdjust) = @_;

    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;
    $part->{rootDevice} = $hd->{device};
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    $part->{start} ||= 1; #- starting at sector 0 is not allowed
    adjustStartAndEnd($hd, $part) unless $forceNoAdjust;

    my $e = $hd->{primary}{extended};

    if ($primaryOrExtended eq 'Primary' ||
	$primaryOrExtended ne 'Extended' && is_empty_array_ref($hd->{primary}{normal})) {
	eval { add_primary($hd, $part) };
	return unless $@;
    }
    eval { add_extended($hd, $part) }; #- try adding extended
    if (my $err = $@) {
	eval { add_primary($hd, $part) };
	die $@ if $@; #- send the add extended error which should be better
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

sub load($$;$) {
    my ($hd, $file, $force) = @_;

    local *F;
    open F, $file or die _("Error reading file %s", $file);

    my $h;
    {
	local $/ = "\0";
	eval <F>;
    }
    $@ and die _("Restoring from file %s failed: %s", $file, $@);

    ref $h eq 'ARRAY' or die _("Bad backup file");

    my %h; @h{@fields2save} = @$h;

    $h{totalsectors} == $hd->{totalsectors} or $force or cdie("Bad totalsectors");

    #- unsure we don't modify totalsectors
    local $hd->{totalsectors};

    @{$hd}{@fields2save} = @$h;

    $hd->{isDirty} = $hd->{needKernelReread} = 1;
}

sub save($$) {
    my ($hd, $file) = @_;
    my @h = @{$hd}{@fields2save};
    local *F;
    open F, ">$file"
      and print F Data::Dumper->Dump([\@h], ['$h']), "\0"
      or die _("Error writing to file %s", $file);
}
