package partition_table::empty; # $Id$

#- this is a mainly dummy partition table. If we find it's empty, we just call -
#- ->clear which will take care of bless'ing us to the partition table type best
#- suited


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use partition_table;
use c;


sub read_one {
    my ($hd, $sector) = @_;
    my $tmp;

    my $F = partition_table::raw::openit($hd) or die "failed to open device";
    c::lseek_sector(fileno($F), $sector, 0) or die "reading of partition in sector $sector failed";

    #- check magic number
    sysread $F, $tmp, 1024 or die "error reading magic number on disk $hd->{device}";
    $tmp eq substr($tmp, 0, 1) x 1024 or die "bad magic number on disk $hd->{device}";

    partition_table::raw::clear($hd);

    $hd->{primary}{raw}, $hd->{primary}{info};
}

1;
