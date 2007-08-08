package partition_table::mac; # $Id$

use diagnostics;
#use strict;   - fixed other PPC code to comply, but program bails on empty partition table - sbenedict
use vars qw(@ISA $freepart $bootstrap_part $macos_part $new_bootstrap);

@ISA = qw(partition_table::raw);

use common;
use fs::type;
use partition_table::raw;
use partition_table;
use c;

my %_typeToDos = (
  "Apple_partition_map" => 0x401,
  "Apple_Bootstrap"	=> 0x401,
  "Apple_Driver43"	=> 0x401,
  "Apple_Driver_IOKit"	=> 0x401,
  "Apple_Patches"	=> 0x401,
  "Apple_HFS"		=> 0x402,
  "Apple_UNIX_SVR2"	=> 0x83,
  "Apple_UNIX_SVR2"     => 0x183,
  "Apple_UNIX_SVR2"     => 0x283,
  "Apple_UNIX_SVR2"     => 0x383,
  "Apple_UNIX_SVR2"     => 0x483,
  "Apple_Free"		=> 0x0,
);


my ($bz_format, $bz_fields) = list2kv(
  n	=> 'bzSig',
  n	=> 'bzBlkSize',
  N	=> 'bzBlkCnt',
  n	=> 'bzDevType',
  n	=> 'bzDevID',
  N	=> 'bzReserved',
  n	=> 'bzDrvrCnt',
);
$bz_format = join '', @$bz_format;


my ($dd_format, $dd_fields) = list2kv(
  N	=> 'ddBlock',
  n	=> 'ddSize',
  n	=> 'ddType',
);
$dd_format = join '', @$dd_format;


my ($p_format, $p_fields) = list2kv(
  n	=> 'pSig',
  n	=> 'pSigPad',
  N	=> 'pMapEntry',
  N	=> 'pPBlockStart',
  N	=> 'pPBlocks',

  a32	=> 'pName',
  a32	=> 'pType',

  N	=> 'pLBlockStart',
  N	=> 'pLBlocks',
  N	=> 'pFlags',
  N	=> 'pBootBlock',
  N	=> 'pBootBytes',

  N	=> 'pAddrs1',
  N	=> 'pAddrs2',
  N	=> 'pAddrs3',
  N	=> 'pAddrs4',
  N	=> 'pChecksum',

  a16	=> 'pProcID',
  a128	=> 'pBootArgs',
  a248	=> 'pReserved',
);
$p_format = join '', @$p_format;

my $magic = 0x4552;
my $pmagic = 0x504D;

sub use_pt_type { 1 }

sub first_usable_sector { 1 }

sub adjustStart($$) {
    my ($hd, $part) = @_;
    my $end = $part->{start} + $part->{size};
    my $partmap_end = $hd->{primary}{raw}[0]{size};

    if ($part->{start} <= $partmap_end) {
        $part->{start} = $partmap_end + 1;
        $part->{size} = $end - $part->{start};
    }
}

sub adjustEnd($$) {
    my ($_hd, $_part) = @_;
}

sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, 0) or die "reading of partition in sector $sector failed";

    sysread $F, $tmp, psizeof($bz_format) or die "error while reading bz (Block Zero) in sector $sector";
    my %info; @info{@$bz_fields} = unpack $bz_format, $tmp;

    foreach (1 .. $info{bzDrvrCnt}) {
        sysread $F, $tmp, psizeof($dd_format) or die "error while reading driver data in sector $sector";
        my %dd; @dd{@$dd_fields} = unpack $dd_format, $tmp;
        push @{$info{ddMap}}, \%dd;
    }

    #- check magic number
    $info{bzSig}  == $magic or die "bad magic number on disk $hd->{device}";

    my $numparts;
    c::lseek_sector(fileno($F), $sector, 516) or die "reading of partition in sector $sector failed";
    sysread $F, $tmp, 4 or die "error while reading partition info in sector $sector";
    $numparts = unpack "N", $tmp;

    my $partmapsize;
    c::lseek_sector(fileno($F), $sector, 524) or die "reading of partition in sector $sector failed";
    sysread $F, $tmp, 4 or die "error while reading partition info in sector $sector";
    $partmapsize = ((unpack "N", $tmp) * $info{bzBlkSize}) / psizeof($p_format);

    c::lseek_sector(fileno($F), $sector, 512) or die "reading of partition in sector $sector failed";

    my @pt;
    for (my $i = 0; $i < $partmapsize; $i++) {
    	my $part;
        sysread $F, $part, psizeof($p_format) or die "error while reading partition info in sector $sector";

        push @pt, map {
            my %h; @h{@$p_fields} = unpack $p_format, $part;
            if ($i < $numparts && $h{pSig} eq $pmagic) {

                $h{size} = ($h{pPBlocks} * $info{bzBlkSize}) / 512;
                $h{start} = ($h{pPBlockStart} * $info{bzBlkSize}) / 512;

                if ($h{pType} =~ /^Apple_UNIX_SVR2/i) {
		    $h{fs_type} = $h{pName} =~ /swap/i ? 'swap' : 'ext2';
                } elsif ($h{pType} =~ /^Apple_Free/i) {
                	#- need to locate a 1MB partition to setup a bootstrap on
                	if ($freepart && $freepart->{size} >= 1) {
			    #- already found a suitable partition
                	} else {
			    $freepart = { start => $h{start}, size => $h{size}/2048, hd => $hd, part => "/dev/$hd->{device}" . ($i+1) };
			    log::l("free apple partition found on drive /dev/$freepart->{hd}{device}, block $freepart->{start}, size $freepart->{size}");
                	}
			$h{pt_type} = 0x0;
			$h{pName} = 'Extra';                    
                } elsif ($h{pType} =~ /^Apple_HFS/i) {
			fs::type::set_pt_type(\%h, 0x402);
                 	if (defined $macos_part) {		
                 		#- swag at identifying MacOS - 1st HFS partition
                 	} else {	
                 		$macos_part = "/dev/" . $hd->{device} . ($i+1);
                 		log::l("found MacOS at partition $macos_part");
                 	}
                } elsif ($h{pType} =~ /^Apple_Partition_Map/i) {
                 	$h{pt_type} = 0x401;
                 	$h{isMap} = 1;
                } elsif ($h{pType} =~ /^Apple_Bootstrap/i) {
                 	$h{pt_type} = 0x401;
                 	$h{isBoot} = 1;
                 	if (defined $bootstrap_part) {
                 		#found a bootstrap already - use it, but log the find
                 		log::l("found another apple bootstrap at partition /dev/$hd->{device}" . ($i+1));
                 	} else {
                 		$bootstrap_part = "/dev/" . $hd->{device} . ($i+1);
                 		log::l("found apple bootstrap at partition $bootstrap_part");
                 	}
                } else {
                 	$h{pt_type} = 0x401;
                     $h{isDriver} = 1;
                }

                # Let's see if this partition is a driver.
                foreach (@{$info{ddMap}}) {
                    $_->{ddBlock} == $h{pPBlockStart} and $h{isDriver} = 1;
                }

            }
            \%h;
        } [ $part ];
    }

    [ @pt ], \%info;
}

sub write($$$;$) {
    my ($hd, $sector, $pt, $info) = @_;

    #- handle testing for writing partition table on file only!
    my $F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open $F, ">$file" or die "error opening test file $file";
    } else {
	$F = partition_table::raw::openit($hd, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno($F), $sector, 0) or return 0;
    }

    # Find the partition map.
    my @partstowrite;
    my $part = $pt->[0];
    defined $part->{isMap} or die "the first partition is not the partition map";
    push @partstowrite, $part;

    # Now go thru the partitions, sort and fill gaps.
    my $last;
    while ($part) {
        $last = $part;
        $part = &partition_table::next($hd, $part);
        $part or last;

        if ($last->{start} + $last->{size} < $part->{start}) {
            #There is a gap between partitions.  Fill it and move on.
            push @partstowrite, {
                pt_type => 0x0,
                start => $last->{start} + $last->{size},
                size => $part->{start} - ($last->{start} + $last->{size}),
            };
        }
        push @partstowrite, $part;
    }

    # now, fill a gap at the end if there is one.
    if ($last->{start} + $last->{size} < $hd->{totalsectors}) {
        push @partstowrite, {
            pt_type => 0x0,
            start => $last->{start} + $last->{size},
            size => $hd->{totalsectors} - ($last->{start} + $last->{size}),
     	};
    }

    # Since we did not create any new drivers, let's try and match up our driver records with out partitons and see if any are missing.
    $info->{bzDrvrCnt} = 0;
    my @ddstowrite;
    foreach my $dd (@{$info->{ddMap}}) {
        foreach (@partstowrite) {
            if ($dd->{ddBlock} == $_->{pPBlockStart}) {
            	push @ddstowrite, $dd;
            	$info->{bzDrvrCnt}++;
            	last;
            }
        }
    }

    # Now let's write our first block.
    syswrite $F, pack($bz_format, @$info{@$bz_fields}), psizeof($bz_format) or return 0;

    # ...and now the driver information.
    foreach (@ddstowrite) {
        syswrite $F, pack($dd_format, @$_{@$dd_fields}), psizeof($dd_format) or return 0;
    }
    # zero the rest of the data in the first block.
    foreach (1 .. (494 - ((@ddstowrite) * 8))) {
     	syswrite $F, "\0", 1 or return 0;
    }
    #c::lseek_sector(fileno($F), $sector, 512) or return 0;
    # Now, we iterate thru the partstowrite and write them.
    foreach (@partstowrite) {
        if (!defined $_->{pSig}) {
            # The values we need to write to disk are not defined.  Let's make them up.
            $_->{pSig} = $pmagic;
            $_->{pSigPad} = 0;
            $_->{pPBlockStart} = ($_->{start} * 512) / $info->{bzBlkSize};
            $_->{pPBlocks} = ($_->{size} * 512) / $info->{bzBlkSize};
            $_->{pLBlockStart} = 0;
            $_->{pLBlocks} = $_->{pPBlocks};
            $_->{pBootBlock} = 0;
            $_->{pBootBytes} = 0;
            $_->{pAddrs1} = 0;
            $_->{pAddrs2} = 0;
            $_->{pAddrs3} = 0;
            $_->{pAddrs4} = 0;
            $_->{pChecksum} = 0;
            $_->{pProcID} = "\0";
            $_->{pBootArgs} = "\0";
            $_->{pReserved} = "\0";

            if ($_->{pt_type} == 0x402) {
                $_->{pType} = "Apple_HFS";
                $_->{pName} = "MacOS";
                $_->{pFlags} = 0x4000037F;
            } elsif ($_->{pt_type} == 0x401 && $_->{start} == 1) {
                $_->{pType} = "Apple_Partition_Map";
                $_->{pName} = "Apple";
                $_->{pFlags} = 0x33;
            } elsif ($_->{pt_type} == 0x401) {
                $_->{pType} = "Apple_Bootstrap";
                $_->{pName} = "bootstrap";
                $_->{pFlags} = 0x33;
		$_->{isBoot} = 1;
		log::l("writing a bootstrap at /dev/$_->{device}");
		$new_bootstrap = 1 if !(defined $bootstrap_part);
		$bootstrap_part = "/dev/" . $_->{device};
            } elsif (isSwap($_)) {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "swap";
                $_->{pFlags} = 0x33;
            } elsif ($_->{fs_type} eq 'ext2') {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux Native";
                $_->{pFlags} = 0x33;
            } elsif ($_->{fs_type} eq 'reiserfs') {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux ReiserFS";
                $_->{pFlags} = 0x33;
            } elsif ($_->{fs_type} eq 'xfs') {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux XFS";
                $_->{pFlags} = 0x33;
            } elsif ($_->{fs_type} eq 'jfs') {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux JFS";
                $_->{pFlags} = 0x33;
            } elsif ($_->{fs_type} eq 'ext3') {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux ext3";
                $_->{pFlags} = 0x33;
            } elsif ($_->{pt_type} == 0x0) {
                $_->{pType} = "Apple_Free";
                $_->{pName} = "Extra";
                $_->{pFlags} = 0x31;
            }
        }
        $_->{pMapEntry} = @partstowrite;
        syswrite $F, pack($p_format, @$_{@$p_fields}), psizeof($p_format) or return 0;
    }

    common::sync();

    1;
}

sub info {
    my ($hd) = @_;

    # - Build the first block of the drive.

    my $info = {
	bzSig => $magic,
	bzBlkSize => 512,
	bzBlkCnt => $hd->{totalsectors},
	bzDevType => 0,
	bzDevID => 0,
	bzReserved => 0,
	bzDrvrCnt => 0,
    };

    $info;
}

sub clear_raw {
    my ($hd) = @_;
    my @oldraw = @{$hd->{primary}{raw}};
    my $pt = { raw => [ ({}) x 63 ], info => info($hd) };

    #- handle special case for partition 1 which is the partition map.
    $pt->{raw}[0] = {
        pt_type => 0x401,
        start => 1,
        size => 63,
        isMap => 1,
    };
#	$pt->{raw}[1] = {
#		pt_type => 0x0,
#		start => 64,
#		size => $hd->{totalsectors} - 64,
#		isMap => 0,
#	};
    push @{$pt->{normal}}, $pt->{raw}[0];
#	push @{$pt->{normal}}, $pt->{raw}[1];

    #- Recover any Apple Drivers, if any.
    my $i = 1;
    foreach (@oldraw) {
        if (defined $_->{isDriver}) {
            $pt->{raw}[$i] = $_;
            push @{$pt->{normal}}, $pt->{raw}[$i];
            $i++;
        }
    }
    @{$pt->{info}{ddMap}} = @{$hd->{primary}{info}{ddMap}};

    $pt;
}

1;
