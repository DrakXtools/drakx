use diagnostics;
use strict;

my $scsiDeviceAvailable;
my $CSADeviceAvailable;

1;

sub scsiDeviceAvailable {
    defined $scsiDeviceAvailable and return $scsiDeviceAvailable;
    local *F;
    open F, "/proc/scsi/scsi" or log::l("failed to open /proc/scsi/scsi: $!"), return 0;
    foreach (<F>) {
	/devices: none/ and log::l("no scsi devices are available"), return $scsiDeviceAvailable = 0;
    }
    log::l("scsi devices are available");
    $scsiDeviceAvailable = 1;
}

sub CompaqSmartArrayDeviceAvailable {
    defined $CSADeviceAvailable and return $CSADeviceAvailable;
    -r "/proc/array/ida0" or log::l("failed to open /proc/array/ida0: $!"), return $CSADeviceAvailable = 0;
    log::l("Compaq Smart Array controllers available");
    $CSADeviceAvailable = 1;
}

sub scsiGetDevices {
    my @drives;
    my ($driveNum, $cdromNum, $tapeNum) = qw(0 0 0);
    my $err = sub { chop; log::l("unexpected line in /proc/scsi/scsi: $_"); error() };
    local $_;

    local *F;
    open F, "/proc/scsi/scsi" or return &$err();
    $_ = <F>; /^Attached devices:/ or return &$err();
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
    [ @drives ];
}

sub ideGetDevices {
    my @idi;

    -r "/proc/ide" or die "sorry, /proc/ide not available, seems like you have a pre-2.2 kernel\n => not handled yet :(";

    #- Great. 2.2 kernel, things are much easier and less error prone.
    foreach my $d (glob_('/proc/ide/hd*')) {
	my ($t) = chomp_(cat_("$d/media"));
	my $type = ${{ disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd' }}{$t} or next;
	my ($info) = chomp_(cat_("$d/model")); $info ||= "(none)";

	my $num = ord (($d =~ /(.)$/)[0]) - ord 'a';
	push @idi, { type => $type, device => basename($d), info => $info, bus => $num/2, id => $num%2 };
    }
    [ @idi ];
}


sub CompaqSmartArrayGetDevices {
    my @idi;
    my $f;

    for (my $i = 0; -r ($f = "/proc/array/ida$i"); $i++) {
	local *F;
	open F, $f or die;
	local $_ = <F>;
	my ($name) = m|ida/(.*?):| or next;
	push @idi, { device => $name, info => "Compaq RAID logical disk", type => 'hd' };
    }
    [ @idi ];
}

sub dac960GetDevices {
    my @idi;
    my $file = "/var/log/dmesg";
    -r $file or $file = "/tmp/syslog";

    local *F;
    open F, $file or die "Failed to open $file: $!";

    #- We are looking for lines of this format:DAC960#0:
    #- /dev/rd/c0d0: RAID-7, Online, 17928192 blocks, Write Thru0123456790123456789012
    foreach (<F>) {
	my ($devicename, $info) = m|/dev/rd/(.*?): (.*?),| or next;
	push @idi, { info => $info, type => 'hd', devicename => $devicename };
	log::l("DAC960: $devicename: $info");
    }
    [ @idi ];
}
