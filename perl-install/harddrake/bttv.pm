#!/usr/bin/perl -w

package bttv;

use strict;
use lib qw(/usr/lib/libDrakX);

use standalone;

use interactive;
use detect_devices;
use lang;
use log;
use MDK::Common;
use modules;

# please update me on bttv update :
my %tuners_lst = 
    (
	-1 => _("Auto-detect"),
	0 => "Temic PAL (4002 FH5)",
	1 => "Philips PAL_I",
	2 => "Philips NTSC",
	3 => "Philips SECAM",
	4 => "NoTuner",
	5 => "Philips PAL",
	6 => "Temic NTSC (4032 FY5)",
	7 => "Temic PAL_I (4062 FY5)",
	8 => "Temic NTSC (4036 FY5)",
	9 => "Alps HSBH1",
	10 => "Alps TSBE1",
	11 => "Alps TSBB5",
	12 => "Alps TSBE5",
	13 => "Alps TSBC5",
	14 => "Temic PAL_BG (4006FH5)",
	15 => "Alps TSCH6",
	16 => "Temic PAL_DK (4016 FY5)",
	17 => "Philips NTSC_M (MK2)",
	18 => "Temic PAL_I (4066 FY5)",
	19 => "Temic PAL* auto (4006 FN5)",
	20 => "Temic PAL_BG (4009 FR5) or PAL_I (4069 FR5)",
	21 => "Temic NTSC (4039 FR5)",
	22 => "Temic PAL/SECAM multi (4046 FM5)",
	23 => "Philips PAL_DK",
	24 => "Philips PAL/SECAM multi (FQ1216ME)",
	25 => "LG PAL_I+FM (TAPC-I001D)",
	26 => "LG PAL_I (TAPC-I701D)",
	27 => "LG NTSC+FM (TPI8NSR01F)",
	28 => "LG PAL_BG+FM (TPI8PSB01D)",
	29 => "LG PAL_BG (TPI8PSB11D)",
	30 => "Temic PAL* auto + FM (4009 FN5)",
	31 => "SHARP NTSC_JP (2U5JF5540)",
	32 => "Samsung PAL TCPM9091PD27",
	33 => "MT2032 universal",
	34 => "Temic PAL_BG (4106 FH5)",
	35 => "Temic PAL_DK/SECAM_L (4012 FY5)",
	36 => "Temic NTSC (4136 FY5)",
	37 => "LG PAL (newer TAPC series)",
	38 => "Philips PAL/SECAM multi (FM1216ME)"
	);

my %cards_lst =
    (
	-1 => _("Auto-detect"),
	0 => _("Unknown/Generic"),
	1 => "MIRO PCTV",
	2 => "Hauppauge (bt848)",
	3 => "STB",
	4 => "Intel Create and Share PCI/ Smart Video Recorder III",
	5 => "Diamond DTV2000",
	6 => "AVerMedia TVPhone",
	7 => "MATRIX-Vision MV-Delta",
	8 => "Lifeview FlyVideo II (Bt848) LR26",
	9 => "IMS/IXmicro TurboTV",
	10 => "Hauppauge (bt878)",
	11 => "MIRO PCTV pro",
	12 => "ADS Technologies Channel Surfer TV (bt848)",
	13 => "AVerMedia TVCapture 98",
	14 => "Aimslab Video Highway Xtreme (VHX)",
	15 => "Zoltrix TV-Max",
	16 => "Prolink Pixelview PlayTV (bt878)",
	17 => "Leadtek WinView 601",
	18 => "AVEC Intercapture",
	19 => "Lifeview FlyVideo II EZ /FlyKit LR38 Bt848 (capture only)",
	20 => "CEI Raffles Card",
	21 => "Lifeview FlyVideo 98/ Lucky Star Image World ConferenceTV LR50",
	22 => "Askey CPH050/ Phoebe Tv Master + FM",
	23 => "Modular Technology MM205 PCTV, bt878",
	24 => "Askey CPH05X/06X (bt878) [many vendors]",
	25 => "Terratec Terra TV+ Version 1.0 (Bt848)/Vobis TV-Boostar",
	26 => "Hauppauge WinCam newer (bt878)",
	27 => "Lifeview FlyVideo 98/ MAXI TV Video PCI2 LR50",
	28 => "Terratec TerraTV+",
	29 => "Imagenation PXC200",
	30 => "Lifeview FlyVideo 98 LR50",
	31 => "Formac iProTV",
	32 => "Intel Create and Share PCI/ Smart Video Recorder III",
	33 => "Terratec TerraTValue",
	34 => "Leadtek WinFast 2000",
	35 => "Lifeview FlyVideo 98 LR50 / Chronos Video Shuttle II",
	36 => "Lifeview FlyVideo 98FM LR50 / Typhoon TView TV/FM Tuner",
	37 => "Prolink PixelView PlayTV pro",
	38 => "Askey CPH06X TView99",
	39 => "Pinnacle PCTV Studio/Rave",
	40 => "STB2",
	41 => "AVerMedia TVPhone 98",
	42 => "ProVideo PV951",
	43 => "Little OnAir TV",
	44 => "Sigma TVII-FM",
	45 => "MATRIX-Vision MV-Delta 2",
	46 => "Zoltrix Genie TV/FM",
	47 => "Terratec TV/Radio+",
	48 => "Askey CPH03x/ Dynalink Magic TView",
	49 => "IODATA GV-BCTV3/PCI",
	50 => "Prolink PV-BT878P+4E / PixelView PlayTV PAK / Lenco MXTV-9578 CP",
	51 => "Eagle Wireless Capricorn2 (bt878A)",
	52 => "Pinnacle PCTV Studio Pro",
	53 => "Typhoon TView RDS + FM Stereo / KNC1 TV Station RDS",
	54 => "Lifeview FlyVideo 2000 /FlyVideo A2/ Lifetec LT 9415 TV [LR90]",
	55 => "Askey CPH031/ BESTBUY Easy TV",
	56 => "Lifeview FlyVideo 98FM LR50",
	57 => "GrandTec 'Grand Video Capture' (Bt848)",
	58 => "Askey CPH060/ Phoebe TV Master Only (No FM)",
	59 => "Askey CPH03x TV Capturer",
	60 => "Modular Technology MM100PCTV",
	61 => "AG Electronics GMV1",
	62 => "Askey CPH061/ BESTBUY Easy TV (bt878)",
	63 => "ATI TV-Wonder",
	64 => "ATI TV-Wonder VE",
	65 => "Lifeview FlyVideo 2000S LR90",
	66 => "Terratec TValueRadio",
	67 => "IODATA GV-BCTV4/PCI",
	68 => "3Dfx VoodooTV FM (Euro), VoodooTV 200 (USA)",
	69 => "Active Imaging AIMMS",
	70 => "Prolink Pixelview PV-BT878P+ (Rev.4C)",
	71 => "Lifeview FlyVideo 98EZ (capture only) LR51",
	72 => "Prolink Pixelview PV-BT878P+9B (PlayTV Pro rev.9B FM+NICAM)",
	73 => "Sensoray 311",
	74 => "RemoteVision MX (RV605)",
	75 => "Powercolor MTV878/ MTV878R/ MTV878F",
	76 => "Canopus WinDVR PCI (COMPAQ Presario 3524JP, 5112JP)",
	77 => "GrandTec Multi Capture Card (Bt878)",
	78 => "Jetway TV/Capture JW-TV878-FBK, Kworld KW-TV878RF",
	79 => "DSP Design TCVIDEO"
	);

my %pll_lst = 
    (
	-1 => _("Default"),
	0 => "don't use pll",
	1 => "28 Mhz Crystal (X)",
	2 =>"35 Mhz Crystal"
	);

sub config {
    my ($in) = @_;
    my ($card, $tuner, $radio, $pll) = (-1, -1, 0, -1);
#    return unless (grep { $_->{media_type} eq 'MULTIMEDIA_VIDEO' } detect_devices::probeall(1));
    if ($in->ask_from("BTTV configuration", _("Please,\nselect your tv card parameters if needed"),
				  [
				   { label => _("Card model :"), val => \$card, list => [keys %cards_lst], format => sub { $cards_lst{$_[0]} }, type => 'combo', default => -1, sort =>1},
				   { label => _("PLL type :"), val => \$pll, list => [keys %pll_lst], format => sub { $pll_lst{$_[0]} }, sort => 1, default => 0, advanced =>1},
				   { label => _("Tuner type :"), val => \$tuner, list => [keys %tuners_lst], format => sub { $tuners_lst{$_[0]} }, sort => 1},
				   { label => _("Radio support :"), val => \$radio, type => "bool", text => _("enable radio support")},
				   ]
				  ))
    {
	   my $options = join ' ', mapn {if  ($_[0] ne "-1") { $_[1]."=".$_[0]} else {} } [$card, $pll, $tuner], ["card", "pll", "tuner"];
	   print "@",$options,"@\n";
	   log::l("[harddrake::tv] $options");
	   standalone::explanations("modified file /etc/modules.conf ($options)");
	   modules::read_conf("/etc/modules.conf");
	   modules::set_options("bttv",$options) if ($options ne "");
	   modules::write_conf();
	 }
}



1;
