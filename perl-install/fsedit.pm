package fsedit; # $Id$

use diagnostics;
use strict;
use vars qw(%suggestions);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table qw(:types);
use partition_table::raw;
use detect_devices;
use fsedit;
use devices;
use loopback;
use log;
use fs;

%suggestions = (
  N_("simple") => [
    { mntpoint => "/",     size => 300 << 11, type =>0x483, ratio => 5, maxsize => 5500 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize =>  250 << 11 },
    { mntpoint => "/home", size => 300 << 11, type =>0x483, ratio => 3 },
  ], N_("with /usr") => [
    { mntpoint => "/",     size => 150 << 11, type =>0x483, ratio => 1, maxsize => 1000 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 1, maxsize =>  250 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type =>0x483, ratio => 4, maxsize => 4000 << 11 },
    { mntpoint => "/home", size => 100 << 11, type =>0x483, ratio => 3 },
  ], N_("server") => [
    { mntpoint => "/",     size => 150 << 11, type =>0x483, ratio => 1, maxsize =>  250 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, type => 0x82, ratio => 2, maxsize =>  400 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, type =>0x483, ratio => 4, maxsize => 4000 << 11 },
    { mntpoint => "/var",  size => 150 << 11, type =>0x483, ratio => 3 },
    { mntpoint => "/home", size => 150 << 11, type =>0x483, ratio => 3 },
    { mntpoint => "/tmp",  size => 150 << 11, type =>0x483, ratio => 2, maxsize =>  500 << 11 },
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
    #- RedHat also has /usr/local and /opt
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
if_(arch() !~ /^sparc/,
    [ 0x6,  0x1FE, "\x55\xAA", 0x36, "FAT" ],
),
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
    { hds => [], lvms => [], raids => [], loopbacks => [], raw_hds => [], nfss => [], smbs => [], davs => [], special => [] };
}
sub recompute_loopbacks {
    my ($all_hds) = @_;
    my @fstab = get_all_fstab($all_hds);
    @{$all_hds->{loopbacks}} = map { isPartOfLoopback($_) ? @{$_->{loopback}} : () } @fstab;
}

sub raids {
    my ($hds) = @_;

    my @parts = get_fstab(@$hds);
    {
	my @l = grep { isRawRAID($_) } @parts or return [];
	detect_devices::raidAutoStart(@l);
    }

    fs::get_major_minor(@parts);
    my %devname2part = map { $_->{dev} => { %$_, device => $_->{dev} } } read_proc_partitions_raw();

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
	      if (my $part = find { is_same_hd($mdpart, $_) } @parts) {
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

sub lvms {
    my ($all_hds) = @_;
    my @pvs = grep { isRawLVM($_) } get_all_fstab($all_hds) or return;

    #- otherwise vgscan won't find them
    devices::make($_->{device}) foreach @pvs; 
    require lvm;

    my @lvms;
    foreach (@pvs) {
	my $name = lvm::get_vg($_) or next;
	my $lvm = find { $_->{VG_name} eq $name } @lvms;
	if (!$lvm) {
	    $lvm = new lvm($name);
	    lvm::update_size($lvm);
	    lvm::get_lvs($lvm);
	    push @lvms, $lvm;
	}
	$_->{lvm} = $name;
	push @{$lvm->{disks}}, $_;
    }
    @lvms;
}

sub hds {
    my ($flags, $ask_before_blanking) = @_;
    $flags ||= {};
    $flags->{readonly} && ($flags->{clearall} || $flags->{clear}) and die "conflicting flags readonly and clear/clearall";

    my @drives = detect_devices::hds();

    my (@hds);
    foreach my $hd (@drives) {
	$hd->{file} = devices::make($hd->{device});
	$hd->{prefix} ||= $hd->{device};
	$hd->{readonly} = $flags->{readonly};

	my $h = partition_table::raw::get_geometry($hd->{file}) or log::l("An error occurred while getting the geometry of block device $hd->{file}: $!"), next;
	add2hash_($hd, $h);

	eval { partition_table::raw::test_for_bad_drives($hd) if $::isInstall };
	if (my $err = $@) {
	    if ($err =~ /write error:/) { 
		$hd->{readonly} = 1;
	    } else {
		cdie $err if $err !~ /read error:/;
		next;
	    }
	}

	if ($flags->{clearall} || member($hd->{device}, @{$flags->{clear} || []})) {
	    partition_table::raw::zero_MBR_and_dirty($hd);
	} else {
	    eval { 
		partition_table::read($hd); 
		compare_with_proc_partitions($hd) if $::isInstall;
	    };
	    if (my $err = $@) {
		if ($hd->{readonly}) {
		    use_proc_partitions($hd);
		} elsif ($ask_before_blanking && $ask_before_blanking->($hd->{device}, $err)) {
		    partition_table::raw::zero_MBR($hd);
		} else {
		    #- using it readonly
		    use_proc_partitions($hd);
		}
	    }
	    member($_->{device}, @{$flags->{clear} || []}) and partition_table::remove($hd, $_)
	      foreach partition_table::get_normal_parts($hd);
	}

	# special case for Various type
	$_->{type} = typeOfPart($_->{device}) || 0x100 foreach grep { $_->{type} == 0x100 } partition_table::get_normal_parts($hd);

	#- special case for type overloading (eg: reiserfs is 0x183)
	foreach (grep { isExt2($_) } partition_table::get_normal_parts($hd)) {
	    my $type = typeOfPart($_->{device});
	    $_->{type} = $type if $type > 0x100 || $type && $hd->isa('partition_table::gpt');
	}
	push @hds, $hd;
    }

    #- detect raids before LVM allowing LVM on raid
    my $raids = raids(\@hds);
    my $all_hds = { %{ empty_all_hds() }, hds => \@hds, lvms => [], raids => $raids };

    $all_hds->{lvms} = [ lvms($all_hds) ];

    fs::get_major_minor(get_all_fstab($all_hds));

    $all_hds;
}

sub get_hds {
    #- $in is optional
    my ($flags, $in) = @_;

    if ($in) {
	catch_cdie { hds($flags, sub {
	    my ($dev, $err) = @_;
            $in->ask_yesorno(N("Error"), 
N("I can't read the partition table of device %s, it's too corrupted for me :(
I can try to go on, erasing over bad partitions (ALL DATA will be lost!).
The other solution is to not allow DrakX to modify the partition table.
(the error is %s)

Do you agree to loose all the partitions?
", $dev, formatError($err)));
        }) } sub { $in->ask_okcancel('', formatError($@)) };
    } else {
	catch_cdie { hds($flags) } sub { 1 }
    }
}

sub read_proc_partitions_raw() {
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

sub read_proc_partitions {
    my ($hds) = @_;

    my @all = read_proc_partitions_raw();
    my @parts = grep { $_->{dev} =~ /\d$/ } @all;
    my @disks = grep { $_->{dev} !~ /\d$/ } @all;

    my $devfs_like = any { $_->{dev} =~ m|/disc$| } @disks;

    my %devfs2normal = map {
	my (undef, $major, $minor) = devices::entry($_->{device});
	my $disk = find { $_->{major} == $major && $_->{minor} == $minor } @disks;
	$disk->{dev} => $_->{device};
    } @$hds;

    my $prev_part;
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
	$part->{size} *= 2;	# from KB to sectors
	$part->{type} = typeOfPart($dev); 
	$part->{start} = $prev_part ? $prev_part->{start} + $prev_part->{size} : 0;
	$prev_part = $part;
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
    my $hd = find { $part->{rootDevice} eq ($_->{device} || $_->{VG_name}) } all_hds($all_hds);
    $hd;
}

sub is_same_hd {
    my ($hd1, $hd2) = @_;
    if ($hd1->{major} && $hd2->{major}) {
	$hd1->{major} == $hd2->{major} && $hd1->{minor} == $hd2->{minor};
    } elsif (my ($s1) = $hd1->{device} =~ m|https?://(.+?)/*$|) {
	my ($s2) = $hd2->{device} =~ m|https?://(.+?)/*$|;
	$s1 eq $s2;
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
	    my $free_part = { start => 0, size => $free, type => 0, rootDevice => $_->{VG_name} };
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
    my @raids = grep { $_ } @{$all_hds->{raids}};
    @parts, @raids, @{$all_hds->{loopbacks}};
}
sub get_really_all_fstab {
    my ($all_hds) = @_;
    my @parts = map { partition_table::get_normal_parts($_) } all_hds($all_hds);
    my @raids = grep { $_ } @{$all_hds->{raids}};
    @parts, @raids, @{$all_hds->{loopbacks}}, @{$all_hds->{raw_hds}}, @{$all_hds->{nfss}}, @{$all_hds->{smbs}}, @{$all_hds->{davs}};
}
sub get_all_fstab_and_holes {
    my ($all_hds) = @_;
    my @raids = grep { $_ } @{$all_hds->{raids}};
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
    my ($fstab, $file, $keep_simple_symlinks) = @_;    
    my $part;

    $file = $keep_simple_symlinks ? common::expand_symlinks_but_simple("$::prefix$file") : expand_symlinks("$::prefix$file");
    unless ($file =~ s/^$::prefix//) {
	my $part = find { loopback::carryRootLoopback($_) } @$fstab or die;
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
    (any { $_->{size} < $max - $size } @L) ? $size : $max;
}

sub suggest_part {
    my ($part, $all_hds, $suggestions) = @_;
    $suggestions ||= $suggestions{server} || $suggestions{simple};

    my $has_swap = any { isSwap($_) } get_all_fstab($all_hds);

    my ($best) =
      grep { !$_->{maxsize} || $part->{size} <= $_->{maxsize} }
      grep { $_->{size} <= ($part->{maxsize} || $part->{size}) }
      grep { !has_mntpoint($_->{mntpoint}, $all_hds) || isSwap($_) && !$has_swap }
      grep { !$_->{hd} || $_->{hd} eq $part->{rootDevice} }
      grep { !$part->{type} || $part->{type} == $_->{type} || isTrueFS($part) && isTrueFS($_) }
	@$suggestions or return;

    defined $best or return; #- sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    $part->{type} = $best->{type} if !(isTrueFS($best) && isTrueFS($part));
    $part->{size} = computeSize($part, $best, $all_hds, $suggestions);
    $part->{options} = $best->{options} if $best->{options};
    1;
}

sub suggestions_mntpoint {
    my ($all_hds) = @_;
    sort grep { !/swap/ && !has_mntpoint($_, $all_hds) }
      (@suggestions_mntpoints, map { $_->{mntpoint} } @{$suggestions{server} || $suggestions{simple}});
}

sub mntpoint2part {
    my ($mntpoint, $fstab) = @_;
    find { $mntpoint eq $_->{mntpoint} } @$fstab;
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
    my ($type, $_hd, $part) = @_;
    isThisFs("jfs", { type => $type }) && $part->{size} < 16 << 11 and die N("You can't use JFS for partitions smaller than 16MB");
    isThisFs("reiserfs", { type => $type }) && $part->{size} < 32 << 11 and die N("You can't use ReiserFS for partitions smaller than 32MB");
}

sub package_needed_for_partition_type {
    my ($part) = @_;
    my %l = (
	reiserfs => 'reiserfsprogs',
	xfs => 'xfsprogs',
        jfs => 'jfsprogs',
    );
    $l{type2fs($part)};
}

#- do this before modifying $part->{mntpoint}
#- $part->{mntpoint} should not be used here, use $mntpoint instead
sub check_mntpoint {
    my ($mntpoint, $hd, $part, $all_hds) = @_;

    $mntpoint eq '' || isSwap($part) || isNonMountable($part) and return;
    $mntpoint =~ m|^/| or die N("Mount points must begin with a leading /");
    $mntpoint ne $part->{mntpoint} && has_mntpoint($mntpoint, $all_hds) and die N("There is already a partition with mount point %s\n", $mntpoint);

    die "raid / with no /boot" 
      if $mntpoint eq "/" && isRAID($part) && !has_mntpoint("/boot", $all_hds);
    die N("You can't use a LVM Logical Volume for mount point %s", $mntpoint)
      if ($mntpoint eq '/' || $mntpoint eq '/boot') && isLVM($hd);
    die N("This directory should remain within the root filesystem")
      if member($mntpoint, qw(/bin /dev /etc /lib /sbin /root /mnt));
    die N("You need a true filesystem (ext2/ext3, reiserfs, xfs, or jfs) for this mount point\n")
      if !isTrueFS($part) && member($mntpoint, qw(/ /home /tmp /usr /var));
    die N("You can't use an encrypted file system for mount point %s", $mntpoint)
      if $part->{options} =~ /encrypted/ && member($mntpoint, qw(/ /usr /var /boot));

    local $part->{mntpoint} = $mntpoint;
    loopback::check_circular_mounts($hd, $part, $all_hds);
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

    foreach my $part_ (get_all_holes($all_hds)) {
	my ($start, $size, $dev) = @$part_{"start", "size", "rootDevice"};
	my $part;
	while (suggest_part($part = { start => $start, size => 0, maxsize => $size, rootDevice => $dev }, 
			    $all_hds, $to_add)) {
	    my $hd = fsedit::part2hd($part, $all_hds);
	    add($hd, $part, $all_hds);
	    $size -= $part->{size} + $part->{start} - $start;
	    $start = $part->{start} + $part->{size};
	}
    }
}

sub auto_allocate {
    my ($all_hds, $suggestions) = @_;
    my $before = listlength(fsedit::get_all_fstab($all_hds));

    my $suggestions_ = $suggestions || $suggestions{simple};
    allocatePartitions($all_hds, $suggestions_);

    if ($suggestions) {
	auto_allocate_raids($all_hds, $suggestions);
	if (auto_allocate_vgs($all_hds, $suggestions)) {
	    #- allocatePartitions needs to be called twice, once for allocating PVs, once for allocating LVs
	    my @vgs = map { $_->{VG_name} } @{$all_hds->{lvms}};
	    my @suggested_lvs = grep { member($_->{hd}, @vgs) } @$suggestions;
	    allocatePartitions($all_hds, \@suggested_lvs);
	}
    }

    partition_table::assign_device_numbers($_) foreach @{$all_hds->{hds}};

    if ($before == listlength(fsedit::get_all_fstab($all_hds))) {
	# find out why auto_allocate failed
	if (any { !has_mntpoint($_->{mntpoint}, $all_hds) } @$suggestions_) {
	    die N("Not enough free space for auto-allocating");
	} else {
	    die N("Nothing to do");
	}
    }
}

sub auto_allocate_raids {
    my ($all_hds, $suggestions) = @_;

    my @raids = grep { isRawRAID($_) } get_all_fstab($all_hds) or return;

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

sub auto_allocate_vgs {
    my ($all_hds, $suggestions) = @_;

    my @pvs = grep { isRawLVM($_) } get_all_fstab($all_hds) or return;

    my @vgs = grep { $_->{VG_name} } @$suggestions or return;

    partition_table::write(@{$all_hds->{hds}});

    require lvm;

    foreach my $vg (@vgs) {
	my $lvm = new lvm($vg->{VG_name});
	push @{$all_hds->{lvms}}, $lvm;
	
	my @pvs_ = grep { !$vg->{parts} || $vg->{parts} =~ /\Q$_->{mntpoint}/ } @pvs;
	@pvs = difference2(\@pvs, \@pvs_);

	foreach my $part (@pvs_) {
	    raid::make($all_hds->{raids}, $part) if isRAID($part);
	    $part->{lvm} = $lvm->{VG_name};
	    delete $part->{mntpoint};
	    lvm::vg_add($part);
	    push @{$lvm->{disks}}, $part;
	}
	lvm::update_size($lvm);
    }
    1;
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
    sysopen G, $hd2->{file}, 2 or die N("Error opening %s for writing: %s", $hd2->{file}, $!);

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
    open(my $F, "rescuept $dev|");
    local $_;
    while (<$F>) {
	my ($st, $si, $id) = /start=\s*(\d+),\s*size=\s*(\d+),\s*Id=\s*(\d+)/ or next;
	my $part = { start => $st, size => $si, type => hex($id) };
	if (isExtended($part)) {
	    $ext = $part;
	} else {
	    push @hd, $part;
	}
    }
    close $F or die "rescuept failed";

    partition_table::raw::zero_MBR($hd);
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

sub compare_with_proc_partitions {
    my ($hd) = @_;

    my @l1 = partition_table::get_normal_parts($hd);
    my @l2 = grep { $_->{rootDevice} eq $hd->{device} } read_proc_partitions([$hd]);
    
    if (int(@l1) != int(@l2) && arch() ne 'ppc') {
	die sprintf(
		    "/proc/partitions doesn't agree with drakx %d != %d:\n%s\n", int(@l1), int(@l2),
		    "/proc/partitions: " . join(", ", map { "$_->{device} ($_->{rootDevice})" } @l2));
    }
    int @l2;
}

sub use_proc_partitions {
    my ($hd) = @_;

    log::l("using /proc/partitions since diskdrake failed :(");
    partition_table::raw::zero_MBR($hd);
    $hd->{readonly} = 1;
    $hd->{getting_rid_of_readonly_allowed} = 1;
    $hd->{primary} = { normal => [ grep { $_->{rootDevice} eq $hd->{device} } read_proc_partitions([$hd]) ] };
}

1;
