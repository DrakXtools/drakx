package install::gtk;

use diagnostics;
use strict;

use ugtk3;
use mygtk3;
use common;
use lang;
use devices;
use detect_devices;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################

# FIXME: either drop 'doc' option or convert this to CSS!
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
sub load_css {
    my ($o, $name) = @_;

    my $f = $name;
    -r $name or $f = find { -r $_ } map { "$_/themes-$name.css" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__) . '/..');
    if ($f) {
	my $pl = Gtk3::CssProvider->new;
	$pl->load_from_data($o->{doc} ? $theme_overriding_for_doc : scalar cat_($f));
	Gtk3::StyleContext::add_provider_for_screen(Gtk3::Gdk::Screen::get_default(), $pl, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
   }
}

#------------------------------------------------------------------------------
sub load_font {
    my ($o) = @_;

    if (defined($::WizardWindow) && lang::text_direction_rtl()) {
	Gtk3::Widget::set_default_direction('rtl');
	my ($x, $y) = $::WizardWindow->get_position;
	my ($width) = $::WizardWindow->get_size;
	$::WizardWindow->move($::rootwidth - $width - $x, $y);
    }

    my $font = lang::l2pango_font($o->{locale}{lang});
    my $s = qq(gtk-font-name = $font);
    my $pl = Gtk3::CssProvider->new;
    $pl->load_from_data(sprintf("GtkWindow { %s }", lang::l2css_font($o->{locale}{lang})));
    Gtk3::StyleContext::add_provider_for_screen(Gtk3::Gdk::Screen::get_default(), $pl, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
    # FIXME: this should be done in /mnt too for forked app such as gurpmi{,.addmedia} (mga#67):
    output("/.config/gtk-3.0/settings.ini", qq([Settings]
$s
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

    load_css($o, $o->{theme} ||= default_theme($o));
    load_font($o);

    my $win = gtknew('Window', widget_name => 'background', title => 'root window');
    $win->set_type_hint('desktop'); # for matchbox window manager
    $win->realize;
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
            mygtk3::flush(); #- for auto_installs which never go through the Gtk3 main loop
            $o->{steps_widget}->move_selection($steps{steps}{$_}{text});

            if ($last_step) {
                $steps{steps}{$last_step}{img}->set_from_pixbuf($steps{done});
            }
	    return;
	}
        $last_step = $_;
    }
    mygtk3::flush(); #- for auto_installs which never go through the Gtk3 main loop
}

#------------------------------------------------------------------------------
sub init_gtk {
    my ($o) = @_;

    symlink("/tmp/stage2/etc/$_", "/etc/$_") foreach qw(gtk-3.0 pango fonts);

    # Custom _global_ CSS:
    mkdir_p("/.config/gtk-3.0");  # TODO/FIXME: set ENV{HOME} ?
    # FIXME: this should be done in /mnt too for forked app such as gurpmi{,.addmedia} (mga#67):
    symlinkf('/usr/lib/libDrakX/gtk.css', '/.config/gtk-3.0/gtk.css');

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

    Gtk3->init;
    c::init_setlocale();
}

#------------------------------------------------------------------------------
sub init_sizes {
    my ($o) = @_;
    ($::rootwidth,  $::rootheight)    = (Gtk3::Gdk::Screen::width, Gtk3::Gdk::Screen::height);
    $::stepswidth = $::rootwidth <= 640 ? 0 : 196;
    ($o->{windowwidth}, $o->{windowheight}) = ($::rootwidth - $::stepswidth, $::rootheight);
    ($::real_windowwidth, $::real_windowheight) = (640, 500);
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
    my $d = ${{ Gtk3::Gdk::KEY_F2 => 'screenshot', Gtk3::Gdk::KEY_Home => 'restart' }}{$event->keyval};
    if ($d eq 'screenshot') {
	# FIXME: should handle the fact it doesn't work when chrooted by urpmi during transaction:
	install::any::take_screenshot($::o);
    } elsif ($d eq 'restart' && member('control-mask', @{$event->state}) && member('mod1-mask', @{$event->state})) {
	log::l("restarting install");
	ugtk3->exit(0x35);
    }
    0;
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $Driver) = @_;

    #- remove "error opening security policy file" warning
    symlink("/tmp/stage2/etc/X11", "/etc/X11");

    return if !$Driver;

     # grub2-efi init framebuffer in 1024x768, we must stay in sync or loading fails
     my $resolution = $Driver eq 'fbdev' ? is_uefi() ? '"1024x768"' : '"default"' : '"800x600" "640x480"';
     # efi framebuffer wants 24 bit
     my $depth = is_uefi() ? '24' : '16';

     my $driversection = $Driver eq 'auto' ? "" : qq(Section "Device"
    Identifier "device"
    Driver "$Driver"
EndSection);

     output($file, qq(Section "ServerFlags"
EndSection

Section "Module"
      Disable "glx"
EndSection

Section "Files"
   FontPath   "/usr/share/fonts:unscaled"
EndSection

Section "Monitor"
    Identifier "monitor"
    HorizSync 31.5-35.5
    VertRefresh 50-70
EndSection

$driversection

Section "Screen"
    Identifier "screen"
    Device "device"
    Monitor "monitor"
    DefaultColorDepth $depth
    Subsection "Display"
        Depth $depth
        Modes $resolution
    EndSubsection
EndSection

Section "ServerLayout"
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
    Identifier "layout"
    Screen "screen"
EndSection
));
}

1;
