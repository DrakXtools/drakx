package modules; # $Id$

use strict;
use vars qw(%drivers);

use common qw(:common :file :system :functional);
use detect_devices;
use run_program;
use install_any;
use log;


my %conf;
my $scsi = 0;
my %deps = ();

my @drivers_by_category = (
[ 'net', {
if_(arch() =~ /ppc/,
  "mace" => "Apple PowerMac Ethernet",
  "bmac" => "Apple G3 Ethernet",
  "gmac" => "Apple G4/iBook Ethernet",
),
if_(arch() =~ /^sparc/,
  "myri_sbus" => "MyriCOM Gigabit Ethernet",
  "sunbmac" => "Sun BigMac Ethernet",
  "sunqe" => "Sun Quad Ethernet",
),
if_(arch() !~ /alpha/ && arch() !~ /sparc/,
  "3c501" => "3com 3c501",
  "3c503" => "3com 3c503",
  "3c505" => "3com 3c505",
  "3c507" => "3com 3c507",
  "3c509" => "3com 3c509",
  "3c515" => "3com 3c515",
  "3c90x" => "3Com 3c90x (Cyclone/Hurricane/Tornado)",
  "82596" => "Apricot 82596",
  "abyss" => "Smart 16/4 PCI Ringnode (token ring)",
# unused from Jeff  "ac3200" => "Ansel Communication AC3200",
  "acenic" => "AceNIC Gigabit Ethernet",
  "aironet4500_card" => "aironet4500_card",
# unused from Jeff "at1700" => "Allied Telesis AT1700",
# unused from Jeff  "atp" => "ATP", 
  "com20020-pci" => "com20020-pci",
  "cs89x0" => "CS89x0",
  "de600" => "D-Link DE-600 pocket adapter",
  "de620" => "D-Link DE-620 pocket adapter",
  "defxx" => "DEC DEFPA FDDI", # most unused
  "depca" => "Digital DEPCA and EtherWORKS",
  "dgrs" => "Digi International RightSwitch",
  "dmfe" => "dmfe",
  "e100" => "Intel Ethernet Pro 100", #- newer Intel version of eepro100
  "e1000" => "Intel Gigabit Ethernet",
  "e2100" => "Cabletron E2100",
  "eepro" => "Intel EtherExpress Pro",
  "eepro100" => "Intel EtherExpress Pro 100", #- should run on sparc but no memory on floppy
  "eexpress" => "Intel EtherExpress",
  "epic100" => "SMC 83c170 EPIC/100",
  "eth16i" => "ICL EtherTeam 16i",
  "ewrk3" => "Digital EtherWORKS 3",
  "hamachi" => "hamachi",
  "hp" => "HP LAN/AnyLan",
  "hp-plus" => "HP PCLAN/plus",
  "hp100" => "HP10/100VG any LAN ",
  "ibmtr" => "Token Ring Tropic",
  "kaweth" => "kaweth",
# requires scsi_mod???  "iph5526" => "iph5526",
  "lance" => "Lance",
  "natsemi" => "National Semiconductor 10/100",
  "ne" => "NE2000 and compatible",
  "ne2k-pci" => "NE2000 PCI",
# unused from Jeff  "ni5010" => "NI 5010",
# unused from Jeff  "ni52" => "NI 5210",
# unused from Jeff  "ni65" => "NI 6510",
  "old_tulip" => "Digital 21040/21041/21140 (old Tulip driver)",
  "olympic" => "olympic",
  "pcnet32" => "AMD PC/Net 32",
  "pegasus" => "pegasus", 
  "plip" => "PLIP (parallel port)",
  "rcpci" => "Red Creek Hardware VPN",
  "rrunner" => "Roadrunner serial HIPPI", # mostly unused
  "sb1000" => "sb1000",
  "sis900" => "sis900",
  "sk98lin" => "Syskonnect (Schneider & Koch)|Gigabit Ethernet",
  "sktr" => "Syskonnect Token ring adaptor",
  "smc-ultra" => "SMC Ultra",
  "smc9194" => "SMC 9000 series",
  "starfire" => "Adaptec StarFire",
  "tlan" => "Compaq Netelligent",
  "tmspci" => "tmspci (token ring)",
  "tulip" => "Digital 21040/21041/21140 (Tulip)",
  "via-rhine" => "VIA Rhine",
#  "wavelan" => "AT&T WaveLAN & DEC RoamAbout DS", # TODO is a "AT&T GIS WaveLAN ISA" ?
  "wd" => "WD8003, WD8013 and compatible",
  "winbond-840" => "Compex RL100-ATX",
  "yellowfin" => "Symbios Yellowfin G-NIC",
#******(missing-2.4)    "smc-ultra32" => "SMC Ultra 32",
#******(missing-2.4)  "rl100a" => "rl100a",
#******(missing-2.4)  "z85230" => "Z85x30",
),
  "3c59x" => "3com 3c59x (Vortex)",
  "8139too" => "Realtek RTL-8139",
  "de4x5" => "Digital 425,434,435,450,500",
  "rtl8139" => "RealTek RTL8129/8139",
  "sundance" => "sundance",
  "sunhme" => "Sun Happy Meal Ethernet",
}],
[ 'net_raw', {
  "8390" => "8390",
  "af_packet" => "packet socket",
  "nfs" => "Network File System (nfs)",
  "lockd" => "lockd",
  "parport" => "parport",
  "parport_pc" => "parport_pc",
  "sunrpc" => "sunrpc",
  "pci-scan" => "pci-scan",
  "usbcore" => "usbcore",
}],
[ 'isdn', {
   "hisax" => "hisax",
   "hysdn" => "hysdn",
   "b1pci" => "b1pci",
   "t1pci" => "t1pci",
   "c4" => "c4",
}],
[ 'tv', {
 "bttv" => "Brooktree Corporation|Bt8xx Video Capture",
 "cpia_usb" => '',
 "ibmcam" => '',
 "mod_quickcam" => '',
 "ov511" => '',
 "ultracam" => '',
 "usbvideo" => '',
}],
[ 'scanner', {
 "scanner" => '',
 "microtek" => '',
}],
[ 'photo', {
 "dc2xx" => '',
 "mdc800" => '',
}],
[ 'joystick', {
   "ns558" => "Creative Labs SB Live! joystick",
}],
[ 'radio', {
   "radio-maxiradio" => "radio-maxiradio",
}],
[ 'scsi', {
if_(arch() =~ /ppc/,
  "mesh" => "Apple Internal SCSI",
  "mac53c94" => "Apple External SCSI",
),
if_(arch() =~ /^sparc/,
  "qlogicpti" => "Performance Technologies ISP",
),
if_(arch() !~ /alpha/ && arch() !~ /sparc/,
  "3w-xxxx" => "3ware ATA-RAID",
  "53c7,8xx" => "NCR 53c7xx",
  "AM53C974" => "AMD SCSI",
  "BusLogic" => "BusLogic Adapters",
  "NCR53c406a" => "NCR 53c406a",
  "a100u2w" => "a100u2w",
  "advansys" => "AdvanSys Adapters",
  "aha152x" => "Adaptec 152x",
  "aha1542" => "Adaptec 1542",
  "aha1740" => "Adaptec 1740",
  "atp870u" => "atp870u (Acard/Artop)",
  "dc395x_trm" => "dc395x_trm",
  "dtc" => "DTC 3180/3280",
  "fdomain" => "Future Domain TMC-16x0",
  "g_NCR5380" => "NCR 5380",
  "in2000" => "Always IN2000",
  "initio" => "Initio",
  "pci2220i" => "Perceptive Solutions 2240I",
  "psi240i" => "psi240i",
  "qla1280" => "Q Logic QLA1280",
  "qla2x00" => "Q Logic QLA2200",
  "qlogicfas" => "Qlogic FAS",
  "qlogicfc" => "qlogicfc",
  "seagate" => "Seagate ST01/02",
  "sim710" => "sim710",
  "sym53c416" => "sym53c416",
  "t128" => "Trantor T128/T128F/T228",
  "tmscsim" => "tmscsim",
  "u14-34f" => "UltraStor 14F/34F",
  "ultrastor" => "UltraStor 14F/24F/34F",
  "wd7000" => "Western Digital wd7000",
),
  "aic7xxx" => "Adaptec 2740, 2840, 2940",
  "ncr53c8xx" => "NCR 53C8xx PCI",
  "pci2000" => "Perceptive Solutions PCI-2000", # TODO
  "qlogicisp" => "Qlogic ISP",
  "sym53c8xx" => "Symbios 53c8xx",
}],
[ 'scsi_raw', {
  "scsi_mod" => "scsi_mod",
  "sd_mod" => "sd_mod",
#-  "ide-mod" => "ide-mod",
#-  "ide-probe" => "ide-probe",
#-  "ide-probe-mod" => "ide-probe-mod",
}],
[ 'disk', {
if_(arch() =~ /^sparc/,
  "pluto" => "Sun SparcSTORAGE Array SCSI", #- name it "fc4:soc:pluto" ?
),
if_(arch() !~ /alpha/ && arch() !~ /sparc/,
  "DAC960" => "Mylex DAC960",
  "dpt_i2o" => "Distributed Tech SmartCache/Raid I-V Controller",
  "megaraid" => "AMI MegaRAID",
  "aacraid" => "AACxxx Raid Controller",
  "cciss" => "Compaq Smart Array 5300 Controller",
  "cpqarray" => "Compaq Smart-2/P RAID Controller",
  "gdth" => "ICP Disk Array Controller",
  "i2o_block" => "Intel Integrated RAID",
  "ips" => "IBM ServeRAID controller",
  "eata" => "EATA SCSI PM2x24/PM3224",
  "eata_pio" => "EATA PIO Adapters",
  "eata_dma" => "EATA DMA Adapters",
  "ppa" => "Iomega PPA3 (parallel port Zip)",
  "imm" => "Iomega Zip (new driver)",
),
}],
[ 'disk_raw', {
#-  "ide-disk" => "IDE disk",
}],
[ 'cdrom', {
if_(arch() !~ /alpha/ && arch() !~ /sparc/,
#******(missing-2.4)  "sbpcd" => "SoundBlaster/Panasonic",
#******(missing-2.4)  "aztcd" => "Aztech CD",
#******(missing-2.4)  "gscd" => "Goldstar R420",
#******(missing-2.4)  "isp16" => "ISP16/MAD16/Mozart",
#******(missing-2.4)  "mcd" => "Mitsumi", #- removed for space
#******(missing-2.4)  "mcdx" => "Mitsumi (alternate)",
#******(missing-2.4)  "optcd" => "Optics Storage 8000",
#******(missing-2.4)  "cm206" => "Phillips CM206/CM260",
#******(missing-2.4)  "sjcd" => "Sanyo",
#******(missing-2.4)  "cdu31a" => "Sony CDU-31A",
#******(missing-2.4) "sonycd535" => "Sony CDU-5xx",
),
}],
[ 'cdrom_raw', {
  "isofs" => "iso9660",
  "ide-cd" => "ide-cd",
  "sr_mod" => "SCSI CDROM support",
  "cdrom" => "cdrom",
}],
[ 'sound', {
if_(arch() =~ /ppc/,
  "dmasound" => "Amiga or PowerMac DMA sound",
),
if_(arch() !~ /^sparc/,
  "cmpci" => "C-Media Electronics CMI8338A CMI8338B CMI8738",
  "cs46xx" => "CrystalClear SoundFusion (cs46xx)",
  "cs4281" => "Crystal CS4281",
  "es1370" => "Ensoniq ES1370 [AudioPCI]",
  "es1371" => "Ensoniq ES1371 [AudioPCI-97]",
  "esssolo1" => "ESS Technology ES1969 Solo-1 Audiodrive",
  "i810_audio" => "i810 integrated sound card",
  "maestro" => "Maestro",
  "maestro3" => "ESS Maestro-3",
  "nm256" => "Neomagic MagicMedia 256AV",
  "pas16" => "Pro Audio Spectrum/Studio 16",
  "trident" => "M5451 PCI South Bridge Audio",
  "via82cxxx" => "VIA VT82C686_5",
  "via82cxxx_audio" => "VT82C686 (Apollo Super AC97)",
  "sonicvibes" => "S3 SonicVibes",
  "snd-card-ice1712" => "IC Ensemble Inc|ICE1712 [Envy24]",
  "emu10k1" => "Creative Labs|SB Live! (audio)",
  "ymfpci" => "Yamaha YMF-740, DS-1",
#  "au8820" => "Aureal Semiconductor|Vortex 1",
#  "au8830" => "Aureal Semiconductor|Vortex 2",
  "snd-card-cmipci" => "CMI",
  "snd-card-cs461x" => "Cirrus Logic|CS 4610/11 [CrystalClear SoundFusion Audio Accelerator]",
  "snd-card-ens1371" => "Ensoniq/Creative Labs ES1371",
  "snd-card-es1938" => "ESS Technology|ES1969 Solo-1 Audiodrive",
  "snd-card-fm801" => "Fortemedia, Inc|Xwave QS3000A [FM801]<>Fortemedia, Inc|FM801 PCI Audio",
  "snd-card-intel8x0" => "Intel Corporation|82440MX AC'97 Audio Controller<>Intel Corporation",
  "snd-card-rme96" => "Xilinx, Inc.|RME Digi96<>Xilinx, Inc.",
  "snd-card-trident" => "Silicon Integrated Systems [SiS]|7018 PCI Audio",
  "snd-card-via686a" => "VIA Technologies|VT82C686 [Apollo Super AC97/Audio]",
  "snd-card-ymfpci" => "Yamaha Corporation|YMF-740",
),
}],
[ 'pcmcia', {
if_(arch() !~ /^sparc/,
  "ide_cs" => "ide_cs",
  "fmvj18x_cs" => "fmvj18x_cs",
  "fdomain_cs" => "fdomain_cs",
  "netwave_cs" => "netwave_cs",
  "serial_cs" => "serial_cs",
  "wavelan_cs" => "wavelan_cs",
  "pcnet_cs" => "pcnet_cs",
  "aha152x_cs" => "aha152x_cs",
  "xirc2ps_cs" => "xirc2ps_cs",
  "3c574_cs" => "3c574_cs",
  "qlogic_cs" => "qlogic_cs",
  "nmclan_cs" => "nmclan_cs",
  "ibmtr_cs" => "ibmtr_cs",
#  "dummy_cs" => "dummy_cs",
#  "memory_cs" => "memory_cs",
  "ftl_cs" => "ftl_cs",
  "smc91c92_cs" => "smc91c92_cs",
  "3c589_cs" => "3c589_cs",
#******(missing-2.4)   "parport_cs" => "parport_cs", 
  "3c575_cb" => "3c575_cb",
  "apa1480_cb" => "apa1480_cb",
  "cb_enabler" => "cb_enabler",
  "epic_cb" => "epic_cb",
  "iflash2+_mtd" => "iflash2+_mtd",
  "iflash2_mtd" => "iflash2_mtd",
#  "memory_cb" => "memory_cb",
  "serial_cb" => "serial_cb",
#  "sram_mtd" => "sram_mtd",
  "tulip_cb" => "tulip_cb",

),
}],
[ 'pcmcia_everywhere', {
if_(arch() !~ /^sparc/,
  "pcmcia_core" => "PCMCIA core support",
  "tcic" => "PCMCIA tcic controller",
  "ds" => "PCMCIA card support",
  "i82365" => "PCMCIA i82365 controller",
),
}],
[ 'paride', {
if_(arch() !~ /^sparc/,
  "aten" => "ATEN EH-100",
  "bpck" => "Microsolutions backpack",
  "comm" => "DataStor (older type) commuter adapter",
  "dstr" => "DataStor EP-2000",
  "epat" => "Shuttle EPAT",
  "epia" => "Shuttle EPIA",
  "fit2" => "Fidelity Intl. (older type)",
  "fit3" => "Fidelity Intl. TD-3000",
  "frpw" => "Freecom Power",
  "friq" => "Freecom IQ (ASIC-2)",
  "kbic" => "KingByte KBIC-951A and KBIC-971A",
  "ktti" => "KT Tech. PHd",
  "on20" => "OnSpec 90c20",
  "on26" => "OnSpec 90c26",
  "pd"   => "Parallel port IDE disks",
  "pcd"  => "Parallel port CD-ROM",
  "pf"   => "Parallel port ATAPI disk",
  "paride" => "Main parallel port module",
),
}],
[ 'raid', {
  "linear" => "linear",
  "raid0" => "raid0",
  "raid1" => "raid1",
  "raid5" => "raid5",
}],
[ 'mouse', {
if_(arch() !~ /^sparc/,
  "busmouse" => "busmouse",
  "msbusmouse" => "msbusmouse",
  "serial" => "serial",
  "qpmouse" => "qpmouse",
  "atixlmouse" => "atixlmouse",
),
}],
[ 'usb', {
  "usb-uhci" => "USB (uhci)",
  "usb-ohci" => "USB (ohci)",
  "usb-ohci-hcd" => "USB (ohci-hcd)",
}],
[ 'fs', {
  "smbfs" => "Windows SMB",
  "fat" => "fat",
  "msdos" => "msdos",
  "romfs" => "romfs",
  "vfat" => "vfat",
}],
[ 'other', {
  "agpgart" => "agpgart",
  "buz" => "Zoran Corporation|ZR36057PQC Video cutting chipset",
  "defxx" => "DEC|DEFPA",
  "i810_rng" => "i810_rng",
  "ide-floppy" => "ide-floppy",
  "ide-scsi" => "ide-scsi",
  "ide-tape" => "ide-tape",
  "loop" => "Loopback device",
  "lp" => "Parallel Printer",
  "nbd" => "nbd",
  "rrunner" => "Essential Communications|Roadrunner serial HIPPI",
  "sg" => "sg",
  "st" => "st",
}],
);

my %type_aliases = (
  scsi => 'disk',
);

my @skip_big_modules_on_stage1 = (
# dgrs e1000
qw(
olympic
sk98lin acenic
aironet4500_card com20020-pci hamachi starfire winbond-840

dc395x_trm
BusLogic seagate fdomain g_NCR5380 tmscsim
)
); #******(missing-2.4)  dpt_i2o aztcd gscd isp16 mcd mcdx optcd cm206 sjcd cdu31a

my @skip_modules_on_stage1 = (
  qw(sktr tmspci ibmtr abyss), # alt token ring
  qw(old_tulip rtl8139), # doesn't exist in 2.4
  qw(kaweth pegasus), # usb net
  if_(arch() =~ /alpha|ppc/, qw(sb1000)),
  "apa1480_cb",
  "imm",
  "ppa",
  "parport",
  "parport_pc",
  "plip",
  qw(3w-xxxx pci2220i qla1280 qla2x00 i2o_block),
  qw(gdth eata eata_pio eata_dma ips),
);


my @drivers_fields = qw(text type);
%drivers = ();

foreach (@drivers_by_category) {
    my ($type, $l) = @$_;
    foreach (keys %$l) { $drivers{$_} = [ $l->{$_}, $type ]; }
}
while (my ($k, $v) = each %drivers) {
    my %l; @l{@drivers_fields} = @$v;
    $drivers{$k} = \%l;
}

sub module_of_type__4update_kernel {
    my ($type) = @_;
    $type = join "|", map { $_, $_ . "_raw" } split ' ', $type;
    my %skip; 
    @skip{@skip_modules_on_stage1} = ();
    @skip{@skip_big_modules_on_stage1} = () if $type !~ /big/;
    "big" =~ /^($type)$/ ? @skip_big_modules_on_stage1 : (),
      grep { !exists $skip{$_} } grep { $drivers{$_}{type} =~ /^($type)$/ } keys %drivers;
}
sub module_of_type {
    my ($type) = @_;
    my $alias = $type_aliases{$type} || $type;
    grep { $drivers{$_}{type} =~ /^(($type)|$alias)$/ } keys %drivers;
}
sub module2text { $drivers{$_[0]}{text} or log::l("trying to get text of unknown module $_[0]"), return $_[0] }

sub get_alias {
    my ($alias) = @_;
    $conf{$alias}{alias};
}
sub get_options {
    my ($name) = @_;
    $conf{$name}{options};
}

sub add_alias { 
    my ($alias, $name) = @_;
    $name =~ /ignore/ and return;
    /\Q$alias/ && $conf{$_}{alias} && $conf{$_}{alias} eq $name and return $_ foreach keys %conf;
    $alias .= $scsi++ || '' if $alias eq 'scsi_hostadapter';
    log::l("adding alias $alias to $name");
    $conf{$alias}{alias} ||= $name;
    if ($name =~ /^snd-card-/) {
	$conf{$name}{"post-install"} = "modprobe snd-pcm-oss";
    }
    $alias;
}

sub remove_alias($) {
    my ($name) = @_;
    foreach (keys %conf) {
	$conf{$_}{alias} && $conf{$_}{alias} eq $name or next;
	delete $conf{$_}{alias};
	return 1;
    }
    0;
}

sub when_load {
    my ($name, $type, @options) = @_;
    if ($type =~ /\bscsi\b/ || $type eq $type_aliases{scsi}) {
	add_alias('scsi_hostadapter', $name), eval { load('sd_mod') };
    }
    if ($type eq 'sound') {
	#- mainly for ppc
	add_alias('sound-slot-0', $name);
    }
    if ($name =~ /^snd-card-/) {
	load('snd-pcm-oss', 'prereq');
    }
    $conf{$name}{options} = join " ", @options if @options;
}

sub load {
    my ($name, $type, @options) = @_;

    my @netdev = detect_devices::getNet() if $type eq 'net';

    if ($::testing) {
	log::l("i try to install $name module (@options)");
    } elsif ($::isStandalone || $::live) {
	run_program::run(-x "/sbin/modprobe.static" ? "/sbin/modprobe.static" : "/sbin/modprobe", $name, @options)
	    or die "insmod'ing module $name failed";
    } else {
	$conf{$name}{loaded} and return;

	eval { load($_, 'prereq') } foreach @{$deps{$name}};
	load_raw([ $name, @options ]);
    }
    sleep 2 if $name =~ /usb-storage|mousedev/;

    if ($type eq 'net') {
	add_alias($_, $name) foreach difference2([ detect_devices::getNet() ], \@netdev);
    }
    when_load($name, $type, @options);
}
sub load_multi {
    my $f; $f = sub { map { $f->(@{$deps{$_}}), $_ } @_ };
    my %l; my @l = 
      grep { !$conf{$_}{loaded} }
      grep { my $o = $l{$_}; $l{$_} = 1; !$o }
      $f->(@_);

    if ($::testing) {
	log::l("i would install modules @l");
    } elsif ($::isStandalone || $::live) {
	foreach (@l) { run_program::run(-x "/sbin/modprobe.static" ? "/sbin/modprobe.static" : "/sbin/modprobe", $_) }
    } else {
	load_raw(map { [ $_ ] } @l);
    }
}

sub unload {
    my ($m) = @_; 
    if ($::testing) {
	log::l("rmmod $m");
    } else {
	if (run_program::run("rmmod", $m)) {
	    delete $conf{$m}{loaded};
	}
    }
}

sub load_raw {
    my @l = map { my ($i, @i) = @$_; [ $i, \@i ] } grep { $_->[0] !~ /ignore/ } @_;
    my $cz = "/lib/modules" . (arch() eq 'sparc64' && "64") . ".cz-" . c::kernel_version();
    if (!-e $cz) {
	unlink $_ foreach glob_("/lib/modules*.cz*");
	require install_any;
        install_any::getAndSaveFile("Mandrake/mdkinst$cz", $cz) or die "failed to get modules $cz: $!";
    }
    eval {
	require packdrake;
	my $packer = new packdrake($cz);
	$packer->extract_archive("/tmp", map { "$_->[0].o" } @l);
    };
    #run_program::run("packdrake", "-x", $cz, "/tmp", map { "$_->[0].o" } @l);
    my @failed = grep {
	my $m = "/tmp/$_->[0].o";
	if (-e $m && run_program::run(["/usr/bin/insmod_", "insmod"], '2>', '/dev/tty5', '-f', $m, @{$_->[1]})) {
	    unlink $m;
	    $conf{$_->[0]}{loaded} = 1;
	    '';
	} else {
	    log::l("missing module $_->[0]") unless -e $m;
	    -e $m;
	}
    } @l;

    die "insmod'ing module " . join(", ", map { $_->[0] } @failed) . " failed" if @failed;

    foreach (@l) {
	if ($_->[0] eq "parport_pc") {
	    #- this is a hack to make plip go
	    foreach (@{$_->[1]}) {
		/^irq=(\d+)/ and eval { output "/proc/parport/0/irq", $1 };
	    }
	} elsif ($_->[0] =~ /usb-[uo]hci/) {
	    add_alias('usb-interface', $_->[0]);
	    eval {
		require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
		#- ensure keyboard is working, the kernel must do the job the BIOS was doing
		sleep 2;
		load_multi("usbkbd", "keybdev") if detect_devices::usbKeyboards();
	    }
	}
    }
}

sub read_already_loaded() {
    foreach (cat_("/proc/modules")) {
	my ($name) = split;
	$conf{$name}{loaded} = 1;
	when_load($name, $drivers{$name}{type});
    }
}

sub load_deps($) {
    my ($file) = @_;

    local *F; open F, $file or log::l("error opening $file: $!"), return 0;
    local $_;
    while (<F>) {
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
	    $$scsi = max($$scsi, $1 || 0) if /^\s*alias\s+scsi_hostadapter (\d*)/x && $scsi; #- space added to make perl2fcalls happy!
	} if /^\s*(\S+)\s+(\S+)\s+(.*?)\s*$/;
    }
    #- cheating here: not handling aliases of aliases
    while (my ($k, $v) = each %c) {
	if (my $a = $v->{alias}) {
	    local $c{$a}{alias};
	    add2hash($c{$a}, $v);
	}
    }
    \%c;
}

sub mergein_conf {
    my ($file) = @_;
#-    add2hash(\%conf, read_conf($file, \$scsi));
    my $modconfref = read_conf ($file, \$scsi);
    while (my ($key, $value) = each %$modconfref) {
	$conf{$key}{alias} = $value->{alias} unless exists $conf{$key}{alias};
    }
}

sub write_conf {
    my ($prefix) = @_;

    my $file = "$prefix/etc/modules.conf";
    rename "$prefix/etc/conf.modules", $file; #- make the switch to new name if needed

    #- remove the post-install supermount stuff. We now do it in /etc/modules
    #- Substitute new aliases in modules.conf (if config has changed)
    substInFile { $_ = '' if /^post-install supermount/ } $file;
    substInFile {
	my ($type,$alias,$module) = split /\s+/, $_;
	if ($type ne "loaded"     &&
	    $conf{$alias}{alias}  &&
	    $conf{$alias}{alias} !~ /$module/)  {
	    $_ = "$type $alias $conf{$alias}{alias} \n"; 
	}
    } $file;

    my $written = read_conf($file);

    local *F;
    open F, ">> $file" or die("cannot write module config file $file: $!\n");
    while (my ($mod, $h) = each %conf) {
	while (my ($type, $v2) = each %$h) {
	    print F "$type $mod $v2\n" if $v2 && $type ne "loaded" && !$written->{$mod}{$type};
	}
    }
    my @l = map { "scsi_hostadapter$_" } '', 1..$scsi-1 if $scsi;
    push @l, 'ide-floppy' if detect_devices::ide_zips();
    push @l, 'bttv' if grep { $_->{driver} eq 'bttv' } detect_devices::probeall();
    my $l = join '|', @l;
    log::l("to put in modules ", join(", ", @l));

    substInFile { 
	$_ = '' if /$l/;
	$_ = join '', map { "$_\n" } @l if eof;
    } "$prefix/etc/modules";
}

sub read_stage1_conf {
    mergein_conf($_[0]);

    if (arch() =~ /sparc/) {
    } elsif (arch() =~ /ppc/) {
	$conf{pcmcia_core}{"pre-install"} ||= "CARDMGR_OPTS=-f /etc/rc.d/init.d/pcmcia start";    	
    } else {
	$conf{pcmcia_core}{"pre-install"} ||= "CARDMGR_OPTS=-f /etc/rc.d/init.d/pcmcia start";
    }
}

sub load_thiskind {
    my ($type, $f) = @_;

    #- get_that_type returns the PCMCIA cards. It doesn't know they are already
    #- loaded, so:
    read_already_loaded();

    my @try_modules = (
      if_($type =~ /scsi/,
	  if_(arch() !~ /ppc/, 'imm', 'ppa'),
	  if_(detect_devices::usbZips(), 'usb-storage'),
      ),
      if_(arch() =~ /ppc/, 
	  if_($type =~ /scsi/, 'mesh', 'mac53c94'),
	  if_($type =~ /net/, 'bmac', 'gmac', 'mace'),
	  if_($type =~ /sound/, 'dmasound'),
      ),
    );
    grep {
	$f->($_->{description}, $_->{driver}) if $f;
	eval { load($_->{driver}, $type) };
	$_->{error} = $@;

	!($@ && $_->{try});
    } get_that_type($type), 
      map {; { driver => $_, description => $_, try => 1 } } @try_modules;
}

sub get_that_type {
    my ($type) = @_;

    grep {
	my $l = $drivers{$_->{driver}};
	($_->{type} =~ /$type/ || $l && $l->{type} =~ /$type/) && detect_devices::check($_);
    } detect_devices::probeall('');
}

sub load_ide {
    if (1) { #- add it back to support Ultra66 on ide modules.
	eval { load("ide-cd"); }
    } else {
	eval {
	    load("ide-mod", 'prereq', 'options="' . detect_devices::hasUltra66() . '"');
	    delete $conf{"ide-mod"}{options};
	    load_multi(qw(ide-probe ide-probe-mod ide-disk ide-cd));
	}
    }
}

sub configure_pcmcia {
    my ($pcic) = @_;

    #- try to setup pcmcia if cardmgr is not running.
    -s "/var/run/stab" and return;

    log::l("i try to configure pcmcia services");

    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";

    eval {
	load("pcmcia_core");
	load($pcic);
	load("ds");
    };

    #- run cardmgr in foreground while it is configuring the card.
    run_program::run("cardmgr-" . c::kernel_version(), "-f", "-m" ,"/modules");
    sleep(3);
    
    #- make sure to be aware of loaded module by cardmgr.
    read_already_loaded();
}

sub get_pcmcia_devices {
    my (@devs, $desc);

    foreach (cat_("/var/run/stab")) {
	if (/^Socket\s+\d+:\s+(.*)/) {
	    $desc = $1;
	} else {
	    my (undef, $type, $module, undef, $device) = split;
	    push @devs, { description => $desc, driver => $module, type => $type, device => $device };
	}
    }
    @devs;
}

sub write_pcmcia {
    my ($prefix, $pcmcia) = @_;

    #- should be set after installing the package above otherwise the file will be renamed.
    setVarsInSh("$prefix/etc/sysconfig/pcmcia", {
	PCMCIA    => bool2yesno($pcmcia),
	PCIC      => $pcmcia,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}



1;
