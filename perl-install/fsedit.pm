package fsedit;

use diagnostics;
use strict;

use common qw(:common);
use partition_table qw(:types);
use partition_table_raw;
use devices;
use log;

1;

my @suggestions = (
  { mntpoint => "/boot",    minsize =>  10 << 11, size =>  16 << 11, type => 0x83 }, 
  { mntpoint => "/",        minsize =>  50 << 11, size => 100 << 11, type => 0x83 }, 
  { mntpoint => "swap",     minsize =>  30 << 11, size =>  60 << 11, type => 0x82 },
  { mntpoint => "/usr",     minsize => 200 << 11, size => 500 << 11, type => 0x83 }, 
  { mntpoint => "/home",    minsize =>  50 << 11, size => 200 << 11, type => 0x83 }, 
  { mntpoint => "/var",     minsize => 200 << 11, size => 250 << 11, type => 0x83 }, 
  { mntpoint => "/tmp",     minsize =>  50 << 11, size => 100 << 11, type => 0x83 }, 
  { mntpoint => "/mnt/iso", minsize => 700 << 11, size => 800 << 11, type => 0x83 }, 
);


1;

sub hds($$) {
    my ($drives, $flags) = @_;
    my @hds;
    my $rc;

    foreach (@$drives) {
	my $file = devices::make($_->{device});

	my $hd = partition_table_raw::get_geometry($file) or die "An error occurred while getting the geometry of block device $file: $!";
	$hd->{file} = $file;
	$hd->{prefix} = $hd->{device} = $_->{device};
	# for RAID arrays of format c0d0p1 
	$hd->{prefix} .= "p" if $hd->{prefix} =~ m,(rd|ida)/,;

	eval { $rc = partition_table::read($hd, $flags->{clearall}) }; 
	if ($@) {
	    $@ =~ /bad magic number/ or die;
	    partition_table_raw::zero_MBR($hd) if $flags->{eraseBadPartitions};
	}
	$rc ? push @hds, $hd : log::l("An error occurred reading the partition table for the block device $_->{device}");
    }
    [ @hds ];
}

sub get_fstab(@) {
    map { partition_table::get_normal_parts($_) } @_;
}

sub suggest_part($$$;$) {
    my ($hd, $part, $hds, $suggestions) = @_;
    $suggestions ||= \@suggestions;
    foreach (@$suggestions) { $_->{minsize} ||= $_->{size} }

    my $has_swap;
    my @mntpoints = map { $has_swap ||= isSwap($_); $_->{mntpoint} } get_fstab(@$hds);
    my %mntpoints; @mntpoints{@mntpoints} = undef;

    my ($best, $second) = 
      grep { $part->{size} >= $_->{minsize} }
      grep { !exists $mntpoints{$_->{mntpoint}} || isSwap($_) && !$has_swap }
	@$suggestions or return;

    $best = $second if 
      $best->{mntpoint} eq '/boot' && 
      $part->{start} + $best->{minsize} > 1024 * partition_table::cylinder_size($hd); # if the empty slot is beyond the 1024th cylinder, no use having /boot

    defined $best or return; # sorry no suggestion :(

    $part->{mntpoint} = $best->{mntpoint};
    $part->{type} = $best->{type};
    $part->{size} = min($part->{size}, $best->{size});
    1;
}


#sub partitionDrives {
#
#    my $cmd = "/sbin/fdisk";
#    -x $cmd or $cmd = "/usr/bin/fdisk";
#
#    my $drives = findDrivesPresent() or die "You don't have any hard drives available! You probably forgot to configure a SCSI controller.";
#
#    foreach (@$drives) {
#	 my $text = "/dev/" . $_->{device};
#	 $text .= " - SCSI ID " . $_->{id} if $_->{device} =~ /^sd/;
#	 $text .= " - Model " . $_->{info};
#	 $text .= " array" if $_->{device} =~ /^c.d/;
#
#	 # truncate at 50 columns for now 
#	 $text = substr $text, 0, 50;
#    }
#    #TODO TODO
#}



sub checkMountPoint($$) {
#    my $type = shift;
#    local $_ = shift;
#
#    m|^/| or die "The mount point $_ is illegal.\nMount points must begin with a leading /";
#    m|(.)/$| and die "The mount point $_ is illegal.\nMount points may not end with a /";
#    c::isprint($_) or die "The mount point $_ is illegal.\nMount points must be made of printable characters (no accents...)";
#
#    foreach my $dev (qw(/dev /bin /sbin /etc /lib)) {
#	 /^$dev/ and die "The $_ directory must be on the root filesystem.",
#    }
#
#    if ($type eq 'linux_native') {
#	 $_ eq '/'; and return 1;
#	 foreach my $r (qw(/var /tmp /boot /root)) {
#	     /^$r/ and return 1;
#	 }
#	 die "The mount point $_ is illegal.\nSystem partitions must be on Linux Native partitions";
#    }
#    1;
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
		# the free block is just the same size, removing it
		splice(@$list, 0, 2);
	    } else {
		# the free block now start just after this block
		$list->[$i] = $end;
	    }
	} else {
	    $end <= $list->[$i + 1] or die $err;
	    if ($end < $list->[$i + 1]) {
		splice(@$list, $i + 2, 0, $end, $list->[$i + 1]);
	    }
	    $list->[$i + 1] = $start; # shorten the free block
	}
	return;
    }
}


sub allocatePartitions($$) {
    my ($hds, $to_add) = @_;
    my %free_sectors = map { $_->{device} => [1, $_->{totalsectors} ] } @$hds; # first sector is always occupied by the MBR
    my $remove = sub { removeFromList($_[0]->{start}, $_[0]->{start} + $_[0]->{size}, $free_sectors{$_[0]->{rootDevice}}) };
    my $success = 0;

    foreach (get_fstab(@$hds)) { &$remove($_); }

    FSTAB: foreach (@$to_add) {
	my %e = %$_;
	foreach my $hd (@$hds) {
	    my $v = $free_sectors{$hd->{device}};
	    for (my $i = 0; $i < @$v; $i += 2) {
		my $size = $v->[$i + 1] - $v->[$i];
		$e{size} > $size and next;
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
    allocatePartitions($hds, $suggestions || \@suggestions);
    map { partition_table::assign_device_numbers($_) } @$hds;
}
