package Xconfig::screen; # $Id$

use diagnostics;
use strict;

use common;


sub configure {
    my ($raw_X, $card) = @_;

    my @devices = $raw_X->get_devices;
    my @monitors = $raw_X->get_monitors;

    if (@monitors < @devices) {
	$raw_X->set_monitors(@monitors, ({}) x (@devices - @monitors));
	@monitors = $raw_X->get_monitors;
    }

    if ($card->{server}) {
	$raw_X->{xfree3}->set_screens({ Device => $devices[0]{Identifier}, Monitor => $monitors[0]{Identifier},
					Driver => $Xconfig::card::serversdriver{$card->{server}} || internal_error("bad XFree3 server $card->{server}"),
				      });
    } else {
	@{$raw_X->{xfree3}} = ();
    }

    if ($card->{Driver}) {
	my @sections = mapn {
	    my ($device, $monitor) = @_;
	    { Device => $device->{Identifier}, Monitor => $monitor->{Identifier} }
	} \@devices, \@monitors;

	$raw_X->{xfree4}->set_screens(@sections);
    } else {
	@{$raw_X->{xfree4}} = ();
    }

    1;
}

1;
