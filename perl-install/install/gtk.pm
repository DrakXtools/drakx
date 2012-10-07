package install::gtk; # $Id$

use diagnostics;
use strict;

use ugtk2;
use mygtk2;
use common;
use lang;
use devices;
use detect_devices;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################

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

    my $f = $name;
    -r $name or $f = find { -r $_ } map { "$_/themes-$name.rc" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__) . '/..');
    if ($f) {
	Gtk2::Rc->parse_string($o->{doc} ? $theme_overriding_for_doc : scalar cat_($f));
   }
}

#------------------------------------------------------------------------------
sub load_font {
    my ($o) = @_;

    if (defined($::WizardWindow) && lang::text_direction_rtl()) {
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
    $o->{simple_themes} || $o->{vga16} ? 'blue' : 'galaxy';
}

my $root_window;

sub install_theme {
    my ($o) = @_;

    load_rc($o, $o->{theme} ||= default_theme($o));
    load_font($o);

    my $win = gtknew('Window', widget_name => 'background', title => 'root window');
    $win->set_type_hint('desktop'); # for matchbox window manager
    $win->realize;
    mygtk2::set_root_window_background_with_gc($win->style->bg_gc('normal'));
    $root_window = $win;
}

sub create_step_box {
    gtknew('HBox', spacing => 0, children => [
        @_,
        0, gtknew('Alignment', width => 24),
    ]);
}

#------------------------------------------------------------------------------
my %steps;
sub create_steps_window {
    my ($o) = @_;

    $o->{steps_window} and $o->{steps_window}->destroy;

    $steps{$_} ||= gtknew('Pixbuf', file => "steps_$_") foreach qw(on off done);

    my $category = sub { 
	create_step_box(
	    1, gtknew('Label_Right', text_markup => '<b>' . uc($_[0]) . '</b>', widget_name => 'Step-categories'),
	);
    };

    my @l = (
        $category->(N("Installation"))
    );
    foreach (grep { !eval $o->{steps}{$_}{hidden} } @{$o->{orderedSteps}}) {
	if ($_ eq 'setRootPassword_addUser') {
	    push @l, '', $category->(N("Configuration"));
	}
	my $img = gtknew('Image', file => 'steps_off.png');
	$steps{steps}{$_}{img} = $img;
	push @l, create_step_box(
            1, $steps{steps}{$_}{text} = gtknew('Label_Right', text => translate($o->{steps}{$_}{text})),
            0, gtknew('Alignment', width => 6),
            0, $img,
        );
    }

    my $offset = 10;
    $o->{steps_widget} =
      gtknew('MDV_Notebook', widget_name => 'Steps', children => [
          # 145 is the vertical offset in order to be below the actual logo:
          [ gtknew('VBox', spacing => 6, width => ($::stepswidth - $offset), children_tight => \@l), 0, 145 ]
      ]);

    $root_window->add(
        $o->{steps_window} = 
          gtknew('HBox',
                 children =>
                   [
                       if_($::stepswidth != 0, 0, $o->{steps_widget}),
                       1, gtknew('Label', width => -1, height => -1),
                   ],
             )
    );
        
    $root_window->show_all;
}

sub update_steps_position {
    my ($o) = @_;
    return if !$steps{steps};
    my $last_step;
    foreach (@{$o->{orderedSteps}}) {
	exists $steps{steps}{$_} or next;
	if ($o->{steps}{$_}{entered} && !$o->{steps}{$_}{done}) {
            # we need to flush the X queue since else we got a temporary Y position of -1 when switching locales:
            mygtk2::flush(); #- for auto_installs which never go through the Gtk2 main loop
            $o->{steps_widget}->move_selection($steps{steps}{$_}{text});

            if ($last_step) {
                $steps{steps}{$last_step}{img}->set_from_pixbuf($steps{done});
            }
	    return;
	}
        $last_step = $_;
    }
    mygtk2::flush(); #- for auto_installs which never go through the Gtk2 main loop
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
sub init_sizes {
    my ($o) = @_;
    ($::rootwidth,  $::rootheight)    = (Gtk2::Gdk->screen_width, Gtk2::Gdk->screen_height);
    $::stepswidth = $::rootwidth <= 640 ? 0 : 196;
    ($::logowidth, $::logoheight) = $::rootwidth <= 640 ? (0, 0) : (800, 75);
    ($o->{windowwidth}, $o->{windowheight}) = ($::rootwidth - $::stepswidth, $::rootheight);
    ($::real_windowwidth, $::real_windowheight) = (601, 600);
}

sub handle_unsafe_mouse {
    my ($o, $window) = @_;

    $o->{mouse}{unsafe} or return;

    $window->add_events('pointer-motion-mask');
    my $signal; $signal = $window->signal_connect(motion_notify_event => sub {
	delete $o->{mouse}{unsafe};
	log::l("unsetting unsafe mouse");
	$window->signal_handler_disconnect($signal);
    });
}

sub special_shortcuts {
    my (undef, $event) = @_;
    my $d = ${{ $Gtk2::Gdk::Keysyms{F2} => 'screenshot', $Gtk2::Gdk::Keysyms{Home} => 'restart' }}{$event->keyval};
    if ($d eq 'screenshot') {
	install::any::take_screenshot($::o);
    } elsif ($d eq 'restart' && member('control-mask', @{$event->state}) && member('mod1-mask', @{$event->state})) {
	log::l("restarting install");
	ugtk2->exit(0x35);
    }
    0;
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $mouse_type, $mouse_dev, $_wacom_dev, $Driver) = @_;

    $mouse_type = 'IMPS/2' if $mouse_type eq 'vboxmouse';
    symlinkf(devices::make($mouse_dev), "/dev/mouse") if $mouse_dev ne 'none';

    return if !$Driver;

     my ($mouse_driver, $mouse_protocol) = detect_devices::is_vmware() ? qw(vmmouse auto) : ('mouse', $mouse_type);
     output($file, sprintf(<<'END', $mouse_driver, $mouse_protocol, $Driver, $Driver eq 'fbdev' ? '"default"' : '"1024x768" "800x600" "640x480"'));
Section "ServerFlags"
   Option "AutoAddDevices" "False"
EndSection

Section "Module"
      Disable "dbe"
      Disable "record"
      Disable "dri"
      Disable "dri2"
      Disable "glx"
EndSection

Section "Files"
   FontPath   "/usr/share/fonts:unscaled"
EndSection

Section "InputDevice"
    Identifier "Keyboard"
    Driver "keyboard"
    Option "XkbModel" "pc105"
    Option "XkbLayout" "us"
EndSection

Section "InputDevice"
    Identifier "Mouse"
    Driver "%s"
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
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
    Identifier "layout"
    Screen "screen"
    InputDevice "Mouse" "CorePointer"
    InputDevice "Keyboard" "CoreKeyboard"
EndSection

END
}

1;
