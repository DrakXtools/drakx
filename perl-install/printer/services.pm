package printer::services;

use strict;
use services;
use run_program;

sub restart ($) {
    my ($service) = @_;
    if (services::restart($service)) {
	# CUPS needs some time to come up.
	wait_for_cups() if $service eq "cups";
	return 1;
    } else { return 0 }
}

sub start ($) {
    my ($service) = @_;
    if (services::start($service)) {
	# CUPS needs some time to come up.
	wait_for_cups() if $service eq "cups";
	return 1;
    } else { return 0 }
}

sub start_not_running_service ($) {
    my ($service) = @_;
    # The exit status is not zero when the service is not running
    if (services::start_not_running_service($service)) {
	return 0;
    } else { 
	run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "start");
	if (($? >> 8) != 0) {
	    return 0;
	} else {
	    # CUPS needs some time to come up.
	    wait_for_cups() if $service eq "cups";
	    return 1;
	}
    }
}

sub wait_for_cups() {
    # CUPS needs some time to come up. Wait up to 30 seconds, checking
    # whether CUPS is ready.
    my $cupsready = 0;
    my $i;
    for ($i = 0; $i < 30; $i++) {
	# Check whether CUPS is running without any console output
	system(($::testing ? $::prefix : "chroot $::prefix/ ") . 
	    "/usr/bin/lpstat -r >/dev/null 2>&1");
	if (($? >> 8) != 0) {
	    # CUPS is not ready, continue
	    sleep 1;
	} else {
	    # CUPS is ready, quit
	    $cupsready = 1;
	    last;
	}
    }
    return $cupsready;
}

1;
