package partition_table_lvm; # $Id$

use diagnostics;
use strict;

our @ISA = qw(partition_table_raw);

use partition_table_raw;
use c;

my $magic = "HM\1\0";
my $offset = 0;


#- Allows people having PVs on unpartitioned disks to install
#- (but no way to create such beasts)
#-
#- another way to handle them would be to ignore those disks,
#- but this would make those hds unshown in diskdrake,
#- disallowing to zero_MBR, clearing this PV


sub read {
    my ($hd, $sector) = @_;

    local *F; partition_table_raw::openit($hd, *F) or die "failed to open device";
    c::lseek_sector(fileno(F), $sector, $offset) or die "reading of partition in sector $sector failed";

    sysread F, my $tmp, length $magic or die "error reading magic number on disk $hd->{file}";
    $tmp eq $magic or die "bad magic number on disk $hd->{file}";

    [ ];
}

sub write { 
    die "ERROR: should not be writing raw disk lvm PV!!";
}

sub clear_raw {
    die "ERROR: should not be creating new raw disk lvm PV!!";
}

1;
