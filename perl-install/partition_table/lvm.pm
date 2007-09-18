package partition_table::lvm; # $Id: $

# LVM on full disk

use diagnostics;
use strict;

our @ISA = qw(partition_table::readonly);

use common;
use partition_table::readonly;
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

    partition_table::lvm->initialize($hd);
    1;
}

sub initialize {
    my ($class, $hd) = @_;

    partition_table::readonly::initialize($class, $hd, _parts($hd));    
}
