package mouse; # $Id$

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

my @mouses_fields = qw(nbuttons MOUSETYPE XMOUSETYPE name);

my %mice = 
 arch() =~ /^sparc/ ? 
(
 'sunmouse' =>
 [ [ 'sunmouse' ],
   [ [ 3, 'sun', 'sun', __("Sun - Mouse") ]
   ]]
) :
(
 'PS/2' => 
 [ [ 'psaux' ],
   [ [ 2, 'ps/2', 'PS/2', __("Standard") ],
     [ 5, 'ps/2', 'MouseManPlusPS/2', __("Logitech MouseMan+") ],
     [ 5, 'imps2', 'IMPS/2', __("Generic PS2 Wheel Mouse") ],
     [ 5, 'ps/2', 'GlidePointPS/2', __("GlidePoint") ],
     '',
     [ 5, 'ps/2', 'ThinkingMousePS/2', __("Kensington Thinking Mouse") ],
     [ 5, 'netmouse', 'NetMousePS/2', __("Genius NetMouse") ],
     [ 5, 'netmouse', 'NetScrollPS/2', __("Genius NetScroll") ],
   ]],
     
 'USB' =>
 [ [ 'usbmouse' ],
   [ if_(arch() eq 'ppc', [ 1, 'ps/2', 'PS/2', __("1 button") ]),
     [ 2, 'ps/2', 'PS/2', __("Generic") ],
     [ 5, 'ps/2', 'IMPS/2', __("Wheel") ],
   ]],

 __("serial") =>
 [ [ map { "ttyS$_" } 0..3 ],
   [ [ 2, 'Microsoft', 'Microsoft', __("Generic 2 Button Mouse") ],
     [ 3, 'Microsoft', 'Microsoft', __("Generic 3 Button Mouse") ],
     [ 5, 'ms3', 'IntelliMouse', __("Microsoft IntelliMouse") ],
     [ 3, 'MouseMan', 'MouseMan', __("Logitech MouseMan") ],
     [ 2, 'MouseSystems', 'MouseSystems', __("Mouse Systems") ],     
     '',
     [ 3, 'logim', 'MouseMan', __("Logitech CC Series") ],
     [ 5, 'pnp', 'IntelliMouse', __("Logitech MouseMan+/FirstMouse+") ],
     [ 5, 'ms3', 'IntelliMouse', __("Genius NetMouse") ],
     [ 2, 'MMSeries', 'MMSeries', __("MM Series") ],
     [ 2, 'MMHitTab', 'MMHittab', __("MM HitTablet") ],
     [ 3, 'Logitech', 'Logitech', __("Logitech Mouse (serial, old C7 type)") ],
     [ 3, 'Microsoft', 'ThinkingMouse', __("Kensington Thinking Mouse") ],
   ]],

 __("busmouse") =>
 [ [ arch() eq 'ppc' ? 'adbmouse' : ('atibm', 'inportbm', 'logibm') ],
   [ if_(arch() eq 'ppc', [ 1, 'Busmouse', 'BusMouse', __("1 button") ]),
     [ 2, 'Busmouse', 'BusMouse', __("2 buttons") ],
     [ 3, 'Busmouse', 'BusMouse', __("3 buttons") ],
   ]],

 __("none") =>
 [ [ 'none' ],
   [ [ 0, 'none', 'Microsoft', __("No mouse") ],
   ]],
);


sub xmouse2xId { 
    #- xmousetypes must be sorted as found in /usr/include/X11/extensions/xf86misc.h
    #- so that first mean "0", etc
    my @xmousetypes = (
		   "Microsoft",
		   "MouseSystems",
		   "MMSeries",
		   "Logitech",
		   "BusMouse", #MouseMan,
		   "Logitech",
		   "PS/2",
		   "MMHittab",
		   "GlidePoint",
		   "IntelliMouse",
		   "ThinkingMouse",
		   "IMPS/2",
		   "ThinkingMousePS/2",
		   "MouseManPlusPS/2",
		   "GlidePointPS/2",
		   "NetMousePS/2",
		   "NetScrollPS/2",
		   "SysMouse",
		   "Auto",
		   "AceCad",
		   "WSMouse",
		   "USB",
    );
    my ($id) = @_;
    $id = 'BusMouse' if $id eq 'MouseMan';
    my $i; map_index { $_ eq $id and $i = $::i } @xmousetypes; $i;
}

my %mouse_btn_keymap = (
    0   => "NONE",
    67  => "F9",
    68  => "F10",
    87  => "F11",
    88  => "F12",
    85  => "F13",
    89  => "F14",
    90  => "F15",
    56  => "L-Option/Alt",
    125 => "L-Command",
    98  => "Num: /",
    55  => "Num: *",
    117 => "Num: =",
);
sub ppc_one_button_keys { keys %mouse_btn_keymap }
sub ppc_one_button_key2text { $mouse_btn_keymap{$_[0]} }

sub raw2mouse {
    my ($type, $raw) = @_;
    $raw or return;

    my %l; @l{@mouses_fields} = @$raw;
    +{ %l, type => $type };
}

sub fullnames { 
    map_each { 
	my $type = $::a;
	grep {$_} map {
	    if ($_) {
		my $l = raw2mouse($type, $_);
		"$type|$l->{name}";
	    } else { 
		$type .= "|[" . _("Other") . "]";
		'';
	    }
	} @{$::b->[1]}
    } %mice;
}

sub fullname2mouse {
    my ($fname, %opts) = @_;
    my ($type, @l) = split '\|', $fname;
    my ($name) = pop @l;
    $opts{device} ||= $mice{$type}[0][0];
    foreach (@{$mice{$type}[1]}) {
	my $l = raw2mouse($type, $_);
	$name eq $l->{name} and return { %$l, %opts };
    }
    die "$fname not found ($type, $name)";
}

sub serial_ports() { map { "ttyS$_" } 0..7 }
sub serial_port2text {
    $_[0] =~ /ttyS (\d+)/x ? "$_[0] / COM" . ($1 + 1) : $_[0];
}

sub read {
    my ($prefix) = @_;
    my %mouse = getVarsFromSh "$prefix/etc/sysconfig/mouse";
    eval { add2hash_(\%mouse, fullname2mouse($mouse{FULLNAME})) };
    $mouse{device} = readlink "$prefix/dev/mouse" or log::l("reading $prefix/dev/mouse symlink failed");
    $mouse{nbuttons} = $mouse{XEMU3} eq "yes" ? 2 : $mouse{WHEEL} eq "yes" ? 5 : 3;
    \%mouse;
}

sub write {
    my ($prefix, $mouse) = @_;
    local $mouse->{FULLNAME} = qq("$mouse->{type}|$mouse->{name}"); #-"
    local $mouse->{XEMU3} = bool2yesno($mouse->{nbuttons} < 3);
    local $mouse->{WHEEL} = bool2yesno($mouse->{nbuttons} > 3);
    setVarsInSh("$prefix/etc/sysconfig/mouse", $mouse, qw(MOUSETYPE XMOUSETYPE FULLNAME XEMU3 WHEEL device));
    symlinkf $mouse->{device}, "$prefix/dev/mouse" or log::l("creating $prefix/dev/mouse symlink failed");

    if (arch() =~ /ppc/) {
	my $s = join('',
	  "dev.mac_hid.mouse_button_emulation = " . bool($mouse->{button2_key} || $mouse->{button3_key}) . "\n",
	  if_($mouse->{button2_key}, "dev.mac_hid.mouse_button2_keycode = $mouse->{button2_key}\n"),
	  if_($mouse->{button3_key}, "dev.mac_hid.mouse_button3_keycode = $mouse->{button3_key}\n"),
	);
	substInFile { 
	    $_ = '' if /^\Qdev.mac_hid.mouse_button/;
	    $_ .= $s if eof;
	} "$prefix/etc/sysctl.conf";
	#- hack - dev RPM symlinks to mouse0 - lands on mouse1 with new input layer on PPC input/mice will get both ADB and USB
	symlinkf "/dev/input/mice", "$prefix/dev/usbmouse" if ($mouse->{device} eq "usbmouse");    
    }
}

sub mouseconfig {
    my ($t, $mouse, @wacom);

    #- Whouah! probing all devices from ttyS0 to ttyS3 once a time!
    detect_devices::probeSerialDevices();

    #- check new probing methods keep everything used here intact!
    foreach (0..3) {
	$t = detect_devices::probeSerial("/dev/ttyS$_");
	if ($t->{CLASS} eq 'MOUSE') {
	    $t->{MFG} ||= $t->{MANUFACTURER};

	    $mouse = fullname2mouse("serial|Microsoft IntelliMouse") if $t->{MFG} eq 'MSH' && $t->{MODEL} eq '0001';
	    $mouse = fullname2mouse("serial|Logitech MouseMan") if $t->{MFG} eq 'LGI' && $t->{MODEL} =~ /^80/;
	    $mouse = fullname2mouse("serial|Genius NetMouse") if $t->{MFG} eq 'KYE' && $t->{MODEL} eq '0003';

	    $mouse ||= fullname2mouse("serial|Generic 2 Button Mouse"); #- generic by default.
	    $mouse->{device} = "ttyS$_";
	    last;
	} elsif ($t->{CLASS} eq "PEN" || $t->{MANUFACTURER} eq "WAC") {
	    push @wacom, "ttyS$_";
	}
    }
    $mouse, @wacom;
}

sub detect() {
    if (arch() =~ /^sparc/) {
	return fullname2mouse("sunmouse|Sun - Mouse");
    }
    if (arch() eq "ppc") {
        return fullname2mouse(detect_devices::hasMousePS2("usbmouse") ? 
			      "USB|1 button" :
			      # No need to search for an ADB mouse.  If I did, the PPC kernel would
			      # find one whether or not I had one installed!  So..  default to it.
			      "busmouse|1 button");
    }

    my @wacom;
    my $fast_mouse_probe = sub {
	my $auxmouse = detect_devices::hasMousePS2("psaux") && fullname2mouse("PS/2|Standard", unsafe => 1);

	if (modules::get_alias("usb-interface")) {
	    if (my (@l) = detect_devices::usbMice()) {
		log::l("found usb mouse $_->{driver} $_->{description} ($_->{type})") foreach @l;
		eval { modules::load("usbmouse"); modules::load("mousedev"); };
		if (!$@ && detect_devices::tryOpen("usbmouse")) {
		    my $mouse = fullname2mouse($l[0]{driver} =~ /Mouse:(.*)/ ? $1 : "USB|Generic");
		    $auxmouse and $mouse->{auxmouse} = $auxmouse; #- for laptop, we kept the PS/2 as secondary (symbolic).
		    return $mouse;
		}
		eval { modules::unload("mousedev"); modules::unload("usbmouse"); };
	    }
	}
	$auxmouse;
    };

    if (modules::get_alias("usb-interface")) {
	my $keep_mouse;
	if (my (@l) = detect_devices::usbWacom()) {
	    log::l("found usb wacom $_->{driver} $_->{description} ($_->{type})") foreach @l;
	    eval { modules::load("wacom"); modules::load("evdev"); };
	    unless ($@) {
		foreach (0..$#l) {
		    detect_devices::tryOpen("input/event$_") and $keep_mouse = 1, push @wacom, "input/event$_";
		}
	    }
	    $keep_mouse or eval { modules::unload("evdev"); modules::unload("wacom"); };
	}
    }

    #- at this level, not all possible mice are detected so avoid invoking serial_probe
    #- which takes a while for its probe.
    if ($::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$mouse and return ($mouse, @wacom);
    }

    #- probe serial device to make sure a wacom has been detected.
    eval { modules::load("serial") };
    my ($r, @serial_wacom) = mouseconfig(); push @wacom, @serial_wacom;

    if (!$::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$r && $mouse and $r->{auxmouse} = $mouse; #- we kept the auxilliary mouse as PS/2.
	$r and return ($r, @wacom);
	$mouse and return ($mouse, @wacom);
    } else {
	$r and return ($r, @wacom);
    }

    #- in case only a wacom has been found, assume an inexistant mouse (necessary).
    @wacom and return { CLASS      => 'MOUSE',
			nbuttons   => 2,
			device     => "nothing",
			MOUSETYPE  => "Microsoft",
			XMOUSETYPE => "Microsoft"}, @wacom;

    #- defaults to generic serial mouse on ttyS0.
    #- Oops? using return let return a hash ref, if not using it, it return a list directly :-)
    return fullname2mouse("serial|Generic 2 Button Mouse", unsafe => 1);
}

#- write_conf : write the mouse infos into the Xconfig files.
#- input :
#-  $mouse : the hashtable containing the informations
#- $mouse input
#-  $mouse->{nbuttons} : number of buttons : integer
#-  $mouse->{device} : device of the mouse : string : ex 'psaux'
#-  $mouse->{XMOUSETYPE} : type of the mouse for gpm : string : ex 'PS/2'
#-  $mouse->{type} : type (generic ?) of the mouse : string : ex 'PS/2'
#-  $mouse->{name} : name of the mouse : string : ex 'Standard'
#-  $mouse->{MOUSETYPE} : type of the mouse : string : ex "ps/2"
#-  $mouse->{XEMU3} : emulate 3rd button : string : 'yes' or 'no'
sub write_conf {
    my ($mouse) = @_;

    &write('', $mouse);
    modules::write_conf('') if $mouse->{device} eq "usbmouse" && !$::testing;

    my $f = "/etc/X11/XF86Config";
    my $g = "/etc/X11/XF86Config-4";

    my $update_mouse = sub {
	my ($mouse, $id) = @_;

	my @zaxis = (
		     $mouse->{nbuttons} > 3 ? [ "ZAxisMapping", "4 5" ] : (),
		     $mouse->{nbuttons} > 5 ? [ "ZAxisMapping", "6 7" ] : (),
		     $mouse->{nbuttons} < 3 ? ([ "Emulate3Buttons" ], [ "Emulate3Timeout", "50" ]) : ()
		    );

	my $zaxis = join('', map { qq(\n    $_->[0]) . ($_->[1] && qq( $_->[1])) } @zaxis);
	substInFile {
	    if ($id > 1) {
		if (/^DeviceName\s+"Mouse$id"/ .. /^EndSection/) {
		    $_ = '' if /(ZAxisMapping|Emulate3)/; #- remove existing line
		    s|^(\s*Protocol\s+).*|$1"$mouse->{XMOUSETYPE}"|;
		    s|^(\s*Device\s+).*|$1"/dev/mouse"$zaxis|;
		}
	    } else {
		if (/^Section\s+"Pointer"/ .. /^EndSection/) {
		    $_ = '' if /(ZAxisMapping|Emulate3)/; #- remove existing line
		    s|^(\s*Protocol\s+).*|$1"$mouse->{XMOUSETYPE}"|;
		    s|^(\s*Device\s+).*|$1"/dev/mouse"$zaxis|;
		}
	    }
	} $f if -e $f && !$::testing;

	$zaxis = join('', map { qq(\n    Option "$_->[0]") . ($_->[1] && qq( "$_->[1]")) } @zaxis);
	substInFile {
	    if (/Identifier\s+"Mouse$id"/ .. /^EndSection/) {
		$_ = '' if /(ZAxisMapping|Emulate3)/; #- remove existing line
		s|^(\s*Option\s+"Protocol"\s+).*|$1"$mouse->{XMOUSETYPE}"|;
		s|^(\s*Option\s+"Device"\s+).*|$1"/dev/mouse"$zaxis|;
	    }
	} $g if -e $g && !$::testing;
    };
    $update_mouse->($mouse, 1);
    $mouse->{auxmouse} and $update_mouse->($mouse->{auxmouse}, 2);
}
