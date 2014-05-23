package detect_devices; # $Id$

use diagnostics;
use strict;
use vars qw($pcitable_addons $usbtable_addons);

#-######################################################################################
#- misc imports
#-######################################################################################
use log;
use MDK::Common; # help perl_checker
use common;
use devices;
use run_program;
use modules;
use c;
use LDetect;
use feature 'state';

#-#####################################################################################
#- Globals
#-#####################################################################################
my %serialprobe;

#-######################################################################################
#- Functions
#-######################################################################################

sub get() {
    #- Detect the default BIOS boot harddrive is kind of tricky. We may have IDE,
    #- SCSI and RAID devices on the same machine. From what I see so far, the default
    #- BIOS boot harddrive will be
    #- 1. The first IDE device if IDE exists. Or
    #- 2. The first SCSI device if SCSI exists. Or
    #- 3. The first RAID device if RAID exists.

    getIDE(), getSCSI(), getMmcBlk(), getXenBlk(), getVirtIO(), getDAC960(), getCompaqSmartArray(), getATARAID();
}
sub hds()         { grep { may_be_a_hd($_) } get() }
sub tapes()       { grep { $_->{media_type} eq 'tape' } get() }
sub cdroms()      { grep { $_->{media_type} eq 'cdrom' } get() }
sub burners()     { grep { isBurner($_) } cdroms() }
sub dvdroms()     { grep { isDvdDrive($_) } cdroms() }
sub raw_zips()    { grep { member($_->{media_type}, 'fd', 'hd') && isZipDrive($_) } get() }
sub ls120s()      { grep { member($_->{media_type}, 'fd', 'hd') && isLS120Drive($_) } get() }
sub zips()        {
    map { 
	$_->{device} .= 4; 
	$_;
    } raw_zips();
}

sub floppies {
    my ($o_not_detect_legacy_floppies) = @_;
    require modules;
    state @fds;
    state $legacy_already_detected;

    $o_not_detect_legacy_floppies = 1 if arch() =~ /mips|arm/;

    if (!$o_not_detect_legacy_floppies && !$legacy_already_detected) {
        $legacy_already_detected = 1;
        eval { modules::load("floppy") if $::isInstall };
        #- do not bother probing /dev/fd0 and loading floppy device uselessly,
        #- it takes time and it is already done by boot process (if not in install):
        #-   /dev/fd0 is created by udev (/etc/udev/devices.d/default.nodes)
        #-   then hal probes /dev/fd0 and triggers floppy module loading through kernel's kmod
        if (any { (split)[1] eq 'fd' } cat_("/proc/devices")) {
            @fds = map {
                my $info = c::floppy_info(devices::make("fd$_"));
                if_($info && $info ne '(null)', { device => "fd$_", media_type => 'fd', info => $info });
            } qw(0 1);
        }
    }
        
    my @ide = ls120s() and eval { modules::load("ide_floppy") };

    eval { modules::load("usb_storage") } if $::isInstall && usbStorage();
    my @scsi = grep { $_->{media_type} eq 'fd' } getSCSI();
    @ide, @scsi, @fds;
}
sub floppies_dev() { map { $_->{device} } floppies() }
sub floppy() { first(floppies_dev()) }
#- example ls120, model = "LS-120 SLIM 02 UHD Floppy"

sub removables() {
    floppies(), cdroms(), zips();
}

sub get_sys_cdrom_info {
    my (@drives) = @_;

    my @drives_order;
    foreach (cat_("/proc/sys/dev/cdrom/info")) {
	my ($t, $l) = split ':';
	my @l;
	@l = split(' ', $l) if $l;
	if ($t eq 'drive name') {
	    @drives_order = map {
		my $dev = $_;
		find { $_->{device} eq $dev } @drives;
	    } @l;
	} else {
	    my $capacity;
	    if ($t eq 'Can write CD-R') {
		$capacity = 'burner';
	    } elsif ($t eq 'Can read DVD') {
		$capacity = 'DVD';
	    }
	    if ($capacity) {
		each_index {
		    ($drives_order[$::i] || {})->{capacity} .= "$capacity " if $_;
		} @l;
	    }
	}
    }
}

sub complete_usb_storage_info {
    my (@l) = @_;

    my @usb = grep { exists $_->{usb_vendor} } @l;

    foreach my $usb (usb_probe()) {
	if (my $e = find { !$_->{found} && $_->{usb_vendor} == $usb->{vendor} && $_->{usb_id} == $usb->{id} } @usb) {
         my $host = get_sysfs_usbpath_for_block($e->{device});
         if ($host) {
             my $file = "/sys/block/$host/../serial";
             $e->{info} = chomp_(cat_($file)) if -e $file;
             $e->{usb_description} = join('|', 
                                          chomp_(cat_("/sys/block/$host/../manufacturer")),
                                          chomp_(cat_("/sys/block/$host/../product")));
         }
         local $e->{found} = 1;
	    $e->{"usb_$_"} ||= $usb->{$_} foreach keys %$usb;
	}
    }
}

sub isBurner { 
    my ($e) = @_;
    $e->{capacity} =~ /burner/ and return 1;
      
    #- do not work for SCSI
    my $f = tryOpen($e->{device}); #- SCSI burner are not detected this way.
    $f && c::isBurner(fileno($f));
}
sub isDvdDrive {
    my ($e) = @_;
    $e->{capacity} =~ /DVD/ || $e->{info} =~ /DVD/ and return 1;

    #- do not work for SCSI
    my $f = tryOpen($e->{device});
    $f && c::isDvdDrive(fileno($f));
}
sub isZipDrive { $_[0]{info} =~ /ZIP\s+\d+/ } #- accept ZIP 100, untested for bigger ZIP drive.
sub isLS120Drive { $_[0]{info} =~ /LS-?120|144MB/ }
sub isKeyUsb { begins_with($_[0]{usb_media_type} || '', 'Mass Storage') && $_[0]{media_type} eq 'hd' }
sub isFloppyUsb { $_[0]{usb_driver} && $_[0]{usb_driver} eq 'Removable:floppy' }
sub may_be_a_hd { 
    my ($e) = @_;
    $e->{media_type} eq 'hd' && !(
	isZipDrive($e) 
           || isLS120Drive($e)
           || begins_with($e->{usb_media_type} || '', 'Mass Storage|Floppy (UFI)')
    );
}

sub get_sysfs_field_from_link {
    my ($device, $field) = @_;
    my $l = readlink("$device/$field");
    $l =~ s!.*/!!;
    $l;
}

sub get_sysfs_usbpath_for_block {
    my ($device) = @_;
    my $host = readlink("/sys/block/$device");
    $host =~ s!/host.*!!;
    $host;
}

sub get_scsi_driver {
    my (@l) = @_;
    # find driver of host controller from sysfs:
    foreach (@l) {
	next if $_->{driver};
	my $host = get_sysfs_usbpath_for_block($_->{device});
	require list_modules;
	$_->{driver} = list_modules::filename2modname(get_sysfs_field_from_link("/sys/block/$host", 'driver'));
    }
}

sub getSCSI() {
    my $dev_dir = '/sys/bus/scsi/devices';

    my @scsi_types = (
	"Direct-Access",
	"Sequential-Access",
	"Printer",
	"Processor",
	"WORM",
	"CD-ROM",
	"Scanner",
	"Optical Device",
	"Medium Changer",
	"Communications",
    );

    my @l;
    foreach (all($dev_dir)) {
	my ($host, $channel, $id, $lun) = split ':';
	defined $lun or next;

	my $dir = "$dev_dir/$_";

	# handle both old and new kernels:
	my $node =  find { -e $_ } "$dir/block", top(glob_("$dir/block*")), "$dir/tape", top(glob_("$dir/scsi_generic*"));
	my ($device) = readlink($node) =~ m!/?(?:scsi_(?:generic|tape)|block)/(.*)!;
        if (!$device) {
            ($device) = top(glob_("$node/*")) =~ m!/?(?:scsi_(?:generic|tape)|block)/(.*)!;
        }
	warn("cannot get info for device ($_)"), next if !$device;

	my $usb_dir = readlink($dir) =~ m!/usb! && "$dir/../../../..";
	my $get_usb = sub { chomp_(cat_("$usb_dir/$_[0]")) };

	my $get = sub {
	    my $s = cat_("$dir/$_[0]");
	    $s =~ s/\s+$//;
	    $s;
	};

	# Old hp scanners report themselves as "Processor"s
	# (see linux/include/scsi/scsi.h and sans-find-scanner.1)
	my $raw_type = $scsi_types[$get->('type')];

	my $media_type = ${{ st => 'tape', sr => 'cdrom', sd => 'hd', sg => 'generic' }}{substr($device, 0, 2)} ||
	  $raw_type =~ /Scanner|Processor/ && 'scanner';

	my ($vendor, $model) = ($get->('vendor'), $get->('model'));
	my ($v, $m) = _get_hd_vendor($model);
	if ($v && $m) {
            ($vendor, $model) = ($v, $m);
	}
	push @l, { info =>  $vendor . ' ' . $model, host => $host, channel => $channel, id => $id, lun => $lun, 
	  description => join('|', $vendor, $model),
	  bus => 'SCSI', media_type => $media_type, device => $device,
	    $usb_dir ? (
	  usb_vendor => hex($get_usb->('idVendor')), usb_id => hex($get_usb->('idProduct')),
	    ) : (),
        };
    } 

    @l = sort { $a->{host} <=> $b->{host} || $a->{channel} <=> $b->{channel} || $a->{id} <=> $b->{id} || $a->{lun} <=> $b->{lun} } @l;

    complete_usb_storage_info(@l);

    foreach (@l) {
	$_->{media_type} = 'fd' if $_->{media_type} eq 'hd' && isFloppyUsb($_);
    }

    get_sys_cdrom_info(@l);
    get_scsi_driver(@l);
    @l;
}


my %hd_vendors = (
    "ASUS" => "Asus",
    "ATA Maxtor" => "Maxtor",
    "CD-ROM CDU" => "Sony",
    "CD-ROM Drive/F5D" => "ASUSTeK",
    "Compaq" => "Compaq",
    "CONNER" => "Conner Peripherals",
    "IBM" => "IBM",
    "FUJITSU" => "Fujitsu",
    "HITACHI" => "Hitachi",
    "Lite-On" => "Lite-On Technology Corp.",
    "LITE-ON" => "Lite-On Technology Corp.",
    "LTN" => "Lite-On Technology Corp.",
    "IOMEGA" => "Iomega",
    "MAXTOR" => "Maxtor",
    "Maxtor" => "Maxtor",
    "Micropolis" => "Micropolis",
    "Pioneer" => "Pioneer",
    "PLEXTOR" => "Plextor",
    "QUANTUM" => "Quantum", 
    "SAMSUNG" => "Samsung",
    "Seagate " => "Seagate Technology",
    "ST3" => "Seagate Technology",
    "TEAC" => "Teac",
    "TOSHIBA" => "Toshiba",
    "WDC" => "Western Digital Corp.",
);

# return ($vendor, $model)
sub _get_hd_vendor {
    my ($info) = @_;
    foreach my $name (keys %hd_vendors) {
        next if !$name;
        return ($hd_vendors{$name}, $2) if $info =~ /^$name(-|\s)*(.*)/;
    }
    return ("Hitachi", $info) if $info =~ /^HD[ST][0-9]/;
}


sub getIDE() {
    my @idi;

    #- what about a system with absolutely no IDE on it, like some sparc machine.
    -e "/proc/ide" or return ();

    #- Great. 2.2 kernel, things are much easier and less error prone.
    foreach my $d (sort @{[glob_('/proc/ide/hd*')]}) {
	my $t = chomp_(cat_("$d/media"));
	my $type = ${{ disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd' }}{$t} or next;
	my $info = chomp_(cat_("$d/model")) || "(none)";

	my $num = ord(($d =~ /(.)$/)[0]) - ord 'a';
	my ($vendor, $model) = _get_hd_vendor($info);

	my $host = $num;
	($host, my $id) = divide($host, 2);
	($host, my $channel) = divide($host, 2);

	push @idi, { media_type => $type, device => basename($d), 
		     info => $info, host => $host, channel => $channel, id => $id, bus => 'ide', 
		     if_($vendor, Vendor => $vendor), if_($model, Model => $model) };
    }
    get_sys_cdrom_info(@idi);
    @idi;
}

sub block_devices() {
    -d '/sys/block' 
      ? map { s|!|/|; $_ } all('/sys/block') 
      : map { $_->{dev} } do { require fs::proc_partitions; fs::proc_partitions::read_raw() };
}

sub getCompaqSmartArray() {
    my (@idi, $f);

    foreach ('array/ida', 'cpqarray/ida', 'cciss/cciss') {
	my $prefix = "/proc/driver/$_";
	my ($name) = m|/(.*)|;
	for (my $i = 0; -r ($f = "${prefix}$i"); $i++) {
	    my @raw_devices = cat_($f) =~ m|^\s*($name/.*?):|gm;

	    #- this is ugly and buggy. keeping it for 2007.0
	    #- on a cciss, cciss/cciss0 didn't contain c0d0, but cciss/cciss1 did contain c0d1
	    #- the line below adds both c0d0 and c0d1 for cciss0, and so some duplicates
	    @raw_devices or @raw_devices = grep { m!^$name/! } block_devices();

	    foreach my $raw_device (@raw_devices) {
		my $device = -d "/dev/$raw_device" ? "$raw_device/disc" : $raw_device;
		push @idi, { device => $device, prefix => $raw_device . 'p', 
			     info => "Compaq RAID logical disk",
			     media_type => 'hd', bus => $name };
	    }
	}
    }
    #- workaround the buggy code above. this should be safe though
    uniq_ { $_->{device} } @idi;
}

sub getDAC960() {
    my %idi;

    #- We are looking for lines of this format:DAC960#0:
    #- /dev/rd/c0d0: RAID-7, Online, 17928192 blocks, Write Thru0123456790123456789012
    foreach (syslog()) {
	my ($device, $info) = m|/dev/(rd/.*?): (.*?),| or next;
	$idi{$device} = { info => $info, media_type => 'hd', device => $device, bus => 'dac960' };
    }
    values %idi;
}

sub getATARAID() {
    my %l;
    foreach (syslog()) {
	my ($device) = m|^\s*(ataraid/d\d+):| or next;
	$l{$device} = { info => 'ATARAID block device', media_type => 'hd', device => $device, bus => 'ataraid' };
	log::l("ATARAID: $device");
    }
    values %l;
}

sub getXenBlk() {
    -d '/sys/bus/xen/devices' or return;
    map {   
            s/block://;
            { device => basename($_), info => "Xen block device", media_type => 'hd', bus => 'xen' };
    } glob("/sys/block/xvd*");
}

sub getVirtIO() {
    -d '/sys/bus/virtio/devices' or return;
    map {
            { device => basename($_), info => "VirtIO block device", media_type => 'hd', bus => 'virtio' };
    }
    glob("/sys/bus/virtio/devices/*/block/*");
}

sub getMmcBlk() {
    -d '/sys/bus/mmc/devices' or return;
    map {
            { device => basename($_), info => "MMC block device", media_type => 'hd', bus => 'mmc' };
    }
    glob("/sys/bus/mmc/devices/*/block/*");
}

# cpu_name : arch() =~ /^alpha/ ? "cpu	" :
# arch() =~ /^ppc/ ? "processor" : "vendor_id"

# cpu_model : arch() =~ /^alpha/ ? "cpu model" :
# arch() =~ /^ppc/ ? "cpu  " : "model name"

# cpu_freq = arch() =~ /^alpha/ ? "cycle frequency [Hz]" :
# arch() =~ /^ppc/ ? "clock" : "cpu MHz"

sub getCPUs() { 
    my (@cpus, $cpu);
    foreach (cat_("/proc/cpuinfo")) {
	   if (/^processor/) { # ix86 specific
		  push @cpus, $cpu if $cpu;
		  $cpu = {};
	   }
	   $cpu->{$1} = $2 if /^([^\t]+).*:\s(.*)$/;
	   $cpu->{processor}++ if $1 eq "processor";
    }
    push @cpus, $cpu;
    @cpus;
}

sub ix86_cpu_frequency() {
    cat_('/proc/cpuinfo') =~ /cpu MHz\s*:\s*(\d+)/ && $1;
}

sub probe_category {
    my ($category) = @_;

    require list_modules;
    my @modules = list_modules::category2modules($category);

    if_($category =~ /sound/ && arch() =~ /ppc/ && get_mac_model() !~ /IBM/,
	{ driver => 'snd_powermac', description => 'Macintosh built-in' },
    ),
    grep {
	if ($category eq 'network/isdn') {
	    my $b = $_->{driver} =~ /ISDN:([^,]*),?([^,]*)(?:,firmware=(.*))?/;
	    if ($b) {
                $_->{driver} = $1;
                $_->{type} = $2;
                $_->{type} =~ s/type=//;
                $_->{firmware} = $3;
                $_->{driver} eq "hisax" and $_->{options} .= " id=HiSax";
	    }
	    $b;
	} else {
	    member($_->{driver}, @modules);
	}
    } probeall();
}

sub getSoundDevices() {
    probe_category('multimedia/sound');
}

sub isTVcardConfigurable { member($_[0]{driver}, qw(bttv cx88 saa7134)) }

sub getTVcards() { probe_category('multimedia/tv') }

sub getInputDevices() {
    my (@devices, $device);
    my $event;
    foreach (cat_('/proc/bus/input/devices')) {
        if (/^I:/) {
            $device = {};
            $device->{vendor} = /Vendor=(\w+)/ && $1;
            $device->{id} = /Product=(\w+)/ && $1;
            $device->{bustype} = /Bus=(\w+)/ && $1;
        } elsif (/N: Name="(.*)"/) {
	    my $descr = $1;
	    $device->{description} = "|$descr";

	    #- I: Bus=0011 Vendor=0002 Product=0008 Version=7321
	    #- N: Name="AlpsPS/2 ALPS GlidePoint"
	    #- P: Phys=isa0060/serio1/input0
	    #- H: Handlers=mouse1 event2 ts1
	    #- B: EV=f
	    #- B: KEY=420 0 70000 0 0 0 0 0 0 0 0 #=> BTN_LEFT BTN_RIGHT BTN_MIDDLE BTN_TOOL_FINGER BTN_TOUCH
	    #-    or B: KEY=420 0 670000 0 0 0 0 0 0 0 0 #=> same with BTN_BACK
	    #- B: REL=3       #=> X Y
	    #- B: ABS=1000003 #=> X Y PRESSURE

	    #- I: Bus=0011 Vendor=0002 Product=0008 Version=2222
	    #- N: Name="AlpsPS/2 ALPS DualPoint TouchPad"
	    #- P: Phys=isa0060/serio1/input0
	    #- S: Sysfs=/class/input/input2
	    #- H: Handlers=mouse1 ts1 event2 
	    #- B: EV=f
	    #- B: KEY=420 0 70000 0 0 0 0 0 0 0 0
	    #- B: REL=3
	    #- B: ABS=1000003

	    #- I: Bus=0011 Vendor=0002 Product=0007 Version=0000
	    #- N: Name="SynPS/2 Synaptics TouchPad"
	    #- P: Phys=isa0060/serio1/input0
	    #- S: Sysfs=/class/input/input1
	    #- H: Handlers=mouse0 event1 ts0
	    #- B: EV=b
	    #- B: KEY=6420 0 70000 0 0 0 0 0 0 0 0 #=> BTN_LEFT BTN_RIGHT BTN_MIDDLE BTN_TOOL_FINGER BTN_TOUCH BTN_TOOL_DOUBLETAP BTN_TOOL_TRIPLETAP
	    #-    or B: KEY=6420 0 670000 0 0 0 0 0 0 0 0  #=> same with BTN_BACK
	    #-    or B: KEY=420 30000 670000 0 0 0 0 0 0 0 0 #=> same without BTN_TOOL_TRIPLETAP but with BTN_B
	    #- B: ABS=11000003 #=> X Y PRESSURE TOOL_WIDTH

	    #- I: Bus=0003 Vendor=056a Product=0065 Version=0108
	    #- N: Name="Wacom Bamboo"
	    #- B: KEY=1c63 0 70033 0 0 0 0 0 0 0 0 #=> BTN_0 BTN_1 BTN_4 BTN_5 BTN_LEFT BTN_RIGHT BTN_MIDDLE TOOL_PEN TOOL_RUBBER TOOL_BRUSH TOOL_FINGER TOOL_MOUSE TOUCH STYLUS STYLUS2
            #- B: ABS=100 3000103 #=> X Y WHEEL PRESSURE DISTANCE MISC

	    #- I: Bus=0003 Vendor=056a Product=0011 Version=0201
	    #- N: Name="Wacom Graphire2 4x5"
            #- B: KEY=1c43 0 70000 0 0 0 0 0 0 0 0 #=> BTN_LEFT BTN_RIGHT BTN_MIDDLE TOOL_PEN TOOL_RUBBER TOOL_FINGER TOOL_MOUSE TOUCH STYLUS STYLUS2
            #- B: ABS=100 3000003 #=> X Y PRESSURE DISTANCE MISC

            #I: Bus=0003 Vendor=049f Product=0024 Version=0001
	    #N: Name="Compaq Compaq Numeric Keypad"
	    #P: Phys=usb-0000:00:03.2-2/input0
	    #S: Sysfs=/class/input/input7
	    #H: Handlers=kbd event3
	    #B: EV=120003
	    #B: KEY=10000 7 ff800000 7ff febeffdf ffefffff ffffffff fffffffe
	    #B: LED=1f

	    $device->{Synaptics} = $descr eq 'SynPS/2 Synaptics TouchPad';
	    $device->{ALPS} = $descr =~ m!^AlpsPS/2 ALPS!;
	    $device->{Elantech} = $descr eq 'ETPS/2 Elantech Touchpad';
	    $device->{Numpad} = $descr =~ /Numeric Keypad/;

	} elsif (/H: Handlers=(.*)/) {
	    my @l = split(' ', $1);
	    $device->{driver} = $l[0]; #- keep it for compatibility
	    $device->{Handlers} = +{ map { (/^(.*?)\d*$/ ? $1 : $_, $_) } split(' ', $1) };
	    $event = $device->{Handlers}{event};
	} elsif (/S: Sysfs=(.+)/) {
	    $device->{sysfs_path} = $1;
	} elsif (/P: Phys=(.*)/) {
            $device->{location} = $1;
            $device->{bus} = 'isa' if $device->{location} =~ /^isa/;
            $device->{bus} = 'usb' if $device->{location} =~ /^usb/i;
	} elsif (/B: REL=(.* )?(.*)/) {
	    #- REL=3   #=> X Y
	    #- REL=103 #=> X Y WHEEL
	    #- REL=143 #=> X Y HWHEEL WHEEL
	    #- REL=1c3 #=> X Y HWHEEL DIAL WHEEL
	    my $REL = hex($2);
	    $device->{HWHEEL} = 1 if $REL & (1 << 6);
	    $device->{WHEEL} = 1 if $REL & (1 << 8); #- not reliable ("Mitsumi Apple USB Mouse" says REL=103 and KEY=1f0000 ...)

	} elsif (/B: KEY=(\S+)/) {	   
	    #- some KEY explained:
	    #- (but note that BTN_MIDDLE can be reported even if missing)
	    #- (and "Mitsumi Apple USB Mouse" reports 1f0000)
	    #- KEY=30000 0 0 0 0 0 0 0 0  #=> BTN_LEFT BTN_RIGHT
	    #- KEY=70000 0 0 0 0 0 0 0 0  #=> BTN_LEFT BTN_RIGHT BTN_MIDDLE
	    #- KEY=1f0000 0 0 0 0 0 0 0 0 #=> BTN_LEFT BTN_RIGHT BTN_MIDDLE BTN_SIDE BTN_EXTRA
	    if (!$> && ! -f "/dev/input/$event") {
		    devices::make("/dev/input/$event");
	    }
	    if (-r "/dev/input/$event") {
		my @KEYS = c::EVIocGBitKey("/dev/input/$event");
		$device->{SIDE} = 1 if $KEYS[0] & (1 << 0x13);
	    } else {
		my $KEY = hex($1);
		$device->{SIDE} = 1 if $KEY & (1 << 0x13);
	    }

        } elsif (/^\s*$/) {
	    push @devices, $device if $device;
	    undef $device;
	}
    }
    @devices;
}

sub getInputDevices_and_usb() {
    my @l = getInputDevices();

    foreach my $usb (usb_probe()) {
	if (my $e = find { hex($_->{vendor}) == $usb->{vendor} && hex($_->{id}) == $usb->{id} } @l) {
	    $e->{usb} = $usb;
	}
    }

    @l;
}

sub serialPorts() { map { "ttyS$_" } 0..7 }
sub serialPort2text {
    $_[0] =~ /ttyS(\d+)/ ? "$_[0] / COM" . ($1 + 1) : $_[0];
}

sub getSerialModem {
    my ($modules_conf, $o_mouse) = @_;
    my $mouse = $o_mouse || {};
    $mouse->{device} = readlink "/dev/mouse";
    my $serdev = arch() =~ /ppc/ ? "macserial" : arch() =~ /mips/ ? "8250" : "serial";

    eval { modules::load($serdev) };

    my @modems;

    probeSerialDevices();
    foreach my $port (serialPorts()) {
	next if $mouse->{device} =~ /$port/;
     my $device = "/dev/$port";
	next if !-e $device || !hasModem($device);
     $serialprobe{$device}{device} = $device;
     push @modems, $serialprobe{$device};
    }
    my @devs = pcmcia_probe();
    foreach my $modem (@modems) {
        #- add an alias for macserial on PPC
        $modules_conf->set_alias('serial', $serdev) if arch() =~ /ppc/ && $modem->{device};
        foreach (@devs) { $_->{device} and $modem->{device} = $_->{device} }
    }
    @modems;
}

our $detect_serial_modem = 1;
sub getModem {
    my ($modules_conf) = @_;
    ($detect_serial_modem ? getSerialModem($modules_conf, {}) : ()), get_winmodems();
}

sub get_winmodems() {
    matching_driver__regexp('www\.linmodems\.org'),
    matching_driver(list_modules::category2modules('network/modem'),
    list_modules::category2modules('network/slmodem'));
}

sub getBewan() {
    matching_desc__regexp('Bewan Systems\|.*ADSL|BEWAN ADSL USB|\[Unicorn\]');
}

# generate from the following from eci driver sources:
# perl -e 'while (<>) { print qq("$1$2",\n"$3$4",\n) if /\b([a-z\d]*)\s*([a-z\d]*)\s*([a-z\d]*)\s*([a-z\d]*)$/ }' <modems.db|sort|uniq
sub getECI() {
    my @ids = (
              "05090801",
              "05472131",
              "06590915",
              "071dac81",
              "08ea00c9",
              "09150001",
              "09150002",
              "091500ca",
              "091500e7",
              "09150101",
              "09150102",
              "09150204",
              "09150206",
              "09150802",
              "09150916",
              "09158000",
              "09158001",
              "0915ac82",
              "0baf00e6",
              "0e600100",
              "0e600101",
              "0fe88000",
              "16900203",
              "16900205",
             );
    grep { member(sprintf("%04x%04x%04x%04x", $_->{vendor}, $_->{id}, $_->{subvendor}, $_->{subid}), @ids) } usb_probe();
}

sub get_xdsl_usb_devices() {
    my @bewan = detect_devices::getBewan();
    $_->{driver} = $_->{bus} eq 'USB' ? 'unicorn_usb_atm' : 'unicorn_pci_atm' foreach @bewan;
    my @eci = detect_devices::getECI();
    $_->{driver} = 'eciusb' foreach @eci;
    my @usb = detect_devices::probe_category('network/usb_dsl');
    $_->{description} = "USB ADSL modem (eagle chipset)" foreach
      grep { $_->{driver} eq 'ueagle_atm' && $_->{description} eq '(null)' } @usb;
    @usb, @bewan, @eci;
}

sub is_lan_interface {
    #- we want LAN like interfaces here (eg: ath|br|eth|fddi|plip|ra|tr|usb|wlan).
    #- there's also bnep%d for bluetooth, bcp%d...
    #- we do this by blacklisting the following interfaces:
    #-   hso%d are created by drivers/net/usb/hso.c
    #-   ippp|isdn|plip|ppp (initscripts suggest that isdn%d can be created but kernel sources claim not)
    #-   ippp%d are created by drivers/isdn/i4l/isdn_ppp.c
    #-   plip%d are created by drivers/net/plip.c
    #-   ppp%d are created by drivers/net/ppp_generic.c
    #-   pan%d are created by bnep
    is_useful_interface($_[0]) &&
    $_[0] !~ /^(?:hso|ippp|isdn|plip|ppp|pan)/;
}

sub is_useful_interface {
    #- sit0 which is *always* created by net/ipv6/sit.c, thus is always created since net.agent loads ipv6 module
    #- wifi%d are created by 3rdparty/hostap/hostap_hw.c (pseudo statistics devices, #14523)
    #- wmaster%d are created by net/mac80211/ieee80211.c ("master" 802.11 device)
    #- ax*, rose*, nr*, bce* and scc* are Hamradio devices (#28776)
    $_[0] !~ /^(?:lo|sit0|wifi|wmaster|ax|rose|nr|bce|scc)/;
}

sub is_wireless_interface {
    my ($interface) = @_;
    #- some wireless drivers don't always support the SIOCGIWNAME ioctl
    #-   ralink devices need to be up to support it
    #-   wlan-ng (prism2_*) need some special tweaks to support it
    #- use sysfs as fallback to detect wireless interfaces,
    #- i.e interfaces for which get_wireless_stats() is available
    c::isNetDeviceWirelessAware($interface)
        || -e "/sys/class/net/$interface/wireless"
        || -e "/sys/class/net/$interface/phy80211";
}

sub get_all_net_devices() {
    #- we need both detection schemes since:
    #-   get_netdevices() use the SIOCGIFCONF ioctl that does not list interfaces that are down
    #-   /proc/net/dev does not list VLAN and IP aliased interfaces
    uniq(
        (map { if_(/^\s*([A-Za-z0-9:\.]*):/, $1) } cat_("/proc/net/dev")),
        c::get_netdevices(),
    );
}

sub get_lan_interfaces() { grep { is_lan_interface($_) } get_all_net_devices() }
sub get_net_interfaces() { grep { is_useful_interface($_) } get_all_net_devices() }
sub get_wireless_interface() { find { is_wireless_interface($_) } get_lan_interfaces() }

sub is_bridge_interface {
    my ($interface) = @_;
    -f "/sys/class/net/$interface/bridge/bridge_id";
}

sub get_ids_from_sysfs_device {
    my ($dev_path) = @_;
    my $dev_cat = sub { chomp_(cat_("$dev_path/$_[0]")) };
    my $usb_root = -f "$dev_path/bInterfaceNumber" && "../" || -f "$dev_path/idVendor" && "";
    my $is_pcmcia = -f "$dev_path/card_id";
    my $sysfs_ids;
    my $bus = get_sysfs_field_from_link($dev_path, "subsystem");
    #- FIXME: use $bus
    if ($is_pcmcia) {
      $sysfs_ids = { modalias => $dev_cat->('modalias') };
    } else {
        $sysfs_ids = $bus eq 'ieee1394' ?
          {
            version => "../vendor_id",
            specifier_id => "specifier_id",
            specifier_version => "version",
          } :
        defined $usb_root ?
          { id => $usb_root . 'idProduct', vendor => $usb_root . 'idVendor' } :
          { id => "device", subid => "subsystem_device", vendor => "vendor", subvendor => "subsystem_vendor" };
        $_ = hex($dev_cat->($_)) foreach values %$sysfs_ids;
        if ($bus eq 'pci') {
            my $device = basename(readlink $dev_path);
            my @ids = $device =~ /^(.{4}):(.{2}):(.{2})\.(.+)$/;
            @$sysfs_ids{qw(pci_domain pci_bus pci_device pci_function)} = map { hex($_) } @ids if @ids;
        }
    }
    $sysfs_ids;
}

sub device_matches_sysfs_ids {
    my ($device, $sysfs_ids) = @_;
    every { defined $device->{$_} && member($device->{$_}, $sysfs_ids->{$_}, 0xffff) } keys %$sysfs_ids;
}

sub device_matches_sysfs_device {
  my ($device, $dev_path) = @_;
  device_matches_sysfs_ids($device, get_ids_from_sysfs_device($dev_path));
}

sub getUPS() {
    # MGE serial PnP devices:
    (map {
        $_->{port} = $_->{DEVICE};
        $_->{bus} = "Serial";
        $_->{driver} = "mge-utalk" if $_->{MODEL} =~ /0001/;
        $_->{driver} = "mge-shut"  if $_->{MODEL} =~ /0002/;
        $_->{media_type} = 'UPS';
        $_->{description} = "MGE UPS SYSTEMS|UPS - Uninterruptible Power Supply" if $_->{MODEL} =~ /000[12]/;
        $_;
    } grep { $_->{DESCRIPTION} =~ /MGE UPS/ } values %serialprobe),
    # USB UPSs;
    (map { ($_->{name} = $_->{description}) =~ s/.*\|//; $_ }
        map {
            if ($_->{description} =~ /Back-UPS/ && $_->{driver} eq 'usbhid') {
                #- FIXME: should not be hardcoded, use $_->{sysfs_device} . */usb:(hiddev\d+)
                #- the device should also be assigned to the ups user
                $_->{port} = "/dev/hiddev0";
                $_->{driver} = 'hidups';
                $_;
            } elsif ($_->{description} =~ /^MGE UPS Systems\|/ && $_->{driver} =~ /ups$/) {
                $_->{port} = "auto";
                $_->{media_type} = 'UPS';
                $_->{driver} = 'newhidups';
                $_;
            } else {
                ();
            }
        } usb_probe());
}

$pcitable_addons = <<'EOF';
# add here lines conforming the pcitable format (0xXXXX\t0xXXXX\t"\w+"\t".*")
EOF

$usbtable_addons = <<'EOF';
# add here lines conforming the usbtable format (0xXXXX\t0xXXXX\t"\w+"\t".*")
EOF

sub install_addons {
    my ($prefix) = @_;

    #- this test means install_addons can only be called after ldetect-lst has been installed.
    if (-d "$prefix/usr/share/ldetect-lst") {
	my $update = 0;
	foreach ([ 'pcitable.d', $pcitable_addons ], [ 'usbtable.d', $usbtable_addons ]) {
	    my ($dir, $str) = @$_;
	    -d "$prefix/usr/share/ldetect-lst/$dir" && $str =~ /^[^#]/m and $update = 1 and
	      output "$prefix/usr/share/ldetect-lst/$dir/95drakx.lst", $str;
	}
	$update and run_program::rooted($prefix, "/usr/sbin/update-ldetect-lst");
    }
}

sub add_addons {
    my ($addons, @l) = @_;

    foreach (split "\n", $addons) {
	/^\s/ and die qq(bad detect_devices::probeall_addons line "$_");
	s/^#.*//;
	s/"(.*?)"/$1/g;
	next if /^$/;
	my ($vendor, $id, $driver, $description) = split("\t", $_, 4) or die qq(bad detect_devices::probeall_addons line "$_");
	foreach (@l) {
	    $_->{vendor} == hex $vendor && $_->{id} == hex $id or next;
	    put_in_hash($_, { driver => $driver, description => $description });
	}
    }
    @l;
}

sub get_pci_sysfs_path {
    my ($l) = @_;
    sprintf('%04x:%02x:%02x.%d', $l->{pci_domain}, $l->{pci_bus}, $l->{pci_device}, $l->{pci_function});
}


my (@pci, @usb);

sub pci_probe__real() {
    add_addons($pcitable_addons, map {
	my $l = $_;
	$l->{bus} = 'PCI';
	$l->{sysfs_device} = '/sys/bus/pci/devices/' . get_pci_sysfs_path($l);
	$l;
    } LDetect::pci_probe());
}
sub pci_probe() {
    state $done;
    if (!$done) {
        @pci = pci_probe__real() if !@pci;
        foreach (@pci) {
            $_->{nice_bus} = $_->{is_pciexpress} ? "PCI Express" : "PCI";
        }
    }
    @pci;
}

sub usb_probe__real() {
    -e "/sys/kernel/debug/usb/devices" or return;

    add_addons($usbtable_addons, map {
	my $l = $_;
	$l->{media_type} = join('|', grep { $_ ne '(null)' } split('\|', $l->{media_type}));
	$l->{sysfs_device} = "/sys/bus/usb/devices/$l->{pci_bus}-" . ($l->{usb_port} + 1);
	$l->{bus} = 'USB';
	$l;
    } LDetect::usb_probe());
}
sub usb_probe() {
    if ($::isStandalone && @usb) {
	    @usb;
    } else {
	    @usb = usb_probe__real();
    }
}

sub firewire_probe() {
    my $dev_dir = '/sys/bus/ieee1394/devices';
    my @l = map {
        my $dir = "$dev_dir/$_";
        my $get = sub { chomp_(cat_($_[0])) };
        {
            version => hex($get->("$dir/../vendor_id")),
            specifier_id => hex($get->("$dir/specifier_id")),
            specifier_version => hex($get->("$dir/version")),
            bus => 'Firewire',
            sysfs_device => $dir,
        };
    } grep { -f "$dev_dir/$_/specifier_id" } all($dev_dir);

    my $e;
    foreach (cat_('/proc/bus/ieee1394/devices')) {
	if (m!Vendor/Model ID: (.*) \[(\w+)\] / (.*) \[(\w+)\]!) {
	    push @l, $e = { 
			   vendor => hex($2), id => hex($4), 
			   description => join('|', $1, $3),
			   bus => 'Firewire',
			  };
	} elsif (/Software Specifier ID: (\w+)/) {
	    $e->{specifier_id} = hex $1;
	} elsif (/Software Version: (\w+)/) {
	    $e->{specifier_version} = hex $1;	    
	}
    }

    foreach (@l) {
	if ($_->{specifier_id} == 0x00609e && $_->{specifier_version} == 0x010483) {
	    add2hash($_, { driver => 'sbp2', description => "Generic Firewire Storage Controller" });
	} elsif ($_->{specifier_id} == 0x00005e && $_->{specifier_version} == 0x000001) {
	    add2hash($_, { driver => 'eth1394', description => "IEEE 1394 IPv4 Driver (IPv4-over-1394 as per RFC 2734)" });
	}
    }
    @l;
}

sub pcmcia_controller_probe() {
    my ($controller) =  probe_category('bus/pcmcia');
    if (!$controller && !$::testing && !$::noauto && arch() =~ /i.86/) {
        my $driver = c::pcmcia_probe();
        $controller = { driver => $driver, description => "PCMCIA controller ($driver)" } if $driver;
    }
    $controller;
}

sub pcmcia_probe() {
    require modalias;
    require modules;
    my $dev_dir = '/sys/bus/pcmcia/devices';
    map {
        my $dir = "$dev_dir/$_";
        my $get = sub { chomp_(cat_("$dir/$_[0]")) };
        my $class_dev = first(glob_("$dir/tty/tty*"));
        my $device = $class_dev && basename($class_dev);
        my $modalias = $get->('modalias');
        my $driver = get_sysfs_field_from_link($dir, 'driver');
        #- fallback on modalias result
        #- but only if the module isn't loaded yet (else, it would already be binded)
        #- this prevents from guessing the wrong driver for multi-function devices
        my $module = $modalias && first(modalias::get_modules($modalias));
        $driver ||= !member($module, modules::loaded_modules()) && $module;
        {
            description => join(' ', grep { $_ } map { $get->("prod_id$_") } 1 .. 4),
            driver => $driver,
            if_($modalias, modalias => $modalias),
            if_($device, device => $device),
            bus => 'PCMCIA',
            sysfs_device => $dir,
        };
    } all($dev_dir);
}

sub dmi_probe() {
    state $dmi_probe;
    if (arch() !~ /86/) {
        return [];
    }
    $dmi_probe ||= $> ? [] : [ LDetect::dmi_probe() ];
    @$dmi_probe;
}

# pcmcia_probe provides field "device", used in network.pm
# => probeall with $probe_type is unsafe
sub probeall() {
    return if $::noauto;

    pci_probe(), usb_probe(), firewire_probe(), pcmcia_probe(), dmi_probe(), getInputDevices_and_usb();
}
sub probeall_update_cache() {
    return if $::noauto;
    @pci = pci_probe__real(), @usb = usb_probe__real(), firewire_probe(), pcmcia_probe(), dmi_probe();
}
sub matching_desc__regexp {
    my ($regexp) = @_;
    grep { $_->{description} =~ /$regexp/i } probeall();
}
sub matching_driver__regexp {
    my ($regexp) = @_;
    grep { $_->{driver} =~ /$regexp/i } probeall();
}
sub matching_card__regexp {
    my ($regexp) = @_;
    grep { $_->{card} =~ /$regexp/i } probeall();
}
sub matching_driver {
    my (@list) = @_;
    grep { member($_->{driver}, @list) } probeall();
}
sub matching_card {
    my (@list) = @_;
    grep { member($_->{card}, @list) } probeall();
}
sub probe_name {
    my ($name) = @_;
    map { $_->{driver} =~ /^$name:(.*)/ } probeall();
}
sub probe_unique_name {
    my ($name) = @_;
    my @l = uniq(probe_name($name));
    if (@l > 1) {
	log::l("oops, more than one $name from probe: ", join(' ', @l));
    }
    $l[0];
}

sub stringlist {
    my ($b_verbose) = @_;
    map {
	my $ids = $b_verbose || $_->{description} eq '(null)' ?  sprintf("vendor:%04x device:%04x", $_->{vendor}, $_->{id}) : '';
	my $subids = $_->{subid} && $_->{subid} != 0xffff ? sprintf("subv:%04x subd:%04x", $_->{subvendor}, $_->{subid}) : '';
	sprintf("%-16s: %s%s%s", 
		$_->{driver} || 'unknown', 
		$_->{description},
		$_->{media_type} ? sprintf(" [%s]", $_->{media_type}) : '',
		$ids || $subids ? " ($ids" . ($ids && $subids && " ") . "$subids)" : '',
	       );
    } probeall(); 
}

sub tryOpen($) {
    my $F;
    sysopen($F, devices::make($_[0]), c::O_NONBLOCK()) && $F;
}

sub tryWrite($) {
    my $F;
    sysopen($F, devices::make($_[0]), 1 | c::O_NONBLOCK()) && $F;
}

my @dmesg;
sub syslog() {
    if (-r "/tmp/syslog") {
	map { /<\d+>(.*)/ } cat_("/tmp/syslog");
    } else {
	@dmesg = `/bin/dmesg` if !@dmesg;
	@dmesg;
    }
}

sub get_mac_model() {
    my $mac_model = cat_("/proc/device-tree/model") || die "Cannot open /proc/device-tree/model";
    log::l("Mac model: $mac_model");
    $mac_model;	
}

sub get_mac_generation() {
    cat_('/proc/cpuinfo') =~ /^pmac-generation\s*:\s*(.*)/m ? $1 : "Unknown Generation";	
}

sub hasSMP() { 
    return if $::testing;
    (any { /NR_CPUS limit of 1 reached/ } syslog()) ||
     (any { /^processor\s*:\s*(\d+)/ && $1 > 0 } cat_('/proc/cpuinfo')) ||
      any { /\bProcessor #(\d+)\s+(\S*)/ && $1 > 0 && $2 ne 'invalid' } syslog();
}
sub hasPCMCIA() { $::o->{pcmcia} }

my (@dmis, $dmidecode_already_runned);

# we return a list b/c several DMIs have the same name:
sub dmidecode() {
    return @dmis if $dmidecode_already_runned;

    return if $>;
    my ($ver, @l) = arch() =~ /86/ ? run_program::get_stdout('dmidecode') : ();

    my $tab = "\t";

    my ($major, $minor) = $ver =~ /(\d+)\.(\d+)/;

    if ($major > 2 || $major == 2 && $minor > 7) {
	#- new dmidecode output is less indented
	$tab = '';
	#- drop header
	shift @l while @l && $l[0] ne "\n";
    }

    foreach (@l) {
	next if /TRUNCATED/;
	if (/^$tab\t(.*)/) {
	    $dmis[-1]{string} .= "$1\n";
	    $dmis[-1]{$1} = $2 if /^$tab\t(.*): (.*)$/;
	} elsif (my ($s) = /^$tab(.*)/) {
	    next if $s =~ /^$/ || $s =~ /\bDMI type \d+/;
	    $s =~ s/ Information$//;
	    push @dmis, { name => $s };
	}
    }
    $dmidecode_already_runned = 1;
    @dmis;
}
sub dmidecode_category {
    my ($cat) = @_;
    my @l = grep { $_->{name} eq $cat } dmidecode();
    wantarray() ? @l : $l[0] || {};
}

#- size in MB
sub dmi_detect_memory() {
    my @l1 = map { $_->{'Enabled Size'} =~ /(\d+) MB/ && $1 } dmidecode_category('Memory Module');
    my @l2 = map { $_->{'Form Factor'} =~ /^(SIMM|SIP|DIP|DIMM|FB-DIMM|RIMM|SODIMM|SRIMM)$/ && 		     
		     ($_->{Size} =~ /(\d+) MB/ && $1 || $_->{Size} =~ /(\d+) kB/ && $1 * 1024);
		 } dmidecode_category('Memory Device');
    max(sum(@l1), sum(@l2));
}

sub computer_info() {
     my $Chassis = dmidecode_category('Chassis')->{Type} =~ /(\S+)/ && $1;

     my $date = dmidecode_category('BIOS')->{'Release Date'} || '';
     my $BIOS_Year = $date =~ m!(\d{4})! && $1 ||
	             $date =~ m!\d\d/\d\d/(\d\d)! && "20$1";
	
     +{ 
	 isLaptop => member($Chassis, 'Portable', 'Laptop', 'Notebook', 'Hand Held', 'Sub Notebook', 'Docking Station'),
	 isServer => member($Chassis, 'Pizza Box', 'Main Server Chassis', 'Rack Mount Chassis', 'Blade'),
	 if_($BIOS_Year, BIOS_Year => $BIOS_Year),
     };
}

#- try to detect a laptop, we assume pcmcia service is an indication of a laptop or
#- the following regexp to match graphics card apparently only used for such systems.
sub isLaptop() {
    arch() =~ /ppc/ ? 
      get_mac_model() =~ /Book/ :
      computer_info()->{isLaptop}
	|| glob_("/sys/bus/acpi/devices/PNP0C0D:*") #- ACPI lid button
	|| (matching_desc__regexp('C&T.*655[45]\d') || matching_desc__regexp('C&T.*68554') ||
	    matching_desc__regexp('Neomagic.*Magic(Media|Graph)') ||
	    matching_desc__regexp('ViRGE.MX') || matching_desc__regexp('S3.*Savage.*[IM]X') ||
	    matching_desc__regexp('Intel Corporation\|Mobile') ||
	    matching_desc__regexp('\bATI\b.*(Mobility|\bLT\b)'))
	|| (any { $_->{'model name'} =~ /\b(mobile|C7-M)\b/i } getCPUs())
	|| probe_unique_name("Type") eq 'laptop'
        #- ipw2100/2200/3945 are Mini-PCI (Express) adapters
	|| (any { member($_->{driver}, qw(ipw2100 ipw2200 ipw3945)) } pci_probe());
}

sub isServer() {
    computer_info()->{isServer}
      || (any { $_->{Type} =~ /ECC/ } dmidecode_category('Memory Device'))
      || dmidecode_category('System Information')->{Manufacturer} =~ /Supermicro/i
      || dmidecode_category('System Information')->{'Product Name'} =~ /NetServer|Proliant|PowerEdge|eServer|IBM System x|ThinkServer/i
      || matching_desc__regexp('LSI Logic.*SCSI')
      || matching_desc__regexp('MegaRAID')
      || matching_desc__regexp('NetServer')
      || (any { $_->{'model name'} =~ /(Xeon|Opteron)/i } getCPUs());
}

sub isHyperv() {
      dmidecode_category('System')->{Manufacturer} =~ /Microsoft Corporation/i
      && dmidecode_category('System')->{'Product Name'} =~ /Virtual Machine/i;
}

sub BIGMEM() {
    arch() !~ /x86_64|ia64/ && $> == 0 && dmi_detect_memory() > 4 * 1024;
}

sub is_i586() {
    return 0 if arch() !~ /86/;
    my $cpuinfo = cat_('/proc/cpuinfo');
    $cpuinfo =~ /^cpu family\s*:\s*(\d+)/m && $1 < 6 ||
      $cpuinfo =~ /^model name\s*:\s*Transmeta.* TM5800/m || # mdvbz#37866
      !has_cpu_flag('cmov');
}

sub is_mips_lemote() {
    to_bool(cat_('/proc/cpuinfo') =~ /lemote/);
}

sub is_mips_ict() {
    to_bool(cat_('/proc/cpuinfo') =~ /ict/);
}

sub is_mips_gdium() {
    to_bool(cat_('/proc/cpuinfo') =~ /gdium/);
}

sub is_mips_st_ls2f() {
    to_bool(cat_('/proc/cpuinfo') =~ /st-ls2f/);
}

sub is_arm_openrd_client() {
    to_bool(cat_('/proc/cpuinfo') =~ /OpenRD Client/);
}

sub is_arm_versatile() {
    to_bool(cat_('/proc/cpuinfo') =~ /ARM-Versatile/);
}

sub is_arm_efikamix() {
    to_bool(cat_('/proc/cpuinfo') =~ /Efika MX/);
}

sub is_xbox() {
    any { $_->{vendor} == 0x10de && $_->{id} == 0x02a5 } pci_probe();
}

sub is_virtualbox() {
    any { $_->{driver} eq 'vboxadd' } detect_devices::pci_probe();
}

sub is_vmware() {
    any { $_->{card} =~ /Card:VMware/ } detect_devices::pci_probe();
}

sub is_netbook_nettop() {
    my @cpus = getCPUs();
    (any { $_->{'model name'} =~ /(\bIntel\(R\) Atom\(TM\)\B)/i } @cpus) ||
    (any { $_->{'model name'} =~ /(\bIntel\(R\) Celeron\(R\) M processor\b|\bVIA C7-M Processor\b|\bGeode\(TM\)\B)/i && $_->{'cpu MHz'} < 1500 } @cpus);
}

sub has_low_resources() {
    availableRamMB() < 100 || arch() =~ /i.86/ && ix86_cpu_frequency() < 350;
}

sub need_light_desktop() {
    has_low_resources() || is_netbook_nettop();
}

sub has_cpu_flag {
    my ($flag) = @_;
    cat_('/proc/cpuinfo') =~ /^flags.*\b$flag\b/m;
}

sub matching_types() {
    +{
	mips_lemote => is_mips_lemote(),
	mips_ict => is_mips_ict(),
	mips_st_ls2f => is_mips_st_ls2f(),
	laptop => isLaptop(),
	hyperv => isHyperv(),
	'numpad' => hasNumpad(),
	'touchpad' => hasTouchpad(),
	'64bit' => to_bool(arch() =~ /64/),
	wireless => to_bool(get_wireless_interface() || probe_category('network/wireless')),
    };
}

sub hasCPUMicrocode() {
    state $hasCPUMicrocode;
    if (!defined $hasCPUMicrocode) {
        $hasCPUMicrocode = to_bool(find { 'microcode' } modules::loaded_modules());
    }
    return $hasCPUMicrocode;
}

sub hasCPUFreq()     {
    require cpupower;
     to_bool(cpupower::get_modules())
       || cat_('/proc/cpuinfo') =~ /AuthenticAMD/ && arch() =~ /x86_64/
#       || cat_('/proc/cpuinfo') =~ /model name.*Intel\(R\) Core\(TM\)2 CPU/
       || cat_('/proc/cpuinfo') =~ /GenuineIntel/;
}
sub hasWacom()     { find { $_->{vendor} == 0x056a || $_->{driver} =~ /wacom/ } usb_probe() }
sub hasTouchpad()  { any { $_->{Synaptics} || $_->{ALPS} || $_->{Elantech} } getInputDevices() }
sub hasNumpad()    { any { $_->{Numpad} } getInputDevices() }

sub usbWacom()     { grep { $_->{vendor} eq '056a' } getInputDevices() }
sub usbKeyboards() { grep { $_->{media_type} =~ /\|Keyboard/ } usb_probe() }
sub usbStorage()   { grep { $_->{media_type} =~ /Mass Storage\|/ } usb_probe() }
sub has_mesh()     { find { /mesh/ } all_files_rec("/proc/device-tree") }
sub has_53c94()    { find { /53c94/ } all_files_rec("/proc/device-tree") }

sub usbKeyboard2country_code {
    my ($usb_kbd) = @_;
    my ($F, $tmp);
    # usbfs is deprecated, so this will be broken if not mounted, but the code seems unused anyways..(?)
    sysopen($F, sprintf("/proc/bus/usb/%03d/%03d", $usb_kbd->{pci_bus}, $usb_kbd->{pci_device}), 0) and
      sysseek $F, 0x28, 0 and
      sysread $F, $tmp, 1 and
      unpack("C", $tmp);
}

sub probeSerialDevices() {
    require list_modules;
    require modules;
    modules::append_to_modules_loaded_at_startup_for_all_kernels(modules::load_category($::o->{modules_conf}, 'various/serial'));
    foreach (0..3) {
	#- make sure the device are created before probing,
	devices::make("/dev/ttyS$_");
	#- and make sure the device is a real terminal (major is 4).
	int((stat "/dev/ttyS$_")[6]/256) == 4 or $serialprobe{"/dev/ttyS$_"} = undef;
    }

    #- for device already probed, we can safely (assuming device are
    #- not moved during install :-)
    #- include /dev/mouse device if using an X server.
    mkdir_p("/var/lock");
    -l "/dev/mouse" and $serialprobe{"/dev/" . readlink "/dev/mouse"} = undef;
    foreach (keys %serialprobe) { m|^/dev/(.*)| and touch "/var/lock/LCK..$1" }

    print STDERR "Please wait while probing serial ports...\n";
    #- start probing all serial ports... really faster than before ...
    #- ... but still take some time :-)
    my %current; 
    foreach (run_program::get_stdout('serial_probe')) {
	if (/^\s*$/) {
	    $serialprobe{$current{DEVICE}} = { %current } if $current{DEVICE};
	    %current = ();
	} elsif (/^([^=]+)=(.*?)\s*$/) {
	    $current{$1} = $2;
	}
    }

    foreach (values %serialprobe) {
	$_->{DESCRIPTION} =~ /modem/i and $_->{CLASS} = 'MODEM'; #- hack to make sure a modem is detected.
	$_->{DESCRIPTION} =~ /olitec/i and $_->{CLASS} = 'MODEM'; #- hack to make sure such modem gets detected.
	log::l("probed $_->{DESCRIPTION} of class $_->{CLASS} on device $_->{DEVICE}");
    }
}

sub probeSerial($) { $serialprobe{$_[0]} }

sub hasModem($) {
    $serialprobe{$_[0]} && $serialprobe{$_[0]}{CLASS} eq 'MODEM' && $serialprobe{$_[0]}{DESCRIPTION};
}

sub hasMousePS2 {
    my $t; sysread(tryOpen($_[0]) || return, $t, 256) != 1 || $t ne "\xFE";
}

sub probeall_unavailable_modules() {
    map {
        my $driver = $_->{driver};
        $driver !~ /:/ &&
        !member($driver, 'hub', 'unknown', 'amd64_agp') &&
        !modules::module_is_available($driver) ?
          $driver :
          @{[]};
    } probeall();
}

sub probeall_dkms_modules() {
    my @unavailable_modules = probeall_unavailable_modules() or return;
    require modalias;
    my $dkms_modules = modalias::parse_file_modules($::prefix . "/usr/share/ldetect-lst/dkms-modules.alias");
    intersection([ keys(%$dkms_modules) ], \@unavailable_modules);
}

sub usb_description2removable {
    local ($_) = @_;
    return 'camera' if /\bcamera\b/i;
    return 'memory_card' if /\bmemory\s?stick\b/i || /\bcompact\s?flash\b/i || /\bsmart\s?media\b/i;
    return 'memory_card' if /DiskOnKey/i || /IBM-DMDM/i;
    return 'zip' if /\bzip\s?(100|250|750)/i;
    return 'floppy' if /\bLS-?120\b/i;
    return;
}

sub usb2removable {
    my ($e) = @_;
    $e->{usb_driver} or return;

    if ($e->{usb_driver} =~ /Removable:(.*)/) {
	return $1;
    } elsif (my $name = usb_description2removable($e->{usb_description})) {
	return $name;
    }
    undef;
}

sub suggest_mount_point {
    my ($e) = @_;

    my $name = $e->{media_type};
    if (member($e->{media_type}, 'hd', 'fd')) {
	if (exists $e->{usb_driver}) {
	    $name = usb2removable($e) || 'removable';
	} elsif (isZipDrive($e)) {
	    $name = 'zip';
	} elsif ($e->{media_type} eq 'fd') {
	    $name = 'floppy';
	} else {
	    log::l("suggest_mount_point: do not know what to with hd $e->{device}");
	}
    }
    $name;
}

1;

#- Local Variables:
#- mode:cperl
#- tab-width:8
#- End:
