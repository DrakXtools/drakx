package harddrake::data;

use strict;
use detect_devices;
use common;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(version tree);
our ($version, $sbindir, $bindir) = ("10", "/usr/sbin", "/usr/bin");

my @devices = detect_devices::probeall();

# Update me each time you handle one more devices class (aka configurator)
sub unknown() {
    grep { $_->{media_type} !~ /BRIDGE|class\|Mouse|DISPLAY|Hub|MEMORY_RAM|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|NETWORK|Printer|SERIAL_(USB|SMBUS)|STORAGE_(IDE|OTHER|SCSI)|tape/
	       && !member($_->{driver}, qw(cpia_usb cyber2000fb forcedeth ibmcam megaraid mod_quickcam nvnet ohci1394 ov511 ov518_decomp scanner ultracam usbvideo usbvision))
	       && $_->{driver} !~ /^ISDN|Mouse:USB|Removable:zip|class\|Mouse|www.linmodems.org/
	       && $_->{type} ne 'network'
	       && $_->{description} !~ /Alcatel|ADSL Modem/
	   } @devices;
}

my @alrd_dected;
sub f { 
    my @devs = grep { !member(pciusb_id($_), @alrd_dected) } @_;
    push @alrd_dected, map { pciusb_id($_) } @devs;
    @devs;
}


# tree format ("CLASS_ID", "type", "type_icon", configurator, detect_sub)
# NEVER, NEVER alter CLASS_ID or you'll see harddrake2 service detect changes
# in hw configuration ... :-(

# FIXME: add translated items

sub is_removable { $_[0] =~ /FLOPPY|ZIP|DVDROM|CDROM|BURNER/ }

sub set_removable_configurator {
    my ($class, $device) = @_;
    return "/usr/sbin/diskdrake --auto --removable=$device->{device}" if is_removable($class);
}

sub set_removable_remover {
    my ($class, $device) = @_;
    return "/usr/sbin/drakupdate_fstab --no-flag --del $device->{device}" if is_removable($class);
}


# Format is (HW class ID, l18n class name, icon, config tool , is_to_be_detected_on_boot)
our @tree =
    (
     {
      class => "FLOPPY",
      string => N("Floppy"),
      icon => "floppy.png",
      configurator => "",
      detector => \&detect_devices::floppies,
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "ZIP",
      string => N("Zip"),
      icon => "floppy.png",
      configurator => "",
      detector => \&detect_devices::zips,
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "HARDDISK",
      string => N("Disk"),
      icon => "harddisk.png",
      configurator => "$sbindir/diskdrake",
      detector => \&detect_devices::hds,
      checked_on_boot => 1,
     },

     {
      class => "CDROM",
      string => N("CDROM"),
      icon => "cd.png",
      configurator => "",
      detector => sub { grep { !(detect_devices::isBurner($_) || detect_devices::isDvdDrive($_)) } &detect_devices::cdroms },
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "BURNER",
      string => N("CD/DVD burners"),
      icon => "cd.png",
      configurator => "",
      detector => \&detect_devices::burners,
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "DVDROM",
      string => N("DVD-ROM"),
      icon => "cd.png",
      configurator => "",
      detector => sub { grep { ! detect_devices::isBurner($_) } detect_devices::dvdroms() },
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "TAPE",
      string => N("Tape"),
      icon => "tape.png",
      configurator => "",
      detector => \&detect_devices::tapes,
      checked_on_boot => 0,
     },

     {
      class => "VIDEO",
      string => N("Videocard"),
      icon => "video.png",
      configurator => "$sbindir/XFdrake",
      configurator_auto => "$sbindir/XFdrake --auto",
      detector =>  sub { f(grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ /DISPLAY_VGA/ } @devices) },
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "TV",
      string => N("Tvcard"),
      icon => "tv.png",
      configurator => "/usr/bin/XawTV",
      detector => sub { f(grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} eq 'PCI' || $_->{driver} eq 'usbvision' } @devices) },
      checked_on_boot => 0,
     },
     
     {
      class => "MULTIMEDIA_OTHER",
      string => N("Other MultiMedia devices"),
      icon => "multimedia.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /MULTIMEDIA_OTHER/ } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "AUDIO",
      string => N("Soundcard"),
      icon => "sound.png",
      configurator => "$sbindir/draksound",
      detector => sub { f(grep { $_->{media_type} =~ /MULTIMEDIA_AUDIO/ } @devices) },
      checked_on_boot => 1,
     },

     {
      class => "WEBCAM",
      string => N("Webcam"),
      icon => "webcam.png",
      configurator => "",
      detector => sub { 
          f(grep {
              $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} ne 'PCI'
                || member($_->{driver}, qw(cpia_usb cyber2000fb ibmcam mod_quickcam ov511 ov518_decomp pwc ultracam usbvideo))
            } @devices)
      },
      checked_on_boot => 0,
     },

     {
      class => "CPU",
      string => N("Processors"),
      icon => "cpu.png",
      configurator => "",
      detector => sub { detect_devices::getCPUs() },
      checked_on_boot => 0,
     },

     {
      class => "ISDN",
      string => N("ISDN adapters"),
      icon => "modem.png",
      configurator => "$sbindir/drakconnect",
      detector => sub { require network::isdn; my $isdn = network::isdn::detect_backend(); if_(@$isdn, f(@$isdn)) },
      checked_on_boot => 0,
     },

     {
      class => "ETHERNET",
      string => N("Ethernetcard"),
      icon => "hw_network.png",
      configurator => "$sbindir/drakconnect",
      detector => sub {
          #- generic NIC detection for USB seems broken (class, subclass, 
          #- protocol report are not accurate) so I'll need to verify against
          #- known drivers :-(
          require list_modules;
          my @usbnet = (list_modules::category2modules('network/usb'), "nvnet"); # rought hack for nforce2's nvet
          
          f(grep {
              $_->{media_type} && $_->{media_type} =~ /^NETWORK/
                || member($_->{driver}, @usbnet)
                  || $_->{type} && $_->{type} eq 'network'
              } @devices)
      },
      checked_on_boot => 1,
     },

     {
      class => "MODEM",
      string => N("Modem"),
      icon => "modem.png",
      configurator => "$sbindir/drakconnect",
      detector => sub { detect_devices::getModem() },
      checked_on_boot => 0,
     },

     {
      class => "ADSL",
      string => N("ADSL adapters"),
      icon => "modem.png",
      configurator => "$sbindir/drakconnect",
      detector => sub { 
          require network::adsl;
          my $a = network::adsl::adsl_detect();
          $a ? f(grep { $_ } values %$a) : ();
      },
      checked_on_boot => 0,
     },

     {
      class => "AGP",
      string => N("AGP controllers"),
      icon => "memory.png",
      configurator => "",
      detector => sub { f(modules::probe_category('various/agpgart')) },
      checked_on_boot => 0,
     },

     {
      class => "BRIDGE",
      string => N("Bridges and system controllers"),
      icon => "memory.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /BRIDGE|MEMORY_RAM/ && $_->{driver} ne 'nvnet' } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "PRINTER",
      string => N("Printer"),
      icon => "hw_printer.png",
      configurator => "$sbindir/printerdrake",
      detector => sub { require printer::detect; printer::detect::local_detect() },
      checked_on_boot => 0,
     },

     {
      class => "MOUSE",
      string => N("Mouse"),
      icon => "hw_mouse.png",
      configurator => "$sbindir/mousedrake",
      detector => sub { 
          require mouse;
          require modules;
          modules::mergein_conf('/etc/modules.conf') if -r '/etc/modules.conf';
          &mouse::detect();
      },
      checked_on_boot => 1,
     },

     {
      class => "JOYSTICK",
      string => N("Joystick"),
      icon => "joystick.png",
      configurator => "",
      detector => sub {},
      checked_on_boot => 0,
     },


     {
      class => "ATA_STORAGE",
      string => N("(E)IDE/ATA controllers"),
      icon => "ide_hd.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /STORAGE_(IDE|OTHER)/ || $_->{driver} eq '3w-xxxx' } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "FIREWIRE_CONTROLLER",
      string => N("Firewire controllers"),
      icon => "usb.png",
      configurator => "",
      detector => sub { f(grep { $_->{driver} =~ /ohci1394/ } @devices) },
      checked_on_boot => 1,
     },

     {
      class => "SCSI_CONTROLLER",
      string => N("SCSI controllers"),
      icon => "scsi.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /STORAGE_SCSI/ || $_->{driver} eq 'megaraid' } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "USB_CONTROLLER",
      string => N("USB controllers"),
      icon => "usb.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} eq 'SERIAL_USB' } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "USB_HUB",
      string => N("USB ports"),
      icon => "usb.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /Hub/ } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "SMB_CONTROLLER",
      string => N("SMBus controllers"),
      icon => "usb.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /SERIAL_SMBUS/ } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "SCANNER",
      string => N("Scanner"),
      icon => "scanner.png",
      configurator => "$sbindir/scannerdrake",
      detector => sub { 
         require scanner; f(scanner::detect()) },
      checked_on_boot => 0,
     },

     {
      class => "UNKNOWN",
      string => N("Unknown/Others"),
      icon => "unknown.png",
      configurator => "",
      detector => sub { f(unknown()) },
      checked_on_boot => 0,
     },

    );

sub pciusb_id {
    my ($dev) = @_;
    join(':', map { $dev->{$_} } qw(bus pci_bus pci_device vendor id subvendor subid description));
}


sub custom_id {
    my ($device, $str) = @_;
    return if !ref($device);
    defined($device->{device}) ? $device->{device} :
        (defined($device->{processor}) ? 
         N("cpu # ") . $device->{processor} . ": " . $device->{'model name'} :
         (defined($device->{description}) ? $device->{description} : $str));
}

1;
