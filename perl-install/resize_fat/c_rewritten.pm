package resize_fat::c_rewritten; # $Id$

use strict;

require DynaLoader;

our @ISA = qw(DynaLoader);
our $VERSION = '0.01';
our @EXPORT_OK = qw(next set_next);

resize_fat::c_rewritten->bootstrap($VERSION);

1;

