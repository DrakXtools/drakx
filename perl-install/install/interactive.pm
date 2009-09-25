package install::interactive; # $Id$

use diagnostics;
use strict;

use common;
use detect_devices;
use install::steps;
use log;


sub tellAboutProprietaryModules {
    my ($o) = @_;
    my @l = detect_devices::probe_name('Bad') or return;
    $o->ask_warn('', formatAlaTeX(
N("Some hardware on your computer needs ``proprietary'' drivers to work.
You can find some information about them at: %s", join(", ", @l))));
}

sub upNetwork {
    my ($o, $b_pppAvoided) = @_;
    my $_w = $o->wait_message('', N("Bringing up the network"));
    install::steps::upNetwork($o, $b_pppAvoided);
}
sub downNetwork {
    my ($o, $b_pppOnly) = @_;
    my $_w = $o->wait_message('', N("Bringing down the network"));
    install::steps::downNetwork($o, $b_pppOnly);
}



1;
