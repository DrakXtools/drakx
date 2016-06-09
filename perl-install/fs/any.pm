package fs::any;

use diagnostics;
use strict;

use c;
use common;
use fsedit;
use fs::get;
use fs::mount_point;
use fs::type;
use run_program;

sub get_hds {
    my ($all_hds, $fstab, $manual_fstab, $partitioning_flags, $skip_mtab, $o_in) = @_;

    my $probed_all_hds = fsedit::get_hds($partitioning_flags, $o_in);
    my $hds = $probed_all_hds->{hds};

    if (is_empty_array_ref($hds)) { #- no way
	die N("An error occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    #- try to figure out if the same number of hds is available, use them if ok.
    @{$all_hds->{hds} || []} == @$hds and return 1;

    fs::get_raw_hds('', $probed_all_hds);
    fs::add2all_hds($probed_all_hds, @$manual_fstab);

    %$all_hds = %$probed_all_hds;
    @$fstab = fs::get::really_all_fstab($all_hds);

    if (!$skip_mtab) {
        #- do not mount the windows partition
        fs::merge_info_from_mtab($fstab);
        fs::mount_point::suggest_mount_points_always($fstab);
    }

    1;
}

sub write_hds {
    my ($all_hds, $fstab, $set_mount_defaults, $on_reboot_needed, $opts) = @_;
    if (!$::testing) {
	my $hds = $all_hds->{hds};
	partition_table::write($_) foreach @$hds;
	$_->{rebootNeeded} and $on_reboot_needed->() foreach @$hds;
    }

    fs::set_removable_mntpoints($all_hds);
    fs::mount_options::set_all_default($all_hds, %$opts, lang::fs_options($opts->{locale}))
	if $set_mount_defaults;

    @$fstab = fs::get::fstab($all_hds);
}

sub set_cdrom_symlink {
    my ($raw_hds) = @_;

    foreach (grep { $_->{media_type} eq 'cdrom' } @$raw_hds) {
	next if $_->{device_alias};
	my $alias = basename($_->{mntpoint}) or next;
	log::l("using alias $alias for $_->{device}");
	$_->{device_alias} = $alias;
	symlink($_->{device}, "/dev/$alias");
    }
}

sub check_hds_boot_and_root {
    my ($all_hds, $fstab) = @_;
    fs::get::root_($fstab) or die "Oops, no root partition";

    if (is_uefi()) {
	if (!fs::get::has_mntpoint("/boot/EFI", $all_hds)) {
	    die N("You must have a ESP FAT32 partition mounted in /boot/EFI");
	}
    } else {
	if (is_boot_bios_part_needed($all_hds, $fstab)) {
	    die N("You must have a Boot BIOS partition");
	}
    }
}

sub create_minimal_files() {
    mkdir "$::prefix/$_", 0755 foreach 
      qw(dev etc etc/profile.d etc/rpm etc/sysconfig etc/sysconfig/console 
	etc/sysconfig/network-scripts etc/sysconfig/console/consolefonts 
	etc/sysconfig/console/consoletrans
	home mnt run tmp var var/tmp var/lib var/lib/rpm var/lib/urpmi);
    mkdir "$::prefix/$_", 0700 foreach qw(root root/tmp root/drakx);
}

sub prepare_minimal_root() {

    create_minimal_files();

    # ensure we've all needed devices, for bootloader install and mkinitrd:
    run_program::run('mount', '--bind', '/dev', "$::prefix/dev");
    run_program::run('mount', '--bind', '/run', "$::prefix/run");
    eval { fs::mount::mount('none', "$::prefix/proc", 'proc') };
    eval { fs::mount::mount('none', "$::prefix/sys", 'sysfs') };
    eval { fs::mount::sys_kernel_debug($::prefix) };
}

sub getNeededMinSpace {
    my ($n) = @_;

    #- make sure of this place to be available for installation, this could help a lot.
    #- currently doing a very small install use 36Mb of postinstall-rpm, but installing
    #- these packages may eat up to 90Mb (of course not all the server may be installed!).
    #- 65mb may be a good choice to avoid almost all problem of insuficient space left...
    my $minAvailableSize = 65 * sqr(1024);

    max(0.1 * $n, $minAvailableSize);
}

sub getAvailableSpace {
    my ($fstab, $o_skip_mounted, $o_skip_min_space) = @_;

    my $n = !$::testing && !$o_skip_mounted && getAvailableSpace_mounted($::prefix) || 
            getAvailableSpace_raw($fstab) * 512 / 1.07;
    $o_skip_min_space ? $n : $n - getNeededMinSpace($n);
}

sub getAvailableSpace_mounted {
    my ($prefix) = @_;
    my $dir = -d "$prefix/usr" ? "$prefix/usr" : $prefix;
    my (undef, $free) = MDK::Common::System::df($dir) or return;
    log::l("getAvailableSpace_mounted $free KB");
    $free * 1024 || 1;
}
sub getAvailableSpace_raw {
    my ($fstab) = @_;

    do { $_->{mntpoint} eq '/usr' and return $_->{size} } foreach @$fstab;
    do { $_->{mntpoint} eq '/'    and return $_->{size} } foreach @$fstab;

    if ($::testing) {
	my $nb = 450;
	log::l("taking ${nb}MB for testing");
	return MB($nb);
    }
    die "missing root partition";
}

=head3 is_boot_bios_part_needed($fstab)

Returns whether a Boot BIOS Partition is needed
(aka the device holding /boot is GPT partitionned but doesn't already have one).

=cut

sub is_boot_bios_part_needed {
    my ($all_hds, $fstab) = @_;
    # failsafe:
    return if is_uefi();
    return if !@$fstab;
    # mount point holding /boot:
    my $root = fs::get::root($fstab, 1);
    my $rootDev = $root->{rootDevice};
    my $boot_hd;
    if ($rootDev) {
	# is it GPT?
	return if c::get_disk_type($rootDev) ne 'gpt';
	($boot_hd) = find { $_->{device} eq $rootDev } fs::get::hds($all_hds);
    }
    # finally check if there's already a  Boot BIOS Partition:
    my @parts = map { partition_table::get_normal_parts($_) } $boot_hd || fs::get::hds($all_hds);
    return !any { isBIOS_GRUB($_) } @parts;
}

1;
