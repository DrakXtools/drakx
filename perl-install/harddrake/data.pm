package harddrake::data;

use strict;
use detect_devices;
use MDK::Common;
use class_discard;

our (@ISA, @EXPORT_OK) = (qw(Exporter), (qw(version tree)));
our ($version, $sbindir, $bindir) = ("1.1.6", "/usr/sbin", "/usr/bin");

# Update me each time you handle one more devices class (aka configurator)
sub unknown {
    grep { ($_->{media_type} !~ /tape|SERIAL_(USB|SMBUS)|Printer|DISPLAY|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|STORAGE_IDE|BRIDGE|NETWORK/) && ($_->{driver} ne 'scanner') } detect_devices::probeall(1);
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll harddrake2 service to detect changes
# in hw configuration ... :-(

my @devices = detect_devices::probeall(1);

our @tree =
    (
	["FLOPPY","Floppy", "floppy.png", "",\&detect_devices::floppies],
	["HARDDISK","Disk", "harddisk.png", "$sbindir/diskdrake", \&detect_devices::hds],
	["CDROM","CDROM", "cd.png", "", sub { grep { !(detect_devices::isBurner($_) || detect_devices::isDvdDrive($_))} &detect_devices::cdroms}],
	["BURNER","CD/DVD burners", "cd.png", "", \&detect_devices::burners],
	["DVDROM","DVD-ROM", "cd.png", "", \&detect_devices::dvdroms],
	["TAPE","Tape", "tape.png", "", \&detect_devices::tapes],
#	["CDBURNER","Cd burners", "cd.png", "", \&detect_devices::burners],

	["VIDEO","Videocard", "video.png", "$sbindir/XFdrake", 
	 sub {grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ 'DISPLAY_VGA' } @devices }],
	["TV","Tvcard", "tv.png", "/usr/bin/XawTV", 
	 sub {grep { $_->{media_type} =~ 'MULTIMEDIA_VIDEO' } @devices}],
	["MULTIMEDIA_OTHER","Other MultiMedia devices", "tv.png", "", 
	 sub {grep { $_->{media_type} =~ 'MULTIMEDIA_OTHER' } @devices}],
	["AUDIO","Soundcard", "sound.png", "$bindir/aumix", 
	 sub {grep { $_->{media_type} =~ 'MULTIMEDIA_AUDIO' } @devices}],
#	"MULTIMEDIA_AUDIO" => "/usr/bin/X11/sounddrake";
	["WEBCAM","Webcam", "webcam.png", "", sub {}],
	["ETHERNET","Ethernetcard", "hw_network.png", "$sbindir/drakconnect", sub {
	    #- generic NIC detection for USB seems broken (class, subclass, 
	    #- protocol report are not accurate) so I'll need to verify against
	    #- known drivers :-(
	    my @usbnet = qw/CDCEther catc kaweth pegasus usbnet/;
	    # should be taken from detect_devices.pm or modules.pm. it's identical
	    
	    grep { $_->{media_type} =~ /^NETWORK/ || member($_->{driver}, @usbnet) } @devices}],
#	["","Tokenring cards", "Ethernetcard.png", "", \&detect_devices::getNet],
#	["","FDDI cards", "Ethernetcard.png", "", \&detect_devices::getNet],
#	["","Modem", "Modem.png", "", \&detect_devices::getNet],
#	["","Isdn", "", "", \&detect_devices::getNet]

	["BRIDGE","Bridge(s)", "memory.png", "", sub {grep { $_->{media_type} =~ 'BRIDGE' } @devices}],
# 	["","Cpu", "cpu.png", "", sub {}],
#	["","Memory", "memory.png", "", sub {}],
	["UNKNOWN","Unknown/Others", "unknown.png", "" , \&unknown],

	["PRINTER","Printer", "hw_printer.png", "$sbindir/printerdrake", 
	 sub { require printerdrake; printerdrake::auto_detect(class_discard->new)  } ],
	["SCANNER","Scanner", "scanner.png", "$sbindir/scannerdrake",
	 sub { require scanner; scanner::findScannerUsbport() }],
	["MOUSE","Mouse", "hw_mouse.png", "$sbindir/mousedrake", sub { require mouse; &mouse::detect()}],
	["JOYSTICK","Joystick", "joystick.png", "", sub {}],

	["ATA_STORAGE","(E)IDE/ATA controllers", "ide_hd.png", "", sub {grep { $_->{media_type} =~ 'STORAGE_IDE' } @devices}],
	["SCSI_CONTROLLER","SCSI controllers", "scsi.png", "", \&detect_devices::getSCSI],
	["USB_CONTROLLER","USB controllers", "usb.png", "", sub {grep { $_->{media_type} =~ 'SERIAL_USB' } @devices}],
	["SMB_CONTROLLER","SMBus controllers", "usb.png", "", sub {grep { $_->{media_type} =~ 'SERIAL_SMBUS' } @devices}],
	);


1;
