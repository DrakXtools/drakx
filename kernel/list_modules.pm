package list_modules;

use MDK::Common;

our @ISA = qw(Exporter);
our @EXPORT = qw(load_dependencies dependencies_closure category2modules module2category sub_categories);

# the categories have 2 purposes
# - choosing modules to include on stage1's (cf update_kernel and mdk-stage1/pci-resource/update-pci-ids.pl)
# - performing a load_category or probe_category (modules.pm and many files in perl-install)

our %l = (
  ################################################################################
  network => 
  {
    main => [
      if_(arch() =~ /ppc/, qw(mace bmac gmac)),
      if_(arch() =~ /^sparc/, qw(myri_sbus sunbmac sunhme sunqe)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
        qw(3c501 3c503 3c505 3c507 3c509 3c515), # 3c90x
        qw(82596 abyss ac3200 acenic aironet4500_card at1700 atp com20020-pci),
        qw(cs89x0 de600 de620),
        qw(defxx orinoco_plx), # most unused
        qw(depca dgrs dmfe e100 e1000 e2100 eepro eepro100 eexpress epic100 eth16i),
        qw(ewrk3 hamachi hp hp-plus hp100 ibmtr),
        qw(lance natsemi ne ne2k-pci ni5010 ni52 ni65 olympic pcnet32 plip rcpci), #old_tulip 
        qw(sb1000 sis900 sk98lin smc-ultra smc9194 starfire tlan tmspci tulip via-rhine), #sktr 
        qw(wd winbond-840 yellowfin ns83820),

	qw(iph5526), #- fibre channel
      ),
      qw(3c59x 8139too sundance dl2k), #rtl8139 
    ],
    raw => [
      qw(8390 mii),
      qw(ppp_generic ppp_async slhc aironet4500_core),
    ],
    pcmcia => [ 
      qw(3c574_cs 3c589_cs airo airo_cs aironet4500_cs axnet_cs fmvj18x_cs),
      qw(ibmtr_cs netwave_cs nmclan_cs pcnet_cs ray_cs smc91c92_cs wavelan_cs wvlan_cs),
      qw(xirc2ps_cs xircom_cb xircom_tulip_cb),
    ],
    usb => [ 
      qw(pegasus kaweth usbnet catc CDCEther),
    ],
    isdn => [
      qw(hisax hysdn b1pci t1pci c4),
    ],
  },

  ################################################################################
  disk => 
  {
    scsi => [
      if_(arch() =~ /ppc/, qw(mesh mac53c94)),
      if_(arch() =~ /^sparc/, qw(qlogicpti)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
        qw(3w-xxxx AM53C974 BusLogic NCR53c406a a100u2w advansys aha152x aha1542 aha1740),
        qw(atp870u dc395x_trm dtc fdomain g_NCR5380 in2000 initio pci2220i psi240i),
        qw(qla1280 qla2x00 qlogicfas qlogicfc),
        qw(seagate sim710 sym53c416 t128 tmscsim u14-34f ultrastor wd7000),
        qw(eata eata_pio eata_dma),
      ),
      '53c7,8xx',
      qw(aic7xxx pci2000 qlogicisp sym53c8xx), # ncr53c8xx
    ],
    hardware_raid => [
      if_(arch() =~ /^sparc/, qw(pluto)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
        qw(DAC960 dpt_i2o megaraid aacraid ataraid cciss cpqarray gdth i2o_block),
	qw(qla2200 qla2300 cpqfc),
        qw(ips ppa imm),
      ),
    ],
    pcmcia => [ qw(aha152x_cs fdomain_cs nsp_cs qlogic_cs ide-cs) ], #ide_cs
    raw => [ qw(scsi_mod sd_mod) ],
    usb => [ qw(usb-storage) ],
    cdrom => [ qw(ide-cd cdrom sr_mod) ],
  },

  ################################################################################

  bus => 
  {
    usb => [ qw(usbcore usb-uhci usb-ohci ehci-hcd usbkbd keybdev input) ],
    pcmcia => [
      if_(arch() !~ /^sparc/, qw(pcmcia_core tcic ds i82365 yenta_socket)), # cb_enabler
    ],
   #serial_cs
   #ftl_cs 3c575_cb apa1480_cb epic_cb serial_cb tulip_cb iflash2+_mtd iflash2_mtd
   #cb_enabler
  },

  fs => 
  {
    network => [ qw(af_packet nfs lockd sunrpc) ],
    cdrom => [ qw(isofs) ],
    loopback => [ qw(isofs loop) ],
    local => [
      if_(arch() =~ /^i.86/, qw(vfat fat)),
      if_(arch() =~ /^ppc/, qw(hfs)),
      qw(reiserfs),
    ],
    various => [ qw(smbfs romfs jbd xfs) ],

  },

  ################################################################################
  multimedia => 
  {
    sound => [
      if_(arch() =~ /ppc/, qw(dmasound_awacs)),
      if_(arch() !~ /^sparc/,
        qw(cmpci cs46xx cs4281 es1370 es1371 esssolo1 i810_audio maestro maestro3),
        qw(nm256_audio pas16 trident via82cxxx_audio sonicvibes emu10k1 ymfpci),
	qw(rme96xx audigy),

        qw(snd-ice1712 snd-cmipci snd-ens1371 snd-via8233),
        qw(snd-es1938 snd-fm801 snd-intel8x0 snd-rme96),
	qw(snd-cs46xx snd-maestro3 snd-korg1212 snd-ens1370 snd-als4000),
        qw(snd-trident snd-ymfpci),
      ),
    ],
    tv => [ qw(bttv cpia_usb ibmcam mod_quickcam ov511 ultracam usbvideo cyber2000fb) ],
    photo => [ qw(dc2xx mdc800) ],
    radio => [ qw(radio-maxiradio) ],
    scanner => [ qw(scanner microtek) ],
    joystick => [ qw(ns558 emu10k1-gp iforce) ],
  },

  various => 
  # just here for classification, unused categories (nor auto-detect, nor load_thiskind)
  {
    raid => [
      qw(linear raid0 raid1 raid5 lvm-mod md multipath xor),
    ],
    mouse => [
      qw(busmouse msbusmouse logibusmouse serial qpmouse atixlmouse),
    ],
    char => [
      qw(amd768_rng applicom n_r3964 nvram pc110pad ppdev),
      qw(mxser moxa isicom wdt_pci epca synclink istallion sonypi i810-tco sx), #- what are these???
    ],
    other => [
      qw(agpgart defxx i810_rng i810fb ide-floppy ide-scsi ide-tape loop lp nbd sg st),
      qw(parport parport_pc parport_serial),
      qw(btaudio),

      #- these need checking
      qw(pcilynx sktr rrunner gmac meye 3c559 buz paep),
    ],
  },
);

my %dependencies;

sub load_dependencies {
    my ($file) = @_;

    %dependencies = map {
	my ($f, $deps) = split ':';
	$f => [ split ' ', $deps ];
    } cat_($file);
}

sub dependencies_closure {
    my @l = map { dependencies_closure($_) } @{$dependencies{$_[0]} || []};
    (@l, $_[0]);
}

sub category2modules {
    map {
	my ($t1, $t2s) = m|(.*)/(.*)|;
	map { 
	    my $l = $l{$t1}{$_} or die "bad category $t1/$_\n" . backtrace();
	    @$l;
	} split('\|', $t2s);
    } split(' ', $_[0]);
}

sub module2category {
    my ($module) = @_;
    foreach my $t1 (keys %l) {
	my $h = $l{$t1};
	foreach my $t2 (keys %$h) {
	  $module eq $_ and return "$t1/$t2" foreach @{$h->{$t2}};
      }
    }
    return;
}

sub sub_categories {
    my ($t1) = @_;
    keys %{$l{$t1}};
}

1;
