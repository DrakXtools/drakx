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
     [ 5, 'imps2', 'IMPS/2', __("Microsoft IntelliMouse") ],
     [ 5, 'ps/2', 'GlidePointPS/2', __("GlidePoint") ],
     '',
     [ 5, 'ps/2', 'ThinkingMousePS/2', __("Kensington Thinking Mouse") ],
     [ 5, 'netmouse', 'NetMousePS/2', __("Genius NetMouse") ],
     [ 5, 'netmouse', 'NetScrollPS/2', __("Genius NetScroll") ],
   ]],
     
 'USB' =>
 [ [ 'usbmouse' ],
   [ [ 2, 'ps/2', 'PS/2', __("Generic") ],
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

 'busmouse' =>
 [ [ arch() eq 'ppc' ? 'adbmouse' : ('atibm', 'inportbm', 'logibm') ],
   [ [ 2, 'Busmouse', 'BusMouse', __("2 buttons") ],
     [ 3, 'Busmouse', 'BusMouse', __("3 buttons") ],
   ]],

 'none' =>
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
		$type .= "|[" . _("Other");
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

sub serial_ports() { map { "ttyS$_" } 0..3 }
sub serial_port2text {
    $_[0] =~ /ttyS (\d+)/x;
    "$_[0] / COM" . ($1 + 1);
}

sub read {
    my ($prefix) = @_;
    my %mouse = getVarsFromSh "$prefix/etc/sysconfig/mouse";
    add2hash_(\%mouse, fullname2mouse($mouse{FULLNAME}));
    $mouse{device} = readlink "$prefix/dev/mouse" or log::l("reading $prefix/dev/mouse symlink failed");
    $mouse{nbuttons} = $mouse{XEMU3} eq "yes" ? 2 : $mouse{WHEEL} eq "yes" ? 5 : 3;
    \%mouse;
}

sub write {
    my ($prefix, $mouse) = @_;
    local $mouse->{FULLNAME} = qq("$mouse->{type}|$mouse->{name}");
    local $mouse->{XEMU3} = bool2yesno($mouse->{nbuttons} < 3);
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

	    $mouse = fullname2mouse("serial|Microsoft IntelliMouse") if $t->{MFG} eq 'MSH' && $t->{MODEL} eq '0001';
	    $mouse = fullname2mouse("serial|Logitech MouseMan") if $t->{MFG} eq 'LGI' && $t->{MODEL} =~ /^80/;
	    $mouse = fullname2mouse("serial|Genius NetMouse") if $t->{MFG} eq 'KYE' && $t->{MODEL} eq '0003';

	    $mouse ||= fullname2mouse("serial|Generic 2 Button Mouse"); #- generic by default.
	    $mouse->{device} = "ttyS$_";
	    last;
	} elsif ($t->{CLASS} eq "PEN" || $t->{MANUFACTURER} eq "WAC") {
	    $wacom = "ttyS$_";
	}
    }
    $mouse, $wacom;
}

sub detect() {
    if (arch() =~ /^sparc/) {
	return fullname2mouse("sunmouse|Sun - Mouse");
    }
    if (arch() eq "ppc") {
        return fullname2mouse(detect_devices::hasMousePS2("usbmouse") ? 
			      "USB|Generic" :
			      # No need to search for an ADB mouse.  If I did, the PPC kernel would
			      # find one whether or not I had one installed!  So..  default to it.
			      "busmouse|2 buttons");
    }
    
    if ($::isStandalone) {
        detect_devices::hasMousePS2("psaux") and return fullname2mouse("PS/2|Standard", unsafe => 1);
    }

    #- probe serial device to make sure a wacom has been detected.
    eval { commands::modprobe("serial") };
    my ($r, $wacom) = mouseconfig(); return ($r, $wacom) if $r;

    if (!$::isStandalone) {
        detect_devices::hasMousePS2("psaux") and return fullname2mouse("PS/2|Standard", unsafe => 1), $wacom;
    }

    if (modules::get_alias("usb-interface") && detect_devices::hasUsbMouse()) {
	eval { 
	    modules::load("usbmouse");
	    modules::load("mousedev");
	};
	!$@ && detect_devices::tryOpen("usbmouse") and return fullname2mouse("USB|Generic"), $wacom;
	eval { 
	    modules::unload("mousedev");
	    modules::unload("usbmouse");
	}
    }

    #- in case only a wacom has been found, assume an inexistant mouse (necessary).
    $wacom and 	return { CLASS      => 'MOUSE',
			 nbuttons   => 2,
			 device     => "nothing",
			 MOUSETYPE  => "Microsoft",
			 XMOUSETYPE => "Microsoft"}, $wacom;

    #- defaults to generic serial mouse on ttyS0.
    #- Oops? using return let return a hash ref, if not using it, it return a list directly :-)
    return fullname2mouse("serial|Generic 2 Button Mouse", unsafe => 1);
}
