package c; # $Id$

use vars qw($AUTOLOAD);

use c::stuff;
use MDK::Common;

sub AUTOLOAD {
    $AUTOLOAD =~ /::(.*)/;
    my @l = eval { &{$c::stuff::{$1}} };
    if (my $err = $@) {
	$err =~ /Undefined subroutine &main::/ ?
	  die("can't find function $AUTOLOAD\n" . backtrace()) :
	  die($err);	
    }
    wantarray() ? @l : $l[0];
}

1;
