package mouse; # $Id$

#use diagnostics;
#use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;
use detect_devices;
use run_program;
use devices;
use modules;
use any;
use log;

my @mouses_fields = qw(nbuttons MOUSETYPE XMOUSETYPE name EMULATEWHEEL);

my %mice = 
 arch() =~ /^sparc/ ? 
(
 'sunmouse' =>
 [ [ 'sunmouse' ],
   [ [ 3, 'sun', 'sun', N_("Sun - Mouse") ]
   ] ]
) :
(
 'PS/2' => 
 [ [ 'psaux' ],
   [ [ 2, 'ps/2', 'PS/2', N_("Standard") ],
     [ 5, 'ps/2', 'MouseManPlusPS/2', N_("Logitech MouseMan+") ],
     [ 5, 'imps2', 'IMPS/2', N_("Generic PS2 Wheel Mouse") ],
     [ 5, 'ps/2', 'GlidePointPS/2', N_("GlidePoint") ],
     '',
     [ 5, 'ps/2', 'ThinkingMousePS/2', N_("Kensington Thinking Mouse") ],
     [ 5, 'netmouse', 'NetMousePS/2', N_("Genius NetMouse") ],
     [ 5, 'netmouse', 'NetScrollPS/2', N_("Genius NetScroll") ],
     [ 7, 'ps/2', 'ExplorerPS/2', N_("Microsoft Explorer") ],
   ] ],
     
 'USB' =>
 [ [ 'usbmouse' ],
   [ [ 1, 'ps/2', 'IMPS/2', N_("1 button") ],
     [ 2, 'ps/2', 'IMPS/2', N_("Generic 2 Button Mouse") ],
     [ 3, 'ps/2', 'IMPS/2', N_("Generic") ],
     [ 3, 'ps/2', 'IMPS/2', N_("Generic 3 Button Mouse with Wheel emulation"), 'wheel' ],
     [ 5, 'ps/2', 'IMPS/2', N_("Wheel") ],
     [ 7, 'ps/2', 'ExplorerPS/2', N_("Microsoft Explorer") ],
   ] ],

 N_("serial") =>
 [ [ map { "ttyS$_" } 0..3 ],
   [ [ 2, 'Microsoft', 'Microsoft', N_("Generic 2 Button Mouse") ],
     [ 3, 'Microsoft', 'Microsoft', N_("Generic 3 Button Mouse") ],
     [ 3, 'Microsoft', 'Microsoft', N_("Generic 3 Button Mouse with Wheel emulation"), 'wheel' ],
     [ 5, 'ms3', 'IntelliMouse', N_("Microsoft IntelliMouse") ],
     [ 3, 'MouseMan', 'MouseMan', N_("Logitech MouseMan") ],
     [ 3, 'MouseMan', 'MouseMan', N_("Logitech MouseMan with Wheel emulation"), 'wheel' ],
     [ 2, 'MouseSystems', 'MouseSystems', N_("Mouse Systems") ],     
     '',
     [ 3, 'logim', 'MouseMan', N_("Logitech CC Series") ],
     [ 3, 'logim', 'MouseMan', N_("Logitech CC Series with Wheel emulation"), 'wheel' ],
     [ 5, 'pnp', 'IntelliMouse', N_("Logitech MouseMan+/FirstMouse+") ],
     [ 5, 'ms3', 'IntelliMouse', N_("Genius NetMouse") ],
     [ 2, 'MMSeries', 'MMSeries', N_("MM Series") ],
     [ 2, 'MMHitTab', 'MMHittab', N_("MM HitTablet") ],
     [ 3, 'Logitech', 'Logitech', N_("Logitech Mouse (serial, old C7 type)") ],
     [ 3, 'Logitech', 'Logitech', N_("Logitech Mouse (serial, old C7 type) with Wheel emulation"), 'wheel' ],
     [ 3, 'Microsoft', 'ThinkingMouse', N_("Kensington Thinking Mouse") ],
     [ 3, 'Microsoft', 'ThinkingMouse', N_("Kensington Thinking Mouse with Wheel emulation"), 'wheel' ],
   ] ],

 N_("busmouse") =>
 [ [ arch() eq 'ppc' ? 'adbmouse' : ('atibm', 'inportbm', 'logibm') ],
   [ if_(arch() eq 'ppc', [ 1, 'Busmouse', 'BusMouse', N_("1 button") ]),
     [ 2, 'Busmouse', 'BusMouse', N_("2 buttons") ],
     [ 3, 'Busmouse', 'BusMouse', N_("3 buttons") ],
     [ 3, 'Busmouse', 'BusMouse', N_("3 buttons with Wheel emulation"), 'wheel' ],
   ] ],

 N_("none") =>
 [ [ 'none' ],
   [ [ 0, 'none', 'Microsoft', N_("No mouse") ],
   ] ],
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
		   "ExplorerPS/2",
		   "USB",
    );
    my ($id) = @_;
    $id = 'BusMouse' if $id eq 'MouseMan';
    $id = 'IMPS/2' if $id eq 'ExplorerPS/2' && $::isInstall;
    eval { find_index { $_ eq $id } @xmousetypes } || 0;
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
    125 => "L-Command (Apple)",
    98  => "Num: /",
    55  => "Num: *",
    117 => "Num: =",
    96 => "Enter",
);
sub ppc_one_button_keys() { keys %mouse_btn_keymap }
sub ppc_one_button_key2text { $mouse_btn_keymap{$_[0]} }

sub raw2mouse {
    my ($type, $raw) = @_;
    $raw or return;

    my %l; @l{@mouses_fields} = @$raw;
    +{ %l, type => $type };
}

sub fullnames() { 
    map_each { 
	my $type = $::a;
	grep { $_ } map {
	    if ($_) {
		my $l = raw2mouse($type, $_);
		"$type|$l->{name}";
	    } else { 
		$type .= "|[" . N("Other") . "]";
		'';
	    }
	} @{$::b->[1]}
    } %mice;
}

sub fullname2mouse {
    my ($fname, %opts) = @_;
    my ($type, @l) = split '\|', $fname;
    my ($name) = pop @l;
  search:
    $opts{device} ||= $mice{$type}[0][0];
    foreach (@{$mice{$type}[1]}) {
	my $l = raw2mouse($type, $_);
	$name eq $l->{name} and return { %$l, %opts };
    }
    if ($name eq '1 Button' || $name eq '1 button') {
	$name = "Generic 2 Button Mouse";
	goto search;
    }
    die "$fname not found ($type, $name)";
}

sub serial_ports() { map { "ttyS$_" } 0..7 }
sub serial_port2text {
    $_[0] =~ /ttyS(\d+)/ ? "$_[0] / COM" . ($1 + 1) : $_[0];
}

sub read() {
    my %mouse = getVarsFromSh "$::prefix/etc/sysconfig/mouse";
    eval { add2hash_(\%mouse, fullname2mouse($mouse{FULLNAME})) };
    $mouse{nbuttons} ||= $mouse{XEMU3} eq "yes" ? 2 : $mouse{WHEEL} eq "yes" ? 5 : 3;
    \%mouse;
}

sub write {
    my ($in, $mouse) = @_;
    local $mouse->{FULLNAME} = qq("$mouse->{type}|$mouse->{name}"); #-"
    local $mouse->{XEMU3} = bool2yesno($mouse->{nbuttons} < 3);
    local $mouse->{WHEEL} = bool2yesno($mouse->{nbuttons} > 3);
    setVarsInSh("$::prefix/etc/sysconfig/mouse", $mouse, qw(MOUSETYPE XMOUSETYPE FULLNAME XEMU3 WHEEL device));
    any::devfssymlinkf($mouse, 'mouse');

    #- we should be using input/mice directly instead of usbmouse, but legacy...
    symlinkf 'input/mice', "$::prefix/dev/usbmouse" if $mouse->{device} eq "usbmouse";

    any::devfssymlinkf($mouse->{auxmouse}, 'mouse1') if $mouse->{auxmouse};


    various_xfree_conf($in, $mouse);

    if (arch() =~ /ppc/) {
	my $s = join('',
	  "dev.mac_hid.mouse_button_emulation = " . to_bool($mouse->{button2_key} || $mouse->{button3_key}) . "\n",
	  if_($mouse->{button2_key}, "dev.mac_hid.mouse_button2_keycode = $mouse->{button2_key}\n"),
	  if_($mouse->{button3_key}, "dev.mac_hid.mouse_button3_keycode = $mouse->{button3_key}\n"),
	);
	substInFile { 
	    $_ = '' if /^\Qdev.mac_hid.mouse_button/;
	    $_ .= $s if eof;
	} "$::prefix/etc/sysctl.conf";
    }
}

sub mouseconfig() {
    my ($t, $mouse, @wacom);

    #- Whouah! probing all devices from ttyS0 to ttyS3 once a time!
    detect_devices::probeSerialDevices();

    #- check new probing methods keep everything used here intact!
    foreach (0..3) {
	$t = detect_devices::probeSerial("/dev/ttyS$_") or next;
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

	#- workaround for some special case were mouse is openable 1/2.
	unless ($auxmouse) {
	    $auxmouse = detect_devices::hasMousePS2("psaux") && fullname2mouse("PS/2|Generic PS2 Wheel Mouse", unsafe => 0);
	    $auxmouse and detect_devices::hasMousePS2("psaux"); #- fake another open in order for XFree to see the mouse.
	}

	if (modules::get_probeall("usb-interface")) {
	    if (my (@l) = detect_devices::usbMice()) {
		log::l(join('', "found usb mouse $_->{driver} $_->{description} (", if_($_->{type}, $_->{type}), ")")) foreach @l;
		eval { modules::load(qw(hid mousedev usbmouse)) };
		if (!$@ && detect_devices::tryOpen("usbmouse")) {
		    my $mouse = fullname2mouse($l[0]{driver} =~ /Mouse:(.*)/ ? $1 : "USB|Wheel");
		    $auxmouse and $mouse->{auxmouse} = $auxmouse; #- for laptop, we kept the PS/2 as secondary (symbolic).
		    return $mouse;
		}
		eval { modules::unload(qw(usbmouse mousedev hid)) };
	    }
	} else {
	    log::l("no usb interface found for mice");
	}
	$auxmouse;
    };

    if (modules::get_probeall("usb-interface")) {
	my $keep_mouse;
	if (my (@l) = detect_devices::usbWacom()) {
	    log::l("found usb wacom $_->{driver} $_->{description} ($_->{type})") foreach @l;
	    eval { modules::load("wacom", "evdev") };
	    unless ($@) {
		foreach (0..$#l) {
		    detect_devices::tryOpen("input/event$_") and $keep_mouse = 1, push @wacom, "input/event$_";
		}
	    }
	    $keep_mouse or eval { modules::unload("evdev", "wacom") };
	}
    } else {
	log::l("no usb interface found for wacom");
    }

    #- at this level, not all possible mice are detected so avoid invoking serial_probe
    #- which takes a while for its probe.
    if ($::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$mouse and return { wacom => \@wacom, %$mouse };
    }

    #- probe serial device to make sure a wacom has been detected.
    eval { modules::load("serial") };
    my ($r, @serial_wacom) = mouseconfig(); push @wacom, @serial_wacom;
    $r and return { wacom => \@wacom, %$r };

    if (!$::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$mouse and return { wacom => \@wacom, %$mouse };
    }

    #- in case only a wacom has been found, assume an inexistant mouse (necessary).
    @wacom and return fullname2mouse('none|No mouse', wacom => \@wacom);

    #- defaults to generic serial mouse on ttyS0.
    #- Oops? using return let return a hash ref, if not using it, it return a list directly :-)
    return fullname2mouse("serial|Generic 2 Button Mouse", unsafe => 1);
}

sub set_xfree_conf {
    my ($mouse, $xfree_conf, $b_keep_auxmouse_unchanged) = @_;
    
    my @mice = map {
	{
	    Protocol => $_->{XMOUSETYPE},
	    Device => "/dev/$_->{device}",
	    if_($_->{nbuttons} > 3, ZAxisMapping => [ $_->{nbuttons} > 5 ? '6 7' : '4 5' ]),
	    if_($_->{nbuttons} < 3, Emulate3Buttons => undef, Emulate3Timeout => 50),
	    if_($_->{EMULATEWHEEL}, Emulate3Buttons => undef, Emulate3Timeout => 50, EmulateWheel => undef, EmulateWheelButton => 2),
	};
    } ($mouse, if_($mouse->{auxmouse}, $mouse->{auxmouse}));
    
    if (!$mouse->{auxmouse} && $b_keep_auxmouse_unchanged) {
	my (undef, @l) = $xfree_conf->get_mice;
	push @mice, @l;
    }

    $xfree_conf->set_mice(@mice);

    if (my @wacoms = @{$mouse->{wacom} || []}) {
	$xfree_conf->set_wacoms(map { { Device => "/dev/$_", USB => m|input/event| } } @wacoms);
	$xfree_conf->{xfree3}->add_load_module('xf86Wacom.so') if $xfree_conf->{xfree3};
    }
}

sub various_xfree_conf {
    my ($in, $mouse) = @_;

    {
	my $f = "$::prefix/etc/X11/xinit.d/mouse_buttons";
	if ($mouse->{nbuttons} <= 5) {
	    unlink($f);
	} else {
	    output_with_perm($f, 0755, "xmodmap -e 'pointer = 1 2 3 6 7 4 5'\n");
	}
    }
    {
	my $f = "$::prefix/etc/X11/xinit.d/auxmouse_buttons";
	if (!$mouse->{auxmouse} || $mouse->{auxmouse}{nbuttons} <= 5) {
	    unlink($f);
	} else {
	    $in->do_pkgs->install('xinput');
	    output_with_perm($f, 0755, "xinput set-button-map Mouse2 1 2 3 6 7 4 5\n");
	}
    }
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
    my ($in, $mouse, $b_keep_auxmouse_unchanged) = @_;

    &write($in, $mouse);
    modules::write_conf('') if $mouse->{device} eq "usbmouse" && !$::testing;

    require Xconfig::xfree;
    my $xfree_conf = Xconfig::xfree->read;
    set_xfree_conf($mouse, $xfree_conf, $b_keep_auxmouse_unchanged);
    $xfree_conf->write;
}

sub test_mouse_install {
    my ($mouse, $x_protocol_changed) = @_;
    require ugtk2;
    ugtk2->import(qw(:wrappers :create));
    my $w = ugtk2->new('', disallow_big_help => 1);
    my $darea = Gtk2::DrawingArea->new;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkadd($w->{window},
  	   gtkpack(my $vbox_grab = Gtk2::VBox->new(0, 0),
		   $darea,
		   gtkset_sensitive(create_okcancel($w, undef, undef, 'edge'), 1)
		  ),
	  );
    test_mouse($mouse, $darea, $x_protocol_changed);
    $w->sync; # HACK
    Gtk2::Gdk->pointer_grab($vbox_grab->window, 1, 'pointer_motion_mask', $vbox_grab->window, undef, 0);
    my $r = $w->main;
    Gtk2::Gdk->pointer_ungrab(0);
    $r;
}

sub test_mouse_standalone {
    my ($mouse, $hbox) = @_;
    require ugtk2;
    ugtk2->import(qw(:wrappers));
    my $darea = Gtk2::DrawingArea->new;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkpack($hbox, gtkpack(gtkset_border_width(Gtk2::VBox->new(0,10), 10), $darea));
    test_mouse($mouse, $darea);
}

sub test_mouse {
    my ($mouse, $darea, $b_x_protocol_changed) = @_;

    require ugtk2;
    ugtk2->import(qw(:wrappers));
    my $suffix = $mouse->{nbuttons} <= 2 ? '2b' : $mouse->{nbuttons} == 3 ? '3b' : '3b+';
    my %offsets = (mouse_2b_right => [ 93, 0 ], mouse_3b_right => [ 117, 0 ],
		   mouse_2b_middle => [ 82, 80 ], mouse_3b_middle => [ 68, 0 ], 'mouse_3b+_middle' => [ 85, 67 ]);
    my %image_files = (
		       mouse => "mouse_$suffix",
		       left => 'mouse_' . ($suffix eq '3b+' ? '3b' : $suffix) . '_left',
		       right => 'mouse_' . ($suffix eq '3b+' ? '3b' : $suffix) . '_right',
		       if_($mouse->{nbuttons} > 2, middle => 'mouse_' . $suffix . '_middle'),
		       up => 'arrow_up',
		       down => 'arrow_down');
    my %images = map { $_ => ugtk2::gtkcreate_pixbuf("$image_files{$_}.png") } keys %image_files;
    my $width = $images{mouse}->get_width;
    my $height = round_up(min($images{mouse}->get_height, $::windowheight - 150), 6);

    my $draw_text = sub {
  	my ($t, $y) = @_;
	my $layout = $darea->create_pango_layout($t);
	my ($w) = $layout->get_pixel_size;
	$darea->window->draw_layout($darea->style->black_gc,
				    ($darea->allocation->width-$w)/2,
				    ($darea->allocation->height-$height)/2 + $y,
				    $layout);
    };
    my $draw_pixbuf = sub {
	my ($p, $x, $y, $w, $h) = @_;
	$w = $p->get_width;
	$h = $p->get_height;
	$p->render_to_drawable($darea->window, $darea->style->bg_gc('normal'), 0, 0,
			       ($darea->allocation->width-$width)/2 + $x, ($darea->allocation->height-$height)/2 + $y,
			       $w, $h, 'none', 0, 0);
    };
    my $draw_by_name = sub {
	my ($name) = @_;
	my $file = $image_files{$name};
	my ($x, $y) = @{$offsets{$file} || [ 0, 0 ]};
	$draw_pixbuf->($images{$name}, $x, $y);
    };
    my $drawarea = sub {
	my ($height) = @_;
	$draw_by_name->('mouse');
	if ($::isInstall || 1) {
	    $draw_text->(N("Please test the mouse"), 200);
	    if ($b_x_protocol_changed && $mouse->{nbuttons} > 3 && $mouse->{device} eq 'psaux' && member($mouse->{XMOUSETYPE}, 'IMPS/2', 'ExplorerPS/2')) {
		$draw_text->(N("To activate the mouse,"), 240);
		$draw_text->(N("MOVE YOUR WHEEL!"), 260);
	    }
	}
    };

    my $timeout;
    my $paintButton = sub {
	my ($nb) = @_;
	$timeout or $drawarea->();
	if ($nb == 0) {
	    $draw_by_name->('left');
	} elsif ($nb == 2) {
	    $draw_by_name->('right');
	} elsif ($nb == 1) {
	    if ($mouse->{nbuttons} >= 3) {
		$draw_by_name->('middle');
	    } else {
		my ($x, $y) = @{$offsets{mouse_2b_middle}};
  		$darea->window->draw_arc($darea->style->black_gc,
  					  1, ($darea->allocation->width-$width)/2 + $x, ($darea->allocation->height-$height)/2 + $y, 20, 25,
  					  0, 360 * 64);
	    }
	} elsif ($mouse->{nbuttons} > 3) {
	    my ($x, $y) = @{$offsets{$image_files{middle}}};
	    if ($nb == 3) {
		$draw_pixbuf->($images{up}, $x+6, $y-10);
	    } elsif ($nb == 4) {
		$draw_pixbuf->($images{down}, $x+6, $y + $images{middle}->get_height + 2);
	    }
	    $draw_by_name->('middle');
	    $timeout and Glib::Source->remove($timeout);
	    $timeout = Glib::Timeout->add(100, sub { $drawarea->(); $timeout = 0; 0 });
	}
    };
    
    $darea->signal_connect(button_press_event => sub { $paintButton->($_[1]->button - 1) });
    $darea->signal_connect(scroll_event => sub { $paintButton->($_[1]->direction eq 'up' ? 3 : 4) });
    $darea->signal_connect(button_release_event => $drawarea);
    $darea->signal_connect(expose_event => $drawarea);
    $darea->set_size_request($width, $height);
}


=begin

=head1 NAME

mouse - Perl functions to handle mice

=head1 SYNOPSYS

   require modules;
   require mouse;
   modules::mergein_conf('/etc/modules.conf') if -r '/etc/modules.conf';
   &mouse::detect();

=head1 DESCRIPTION

C<mouse> is a perl module used by mousedrake to detect and configure the mouse.

=head1 COPYRIGHT

Copyright (C) 2000-2002 MandrakeSoft <tvignaud@mandrakesoft.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
