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
      if_(arch() =~ /ppc/, qw(mace bmac sungem)),
      if_(arch() =~ /^sparc/, qw(sunbmac sunhme sunqe)),
      if_(arch() !~ /alpha|sparc/,
        qw(3c501 3c503 3c505 3c507 3c509 3c515 3c90x),
	qw(82596 abyss ac3200 acenic aironet4500_card at1700 atp com20020-pci),
        qw(cs89x0 de600 de620),
        qw(defxx), # most unused
        qw(depca dgrs dmfe e100 e2100 eepro eepro100 eexpress epic100 eth16i),
        qw(ewrk3 hamachi hp hp-plus hp100 ibmtr),
        qw(lance natsemi ne ne2k-pci ni5010 ni52 ni65 nvnet olympic pcnet32 plip rcpci),
        qw(sb1000 sis900 smc-ultra smc9194 starfire tlan tmspci tulip tulip_old via-rhine),
        qw(wd winbond-840 forcedeth),
	qw(fealnx 3c990 3c990fx b44 bcm4400),
        qw(skfp tc35815 lanstreamer farsync sdladrv prism2_plx),

	qw(iph5526), #- fibre channel
      ),
      qw(3c59x 8139too 8139cp sundance), #rtl8139
    ],
    firewire => [ qw(eth1394) ],
    gigabit => [
      qw(dl2k myri_sbus yellowfin ns83820 r8169 tg3 e1000 sk98lin),
      qw(bcm5820 bcm5700), #- encrypted
    ],

    raw => [
      qw(ppp_generic ppp_async),
    ],
    pcmcia => [ 
      qw(3c574_cs 3c589_cs axnet_cs fmvj18x_cs),
      qw(ibmtr_cs nmclan_cs pcnet_cs smc91c92_cs),
      qw(xirc2ps_cs xircom_cb xircom_tulip_cb),
    ],
    usb => [ 
      qw(catc CDCEther kaweth pegasus rtl8150 usbnet),
    ],
    wireless => [
      qw(acx100_pci airo airo_cs aironet4500_cs aironet_cs at76c503-rfmd atmel_cs),
      qw(ipw2100 ipw2200 madwifi_pci netwave_cs orinoco orinoco_cs orinoco_pci orinoco_plx),
      qw(prism2_usb prism54 ray_cs usbvnet_rfmd vt_ar5k wavelan_cs wvlan_cs),
      if_(arch() =~ /ppc/, qw(airport)),
    ],
    isdn => [
      qw(b1pci c4 hisax hisax_fcpcipnp hysdn t1pci tpam divas),
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
        qw(atp870u dc395x_trm dtc g_NCR5380 in2000 initio pas16 pci2220i psi240i fdomain),
        qw(qla1280 qla2x00 qlogicfas qlogicfc),
        qw(seagate wd7000 sim710 sym53c416 t128 tmscsim u14-34f ultrastor),
        qw(eata eata_pio eata_dma mptscsih nsp32),
        qw(ata_piix sata_promise sata_svw sata_via sata_sis sata_sil),
      ),
      '53c7,8xx',
      qw(aic7xxx aic7xxx_old aic79xx pci2000 qlogicisp sym53c8xx lpfcdd), # ncr53c8xx
    ],
    hardware_raid => [
      if_(arch() =~ /^sparc/, qw(pluto)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
        qw(DAC960 dpt_i2o megaraid aacraid cciss cpqarray gdth i2o_block),
	qw(cpqfc qla2200 qla2300 pdc-ultra iteraid),
        qw(ips ppa imm),
       if_(c::kernel_version =~ /^\Q2.4/,
	qw(ataraid hptraid silraid pdcraid)
       ),
      ),
    ],
    pcmcia => [ qw(aha152x_cs fdomain_cs nsp_cs qlogic_cs ide-cs) ], #ide_cs
    raw => [ qw(sd_mod) ],
    usb => [ qw(usb-storage) ],
    firewire => [ qw(sbp2) ],
    cdrom => [ qw(ide-cd sr_mod) ],
  },

  ################################################################################

  bus => 
  {
    usb => [ qw(usb-uhci usb-ohci ehci-hcd uhci-hcd ohci-hcd) ],
    firewire => [ qw(ohci1394) ],
    pcmcia => [
      if_(arch() !~ /^sparc/, qw(tcic i82365 i82092 yenta_socket)), # cb_enabler
    ],
    usb_keyboard => [ qw(usbkbd keybdev) ],
   #serial_cs
   #ftl_cs 3c575_cb apa1480_cb epic_cb serial_cb tulip_cb iflash2+_mtd iflash2_mtd
   #cb_enabler
  },

  fs => 
  {
    network => [ qw(af_packet nfs) ],
    cdrom => [ qw(isofs) ],
    loopback => [ qw(isofs loop), if_($ENV{MOVE}, qw(cryptoloop gzloop supermount)) ],
    local => [
      if_(arch() =~ /^i.86|x86_64/, qw(vfat ntfs)),
      if_(arch() =~ /^ppc/, qw(hfs)),
      qw(reiserfs),
    ],
    various => [ qw(smbfs romfs ext3 xfs) ],

  },

  ################################################################################
  multimedia => 
  {
    sound => [
      if_(arch() =~ /ppc/, qw(dmasound_pmac snd-powermac)),
      if_(arch() =~ /sparc/, qw(snd-sun-amd7930 snd-sun-cs4231)),
      if_(arch() !~ /^sparc/,
          qw(ad1816 ad1848 ad1889 ali5455 audigy audio awe_wave cmpci cs4232 cs4281 cs46xx),
          qw(emu10k1 es1370 es1371 esssolo1 forte gus i810_audio ice1712 kahlua mad16 maestro),
          qw(maestro3 mpu401 msnd_pinnacle nm256_audio nvaudio opl3 opl3sa opl3sa2 pas2 pss),
          qw(rme96xx sam9407 sb sgalaxy snd-ad1816a snd-ad1848 snd-ali5451 snd-als100),
          qw(snd-als4000 snd-atiixp snd-au8810 snd-au8820 snd-au8830 snd-azt2320 snd-azt3328),
          qw(snd-bt87x snd-cmi8330 snd-cmipci snd-cs4231 snd-cs4232 snd-cs4236 snd-cs4281),
          qw(snd-cs46xx snd-dt019x snd-emu10k1 snd-ens1370 snd-ens1371 snd-es1688 snd-es18xx),
          qw(snd-es1938 snd-es1968 snd-es968 snd-fm801 snd-gusclassic snd-gusextreme),
          qw(snd-gusmax snd-hdsp snd-ice1712 snd-ice1724 snd-intel8x0 snd-interwave),
          qw(snd-interwave-stb snd-korg1212 snd-maestro3 snd-mixart snd-mpu401 snd-nm256),
          qw(snd-opl3sa2 snd-opti92x-ad1848 snd-opti92x-cs4231 snd-opti93x snd-rme32),
          qw(snd-rme96 snd-rme9652 snd-sb16 snd-sb8 snd-sbawe snd-sgalaxy snd-sonicvibes),
          qw(snd-sscape snd-trident snd-via82xx snd-vx222 snd-vxp440 snd-vxpocket snd-wavefront),
          qw(snd-ymfpci sonicvibes sscape trident via82cxxx_audio wavefront ymfpci),
      ),
    ],
    tv => [ qw(bttv cpia_usb cyber2000fb ibmcam mod_quickcam ov511 ov518_decomp pwc saa7134 ultracam usbvideo) ],
    photo => [ qw(dc2xx mdc800) ],
    radio => [ qw(radio-maxiradio) ],
    scanner => [ qw(scanner microtek) ],
    joystick => [ qw(ns558 emu10k1-gp iforce) ],
  },

  various => 
  # just here for classification, unused categories (nor auto-detect, nor load_thiskind)
  {
    raid => [
      qw(linear raid0 raid1 raid5 lvm-mod multipath),
    ],
    mouse => [
      qw(busmouse msbusmouse logibusmouse serial qpmouse atixlmouse),
    ],
    char => [
      if_(arch() =~ /ia64/, qw(efivars)),
      qw(amd768_rng applicom n_r3964 nvram pc110pad ppdev),
      qw(mxser moxa isicom wdt_pci epca synclink istallion sonypi i810-tco sx), #- what are these???
    ],
    other => [
      qw(defxx i810_rng i810fb ide-floppy ide-scsi ide-tape loop lp nbd sg st),
      qw(parport_pc parport_serial),
      qw(btaudio),

      #- these need checking
      qw(pcilynx sktr rrunner meye 3c559 buz paep),
    ],
    agpgart => [
      if_(arch() =~ /alpha/, qw(alpha-agp)),
      if_(arch() =~ /ia64/, qw(hp-agp i460-agp)),
      if_(arch() =~ /ppc/, qw(uninorth-agp)),

      qw(ali-agp amd64-agp amd-k7-agp ati-agp intel-agp),
	 qw(nvidia-agp sworks-agp sis-agp via-agp),
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
	} $t2s eq '*' ? keys %{$l{$t1}} : split('\|', $t2s);
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
