package raid; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use fs::get;
use run_program;
use devices;
use modules;

sub max_nb() { 31 }

sub check_prog {
    my ($in) = @_;
    $::isInstall || $in->do_pkgs->ensure_binary_is_installed('mdadm', 'mdadm');
}

sub new {
    my ($raids, %opts) = @_;
    my $md_part = { %opts };
    add2hash_($md_part, { 'chunk-size' => '64', disks => [], 
			  fs_type => 'ext3',
			  device => first(free_mds($raids)), 
			  notFormatted => 1, level => 1 });
    push @$raids, $md_part;
    foreach (@{$md_part->{disks}}) {
	$_->{raid} = $md_part->{device};
	fs::type::set_pt_type($_, 0xfd);
	delete $_->{mntpoint};
    }
    update($md_part);
    $md_part;
}

sub add {
    my ($md_part, $part) = @_;
    $md_part->{isMounted} and die N("Can not add a partition to _formatted_ RAID %s", $md_part->{device});
    inactivate_and_dirty($md_part);
    set_isFormatted($part, 0);
    $part->{raid} = $md_part->{device};
    delete $part->{mntpoint};
    push @{$md_part->{disks}}, $part;
    update($md_part);
}

sub delete {
    my ($raids, $md_part) = @_;
    inactivate_and_dirty($md_part);
    delete $_->{raid} foreach @{$md_part->{disks}};
    @$raids = grep { $_ != $md_part } @$raids;
    write_conf($raids) if $::isStandalone;
}

sub change_device {
    my ($md_part, $new_device) = @_;
    if ($new_device ne $md_part->{device}) {
	inactivate_and_dirty($md_part);
	$md_part->{device} = $new_device;
	$_->{raid} = $new_device foreach @{$md_part->{disks}};
    }
}

sub removeDisk {
    my ($raids, $part) = @_;
    my $md_part = fs::get::device2part($part->{raid}, $raids);
    inactivate_and_dirty($md_part);
    fs::type::set_isFormatted($part, 0);
    delete $part->{raid};
    my $disks = $md_part->{disks};
    @$disks = grep { $_ != $part } @$disks;
    if (@$disks) {
	update($md_part);
    } else {
	@$raids = grep { $_ != $md_part } @$raids;
    }
    write_conf($raids) if $::isStandalone;
}

sub updateSize {
    my ($part) = @_;
    local $_ = $part->{level};
    my @l = map { $_->{size} } @{$part->{disks}};

    $part->{size} = do {
	if (/0|linear/) { sum @l }
	elsif (/1/)     { min @l }
	elsif (/4|5/)   { min(@l) * (@l - 1) }
	elsif (/6/)     { min(@l) * (@l - 2) }
    };
}

sub module {
    my ($part) = @_;
    my $mod = $part->{level};

    $mod = 5 if $mod eq "4";
    $mod = "raid$mod" if $mod =~ /^\d+$/;
    $mod;
}


sub update {
    updateSize($_) foreach @_;
}

sub make {
    my ($raids, $part) = @_;    

    return if is_active($part->{device});

    inactivate_and_dirty($part);

    isRAID($_) and make($raids, $_) foreach @{$part->{disks}};
    eval { modules::load(module($part)) };

    whereis_binary('mdadm') or die 'mdadm not installed';

    my $dev = devices::make($part->{device});
    my $nb = @{$part->{disks}};

    run_program::run_or_die('mdadm', '--create', '--run', $dev, 
			    if_($nb == 1, '--force'),
			    '--chunk=' . $part->{'chunk-size'}, 
			    "--level=$part->{level}", 
			    "--raid-devices=$nb",
			    map { devices::make($_->{device}) } @{$part->{disks}});

    if (my $raw_part = get_md_info($dev)) {
	$part->{UUID} = $raw_part->{UUID};
    }
    write_conf($raids) if $::isStandalone;
}

sub format_part {
    my ($raids, $part) = @_;
    $part->{isFormatted} and return;

    make($raids, $part);
    fs::format::part_raw($part, undef);
    set_isFormatted($_, 1) foreach @{$part->{disks}};
}

sub verify {
    my ($raids) = @_;
    foreach (@$raids) {
	my $nb = $_->{level} =~ /6/ ? 4 : $_->{level} =~ /4|5/ ? 3 : 2;
	@{$_->{disks}} >= $nb or die N("Not enough partitions for RAID level %d\n", $_->{level});
    }
}

sub inactivate_and_dirty {
    my ($part) = @_;
    run_program::run('mdadm', '--stop', devices::make($part->{device}));
    set_isFormatted($part, 0);
}

sub active_mds() {
    map { if_(/^(md\d+)\s*:\s*active/, $1) } cat_("/proc/mdstat");
}
sub inactive_mds() {
    map { if_(/^(md\d+)\s*:\s*inactive/, $1) } cat_("/proc/mdstat");
}

sub free_mds {
    my ($raids) = @_;
    difference2([ map { "md$_" } 0 .. max_nb() ], [ map { $_->{device} } @$raids ]);
}

sub detect_during_install {
    my (@parts) = @_;
    detect_during_install_once(@parts);
    detect_during_install_once(@parts) if active_mds(); #- try again to detect RAID 10

    foreach (inactive_mds()) {
	log::l("$_ is an inactive md, we stop it to ensure it doesn't busy devices");
	run_program::run('mdadm', '--stop', devices::make($_));
    }
}

sub detect_during_install_once {
    my (@parts) = @_;
    devices::make("md$_") foreach 0 .. max_nb();
    output('/etc/mdadm.conf', join(' ', 'DEVICE', 
				   (map { "/dev/$_" } active_mds()), 
				   map { devices::make($_->{device}) } @parts), "\n");
    run_program::run('mdadm', '>>', '/etc/mdadm.conf', '--examine', '--scan');

    foreach (@{parse_mdadm_conf(scalar cat_('/etc/mdadm.conf'))->{ARRAY}}) {
	eval { modules::load($_->{level}) };
    }
    run_program::run('mdadm', '--assemble', '--scan');    
}

sub get_existing {
    my @parts = @_;
    my $raids = [];
    foreach my $md (active_mds()) {
	my $raw_part = get_md_info(devices::make($md)) or next;

	$raw_part->{level} =~ s/raid//; #- { linear | raid0 | raid1 | raid5 | raid6 } -> { linear | 0 | 1 | 5 | 6 }

	my @mdparts = 
	  map { 
	      if (my $part = fs::get::device2part($_, [ @parts, @$raids ])) {
		  $part;
	      } else {
		  log::l("ERROR: unknown raw raid device $_");
		  ();
	      }
	  } split(',', $raw_part->{devices});

	my $md_part = new($raids, device => $md, UUID => $raw_part->{UUID}, level => $raw_part->{level}, disks => \@mdparts);

	my $type = fs::type::type_subpart_from_magic($md_part);
	if ($type) {
	    put_in_hash($md_part, $type);
	} else {
	    fs::type::set_fs_type($md_part, 'ext3');
	}
	my $fs_type = $type && $type->{fs_type};
	fs::type::set_isFormatted($md_part, to_bool($fs_type));

	log::l("RAID: found $md (raid $md_part->{level}) type $fs_type with parts $raw_part->{devices}");
    }
    $raids;
}

sub is_active {
    my ($dev) = @_;
    member($dev, active_mds());
}

sub write_conf {
    my ($raids) = @_;

    @$raids or return;

    my @devices = uniq(map { devices::make($_->{device}) } map { @{$_->{disks}} } @$raids);

    output("$::prefix/etc/mdadm.conf",
	   join(' ', 'DEVICE', @devices) . "\n",
	   map { "ARRAY " . devices::make($_->{device}) . " UUID=$_->{UUID} auto=yes\n" } @$raids);
}

sub get_md_info {
    my ($dev) = @_;
    my $conf = parse_mdadm_conf(scalar run_program::get_stdout('mdadm', '--detail', '--brief', '-v', $dev));

    @{$conf->{ARRAY}} or return;
    @{$conf->{ARRAY}} == 1 or internal_error("too many answers");
    $conf->{ARRAY}[0];
}

sub parse_mdadm_conf {
    my ($s) = @_;
    my %conf = (DEVICE => [], ARRAY => []);
    $s =~ s!^\s*#.*!!gm; #- remove comments
    $s =~ s!\n(\s)!$1!g; #- join lines starting with a space
    foreach (split("\n", $s)) {
	if (/^DEVICE\s+(.*)/) {
	    push @{$conf{DEVICE}}, split(' ', $1);
	} elsif (my ($md, $md_conf) = /^ARRAY\s+(\S+)\s*(.*)/) {
	    my %md_conf = map { if_(/(.*)=(.*)/, $1 => $2) } split(' ', $md_conf);
	    $md_conf{device} = $md;
	    push @{$conf{ARRAY}}, \%md_conf;
	}
    }
    \%conf;
}

1;
