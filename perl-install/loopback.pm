package loopback; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use MDK::Common::System;
use common;
use partition_table qw(:types);
use fs;
use fsedit;
use log;


sub carryRootLoopback {
    my ($part) = @_;
    $_->{mntpoint} eq '/' and return 1 foreach @{$part->{loopback} || []};
    0;
}

sub check_circular_mounts {
    my ($hd, $part, $all_hds) = @_;

    my $fstab = [ fsedit::get_all_fstab($all_hds), $part ]; # no pb if $part is already in $all_hds

    my $base_mntpoint = $part->{mntpoint};
    my $check; $check = sub {
	my ($part, @seen) = @_;
	push @seen, $part->{mntpoint} || return;
	@seen > 1 && $part->{mntpoint} eq $base_mntpoint and die _("Circular mounts %s\n", join(", ", @seen));
	if (my $part = fs::up_mount_point($part->{mntpoint}, $fstab)) {
	    #- '/' carrier is a special case, it will be mounted first
	    $check->($part, @seen) if !carryRootLoopback($part);
	}
	if (isLoopback($part)) {
	    $check->($part->{loopback_device}, @seen);
	}
    };
    $check->($part) if !($base_mntpoint eq '/' && isLoopback($part)); #- '/' is a special case, no loop check
}

sub carryRootCreateSymlink {
    my ($part, $prefix) = @_;

    carryRootLoopback($part) or return;

    my $mntpoint = "$prefix$part->{mntpoint}";
    unless (-e $mntpoint) {
	eval { mkdir_p(dirname($mntpoint)) };
	#- do non-relative link for install, should be changed to relative link before rebooting
	symlink "/initrd/loopfs", $mntpoint;

	mkdir_p("/initrd/loopfs/lnx4win/boot");
	symlink "/initrd/loopfs/lnx4win/boot", "$prefix/boot";
    }
    #- indicate kernel to keep initrd
    mkdir "$prefix/initrd", 0755;
}


sub format_part {
    my ($part, $prefix) = @_;
    fs::mount_part($part->{loopback_device}, $prefix);
    create($part, $prefix);
    fs::real_format_part($part);
}

sub create {
    my ($part, $prefix) = @_;
    my $f = $part->{device} = "$prefix$part->{loopback_device}{mntpoint}$part->{loopback_file}";
    return if -e $f;

    eval { mkdir_p(dirname($f)) };

    log::l("creating loopback file $f ($part->{size} sectors)");

    local *F;
    my $block_size = 128;
    my $s = "\0" x (512 * $block_size);
    sysopen F, $f, 2 | c::O_CREAT() or die "failed to create loopback file";
    for (my $i = 0; $i < $part->{size}; $i += $block_size) {
	syswrite F, $s or die "failed to create loopback file";
    }
}

sub getFree {
    my ($dir, $part) = @_;
    my $freespace = $dir ? 
      2 * (MDK::Common::System::df($dir))[1] : #- df in KiB
      $part->{size};

    $freespace - sum map { $_->{size} } @{$part->{loopback} || []};
}

#- returns the size of the loopback file if it already exists
#- returns -1 is the loopback file can't be used
sub verifFile {
    my ($dir, $file, $part) = @_;
    -e "$dir$file" and return -s "$dir$file";

    $_->{loopback_file} eq $file and return -1 foreach @{$part->{loopback} || []};

    undef;
}

sub prepare_boot {
    my $r = readlink "$::prefix/boot"; 
    unlink "$::prefix/boot"; 
    mkdir "$::prefix/boot", 0755;
    [$r, $::prefix];
}

sub save_boot {
    my ($loop_boot, $prefix) = @{$_[0]};
    
    $loop_boot or return;

    my @files = glob_("$prefix/boot/*");
    cp_af(@files, $loop_boot) if @files;
    rm_rf("$prefix/boot");
    symlink $loop_boot, "$prefix/boot";
}


1;

