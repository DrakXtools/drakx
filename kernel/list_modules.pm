package list_modules;

use MDK::Common;

our @ISA = qw(Exporter);
our @EXPORT = qw(load_dependencies dependencies_closure category2modules module2category sub_categories);

# the categories have 2 purposes
# - choosing modules to include on stage1's (cf update_kernel and mdk-stage1/pci-resource/update-pci-ids.pl)
# - performing a load_category or probe_category (detect_devices.pm and many files in perl-install)

our %l = (
  ################################################################################
  network => 
  {
    atm => [ qw(ambassador eni firestream fore_200e he horizon idt77252 iphase lanai nicstar solos-pci zatm) ],
    main => [
        qw(3c501 3c503 3c505 3c507 3c509 3c515 3c990 3c990fx),
        qw(82596 ac3200 acenic aironet4500_card altera_tse amd8111e at1700 atl2 atp),
        qw(bcm4400 cassini cs89x0 cx82310_eth de600 de620),
        qw(depca dmfe e2100 ec_bhf eepro eexpress enic eth16i),
        qw(ewrk3 hp hp-plus hp100 i40e i40evf),
        qw(iph5526), #- fibre channel
        qw(i40evf jme lance ne ni5010 ni52 ni65 nvnet),
        qw(prism2_plx qlge r6040 rcpci rhineget),
        qw(sb1000 sc92031 sh_eth smc-ultra smsc911x smc9194 smsc9420 smsc95xx),
        qw(tc35815 tlan uli526x vmxnet3),
        qw(b44 com20020-pci de2104x),
        qw(defxx), # most unused
        qw(dgrs e100 eepro100 epic100 fealnx hamachi natsemi),
        qw(ne2k-pci pcnet32 plip sis900 skfp starfire tulip),
        qw(typhoon via-rhine winbond-840 xgene-enet forcedeth),
        qw(sungem sunhme), # drivers for ultrasparc, but compiled in ix86 kernels...
      qw(3c59x 8139too 8139cp cpmac niu sundance), #rtl8139
      # add all phys
      qw(amd at803x bcm7xxx bcm87xx broadcom cicada davicom et1011c icplus lxt marvell mdio-bitbang mdio-gpiomicrel),
      qw(national qsemi r8152 r815x realtek smsc spi_ks8995 ste10Xp vitesse),
    ],
    firewire => [ qw(eth1394 pcilynx) ],
    gigabit => [
      qw(alx atl1 atl1c atl1e at91_ether ax88179_178a be2net bna bnx2 bnx2x cxgb cxgb3 cxgb4 dl2k e1000 e1000e et131x igb ipg ixgb ixgbe),
      qw(macb mvmdio myri_sbus myri10ge netxen_nic ns83820 pch_gbe qla3xxx r8169 s2io samsung-sxgbe sfc sxg_nic),
      qw(sis190 sk98lin skge sky2 slicoss spidernet stmmac tehuti tg3 via-velocity vxge yellowfin),
      qw(bcm5820 bcm5700), #- encrypted
    ],

    raw => [
      qw(ppp_generic ppp_async ppp_deflate bsd_comp),
    ],
    pcmcia => [ 
      qw(3c574_cs 3c589_cs axnet_cs fmvj18x_cs),
      qw(ibmtr_cs libertas_cs nmclan_cs pcnet_cs smc91c92_cs),
      qw(xirc2ps_cs xircom_cb xircom_tulip_cb),
    ],
   #- generic NIC detection for USB seems broken (class, subclass, 
   #- protocol reported are not accurate) so we match network adapters against
   #- known drivers :-(
    usb => [ 
      qw(asix catc cdc_ether cdc_mbim dm9601 huawei_cdc_ncm kaweth mcs7830 pegasus rtl8150 smsc75xx smsc95xx usbnet),
    ],
    wireless => [
      qw(acx-pci acx-usb adm8211 agnx airo airo_cs aironet4500_cs),
      qw(aironet_cs ar5523 ar9170usb arlan arusb_lnx ath10k_pci ath5k ath6kl ath6kl_usb ath9k ath9k_htc), # at76c50x_usb lacks firmware
      qw(ath_pci atmel_cs atmel_pci b43 b43legacy bcm43xx bcm_wimax bcma brcm80211 brcmsmac brcmfmac carl9170 com20020_cs),
      qw(dyc_ar5 hostap_cs hostap_pci hostap_plx i2400m_usb ipw2100),
      qw(ipw2200 ipw3945 iwl3945 iwl4965 iwlagn iwldvm iwlmvm iwlwifi madwifi_pci),
      qw(mwifiex_usb mwl8k ndiswrapper netwave_cs orinoco orinoco_cs),
      qw(orinoco_nortel orinoco_pci orinoco_plx orinoco_tmd orinoco_usb p54pci),
      qw(p54usb prism2_cs prism2_pci prism2_usb prism54 qmi_wwan r8180),
      qw(r8187se rtl8188ee r8192_pci r8192s_usb r8192u_usb r8712u ray_cs rndis_wlan rsi_sdio rt2400 rt2400pci rt2500),
      qw(rt2500pci rt2500usb rt2570 rt2800pci rt2800usb rt2860 rt2860sta rt2870),
      qw(rt3070sta rt61 rt61pci rt73 rt73usb rtl8180 rtl8187 rtl8187se r8188eu r8723au rtl8821ae rtl_pci rtl_usb rtusb),
      qw(rtl8192se rtl8192cu rtl8192de rtl8723ae rtl8723be rtl8821ae spectrum_cs sr9700 sr9800 ssb usb8xxx usbvnet_rfmd vt6655_stage vt6656_stage vt_ar5k w35und),
      qw(wavelan_cs wcn36xx wl wl3501_cs wvlan_cs zd1201 zd1211rw),
    ],
    isdn => [
      qw(avmfritz c4 cdc-acm b1pci divas hfc4s8s_l1 hfc_usb hfc4s8s_l1 hisax hisax_st5481 hisax_fcpcipnp hysdn sedlfax t1pci tpam w6692pci),
      qw(avmfritz hfcpci hfcmulti hfcsusb mISDNinfineon netjet), # mISDN
      qw(fcpci fcdsl fcdsl fcdsl2 fcdslsl fcdslslusb fcdslusb fcdslusba fcusb fcusb2 fxusb fxusb_CZ)
    ],
    cellular => [
      qw(hso nozomi option sierra),
    ],
    modem => [
      qw(ltmodem mwave sm56 ft1000),
    ],
    slmodem => [
      qw(slamr slusb snd-ali5451 snd-atiixp-modem snd-intel8x0m snd-via82xx-modem),
    ],
    wan => [ qw(c101 cosa cyclomx cycx_drv dlci dscc4 farsync hdlc hostess_sv11 lapbether lmc n2 pc300 pci200syn sbni sdla sdladrv sealevel syncppp wanxl z85230) ],
    usb_dsl => [ qw(cxacru speedtch ueagle-atm usbatm xusbatm) ],
    virtual => [ qw(hv_netvsc vboxdrv virtio_net xen-netfront) ],
  },

  ################################################################################
  disk => 
  {
    # ide drivers compiled as modules:
    ide => [
        qw(aec62xx ali14xx alim15x3 amd74xx atiixp cmd64x cy82c693 cs5520 cs5530 cs5535 cs5536),
        qw(delkin_cb dtc2278 hpt34x hpt366 ns87415 ht6560b it8172 it8213 it821x jmicron),
        qw(opti621 pdc202xx_new pdc202xx_old piix qd65xx rz1000 sc1200 serverworks siimage sis5513 slc90e66),
        qw(tc86c001 triflex trm290 tx4938ide tx4939ide umc8672 via82cxxx ide-pci-generic ide-generic),
    ],
    scsi => [
	'53c7,8xx',
        qw(a100u2w advansys aha152x aha1542 aha1740 AM53C974 atp870u),
        qw(be2iscsi bfa BusLogic dc395x dc395x_trm dmx3191d dtc eata eata_dma),
        qw(eata_pio fdomain g_NCR5380 in2000 initio mpt2sas mpt3sas mvsas NCR53c406a),
        qw(nsp32 pas16 pci2220i pm80xx pm8001 psi240i qla1280 qla2x00 qla2xxx),
        qw(qlogicfas qlogicfc rsxx seagate shasta skd sim710 stex sym53c416),
        qw(t128 tmscsim u14-34f ultrastor vmw_pvscsi wd7000),
      qw(aic7xxx aic7xxx_old aic79xx pci2000 qlogicfas408 sym53c8xx lpfc lpfcdd), # ncr53c8xx
    ],
    sata => [
      # note that ata_piix manage RAID devices on ICH6R
      qw(ahci aic94xx ata_adma ata_piix pata_pdc2027x pdc_adma),
      qw(sata_fsl sata_inic162x sata_mv sata_nv sata_promise),
      qw(sata_qstor sata_rcar sata_sil sata_sil24 sata_sis sata_svw sata_sx4 sata_uli sata_via sata_vsc sx8),
      # new drivers: old ide drivers ported over libata:
      qw(ata_generic mv-ahci pata_ali pata_amd pata_artop pata_atiixp pata_atp867x),
      qw(pata_bf54x pata_cmd640 pata_cmd64x pata_cs5520 pata_cs5530),
      qw(pata_cs5535 pata_cs5536 pata_cypress pata_efar pata_hpt366),
      qw(pata_hpt37x pata_hpt3x2n pata_hpt3x3 pata_isapnp pata_it8172),
      qw(pata_it8213 pata_it821x pata_jmicron pata_legacy pata_marvell),
      qw(pata_mpiix pata_netcell pata_ninja32 pata_ns87410),
      qw(pata_ns87415 pata_oldpiix pata_opti pata_optidma),
      qw(pata_pdc2027x pata_pdc202xx_old pata_piccolo pata_platform pata_qdi),
      qw(pata_radisys pata_rdc pata_rz1000 pata_sc1200 pata_sch),
      qw(pata_serverworks pata_sil680 pata_sis pata_sl82c105),
      qw(pata_triflex pata_via pata_winbond),
      qw(pata_acpi),
    ],
    hardware_raid => [
        # 3w-xxxx drives ATA-RAID, 3w-9xxx and arcmsr drive SATA-RAID
        qw(3w-9xxx 3w-sas 3w-xxxx a320raid aacraid arcmsr cciss cpqarray),
        qw(cpqfc csiostor DAC960 dpt_i2o esas2r gdth hpsa hptiop i2o_block imm ipr ips isci),
        qw(it8212 it821x iteraid megaide megaraid megaraid_mbox),
        qw(megaraid_sas mptfc mptsas mptscsih mptspi pdc-ultra pmcraid ppa),
        qw(qla2100 qla2200 qla2300 qla2322 qla4xxx qla6312 qla6322),
    ],
    video => [ qw(vmwgfx cirrusfb radeonfb kyrofb i740fb matroxfb_crct2 matroxfb_DAC1064 matroxfb_g450 matroxfb_misc matroxfb_accel matroxfb_Ti3026 matroxfb_base aty128fb vga16fb vt8236fb sstfb s3fb rivafb  mb862xfb nvidiafb fb_ddc udlfb tdfxfb uvesafb viafb tridentfb savagefb cfag1286bfb) ],
    virtual => [ qw(hv_storvsc virtio_blk virtio_scsi xenblk xen-blkfront) ],
    pcmcia => [ qw(aha152x_cs fdomain_cs nsp_cs qlogic_cs ide-cs pata_pcmcia sym53c500_cs) ],
    raw => [ qw(ide-gd_mod sd_mod) ],
    usb => [ qw(keucr uas ums-alauda ums-cypress ums-datafab ums-eneub6250 ums-freecom ums-isd200),
	     qw(ums-jumpshot ums-karma ums-onetouch ums-realtek ums-sddr09 ums-sddr55 ums-usbat usb-storage) ],
    firewire => [ qw(sbp2) ],
    cdrom => [ qw(ide-cd_mod sr_mod) ],
    card_reader => [ qw(rts5208 sdhci sdhci-pci tifm_sd tifm_7xx1) ],
  },

  ################################################################################

  bus => 
  {
    usb => [ qw(bcma-hcd c67x00 dwc3 dwc3-pci ehci-hcd ehci-pci ehci-platform ehci-tegra fhci fusbh200-hcd hwa-hc
		imx21-hcd isp116x-hcd isp1362-hcd isp1760 ohci-hcd ohci-pci ohci-platform oxu210hp-hcd
		r8a66597-hcd renesas-usbhs sl811_cs sl811-hcd ssb-hcd u132-hcd
		uhci-hcd usb-ohci usb-uhci whci-hcd xhci-hcd) ],
    bluetooth => [ qw(ath3k bcm203x bfusb bluecard_cs bpa10x bt3c_cs btusb dtl1_cs) ],
    firewire => [ qw(ohci1394) ],
    i2c => [
      qw(i2c-ali1535 i2c-ali1563 i2c-ali15x3 i2c-amd756 i2c-amd8111 i2c-i801 i2c-i810 i2c-nforce2),
      qw(i2c-piix4 i2c-prosavage i2c-savage4 i2c-sis5595 i2c-sis630 i2c-sis96x i2c-via i2c-viapro i2c-voodoo3),
      qw(i2c-hydra i2c-ibm_iic i2c-mpc),
    ],
    pcmcia => [
      qw(au1x00_ss i82365 i82092 pd6729 tcic vrc4171_card vrc4173_cardu yenta_socket), # cb_enabler
    ],
    hid => [ qw(ff-memless hid hid-a4tech hid-apple hid-appleir hid-aureal hid-axff hid-belkin
	    hid-cherry hid-chicony hid-cp2112 hid-cypress hid-dr hid-drff hid-elecom hid-elo hid-emsff
	    hid-ezkey hid-gaff hid-generic hid-gt683r hid-gyration hid-holtek-kbd hid-holtekff hid-holtek-mouse hid-huion
	    hid-hyperv hid-icade hid-kensington hid-keytouch hid-kye hid-lcpower hid-lenovo hid-lenovo-tpkbd
	    hid-logitech hid-logitech-dj hid-magicmouse hid-microsoft hid-monterey
	    hid-multilaser hid-multitouch hid-ntrig hid-ortek hid-petalynx hid-picolcd
	    hid-pl hid-primax hid-prodikeys hid-roccat hid-roccat-arvo hid-roccat-common
	    hid-roccat-isku hid-roccat-kone hid-roccat-koneplus hid-roccat-konepure hid-roccat-kovaplus hid-roccat-lua
	    hid-roccat-pyra hid-roccat-ryos hid-roccat-savu hid-saitek hid-samsung hid-sensor-hub hid-sjoy hid-sony
	    hid-speedlink hid-steelseries hid-sunplus hid-tivo hid-thingm hid-tmff hid-topseed hid-twinhan
	    hid-uclogic hid-wacom hid-waltop hid-wiimote hid-xinmo hid-zpff hid-zydacron wacom) ],

   #serial_cs
   #ftl_cs 3c575_cb apa1480_cb epic_cb serial_cb tulip_cb iflash2+_mtd iflash2_mtd
   #cb_enabler
  },

  fs => 
  {
    network => [ qw(af_packet nfs nfsv2 nfsv3 nfsv4 smbfs) ],
    cdrom => [ qw(isofs) ],
    loopback => [ qw(isofs loop squashfs) ],
    local => [
      qw(btrfs ext3 ext4 jfs nilfs2 ntfs reiserfs vfat xfs),
    ],
    various => [ qw(efivarfs overlayfs romfs ufs fuse) ],

  },

  ################################################################################
  multimedia => 
  {
    sound => [
          qw(ad1816 ad1848 ad1889 ali5455 audigy audio awe_wave cmpci cs4232 cs4281 cs46xx cx88-alsa),
          qw(emu10k1 es1370 es1371 esssolo1 forte gus i810_audio ice1712 kahlua mad16 maestro),
          qw(maestro3 mpu401 msnd_pinnacle nm256_audio nvaudio opl3 opl3sa opl3sa2 pas2 pss),
          qw(rme96xx sam9407 sb sgalaxy snd-ad1816a snd-ad1848 snd-ad1889 snd-ali5451 snd-als100 snd-als300),
          qw(snd-als4000 snd-atiixp snd-au8810 snd-au8820 snd-au8830 snd-audigyls snd-aw2 snd-azt2316 snd-azt2320 snd-azt3328 snd-azx),
          qw(snd-asihpi snd-at73c213 snd-bcd2000 snd-bebob snd-bt87x snd-ca0106 snd-cmi8330 snd-cmi8788 snd-cmipci),
          qw(snd-cs4231 snd-cs4232 snd-cs4236 snd-cs4281 snd-cs46xx snd-cs5530 snd-cs5535audio),
          qw(snd_ctxfi),
          qw(snd-darla20 snd-darla24 snd-dice snd-dt019x snd-echo3g snd-emu10k1 snd-emu10k1x),
          qw(snd-ens1370 snd-ens1371 snd-es1688 snd-es18xx snd-es1938 snd-es1968 snd-es968),
          qw(snd-fireworks snd-fm801 snd-gina20 snd-gina24 snd-gina3g),
          qw(snd-gusclassic snd-gusextreme snd-gusmax),
          qw(snd-hda-intel snd-hdsp snd-hdspm snd-ice1712 snd-ice1724),
          qw(snd-indi snd-indigo snd-indigodj snd-indigodjx snd-indigoio snd-indigoiox snd-intel8x0 snd-interwave),
          qw(snd-interwave-stb snd-korg1212 snd-layla20 snd-layla24 snd-layla3g snd-lola snd-lx6464es),
          qw(snd-maestro3 snd-mia snd-mixart snd-mona snd-mpu401 snd-nm256),
          qw(snd-opl3sa2 snd-opti92x-ad1848 snd-opti92x-cs4231 snd-opti93x snd-oxygen snd-pcsp snd-pcxhr snd-riptide snd-rme32),
          qw(snd-rme96 snd-rme9652 snd-sb16 snd-sb8 snd-sbawe snd-sc6000 snd-sgalaxy snd-sis7019 snd-sonicvibes),
          qw(snd-sscape snd-trident snd-via82xx snd-virtuoso snd-vx222 snd-vxp440 snd-vxpocket snd-wavefront),
          qw(snd-ymfpci sonicvibes sscape trident via82cxxx_audio wavefront ymfpci),
  ],
    tv => [ qw(bt878 bttv cx23885 cx25821 cx8800 cx8802 cx88-blackbird dpc7146),
            qw(ivtv mxb pvrusb2 saa7134 saa7164 zr36067) ],
    dvb => [
        qw(b2c2-flexcop-pci b2c2-flexcop-usb budget budget-av),
        qw(budget-ci cinergyT2 dm1105 dvb-dibusb dvb-ttpci),
        qw(dvb-ttusb-budget dvb-usb-a800 dvb-usb-af9015 dvb-usb-ce6230),
        qw(dvb-usb-cinergyT2 dvb-usb-cxusb dvb-usb-dib0700),
        qw(dvb-usb-dibusb-mb dvb-usb-dibusb-mc dvb-usb-digitv),
        qw(dvb-usb-dtt200u dvb-usb-dtv5100 dvb-usb-ec168 dvb-usb-friio dvb-usb-gp8ps),
        qw(dvb-usb-nova-t-usb2 dvb-usb-ttusb2 dvb-usb-umt-010),
        qw(dvb-usb-vp702x dvb-usb-vp7045 earth-pt1 firedtv hexium_gemini),
        qw(hexium_orion pluto2 skystar2 smsusb ttusb_dec),
    ],
    photo => [ qw(dc2xx mdc800) ],
    radio => [ qw(radio-gemtek-pci radio-keene radio-maestro radio-ma901
	    radio-maxiradio radio-miropcm20 radio-mr800 radio-raremono radio-shark
	    radio-usb-si470x shark2) ],
    scanner => [ qw(scanner microtek) ],
    firewire => [ qw(snd-firewire-speakers snd-isight snd-scs1x) ],
    gameport => [ qw(cs461x ns558 emu10k1-gp fm801-gp lightning ns558 vortex) ],
    usb_sound => [ qw(audio dabusb dsbr100 snd-usb-audio snd-usb-6fire snd-usb-caiaq snd-usb-hiface snd-usb-usx2y usb-midi) ],
    webcam => [
        qw(cafe_ccic cpia2 cpia_usb cyber2000fb em28xx et61x251 gspca),
        qw(gspca_benq gspca_conex gspca_cpia1 gspca_etoms
        gspca_finepix gspca_gl860 gspca_jeilinj gspca_jl2005bcd
        gspca_kinect gspca_konica gspca_m5602 gspca_mars
        gspca_mr97310a gspca_nw80x gspca_ov519 gspca_ov534
        gspca_ov534_9 gspca_pac207 gspca_pac7302 gspca_pac7311
        gspca_se401 gspca_sn9c2028 gspca_sn9c20x gspca_sonixb
        gspca_sonixj gspca_spca1528 gspca_spca500 gspca_spca501
        gspca_spca505 gspca_spca506 gspca_spca508 gspca_spca561
        gspca_sq905 gspca_sq905c gspca_sq930x gspca_stk014 gspca_stk1135
        gspca_stv0680 gspca_stv06xx gspca_sunplus gspca_t613
        gspca_topro gspca_tv8532 gspca_vc032x gspca_vicam
        gspca_xirlink_cit gspca_zc3xx),
        qw(ibmcam konicawc mod_quickcam ov511 ov511-alt ov518_decomp),
        qw(ov51x-jpeg ovfx2 pwc qc-usb-messenger quickcam quickcam_messenger),
        # both STV06xx & stv06xx b/c drivers/media/video/gspca/stv06xx/stv06xx.h
        # wrongly use upcase letters:
        qw(se401 sn9c102 STV06xx stv06xx stv680 tcm825x ultracam),
        qw(usbvideo usbvision vicam w9968cf zc0301 zc3xx),
    ],
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
      tablet => [ qw(acecad aiptek wacom wacom_serial4 kbtab) ],
      touchscreen => [ qw(ads7846_ts gunze hp680_ts_input itmtouch mk712 mtouch sur40 usbtouchscreen) ],
  },

  various => 
  # just here for classification, unused categories (nor auto-detect, nor load_thiskind)
  {
    raid => [
      qw(dm-crypt dm-log dm-log-userspace dm-mirror dm-mod dm-multipath dm-queue-length dm-raid dm-region-hash dm-round-robin),
      qw(dm-service-time dm-snapshot dm-zero faulty linear lvm-mod md-mod multipath md-mod raid0 raid10 raid1 raid456),
      # needed by raid456 and dm-raid 456 target
      qw(async_memcpy async_pq async_raid6_recov async_tx async_xor raid6_pq xor),
    ],
    mouse => [
      qw(atixlmouse busmouse generic_serial inport ioc3_serial logibm logibusmouse msbusmouse pcips2 qpmouse synclinkmp),
      qw(mousedev usbhid usbmouse synaptics_usb),
    ],
    char => [
      if_(arch() =~ /ia64/, qw(efivars)),
      qw(applicom n_r3964 nvram pc110pad ppdev),
      qw(wdt_pci i810-tco sx), #- what are these???
    ],
    crypto => [
      qw(aes-i586 aes-x86_64 aes_generic aesni_intel amd768_rng amd7xx_tco cbc cryptd hw_random i810_rng leedslite padlock sha256_generic xts),
    ],
    laptop => [
      qw(i8k sonypi toshiba),
    ],
    serial => [
      qw(8250_pci 8250 epca esp isicom istallion jsm moxa mxser mxser_new stallion sx synclink synclinkmp),
    ],
    other => [
      qw(defxx ide-floppy ide-tape loop lp nbd sg st),
      qw(parport_pc parport_serial),
      qw(btaudio),
      qw(mmc_block sdhci-acpi), # eMMC

      'cryptoloop',

      qw(crc32c crc32c-intel),
      
      qw(evdev), qw(usblp printer), 'floppy', 'microcode', 'usb_common',
      qw(acpi_cpufreq processor),

      #- these need checking
      qw(rrunner meye),

      qw(virtio virtio_balloon virtio_pci virtio_ring vhost_scsi hyperv-keyboard),
      qw(mei pch_phub),
      qw(vmvgfx),
    ],
    agpgart => [
      qw(ali-agp amd64-agp amd-k7-agp ati-agp efficeon-agp intel-agp),
	 qw(k7-agp mch-agp nvidia-agp sis-agp sworks-agp via-agp),
    ],
  },
);

my %moddeps;

sub load_dependencies {
    my ($file, $o_root) = @_;

    %moddeps = ();
    foreach (cat_($o_root . $file)) {
	my ($m, $d) = split ':';
	my $path = $m;
	my ($filename, @fdeps) = map {
	    s![^ ]*/!!g;
	    s!\.ko!!g;
	    s!\.[gx]z!!g;
	    $_;
	} $m, split(' ', $d);

	my ($modname, @deps) = map { filename2modname($_) } $filename, @fdeps;
	$moddeps{$modname}{deps} = \@deps;
	$moddeps{$modname}{filename} = $filename;
	if (!begins_with($path, "/")) {
		#- with newer module-init-tools, modules.dep can contain
		#- relative paths
		$path = dirname($file) . '/' . $path;
	}
 	$moddeps{$modname}{path} = $path;
    }
}

sub dependencies_closure {
    my @l = map { dependencies_closure($_) } @{exists $moddeps{$_[0]} && $moddeps{$_[0]}{deps} || []};
    (@l, $_[0]);
}

sub filename2modname {
    my ($modname) = @_;
    $modname =~ s/-/_/g;
    $modname;
}

sub load_default_moddeps() {
    require c;
    load_dependencies('/lib/modules/' . c::kernel_version() . '/modules.dep');
}

sub modname2filename {
    load_default_moddeps() if !%moddeps;
    $moddeps{$_[0]}{filename};
}

sub modname2path {
    load_default_moddeps() if !%moddeps;
    $moddeps{$_[0]}{path};
}

sub category2modules {
    map {
	my ($t1, $t2s) = m|(.*)/(.*)|;
	my @sub = $t2s eq '*' ? keys %{$l{$t1}} : split('\|', $t2s);
	map {
	    my $l = $l{$t1}{$_} or die "bad category $t1/$_\n" . backtrace();
	    map { filename2modname($_) } @$l;
	} @sub;
    } split(' ', $_[0]);
}

sub all_modules() {
    map { @$_ } map { values %$_ } values %l;
}

sub module2category {
    my ($module) = @_;
    $module = filename2modname($module);
    foreach my $t1 (keys %l) {
	my $h = $l{$t1};
	foreach my $t2 (keys %$h) {
	  $module eq filename2modname($_) and return "$t1/$t2" foreach @{$h->{$t2}};
      }
    }
    return;
}

sub ethernet_categories() {
    'network/main|gigabit|pcmcia|usb|wireless|firewire';
}

sub sub_categories {
    my ($t1) = @_;
    keys %{$l{$t1}};
}

1;
