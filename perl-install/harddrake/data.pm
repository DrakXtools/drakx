package harddrake::data;

use strict;
use detect_devices;
use common;

our (@ISA, @EXPORT_OK) = (qw(Exporter), (qw(version tree)));
our ($version, $sbindir, $bindir) = ("1.1.8", "/usr/sbin", "/usr/bin");

my @devices = detect_devices::probeall(1);

# Update me each time you handle one more devices class (aka configurator)
sub unknown {
    grep { ($_->{media_type} !~ /tape|SERIAL_(USB|SMBUS)|Printer|DISPLAY|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|STORAGE_(IDE|SCSI|OTHER)|BRIDGE|NETWORK/) && ($_->{driver} ne '^(scanner|usbvideo)$') && $_->{type} ne 'network' && $_->{driver} !~ /Mouse:USB|class\|Mouse/ } @devices;
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll harddrake2 service to detect changes
# in hw configuration ... :-(

our @tree =
    (
     ["FLOPPY", "Floppy", "floppy.png", "", \&detect_devices::floppies, 0 ],
     ["HARDDISK", "Disk", "harddisk.png", "$sbindir/diskdrake", \&detect_devices::hds, 1 ],
     ["CDROM", "CDROM", "cd.png", "", sub { grep { !(detect_devices::isBurner($_) || detect_devices::isDvdDrive($_)) } &detect_devices::cdroms }, 0 ],
     ["BURNER", "CD/DVD burners", "cd.png", "", \&detect_devices::burners(), 0 ],
     ["DVDROM", "DVD-ROM", "cd.png", "", sub { grep { ! detect_devices::isBurner($_) } detect_devices::dvdroms() }, 0 ],
     ["TAPE", "Tape", "tape.png", "", \&detect_devices::tapes, 0 ],
     ["VIDEO", "Videocard", "video.png", "$sbindir/XFdrake",  sub { grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ /DISPLAY_VGA/ } @devices }, 1 ],
     ["TV", "Tvcard", "tv.png", "/usr/bin/XawTV", sub { grep { ($_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} eq 'PCI') || $_->{driver} eq 'usbvision' } @devices }, 0 ],     
     ["MULTIMEDIA_OTHER", "Other MultiMedia devices", "multimedia.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_OTHER/ } @devices }, 0 ],
     ["AUDIO", "Soundcard", "sound.png", "$sbindir/draksound", sub { grep { $_->{media_type} =~ /MULTIMEDIA_AUDIO/ } @devices }, 0 ],
     ["WEBCAM", "Webcam", "webcam.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} ne 'PCI' } @devices }, 0 ],
     ["CPU", "Processors", "cpu.png", "", sub { detect_devices::getCPUs() }, 0 ],
     ["ETHERNET", "Ethernetcard", "hw_network.png", "$sbindir/drakconnect", sub {
         #- generic NIC detection for USB seems broken (class, subclass, 
         #- protocol report are not accurate) so I'll need to verify against
         #- known drivers :-(
         my @usbnet = qw(CDCEther catc kaweth pegasus usbnet);
         # should be taken from detect_devices.pm or modules.pm. it's identical
         
         grep { $_->{media_type} =~ /^NETWORK/ || member($_->{driver}, @usbnet) || $_->{type} eq 'network' } @devices }, 1 ],
     ["MODEM", "Modem", "modem.png", "", sub { detect_devices::getModem() }, 0 ],
     ["BRIDGE", "Bridge(s)", "memory.png", "", sub { grep { $_->{media_type} =~ /BRIDGE/ } @devices }, 0 ],
     ["UNKNOWN", "Unknown/Others", "unknown.png", "", \&unknown, 0 ],

     ["PRINTER", "Printer", "hw_printer.png", "$sbindir/printerdrake", sub { 
         require printer::detect; printer::detect::detect() }, 0 ],
     ["SCANNER", "Scanner", "scanner.png", "$sbindir/scannerdrake", sub { 
         require scanner; scanner::detect() }, 0 ],
     ["MOUSE", "Mouse", "hw_mouse.png", "$sbindir/mousedrake", sub { 
         require mouse;
         require modules;
         modules::mergein_conf('/etc/modules.conf') if -r '/etc/modules.conf';
         &mouse::detect() }, 1 ],
     ["JOYSTICK", "Joystick", "joystick.png", "", sub {}, 0 ],

     ["ATA_STORAGE", "(E)IDE/ATA controllers", "ide_hd.png", "", sub { grep { $_->{media_type} =~ /STORAGE_(IDE|OTHER)/ } @devices }, 0 ],
     ["SCSI_CONTROLLER", "SCSI controllers", "scsi.png", "", sub { grep { $_->{media_type} =~ /STORAGE_SCSI/ } @devices }, 0 ],
     ["USB_CONTROLLER", "USB controllers", "usb.png", "", sub { grep { $_->{media_type} =~ /SERIAL_USB/ } @devices }, 0 ],
     ["SMB_CONTROLLER", "SMBus controllers", "usb.png", "", sub { grep { $_->{media_type} =~ /SERIAL_SMBUS/ } @devices }, 0 ],
     );


sub custom_id {
    my ($device, $str) = @_;
    defined($device->{device}) ? $device->{device} :
        (defined($device->{processor}) ? 
         "$device->{vendor_id} $device->{name} " . N("cpu number ") . $device->{processor} :
         (defined($device->{description}) ? $device->{description} : $str));
}

1;
