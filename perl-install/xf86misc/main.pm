package xf86misc::main; # $Id$

use strict;
use vars qw($VERSION @ISA);
use DynaLoader;

use vars qw($VERSION @ISA);
@ISA = qw(DynaLoader);
$VERSION = '0.01';
xf86misc::main->bootstrap($VERSION);

1;
