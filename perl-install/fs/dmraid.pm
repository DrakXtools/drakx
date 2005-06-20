package fs::dmraid; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;
use devices;
use fs::type;
use run_program;


init() or log::l("dmraid::init failed");

sub init() {
    eval { modules::load('dm-mirror') };
    devices::init_device_mapper();
    if ($::isInstall) {
	run_program::run('dmraid', '-ay');
    }
    1;
}

sub check {
    my ($in) = @_;

    $in->do_pkgs->ensure_binary_is_installed('dmraid', 'dmraid') or return;
    init();
    1;
}

sub pvs_and_vgs() {
    map {
	my @l = split(':');
	{ pv => $l[0], format => $l[1], vg => $l[2], level => $l[3], status => $l[4] };
    } run_program::get_stdout('dmraid', '-rcc');
}

sub vgs() {
    map {
	my $dev = "mapper/$_->{vg}";
	my $vg = fs::subpart_from_wild_device_name("/dev/$dev");
	add2hash($vg, { media_type => 'hd', prefix => $dev, bus => "dm_$_->{format}" });
	$vg;
    } grep { $_->{status} eq 'ok' } uniq_ { $_->{vg} } pvs_and_vgs();
}

sub pvs() {
    map { $_->{pv} } grep { $_->{status} eq 'ok' } pvs_and_vgs();
}

1;
