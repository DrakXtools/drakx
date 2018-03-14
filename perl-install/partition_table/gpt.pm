package partition_table::gpt;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use fs::type;
use partition_table::raw;
use c;

my $nb_primary = 128;

# See https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs for a list of exitings GUIDs

sub first_usable_sector { 34 }

sub last_usable_sector {
    my ($hd) = @_;
    #- do not use totalsectors because backup GPT is at end
    $hd->{totalsectors} - 33;
}

my %parted_mapping = (
   'linux-swap(v1)' => 'swap',
   'ntfs' => 'ntfs-3g',
   'fat16' => 'vfat',
   'fat32' => 'vfat',
   );
my %rev_parted_mapping = reverse %parted_mapping;
# prefer 'fat32' over 'fat16':
$rev_parted_mapping{vfat} = 'fat32';

sub read_one {
    my ($hd, $_sector) = @_;

    c::get_disk_type($hd->{file}) eq "gpt" or die "$hd->{device} not a GPT disk ($hd->{file})";

    my @pt;
    foreach (c::get_disk_partitions($hd->{file})) {
        # compatibility with MBR partitions tables:
        $_->{pt_type} = 0x82 if $_->{fs_type} eq 'swap';
        $_->{pt_type} = 0x0b if $_->{fs_type} eq 'vfat';
        $_->{pt_type} = 0x83 if $_->{fs_type} =~ /^ext/;

        # fix detecting ESP (special case are they're detected through pt_type):
        if ($_->{flag} eq 'ESP') {
	    $_->{pt_type} = 0xef;
        } elsif ($_->{flag} eq 'BIOS_GRUB') {
	    $_->{fs_type} = $_->{flag}; # hack to prevent it to land in hd->{raw}
	    $_->{pt_type} = $_->{flag}; # hack...
        } elsif ($_->{flag} eq 'LVM') {
	    $_->{pt_type} = 0x8e;
        } elsif ($_->{flag} eq 'RAID') {
	    $_->{pt_type} = 0xfd;
        } elsif ($_->{flag} eq 'RECOVERY') {
	    $_->{pt_type} = 0x12;
        }
        $_->{fs_type} = $parted_mapping{$_->{fs_type}} if $parted_mapping{$_->{fs_type}};

        @pt[$_->{part_number}-1] = $_;
    }

    for (my $part_number = 1; $part_number < $nb_primary; $part_number++) {
	next if exists($pt[$part_number-1]);
	$pt[$part_number-1] = { part_number => $part_number };
    }

    \@pt;
}

sub write {
    my ($hd, $_handle, $_sector, $pt, $_info) = @_;

    my $ped_disk;
    my $partitions_killed;

    # Initialize the disk if current partition table is not gpt
    if (c::get_disk_type($hd->{file}) ne "gpt") {
        $ped_disk = c::disk_open($hd->{file}, "gpt") or die "failed to create new partition table on $hd->{file}";
        $partitions_killed = 1;
    } else {
        $ped_disk = c::disk_open($hd->{file}) or die "failed to open partition table on $hd->{file}";
    }

    foreach (@{$hd->{will_tell_kernel}}) {
        my ($action, $part_number, $o_start, $o_size) = @$_;
        my ($part) = grep { $_->{start} == $o_start && $_->{size} == $o_size } @$pt;
        log::l("GPT partitioning: ($action, $part_number, $o_start, $o_size)");
        if ($action eq 'add') {
            local $part->{fs_type} = $rev_parted_mapping{$part->{fs_type}} if $rev_parted_mapping{$part->{fs_type}};
            c::disk_add_partition($ped_disk, $o_start, $o_size, $part->{fs_type}) or die "failed to add partition #$part_number on $hd->{file}";
	    my $flag;
	    if (isESP($part)) {
                $flag = 'ESP';
	    } elsif (isBIOS_GRUB($part)) {
                $flag = 'BIOS_GRUB';
	    } elsif (isRawLVM($part)) {
                $flag = 'LVM';
	    } elsif (isRawRAID($part)) {
                $flag = 'RAID';
	    }
	    if ($flag) {
	        c::set_partition_flag($ped_disk, $part_number, $flag)
	          or die "failed to set type '$flag' for $part->{file} on $part->{mntpoint}";
	    }
        } elsif ($action eq 'del' && !$partitions_killed) {
            c::disk_del_partition($ped_disk, $part_number) or die "failed to del partition #$part_number on $hd->{file}";
        } elsif ($action eq 'init' && !$partitions_killed) {
            c::disk_delete_all($ped_disk) or die "failed to delete all partitions on $hd->{file}";
        }
    }

    # Commit changes to the disk and inform the kernel
    my $commit_level = c::disk_commit($ped_disk);
    # Updating the kernel partition table will fail if any of the deleted partitions were mounted
    $hd->{rebootNeeded} = 1 if $commit_level < 2;
    $commit_level;
}

# Hint partition_table::write() that telling the kernel to reread the
# partition_table is not needed if we already succeeded in that:
sub need_to_tell_kernel {
    my ($hd) = @_;
    # If we failed, try again (partion_table::tell_kernel() will unmount some partitions first)
    $hd->{rebootNeeded};
}

sub initialize {
    my ($class, $hd) = @_;
    # part_number starts at 1
    my @raw = map { +{ part_number => $_ + 1 } } 0..$nb_primary-2;
    $hd->{primary} = { raw => \@raw };
    bless $hd, $class;
}

sub can_add { &can_raw_add }
sub adjustStart {}
sub adjustEnd {}

1;
