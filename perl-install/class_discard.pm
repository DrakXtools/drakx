package class_discard; # $Id$

use log;

sub new { bless {}, "class_discard" }

sub AUTOLOAD {
    log::l("class_discard: $AUTOLOAD called at ", caller);
}

1;
