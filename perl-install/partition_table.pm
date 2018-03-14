package partition_table;

use diagnostics;
use strict;

use common;
use fs::type;
use partition_table::raw;
use detect_devices;
use log;

=head1 SYNOPSYS

B<partition_table> enables to read & write partitions on various partition schemes (DOS, GPT, BSD, ...)

It holds base partition table management methods, it manages
appriopriate partition_table_XXX object according to what has been read
as XXX partition table type.

=head1 Functions

=over

=cut


sub hd2minimal_part {
    my ($hd) = @_;
    { 
	rootDevice => $hd->{device}, 
	if_($hd->{usb_media_type}, is_removable => 1),
    };
}

=item description($hd)

Works for both hard disk drives and partitions ;p

=cut

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

=item align_to_MB_boundaries($part)

Align partition start to the next MB boundary

=cut

sub align_to_MB_boundaries {
    my ($part) = @_;

    my $end = $part->{start} + $part->{size};
    $part->{start} = round_up($part->{start}, MB(1));
    $part->{size} = $end - $part->{start};
}

sub adjustStartAndEnd {
    my ($hd, $part) = @_;

    # always align partition start to MB boundaries
    # (this accounts for devices with non-512 physical sector sizes):
    align_to_MB_boundaries($part);

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
	    next if !$i || !$_ || $i == $_ || isExtended($i); #- avoid testing twice for simplicity :-)
	    if (isExtended($_)) {
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
    $_->{start} > 0 || die "partition must NOT start at sector 0" foreach @{$pt->{normal}};
    verifyParts_(@{$pt->{normal}}, $pt->{extended});
}

sub compute_device_name {
    my ($part, $hd) = @_;
    $part->{device} = _compute_device_name($hd, $part->{part_number});
}

sub _compute_device_name {
    my ($hd, $nb) = @_;
    my $prefix = $hd->{prefix} || devices::prefix_for_dev($hd->{device});
    $prefix . $nb;
}

sub assign_device_numbers {
    my ($hd) = @_;

    my $i = 1;
    my $start = 1; 
    
    {
	foreach (@{$hd->{primary}{raw}}) {
	    $_->{part_number} = $i;
	    compute_device_name($_, $hd);
	    $i++;
	}
	foreach (map { $_->{normal} } @{$hd->{extended} || []}) {
	    my $dev = _compute_device_name($hd, $i);
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
    my ($c, @others) = grep { isnormal_Fat_or_NTFS($_) } @{$hd->{primary}{normal}};

    $i = ord 'C';
    $c->{device_windobe} = chr($i++) if $c;
    $_->{device_windobe} = chr($i++) foreach grep { isnormal_Fat_or_NTFS($_) } map { $_->{normal} } @{$hd->{extended}};
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
    } sort { $a->{start} <=> $b->{start} } get_normal_parts($hd);

    push @l, { start => $start, size => min($last - $start, $hd->max_partition_size), %$minimal_hole } if $start < $hd->max_partition_start;
    grep { !isEmpty($_) || $_->{size} >= $hd->cylinder_size } @l;
}


=item default_type($hd)

Returns the default type of $hd ('gpt' or 'dos' depending on whether we're running under UEFI or
whether the disk size is too big for a MBR partition table.

=cut

sub default_type {
    my ($hd) = @_;

    # default to GPT on UEFI systems and disks > 2TB
    is_uefi() || $hd->{totalsectors} > 2 * 1024 * 1024 * 2048 ? 'gpt' : "dos";
}

=item initialize($hd, $o_type)

Initialize a $hd object.

Expect $hd->{file} to point to the raw device disk.

The optional $o_type parameter enables to override the detected disk type (eg: 'dos', 'gpt', ...).

=cut

sub initialize {
    my ($hd, $o_type) = @_;

    my $current = c::get_disk_type($hd->{file});
    $current = 'dos' if $current eq 'msdos';
    my $type = $o_type || $current || default_type($hd);
    $hd->{pt_table_type} = $type;

    require "partition_table/$type.pm";
    "partition_table::$type"->initialize($hd);

    delete $hd->{extended};
    if (detect_devices::is_xbox()) {
        my $part = { start => 1, size => 15632048, pt_type => 0x0bf, isFormatted => 1 };
        partition_table::dos::compute_CHS($hd, $part);
	$hd->{primary}{raw}[0] = $part;
    }

    will_tell_kernel($hd, 'init');
}

sub read_primary {
    my ($hd) = @_;

    #- it can be safely considered that the first sector is used to probe the partition table
    #- but other sectors (typically for extended partition ones) have to match this type!
	my @parttype = (
          # gpt must be tried before dos as it presents a fake compatibility mbr
	  'gpt', 'lvm', 'dmcrypt', 'dos', 'bsd', 'sun', 'mac',
	);
	foreach ('empty', @parttype, 'unknown') {
	    /unknown/ and die "unknown partition table format on disk " . $hd->{file};

		# perl_checker: require partition_table::bsd
		# perl_checker: require partition_table::dos
		# perl_checker: require partition_table::empty
		# perl_checker: require partition_table::dmcrypt
		# perl_checker: require partition_table::lvm
		# perl_checker: require partition_table::gpt
		# perl_checker: require partition_table::mac
		# perl_checker: require partition_table::sun
		require "partition_table/$_.pm";
		bless $hd, "partition_table::$_";
	        if ($hd->read_primary) {
		    log::l("found a $_ partition table on $hd->{file} at sector 0");
		    $hd->{pt_table_type} = $_ if $_ ne 'empty';
		    return 1;
		}
	}
    0;
}


=item read($hd)

Read the partition table of $hd.

=cut

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
    } elsif ($action eq 'init') {
	# We will tell the kernel to reread the partition table, so no need to remember
	# previous changes.
	delete $hd->{will_tell_kernel};
	delete $hd->{will_tell_kerneldelay_add};
	delete $hd->{will_tell_kerneldelay_del};
	push @{$hd->{will_tell_kernel} ||= []}, [ $action, () ];
    } else {
	my $part_number;
	if ($o_part) {
	    ($part_number) = $o_part->{device} =~ /(\d+)$/ or
	      #- do not die, it occurs when we zero_MBR_and_dirty a raw_lvm_PV
	      log::l("ERROR: will_tell_kernel bad device " . description($o_part)), return;
	}

	my @para =
	  $action eq 'add' ? ($part_number, $o_part->{start}, $o_part->{size}) :
	  $action eq 'del' ? $part_number :
	  internal_error("unknown action $action");

	push @{$hd->{'will_tell_kernel' . ($o_delay || '')} ||= []}, [ $action, @para ];
    }
    $hd->{isDirty} = 1;
}

sub will_tell_kernel_delayed {
    my ($hd) = @_;
    foreach my $delay ('delay_del', 'delay_add') {
	my $l = delete $hd->{"will_tell_kernel$delay"} or next;
	push @{$hd->{will_tell_kernel} ||= []}, @$l;
    }
}

sub tell_kernel {
    my ($hd, $tell_kernel) = @_;

    my $F = partition_table::raw::openit($hd);

    my $force_reboot = $hd->{rebootNeeded} || any { $_->[0] eq 'init' } @$tell_kernel;
    if (!$force_reboot) {
	foreach (@$tell_kernel) {
	    my ($action, $part_number, $o_start, $o_size) = @$_;
	    
	    if ($action eq 'add') {
		$force_reboot ||= !c::add_partition(fileno($F), $part_number, $o_start, $o_size);
	    } elsif ($action eq 'del') {
		$force_reboot ||= !c::del_partition(fileno($F), $part_number);
	    }
	    log::l("tell kernel $action ($hd->{device} $part_number $o_start $o_size) force_reboot=$force_reboot rebootNeeded=$hd->{rebootNeeded}");
	}
    }

    if ($force_reboot) {
	# FIXME Handle LVM/dmcrypt/RAID
	my @magic_parts = grep { $_->{isMounted} && $_->{real_mntpoint} } get_normal_parts($hd);
	foreach (@magic_parts) {
	    syscall_('umount', $_->{real_mntpoint}) or log::l(N("error unmounting %s: %s", $_->{real_mntpoint}, $!));
	}
	$hd->{rebootNeeded} = !c::tell_kernel_to_reread_partition_table($hd->{file});
	log::l("tell kernel force_reboot ($hd->{device}), rebootNeeded=$hd->{rebootNeeded}");

	foreach (@magic_parts) {
	    syscall_('mount', $_->{real_mntpoint}, $_->{fs_type}, c::MS_MGC_VAL()) or log::l(N("mount failed: ") . $!);
	}
    }
}

=item write($hd)

Write the partition table

The partition_table_XXX object is expected to provide three functions to
support writing the partition table:

=over

=item * start_write()

start_write() is called once at the beginning to initiate the write operation,

=item * write()

write() is then called one or more times (depending on whether there are any
extended partitions),

=item * end_write().

and end_write() is called once to complete the write operation.

=back

For partition table types that support extended partitions (e.g.  DOS),
start_write() is expected to return a file handle to the raw device which is
then passed to write() and end_write(), allowing the entire table to be written
before closing the raw device. For partition table types that don't support
extended partitions, this is optional, and the entire write operation can be
performed in the single call to write().

=cut

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

    my $handle = $hd->start_write();
    $hd->write($handle, 0, $hd->{primary}{raw}, $hd->{primary}{info}) or die "writing of partition table failed";
    #- should be fixed but a extended exist with no real extended partition, that blanks mbr!
	foreach (@{$hd->{extended}}) {
	    # in case of extended partitions, the start sector must be local to the partition
	    $_->{normal}{local_start} = $_->{normal}{start} - $_->{start};
	    $_->{extended} and $_->{extended}{local_start} = $_->{extended}{start} - $hd->{primary}{extended}{start};

	    $hd->write($handle, $_->{start}, $_->{raw}) or die "writing of partition table failed";
	}
    $hd->end_write($handle);
    $hd->{isDirty} = 0;

    if (my $tell_kernel = delete $hd->{will_tell_kernel}) {
	if (fs::type::is_dmraid($hd)) {
	    fs::dmraid::call_dmraid('-an');
	    fs::dmraid::call_dmraid('-ay');
	} else {
	    tell_kernel($hd, $tell_kernel) if $hd->need_to_tell_kernel();
	}
    }
    # get major/minor again after writing the partition table so that we got them for dynamic devices
    # (eg: for SCSI like devices with kernel-2.6.28+):
    fs::get_major_minor([ get_normal_parts($hd) ]);
}

sub active {
    my ($hd, $part) = @_;

    $_->{active} = 0 foreach @{$hd->{primary}{normal}};
    $part->{active} = 0x80;
    $hd->{isDirty} = 1;
}

=item remove($hd, $part)

Remove a normal partition from hard disk drive $hd

=cut

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
	die "Cannot handle removing hda5 when hda6 is not the second partition" if $second->{start} > $third->{start};
    }      

    #- otherwise search it in extended partitions
    foreach (@{$hd->{extended} || []}) {
	$_->{normal} eq $part or next;

	delete $_->{normal}; #- remove it
	remove_empty_extended($hd);
	assign_device_numbers($hd);

	will_tell_kernel($hd, del => $part);
	#- schedule renumbering after deleting the partition
	will_tell_kernel_delayed($hd);
	return 1;
    }
    0;
}

=item add_primary($hd, $part)

Create of partition at starting at `start', of size `size' and of type `pt_type'

=cut

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
    my ($hd, $part, $extended_type) = @_;
    $extended_type =~ s/Extended_?//;

    my $e = $hd->{primary}{extended};

    if ($e && !verifyInside($part, $e)) {
	#-die "sorry, cannot add outside the main extended partition" unless $::unsafe;
	my $end = $e->{start} + $e->{size};
	my $start = min($e->{start}, $part->{start});
	$end = max($end, $part->{start} + $part->{size}) - $start;

	{ #- faking a resizing of the main extended partition to test for problems
	    local $e->{start} = $start;
	    local $e->{size} = $end - $start;
	    eval { verifyPrimary($hd->{primary}) };
	    $@ and die
N("You have a hole in your partition table but I cannot use it.
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

    get_normal_parts($hd) >= ($hd->{device} =~ /^rd/ ? 7 : $hd->{device} =~ /^(ida|cciss)/ ? 15 : 63) and cdie "maximum number of partitions handled by linux reached";

    set_isFormatted($part, 0);
    put_in_hash($part, hd2minimal_part($hd));
    $part->{start} ||= 1; #- starting at sector 0 is not allowed
    adjustStartAndEnd($hd, $part) unless $b_forceNoAdjust;

    my $nb_primaries = $hd->{device} =~ /^rd/ ? 3 : 1;

    if ($b_primaryOrExtended eq 'Primary' ||
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
    #- schedule renumbering before adding the partition
    will_tell_kernel_delayed($hd);
    will_tell_kernel($hd, add => $part);
}

=item next($hd, $part)

Search for the next partition

=cut

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

=back

=cut

1;
