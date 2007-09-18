package partition_table::lvm; # $Id: $

# LVM on full disk

use diagnostics;
use strict;

1;

use common;
use fs::type;
use lvm;

sub _parts {
    my ($hd) = @_;

    my $part = { size => $hd->{totalsectors}, device => $hd->{device} };
    add2hash($part, fs::type::type_name2subpart('Linux Logical Volume Manager'));

    [ $part ];
}

sub read_primary {
    my ($hd) = @_;

    my $wanted = fs::type::type_name2subpart('Linux Logical Volume Manager');
    my $type = fs::type::type_subpart_from_magic($hd);

    $type && $type->{pt_type} == $wanted->{pt_type} or return;

    require partition_table::readonly;
    partition_table::readonly->initialize($hd, _parts($hd));

    1;
}
