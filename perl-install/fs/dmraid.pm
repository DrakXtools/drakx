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
use fs::wild_device;
use run_program;


init() or log::l("dmraid::init failed");

sub init() {
    eval { modules::load('dm-mirror') };
    devices::init_device_mapper();
    if ($::isInstall) {
	call_dmraid('-ay');
    }
    1;
}

#- call_dmraid is overloaded when debugging, see the end of this file
sub call_dmraid {
    my ($option) = @_;
    run_program::get_stdout('dmraid', $option);
}

sub check {
    my ($in) = @_;

    $in->do_pkgs->ensure_binary_is_installed('dmraid', 'dmraid') or return;
    init();
    1;
}

sub _raid_devices_raw() {
    map {
	chomp;
	my %l; @l{qw(pv format vg level status size)} = split(':');
	\%l;
    } call_dmraid('-ccr');
}

sub _raid_devices() {
    my @l = _raid_devices_raw();
    my %vg2pv; push @{$vg2pv{$_->{vg}}}, delete $_->{pv} foreach @l;
    map {
	delete $_->{size}; #- now irrelevant
	$_->{disks} = $vg2pv{$_->{vg}};
	$_;
    } uniq_ { $_->{vg} } @l;
}

sub _sets_raw() {
    map {
	chomp;
	my %l; @l{qw(name size stride level status subsets devs spares)} = split(':');
	\%l;
    } call_dmraid('-ccs');
}

sub _sets() {
    my @sets = _sets_raw();
    my @raid_devices = _raid_devices();
    foreach (@sets) {
	my $name = $_->{name};
	my @l = grep { begins_with($name, $_->{vg}) } @raid_devices;
	if (@l) {
	    log::l("ERROR: multiple match for set $name: " . join(' ', map { $_->{vg} } @l)) if @l > 1;
	    my ($raid) = @l;
	    add2hash($_, $raid);
	} else {
	    log::l("ERROR: no matching raid devices for set $name");
	}
    }
    @sets;
}

sub vgs() {
    map {
	my $dev = "mapper/$_->{name}";
	my $vg = fs::wild_device::to_subpart("/dev/$dev");
	add2hash($vg, { media_type => 'hd', prefix => $dev, bus => "dm_$_->{format}", disks => $_->{disks} });

	#- device should exist, created by dmraid(8) using libdevmapper
	#- if it doesn't, we suppose it's not in use
	if_(-e "/dev/$dev", $vg); 

    } grep { $_->{status} eq 'ok' } _sets();
}

if ($ENV{DRAKX_DEBUG_DMRAID}) {
    eval(<<'EOF');
    my %debug_data = (
    
     isw => {
    
      # dmraid -s ####################
      # *** Group superset isw_ffafgbdhi
      # --> Active Subset
      # name   : isw_ffafgbdhi_toto
      # size   : 234441216
      # stride : 256
      # type   : mirror
      # status : ok
      # subsets: 0
      # devs   : 2
      # spares : 0
    
      '-ccs' => "isw_ffafgbdhi_toto:234441216:256:mirror:ok:0:2:0\n",
    
      # dmraid -r ####################
      #/dev/sda: isw, "isw_ffafgbdhi", GROUP, ok, 488397166 sectors, data@ 0
      #/dev/sdb: isw, "isw_ffafgbdhi", GROUP, ok, 234441646 sectors, data@ 0
    
      '-ccr' => "/dev/sda:isw:isw_ffafgbdhi:GROUP:ok:488397166:0\n" .
                "/dev/sdb:isw:isw_ffafgbdhi:GROUP:ok:234441646:0\n",
     },
    
     pdc => {
      # dmraid -s ####################
      # *** Active Set
      # name   : pdc_bcefbiigfg
      # size   : 80043200
      # stride : 128
      # type   : mirror
      # status : ok
      # subsets: 0
      # devs   : 2
      # spares : 0
    
      '-ccs' => "pdc_bcefbiigfg:80043200:128:mirror:ok:0:2:0\n",
    
      # dmraid -r ####################
      # /dev/sda: pdc, "pdc_bcefbiigfg", mirror, ok, 80043200 sectors, data@ 0
      # /dev/sdb: pdc, "pdc_bcefbiigfg", mirror, ok, 80043200 sectors, data@ 0
    
      '-ccr' => "/dev/sda:pdc:pdc_bcefbiigfg:mirror:ok:80043200:0\n" .
                "/dev/sdb:pdc:pdc_bcefbiigfg:mirror:ok:80043200:0\n",
      },
    
    );
    
    *call_dmraid = sub {
        my ($option) = @_;
        my $s = $debug_data{$ENV{DRAKX_DEBUG_DMRAID}}{$option} or return;
        split("\n", $s);
    };
EOF
}

1;
