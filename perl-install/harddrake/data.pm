package harddrake::data;

use strict;
use detect_devices;
use common;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(version tree);
our ($version, $sbindir, $bindir) = ("9.0.1", "/usr/sbin", "/usr/bin");

my @devices = detect_devices::probeall(1);

# Update me each time you handle one more devices class (aka configurator)
sub unknown {
    grep { $_->{media_type} !~ /BRIDGE|class\|Mouse|DISPLAY|Hub|MEMORY_RAM|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|NETWORK|Printer|SERIAL_(USB|SMBUS)|STORAGE_(IDE|OTHER|SCSI)|tape/ && $_->{driver} !~ /^(scanner|usbvision)$|Mouse:USB|class\|Mouse|www.linmodems.org|nvnet/ && $_->{type} ne 'network' } @devices;
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll see harddrake2 service detect changes
# in hw configuration ... :-(

# FIXME: add translated items

our @tree =
    (
     [ "FLOPPY", , N("Floppy"), "floppy.png", "", \&detect_devices::floppies, 0 ],
     [ "ZIP", , N("Zip"), "floppy.png", "", \&detect_devices::zips, 0 ],
     [ "HARDDISK", , N("Disk"), "harddisk.png", "$sbindir/diskdrake", \&detect_devices::hds, 1 ],
     [ "CDROM", , N("CDROM"), "cd.png", "", sub { grep { !(detect_devices::isBurner($_) || detect_devices::isDvdDrive($_)) } &detect_devices::cdroms }, 0 ],
     [ "BURNER", , N("CD/DVD burners"), "cd.png", "", \&detect_devices::burners, 0 ],
     [ "DVDROM", , N("DVD-ROM"), "cd.png", "", sub { grep { ! detect_devices::isBurner($_) } detect_devices::dvdroms() }, 0 ],
     [ "TAPE", , N("Tape"), "tape.png", "", \&detect_devices::tapes, 0 ],
     [ "VIDEO", , N("Videocard"), "video.png", "$sbindir/XFdrake",  sub { grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ /DISPLAY_VGA/ } @devices }, 1 ],
     [ "TV", , N("Tvcard"), "tv.png", "/usr/bin/XawTV", sub { grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} eq 'PCI' || $_->{driver} eq 'usbvision' } @devices }, 0 ],     
     [ "MULTIMEDIA_OTHER", , N("Other MultiMedia devices"), "multimedia.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_OTHER/ } @devices }, 0 ],
     [ "AUDIO", , N("Soundcard"), "sound.png", "$sbindir/draksound", sub { grep { $_->{media_type} =~ /MULTIMEDIA_AUDIO/ } @devices }, 0 ],
     [ "WEBCAM", , N("Webcam"), "webcam.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} ne 'PCI' } @devices }, 0 ],
     [ "CPU", , N("Processors"), "cpu.png", "", sub { detect_devices::getCPUs() }, 0 ],
     [ "ETHERNET", , N("Ethernetcard"), "hw_network.png", "$sbindir/drakconnect", sub {
         #- generic NIC detection for USB seems broken (class, subclass, 
         #- protocol report are not accurate) so I'll need to verify against
         #- known drivers :-(
         my @usbnet = qw(CDCEther catc kaweth nvnet pegasus usbnet); # rought hack for nforce2's nvet
         # should be taken from detect_devices.pm or modules.pm. it's identical
         
         grep { $_->{media_type} =~ /^NETWORK/ || member($_->{driver}, @usbnet) || $_->{type} eq 'network' } @devices }, 1 ],
     [ "MODEM", , N("Modem"), "modem.png", "", sub { detect_devices::getModem() }, 0 ],
     [ "BRIDGE", , N("Bridges and system controllers"), "memory.png", "", sub { grep { $_->{media_type} =~ /BRIDGE|MEMORY_RAM/ && $_->{driver} ne 'nvnet' } @devices }, 0 ],
     [ "UNKNOWN", , N("Unknown/Others"), "unknown.png", "", \&unknown, 0 ],

     [ "PRINTER", , N("Printer"), "hw_printer.png", "$sbindir/printerdrake", sub { 
         require printer::detect; printer::detect::detect() }, 0 ],
     [ "SCANNER", , N("Scanner"), "scanner.png", "$sbindir/scannerdrake", sub { 
         require scanner; scanner::detect() }, 0 ],
     [ "MOUSE", , N("Mouse"), "hw_mouse.png", "$sbindir/mousedrake", sub { 
         require mouse;
         require modules;
         modules::mergein_conf('/etc/modules.conf') if -r '/etc/modules.conf';
         &mouse::detect() }, 1 ],
     [ "JOYSTICK", , N("Joystick"), "joystick.png", "", sub {}, 0 ],

     [ "ATA_STORAGE", , N("(E)IDE/ATA controllers"), "ide_hd.png", "", sub { grep { $_->{media_type} =~ /STORAGE_(IDE|OTHER)/ } @devices }, 0 ],
     [ "SCSI_CONTROLLER", , N("SCSI controllers"), "scsi.png", "", sub { grep { $_->{media_type} =~ /STORAGE_SCSI/ } @devices }, 0 ],
     [ "USB_CONTROLLER", , N("USB controllers"), "usb.png", "", sub { grep { $_->{media_type} =~ /SERIAL_USB|Hub/ } @devices }, 0 ],
     [ "SMB_CONTROLLER", , N("SMBus controllers"), "usb.png", "", sub { grep { $_->{media_type} =~ /SERIAL_SMBUS/ } @devices }, 0 ],
     );


sub custom_id {
    my ($device, $str) = @_;
    defined($device->{device}) ? $device->{device} :
        (defined($device->{processor}) ? 
         N("cpu # ") . $device->{processor} . ": " . $device->{'model name'} :
         (defined($device->{description}) ? $device->{description} : $str));
}

1;
