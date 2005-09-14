package network::isdn_consts; # $Id$
use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(@isdndata @isdn_capi);

our @isdndata =
  (
   { description => "Teles|16.0",               #1 irq, mem, io
    driver => 'hisax',
    type => '1',
    irq => '5',
    mem => '0xd000',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Teles|8.0", #2 irq, mem
    driver => 'hisax',
    type => '2',
    irq => '9',
    mem => '0xd800',
    card => 'isa',
   },
   { description => "Teles|16.3 (ISA non PnP)", #3 irq, io
    driver => 'hisax',
    type => '3',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Teles|16.3c (ISA PnP)", #14 irq, io
    driver => 'hisax',
    type => '14',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Creatix/Teles|Generic (ISA PnP)",	#4 irq, io0 (ISAC), io1 (HSCX)
    driver => 'hisax',
    type => '4',
    irq => '5',
    io0 => '0x0000',
    io1 => '0x0000',
    card => 'isa',
   },
   { description => "Teles|generic", #21 no parameter
    driver => 'hisax',
    type => '21',
    card => 'pci',
   },
   { description => "Teles|16.3 (PCMCIA)",	#8 irq, io
    driver => 'hisax',
    type => '8',
    irq => '',
    io => '0x',
    card => 'isa',
   },
   { description => "Teles|S0Box", #25 irq, io (of the used lpt port)
    driver => 'hisax',
    type => '25',
    irq => '7',
    io => '0x378',
    card => 'isa',
   },
   { description => "ELSA|PCC/PCF cards", #6 io or nothing for autodetect (the io is required only if you have n>1 ELSA|card)
    driver => 'hisax',
    type => '6',
    io => "",
    card => 'isa',
   },
   { description => "ELSA|Quickstep 1000", #7 irq, io  (from isapnp setup)
    driver => 'hisax',
    type => '7',
    irq => '5',
    io => '0x300',
    card => 'isa',
   },
   { description => "ELSA|Quickstep 1000", #18 no parameter
    driver => 'hisax',
    type => '18',
    card => 'pci',
   },
   { description => "ELSA|Quickstep 3000", #18 no parameter
    driver => 'hisax',
    type => '18',
    card => 'pci',
   },
   { description => "ELSA|generic (PCMCIA)", #10 irq, io  (set with card manager)
    driver => 'hisax',
    type => '10',
    irq => '',
    io => '0x',
    card => 'isa',
   },
   { description => "ELSA|MicroLink (PCMCIA)", #10 irq, io  (set with card manager)
    driver => 'elsa_cs',
    card => 'isa',
   },
   { description => "ITK|ix1-micro Rev.2", #9 irq, io
    driver => 'hisax',
    type => '9',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Eicon.Diehl|Diva (ISA PnP)", #11 irq, io
    driver => 'hisax',
    type => '11',
    irq => '9',
    io => '0x180',
    card => 'isa',
   },
   { description => "Eicon.Diehl|Diva 20", #11 no parameter
    driver => 'hisax',
    type => '11',
    card => 'pci',
   },
   { description => "Eicon.Diehl|Diva 20PRO", #11 no parameter
    driver => 'hisax',
    type => '11',
    card => 'pci',
   },
   { description => "Eicon.Diehl|Diva 20_U", #11 no parameter
    driver => 'hisax',
    type => '11',
    card => 'pci',
   },
   { description => "Eicon.Diehl|Diva 20PRO_U", #11 no parameter
    driver => 'hisax',
    type => '11',
    card => 'pci',
   },
   { description => "ASUS|COM ISDNLink", #12 irq, io  (from isapnp setup)
    driver => 'hisax',
    type => '12',
    irq => '5',
    io => '0x200',
    card => 'isa',
   },
   { description => "ASUS|COM ISDNLink",
    driver => 'hisax',
    type => '35',
    card => 'pci',
   },
   { description => "DynaLink|Any",
    driver => 'hisax',
    type => '12',
    card => 'pci',
   },
   { description => "DynaLink|IS64PH, ASUSCOM", #36
    driver => 'hisax',
    type => '36',
    card => 'pci',
   },
   { description => "HFC|2BS0 based cards", #13 irq, io
    driver => 'hisax',
    type => '13',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "HFC|2BDS0", #35 none
    driver => 'hisax',
    type => '35',
    card => 'pci',
   },
   { description => "HFC|2BDS0 S+, SP (PCMCIA)", #37 irq,io (pcmcia must be set with cardmgr)
    driver => 'hisax',
    type => '37',
    card => 'isa',
   },
   { description => "Sedlbauer|Speed Card", #15 irq, io
    driver => 'hisax',
    type => '15',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Sedlbauer|PC/104", #15 irq, io
    driver => 'hisax',
    type => '15',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Sedlbauer|Speed Card", #15 no parameter
    driver => 'hisax',
    type => '15',
    card => 'pci',
   },
   { description => "Sedlbauer|Speed Star (PCMCIA)", #22 irq, io (set with card manager)
    driver => 'sedlbauer_cs',
    card => 'isa',
   },
   { description => "Sedlbauer|Speed Fax+ (ISA Pnp)", #28 irq, io (from isapnp setup)
    driver => 'hisax',
    type => '28',
    irq => '9',
    io => '0xd80',
    card => 'isa',
    firmware => '/usr/lib/isdn/ISAR.BIN',
   },
   { description => "Sedlbauer|Speed Fax+", #28 no parameter
    driver => 'hisax',
    type => '28',
    card => 'pci',
    firmware => '/usr/lib/isdn/ISAR.BIN',
   },
   { description => "USR|Sportster internal", #16 irq, io
    driver => 'hisax',
    type => '16',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Generic|MIC card",	#17 irq, io
    driver => 'hisax',
    type => '17',
    irq => '9',
    io => '0xd80',
    card => 'isa',
   },
   { description => "Compaq|ISDN S0 card", #19 irq, io0, io1, io (from isapnp setup io=IO2)
    driver => 'hisax',
    type => '19',
    irq => '5',
    io => '0x0000',
    io0 => '0x0000',
    io1 => '0x0000',
    card => 'isa',
   },
   { description => "Generic|NETjet card", #20 no parameter
    driver => 'hisax',
    type => '20',
    card => 'pci',
   },
   { description => "Dr. Neuhaus|Niccy (ISA PnP)", #24 irq, io0, io1 (from isapnp setup)
    driver => 'hisax',
    type => '24',
    irq => '5',
    io0 => '0x0000',
    io1 => '0x0000',
    card => 'isa',
   },
   { description => "Dr. Neuhaus|Niccy", ##24 no parameter
    driver => 'hisax',
    type => '24',
    card => 'pci',
   },
   { description => "AVM|A1 (Fritz) (ISA non PnP)", #5 irq, io
    driver => 'hisax',
    type => '5',
    irq => '10',
    io => '0x300',
    card => 'isa',
   },
   { description => "AVM|ISA Pnp generic", #27 irq, io  (from isapnp setup)
    driver => 'hisax',
    type => '27',
    irq => '5',
    io => '0x300',
    card => 'isa',
   },
   { description => "AVM|A1 (Fritz) (PCMCIA)", #26 irq, io (set with card manager)
    driver => 'hisax',
    type => '26',
    irq => '',
    card => 'isa',
   },
   { description => "AVM|PCI (Fritz!)", #27 no parameter
    driver => 'hisax',
    type => '27',
    card => 'pci',
   },
   { description => "AVM|B1",
    driver => 'b1pci',
    card => 'pci',
   },
   { description => "Siemens|I-Surf 1.0 (ISA Pnp)", #29 irq, io, memory (from isapnp setup)   
    driver => 'hisax',
    type => '29',
    irq => '9',
    io => '0xd80',
    mem => '0xd000',
    card => 'isa',
   },
   { description => "ACER|P10 (ISA Pnp)",	#30 irq, io (from isapnp setup)   
    driver => 'hisax',
    type => '30',
    irq => '5',
    io => '0x300',
    card => 'isa',
   },
   { description => "HST|Saphir (ISA Pnp)", #31 irq, io
    driver => 'hisax',
    type => '31',
    irq => '5',
    io => '0x300',
    card => 'isa',
   },
   { description => "Telekom|A4T", #32 none
    driver => 'hisax',
    type => '32',
    card => 'pci',
   },
   { description => "Scitel|Quadro", #33 subcontroller (4*S0, subctrl 1...4)
    driver => 'hisax',
    type => '33',
    card => 'pci',
   },
   { description => "Gazel|ISDN cards", #34 irq,io
    driver => 'hisax',
    type => '34',
    irq => '5',
    io => '0x300',
    card => 'isa',
   },
   { description => "Gazel|Gazel ISDN cards", #34 none
    driver => 'hisax',
    type => '34',
    card => 'pci',
   },
   { description => "Winbond|W6692 and Winbond based cards", #36 none
    driver => 'hisax',
    type => '36',
    card => 'pci',
   },
   { description => "BeWAN|R834",
    driver => 'hisax_st5481',
    type => '99',
    card => 'usb',
   },
   { description => "Gazel|128",
    driver => 'hisax_st5481',
    type => '99',
    card => 'usb',
   },
  );

#- cards than can be used with capi drivers
our @isdn_capi =
  (
   {
    vendor => 0x1131,
    id => 0x5402,
    description => 'AVM Audiovisuelles|Fritz DSL ISDN/DSL Adapter',
    bus => 'PCI',
    driver => 'fcdsl',
    firmware => 'fdslbase.bin'
   },
   {
    vendor => 0x1244,
    id => 0x0a00,
    description => 'AVM Audiovisuelles|A1 ISDN Adapter [Fritz] CAPI',
    bus => 'PCI',
    driver => 'fcpci'
   },
   {
    vendor => 0x1244,
    id => 0x0e00,
    description => 'AVM Audiovisuelles|A1 ISDN Adapter [Fritz] CAPI',
    bus => 'PCI',
    driver => 'fcpci'
   },
   {
    vendor => 0x1244,
    id => 0x0f00,
    description => 'AVM Audiovisuelles|Fritz DSL ISDN/DSL Adapter',
    bus => 'PCI',
    driver => 'fcdsl',
    firmware => 'fdslbase.bin'
   },
   {
    vendor => 0x1244,
    id => 0x2700,
    description => 'AVM Audiovisuelles|Fritz!Card DSL SL',
    bus => 'PCI',
    driver => 'fcdslsl',
    firmware => 'fdssbase.bin'
   },
   {
    vendor => 0x1244,
    id => 0x2900,
    description => 'AVM Audiovisuelles|Fritz DSL Ver. 2.0',
    bus => 'PCI',
    driver => 'fcdsl2',
    firmware => 'fds2base.bin'
   },
   {
    vendor => 0x057c,
    id => 0x0c00,
    description => 'AVM GmbH|FritzCard USB ISDN TA',
    bus => 'USB',
    driver => 'fcusb'
   },
   {
    vendor => 0x057c,
    id => 0x1000,
    description => 'AVM GmbH|FritzCard USB 2 Ver. 2.0 ISDN TA',
    bus => 'USB',
    driver => 'fcusb2',
    firmware => 'fus2base.frm'
   },
   {
    vendor => 0x057c,
    id => 0x1900,
    description => 'AVM GmbH|FritzCard USB 2 Ver. 3.0 ISDN TA',
    bus => 'USB',
    driver => 'fcusb2',
    firmware => 'fus3base.frm'
   },
   {
    vendor => 0x057c,
    id => 0x2000,
    description => 'AVM GmbH|Fritz X USB ISDN TA',
    bus => 'USB',
    driver => 'fxusb'
   },
   {
    vendor => 0x057c,
    id => 0x2300,
    description => 'AVM GmbH|FtitzCard USB DSL ISDN TA/ DSL Modem',
    bus => 'USB',
    driver => 'fcdslusb',
    firmware => 'fdsubase.frm'
   },
   {
    vendor => 0x057c,
    id => 0x2800,
    description => 'AVM GmbH|Fritz X USB OEM ISDN TA',
    bus => 'USB',
    driver => 'fxusb_CZ'
   },
   {
    vendor => 0x057c,
    id => 0x3000,
    description => 'AVM GmbH|FtitzCard USB DSL SL USB',
    bus => 'USB',
    driver => 'fcdslusba',
    firmware => 'fdlabase.frm'
   },
   {
    vendor => 0x057c,
    id => 0x3500,
    description => 'AVM GmbH|FtitzCard USB DSL SL USB Analog',
    bus => 'USB',
    driver => 'fcdslslusb',
    firmware => 'fdlubase.frm',
   },
   {
    vendor => 0x057c,
    id => 0x3600,
    description => 'AVM FRITZ!Card DSL USB v2.0',
    bus => 'USB',
    driver => 'fcdslusb2',
    firmware => 'fds2base.frm',
   },
  );


1;
