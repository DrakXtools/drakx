package c;

use vars qw($AUTOLOAD);

use c::stuff;
use MDK::Common;

sub AUTOLOAD() {
    $AUTOLOAD =~ /::(.*)/ or return;
    my $fct = $1;
    my @l = eval { &{$c::stuff::{$fct}} };
    if (my $err = $@) {
	$err =~ /Undefined subroutine &main::/ ?
	  die("cannot find function $AUTOLOAD\n" . backtrace()) :
	  die("$fct: " . $err);	
    }
    wantarray() ? @l : $l[0];
}

1;
