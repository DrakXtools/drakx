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
}

style "background-logo"
{
  bg[NORMAL] = { 0.70, 0.70, 0.70 }
}
widget "*logo*" style "background-logo"

);

#------------------------------------------------------------------------------
sub load_rc {
    my ($o, $name) = @_;

    if (my $f = -r $name ? $name
                         : find { -r $_ } map { "$_/themes-$name.rc" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__))) {
	my @contents = cat_($f);
	$o->{doc} and push @contents, $theme_overriding_for_doc;

	Gtk2::Rc->parse_string(join("\n", @contents));
 	foreach (@contents) {
	    if (/style\s+"background"/ .. /^\s*$/) {
		@background = map { $_ * 255 * 255 } split ',', $1 if /NORMAL.*\{(.*)\}/;
	    }
	}
   }

    if ($::move) {
        #- override selection color since we won't do inverse-video on the text when it's images
	Gtk2::Rc->parse_string(q(
style "galaxy-default"
{
    base[ACTIVE]      = "#CECECE"
    base[SELECTED]    = "#CECECE"
    text[ACTIVE]      = "#000000"
    text[PRELIGHT]    = "#000000"
    text[SELECTED]    = "#000000"
}
));
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
    $::move ? '/usr/share/themes/Galaxy/gtk-2.0/gtkrc' :
    $o->{simple_themes} || $o->{vga16} ? 'blue' : 'galaxy';
}

sub install_theme {
    my ($o) = @_;

    load_rc($o, $o->{theme} ||= default_theme($o));
    load_font($o);
    gtkset_background(@background) if !$::move;
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
    }
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
    $w->{rwindow}->set_uposition(lang::text_direction_rtl() ? ($::rootwidth - $::stepswidth - 8) : 8, 150);
    $w->{rwindow}->set_size_request($::stepswidth, -1);
    $w->{rwindow}->set_name('Steps');
    $w->{rwindow}->set_title('skip');

    $steps{$_} ||= gtkcreate_pixbuf("steps_$_") foreach qw(on off);
    my $category = sub { gtkset_name(Gtk2::Label->new($_[0]), 'Step-categories') };

    gtkpack__(my $vb = Gtk2::VBox->new(0, 3), $steps{inst} = $category->(N("System installation")), '');
    foreach (grep { !eval $o->{steps}{$_}{hidden} } @{$o->{orderedSteps}}) {
	$_ eq 'setRootPassword'
	  and gtkpack__($vb, '', '', $steps{conf} = $category->(N("System configuration")), '');
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

    return if $::logowidth == 0 || $::move;

    gtkdestroy($o->{logo_window});

    my $w = bless {}, 'ugtk2';
    $w->{rwindow} = $w->{window} = Gtk2::Window->new('toplevel');
#    $w->{rwindow}->set_position(0, 0);
    $w->{rwindow}->set_size_request($::logowidth, $::logoheight);
    $w->{rwindow}->set_name("logo");
    $w->{rwindow}->set_title('skip');
    $w->show;
    my $file = $o->{meta_class} eq 'firewall' ? "logo-mandrake-Firewall.png" : "logo-mandrake.png";
    -r $file or $file = "$ENV{SHARE_PATH}/$file";
    -r $file and gtkadd($w->{window}, gtkcreate_img($file));
    $o->{logo_window} = $w;
}

#------------------------------------------------------------------------------
sub init_gtk {
    my ($o) = @_;

    symlink("/tmp/stage2/etc/$_", "/etc/$_") foreach qw(gtk-2.0 pango fonts);

    if ($o->{vga16}) {
        #- inactivate antialias in VGA16 because it makes fonts look worse
        output('/tmp/fonts.conf',
q(<fontconfig>
<include>/etc/fonts/fonts.conf</include>
<match target="font"><edit name="antialias"><bool>false</bool></edit></match>
</fontconfig>
));
        $ENV{FONTCONFIG_FILE} = '/tmp/fonts.conf';
    }

    Gtk2->init;
    Gtk2->set_locale;
}

#------------------------------------------------------------------------------
sub init_sizes() {
    ($::rootwidth,  $::rootheight)    = (Gtk2::Gdk->screen_width, Gtk2::Gdk->screen_height);
    #- ($::rootheight,  $::rootwidth)    = (min(768, $::rootheight), min(1024, $::rootwidth));
    $::stepswidth = $::rootwidth <= 640 ? 0 : 200 if !$::move;
    ($::logowidth, $::logoheight) = $::rootwidth <= 640 ? (0, 0) : (500, 40);
    ($::helpwidth,   $::helpheight)   = ($::rootwidth - $::stepswidth, $::move && 15);
    ($::windowwidth, $::windowheight) = ($::rootwidth - $::stepswidth, $::rootheight - $::helpheight - $::logoheight);
    ($::real_windowwidth, $::real_windowheight) = (576, 418);
    $::move and $::windowwidth -= 100;
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $mouse_type, $mouse_dev, $_wacom_dev, $Driver) = @_;

    symlinkf(devices::make($mouse_dev), "/dev/mouse") if $mouse_dev ne 'none';

    #- needed for imlib to start on 8-bit depth visual.
    symlink("/tmp/stage2/etc/imrc", "/etc/imrc");
    symlink("/tmp/stage2/etc/im_palette.pal", "/etc/im_palette.pal");

    #- remove "error opening security policy file" warning
    symlink("/tmp/stage2/etc/X11", "/etc/X11");

if ($Driver) {
     output($file, sprintf(<<'END', ($::globetrotter ? "" : 'Option "XkbDisable"'), $mouse_type, $Driver, $Driver eq 'fbdev' ? '"default"' : '"800x600" "640x480"'));
Section "Files"
   FontPath   "/usr/X11R6/lib/X11/fonts:unscaled"
EndSection

Section "InputDevice"
    Identifier "Keyboard"
    Driver "Keyboard"
    %s
    Option "XkbModel" "pc105"
    Option "XkbLayout" ""
EndSection

Section "InputDevice"
    Identifier "Mouse"
    Driver "mouse"
    Option "Protocol" "%s"
    Option "Device" "/dev/mouse"
    Option "ZAxisMapping" "4 5"
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
        Modes %s
    EndSubsection
EndSection

Section "ServerLayout"
    Identifier "layout"
    Screen "screen"
    InputDevice "Mouse" "CorePointer"
    InputDevice "Keyboard" "CoreKeyboard"
EndSection

END
 }
}

1;
