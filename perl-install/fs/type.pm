package fs::type; # $Id$

use diagnostics;
use strict;

use common;


our @ISA = qw(Exporter);
our @EXPORT = qw(
   isExtended isTrueLocalFS isTrueFS isDos isSwap isSunOS isOtherAvailableFS isRawLVM isRawRAID isRAID isLVM isMountableRW isNonMountable isPartOfLVM isPartOfRAID isPartOfLoopback isLoopback isMounted isBusy isSpecial isApple isAppleBootstrap isWholedisk isHiddenMacPart isFat_or_NTFS
   maybeFormatted set_isFormatted
);


my (%type_name2pt_type, %type_name2fs_type, %fs_type2pt_type, %pt_type2fs_type, %type_names);

{
    my @list_types = (
	important => [
  0x82 => 'swap',     'Linux swap',
  0x83 => 'ext2',     'Linux native',
  0x83 => 'ext3',     'Journalised FS: ext3',
  0x83 => 'reiserfs', 'Journalised FS: ReiserFS',
if_(arch() =~ /ppc|i.86|ia64|x86_64/, 
  0x83 => 'xfs',      'Journalised FS: XFS',
),
if_(arch() =~ /ppc|i.86/, 
  0x83 => 'jfs',      'Journalised FS: JFS',
),
if_(arch() =~ /i.86|ia64|x86_64/,
  0x0b => 'vfat',     'FAT32',
),
if_(arch() =~ /ppc/,
  0x401	=> 'apple',    'Apple Bootstrap',
  0x402	=> 'hfs',      'Apple HFS Partition',
  0x41  => '',         'PPC PReP Boot',
),
	],

        less_important => [
  0x8e => '',         'Linux Logical Volume Manager',
  0xfd => '',         'Linux RAID',
	],

	special => [
  0x0  => '',         'Empty',
  0x05 => '',         'Extended',
  0x0f => '',         'W95 Extended (LBA)',
  0x85 => '',         'Linux extended',
	],

        backward_compatibility => [
  0x183 => 'reiserfs', 'reiserfs (deprecated)',
  0x283 => 'xfs',      'xfs (deprecated)',
  0x383 => 'jfs',      'jfs (deprecated)',
  0x483 => 'ext3',     'ext3 (deprecated)',
	],

	other => [
 if_(arch() =~ /^ia64/,
  0x100 => '',         'Various',
), if_(arch() =~ /^ppc/,
  0x401	=> 'apple',    'Apple Partition',
), if_(arch() =~ /^sparc/,
  0x01 => 'ufs',      'SunOS boot',
  0x02 => 'ufs',      'SunOS root',
  0x03 => 'ufs',      'SunOS swap',
  0x04 => 'ufs',      'SunOS usr',
  0x05 => 'ufs',      'Whole disk',
  0x06 => 'ufs',      'SunOS stand',
  0x07 => 'ufs',      'SunOS var',
  0x08 => 'ufs',      'SunOS home',
), if_(arch() =~ /^i.86/,
  0x01 => 'vfat',     'FAT12',
  0x02 => '',         'XENIX root',
  0x03 => '',         'XENIX usr',
  0x04 => 'vfat',     'FAT16 <32M',
  0x06 => 'vfat',     'FAT16',
  0x07 => (arch() =~ /^ppc/ ? 'hpfs' : 'ntfs'), 'NTFS (or HPFS)',
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
  0x1b => 'vfat',     'Hidden W95 FAT32',
  0x1c => 'vfat',     'Hidden W95 FAT32 (LBA)',
  0x1e => 'vfat',     'Hidden W95 FAT16 (LBA)',
  0x24 => '',         'NEC DOS',
  0x39 => '',         'Plan 9',
  0x3c => '',         'PartitionMagic recovery',
  0x40 => '',         'Venix 80286',
if_(arch() !~ /ppc/,
  0x41 => '',         'PPC PReP Boot',
),
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
  0x84 => '',         'OS/2 hidden C: drive',
  0x86 => '',         'NTFS volume set',
  0x87 => '',         'NTFS volume set ',
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
  0xef => 'vfat',     'EFI (FAT-12/16/32)',
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


sub type_names() { 
    my @l = @{$type_names{important}};
    push @l, @{$type_names{less_important}}, sort @{$type_names{other}} if $::expert;
    @l;
}

sub type_name2subpart {
    my ($name) = @_;
    exists $type_name2fs_type{$name} && 
      { fs_type => $type_name2fs_type{$name}, pt_type => $type_name2pt_type{$name} };
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


my @partitions_signatures = (
    (map { [ 'Linux Logical Volume Manager', 0x200 * $_ + 0x18, "LVM2" ] } 0 .. 3),
    [ 'Linux Logical Volume Manager', 0, "HM\1\0" ],
    [ 'ext2', 0x438, "\x53\xEF" ],
    [ 'reiserfs', 0x10034, "ReIsErFs" ],
    [ 'reiserfs', 0x10034, "ReIsEr2Fs" ],
    [ 'xfs', 0, 'XFSB', 0x200, 'XAGF', 0x400, 'XAGI' ],
    [ 'jfs', 0x8000, 'JFS1' ],
    [ 'swap', 4086, "SWAP-SPACE" ],
    [ 'swap', 4086, "SWAPSPACE2" ],
    [ 'ntfs', 0x1FE, "\x55\xAA", 0x3, "NTFS" ],
    [ 'FAT32',  0x1FE, "\x55\xAA", 0x52, "FAT32" ],
if_(arch() !~ /^sparc/,
    [ 'FAT16',  0x1FE, "\x55\xAA", 0x36, "FAT" ],
),
);

sub fs_type_from_magic {
    my ($part) = @_;
    if (exists $part->{fs_type_from_magic}) {
	$part->{fs_type_from_magic};
    } else {
	my $type = type_subpart_from_magic($part);
	$type && $type->{fs_type};
    }
}

sub type_subpart_from_magic { 
    my ($part) = @_;
    my $dev = devices::make($part->{device});

    my $check_md = sub {
	my ($F) = @_;
	my $MD_RESERVED_SECTORS = 128;
	my $sector = round_down($part->{size}, $MD_RESERVED_SECTORS) - $MD_RESERVED_SECTORS; #- MD_NEW_SIZE_SECTORS($part->{size})
	if (c::lseek_sector(fileno $F, $sector, 0)) {
	    my $tmp;
	    my $signature = "\xfc\x4e\x2b\xa9";
	    sysread($F, $tmp, length $signature);
	    $tmp eq $signature and return "Linux RAID";
	}
	'';
    };
    my $t = typeFromMagic($dev, 
			  if_($part->{size}, $check_md),
			  @partitions_signatures) or return;

    my $p = type_name2subpart($t) || fs_type2subpart($t) || internal_error("unknown name/fs $t");
    if ($p->{fs_type} eq 'ext2') {
	#- there is no magic to differentiate ext3 and ext2. Using libext2fs
	#- to check if it has a journal
	$p->{fs_type} = 'ext3' if c::is_ext3($dev);
    }
    $part->{fs_type_from_magic} = $p->{fs_type};
    $p;
}


sub isEfi { arch() =~ /ia64/ && $_[0]{pt_type} == 0xef }
sub isWholedisk { arch() =~ /^sparc/ && $_[0]{pt_type} == 5 }
sub isExtended { arch() !~ /^sparc/ && ($_[0]{pt_type} == 5 || $_[0]{pt_type} == 0xf || $_[0]{pt_type} == 0x85) }
sub isRawLVM { $_[0]{pt_type} == 0x8e }
sub isRawRAID { $_[0]{pt_type} == 0xfd }
sub isSwap { $_[0]{fs_type} eq 'swap' }
sub isDos { arch() !~ /^sparc/ && ${{ 1 => 1, 4 => 1, 6 => 1 }}{$_[0]{pt_type}} }
sub isFat_or_NTFS { member($_[0]{fs_type}, 'vfat', 'ntfs') }
sub isSunOS { arch() =~ /sparc/ && ${{ 0x1 => 1, 0x2 => 1, 0x4 => 1, 0x6 => 1, 0x7 => 1, 0x8 => 1 }}{$_[0]{pt_type}} }
sub isApple { $_[0]{fs_type} eq 'apple' && defined $_[0]{isDriver} }
sub isAppleBootstrap { $_[0]{fs_type} eq 'apple' && defined $_[0]{isBoot} }
sub isHiddenMacPart { defined $_[0]{isMap} }

sub isTrueFS { isTrueLocalFS($_[0]) || member($_[0]{fs_type}, qw(nfs)) }
sub isTrueLocalFS { member($_[0]{fs_type}, qw(ext2 reiserfs xfs jfs ext3)) }

sub isOtherAvailableFS { isEfi($_[0]) || isFat_or_NTFS($_[0]) || isSunOS($_[0]) || $_[0]{fs_type} eq 'hfs' } #- other OS that linux can access its filesystem
sub isMountableRW { (isTrueFS($_[0]) || isOtherAvailableFS($_[0])) && $_[0]{fs_type} ne 'ntfs' }
sub isNonMountable { 
    my ($part) = @_;
    isRawRAID($part) || isRawLVM($part) || $part->{fs_type} eq 'ntfs' && !$part->{isFormatted} && $part->{notFormatted};
}

sub isPartOfLVM { defined $_[0]{lvm} }
sub isPartOfRAID { defined $_[0]{raid} }
sub isPartOfLoopback { defined $_[0]{loopback} }
sub isRAID { $_[0]{device} =~ /^md/ }
sub isUBD { $_[0]{device} =~ /^ubd/ } #- should be always true during an $::uml_install
sub isLVM { $_[0]{VG_name} }
sub isLoopback { defined $_[0]{loopback_file} }
sub isMounted { $_[0]{isMounted} }
sub isBusy { isMounted($_[0]) || isPartOfRAID($_[0]) || isPartOfLVM($_[0]) || isPartOfLoopback($_[0]) }
sub isSpecial { isRAID($_[0]) || isLVM($_[0]) || isLoopback($_[0]) || isUBD($_[0]) }

sub can_be_this_fs_type {
    my ($part, $fs_type) = @_;
    $part->{fs_type} && ($part->{fs_type} eq 'auto' || member($fs_type, split(':', $part->{fs_type})));
}

sub maybeFormatted { 
    my ($part) = @_;
    $part->{isFormatted} || !$part->{notFormatted} && !$part->{bad_fs_type_magic};
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
    $fs_type eq "jfs" && $part->{size} < 16 << 11 and die N("You can't use JFS for partitions smaller than 16MB");
    $fs_type eq "reiserfs" && $part->{size} < 32 << 11 and die N("You can't use ReiserFS for partitions smaller than 32MB");
}
