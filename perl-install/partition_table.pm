package partition_table; # $Id$

#use diagnostics;
#use strict;
#use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @important_types @important_types2 @fields2save);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    types => [ qw(type2name type2fs name2type fs2type isExtended isExt2 isReiserfs isXfs isTrueFS isSwap isDos isWin isFat isSunOS isOtherAvailableFS isPrimary isNfs isSupermount isLVM isRAID isMDRAID isLVMBased isHFS isNT isMountableRW isNonMountable isApplePartMap isLoopback isApple isAppleBootstrap) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


use common qw(:common :system :functional);
use partition_table_raw;
use log;

if (arch() =~ /ppc/) {
    @important_types = ('Linux native', 'Linux swap', 'Apple HFS Partition', 'Apple Bootstrap');
} else {
	@important_types = ('Linux native', 'Linux swap', if_(arch() =~ /i.86/, 'ReiserFS', 'DOS FAT16', 'Win98 FAT32'));
}
@important_types2 = ('Linux RAID', 'Linux Logical Volume Manager partition');

@fields2save = qw(primary extended totalsectors isDirty needKernelReread);

@bad_types = ('Empty', 'DOS 3.3+ Extended Partition', 'Win95: Extended partition, LBA-mapped', 'Linux extended partition');

my %types = (
  0x0 => 'Empty',
arch() =~ /^ppc/ ? (
  0x401	=> 'Apple Partition',
  0x401	=> 'Apple Bootstrap',
  0x402	=> 'Apple HFS Partition',
) : arch() =~ /^i.86/ ? (
  0x183 => 'ReiserFS',
  0x283 => 'XFS',
) : arch() =~ /^sparc/ ? (
  0x1 => 'SunOS boot',
  0x2 => 'SunOS root',
  0x3 => 'SunOS swap',
  0x4 => 'SunOS usr',
  0x5 => 'Whole disk',
  0x6 => 'SunOS stand',
  0x7 => 'SunOS var',
  0x8 => 'SunOS home',
) : (
  0x1 => 'DOS 12-bit FAT',
  0x2 => 'XENIX root',
  0x3 => 'XENIX /usr',
  0x4 => 'DOS 16-bit FAT (up to 32M)',
  0x5 => 'DOS 3.3+ Extended Partition',
  0x6 => 'DOS FAT16',
  0x7 => 'NTFS (or HPFS)',
  0x8 => 'OS/2 (v1.0-1.3 only) / AIX boot partition / SplitDrive / Commodore DOS / DELL partition spanning multiple drives / QNX 1.x and 2.x ("qny")',
),
  0x9 => 'AIX data partition / Coherent filesystem / QNX 1.x and 2.x ("qnz")',
  0xa => 'OS/2 Boot Manager / Coherent swap partition / OPUS',
  0xb => 'Win98 FAT32',
  0xc => 'Win98 FAT32, LBA-mapped',
  0xe => 'Win95: DOS 16-bit FAT, LBA-mapped',
  0xf => 'Win95: Extended partition, LBA-mapped',
  0x10 => 'OPUS (?)',
  0x11 => 'Hidden DOS 12-bit FAT',
  0x12 => 'Compaq/HP config partition',
  0x14 => 'Hidden DOS 16-bit FAT <32M',
  0x16 => 'Hidden DOS 16-bit FAT >=32M',
  0x17 => 'Hidden IFS (e.g., HPFS)',
  0x18 => 'AST Windows swapfile',
  0x1b => 'Hidden WIN95 OSR2 32-bit FAT',
  0x1c => 'Hidden WIN95 OSR2 32-bit FAT, LBA-mapped',
  0x1e => 'Hidden FAT95',
  0x22 => 'Used for Oxygen Extended Partition Table by ekstazya@sprint.ca.',
  0x24 => 'NEC DOS 3.x',
  0x38 => 'THEOS ver 3.2 2gb partition',
  0x39 => 'THEOS ver 4 spanned partition',
  0x3a => 'THEOS ver 4 4gb partition',
  0x3b => 'THEOS ver 4 extended partition',
  0x3c => 'PartitionMagic recovery partition',
  0x40 => 'Venix 80286',
  0x41 => 'Linux/MINIX (sharing disk with DRDOS) / Personal RISC Boot / PPC PReP (Power PC Reference Platform) Boot',
  0x42 => 'Linux swap (sharing disk with DRDOS) / SFS (Secure Filesystem) / W2K marker',
  0x43 => 'Linux native (sharing disk with DRDOS)',
  0x45 => 'EUMEL/Elan',
  0x46 => 'EUMEL/Elan 0x46',
  0x47 => 'EUMEL/Elan 0x47',
  0x48 => 'EUMEL/Elan 0x48',
  0x4d => 'QNX4.x',
  0x4e => 'QNX4.x 2nd part',
  0x4f => 'QNX4.x 3rd part / Oberon partition',
  0x50 => 'OnTrack Disk Manager (older versions) RO',
  0x51 => 'OnTrack Disk Manager RW (DM6 Aux1) / Novell',
  0x52 => 'CP/M / Microport SysV/AT',
  0x53 => 'Disk Manager 6.0 Aux3',
  0x54 => 'Disk Manager 6.0 Dynamic Drive Overlay',
  0x55 => 'EZ-Drive',
  0x56 => 'Golden Bow VFeature Partitioned Volume. / DM converted to EZ-BIOS',
  0x57 => 'DrivePro',
  0x5c => 'Priam EDisk',
  0x61 => 'SpeedStor',
  0x63 => 'Unix System V (SCO, ISC Unix, UnixWare, ...), Mach, GNU Hurd',
  0x64 => 'PC-ARMOUR protected partition / Novell Netware 2.xx',
  0x65 => 'Novell Netware 3.xx or 4.xx',
  0x67 => 'Novell',
  0x68 => 'Novell 0x68',
  0x69 => 'Novell 0x69',
  0x70 => 'DiskSecure Multi-Boot',
  0x75 => 'IBM PC/IX',
  0x80 => 'MINIX until 1.4a',
  0x81 => 'MINIX since 1.4b, early Linux / Mitac disk manager',
  0x82 => 'Linux swap',
  0x83 => 'Linux native',
  0x84 => 'OS/2 hidden C: drive / Hibernation partition',
  0x85 => 'Linux extended partition',
  0x86 => 'Old Linux RAID partition superblock / NTFS volume set',
  0x87 => 'NTFS volume set',
  0x8a => 'Linux Kernel Partition (used by AiR-BOOT)',
  0x8e => 'Linux Logical Volume Manager partition',
  0x93 => 'Amoeba',
  0x94 => 'Amoeba bad block table',
  0x99 => 'DCE376 logical drive',
  0xa0 => 'IBM Thinkpad hibernation partition / Phoenix NoteBIOS Power Management "Save-to-Disk" partition',
  0xa5 => 'BSD/386, 386BSD, NetBSD, FreeBSD',
  0xa6 => 'OpenBSD',
  0xa7 => 'NEXTSTEP',
  0xa9 => 'NetBSD',
  0xaa => 'Olivetti Fat 12 1.44Mb Service Partition',
  0xb7 => 'BSDI filesystem',
  0xb8 => 'BSDI swap partition',
  0xbe => 'Solaris boot partition',
  0xc0 => 'CTOS / REAL/32 secure small partition',
  0xc1 => 'DRDOS/secured (FAT-12)',
  0xc4 => 'DRDOS/secured (FAT-16, < 32M)',
  0xc6 => 'DRDOS/secured (FAT-16, >= 32M) / Windows NT corrupted FAT16 volume/stripe set',
  0xc7 => 'Windows NT corrupted NTFS volume/stripe set / Syrinx boot',
  0xcb => 'reserved for DRDOS/secured (FAT32)',
  0xcc => 'reserved for DRDOS/secured (FAT32, LBA)',
  0xcd => 'CTOS Memdump?',
  0xce => 'reserved for DRDOS/secured (FAT16, LBA)',
  0xd0 => 'REAL/32 secure big partition',
  0xd1 => 'Old Multiuser DOS secured FAT12',
  0xd4 => 'Old Multiuser DOS secured FAT16 <32M',
  0xd5 => 'Old Multiuser DOS secured extended partition',
  0xd6 => 'Old Multiuser DOS secured FAT16 >=32M',
  0xd8 => 'CP/M-86',
  0xdb => 'Digital Research CP/M, Concurrent CP/M, Concurrent DOS / CTOS (Convergent Technologies OS -Unisys) / KDG Telemetry SCPU boot',
  0xdd => 'Hidden CTOS Memdump?',
  0xe1 => 'DOS access or SpeedStor 12-bit FAT extended partition',
  0xe3 => 'DOS R/O or SpeedStor',
  0xe4 => 'SpeedStor 16-bit FAT extended partition < 1024 cyl.',
  0xeb => 'BeOS',
  0xee => 'Indication that this legacy MBR is followed by an EFI header',
  0xef => 'Partition that contains an EFI file system',
  0xf1 => 'SpeedStor 0xf1',
  0xf2 => 'DOS 3.3+ secondary partition',
  0xf4 => 'SpeedStor large partition / Prologue single-volume partition',
  0xf5 => 'Prologue multi-volume partition',
  0xfd => 'Linux RAID',
  0xfe => 'SpeedStor > 1024 cyl. or LANstep / IBM PS/2 IML (Initial Microcode Load) partition, located at the end of the disk. / Windows NT Disk Administrator hidden partition / Linux Logical Volume Manager partition (old)',
  0xff => 'Xenix Bad Block Table',
);

my %type2fs = (
arch() =~ /^ppc/ ? (
  0x07 => 'hpfs',
) : (
  0x07 => 'ntfs',
),
arch() !~ /sparc/ ? (
  0x01 => 'vfat',
  0x04 => 'vfat',
  0x05 => 'ignore',
  0x06 => 'vfat',
) : (
  0x01 => 'ufs',
  0x02 => 'ufs',
  0x04 => 'ufs',
  0x06 => 'ufs',
  0x07 => 'ufs',
  0x08 => 'ufs',
),
  0x0b => 'vfat',
  0x0c => 'vfat',
  0x0e => 'vfat',
  0x1b => 'vfat',
  0x1c => 'vfat',
  0x1e => 'vfat',
  0x82 => 'swap',
  0x83 => 'ext2',
  0x183=> 'reiserfs',
  0x283=> 'xfs',
  0x401 => 'apple',
  0x402 => 'hfs',
  nfs  => 'nfs', #- hack
);

my %types_rev = reverse %types;
my %fs2type = reverse %type2fs;


1;

sub important_types { 
    my @l = (@important_types, if_($::expert, @important_types2, sort values %types));
    difference2(\@l, \@bad_types);
}

sub type2name($) { $types{$_[0]} || $_[0] }
sub type2fs($) { $type2fs{$_[0]} }
sub fs2type($) { $fs2type{$_[0]} }
sub name2type($) { 
    local ($_) = @_;
    /0x(.*)/ ? hex $1 : $types_rev{$_} || $_;
}

sub isWholedisk($) { arch() =~ /^sparc/ && $_[0]{type} == 5 }
sub isExtended($) { arch() !~ /^sparc/ && ($_[0]{type} == 5 || $_[0]{type} == 0xf || $_[0]{type} == 0x85) }
sub isLVM($) { $_[0]{type} == 0x8e }
sub isRAID($) { $_[0]{type} == 0xfd }
sub isMDRAID { $_[0]{device} =~ /^md/ }
sub isLVMBased { $_[0]{LVMname} }
sub isSwap($) { $type2fs{$_[0]{type}} eq 'swap' }
sub isExt2($) { $type2fs{$_[0]{type}} eq 'ext2' }
sub isReiserfs($) { $type2fs{$_[0]{type}} eq 'reiserfs' }
sub isXfs($) { $type2fs{$_[0]{type}} eq 'xfs' }
sub isDos($) { arch() !~ /^sparc/ && $ {{ 1=>1, 4=>1, 6=>1 }}{$_[0]{type}} }
sub isWin($) { $ {{ 0xb=>1, 0xc=>1, 0xe=>1, 0x1b=>1, 0x1c=>1, 0x1e=>1 }}{$_[0]{type}} }
sub isFat($) { isDos($_[0]) || isWin($_[0]) }
sub isSunOS($) { arch() =~ /sparc/ && $ {{ 0x1=>1, 0x2=>1, 0x4=>1, 0x6=>1, 0x7=>1, 0x8=>1 }}{$_[0]{type}} }
sub isSolaris($) { 0; } #- hack to search for getting the difference ? TODO
sub isOtherAvailableFS($) { isFat($_[0]) || isSunOS($_[0]) || isHFS($_[0]) } #- other OS that linux can access its filesystem
sub isNfs($) { $_[0]{type} eq 'nfs' } #- small hack
sub isNT($) { arch() !~ /^sparc/ && $_[0]{type} == 0x7 }
sub isSupermount($) { $_[0]{type} eq 'supermount' }
sub isHFS($) { $type2fs{$_[0]{type}} eq 'hfs' }
sub isApple($) { $type2fs{$_[0]{type}} eq 'apple' && defined $_[0]{isDriver} }
sub isAppleBootstrap($) { $type2fs{$_[0]{type}} eq 'apple' && defined $_[0]{isBoot} }
sub isHiddenMacPart { defined $_[0]{isMap} }
sub isLoopback { defined $_[0]{loopback_file} }
sub isTrueFS { isExt2($_[0]) || isReiserfs($_[0]) || isXfs($_[0]) }
sub isMountableRW { isTrueFS($_[0]) || isOtherAvailableFS($_[0]) }
sub isNonMountable { isRAID($_[0]) || isLVM($_[0]) }

sub isPrimary($$) {
    my ($part, $hd) = @_;
    foreach (@{$hd->{primary}{raw}}) { $part eq $_ and return 1; }
    0;
}

sub adjustStartAndEnd($$) {
    my ($hd, $part) = @_;

    $hd->adjustStart($part);
    $hd->adjustEnd($part);
}

sub verifyNotOverlap($$) {
    my ($a, $b) = @_;
    $a->{start} + $a->{size} <= $b->{start} || $b->{start} + $b->{size} <= $a->{start};
}
sub verifyInside($$) {
    my ($a, $b) = @_;
    $b->{start} <= $a->{start} && $a->{start} + $a->{size} <= $b->{start} + $b->{size};
}

sub verifyParts_ {
    foreach my $i (@_) {
	foreach (@_) {
	    next if !$i || !$_ || $i == $_ || isWholedisk($i) || isExtended($i); #- avoid testing twice for simplicity :-)
	    if (isWholedisk($_)) {
		verifyInside($i, $_) or
		  cdie sprintf("partition sector #$i->{start} (%s) is not inside whole disk (%s)!",
			       formatXiB($i->{size}, 512), formatXiB($_->{size}, 512));
	    } elsif (isExtended($_)) {
		verifyNotOverlap($i, $_) or
		  log::l(sprintf("warning partition sector #$i->{start} (%s) is overlapping with extended partition!",
				 formatXiB($i->{size}, 512))); #- only warning for this one is acceptable
	    } else {
		verifyNotOverlap($i, $_) or
		  cdie sprintf("partitions sector #$i->{start} (%s) and sector #$_->{start} (%s) are overlapping!",
			       formatXiB($i->{size}, 512), formatXiB($_->{size}, 512));
	    }
	}
    }
}
sub verifyParts($) {
    my ($hd) = @_;
    verifyParts_(get_normal_parts($hd));
}
sub verifyPrimary($) {
    my ($pt) = @_;
    $_->{start} > 0 || arch() =~ /^sparc/ || die "partition must NOT start at sector 0" foreach @{$pt->{normal}};
    verifyParts_(@{$pt->{normal}}, $pt->{extended});
}

sub assign_device_numbers($) {
    my ($hd) = @_;

    my $i = 1;
    $_->{device} = $hd->{prefix} . $i++ foreach @{$hd->{primary}{raw}},
                                                map { $_->{normal} } @{$hd->{extended} || []};

    #- try to figure what the windobe drive letter could be!
    #
    #- first verify there's at least one primary dos partition, otherwise it
    #- means it is a secondary disk and all will be false :(
    my ($c, @others) = grep { isFat($_) } @{$hd->{primary}{normal}};

    $i = ord 'C';
    $c->{device_windobe} = chr($i++) if $c;
    $_->{device_windobe} = chr($i++) foreach grep { isFat($_) } map { $_->{normal} } @{$hd->{extended}};
    $_->{device_windobe} = chr($i++) foreach @others;
}

sub remove_empty_extended($) {
    my ($hd) = @_;
    my $last = $hd->{primary}{extended} or return;
    @{$hd->{extended}} = grep {
	if ($_->{normal}) {
	    $last = $_;
	} else {
	    %{$last->{extended}} = $_->{extended} ? %{$_->{extended}} : ();
	}
	$_->{normal};
    } @{$hd->{extended}};
    adjust_main_extended($hd);
}

sub adjust_main_extended($) {
    my ($hd) = @_;

    if (!is_empty_array_ref $hd->{extended}) {
	my ($l, @l) = @{$hd->{extended}};

	# the first is a special case, must recompute its real size
	my $start = round_down($l->{normal}{start} - 1, $hd->{geom}{sectors});
	my $end = $l->{normal}{start} + $l->{normal}{size};
	my $only_linux = 1; my $has_win_lba = 0;
	foreach (map $_->{normal}, $l, @l) {
	    $start = min($start, $_->{start});
	    $end = max($end, $_->{start} + $_->{size});
	    $only_linux &&= isTrueFS($_) || isSwap($_);
	    $has_win_lba ||= $_->{type} == 0xc || $_->{type} == 0xe;
	}
	$l->{start} = $hd->{primary}{extended}{start} = $start;
	$l->{size} = $hd->{primary}{extended}{size} = $end - $start;
	$hd->{primary}{extended}{type} = $only_linux ? 0x85 : $has_win_lba ? 0xf : 0x5 if !$::expert;
    }
    unless (@{$hd->{extended} || []} || !$hd->{primary}{extended}) {
	%{$hd->{primary}{extended}} = (); #- modify the raw entry
	delete $hd->{primary}{extended};
    }
    verifyParts($hd); #- verify everything is all right
}

sub adjust_local_extended($$) {
    my ($hd, $part) = @_;
    
    foreach (@{$hd->{extended} || []}) {
	$_->{normal} == $part or next;
	$_->{size} = $part->{size} + $part->{start} - $_->{start};
	last;
    }
}

sub get_normal_parts($) {
    my ($hd) = @_;

    #- HACK !!
    $hd->{raid} and return grep {$_} @{$hd->{raid}};
    $hd->{loopback} and return grep {$_} @{$hd->{loopback}};

    @{$hd->{primary}{normal} || []}, map { $_->{normal} } @{$hd->{extended} || []}
}

sub get_holes($) {
    my ($hd) = @_;

    my $start = arch() eq "alpha" ? 2048 : 1;

    map {
	my $current = $start;
	$start = $_->{start} + $_->{size};
	{ start => $current, size => $_->{start} - $current }
    } sort { $a->{start} <=> $b->{start} } grep { !isWholedisk($_) } get_normal_parts($hd), { start => $hd->{totalsectors}, size => 0 };    
}


sub read_one($$) {
    my ($hd, $sector) = @_;
    my ($pt, $info);

    #- it can be safely considered that the first sector is used to probe the partition table
    #- but other sectors (typically for extended partition ones) have to match this type!
    if (!$sector) {
	my @parttype = arch() =~ /^sparc/ ? ('sun', 'bsd', 'unknown') : ('dos', 'bsd', 'sun', 'mac', 'unknown');
	foreach ('empty', @parttype) {
	    /unknown/ and die "unknown partition table format";
	    eval {
		require("partition_table_$_.pm");
		bless $hd, "partition_table_$_";
		($pt, $info) = $hd->read($sector);
		log::l("found a $_ partition table on $hd->{file} at sector $sector");
	    };
	    $@ or last;
	}
    } else {
	#- keep current blessed object for that, this means it is neccessary to read sector 0 before.
	($pt, $info) = $hd->read($sector);
    }

    my @extended = $hd->hasExtended ? grep { isExtended($_) } @$pt : ();
    my @normal = grep { $_->{size} && $_->{type} && !isExtended($_) } @$pt;

    @extended > 1 and die "more than one extended partition";

    $_->{rootDevice} = $hd->{device} foreach @normal, @extended;
    { raw => $pt, extended => $extended[0], normal => \@normal, info => $info };
}

sub read($;$) {
    my ($hd, $clearall) = @_;
    if ($clearall) {
	partition_table_raw::zero_MBR_and_dirty($hd);
	return 1;
    }
    my $pt = read_one($hd, 0) or return 0;
    $hd->{primary} = $pt;
    undef $hd->{extended};
    verifyPrimary($pt);
    eval {
	$pt->{extended} and read_extended($hd, $pt->{extended}) || return 0;
    }; die "extended partition: $@" if $@;

    assign_device_numbers($hd);
    remove_empty_extended($hd);
    1;
}

sub read_extended {
    my ($hd, $extended) = @_;

    my $pt = read_one($hd, $extended->{start}) or return 0;
    $pt = { %$extended, %$pt };

    push @{$hd->{extended}}, $pt;
    @{$hd->{extended}} > 100 and die "oops, seems like we're looping here :(  (or you have more than 100 extended partitions!)";

    @{$pt->{normal}} <= 1 or die "more than one normal partition in extended partition";
    @{$pt->{normal}} >= 1 or cdie "no normal partition in extended partition";
    $pt->{normal} = $pt->{normal}[0];
    #- in case of extended partitions, the start sector is local to the partition or to the first extended_part!
    $pt->{normal}{start} += $pt->{start};

    #- the following verification can broke an existing partition table that is
    #- correctly read by fdisk or cfdisk. maybe the extended partition can be
    #- recomputed to get correct size.
    if (!verifyInside($pt->{normal}, $extended)) {
	$extended->{size} = $pt->{normal}{start} + $pt->{normal}{size};
	verifyInside($pt->{normal}, $extended) or die "partition $pt->{normal}{device} is not inside its extended partition";
    }

    if ($pt->{extended}) {
	$pt->{extended}{start} += $hd->{primary}{extended}{start};
	read_extended($hd, $pt->{extended}) or return 0;
    }
    1;
}

# write the partition table
sub write($) {
    my ($hd) = @_;
    $hd->{isDirty} or return;

    #- set first primary partition active if no primary partitions are marked as active.
    for ($hd->{primary}{raw}) {
	(grep { $_->{local_start} = $_->{start}; $_->{active} ||= 0 } @$_) or $_->[0]{active} = 0x80;
    }

    #- last chance for verification, this make sure if an error is detected,
    #- it will never be writed back on partition table.
    verifyParts($hd);

    $hd->write(0, $hd->{primary}{raw}, $hd->{primary}{info}) or die "writing of partition table failed";

    #- should be fixed but a extended exist with no real extended partition, that blanks mbr!
    if (arch() !~ /^sparc/) {
	foreach (@{$hd->{extended}}) {
	    # in case of extended partitions, the start sector must be local to the partition
	    $_->{normal}{local_start} = $_->{normal}{start} - $_->{start};
	    $_->{extended} and $_->{extended}{local_start} = $_->{extended}{start} - $hd->{primary}{extended}{start};

	    $hd->write($_->{start}, $_->{raw}) or die "writing of partition table failed";
	}
    }
    $hd->{isDirty} = 0;
    $hd->{hasBeenDirty} = 1; #- used in undo (to know if undo should believe isDirty or not)

    #- now sync disk and re-read the partition table
    if ($hd->{needKernelReread}) {
	sync();
	$hd->kernel_read;
	$hd->{needKernelReread} = 0;
    }
}

sub active($$) {
    my ($hd, $part) = @_;

    $_->{active} = 0 foreach @{$hd->{primary}{normal}};
    $part->{active} = 0x80;
    $hd->{isDirty} = 1;
}


# remove a normal partition from hard drive hd
sub remove($$) {
    my ($hd, $part) = @_;
    my $i;

    #- first search it in the primary partitions
    $i = 0; foreach (@{$hd->{primary}{normal}}) {
	if ($_ eq $part) {
	    splice(@{$hd->{primary}{normal}}, $i, 1);
	    %$_ = (); #- blank it

	    return $hd->{isDirty} = $hd->{needKernelReread} = 1;
	}
	$i++;
    }

    my ($first, $second, $third) = map { $_->{normal} } @{$hd->{extended} || []};
    if ($third && $first eq $part) {
	die "Can't handle removing hda5 when hda6 is not the second partition" if $second->{start} > $third->{start};
    }      

    #- otherwise search it in extended partitions
    foreach (@{$hd->{extended} || []}) {
	$_->{normal} eq $part or next;

	delete $_->{normal}; #- remove it
	remove_empty_extended($hd);

	return $hd->{isDirty} = $hd->{needKernelReread} = 1;
    }
    0;
}

# create of partition at starting at `start', of size `size' and of type `type' (nice comment, uh?)
sub add_primary($$) {
    my ($hd, $part) = @_;

    {
	local $hd->{primary}{normal}; #- save it to fake an addition of $part, that way add_primary do not modify $hd if it fails
	push @{$hd->{primary}{normal}}, $part;
	adjust_main_extended($hd); #- verify
	raw_add($hd->{primary}{raw}, $part);
    }
    push @{$hd->{primary}{normal}}, $part; #- really do it
}

sub add_extended {
    arch() =~ /^sparc/ and die _("Extended partition not supported on this platform");

    my ($hd, $part, $extended_type) = @_;
    $extended_type =~ s/Extended_?//;

    my $e = $hd->{primary}{extended};

    if ($e && !verifyInside($part, $e)) {
	#-die "sorry, can't add outside the main extended partition" unless $::unsafe;
	my $end = $e->{start} + $e->{size};
	my $start = min($e->{start}, $part->{start});
	$end = max($end, $part->{start} + $part->{size}) - $start;

	{ #- faking a resizing of the main extended partition to test for problems
	    local $e->{start} = $start;
	    local $e->{size} = $end - $start;
	    eval { verifyPrimary($hd->{primary}) };
	    $@ and die
_("You have a hole in your partition table but I can't use it.
The only solution is to move your primary partitions to have the hole next to the extended partitions");
	}
    }

    if ($e && $part->{start} < $e->{start}) {
	my $l = first (@{$hd->{extended}});

	#- the first is a special case, must recompute its real size
	$l->{start} = round_down($l->{normal}{start} - 1, $hd->cylinder_size());
	$l->{size} = $l->{normal}{start} + $l->{normal}{size} - $l->{start};
	my $ext = { %$l };
	unshift @{$hd->{extended}}, { type => 5, raw => [ $part, $ext, {}, {} ], normal => $part, extended => $ext };
	#- size will be autocalculated :)
    } else {
	my ($ext, $ext_size) = is_empty_array_ref($hd->{extended}) ?
	  ($hd->{primary}, -1) : #- -1 size will be computed by adjust_main_extended
	  (top(@{$hd->{extended}}), $part->{size});
	my %ext = ( type => $extended_type || 5, start => $part->{start}, size => $ext_size );

	raw_add($ext->{raw}, \%ext);
	$ext->{extended} = \%ext;
	push @{$hd->{extended}}, { %ext, raw => [ $part, {}, {}, {} ], normal => $part };
    }
    $part->{start}++; $part->{size}--; #- let it start after the extended partition sector
    adjustStartAndEnd($hd, $part);

    adjust_main_extended($hd);
}

sub add($$;$$) {
    my ($hd, $part, $primaryOrExtended, $forceNoAdjust) = @_;

    get_normal_parts($hd) >= ($hd->{device} =~ /^rd/ ? 7 : $hd->{device} =~ /^(sd|ida|cciss)/ ? 15 : 63) and cdie "maximum number of partitions handled by linux reached";

    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;
    $part->{rootDevice} = $hd->{device};
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    $part->{start} ||= 1 if arch() !~ /^sparc/; #- starting at sector 0 is not allowed
    adjustStartAndEnd($hd, $part) unless $forceNoAdjust;

    my $e = $hd->{primary}{extended};
    my $nb_primaries = $hd->{device} =~ /^rd/ ? 3 : 1;

    if (arch() =~ /^sparc|ppc/ ||
	$primaryOrExtended eq 'Primary' ||
	$primaryOrExtended !~ /Extended/ && @{$hd->{primary}{normal} || []} < $nb_primaries) {
	eval { add_primary($hd, $part) };
	return unless $@;
    }
    eval { add_extended($hd, $part, $primaryOrExtended) } if $hd->hasExtended; #- try adding extended
    if ($@ || !$hd->hasExtended) {
	eval { add_primary($hd, $part) };
	die $@ if $@; #- send the add extended error which should be better
    }
}

# search for the next partition
sub next($$) {
    my ($hd, $part) = @_;

    first(
	  sort { $a->{start} <=> $b->{start} }
	  grep { $_->{start} >= $part->{start} + $part->{size} }
	  get_normal_parts($hd)
	 );
}
sub next_start($$) {
    my ($hd, $part) = @_;
    my $next = &next($hd, $part);
    $next ? $next->{start} : $hd->{totalsectors};
}

sub can_raw_add {
    my ($hd) = @_;
    $_->{size} || $_->{type} or return 1 foreach @{$hd->{primary}{raw}};
    0;
}
sub raw_add {
    my ($raw, $part) = @_;

    foreach (@$raw) {
	$_->{size} || $_->{type} and next;
	$_ = $part;
	return;
    }
    die "raw_add: partition table already full";
}

sub load($$;$) {
    my ($hd, $file, $force) = @_;

    local *F;
    open F, $file or die _("Error reading file %s", $file);

    my $h;
    {
	local $/ = "\0";
	eval <F>;
    }
    $@ and die _("Restoring from file %s failed: %s", $file, $@);

    ref $h eq 'ARRAY' or die _("Bad backup file");

    my %h; @h{@fields2save} = @$h;

    $h{totalsectors} == $hd->{totalsectors} or $force or cdie "bad totalsectors";

    #- unsure we don't modify totalsectors
    local $hd->{totalsectors};

    @{$hd}{@fields2save} = @$h;

    delete @$_{qw(isMounted isFormatted notFormatted toFormat toFormatUnsure)} foreach get_normal_parts($hd);
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
}

sub save($$) {
    my ($hd, $file) = @_;
    my @h = @{$hd}{@fields2save};
    local *F;
    require Data::Dumper;
    open F, ">$file"
      and print F Data::Dumper->Dump([\@h], ['$h']), "\0"
      or die _("Error writing to file %s", $file);
}
