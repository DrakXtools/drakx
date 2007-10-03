package fs::any; # $Id$

use diagnostics;
use strict;

use common;
use fsedit;
use fs::mount_point;

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

sub set_cdrom_symlink_udev_rule {
    my ($raw_hds) = @_;

    my $cdrom_helper = '/lib/udev/cdrom_helper';
    -x "$::prefix$cdrom_helper" or return;

    my $udev_rule = "$::prefix/etc/udev/rules.d/61-block_config.rules";
    if (-e $udev_rule) {
	log::l("cleaning $udev_rule from previous cdrom symlink rules");
	substInFile { $_ = '' if /SYMLINK\+="cdrom/ } $udev_rule;
    }

    foreach (grep { $_->{media_type} eq 'cdrom' } @$raw_hds) {
	my @env = (
	    'SUBSYSTEM=block',
	    run_program::rooted_get_stdout($::prefix, '/lib/udev/path_id', "/block/$_->{device}"),
	    run_program::rooted_get_stdout($::prefix, '/lib/udev/cdrom_id', "/dev/$_->{device}"),
	);
	local %ENV = (%ENV, map { if_(/(.*?)=(.*)/, $1 => $2) } @env);

	log::l("calling $cdrom_helper with ID_PATH=$ENV{ID_PATH}");
	my ($alias) = run_program::rooted_get_stdout($::prefix, $cdrom_helper) =~ /(\w+)/;

	log::l("using alias $alias for $_->{device}");
	$_->{device_alias} = $alias;
	symlink($_->{device}, "$::prefix/dev/$alias");
    }
}

sub check_hds_boot_and_root {
    my ($all_hds, $fstab) = @_;
    fs::get::root_($fstab) or die "Oops, no root partition";

    if (arch() =~ /ppc/ && detect_devices::get_mac_generation() =~ /NewWorld/) {
	die "Need bootstrap partition to boot system!" if !(defined $partition_table::mac::bootstrap_part);
    }

    if (arch() =~ /ia64/ && !fs::get::has_mntpoint("/boot/efi", $all_hds)) {
	die N("You must have a FAT partition mounted in /boot/efi");
    }
}

1;
