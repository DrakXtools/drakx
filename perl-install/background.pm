package background;

use Gtk3;

sub draw_bg_pixbuf($$) {
    my ($widget, $event) = @_;
    my $gdk_window = $widget->window;
    my ($w, $h) = $gdk_window->get_size;
    if (!defined($::bg_pixbuf_orig)) {
        eval {
	    my $default_bg = "/usr/share/mdk/backgrounds/default";
	    $default_bg .= (-f "$default_bg.png" ? ".png" : ".jpg");
	    $::bg_pixbuf_orig = Gtk3::Gdk::Pixbuf->new_from_file();
        };
	if (!$::bg_pixbuf_orig) {
	    print STDERR "Failed to load image file!\n";
	    return 0;
        }
    }
    if (!defined($::bg_pixbuf)) {
	$::bg_pixbuf = $::bg_pixbuf_orig;
    }
    my ($pw, $ph) = ($::bg_pixbuf->get_width, $::bg_pixbuf->get_height);
    if (($w != $pw) or ($h != $ph)) {
        $::bg_pixbuf = $::bg_pixbuf_orig->scale_simple($w, $h, 'bilinear');
	my $rect = Gtk3::Gdk::Rectangle->new(0, 0, $w, $h);
	$gdk_window->invalidate_rect($rect, TRUE);
    }
    $gdk_window->draw_pixbuf($widget->style->bg_gc('normal'), $::bg_pixbuf, 0, 0, 0, 0, $w, $h, 'none', 0, 0);
    return 1;
}

my $bg_window;

sub show_bg_window {
    $bg_window = Gtk3::Window->new();
    $bg_window->signal_connect('destroy', sub { Gtk3->main_quit; });
    $bg_window->maximize;
    $bg_window->set_keep_below(TRUE);
    $bg_window->signal_connect('expose-event', \&draw_bg_pixbuf);
    $bg_window->show;
}

sub hide_bg_window {
    $bg_window->hide;
    $bg_window->destroy;
}

1;

