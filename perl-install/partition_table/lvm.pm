package partition_table::lvm; # $Id: $

# LVM on full disk

use diagnostics;
use strict;

our @ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use fs::type;
use lvm;

sub initialize {
    my ($class, $hd) = @_;

    my $part = { size => $hd->{totalsectors}, device => $hd->{device} };
    add2hash($part, fs::type::type_name2subpart('Linux Logical Volume Manager'));

    $hd->{readonly} = $hd->{getting_rid_of_readonly_allowed} = 1;
    $hd->{primary}{normal} = [ $part ];   

    bless $hd, $class;
}
