package modules;

use vars qw(%drivers);

use common qw(:common :file :system);
use detect_devices;
use run_program;
use log;


my %conf;
my $scsi = 0;
my %deps = ();

my @drivers_by_category = (
[ 'net', {
arch() =~ /^sparc/ ? (
  "myri_sbus" => "MyriCOM Gigabit Ethernet",
  "sunbmac" => "Sun BigMac Ethernet",
  "sunhme" => "Sun Happy Meal Ethernet",
  "sunqe" => "Sun Quad Ethernet",
) : arch =~ /alpha/ ? () : (
  "3c509" => "3com 3c509",
  "3c501" => "3com 3c501",
  "3c503" => "3com 3c503",
  "3c505" => "3com 3c505",
  "3c507" => "3com 3c507",
  "3c515" => "3com 3c515",
  "3c90x" => "3Com 3c90x (Cyclone/Hurricane/Tornado)",
  "at1700" => "Allied Telesis AT1700",
  "ac3200" => "Ansel Communication AC3200",
  "acenic" => "AceNIC Gigabit Ethernet",
  "pcnet32" => "AMD PC/Net 32",
  "82596" => "Apricot 82596",
#  "atp" => "ATP", # builtin the kernel
  "e2100" => "Cabletron E2100",
  "tlan" => "Compaq Netelligent",
  "cs89x0" => "CS89x0",
  "de600" => "D-Link DE-600 pocket adapter",
  "de620" => "D-Link DE-620 pocket adapter",
  "dgrs" => "Digi International RightSwitch",
  "depca" => "Digital DEPCA and EtherWORKS",
  "ewrk3" => "Digital EtherWORKS 3",
  "old_tulip" => "Digital 21040/21041/21140 (old Tulip driver)",
  "tulip" => "Digital 21040/21041/21140 (Tulip)",
  "eth16i" => "ICL EtherTeam 16i",
  "epic100" => "EPIC 100",
  "eexpress" => "Intel EtherExpress",
  "eepro" => "Intel EtherExpress Pro",
  "eepro100" => "Intel EtherExpress Pro 100", #- should run on sparc but no memory on floppy
  "hp100" => "HP10/100VG any LAN ",
  "hp" => "HP LAN/AnyLan",
  "hp-plus" => "HP PCLAN/plus",
  "lance" => "Lance",
  "lne390" => "Mylex LNE390",
  "ne" => "NE2000 and compatible",
  "ne2k-pci" => "NE2000 PCI",
  "ne3210" => "NE3210",
  "ni5010" => "NI 5010",
  "ni52" => "NI 5210",
  "ni65" => "NI 6510",
  "es3210" => "Racal-Interlan ES3210",
  "rcpci" => "Red Creek Hardware VPN",
  "epic100" => "SMC 83c170 EPIC/100",
  "sktr" => "Syskonnect Token ring adaptor",
  "smc9194" => "SMC 9000 series",
  "smc-ultra" => "SMC Ultra",
  "smc-ultra32" => "SMC Ultra 32",
  "yellowfin" => "Symbios Yellowfin G-NIC",
  "via-rhine" => "VIA Rhine",
#  "wavelan" => "AT&T WaveLAN & DEC RoamAbout DS", # TODO is a "AT&T GIS WaveLAN ISA" ?
  "wd" => "WD8003, WD8013 and compatible",
  "z85230" => "Z85x30",

  "dmfe" => "dmfe",
  "fmv18x" => "fmv18x",
  "ibmtr" => "Token Ring Tropic",
  "olympic" => "olympic",
  "plip" => "PLIP (parallel port)",
  "rl100a" => "rl100a",
  "sb1000" => "sb1000",
  "sbni" => "sbni",
  "sis900" => "sis900",
),
  "3c59x" => "3com 3c59x (Vortex)",
  "de4x5" => "Digital 425,434,435,450,500",
  "rtl8139" => "RealTek RTL8129/8139",
}],
[ 'network', {
  "8390" => "8390",
  "af_packet" => "packet socket",
  "nfs" => "Network File System (nfs)",
  "lockd" => "lockd",
  "parport" => "parport",
  "parport_pc" => "parport_pc",
  "sunrpc" => "sunrpc",
}],
[ 'isdn', {
  "hisax" => "hisax",
}],
[ 'scsi', {
arch() =~ /^sparc/ ? (
  "qlogicpti" => "Performance Technologies ISP",
) : arch() =~ /alpha/ ? () : (
  "aha152x" => "Adaptec 152x",
  "aha1542" => "Adaptec 1542",
  "aha1740" => "Adaptec 1740",
  "advansys" => "AdvanSys Adapters",
  "in2000" => "Always IN2000",
  "AM53C974" => "AMD SCSI",
  "BusLogic" => "BusLogic Adapters",
  "dtc" => "DTC 3180/3280",
  "seagate" => "Future Domain TMC-885, TMC-950",
  "fdomain" => "Future Domain TMC-16x0",
  "initio" => "Initio",
  "g_NCR5380" => "NCR 5380",
  "NCR53c406a" => "NCR 53c406a",
  "53c7,8xx" => "NCR 53c7xx",
  "qlogicfas" => "Qlogic FAS",
  "seagate" => "Seagate ST01/02",
  "t128" => "Trantor T128/T128F/T228",
  "u14-34f" => "UltraStor 14F/34F",
  "ultrastor" => "UltraStor 14F/24F/34F",
  "wd7000" => "Western Digital wd7000",

  "a100u2w" => "a100u2w",
  "atp870u" => "atp870u (Acard/Artop)",
  "dc395x_trm" => "dc395x_trm",
  "psi240i" => "psi240i",
  "qlogicfc" => "qlogicfc",
  "sim710" => "sim710",
  "sym53c416" => "sym53c416",
  "tmscsim" => "tmscsim",
  "scsi_mod" => "scsi_mod",
),
  "aic7xxx" => "Adaptec 2740, 2840, 2940",
  "ncr53c8xx" => "NCR 53C8xx PCI",
#  "pci2000" => "Perceptive Solutions PCI-2000", # TODO
  "qlogicisp" => "Qlogic ISP",
  "sym53c8xx" => "Symbios 53c8xx",
  "sd_mod" => "sd_mod",
  "ide-mod" => "ide-mod",
  "ide-probe" => "ide-probe",
#-  "ide-probe-mod" => "ide-probe-mod",
}],
[ 'disk', {
arch() =~ /^sparc/ ? (
  "pluto" => "Sun SparcSTORAGE Array SCSI", #- name it "fc4:soc:pluto" ?
) : arch() =~ /alpha/ ? () : (
  "DAC960" => "Mylex DAC960",
#  "dpt" => "Distributed Tech SmartCache/Raid I-IV Controller", # not there anymore?
  "megaraid" => "AMI MegaRAID",
  "aacraid" => "AACxxx Raid Controller",
  "cpqarray" => "Compaq Smart-2/P RAID Controller",
  "gdth" => "ICP Disk Array Controller",
  "ips" => "IBM ServeRAID controller",
  "eata" => "EATA SCSI PM2x24/PM3224",
  "eata_pio" => "EATA PIO Adapters",
  "eata_dma" => "EATA DMA Adapters",
  "ppa" => "Iomega PPA3 (parallel port Zip)",
  "imm" => "Iomega Zip (new driver)",
),
  "ide-disk" => "IDE disk",
}],
[ 'cdrom', {
arch() !~ /^sparc|alpha/ ? (
  "sbpcd" => "SoundBlaster/Panasonic",
#-  "aztcd" => "Aztech CD",
#-  "gscd" => "Goldstar R420",
#-  "isp16" => "ISP16/MAD16/Mozart",
#-  "mcd" => "Mitsumi", #- removed for space
#-  "mcdx" => "Mitsumi (alternate)",
#-  "optcd" => "Optics Storage 8000",
#-  "cm206" => "Phillips CM206/CM260",
#-  "sjcd" => "Sanyo",
  "cdu31a" => "Sony CDU-31A",
  "sonycd535" => "Sony CDU-5xx",
) : (),
  "isofs" => "iso9660",
  "ide-cd" => "ide-cd",
  "sr_mod" => "SCSI CDROM support",
  "cdrom" => "cdrom",
}],
[ 'sound', {
arch() !~ /^sparc/ ? (
  "alsa" => "ALSA sound module, many sound cards",
  "cmpci" => "C-Media Electronics CMI8338A CMI8338B CMI8738",
  "es1370" => "Ensoniq ES1370 [AudioPCI]",
  "es1371" => "Ensoniq ES1371 [AudioPCI-97]",
  "esssolo1" => "ESS Technology ES1969 Solo-1 Audiodrive",
  "maestro" => "Maestro",
  "nm256" => "Neomagic MagicMedia 256AV",
  "pas16" => "Pro Audio Spectrum/Studio 16",
  "via82cxxx" => "VIA VT82C686_5",
  "sonicvibes" => "S3 SonicVibes",
) : (),
}],
[ 'pcmcia', {
arch() !~ /^sparc/ ? (
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
  "dummy_cs" => "dummy_cs",
  "memory_cs" => "memory_cs",
  "ftl_cs" => "ftl_cs",
  "smc91c92_cs" => "smc91c92_cs",
  "3c589_cs" => "3c589_cs",
  "parport_cs" => "parport_cs", 
  "3c575_cb" => "3c575_cb",
  "apa1480_cb" => "apa1480_cb",
  "cb_enabler" => "cb_enabler",
  "epic_cb" => "epic_cb",
  "iflash2+_mtd" => "iflash2+_mtd",
  "iflash2_mtd" => "iflash2_mtd",
  "memory_cb" => "memory_cb",
  "serial_cb" => "serial_cb",
  "sram_mtd" => "sram_mtd",
  "tulip_cb" => "tulip_cb",

) : (),
}],
[ 'pcmcia_everywhere', {
arch() !~ /^sparc/ ? (
  "pcmcia_core" => "PCMCIA core support",
  "tcic" => "PCMCIA tcic controller",
  "ds" => "PCMCIA card support",
  "i82365" => "PCMCIA i82365 controller",
) : (),
}],
[ 'paride', {
arch() !~ /^sparc/ ? (
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
) : (),
}],
[ 'raid', {
  "linear" => "linear",
  "raid0" => "raid0",
  "raid1" => "raid1",
  "raid5" => "raid5",
}],
[ 'mouse', {
arch() !~ /^sparc/ ? (
  "busmouse" => "busmouse",
  "msbusmouse" => "msbusmouse",
  "serial" => "serial",
  "qpmouse" => "qpmouse",
  "atixlmouse" => "atixlmouse",

  "usb-uhci", "USB (uhci)",
  "usb-ohci", "USB (ohci)",
  "usb-ohci-hcd", "USB (ohci-hcd)",
) : (),
}],
[ 'fs', {
  "smbfs" => "Windows SMB",
  "fat" => "fat",
  "msdos" => "msdos",
  "romfs" => "romfs",
  "sysv" => "sysv",
  "ufs" => "ufs",
  "umsdos" => "umsdos",
  "vfat" => "vfat",
}],
[ 'other', {
  "st" => "st",
  "sg" => "sg",
  "ide-scsi" => "ide-scsi",
  "loop" => "Loopback device",
  "lp" => "Parallel Printer",
  "ide-floppy" => "ide-floppy",
  "ide-tape" => "ide-tape",
  "nbd" => "nbd",
}],
);

my %type_aliases = (
  scsi => 'disk',
);

my @skip_modules_on_stage1 =
  arch() =~ /alpha/ ? qw(sb1000) :
  ();


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
    my %skip; @skip{@skip_modules_on_stage1} = ();
    grep { !exists $skip{$_} } grep { $drivers{$_}{type} =~ /^($type)$/ } keys %drivers;
}
sub module_of_type {
    my ($type) = @_;
    my $alias = $type_aliases{$type};
    grep { $drivers{$_}{type} =~ /^(($type)|$alias)$/ } keys %drivers;
}
sub module2text { $drivers{$_[0]}{text} }

sub get_alias {
    my ($alias) = @_;
    $conf{$alias}{alias};
}
sub get_options {
    my ($name) = @_;
    $conf{$name}{options};
}

sub add_alias($$) { 
    my ($alias, $name) = @_;
    $name =~ /ignore/ and return;
    /\Q$alias/ && $conf{$_}{alias} && $conf{$_}{alias} eq $name and return $_ foreach keys %conf;
    $alias .= $scsi++ || '' if $alias eq 'scsi_hostadapter';
    log::l("adding alias $alias to $name");
    $conf{$alias}{alias} ||= $name;
    if ($alias eq "sound" && $name =~ /^snd-card-/) {
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

sub load {
    my ($name, $type, @options) = @_;

    if ($::testing) {
	log::l("i try to install $name module (@options)");
    } else {
	$conf{$name}{loaded} and return;

	eval { load($_, 'prereq') } foreach @{$deps{$name}};
	load_raw([ $name, @options ]);
    }
    if ($name eq "usb-storage") {
	sleep(2); 
	-d "/proc/scsi/usb" or return;
    }
    if ($type) {
	add_alias('usb-interface', $name) if $type =~ /SERIAL_USB/i;
	add_alias('scsi_hostadapter', $name), load('sd_mod') if $type =~ /scsi/ || $type eq $type_aliases{scsi};
    }
    $conf{$name}{options} = join " ", @options if @options;
}
sub load_multi {
    my $f; $f = sub { map { $f->(@{$deps{$_}}), $_ } @_ };
    my %l; my @l = 
      grep { !$conf{$_}{loaded} }
      grep { my $o = $l{$_}; $l{$_} = 1; !$o }
      $f->(@_);

    $::testing and log::l("i would install modules @l"), return;

    load_raw(map { [ $_ ] } @l);
}

sub unload($;$) {
    my ($m, $remove_alias) = @_; 
    if ($::testing) {
	log::l("rmmod $m");
    } else {
	if (run_program::run("rmmod", $m)) {
	    delete $conf{$m}{loaded};
	}
    }
    remove_alias($m) if $remove_alias;
}

sub load_raw {
    my @l = map { my ($i, @i) = @$_; [ $i, \@i ] } grep { $_->[0] !~ /ignore/ } @_;
    my $cz = "/lib/modules" . (arch() eq 'sparc64' && "64") . ".cz"; -e $cz or $cz .= "2";
    run_program::run("extract_archive", $cz, "/tmp", map { "$_->[0].o" } @l);
    my @failed = grep {
	my $m = "/tmp/$_->[0].o";
	if (-e $m && run_program::run(["insmod_", "insmod"], "-f", $m, @{$_->[1]})) {
	    unlink $m;
	    $conf{$_->[0]}{loaded} = 1;
	    '';
	} else {
	    log::l("missing module $_->[0]") unless -e $m;
	    -e $m;
	}
    } @l;

    foreach (@l) {
	if ($_->[0] eq "parport_pc") {
	    #- this is a hack to make plip go
	    foreach (@{$_->[1]}) {
		/^irq=(\d+)/ and eval { output "/proc/parport/0/irq", $1 };
	    }
	} elsif ($_->[0] =~ /usb-[uo]hci/) {
	    #- ensure keyboard is working, the kernel must do the job the BIOS was doing
	    load_multi("usbkbd", "keybdev");
	}
    }
    die "insmod'ing module " . join(", ", map { $_->[0] } @failed) . " failed" if @failed;
}

sub read_already_loaded() {
    foreach (cat_("/proc/modules")) {
	my ($name) = split;
	$conf{$name}{loaded} = 1;
	push @$l, $name unless member($name, @$l);
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
	    $$scsi = max($$scsi, $1 || 0) if /^\s*alias\s+scsi_hostadapter (\d*)/x && $scsi; #- space added to make perl2fcalls happy!
	} if /^\s*(\S+)\s+(\S+)\s+(.*?)\s*$/;
    }
    #- cheating here: not handling aliases of aliases
    while (my ($k, $v) = each %c) {
#-	$$scsi ||= $v->{scsi_hostadapter} if $scsi;
	if (my $a = $v->{alias}) {
	    local $c{$a}{alias};
	    add2hash($c{$a}, $v);
	}
    }
    \%c;
}

sub write_conf {
    my ($prefix) = @_;

    my $file = "$prefix/etc/modules.conf";
    rename "$prefix/etc/conf.modules", $file; #- make the switch to new name if needed

    #- remove the post-install supermount stuff. We may have to add some more
    substInFile { $_ = '' if /^post-install supermount/ } $file;

    my $written = read_conf($file);

    my %net = detect_devices::net2module();
    while (my ($k, $v) = each %net) { add_alias($k, $v) }

    my @l = sort grep { $conf{$_}{alias} && /scsi_hostadapter/ } keys %conf;
    add_alias('block-major-11', 'scsi_hostadapter') if @l;
    push @l, "ide-floppy" if detect_devices::ide_zips();
    $conf{supermount}{"post-install"} = join " ; ", map { "modprobe $_" } @l if @l;
    $conf{"usb-storage"}{"post-install"} = "modprobe usbkbd; modprobe keybdev" if @l && arch() !~ /sparc|alpha/;

    local *F;
    open F, ">> $file" or die("cannot write module config file $file: $!\n");
    while (my ($mod, $h) = each %conf) {
	while (my ($type, $v2) = each %$h) {
	    print F "$type $mod $v2\n" if $v2 && $type ne "loaded" && !$written->{$mod}{$type};
	}
    }
}

sub read_stage1_conf {
    add2hash(\%conf, read_conf($_[0], \$scsi));
    if (arch() =~ /sparc/) {
	$conf{parport_lowlevel}{alias} ||= "parport_ax";
	$conf{plip}{"pre-install"} ||= "modprobe parport_ax ; echo 7 > /proc/parport/0/irq"; #- TOCHECK
    } else {
	$conf{parport_lowlevel}{alias} ||= "parport_pc";
	$conf{pcmcia_core}{"pre-install"} ||= "CARDMGR_OPTS=-f /etc/rc.d/init.d/pcmcia start";
	$conf{plip}{"pre-install"} ||= "modprobe parport_pc ; echo 7 > /proc/parport/0/irq";
    }
}

sub load_thiskind {
    my ($type, $pcic, $f) = @_;

    grep {
	$f->($_->{description}, $_->{driver}) if $f;
	eval { load($_->{driver}) };
	$_->{error} = $@;

	!($@ && $_->{try});
    } get_that_type($type, $pcic),
      $type =~ /scsi/ && arch() !~ /sparc/ ? 
	(map { +{ driver => $_, description => $_, try => 1 } } "usb-storage", "imm", "ppa") : ();
}

sub get_that_type {
    my ($type, $pcic) = @_;
    
    grep { 
	my $l = $drivers{$_->{driver}}; 
	$l && $l->{type} eq $type && detect_devices::check($_);
    } detect_devices::probeall('', $pcic);
}

sub pcmcia_need_config($) {
    return $_[0] && ! -s "/var/run/stab";
}

sub get_pcmcia_devices($$) {
    my ($pcic) = @_;
    my (@devs, $module, $desc, $type, $device);

    #- try to setup pcmcia if cardmgr is not running.
    if (pcmcia_need_config($pcic)) {
	log::l("i try to configure pcmcia services");

	symlink("/tmp/stage2/etc/pcmcia", "/etc/pcmcia") unless -e "/etc/pcmcia";
	symlink("/sbin/install", "/sbin/cardmgr") unless -x "/sbin/cardmgr";

	eval {
	    load("pcmcia_core");
	    load($pcic);
	    load("ds");
	};

	#- run cardmgr in foreground while it is configuring the card.
	run_program::run("cardmgr", "-f", "-m" ,"/modules");
	sleep(3);

	#- make sure to be aware of loaded module by cardmgr.
	read_already_loaded();
    }

    foreach (cat_("/var/run/stab")) {
	$desc = $1 if /^Socket\s+\d+:\s+(.*)/;
	($type, $module, $device) = ($1, $2, $3) if /^\d+\s+(\S+)\s+(\S+)\s+\S+\s+(\S+)/;
	if ($desc && $module) {
	    push @devs, { description => $desc, driver => $module, type => $type, device => $device };
	    $desc = $module = undef;
	}
    }
    @devs;
}

sub load_ide {
    eval {
	load("ide-mod", 'prereq', 'options="' . detect_devices::hasUltra66() . '"');
	delete $conf{"ide-mod"}{options};
	load_multi(qw(ide-probe ide-probe-mod ide-disk ide-cd));
    }

}

1;

