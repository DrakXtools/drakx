package partition_table::lvm_PV; # $Id$

use diagnostics;
use strict;

our @ISA = qw(partition_table::raw);

use partition_table::raw;
use c;


#- Allows people having PVs on unpartitioned disks to install
#- (but no way to create such beasts)
#-
#- another way to handle them would be to ignore those disks,
#- but this would make those hds unshown in diskdrake,
#- disallowing to zero_MBR, clearing this PV


sub read {
    my ($hd, $sector) = @_;

    my $t = fs::type::type_subpart_from_magic($hd);

    $t && $t->{pt_type} eq 0x8e or die "bad magic number on disk $hd->{device}";

    [];
}

sub write { 
    die "ERROR: should not be writing raw disk lvm PV!!";
}

sub clear_raw {
    die "ERROR: should not be creating new raw disk lvm PV!!";
}

1;
