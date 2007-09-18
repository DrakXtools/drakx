package partition_table; # $Id$

use diagnostics;
use strict;

use common;
use fs::type;
use partition_table::raw;
use detect_devices;
use log;

our @fields2save = qw(primary extended totalsectors isDirty will_tell_kernel);


sub hd2minimal_part {
    my ($hd) = @_;
    { 
	rootDevice => $hd->{device}, 
	if_($hd->{usb_media_type}, is_removable => 1),
    };
}

#- works for both hard drives and partitions ;p
sub description {
    my ($hd) = @_;
    my $win = $hd->{device_windobe};

    sprintf "%s%s (%s)", 
      $hd->{device}, 
      $win && " [$win:]", 
	join(', ', 
	     grep { $_ } 
	       formatXiB($hd->{totalsectors} || $hd->{size}, 512),
	       $hd->{info}, $hd->{mntpoint}, $hd->{fs_type});
}

sub adjustStartAndEnd {
    my ($hd, $part) = @_;

    $hd->adjustStart($part);
    $hd->adjustEnd($part);
}

sub verifyNotOverlap {
    my ($a, $b) = @_;
    $a->{start} + $a->{size} <= $b->{start} || $b->{start} + $b->{size} <= $a->{start};
}
sub verifyInside {
    my ($a, $b) = @_;
    $b->{start} <= $a->{start} && $a->{start} + $a->{size} <= $b->{start} + $b->{size};
}

sub verifyParts_ {
    foreach my $i (@_) {
	foreach (@_) {
	    next if !$i || !$_ || $i == $_ || isWholedisk($i) || isExtended($i); #- avoid testing twice for simplicity :-)
	    if (isWholedisk($_)) {
		verifyInside($i, $_) or
		  cdie sprintf("partition sector #$i->{start} (%s) is not inside whole disk (%s)!",
			       formatXiB($i->{size}, 512), formatXiB($_->{size}, 512));
	    } elsif (isExtended($_)) {
		verifyNotOverlap($i, $_) or
		  log::l(sprintf("warning partition sector #$i->{start} (%s) is overlapping with extended partition!",
				 formatXiB($i->{size}, 512))); #- only warning for this one is acceptable
	    } else {
		verifyNotOverlap($i, $_) or
		  cdie sprintf("partitions sector #$i->{start} (%s) and sector #$_->{start} (%s) are overlapping!",
			       formatXiB($i->{size}, 512), formatXiB($_->{size}, 512));
	    }
	}
    }
}
sub verifyParts {
    my ($hd) = @_;
    verifyParts_(get_normal_parts($hd));
}
sub verifyPrimary {
    my ($pt) = @_;
    $_->{start} > 0 || arch() =~ /^sparc/ || die "partition must NOT start at sector 0" foreach @{$pt->{normal}};
    verifyParts_(@{$pt->{normal}}, $pt->{extended});
}

sub compute_device_name {
    my ($part, $hd) = @_;
    $part->{device} = $hd->{prefix} . $part->{part_number};
}

sub assign_device_numbers {
    my ($hd) = @_;

    my $i = 1;
    my $start = 1; 
    
    #- on PPC we need to assign device numbers to the holes too - big FUN!
    #- not if it's an IBM machine using a DOS partition table though
    if (arch() =~ /ppc/ && detect_devices::get_mac_model() !~ /^IBM/) {
	#- first sort the normal parts
	$hd->{primary}{normal} = [ sort { $a->{start} <=> $b->{start} } @{$hd->{primary}{normal}} ];
    
	#- now loop through them, assigning partition numbers - reserve one for the holes
	foreach (@{$hd->{primary}{normal}}) {
	    if ($_->{start} > $start) {
		log::l("PPC: found a hole on $hd->{prefix} before $_->{start}, skipping device..."); 
		$i++;
	    }
	    $_->{part_number} = $i;
	    compute_device_name($_, $hd);
	    $start = $_->{start} + $_->{size};
	    $i++;
	}
    } else {
	foreach (@{$hd->{primary}{raw}}) {
	    $_->{part_number} = $i;
	    compute_device_name($_, $hd);
	    $i++;
	}
	foreach (map { $_->{normal} } @{$hd->{extended} || []}) {
	    my $dev = $hd->{prefix} . $i;
	    my $renumbered = $_->{device} && $dev ne $_->{device};
	    if ($renumbered) {
		require fs::mount;
		eval { fs::mount::umount_part($_) }; #- at least try to umount it
		will_tell_kernel($hd, del => $_, 'delay_del');
		push @{$hd->{partitionsRenumbered}}, [ $_->{device}, $dev ];
	    }
	    $_->{part_number} = $i;
	    compute_device_name($_, $hd);
	    if ($renumbered) {
		will_tell_kernel($hd, add => $_, 'delay_add');
	    }
	    $i++;
	}
    }

    #- try to figure what the windobe drive letter could be!
    #
    #- first verify there's at least one primary dos partition, otherwise it
    #- means it is a secondary disk and all will be false :(
    #-
    my ($c, @others) = grep { isFat_or_NTFS($_) } @{$hd->{primary}{normal}};

    $i = ord 'C';
    $c->{device_windobe} = chr($i++) if $c;
    $_->{device_windobe} = chr($i++) foreach grep { isFat_or_NTFS($_) } map { $_->{normal} } @{$hd->{extended}};
    $_->{device_windobe} = chr($i++) foreach @others;
}

sub remove_empty_extended {
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

sub adjust_main_extended {
    my ($hd) = @_;

    if (!is_empty_array_ref $hd->{extended}) {
	my ($l, @l) = @{$hd->{extended}};

	# the first is a special case, must recompute its real size
	my $start = round_down($l->{normal}{start} - 1, $hd->{geom}{sectors});
	my $end = $l->{normal}{start} + $l->{normal}{size};
	my $only_linux = 1; my $has_win_lba = 0;
	foreach (map { $_->{normal} } $l, @l) {
	    $start = min($start, $_->{start});
	    $end = max($end, $_->{start} + $_->{size});
	    $only_linux &&= isTrueLocalFS($_) || isSwap($_);
	    $has_win_lba ||= $_->{pt_type} == 0xc || $_->{pt_type} == 0xe;
	}
	$l->{start} = $hd->{primary}{extended}{start} = $start;
	$l->{size} = $hd->{primary}{extended}{size} = $end - $start;
    }
    if (!@{$hd->{extended} || []} && $hd->{primary}{extended}) {
	will_tell_kernel($hd, del => $hd->{primary}{extended});
	%{$hd->{primary}{extended}} = (); #- modify the raw entry
	delete $hd->{primary}{extended};
    }
    verifyParts($hd); #- verify everything is all right
}

sub adjust_local_extended {
    my ($hd, $part) = @_;

    my $extended = find { $_->{normal} == $part } @{$hd->{extended} || []} or return;
    $extended->{size} = $part->{size} + $part->{start} - $extended->{start};

    #- must write it there too because values are not shared
    my $prev = find { $_->{extended}{start} == $extended->{start} } @{$hd->{extended} || []} or return;
    $prev->{extended}{size} = $part->{size} + $part->{start} - $prev->{extended}{start};
}

sub get_normal_parts {
    my ($hd) = @_;

    @{$hd->{primary}{normal} || []}, map { $_->{normal} } @{$hd->{extended} || []};
}

sub get_normal_parts_and_holes {
    my ($hd) = @_;
    my ($start, $last) = ($hd->first_usable_sector, $hd->last_usable_sector);

    ref($hd) or print("get_normal_parts_and_holes: bad hd" . backtrace(), "\n");

    my $minimal_hole = put_in_hash({ pt_type => 0 }, hd2minimal_part($hd));

    my @l = map {
	my $current = $start;
	$start = $_->{start} + $_->{size};
	my $hole = { start => $current, size => $_->{start} - $current, %$minimal_hole };
	put_in_hash($hole, hd2minimal_part($hd));
	$hole, $_;
    } sort { $a->{start} <=> $b->{start} } grep { !isWholedisk($_) } get_normal_parts($hd);

    push @l, { start => $start, size => $last - $start, %$minimal_hole };
    grep { !isEmpty($_) || $_->{size} >= $hd->cylinder_size } @l;
}

sub read_primary {
    my ($hd) = @_;

    #- it can be safely considered that the first sector is used to probe the partition table
    #- but other sectors (typically for extended partition ones) have to match this type!
	my @parttype = (
	  if_(arch() =~ /^ia64/, 'gpt'),
	  arch() =~ /^sparc/ ? ('sun', 'bsd') : ('dos', 'bsd', 'sun', 'mac'),
	);
	foreach ('empty', @parttype, 'unknown') {
	    /unknown/ and die "unknown partition table format on disk " . $hd->{file};

		# perl_checker: require partition_table::bsd
		# perl_checker: require partition_table::dos
		# perl_checker: require partition_table::empty
		# perl_checker: require partition_table::gpt
		# perl_checker: require partition_table::mac
		# perl_checker: require partition_table::sun
		require "partition_table/$_.pm";
		bless $hd, "partition_table::$_";
	        if ($hd->read_primary) {
		    log::l("found a $_ partition table on $hd->{file} at sector 0");
		    return 1;
		}
	}
    0;
}

sub read {
    my ($hd) = @_;
    read_primary($hd) or return 0;
    eval {
	my $need_removing_empty_extended;
	if ($hd->{primary}{extended}) {
	    read_extended($hd, $hd->{primary}{extended}, \$need_removing_empty_extended) or return 0;
	}
	if ($need_removing_empty_extended) {
	    #- special case when hda5 is empty, it must be skipped
	    #- (windows XP generates such partition tables)
	    remove_empty_extended($hd); #- includes adjust_main_extended
	}
	
    }; 
    die "extended partition: $@" if $@;

    assign_device_numbers($hd);
    remove_empty_extended($hd);

    $hd->set_best_geometry_for_the_partition_table;
    1;
}

sub read_extended {
    my ($hd, $extended, $need_removing_empty_extended) = @_;

    my $pt = do {
	my ($pt, $info) = $hd->read_one($extended->{start}) or return 0;
	partition_table::raw::pt_info_to_primary($hd, $pt, $info);
    };
    $pt = { %$extended, %$pt };

    push @{$hd->{extended}}, $pt;
    @{$hd->{extended}} > 100 and die "oops, seems like we're looping here :(  (or you have more than 100 extended partitions!)";

    if (@{$pt->{normal}} == 0) {
	$$need_removing_empty_extended = 1;
	delete $pt->{normal};
	print "need_removing_empty_extended\n";
    } elsif (@{$pt->{normal}} > 1) {
	die "more than one normal partition in extended partition";
    } else {
	$pt->{normal} = $pt->{normal}[0];
	#- in case of extended partitions, the start sector is local to the partition or to the first extended_part!
	$pt->{normal}{start} += $pt->{start};

	#- the following verification can broke an existing partition table that is
	#- correctly read by fdisk or cfdisk. maybe the extended partition can be
	#- recomputed to get correct size.
	if (!verifyInside($pt->{normal}, $extended)) {
	    $extended->{size} = $pt->{normal}{start} + $pt->{normal}{size};
	    verifyInside($pt->{normal}, $extended) or die "partition $pt->{normal}{device} is not inside its extended partition";
	}
    }

    if ($pt->{extended}) {
	$pt->{extended}{start} += $hd->{primary}{extended}{start};
	return read_extended($hd, $pt->{extended}, $need_removing_empty_extended);
    } else {
	1;
    }
}

sub will_tell_kernel {
    my ($hd, $action, $o_part, $o_delay) = @_;

    if ($action eq 'resize') {
	will_tell_kernel($hd, del => $o_part);
	will_tell_kernel($hd, add => $o_part);
    } else {
	my $part_number;
	if ($o_part) {
	    ($part_number) = $o_part->{device} =~ /(\d+)$/ or
	      #- do not die, it occurs when we zero_MBR_and_dirty a raw_lvm_PV
	      log::l("ERROR: will_tell_kernel bad device " . description($o_part)), return;
	}

	my @para =
	  $action eq 'force_reboot' ? () :
	  $action eq 'add' ? ($part_number, $o_part->{start}, $o_part->{size}) :
	  $action eq 'del' ? $part_number :
	  internal_error("unknown action $action");

	push @{$hd->{'will_tell_kernel' . ($o_delay || '')} ||= []}, [ $action, @para ];
    }
    if (!$o_delay) {
	foreach my $delay ('delay_del', 'delay_add') {
	    my $l = delete $hd->{"will_tell_kernel$delay"} or next;
	    push @{$hd->{will_tell_kernel} ||= []}, @$l;
	}
    }
    $hd->{isDirty} = 1;
}

sub tell_kernel {
    my ($hd, $tell_kernel) = @_;

    my $F = partition_table::raw::openit($hd);

    my $force_reboot = any { $_->[0] eq 'force_reboot' } @$tell_kernel;
    if (!$force_reboot) {
	foreach (@$tell_kernel) {
	    my ($action, $part_number, $o_start, $o_size) = @$_;
	    
	    if ($action eq 'add') {
		$force_reboot ||= !c::add_partition(fileno $F, $part_number, $o_start, $o_size);
	    } elsif ($action eq 'del') {
		$force_reboot ||= !c::del_partition(fileno $F, $part_number);
	    }
	    log::l("tell kernel $action ($hd->{device} $part_number $o_start $o_size) force_reboot=$force_reboot rebootNeeded=$hd->{rebootNeeded}");
	}
    }
    if ($force_reboot) {
	my @magic_parts = grep { $_->{isMounted} && $_->{real_mntpoint} } get_normal_parts($hd);
	foreach (@magic_parts) {
	    syscall_('umount', $_->{real_mntpoint}) or log::l(N("error unmounting %s: %s", $_->{real_mntpoint}, $!));
	}
	$hd->{rebootNeeded} = !ioctl($F, c::BLKRRPART(), 0);
	log::l("tell kernel force_reboot ($hd->{device}), rebootNeeded=$hd->{rebootNeeded}");

	foreach (@magic_parts) {
	    syscall_('mount', $_->{real_mntpoint}, $_->{fs_type}, c::MS_MGC_VAL()) or log::l(N("mount failed: ") . $!);
	}
    }
}

# write the partition table
sub write {
    my ($hd) = @_;
    $hd->{isDirty} or return;
    $hd->{readonly} and internal_error("a read-only partition table should not be dirty ($hd->{device})!");

    #- set first primary partition active if no primary partitions are marked as active.
    if (my @l = @{$hd->{primary}{raw}}) {
	foreach (@l) { 
	    $_->{local_start} = $_->{start}; 
	    $_->{active} ||= 0;
	}
	$l[0]{active} = 0x80 if !any { $_->{active} } @l;
    }

    #- last chance for verification, this make sure if an error is detected,
    #- it will never be writed back on partition table.
    verifyParts($hd);

    $hd->write(0, $hd->{primary}{raw}, $hd->{primary}{info}) or die "writing of partition table failed";

    #- should be fixed but a extended exist with no real extended partition, that blanks mbr!
    if (arch() !~ /^sparc/) {
	foreach (@{$hd->{extended}}) {
	    # in case of extended partitions, the start sector must be local to the partition
	    $_->{normal}{local_start} = $_->{normal}{start} - $_->{start};
	    $_->{extended} and $_->{extended}{local_start} = $_->{extended}{start} - $hd->{primary}{extended}{start};

	    $hd->write($_->{start}, $_->{raw}) or die "writing of partition table failed";
	}
    }
    $hd->{isDirty} = 0;
    $hd->{hasBeenDirty} = 1; #- used in undo (to know if undo should believe isDirty or not)

    if (my $tell_kernel = delete $hd->{will_tell_kernel}) {
	if (fs::type::is_dmraid($hd)) {
	    fs::dmraid::call_dmraid('-an');
	    fs::dmraid::call_dmraid('-ay');
	} else {
	    tell_kernel($hd, $tell_kernel);
	}
    }
}

sub active {
    my ($hd, $part) = @_;

    $_->{active} = 0 foreach @{$hd->{primary}{normal}};
    $part->{active} = 0x80;
    $hd->{isDirty} = 1;
}


# remove a normal partition from hard drive hd
sub remove {
    my ($hd, $part) = @_;
    my $i;

    #- first search it in the primary partitions
    $i = 0; foreach (@{$hd->{primary}{normal}}) {
	if ($_ eq $part) {
	    will_tell_kernel($hd, del => $_);

	    splice(@{$hd->{primary}{normal}}, $i, 1);
	    %$_ = (); #- blank it

	    $hd->raw_removed($hd->{primary}{raw});
	    return 1;
	}
	$i++;
    }

    my ($first, $second, $third) = map { $_->{normal} } @{$hd->{extended} || []};
    if ($third && $first eq $part) {
	die "Can not handle removing hda5 when hda6 is not the second partition" if $second->{start} > $third->{start};
    }      

    #- otherwise search it in extended partitions
    foreach (@{$hd->{extended} || []}) {
	$_->{normal} eq $part or next;

	delete $_->{normal}; #- remove it
	remove_empty_extended($hd);
	assign_device_numbers($hd);

	will_tell_kernel($hd, del => $part);
	return 1;
    }
    0;
}

# create of partition at starting at `start', of size `size' and of type `pt_type' (nice comment, uh?)
sub add_primary {
    my ($hd, $part) = @_;

    {
	local $hd->{primary}{normal}; #- save it to fake an addition of $part, that way add_primary do not modify $hd if it fails
	push @{$hd->{primary}{normal}}, $part;
	adjust_main_extended($hd); #- verify
	$hd->raw_add($hd->{primary}{raw}, $part);
    }
    push @{$hd->{primary}{normal}}, $part; #- really do it
}

sub add_extended {
    arch() =~ /^sparc|ppc/ and die N("Extended partition not supported on this platform");

    my ($hd, $part, $extended_type) = @_;
    $extended_type =~ s/Extended_?//;

    my $e = $hd->{primary}{extended};

    if ($e && !verifyInside($part, $e)) {
	#-die "sorry, can not add outside the main extended partition" unless $::unsafe;
	my $end = $e->{start} + $e->{size};
	my $start = min($e->{start}, $part->{start});
	$end = max($end, $part->{start} + $part->{size}) - $start;

	{ #- faking a resizing of the main extended partition to test for problems
	    local $e->{start} = $start;
	    local $e->{size} = $end - $start;
	    eval { verifyPrimary($hd->{primary}) };
	    $@ and die
N("You have a hole in your partition table but I can not use it.
The only solution is to move your primary partitions to have the hole next to the extended partitions.");
	}
    }

    if ($e && $part->{start} < $e->{start}) {
	my $l = first(@{$hd->{extended}});

	#- the first is a special case, must recompute its real size
	$l->{start} = round_down($l->{normal}{start} - 1, $hd->cylinder_size);
	$l->{size} = $l->{normal}{start} + $l->{normal}{size} - $l->{start};
	my $ext = { %$l };
	unshift @{$hd->{extended}}, { pt_type => 5, raw => [ $part, $ext, {}, {} ], normal => $part, extended => $ext };
	#- size will be autocalculated :)
    } else {
	my ($ext, $ext_size) = is_empty_array_ref($hd->{extended}) ?
	  ($hd->{primary}, -1) : #- -1 size will be computed by adjust_main_extended
	  (top(@{$hd->{extended}}), $part->{size});
	my %ext = (pt_type => $extended_type || 5, start => $part->{start}, size => $ext_size);

	$hd->raw_add($ext->{raw}, \%ext);
	$ext->{extended} = \%ext;
	push @{$hd->{extended}}, { %ext, raw => [ $part, {}, {}, {} ], normal => $part };
    }
    $part->{start}++; $part->{size}--; #- let it start after the extended partition sector
    adjustStartAndEnd($hd, $part);

    adjust_main_extended($hd);
}

sub add {
    my ($hd, $part, $b_primaryOrExtended, $b_forceNoAdjust) = @_;

    get_normal_parts($hd) >= ($hd->{device} =~ /^rd/ ? 7 : $hd->{device} =~ /^(sd|ida|cciss|ataraid)/ ? 15 : 63) and cdie "maximum number of partitions handled by linux reached";

    set_isFormatted($part, 0);
    put_in_hash($part, hd2minimal_part($hd));
    $part->{start} ||= 1 if arch() !~ /^sparc/; #- starting at sector 0 is not allowed
    adjustStartAndEnd($hd, $part) unless $b_forceNoAdjust;

    my $nb_primaries = $hd->{device} =~ /^rd/ ? 3 : 1;

    if (arch() =~ /^sparc|ppc/ ||
	$b_primaryOrExtended eq 'Primary' ||
	$b_primaryOrExtended !~ /Extended/ && @{$hd->{primary}{normal} || []} < $nb_primaries) {
	eval { add_primary($hd, $part) };
	goto success if !$@;
    }
    if ($hd->hasExtended) {
	eval { add_extended($hd, $part, $b_primaryOrExtended) };
	goto success if !$@;
    }
    {
	add_primary($hd, $part);
    }
  success:
    assign_device_numbers($hd);
    will_tell_kernel($hd, add => $part);
}

# search for the next partition
sub next {
    my ($hd, $part) = @_;

    first(
	  sort { $a->{start} <=> $b->{start} }
	  grep { $_->{start} >= $part->{start} + $part->{size} }
	  get_normal_parts($hd)
	 );
}
sub next_start {
    my ($hd, $part) = @_;
    my $next = &next($hd, $part);
    $next ? $next->{start} : $hd->last_usable_sector;
}

sub load {
    my ($hd, $file, $b_force) = @_;

    my $F = ref $file ? $file : common::open_file($file) || die N("Error reading file %s", $file);

    my $h;
    {
	local $/ = "\0";
	eval <$F>;
    }
    $@ and die N("Restoring from file %s failed: %s", $file, $@);

    ref($h) eq 'ARRAY' or die N("Bad backup file");

    my %h; @h{@fields2save} = @$h;

    $h{totalsectors} == $hd->{totalsectors} or $b_force or cdie "bad totalsectors";

    #- unsure we do not modify totalsectors
    local $hd->{totalsectors};

    @$hd{@fields2save} = @$h;

    delete @$_{qw(isMounted isFormatted notFormatted toFormat toFormatUnsure)} foreach get_normal_parts($hd);
    will_tell_kernel($hd, 'force_reboot'); #- just like undo, do not force write_partitions so that user can see the new partition table but can still discard it
}

sub save {
    my ($hd, $file) = @_;
    my @h = @$hd{@fields2save};
    require Data::Dumper;
    eval { output($file, Data::Dumper->Dump([\@h], ['$h']), "\0") }
      or die N("Error writing to file %s", $file);
}

1;
