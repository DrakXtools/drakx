package detect_devices; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use log;
use common qw(:common :file :functional);
use devices;
use c;

#-#####################################################################################
#- Globals
#-#####################################################################################
my @netdevices = map { my $l = $_; map { "$l$_" } (0..3) } qw(eth tr plip fddi);
my %serialprobe = ();
my $usb_interface = undef;

#-######################################################################################
#- Functions
#-######################################################################################
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
sub hds() { grep { $_->{type} eq 'hd' && ($::isStandalone || !isRemovableDrive($_)) } get(); }
sub zips() { grep { $_->{type} =~ /.d/ && isZipDrive($_) } get(); }
sub ide_zips() { grep { $_->{type} =~ /.d/ && isZipDrive($_) } getIDE(); }
#-sub jazzs() { grep { $_->{type} =~ /.d/ && isJazDrive($_) } get(); }
sub ls120s() { grep { $_->{type} =~ /.d/ && isLS120Drive($_) } get(); }
sub usbfdus() { grep { $_->{type} =~ /.d/ && isUSBFDUDrive($_) } get(); }
sub cdroms() { 
    my @l = grep { $_->{type} eq 'cdrom' } get(); 
    if (my @l2 = getIDEBurners()) {
	require modules;
	modules::add_alias('scsi_hostadapter', 'ide-scsi');
	my $nb = 1 + max(-1, map { $_->{device} =~ /scd(\d+)/ } @l);
	foreach my $b (@l2) {
	    log::l("getIDEBurners: $b");
	    my ($e) = grep { $_->{device} eq $b } @l or next;
	    $e->{device} = "scd" . $nb++;
	}
    }
    @l;
}
sub floppies() {
    my @ide = map { $_->{device} } ls120s() and modules::load("ide-floppy");
    my @scsi = map { $_->{device} } usbfdus();
    (@ide, @scsi, grep { tryOpen($_) } qw(fd0 fd1));
}
#- example ls120, model = "LS-120 SLIM 02 UHD Floppy"

sub isZipDrive() { $_[0]->{info} =~ /ZIP\s+\d+/ } #- accept ZIP 100, untested for bigger ZIP drive.
#-sub isJazzDrive() { $_[0]->{info} =~ /JAZZ?\s+/ } #- untested.
sub isLS120Drive() { $_[0]->{info} =~ /LS-?120/ }
sub isUSBFDUDrive() { $_[0]->{info} =~ /USB-?FDU/ }
sub isRemovableDrive() { &isZipDrive || &isLS120Drive || &isUSBFDUDrive } #-or &isJazzDrive }

sub hasSCSI() {
    local *F;
    open F, "/proc/scsi/scsi" or return 0;
    foreach (<F>) {
	/devices: none/ and log::l("no scsi devices are available"), return 0;
    }
#-    log::l("scsi devices are available");
    1;
}
sub hasIDE() { -e "/proc/ide" }
sub hasDAC960() { 1 }
sub hasCompaqSmartArray() { -r "/proc/array/ida0" }

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
	if ($type =~ /Direct-Access/) { #- what about LS-120 floppy drive, assuming there are Direct-Access...
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

    #- what about a system with absolutely no IDE on it, like some sparc machine.
    hasIDE() or return ();

    #- Great. 2.2 kernel, things are much easier and less error prone.
    foreach my $d (sort @{[glob_('/proc/ide/hd*')]}) {
	my ($t) = chop_(cat_("$d/media"));
	my $type = $ {{disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd'}}{$t} or next;
	my ($info) = chop_(cat_("$d/model")); $info ||= "(none)";

	my $num = ord (($d =~ /(.)$/)[0]) - ord 'a';
	push @idi, { type => $type, device => basename($d), info => $info, bus => $num/2, id => $num%2 };
    }
    @idi;
}

#- do not work if ide-scsi is built in the kernel (aka not in module)
sub getIDEBurners() { uniq map { m!ATAPI.* CD(-R|/RW){1,2} ! ? /(\w+)/ : () } syslog() }

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
    my %idi;

    #- We are looking for lines of this format:DAC960#0:
    #- /dev/rd/c0d0: RAID-7, Online, 17928192 blocks, Write Thru0123456790123456789012
    foreach (syslog()) {
	my ($device, $info) = m|/dev/(rd/.*?): (.*?),| or next;
	$idi{$device} = { info => $info, type => 'hd', device => $device };
	log::l("DAC960: $device ($info)");
    }
    values %idi;
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

# pci_probing::main::probe with $probe_type is unsafe for pci! (bug in kernel&hardware)
# get_pcmcia_devices provides field "device", used in network.pm
# => probeall with $probe_type is unsafe
sub probeall {
    my ($probe_type) = @_;
    require pci_probing::main;
    require sbus_probing::main;
    pci_probing::main::probe($probe_type), sbus_probing::main::probe(), modules::get_pcmcia_devices();
}
sub matching_desc {
    my ($regexp) = @_;
    grep { $_->{description} =~ /$regexp/i } probeall();
}
sub stringlist { 
    map { " $_->{description} ($_->{type} $_->{driver})" } probeall(1); 
}
sub check {
    my ($l) = @_;
    my $ok = $l->{driver} !~ /(unknown|ignore)/;
    $ok or log::l("skipping $l->{description}, no module available (if you know one, please mail bugs\@linux-mandrake.com)");
    $ok
}


sub tryOpen($) {
    local *F;
    sysopen F, devices::make($_[0]), c::O_NONBLOCK() and *F;
}

sub tryWrite($) {
    local *F;
    sysopen F, devices::make($_[0]), 1 | c::O_NONBLOCK() and *F;
}

sub syslog {
    -r "/tmp/syslog" and return map { /<\d+>(.*)/ } cat_("/tmp/syslog");
    `dmesg`;
}

sub hasUsb {
    my ($class, $prot) = @_;
    foreach (cat_("/proc/bus/usb/devices")) {
	if (/^P/ .. /^I/) {
	    my ($c, $p) = /Cls=(\d+).*Prot=(\d+)/;
	    $c == $class && ($prot < 0 || $prot == $p) and log::l("found usb $c $p"), return 1;
	}
    }
    0;
}
sub hasUsbKeyboard { hasUsb(3, 1) }
sub hasUsbMouse { hasUsb(3, 2) }
sub hasUsbZip { hasUsb(8, -1) }

sub hasSMP { c::detectSMP() }

sub hasUltra66 {
    cat_("/proc/cmdline") =~ /(ide2=(\S+)(\s+ide3=(\S+))?)/ and return $1;

#    #- disable hasUltra66 (now included in kernel)
#    return;

    my @l = map { $_->{verbatim} } matching_desc('HPT|Ultra66') or return;
    
    my $ide = sprintf "ide2=0x%x,0x%x ide3=0x%x,0x%x",
      @l == 2 ?
	(map_index { hex($_) + (odd($::i) ? 1 : -1) } map { (split ' ')[3..4] } @l) :
	(map_index { hex($_) + (odd($::i) ? 1 : -1) } map { (split ' ')[3..6] } @l);

    log::l("HPT|Ultra66: found $ide");
    $ide;
}

sub whatParport() {
    my @res =();
    foreach (0..3) {
	local *F;
	my $elem = {};
	open F, "/proc/parport/$_/autoprobe" or next;
	foreach (<F>) { $elem->{$1} = $2 if /(.*):(.*);/ }
	push @res, { port => "/dev/lp$_", val => $elem};
    }
    @res;
}

#-CLASS:PRINTER;
#-MODEL:HP LaserJet 1100;
#-MANUFACTURER:Hewlett-Packard;
#-DESCRIPTION:HP LaserJet 1100 Printer;
#-COMMAND SET:MLC,PCL,PJL;
sub whatPrinter() {
    my @res = whatParport();
    grep { $_->{val}{CLASS} eq "PRINTER"} @res;
}

sub whatPrinterPort() {
    grep { tryWrite($_)} qw(/dev/lp0 /dev/lp1 /dev/lp2 /dev/usb/lp0);
}

sub probeSerialDevices {
    #- make sure the device are created before probing.
    foreach (0..3) { devices::make("/dev/ttyS$_") }

    #- for device already probed, we can safely (assuming device are
    #- not moved during install :-)
    #- include /dev/mouse device if using an X server.
    -d "/var/lock" or mkdir "/var/lock", 0755;
    -l "/dev/mouse" and $serialprobe{"/dev/" . readlink "/dev/mouse"} = undef;
    foreach (keys %serialprobe) { m|^/dev/(.*)| and touch "/var/lock/LCK..$1" }

    print STDERR "Please wait while probing serial ports...\n";
    #- start probing all serial ports... really faster than before ...
    #- ... but still take some time :-)
    local *F;
    open F, "serial_probe 2>/dev/null |";
    my %current = (); foreach (<F>) {
	$serialprobe{$current{DEVICE}} = { %current } and %current = () if /^\s*$/ && $current{DEVICE};
	$current{$1} = $2 if /^([^=]+)=(.*?)\s*$/;
    }
    close F;

    foreach (values %serialprobe) {
	$_->{DESCRIPTION} =~ /modem/i and $_->{CLASS} = 'MODEM'; #- hack to make sure a modem is detected.
	$_->{DESCRIPTION} =~ /olitec/i and $_->{CLASS} = 'MODEM'; #- hack to make sure such modem gets detected.
	log::l("probed $_->{DESCRIPTION} of class $_->{CLASS} on device $_->{DEVICE}");
    }
}

sub probeSerial($) { $serialprobe{$_[0]} }

sub hasModem($) {
    $serialprobe{$_[0]} and $serialprobe{$_[0]}{CLASS} eq 'MODEM' and $serialprobe{$_[0]}{DESCRIPTION};
}

sub hasMousePS2 {
    my $t; sysread(tryOpen($_[0]) || return, $t, 256) != 1 || $t ne "\xFE";
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #

