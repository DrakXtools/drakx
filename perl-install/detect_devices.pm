package detect_devices;

use diagnostics;
use strict;

use log;
use common qw(:common :file);
use c;


my $scsiDeviceAvailable;
my $CSADeviceAvailable;

1;

sub get {
    # Detect the default BIOS boot harddrive is kind of tricky. We may have IDE,
    # SCSI and RAID devices on the same machine. From what I see so far, the default
    # BIOS boot harddrive will be
    # 1. The first IDE device if IDE exists. Or 
    # 2. The first SCSI device if SCSI exists. Or
    # 3. The first RAID device if RAID exists.

    map { &{$_->[0]}() ? &{$_->[1]}() : () }
    [ \&hasIDE, \&getIDE ],
    [ \&hasSCSI, \&getSCSI ],
    [ \&hasDAC960, \&getDAC960 ],
    [ \&hasCompaqSmartArray, \&getCompaqSmartArray ];
}
sub hds() { grep { $_->{type} eq 'hd' } get(); }
sub cdroms() { grep { $_->{type} eq 'cdrom' } get(); }

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

    # Great. 2.2 kernel, things are much easier and less error prone. 
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
	local *F;
	open F, $f or die;
	local $_ = <F>;
	my ($name) = m|ida/(.*?):| or next;
	push @idi, { device => $name, info => "Compaq RAID logical disk", type => 'hd' };
    }
    @idi;
}

sub getDAC960() {
    my @idi;
    my $file = "/var/log/dmesg";
    -r $file or $file = "/tmp/syslog";

    local *F;
    open F, $file or die "Failed to open $file: $!";

    # We are looking for lines of this format:DAC960#0:
    # /dev/rd/c0d0: RAID-7, Online, 17928192 blocks, Write Thru0123456790123456789012    
    foreach (<F>) {
	my ($devicename, $info) = m|/dev/rd/(.*?): (.*?),| or next;
	push @idi, { info => $info, type => 'hd', devicename => $devicename }; 
	log::l("DAC960: $devicename: $info");
    }
    @idi;
}


sub getNet() {
    # I should probably ask which device to use if multiple ones are available -- oh well :-( 
    foreach (qw(eth0 tr0 plip0 plip1 plip2 fddi0)) {
	hasNetDevice($_) and log::l("$_ is available -- using it for networking"), return $_;
    }
    undef;
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
