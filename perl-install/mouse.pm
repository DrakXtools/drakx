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
     [ 7, 'ps/2', 'ExplorerPS/2', __("Microsoft Explorer") ],
   ]],
     
 'USB' =>
 [ [ 'usbmouse' ],
   [ if_(arch() eq 'ppc', [ 1, 'ps/2', 'PS/2', __("1 button") ]),
     [ 2, 'ps/2', 'PS/2', __("Generic 2 Button Mouse") ],
     [ 3, 'ps/2', 'PS/2', __("Generic") ],
     [ 5, 'ps/2', 'IMPS/2', __("Wheel") ],
     [ 7, 'ps/2', 'ExplorerPS/2', __("Microsoft Explorer") ],
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
		   "ExplorerPS/2",
		   "USB",
    );
    my ($id) = @_;
    $id = 'BusMouse' if $id eq 'MouseMan';
    $id = 'IMPS/2' if $id eq 'ExplorerPS/2' && $::isInstall;
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

sub update_type_name {
    my ($mouse) = @_;
    while (my ($k, $v) = each %mice) {
	$mouse->{device} =~ /usb/ && $k ne 'USB' and next; #- avoid mixing USB and PS/2 mice.
	foreach (@{$v->[1]}) {
	    if ($_->[0] == $mouse->{nbuttons} && $_->[2] eq $mouse->{XMOUSETYPE}) {
		add2hash($mouse, { MOUSETYPE => $_->[1],
				   type      => $k,
				   name      => $_->[3],
				 });
		return $mouse;
	    }
	}
    }
}

sub fullnames { 
    map_each { 
	my $type = $::a;
	grep { $_ } map {
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

sub read {
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

sub mouseconfig {
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

	if (modules::get_probeall("usb-interface")) {
	    if (my (@l) = detect_devices::usbMice()) {
		log::l("found usb mouse $_->{driver} $_->{description} ($_->{type})") foreach @l;
		eval { modules::load(qw(hid mousedev usbmouse)) };
		if (!$@ && detect_devices::tryOpen("usbmouse")) {
		    my $mouse = fullname2mouse($l[0]{driver} =~ /Mouse:(.*)/ ? $1 : "USB|Generic");
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

    if (!$::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$r && $mouse and $r->{auxmouse} = $mouse; #- we kept the auxilliary mouse as PS/2.
	$r and return { wacom => \@wacom, %$r };
	$mouse and return { wacom => \@wacom, %$mouse };
    } else {
	$r and return { wacom => \@wacom, %$r };
    }

    #- in case only a wacom has been found, assume an inexistant mouse (necessary).
    @wacom and return { CLASS      => 'MOUSE',
			nbuttons   => 2,
			device     => "nothing",
			MOUSETYPE  => "Microsoft",
			XMOUSETYPE => "Microsoft", wacom => \@wacom };

    if (!modules::get_probeall("usb-interface") && detect_devices::is_a_recent_computer() && $::isInstall) {
	#- special case for non detected usb interface on a box with no mouse.
	#- we *must* find out if there really is no usb, otherwise the box may
	#- not be accessible via the keyboard (if the keyboard is USB)
	#- the only way to know this is to make a full pci probe
	modules::load_category('bus/usb', '', 'unsafe'); 
	if (my $mouse = $fast_mouse_probe->()) {
	    return $mouse;
	}
    }

    #- defaults to generic serial mouse on ttyS0.
    #- Oops? using return let return a hash ref, if not using it, it return a list directly :-)
    return fullname2mouse("serial|Generic 2 Button Mouse", unsafe => 1);
}

sub set_xfree_conf {
    my ($mouse, $xfree_conf, $keep_auxmouse_unchanged) = @_;
    
    my @mice = map {
	{
	    Protocol => $_->{XMOUSETYPE},
	    Device => "/dev/$_->{device}",
	    if_($_->{nbuttons} > 3, ZAxisMapping => [ $_->{nbuttons} > 5 ? '6 7' : '4 5' ]),
	    if_($_->{nbuttons} < 3, Emulate3Buttons => undef, Emulate3Timeout => 50),
	};
    } ($mouse, if_($mouse->{auxmouse}, $mouse->{auxmouse}));
    
    if (!$mouse->{auxmouse} && $keep_auxmouse_unchanged) {
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
	    output_p($f, "xmodmap -e 'pointer = 1 2 3 6 7 4 5'\n");
	    chmod 0755, $f;
	}
    }
    {
	my $f = "$::prefix/etc/X11/xinit.d/auxmouse_buttons";
	if (!$mouse->{auxmouse} || $mouse->{auxmouse}{nbuttons} <= 5) {
	    unlink($f);
	} else {
	    $in->do_pkgs->install('xinput');
	    output_p($f, "xinput set-button-map Mouse2 1 2 3 6 7 4 5\n");
	    chmod 0755, $f;
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
    my ($in, $mouse, $keep_auxmouse_unchanged) = @_;

    &write($in, $mouse);
    modules::write_conf('') if $mouse->{device} eq "usbmouse" && !$::testing;

    require Xconfig::xfree;
    my $xfree_conf = Xconfig::xfree->read;
    set_xfree_conf($mouse, $xfree_conf, $keep_auxmouse_unchanged);
    $xfree_conf->write;
}

sub test_mouse_install {
    my ($mouse) = @_;
    require my_gtk;
    my_gtk->import(qw(:wrappers :helpers));
    my $w = my_gtk->new('', disallow_big_help => 1);
    my ($width, $height, $offset) = (210, round_up(min(350, $::windowheight - 150), 6), 25);
    my $darea = new Gtk::DrawingArea;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkadd($w->{window},
  	   gtkpack(my $vbox_grab = new Gtk::VBox(0,0),
		   gtksize(gtkset_usize($darea, $width+1, $height+1), $width+1, $height+1),
		   my $okcancel = gtkset_sensitive(create_okcancel($w, undef, undef, "edge"), 1)
		  ),
	  );
    $okcancel->set_uposition(7, $height-43);
    Gtk->timeout_add(2000, sub { gtkset_sensitive($okcancel, 1); $okcancel->draw(undef) });
    test_mouse($mouse, $w, $darea, $width, $height);
    $w->{window}->set_usize(undef, $height+10);
    $w->sync; # HACK
    Gtk::Gdk->pointer_grab($darea->window, 1,
			   [ 'pointer_motion_mask'],
			   $darea->window, undef ,0);
    $w->main;
}

sub test_mouse_standalone {
    my ($mouse, $hbox) = @_;
    require my_gtk;
    my_gtk->import(qw(:wrappers));
    my ($width, $height, $offset) = (210, round_up(min(350, $::windowheight - 150), 6), 25);
    my $darea = new Gtk::DrawingArea;
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);  #$darea must be unrealized.
    gtkpack($hbox,
	    gtkpack(gtkset_border_width(new Gtk::VBox(0,10), 10),
		    gtksize(gtkset_usize($darea, $width+1, $height+1), $width, $height)
		   )
	   );
    test_mouse($mouse, $hbox, $darea, $width, $height);
}

sub test_mouse {
    my ($mouse, $w, $darea, $width, $height) = @_;

    $darea->realize();
    my $wait = 0;
    my ($m3_image, $m3_mask) = gtkcreate_xpm('mouse_3b.xpm');
    my ($m3_imagep, $m3_maskp) = gtkcreate_xpm('mouse_3b+.xpm');
    my ($m3_left, $m3_left_mask) = gtkcreate_xpm('mouse_left.xpm');
    my ($m3_right, $m3_right_mask) = gtkcreate_xpm('mouse_right.xpm');
    my ($m3_middle, $m3_middle_mask) = gtkcreate_xpm('mouse_middle.xpm');
    my ($aru, $aru_mask) = gtkcreate_xpm('arrow_up.xpm');
    my ($ard, $ard_mask) = gtkcreate_xpm('arrow_down.xpm');
    my $image = $m3_image;
    $mouse->{nbuttons} > 3 and $image = $m3_imagep;
    my $draw_text = sub {
  	my ($t, $y) = @_;
  	my $font = $darea->style->font;
  	my $w = $font->string_width($t);
  	$darea->window->draw_string($font, $darea->style->black_gc, ($darea->allocation->[2]-$width)/2 + ($width - $w) / 2, ($darea->allocation->[3]-$height)/2 + $y, $t);
    };
    my $drawarea; 
    $drawarea = sub { $darea->window->draw_pixmap($darea->style->bg_gc('normal'),
						  $image, 0, 0,
						  ($darea->allocation->[2]-$width)/2, ($darea->allocation->[3]-$height)/2,
						  210, 350);
		      if ($::isInstall) {
			  $draw_text->(_("Please test the mouse"), $height - 120);
			  $draw_text->(_("To activate the mouse,"), $height - 105) if $mouse->{XMOUSETYPE} eq 'IMPS/2';
			  $draw_text->(_("MOVE YOUR WHEEL!"), $height - 90) if $mouse->{XMOUSETYPE} eq 'IMPS/2';
			  $darea->window->draw_rectangle($darea->style->bg_gc('normal'), 1, 0, $height-65, $width, $height);
		      }
		  };

    my $paintButton = sub {
	my ($nb, $pressed) = @_;
	my $x = 60 + $nb*33;
	$drawarea->();
	if ($nb == 0) {
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $m3_left, 0, 0,
					 ($darea->allocation->[2]-$width)/2+31, ($darea->allocation->[3]-$height)/2 + 52,
					 59, 91);
	} elsif ($nb == 2) {
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $m3_right, 0, 0,
					 ($darea->allocation->[2]-$width)/2+117, ($darea->allocation->[3]-$height)/2 + 52,
					 61, 91);
	} elsif ($nb == 1) {
	    if ($mouse->{nbuttons} > 3) {
		$darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					     $m3_middle, 0, 0,
					     ($darea->allocation->[2]-$width)/2+98, ($darea->allocation->[3]-$height)/2 + 67,
					     13, 62);
	    } else {
  		$darea->window->draw_arc ($darea->style->black_gc,
  					  1, ($darea->allocation->[2]-$width)/2 + $x, ($darea->allocation->[3]-$height)/2 + 90, 20, 25,
  					  0, 360*64);
	    }
	} elsif ($nb == 3) {
	    $wait = 1;
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $aru, 0, 0,
					 ($darea->allocation->[2]-$width)/2+102, ($darea->allocation->[3]-$height)/2 + 57,
					 6, 8);
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $m3_middle, 0, 0,
					 ($darea->allocation->[2]-$width)/2+98, ($darea->allocation->[3]-$height)/2 + 67,
					 13, 62);
	    Gtk->timeout_add(200, sub { $wait = 0 });
	} elsif ($nb == 4) {
	    $wait = 1;
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $ard, 0, 0,
					 ($darea->allocation->[2]-$width)/2+102, ($darea->allocation->[3]-$height)/2 + 131,
					 6, 8);
	    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
					 $m3_middle, 0, 0,
					 ($darea->allocation->[2]-$width)/2+98, ($darea->allocation->[3]-$height)/2 + 67,
					 13, 62);
	    Gtk->timeout_add(200, sub { $wait = 0 });
	}
    };
    $darea->signal_connect(button_press_event => sub {
  			       my $b = $_[1]{button};
			       $paintButton->($b - 1);
  			   });
    $darea->signal_connect(button_release_event => sub {
			       while ($wait) { my_gtk::flush() }
			       $drawarea->()
  			   });
    $darea->signal_connect(expose_event => sub { $drawarea->() });
    $darea->size($width, $height);
}
