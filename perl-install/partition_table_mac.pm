package partition_table_mac;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table_raw);

use common qw(:common :system :file :functional);
use partition_table_raw;
use partition_table;
use c;

my %typeToDos = (
  "Apple_partition_map" => 0x401,
  "Apple_Driver43"	=> 0x401,
  "Apple_Driver_IOKit"	=> 0x401,
  "Apple_Patches"	=> 0x401,
  "Apple_HFS"		=> 0x402,
  "Apple_UNIX_SVR2"	=> 0x83,
  "Apple_Free"		=> 0x0,
);
my %typeFromDos = reverse %typeToDos;


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

sub adjustStart($$) {
    my ($hd, $part) = @_;
}
sub adjustEnd($$) {
    my ($hd, $part) = @_;
}

sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $sector, 0) or die "reading of partition in sector $sector failed";

    sysread F, $tmp, psizeof($bz_format) or die "error while reading bz \(Block Zero\) in sector $sector";
    my %info; @info{@$bz_fields} = unpack $bz_format, $tmp;
    my $i;

    foreach $i (0 .. $info{bzDrvrCnt}-1) {
        sysread F, $tmp, psizeof($dd_format) or die "error while reading driver data in sector $sector";
        $info{ddMap}[$i] = unpack $dd_format, $tmp;
    }

    #- check magic number
    $info{bzSig}  == $magic or die "bad magic number";

    my $numparts;
    c::lseek_sector(fileno(F), $sector, 516) or die "reading of partition in sector $sector failed";
    sysread F, $tmp, 4 or die "error while reading partition info in sector $sector";
    $numparts = unpack "N", $tmp;

    my $partmapsize;
    c::lseek_sector(fileno(F), $sector, 524) or die "reading of partition in sector $sector failed";
    sysread F, $tmp, 4 or die "error while reading partition info in sector $sector";
    $partmapsize = ((unpack "N", $tmp) * $info{bzBlkSize}) / psizeof($p_format);

    c::lseek_sector(fileno(F), $sector, 512) or die "reading of partition in sector $sector failed";

    my @pt;
    for($i=0;$i<$partmapsize;$i++) {
    	my $part;
        sysread F, $part, psizeof($p_format) or die "error while reading partition info in sector $sector";

        push @pt, map {
            my %h; @h{@$p_fields} = unpack $p_format, $part;
            if ($i < $numparts && $h{pSig} eq $pmagic) {

                $h{size} = ($h{pPBlocks} * $info{bzBlkSize}) / 512;
                $h{start} = ($h{pPBlockStart} * $info{bzBlkSize}) / 512;

                if ($h{pType} =~ /^Apple_UNIX_SVR2/i) {
                    $h{pName} =~ /swap/i ? ($h{type} = 0x82) : ($h{type} = 0x83);
                } elsif ($h{pType} =~ /^Apple_Free/i) {
                    $h{type} = 0x0;
                } elsif ($h{pType} =~ /^Apple_HFS/i) {
                 	$h{type} = 0x402;
                } elsif ($h{pType} =~ /^Apple_Partition_Map/i) {
                 	$h{type} = 0x401;
                 	$h{isMap} = 1;
                } else {
                 	$h{type} = 0x401;
                };
            }
            \%h;
        } [ $part ];
    };

    [ @pt ], \%info;
}

sub write($$$;$) {
    my ($hd, $sector, $pt, $info) = @_;

    #- handle testing for writing partition table on file only!
    local *F;
    if ($::testing) {
	my $file = "/tmp/partition_table_$hd->{device}";
	open F, ">$file" or die "error opening test file $file";
    } else {
	partition_table_raw::openit($hd, *F, 2) or die "error opening device $hd->{device} for writing";
        c::lseek_sector(fileno(F), $sector, 0) or return 0;
    }

    # Find the partition map.
    my @partstowrite;
    my $part = $pt->[0];
    (defined $part->{isMap}) or die "the first partition is not the partition map";
    push @partstowrite, $part;

    # Now go thru the partitions, sort and fill gaps.
    my $last;
    while($part) {
        $last = $part;
        $part = &partition_table::next($hd, $part);
        $part or last;

        if($last->{start} + $last->{size} < $part->{start}) {
            #There is a gap between partitions.  Fill it and move on.
            push @partstowrite, {
                type => 0x0,
                start => $last->{start} + $last->{size},
                size => $part->{start} - ($last->{start} + $last->{size}),
            };
        }
        push @partstowrite, $part;
    };

    # now, fill a gap at the end if there is one.
    if($last->{start} + $last->{size} < $hd->{totalsectors}) {
        push @partstowrite, {
            type => 0x0,
            start => $last->{start} + $last->{size},
            size => $hd->{totalsectors} - ($last->{start} + $last->{size}),
     	};
    }

    # Since we didn't create any new drivers, let's try and match up our driver records with out partitons and see if any are missing.
    my $i;
    my @ddstowrite;
    foreach $i ( 0 .. $info->{bzDrvrCnt} - 1) {
        my $ddBlock = $_->{ddBlock};
        my $dd = $_;
        foreach(@partstowrite) {
            $ddBlock == $_->{pPBlockStart} and push @ddstowrite, $dd;
        }
    }

    # Now let's write our first block.
    syswrite F, pack($bz_format, @$info{@$bz_fields}), psizeof($bz_format) or return 0;

    # ...and now the driver information.
    foreach $i ( 0 .. $info->{bzDrvrCnt} - 1) {
        syswrite F, pack($dd_format, $ddstowrite[$i]{@$dd_fields}), psizeof($dd_format) or return 0;
    }
    # zero the rest of the data in the first block.
    foreach $i ( 1 .. (494 - ($info->{bzDrvrCnt} * 8))) {
     	syswrite F, "\0", 1 or return 0;
    }
    #c::lseek_sector(fileno(F), $sector, 512) or return 0;
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

            if($_->{type} == 0x402) {
                $_->{pType} = "Apple_HFS";
                $_->{pName} = "MacOS";
                $_->{pFlags} = 0x4000037F;
            } elsif ($_->{type} == 0x401 && $_->{start} == 1) {
                $_->{pType} = "Apple_Partition_Map";
                $_->{pName} = "Apple";
                $_->{pFlags} = 0x33;
            } elsif ($_->{type} == 0x82) {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "swap";
                $_->{pFlags} = 0x33;
            } elsif ($_->{type} == 0x83) {
                $_->{pType} = "Apple_UNIX_SVR2";
                $_->{pName} = "Linux Native";
                $_->{pFlags} = 0x33;
            } elsif ($_->{type} == 0x0) {
                $_->{pType} = "Apple_Free";
                $_->{pName} = "Extra";
                $_->{pFlags} = 0x31;
            }
        };
        $_->{pMapEntry} = @partstowrite;
        syswrite F, pack($p_format, @$_{@$p_fields}), psizeof($p_format) or return 0;
    }

    sync();

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
    my $pt = { raw => [ ({}) x 63 ], info => info($hd) };

    #- handle special case for partition 1 which is the partition map.
    my $part = {
        type => 0x401,
        start => 1,
        size => 63,
        isMap => 1,
    };

    $pt->{raw}[0] = $part;
    push @{$pt->{normal}}, $part;
    $pt;
}

1;
