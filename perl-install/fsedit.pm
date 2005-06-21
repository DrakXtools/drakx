package fsedit; # $Id$

use diagnostics;
use strict;
use vars qw(%suggestions);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table;
use partition_table::raw;
use fs::get;
use fs::type;
use fs::loopback;
use fs::proc_partitions;
use detect_devices;
use devices;
use log;
use fs;

%suggestions = (
  N_("simple") => [
    { mntpoint => "/",     size => 300 << 11, fs_type => 'ext3', ratio => 5, maxsize => 6000 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, fs_type => 'swap', ratio => 1, maxsize => 1100 << 11 },
    { mntpoint => "/home", size => 300 << 11, fs_type => 'ext3', ratio => 3 },
  ], N_("with /usr") => [
    { mntpoint => "/",     size => 250 << 11, fs_type => 'ext3', ratio => 1, maxsize => 2000 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, fs_type => 'swap', ratio => 1, maxsize => 1100 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, fs_type => 'ext3', ratio => 4, maxsize => 4000 << 11 },
    { mntpoint => "/home", size => 100 << 11, fs_type => 'ext3', ratio => 3 },
  ], N_("server") => [
    { mntpoint => "/",     size => 150 << 11, fs_type => 'ext3', ratio => 1, maxsize =>  800 << 11 },
    { mntpoint => "swap",  size =>  64 << 11, fs_type => 'swap', ratio => 2, maxsize => 1600 << 11 },
    { mntpoint => "/usr",  size => 300 << 11, fs_type => 'ext3', ratio => 4, maxsize => 4000 << 11 },
    { mntpoint => "/var",  size => 200 << 11, fs_type => 'ext3', ratio => 3 },
    { mntpoint => "/home", size => 150 << 11, fs_type => 'ext3', ratio => 3 },
    { mntpoint => "/tmp",  size => 150 << 11, fs_type => 'ext3', ratio => 2, maxsize => 1000 << 11 },
  ],
);
foreach (values %suggestions) {
    if (arch() =~ /ia64/) {
	@$_ = ({ mntpoint => "/boot/efi", size => 50 << 11, pt_type => 0xef, ratio => 1, maxsize => 150 << 11 }, @$_);
    }
}

my @suggestions_mntpoints = (
    "/var/ftp", "/var/www", "/boot", '/usr/local', '/opt',
    arch() =~ /sparc/ ? "/mnt/sunos" : arch() =~ /ppc/ ? "/mnt/macos" : "/mnt/windows",
);

#-######################################################################################
#- Functions
#-######################################################################################
sub recompute_loopbacks {
    my ($all_hds) = @_;
    my @fstab = fs::get::fstab($all_hds);
    @{$all_hds->{loopbacks}} = map { isPartOfLoopback($_) ? @{$_->{loopback}} : () } @fstab;
}

sub raids {
    my ($hds) = @_;

    my @parts = fs::get::hds_fstab(@$hds);

    my @l = grep { isRawRAID($_) } @parts or return [];

    log::l("looking for raids in " . join(' ', map { $_->{device} } @l));
    
    require raid;
    raid::detect_during_install(@l) if $::isInstall;
    raid::get_existing(@l);
}

sub lvms {
    my ($all_hds) = @_;
    my @pvs = grep { isRawLVM($_) } fs::get::fstab($all_hds) or return;

    log::l("looking for vgs in " . join(' ', map { $_->{device} } @pvs));

    #- otherwise vgscan will not find them
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

sub handle_dmraid {
    my ($drives) = @_;

    @$drives > 1 or return;

    devices::make($_->{device}) foreach @$drives;

    require fs::dmraid;

    my @pvs = fs::dmraid::pvs();
    my @vgs = fs::dmraid::vgs();
    log::l(sprintf('dmraid: pvs = [%s], vgs = [%s]',
		   join(' ', @pvs),
		   join(' ', map { $_->{device} } @vgs)));

    my @used_hds = map {
	my $part = fs::get::device2part($_, $drives) or log::l("handle_dmraid: can't find $_ in known drives");
	if_($part, $part);
    } @pvs;

    @$drives = difference2($drives, \@used_hds);

    push @$drives, @vgs;
}

sub get_hds {
    my ($o_flags, $o_in) = @_;
    my $flags = $o_flags || {};
    $flags->{readonly} && ($flags->{clearall} || $flags->{clear}) and die "conflicting flags readonly and clear/clearall";

    my @drives = detect_devices::hds();

    #- replace drives used in dmraid by the merged name
    handle_dmraid(\@drives);

    foreach my $hd (@drives) {
	$hd->{file} = devices::make($hd->{device});
	$hd->{prefix} ||= $hd->{device};
    }

    @drives = partition_table::raw::get_geometries(@drives);

    my (@hds, @raw_hds);
    foreach my $hd (@drives) {
	$hd->{readonly} = $flags->{readonly};

	eval { partition_table::raw::test_for_bad_drives($hd) if !$flags->{no_bad_drives} };
	if (my $err = $@) {
	    if ($err =~ /write error:/) { 
		$hd->{readonly} = 1;
	    } elsif ($err =~ /read error:/) {
		next;
	    } else {
		$o_in and $o_in->ask_warn('', $err);
		next;
	    }
	}

	if ($flags->{clearall} || member($hd->{device}, @{$flags->{clear} || []})) {
	    partition_table::raw::zero_MBR_and_dirty($hd);
	} else {
	    my $handle_die_and_cdie = sub {
		if ($hd->{readonly}) {
		    log::l("using /proc/partitions since diskdrake failed :(");
		    fs::proc_partitions::use_($hd);
		    1;
		} elsif (my $type = fs::type::type_subpart_from_magic($hd)) {
		    #- non partitioned drive?
		    if (exists $hd->{usb_description} && $type->{fs_type}) {
			#- USB keys
			put_in_hash($hd, $type);
			push @raw_hds, $hd;
			$hd = '';
			1;
		    } elsif ($type->{pt_type} == 0x8e) {
			#- LVM on full disk
			my $part = { size => $hd->{totalsectors}, device => $hd->{device}, %$type };
			bless $hd, 'partition_table::raw';
			$hd->{readonly} = $hd->{getting_rid_of_readonly_allowed} = 1;
			$hd->{primary}{normal} = [ $part ];
			1;
		    } else {
			0;
		    }
		} else {
		    0;
		}
	    };
	    my $handled;
	    eval {
		catch_cdie {
		    partition_table::read($hd);
		    if (listlength(partition_table::get_normal_parts($hd)) == 0) {
			$handled = 1 if $handle_die_and_cdie->();
		    } else {
			fs::proc_partitions::compare($hd) if $::isInstall;
		    }
		} sub {
		    my $err = $@;
		    if ($handle_die_and_cdie->()) {
			$handled = 1;
			0; #- do not continue, transform cdie into die
		    } else {
			!$o_in || $o_in->ask_okcancel('', formatError($err));
		    }
		};
	    };
	    if (my $err = $@) {
		if ($handled) {
		    #- already handled in cdie handler above
		} elsif ($handle_die_and_cdie->()) {
		} elsif ($o_in && $o_in->ask_yesorno(N("Error"), 
N("I can not read the partition table of device %s, it's too corrupted for me :(
I can try to go on, erasing over bad partitions (ALL DATA will be lost!).
The other solution is to not allow DrakX to modify the partition table.
(the error is %s)

Do you agree to lose all the partitions?
", $hd->{device}, formatError($err)))) {
		    partition_table::raw::zero_MBR($hd);
		} else {
		    #- using it readonly
		    log::l("using /proc/partitions since diskdrake failed :(");
		    fs::proc_partitions::use_($hd);
		}
	    }
	    $hd or next;

	    member($_->{device}, @{$flags->{clear} || []}) and partition_table::remove($hd, $_)
	      foreach partition_table::get_normal_parts($hd);
	}

	my @parts = partition_table::get_normal_parts($hd);

	# checking the magic of the filesystem, do not rely on pt_type
	foreach (grep { member($_->{fs_type}, 'vfat', 'ntfs', 'ext2') || $_->{pt_type} == 0x100 } @parts) {
	    if (my $type = fs::type::type_subpart_from_magic($_)) {
                if ($type->{fs_type}) {
                    #- keep {pt_type}
		    $_->{fs_type} = $type->{fs_type};
                } else {
                    put_in_hash($_, $type); 
                }
	    } else {
		$_->{bad_fs_type_magic} = 1;
	    }
	}
	
	foreach (@parts) {
	    my $label =
	      member($_->{fs_type}, qw(ext2 ext3)) ?
		c::get_ext2_label(devices::make($_->{device})) :
		'';
	    $_->{device_LABEL} = $label if $label;
	}

	if ($hd->{usb_media_type}) {
	    $_->{is_removable} = 1 foreach @parts;
	}

	push @hds, $hd;
    }

    #- detect raids before LVM allowing LVM on raid
    my $raids = raids(\@hds);
    my $all_hds = { %{ fs::get::empty_all_hds() }, hds => \@hds, raw_hds => \@raw_hds, lvms => [], raids => $raids };

    $all_hds->{lvms} = [ lvms($all_hds) ];

    fs::get_major_minor([ fs::get::fstab($all_hds) ]);

    $all_hds;
}

#- are_same_partitions() do not look at the device name since things may have changed
sub are_same_partitions {
    my ($part1, $part2) = @_;
    foreach ('start', 'size', 'pt_type', 'fs_type', 'rootDevice') {
	$part1->{$_} eq $part2->{$_} or return 0;
    }
    1;
}

sub is_one_big_fat_or_NT {
    my ($hds) = @_;
    @$hds == 1 or return 0;

    my @l = fs::get::hds_fstab(@$hds);
    @l == 1 && isFat_or_NTFS($l[0]) && fs::get::hds_free_space(@$hds) < 10 << 11;
}


sub computeSize {
    my ($part, $best, $all_hds, $suggestions) = @_;
    my $max = $part->{maxsize} || $part->{size};
    return min($max, $best->{size}) unless $best->{ratio};

    my %free_space;
    $free_space{$_->{rootDevice}} += $_->{size} foreach fs::get::holes($all_hds);

    my @l = my @L = grep {
	my @possible = $_->{hd} ? $_->{hd} : keys %free_space;
	my $size = $_->{size};
	if (my $dev = find { $free_space{$_} >= $size } @possible) {
	    $free_space{$dev} -= $size;
	    1;
	} else { 0 } } @$suggestions;

    my $free_space = $best->{hd} && $free_space{$best->{hd}} || sum(values %free_space);

    my $cylinder_size_maxsize_adjusted;
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
		if (!$cylinder_size_maxsize_adjusted++) {
		    eval { $free_space += fs::get::part2hd($part, $all_hds)->cylinder_size - 1 };
		}
		0;
	    } else {
		$_->{ratio};
	    } 
	} @l;
    }
    my $size = int min($max, $best->{size} + $free_space * ($tot_ratios && $best->{ratio} / $tot_ratios));
    #- verify other entry can fill the hole
    (any { $_->{size} <= $max - $size } @L) ? $size : $max;
}

sub suggest_part {
    my ($part, $all_hds, $o_suggestions) = @_;
    my $suggestions = $o_suggestions || $suggestions{server} || $suggestions{simple};

    #- suggestions now use {fs_type}, but still keep compatibility
    foreach (@$suggestions) {
	fs::type::set_pt_type($_, $_->{pt_type}) if !exists $_->{fs_type};
    }

    my $has_swap = any { isSwap($_) } fs::get::fstab($all_hds);

    my @local_suggestions =
      grep { !fs::get::has_mntpoint($_->{mntpoint}, $all_hds) || isSwap($_) && !$has_swap }
      grep { !$_->{hd} || $_->{hd} eq $part->{rootDevice} }
	@$suggestions;

    my ($best) =
      grep { !$_->{maxsize} || $part->{size} <= $_->{maxsize} }
      grep { $_->{size} <= ($part->{maxsize} || $part->{size}) }
      grep { !$part->{fs_type} || $part->{fs_type} eq $_->{fs_type} || isTrueFS($part) && isTrueFS($_) }
	@local_suggestions;

    defined $best or return 0; #- sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    fs::type::set_type_subpart($part, $best) if !isTrueFS($best) || !isTrueFS($part);
    $part->{size} = computeSize($part, $best, $all_hds, \@local_suggestions);
    foreach ('options', 'lv_name', 'encrypt_key', 'device_LABEL', 'prefer_device_LABEL') {
	$part->{$_} = $best->{$_} if $best->{$_};
    }
    1;
}

sub suggestions_mntpoint {
    my ($all_hds) = @_;
    sort grep { !/swap/ && !fs::get::has_mntpoint($_, $all_hds) }
      (@suggestions_mntpoints, map { $_->{mntpoint} } @{$suggestions{server} || $suggestions{simple}});
}

#- you can do this before modifying $part->{mntpoint}
#- so $part->{mntpoint} should not be used here, use $mntpoint instead
sub check_mntpoint {
    my ($mntpoint, $part, $all_hds) = @_;

    $mntpoint eq '' || isSwap($part) || isNonMountable($part) and return 0;
    $mntpoint =~ m|^/| or die N("Mount points must begin with a leading /");
    $mntpoint =~ m|[\x7f-\xff]| and cdie N("Mount points should contain only alphanumerical characters");
    fs::get::mntpoint2part($mntpoint, [ grep { $_ ne $part } fs::get::really_all_fstab($all_hds) ]) and die N("There is already a partition with mount point %s\n", $mntpoint);

    cdie N("You've selected a software RAID partition as root (/).
No bootloader is able to handle this without a /boot partition.
Please be sure to add a /boot partition") if $mntpoint eq "/" && isRAID($part) && !fs::get::has_mntpoint("/boot", $all_hds);
    die N("You can not use a LVM Logical Volume for mount point %s", $mntpoint)
      if $mntpoint eq '/boot' && isLVM($part);
    cdie N("You've selected a LVM Logical Volume as root (/).
The bootloader is not able to handle this without a /boot partition.
Please be sure to add a /boot partition") if $mntpoint eq "/" && isLVM($part) && !fs::get::has_mntpoint("/boot", $all_hds);
    cdie N("You may not be able to install lilo (since lilo does not handle a LV on multiple PVs)")
      if 0; # arch() =~ /i.86/ && $mntpoint eq '/' && isLVM($hd) && @{$hd->{disks} || []} > 1;

    cdie N("This directory should remain within the root filesystem")
      if member($mntpoint, qw(/root));
    die N("This directory should remain within the root filesystem")
      if member($mntpoint, qw(/bin /dev /etc /lib /sbin /mnt));
    die N("You need a true filesystem (ext2/ext3, reiserfs, xfs, or jfs) for this mount point\n")
      if !isTrueLocalFS($part) && $mntpoint eq '/';
    die N("You need a true filesystem (ext2/ext3, reiserfs, xfs, or jfs) for this mount point\n")
      if !isTrueFS($part) && member($mntpoint, fs::type::directories_needed_to_boot());
    die N("You can not use an encrypted file system for mount point %s", $mntpoint)
      if $part->{options} =~ /encrypted/ && member($mntpoint, qw(/ /usr /var /boot));

    local $part->{mntpoint} = $mntpoint;
    fs::loopback::check_circular_mounts($part, $all_hds);
}

sub add {
    my ($hd, $part, $all_hds, $options) = @_;

    isSwap($part) ?
      ($part->{mntpoint} = 'swap') :
      $options->{force} || check_mntpoint($part->{mntpoint}, $part, $all_hds);

    delete $part->{maxsize};

    if (isLVM($hd)) {
	lvm::lv_create($hd, $part);
    } else {
	partition_table::add($hd, $part, $options->{primaryOrExtended});
    }
}

sub allocatePartitions {
    my ($all_hds, $to_add) = @_;

    foreach my $part_ (fs::get::holes($all_hds)) {
	my ($start, $size, $dev) = @$part_{"start", "size", "rootDevice"};
	my $part;
	while (suggest_part($part = { start => $start, size => 0, maxsize => $size, rootDevice => $dev }, 
			    $all_hds, $to_add)) {
	    my $hd = fs::get::part2hd($part, $all_hds);
	    add($hd, $part, $all_hds, {});
	    $size -= $part->{size} + $part->{start} - $start;
	    $start = $part->{start} + $part->{size};
	}
    }
}

sub auto_allocate {
    my ($all_hds, $o_suggestions) = @_;
    my $before = listlength(fs::get::fstab($all_hds));

    my $suggestions = $o_suggestions || $suggestions{simple};
    allocatePartitions($all_hds, $suggestions);

    if ($o_suggestions) {
	auto_allocate_raids($all_hds, $suggestions);
	if (auto_allocate_vgs($all_hds, $suggestions)) {
	    #- allocatePartitions needs to be called twice, once for allocating PVs, once for allocating LVs
	    my @vgs = map { $_->{VG_name} } @{$all_hds->{lvms}};
	    my @suggested_lvs = grep { member($_->{hd}, @vgs) } @$suggestions;
	    allocatePartitions($all_hds, \@suggested_lvs);
	}
    }

    partition_table::assign_device_numbers($_) foreach @{$all_hds->{hds}};

    if ($before == listlength(fs::get::fstab($all_hds))) {
	# find out why auto_allocate failed
	if (any { !fs::get::has_mntpoint($_->{mntpoint}, $all_hds) } @$suggestions) {
	    die N("Not enough free space for auto-allocating");
	} else {
	    die N("Nothing to do");
	}
    }
}

sub auto_allocate_raids {
    my ($all_hds, $suggestions) = @_;

    my @raids = grep { isRawRAID($_) } fs::get::fstab($all_hds) or return;

    require raid;
    my @mds = grep { $_->{hd} =~ /md/ } @$suggestions;
    foreach my $md (@mds) {
	my @raids_ = grep { !$md->{parts} || $md->{parts} =~ /\Q$_->{mntpoint}/ } @raids;
	@raids = difference2(\@raids, \@raids_);

	my %h = %$md;
	delete @h{'hd', 'parts'}; # keeping mntpoint, level, chunk-size, fs_type/pt_type
	$h{disks} = \@raids_;

	my $part = raid::new($all_hds->{raids}, %h);

	raid::updateSize($part);
	push @raids, $part; #- we can build raid over raid
    }
}

sub auto_allocate_vgs {
    my ($all_hds, $suggestions) = @_;

    my @pvs = grep { isRawLVM($_) } fs::get::fstab($all_hds) or return 0;

    my @vgs = grep { $_->{VG_name} } @$suggestions or return 0;

    partition_table::write($_) foreach @{$all_hds->{hds}};

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

sub change_type {
    my ($type, $hd, $part) = @_;
    $type->{pt_type} != $part->{pt_type} || $type->{fs_type} ne $part->{fs_type} or return;
    fs::type::check($type->{fs_type}, $hd, $part);
    $hd->{isDirty} = 1;
    $part->{mntpoint} = '' if isSwap($part) && $part->{mntpoint} eq "swap";
    $part->{mntpoint} = '' if isRawLVM($type) || isRawRAID($type);
    set_isFormatted($part, 0);
    fs::type::set_type_subpart($part, $type);
    fs::mount_options::rationalize($part);
    1;
}

sub rescuept($) {
    my ($hd) = @_;
    my ($ext, @hd);

    my $dev = devices::make($hd->{device});
    open(my $F, "rescuept $dev|");
    local $_;
    while (<$F>) {
	my ($st, $si, $id) = /start=\s*(\d+),\s*size=\s*(\d+),\s*Id=\s*(\d+)/ or next;
	my $part = { start => $st, size => $si };
	fs::type::set_pt_type($part, hex($id));
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

1;
