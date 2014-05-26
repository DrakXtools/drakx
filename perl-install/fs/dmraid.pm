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


=head1 SYNOPSYS

Manage fake RAIDs using dmraid

=head1 Functions

=over

=item init()

Load kernel modules, init device mapper then scan for fake RAIDs.

=cut

sub init() {
    whereis_binary('dmraid') or die "dmraid not installed";

    eval { modules::load('dm-mirror', 'dm-zero') };
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
    # get the real vg names, needed for ddf1, and safer than begins_with for raid10
    log::l("_raid_devices_raw");
    my %vgs;
    my %pv2vg = map {
	chomp();
	log::l("got: $_");
	my %l; @l{qw(name size stride level status subsets devs spares)} = split(':');
	$vgs{$l{name}} = 1 if defined $l{spares};
	if (/freeing device "(.*)", path "(.*)"/ && defined $vgs{$1}) {
	    log::l("$2 => $1");
	    { $2 => $1 }
        }
    } call_dmraid(qw(-d -s -c -c));
    map {
	chomp;
	log::l("got: $_");
	my %l; @l{qw(pv format vg level status size)} = split(':');
	if (defined $l{size} && defined $l{vg} && defined $pv2vg{$l{pv}} && !defined $vgs{$l{vg}}) {
	    log::l("using $pv2vg{$l{pv}} instead of $l{vg}");
	    $l{vg} = $pv2vg{$l{pv}};
	}
	if_(defined $l{size}, \%l);
    } call_dmraid(qw(-r -c -c));
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
    } call_dmraid('-s', '-c', '-c');
}

sub _sets() {
    my @sets = _sets_raw();
    my @raid_devices = _raid_devices();
    foreach (@sets) {
	my $name = $_->{name};
	my @l = grep { begins_with($name, $_->{vg}) } @raid_devices;
	log::l("ERROR: multiple match for set $name: " . join(' ', map { $_->{vg} } @l)) if @l > 1;

	@l = grep { begins_with($_->{vg}, $name) } @raid_devices if !@l;
	
	if (@l) {
	    foreach my $raid (@l) {
		push @{$_->{disks}}, @{$raid->{disks}};
		add2hash($_, $raid);
		$_->{status} = $raid->{status} if $_->{status} eq 'ok' && $::isInstall;
	    }
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
	add2hash($vg, { media_type => 'hd', bus => "dmraid_$_->{format}", disks => $_->{disks} });

	#- device should exist, created by dmraid(8) using libdevmapper
	#- if it doesn't, we suppose it's not in use
	if (-e "/dev/$dev") {
	    $vg; 
	} else {
	    log::l("ignoring $dev as /dev/$dev doesn't exist");
	    ();
	}

    } grep { 
	if ($_->{status} eq 'ok') {
	    1;
	} else {
	    call_dmraid('-an', $_->{vg}) if $::isInstall; #- for things like bad_sil below, deactivating half activated dmraid
	    0;
	}
    } _sets();
}

# the goal is to handle migration from /dev/mapper/xxx1 to /dev/mapper/xxxp1,
# as used by initrd/nash.
# dmraid has been patched to follow xxxp1 device names.
# so until the box has rebooted on new initrd/dmraid, we must cope with /dev/mapper/xxx1 device names
# (cf #44182)
sub migrate_device_names {
    my ($vg) = @_;

    my $dev_name = basename($vg->{device});
    foreach (all('/dev/mapper')) {
	my ($nb) = /^\Q$dev_name\E(\d+)$/ or next;
	my $new = $dev_name . 'p' . $nb;
	if (! -e "/dev/mapper/$new") {
	    log::l("migrating to $new, creating a compat symlink $_");
	    rename "/dev/mapper/$_", "/dev/mapper/$new";
	    symlink $new, "/dev/mapper/$_";
	}
    }
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
    
      '-s' => "isw_ffafgbdhi_toto:234441216:256:mirror:ok:0:2:0\n",
    
      # dmraid -r ####################
      #/dev/sda: isw, "isw_ffafgbdhi", GROUP, ok, 488397166 sectors, data@ 0
      #/dev/sdb: isw, "isw_ffafgbdhi", GROUP, ok, 234441646 sectors, data@ 0
    
      '-r' => "/dev/sda:isw:isw_ffafgbdhi:GROUP:ok:488397166:0\n" .
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
    
      '-s' => "pdc_bcefbiigfg:80043200:128:mirror:ok:0:2:0\n",
    
      # dmraid -r ####################
      # /dev/sda: pdc, "pdc_bcefbiigfg", mirror, ok, 80043200 sectors, data@ 0
      # /dev/sdb: pdc, "pdc_bcefbiigfg", mirror, ok, 80043200 sectors, data@ 0
    
      '-r' => "/dev/sda:pdc:pdc_bcefbiigfg:mirror:ok:80043200:0\n" .
                "/dev/sdb:pdc:pdc_bcefbiigfg:mirror:ok:80043200:0\n",
     },
    
     bad_sil => {
      '-s' => "sil_aeacdidecbcb:234439600:0:mirror:ok:0:1:0\n",
                # ERROR: sil: only 3/4 metadata areas found on /dev/sdb, electing...

      '-r' => "/dev/sdb:sil:sil_aeacdidecbcb:mirror:broken:234439600:0\n",
                # ERROR: sil: only 3/4 metadata areas found on /dev/sdb, electing...
     },

     weird_nvidia =>  {
      '-s' => <<'EO',
/dev/sda: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sdb: "sil" and "nvidia" formats discovered (using nvidia)!
nvidia_bcjdbjfa:586114702:128:mirror:ok:0:2:0
EO
       '-r' => <<'EO',
/dev/sda: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sdb: "sil" and "nvidia" formats discovered (using nvidia)!
/dev/sda:nvidia:nvidia_bcjdbjfa:mirror:ok:586114702:0
/dev/sdb:nvidia:nvidia_bcjdbjfa:mirror:ok:586114702:0
EO
	 # ERROR: multiple match for set nvidia_bcjdbjfa:  nvidia_bcjdbjfa
     },

     nvidia_with_subsets => {
      '-s' => <<'EO',
nvidia_bfcciffh:625163520:128:raid10:ok:2:4:0
EO
       '-r' => <<'EO',
/dev/sda:nvidia:nvidia_bfcciffh-0:stripe:ok:312581806:0
/dev/sdb:nvidia:nvidia_bfcciffh-0:stripe:ok:312581806:0
/dev/sdc:nvidia:nvidia_bfcciffh-1:stripe:ok:312581806:0
/dev/sdd:nvidia:nvidia_bfcciffh-1:stripe:ok:312581806:0
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
