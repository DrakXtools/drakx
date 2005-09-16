package detect_devices; # $Id$

use diagnostics;
use strict;
use vars qw($pcitable_addons $usbtable_addons);

#-######################################################################################
#- misc imports
#-######################################################################################
use log;
use common;
use devices;
use run_program;
use modules;
use c;

#-#####################################################################################
#- Globals
#-#####################################################################################
my %serialprobe;

#-######################################################################################
#- Functions
#-######################################################################################
sub dev_is_devfs() { -e "/dev/.devfsd" } #- no $::prefix, returns false during install and that's nice :)


sub get() {
    #- Detect the default BIOS boot harddrive is kind of tricky. We may have IDE,
    #- SCSI and RAID devices on the same machine. From what I see so far, the default
    #- BIOS boot harddrive will be
    #- 1. The first IDE device if IDE exists. Or
    #- 2. The first SCSI device if SCSI exists. Or
    #- 3. The first RAID device if RAID exists.

    getIDE(), getSCSI(), getDAC960(), getCompaqSmartArray(), getATARAID();
}
sub hds()         { grep { may_be_a_hd($_) } get() }
sub tapes()       { grep { $_->{media_type} eq 'tape' } get() }
sub cdroms()      { grep { $_->{media_type} eq 'cdrom' } get() }
sub burners()     { grep { isBurner($_) } cdroms() }
sub dvdroms()     { grep { isDvdDrive($_) } cdroms() }
sub raw_zips()    { grep { member($_->{media_type}, 'fd', 'hd') && isZipDrive($_) } get() }
#-sub jazzs     { grep { member($_->{media_type}, 'fd', 'hd') && isJazzDrive($_) } get() }
sub ls120s()      { grep { member($_->{media_type}, 'fd', 'hd') && isLS120Drive($_) } get() }
sub zips()        {
    map { 
	$_->{device} .= 4; 
	$_->{devfs_device} = $_->{devfs_prefix} . '/part4'; 
	$_;
    } raw_zips();
}

sub floppies() {
    require modules;
    my @fds;
    eval { modules::load("floppy") if $::isInstall };
    if (!is_xbox()) {
        @fds = map {
            my $info = (!dev_is_devfs() || -e "/dev/fd$_") && c::floppy_info(devices::make("fd$_"));
            if_($info && $info ne '(null)', { device => "fd$_", devfs_device => "floppy/$_", media_type => 'fd', info => $info });
        } qw(0 1);
    }
        
    my @ide = ls120s() and eval { modules::load("ide-floppy") };

    eval { modules::load("usb-storage") } if $::isInstall && usbStorage();
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

sub get_usb_storage_info_24 {
    my (@l) = @_;

    my %usbs = map {
	my $s = cat_(glob_("$_/*"));
	my ($host) = $s =~ /^\s*Host scsi(\d+):/m; #-#
	my ($vendor_name) = $s =~ /^\s*Vendor: (.*)/m;
	my ($vendor, $id) = $s =~ /^\s*GUID: (....)(....)/m;
	if_(defined $host, $host => { vendor_name => $vendor_name, usb_vendor => hex $vendor, usb_id => hex $id });
    } glob_('/proc/scsi/usb-storage-*') or return;

    #- only the entries matching the following conditions can be usb-storage devices
    @l = grep { $_->{channel} == 0 && $_->{id} == 0 && $_->{lun} == 0 } @l;
    my %l; push @{$l{$_->{host}}}, $_ foreach @l;

    foreach my $host (keys %usbs) {
	my @choices = @{$l{$host} || []} or log::l("weird, host$host from /proc/scsi/usb-storage-*/* is not in /proc/scsi/scsi"), next;
	if (@choices > 1) {
	    @choices = grep { $_->{info} =~ /^\Q$usbs{$host}{vendor_name}/ } @choices;
	    @choices or log::l("weird, can not find the good entry host$host from /proc/scsi/usb-storage-*/* in /proc/scsi/scsi"), next;
	    @choices == 1 or log::l("argh, can not determine the good entry host$host from /proc/scsi/usb-storage-*/* in /proc/scsi/scsi"), next;
	}
	add2hash($choices[0], $usbs{$host});
    }
    complete_usb_storage_info(@l);

    @l;
}

sub complete_usb_storage_info {
    my (@l) = @_;

    my @usb = grep { exists $_->{usb_vendor} } @l;

    foreach my $usb (usb_probe()) {
	if (my $e = find { !$_->{found} && $_->{usb_vendor} == $usb->{vendor} && $_->{usb_id} == $usb->{id} } @usb) {
         local $e->{found} = 1;
	    $e->{"usb_$_"} = $usb->{$_} foreach keys %$usb;
	}
    }
}

sub get_devfs_devices {
    my (@l) = @_;

    my %h = (cdrom => 'cd', hd => 'disc');

    foreach (@l) {
	$_->{devfs_prefix} = sprintf('scsi/host%d/bus%d/target%d/lun%d', $_->{host}, $_->{channel}, $_->{id}, $_->{lun})
	  if $_->{bus} eq 'SCSI';

	my $t = $h{$_->{media_type}} or next;
	$_->{devfs_device} = $_->{devfs_prefix} . '/' . $t;
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
sub isJazzDrive { $_[0]{info} =~ /\bJAZZ?\b/i } #- accept "iomega jaz 1GB"
sub isLS120Drive { $_[0]{info} =~ /LS-?120|144MB/ }
sub isRemovableUsb { begins_with($_[0]{usb_media_type} || '', 'Mass Storage') && usb2removable($_[0]) }
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

sub get_scsi_driver {
    my (@l) = @_;
    # find driver of host controller from sysfs:
    foreach (@l) {
	next if $_->{driver};
	my $host = readlink("/sys/block/$_->{device}/device");
     $host =~ s!/host.*!!;
	$_->{driver} = readlink("/sys/block/$_->{device}/$host/driver");
	$_->{driver} =~ s!.*/!!;
    }
}

sub getSCSI_24() {
    my $err = sub { log::l("ERROR: unexpected line in /proc/scsi/scsi: $_[0]") };

    my ($first, @l) = common::join_lines(cat_("/proc/scsi/scsi")) or return;
    $first =~ /^Attached devices:/ or $err->($first);

    @l = map_index {
	my ($host, $channel, $id, $lun) = m/^Host: scsi(\d+) Channel: (\d+) Id: (\d+) Lun: (\d+)/ or $err->($_);
	my ($vendor, $model) = /^\s*Vendor:\s*(.*?)\s+Model:\s*(.*?)\s+Rev:/m or $err->($_);
	my ($type) = /^\s*Type:\s*(.*)/m or $err->($_);
	{ info => "$vendor $model", host => $host, channel => $channel, id => $id, lun => $lun, 
	  device => "sg$::i", raw_type => $type, bus => 'SCSI' };
    } @l;

    get_usb_storage_info_24(@l);

    each_index {
	my $dev = "sd" . chr($::i + ord('a'));
	put_in_hash $_, { device => $dev, media_type => isFloppyUsb($_) ? 'fd' : 'hd' };
    } grep { $_->{raw_type} =~ /Direct-Access|Optical Device/ } @l;

    each_index {
	put_in_hash $_, { device => "st$::i", media_type => 'tape' };
    } grep { $_->{raw_type} =~ /Sequential-Access/ } @l;

    each_index {
	put_in_hash $_, { device => "sr$::i", media_type => 'cdrom' };
    } grep { $_->{raw_type} =~ /CD-ROM|WORM/ } @l;

    # Old hp scanners report themselves as "Processor"s
    # (see linux/include/scsi/scsi.h and sans-find-scanner.1)
    each_index {
	put_in_hash $_, { media_type => 'scanner' };
    } grep { $_->{raw_type} =~ /Scanner/ || $_->{raw_type} =~ /Processor / } @l;

    delete $_->{raw_type} foreach @l;

    get_devfs_devices(@l);
    get_sys_cdrom_info(@l);
    get_scsi_driver(@l);
    @l;
}

sub getSCSI_26() {
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

    my @l = map {
	my ($host, $channel, $id, $lun) = split ':' or log::l("bad entry in $dev_dir: $_"), next;

	my $dir = "$dev_dir/$_";
	my $get = sub {
	    my $s = cat_("$dir/$_[0]");
	    $s =~ s/\s+$//;
	    $s;
	};

	my $usb_dir = readlink("$dir/block/device") =~ m!/usb! && "$dir/block/device/../../../..";
	my $get_usb = sub { chomp_(cat_("$usb_dir/$_[0]")) };

	my ($device) = readlink("$dir/block") =~ m!/block/(.*)!;

	my $media_type = ${{ st => 'tape', sr => 'cdrom', sd => 'hd' }}{substr($device, 0, 2)};
	# Old hp scanners report themselves as "Processor"s
	# (see linux/include/scsi/scsi.h and sans-find-scanner.1)
	my $raw_type = $scsi_types[$get->('type')];
	$media_type ||= 'scanner' if $raw_type =~ /Scanner|Processor/;

	{ info =>  $get->('vendor') . ' ' . $get->('model'), host => $host, channel => $channel, id => $id, lun => $lun, 
	  bus => 'SCSI', media_type => $media_type, device => $device,
	    $usb_dir ? (
	  usb_vendor => hex($get_usb->('idVendor')), usb_id => hex($get_usb->('idProduct')),
	    ) : (),
        };
    } all($dev_dir);

    @l = sort { $a->{host} <=> $b->{host} || $a->{channel} <=> $b->{channel} || $a->{id} <=> $b->{id} || $a->{lun} <=> $b->{lun} } @l;

    complete_usb_storage_info(@l);

    foreach (@l) {
	$_->{media_type} = 'fd' if $_->{media_type} eq 'hd' && isFloppyUsb($_);
    }

    get_devfs_devices(@l);
    get_sys_cdrom_info(@l);
    get_scsi_driver(@l);
    @l;
}
sub getSCSI() { c::kernel_version() =~ /^\Q2.6/ ? getSCSI_26() : getSCSI_24() }


my %eide_hds = (
    "ASUS" => "Asus",
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


sub getIDE() {
    my @idi;

    #- what about a system with absolutely no IDE on it, like some sparc machine.
    -e "/proc/ide" or return ();

    #- Great. 2.2 kernel, things are much easier and less error prone.
    foreach my $d (sort @{[glob_('/proc/ide/hd*')]}) {
	cat_("$d/driver") =~ /ide-scsi/ and next; #- already appears in /proc/scsi/scsi
	my $t = chomp_(cat_("$d/media"));
	my $type = ${{ disk => 'hd', cdrom => 'cdrom', tape => 'tape', floppy => 'fd' }}{$t} or next;
	my $info = chomp_(cat_("$d/model")) || "(none)";

	my $num = ord(($d =~ /(.)$/)[0]) - ord 'a';
	my ($vendor, $model) = map { 
	    if_($info =~ /^$_(-|\s)*(.*)/, $eide_hds{$_}, $2);
	} keys %eide_hds;

	my $host = $num;
	($host, my $id) = divide($host, 2);
	($host, my $channel) = divide($host, 2);
	my $devfs_prefix = sprintf('ide/host%d/bus%d/target%d/lun0', $host, $channel, $id);

	push @idi, { media_type => $type, device => basename($d), 
		     devfs_prefix => $devfs_prefix,
		     info => $info, host => $host, channel => $channel, id => $id, bus => 'ide', 
		     if_($vendor, Vendor => $vendor), if_($model, Model => $model) };
    }
    get_devfs_devices(@idi);
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
	my $prefix = "/proc/driver/$_"; #- kernel 2.4 places it here
	$prefix = "/proc/$_" if !-e "${prefix}0"; #- kernel 2.2

	my ($name) = m|/(.*)|;
	for (my $i = 0; -r ($f = "${prefix}$i"); $i++) {
	    my @raw_devices = cat_($f) =~ m|^\s*($name/.*?):|gm;
	    @raw_devices or @raw_devices = grep { m!^$name/! } block_devices();

	    foreach my $raw_device (@raw_devices) {
		my $device = -d "/dev/$raw_device" ? "$raw_device/disc" : $raw_device;
		push @idi, { device => $device, prefix => $raw_device . 'p', 
			     info => "Compaq RAID logical disk",
			     media_type => 'hd', bus => $name };
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
	$idi{$device} = { info => $info, media_type => 'hd', device => $device, prefix => $device . 'p', bus => 'dac960' };
    }
    values %idi;
}

sub getATARAID() {
    my %l;
    foreach (syslog()) {
	my ($device) = m|^\s*(ataraid/d\d+):| or next;
	$l{$device} = { info => 'ATARAID block device', media_type => 'hd', device => $device, prefix => $device . 'p', bus => 'ataraid' };
	log::l("ATARAID: $device");
    }
    values %l;
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

sub getSoundDevices() {
    modules::probe_category('multimedia/sound');
}

sub isTVcardConfigurable { member($_[0]{driver}, qw(bttv cx88 saa7134)) }

sub getTVcards() { modules::probe_category('multimedia/tv') }

sub getInputDevices() {
    my (@devices, $device);
    foreach (cat_('/proc/bus/input/devices')) {
        if (/^I:/) {
            push @devices, $device if $device;
            $device = {};
            $device->{vendor} = $1 if /Vendor=([0-9a-f]+)/;
            $device->{id} = $1 if /Product=([0-9a-f]+)/;
        }
        $device->{description} = "|$1" if /N: Name="(.*)"/;
        $device->{driver} = $1 if /H: Handlers=(\w+)/;
        if (/P: Phys=(.*)/) {
            $device->{location} = $1;
            $device->{bus} = 'isa' if $device->{location} =~ /^isa/;
            $device->{bus} = 'usb' if $device->{location} =~ /^usb/i;
        }
    }
    push @devices, $device if $device;
    @devices;
}

sub getSynapticsTouchpads() {
    grep { $_->{description} =~ m,^\|(?:SynPS/2 Synaptics TouchPad$|AlpsPS/2 ALPS), } getInputDevices();
}

sub getSerialModem {
    my ($modules_conf, $o_mouse) = @_;
    my $mouse = $o_mouse || {};
    $mouse->{device} = readlink "/dev/mouse";
    my $serdev = arch() =~ /ppc/ ? "macserial" : "serial";
    eval { modules::load($serdev) };

    my @modems;

    probeSerialDevices();
    foreach my $port (map { "ttyS$_" } (0..7)) {
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
        foreach (@devs) { $_->{type} =~ /serial/ and $modem->{device} = $_->{device} }
    }
    @modems;
}

sub getModem {
    my ($modules_conf) = @_;
    getSerialModem($modules_conf, {}), matching_driver__regexp('www\.linmodems\.org'),
      matching_driver(list_modules::category2modules('network/modem'), list_modules::category2modules('network/slmodem'));
}

sub getSpeedtouch() {
    grep { $_->{description} eq 'Alcatel|USB ADSL Modem (Speed Touch)' } probeall();
}

sub getBewan() {
    matching_desc__regexp('Bewan Systems\|.*ADSL|BEWAN ADSL USB|\[Unicorn\]');
}
sub getSagem() {
    matching_driver('eagle-usb');
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

sub is_lan_interface {
    # we want LAN like interfaces here (eg: ath|br|eth|fddi|plip|ra|tr|usb|wifi|wlan).
    # there's also bnep%d for bluetooth, bcp%d...
    # we do this by blacklisting the following interfaces:
    # - ippp|isdn|plip|ppp (initscripts suggest that isdn%d can be created but kernel sources claim not)
    #   ippp%d are created by drivers/isdn/i4l/isdn_ppp.c
    #   plip%d are created by drivers/net/plip.c
    #   ppp%d are created by drivers/net/ppp_generic.c
    #
    # we need both detection schemes since:
    # - get_netdevices() use the SIOCGIFCONF ioctl that does not list interfaces that are down
    # - /proc/net/dev does not list VLAN and IP aliased interfaces

    is_useful_interface($_[0]) &&
    $_[0] !~ /^(?:lo|ippp|isdn|plip|ppp|sit0|wifi)/;
}

sub is_useful_interface {
    # - sit0 which is *always* created by net/ipv6/sit.c, thus is always created since net.agent loads ipv6 module
    # - wifi%d are created by 3rdparty/hostap/hostap_hw.c (pseudo statistics devices, #14523)
    $_[0] !~ /^(?:lo|sit0|wifi)/;
}

sub is_wireless_interface {
    my ($interface) = @_;
    #- some wireless drivers don't always support the SIOCGIWNAME ioctl
    #-   ralink devices need to be up to support it
    #-   wlan-ng (prism2_*) need some special tweaks to support it
    #- use sysfs as fallback to detect wireless interfaces,
    #- i.e interfaces for which get_wireless_stats() is available
    c::isNetDeviceWirelessAware($interface) || -e "/sys/class/net/$interface/wireless";
}
sub get_wireless_interface() { find { is_wireless_interface($_) } getNet() }

sub is_bridge_interface {
    my ($interface) = @_;
    -f "/sys/class/net/$interface/bridge/bridge_id";
}

sub get_sysfs_device_id_map {
    my ($dev_path) = @_;
    my $is_usb = -f "$dev_path/bInterfaceNumber";
    $is_usb ?
      { id => '../idProduct', vendor => '../idVendor' } :
      { id => "device", subid => "subsystem_device", vendor => "vendor", subvendor => "subsystem_vendor" };
}

sub get_all_net_devices() {
    uniq(
        (map { if_(/^\s*([A-Za-z0-9:\.]*):/, $1) } cat_("/proc/net/dev")),
        c::get_netdevices(),
    );
}

sub getNet() {
    grep { is_lan_interface($_) } get_all_net_devices();
 }

sub get_net_interfaces() {
    grep { is_useful_interface($_) } get_all_net_devices();
}

#sub getISDN() {
#    mapgrep(sub {member (($_[0] =~ /\s*(\w*):/), @netdevices), $1 }, split(/\n/, cat_("/proc/net/dev")));
#}

sub getUPS() {
    my @usb_devices = map { ($_->{name} = $_->{description}) =~ s/.*\|//; $_ } grep { $_->{description} !~ /GamePad|IR Combo Device|Joystick|SideWinder/ } usb_probe();

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
      (grep { $_->{driver} = 'hidups' if $_->{driver} eq 'usbhid'; $_->{description} =~ /American Power Conversion\|Back-UPS/ } @usb_devices),
      (map {
          $_->{port} = "auto";
          $_->{media_type} = 'UPS';
          $_->{driver} = 'newhidups';
          $_;
      } grep { $_->{driver} =~ /ups$/ && $_->{description} !~ /American Power Conversion\|Back-UPS|Keyboard|Logitech|WingMan/ } @usb_devices);
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

my (@pci, @usb);
sub pci_probe__real() {
    add_addons($pcitable_addons, map {
	my %l;
	@l{qw(vendor id subvendor subid pci_bus pci_device pci_function media_type driver description)} = split "\t";
	$l{$_} = hex $l{$_} foreach qw(vendor id subvendor subid);
	$l{bus} = 'PCI';
	\%l;
    } c::pci_probe());
}
sub pci_probe() {
    if ($::isStandalone && @pci) {
	    @pci;
    } else {
	    @pci = pci_probe__real();
    }
}

sub usb_probe__real() {
    -e "/proc/bus/usb/devices" or return;

    add_addons($usbtable_addons, map {
	my %l;
	@l{qw(vendor id media_type driver description pci_bus pci_device)} = split "\t";
	$l{media_type} = join('|', grep { $_ ne '(null)' } split('\|', $l{media_type}));
	$l{$_} = hex $l{$_} foreach qw(vendor id);
	$l{bus} = 'USB';
	\%l;
    } c::usb_probe());
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
    require list_modules;
    my @modules = list_modules::category2modules('bus/pcmcia');
    grep { member($_->{driver}, @modules) } probeall();
}

sub real_pcmcia_probe() {
    return if $::testing;

    c::pcmcia_probe() || first(map { $_->{driver} } pcmcia_controller_probe());
}

sub pcmcia_probe() {
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

my $dmi_probe;
sub dmi_probe() {
    $dmi_probe ||= [ map {
	/(.*?)\t(.*)/ && { bus => 'DMI', driver => $1, description => $2 };
    } c::dmi_probe() ];
    @$dmi_probe;
}

# pcmcia_probe provides field "device", used in network.pm
# => probeall with $probe_type is unsafe
sub probeall() {
    return if $::noauto;

    require sbus_probing::main;
    pci_probe(), usb_probe(), firewire_probe(), pcmcia_probe(), sbus_probing::main::probe(), dmi_probe();
}
sub matching_desc__regexp {
    my ($regexp) = @_;
    grep { $_->{description} =~ /$regexp/i } probeall();
}
sub matching_driver__regexp {
    my ($regexp) = @_;
    grep { $_->{driver} =~ /$regexp/i } probeall();
}

sub matching_driver {
    my (@list) = @_;
    grep { member($_->{driver}, @list) } probeall();
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

sub stringlist() { 
    map {
	sprintf("%-16s: %s%s%s", 
		$_->{driver} || 'unknown', 
		$_->{description} eq '(null)' ? sprintf("Vendor=0x%04x Device=0x%04x", $_->{vendor}, $_->{id}) : $_->{description},
		$_->{media_type} ? sprintf(" [%s]", $_->{media_type}) : '',
		$_->{subid} && $_->{subid} != 0xffff ? sprintf(" SubVendor=0x%04x SubDevice=0x%04x", $_->{subvendor}, $_->{subid}) : '',
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
    my $mac_model = cat_("/proc/device-tree/model") || die "Can not open /proc/device-tree/model";
    log::l("Mac model: $mac_model");
    $mac_model;	
}

sub get_mac_generation() {
    cat_('/proc/cpuinfo') =~ /^pmac-generation\s*:\s*(.*)/m ? $1 : "Unknown Generation";	
}

sub hasSMP() { 
    return if $::testing;
    c::detectSMP() || any { /\bProcessor #(\d+)\s+(\S*)/ && $1 > 0 && $2 ne 'invalid' } syslog();
}
sub hasPCMCIA() { $::o->{pcmcia} } #- because /proc/pcmcia seems not to be present on 2.4 at least (or use /var/run/stab)

my (@dmis, $dmidecode_already_runned);

# we return a list b/c several DMIs have the same name:
sub dmidecode() {
    return @dmis if $dmidecode_already_runned;

    foreach (run_program::get_stdout('dmidecode')) {
	if (/^\t\t(.*)/) {
	    $dmis[-1]{string} .= "$1\n";
	    $dmis[-1]{$1} = $2 if /^\t\t(.*): (.*)$/;
	} elsif (my ($s) = /^\t(.*)/) {
	    next if $s =~ /^DMI type /;
	    $s =~ s/ Information$//;
	    push @dmis, { name => $s };
	}
    }
    $dmidecode_already_runned = 1;
    @dmis;
}
sub dmidecode_category {
    my ($cat) = @_;
    my @l = find { $_->{name} eq $cat } dmidecode();
    wantarray() ? @l : $l[0] || {};
}

sub computer_info() {
     my $Chassis = dmidecode_category('Chassis')->{Type} =~ /(\S+)/ && $1;

     my $date = dmidecode_category('BIOS')->{'Release Date'} || '';
     my $BIOS_Year = $date =~ m!(\d{4})! && $1 ||
	             $date =~ m!\d\d/\d\d/(\d\d)! && "20$1";
	
     +{ 
	 isLaptop => member($Chassis, 'Portable', 'Laptop', 'Notebook', 'Hand Held', 'Sub Notebook', 'Docking Station'),
	 if_($BIOS_Year, BIOS_Year => $BIOS_Year),
     };
}

#- try to detect a laptop, we assume pcmcia service is an indication of a laptop or
#- the following regexp to match graphics card apparently only used for such systems.
sub isLaptop() {
    arch() =~ /ppc/ ? 
      get_mac_model() =~ /Book/ :
      computer_info()->{isLaptop}
	|| (matching_desc__regexp('C&T.*655[45]\d') || matching_desc__regexp('C&T.*68554') ||
	    matching_desc__regexp('Neomagic.*Magic(Media|Graph)') ||
	    matching_desc__regexp('ViRGE.MX') || matching_desc__regexp('S3.*Savage.*[IM]X') ||
	    matching_desc__regexp('ATI.*(Mobility|LT)'))
	|| cat_('/proc/cpuinfo') =~ /\bmobile\b/i;
}

sub BIGMEM() {
    arch() !~ /x86_64|ia64/ && $> == 0 && c::dmiDetectMemory() > 4 * 1024;
}

sub is_i586() {
    my $cpuinfo = cat_('/proc/cpuinfo');
    $cpuinfo =~ /^cpu family\s*:\s*(\d+)/m && $1 < 6 ||
      !has_cpu_flag('cmov');
}

sub is_xbox() {
    any { $_->{vendor} == 0x10de && $_->{id} == 0x02a5 } detect_devices::pci_probe();
}

sub has_cpu_flag {
    my ($flag) = @_;
    cat_('/proc/cpuinfo') =~ /^flags.*\b$flag\b/m;
}

sub matching_type {
    my ($type) = @_;
    if ($type =~ /laptop/i) {
        return isLaptop();
    } elsif ($type =~ /wireless/i) {
        return to_bool(get_wireless_interface());
    }
}

sub usbMice()      { grep { $_->{media_type} =~ /\|Mouse/ && $_->{driver} !~ /wacom/ ||
			  $_->{driver} =~ /Mouse:USB/ } usb_probe() }
sub usbWacom()     { grep { $_->{driver} =~ /wacom/ } usb_probe() }
sub usbKeyboards() { grep { $_->{media_type} =~ /\|Keyboard/ } usb_probe() }
sub usbStorage()   { grep { $_->{media_type} =~ /Mass Storage\|/ } usb_probe() }
sub has_mesh()     { find { /mesh/ } all_files_rec("/proc/device-tree") }
sub has_53c94()    { find { /53c94/ } all_files_rec("/proc/device-tree") }

sub usbKeyboard2country_code {
    my ($usb_kbd) = @_;
    my ($F, $tmp);
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
