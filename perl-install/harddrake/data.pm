package harddrake::data;

use strict;
use detect_devices;
use MDK::Common;
use class_discard;

our (@ISA, @EXPORT_OK) = (qw(Exporter), (qw(version tree)));
our ($version, $sbindir, $bindir) = ("1.1.5", "/usr/sbin", "/usr/bin");

# Update me each time you handle one more devices class (aka configurator)
sub unknown {
    grep { $_->{media_type} !~ /tape|DISPLAY|MULTIMEDIA_VIDEO|BRIDGE|NETWORK|MULTIMEDIA_AUDIO/ } detect_devices::probeall(1);
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll harddrake2 service to detect changes
# in hw configuration ... :-(

our @tree =
    (
	["FLOPPY","Floppy", "floppy.png", "",\&detect_devices::floppies],
	["HARDDISK","Disk", "harddisk.png", "$sbindir/diskdrake", \&detect_devices::hds],
	["CDROM","Cdrom", "cd.png", "", \&detect_devices::cdroms],
	["TAPE","Tape", "tape.png", "", \&detect_devices::tapes],
#	["CDBURNER","Cd burners", "cd.png", "", \&detect_devices::burners],

	["VIDEO","Videocard", "video.png", "$sbindir/XFdrake", 
	 sub {grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ 'DISPLAY_VGA' } detect_devices::probeall(1) }],
	["TV","Tvcard", "tv.png", "/usr/bin/XawTV", 
	 sub {grep { $_->{media_type} =~ 'MULTIMEDIA_VIDEO' } detect_devices::probeall(1)}],
	["AUDIO","Soundcard", "sound.png", "$bindir/aumix", 
	 sub {grep { $_->{media_type} =~ 'MULTIMEDIA_AUDIO' } detect_devices::probeall(1)}],
#	"MULTIMEDIA_AUDIO" => "/usr/bin/X11/sounddrake";
	["WEBCAM","Webcam", "webcam.png", "", sub {}],
	["ETHERNET","Ethernetcard", "hw_network.png", "$sbindir/draknet", sub {
	    #- generic NIC detection for USB seems broken (class, subclass, 
	    #- protocol report are not accurate) so I'll need to verify against
	    #- known drivers :-(
	    my @usbnet = qw/CDCEther catc kaweth pegasus usbnet/;
	    # should be taken from detect_devices.pm or modules.pm. it's identical
	    
	    grep { $_->{media_type} =~ /^NETWORK/ || 
				member($_->{driver}, @usbnet)
			 } detect_devices::probeall(1)}],
#	["","Tokenring cards", "Ethernetcard.png", "", \&detect_devices::getNet],
#	["","FDDI cards", "Ethernetcard.png", "", \&detect_devices::getNet],
#	["","Modem", "Modem.png", "", \&detect_devices::getNet],
#	["","Isdn", "", "", \&detect_devices::getNet]

	["BRIDGE","Bridge", "memory.png", "", sub {grep { $_->{media_type} =~ 'BRIDGE' } detect_devices::probeall(1)}],
# 	["","Cpu", "cpu.png", "", sub {}],
#	["","Memory", "memory.png", "", sub {}],
	["UNKNOWN","Unknown/Others", "unknown.png", "" , \&unknown],

	["PRINTER","Printer", "hw_printer.png", "$sbindir/printerdrake", 
	 sub { require printerdrake; printerdrake::auto_detect(class_discard->new)  } ],
	["SCANNER","Scanner", "scanner.png", "$sbindir/scannerdrake",
	 sub { require scanner; scanner::findScannerUsbport() }],
	["MOUSE","Mouse", "hw_mouse.png", "$sbindir/mousedrake", sub { require mouse; &mouse::detect()}],
	["JOYSTICK","Joystick", "joystick.png", "", sub {}]

#	["","Ideinterface", "Ideinterface.png", "", "STORAGE_IDE"],
#	["","Scsiinterface", "Scsiinterface.png", "", \&detect_devices::getSCSI],
#	["","Usbinterface", "Usbinterface.png", "", \&detect_devices::usb_probe]
	);


1;
