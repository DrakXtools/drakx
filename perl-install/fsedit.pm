package fsedit; # $Id$

use diagnostics;
use strict;
use vars qw(%suggestions);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :constant :functional :file);
use partition_table qw(:types);
use partition_table_raw;
use detect_devices;
use fsedit;
use devices;
use loopback;
use log;
use fs;

%suggestions = (
  __("simple") => [
    { mntpoint => "/",     size => 300 << 11, type => 0x83, ratio => 5, maxsize =>3500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/home", size => 300 << 11, type => 0x83, ratio => 3 },
  ], 'with usr' => [
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 4, maxsize =>3000 << 11 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ], __("server") => [
    { mntpoint => "/",     size => 150 << 11, type => 0x83, ratio => 1, maxsize => 250 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 2, maxsize => 400 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type => 0x83, ratio => 3, maxsize =>3000 << 11 },
    { mntpoint => "/var",  size => 100 << 11, type => 0x83, ratio => 4 },
    { mntpoint => "/home", size => 100 << 11, type => 0x83, ratio => 5 },
  ],
);
my @suggestions_mntpoints = (
    "/root", "/var/ftp", "/var/www", "/boot",
    arch() =~ /sparc/ ? "/mnt/sunos" : "/mnt/windows",
);

my @partitions_signatures = (
    [ 0x83, 0x438, "\x53\xEF" ],
    [ 0x183, 0x10034, "ReIsErFs" ],
    [ 0x183, 0x10034, "ReIsEr2Fs" ],
    [ 0x283, 0, 'XFSB', 0x200, 'XAGF', 0x400, 'XAGI' ],
    [ 0x82, 4086, "SWAP-SPACE" ],
    [ 0x7,  0x1FE, "\x55\xAA", 0x3, "NTFS" ],
    [ 0xc,  0x1FE, "\x55\xAA", 0x52, "FAT32" ],
arch() !~ /^sparc/ ? (
    [ 0x6,  0x1FE, "\x55\xAA", 0x36, "FAT" ],
) : (),
);

sub typeOfPart { typeFromMagic(devices::make($_[0]), @partitions_signatures) }

#-######################################################################################
#- Functions
#-######################################################################################
sub hds {
    my ($drives, $flags) = @_;
    my (@hds, @lvms);
    my $rc;

    foreach (@$drives) {
	my $file = devices::make($_->{device});

	my $hd = partition_table_raw::get_geometry($file) or log::l("An error occurred while getting the geometry of block device $file: $!"), next;
	add2hash_($hd, $_);
	$hd->{file} = $file;
	$hd->{prefix} = $hd->{device};
	# for RAID arrays of format c0d0p1
	$hd->{prefix} .= "p" if $hd->{prefix} =~ m,(rd|ida|cciss)/,;

	eval { partition_table::read($hd, $flags->{clearall} || member($_->{device}, @{$flags->{clear} || []})) };
	if ($@) {
	    partition_table_raw::zero_MBR($hd);
	}
	member($_->{device}, @{$flags->{clear} || []}) and partition_table::remove($hd, $_)
	  foreach partition_table::get_normal_parts($hd);

	#- special case for type overloading (eg: reiserfs is 0x183)
	foreach (grep { isExt2($_) } partition_table::get_normal_parts($hd)) {
	    my $type = typeOfPart($_->{device});
	    $_->{type} = $type if $type > 0x100;
	}
	push @hds, $hd;
    }
    if (my @pvs = grep { isLVM($_) } map { partition_table::get_normal_parts($_) } @hds) {
	#- otherwise vgscan won't find them
	devices::make($_->{device}) foreach @pvs; 
	require lvm;
	foreach (@pvs) {
	    my $name = lvm::get_vg($_) or next;
	    my ($lvm) = grep { $_->{LVMname} eq $name } (@hds, @lvms);
	    if (!$lvm) {
		$lvm = bless { disks => [], LVMname => $name, level => 'linear' }, 'lvm';
		lvm::update_size($lvm);
		lvm::get_lvs($lvm);
		push @lvms, $lvm;
	    }
	    $_->{lvm} = $name;
	    push @{$lvm->{disks}}, $_;
	}
    }
    \@hds, \@lvms;
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
sub get_fstab {
    loopback::loopbacks(@_), map { partition_table::get_normal_parts($_) } @_
}

#- get normal partition that should be visible for working on.
sub get_visible_fstab {
    grep { $_ && !partition_table::isWholedisk($_) && !partition_table::isHiddenMacPart($_) } map { partition_table::get_normal_parts($_) } @_;
}

sub free_space {
    sum map { $_->{size} } map { partition_table::get_holes($_) } @_;
}

sub is_one_big_fat {
    my ($hds) = @_;
    @$hds == 1 or return;

    my @l = get_fstab(@$hds);
    @l == 1 && isFat($l[0]) && free_space(@$hds) < 10 << 11;
}


sub computeSize {
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
    my $size = int min($max, $best->{size} + $free_space * ($tot_ratios && $best->{ratio} / $tot_ratios));
    #- verify other entry can fill the hole
    if (grep { $_->{size} < $max - $size } @L) { $size } else { $max }
}

sub suggest_part {
    my ($part, $hds, $suggestions) = @_;
    $suggestions ||= $suggestions{server};

    my $has_swap = grep { isSwap($_) } get_fstab(@$hds);

    my ($best, $second) =
      grep { !$_->{maxsize} || $part->{size} <= $_->{maxsize} }
      grep { $_->{size} <= ($part->{maxsize} || $part->{size}) }
      grep { !has_mntpoint($_->{mntpoint}, $hds) || isSwap($_) && !$has_swap }
      grep { !$_->{hd} || $_->{hd} eq $part->{rootDevice} }
      grep { !$part->{type} || $part->{type} == $_->{type} || isTrueFS($part) && isTrueFS($_) }
	@$suggestions or return;

#-    if (arch() =~ /i.86/) {
#-	  $best = $second if
#-	    $best->{mntpoint} eq '/boot' &&
#-	    $part->{start} + $best->{size} > 1024 * $hd->cylinder_size(); #- if the empty slot is beyond the 1024th cylinder, no use having /boot
#-    }

    defined $best or return; #- sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    $part->{type} = $best->{type};
    $part->{size} = computeSize($part, $best, $hds, $suggestions);
    1;
}

sub suggestions_mntpoint {
    my ($hds) = @_;
    sort grep { !/swap/ && !has_mntpoint($_, $hds) }
      (@suggestions_mntpoints, map { $_->{mntpoint} } @{$suggestions{server}});
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


sub mntpoint2part {
    my ($mntpoint, $fstab) = @_;
    first(grep { $mntpoint eq $_->{mntpoint} } @$fstab);
}
sub has_mntpoint {
    my ($mntpoint, $hds) = @_;
    mntpoint2part($mntpoint, [ get_fstab(@$hds) ]);
}
sub get_root_ {
    my ($fstab, $boot) = @_;
    $boot && mntpoint2part("/boot", $fstab) || mntpoint2part("/", $fstab);
}
sub get_root { &get_root_ || {} }

#- do this before modifying $part->{mntpoint}
#- $part->{mntpoint} should not be used here, use $mntpoint instead
sub check_mntpoint {
    my ($mntpoint, $hd, $part, $hds, $loopbackDevice) = @_;

    ref $loopbackDevice or undef $loopbackDevice;

    $mntpoint eq '' || isSwap($part) || isNonMountable($part) and return;

    local $_ = $mntpoint;
    m|^/| or die _("Mount points must begin with a leading /");
#-    m|(.)/$| and die "The mount point $_ is illegal.\nMount points may not end with a /";

    has_mntpoint($mntpoint, $hds) and die _("There is already a partition with mount point %s\n", $mntpoint);

    my $fake_part = { mntpoint => $mntpoint, device => $loopbackDevice };
    $fake_part->{loopback_file} = 1 if $loopbackDevice;
    my $fstab = [ get_fstab(@$hds), $fake_part ];
    my $check; $check = sub {
	my ($p, @seen) = @_;
	push @seen, $p->{mntpoint} || return;
	@seen > 1 && $p->{mntpoint} eq $mntpoint and die _("Circular mounts %s\n", join(", ", @seen));
	if (my $part = fs::up_mount_point($p->{mntpoint}, $fstab)) {
	    #- '/' carrier is a special case, it will be mounted first
	    $check->($part, @seen) unless loopback::carryRootLoopback($p);
	}
	if (isLoopback($p)) {
	    $check->($p->{device}, @seen);
	}
    };
    $check->($fake_part) unless $mntpoint eq '/' && $loopbackDevice; #- '/' is a special case, no loop check

    die "raid / with no /boot" if $mntpoint eq "/" && isMDRAID($part) && !has_mntpoint("/boot", $hds);
    die _("You can't use a LVM Logical Volume for mount point %s", $mntpoint) if ($mntpoint eq '/' || $mntpoint eq '/boot') && isLVMBased($hd);
    die _("This directory should remain within the root filesystem") if member($mntpoint, qw(/bin /dev /etc /lib /sbin));
    die _("You need a true filesystem (ext2, reiserfs) for this mount point\n") if !isTrueFS($part) && member($mntpoint, qw(/ /home /tmp /usr /var));
#-    if ($part->{start} + $part->{size} > 1024 * $hd->cylinder_size() && arch() =~ /i.86/) {
#-	  die "/boot ending on cylinder > 1024" if $mntpoint eq "/boot";
#-	  die     "/ ending on cylinder > 1024" if $mntpoint eq "/" && !has_mntpoint("/boot", $hds);
#-    }
}

sub add($$$;$) {
    my ($hd, $part, $hds, $options) = @_;

    isSwap($part) ?
      ($part->{mntpoint} = 'swap') :
      $options->{force} || check_mntpoint($part->{mntpoint}, $hd, $part, $hds);

    delete $part->{maxsize};

    if (isLVMBased($hd)) {
	lvm::lv_create($hd, $part);
    } else {
	partition_table::add($hd, $part, $options->{primaryOrExtended});
    }
}

sub allocatePartitions($$) {
    my ($hds, $to_add) = @_;

    foreach my $hd (@$hds) {
	foreach (partition_table::get_holes($hd)) {
	    my ($start, $size) = @$_{"start", "size"};
	    my $part;
	    while (suggest_part($part = { start => $start, size => 0, maxsize => $size, rootDevice => $hd->{device} }, 
				$hds, $to_add)) {
		add($hd, $part, $hds);
		$size -= $part->{size} + $part->{start} - $start;
		$start = $part->{start} + $part->{size};
	    }
	}
    }
}

sub auto_allocate {
    my ($hds, $suggestions) = @_;    
    allocatePartitions($hds, $suggestions || $suggestions{simple});
    map { partition_table::assign_device_numbers($_) } @$hds;
}

sub undo_prepare($) {
    my ($hds) = @_;
    require Data::Dumper;
    $Data::Dumper::Purity = 1;
    foreach (@$hds) {
	my @h = @{$_}{@partition_table::fields2save};
	push @{$_->{undo}}, Data::Dumper->Dump([\@h], ['$h']);
    }
}
sub undo($) {
    my ($hds) = @_;
    foreach (@$hds) {
	my $h; eval pop @{$_->{undo}} || next;
	@{$_}{@partition_table::fields2save} = @$h;

	$_->{isDirty} = $_->{needKernelReread} = 1 if $_->{hasBeenDirty};
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
    $part->{mntpoint} = '' if isLVM({ type => $type }) || isRAID({ type => $type });
    $part->{type} = $type;
    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;    
}

sub rescuept($) {
    my ($hd) = @_;
    my ($ext, @hd);

    my $dev = devices::make($hd->{device});
    local *F; open F, "rescuept $dev|";
    local $_;
    while (<F>) {
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
    $ok &&= @parts == listlength(get_fstab(@$hds)) unless arch() eq "ppc";

    if ($readonly && !$ok) {
	log::l("using /proc/partitions as diskdrake failed :(");
	foreach my $hd (@$hds) {
	    partition_table_raw::zero_MBR($hd);
	    $hd->{primary} = { normal => [ grep { $hd->{device} eq $_->{rootDevice} } @parts ] };
	}
	$ok = 1;
    }
    $readonly && get_fstab(@$hds) == 0 and die _("You don't have any partitions!");
    $ok;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
