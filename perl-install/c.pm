package c; # $Id$

use vars qw($AUTOLOAD);

use c::stuff;

sub AUTOLOAD {
    $AUTOLOAD =~ /::(.*)/;
    goto &{$c::stuff::{$1}};
}

1;
