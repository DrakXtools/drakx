package install_gtk;

use diagnostics;
use strict;

use my_gtk qw(:helpers :wrappers);
use common qw(:common :file :functional);
use lang;
use devices;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################
my @themes_vga16 = qw(blue blackwhite savane);
my @themes = qw(mdk DarkMarble marble3d blueHeart);

my (@background1, @background2);


#------------------------------------------------------------------------------
sub load_rc {
    my ($name) = @_;

    if (my ($f) = grep { -r $_ } map { "$_/$name.rc" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__))) {
	Gtk::Rc->parse($f);
	foreach (cat_($f)) {
	    if (/style\s+"background"/ .. /^\s*$/) {
		@background1 = map { $_ * 256 * 257 } split ',', $1 if /NORMAL.*\{(.*)\}/;
		@background2 = map { $_ * 256 * 257 } split ',', $1 if /PRELIGHT.*\{(.*)\}/;
	    }
	}
    }
}

sub default_theme {
    my ($o) = @_;
    @themes = @themes_vga16 if $o->{simple_themes} || $o->{vga16};
    install_theme($o, $o->{theme} || $themes[0]);
}

#------------------------------------------------------------------------------
sub install_theme {
    my ($o, $theme) = @_;
    $::live and return;

    $o->{theme} = $theme || $o->{theme};

    load_rc($_) foreach "themes-$o->{theme}", "install", "themes";

    if (my ($font, $font2) = lang::get_x_fontset($o->{lang}, $::rootwidth < 800 ? 10 : 12)) {
	$font2 ||= $font;
	Gtk::Rc->parse_string(qq(
style "default-font" 
{
   fontset = "$font"
}
style "small-font"
{
   fontset = "$font2"
}
widget "*" style "default-font"
widget "*Steps*" style "small-font"

));
    }
    gtkset_background(@background1);# unless $::testing;

    create_logo_window($o);
    create_help_window($o);
}

#------------------------------------------------------------------------------
sub create_big_help {
    my $w = my_gtk->new('', grab => 1, force_position => [ $::stepswidth, $::logoheight ]);
    $w->{rwindow}->set_usize($::logowidth, $::rootheight - $::logoheight);
    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,0),
		    1, createScrolledWindow(gtktext_insert(new Gtk::Text, 
							   formatAlaTeX(_ deref($help::steps{$::o->{step}})))),
		    0, gtksignal_connect(my $ok = new Gtk::Button(_("Ok")), "clicked" => sub { Gtk->main_quit }),
		   ));
    $ok->grab_focus;
    $w->main;
    gtkset_mousecursor_normal();
}

#------------------------------------------------------------------------------
sub create_help_window {
    my ($o) = @_;
    $::live and return;

    my $w;
    if ($w = $o->{help_window}) {
	$_->destroy foreach $w->{window}->children;
    } else {
	$w = bless {}, 'my_gtk';
	$w->{rwindow} = $w->{window} = new Gtk::Window;
	$w->{rwindow}->set_uposition($::rootwidth - $::helpwidth, $::rootheight - $::helpheight);
	$w->{rwindow}->set_usize($::helpwidth, $::helpheight);
	$w->sync;
    }
    my $pixmap = new Gtk::Pixmap(gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/help.xpm"));
    gtkadd($w->{window},
	   gtkpack_(new Gtk::HBox(0,-2),
		    0, gtkadd(gtksignal_connect(new Gtk::Button, clicked => \&create_big_help), $pixmap),
		    1, createScrolledWindow($o->{help_window_text} = new Gtk::Text),
		   ));
    gtktext_insert($o->{help_window_text}, $o->{step} ? formatAlaTeX(_ deref($help::steps{$o->{step}})) : '');

    $w->show;
    $o->{help_window} = $w;
}

#------------------------------------------------------------------------------
sub create_steps_window {
    my ($o) = @_;
    $::live and return;

    my $PIX_H = my $PIX_W = 21;

    $o->{steps_window}->destroy if $o->{steps_window};

    my $w = bless {}, 'my_gtk';
    $w->{rwindow} = $w->{window} = new Gtk::Window;
    $w->{rwindow}->set_uposition(0, 0);
    $w->{rwindow}->set_usize($::stepswidth, $::stepsheight);
    $w->{rwindow}->set_name('Steps');
    $w->{rwindow}->set_events('button_press_mask');
    $w->show;

    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,0),
		    (map {; 1, $_ } map {
			my $step_name = $_;
			my $step = $o->{steps}{$_};
			my $darea = new Gtk::DrawingArea;
			my $in_button;
			my $draw_pix = sub {
			    my $pixmap = Gtk::Gdk::Pixmap->create_from_xpm($darea->window,
									   $darea->style->bg('normal'),
									   $_[0]) or die;
			    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
							 $pixmap, 0, 0,
							 ($darea->allocation->[2]-$PIX_W)/2,
							 ($darea->allocation->[3]-$PIX_H)/2,
							 $PIX_W , $PIX_H );
			};

			my $f = sub { 
			    my ($type) = @_;
			    my $color = $step->{done} ? 'green' : $step->{entered} ? 'orange' : 'red';
			    "$ENV{SHARE_PATH}/step-$color$type.xpm";
			};
			$darea->set_usize($PIX_W,$PIX_H);
			$darea->set_events(['exposure_mask', 'enter_notify_mask', 'leave_notify_mask', 'button_press_mask', 'button_release_mask' ]);
			$darea->signal_connect(expose_event => sub { $draw_pix->($f->('')) });
			if ($step->{reachable}) {
			    $darea->signal_connect(enter_notify_event => sub { $in_button=1; $draw_pix->($f->('-on')); });
			    $darea->signal_connect(leave_notify_event => sub { undef $in_button; $draw_pix->($f->('')); });
			    $darea->signal_connect(button_press_event => sub { $draw_pix->($f->('-click')); });
			    $darea->signal_connect(button_release_event => sub { $in_button && die "setstep $step_name\n" });
			}
			gtkpack_(new Gtk::HBox(0,5), 0, $darea, 0, new Gtk::Label(translate($step->{text})));
		    } grep {
			!eval $o->{steps}{$_}{hidden};
		    } @{$o->{orderedSteps}}),
		    0, gtkpack(new Gtk::HBox(0,0), map {
			my $t = $_;
			my $w = new Gtk::Button('');
			$w->set_name($t);
			$w->set_usize(0, 7);
			gtksignal_connect($w, clicked => sub {
			    $::setstep or return; #- just as setstep s
			    install_theme($o, $t); die "theme_changed\n" 
			});
		    } @themes)));
    $w->show;
    $o->{steps_window} = $w;
}

#------------------------------------------------------------------------------
sub create_logo_window {
    my ($o) = @_;
    $::live and return;

    gtkdestroy($o->{logo_window});
    my $w = bless {}, 'my_gtk';
    $w->{rwindow} = $w->{window} = new Gtk::Window;
    $w->{rwindow}->set_uposition($::stepswidth, 0);
    $w->{rwindow}->set_usize($::logowidth, $::logoheight);
    $w->{rwindow}->set_name("logo");
    $w->show;
    my $file = "logo-mandrake.xpm";
    -r $file or $file = "$ENV{SHARE_PATH}/$file";
    if (-r $file) {
	my $ww = $w->{window};
	my @logo = Gtk::Gdk::Pixmap->create_from_xpm($ww->window, $ww->style->bg('normal'), $file);
	gtkadd($ww, new Gtk::Pixmap(@logo));
    }
    $o->{logo_window} = $w;
}

#------------------------------------------------------------------------------
sub init_sizes() {
#    my $maxheight = arch() eq "ppc" ? 1024 : 600;
#    my $maxwidth = arch() eq "ppc" ? 1280 : 800;
    ($::rootheight,  $::rootwidth)    = (480, 640);
    ($::rootheight,  $::rootwidth)    = my_gtk::gtkroot()->get_size;
    #- ($::rootheight,  $::rootwidth)    = (min(768, $::rootheight), min(1024, $::rootwidth));
    ($::stepswidth,  $::stepsheight)  = (145, $::rootheight);
    ($::logowidth,   $::logoheight)   = ($::rootwidth - $::stepswidth, 40);
    ($::helpwidth,   $::helpheight)   = ($::rootwidth - $::stepswidth, 104);
    ($::windowwidth, $::windowheight) = ($::rootwidth - $::stepswidth, $::rootheight - $::helpheight - $::logoheight);
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $mouse_type, $mouse_dev, $wacom_dev) = @_;

    devices::make("/dev/kbd") if arch() =~ /^sparc/; #- used by Xsun style server.
    symlinkf($mouse_dev, "/dev/mouse");

    #- needed for imlib to start on 8-bit depth visual.
    symlink("/tmp/stage2/etc/imrc", "/etc/imrc");
    symlink("/tmp/stage2/etc/im_palette.pal", "etc/im_palette.pal");

    my $wacom;
    if ($wacom_dev) {
	$wacom_dev = devices::make($wacom_dev);
	$wacom = <<END;
Section "Module"
   Load "xf86Wacom.so"
EndSection

Section "XInput"
    SubSection "WacomStylus"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomCursor"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomEraser"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
EndSection
END
    }

    local *F;
    open F, ">$file" or die "can't create X configuration file $file";
    print F <<END;
Section "Files"
   FontPath   "/usr/X11R6/lib/X11/fonts:unscaled"
EndSection

Section "Keyboard"
   Protocol    "Standard"
   AutoRepeat  0 0

   LeftAlt         Meta
   RightAlt        Meta
   ScrollLock      Compose
   RightCtl        Control
END

    if (arch() =~ /^sparc/) {
	print F <<END;
   XkbRules    "sun"
   XkbModel    "sun"
   XkbLayout   "us"
   XkbCompat   "compat/complete"
   XkbTypes    "types/complete"
   XkbKeycodes "sun(type5)"
   XkbGeometry "sun(type5)"
   XkbSymbols  "sun/us(sun5)"
END
    } else {
	print F "    XkbDisable\n";
    }

    print F <<END;
EndSection

Section "Pointer"
   Protocol    "$mouse_type"
   Device      "/dev/mouse"
   ZAxisMapping 4 5
EndSection

$wacom

Section "Monitor"
   Identifier  "My Monitor"
   VendorName  "Unknown"
   ModelName   "Unknown"
   HorizSync   31.5-35.5
   VertRefresh 50-70
   Modeline "640x480"     25.175 640  664  760  800   480  491  493  525
   Modeline "640x480"     28.3   640  664  760  800   480  491  493  525
   ModeLine "800x600"     36     800  824  896 1024   600  601  603  625
EndSection


Section "Device"
   Identifier "Generic VGA"
   VendorName "Unknown"
   BoardName "Unknown"
   Chipset "generic"
EndSection

Section "Device"
   Identifier "svga"
   VendorName "Unknown"
   BoardName "Unknown"
EndSection

Section "Screen"
    Driver      "vga16"
    Device      "Generic VGA"
    Monitor     "My Monitor"
    Subsection "Display"
        Modes       "640x480"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "fbdev"
    Device      "Generic VGA"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "default"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver "svga"
    Device      "svga"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "800x600" "640x480"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "accel"
    Device      "svga"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "800x600" "640x480"
        ViewPort    0 0
    EndSubsection
EndSection
END
}
#-   ModeLine "640x480"     28     640  672  768  800   480  490  492  525


sub test_mouse {
    my ($mouse) = @_;

    my $w = my_gtk->new;
    my ($width, $height, $offset) = (210, 300, 25);
    my ($bw, $bh) = ($width / 3, $height / 3);

    gtkadd($w->{window}, 
	   gtkpack(new Gtk::VBox(0,0),
		   my $darea = gtkset_usize(new Gtk::DrawingArea, $width+1, $height+1),
		   '',
		   create_okcancel($w, '', '', "edge"),
		  ),
	  );

    my $draw_rect; $draw_rect = sub {
	my ($black, $fill, $rect) = @_;
	$draw_rect->(0, 1, $rect) if !$fill; #- blank it first
	$darea->window->draw_rectangle($black ? $darea->style->fg_gc('normal') : $darea->style->bg_gc('normal'), $fill, @$rect);
	$darea->draw($rect);
    };
    my $paintWheel = sub {
	my ($x, $y, $w, $h) = ($width / 2 - $bw / 6, $bh / 4, $bw / 3, $bh / 2);
	$mouse->{nbuttons} = max($mouse->{nbuttons}, 5); #- it means, the mouse has more than 3 buttons...
	$draw_rect->(1, 0, [ $x, $y, $w, $h ]);

	my $offset = 0 if 0;
	$offset += $_[0] if $_[0];
	my $step = 10;
	for (my $i = $offset % $step; $i < $h; $i += $step) {
	    $draw_rect->(1, 1, [ $x, $y + $i, $w, min(2, $h - $i) ]);
	}
    };
    my $paintButton = sub {
	my ($nb, $pressed) = @_;
	my $rect = [ $bw * $nb, 0, $bw, $bh ];
	$draw_rect->(1, $pressed, $rect);
	$paintWheel->(0) if $nb == 1 && $mouse->{nbuttons} > 3;
    };
    my $draw_text = sub {
	my ($t, $y) = @_;
	my $font = $darea->style->font;
	my $w = $font->string_width($t);
	$darea->window->draw_string($font, $darea->style->fg_gc('normal'), ($width - $w) / 2, $y, $t);
    };
    my $default_time = 10;
    my $time = $default_time;
    $darea->signal_connect(button_press_event => sub {
			       my $b = $_[1]{button};
			       $time = $default_time;
			       $b >= 4 ?
				 $paintWheel->($b == 4 ? -1 : 1) :
				 $paintButton->($b - 1, 1);
			   });
    $darea->signal_connect(button_release_event => sub { 
			       my $b = $_[1]{button};
			       $paintButton->($b - 1, 0) if $b < 4;
			   });
    $darea->size($width, $height);
    $darea->set_events([ 'button_press_mask', 'button_release_mask' ]);

    $w->sync; # HACK
    $draw_rect->(1, 0, [ 0, 0, $width, $height]);
    $draw_text->(_("Please test the mouse"), 2 * $bh - 20);
    $draw_text->(_("Move your wheel!"), 2 * $bh + 10) if $mouse->{XMOUSETYPE} eq 'IMPS/2';
    $paintButton->($_, 0) foreach 0..2;
    $w->{cancel}->grab_focus;
    my $timeout = Gtk->timeout_add(1000, sub { if ($time-- == 0) { undef $w->{retval}; Gtk->main_quit } 1 });
    my $b = before_leaving { Gtk->timeout_remove($timeout) };
    $w->main;
}


1;
