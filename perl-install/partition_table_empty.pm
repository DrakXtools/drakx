package partition_table_empty; # $Id$

#- this is a mainly dummy partition table. If we find it's empty, we just call -
#- zero_MBR which will take care of bless'ing us to the partition table type best
#- suited


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table_raw);

use common;
use partition_table_raw;
use partition_table;
use c;


sub read($$) {
    my ($hd, $sector) = @_;
    my $tmp;

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $sector, 0) or die "reading of partition in sector $sector failed";

    #- check magic number
    sysread F, $tmp, 512 or die "error reading magic number on disk $hd->{device}";
    $tmp eq substr($tmp, 0, 1) x 512 or die "bad magic number on disk $hd->{device}";

    partition_table_raw::zero_MBR($hd);

    $hd->{primary}{raw};
}

1;
