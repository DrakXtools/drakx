package partition_table::dmcrypt;

# dmcrypt on full disk

use diagnostics;
use strict;

our @ISA = qw(partition_table::readonly);

use common;
use partition_table::readonly;
use fs::type;

sub _parts {
    my ($hd) = @_;

    my $part = { size => $hd->{totalsectors}, device => $hd->{device} };
    add2hash($part, fs::type::type_name2subpart('Encrypted'));

    require fs;
    fs::get_major_minor([$part]); # to allow is_same_hd() in fs::dmcrypt

    [ $part ];
}

sub read_primary {
    my ($hd) = @_;

    my $type = fs::type::type_subpart_from_magic($hd);

    $type && $type->{type_name} eq 'Encrypted' or return;

    partition_table::dmcrypt->initialize($hd);
    1;
}

sub initialize {
    my ($class, $hd) = @_;

    partition_table::readonly::initialize($class, $hd, _parts($hd));    
}
