package fsedit; # $Id$

use diagnostics;
use strict;
use vars qw(%suggestions);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
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
foreach (values %suggestions) {
    if (arch() =~ /ia64/) {
	@$_ = ({ mntpoint => "/boot/efi", size => 50 << 11, type => 0xb, ratio => 1, maxsize => 150 << 11 }, @$_);
    }
}

my @suggestions_mntpoints = (
    "/var/ftp", "/var/www", "/boot",
    arch() =~ /sparc/ ? "/mnt/sunos" : arch() =~ /ppc/ ? "/mnt/macos" : "/mnt/windows",
);

my @partitions_signatures = (
    [ 0x8e, 0, "HM\1\0" ],
    [ 0x83, 0x438, "\x53\xEF" ],
    [ 0x183, 0x10034, "ReIsErFs" ],
    [ 0x183, 0x10034, "ReIsEr2Fs" ],
    [ 0x283, 0, 'XFSB', 0x200, 'XAGF', 0x400, 'XAGI' ],
    [ 0x383, 0x8000, 'JFS1' ],
    [ 0x82, 4086, "SWAP-SPACE" ],
    [ 0x82, 4086, "SWAPSPACE2" ],
    [ 0x7,  0x1FE, "\x55\xAA", 0x3, "NTFS" ],
    [ 0xc,  0x1FE, "\x55\xAA", 0x52, "FAT32" ],
arch() !~ /^sparc/ ? (
    [ 0x6,  0x1FE, "\x55\xAA", 0x36, "FAT" ],
) : (),
);

sub typeOfPart { 
    my $dev = devices::make($_[0]);
    my $t = typeFromMagic($dev, @partitions_signatures);
    if ($t == 0x83) {
	#- there is no magic to differentiate ext3 and ext2. Using libext2fs
	#- to check if it has a journal
	$t = 0x483 if c::is_ext3($dev);
    }
    $t;
}

#-######################################################################################
#- Functions
#-######################################################################################
sub empty_all_hds {
    { hds => [], lvms => [], raids => [], loopbacks => [], raw_hds => [], nfss => [], smbs => [], special => [] };
}
sub recompute_loopbacks {
    my ($all_hds) = @_;
    my @fstab = get_all_fstab($all_hds);
    @{$all_hds->{loopbacks}} = map { isPartOfLoopback($_) ? @{$_->{loopback}} : () } @fstab;
}

sub raids {
    my ($hds) = @_;

    my @parts = get_fstab(@$hds);
    (grep { isRawRAID($_) } @parts) && detect_devices::raidAutoStart() or return [];

    fs::get_major_minor(@parts);
    my %devname2part = map { $_->{dev} => { %$_, device => $_->{dev} } } read_partitions();

    my @raids;
    my @mdstat = cat_("/proc/mdstat");
    for (my $i = 0; $i < @mdstat; $i++) {

	my ($nb, $level, $mdparts) = 
	  #- line format is:
	  #- md%d : {in}?active{ (read-only)}? {linear|raid1|raid4|raid5}{ DEVNAME[%d]{(F)}?}*
	  $mdstat[$i] =~ /^md(.).* ([^ \[\]]+) (\S+\[\d+\].*)/ or next;

	$level =~ s/raid//; #- { linear | raid0 | raid1 | raid5 } -> { linear | 0 | 1 | 5 }

	my $chunks = $mdstat[$i+1] =~ /(\S+) chunks/ ? $1 : "64k";

	my @raw_mdparts = map { /([^\[]+)/ } split ' ', $mdparts;
	my @mdparts = 
	  map { 
	      my $mdpart = $devname2part{$_} || { device => $_ };
	      if (my ($part) = grep { is_same_hd($mdpart, $_) } @parts) {
		  $part->{raid} = $nb;
		  delete $part->{mntpoint};
		  $part;
	      } else {
		  #- forget it when not found? that way it won't break much... beurk.
		  ();
	      }
	  } @raw_mdparts;

	my $type = typeOfPart("md$nb");
	log::l("RAID: found md$nb (raid $level) chunks $chunks ", if_($type, "type $type "), "with parts ", join(", ", @raw_mdparts));
	$raids[$nb] = { 'chunk-size' => $chunks, type => $type || 0x83, disks => \@mdparts,
			device => "md$nb", notFormatted => !$type, level => $level };
    }
    require raid;
    raid::update(@raids);
    \@raids;
}

sub hds {
    my ($drives, $flags) = @_;
    my (@hds);
    my $rc;

    foreach (@$drives) {
	my $file = devices::make($_->{device});

	my $hd = partition_table_raw::get_geometry($file) or log::l("An error occurred while getting the geometry of block device $file: $!"), next;
	add2hash_($hd, $_);
	$hd->{file} = $file;
	$hd->{prefix} = $hd->{device};
	# for RAID arrays of format c0d0p1
	$hd->{prefix} .= "p" if $hd->{prefix} =~ m,(rd|ida|cciss|ataraid)/,;

	eval { partition_table::read($hd, $flags->{clearall} || member($_->{device}, @{$flags->{clear} || []})) };
	if ($@) {
	    partition_table_raw::zero_MBR($hd);
	}
	member($_->{device}, @{$flags->{clear} || []}) and partition_table::remove($hd, $_)
	  foreach partition_table::get_normal_parts($hd);

	# special case for Various type
	$_->{type} = typeOfPart($_->{device}) || 0x100 foreach grep { $_->{type} == 0x100 } partition_table::get_normal_parts($hd);

	#- special case for type overloading (eg: reiserfs is 0x183)
	foreach (grep { isExt2($_) } partition_table::get_normal_parts($hd)) {
	    my $type = typeOfPart($_->{device});
	    $_->{type} = $type if $type > 0x100 || $type && $hd->isa('partition_table_gpt');
	}
	push @hds, $hd;
    }
    #- detect raids before LVM allowing LVM on raid
    my $raids = raids(\@hds);
    my $all_hds = { %{ empty_all_hds() }, hds => \@hds, lvms => [], raids => $raids };

    my @lvms;
    if (my @pvs = grep { isRawLVM($_) } get_all_fstab($all_hds)) {
	#- otherwise vgscan won't find them
	devices::make($_->{device}) foreach @pvs; 
	require lvm;
	foreach (@pvs) {
	    my $name = lvm::get_vg($_) or next;
	    my ($lvm) = grep { $_->{LVMname} eq $name } @lvms;
	    if (!$lvm) {
		$lvm = bless { disks => [], LVMname => $name }, 'lvm';
		lvm::update_size($lvm);
		lvm::get_lvs($lvm);
		push @lvms, $lvm;
	    }
	    $_->{lvm} = $name;
	    push @{$lvm->{disks}}, $_;
	}
    }
    $all_hds->{lvms} = \@lvms;

    fs::get_major_minor(get_all_fstab($all_hds));

    $all_hds;
}


sub read_partitions() {
    my (undef, undef, @all) = cat_("/proc/partitions");
    grep {
	$_->{size} != 1 &&	 # skip main extended partition
	$_->{size} != 0x3fffffff # skip cdroms (otherwise stops cd-audios)
    } map { 
	my %l; 
	@l{qw(major minor size dev)} = split; 
	\%l;
    } @all;
}

sub readProcPartitions {
    my ($hds) = @_;

    my @all = read_partitions();
    my @parts = grep { $_->{dev} =~ /\d$/ } @all;
    my @disks = grep { $_->{dev} !~ /\d$/ } @all;

    my $devfs_like = grep { $_->{dev} =~ m|/disc$| } @disks;

    my %devfs2normal = map {
	my (undef, $major, $minor) = devices::entry($_->{device});
	my ($disk) = grep { $_->{major} == $major && $_->{minor} == $minor } @disks;
	$disk->{dev} => $_->{device};
    } @$hds;

    foreach my $part (@parts) {
	my $dev;
	if ($devfs_like) {
	    $dev = -e "/dev/$part->{dev}" ? $part->{dev} : sprintf("0x%x%02x", $part->{major}, $part->{minor});
	    $part->{rootDevice} = $devfs2normal{dirname($part->{dev}) . '/disc'};
	} else {
	    $dev = $part->{dev};
	    foreach my $hd (@$hds) {
		$part->{rootDevice} = $hd->{device} if $part->{dev} =~ /^$hd->{device}./;
	    }
	}
	$part->{device} = $dev;
	$part->{start} = 0;	# unknown, but we don't care
	$part->{size} *= 2;	# from KB to sectors
	$part->{type} = typeOfPart($dev); 

	delete $part->{dev}; # cleanup
    }
    @parts;
}

sub all_hds {
    my ($all_hds) = @_;
    (@{$all_hds->{hds}}, @{$all_hds->{lvms}});
}
sub part2hd {
    my ($part, $all_hds) = @_;
    my ($hd) = grep { $part->{rootDevice} eq $_->{device} } all_hds($all_hds);
    $hd;
}

sub is_same_hd {
    my ($hd1, $hd2) = @_;
    if ($hd1->{major} && $hd2->{major}) {
	$hd1->{major} == $hd2->{major} && $hd1->{minor} == $hd2->{minor};
    } else {
	$hd1->{device} eq $hd2->{device};
    }
}

sub is_same_part {
    my ($part1, $part2) = @_;
    foreach ('start', 'size', 'type', 'rootDevice') {
	$part1->{$_} eq $part2->{$_} or return;
    }
    1;
}

#- get all normal partition including special ones as found on sparc.
sub get_fstab {
    map { partition_table::get_normal_parts($_) } @_;
}

#- get normal partition that should be visible for working on.
sub get_visible_fstab {
    grep { $_ && !partition_table::isWholedisk($_) && !partition_table::isHiddenMacPart($_) }
      map { partition_table::get_normal_parts($_) } @_;
}

sub get_fstab_and_holes {
    map {
	if (isLVM($_)) {
	    my @parts = partition_table::get_normal_parts($_);
	    my $free = $_->{totalsectors} - sum map { $_->{size} } @parts;
	    my $free_part = { start => 0, size => $free, type => 0, rootDevice => $_->{device} };
	    @parts, if_($free >= $_->cylinder_size, $free_part);
	} else {
	    partition_table::get_normal_parts_and_holes($_);
	}
    } @_;
}
sub get_holes {
    grep { $_->{type} == 0 } get_fstab_and_holes(@_);
}

sub get_all_fstab {
    my ($all_hds) = @_;
    my @parts = map { partition_table::get_normal_parts($_) } all_hds($all_hds);
    my @raids = grep {$_} @{$all_hds->{raids}};
    @parts, @raids, @{$all_hds->{loopbacks}};
}
sub get_really_all_fstab {
    my ($all_hds) = @_;
    my @parts = map { partition_table::get_normal_parts($_) } all_hds($all_hds);
    my @raids = grep {$_} @{$all_hds->{raids}};
    @parts, @raids, @{$all_hds->{loopbacks}}, @{$all_hds->{raw_hds}}, @{$all_hds->{nfss}}, @{$all_hds->{smbs}};
}
sub get_all_fstab_and_holes {
    my ($all_hds) = @_;
    my @raids = grep {$_} @{$all_hds->{raids}};
    get_fstab_and_holes(all_hds($all_hds)), @raids, @{$all_hds->{loopbacks}};
}
sub get_all_holes {
    my ($all_hds) = @_;
    grep { $_->{type} == 0 } get_all_fstab_and_holes($all_hds);
}

sub all_free_space {
    my ($all_hds) = @_;
    sum map { $_->{size} } get_all_holes($all_hds);
}
sub free_space {
    sum map { $_->{size} } get_holes(@_);
}

sub is_one_big_fat {
    my ($hds) = @_;
    @$hds == 1 or return;

    my @l = get_fstab(@$hds);
    @l == 1 && isFat($l[0]) && free_space(@$hds) < 10 << 11;
}

sub file2part {
    my ($prefix, $fstab, $file, $keep_simple_symlinks) = @_;    
    my $part;

    $file = $keep_simple_symlinks ? common::expand_symlinks_but_simple("$prefix$file") : expand_symlinks("$prefix$file");
    unless ($file =~ s/^$prefix//) {
	my ($part) = grep { loopback::carryRootLoopback($_) } @$fstab or die;
	log::l("found $part->{mntpoint}");
	$file =~ s|/initrd/loopfs|$part->{mntpoint}|;
    }
    foreach (@$fstab) {
	my $m = $_->{mntpoint};
	$part = $_ if 
	  $file =~ /^\Q$m/ && 
	    (!$part || length $part->{mntpoint} < length $m);
    }
    $part or die "file2part: not found $file";
    $file =~ s|$part->{mntpoint}/?|/|;
    ($part, $file);
}


sub computeSize {
    my ($part, $best, $all_hds, $suggestions) = @_;
    my $max = $part->{maxsize} || $part->{size};
    return min($max, $best->{size}) unless $best->{ratio};

    my $free_space = all_free_space($all_hds);
    my @l = my @L = grep { 
	if (!has_mntpoint($_->{mntpoint}, $all_hds) && $free_space >= $_->{size}) {
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
    my ($part, $all_hds, $suggestions) = @_;
    $suggestions ||= $suggestions{server};

    my $has_swap = grep { isSwap($_) } get_all_fstab($all_hds);

    my ($best, $second) =
      grep { !$_->{maxsize} || $part->{size} <= $_->{maxsize} }
      grep { $_->{size} <= ($part->{maxsize} || $part->{size}) }
      grep { !has_mntpoint($_->{mntpoint}, $all_hds) || isSwap($_) && !$has_swap }
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
    $part->{type} = $best->{type} if !(isTrueFS($best) && isTrueFS($part));
    $part->{size} = computeSize($part, $best, $all_hds, $suggestions);
    1;
}

sub suggestions_mntpoint {
    my ($all_hds) = @_;
    sort grep { !/swap/ && !has_mntpoint($_, $all_hds) }
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
    my ($mntpoint, $all_hds) = @_;
    mntpoint2part($mntpoint, [ get_really_all_fstab($all_hds) ]);
}
sub get_root_ {
    my ($fstab, $boot) = @_;
    $boot && mntpoint2part("/boot", $fstab) || mntpoint2part("/", $fstab);
}
sub get_root { &get_root_ || {} }

#- do this before modifying $part->{type}
sub check_type {
    my ($type, $hd, $part) = @_;
    isThisFs("jfs", { type => name2type($type) }) && $part->{size} < 16 << 11 and die _("You can't use JFS for partitions smaller than 16MB");    
    isThisFs("reiserfs", { type => name2type($type) }) && $part->{size} < 32 << 11 and die _("You can't use ReiserFS for partitions smaller than 32MB");
}

#- do this before modifying $part->{mntpoint}
#- $part->{mntpoint} should not be used here, use $mntpoint instead
sub check_mntpoint {
    my ($mntpoint, $hd, $part, $all_hds) = @_;

    $mntpoint eq '' || isSwap($part) || isNonMountable($part) and return;
    $mntpoint =~ m|^/| or die _("Mount points must begin with a leading /");
    has_mntpoint($mntpoint, $all_hds) and die _("There is already a partition with mount point %s\n", $mntpoint);

    die "raid / with no /boot" 
      if $mntpoint eq "/" && isRAID($part) && !has_mntpoint("/boot", $all_hds);
    die _("You can't use a LVM Logical Volume for mount point %s", $mntpoint)
      if ($mntpoint eq '/' || $mntpoint eq '/boot') && isLVM($hd);
    die _("This directory should remain within the root filesystem")
      if member($mntpoint, qw(/bin /dev /etc /lib /sbin));
    die _("You need a true filesystem (ext2, reiserfs) for this mount point\n")
      if !isTrueFS($part) && member($mntpoint, qw(/ /home /tmp /usr /var));

    local $part->{mntpoint} = $mntpoint;
    loopback::check_circular_mounts($hd, $part, $all_hds);
}

sub check {
    my ($hd, $part, $all_hds) = @_;
    check_mntpoint($part->{mntpoint}, $hd, $part, $all_hds);
    check_type($part->{type}, $hd, $part);
}

sub add {
    my ($hd, $part, $all_hds, $options) = @_;

    isSwap($part) ?
      ($part->{mntpoint} = 'swap') :
      $options->{force} || check_mntpoint($part->{mntpoint}, $hd, $part, $all_hds);

    delete $part->{maxsize};

    if (isLVM($hd)) {
	lvm::lv_create($hd, $part);
    } else {
	partition_table::add($hd, $part, $options->{primaryOrExtended});
    }
}

sub allocatePartitions {
    my ($all_hds, $to_add) = @_;

    foreach my $part (get_all_holes($all_hds)) {
	my ($start, $size, $dev) = @$part{"start", "size", "rootDevice"};
	my $part;
	while (suggest_part($part = { start => $start, size => 0, maxsize => $size, rootDevice => $dev }, 
			    $all_hds, $to_add)) {
	    my ($hd) = fsedit::part2hd($part, $all_hds);
	    add($hd, $part, $all_hds);
	    $size -= $part->{size} + $part->{start} - $start;
	    $start = $part->{start} + $part->{size};
	}
    }
}

sub auto_allocate {
    my ($all_hds, $suggestions) = @_;
    my $before = listlength(fsedit::get_all_fstab($all_hds));

    allocatePartitions($all_hds, $suggestions || $suggestions{simple});
    auto_allocate_raids($all_hds, $suggestions) if $suggestions;

    partition_table::assign_device_numbers($_) foreach @{$all_hds->{hds}};

    $before != listlength(fsedit::get_all_fstab($all_hds));
}

sub auto_allocate_raids {
    my ($all_hds, $suggestions) = @_;

    my @raids = grep { isRawRAID($_) } get_all_fstab($all_hds) or return;
    if (@raids) {
	require raid;
	my @mds = grep { $_->{hd} =~ /md/ } @$suggestions;
	foreach my $md (@mds) {
	    my @raids_ = grep { !$md->{parts} || $md->{parts} =~ /\Q$_->{mntpoint}/ } @raids;
	    @raids = difference2(\@raids, \@raids_);
	    my $nb = raid::new($all_hds->{raids}, @raids_);
	    my $part = $all_hds->{raids}[$nb];

	    my %h = %$md;
	    delete @h{'hd', 'parts'};
	    put_in_hash($part, \%h); # mntpoint, level, chunk-size, type
	    raid::updateSize($part);
	}
    }
}

sub undo_prepare {
    my ($all_hds) = @_;
    require Data::Dumper;
    $Data::Dumper::Purity = 1;
    foreach (@{$all_hds->{hds}}) {
	my @h = @{$_}{@partition_table::fields2save};
	push @{$_->{undo}}, Data::Dumper->Dump([\@h], ['$h']);
    }
}
sub undo {
    my ($all_hds) = @_;
    foreach (@{$all_hds->{hds}}) {
	my $h; eval pop @{$_->{undo}} || next;
	@{$_}{@partition_table::fields2save} = @$h;

	$_->{isDirty} = $_->{needKernelReread} = 1 if $_->{hasBeenDirty};
    }
    
}

sub move {
    my ($hd, $part, $hd2, $sector2) = @_;

    die 'TODO'; # doesn't work for the moment
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

sub change_type {
    my ($type, $hd, $part) = @_;
    $type != $part->{type} or return;
    check_type($type, $hd, $part);
    $hd->{isDirty} = 1;
    $part->{mntpoint} = '' if isSwap($part) && $part->{mntpoint} eq "swap";
    $part->{mntpoint} = '' if isRawLVM({ type => $type }) || isRawRAID({ type => $type });
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
    foreach my $hd (@$hds) {
	my @l1 = partition_table::get_normal_parts($hd);
	my @l2 = grep { $_->{rootDevice} eq $hd->{device} } @parts;
	if (int(@l1) != int(@l2) && arch() ne 'ppc') {
	    log::l(sprintf
		   "/proc/partitions doesn't agree with drakx %d != %d:\n%s\n", int(@l1), int(@l2),
		   "/proc/partitions: " . join(", ", map { "$_->{device} ($_->{rootDevice})" } @parts));
	    $ok = 0;
	}
    }

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
