package swap; # $Id$

use diagnostics;
use strict;

use common;
use log;
use devices;

sub make {
    my ($dev, $checkBlocks) = @_;
    run_program::raw({ timeout => 60 * 60 }, "mkswap_", if_($checkBlocks, '-c'), devices::make($dev)) or die \N("%s formatting of %s failed", 'swap', $dev);
}

sub enable {
    my ($dev, $checkBlocks) = @_;
    make($dev, $checkBlocks);
    swapon($dev);
}

sub swapon {
    my ($dev) = @_;
    log::l("swapon called with $dev");
    syscall_('swapon', devices::make($dev), 0) or die "swapon($dev) failed: $!";
}

sub swapoff($) {
    my ($dev) = @_;
    syscall_('swapoff', devices::make($dev)) or die "swapoff($dev) failed: $!";
}

1;
