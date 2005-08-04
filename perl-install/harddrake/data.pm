package harddrake::data;

use strict;
use detect_devices;
use common;
use modules;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(version tree);
our ($version, $sbindir, $bindir) = ("10", "/usr/sbin", "/usr/bin");

my @devices = detect_devices::probeall();

# Update me each time you handle one more devices class (aka configurator)
sub unknown() {
    grep { $_->{media_type} !~ /BRIDGE|class\|Mouse|DISPLAY|Hub|MEMORY_RAM|MULTIMEDIA_(VIDEO|AUDIO|OTHER)|NETWORK|Printer|SERIAL_(USB|SMBUS)|STORAGE_(IDE|OTHER|SCSI)|SYSTEM_OTHER|tape|UPS/
	       && !member($_->{driver}, qw(cpia_usb cyber2000fb forcedeth ibmcam megaraid mod_quickcam nvnet ohci1394 ov511 ov518_decomp scanner ultracam usbvideo usbvision))
	       && $_->{driver} !~ /^ISDN|Mouse:USB|Removable:zip|class\|Mouse|sata|www.linmodems.org/
	       && $_->{type} ne 'network'
	       && $_->{description} !~ /Alcatel|ADSL Modem/;
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
    return "/usr/sbin/diskdrake --removable=$device->{device}" if is_removable($class);
 }

sub set_removable_auto_configurator {
    my ($class, $device) = @_;
    return "/usr/sbin/drakupdate_fstab --no-flag --auto --add $device->{device}" if is_removable($class);
}

sub set_removable_remover {
    my ($class, $device) = @_;
    return "/usr/sbin/drakupdate_fstab --no-flag --del $device->{device}" if is_removable($class);
}

my $modules_conf = modules::any_conf->read;

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
      detector => sub {
	  my ($options) = @_;
	  if ($options->{PARALLEL_ZIP_DETECTION}) {
	      modules::load_parallel_zip($modules_conf) and $modules_conf->write;
	  }
	  detect_devices::zips();
      },
      checked_on_boot => 1,
      automatic => 1,
     },

     {
      class => "HARDDISK",
      string => N("Hard Disk"),
      icon => "harddisk.png",
      configurator => "$sbindir/diskdrake",
      detector => sub { f(detect_devices::hds()) },
      checked_on_boot => 0,
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
      configurator_auto => "$sbindir/XFdrake",
      detector =>  sub { f(grep { $_->{driver} =~ /^(Card|Server):/ || $_->{media_type} =~ /DISPLAY_VGA/ } @devices) },
      checked_on_boot => 1,
     },

     {
      class => "DVB",
      string => N("DVB card"),
      icon => "tv.png",
      detector => sub { f(modules::probe_category('multimedia/dvb')) },
      checked_on_boot => 1,
     },

     {
      class => "TV",
      string => N("Tvcard"),
      icon => "tv.png",
      configurator => "/usr/bin/XawTV",
      detector => sub { f(grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} eq 'PCI' || $_->{driver} eq 'usbvision' } @devices) },
      checked_on_boot => 1,
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
      detector => sub { 
          require list_modules;
          my @modules = list_modules::category2modules('multimedia/sound');
          f(grep { $_->{media_type} =~ /MULTIMEDIA_AUDIO/  || member($_->{driver}, @modules) } @devices);
      },
      checked_on_boot => 1,
     },

     {
      class => "WEBCAM",
      string => N("Webcam"),
      icon => "webcam.png",
      configurator => "",
      detector => sub { 
          require list_modules;
          my @modules = list_modules::category2modules('multimedia/webcam');
          f(grep { $_->{media_type} =~ /MULTIMEDIA_VIDEO/ && $_->{bus} ne 'PCI' || member($_->{driver}, @modules) } @devices);
      },
      # managed by hotplug:
      checked_on_boot => 0,
     },

     {
      class => "CPU",
      string => N("Processors"),
      icon => "cpu.png",
      configurator => "",
      detector => sub { detect_devices::getCPUs() },
      # maybe should we install schedutils?
      checked_on_boot => 0,
     },

     {
      class => "ISDN",
      string => N("ISDN adapters"),
      icon => "modem.png",
      configurator => "$sbindir/drakconnect",
      detector => sub { require network::isdn; my $isdn = network::isdn::detect_backend($modules_conf); if_(@$isdn, f(@$isdn)) },
      # we do not check these b/c this need user interaction (auth, ...):
      checked_on_boot => 0,
     },


     {
      class => "USB_AUDIO",
      string => N("USB sound devices"),
      icon => "sound.png",
      configurator => "",
      detector => sub { f(modules::probe_category('multimedia/usb_sound')) },
      checked_on_boot => 0,
     },

     {
      class => "RADIO",
      string => N("Radio cards"),
      icon => "tv.png",
      configurator => "",
      detector => sub { f(modules::probe_category('multimedia/radio')) },
      checked_on_boot => 0,
     },

     {
      class => "ATM",
      string => N("ATM network cards"),
      icon => "hw_network.png",
      configurator => "",
      detector => sub { f(modules::probe_category('network/atm')) },
      checked_on_boot => 0,
     },

     {
      class => "WAN",
      string => N("WAN network cards"),
      icon => "hw_network.png",
      configurator => "",
      detector => sub { f(modules::probe_category('network/wan')) },
      checked_on_boot => 0,
     },

     {
      class => "BLUETOOTH",
      string => N("Bluetooth devices"),
      icon => "hw_network.png",
      configurator => "",
      detector => sub { f(modules::probe_category('bus/bluetooth')) },
      checked_on_boot => 0,
     },

     {
      class => "ETHERNET",
      string => N("Ethernetcard"),
      icon => "hw_network.png",
      configurator => "$sbindir/drakconnect",
      detector => sub {
          require list_modules;
          my @net_modules = list_modules::category2modules(list_modules::ethernet_categories());
          f(grep {
              $_->{media_type} && $_->{media_type} =~ /^NETWORK/
                || $_->{type} && $_->{type} eq 'network'
                  ||  member($_->{driver}, @net_modules);
          } @devices);
      },
      checked_on_boot => 1,
     },

     {
      class => "MODEM",
      string => N("Modem"),
      icon => "modem.png",
      configurator => "$sbindir/drakconnect",
      detector => sub { detect_devices::getModem($modules_conf) },
      # we do not check these b/c this need user interaction (auth, ...):
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
          $a ? f(map { @$_ } grep { defined($_) } values %$a) : ();
      },
      # we do not check these b/c this need user interaction (auth, ...):
      checked_on_boot => 0,
     },

     {
      class => "MEMORY",
      string => N("Memory"),
      icon => "memory.png",
      configurator => "",
      detector => sub { grep { member($_->{name}, 'Cache', 'Memory Module') } detect_devices::dmidecode() },
      checked_on_boot => 0,
     },

     {
      class => "AGP",
      string => N("AGP controllers"),
      icon => "memory.png",
      configurator => "",
      detector => sub { f(modules::probe_category('various/agpgart')) },
      checked_on_boot => 1,
     },

     {
      class => "PRINTER",
      string => N("Printer"),
      icon => "hw_printer.png",
      configurator => "$sbindir/printerdrake",
      detector => sub { require printer::detect; printer::detect::local_detect() },
      # we do not check these b/c this need user interaction (auth, ...):
      checked_on_boot => 0,
     },



     {
      class => "GAMEPORT",
      string => 
      #-PO: these are joysticks controllers:
      N("Game port controllers"),
      icon => "joystick.png",
      configurator => "",
      detector => sub { f(modules::probe_category('multimedia/gameport')) },
      checked_on_boot => 0,
     },

     {
      class => "JOYSTICK",
      string => N("Joystick"),
      icon => "joystick.png",
      configurator => "",
      detector => sub { f(modules::probe_category('input/joystick')), f(grep { $_->{description} =~ /Joystick/ } @devices) },
      checked_on_boot => 0,
     },


     {
      class => "SATA_STORAGE",
      string => N("SATA controllers"),
      icon => "ide_hd.png",
      configurator => "",
      detector => sub { f(modules::probe_category('disk/sata')) },
      checked_on_boot => 1,
     },

     {
      class => "RAID_STORAGE",
      string => N("RAID controllers"),
      icon => "ide_hd.png",
      configurator => "",
      detector => sub { f(modules::probe_category('disk/hardware_raid')) },
      checked_on_boot => 1,
     },

     {
      class => "ATA_STORAGE",
      string => N("(E)IDE/ATA controllers"),
      icon => "ide_hd.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /STORAGE_(IDE|OTHER)/ } @devices) },
      checked_on_boot => 1,
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
      class => "PCMCIA_CONTROLLER",
      string => N("PCMCIA controllers"),
      icon => "scsi.png",
      configurator => "",
      detector => sub { f(detect_devices::pcmcia_controller_probe()) },
      checked_on_boot => 1,
     },

     {
      class => "SCSI_CONTROLLER",
      string => N("SCSI controllers"),
      icon => "scsi.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /STORAGE_SCSI/ } @devices) },
      checked_on_boot => 1,
     },

     {
      class => "USB_CONTROLLER",
      string => N("USB controllers"),
      icon => "usb.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} eq 'SERIAL_USB' } @devices) },
      checked_on_boot => 1,
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
      class => "BRIDGE",
      string => N("Bridges and system controllers"),
      icon => "memory.png",
      configurator => "",
      detector => sub { f(grep { $_->{media_type} =~ /BRIDGE|MEMORY_RAM|SYSTEM_OTHER/ } @devices) },
      checked_on_boot => 0,
     },

     {
      class => "KEYBOARD",
      string => N("Keyboard"),
      icon => "usb.png",
      configurator => "$sbindir/keyboarddrake",
      detector => sub {
          f(grep { $_->{description} =~ /Keyboard/i } @devices),
            # USB devices are filtered out since we already catch them through probeall():
          grep { $_->{bus} ne 'usb' && $_->{driver} eq 'kbd' && $_->{description} !~ /PC Speaker/ } detect_devices::getInputDevices();
      },
      checked_on_boot => 0,
     },

     {
      class => "MISC_INPUT",
      string => N("Tablet and touchscreen"),
      icon => "hw_mouse.png",
      detector => sub { f(modules::probe_category('input/tablet'), modules::probe_category('input/touchscreen')) },
      configurator => "$sbindir/mousedrake",
      checked_on_boot => 0,
     },

     {
      class => "MOUSE",
      string => N("Mouse"),
      icon => "hw_mouse.png",
      configurator => "$sbindir/mousedrake",
      detector => sub {
          f(grep { $_->{driver} =~ /^Mouse:|^Tablet:/ || $_->{media_type} =~ /class\|Mouse/ } @devices),
            # USB devices are filtered out since we already catch them through probeall():
            grep { $_->{bus} ne 'usb' && $_->{driver} =~ /mouse/ } detect_devices::getInputDevices();
      },
      checked_on_boot => 1,
      automatic => 1,
     },
     
     {
      class => "UPS",
      string => N("UPS"),
      icon => "ups.png",
      configurator => "$sbindir/drakups",
      detector => sub { f(detect_devices::getUPS()) },
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
    my %alt = (
               bus => 'usb_bus',
               description => 'usb_description',
               id => 'usb_id',
               pci_bus => 'usb_pci_bus',
               pci_device => 'usb_pci_device',
               vendor => 'usb_vendor',
               );
    join(':', map { $dev->{$alt{$_}} || $dev->{$_} } qw(bus pci_bus pci_device vendor id subvendor subid description));
}


sub custom_id {
    my ($device, $str) = @_;
    return if !ref($device);
    defined($device->{device}) ? $device->{device} :
        (defined($device->{processor}) ? 
         N("cpu # ") . $device->{processor} . ": " . $device->{'model name'} :
         $device->{"Socket Designation"} ?
         "$device->{name} (" . $device->{"Socket Designation"} . ")" :
         $device->{name} ? $device->{name} :
         (defined($device->{description}) ? $device->{description} : $str));
}

1;
