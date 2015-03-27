package partition_table::gpt;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use fs::type;
use partition_table::raw;
use c;

my $nb_primary = 128;

my %_GUID_to_Label = (
  # No OS
  "00000000-0000-0000-0000-000000000000" => "Unused entry",
  "024DEE41-33E7-11D3-9D69-0008C781F39F" => "MBR partition scheme",
  "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" => "EFI System partition",
  "21686148-6449-6E6F-744E-656564454649" => "BIOS Boot partition",
  "D3BFE2DE-3DAF-11DF-BA40-E3A556D89593" => "Intel Fast Flash (iFFS) partition for Rapid Start (iRST)",
  "F4019732-066E-4E12-8273-346C5641494F" => "Sony boot partition",
  "BFBFAFE7-A34F-448A-9A5B-6213EB736C22" => "Lenovo boot partition",
  # Microsoft
  "E3C9E316-0B5C-4DB8-817D-F92DF00215AE" => "Microsoft Reserved Partition (MSR)",
  "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" => "Microsoft Basic data partition",
  "5808C8AA-7E8F-42E0-85D2-E1E90434CFB3" => "Microsoft Logical Disk Manager (LDM) metadata partition",
  "AF9B60A0-1431-4F62-BC68-3311714A69AD" => "Microsoft Logical Disk Manager data partition",
  "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC" => "Microsoft Windows Recovery Environment",
  "37AFFC90-EF7D-4E96-91C3-2D7AE055B174" => "Microsoft IBM General Parallel File System (GPFS) partition",
  "E75CAF8F-F680-4CEE-AFA3-B001E56EFC2D" => "Microsoft Storage Spaces partition",
  # HP-UX
  "75894C1E-3AEB-11D3-B7C1-7B03A0000000" => "HP-UX Data partition",
  "E2A1E728-32E3-11D6-A682-7B03A0000000" => "HP-UX Service Partition",
  # Linux
  "0FC63DAF-8483-4772-8E79-3D69D8477DE4" => "Linux filesystem data",
  "A19D880F-05FC-4D3B-A006-743F0F84911E" => "Linux RAID partition",
  "0657FD6D-A4AB-43C4-84E5-0933C84B4F4F" => "Linux Swap partition",
  "E6D6D379-F507-44C2-A23C-238F2A3DF928" => "Linux Logical Volume Manager (LVM) partition",
  "933AC7E1-2EB4-4F13-B844-0E14E2AEF915" => "Linux /home partition",
  "3B8F8425-20E0-4F3B-907F-1A25A76F98E8" => "Linux /srv (server data) partition",
  "7FFEC5C9-2D00-49B7-8941-3EA10A5586B7" => "Linux Plain dm-crypt partition",
  "CA7D7CCB-63ED-4C53-861C-1742536059CC" => "Linux LUKS partition",
  "8DA63339-0007-60C0-C436-083AC8230908" => "Linux Reserved",
  # FreeBSD
  "83BD6B9D-7F41-11DC-BE0B-001560B84F0F" => "FreeBSD Boot partition",
  "516E7CB4-6ECF-11D6-8FF8-00022D09712B" => "FreeBSD Data partition",
  "516E7CB5-6ECF-11D6-8FF8-00022D09712B" => "FreeBSD Swap partition",
  "516E7CB6-6ECF-11D6-8FF8-00022D09712B" => "FreeBSD Unix File System (UFS) partition",
  "516E7CB8-6ECF-11D6-8FF8-00022D09712B" => "FreeBSD Vinum volume manager partition",
  "516E7CBA-6ECF-11D6-8FF8-00022D09712B" => "FreeBSD ZFS partition",
  # Mac OSX
  "48465300-0000-11AA-AA11-00306543ECAC" => "Mac OSX Hierarchical File System Plus (HFS+) partition",
  "55465300-0000-11AA-AA11-00306543ECAC" => "Mac OSX Apple UFS",
  "6A898CC3-1DD2-11B2-99A6-080020736631" => "Mac OSX ZFS",
  "52414944-0000-11AA-AA11-00306543ECAC" => "Apple RAID partition",
  "52414944-5F4F-11AA-AA11-00306543ECAC" => "Apple RAID partition, offline",
  "426F6F74-0000-11AA-AA11-00306543ECAC" => "Apple Boot partition",
  "4C616265-6C00-11AA-AA11-00306543ECAC" => "Apple Label",
  "5265636F-7665-11AA-AA11-00306543ECAC" => "Apple TV Recovery partition",
  "53746F72-6167-11AA-AA11-00306543ECAC" => "Apple Core Storage (Lion FileVault) partition",
  # Solaris
  "6A82CB45-1DD2-11B2-99A6-080020736631" => "Solaris Boot partition",
  "6A85CF4D-1DD2-11B2-99A6-080020736631" => "Solaris Root partition",
  "6A87C46F-1DD2-11B2-99A6-080020736631" => "Solaris Swap partition",
  "6A8B642B-1DD2-11B2-99A6-080020736631" => "Solaris Backup partition",
  "6A898CC3-1DD2-11B2-99A6-080020736631" => "Solaris /usr partition",
  "6A8EF2E9-1DD2-11B2-99A6-080020736631" => "Solaris /var partition",
  "6A90BA39-1DD2-11B2-99A6-080020736631" => "Solaris /home partition",
  "6A9283A5-1DD2-11B2-99A6-080020736631" => "Solaris Alternate sector",
  "6A945A3B-1DD2-11B2-99A6-080020736631" => "Solaris Reserved partition",
  "6A9630D1-1DD2-11B2-99A6-080020736631" => "Solaris Reserved partition",
  "6A980767-1DD2-11B2-99A6-080020736631" => "Solaris Reserved partition",
  "6A96237F-1DD2-11B2-99A6-080020736631" => "Solaris Reserved partition",
  "6A8D2AC7-1DD2-11B2-99A6-080020736631" => "Solaris Reserved partition",
  # NetBSD
  "49F48D32-B10E-11DC-B99B-0019D1879648" => "NetBSD Swap partition",
  "49F48D5A-B10E-11DC-B99B-0019D1879648" => "NetBSD FFS partition",
  "49F48D82-B10E-11DC-B99B-0019D1879648" => "NetBSD LFS partition",
  "49F48DAA-B10E-11DC-B99B-0019D1879648" => "NetBSD RAID partition",
  "2DB519C4-B10F-11DC-B99B-0019D1879648" => "NetBSD Concatenated partition",
  "2DB519EC-B10F-11DC-B99B-0019D1879648" => "NetBSD Encrypted partition",
  # ChromeOS
  "FE3A2A5D-4F32-41A7-B725-ACCC3285A309" => "ChromeOS kernel",
  "3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC" => "ChromeOS rootfs",
  "2E0A753D-9E48-43B0-8337-B15192CB1B5E" => "ChromeOS future use",
  # Haiku
  "42465331-3BA3-10F1-802A-4861696B7521" => "Haiku BFS",
  # MidnightBSD
  "85D5E45E-237C-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD Boot partition",
  "85D5E45A-237C-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD Data partition",
  "85D5E45B-237C-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD Swap partition",
  "0394EF8B-237E-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD Unix File System (UFS) partition",
  "85D5E45C-237C-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD Vinum volume manager partition",
  "85D5E45D-237C-11E1-B4B3-E89A8F7FC3A7" => "MidnightBSD ZFS partition",
  # Ceph
  "BFBFAFE7-A34F-448A-9A5B-6213EB736C22" => "Ceph Journal",
  "45B0969E-9B03-4F30-B4C6-5EC00CEFF106" => "Ceph dm-crypt Encrypted Journal",
  "4FBD7E29-9D25-41B8-AFD0-062C0CEFF05D" => "Ceph OSD",
  "4FBD7E29-9D25-41B8-AFD0-5EC00CEFF05D" => "Ceph dm-crypt OSD",
  "89C57F98-2FE5-4DC0-89C1-F3AD0CEFF2BE" => "Ceph disk in creation",
  "89C57F98-2FE5-4DC0-89C1-5EC00CEFF2BE" => "Ceph dm-crypt disk in creation",
);

sub read_one {
    my ($hd, $_sector) = @_;

    c::get_disk_type($hd->{file}) eq "gpt" or die "$hd->{device} not a GPT disk ($hd->{file})";

    my @pt;
    # FIXME: just use '@pt = map { ... } c::...' if part_numbers are always linear:
    foreach (c::get_disk_partitions($hd->{file})) {
        # fix detecting ESP (special case are they're detected through pt_type):
        if (c::get_partition_flag($hd->{file}, $_->{part_number}, 'ESP')) {
	    $_->{pt_type} = 0xef;
        } elsif (c::get_partition_flag($hd->{file}, $_->{part_number}, 'LVM')) {
	    $_->{pt_type} = 0x8e;
        } elsif (c::get_partition_flag($hd->{file}, $_->{part_number}, 'RAID')) {
	    $_->{pt_type} = 0xfd;
        }
        $_->{fs_type} = 'swap' if $_->{fs_type} eq 'linux-swap(v1)';
        @pt[$_->{part_number}-1] = $_;
    }

    for (my $part_number = 1; $part_number < $nb_primary; $part_number++) {
	next if exists($pt[$part_number-1]);
	$pt[$part_number-1] = { part_number => $part_number };
    }

    \@pt;
}

sub write {
    my ($hd, $_sector, $pt, $_info) = @_;

    my $partitions_killed;

    # Initialize the disk if current partition table is not gpt
    if (c::get_disk_type($hd->{file}) ne "gpt") {
        c::set_disk_type($hd->{file}, "gpt");
        $partitions_killed = 1;
    }

    foreach (@{$hd->{will_tell_kernel}}) {
        my ($action, $part_number, $o_start, $o_size) = @$_;
        my ($part) = grep { $_->{start} == $o_start && $_->{size} == $o_size } @$pt;
        print "($action, $part_number, $o_start, $o_size)\n";
        if ($action eq 'add') {
            local $part->{fs_type} = 'linux-swap(v1)' if isSwap($part->{fs_type});
            local $part->{fs_type} = 'ntfs' if $part->{fs_type} eq 'ntfs-3g';
            c::disk_add_partition($hd->{file}, $o_start, $o_size, $part->{fs_type}) or die "failed to add partition #$part_number on $hd->{file}";
	    my $flag;
	    if (isESP($part)) {
                $flag = 'ESP';
	    } elsif (isRawLVM($part)) {
                $flag = 'LVM';
	    } elsif (isRawRAID($part)) {
                $flag = 'RAID';
	    }
	    if ($flag) {
	        c::set_partition_flag($hd->{file}, $part_number, $flag)
	          or die "failed to set type '$flag' for $part->{file} on $part->{mntpoint}";
	    }
        } elsif ($action eq 'del' && !$partitions_killed) {
            c::disk_del_partition($hd->{file}, $part_number) or die "failed to del partition #$part_number on $hd->{file}";
        }
    }
    common::sync();
    1;
}

sub initialize {
    my ($class, $hd) = @_;
    my @raw;
    for (my $part_number = 0; $part_number < $nb_primary-1; $part_number++) {
        # part_number starts at 1
        $raw[$part_number] = { part_number => $part_number + 1 };
    }
    $hd->{primary} = { raw => \@raw };
    bless $hd, $class;
}

sub can_add { &can_raw_add }
sub adjustStart {}
sub adjustEnd {}

1;
