package raid; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use run_program;
use devices;
use modules;
use fs;

sub max_nb() { 31 }

sub new {
    my ($raids, %opts) = @_;
    my $md_part = { %opts };
    add2hash_($md_part, { 'chunk-size' => '64', disks => [], 
			  device => 'md' . int(@$raids), 
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
    $md_part->{isMounted} and die N("Can't add a partition to _formatted_ RAID %s", $md_part->{device});
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
}

sub change_device {
    my ($md_part, $prev_device) = @_;
    if ($prev_device ne $md_part->{device}) {
	inactivate_and_dirty({ device => $prev_device });
	$_->{raid} = $md_part->{device} foreach @{$md_part->{disks}};
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
}

sub updateSize {
    my ($part) = @_;
    local $_ = $part->{level};
    my @l = map { $_->{size} } @{$part->{disks}};

    $part->{size} = do {
	if (/0|linear/) { sum @l        }
	elsif (/1/)     { min @l        }
	elsif (/4|5/)   { min(@l) * $#l }
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

    run_program::run_or_die('mdadm', '--create', '--run', devices::make($part->{device}), 
			    '--chunk=' . $part->{'chunk-size'}, 
			    "--level=$part->{level}", 
			    '--raid-devices=' . int(@{$part->{disks}}),
			    map { devices::make($_->{device}) } @{$part->{disks}});
}

sub format_part {
    my ($raids, $part) = @_;
    $part->{isFormatted} and return;

    make($raids, $part);
    fs::format::part_raw($part);
    set_isFormatted($_, 1) foreach @{$part->{disks}};
}

sub verify {
    my ($raids) = @_;
    foreach (@$raids) {
	@{$_->{disks}} >= ($_->{level} =~ /4|5/ ? 3 : 2) or die N("Not enough partitions for RAID level %d\n", $_->{level});
    }
}

sub prepare_prefixed {
    my ($_raids) = @_;
}

sub inactivate_and_dirty {
    my ($part) = @_;
    run_program::run('mdadm', '--stop', devices::make($part->{device}));
    set_isFormatted($part, 0);
}

sub active_mds() {
    map { if_(/^(md\d+) /, $1) } cat_("/proc/mdstat");
}

sub detect_during_install {
    my (@parts) = @_;
    detect_during_install_once(@parts);
    detect_during_install_once(@parts) if active_mds(); #- try again to detect RAID 10
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
	my $conf = parse_mdadm_conf(scalar run_program::get_stdout('mdadm', '--detail', '--brief', devices::make($md)));

	@{$conf->{ARRAY}} == 1 or internal_error("too many answers");
	my $raw_part = $conf->{ARRAY}[0];

	$raw_part->{level} =~ s/raid//; #- { linear | raid0 | raid1 | raid5 } -> { linear | 0 | 1 | 5 }

	my @mdparts = 
	  map { 
	      if (my $part = fs::get::device2part($_, [ @parts, @$raids ])) {
		  $part;
	      } else {
		  log::l("ERROR: unknown raw raid device $_");
		  ();
	      }
	  } split(',', $raw_part->{devices});

	my $md_part = new($raids, device => $md, level => $raw_part->{level}, disks => \@mdparts);

	my $fs_type = fs::type::fs_type_from_magic($md_part);
	fs::type::set_fs_type($md_part, $fs_type || 'ext3');
	fs::type::set_isFormatted($md_part, to_bool($fs_type));

	log::l("RAID: found $md (raid $md_part->{level}) type $fs_type with parts $raw_part->{devices}");
    }
    $raids;
}

sub is_active {
    my ($dev) = @_;
    member($dev, active_mds());
}

sub inactivate_all() { 
    run_program::run('mdadm', '--stop', devices::make($_)) foreach active_mds();
}

sub prepare_prefixed {
    my ($raids) = @_;
    my %raids = map {
	devices::make($_->{device}) =>
	    [ map { devices::make($_->{device}) } @{$_->{disks}} ]
    } @$raids;

    output("$::prefix/etc/mdadm.conf",
	   join(' ', 'DEVICE', uniq(map { @$_ } values %raids)) . "\n",
	   map_each { "ARRAY $::a devices=" . join(',', @$::b) . "\n" } %raids);
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
    \%conf
}

1;
