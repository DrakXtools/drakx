package partition_table::readonly;

use diagnostics;
use strict;

our @ISA = qw(partition_table::raw);

use common;
use partition_table::raw;
use fs::type;

sub initialize {
    my ($class, $hd, $parts) = @_;

    $hd->{readonly} = $hd->{getting_rid_of_readonly_allowed} = 1;
    $hd->{primary} = { normal => $parts };
    delete $hd->{extended};

    bless $hd, $class;
}
