package network::dav; # $Id$

use strict;
use diagnostics;

use common;

sub check {
    my ($class, $in) = @_;
    $in->do_pkgs->ensure_is_installed('davfs', '/sbin/mount.davfs');
}
