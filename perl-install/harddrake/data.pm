package harddrake::data;

use strict;
use detect_devices;
use common;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(version tree);
our ($version, $sbindir, $bindir) = ("9.1.1", "/usr/sbin", "/usr/bin");

my @devices = detect_devices::probeall();

# Update me each time you handle one more devices class (aka configurator)
sub unknown() {
    grep { $_->{media_type} !~ /BRIDGE|class\|Mouse|DISPLAY|Hub|MEMORY_RAM|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|NETWORK|Printer|SERIAL_(USB|SMBUS)|STORAGE_(IDE|OTHER|SCSI)|tape/
	       && $_->{driver} !~ /^(ISDN|mod_quickcam|ohci1394|scanner|usbvision)$|Mouse:USB|class\|Mouse|Removable:zip|megaraid|nvnet|www.linmodems.org/
	       && $_->{type} ne 'network'
	       && $_->{description} !~ /Alcatel|ADSL Modem/
	   } @devices;
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll see harddrake2 service detect changes
# in hw configuration ... :-(

# FIXME: add translated items

sub is_removable { $_[0] =~ /FLOPPY|ZIP|DVDROM|CDROM|BURNER/ }

sub set_removable_configurator {
    my ($class, $device) = @_;
    return "/usr/sbin/diskdrake --removable=$device->{device}" if is_removable($class);
}

sub set_removable_remover {
    my ($class, $device) = @_;
    return "/usr/sbin/drakupdate_fstab --no-flag --del $device->{device}" if is_removable($class);
}


# Format is (HW class ID, l18n class name, icon, config tool , is_to_be_detected_on_boot)
our @tree =
    (
     [ "FLOPPY", , N("Floppy"), "floppy.png", "", \&detect_devices::floppies, 1 ],
     [ "ZIP", , N("Zip"), "floppy.png", "", \&detect_devices::zips, 1 ],
     [ "HARDDISK", , N("Disk"), "harddisk.png", "$sbindir/diskdrake", \&detect_devices::hds, 1 ],
     [ "CDROM", , N("CDROM"), "cd.png", "", sub { grep { !(detect_devices::isBurner($_) || detect_devices::isDvdDrive($_)) } &detect_devices::cdroms }, 1 ],
     [ "BURNER", , N("CD/DVD burners"), "cd.png", "", \&detect_devices::burners, 1 ],
     [ "DVDROM", , N("DVD-ROM"), "cd.png", "", sub { grep { ! detect_devices::isBurner($_) } detect_devices::dvdroms() }, 1 ],
     [ "TAPE", , N("Tape"), "tape.png", "", \&detect_devices::tapes, 0 ],
     [ "VIDEO", , N("Videocard"), "video.png", "$sbindir/XFdrake",  sub { grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ /DISPLAY_VGA/ } @devices }, 1 ],
     [ "TV", , N("Tvcard"), "tv.png", "/usr/bin/XawTV", sub { grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} eq 'PCI' || $_->{driver} eq 'usbvision' } @devices }, 0 ],     
     [ "MULTIMEDIA_OTHER", , N("Other MultiMedia devices"), "multimedia.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_OTHER/ } @devices }, 0 ],
     [ "AUDIO", , N("Soundcard"), "sound.png", "$sbindir/draksound", sub { grep { $_->{media_type} =~ /MULTIMEDIA_AUDIO/ } @devices }, 0 ],
     [ "WEBCAM", , N("Webcam"), "webcam.png", "", sub { grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} ne 'PCI' || $_->{driver} eq 'mod_quickcam' } @devices }, 0 ],
     [ "CPU", , N("Processors"), "cpu.png", "", sub { detect_devices::getCPUs() }, 0 ],
     [ "ETHERNET", , N("Ethernetcard"), "hw_network.png", "$sbindir/drakconnect", sub {
         #- generic NIC detection for USB seems broken (class, subclass, 
         #- protocol report are not accurate) so I'll need to verify against
         #- known drivers :-(
         require list_modules;
         my @usbnet = (list_modules::category2modules('network/usb'), "nvnet"); # rought hack for nforce2's nvet
         
         grep { $_->{media_type} && $_->{media_type} =~ /^NETWORK/ || member($_->{driver}, @usbnet) || $_->{type} && $_->{type} eq 'network' } @devices }, 1 ],
     [ "MODEM", , N("Modem"), "modem.png", "$sbindir/drakconnect", sub { detect_devices::getModem() }, 0 ],
     [ "ADSL", , N("ADSL adapters"), "modem.png", "$sbindir/drakconnect", sub { 
           require network::adsl; my $a = network::adsl::adsl_detect(); use Data::Dumper; print Data::Dumper->Dump([ $a ], [ 'adsl' ]); $a ? grep { $_ } values %$a : () }, 0 ],
     [ "ISDN", , N("ISDN adapters"), "modem.png", "$sbindir/drakconnect", sub { require network::isdn; my $isdn = network::isdn::isdn_detect_backend(); 
                                                            if_(!is_empty_hash_ref($isdn), $isdn) }, 0 ],
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
     [ "FIREWIRE_CONTROLLER", , N("Firewire controllers"), "usb.png", "", sub { grep { $_->{driver} =~ /ohci1394/ } @devices }, 1 ],
     [ "SCSI_CONTROLLER", , N("SCSI controllers"), "scsi.png", "", sub { grep { $_->{media_type} =~ /STORAGE_SCSI/ || $_->{driver} eq 'megaraid' } @devices }, 0 ],
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
