package fs::type;

use diagnostics;
use strict;

use common;
use devices;


our @ISA = qw(Exporter);
our @EXPORT = qw(
   isEmpty isExtended isTrueLocalFS isTrueFS isDos isSwap isOtherAvailableFS isRawLVM isRawRAID isRawLUKS isRAID isLVM isLUKS isMountableRW isNonMountable isPartOfLVM isPartOfRAID isPartOfLoopback isLoopback isMounted isBusy isSpecial isApple isAppleBootstrap isESP isFat_or_NTFS isnormal_Fat_or_NTFS isRecovery
   maybeFormatted set_isFormatted defaultFS
);


my (%type_name2pt_type, %type_name2fs_type, %fs_type2pt_type, %pt_type2fs_type, %type_names);

{
    my @list_types = (
	important => [
  0x82 => 'swap',     'Linux swap',
  0x83 => 'ext2',     'Linux native (ext2)',
  0x83 => 'ext3',     'Journalised FS: ext3',
  0x83 => 'ext4',     'Journalised FS: ext4',
  0x83 => 'btrfs',    'Journalised FS: Btrfs',
if_(is_uefi(),
  0xef => 'vfat',     'EFI System Partition',
),
  0x83 => 'xfs',      'Journalised FS: XFS',
  0x83 => 'jfs',      'Journalised FS: JFS',
  0x0b => 'vfat',     'FAT32',
  0x07 => 'ntfs-3g',  'NTFS-3G',
  0x07 => 'ntfs',     'NTFS',
	],

        non_fs_type => [
  0x83 => '',         'Encrypted',
  0x8e => '',         'Linux Logical Volume Manager',
  0xfd => '',         'Linux RAID',
	],

	special => [
  0x0  => '',         'Empty',
  0x05 => '',         'Extended',
  0x0f => '',         'W95 Extended (LBA)',
  0x85 => '',         'Linux extended',
	],

	other => [
 if_(arch() =~ /^i.86|x86_64/,
  0x01 => 'vfat',     'FAT12',
  0x02 => '',         'XENIX root',
  0x03 => '',         'XENIX usr',
  0x04 => 'vfat',     'FAT16 <32M',
  0x06 => 'vfat',     'FAT16',
  0x07 => 'hpfs',     'HPFS',
  0x08 => '',         'AIX',
),
  0x09 => '',         'AIX bootable',
  0x0a => '',         'OS/2 Boot Manager',
  0x0c => 'vfat',     'W95 FAT32 (LBA)',
  0x0e => 'vfat',     'W95 FAT16 (LBA)',
  0x10 => '',         'OPUS',
  0x11 => '',         'Hidden FAT12',
  0x12 => '',         'Compaq diagnostics',
  0x14 => '',         'Hidden FAT16 <32M',
  0x16 => '',         'Hidden FAT16',
  0x17 => 'ntfs',     'Hidden HPFS/NTFS',
  0x18 => '',         'AST SmartSleep',
  0x1b => 'vfat',     'Hidden W95 FAT32',       # \ 
  0x1c => 'vfat',     'Hidden W95 FAT32 (LBA)', #  > don't change label, it's used to know if it's not a boot partition in bootloader.pm
  0x1e => 'vfat',     'Hidden W95 FAT16 (LBA)', # /
  0x24 => '',         'NEC DOS',
  0x39 => '',         'Plan 9',
  0x3c => '',         'PartitionMagic recovery',
  0x40 => '',         'Venix 80286',
  0x41 => '',         'PPC PReP Boot',
  0x42 => '',         'SFS',
  0x4d => '',         'QNX4.x',
  0x4e => '',         'QNX4.x 2nd part',
  0x4f => '',         'QNX4.x 3rd part',
  0x50 => '',         'OnTrack DM',
  0x51 => '',         'OnTrack DM6 Aux1',
  0x52 => '',         'CP/M',
  0x53 => '',         'OnTrack DM6 Aux3',
  0x54 => '',         'OnTrackDM6',
  0x55 => '',         'EZ-Drive',
  0x56 => '',         'Golden Bow',
  0x5c => '',         'Priam Edisk',
  0x61 => '',         'SpeedStor',
  0x63 => '',         'GNU HURD or SysV',
  0x64 => '',         'Novell Netware 286',
  0x65 => '',         'Novell Netware 386',
  0x70 => '',         'DiskSecure Multi-Boot',
  0x75 => '',         'PC/IX',
  0x80 => '',         'Old Minix',
  0x81 => '',         'Minix / old Linux',
  0x83 => 'reiserfs', 'Journalised FS: ReiserFS',
  0x83 => 'nilfs2',   'Journalised FS: NILFS2',
  0x84 => '',         'OS/2 hidden C: drive',
  0x86 => '',         'NTFS volume set (0x86)',
  0x87 => '',         'NTFS volume set (0x87)',
  0x93 => '',         'Amoeba',
  0x94 => '',         'Amoeba BBT',
  0x9f => '',         'BSD/OS',
  0xa0 => '',         'IBM Thinkpad hibernation',
  0xa5 => '',         'FreeBSD',
  0xa6 => '',         'OpenBSD',
  0xa7 => '',         'NeXTSTEP',
  0xa8 => '',         'Darwin UFS',
  0xa9 => '',         'NetBSD',
  0xab => '',         'Darwin boot',
  0xb7 => '',         'BSDI fs',
  0xb8 => '',         'BSDI swap',
  0xbb => '',         'Boot Wizard hidden',
  0xbe => '',         'Solaris boot',
  0xbf => '',         'Microsoft XBox OS Partitions',
  0xc1 => '',         'DRDOS/sec (FAT-12)',
  0xc4 => '',         'DRDOS/sec (FAT-16 < 32M)',
  0xc6 => '',         'DRDOS/sec (FAT-16)',
  0xc7 => '',         'Syrinx',
  0xda => '',         'Non-FS data',
  0xdb => '',         'CP/M / CTOS / ...',
  0xde => '',         'Dell Utility',
  0xdf => '',         'BootIt',
  0xe1 => '',         'SpeedStor (FAT-12)',
  0xe3 => '',         'DOS R/O',
  0xe4 => '',         'SpeedStor (FAT-16)',
  0xeb => 'befs',     'BeOS fs',
  0xee => '',         'EFI GPT',
  0xf0 => '',         'Linux/PA-RISC boot',
  0xf4 => '',         'SpeedStor (large part.)',
  0xf2 => '',         'DOS secondary',
  0xfe => '',         'LANstep',
  0xff => '',         'BBT',
	],
    );

    foreach (group_by2(@list_types)) {
	my ($name, $l) = @$_;
	for (my $i = 0; defined $l->[$i]; $i += 3) {
	    my $pt_type   = $l->[$i];
	    my $fs_type   = $l->[$i + 1];
	    my $type_name = $l->[$i + 2];
	    !exists $type_name2fs_type{$type_name} or internal_error("'$type_name' is not unique");
	    $type_name2fs_type{$type_name} = $fs_type;
	    $type_name2pt_type{$type_name} = $pt_type;

	    $fs_type2pt_type{$fs_type} ||= $pt_type;
	    $pt_type2fs_type{$pt_type} ||= $fs_type;
	    push @{$type_names{$name}}, $type_name;
	}
    }
}


sub type_names { 
    my ($expert, $o_hd) = @_;
    my @l = @{$type_names{important}};
    push @l, grep { $_ ne 'Encrypted' } @{$type_names{non_fs_type}};
    push @l, sort @{$type_names{other}} if $expert;
    if ($o_hd && !$o_hd->use_pt_type) {
	@l = grep { $type_name2fs_type{$_} } @l;
	@l = uniq_ { $type_name2fs_type{$_} } @l;
	(@l, @{$type_names{non_fs_type}});
    } else {
	@l;
    }
}

sub type_name2subpart {
    my ($name) = @_;
    exists $type_name2fs_type{$name} && 
      { type_name => $name,
	fs_type => $type_name2fs_type{$name}, pt_type => $type_name2pt_type{$name} };
}

sub part2type_name { 
    my ($part) = @_;
    my @names = keys %type_name2fs_type;
   
    my $pt_type = defined $part->{pt_type} ? $part->{pt_type} : $part->{fs_type} && $fs_type2pt_type{$part->{fs_type}};
    if (defined $pt_type) {
	@names = grep { $pt_type eq $type_name2pt_type{$_} } @names;
    }
    if (my $fs_type = $part->{fs_type} || $part->{pt_type} && $pt_type2fs_type{$part->{pt_type}}) {
	@names = grep { $fs_type eq $type_name2fs_type{$_} } @names;
    }
    if (@names > 1) {
	log::l("ERROR: (part2type_name) multiple match for $part->{pt_type} $part->{fs_type}");
    }
    first(@names);
}
sub type_name2pt_type { 
    local ($_) = @_;
    /0x(.*)/ ? hex $1 : $type_name2pt_type{$_} || $_;
}


sub pt_type2subpart {
    my ($pt_type) = @_;
    my $fs_type = $pt_type2fs_type{$pt_type};
    { pt_type => $pt_type, if_($fs_type, fs_type => $fs_type) };
}
sub fs_type2subpart {
    my ($fs_type) = @_;
    my $pt_type = $fs_type2pt_type{$fs_type};
    { fs_type => $fs_type, if_($pt_type, pt_type => $pt_type) };
}
sub set_fs_type {
    my ($part, $fs_type) = @_;
    put_in_hash($part, fs_type2subpart($fs_type));
}
sub set_pt_type {
    my ($part, $pt_type) = @_;
    put_in_hash($part, pt_type2subpart($pt_type));
}
sub suggest_fs_type {
    my ($part, $fs_type) = @_;
    set_fs_type($part, $fs_type) if !$part->{pt_type} && !$part->{fs_type};
}
sub set_type_subpart {
    my ($part, $subpart) = @_;
    if (exists $subpart->{pt_type} && exists $subpart->{fs_type}) {
	$part->{fs_type} = $subpart->{fs_type};
	$part->{pt_type} = $subpart->{pt_type};
    } elsif (exists $subpart->{pt_type}) {
	set_pt_type($part, $subpart->{pt_type});
    } elsif (exists $subpart->{fs_type}) {
	set_fs_type($part, $subpart->{fs_type});
    } else {
	log::l("ERROR: (set_type_subpart) subpart has no type");
    }
}

sub fs_type_from_magic {
    my ($part) = @_;
    if (exists $part->{fs_type_from_magic}) {
	$part->{fs_type_from_magic};
    } else {
	my $type = type_subpart_from_magic($part);
	$type && $type->{fs_type};
    }
}

sub call_blkid {
    my ($part) = @_;

    # IMPORTANT: Always use the -p argument with blkid. See r7324 commit msg
    my %h = map {
	if_(/(.*?)=(.*)/, $1 => $2);
    } run_program::get_stdout_raw({ timeout => 30 }, 'blkid', '2>', '/dev/null', '-o', 'udev', '-p', devices::make($part->{device}));

    \%h;
}

sub type_subpart_from_magic { 
    my ($part) = @_;
    my $ids = call_blkid($part);

    my $p;
    if ($ids->{ID_FS_USAGE} eq 'raid') {
	my $name = {
	    linux_raid_member => "Linux RAID",
	    LVM1_member => 'Linux Logical Volume Manager',
	    LVM2_member => 'Linux Logical Volume Manager',
	}->{$ids->{ID_FS_TYPE}};

	$p = type_name2subpart($name) if $name;
    } elsif ($ids->{ID_FS_USAGE} eq 'crypto') {
	$p = type_name2subpart('Encrypted');
    } elsif (my $fs_type = $ids->{ID_FS_TYPE}) {
	$fs_type = 'ntfs-3g' if $fs_type eq 'ntfs';
	$p = fs_type2subpart($fs_type) or log::l("unknown filesystem $fs_type returned by blkid");
    }

    if ($p) {
	$part->{fs_type_from_magic} = $p->{fs_type};
	$p->{device_LABEL} = $ids->{ID_FS_LABEL} if $ids->{ID_FS_LABEL};
	$p->{device_UUID} = $ids->{ID_FS_UUID} if $ids->{ID_FS_UUID};
	log::l("blkid gave: $p->{fs_type} $p->{device_UUID} $p->{device_LABEL}");
    }
    $p;
}

sub defaultFS() { 'ext4' }

sub true_local_fs_types() { qw(btrfs ext3 ext2 ext4 reiserfs xfs jfs) }

sub isEmpty { !$_[0]{fs_type} && $_[0]{pt_type} == 0 }
sub isESP { $_[0]{pt_type} == 0xef }
sub isExtended { $_[0]{pt_type} == 5 || $_[0]{pt_type} == 0xf || $_[0]{pt_type} == 0x85 }
sub isRawLVM { $_[0]{pt_type} == 0x8e || $_[0]{type_name} eq 'Linux Logical Volume Manager' }
sub isRawRAID { $_[0]{pt_type} == 0xfd || $_[0]{type_name} eq 'Linux RAID' }
sub isRawLUKS { $_[0]{type_name} eq 'Encrypted' }
sub isSwap { $_[0]{fs_type} eq 'swap' }
sub isDos { ${{ 1 => 1, 4 => 1, 6 => 1 }}{$_[0]{pt_type}} }
sub isFat_or_NTFS { member($_[0]{fs_type}, 'vfat', 'ntfs', 'ntfs-3g') }
sub isnormal_Fat_or_NTFS { grep { isFat_or_NTFS($_) && !isESP($_) && !isRecovery($_) } @_ }
sub isApple { $_[0]{pt_type} == 0x401 && defined $_[0]{isDriver} }
sub isAppleBootstrap { $_[0]{pt_type} == 0x401 && defined $_[0]{isBoot} }
sub isRecovery { 
    isFat_or_NTFS($_[0]) && ($_[0]{type_name} =~ /^Hidden/ ||
      $_[0]{pt_type} == 0x12 || # "Compaq diagnostics"
        member($_[0]{device_LABEL} , 
            # Extracted from /usr/lib/udev/rules.d/80-udisks2.rules
            # Hopefuly we'll ask to udev/udisk2 someday
            # generated by grep Recovery /usr/lib/udev/rules.d/80-udisks2.rules :
            qw(Recovery RECOVERY Lenovo_Recovery HP_RECOVERY Recovery_Partition DellUtility DellRestore IBM_SERVICE SERVICEV001 SERVICEV002 SYSTEM_RESERVED System_Reserved WINRE_DRV DIAGS IntelRST),
            # gathered over the years (Hald, mga#1371, mga#15999):
            qw(PQSERVICE Packard_Bell Push_Button_Reset SYSTEM_DRV))
    );
}

sub isTrueFS { isTrueLocalFS($_[0]) || member($_[0]{fs_type}, qw(nfs)) }
sub isTrueLocalFS { member($_[0]{fs_type}, true_local_fs_types()) }

sub isOtherAvailableFS { isESP($_[0]) || isFat_or_NTFS($_[0]) || member($_[0]{fs_type}, 'ufs', 'hfs', 'iso9660') } #- other OS that linux can access its filesystem
sub isMountableRW { (isTrueFS($_[0]) || isOtherAvailableFS($_[0])) && $_[0]{fs_type} ne 'ntfs' }
sub cannotBeMountable { 
    my ($part) = @_;
    isRawRAID($part) || isRawLUKS($part) || isRawLVM($part);
}
sub isNonMountable { 
    my ($part) = @_;
    cannotBeMountable($part) || $part->{fs_type} eq 'ntfs' && !$part->{isFormatted} && $part->{notFormatted};
}

sub isPartOfLVM { defined $_[0]{lvm} }
sub isPartOfRAID { defined $_[0]{raid} }
sub isPartOfLoopback { defined $_[0]{loopback} }
sub isRAID { $_[0]{device} =~ /^md/ && defined $_[0]{level} }
sub isUBD { $_[0]{device} =~ /^ubd/ } #- should be always true during an $::uml_install
sub isLVM { $_[0]{VG_name} || $_[0]{lv_name} }
sub isLUKS { defined $_[0]{dmcrypt_name} }
sub isLoopback { defined $_[0]{loopback_file} }
sub isMounted { $_[0]{isMounted} }
sub isBusy { isMounted($_[0]) || isPartOfRAID($_[0]) || isPartOfLVM($_[0]) || $_[0]{dm_active} || isPartOfLoopback($_[0]) }
sub isSpecial { isRAID($_[0]) || isLVM($_[0]) || isLoopback($_[0]) || isUBD($_[0]) }

#- not for partitions, but for hds:
sub is_dmraid { $_[0]{bus} =~ /^dmraid_/ }

sub can_be_this_fs_type {
    my ($part, $fs_type) = @_;
    can_be_one_of_those_fs_types($part, $fs_type);
}
sub can_be_one_of_those_fs_types {
    my ($part, @fs_types) = @_;
    $part->{fs_type} or return;
    $part->{fs_type} eq 'auto' || listlength(intersection(\@fs_types, [ split(':', $part->{fs_type}) ]));
}

sub maybeFormatted { 
    my ($part) = @_;
    $part->{isFormatted} || !$part->{notFormatted} && (!$part->{bad_fs_type_magic} || $part->{options} =~ /encrypted/);
}
sub set_isFormatted {
    my ($part, $val) = @_;
    $part->{isFormatted} = $val;
    $part->{notFormatted} = !$val;
    delete $part->{bad_fs_type_magic};
    delete $part->{fs_type_from_magic};
}

#- do this before modifying $part->{fs_type}
sub check {
    my ($fs_type, $_hd, $part) = @_;
    $fs_type eq "jfs" && $part->{size} < MB(16) and die N("You cannot use JFS for partitions smaller than 16MB");
    $fs_type eq "reiserfs" && $part->{size} < MB(32) and die N("You cannot use ReiserFS for partitions smaller than 32MB");
    $fs_type eq "btrfs" && $part->{size} < MB(256) and die N("You cannot use btrfs for partitions smaller than 256MB");
}

sub guessed_by_mount() {
    grep { $_ && !/nodev/ } chomp_(cat_('/etc/filesystems'));
}

sub directories_needed_to_boot_not_ESP() {
    qw(/ /usr /var /boot /tmp);
}
sub directories_needed_to_boot() { 
    directories_needed_to_boot_not_ESP(), '/boot/EFI';
}

sub carry_root_loopback {
    my ($part) = @_;
    any { $_->{mntpoint} eq '/' } @{$part->{loopback} || []};
}

1;
