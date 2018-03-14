package partition_table::dos;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use Time::HiRes qw(usleep);
use common;
use partition_table::raw;
use partition_table;
use fs::proc_partitions;
use fs::type;
use c;

my @fields = qw(active start_head start_sec start_cyl pt_type end_head end_sec end_cyl start size);
my $format = "C8 V2";
my $magic = "\x55\xAA";
my $nb_primary = 4;

my $offset = $common::SECTORSIZE - length($magic) - $nb_primary * common::psizeof($format);

sub use_pt_type { 1 }
sub hasExtended { 1 }

sub geometry_to_string {
    my ($geom) = @_;
    "$geom->{cylinders}/$geom->{heads}/$geom->{sectors}";
}

sub last_usable_sector { 
    my ($hd) = @_;
    #- do not use totalsectors, see docs/Partition-ends-after-end-of-disk.txt for more
    $hd->{geom}{sectors} * $hd->{geom}{heads} * $hd->{geom}{cylinders};
}

my $two_TB = 2 * 1024 * 1024 * 2048;
sub max_partition_start { $two_TB - 1 }
sub max_partition_size { $two_TB - 1 }

sub get_rawCHS {
    my ($part) = @_;

    exists $part->{start_cyl} or internal_error("get_rawCHS $part->{device}");

    [ $part->{start_cyl}, $part->{start_head}, $part->{start_sec} ],
      [ $part->{end_cyl}, $part->{end_head}, $part->{end_sec} ];
}
sub set_rawCHS {
    my ($part, $raw_chs_start, $raw_chs_end) = @_;   
    ($part->{start_cyl}, $part->{start_head}, $part->{start_sec}) = @$raw_chs_start;
    ($part->{end_cyl}, $part->{end_head}, $part->{end_sec}) = @$raw_chs_end;
}

sub compute_CHS {
    my ($hd, $part) = @_;
    my ($chs_start, $chs_end) = CHS_from_part_linear($hd->{geom}, $part);
    set_rawCHS($part, $chs_start ? CHS2rawCHS($hd->{geom}, $chs_start) : [0,0,0], 
	              $chs_end ? CHS2rawCHS($hd->{geom}, $chs_end) : [0,0,0]);
}

sub CHS_from_part_rawCHS {
    my ($part) = @_;

    $part->{start} || $part->{pt_type} or return;

    my ($raw_chs_start, $raw_chs_end) = get_rawCHS($part);
    rawCHS2CHS($raw_chs_start), rawCHS2CHS($raw_chs_end);
}

sub CHS_from_part_linear {
    my ($geom, $part) = @_;

    $part->{start} || $part->{pt_type} or return;

    sector2CHS($geom, $part->{start}), sector2CHS($geom, $part->{start} + $part->{size} - 1);
}

sub rawCHS2CHS {
    my ($chs) = @_;
    my ($c, $h, $s) = @$chs;
    [ $c | (($s & 0xc0) << 2), $h, ($s & 0x3f) - 1 ];
}

sub CHS2rawCHS {
    my ($geom, $chs) = @_;
    my ($c, $h, $s) = @$chs;
    if ($c > 1023) {
	#- no way to have a #cylinder >= 1024
	$c = 1023;
	$h = $geom->{heads} - 1;
	$s = $geom->{sectors} - 1;
    }
    [ $c & 0xff, $h, ($s + 1) | (($c >> 2) & 0xc0) ];
}

# returns (cylinder, head, sector)
sub sector2CHS {
    my ($geom, $start) = @_;
    my ($s, $h);
    ($start, $s) = divide($start, $geom->{sectors});
    ($start, $h) = divide($start, $geom->{heads});
    [ $start, $h, $s ];
}

sub is_geometry_valid_for_the_partition_table {
    my ($hd, $geom, $no_log) = @_;

    every {
	my ($chs_start_v1, $chs_end_v1) = map { join(',', @$_) } CHS_from_part_rawCHS($_) or next;
	my ($chs_start_v2, $chs_end_v2) = map { join(',', @$_) } map { [ min($_->[0], 1023), $_->[1], $_->[2] ] } CHS_from_part_linear($geom, $_);
	if (!$no_log) {
	    $chs_start_v1 eq $chs_start_v2 or log::l("is_geometry_valid_for_the_partition_table failed for ($_->{device}, $_->{start}): $chs_start_v1 vs $chs_start_v2 with geometry " . geometry_to_string($geom));
	    $chs_end_v1 eq $chs_end_v2 or log::l("is_geometry_valid_for_the_partition_table failed for ($_->{device}, " . ($_->{start} + $_->{size} - 1) . "): $chs_end_v1 vs $chs_end_v2 with geometry " . geometry_to_string($geom));
	}
	$chs_start_v1 eq $chs_start_v2 && $chs_end_v1 eq $chs_end_v2;
    } @{$hd->{primary}{normal} || []};
}

#- from parted, thanks!
my @valid_nb_sectors = (63, 61, 48, 32, 16);
my @valid_nb_heads = (255, 240, 192, 128, 96, 64, 61, 32, 17, 16);

sub guess_geometry_from_partition_table {
    my ($hd) = @_;

    my @chss = map { CHS_from_part_rawCHS($_) } @{$hd->{primary}{normal} || []} or return { empty => 1 };
    my ($nb_heads, $nb_sectors) = (max(map { $_->[1] } @chss) + 1, max(map { $_->[2] } @chss) + 1);    
    my $geom = { sectors => $nb_sectors, heads => $nb_heads };
    partition_table::raw::compute_nb_cylinders($geom, $hd->{totalsectors});
    log::l("guess_geometry_from_partition_table $hd->{device}: " . geometry_to_string($geom));

    member($geom->{sectors}, @valid_nb_sectors) or return { invalid => 1 };
    $geom;
}

sub geometry_from_edd {
    my ($hd, $edd_dir) = @_;

    my $sectors = cat_("$edd_dir/legacy_sectors_per_track") or return;
    my $heads = cat_("$edd_dir/legacy_max_head") or return;

    my $geom = { sectors => 0 + $sectors, heads => 1 + $heads, from_edd => 1 };
    is_geometry_valid_for_the_partition_table($hd, $geom, 0) or return;
    partition_table::raw::compute_nb_cylinders($geom, $hd->{totalsectors});

    log::l("geometry_from_edd $hd->{device} $hd->{volume_id}: " . geometry_to_string($geom));
    
    $geom;
}


sub try_every_geometry {
    my ($hd) = @_;

    my $geom = {};
    foreach (@valid_nb_sectors) {
	$geom->{sectors} = $_;
	foreach (@valid_nb_heads) {
	    $geom->{heads} = $_;
	    if (is_geometry_valid_for_the_partition_table($hd, $geom, 1)) {
		partition_table::raw::compute_nb_cylinders($geom, $hd->{totalsectors});
		log::l("try_every_geometry $hd->{device}: found " . geometry_to_string($geom));
		return $geom;
	    }
	}
    }
    log::l("$hd->{device}: argh! no geometry exists for this partition table");
    undef;
}

sub set_best_geometry_for_the_partition_table {
    my ($hd) = @_;

    my $guessed_geom = guess_geometry_from_partition_table($hd);
    if ($guessed_geom->{empty}) {
	log::l("$hd->{device}: would need looking at BIOS info to find out geometry") if !$hd->{geom}{from_edd};
	return;
    } 
    my $default_ok = is_geometry_valid_for_the_partition_table($hd, $hd->{geom}, 0);
    if ($guessed_geom->{invalid}) {
	log::l("$hd->{device}: no valid geometry guessed from partition table");
	$default_ok and return;
	$guessed_geom = try_every_geometry($hd) or return;
    }
    
    if ($guessed_geom->{heads} == $hd->{geom}{heads} && $guessed_geom->{sectors} == $hd->{geom}{sectors}) {
	# cool!
    } else {
	my $guessed_ok = is_geometry_valid_for_the_partition_table($hd, $guessed_geom, 0);
	if ($default_ok && $guessed_ok) {
	    #- oh my!?
	    log::l("$hd->{device}: both guessed and default are valid??? " . geometry_to_string($hd->{geom}) . " vs " . geometry_to_string($guessed_geom));	    
	} elsif ($default_ok) {
	    log::l("$hd->{device}: keeping default geometry " . geometry_to_string($hd->{geom}));	    
	} elsif ($guessed_ok) {
	    log::l("$hd->{device}: using guessed geometry " . geometry_to_string($guessed_geom) . " instead of " . geometry_to_string($hd->{geom}));
	    put_in_hash($hd->{geom}, $guessed_geom);
	} else {
	    log::l("$hd->{device}: argh! no valid geometry found");	    
	}
    }
}

sub read_one {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, $offset) or die "reading of partition in sector $sector failed";

    my @pt = map {
	sysread $F, $tmp, psizeof($format) or die "error while reading partition table in sector $sector";
	my %h; 
	@h{@fields} = unpack $format, $tmp;
	$h{pt_type} = 'BIOS_GRUB' if $h{pt_type} == 0 && $h{size} > 0;
	fs::type::set_pt_type(\%h, $h{pt_type});
	\%h;
    } (1..$nb_primary);

    #- check magic number
    sysread $F, $tmp, length $magic or die "error reading magic number on disk $hd->{device}";
    $tmp eq $magic or die "bad magic number on disk $hd->{device}";

    if (c::get_disk_type($hd->{file}) ne "msdos") {
	# libparted may have ignored it because of overlapping partitions or other error
	# while it is actually a partition table.
	$hd->{fs_type_from_magic} and die "unpartitionned disk";
	my $primary = partition_table::raw::pt_info_to_primary($hd, [ @pt ]);
       foreach my $i (@{$primary->{normal}}) {
          if ($i->{active} && $i->{active} != 0x80 || 
             $hd->{totalsectors} && $i->{start} > $hd->{totalsectors}) {
                die "Invalid DOS partition table";
          }
       }
    }

    [ @pt ];
}

# prepare to write the partition table (and extended ones)
sub start_write {
    my ($hd) = @_;

    log::l("partition::dos::write $hd->{device}");

    #- handle testing for writing partition table on file only!
    my $F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open $F, ">$file" or die "error opening test file $file";
    } else {
	$F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
    }
    $F;
}

# write the partition table (and extended ones)
# for each entry, it uses fields: start, size, pt_type, active
sub write {
    my ($hd, $F, $sector, $pt) = @_;

    if (!$::testing) {
        c::lseek_sector(fileno($F), $sector, $offset) or return 0;
    }

    @$pt == $nb_primary or die "partition table does not have $nb_primary entries";
    foreach (@$pt) {
	compute_CHS($hd, $_);
	local $_->{start} = $_->{local_start} || 0;
	$_->{active} ||= 0; $_->{pt_type} ||= 0; $_->{size} ||= 0; #- for no warning
	syswrite $F, pack($format, @$_{@fields}), psizeof($format) or return 0;
    }
    syswrite $F, $magic, length $magic or return 0;
    1;
}

sub end_write {
    my ($hd, $F) = @_;
    close $F;
}

sub need_to_tell_kernel {
    my ($hd) = @_;
    # Whenever udevd receives a change event for a raw disk device it is watching, it asks the kernel to
    # rescan the partition table on that device by calling the BLKRRPART ioctl. This is only successful
    # if none of the partitions on that device are currently mounted. So if any partitions are mounted,
    # we need to tell the kernel what has changed ourselves.
    # The udev/rules.d/60-block.rules file causes the raw disk devices to be watched by udev. This file is
    # not present in the cut-down system used to run the classic installer, so we always need to tell the
    # kernel in that case.
    # diskdrake will not let the user delete an individual partition that is mounted, but will let the
    # user clear all partitions. So initialize() records if any partitions were mounted and we take note
    # of that here.
    return 1 if ! -e '/usr/lib/udev/rules.d/60-block.rules' || delete $hd->{hadMountedPartitions} || any { $_->{isMounted} } partition_table::get_normal_parts($hd);

    # No further actions must be performed until the kernel has been informed of the changes. There is
    # no easy way to check that udevd has received the uevent and called the BLKRRPART ioctl, so do it
    # the hard way.
    my $tries = 0;
    do {
	usleep(100000);
	log::l("checking that udevd has informed the kernel of partition table changes");
	eval { fs::proc_partitions::compare($hd) };
	return 0 if !$@;
	$tries++;
    } while $tries < 5;

    # We don't expect to get here, but fail safe if so.
    log::l("udevd failed to inform kernel of partition table changes");
    $hd->{rebootNeeded} = 1;
    1;
}

sub empty_raw { { raw => [ ({}) x $nb_primary ] } }

sub initialize { 
    my ($class, $hd) = @_;
    # Remember whether any existing partitions are mounted, for use by need_to_tell_kernel().
    $hd->{hadMountedPartitions} = 1 if any { $_->{isMounted} } partition_table::get_normal_parts($hd);
    $hd->{primary} = empty_raw();
    bless $hd, $class;
}

1;
