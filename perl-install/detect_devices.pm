package detect_devices; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use log;
use common;
use devices;
use c;

#-#####################################################################################
#- Globals
#-#####################################################################################
my @netdevices = map { my $l = $_; map { "$l$_" } (0..3) } qw(eth tr fddi plip);
my %serialprobe = ();

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

    getIDE(), getSCSI(), getDAC960(), getCompaqSmartArray(), getATARAID();
}
sub hds() { grep { $_->{media_type} eq 'hd' && ($::isStandalone || !isRemovableDrive($_)) } get(); }
sub zips() { grep { $_->{media_type} =~ /.d/ && isZipDrive($_) } get(); }
sub ide_zips() { grep { $_->{media_type} =~ /.d/ && isZipDrive($_) } getIDE(); }
#-sub jazzs() { grep { $_->{media_type} =~ /.d/ && isJazDrive($_) } get(); }
sub ls120s() { grep { $_->{media_type} =~ /.d/ && isLS120Drive($_) } get(); }
sub cdroms() { 
    my @l = grep { $_->{media_type} eq 'cdrom' } get(); 
    if (my @l2 = IDEburners()) {
	require modules;
	modules::add_alias('scsi_hostadapter', 'ide-scsi');
	my $nb = 1 + max(-1, map { $_->{device} =~ /scd(\d+)/ } @l);
	foreach my $i (@l2) {	    
	    log::l("IDEBurner: $i->{device}");
	    my ($e) = grep { $_->{device} eq $i->{device} } @l;
	    $e->{device} = "scd" . $nb++;
	}
    }
    @l;
}
sub burners    { grep { $_->{media_type} eq 'cdrom' && isBurner($_) } get() }
sub IDEburners { grep { $_->{media_type} eq 'cdrom' && isBurner($_) } getIDE() }
sub dvdroms    { grep { $_->{media_type} eq 'cdrom' && isDvdDrive($_) } get() }

sub get_mac_model() {
    my $mac_model = cat_("/proc/device-tree/model") || die "Can't open /proc/device-tree/model";
    log::l("Mac model: $mac_model");
    $mac_model;	
}

sub get_mac_generation() {
    my $generation = cat_("/proc/cpuinfo") || die "Can't open /proc/cpuinfo";
    my @genarray = split(/\n/, $generation);
    my $count = 0;
    while ($count <= @genarray) {
	if ($genarray[$count] =~ /pmac-generation/) {
	    @genarray = split(/:/, $genarray[$count]);
	    return $genarray[1];
	}
	$count++;
    }
    return "Unknown Generation";	
}

sub dev_is_devfs { -e "/dev/.devfsd" }

sub floppies() {
    require modules;
    eval { modules::load("floppy") };
    my @fds = map {
	my $info = (!dev_is_devfs() || -e "/dev/$_") && c::floppy_info(devices::make($_));
	if_($info && $info ne '(null)', { device => $_, media_type => 'fd', info => $info })
    } qw(fd0 fd1);
    my @ide = ls120s() and eval { modules::load("ide-floppy") };

    eval { modules::load("usb-storage") } if usbStorage();
    my @scsi = grep { $_->{media_type} eq 'fd' } getSCSI();
    @ide, @scsi, @fds;
}
sub floppies_dev() { map { $_->{device} } floppies() }
sub floppy { first(floppies_dev()) }
#- example ls120, model = "LS-120 SLIM 02 UHD Floppy"

sub isBurner { 
    my $dev = $_[0]{device};
    if (my($nb) = $dev =~ /scd(.*)/) {
	grep { /^(scd|sr)$nb:.*writer/ } syslog();
    } else {
	my $f = tryOpen($dev); #- SCSI burner are not detected this way.
	$f && c::isBurner(fileno($f));
    }
}
sub isDvdDrive {
    $_[0]{info} =~ /DVD/; #- SCSI DVD seems not to be detected correctly, so use another probe after.
    my $f = tryOpen($_[0]{device});
    $f && c::isDvdDrive(fileno($f));
}
sub isZipDrive { $_[0]->{info} =~ /ZIP\s+\d+/ } #- accept ZIP 100, untested for bigger ZIP drive.
#-sub isJazzDrive { $_[0]->{info} =~ /JAZZ?\s+/ } #- untested.
sub isLS120Drive { $_[0]->{info} =~ /LS-?120|144MB/ }
sub isRemovableDrive { &isZipDrive || &isLS120Drive || $_[0]->{media_type} eq 'fd' } #-or &isJazzDrive }

sub isFloppyOrHD {
    my ($dev) = @_;
    require partition_table_raw;
    my $geom = partition_table_raw::get_geometry(devices::make($dev));
    $geom->{totalsectors} < 10 << 11 ? 'fd' : 'hd';
}

sub getSCSI() {
    my @drives;
    my ($driveNum, $cdromNum, $tapeNum) = qw(0 0 0);
    my $err = sub { chop; die "unexpected line in /proc/scsi/scsi: $_"; };
    local $_;

    local *F;
    open F, "/proc/scsi/scsi" or return;
    local $_ = <F>; /^Attached devices:/ or return &$err();
    while ($_ = <F>) {
	my ($id) = /^Host:.*?Id: (\d+)/ or return &$err();
	$_ = <F>; my ($vendor, $model) = /^\s*Vendor:\s*(.*?)\s+Model:\s*(.*?)\s+Rev:/ or return &$err();
	$_ = <F>; my ($type) = /^\s*Type:\s*(.*)/ or &$err();
	my $device;
	if ($type =~ /Direct-Access/) { #- what about LS-120 floppy drive, assuming there are Direct-Access...
	    $device = "sd" . chr($driveNum++ + ord('a'));
	    $type = isFloppyOrHD($device);
	} elsif ($type =~ /Sequential-Access/) {
	    $device = "st" . $tapeNum++;
	    $type = 'tape';
	} elsif ($type =~ /CD-ROM/) {
	    $device = "scd" . $cdromNum++;
	    $type = 'cdrom';
	}
	$device and push @drives, { device => $device, media_type => $type, info => "$vendor $model", id => $id, bus => 0 };
    }
    @drives;
}

sub getIDE() {
    my @idi;

    #- what about a system with absolutely no IDE on it, like some sparc machine.
    -e "/proc/ide" or return ();

    #- Great. 2.2 kernel, things are much easier and less error prone.
    foreach my $d (sort @{[glob_('/proc/ide/hd*')]}) {
	cat_("$d/driver") =~ /ide-scsi/ and next; #- already appears in /proc/scsi/scsi
	my $t = chomp_(cat_("$d/media"));
	my $type = $ {{disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd'}}{$t} or next;
	my $info = chomp_(cat_("$d/model")) || "(none)";

	my $num = ord (($d =~ /(.)$/)[0]) - ord 'a';
	push @idi, { media_type => $type, device => basename($d), info => $info, bus => $num/2, id => $num%2 };
    }
    @idi;
}

sub getCompaqSmartArray() {
    my (@idi, $f);

    foreach ('array/ida', 'cpqarray/ida', 'cciss/cciss') {
	my $prefix = "/proc/driver/$_"; #- kernel 2.4 places it here
	$prefix = "/proc/$_" if !-e "${prefix}0"; #- kernel 2.2

	my ($name) = m|/(.*)|;
	for (my $i = 0; -r ($f = "${prefix}$i"); $i++) {
	    foreach (cat_($f)) {
		if (m|^\s*($name/.*?):|) {
		    push @idi, { device => $1, info => "Compaq RAID logical disk", media_type => 'hd' };
		}
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
	$idi{$device} = { info => $info, media_type => 'hd', device => $device };
    }
    values %idi;
}

sub getATARAID {
    my %l;
    foreach (syslog()) {
	my ($device) = m|^\s*(ataraid/d\d+):| or next;
	$l{$device} = { info => 'ATARAID block device', media_type => 'hd', device => $device };
	log::l("ATARAID: $device");
    }
    values %l;
}

sub getNet() {
#      my @a;
#      foreach (@netdevices) {
#  	$::isStandalone && /plip/ and next;
#  	print (" hhhhh $_ \n");
#  	/ippp/ and run_program::rooted("", "/sbin/isdnctrl addif $_");
#  	c::hasNetDevice($_) and push @a, $_;
#      }
#      /ippp/ and run_program::rooted("", "/sbin/isdnctrl delif $_") foreach @netdevices;
#      @a;
    grep { !(($::isStandalone || $::live) && /plip/) && c::hasNetDevice($_) } @netdevices;
}

#sub getISDN() {
#    mapgrep(sub {member (($_[0] =~ /\s*(\w*):/), @netdevices), $1 }, split(/\n/, cat_("/proc/net/dev")));
#}

sub pci_probe {
    my ($probe_type) = @_;
    log::l("full pci_probe") if $probe_type;
    map {
	my %l;
	@l{qw(vendor id subvendor subid pci_bus pci_device pci_function media_type driver description)} = split "\t";
	$l{$_} = hex $l{$_} foreach qw(vendor id subvendor subid);
	$l{bus} = 'PCI';
	\%l
    } c::pci_probe($probe_type || 0);
}

sub usb_probe {
    -e "/proc/bus/usb/devices" or return ();

    map {
	my %l;
	@l{qw(vendor id media_type driver description)} = split "\t";
	$l{$_} = hex $l{$_} foreach qw(vendor id);
	$l{bus} = 'USB';
	\%l
    } c::usb_probe();
}

sub pcmcia_probe {
    -e '/var/run/stab' || -e '/var/lib/pcmcia/stab' or return ();

    my (@devs, $desc);
    foreach (cat_('/var/run/stab'), cat_('/var/lib/pcmcia/stab')) {
	if (/^Socket\s+\d+:\s+(.*)/) {
	    $desc = $1;
	} else {
	    my (undef, $type, $module, undef, $device) = split;
	    push @devs, { description => $desc, driver => $module, type => $type, device => $device };
	}
    }
    @devs;
}

# pci_probe with $probe_type is unsafe for pci! (bug in kernel&hardware)
# pcmcia_probe provides field "device", used in network.pm
# => probeall with $probe_type is unsafe
sub probeall {
    my ($probe_type) = @_;
    require sbus_probing::main;
    pci_probe($probe_type), usb_probe(), pcmcia_probe(), sbus_probing::main::probe();
}
sub matching_desc {
    my ($regexp) = @_;
    grep { $_->{description} =~ /$regexp/i } probeall();
}
sub stringlist { 
    map {
	sprintf("%-16s: %s%s%s", 
		$_->{driver} ? $_->{driver} : 'unknown', 
		$_->{description} eq '(null)' ? sprintf("Vendor=0x%04x Device=0x%04x", $_->{vendor}, $_->{id}) : $_->{description},
		$_->{media_type} ? sprintf(" [%s]", $_->{media_type}) : '',
		$_->{subid} && $_->{subid} != 0xffff ? sprintf(" SubVendor=0x%04x SubDevice=0x%04x", $_->{subvendor}, $_->{subid}) : '',
	       );
    } probeall(@_); 
}
sub check {
    my ($l) = @_;
    my $ok = $l->{driver} !~ /(unknown|ignore)/;
    $ok or log::l("skipping $l->{description}, no module available (if you know one, please mail install\@mandrakesoft.com)");
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
    `$ENV{LD_LOADER} /bin/dmesg`;
}

sub hasSMP { c::detectSMP() }
sub hasPCMCIA { $::o->{pcmcia} } #- because /proc/pcmcia seems not to be present on 2.4 at least (or use /var/run/stab)

#- try to detect a laptop, we assume pcmcia service is an indication of a laptop or
#- the following regexp to match graphics card apparently only used for such systems.
sub isLaptop {
    hasPCMCIA() || (matching_desc('C&T.*655[45]\d') || matching_desc('C&T.*68554') ||
		    matching_desc('Neomagic.*Magic(Media|Graph)') ||
		    matching_desc('ViRGE.MX') || matching_desc('S3.*Savage.*[IM]X') ||
		    matching_desc('ATI.*(Mobility|LT)'));
}

sub hasUltra66 {
    die "hasUltra66 deprecated";
    #- keep it BUT DO NOT USE IT as now included in kernel.
    cat_("/proc/cmdline") =~ /(ide2=(\S+)(\s+ide3=(\S+))?)/ and return $1;

    my @l = map { $_->{verbatim} } matching_desc('HPT|Ultra66') or return;
    
    my $ide = sprintf "ide2=0x%x,0x%x ide3=0x%x,0x%x",
      @l == 2 ?
	(map_index { hex($_) + (odd($::i) ? 1 : -1) } map { (split ' ')[3..4] } @l) :
	(map_index { hex($_) + (odd($::i) ? 1 : -1) } map { (split ' ')[3..6] } @l);

    log::l("HPT|Ultra66: found $ide");
    $ide;
}

sub whatParport() {
    my @res = ();
    foreach (0..3) {
	my $elem = {};
	local *F;
	open F, "/proc/parport/$_/autoprobe" or open F, "/proc/sys/dev/parport/parport$_/autoprobe" or next;
	{
	    local $_;
	    while (<F>) { $elem->{$1} = $2 if /(.*):(.*);/ }
	}
	push @res, { port => "/dev/lp$_", val => $elem};
    }
    @res;
}

sub usbMice      { grep { $_->{media_type} =~ /\|Mouse/ && $_->{driver} !~ /Tablet:wacom/} usb_probe() }
sub usbWacom     { grep { $_->{driver} =~ /Tablet:wacom/ } usb_probe() }
sub usbKeyboards { grep { $_->{media_type} =~ /\|Keyboard/ } usb_probe() }
sub usbStorage   { grep { $_->{media_type} =~ /Mass Storage\|/ } usb_probe() }

sub whatUsbport() {
    my ($i, $elem, @res) = (0, {});
    foreach (grep { $_->{media_type} =~ /Printer/ } usb_probe()) {
	my ($manufacturer, $model) = split '\|', $_->{description};
	$_->{description} =~ s/Hewlett[-\s_]Packard/HP/;
	push @res, { port => "/dev/usb/lp$i", val => { CLASS => 'PRINTER',
						       MODEL => $model,
						       MANUFACTURER => $manufacturer,
						       DESCRIPTION => $_->{description},
						     }};
	++$i;
    }
    @res;
}

#-CLASS:PRINTER;
#-MODEL:HP LaserJet 1100;
#-MANUFACTURER:Hewlett-Packard;
#-DESCRIPTION:HP LaserJet 1100 Printer;
#-COMMAND SET:MLC,PCL,PJL;
sub whatPrinter() {
    my @res = (whatParport(), whatUsbport());
    grep { $_->{val}{CLASS} eq "PRINTER"} @res;
}

sub whatPrinterPort() {
    grep { tryWrite($_)} qw(/dev/lp0 /dev/lp1 /dev/lp2 /dev/usb/lp0 /dev/usb/lp1 /dev/usb/lp2);
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
    local *F; open F, "$ENV{LD_LOADER} serial_probe |";
    local $_;
    my %current = (); while (<F>) {
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

sub raidAutoStartIoctl {
    eval { modules::load('md') };
    my $md = devices::make("md0");
    local *F;
    sysopen F, $md, 2 or return;
    ioctl F, 2324, 0;
}

sub raidAutoStart {
    log::l("raidAutoStart");
    my %personalities = ( '1' => 'linear', '2' => 'raid0', '3' => 'raid1', '4' => 'raid5' );
    raidAutoStartIoctl() or log::l("warning, RAID_AUTORUN not supported by kernel"), return;
    if (my @needed_perso = map { if_(/^kmod: failed.*md-personality-(.)/, $personalities{$1}) } syslog()) {
	log::l("RAID: autostart needs personality from $_"), eval { modules::load($_) } foreach @needed_perso;
	return raidAutoStartIoctl();
    } else {
	1;
    }
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #

