package partition_table; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @important_types @important_types2 @fields2save @bad_types);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    types => [ qw(part2name type2fs name2pt_type fs2pt_type isExtended isExt2 isThisFs isTrueLocalFS isTrueFS isSwap isDos isWin isFat isFat_or_NTFS isSunOS isOtherAvailableFS isPrimary isRawLVM isRawRAID isRAID isLVM isMountableRW isNonMountable isPartOfLVM isPartOfRAID isPartOfLoopback isLoopback isMounted isBusy isSpecial maybeFormatted isApple isAppleBootstrap isEfi) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


use common;
use partition_table::raw;
use detect_devices;
use log;

@important_types = ('Linux native', 'Linux swap', 'Journalised FS: ext3', 'Journalised FS: ReiserFS',
		    if_(arch() =~ /ppc/, 'Journalised FS: JFS', 'Journalised FS: XFS', 'Apple HFS Partition', 'Apple Bootstrap'),
		    if_(arch() =~ /i.86/, 'Journalised FS: JFS', 'Journalised FS: XFS', 'FAT32'),
		    if_(arch() =~ /ia64/, 'Journalised FS: XFS', 'FAT32'),
		    if_(arch() =~ /x86_64/, 'FAT32'),
		   );
@important_types2 = ('Linux RAID', 'Linux Logical Volume Manager');

@fields2save = qw(primary extended totalsectors isDirty will_tell_kernel);

@bad_types = ('Empty', 'Extended', 'W95 Extended (LBA)', 'Linux extended');

my %pt_type2name = (
  0x0 => 'Empty',
if_(arch() =~ /^ppc/, 
  0x183 => 'Journalised FS: ReiserFS',
  0x283 => 'Journalised FS: XFS',
  0x383 => 'Journalised FS: JFS',
  0x483 => 'Journalised FS: ext3',
  0x401	=> 'Apple Partition',
  0x401	=> 'Apple Bootstrap',
  0x402	=> 'Apple HFS Partition',
), if_(arch() =~ /^i.86/,
  0x107 => 'NTFS',
  0x183 => 'Journalised FS: ReiserFS',
  0x283 => 'Journalised FS: XFS',
  0x383 => 'Journalised FS: JFS',
  0x483 => 'Journalised FS: ext3',
), if_(arch() =~ /^ia64/,
  0x100 => 'Various',
  0x183 => 'Journalised FS: ReiserFS',
  0x283 => 'Journalised FS: XFS',
  0x483 => 'Journalised FS: ext3',
), if_(arch() =~ /^x86_64/,
  0x183 => 'Journalised FS: ReiserFS',
  0x483 => 'Journalised FS: ext3',
), if_(arch() =~ /^sparc/,
  0x01 => 'SunOS boot',
  0x02 => 'SunOS root',
  0x03 => 'SunOS swap',
  0x04 => 'SunOS usr',
  0x05 => 'Whole disk',
  0x06 => 'SunOS stand',
  0x07 => 'SunOS var',
  0x08 => 'SunOS home',
), if_(arch() =~ /^i.86/,
  0x01 => 'FAT12',
  0x02 => 'XENIX root',
  0x03 => 'XENIX usr',
  0x04 => 'FAT16 <32M',
  0x05 => 'Extended',
  0x06 => 'FAT16',
  0x07 => 'NTFS (or HPFS)',
  0x08 => 'AIX',
),
  0x09 => 'AIX bootable',
  0x0a => 'OS/2 Boot Manager',
  0x0b => 'FAT32',
  0x0c => 'W95 FAT32 (LBA)',
  0x0e => 'W95 FAT16 (LBA)',
  0x0f => 'W95 Extended (LBA)',
  0x10 => 'OPUS',
  0x11 => 'Hidden FAT12',
  0x12 => 'Compaq diagnostics',
  0x14 => 'Hidden FAT16 <32M',
  0x16 => 'Hidden FAT16',
  0x17 => 'Hidden HPFS/NTFS',
  0x18 => 'AST SmartSleep',
  0x1b => 'Hidden W95 FAT32',

  0x1c => 'Hidden W95 FAT32 (LBA)',
  0x1e => 'Hidden W95 FAT16 (LBA)',
  0x24 => 'NEC DOS',
  0x39 => 'Plan 9',
  0x3c => 'PartitionMagic recovery',
  0x40 => 'Venix 80286',
  0x41 => 'PPC PReP Boot',
  0x42 => 'SFS',
  0x4d => 'QNX4.x',
  0x4e => 'QNX4.x 2nd part',
  0x4f => 'QNX4.x 3rd part',

  0x50 => 'OnTrack DM',
  0x51 => 'OnTrack DM6 Aux1',
  0x52 => 'CP/M',
  0x53 => 'OnTrack DM6 Aux3',
  0x54 => 'OnTrackDM6',
  0x55 => 'EZ-Drive',
  0x56 => 'Golden Bow',
  0x5c => 'Priam Edisk',
  0x61 => 'SpeedStor',
  0x63 => 'GNU HURD or SysV',
  0x64 => 'Novell Netware 286',
  0x65 => 'Novell Netware 386',
  0x70 => 'DiskSecure Multi-Boot',
  0x75 => 'PC/IX',
  0x80 => 'Old Minix',
  0x81 => 'Minix / old Linux',


  0x82 => 'Linux swap',
  0x83 => 'Linux native',

  0x84 => 'OS/2 hidden C: drive',
  0x85 => 'Linux extended',
  0x86 => 'NTFS volume set',
  0x87 => 'NTFS volume set',
  0x8e => 'Linux Logical Volume Manager',
  0x93 => 'Amoeba',
  0x94 => 'Amoeba BBT',
  0x9f => 'BSD/OS',
  0xa0 => 'IBM Thinkpad hibernation',
  0xa5 => 'FreeBSD',
  0xa6 => 'OpenBSD',
  0xa7 => 'NeXTSTEP',
  0xa8 => 'Darwin UFS',
  0xa9 => 'NetBSD',
  0xab => 'Darwin boot',
  0xb7 => 'BSDI fs',
  0xb8 => 'BSDI swap',
  0xbb => 'Boot Wizard hidden',
  0xbe => 'Solaris boot',
  0xc1 => 'DRDOS/sec (FAT-12)',
  0xc4 => 'DRDOS/sec (FAT-16 < 32M)',
  0xc6 => 'DRDOS/sec (FAT-16)',
  0xc7 => 'Syrinx',
  0xda => 'Non-FS data',
  0xdb => 'CP/M / CTOS / ...',
  0xde => 'Dell Utility',
  0xdf => 'BootIt',
  0xe1 => 'DOS access',
  0xe3 => 'DOS R/O',
  0xe4 => 'SpeedStor',
  0xeb => 'BeOS fs',
  0xee => 'EFI GPT',
  0xef => 'EFI (FAT-12/16/32)',
  0xf0 => 'Linux/PA-RISC boot',
  0xf1 => 'SpeedStor',
  0xf4 => 'SpeedStor',
  0xf2 => 'DOS secondary',
  0xfd => 'Linux RAID',
  0xfe => 'LANstep',
  0xff => 'BBT',
);

my %pt_type2fs = (
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
  0xeb => 'befs',
  0xef => 'vfat',
  0x107 => 'ntfs',
  0x183 => 'reiserfs',
  0x283 => 'xfs',
  0x383 => 'jfs',
  0x483 => 'ext3',
  0x401 => 'apple',
  0x402 => 'hfs',
);

my %name2pt_type = reverse %pt_type2name;
my %fs2pt_type = reverse %pt_type2fs;

		foreach (@important_types, @important_types2, @bad_types) {
		    exists $name2pt_type{$_} or die "unknown $_\n";
		}


1;

sub important_types() { 
    my @l = (@important_types, if_($::expert, @important_types2, sort values %pt_type2name));
    difference2(\@l, \@bad_types);
}

sub type2fs {
    my ($part, $o_default) = @_;
    my $pt_type = $part->{pt_type};
    $pt_type2fs{$pt_type} || $pt_type =~ /^(\d+)$/ && $o_default || $pt_type;
}
sub fs2pt_type { $fs2pt_type{$_[0]} || $_[0] }
sub part2name { 
    my ($part) = @_;
    $pt_type2name{$part->{pt_type}} || $part->{pt_type};
}
sub name2pt_type { 
    local ($_) = @_;
    /0x(.*)/ ? hex $1 : $name2pt_type{$_} || $_;
}
#sub name2type { { pt_type => name2pt_type($_[0]) } }

sub isEfi { arch() =~ /ia64/ && $_[0]{pt_type} == 0xef }
sub isWholedisk { arch() =~ /^sparc/ && $_[0]{pt_type} == 5 }
sub isExtended { arch() !~ /^sparc/ && ($_[0]{pt_type} == 5 || $_[0]{pt_type} == 0xf || $_[0]{pt_type} == 0x85) }
sub isRawLVM { $_[0]{pt_type} == 0x8e }
sub isRawRAID { $_[0]{pt_type} == 0xfd }
sub isSwap { type2fs($_[0]) eq 'swap' }
sub isExt2 { type2fs($_[0]) eq 'ext2' }
sub isDos { arch() !~ /^sparc/ && ${{ 1 => 1, 4 => 1, 6 => 1 }}{$_[0]{pt_type}} }
sub isWin { ${{ 0xb => 1, 0xc => 1, 0xe => 1, 0x1b => 1, 0x1c => 1, 0x1e => 1 }}{$_[0]{pt_type}} }
sub isFat { isDos($_[0]) || isWin($_[0]) }
sub isFat_or_NTFS { isDos($_[0]) || isWin($_[0]) || $_[0]{pt_type} == 0x107 }
sub isSunOS { arch() =~ /sparc/ && ${{ 0x1 => 1, 0x2 => 1, 0x4 => 1, 0x6 => 1, 0x7 => 1, 0x8 => 1 }}{$_[0]{pt_type}} }
sub isApple { type2fs($_[0]) eq 'apple' && defined $_[0]{isDriver} }
sub isAppleBootstrap { type2fs($_[0]) eq 'apple' && defined $_[0]{isBoot} }
sub isHiddenMacPart { defined $_[0]{isMap} }

sub isThisFs { type2fs($_[1]) eq $_[0] }
sub isTrueFS { isTrueLocalFS($_[0]) || member(type2fs($_[0]), qw(nfs)) }
sub isTrueLocalFS { member(type2fs($_[0]), qw(ext2 reiserfs xfs jfs ext3)) }

sub isOtherAvailableFS { isEfi($_[0]) || isFat_or_NTFS($_[0]) || isSunOS($_[0]) || isThisFs('hfs', $_[0]) } #- other OS that linux can access its filesystem
sub isMountableRW { (isTrueFS($_[0]) || isOtherAvailableFS($_[0])) && !isThisFs('ntfs', $_[0]) }
sub isNonMountable { 
    my ($part) = @_;
    isRawRAID($part) || isRawLVM($part) || isThisFs("ntfs", $part) && !$part->{isFormatted} && $part->{notFormatted};
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
sub maybeFormatted { $_[0]{isFormatted} || !$_[0]{notFormatted} }


#- works for both hard drives and partitions ;p
sub description {
    my ($hd) = @_;
    my $win = $hd->{device_windobe};

    sprintf "%s%s (%s%s%s%s)", 
      $hd->{device}, 
      $win && " [$win:]", 
      formatXiB($hd->{totalsectors} || $hd->{size}, 512),
      $hd->{info} && ", $hd->{info}",
      $hd->{mntpoint} && ", " . $hd->{mntpoint},
      $hd->{pt_type} && ", " . part2name($hd);
}

sub isPrimary {
    my ($part, $hd) = @_;
    foreach (@{$hd->{primary}{raw}}) { $part eq $_ and return 1 }
    0;
}

sub adjustStartAndEnd {
    my ($hd, $part) = @_;

    $hd->adjustStart($part);
    $hd->adjustEnd($part);
}

sub verifyNotOverlap {
    my ($a, $b) = @_;
    $a->{start} + $a->{size} <= $b->{start} || $b->{start} + $b->{size} <= $a->{start};
}
sub verifyInside {
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
sub verifyParts {
    my ($hd) = @_;
    verifyParts_(get_normal_parts($hd));
}
sub verifyPrimary {
    my ($pt) = @_;
    $_->{start} > 0 || arch() =~ /^sparc/ || die "partition must NOT start at sector 0" foreach @{$pt->{normal}};
    verifyParts_(@{$pt->{normal}}, $pt->{extended});
}

sub assign_device_numbers {
    my ($hd) = @_;

    my $i = 1;
    my $start = 1; 
    
    #- on PPC we need to assign device numbers to the holes too - big FUN!
    #- not if it's an IBM machine using a DOS partition table though
    if (arch() =~ /ppc/ && detect_devices::get_mac_model() !~ /^IBM/) {
	#- first sort the normal parts
	$hd->{primary}{normal} = [ sort { $a->{start} <=> $b->{start} } @{$hd->{primary}{normal}} ];
    
	#- now loop through them, assigning partition numbers - reserve one for the holes
	foreach (@{$hd->{primary}{normal}}) {
	    if ($_->{start} > $start) {
		log::l("PPC: found a hole on $hd->{prefix} before $_->{start}, skipping device..."); 
		$i++;
	    }
	    $_->{device} = $hd->{prefix} . $i;
	    $_->{devfs_device} = $hd->{devfs_prefix} . '/part' . $i;
	    $start = $_->{start} + $_->{size};
	    $i++;
	}
    } else {
	foreach (@{$hd->{primary}{raw}}) {
	    $_->{device} = $hd->{prefix} . $i;
	    $_->{devfs_device} = $hd->{devfs_prefix} . '/part' . $i;
	    $i++;
	}
	foreach (map { $_->{normal} } @{$hd->{extended} || []}) {
	    my $dev = $hd->{prefix} . $i;
	    my $renumbered = $_->{device} && $dev ne $_->{device};
	    if ($renumbered) {
		require fs;
		eval { fs::umount_part($_) }; #- at least try to umount it
		will_tell_kernel($hd, del => $_, 'delay_del');
		push @{$hd->{partitionsRenumbered}}, [ $_->{device}, $dev ];
	    }
	    $_->{device} = $dev;
	    $_->{devfs_device} = $hd->{devfs_prefix} . '/part' . $i;
	    if ($renumbered) {
		will_tell_kernel($hd, add => $_, 'delay_add');
	    }
	    $i++;
	}
    }

    #- try to figure what the windobe drive letter could be!
    #
    #- first verify there's at least one primary dos partition, otherwise it
    #- means it is a secondary disk and all will be false :(
    #-
    #- isFat_or_NTFS isn't true for 0x7 partitions, only for 0x107.
    #- alas 0x107 is not set correctly at this stage
    #- solution: don't bother with 0x7 vs 0x107 here
    my ($c, @others) = grep { isFat_or_NTFS($_) || $_->{pt_type} == 0x7 || $_->{pt_type} == 0x17 } @{$hd->{primary}{normal}};

    $i = ord 'C';
    $c->{device_windobe} = chr($i++) if $c;
    $_->{device_windobe} = chr($i++) foreach grep { isFat_or_NTFS($_) || $_->{pt_type} == 0x7 || $_->{pt_type} == 0x17 } map { $_->{normal} } @{$hd->{extended}};
    $_->{device_windobe} = chr($i++) foreach @others;
}

sub remove_empty_extended {
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

sub adjust_main_extended {
    my ($hd) = @_;

    if (!is_empty_array_ref $hd->{extended}) {
	my ($l, @l) = @{$hd->{extended}};

	# the first is a special case, must recompute its real size
	my $start = round_down($l->{normal}{start} - 1, $hd->{geom}{sectors});
	my $end = $l->{normal}{start} + $l->{normal}{size};
	my $only_linux = 1; my $has_win_lba = 0;
	foreach (map { $_->{normal} } $l, @l) {
	    $start = min($start, $_->{start});
	    $end = max($end, $_->{start} + $_->{size});
	    $only_linux &&= isTrueLocalFS($_) || isSwap($_);
	    $has_win_lba ||= $_->{pt_type} == 0xc || $_->{pt_type} == 0xe;
	}
	$l->{start} = $hd->{primary}{extended}{start} = $start;
	$l->{size} = $hd->{primary}{extended}{size} = $end - $start;
    }
    if (!@{$hd->{extended} || []} && $hd->{primary}{extended}) {
	will_tell_kernel($hd, del => $hd->{primary}{extended});
	%{$hd->{primary}{extended}} = (); #- modify the raw entry
	delete $hd->{primary}{extended};
    }
    verifyParts($hd); #- verify everything is all right
}

sub adjust_local_extended {
    my ($hd, $part) = @_;

    my $extended = find { $_->{normal} == $part } @{$hd->{extended} || []} or return;
    $extended->{size} = $part->{size} + $part->{start} - $extended->{start};

    #- must write it there too because values are not shared
    my $prev = find { $_->{extended}{start} == $extended->{start} } @{$hd->{extended} || []} or return;
    $prev->{extended}{size} = $part->{size} + $part->{start} - $prev->{extended}{start};
}

sub get_normal_parts {
    my ($hd) = @_;

    @{$hd->{primary}{normal} || []}, map { $_->{normal} } @{$hd->{extended} || []}
}

sub get_normal_parts_and_holes {
    my ($hd) = @_;
    my ($start, $last) = ($hd->first_usable_sector, $hd->last_usable_sector);

    ref($hd) or print("get_normal_parts_and_holes: bad hd" . backtrace(), "\n");

    my @l = map {
	my $current = $start;
	$start = $_->{start} + $_->{size};
	my $hole = { start => $current, size => $_->{start} - $current, pt_type => 0, rootDevice => $hd->{device} };
	$hole, $_;
    } sort { $a->{start} <=> $b->{start} } grep { !isWholedisk($_) } get_normal_parts($hd);

    push @l, { start => $start, size => $last - $start, pt_type => 0, rootDevice => $hd->{device} };
    grep { $_->{pt_type} || $_->{size} >= $hd->cylinder_size } @l;
}

sub read_one($$) {
    my ($hd, $sector) = @_;
    my ($pt, $info);

    #- it can be safely considered that the first sector is used to probe the partition table
    #- but other sectors (typically for extended partition ones) have to match this type!
    if (!$sector) {
	my @parttype = (
	  if_(arch() =~ /^ia64/, 'gpt'),
	  arch() =~ /^sparc/ ? ('sun', 'bsd') : ('dos', 'bsd', 'sun', 'mac'),
	);
	foreach ('empty', @parttype, 'lvm_PV', 'unknown') {
	    /unknown/ and die "unknown partition table format on disk " . $hd->{file};
	    eval {
		# perl_checker: require partition_table::bsd
		# perl_checker: require partition_table::dos
		# perl_checker: require partition_table::empty
		# perl_checker: require partition_table::gpt
		# perl_checker: require partition_table::lvm_PV
		# perl_checker: require partition_table::mac
		# perl_checker: require partition_table::sun
		require "partition_table/$_.pm";
		bless $hd, "partition_table::$_";
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
    my @normal = grep { $_->{size} && $_->{pt_type} && !isExtended($_) } @$pt;
    my $nb_special_empty = int(grep { $_->{size} && $_->{pt_type} == 0 } @$pt);

    @extended > 1 and die "more than one extended partition";

    $_->{rootDevice} = $hd->{device} foreach @normal, @extended;
    { raw => $pt, extended => $extended[0], normal => \@normal, info => $info, nb_special_empty => $nb_special_empty };
}

sub read {
    my ($hd) = @_;
    my $pt = read_one($hd, 0) or return 0;
    $hd->{primary} = $pt;
    undef $hd->{extended};
    verifyPrimary($pt);
    eval {
	my $need_removing_empty_extended;
	if ($pt->{extended}) {
	    read_extended($hd, $pt->{extended}, \$need_removing_empty_extended) or return 0;
	}
	if ($need_removing_empty_extended) {
	    #- special case when hda5 is empty, it must be skipped
	    #- (windows XP generates such partition tables)
	    remove_empty_extended($hd); #- includes adjust_main_extended
	}
	
    }; 
    die "extended partition: $@" if $@;

    assign_device_numbers($hd);
    remove_empty_extended($hd);

    $hd->set_best_geometry_for_the_partition_table;
    1;
}

sub read_extended {
    my ($hd, $extended, $need_removing_empty_extended) = @_;

    my $pt = read_one($hd, $extended->{start}) or return 0;
    $pt = { %$extended, %$pt };

    push @{$hd->{extended}}, $pt;
    @{$hd->{extended}} > 100 and die "oops, seems like we're looping here :(  (or you have more than 100 extended partitions!)";

    if (@{$pt->{normal}} == 0) {
	$$need_removing_empty_extended = 1;
	delete $pt->{normal};
	print "need_removing_empty_extended\n";
    } elsif (@{$pt->{normal}} > 1) {
	die "more than one normal partition in extended partition";
    } else {
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
    }

    if ($pt->{extended}) {
	$pt->{extended}{start} += $hd->{primary}{extended}{start};
	return read_extended($hd, $pt->{extended}, $need_removing_empty_extended);
    } else {
	1;
    }
}

sub will_tell_kernel {
    my ($hd, $action, $o_part, $o_delay) = @_;

    if ($action eq 'resize') {
	will_tell_kernel($hd, del => $o_part);
	will_tell_kernel($hd, add => $o_part);
    } else {
	my $part_number = sub { $o_part->{device} =~ /(\d+)$/ ? $1 : internal_error("bad device " . description($o_part)) };
	push @{$hd->{'will_tell_kernel' . ($o_delay || '')} ||= []}, 
	  [
	   $action,
	   $action eq 'force_reboot' ? () :
	   $action eq 'add' ? ($part_number->(), $o_part->{start}, $o_part->{size}) :
	   $action eq 'del' ? $part_number->() :
	   internal_error("unknown action $action")
	  ];
    }
    if (!$o_delay) {
	foreach my $delay ('delay_del', 'delay_add') {
	    my $l = delete $hd->{"will_tell_kernel$delay"} or next;
	    push @{$hd->{will_tell_kernel} ||= []}, @$l;
	}
    }
    $hd->{isDirty} = 1;
}

sub tell_kernel {
    my ($hd, $tell_kernel) = @_;

    my $F = partition_table::raw::openit($hd);

    my $force_reboot = any { $_->[0] eq 'force_reboot' } @$tell_kernel;
    if (!$force_reboot) {
	foreach (@$tell_kernel) {
	    my ($action, $part_number, $o_start, $o_size) = @$_;
	    
	    if ($action eq 'add') {
		$force_reboot ||= !c::add_partition(fileno $F, $part_number, $o_start, $o_size);
	    } elsif ($action eq 'del') {
		$force_reboot ||= !c::del_partition(fileno $F, $part_number);
	    }
	    log::l("tell kernel $action ($part_number $o_start $o_size), rebootNeeded is now " . bool2text($hd->{rebootNeeded}));
	}
    }
    if ($force_reboot) {
	my @magic_parts = grep { $_->{isMounted} && $_->{real_mntpoint} } get_normal_parts($hd);
	foreach (@magic_parts) {
	    syscall_('umount', $_->{real_mntpoint}) or log::l(N("error unmounting %s: %s", $_->{real_mntpoint}, $!));
	}
	$hd->{rebootNeeded} = !ioctl($F, c::BLKRRPART(), 0);
	log::l("tell kernel force_reboot, rebootNeeded is now $hd->{rebootNeeded}.");

	foreach (@magic_parts) {
	    syscall_('mount', $_->{real_mntpoint}, type2fs($_), c::MS_MGC_VAL()) or log::l(N("mount failed: ") . $!);
	}
    }
}

# write the partition table
sub write {
    my ($hd) = @_;
    $hd->{isDirty} or return;
    $hd->{readonly} and die "a read-only partition table should not be dirty!";

    #- set first primary partition active if no primary partitions are marked as active.
    if (my @l = @{$hd->{primary}{raw}}) {
	foreach (@l) { 
	    $_->{local_start} = $_->{start}; 
	    $_->{active} ||= 0;
	}
	$l[0]{active} = 0x80 if !any { $_->{active} } @l;
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

    if (my $tell_kernel = delete $hd->{will_tell_kernel}) {
	tell_kernel($hd, $tell_kernel);
    }
}

sub active {
    my ($hd, $part) = @_;

    $_->{active} = 0 foreach @{$hd->{primary}{normal}};
    $part->{active} = 0x80;
    $hd->{isDirty} = 1;
}


# remove a normal partition from hard drive hd
sub remove {
    my ($hd, $part) = @_;
    my $i;

    #- first search it in the primary partitions
    $i = 0; foreach (@{$hd->{primary}{normal}}) {
	if ($_ eq $part) {
	    will_tell_kernel($hd, del => $_);

	    splice(@{$hd->{primary}{normal}}, $i, 1);
	    %$_ = (); #- blank it

	    $hd->raw_removed($hd->{primary}{raw});
	    return 1;
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
	assign_device_numbers($hd);

	will_tell_kernel($hd, del => $part);
	return 1;
    }
    0;
}

# create of partition at starting at `start', of size `size' and of type `pt_type' (nice comment, uh?)
sub add_primary {
    my ($hd, $part) = @_;

    {
	local $hd->{primary}{normal}; #- save it to fake an addition of $part, that way add_primary do not modify $hd if it fails
	push @{$hd->{primary}{normal}}, $part;
	adjust_main_extended($hd); #- verify
	$hd->raw_add($hd->{primary}{raw}, $part);
    }
    push @{$hd->{primary}{normal}}, $part; #- really do it
}

sub add_extended {
    arch() =~ /^sparc|ppc/ and die N("Extended partition not supported on this platform");

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
N("You have a hole in your partition table but I can't use it.
The only solution is to move your primary partitions to have the hole next to the extended partitions.");
	}
    }

    if ($e && $part->{start} < $e->{start}) {
	my $l = first(@{$hd->{extended}});

	#- the first is a special case, must recompute its real size
	$l->{start} = round_down($l->{normal}{start} - 1, $hd->cylinder_size);
	$l->{size} = $l->{normal}{start} + $l->{normal}{size} - $l->{start};
	my $ext = { %$l };
	unshift @{$hd->{extended}}, { pt_type => 5, raw => [ $part, $ext, {}, {} ], normal => $part, extended => $ext };
	#- size will be autocalculated :)
    } else {
	my ($ext, $ext_size) = is_empty_array_ref($hd->{extended}) ?
	  ($hd->{primary}, -1) : #- -1 size will be computed by adjust_main_extended
	  (top(@{$hd->{extended}}), $part->{size});
	my %ext = (pt_type => $extended_type || 5, start => $part->{start}, size => $ext_size);

	$hd->raw_add($ext->{raw}, \%ext);
	$ext->{extended} = \%ext;
	push @{$hd->{extended}}, { %ext, raw => [ $part, {}, {}, {} ], normal => $part };
    }
    $part->{start}++; $part->{size}--; #- let it start after the extended partition sector
    adjustStartAndEnd($hd, $part);

    adjust_main_extended($hd);
}

sub add {
    my ($hd, $part, $b_primaryOrExtended, $b_forceNoAdjust) = @_;

    get_normal_parts($hd) >= ($hd->{device} =~ /^rd/ ? 7 : $hd->{device} =~ /^(sd|ida|cciss|ataraid)/ ? 15 : 63) and cdie "maximum number of partitions handled by linux reached";

    $part->{notFormatted} = 1;
    $part->{isFormatted} = 0;
    $part->{rootDevice} = $hd->{device};
    $part->{start} ||= 1 if arch() !~ /^sparc/; #- starting at sector 0 is not allowed
    adjustStartAndEnd($hd, $part) unless $b_forceNoAdjust;

    my $nb_primaries = $hd->{device} =~ /^rd/ ? 3 : 1;

    if (arch() =~ /^sparc|ppc/ ||
	$b_primaryOrExtended eq 'Primary' ||
	$b_primaryOrExtended !~ /Extended/ && @{$hd->{primary}{normal} || []} < $nb_primaries) {
	eval { add_primary($hd, $part) };
	goto success if !$@;
    }
    if ($hd->hasExtended) {
	eval { add_extended($hd, $part, $b_primaryOrExtended) };
	goto success if !$@;
    }
    {
	add_primary($hd, $part);
    }
  success:
    assign_device_numbers($hd);
    will_tell_kernel($hd, add => $part);
}

# search for the next partition
sub next {
    my ($hd, $part) = @_;

    first(
	  sort { $a->{start} <=> $b->{start} }
	  grep { $_->{start} >= $part->{start} + $part->{size} }
	  get_normal_parts($hd)
	 );
}
sub next_start {
    my ($hd, $part) = @_;
    my $next = &next($hd, $part);
    $next ? $next->{start} : $hd->{totalsectors};
}

sub load {
    my ($hd, $file, $b_force) = @_;

    open(my $F, $file) or die N("Error reading file %s", $file);

    my $h;
    {
	local $/ = "\0";
	eval <$F>;
    }
    $@ and die N("Restoring from file %s failed: %s", $file, $@);

    ref($h) eq 'ARRAY' or die N("Bad backup file");

    my %h; @h{@fields2save} = @$h;

    $h{totalsectors} == $hd->{totalsectors} or $b_force or cdie "bad totalsectors";

    #- unsure we don't modify totalsectors
    local $hd->{totalsectors};

    @$hd{@fields2save} = @$h;

    delete @$_{qw(isMounted isFormatted notFormatted toFormat toFormatUnsure)} foreach get_normal_parts($hd);
    will_tell_kernel($hd, 'force_reboot'); #- just like undo, do not force write_partitions so that user can see the new partition table but can still discard it
}

sub save {
    my ($hd, $file) = @_;
    my @h = @$hd{@fields2save};
    require Data::Dumper;
    eval { output($file, Data::Dumper->Dump([\@h], ['$h']), "\0") }
      or die N("Error writing to file %s", $file);
}
