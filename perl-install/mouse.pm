package mouse;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :functional :file);
use modules;
use detect_devices;
use run_program;
use devices;
use commands;
use modules;
use log;

my @mouses_fields = qw(nbuttons device MOUSETYPE XMOUSETYPE FULLNAME);
my @mouses = (
arch() =~ /^sparc/ ? (
  [ 3, "sunmouse", "sun",       "sun",            __("Sun - Mouse") ],
) : arch() eq "ppc" ? (
  [ 1, "adbmouse", "Busmouse",  "BusMouse",       __("Apple ADB Mouse") ],
  [ 2, "adbmouse", "Busmouse",  "BusMouse",       __("Apple ADB Mouse (2 Buttons)") ],
  [ 3, "adbmouse", "Busmouse",  "BusMouse",       __("Apple ADB Mouse (3+ Buttons)") ],
  [ 1, "usbmouse", "imps2",     "IMPS/2",         __("Apple USB Mouse") ],
  [ 2, "usbmouse", "imps2",     "IMPS/2",         __("Apple USB Mouse (2 Buttons)") ],
  [ 3, "usbmouse", "imps2",     "IMPS/2",         __("Apple USB Mouse (3+ Buttons)") ],
) : (
  [ 2, "psaux", "ps/2",         "PS/2",           __("Generic Mouse (PS/2)") ],
  [ 3, "psaux", "ps/2",         "PS/2",           __("Logitech MouseMan/FirstMouse (ps/2)") ],
  [ 3, "psaux", "ps/2",         "PS/2",           __("Generic 3 Button Mouse (PS/2)") ],
  [ 2, "psaux", "ps/2",      "GlidePointPS/2",    __("ALPS GlidePoint (PS/2)") ],
  [ 5, "psaux", "ps/2",      "MouseManPlusPS/2",  __("Logitech MouseMan+/FirstMouse+ (PS/2)") ],
  [ 5, "psaux", "ps/2",      "ThinkingMousePS/2", __("Kensington Thinking Mouse (PS/2)") ],
  [ 5, "psaux", "ps/2",         "NetMousePS/2",   __("ASCII MieMouse (PS/2)") ],
  [ 5, "psaux", "netmouse",     "NetMousePS/2",   __("Genius NetMouse (PS/2)") ],
  [ 5, "psaux", "netmouse",     "NetMousePS/2",   __("Genius NetMouse Pro (PS/2)") ],
  [ 5, "psaux", "netmouse",     "NetScrollPS/2",  __("Genius NetScroll (PS/2)") ],
  [ 5, "psaux", "imps2",        "IMPS/2",         __("Microsoft IntelliMouse (PS/2)") ],
  [ 2, "atibm",    "Busmouse",  "BusMouse",   	  __("ATI Bus Mouse") ],
  [ 2, "inportbm", "Busmouse",  "BusMouse",       __("Microsoft Bus Mouse") ],
  [ 3, "logibm",   "Busmouse",  "BusMouse",       __("Logitech Bus Mouse") ],
  [ 2, "usbmouse", "ps/2",      "PS/2",           __("USB Mouse") ],
  [ 3, "usbmouse", "ps/2",      "PS/2",           __("USB Mouse (3 buttons or more)") ],
),
  [ 0, "none",  "none",         "Microsoft",      __("No Mouse") ],
  [ 2, "ttyS",  "pnp",          "Auto",           __("Microsoft Rev 2.1A or higher (serial)") ],
  [ 3, "ttyS",  "logim",        "MouseMan",       __("Logitech CC Series (serial)") ],
  [ 5, "ttyS",  "pnp",          "IntelliMouse",   __("Logitech MouseMan+/FirstMouse+ (serial)") ],
  [ 5, "ttyS",  "ms3",          "IntelliMouse",   __("ASCII MieMouse (serial)") ],
  [ 5, "ttyS",  "ms3",          "IntelliMouse",   __("Genius NetMouse (serial)") ],
  [ 5, "ttyS",  "ms3",          "IntelliMouse",   __("Microsoft IntelliMouse (serial)") ],
  [ 2, "ttyS",  "MMSeries",     "MMSeries",       __("MM Series (serial)") ],
  [ 2, "ttyS",  "MMHitTab",     "MMHittab",       __("MM HitTablet (serial)") ],
  [ 3, "ttyS",  "Logitech",     "Logitech",       __("Logitech Mouse (serial, old C7 type)") ],
  [ 3, "ttyS",  "MouseMan",     "MouseMan",       __("Logitech MouseMan/FirstMouse (serial)") ],
  [ 2, "ttyS",  "Microsoft",    "Microsoft",  	  __("Generic Mouse (serial)") ],
  [ 2, "ttyS",  "Microsoft",    "Microsoft",      __("Microsoft compatible (serial)") ],
  [ 3, "ttyS",  "Microsoft",    "Microsoft",  	  __("Generic 3 Button Mouse (serial)") ],
  [ 2, "ttyS",  "MouseSystems", "MouseSystems",   __("Mouse Systems (serial)") ],
);
map_index {
    my %l; @l{@mouses_fields} = @$_;
    $mouses[$::i] = \%l;
} @mouses;

sub names { map { $_->{FULLNAME} } @mouses }

sub name2mouse {
    my ($name) = @_;
    foreach (@mouses) {
	return { %$_ } if $name eq $_->{FULLNAME};
    }
    die "$name not found";
}

sub serial_ports_names() {
    map { "ttyS" . ($_ - 1) . " / COM$_" } 1..4;
}
sub serial_ports_names2dev {
    local ($_) = @_;
    first(/(\w+)/);
}

sub read($) {
    my ($prefix) = @_;
    my %mouse = getVarsFromSh "$prefix/etc/sysconfig/mouse";
    $mouse{device} = readlink "$prefix/dev/mouse" or log::l("reading $prefix/dev/mouse symlink failed");
    %mouse;
}

sub write($;$) {
    my ($prefix, $mouse) = @_;
    local $mouse->{FULLNAME} = qq("$mouse->{FULLNAME}");
    local $mouse->{WHEEL} = bool2yesno($mouse->{nbuttons} > 3);
    setVarsInSh("$prefix/etc/sysconfig/mouse", $mouse, qw(MOUSETYPE XMOUSETYPE FULLNAME XEMU3 WHEEL device));
    symlinkf $mouse->{device}, "$prefix/dev/mouse" or log::l("creating $prefix/dev/mouse symlink failed");
}

sub mouseconfig {
    my ($t, $mouse, $wacom);

    #- Whouah! probing all devices from ttyS0 to ttyS3 once a time!
    detect_devices::probeSerialDevices();

    #- check new probing methods keep everything used here intact!
    foreach (0..3) {
	$t = detect_devices::probeSerial("/dev/ttyS$_");
	if ($t->{CLASS} eq 'MOUSE') {
	    $t->{MFG} ||= $t->{MANUFACTURER};

	    $mouse = name2mouse("Microsoft IntelliMouse (serial)") if $t->{MFG} eq 'MSH' && $t->{MODEL} eq '0001';
	    $mouse = name2mouse("Logitech MouseMan/FirstMouse (serial)") if $t->{MFG} eq 'LGI' && $t->{MODEL} =~ /^80/;
	    $mouse = name2mouse("Genius NetMouse (serial)") if $t->{MFG} eq 'KYE' && $t->{MODEL} eq '0003';

	    $mouse ||= name2mouse("Generic Mouse (serial)"); #- generic by default.
	    $mouse->{device} = "ttyS$_";
	    last;
	} elsif ($t->{CLASS} eq "PEN" || $t->{MANUFACTURER} eq "WAC") {
	    $wacom = "ttyS$_";
	}
    }
    $mouse, $wacom;
}

sub detect() {
    return name2mouse("Sun - Mouse") if arch() =~ /^sparc/;

    if (arch() eq "ppc") {
        return name2mouse("Apple USB Mouse") if detect_devices::hasMouseMacUSB;
        # No need to search for an ADB mouse.  If I did, the PPC kernel would
        # find one whether or not I had one installed!  So..  default to it.
        return name2mouse("Apple ADB Mouse");
    }

    detect_devices::hasMousePS2 and return name2mouse("Generic Mouse (PS/2)");

    eval { commands::modprobe("serial") };
    my ($r, $wacom) = mouseconfig(); return ($r, $wacom) if $r;

    require pci_probing::main;
    if (my ($c) = grep { $_->[1] =~ /usb-/ } pci_probing::main::probe('')) {
	eval { 
	    modules::load($c->[1], "SERIAL_USB");
	    modules::load("usbmouse");
	    modules::load("mousedev");
	   };
	sleep(1);
	if (!$@ && detect_devices::tryOpen("usbmouse")) {
	    $wacom or modules::unload("serial"); 
	    modules::load("usbkbd");
	    modules::load("keybdev");
	    return name2mouse("USB Mouse"), $wacom;
	}
	modules::unload("mousedev");
	modules::unload("usbmouse");
	modules::unload($c->[1], 'remove_alias');
    }

    #- defaults to generic ttyS0
    add2hash({ device => "ttyS0", unsafe => 1 }, name2mouse("Generic Mouse (serial)"));
}
