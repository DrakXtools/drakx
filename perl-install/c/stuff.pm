package c::stuff; # $Id$

use strict;
use vars qw($VERSION @ISA);

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '0.01';

bootstrap c::stuff $VERSION;

sub from_utf8 { iconv($_[0], "utf-8", standard_charset()) }
sub to_utf8 { iconv($_[0], standard_charset(), "utf-8") }

1;
