package Newt; # $Id$

use strict;
use vars qw($VERSION @ISA);
use DynaLoader;

use vars qw($VERSION @ISA);
@ISA = qw(DynaLoader);
$VERSION = '0.01';
Newt->bootstrap($VERSION);

package Newt::Component;

our @ISA = qw(); # help perl_checker

package Newt::Grid;

our @ISA = qw(); # help perl_checker

1;
