package modules;

use diagnostics;
use strict;

use common qw(:common :file);
use pci_probing::main;
use detect_devices;
use run_program;
use log;


my %conf;
my $scsi = 0;
my %deps = ();


my @neOptions = (
  [ "io=", "Base IO port:", "0x300:0x280:0x320:0x340:0x360" ],
  [ "irq=", "IRQ level:", "" ],
);

my @de4x5Options = (
  [ "io=", "Base IO port:", "0x0b" ],
);

my @cdu31aOptions = (
  [ "cdu31a_port=", "Base IO port:", "" ],
  [ "cdu31a_irq=", "IRQ level:", "" ],
);

#
#my %knownAliases = (
#    eth => { type => 'net', minor => 'ethernet' },
#    scsi_hostadapter => { type => 'scsi' },
#);
#
#my @neOptions = (
#  [ "io=", __("Base IO port:"), "0x300", "0x280", "0x320", "0x340", "0x360" ],
#  [ "irq=", __("IRQ level:"), "" ],
#);
#
#my @de4x5Options = (
#  [ "io=", __("Base IO port:"), "0x0b" ],
#);
#
#my @cdu31aOptions = (
#  [ "cdu31a_port=", __("Base IO port:"), "" ],
#  [ "cdu31a_irq=", __("IRQ level:"), "" ],
#);
#
#my @cm206Options = (
#  [ "cm206=", __("IO base, IRQ:"), "" ],
#);
#
#my @mcdOptions = (
#  [ "mcd=", __("Base IO port:"), "" ],
#);
#
#my @optcdOptions = (
#  [ "optcd=", __("Base IO port:"), "" ],
#);
#
#my @fdomainOptions = (
#  [ "setup_called=", __("Use other options"), "1" ],
#  [ "port_base=", __("Base IO port:"), "0xd800" ],
#  [ "interrupt_level=", __("Interrupt level (IRQ):"), "10" ],
#);
#
#my @sbpcdOptions = (
#  [ "sbpcd=", __("IO base, IRQ, label:"), "" ],
#);
#
#my @parportPcOptions = (
#  [ "io=", __("Base IO port:"), "0x378" ],
#  [ "irq=", __("IRQ level:"), "7" ],
#);
#
#my @modules_fields = qw(shouldAutoprobe options flags defaultOptions);
#my %modules = (
#  "8390" => [ 1 ],
#  "cdu31a" => [ 0, \@cdu31aOptions ],
#  "cm206" => [ 0, \@cm206Options ],
#  "de4x5" => [ 1, \@de4x5Options, 'AUTOPROBE', "io=0" ],
#  "ds" => [ 1, undef, 0, '' ],
#  "fdomain" => [ 1, \@fdomainOptions, 0, '' ],
#  "i82365" => [ 1, undef, 0, '' ],
#  "isofs" => [ 1, undef, 0, '' ],
#  "loop" => [ 1, undef, 0, '' ],
#  "lp" => [ 1, undef, 0, '' ],
#  "parport" => [ 1, undef, 0, '' ],
#  "parport_pc" => [ 1, \@parportPcOptions, 0, "irq=7" ],
#  "mcd" => [ 0, \@mcdOptions, 0, '' ],
#  "ne" => [ 0, \@neOptions, 'FAKEAUTOPROBE', "io=0x300" ],
#  "nfs" => [ 1, undef, 0, '' ],
#  "optcd" => [ 0, \@optcdOptions, 0, '' ],
#  "pcmcia_core" => [ 1, undef, 0, '' ],
#  "sbpcd" => [ 1, \@sbpcdOptions, 0, '' ],
#  "smbfs" => [ 1, undef, 0, '' ],
#  "tcic" => [ 1, undef, 0, '' ],
#  "vfat" => [ 1, undef, 0, '' ],
#);
my @drivers_by_category = (
[ \&detect_devices::hasEthernet, 'net', 'ethernet', {
  "3c509" => "3com 3c509",
  "3c501" => "3com 3c501",
  "3c503" => "3com 3c503",
  "3c505" => "3com 3c505",
  "3c507" => "3com 3c507",
  "3c515" => "3com 3c515",
  "3c59x" => "3com 3c59x (Vortex)",
  "3c59x" => "3com 3c90x (Boomerang)",
  "at1700" => "Allied Telesis AT1700",
  "ac3200" => "Ansel Communication AC3200",
  "pcnet32" => "AMD PC/Net 32",
  "apricot" => "Apricot 82596",
  "atp" => "ATP",
  "e2100" => "Cabletron E2100",
  "tlan" => "Compaq Netelligent",
  "de4x5" => "Digital 425,434,435,450,500",
  "depca" => "Digital DEPCA and EtherWORKS",
  "ewrk3" => "Digital EtherWORKS 3",
  "tulip" => "Digital 21040 (Tulip)",
  "de600" => "D-Link DE-600 pocket adapter",
  "de620" => "D-Link DE-620 pocket adapter",
  "epic100" => "EPIC 100",
  "hp100" => "HP10/100VG any LAN ",
  "hp" => "HP LAN/AnyLan",
  "hp-plus" => "HP PCLAN/plus",
  "eth16i" => "ICL EtherTeam 16i",
  "eexpress" => "Intel EtherExpress",
  "eepro" => "Intel EtherExpress Pro",
  "eepro100" => "Intel EtherExpress Pro 100",
  "lance" => "Lance",
  "lne390" => "Mylex LNE390",
  "ne" => "NE2000 and compatible",
  "ne2k-pci" => "NE2000 PCI",
  "ne3210" => "NE3210",
  "ni5010" => "NI 5010",
  "ni52" => "NI 5210",
  "ni65" => "NI 6510",
  "rtl8139" => "RealTek RTL8129/8139",
  "es3210" => "Racal-Interlan ES3210",
  "rcpci45" => "RedCreek PCI45 LAN",
  "epic100" => "SMC 83c170 EPIC/100",
  "smc9194" => "SMC 9000 series",
  "smc-ultra" => "SMC Ultra",
  "smc-ultra32" => "SMC Ultra 32",
  "via-rhine" => "VIA Rhine",
  "wd" => "WD8003, WD8013 and compatible",
}],
[ \&detect_devices::hasSCSI, 'scsi', undef, {
  "aha152x" => "Adaptec 152x",
  "aha1542" => "Adaptec 1542",
  "aha1740" => "Adaptec 1740",
  "aic7xxx" => "Adaptec 2740, 2840, 2940",
  "advansys" => "AdvanSys Adapters",
  "in2000" => "Always IN2000",
  "AM53C974" => "AMD SCSI",
  "megaraid" => "AMI MegaRAID",
  "BusLogic" => "BusLogic Adapters",
  "cpqarray" => "Compaq Smart-2/P RAID Controller",
  "dtc" => "DTC 3180/3280",
  "eata_dma" => "EATA DMA Adapters",
  "eata_pio" => "EATA PIO Adapters",
  "seagate" => "Future Domain TMC-885, TMC-950",
  "fdomain" => "Future Domain TMC-16x0",
  "gdth" => "ICP Disk Array Controller",
  "ppa" => "Iomega PPA3 (parallel port Zip)",
  "g_NCR5380" => "NCR 5380",
  "NCR53c406a" => "NCR 53c406a",
  "53c7,8xx" => "NCR 53c7xx",
  "ncr53c8xx" => "NCR 53C8xx PCI",
  "pci2000" => "Perceptive Solutions PCI-2000",
  "pas16" => "Pro Audio Spectrum/Studio 16",
  "qlogicfas" => "Qlogic FAS",
  "qlogicisp" => "Qlogic ISP",
  "seagate" => "Seagate ST01/02",
  "t128" => "Trantor T128/T128F/T228",
  "u14-34f" => "UltraStor 14F/34F",
  "ultrastor" => "UltraStor 14F/24F/34F",
  "wd7000" => "Western Digital wd7000",
}],
[ undef, 'cdrom', 'none', {
  "sbpcd" => "SoundBlaster/Panasonic",
  "aztcd" => "Aztech CD",
  "bpcd" => "Backpack CDROM",
  "gscd" => "Goldstar R420",
  "mcd" => "Mitsumi",
  "mcdx" => "Mitsumi (alternate)",
  "optcd" => "Optics Storage 8000",
  "cm206" => "Phillips CM206/CM260",
  "sjcd" => "Sanyo",
  "cdu31a" => "Sony CDU-31A",
  "sonycd535" => "Sony CDU-5xx",
}]
);

my @drivers_fields = qw(text detect type minor);
my %drivers = (
  "plip" => [ "PLIP (parallel port)", \&detect_devices::hasPlip, 'net', 'plip' ],
  "ibmtr" => [ "Token Ring", \&detect_devices::hasTokenRing, 'net', 'tr' ],
  "DAC960" => [ "Mylex DAC960", undef, 'scsi', undef ],
  "pcmcia_core" => [ "PCMCIA core support", undef, 'pcmcia', undef ],
  "ds" => [ "PCMCIA card support", undef, 'pcmcia', undef ],
  "i82365" => [ "PCMCIA i82365 controller", undef, 'pcmcia', undef ],
  "tcic" => [ "PCMCIA tcic controller", undef, 'pcmcia', undef ],
  "isofs" => [ "iso9660", undef, 'fs', undef ],
  "nfs" => [ "Network File System (nfs)", undef, 'fs', undef ],
  "smbfs" => [ "Windows SMB", undef, 'fs', undef ],
  "loop" => [ "Loopback device", undef, 'other', undef ],
  "lp" => [ "Parallel Printer", undef, 'other', undef ],
);
foreach (@drivers_by_category) {
    my @l = @$_;
    my $l = pop @l;
    foreach (keys %$l) { $drivers{$_} = [ $l->{$_}, @l ]; }
}
while (my ($k, $v) = each %drivers) {
    my %l; @l{@drivers_fields} = @$v;
    $drivers{$k} = \%l;
}


1;


sub text_of_type($) {
    my ($type) = @_;

    map { $_->{text} } grep { $_->{type} eq $type } values %drivers;
}

sub text2driver($) {
    my ($text) = @_;
    while (my ($k, $v) = each %drivers) {
	$v->{text} eq $text and return $k;
    }
    die "$text is not a valid module description";
}


sub load($;$@) {
    my ($name, $type, @options) = @_;

    $conf{'scsi_hostadapter' . ($scsi++ || '')}{alias} = $name 
      if $type eq 'scsi';

    $conf{$name}{options} = join " ", @options if @options;

    if ($::testing) {
	log::l("i try to install $name module");
    } else {
	$conf{$name}{loaded} and return;
	
	$type ||= $drivers{$name}{type};
	
	load($_, 'prereq') foreach @{$deps{$name}};
	load_raw($name, @options);
    }
}

sub unload($) { 
    if ($::testing) {
	log::l("rmmod $_[0]");
    } else {
	run_program::run("rmmod", $_[0]); 
    }
}

sub load_raw($@) {
    my ($name, @options) = @_;

    run_program::run("insmod", $name, @options) or die("insmod $name failed");

    # this is a hack to make plip go
    if ($name eq "parport_pc") {
	foreach (@options) {
	    /^irq=(\d+)/ or next;
	    log::l("writing to /proc/parport/0/irq");
	    local *F;
	    open F, "> /proc/parport/0/irq" or last;
	    print F $1;
	}
    }
    $conf{$name}{loaded} = 1;
}

sub read_already_loaded() {
    foreach (cat_("/proc/modules", "die")) {
	my ($name) = split;
	$conf{$name}{loaded} = 1;
    }
}

sub load_deps($) {
    my ($file) = @_;

    local *F;
    open F, $file or log::l("error opening $file: $!"), return 0;
    foreach (<F>) {
	my ($f, $deps) = split ':';
	push @{$deps{$f}}, split ' ', $deps;
    }
}

sub read_conf($;$) {
    my ($file, $scsi) = @_;
    my %c;

    foreach (cat_($file)) {
	do {
	    $c{$2}{$1} = $3;
	    $$scsi = max($$scsi, $1 || 0) if /^\s*alias\s+scsi_hostadapter (\d*)/x && $scsi;
	} if /^\s*(\S+)\s+(\S+)\s+(.*?)\s*$/;
    }
    # cheating here: not handling aliases of aliases
    while (my ($k, $v) = each %c) {
	$$scsi ||= $v->{scsi_hostadapter} if $scsi;
	if (my $a = $v->{alias}) {
	    local $c{$a}{alias};
	    add2hash($c{$a}, $v);
	}
    }
    %c;
}

sub write_conf {
    my ($file) = @_;
    my %written = read_conf($file);

    my %net = detect_devices::net2module();
    while (my ($k, $v) = each %net) {
	$conf{$k}{alias} ||= $v;
    }

    local *F;
    open F, ">> $file" or die("cannot write module config file $file: $!\n");

    while (my ($mod, $h) = each %conf) {
	while (my ($type, $v2) = each %$h) {
	    print F "$type $mod $v2\n" if $v2 && $type ne "loaded" && !$written{$mod}{$type};
	}
    }
}

sub get_stage1_conf { 
    %conf = read_conf($_[0], \$scsi);
    $conf{parport_lowlevel}{alias} ||= "parport_pc";
    $conf{pcmcia_core}{"pre-install"} ||= "/etc/rc.d/init.d/pcmcia start";    
    $conf{plip}{"pre-install"} ||= "modprobe parport_pc ; echo 7 > /proc/parport/0/irq";
}

sub load_thiskind($;&) {
    my ($type, $f) = @_;

    my @devs = pci_probing::main::probe($type);
    log::l("pci probe found " . scalar @devs . " $type devices");

    my %devs; foreach (@devs) {
	my ($text, $mod) = @$_;
	$devs{$mod}++ and log::l("multiple $mod devices found"), next;
	$drivers{$mod} or log::l("module $mod not in install table"), next;
	log::l("found driver for $mod");
	&$f($text, $mod) if $f; 
	load($mod, $type);
    }
    @devs;
}

# This assumes only one of each driver type is loaded
sub removeDeviceDriver {
#    my ($type) = @_;
#
#    my @m = grep { $loaded{$_}{type} eq $type } keys %loaded;
#    @m or return 0;
#    @m > 1 and log::l("removeDeviceDriver assume only one of each driver type is loaded, which is not the case (" . join(' ', @m) . ")");
#    removeModule($m[0]);
#    1;
}


