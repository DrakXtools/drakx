package network::dav; # $Id$

use strict;
use diagnostics;

use common;

sub check {
    my ($class, $in) = @_;
    $class->raw_check($in, 'davfs', '/sbin/mount.davfs');
}
