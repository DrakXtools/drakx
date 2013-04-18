package fs::wild_device; # $Id$

use diagnostics;
use strict;
use devices;
use common;


sub analyze {
    my ($dev) = @_;

    if ($dev =~ m!^/u?dev/(.*)!) {
	'dev', $dev;
    } elsif ($dev !~ m!^/! && (-e "/dev/$dev" || -e "/dev/$dev")) {
	'dev', "/dev/$dev";
    } elsif ($dev =~ /^LABEL=(.*)/) {
	'label', $1;
    } elsif ($dev =~ /^UUID=(.*)/) {
	'uuid', $1;
    } elsif ($dev eq 'none' || $dev eq 'rootfs') {
	'virtual';
    } elsif ($dev =~ m!^(\S+):/(\w|$)!) {
	'nfs';
    } elsif ($dev =~ m!^//\w!) {
	'smb';
    } elsif ($dev =~ m!^https?://!) {
	'dav';
    }
}

sub to_subpart {
    my ($dev) = @_;

    my $part = { device => $dev, faked_device => 1 }; #- default

    if (my ($kind, $val) = analyze($dev)) {
	if ($kind eq 'label') {	    
	    $part->{device_LABEL} = $val;
	} elsif ($kind eq 'uuid') {	    
	    $part->{device_UUID} = $val;
	} elsif ($kind eq 'dev') {
	    my %part = (faked_device => 0);
	    if (my $rdev = (stat "$dev")[6]) {
		($part{major}, $part{minor}) = unmakedev($rdev);
	    }

	    my $symlink = $dev !~ m!mapper/! ? readlink("$dev") : undef;
	    $dev =~ s!/u?dev/!!;

	    if ($symlink && $symlink !~ m!^/!) {
		my $keep = 1;
		if ($symlink =~ m!/! || $dev =~ m!/!) {
		    $symlink = MDK::Common::File::concat_symlink("/dev/" . dirname($dev), $symlink);
		    $symlink =~ s!^/dev/!! or $keep = 0;
		}
		if ($keep) {
		    $part{device_LABEL} = $1 if $dev =~  m!^disk/by-label/(.*)!;
		    $part{device_UUID} = $1 if $dev =~  m!^disk/by-uuid/(.*)!;
		    $part{device_alias} = $dev;
		    $dev = $symlink;
		}
	    }
	    if (my $part_number = devices::part_number(\%part)) {
		$part{part_number} = $part_number;
	    }
	    $part{device} = $dev;
	    return \%part;
	}
    } else {
	if ($dev =~ m!^/! && -f "$dev") {
	    #- it must be a loopback file or directory to bind
	} else {
	    log::l("part_from_wild_device_name: unknown device $dev");
	}
    }
    $part;
}

sub _prefer_device_UUID {
    my ($part) = @_;
    $part->{prefer_device_UUID} || 
      !$::no_uuid_by_default && devices::should_prefer_UUID($part->{device});
}

sub from_part {
    my ($prefix, $part) = @_;

    if ($part->{prefer_device_LABEL}) {
	'LABEL=' . $part->{device_LABEL};
    } elsif ($part->{device_alias}) {
	"/dev/$part->{device_alias}";
    } elsif (!$part->{prefer_device} && $part->{device_UUID} && _prefer_device_UUID($part)) {
	'UUID=' . $part->{device_UUID};
    } else {
	my $faked_device = exists $part->{faked_device} ? 
	    $part->{faked_device} : 
	    do {
		#- in case $part has been created without using fs::wild_device::to_subpart()
		my ($kind) = analyze($part->{device});
		$kind ? $kind ne 'dev' : $part->{device} =~ m!^/!;
	    };
	if ($faked_device) {
	    $part->{device};
	} elsif ($part->{device} =~ m!^/dev/!) {
	    log::l("ERROR: i have a full device $part->{device}, this should not happen. use fs::wild_device::to_subpart() instead of creating bad part data-structures!");
	    $part->{device};
	} else {
	    my $dev = "/dev/$part->{device}";
	    eval { devices::make("$prefix$dev") };
	    $dev;
	}
    }
}

1;
