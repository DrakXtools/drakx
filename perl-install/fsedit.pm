package fsedit;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :constant :functional :file);
use partition_table qw(:types);
use partition_table_raw;
use detect_devices;
use Data::Dumper;
use fsedit;
use devices;
use fs;
use log;

#-#####################################################################################
#- Globals
#-#####################################################################################
my @suggestions = (
  { mntpoint => "/boot",    minsize =>  10 << 11, size =>  16 << 11, type => 0x83 },
  { mntpoint => "/",        minsize =>  50 << 11, size => 100 << 11, type => 0x83 },
  { mntpoint => "swap",     minsize =>  30 << 11, size =>  60 << 11, type => 0x82 },
  { mntpoint => "/usr",     minsize => 200 << 11, size => 600 << 11, type => 0x83 },
  { mntpoint => "/home",    minsize =>  50 << 11, size => 200 << 11, type => 0x83 },
  { mntpoint => "/var",     minsize => 200 << 11, size => 250 << 11, type => 0x83 },
  { mntpoint => "/tmp",     minsize =>  50 << 11, size => 100 << 11, type => 0x83 },
  { mntpoint => "/mnt/iso", minsize => 700 << 11, size => 800 << 11, type => 0x83 },
);
my @suggestions_mntpoints = qw(/mnt/dos);


my @partitions_signatures = (
    [ 0x83, 0x438, "\xEF\x53" ],
    [ 0x82, 4086, "SWAP-SPACE" ],
);

sub typeOfPart($) { typeFromMagic(devices::make($_[0]), @partitions_signatures) }

#-######################################################################################
#- Functions
#-######################################################################################
sub suggestions_mntpoint($) {
    my ($hds) = @_;
    sort grep { !/swap/ && !has_mntpoint($_, $hds) }
      (@suggestions_mntpoints, map { $_->{mntpoint} } @suggestions);
}

sub hds($$) {
    my ($drives, $flags) = @_;
    my @hds;
    my $rc;

    foreach (@$drives) {
	my $file = devices::make($_->{device});

	my $hd = partition_table_raw::get_geometry($file) or die _("An error occurred while getting the geometry of block device %s: %s", $file, "$!");
	$hd = { (%$_, %$hd) };
	$hd->{file} = $file;
	$hd->{prefix} = $hd->{device};
	# for RAID arrays of format c0d0p1
	$hd->{prefix} .= "p" if $hd->{prefix} =~ m,(rd|ida)/,;

	eval { partition_table::read($hd, $flags->{clearall}) };
	if ($@) {
	    cdie($@) unless $flags->{eraseBadPartitions};
	    partition_table_raw::zero_MBR($hd);
	}
	push @hds, $hd;
    }
    [ @hds ];
}

sub readProcPartitions {
    my ($hds) = @_;
    my @parts;
    foreach (cat_("/proc/partitions")) {
	my (undef, undef, $size, $device) = split;
	next if $size eq "1"; #- extended partitions
	foreach (@$hds) {
	    push @parts, { start => 0, size => $size * 2, device => $device, 
			   type => typeOfPart($device), rootDevice => $_->{device} 
			 } if $device =~ /^$_->{device}./;
	}
    }
    @parts;
}

sub get_fstab(@) {
    map { partition_table::get_normal_parts($_) } @_;
}

sub get_root($) {
    my ($fstab) = @_;
    $_->{mntpoint} eq "/" and return $_ foreach @$fstab;
    undef;
}
sub get_root_ { get_root([ get_fstab(@{$_[0]}) ]) }

sub suggest_part($$$;$) {
    my ($hd, $part, $hds, $suggestions) = @_;
    $suggestions ||= \@suggestions;
    foreach (@$suggestions) { $_->{minsize} ||= $_->{size} }

    my $has_swap = grep { isSwap($_) } get_fstab(@$hds);

    my ($best, $second) =
      grep { $part->{size} >= $_->{minsize} }
      grep { ! has_mntpoint($_->{mntpoint}, $hds) || isSwap($_) && !$has_swap }
	@$suggestions or return;

    $best = $second if
      $best->{mntpoint} eq '/boot' &&
      $part->{start} + $best->{minsize} > 1024 * partition_table::cylinder_size($hd); #- if the empty slot is beyond the 1024th cylinder, no use having /boot

    defined $best or return; #- sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    $part->{type} = $best->{type};
    $part->{size} = min($part->{size}, $best->{size});
    1;
}


#-sub partitionDrives {
#-
#-    my $cmd = "/sbin/fdisk";
#-    -x $cmd or $cmd = "/usr/bin/fdisk";
#-
#-    my $drives = findDrivesPresent() or die "You don't have any hard drives available! You probably forgot to configure a SCSI controller.";
#-
#-    foreach (@$drives) {
#-	 my $text = "/dev/" . $_->{device};
#-	 $text .= " - SCSI ID " . $_->{id} if $_->{device} =~ /^sd/;
#-	 $text .= " - Model " . $_->{info};
#-	 $text .= " array" if $_->{device} =~ /^c.d/;
#-
#-	 #- truncate at 50 columns for now
#-	 $text = substr $text, 0, 50;
#-    }
#-    #-TODO TODO
#-}


sub has_mntpoint($$) {
    my ($mntpoint, $hds) = @_;
    scalar grep { $mntpoint eq $_->{mntpoint} } get_fstab(@$hds);
}

#- do this before modifying $part->{mntpoint}
#- $part->{mntpoint} should not be used here, use $mntpoint instead
sub check_mntpoint {
    my ($mntpoint, $hd, $part, $hds) = @_;

    $mntpoint eq '' || isSwap($part) and return;

    local $_ = $mntpoint;
    m|^/| or die _("Mount points must begin with a leading /");
#-    m|(.)/$| and die "The mount point $_ is illegal.\nMount points may not end with a /";

    has_mntpoint($mntpoint, $hds) and die _("There is already a partition with mount point %s", $mntpoint);

    if ($part->{start} + $part->{size} > 1024 * partition_table::cylinder_size($hd)) {
	die "/boot ending on cylinder > 1024" if $mntpoint eq "/boot";
	die     "/ ending on cylinder > 1024" if $mntpoint eq "/" && !has_mntpoint("/boot", $hds);
    }
}

sub add($$$;$) {
    my ($hd, $part, $hds, $options) = @_;

    isSwap($part) ?
      ($part->{mntpoint} = 'swap') :
      $options->{force} || check_mntpoint($part->{mntpoint}, $hd, $part, $hds);

    partition_table::add($hd, $part, $options->{primaryOrExtended});
}

sub removeFromList($$$) {
    my ($start, $end, $list) = @_;
    my $err = "error in removeFromList: removing an non-free block";

    for (my $i = 0; $i < @$list; $i += 2) {
	$start < $list->[$i] and die $err;
	$start > $list->[$i + 1] and next;

	if ($start == $list->[$i]) {
	    $end > $list->[$i + 1] and die $err;
	    if ($end == $list->[$i + 1]) {
		#- the free block is just the same size, removing it
		splice(@$list, 0, 2);
	    } else {
		#- the free block now start just after this block
		$list->[$i] = $end;
	    }
	} else {
	    $end <= $list->[$i + 1] or die $err;
	    if ($end < $list->[$i + 1]) {
		splice(@$list, $i + 2, 0, $end, $list->[$i + 1]);
	    }
	    $list->[$i + 1] = $start; #- shorten the free block
	}
	return;
    }
}


sub allocatePartitions($$) {
    my ($hds, $to_add) = @_;
    my %free_sectors = map { $_->{device} => [1, $_->{totalsectors} ] } @$hds; #- first sector is always occupied by the MBR
    my $remove = sub { removeFromList($_[0]{start}, $_[0]->{start} + $_[0]->{size}, $free_sectors{$_[0]->{rootDevice}}) };
    my $success = 0;

    foreach (get_fstab(@$hds)) { &$remove($_); }

    FSTAB: foreach (@$to_add) {
	my %e = %$_;
	foreach my $hd (@$hds) {
	    my $v = $free_sectors{$hd->{device}};
	    for (my $i = 0; $i < @$v; $i += 2) {
		my $size = $v->[$i + 1] - $v->[$i];
		$e{size} > $size and next;

		if ($v->[$i] + $e{size} > 1024 * partition_table::cylinder_size($hd)) {
		    next if $e{mntpoint} eq "/boot" || 
		            $e{mntpoint} eq "/" && !has_mntpoint("/boot", $hds);
		}
		$e{start} = $v->[$i];
		$e{rootDevice} = $hd->{device};
		partition_table::adjustStartAndEnd($hd, \%e);
		&$remove(\%e);
		partition_table::add($hd, \%e);
		$success++;
		next FSTAB;
	    }
	}
	log::ld("can't allocate partition $e{mntpoint} of size $e{size}, not enough room");
    }
    $success;
}

sub auto_allocate($;$) {
    my ($hds, $suggestions) = @_;
    allocatePartitions($hds, [
			      grep { ! has_mntpoint($_->{mntpoint}, $hds) }
			      @{ $suggestions || \@suggestions }
			     ]);
    map { partition_table::assign_device_numbers($_) } @$hds;
}

sub undo_prepare($) {
    my ($hds) = @_;
    $Data::Dumper::Purity = 1;
    foreach (@$hds) {
	my @h = @{$_}{@partition_table::fields2save};
	push @{$_->{undo}}, Data::Dumper->Dump([\@h], ['$h']);
    }
}
sub undo_forget($) {
    my ($hds) = @_;
    pop @{$_->{undo}} foreach @$hds;
}

sub undo($) {
    my ($hds) = @_;
    foreach (@$hds) {
	my $h; eval pop @{$_->{undo}} || next;
	@{$_}{@partition_table::fields2save} = @$h;

	$_->{isDirty} = $_->{needKernelReread} = 1;
    }
}

sub move {
    my ($hd, $part, $hd2, $sector2) = @_;

    my $part2 = { %$part };
    $part2->{start} = $sector2;
    $part2->{size} += partition_table::cylinder_size($hd2) - 1;
    partition_table::remove($hd, $part);
    {
	local ($part2->{notFormatted}, $part2->{isFormatted}); #- do not allow partition::add to change this
	partition_table::add($hd2, $part2);
    }

    return if $part2->{notFormatted} && !$part2->{isFormatted} || $::testing;

    local (*F, *G);
    sysopen F, $hd->{file}, 0 or die '';
    sysopen G, $hd2->{file}, 2 or die _("Error opening %s for writing: %s", $hd2->{file}, "$!");

    my $base = $part->{start};
    my $base2 = $part2->{start};
    my $step = 1 << 10;
    if ($hd eq $hd2) {
	$part->{start} == $part2->{start} and return;
	$step = min($step, abs($part->{start} - $part2->{start}));

	if ($part->{start} < $part2->{start}) {
	    $base  += $part->{size} - $step;
	    $base2 += $part->{size} - $step;
	    $step = -$step;
	}
    }

    my $f = sub {
	c::lseek_sector(fileno(F), $base,  0) or die "seeking to sector $base failed on drive $hd->{device}";
	c::lseek_sector(fileno(G), $base2, 0) or die "seeking to sector $base2 failed on drive $hd2->{device}";

	my $buf;
	sysread F, $buf, $SECTORSIZE * abs($_[0]) or die '';
	syswrite G, $buf;
    };

    for (my $i = 0; $i < $part->{size} / abs($step); $i++, $base += $step, $base2 += $step) {
	&$f($step);
    }
    if (my $v = $part->{size} % abs($step) * sign($step)) {
	$base += $v;
	$base2 += $v;
	&$f($v);
    }
}

sub rescuept($) {
    my ($hd) = @_;
    my ($ext, @hd);

    my $dev = devices::make($hd->{device});
    open F, "rescuept $dev|";
    foreach (<F>) {
	my ($st, $si, $id) = /start=\s*(\d+),\s*size=\s*(\d+),\s*Id=\s*(\d+)/ or next;
	my $part = { start => $st, size => $si, type => hex($id) };
	if (isExtended($part)) {
	    $ext = $part;
	} else {
	    push @hd, $part;
	}
    }
    close F or die "rescuept failed";

    partition_table_raw::zero_MBR($hd);
    foreach (@hd) {
	my $b = partition_table::verifyInside($_, $ext);
	if ($b) {
	    $_->{start}--;
	    $_->{size}++;
	}
	local $b->{notFormatted};

	partition_table::add($hd, $_, ($b ? 'Extended' : 'Primary'), 1);
    }
}

sub verifyHds {
    my ($hds, $readonly, $ok) = @_;

    if (is_empty_array_ref($hds)) { #- no way
	die _("An error has occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    my @parts = readProcPartitions($hds);
    $ok &&= @parts == listlength(get_fstab(@$hds));

    if ($readonly && !$ok) {
	log::l("using /proc/partitions as diskdrake failed :(");
	foreach my $hd (@$hds) {
	    $hd->{primary} = { normal => [ grep { $hd->{device} eq $_->{rootDevice} } @parts ] };
	    delete $hd->{extended};
	}
    }
    my $fstab = [ get_fstab(@$hds) ];
    if (is_empty_array_ref($fstab) && $readonly) {
	die _("You don't have any partitions!");
    }
    ($hds, $fstab, $ok);
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
