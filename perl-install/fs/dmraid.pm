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


sub init() {
    whereis_binary('dmraid') or die "dmraid not installed";

    eval { modules::load('dm-mirror') };
    devices::init_device_mapper();
    if ($::isInstall) {
	call_dmraid('-ay');
    }
    1;
}

#- call_dmraid is overloaded when debugging, see the end of this file
sub call_dmraid {
    my ($option, @args) = @_;
    run_program::get_stdout('dmraid', $option, @args);
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
	log::l("got: $_");
	my %l; @l{qw(pv format vg level status size)} = split(':');
	if_(defined $l{size}, \%l);
    } call_dmraid('-ccr');
}

sub _raid_devices() {
    my @l = _raid_devices_raw();
    my %vg2pv; push @{$vg2pv{$_->{vg}}}, delete $_->{pv} foreach @l;
    my %vg2status; push @{$vg2status{$_->{vg}}}, delete $_->{status} foreach @l;
    map {
	delete $_->{size}; #- now irrelevant
	$_->{disks} = $vg2pv{$_->{vg}};
	$_->{status} = (every { $_ eq 'ok' } @{$vg2status{$_->{vg}}}) ? 'ok' : join(' ', @{$vg2status{$_->{vg}}});
	$_;
    } uniq_ { $_->{vg} } @l;
}

sub _sets_raw() {
    map {
	chomp;
	log::l("got: $_");
	my %l; @l{qw(name size stride level status subsets devs spares)} = split(':');
	if_(defined $l{spares}, \%l);
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
	    $_->{status} = $raid->{status} if $_->{status} eq 'ok' && $::isInstall;
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
	add2hash($vg, { media_type => 'hd', prefix => $dev, bus => "dmraid_$_->{format}", disks => $_->{disks} });

	#- device should exist, created by dmraid(8) using libdevmapper
	#- if it doesn't, we suppose it's not in use
	if_(-e "/dev/$dev", $vg); 

    } grep { 
	if ($_->{status} eq 'ok') {
	    1;
	} else {
	    call_dmraid('-an', $_->{vg}) if $::isInstall; #- for things like bad_sil below, deactivating half activated dmraid
	    0;
	}
    } _sets();
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
    
     bad_sil => {
      '-ccs' => "sil_aeacdidecbcb:234439600:0:mirror:ok:0:1:0\n",
                # ERROR: sil: only 3/4 metadata areas found on /dev/sdb, electing...

      '-ccr' => "/dev/sdb:sil:sil_aeacdidecbcb:mirror:broken:234439600:0\n",
                # ERROR: sil: only 3/4 metadata areas found on /dev/sdb, electing...
     },

     weird_nvidia =>  {
      '-ccs' => <<'EO',
/dev/sda: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sdb: "sil" and "nvidia" formats discovered (using nvidia)!
nvidia_bcjdbjfa:586114702:128:mirror:ok:0:2:0
EO
       '-ccr' => <<'EO',
/dev/sda: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sdb: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sda:nvidia:nvidia_bcjdbjfa:mirror:ok:586114702:0
/dev/sdb:nvidia:nvidia_bcjdbjfa:mirror:ok:586114702:0
EO
	 # ERROR: multiple match for set nvidia_bcjdbjfa:  nvidia_bcjdbjfa
     },


    );
    
    *call_dmraid = sub {
        my ($option, @args) = @_;
        if (my $s = $debug_data{$ENV{DRAKX_DEBUG_DMRAID}}{$option}) {
            split("\n", $s);
	} else {
            warn "dmraid $option @args\n";
        }
    };
EOF
    $@ and die;
}

1;
