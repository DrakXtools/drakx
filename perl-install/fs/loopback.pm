package fs::loopback; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use fs;
use log;


sub check_circular_mounts {
    my ($part, $all_hds) = @_;

    my $fstab = [ fs::get::fstab($all_hds), $part ]; # no pb if $part is already in $all_hds

    my $base_mntpoint = $part->{mntpoint};
    my $check; $check = sub {
	my ($part, @seen) = @_;
	push @seen, $part->{mntpoint} || return;
	@seen > 1 && $part->{mntpoint} eq $base_mntpoint and die N("Circular mounts %s\n", join(", ", @seen));
	if (my $part = fs::get::up_mount_point($part->{mntpoint}, $fstab)) {
	    #- '/' carrier is a special case, it will be mounted first
	    $check->($part, @seen) if !fs::type::carry_root_loopback($part);
	}
	if (isLoopback($part)) {
	    $check->($part->{loopback_device}, @seen);
	}
    };
    $check->($part) if !($base_mntpoint eq '/' && isLoopback($part)); #- '/' is a special case, no loop check
}

sub carryRootCreateSymlink {
    my ($part) = @_;

    fs::type::carry_root_loopback($part) or return;

    my $mntpoint = fs::get::mntpoint_prefixed($part);
    unless (-e $mntpoint) {
	eval { mkdir_p(dirname($mntpoint)) };
	#- do non-relative link for install, should be changed to relative link before rebooting
	symlink "/initrd/loopfs", $mntpoint;

	mkdir_p("/initrd/loopfs/lnx4win/boot");
	symlink "/initrd/loopfs/lnx4win/boot", "$::prefix/boot";
    }
    #- indicate kernel to keep initrd
    mkdir_p("$::prefix/initrd");
}


sub format_part {
    my ($part) = @_;
    fs::mount::part($part->{loopback_device});
    create($part);
    fs::format::part_raw($part, undef);
}

sub create {
    my ($part) = @_;
    my $f = $part->{device} = fs::get::mntpoint_prefixed($part->{loopback_device}) . $part->{loopback_file};
    return if -e $f;

    eval { mkdir_p(dirname($f)) };

    log::l("creating loopback file $f ($part->{size} sectors)");

    my $block_size = 128;
    my $s = "\0" x (512 * $block_size);
    sysopen(my $F, $f, 2 | c::O_CREAT()) or die "failed to create loopback file";
    for (my $i = 0; $i < $part->{size}; $i += $block_size) {
	syswrite $F, $s or die "failed to create loopback file";
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
#- returns -1 is the loopback file can not be used
sub verifFile {
    my ($dir, $file, $part) = @_;
    -e "$dir$file" and return -s "$dir$file";

    $_->{loopback_file} eq $file and return -1 foreach @{$part->{loopback} || []};

    undef;
}

sub prepare_boot() {
    my $r = readlink "$::prefix/boot"; 
    unlink "$::prefix/boot"; 
    mkdir_p("$::prefix/boot");
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

