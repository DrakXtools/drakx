package mouse;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :functional);
use log;

my @mouses_fields = qw(nbuttons device MOUSETYPE XMOUSETYPE FULLNAME);
my @mouses = (
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

sub serial_ports_names {
    map { "ttyS" . ($_ - 1) . " / COM$_" } 1..4;
}
sub serial_ports_names2dev {
    local ($_) = @_;
    /(\w+)/;
}

sub read($) { getVarsFromSh $_[0]; }

sub write($;$) {
    my ($mouse, $prefix) = @_;
    setVarsInSh("$prefix/etc/sysconfig/mouse", $mouse, qw(MOUSETYPE XMOUSETYPE FULLNAME XEMU3));
    symlink $mouse->{device}, "$prefix/dev/mouse" or log::l("creating $prefix/dev/mouse symlink failed");
}

sub detect() {
    my %l;
    @l{qw(FULLNAME nbuttons MOUSETYPE XMOUSETYPE device)} = split("\n", `mouseconfig --nointeractive 2>/dev/null`) or die "mouseconfig failed";
    \%l;
}
