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

my @mouses_fields = qw(nbuttons MOUSETYPE XMOUSETYPE name);

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
     [ 5, 'ps/2', 'IMPS/2', N_("Wheel") ],
     [ 7, 'ps/2', 'ExplorerPS/2', N_("Microsoft Explorer") ],
   ] ],

 N_("serial") =>
 [ [ map { "ttyS$_" } 0..3 ],
   [ [ 2, 'Microsoft', 'Microsoft', N_("Generic 2 Button Mouse") ],
     [ 3, 'Microsoft', 'Microsoft', N_("Generic 3 Button Mouse") ],
     [ 5, 'ms3', 'IntelliMouse', N_("Microsoft IntelliMouse") ],
     [ 3, 'MouseMan', 'MouseMan', N_("Logitech MouseMan") ],
     [ 2, 'MouseSystems', 'MouseSystems', N_("Mouse Systems") ],     
     '',
     [ 3, 'logim', 'MouseMan', N_("Logitech CC Series") ],
     [ 5, 'pnp', 'IntelliMouse', N_("Logitech MouseMan+/FirstMouse+") ],
     [ 5, 'ms3', 'IntelliMouse', N_("Genius NetMouse") ],
     [ 2, 'MMSeries', 'MMSeries', N_("MM Series") ],
     [ 2, 'MMHitTab', 'MMHittab', N_("MM HitTablet") ],
     [ 3, 'Logitech', 'Logitech', N_("Logitech Mouse (serial, old C7 type)") ],
     [ 3, 'Microsoft', 'ThinkingMouse', N_("Kensington Thinking Mouse") ],
   ] ],

 N_("busmouse") =>
 [ [ arch() eq 'ppc' ? 'adbmouse' : ('atibm', 'inportbm', 'logibm') ],
   [ if_(arch() eq 'ppc', [ 1, 'Busmouse', 'BusMouse', N_("1 button") ]),
     [ 2, 'Busmouse', 'BusMouse', N_("2 buttons") ],
     [ 3, 'Busmouse', 'BusMouse', N_("3 buttons") ],
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

    if (detect_devices::is_a_recent_computer() && $::isInstall) {
	#- special case for non detected usb interface on a box with no mouse.
	#- we *must* find out if there really is no usb, otherwise the box may
	#- not be accessible via the keyboard (if the keyboard is USB)
	#- the only way to know this is to make a full pci probe
	modules::get_probeall("usb-interface") or modules::load_category('bus/usb', '', 'unsafe');
	log::l("trying again to find a usb mouse");
	sleep 10;
	if (my $mouse = $fast_mouse_probe->()) {
	    return $mouse;
	}
    }

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
    my ($width, $height, $_offset) = (210, round_up(min(350, $::windowheight - 150), 6), 25);
    my $darea = Gtk2::DrawingArea->new;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkadd($w->{window},
  	   gtkpack(my $vbox_grab = Gtk2::VBox->new(0, 0),
		   gtkset_size_request($darea, $width+1, $height+1),
		   gtkset_sensitive(create_okcancel($w, undef, undef, 'edge'), 1)
		  ),
	  );
    test_mouse($mouse, $w, $darea, $width, $height, $x_protocol_changed);
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
    my ($width, $height, $_offset) = (210, round_up(min(350, $::windowheight - 150), 6), 25);
    my $darea = Gtk2::DrawingArea->new;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkpack($hbox,
	    gtkpack(gtkset_border_width(Gtk2::VBox->new(0,10), 10),
		    gtksize(gtkset_size_request($darea, $width+1, $height+1), $width, $height)));
    test_mouse($mouse, $hbox, $darea, $width, $height);
}

sub test_mouse {
    my ($mouse, $_w, $darea, $width, $height, $b_x_protocol_changed) = @_;

#    $darea->realize;  IS IT REALLY NEEDED? generates a Gtk-CRITICAL when run..
    require ugtk2;
    ugtk2->import(qw(:wrappers));
    my %xpms;
    $xpms{$_} = ugtk2::gtkcreate_pixbuf("mouse_$_.xpm") foreach qw(3b 3b+ left right middle);
    $xpms{au} = ugtk2::gtkcreate_pixbuf('arrow_up.xpm');
    $xpms{ad} = ugtk2::gtkcreate_pixbuf('arrow_down.xpm');
    my $image = $xpms{'3b'};
    $mouse->{nbuttons} > 3 and $image = $xpms{'3b+'};
    my $draw_text = sub {
  	my ($t, $y) = @_;
	my $layout = $darea->create_pango_layout($t);
	my ($w) = $layout->get_pixel_size;
	$darea->window->draw_layout($darea->style->black_gc,
				    ($darea->allocation->width-$w)/2,
				    ($darea->allocation->height-$height)/2 + $y,
				    $layout);
	$layout->unref;
    };
    my $draw_pixbuf = sub {
	my ($p, $x, $y, $w, $h) = @_;
	$p->render_to_drawable($darea->window, $darea->style->bg_gc('normal'), 0, 0,
			       ($darea->allocation->width-$width)/2 + $x, ($darea->allocation->height-$height)/2 + $y,
			       $w, $h, 'none', 0, 0);
    };
    my $drawarea; 
    $drawarea = sub {
	my ($height) = @_;
	$draw_pixbuf->($image, 0, 0, 210, $height || 200);
	if ($::isInstall) {
	    $draw_text->(N("Please test the mouse"), $height - 120);
	    if ($b_x_protocol_changed && $mouse->{nbuttons} > 3 && member($mouse->{XMOUSETYPE}, 'IMPS/2', 'ExplorerPS/2')) {
		$draw_text->(N("To activate the mouse,"), $height - 105);
		$draw_text->(N("MOVE YOUR WHEEL!"), $height - 90);
	    }
	}
    };

    my $timeout;
    my $paintButton = sub {
	my ($nb) = @_;
	my $x = 60 + $nb*33;
	$timeout or $drawarea->();
	if ($nb == 0) {
	    $draw_pixbuf->($xpms{left}, 31, 52, 59, 91);
	} elsif ($nb == 2) {
	    $draw_pixbuf->($xpms{right}, 117, 52, 61, 91);
	} elsif ($nb == 1) {
	    if ($mouse->{nbuttons} > 3) {
		$draw_pixbuf->($xpms{middle}, 98, 67, 13, 62);
	    } else {
  		$darea->window->draw_arc($darea->style->black_gc,
  					  1, ($darea->allocation->width-$width)/2 + $x, ($darea->allocation->height-$height)/2 + 90, 20, 25,
  					  0, 360*64);
	    }
	} else {
	    if ($nb == 3) {
		$draw_pixbuf->($xpms{au}, 102, 57, 6, 8);
	    } elsif ($nb == 4) {
		$draw_pixbuf->($xpms{ad}, 102, 131, 6, 8);
	    }
	    $draw_pixbuf->($xpms{middle}, 98, 67, 13, 62);
	    $timeout and Gtk2->timeout_remove($timeout);
	    $timeout = Gtk2->timeout_add(100, sub { $drawarea->(); $timeout = 0; 0 });
	}
    };
    
    $darea->signal_connect(button_press_event => sub { $paintButton->($_[1]->button - 1) });
    $darea->signal_connect(scroll_event => sub { $paintButton->($_[1]->direction eq 'up' ? 3 : 4) });
    $darea->signal_connect(button_release_event => sub { $drawarea->() });
    $darea->signal_connect(expose_event => sub { $drawarea->(350) });
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
