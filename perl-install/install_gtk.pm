package install_gtk; # $Id$

use diagnostics;
use strict;

use ugtk2 qw(:wrappers :helpers :create);
use common;
use lang;
use devices;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################

my @background;

#- if we're running for the doc team, we want screenshots with
#- a good B&W contrast: we'll override values of our theme
my $theme_overriding_for_doc = q(style "galaxy-default"
{
    base[SELECTED]    = "#E0E0FF"
    base[ACTIVE]      = "#E0E0FF"
    base[PRELIGHT]    = "#E0E0FF"
    bg[SELECTED]      = "#E0E0FF"
    bg[ACTIVE]        = "#E0E0FF"
    bg[PRELIGHT]      = "#E0E0FF"
    text[ACTIVE]      = "#000000"
    text[PRELIGHT]    = "#000000"
    text[SELECTED]    = "#000000"
    fg[SELECTED]      = "#000000"
}

style "white-on-blue"
{
  base[NORMAL] = { 0.93, 0.93, 0.93 }
  bg[NORMAL] = { 0.93, 0.93, 0.93 }
    
  text[NORMAL] = "#000000"
  fg[NORMAL] = "#000000"
}

style "background"
{
  bg[NORMAL] = { 0.93, 0.93, 0.93 }
});

#------------------------------------------------------------------------------
sub load_rc {
    my ($o, $name) = @_;

    if (my $f = find { -r $_ } map { "$_/$name.rc" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__))) {

	my @contents = cat_($f);
	$o->{doc} and push @contents, $theme_overriding_for_doc;

	Gtk2::Rc->parse_string(join("\n", @contents));
	foreach (@contents) {
	    if (/style\s+"background"/ .. /^\s*$/) {
		@background = map { $_ * 256 * 257 } split ',', $1 if /NORMAL.*\{(.*)\}/;
	    }
	}
    }

}

#------------------------------------------------------------------------------
sub load_font {
    my ($o) = @_;

    if (lang::text_direction_rtl()) {
	Gtk2::Widget->set_default_direction('rtl'); 
	my ($x, $y) = $::WizardWindow->get_position;
	my ($width) = $::WizardWindow->get_size;
	$::WizardWindow->move($::rootwidth - $width - $x, $y);
    }

    Gtk2::Rc->parse_string(q(
style "default-font" 
{
   font_name = ") . lang::l2pango_font($o->{locale}{lang}) . q("
}
widget "*" style "default-font"

));
}

#------------------------------------------------------------------------------
sub default_theme {
    my ($o) = @_;
    $o->{meta_class} eq 'desktop' ? 'blue' :
      $o->{meta_class} eq 'firewall' ? 'mdk-Firewall' : 
      $o->{simple_themes} || $o->{vga16} ? 'blue' : 'galaxy';
}

sub install_theme {
    my ($o) = @_;

    $o->{theme} ||= default_theme($o);
    load_rc($o, "themes-$o->{theme}");
    load_font($o);
    gtkset_background(@background) unless $::live; #- || testing;
}

#------------------------------------------------------------------------------
sub create_help_window {
    my ($o) = @_;

    my $w;
    if ($w = $o->{help_window}) {
	$w->{window}->foreach(sub { $_[0]->destroy }, undef);
    } else {
	$w = $o->{help_window} = bless {}, 'ugtk2';
	$w->{rwindow} = $w->{window} = Gtk2::Window->new('toplevel');
	$w->{rwindow}->set_uposition($::rootwidth - $::helpwidth, $::rootheight - $::helpheight);
	$w->{rwindow}->set_size_request($::helpwidth, $::helpheight);
	$w->{rwindow}->set_title('skip');
    };
    gtkadd($w->{window}, create_scrolled_window($o->{help_window_text} = Gtk2::TextView->new));
    $w->show;
}

#------------------------------------------------------------------------------
my %steps;
sub create_steps_window {
    my ($o) = @_;

    return if $::stepswidth == 0;

    $o->{steps_window} and $o->{steps_window}->destroy;
    my $w = bless {}, 'ugtk2';
    $w->{rwindow} = $w->{window} = Gtk2::Window->new('toplevel');
    $w->{rwindow}->set_uposition(lang::text_direction_rtl() ? ($::rootwidth - $::stepswidth - 8) : 8, 160);
    $w->{rwindow}->set_size_request($::stepswidth, -1);
    $w->{rwindow}->set_name('Steps');
    $w->{rwindow}->set_title('skip');

    $steps{$_} ||= gtkcreate_pixbuf("steps_$_") foreach qw(on off);

    gtkpack__(my $vb = Gtk2::VBox->new(0, 3), $steps{inst} = Gtk2::Label->new(N("System installation")), '');
    foreach (grep { !eval $o->{steps}{$_}{hidden} } @{$o->{orderedSteps}}) {
	$_ eq 'setRootPassword'
	  and gtkpack__($vb, '', '', $steps{conf} = Gtk2::Label->new(N("System configuration")), '');
	$steps{steps}{$_} = { img => gtkcreate_img('steps_off.png'),
			      txt => Gtk2::Label->new(translate($o->{steps}{$_}{text})) };
	gtkpack__($vb, gtkpack__(Gtk2::HBox->new(0, 7), $steps{steps}{$_}{img}, $steps{steps}{$_}{txt}));
					      
    }

    gtkadd($w->{window}, $vb);
    $w->show;
    $o->{steps_window} = $w;
}

sub update_steps_position {
    my ($o) = @_;
    return if !$steps{steps};
    my $last_step;
    foreach (@{$o->{orderedSteps}}) {
	exists $steps{steps}{$_} or next;
	if ($o->{steps}{$_}{entered} && !$o->{steps}{$_}{done}) {
	    $steps{steps}{$_}{img}->set_from_pixbuf($steps{on});
	    $last_step and $steps{steps}{$last_step}{img}->set_from_pixbuf($steps{off});
	    return;
	}
	$last_step = $_;
    }
}

#------------------------------------------------------------------------------
sub create_logo_window {
    my ($o) = @_;

    return if $::logowidth == 0;

    gtkdestroy($o->{logo_window});

    my $w = bless {}, 'ugtk2';
    $w->{rwindow} = $w->{window} = Gtk2::Window->new('toplevel');
    $w->{rwindow}->set_uposition(0, 0);
    $w->{rwindow}->set_size_request($::logowidth, $::logoheight);
    $w->{rwindow}->set_name("logo");
    $w->{rwindow}->set_title('skip');
    $w->show;
    my $file = $o->{meta_class} eq 'desktop' ? "logo-mandrake-Desktop.png" : "logo-mandrake.png";
    $o->{meta_class} eq 'firewall' and $file = "logo-mandrake-Firewall.png";
    -r $file or $file = "$ENV{SHARE_PATH}/$file";
    -r $file and gtkadd($w->{window}, gtkcreate_img($file));
    $o->{logo_window} = $w;
}

#------------------------------------------------------------------------------
sub init_gtk() {
    symlink("/tmp/stage2/etc/$_", "/etc/$_") foreach qw(gtk-2.0 pango fonts);
    Gtk2->init(\@ARGV);
    Gtk2->set_locale;
}

#------------------------------------------------------------------------------
sub init_sizes() {
    ($::rootwidth,  $::rootheight)    = (Gtk2::Gdk->screen_width, Gtk2::Gdk->screen_height);
    $::live and $::rootheight -= 80;
    #- ($::rootheight,  $::rootwidth)    = (min(768, $::rootheight), min(1024, $::rootwidth));
    $::stepswidth = $::rootwidth <= 640 ? 0 : 160;
    ($::logowidth,   $::logoheight)   = $::rootwidth <= 640 ? (0, 0) : (500, 40);
    ($::helpwidth,   $::helpheight)   = ($::rootwidth - $::stepswidth, 0);
    ($::windowwidth, $::windowheight) = ($::rootwidth - $::stepswidth, $::rootheight - $::helpheight - $::logoheight);
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $mouse_type, $mouse_dev, $wacom_dev) = @_;

    $mouse_type = 'IMPS/2' if $mouse_type eq 'ExplorerPS/2';
    devices::make("/dev/kbd") if arch() =~ /^sparc/; #- used by Xsun style server.
    symlinkf(devices::make($mouse_dev), "/dev/mouse") if $mouse_dev ne 'none';

    #- needed for imlib to start on 8-bit depth visual.
    symlink("/tmp/stage2/etc/imrc", "/etc/imrc");
    symlink("/tmp/stage2/etc/im_palette.pal", "etc/im_palette.pal");

if (arch() =~ /^ia64/) {
     require Xconfig::card;
     my ($card) = Xconfig::card::probe();
     Xconfig::card::add_to_card__using_Cards($card, $card->{type}) if $card && $card->{type};
     output($file, sprintf(<<'END', $mouse_type, $card->{driver}));

Section "Files"
   FontPath   "/usr/X11R6/lib/X11/fonts:unscaled"
EndSection

Section "InputDevice"
    Identifier "Keyboard"
    Driver "Keyboard"
    Option "XkbDisable"
    Option "XkbModel" "pc105"
    Option "XkbLayout" ""
EndSection

Section "InputDevice"
    Identifier "Mouse"
    Driver "mouse"
    Option "Protocol" "%s"
    Option "Device" "/dev/mouse"
EndSection

Section "Monitor"
    Identifier "monitor"
    HorizSync 31.5-35.5
    VertRefresh 50-70
EndSection

Section "Device"
    Identifier  "device"
    Driver      "%s"
EndSection

Section "Screen"
    Identifier "screen"
    Device "device"
    Monitor "monitor"
    DefaultColorDepth 16
    Subsection "Display"
        Depth 16
        Modes "800x600" "640x480"
    EndSubsection
EndSection

Section "ServerLayout"
    Identifier "layout"
    Screen "screen"
    InputDevice "Mouse" "CorePointer"
    InputDevice "Keyboard" "CoreKeyboard"
EndSection

END


} else {

    my $wacom;
    if ($wacom_dev) {
	my $dev = devices::make($wacom_dev);
	$wacom = <<END;
Section "Module"
   Load "xf86Wacom.so"
EndSection

Section "XInput"
    SubSection "WacomStylus"
        Port "$dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomCursor"
        Port "$dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomEraser"
        Port "$dev"
        AlwaysCore
    EndSubSection
EndSection
END
    }

    output($file, <<END);
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
   XkbDisable
EndSection

Section "Pointer"
   Protocol    "$mouse_type"
   Device      "/dev/mouse"
   ZAxisMapping 4 5
EndSection

$wacom

Section "Monitor"
   Identifier  "monitor"
   HorizSync   31.5-35.5
   VertRefresh 50-70
   ModeLine "640x480"     25.175 640  664  760  800   480  491  493  525
   ModeLine "640x480"     28.3   640  664  760  800   480  491  493  525
   ModeLine "800x600"     36     800  824  896 1024   600  601  603  625
EndSection


Section "Device"
   Identifier "Generic VGA"
   Chipset "generic"
EndSection

Section "Device"
   Identifier "svga"
EndSection

Section "Screen"
    Driver      "vga16"
    Device      "Generic VGA"
    Monitor     "monitor"
    Subsection "Display"
        Modes      "640x480"
        ViewPort   0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "fbdev"
    Device      "Generic VGA"
    Monitor     "monitor"
    Subsection "Display"
        Depth      16
        Modes      "default"
        ViewPort   0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "svga"
    Device      "svga"
    Monitor     "monitor"
    Subsection "Display"
        Depth      16
        Modes      "800x600" "640x480"
        ViewPort   0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "accel"
    Device      "svga"
    Monitor     "monitor"
    Subsection "Display"
        Depth      16
        Modes      "800x600" "640x480"
        ViewPort   0 0
    EndSubsection
EndSection
END
}
}

1;
