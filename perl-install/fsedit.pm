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
arch() =~ /^i386/ ? (
  { mntpoint => "/boot",    size =>  16 << 11, type => 0x83, maxsize =>  30 << 11 },
) : (),
  { mntpoint => "/",        size =>  50 << 11, type => 0x83, ratio => 1, maxsize => 300 << 11 },
  { mntpoint => "swap",     size =>  30 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
  { mntpoint => "/usr",     size => 200 << 11, type => 0x83, ratio => 6, maxsize =>1500 << 11 },
  { mntpoint => "/home",    size =>  50 << 11, type => 0x83, ratio => 3 },
  { mntpoint => "/var",     size => 200 << 11, type => 0x83, ratio => 1, maxsize =>1000 << 11 },
  { mntpoint => "/tmp",     size =>  50 << 11, type => 0x83, ratio => 3, maxsize => 500 << 11 },
  { mntpoint => "/mnt/iso", size => 700 << 11, type => 0x83 },
);
my @suggestions_mntpoints = qw(/mnt/dos);


my @partitions_signatures = (
    [ 0x83, 0x438, "\x53\xEF" ],
    [ 0x82, 4086, "SWAP-SPACE" ],
    [ 0xc,  0x1FE, "\x55\xAA", 0x52, "FAT32" ],
    [ 0x6,  0x1FE, "\x55\xAA", 0x36, "FAT" ],
);

sub typeOfPart($) { typeFromMagic(devices::make($_[0]), @partitions_signatures) }

#-######################################################################################
#- Functions
#-######################################################################################
sub hds($$) {
    my ($drives, $flags) = @_;
    my @hds;
    my $rc;

    foreach (@$drives) {
	my $file = devices::make($_->{device});

	my $hd = partition_table_raw::get_geometry($file) or log::l("An error occurred while getting the geometry of block device $file: $!"), next;
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

#- get all normal partition including special ones as found on sparc.
sub get_fstab(@) {
    map { partition_table::get_normal_parts($_) } @_;
}

#- get normal partition that should be visible for working on.
sub get_visible_fstab(@) {
    grep { $_ && !partition_table::isWholedisk($_) } get_fstab(@_);
}

sub free_space(@) {
    sum map { $_->{size} } map { partition_table::get_holes($_) } @_;
}

sub hasRAID {
    my $b = 0;
    map { $b ||= isRAID($_) } get_fstab(@_);
    $b;
}

sub get_root($;$) {
    my ($fstab, $boot) = @_;
    if ($boot) { $_->{mntpoint} eq "/boot" and return $_ foreach @$fstab; }
    $_->{mntpoint} eq "/" and return $_ foreach @$fstab;
    undef;
}
sub get_root_ { get_root([ get_fstab(@{$_[0]}) ], $_[1]) }

sub is_one_big_fat {
    my ($hds) = @_;
    @$hds == 1 or return;

    my @l = get_fstab(@$hds);
    @l == 1 && isFat($l[0]) && free_space(@$hds) < 10 << 11;
}


sub computeSize($$$$) {
    my ($part, $best, $hds, $suggestions) = @_;
    my $max = $part->{maxsize} || $part->{size};
    return min($max, $best->{size}) unless $best->{ratio};

    my $free_space = free_space(@$hds);
    my @l = my @L = grep { 
	if (!has_mntpoint($_->{mntpoint}, $hds) && $free_space >= $_->{size}) {
	    $free_space -= $_->{size};
	    1;
	} else { 0 } } @$suggestions;

    my $tot_ratios = 0;
    while (1) {
	my $old_free_space = $free_space;
	my $old_tot_ratios = $tot_ratios;

	$tot_ratios = sum(map { $_->{ratio} } @l);
	last if $tot_ratios == $old_tot_ratios;

	@l = grep { 
	    if ($_->{ratio} && $_->{maxsize} && $tot_ratios &&
		$_->{size} + $_->{ratio} / $tot_ratios * $old_free_space >= $_->{maxsize}) {
		return min($max, $best->{maxsize}) if $best->{mntpoint} eq $_->{mntpoint};
		$free_space -= $_->{maxsize} - $_->{size};
		0;
	    } else {
		$_->{ratio};
	    } 
	} @l;
    }
    my $size = min($max, $best->{size} + $free_space * ($tot_ratios && $best->{ratio} / $tot_ratios));

    #- verify other entry can fill the hole
    if (grep { $_->{size} < $max - $size } @L) { $size } else { $max }
}

sub suggest_part($$$;$) {
    my ($hd, $part, $hds, $suggestions) = @_;
    $suggestions ||= \@suggestions;

    my $has_swap = grep { isSwap($_) } get_fstab(@$hds);

    my ($best, $second) =
      grep { !$_->{maxsize} || $part->{size} <= $_->{maxsize} }
      grep { $_->{size} <= ($part->{maxsize} || $part->{size}) }
      grep { !has_mntpoint($_->{mntpoint}, $hds) || isSwap($_) && !$has_swap }
      grep { !$part->{type} || $part->{type} == $_->{type} }
	@$suggestions or return;

    if (arch() =~ /^i386/) {
	$best = $second if
	  $best->{mntpoint} eq '/boot' &&
	  $part->{start} + $best->{size} > 1024 * $hd->cylinder_size(); #- if the empty slot is beyond the 1024th cylinder, no use having /boot
    }

    defined $best or return; #- sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    $part->{type} = $best->{type};
    $part->{size} = computeSize($part, $best, $hds, $suggestions);
    1;
}

sub suggestions_mntpoint($) {
    my ($hds) = @_;
    sort grep { !/swap/ && !has_mntpoint($_, $hds) }
      (@suggestions_mntpoints, map { $_->{mntpoint} } @suggestions);
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

    $mntpoint eq '' || isSwap($part) || isRAID($part) and return;

    local $_ = $mntpoint;
    m|^/| or die _("Mount points must begin with a leading /");
#-    m|(.)/$| and die "The mount point $_ is illegal.\nMount points may not end with a /";

    has_mntpoint($mntpoint, $hds) and die _("There is already a partition with mount point %s", $mntpoint);

    if ($part->{start} + $part->{size} > 1024 * $hd->cylinder_size() && arch() =~ /i386/) {
	die "/boot ending on cylinder > 1024" if $mntpoint eq "/boot";
#	die     "/ ending on cylinder > 1024" if $mntpoint eq "/" && !has_mntpoint("/boot", $hds);
    }
}

sub add($$$;$) {
    my ($hd, $part, $hds, $options) = @_;

    isSwap($part) ?
      ($part->{mntpoint} = 'swap') :
      $options->{force} || check_mntpoint($part->{mntpoint}, $hd, $part, $hds);

    delete $part->{maxsize};
    partition_table::add($hd, $part, $options->{primaryOrExtended});
}

sub allocatePartitions($$) {
    my ($hds, $to_add) = @_;

    foreach my $hd (@$hds) {
	foreach (partition_table::get_holes($hd)) {
	    my ($start, $size) = @$_{"start", "size"};
	    my $part;
	    while (suggest_part($hd, 
				$part = { start => $start, size => 0, maxsize => $size }, 
				$hds, $to_add)) {
		add($hd, $part, $hds);
		$start = $part->{start} + $part->{size};
		$size -= $part->{size};
	    }
	    $start = $_->{start} + $_->{size};
	}
    }
}

sub auto_allocate($;$) {
    my ($hds, $suggestions) = @_;    
    allocatePartitions($hds, $suggestions || \@suggestions);
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

    my $part1 = { %$part };
    my $part2 = { %$part };
    $part2->{start} = $sector2;
    $part2->{size} += $hd2->cylinder_size() - 1;
    partition_table::remove($hd, $part);
    {
	local ($part2->{notFormatted}, $part2->{isFormatted}); #- do not allow partition::add to change this
	partition_table::add($hd2, $part2);
    }

    return if $part2->{notFormatted} && !$part2->{isFormatted} || $::testing;

    local (*F, *G);
    sysopen F, $hd->{file}, 0 or die '';
    sysopen G, $hd2->{file}, 2 or die _("Error opening %s for writing: %s", $hd2->{file}, "$!");

    my $base = $part1->{start};
    my $base2 = $part2->{start};
    my $step = 10;
    if ($hd eq $hd2) {
	$base == $base2 and return;
	$step = min($step, abs($base2 - $base));

	if ($base < $base2) {
	    $base  += $part1->{size} - $step;
	    $base2 += $part1->{size} - $step;
	    $step = -$step;
	}
    }

    my $f = sub {
	$base  < 0 and $base2 += -$base,  $base  = 0;
	$base2 < 0 and $base  += -$base2, $base2 = 0;
	c::lseek_sector(fileno(F), $base,  0) or die "seeking to sector $base failed on drive $hd->{device}";
	c::lseek_sector(fileno(G), $base2, 0) or die "seeking to sector $base2 failed on drive $hd2->{device}";

	my $buf;
	sysread F, $buf, $SECTORSIZE * abs($_[0]) or die '';
	syswrite G, $buf;
    };

    for (my $i = 0; $i < $part1->{size} / abs($step); $i++, $base += $step, $base2 += $step) {
	print "$base $base2\n";
	&$f($step);
    }
    if (my $v = ($part1->{size} % abs($step)) * sign($step)) {
	$base += $v;
	$base2 += $v;
	&$f($v);
    }
}

sub change_type($$$) {
    my ($hd, $part, $type) = @_;
    $type != $part->{type} or return;
    $hd->{isDirty} = 1;
    $part->{mntpoint} = '' if isSwap($part) && $part->{mntpoint} eq "swap";
    $part->{type} = $type;
    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;    
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
	local $_->{notFormatted};

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
	    partition_table_raw::zero_MBR($hd);
	    $hd->{primary} = { normal => [ grep { $hd->{device} eq $_->{rootDevice} } @parts ] };
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
