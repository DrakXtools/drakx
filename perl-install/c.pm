package c;

use strict;
use vars qw($VERSION @ISA);

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '0.01';

bootstrap c $VERSION;

1;

sub headerGetEntry {
    my ($h, $q) = @_;

    $q eq 'name' and return headerGetEntry_string($h, RPMTAG_NAME());
    $q eq 'group' and return headerGetEntry_string($h, RPMTAG_GROUP());
    $q eq 'version' and return headerGetEntry_string($h, RPMTAG_VERSION());
    $q eq 'release' and return headerGetEntry_string($h, RPMTAG_RELEASE());
    $q eq 'arch' and return headerGetEntry_string($h, RPMTAG_ARCH());
    $q eq 'size' and return headerGetEntry_int($h, RPMTAG_SIZE());
}

