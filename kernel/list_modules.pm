package list_modules; # $Id$

use MDK::Common;

our @ISA = qw(Exporter);
our @EXPORT = qw(load_dependencies dependencies_closure category2modules module2category sub_categories kernel_is_26 module_extension);

# the categories have 2 purposes
# - choosing modules to include on stage1's (cf update_kernel and mdk-stage1/pci-resource/update-pci-ids.pl)
# - performing a load_category or probe_category (modules.pm and many files in perl-install)

our %l = (
  ################################################################################
  network => 
  {
    atm => [ qw(ambassador eni firestream fore_200e he horizon idt77252 iphase lanai nicstar zatm) ],
    main => [
      if_(arch() =~ /ppc/, qw(bmac ibm_emac mace oaknet sungem)),
      if_(arch() =~ /^sparc/, qw(sunbmac sunhme sunqe)),
      if_(arch() !~ /alpha|sparc/,
        qw(3c501 3c503 3c505 3c507 3c509 3c515 3c990 3c990fx),
        qw(82596 ac3200 acenic aironet4500_card amd8111e at1700 atp),
        qw(b44 bcm4400 cassini com20020-pci cs89x0 de2104x de600 de620),
        qw(defxx), # most unused
        qw(depca dgrs dmfe e100 e2100 eepro eepro100 eexpress epic100 eth16i),
        qw(ewrk3  fealnx hamachi hp hp-plus hp100),
        qw(iph5526), #- fibre channel
        qw(lance natsemi ne ne2k-pci ni5010 ni52 ni65 nvnet),
        qw(pcnet32 plip prism2_plx rcpci rhineget),
        qw(sb1000 sis900 skfp smc-ultra smc9194 starfire),
        qw(tc35815 tlan tulip typhoon uli526x via-rhine),
        qw(wd winbond-840 forcedeth),
        qw(sungem sunhme), # drivers for ultrasparc, but compiled in ix86 kernels...
      ),
      qw(3c59x 8139too 8139cp sundance), #rtl8139
    ],
    firewire => [ qw(eth1394 pcilynx) ],
    gigabit => [
      qw(bnx2 cxgb dl2k e1000 ixgb myri_sbus ns83820 r8169 s2io sis190 sk98lin skge spidernet tg3 via-velocity yellowfin),
      qw(bcm5820 bcm5700), #- encrypted
    ],

    raw => [
      qw(ppp_generic ppp_async ppp_deflate bsd_comp),
    ],
    pcmcia => [ 
      qw(3c574_cs 3c589_cs axnet_cs fmvj18x_cs),
      qw(ibmtr_cs nmclan_cs pcnet_cs smc91c92_cs),
      qw(xirc2ps_cs xircom_cb xircom_tulip_cb),
    ],
   #- generic NIC detection for USB seems broken (class, subclass, 
   #- protocol reported are not accurate) so we match network adapters against
   #- known drivers :-(
    usb => [ 
      qw(catc CDCEther kaweth pegasus rtl8150 usbnet),
    ],
    wireless => [
      qw(acx100_pci adm8211 airo airo_cs aironet4500_cs aironet_cs),
      qw(at76c503-i3861 at76c503-i3863 at76c503-rfmd at76c503-rfmd-acc at76c505-rfmd at76c505-rfmd2958 at76c505a-rfmd2958),
      qw(ath_pci atmel_cs atmel_pci dyc_ar5),
      qw(hostap_pci hostap_plx ipw2100 ipw2200 madwifi_pci netwave_cs orinoco orinoco_cs orinoco_pci orinoco_plx orinoco_tmd),
      qw(prism2_cs prism2_pci prism2_usb prism54 r8180 ray_cs rt2400 rt2500 usbvnet_rfmd vt_ar5k wavelan_cs wvlan_cs zd1201),
      if_(arch() =~ /ppc/, qw(airport)),
    ],
    isdn => [
      qw(avmfritz c4 cdc-acm b1pci divas hfc4s8s_l1 hfc_usb hfc4s8s_l1 hisax hisax_st5481 hisax_fcpcipnp hysdn sedlfax t1pci tpam w6692pci),
      qw(fcpci fcdsl fcdsl fcdsl2 fcdslsl fcdslslusb fcdslusb fcdslusba fcusb fcusb2 fxusb fxusb_CZ)
    ],
    modem => [
      qw(ltmodem mwave sm56),
    ],
    slmodem => [
      qw(slamr slusb snd-ali5451 snd-atiixp-modem snd-intel8x0m snd-via82xx-modem),
    ],
    tokenring => [ qw(3c359 abyss ibmtr lanstreamer olympic proteon skisa smctr tms380tr tmspci) ],
    wan => [ qw(c101 cosa cyclomx cycx_drv dlci farsync hdlc hostess_sv11 n2 pc300 pci200syn sbni sdla sdladrv sealevel syncppp wanxl z85230) ],
    usb_dsl => [ qw(cxacru eagle-usb speedtch ueagle-atm usbatm xusbatm) ],
  },

  ################################################################################
  disk => 
  {
    # ide drivers compiled as modules:
    ide => [
        qw(aec62xx cs5520 cs5530 cs5535 delkin_cb ide-generic),
        qw(pata_amd pata_mpiix pata_oldpiix pata_opti pata_pdc2027x pata_sil680 pata_triflex pata_via),
        qw(rz1000 sc1200 slc90e66 triflex trm290) ],
    # ide drivers compiled in core kernel:
    all_ide => [
        qw(ali14xx amd74xx dtc2278 ht6560b qd65xx umc8672 alim15x3 atiixp cmd64x cy82c693),
        qw(hpt34x hpt366 ns87415 opti621 pdc202xx_new pdc202xx_old piix serverworks),
        qw(siimage sis5513 via82cxxx),
    ],
    scsi => [
      if_(arch() =~ /ppc/, qw(mesh mac53c94)),
      if_(arch() =~ /^sparc/, qw(qlogicpti)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
	'53c7,8xx',
        qw(AM53C974 BusLogic NCR53c406a a100u2w advansys aha152x aha1542 aha1740),
        qw(atp870u dc395x dc395x_trm dmx3191d dtc g_NCR5380 in2000 initio pas16 pci2220i psi240i fdomain),
        qw(qla1280 qla2x00 qla2xxx qlogicfas qlogicfc),
        qw(seagate wd7000 sim710 sym53c416 t128 tmscsim u14-34f ultrastor),
        qw(eata eata_pio eata_dma nsp32),
      ),
      qw(aic7xxx aic7xxx_old aic79xx pci2000 qlogicfas408 sym53c8xx lpfc lpfcdd), # ncr53c8xx
    ],
    sata => [
      # note that ata_piix manage RAID devices on ICH6R
      qw(ahci aic94xx ata_adma ata_piix pata_pdc2027x pdc_adma sata_mv sata_nv sata_promise sata_qstor sata_sil sata_sil24 sata_sis sata_svw sata_sx4 sata_uli sata_via sata_vsc sx8),
    ],
    hardware_raid => [
      if_(arch() =~ /^sparc/, qw(pluto)),
      if_(arch() !~ /alpha/ && arch() !~ /sparc/,
        # 3w-xxxx drives ATA-RAID, 3w-9xxx and arcmsr drive SATA-RAID
        qw(a320raid),
        qw(3w-9xxx 3w-xxxx aacraid arcmsr cciss cpqfc cpqarray DAC960 dpt_i2o gdth i2o_block ipr it821x it8212),
        qw(iteraid megaraid megaraid_mbox megaraid_sas mptfc mptsas mptscsih qla2100 qla2200 qla2300 qla2322 qla4xxx qla6312 qla6322 pdc-ultra),
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
    bluetooth => [ qw(bcm203x bfusb bpa10x hci_usb) ],
    firewire => [ qw(ohci1394) ],
    i2c => [
      qw(i2c-ali1535 i2c-ali1563 i2c-ali15x3 i2c-amd756 i2c-amd8111 i2c-i801 i2c-i810 i2c-nforce2),
      qw(i2c-piix4 i2c-prosavage i2c-savage4 i2c-sis5595 i2c-sis630 i2c-sis96x i2c-via i2c-viapro i2c-voodoo3),
      if_(arch() !~ /^ppc/, qw(i2c-hydra i2c-ibm_iic i2c-mpc)),
    ],
    pcmcia => [
      if_(arch() !~ /^sparc/, qw(au1x00_ss i82365 i82092 pd6729 tcic vrc4171_card vrc4173_cardu yenta_socket)), # cb_enabler
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
    loopback => [ qw(isofs loop cryptoloop gzloop), if_($ENV{MOVE}, qw(supermount)) ],
    local => [
      if_(arch() =~ /^i.86|x86_64/, qw(vfat ntfs)),
      if_(arch() =~ /^ppc/, qw(hfs)),
      qw(reiserfs jfs xfs),
    ],
    various => [ qw(smbfs romfs ext3 ufs ntfs) ],

  },

  ################################################################################
  multimedia => 
  {
    sound => [
      if_(arch() =~ /ppc/, qw(dmasound_pmac snd-powermac)),
      if_(arch() =~ /sparc/, qw(snd-sun-amd7930 snd-sun-cs4231 snd-sun-dbri)),
      if_(arch() !~ /^sparc/,
          qw(ad1816 ad1848 ad1889 ali5455 audigy audio awe_wave cmpci cs4232 cs4281 cs46xx),
          qw(emu10k1 es1370 es1371 esssolo1 forte gus i810_audio ice1712 kahlua mad16 maestro),
          qw(maestro3 mpu401 msnd_pinnacle nm256_audio nvaudio opl3 opl3sa opl3sa2 pas2 pss),
          qw(rme96xx sam9407 sb sgalaxy snd-ad1816a snd-ad1848 snd-ad1889 snd-ali5451 snd-als100),
          qw(snd-als4000 snd-atiixp snd-au8810 snd-au8820 snd-au8830 snd-audigyls snd-azt2320 snd-azt3328 snd-azx),
          qw(snd-asihpi snd-bt87x snd-ca0106 snd-cmi8330 snd-cmipciAsnd-cs4231 snd-cs4232 snd-cs4236 snd-cs4281),
          qw(snd-cs46xx snd-cs5535audio snd-darla20 snd-darla24 snd-dt019x snd-emu10k1 snd-emu10k1x snd-ens1370 snd-ens1371 snd-es1688 snd-es18xx),
          qw(snd-es1938 snd-es1968 snd-es968 snd-fm801 snd-gina20 snd-gina24 snd-gina3g snd-gusclassic snd-gusextreme),
          qw(snd-gusmax snd-hda-intel snd-hdsp snd-hdspm snd-ice1712 snd-ice1724 snd-indi snd-indigo snd-indigodj snd-indigoio snd-intel8x0 snd-interwave),
          qw(snd-interwave-stb snd-korg1212 snd-layla20 snd-layla24 snd-layla3g snd-maestro3 snd-mia snd-mixart snd-mona snd-mpu401 snd-nm256),
          qw(snd-opl3sa2 snd-opti92x-ad1848 snd-opti92x-cs4231 snd-opti93x snd-pcxhr snd-riptide snd-rme32),
          qw(snd-rme96 snd-rme9652 snd-sb16 snd-sb8 snd-sbawe snd-sgalaxy snd-sonicvibes),
          qw(snd-sscape snd-trident snd-via82xx snd-vx222 snd-vxp440 snd-vxpocket snd-wavefront),
          qw(snd-ymfpci sonicvibes sscape trident via82cxxx_audio wavefront ymfpci),
      ),
    ],
    tv => [ qw(bt878 bttv cx8800 cx88-blackbird dpc7146 ivtv saa7134 zr36067) ],
    dvb => [ qw(budget budget-av budget-ci cinergyT2 dvb-ttusb-budget dvb-usb-a800 dvb-dibusb dvb-usb-dibusb-mb dvb-ttpci dvb-usb-digitv dvb-usb-dtt200u dvb-usb-nova-t-usb2 dvb-usb-umt-010 dvb-usb-vp7045 hexium_orion hexium_gemini pluto2 skystar2) ],
    photo => [ qw(dc2xx mdc800) ],
    radio => [ qw(radio-gemtek-pci radio-maxiradio) ],
    scanner => [ qw(scanner microtek) ],
    gameport => [ qw(cs461x ns558 emu10k1-gp fm801-gp lightning ns558 vortex) ],
    usb_sound => [ qw(audio dabusb dsbr100 snd-usb-audio snd-usb-usx2y usb-midi) ],
    webcam => [ qw(cpia_usb cyber2000fb ibmcam konicawc mod_quickcam ov511 ov511-alt ov518_decomp ovfx2 pwc quickcam se401 stv680 sn9c102 ultracam usbvideo usbvision vicam w9968cf) ],
  },

  # USB input stuff get automagically loaded by hotplug and thus
  # magically work through /dev/input/mice multiplexing:
  input => {
      joystick => [
          qw(iforce xpad),
          # there're more drivers in drivers/input/joystick but they support non USB or PCI devices
          # and thus cannot be detected but by slow (and maybe dangerous?) load_category:
          qw(a3d adi analog cobra db9 gamecon gf2k grip grip_mp guillemot interact),
          qw(joydump magellan sidewinder spaceball spaceorb stinger tmdc turbografx warrior)
      ],
      remote => [ qw(ati_remote) ],
      # USB tablets and touchscreens:
      tablet => [ qw(acecad aiptek wacom kbtab) ],
      touchscreen => [ qw(ads7846_ts gunze hp680_ts_input itmtouch mk712 mtouch mtouchusb touchkitusb) ],
  },

  various => 
  # just here for classification, unused categories (nor auto-detect, nor load_thiskind)
  {
    raid => [
      qw(dm-crypt dm-mirror dm-mod linear lvm-mod multipath raid0 raid1 raid10 raid5),
    ],
    mouse => [
      qw(atixlmouse busmouse generic_serial inport logibm logibusmouse msbusmouse pcips2 qpmouse synclinkmp),
      if_(arch() =~ /ppc/, 'macserial'),
      qw(hid mousedev usbhid usbmouse),
    ],
    char => [
      if_(arch() =~ /ia64/, qw(efivars)),
      qw(applicom n_r3964 nvram pc110pad ppdev),
      qw(wdt_pci i810-tco sx), #- what are these???
    ],
    crypto => [
      qw(amd768_rng amd7xx_tco i810_rng hw_random leedslite padlock),
    ],
    laptop => [
      qw(i8k sonypi toshiba),
    ],
    serial => [
      qw(8250_pci 8250 epca esp isicom istallion moxa mxser stallion sx synclink synclinkmp),
    ],
    other => [
      qw(defxx i810fb ide-floppy ide-scsi ide-tape loop lp nbd sg st),
      qw(parport_pc parport_serial),
      qw(btaudio),

      arch() =~ /i.86/ ? 'aes-i586' : 'aes',
      if_(arch() =~ /sparc/, 'openprom'),
      
      qw(evdev), qw(usblp printer), 'floppy',

      #- these need checking
      qw(rrunner meye),
    ],
    agpgart => [
      if_(arch() =~ /alpha/, qw(alpha-agp)),
      if_(arch() =~ /ia64/, qw(hp-agp i460-agp)),
      if_(arch() =~ /ppc/, qw(uninorth-agp)),

      qw(ali-agp amd64-agp amd-k7-agp ati-agp efficeon-agp intel-agp),
	 qw(k7-agp mch-agp nvidia-agp sis-agp sworks-agp via-agp),
    ],
  },
);

my %dependencies;

sub load_dependencies {
    my ($file) = @_;

    %dependencies = map {
	s![^ ]*/!!g;
	s!\.ko!!g;
	s!\.gz!!g;
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
	my @sub = $t2s eq '*' ? keys %{$l{$t1}} : split('\|', $t2s);
	map {
	    my $l = $l{$t1}{$_} or die "bad category $t1/$_\n" . backtrace();
	    @$l;
	} @sub;
    } split(' ', $_[0]);
}

sub all_modules() {
    map { @$_ } map { values %$_ } values %l;
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

sub ethernet_categories() {
    'network/main|gigabit|pcmcia|tokenring|usb|wireless|firewire';
}

sub sub_categories {
    my ($t1) = @_;
    keys %{$l{$t1}};
}

sub kernel_is_26 { $_[0] =~ /^2\.6/ }

sub module_extension { kernel_is_26($_[0]) ? 'ko' : 'o' }

1;
