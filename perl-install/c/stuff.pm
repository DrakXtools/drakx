package c::stuff; # $Id$

use strict;
use vars qw($VERSION @ISA);

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '0.01';

bootstrap c::stuff $VERSION;

sub from_utf8 { iconv($_[0], "utf-8", standard_charset()) }
sub to_utf8 { iconv($_[0], standard_charset(), "utf-8") }

sub headerGetEntry {
    my ($h, $q) = @_;
    $h or log::l("empty header in headerGetEntry"), return;
    $q eq 'name' and return headerGetEntry_string($h, RPMTAG_NAME());
    $q eq 'group' and return from_utf8(headerGetEntry_string($h, RPMTAG_GROUP()));
    $q eq 'version' and return headerGetEntry_string($h, RPMTAG_VERSION());
    $q eq 'release' and return headerGetEntry_string($h, RPMTAG_RELEASE());
    $q eq 'epoch' and return headerGetEntry_int($h, RPMTAG_EPOCH());
    $q eq 'summary' and return from_utf8(headerGetEntry_string($h, RPMTAG_SUMMARY()));
    $q eq 'description' and return from_utf8(headerGetEntry_string($h, RPMTAG_DESCRIPTION()));
    $q eq 'arch' and return headerGetEntry_string($h, RPMTAG_ARCH());
    $q eq 'size' and return headerGetEntry_int($h, RPMTAG_SIZE());
    $q eq 'obsoletes' and return headerGetEntry_string_list($h, RPMTAG_OBSOLETES());
    $q eq 'requires' and return headerGetEntry_string_list($h, RPMTAG_REQUIRENAME());
    $q eq 'fileflags' and return headerGetEntry_int_list($h, RPMTAG_FILEFLAGS());
    $q eq 'filenames' and return headerGetEntry_filenames($h);
}

1;
