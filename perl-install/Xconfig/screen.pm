package Xconfig::screen; # $Id$

use diagnostics;
use strict;

use common;


sub configure {
    my ($raw_X) = @_;

    my @devices = $raw_X->get_devices;
    my @monitors = $raw_X->get_monitors;

    if (@monitors < @devices) {
	$raw_X->set_monitors(@monitors, ({}) x (@devices - @monitors));
	@monitors = $raw_X->get_monitors;
    }

    my @sections = mapn {
	my ($device, $monitor) = @_;
	{ Device => $device->{Identifier}, Monitor => $monitor->{Identifier} };
    } \@devices, \@monitors;

    $raw_X->set_screens(@sections);
    1;
}

1;
