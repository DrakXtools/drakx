package detect_devices;

use diagnostics;
use strict;

use log;
use common qw(:common :file);
use devices;
use c;

my @netdevices = map { my $l = $_; map { "$l$_" } (0..3) } qw(eth tr plip fddi);
my $scsiDeviceAvailable;
my $CSADeviceAvailable;

1;

sub get {
    #- Detect the default BIOS boot harddrive is kind of tricky. We may have IDE,
    #- SCSI and RAID devices on the same machine. From what I see so far, the default
    #- BIOS boot harddrive will be
    #- 1. The first IDE device if IDE exists. Or 
    #- 2. The first SCSI device if SCSI exists. Or
    #- 3. The first RAID device if RAID exists.

    map { &{$_->[0]}() ? &{$_->[1]}() : () }
    [ \&hasIDE, \&getIDE ],
    [ \&hasSCSI, \&getSCSI ],
    [ \&hasDAC960, \&getDAC960 ],
    [ \&hasCompaqSmartArray, \&getCompaqSmartArray ];
}
sub hds() { grep { $_->{type} eq 'hd' } get(); }
sub cdroms() { grep { $_->{type} eq 'cdrom' } get(); }
sub floppies() {
    (grep { tryOpen($_) } qw(fd0 fd1)),
    (grep { $_->{type} eq 'fd' } get());
}

sub hasSCSI() {
    defined $scsiDeviceAvailable and return $scsiDeviceAvailable;
    local *F;
    open F, "/proc/scsi/scsi" or log::l("failed to open /proc/scsi/scsi: $!"), return 0;
    foreach (<F>) {
	/devices: none/ and log::l("no scsi devices are available"), return $scsiDeviceAvailable = 0;
    }
    log::l("scsi devices are available");
    $scsiDeviceAvailable = 1;
}
sub hasIDE() { -e "/proc/ide" }
sub hasDAC960() { 1 }

sub hasCompaqSmartArray() {
    defined $CSADeviceAvailable and return $CSADeviceAvailable;
    -r "/proc/array/ida0" or log::l("failed to open /proc/array/ida0: $!"), return $CSADeviceAvailable = 0;
    log::l("Compaq Smart Array controllers available");
    $CSADeviceAvailable = 1;
}

sub getSCSI() {
    my @drives;
    my ($driveNum, $cdromNum, $tapeNum) = qw(0 0 0);
    my $err = sub { chop; die "unexpected line in /proc/scsi/scsi: $_"; };
    local $_;

    local *F;
    open F, "/proc/scsi/scsi" or die "failed to open /proc/scsi/scsi";
    local $_ = <F>; /^Attached devices:/ or return &$err();
    while ($_ = <F>) {
	my ($id) = /^Host:.*?Id: (\d+)/ or return &$err();
	$_ = <F>; my ($vendor, $model) = /^\s*Vendor:\s*(.*?)\s+Model:\s*(.*?)\s+Rev:/ or return &$err();
	$_ = <F>; my ($type) = /^\s*Type:\s*(.*)/ or &$err();
	my $device;
	if ($type =~ /Direct-Access/) {
	    $type = 'hd';
	    $device = "sd" . chr($driveNum++ + ord('a'));
	} elsif ($type =~ /Sequential-Access/) {
	    $type = 'tape';
	    $device = "st" . $tapeNum++;
	} elsif ($type =~ /CD-ROM/) {
	    $type = 'cdrom';
	    $device = "scd" . $cdromNum++;
	}
	$device and push @drives, { device => $device, type => $type, info => "$vendor $model", id => $id, bus => 0 };
    }
    @drives;
}

sub getIDE() {
    my @idi;

    #- Great. 2.2 kernel, things are much easier and less error prone. 
    foreach my $d (glob_('/proc/ide/hd*')) {
	my ($t) = chop_(cat_("$d/media"));
	my $type = $ {{disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd'}}{$t} or next;
	my ($info) = chop_(cat_("$d/model")); $info ||= "(none)";

	my $num = ord (($d =~ /(.)$/)[0]) - ord 'a';
	push @idi, { type => $type, device => basename($d), info => $info, bus => $num/2, id => $num%2 };
    }
    @idi;
}

sub getCompaqSmartArray() {
    my @idi;
    my $f;

    for (my $i = 0; -r ($f = "/proc/array/ida$i"); $i++) {
	foreach (cat_($f)) {
	    if (m|^(ida/.*?):|) {
		push @idi, { device => $1, info => "Compaq RAID logical disk", type => 'hd' };
		last;
	    }	      
	}
    }
    @idi;
}

sub getDAC960() {
    my @idi;

    #- We are looking for lines of this format:DAC960#0:
    #- /dev/rd/c0d0: RAID-7, Online, 17928192 blocks, Write Thru0123456790123456789012    
    foreach (syslog()) {
	my ($devicename, $info) = m|/dev/rd/(.*?): (.*?),| or next;
	push @idi, { info => $info, type => 'hd', devicename => $devicename }; 
	log::l("DAC960: $devicename: $info");
    }
    @idi;
}

sub net2module() {
    my @modules = map { quotemeta first(split) } cat_("/proc/modules");
    my $modules = join '|', @modules;
    my $net     = join '|', @netdevices;
    my ($module, %l);
    foreach (syslog()) {
	if (/^($modules)\.c:/) {
	    $module = $1;
	} elsif (/^($net):/) {
	    $l{$1} = $module if $module;
	}
    }
    %l;
}

sub getNet() { 
    grep { hasNetDevice($_) } @netdevices;
}
sub getPlip() {
    foreach (0..2) {
	hasNetDevice("plip$_") and log::l("plip$_ will be used for PLIP"), return "plip$_";
    }
    undef;
}

sub hasNet() { goto &getNet }
sub hasPlip() { goto &getPlip }
sub hasEthernet() { hasNetDevice("eth0"); }
sub hasTokenRing() { hasNetDevice("tr0"); }
sub hasNetDevice($) { c::hasNetDevice($_[0]) }

sub tryOpen($) {
    local *F;
    sysopen F, devices::make($_[0]), c::O_NONBLOCK() and \*F;
}
sub syslog {
    -r "/tmp/syslog" and return map { /<\d+>(.*)/ } cat_("/tmp/syslog");
    `dmesg`
}

sub hasSMP {
    my $nb = grep { /^processor/ } cat_("/proc/cpuinfo");
    $nb > 1;
}
