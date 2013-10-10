package mygtk3;

use diagnostics;
use strict;
use feature 'state';

our @ISA = qw(Exporter);
our @EXPORT = qw(gtknew gtkset gtkadd gtkval_register gtkval_modify);

use c;
use log;
use common;

use Gtk3;

sub init() {
    !check_for_xserver() and print("Cannot be run in console mode.\n"), c::_exit(0);
    $::one_message_has_been_translated and warn("N() was called from $::one_message_has_been_translated BEFORE gtk3 initialisation, replace it with a N_() AND a translate() later.\n"), c::_exit(1);

    Gtk3->init;
    Locale::gettext::bind_textdomain_codeset($_, 'UTF8') foreach 'libDrakX', if_(!$::isInstall, 'libDrakX-standalone'),
        if_($::isRestore, 'draksnapshot'), if_($::isInstall, 'urpmi'),
        'drakx-net', 'drakx-kbd-mouse-x11', # shared translation
          @::textdomains;
    Glib->enable_exceptions3;
}
init() unless $::no_ugtk_init;
Glib->enable_exceptions3 if $::isInstall;



sub gtknew {
    my $class = shift;
    if (@_ % 2 != 0) {
	internal_error("gtknew $class: bad options @_");
    }
    if (my $r = find { ref $_->[0] } group_by2(@_)) {
	internal_error("gtknew $class: $r should be a string in @_");
    }
    my %opts = @_;
    _gtk(undef, $class, 'gtknew', \%opts);
}

sub gtkset {
    my $w = shift;
    my $class = ref($w);
    if (@_ % 2 != 0) {
	internal_error("gtkset $class: bad options @_");
    }
    if (my $r = find { ref $_->[0] } group_by2(@_)) {
	internal_error("gtkset $class: $r should be a string in @_");
    }
    my %opts = @_;

    $class =~ s/^(Gtk3|Gtk3::Gdk|mygtk3)::// or internal_error("gtkset unknown class $class");
    
    _gtk($w, $class, 'gtkset', \%opts);
}

sub gtkadd {
    my $w = shift;
    my $class = ref($w);
    if (@_ % 2 != 0) {
	internal_error("gtkadd $class: bad options @_");
    }
    if (my $r = find { ref $_->[0] } group_by2(@_)) {
	internal_error("gtkadd $class: $r should be a string in @_");
    }
    my %opts = @_;
    $class =~ s/^(Gtk3|Gtk3::Gdk|mygtk3)::// or internal_error("gtkadd unknown class $class");
    
    _gtk($w, $class, 'gtkadd', \%opts);
}


my %refs;

sub gtkval_register {
    my ($w, $ref, $sub) = @_;
    push @{$w->{_ref}}, $ref;
    $w->signal_connect(destroy => sub { 
	@{$refs{$ref}} = grep { $_->[1] != $w } @{$refs{$ref}};
	delete $refs{$ref} if !@{$refs{$ref}};
    });
    push @{$refs{$ref}}, [ $sub, $w ];
}
sub gtkval_modify {
    my ($ref, $val, @to_skip) = @_;
    my $prev = '' . $ref;
    $$ref = $val;
    if ($prev ne '' . $ref) {
	internal_error();
    }
    foreach (@{$refs{$ref} || []}) {	
	my ($f, @para) = @$_;
	$f->(@para) if !member($f, @to_skip);
    }
}

sub _gtk {
    my ($w, $class, $action, $opts) = @_;

    if (my $f = $mygtk3::{"_gtk__$class"}) {
	$w = $f->($w, $opts, $class, $action);
    } else {
	internal_error("$action $class: unknown class");
    }

    $w->set_size_request(delete $opts->{width} || -1, delete $opts->{height} || -1) if exists $opts->{width} || exists $opts->{height};
    if (my $position = delete $opts->{position}) {
	$w->move($position->[0], $position->[1]);
    }
    $w->set_name(delete $opts->{widget_name}) if exists $opts->{widget_name};
    $w->set_can_focus(delete $opts->{can_focus}) if exists $opts->{can_focus};
    $w->set_can_default(delete $opts->{can_default}) if exists $opts->{can_default};
    $w->grab_focus if delete $opts->{grab_focus};
    $w->set_padding(@{delete $opts->{padding}}) if exists $opts->{padding};
    $w->set_sensitive(delete $opts->{sensitive}) if exists $opts->{sensitive};
    $w->signal_connect(draw => delete $opts->{draw}) if exists $opts->{draw};
    $w->signal_connect(realize => delete $opts->{realize}) if exists $opts->{realize};
    (delete $opts->{size_group})->add_widget($w) if $opts->{size_group};
    if (my $tip = delete $opts->{tip}) {
	$w->set_tooltip_text($tip);
    }

    #- WARNING: hide_ref and show_ref are not effective until you gtkval_modify the ref
    if (my $hide_ref = delete $opts->{hide_ref}) {
	gtkval_register($w, $hide_ref, sub { $$hide_ref ? $w->hide : $w->show });
    } elsif (my $show_ref = delete $opts->{show_ref}) {
	gtkval_register($w, $show_ref, sub { $$show_ref ? $w->show : $w->hide });
    }

    if (my $sensitive_ref = delete $opts->{sensitive_ref}) {
	my $set = sub { $w->set_sensitive($$sensitive_ref) };
	gtkval_register($w, $sensitive_ref, $set);
	$set->();
    }

    if (%$opts && !$opts->{allow_unknown_options}) {
	internal_error("$action $class: unknown option(s) " . join(', ', keys %$opts));
    }
    $w;
}

sub _gtk__Install_Button {
    my ($w, $opts, $_class) = @_;
    $opts->{child} = gtknew('HBox', spacing => 5, 
                             children_tight => [
                                 # FIXME: not RTL compliant (lang::text_direction_rtl() ? ...)
                                 gtknew('Image', file => 'advanced_expander'),
                                 gtknew('Label', text => delete $opts->{text}),
                             ],
                         );
    $opts->{relief} = 'none';
    _gtk__Button($w, $opts, 'Button');
}

sub _gtk__Button       { &_gtk_any_Button }
sub _gtk__ToggleButton { &_gtk_any_Button }
sub _gtk__CheckButton  { &_gtk_any_Button }
sub _gtk__RadioButton  { &_gtk_any_Button }
sub _gtk_any_Button {
    my ($w, $opts, $class) = @_;

    if (!$w) {
        my @radio_options;
        if ($class eq 'RadioButton') {
            @radio_options = delete $opts->{group};
	}
	$w = $opts->{child} ? "Gtk3::$class"->new(@radio_options) :
	  delete $opts->{mnemonic} ? "Gtk3::$class"->new_with_mnemonic(@radio_options, delete $opts->{text} || '') :
	    $opts->{text} ? "Gtk3::$class"->new_with_label(@radio_options, delete $opts->{text} || '') :
           "Gtk3::$class"->new(@radio_options);

	$w->{format} = delete $opts->{format} if exists $opts->{format};
    }

    if (my $widget = delete $opts->{child}) {
	$w->add($widget);
	$widget->show;
    }
    $w->set_image(delete $opts->{image}) if exists $opts->{image};
    $w->set_relief(delete $opts->{relief}) if exists $opts->{relief};

    if (my $text_ref = delete $opts->{text_ref}) {
	my $set = sub {
	    eval { $w->set_label(may_apply($w->{format}, $$text_ref)) };
	};
	gtkval_register($w, $text_ref, $set);
	$set->();
    } elsif (exists $opts->{text}) {
	$w->set_label(delete $opts->{text});
    } elsif (exists $opts->{stock}) {
	$w->set_label(delete $opts->{stock});
	$w->set_use_stock(1);
    }

    if ($class eq 'Button') {
	$w->signal_connect(clicked => delete $opts->{clicked}) if exists $opts->{clicked};
    } else {
	if (my $active_ref = delete $opts->{active_ref}) {
	    my $set = sub { $w->set_active($$active_ref) };
	    $w->signal_connect(toggled => sub {
		gtkval_modify($active_ref, $w->get_active, $set);
	    });
	    gtkval_register($w, $active_ref, $set);
	    gtkval_register($w, $active_ref, delete $opts->{toggled}) if exists $opts->{toggled};
	    $set->();
	} else {
	    $w->set_active(delete $opts->{active}) if exists $opts->{active};
	    $w->signal_connect(toggled => delete $opts->{toggled}) if exists $opts->{toggled};
	}
    }
    $w;
}

sub _gtk__CheckMenuItem {
    my ($w, $opts, $class) = @_;

    if (!$w) {
	add2hash_($opts, { mnemonic => 1 });

	$w = $opts->{image} || !exists $opts->{text} ? "Gtk3::$class"->new :
	  delete $opts->{mnemonic} ? "Gtk3::$class"->new_with_label(delete $opts->{text}) :
	    "Gtk3::$class"->new_with_mnemonic(delete $opts->{text});
    }

    $w->set_active(delete $opts->{active}) if exists $opts->{active};
    $w->signal_connect(toggled => delete $opts->{toggled}) if exists $opts->{toggled};
    $w;
}

sub _gtk__SpinButton {
    my ($w, $opts) = @_;

    if (!$w) {
	$opts->{adjustment} ||= do {
	    add2hash_($opts, { step_increment => 1, page_increment => 5, page_size => 1, value => delete $opts->{lower} });
	    Gtk3::Adjustment->new(delete $opts->{value}, delete $opts->{lower}, delete $opts->{upper}, delete $opts->{step_increment}, delete $opts->{page_increment}, delete $opts->{page_size});
	};
	$w = Gtk3::SpinButton->new(delete $opts->{adjustment}, delete $opts->{climb_rate} || 0, delete $opts->{digits} || 0);
    }

    $w->signal_connect(value_changed => delete $opts->{value_changed}) if exists $opts->{value_changed};
    $w;
}

sub _gtk__HScale {
    my ($w, $opts) = @_;

    if (!$w) {
	$opts->{adjustment} ||= do {
	    add2hash_($opts, { step_increment => 1, page_increment => 5, page_size => 1 });
	    add2hash_($opts, { value => $opts->{lower} }) if !exists $opts->{value};
	    Gtk3::Adjustment->new(delete $opts->{value}, delete $opts->{lower}, (delete $opts->{upper}) + 1, delete $opts->{step_increment}, delete $opts->{page_increment}, delete $opts->{page_size});
	};
	$w = Gtk3::HScale->new(delete $opts->{adjustment});
    }

    $w->set_digits(delete $opts->{digits}) if exists $opts->{digits};
    if (my $value_ref = delete $opts->{value_ref}) {
	my $set = sub { $w->set_value($$value_ref) };
	gtkval_register($w, $value_ref, $set);
	$set->();
	$w->signal_connect(value_changed => sub {
		gtkval_modify($value_ref, $w->get_value, $set);
	});
    }
    $w->signal_connect(value_changed => delete $opts->{value_changed}) if exists $opts->{value_changed};
    $w;
}

sub _gtk__ProgressBar {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk3::ProgressBar->new;
    }

    if (my $fraction_ref = delete $opts->{fraction_ref}) {
	my $set = sub { $w->set_fraction($$fraction_ref) };
	gtkval_register($w, $fraction_ref, $set);
	$set->();
    } elsif (exists $opts->{fraction}) {
	$w->set_fraction(delete $opts->{fraction});
    }

    $w;
}

sub _gtk__VSeparator { &_gtk_any_simple }
sub _gtk__HSeparator { &_gtk_any_simple }
sub _gtk__Calendar   { &_gtk_any_simple }

sub _gtk__DrawingArea {
    my ($w, $_opts) = @_;

    if (!$w) {
	$w = Gtk3::DrawingArea->new;
    }
    $w;
}

sub _gtk__Pixbuf {
    my ($w, $opts) = @_;

    if (!$w) {
	my $name = delete $opts->{file} or internal_error("missing file");
	my $file = _find_imgfile($name) or internal_error("cannot find image $name");
	if (my $size = delete $opts->{size}) {
	    $w = Gtk3::Gdk::Pixbuf->new_from_file_at_scale($file, $size, $size, 1);
	} else {
	    $w = Gtk3::Gdk::Pixbuf->new_from_file($file);
	}
        $w = $w->flip(1) if delete $opts->{flip};
    }
    $w;
}

# Image_using_pixmap is rendered using DITHER_MAX which is much better on 16bpp displays
sub _gtk__Image_using_pixmap { &_gtk__Image }
# Image_using_pixbuf is rendered using DITHER_MAX & transparency which is much better on 16bpp displays
sub _gtk__Image_using_pixbuf { &_gtk__Image }
sub _gtk__Image {
    my ($w, $opts, $class) = @_;

    if (!$w) {
	$w = Gtk3::Image->new;
	$w->{format} = delete $opts->{format} if exists $opts->{format};
        
        $w->set_from_stock(delete $opts->{stock}, 'button') if exists $opts->{stock};

        $w->{options} = { flip => delete $opts->{flip} };

        $w->{set_from_file} = $class =~ /using_pixmap/ ? sub { 
            my ($w, $file) = @_;
            my $pixmap = mygtk3::pixmap_from_pixbuf($w, gtknew('Pixbuf', file => $file));
	    $w->set_from_pixmap($pixmap, undef);
        } : $class =~ /using_pixbuf/ ? sub { 
            my ($w, $file) = @_;
            my $pixbuf = _pixbuf_render_alpha(gtknew('Pixbuf', file => $file, %{$w->{options}}), 255);
            my ($width, $height) = ($pixbuf->get_width, $pixbuf->get_height);
            $w->set_size_request($width, $height);
            $w->{pixbuf} = $pixbuf;
            $w->signal_connect(draw => sub {
                                   my (undef, $event) = @_;
                                   if (!$w->{x}) {
                                       my $alloc = $w->get_allocation;
                                       $w->{x} = $alloc->x;
                                       $w->{y} = $alloc->y;
                                   }
                                   # workaround Gtk+ bug: in installer, first event is not complete and rectables are bogus:
                                   if ($::isInstall) {
                                       $pixbuf->render_to_drawable($w->get_window, $w->style->fg_gc('normal'),
                                                                   0, 0, $w->{x}, $w->{y}, $width, $height, 'max', 0, 0);
                                       return;
                                   }
                                   foreach my $rect ($event->region->get_rectangles) {
                                       my @values = $rect->values;
                                       $pixbuf->render_to_drawable($w->get_window, $w->style->fg_gc('normal'),
                                                               @values[0..1], $w->{x}+$values[0], $w->{y}+$values[1], @values[2..3], 'max', 0, 0);
				   }
                               });
        } : sub { 
            my ($w, $file, $o_size) = @_;
            my $pixbuf = gtknew('Pixbuf', file => $file, if_($o_size, size => $o_size), %{$w->{options}});
            $w->set_from_pixbuf($pixbuf);
        };
    }

    if (my $name = delete $opts->{file}) {
	my $file = _find_imgfile(may_apply($w->{format}, $name)) or internal_error("cannot find image $name");
	$w->{set_from_file}->($w, $file, delete $opts->{size});
    } elsif (my $file_ref = delete $opts->{file_ref}) {
	my $set = sub {
	    my $file = _find_imgfile(may_apply($w->{format}, $$file_ref)) or internal_error("cannot find image $$file_ref");
	    $w->{set_from_file}->($w, $file, delete $opts->{size});
	};
	gtkval_register($w, $file_ref, $set);
	$set->() if $$file_ref;
    }
    $w;
}

sub _gtk__WrappedLabel {
    my ($w, $opts) = @_;
    
    $opts->{line_wrap} = 1 if !defined $opts->{line_wrap};
    _gtk__Label($w, $opts);
}

our $left_padding = 20;

sub _gtk__Label_Left {
    my ($w, $opts) = @_;
    $opts->{alignment} ||= [ 0, 0 ];
    $opts->{padding} ||= [ $left_padding, 0 ];
    _gtk__WrappedLabel($w, $opts);
}

sub _gtk__Label_Right {
    my ($w, $opts) = @_;
    $opts->{alignment} ||= [ 1, 0.5 ];
    _gtk__Label($w, $opts);
}


sub _gtk__Label {
    my ($w, $opts) = @_;

    if ($w) {
	$w->set_text(delete $opts->{text}) if exists $opts->{text};
    } else {
	$w = Gtk3::Label->new(delete $opts->{text});
	$w->set_selectable(delete $opts->{selectable}) if exists $opts->{selectable};
	$w->set_ellipsize(delete $opts->{ellipsize}) if exists $opts->{ellipsize};
	$w->set_justify(delete $opts->{justify}) if exists $opts->{justify};
	$w->set_line_wrap(delete $opts->{line_wrap}) if exists $opts->{line_wrap};
	$w->set_alignment(@{delete $opts->{alignment}}) if exists $opts->{alignment};
	$w->override_font(Pango::FontDescription->from_string(delete $opts->{font})) if exists $opts->{font};
    }

    if (my $text_ref = delete $opts->{text_ref}) {
	my $set = sub { $w->set_text($$text_ref) };
	gtkval_register($w, $text_ref, $set);
	$set->();
    }

    if (my $t = delete $opts->{text_markup}) {
	$w->set_markup($t);
	if ($w->get_text eq '') {
	    log::l("invalid markup in $t. not using the markup");
	    $w->set_text($t);
	}
    }
    $w;
}


sub _gtk__Alignment {
    my ($w, $_opts) = @_;

    if (!$w) {
	$w = Gtk3::Alignment->new(0, 0, 0, 0);
    }
    $w;
}


sub title1_to_markup {
    my ($label) = @_;
    if ($::isInstall) {
        my $font = lang::l2pango_font($::o->{locale}{lang});
        if (my ($font_size) = $font =~ /(\d+)/) {
            $font_size++;
            $font =~ s/\d+/$font_size/;
        }
        qq(<span foreground="#5A8AD6" font="$font">$label</span>);
    } else {
        qq(<b><big>$label</big></b>);
  }
}

sub _gtk__Install_Title {
    my ($w, $opts) = @_;
    local $opts->{widget_name} = 'Banner';
    $opts->{text} = uc($opts->{text}) if $::isInstall;
    gtknew('HBox', widget_name => 'Banner', children => [
        0, gtknew('Label', padding => [ 6, 0 ]),
        1, gtknew('VBox', widget_name => 'Banner', children_tight => [
            _gtk__Title2($w, $opts),
            if_($::isInstall, Gtk3::HSeparator->new),
        ]),
        0, gtknew('Label', padding => [ 6, 0 ]),
    ]);
}

sub _gtk__Title1 {
    my ($w, $opts) = @_;
    $opts ||= {};
    $opts->{text_markup} = title1_to_markup(delete($opts->{label})) if $opts->{label};
    _gtk__WrappedLabel($w, $opts);
}

sub _gtk__Title2 {
    my ($w, $opts) = @_;
    $opts ||= {};
    $opts->{alignment} = [ 0, 0 ];
    _gtk__Title1($w, $opts);
}

sub _gtk__Sexy_IconEntry {
    my ($w, $opts) = @_;

    require Gtk3::Sexy;
    if (!$w) {
	$w = Gtk3::Sexy::IconEntry->new;
	$w->set_editable(delete $opts->{editable}) if exists $opts->{editable};
    }

    $w->add_clear_button if delete $opts->{clear_button};
    if (my $icon = delete $opts->{primary_icon}) {
        $w->set_icon('primary', $icon);
        $w->set_icon_highlight('primary', $icon);
    }
    if (my $icon = delete $opts->{secondary_icon}) {
        $w->set_icon('secondary', $icon);
        $w->set_icon_highlight('secondary', $icon);
    }

    $w->signal_connect('icon-released' => delete $opts->{'icon-released'}) if exists $opts->{'icon-released'};
    $w->signal_connect('icon-pressed' => delete $opts->{'icon-pressed'}) if exists $opts->{'icon-pressed'};

    _gtk__Entry($w, $opts);
}

sub _gtk__Entry {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk3::Entry->new;
	$w->set_editable(delete $opts->{editable}) if exists $opts->{editable};
    }

    if (my $icon = delete $opts->{primary_icon}) {
        $w->set_icon_from_stock('primary', $icon);
        #$w->set_icon_highlight('primary', $icon);
    }
    if (my $icon = delete $opts->{secondary_icon}) {
        $w->set_icon_from_stock('secondary', $icon);
        #$w->set_icon_highlight('secondary', $icon);
    }

    $w->signal_connect('icon-release' => delete $opts->{'icon-release'}) if exists $opts->{'icon-release'};
    $w->signal_connect('icon-press' => delete $opts->{'icon-press'}) if exists $opts->{'icon-press'};

    $w->set_text(delete $opts->{text}) if exists $opts->{text};
    $w->signal_connect(key_press_event => delete $opts->{key_press_event}) if exists $opts->{key_press_event};

    if (my $text_ref = delete $opts->{text_ref}) {
	my $set = sub { $w->set_text($$text_ref) };
	gtkval_register($w, $text_ref, $set);
	$set->();
	$w->signal_connect(changed => sub {
		gtkval_modify($text_ref, $w->get_text, $set);
	});
    }

    $w;
}

sub _gtk__WeaknessCheckEntry {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = _gtk__Entry($w, $opts);
    }

    $w->signal_connect('changed' => sub {
	require authentication;
	my $password_weakness = authentication::compute_password_weakness($w->get_text);
	$w->set_icon_from_pixbuf('GTK_ENTRY_ICON_SECONDARY', _get_weakness_icon($password_weakness));
	$w->set_icon_tooltip_text('GTK_ENTRY_ICON_SECONDARY', _get_weakness_tooltip($password_weakness));
    });

    $w;
}

sub _gtk__TextView {
    my ($w, $opts, $_class, $action) = @_;
	
    if (!$w) {
	$w = Gtk3::TextView->new;
	$w->set_editable(delete $opts->{editable}) if exists $opts->{editable};
	$w->set_wrap_mode(delete $opts->{wrap_mode}) if exists $opts->{wrap_mode};
	$w->set_cursor_visible(delete $opts->{cursor_visible}) if exists $opts->{cursor_visible};
    }

    _text_insert($w, delete $opts->{text}, append => $action eq 'gtkadd') if exists $opts->{text};
    $w;
}

sub _gtk__WebKit_View {
    my ($w, $opts, $_class, $_action) = @_;
    if (!$w) {
        $w = Gtk3::WebKit::WebView->new;
    }

    # disable contextual menu:
    if (delete $opts->{no_popup_menu}) {
        $w->signal_connect('populate-popup' => sub {
                               my (undef, $menu) = @_;
                               $menu->destroy if $menu;
                               1;
                           });
    }

    $w;
}

sub _gtk__ComboBox {
    my ($w, $opts, $_class, $action) = @_;

    if (!$w) {
	$w = Gtk3::ComboBoxText->new;
	$w->{format} = delete $opts->{format} if exists $opts->{format};

    }
    my $set_list = sub {
	$w->{formatted_list} = $w->{format} ? [ map { $w->{format}($_) } @{$w->{list}} ] : $w->{list};
	$w->get_model->clear;
	$w->{strings} = $w->{formatted_list};  # used by Gtk3::ComboBox wrappers such as get_text() in ugtk3
	$w->append_text($_) foreach @{$w->{formatted_list}};
    };
    if (my $list_ref = delete $opts->{list_ref}) {
	!$opts->{list} or internal_error("both list and list_ref");
	my $set = sub {
	    $w->{list} = $$list_ref;
	    $set_list->();
	};
	gtkval_register($w, $list_ref, $set);
	$set->();
    } elsif (exists $opts->{list}) {
	$w->{list} = delete $opts->{list};
	$set_list->();
    }

    if ($action eq 'gtknew') {
	if (my $text_ref = delete $opts->{text_ref}) {
	    my $set = sub {
		my $val = may_apply($w->{format}, $$text_ref);
		eval { $w->set_active(find_index { $_ eq $val } @{$w->{formatted_list}}) };
	    };
	    $w->signal_connect(changed => sub {
		gtkval_modify($text_ref, $w->{list}[$w->get_active], $set);
	    });
	    gtkval_register($w, $text_ref, $set);
	    gtkval_register($w, $text_ref, delete $opts->{changed}) if exists $opts->{changed};
	    $set->();
	} else {
	    my $val = delete $opts->{text};
	    eval { $w->set_active(find_index { $_ eq $val } @{$w->{formatted_list}}) } if defined $val;
	    $w->signal_connect(changed => delete $opts->{changed}) if exists $opts->{changed};
	}
    }
    $w;
}

sub _gtk__ScrolledWindow {
    my ($w, $opts, $_class, $action) = @_;
	
    if (!$w) {
	$w = Gtk3::ScrolledWindow->new(undef, undef);
	$w->set_policy(delete $opts->{h_policy} || 'automatic', delete $opts->{v_policy} || 'automatic');
    }

    my $faked_w = $w;

    if (my $child = delete $opts->{child}) {
	if (member(ref($child), qw(Gtk3::Layout Gtk3::Html2::View  Gtk3::SimpleList Gtk3::SourceView::View Gtk3::Text Gtk3::TextView Gtk3::TreeView Gtk3::WebKit::WebView))) {
	    $w->add($child);
	} else {
	    $w->add_with_viewport($child);
	}
	$child->set_focus_vadjustment($w->get_vadjustment) if $child->can('set_focus_vadjustment');
	$child->set_left_margin(6) if ref($child) =~ /Gtk3::TextView/ && $child->get_left_margin <= 6;
	$child->show;

	$w->get_child->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};

	if (ref($child) eq 'Gtk3::TextView' && delete $opts->{to_bottom}) {
	    $child->{to_bottom} = _allow_scroll_TextView_to_bottom($w, $child);
	}

	if (!delete $opts->{no_shadow} && $action eq 'gtknew' && ref($child) =~ /Gtk3::(Html2|SimpleList|TextView|TreeView|WebKit::WebView)/) {
	    $faked_w = gtknew('Frame', shadow_type => 'in', child => $w);
	}
    }
    $faked_w;
}

sub _gtk__Frame {
    my ($w, $opts) = @_;

    if ($w) {
	$w->set_label(delete $opts->{text}) if exists $opts->{text};
    } else {
	$w = Gtk3::Frame->new(delete $opts->{text});
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
	$w->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};
    }

    if (my $child = delete $opts->{child}) {
	$w->add($child);
	$child->show;
    }
    $w;
}

sub _gtk__Expander {
    my ($w, $opts) = @_;

    if ($w) {
	$w->set_label(delete $opts->{text}) if exists $opts->{text};
    } else {
	$w = Gtk3::Expander->new(delete $opts->{text});
    }

    $w->signal_connect(activate => delete $opts->{activate}) if exists $opts->{activate};

    if (my $child = delete $opts->{child}) {
	$w->add($child);
	$child->show;
    }
    $w;
}



sub _gtk__MDV_Notebook {
    my ($w, $opts, $_class, $_action) = @_;
    if (!$w) {
        import_style_ressources();

        my ($layout, $selection_arrow, $selection_bar);
        my $parent_window = delete $opts->{parent_window} || root_window();
        my $root_height = first($parent_window->get_size);
        my $suffix = $root_height == 800 && !$::isStandalone ? '_600' : '_768';
        # the white square is a little bit above the actual left sidepanel:
        my $offset = 20;
        my $is_flip_needed = text_direction_rtl();
        my $filler = gtknew('Image', file => 'left-background-filler.png');
        my $filler_height = $filler->get_pixbuf->get_height;
        my $left_background = gtknew('Image_using_pixbuf', file => 'left-background.png');
        my $lf_height = $left_background->{pixbuf}->get_height;
        my @right_background = $::isInstall ? 
          gtknew('Image', file => "right-white-background_left_part$suffix", flip => $is_flip_needed)
            : map {
                gtknew('Image', file => "right-white-background_left_part-$_", flip => $is_flip_needed);
            } 1, 2, 2, 3;
        my $width1 = $left_background->{pixbuf}->get_width;
        my $total_width = $width1 + $right_background[0]->get_pixbuf->get_width;
        my $arrow_x = text_direction_rtl() ? $offset/2 - 4 : $width1 - $offset - 3;
        $w = gtknew('HBox', spacing => 0, children => [
            0, $layout = gtknew('Layout', width => $total_width - $offset, children => [ #Layout Fixed
                # stacking order is important for "Z-buffer":
                [ $left_background, 0, 0 ],
                if_($suffix ne '_600',
                   [ $filler, 0, $lf_height ],
                   [ gtknew('Image', file => 'left-background-filler.png'), 0, $lf_height + $filler_height ],
                   [ gtknew('Image', file => 'left-background-filler.png'), 0, $lf_height + $filler_height*2 ],
                ),
                [ $selection_bar = gtknew('Image', file => 'rollover.png'), 0, 0 ], # arbitrary vertical position
                ($opts->{children} ? @{ delete $opts->{children} } : ()),
                [ my $box = gtknew('VBox', spacing => 0, height => -1, children => [
                    0, $right_background[0],
                    if_(!$::isInstall,
                        1, $right_background[1],
                        1, $right_background[2], # enought up to to XYZx1280 resolution
                        0, $right_background[3],
                    ),
                ]), (text_direction_rtl() ? 0 : $width1 - $offset), 0 ],
                # stack on top (vertical position is arbitrary):
                [ $selection_arrow = gtknew('Image', file => 'steps_on', flip => $is_flip_needed), $arrow_x, 0, ],
            ]),
            1, delete $opts->{right_child} || 
              gtknew('Image_using_pixbuf', file => "right-white-background_right_part$suffix", flip => $is_flip_needed),
        ]);

        $w->signal_connect('size-allocate' => sub {
                               my (undef, $requisition) = @_;
                               state $width ||= $right_background[0]->get_pixbuf->get_width;
                               $box->set_size_request($width, $requisition->height);
                           });
        $_->set_property('no-show-all', 1) foreach $selection_bar, $selection_arrow;
        bless($w, 'Gtk3::MDV_Notebook');
        add2hash($w, {
            arrow_x         => $arrow_x,
            layout          => $layout,
            selection_arrow => $selection_arrow,
            selection_bar   =>$selection_bar,
        });
    }
    $w;
}


sub _gtk__Fixed {
    my ($w, $opts, $_class, $_action) = @_;
	
    if (!$w) {
	$w = Gtk3::Fixed->new;
	$w->set_has_window(delete $opts->{has_window}) if exists $opts->{has_window};
        _gtknew_handle_layout_children($w, $opts);
    }
    $w;
}

sub _gtk__Overlay {
    my ($w, $opts, $_class, $_action) = @_;

    if (!$w) {
	$w = Gtk3::Overlay->new;
        _gtknew_handle_overlay_children($w, $opts);
    }
    $w;
}

sub _gtknew_handle_overlay_children {
    my ($w, $opts) = @_;
        $w->add(delete $opts->{main_child}) if $opts->{main_child};
        $opts->{children} ||= [];
        foreach (@{$opts->{children}}) {
            $w->add_overlay($_);
        }
        delete $opts->{children};
}


sub _gtk__Layout {
    my ($w, $opts, $_class, $_action) = @_;
	
    if (!$w) {
	$w = Gtk3::Layout->new;
        _gtknew_handle_layout_children($w, $opts);
    }
    $w;
}

sub _gtknew_handle_layout_children {
    my ($w, $opts) = @_;
        $opts->{children} ||= [];
        push @{$opts->{children}}, [ delete $opts->{child}, delete $opts->{x}, delete $opts->{y} ] if exists $opts->{child};
        foreach (@{$opts->{children}}) {
            $w->put(@$_);
        }
        delete $opts->{children};

        if ($opts->{pixbuf_file}) {
            my $pixbuf = if_($opts->{pixbuf_file}, gtknew('Pixbuf', file => delete $opts->{pixbuf_file}));
            $w->signal_connect(
                realize => sub {
                    ugtk3::set_back_pixbuf($w, $pixbuf);
                });
        }
}


sub _gtk__Window { &_gtk_any_Window }
sub _gtk__Dialog { &_gtk_any_Window }
sub _gtk__Plug   { &_gtk_any_Window }
sub _gtk_any_Window {
    my ($w, $opts, $class) = @_;

    if (!$w) {
	if ($class eq 'Window') {
	    $w = "Gtk3::$class"->new(delete $opts->{type} || 'toplevel');
	} elsif ($class eq 'Plug') {
	    $opts->{socket_id} or internal_error("cannot create a Plug without a socket_id");
	    $w = "Gtk3::$class"->new(delete $opts->{socket_id});
	} elsif ($class eq 'FileChooserDialog') {
            my $action = delete $opts->{action} || internal_error("missing action for FileChooser");
            $w = Gtk3::FileChooserDialog->new(delete $opts->{title}, delete $opts->{transient_for} || $::main_window,
                                              $action, N("Cancel") => 'cancel', delete $opts->{button1} || N("Ok") => 'ok',
                                          );
	} else {
	    $w = "Gtk3::$class"->new;
	}

	if ($::isInstall || $::set_dialog_hint) {
	    $w->set_type_hint('dialog'); # for matchbox window manager
	}

	$w->set_modal(delete $opts->{modal}) if exists $opts->{modal};
	$opts->{transient_for} ||= $::main_window if $::main_window;
	$w->set_modal(1) if exists $opts->{transient_for};
	$w->set_transient_for(delete $opts->{transient_for}) if exists $opts->{transient_for};
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
	$w->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};
	$w->set_position(delete $opts->{position_policy}) if exists $opts->{position_policy};
	$w->set_default_size(delete $opts->{default_width} || -1, delete $opts->{default_height} || -1) if exists $opts->{default_width} || exists $opts->{default_height};
	my $icon_no_error = $opts->{icon_no_error};
	if (my $name = delete $opts->{icon} || delete $opts->{icon_no_error}) {
	    if (my $f = _find_imgfile($name)) {
		$w->set_icon(gtknew('Pixbuf', file => $f));
	    } elsif (!$icon_no_error) {
		internal_error("cannot find $name");
	    }
	}
    }
    $w->set_title(delete $opts->{title}) if exists $opts->{title};

    if (my $child = delete $opts->{child}) {
	$w->add($child);
	$child->show;
    }
    $w;
}

my $previous_popped_and_reuse_window;

sub destroy_previous_popped_and_reuse_window() {
    $previous_popped_and_reuse_window or return;

    $previous_popped_and_reuse_window->destroy;
    $previous_popped_and_reuse_window = undef;
}

sub _gtk__MagicWindow {
    my ($w, $opts) = @_;

    my $pop_it = delete $opts->{pop_it} || !$::isWizard && !$::isEmbedded || $::WizardTable && do {
	#- do not take into account the wizard banner
        # FIXME!!!
	any { !$_->isa('Gtk3::DrawingArea') && $_->get_visible } $::WizardTable->get_children;
    };

    my $pop_and_reuse = delete $opts->{pop_and_reuse} && $pop_it;
    my $sub_child = delete $opts->{child};
    my $provided_banner = delete $opts->{banner};

    if ($pop_it && $provided_banner) {
	$sub_child = gtknew('VBox', children => [ 0, $provided_banner, if_($sub_child, 1, $sub_child) ]);
    } else {
	$sub_child ||= gtknew('VBox');
    }
    if (!$pop_and_reuse) {
	destroy_previous_popped_and_reuse_window();
    }

    if ($previous_popped_and_reuse_window && $pop_and_reuse) {
	$w = $previous_popped_and_reuse_window;
	$w->remove($w->get_child);

	gtkadd($w, child => $sub_child);
	%$opts = ();
    } elsif ($pop_it) {
	$opts->{child} = $sub_child;

	$w = _create_Window($opts, '');
	$previous_popped_and_reuse_window = $w if $pop_and_reuse;
    } else {
	if (!$::WizardWindow) {

	    my $banner;
	    if (!$::isEmbedded && !$::isInstall && $::Wizard_title) {
		if (_find_imgfile($opts->{icon_no_error})) {
		    $banner = Gtk3::Banner->new($opts->{icon_no_error}, $::Wizard_title);
		} else { 
		    log::l("ERROR: missing wizard banner $opts->{icon_no_error}");
		}
	    }
	    $::WizardTable = gtknew('VBox', if_($banner, children_tight => [ $banner ]));

	    if ($::isEmbedded) {
		add2hash($opts, {
		    socket_id => $::XID,
		    child => $::WizardTable,
		});
		delete $opts->{no_Window_Manager};
		$::Plug = $::WizardWindow = _gtk(undef, 'Plug', 'gtknew', $opts);
		sync($::WizardWindow);
	    } else {
		add2hash($opts, {
		    child => $::WizardTable,
		});
		$::WizardWindow = _create_Window($opts, 'special_center');
	    }
	} else {
	    %$opts = ();
	}

	set_main_window_size($::WizardWindow);

	$w = $::WizardWindow;
     
	gtkadd($::WizardTable, children_tight => [ $provided_banner ]) if $provided_banner;
	gtkadd($::WizardTable, children_loose => [ $sub_child ]);
    }
    bless { 
	real_window => $w, 
	child => $sub_child, pop_it => $pop_it, pop_and_reuse => $pop_and_reuse,
	if_($provided_banner, banner => $provided_banner),
    }, 'mygtk3::MagicWindow';
}

# A standard About dialog. Used with:
# my $w = gtknew('AboutDialog', ...);
# $w->show_all;
# $w->run;
sub _gtk__AboutDialog {
    my ($w, $opts) = @_;

    if (!$w) {
        $w = Gtk3::AboutDialog->new;
        $w->signal_connect(response => sub { $_[0]->destroy });
        $w->set_program_name(delete $opts->{name}) if exists $opts->{name};
        $w->set_version(delete $opts->{version}) if exists $opts->{version};
        $w->set_icon(gtknew('Pixbuf', file => delete $opts->{icon})) if exists $opts->{icon};
        $w->set_logo(gtknew('Pixbuf', file => delete $opts->{logo})) if exists $opts->{logo};
        $w->set_copyright(delete $opts->{copyright}) if exists $opts->{copyright};
        $w->set_url_hook(sub {
            my (undef, $url) = @_;
            run_program::raw({ detach => 1 }, 'www-browser', $url);
        });
        $w->set_email_hook(sub {
            my (undef, $url) = @_;
            run_program::raw({ detach => 1 }, 'www-browser', $url);
        });

        if (my $url = delete $opts->{website}) {
            $url =~ s/^https:/http:/; # Gtk3::About doesn't like "https://..." like URLs
            $w->set_website($url);
        }
        $w->set_license(delete $opts->{license}) if exists $opts->{license};
        $w->set_wrap_license(delete $opts->{wrap_license}) if exists $opts->{wrap_license};
        $w->set_comments(delete $opts->{comments}) if exists $opts->{comments};
        $w->set_website_label(delete $opts->{website_label}) if exists $opts->{website_label};
        $w->set_authors(delete $opts->{authors}) if exists $opts->{authors};
        $w->set_documenters(delete $opts->{documenters}) if exists $opts->{documenters};
        $w->set_translator_credits(delete $opts->{translator_credits}) if exists $opts->{translator_credits};
        $w->set_artists(delete $opts->{artists}) if exists $opts->{artists};
        $w->set_modal(delete $opts->{modal}) if exists $opts->{modal};
        $w->set_transient_for(delete $opts->{transient_for}) if exists $opts->{transient_for};
        $w->set_position(delete $opts->{position_policy}) if exists $opts->{position_policy};
    }
    $w;
}

sub _gtk__FileSelection {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk3::FileSelection->new(delete $opts->{title} || '');
	gtkset($w->ok_button, %{delete $opts->{ok_button}}) if exists $opts->{ok_button};
	gtkset($w->cancel_button, %{delete $opts->{cancel_button}}) if exists $opts->{cancel_button};
    }
    $w;
}

sub _gtk__FileChooserDialog    { &_gtk_any_Window }

sub _gtk__FileChooser {
    my ($w, $opts) = @_;

    #- no nice way to have a {file_ref} on a FileChooser since selection_changed only works for browsing, not file/folder creation

    if (!$w) {
	my $action = delete $opts->{action} || internal_error("missing action for FileChooser");
	$w = Gtk3::FileChooserWidget->new($action);

	my $file = $opts->{file} && delete $opts->{file};

	if (my $dir = delete $opts->{directory} || $file && dirname($file)) {
	    $w->set_current_folder($dir);
	}
	if ($file) {
	    if ($action =~ /save|create/) {
		$w->set_current_name(basename($file));
	    } else {
		$w->set_filename($file);
	    }
	}
    }
    $w;
}

sub _gtk__VPaned { &_gtk_any_Paned }
sub _gtk__HPaned { &_gtk_any_Paned }
sub _gtk_any_Paned {
    my ($w, $opts, $class, $action) = @_;

    if (!$w) {
	$w = "Gtk3::$class"->new;
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
        $w->set_position(delete $opts->{position}) if exists $opts->{position};
    } elsif ($action eq 'gtkset') {
	$_->destroy foreach $w->get_children;
    }

    foreach my $opt (qw(resize1 shrink1 resize2 shrink2)) {
        $opts->{$opt} = 1 if !defined $opts->{$opt};
    }
    $w->pack1(delete $opts->{child1}, delete $opts->{resize1}, delete $opts->{shrink1});
    $w->pack2(delete $opts->{child2}, delete $opts->{resize2}, delete $opts->{shrink2});
    $w;
}

sub _gtk__VBox { &_gtk_any_Box }
sub _gtk__HBox { &_gtk_any_Box }
sub _gtk_any_Box {
    my ($w, $opts, $class, $action) = @_;

    if (!$w) {
	$w = "Gtk3::$class"->new;
	$w->set_homogeneous(delete $opts->{homogenous}) if exists $opts->{homogenous};
	$w->set_spacing(delete $opts->{spacing}) if exists $opts->{spacing};
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
    } elsif ($action eq 'gtkset') {
	$_->destroy foreach $w->get_children;
    }

    _gtknew_handle_children($w, $opts);
    $w;
}

sub _gtk__VButtonBox { &_gtk_any_ButtonBox }
sub _gtk__HButtonBox { &_gtk_any_ButtonBox }
sub _gtk_any_ButtonBox {
    my ($w, $opts, $class, $action) = @_;

    if (!$w) {
	$w = "Gtk3::$class"->new;
	$w->set_homogeneous(delete $opts->{homogenous}) if exists $opts->{homogenous};
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
	$w->set_spacing(delete $opts->{spacing}) if exists $opts->{spacing};
	$w->set_layout(delete $opts->{layout} || 'spread');
    } elsif ($action eq 'gtkset') {
	$_->destroy foreach $w->get_children;
    }

    _gtknew_handle_children($w, $opts);
    $w;
}

sub _gtk__Notebook {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk3::Notebook->new;
	$w->set_property('show-tabs', delete $opts->{show_tabs}) if exists $opts->{show_tabs};
	$w->set_property('show-border', delete $opts->{show_border}) if exists $opts->{show_border};
    }

    if (exists $opts->{children}) {
	foreach (group_by2(@{delete $opts->{children}})) {
	    my ($title, $page) = @$_;
	    $w->append_page($page, $title);
	    $page->show;
	    $title->show;
	}
    }
    $w;
}

sub _gtk__Table {
    my ($w, $opts) = @_;

    if (!$w) {
	add2hash_($opts, { xpadding => 5, ypadding => 0, border_width => $::isInstall ? 3 : 10 });

	$w = Gtk3::Table->new(0, 0, delete $opts->{homogeneous} || 0);
	$w->set_col_spacings(delete $opts->{col_spacings} || 0);
	$w->set_row_spacings(delete $opts->{row_spacings} || 0);
	$w->set_border_width(delete $opts->{border_width});
	$w->{$_} = delete $opts->{$_} foreach 'xpadding', 'ypadding', 'mcc';
    }

    each_index {
	my ($i, $l) = ($::i, $_);
	each_index {
	    my $j = $::i;
	    if ($_) {
		ref $_ or $_ = Gtk3::WrappedLabel->new($_);
                $w->attach($_, $j, $j + 1, $i, $i + 1,
                           $j != $#$l && !$w->{mcc} ?
			     ('fill', 'fill', $w->{xpadding}, $w->{ypadding}) :
                               (['expand', 'fill'], ref($_) eq 'Gtk3::ScrolledWindow' || $_->get_data('must_grow') ?
                                 ['expand', 'fill'] : [], 0, 0));
		$_->show;
	    }
	} @$l;
    } @{delete $opts->{children} || []};

    $w;
}

sub _gtk_any_simple {
    my ($w, $_opts, $class) = @_;

    $w ||= "Gtk3::$class"->new;
}

sub _gtknew_handle_children {
    my ($w, $opts) = @_;

    my @child = exists $opts->{children_tight} ? map { [ 0, $_ ] } @{delete $opts->{children_tight}} :
                exists $opts->{children_loose} ? map { [ 1, $_ ] } @{delete $opts->{children_loose}} :
	        exists $opts->{children} ? group_by2(@{delete $opts->{children}}) : 
		exists $opts->{children_centered} ? 
		  ([ 1, gtknew('VBox') ], (map { [ 0, $_ ] } @{delete $opts->{children_centered}}), [ 1, gtknew('VBox') ]) :
		  ();

    my $padding = delete $opts->{padding};

    foreach (@child) {
	my ($fill, $child) = @$_;
	$fill eq '0' || $fill eq '1' || $fill eq 'fill' || $fill eq 'expand' or internal_error("odd {children} parameter must be 0 or 1 (got $fill)");
	ref $child or $child = Gtk3::WrappedLabel->new($child);
	my $expand = $fill && $fill ne 'fill' ? 1 : 0;
	$w->pack_start($child, $expand, $fill, $padding || 0);
	$child->show;
    }
}

#- this magic function redirects method calls:
#- * default is to redirect them to the {child}
#- * if the {child} doesn't handle the method, we try with the {real_window}
#-   (eg : add_accel_group set_position set_default_size
#- * a few methods are handled specially
my %for_real_window = map { $_ => 1 } qw(show_all size_request);
sub mygtk3::MagicWindow::AUTOLOAD {
    my ($w, @args) = @_;

    my ($meth) = $mygtk3::MagicWindow::AUTOLOAD =~ /mygtk3::MagicWindow::(.*)/;

    my ($s1, @s2) = $meth eq 'show'
              ? ('real_window', 'banner', 'child') :
            $meth eq 'destroy' || $meth eq 'hide' ?
	      ($w->{pop_it} ? 'real_window' : ('child', 'banner')) :
            $meth eq 'get' && $args[0] eq 'window-position' ||
	    $for_real_window{$meth} ||
            !$w->{child}->can($meth)
	      ? 'real_window'
	      : 'child';

#-    warn "mygtk3::MagicWindow::$meth", first($w =~ /HASH(.*)/), " on $s1 @s2 (@args)\n";

    $w->{$_} && $w->{$_}->$meth(@args) foreach @s2;
    $w->{$s1}->$meth(@args);
}

my $enable_quit_popup;
sub enable_quit_popup {
    my ($bool) = @_;
    $enable_quit_popup = $bool;
}

state $in_callback;
sub quit_popup() {
   return if !$enable_quit_popup;
   if (!$in_callback) {
	$in_callback = 1;
	my $_guard = before_leaving { undef $in_callback };
	require ugtk3;
	my $w = ugtk3->new(N("Confirmation"), grab => 1);
	ugtk3::_ask_okcancel($w, N("Are you sure you want to quit?"), N("Quit"), N("Cancel"));
	my $ret = ugtk3::main($w);
	return 1 if !$ret;
    }
}

sub quit_callback { 
    my ($w) = @_;
    
    return 1 if quit_popup();
    if ($::isWizard) {
	$w->destroy; 
	die 'wizcancel';
    } else { 
	if (Gtk3->main_level) {
	    Gtk3->main_quit;
	} else {
	    # block window deletion if not in main loop (eg: while starting the GUI)
	    return 1;
	}
    } 
}

sub _create_Window {
    my ($opts, $special_center) = @_;

    my $no_Window_Manager = exists $opts->{no_Window_Manager} ? delete $opts->{no_Window_Manager} : !$::isStandalone;

    add2hash($opts, {
	if_(!$::isInstall && !$::isWizard, border_width => 5),

	#- policy: during install, we need a special code to handle the weird centering, see below
	position_policy => $special_center ? 'none' : 
	  $no_Window_Manager ? 'center-always' : 'center-on-parent',

	if_($::isInstall, position => [
	    $::stepswidth + ($::o->{windowwidth} - $::real_windowwidth) / 2, 
	    ($::o->{windowheight} - $::real_windowheight) / 2,
	]),
    });
    my $w = _gtk(undef, 'Window', 'gtknew', $opts);

    #- when the window is closed using the window manager "X" button (or alt-f4)
    $w->signal_connect(delete_event => \&quit_callback);

    if ($::isInstall && !$::isStandalone) {
	require install::gtk; #- for perl_checker
	install::gtk::handle_unsafe_mouse($::o, $w);
	$w->signal_connect(key_press_event => \&install::gtk::special_shortcuts);

	#- force center at a weird position, this can't be handled by position_policy
	#- because center-* really are window manager hints for centering, whereas we want
	#- to center the main window in the right part of the screen
	my ($wi, $he);
	$w->signal_connect(size_allocate => sub {
	    my (undef, $event) = @_;
	    my @w_size = $event->values;

	    # ignore bogus sizing events:
	    return if $w_size[2] < 5;
	    return if $w_size[2] == $wi && $w_size[3] == $he; #BUG
	    (undef, undef, $wi, $he) = @w_size;

            $w->move(max(0, $::rootwidth - ($::o->{windowwidth} + $wi) / 2), 
		     max(0, ($::o->{windowheight} - $he) / 2));
	}) if $special_center;
    }

    $w->present if $no_Window_Manager;

    $w;
}

sub _find_imgfile {
    my ($name) = @_;

    if ($name =~ m|/| && -f $name) {
	$name;
    } else {
	foreach my $path (_icon_paths()) {
	    foreach ('', '.png', '.xpm', '.jpg') {
		my $file = "$path/$name$_";
		-f $file and return $file;
	    }
	}
    }
}

# _text_insert() can be used with any of choose one of theses styles:
# - no tags:
#   _text_insert($textview, "My text..");
# - anonymous tags:
#   _text_insert($textview, [ [ 'first text',  { 'foreground' => 'blue', 'background' => 'green', ... } ],
#			        [ 'second text' ],
#		                [ 'third', { 'font' => 'Serif 15', ... } ],
#                               ... ]);
# - named tags:
#   $textview->{tags} = {
#                        'blue_green' => { 'foreground' => 'blue', 'background' => 'green', ... },
#                        'big_font' => { 'font' => 'Serif 35', ... },
#                       }
#   _text_insert($textview, [ [ 'first text',  'blue_green' ],
#		                [ 'second', 'big_font' ],
#                               ... ]);
# - mixed anonymous and named tags:
#   $textview->{tags} = {
#                        'blue_green' => { 'foreground' => 'blue', 'background' => 'green', ... },
#                        'big_font' => { 'font' => 'Serif 35', ... },
#                       }
#   _text_insert($textview, [ [ 'first text',  'blue_green' ],
#			        [ 'second text' ],
#		                [ 'third', 'big_font' ],
#		                [ 'fourth', { 'font' => 'Serif 15', ... } ],
#                               ... ]);
sub _text_insert {
    my ($textview, $t, %opts) = @_;
    my $buffer = $textview->get_buffer;
    $buffer->{tags} ||= {};
    $buffer->{gtk_tags} ||= {};
    my $gtk_tags = $buffer->{gtk_tags};
    my $tags = $buffer->{tags};
    if (ref($t) eq 'ARRAY') {
        if (!$opts{append}) {
            $buffer->set_text('');
            $textview->{anchors} = [];
        }
        foreach my $token (@$t) {
            my ($item, $tag) = @$token;
            my $iter1 = $buffer->get_end_iter;
            if (ref($item) =~ /^Gtk3::Gdk::Pixbuf/) {
                $buffer->insert_pixbuf($iter1, $item);
                next;
            }
            if (ref($item) =~ /^Gtk3::/) {
                my $anchor = $buffer->create_child_anchor($iter1);
                $textview->add_child_at_anchor($item, $anchor);
                $textview->{anchors} ||= [];
                push @{$textview->{anchors}}, $anchor;
                next;
            }
            if ($tag) {
                if (ref($tag)) {
                    # use anonymous tags
                    $buffer->insert_with_tags($iter1, $item, $buffer->create_tag(undef, %$tag));
                } else {
                    # fast text insertion:
                    # since in some contexts (eg: localedrake, rpmdrake), we use quite a lot of identical tags,
                    # it's much more efficient and less memory pressure to use named tags
                    $gtk_tags->{$tag} ||= $buffer->create_tag($tag, %{$tags->{$token->[1]}});
                    $buffer->insert_with_tags($iter1, $item, $gtk_tags->{$tag});
                }
            } else {
                $buffer->insert($iter1, $item);
            }
        }
    } else {
        if ($opts{append}) {
            $buffer->insert($buffer->get_end_iter, $t);
        } else {
            $textview->{anchors} = [];
            $buffer->set_text($t);
        }
    }
    $textview->{to_bottom}->() if $textview->{to_bottom};

    #- the following line is needed to move the cursor to the beginning, so that if the
    #- textview has a scrollbar, it will not scroll to the bottom when focusing (#3633)
    $buffer->place_cursor($buffer->get_start_iter);
    $textview->set_wrap_mode($opts{wrap_mode} || 'word');
    $textview->set_editable($opts{editable} || 0);
    $textview->set_cursor_visible($opts{visible} || 0);
    $textview;
}

sub _allow_scroll_TextView_to_bottom {
    my ($scrolledWindow, $textView) = @_;

    $textView->get_buffer->create_mark('end', $textView->get_buffer->get_end_iter, 0);
    sub {
	my ($o_force) = @_;
	my $adjustment = $scrolledWindow->get_vadjustment;
	if ($o_force || $adjustment->page_size + $adjustment->value == $adjustment->upper) {
	    flush(); #- one must flush before scrolling to end, otherwise the text just added *may* not be taken into account correctly, and so it doesn't really scroll to end
	    $textView->scroll_to_mark($textView->get_buffer->get_mark('end'), 0, 1, 0, 1);
	}
    };
}

sub asteriskize {
    my ($label) = @_;
    "\x{2022} " . $label;
}

sub get_main_window_size() {
    $::real_windowwidth ? ($::real_windowwidth, $::real_windowheight) : $::isWizard ? (540, 360) : (600, 400);
}

# in order to workaround infamous 6 years old gnome bug #101968:
sub get_label_width() {
    first(mygtk3::get_main_window_size()) - 55 - $left_padding;
}

sub set_main_window_size {
    my ($window) = @_;
    my ($width, $height) = get_main_window_size();
    $window->set_size_request($width, $height);
}

my @icon_paths;
sub add_icon_path { push @icon_paths, @_ }
sub _icon_paths() {
    my $loc = (($ENV{'LC_MESSAGES'} =~ m/ru_RU/) ? 'ru' : 'en');
    (@icon_paths, (exists $ENV{SHARE_PATH} ? ($ENV{SHARE_PATH}, "$ENV{SHARE_PATH}/icons", "$ENV{SHARE_PATH}/libDrakX/pixmaps/$loc", "$ENV{SHARE_PATH}/libDrakX/pixmaps") : ()),
    "/usr/lib/libDrakX/icons", "pixmaps/$loc", "pixmaps", 'data/icons', 'data/pixmaps', 'standalone/icons', '/usr/share/rpmdrake/icons');
}  

sub main {
    my ($window, $o_verif) = @_;
    my $destroyed;
    $window->signal_connect(destroy => sub { $destroyed = 1 });
    $window->show;
    do { Gtk3->main } while (!$destroyed && $o_verif && !$o_verif->());
    may_destroy($window);
    flush();
}

sub sync {
    my ($window) = @_;
    $window->show;
    flush();
}

sub flush() { 
    Gtk3::main_iteration() while Gtk3::events_pending();
}

sub enable_sync_flush {
    my ($w) = @_;
    $w->signal_connect(draw => sub { $w->{displayed} = 1; 0 });
}

sub sync_flush {
    my ($w) = @_;
    # hackish :-(
    mygtk3::sync($w) while !$w->{displayed};
}


sub register_main_window {
    my ($w) = @_;
    push @::main_windows, $::main_window = $w;
}

sub may_destroy {
    my ($w) = @_;
    return if !$w;
    @::main_windows = difference2(\@::main_windows, [ $w->{real_window} ]);
    if ($::main_window eq $w->{real_window}) {
        undef $::main_window;
        $::main_window = $::main_windows[-1];
    }
    $w->destroy;
}

sub root_window() {
    state $root;
    $root ||= Gtk3::Gdk::get_default_root_window();
}

sub root_window_size() {
    state $root;
    $root ||= [Gtk3::Gdk::Screen::width, Gtk3::Gdk::Screen::height];
    @$root;
}

sub rgb2color {
    my ($r, $g, $b) = @_;
    my $color = Gtk3::Gdk::Color->new($r, $g, $b);
    root_window()->get_colormap->rgb_find_color($color);
    $color;
}

sub set_root_window_background {
    my ($r, $g, $b) = @_;
    my $root = root_window();
    my $gc = Gtk3::Gdk::GC->new($root);
    my $color = rgb2color($r, $g, $b);
    $gc->set_rgb_fg_color($color);
    set_root_window_background_with_gc($gc);
}

sub set_root_window_background_with_gc {
    my ($gc) = @_;
    my $root = root_window();
    my ($w, $h) = $root->get_size;
    $root->set_background($gc->get_values->{foreground});
    $root->draw_rectangle($gc, 1, 0, 0, $w, $h);
}

sub _new_alpha_pixbuf {
    my ($pixbuf) = @_;
    my ($height, $width) = ($pixbuf->get_height, $pixbuf->get_width);
    my $new_pixbuf = Gtk3::Gdk::Pixbuf->new('rgb', 1, 8, $width, $height);
    $new_pixbuf->fill(0x00000000); # transparent white
    $width, $height, $new_pixbuf;
}

sub _pixbuf_render_alpha {
    my ($pixbuf, $alpha_threshold) = @_;
    my ($width, $height, $new_pixbuf) = _new_alpha_pixbuf($pixbuf);
    $pixbuf->composite($new_pixbuf, 0, 0, $width, $height, 0, 0, 1, 1, 'bilinear', $alpha_threshold);
    $new_pixbuf;
}

sub pixmap_from_pixbuf {
    my ($widget, $pixbuf) = @_;
    my $window = $widget->get_window or internal_error("you can't use this function if the widget is not realised");
    my ($width, $height) = ($pixbuf->get_width, $pixbuf->get_height);
    my $pixmap = Gtk3::Gdk::Pixmap->new($window, $width, $height, $window->get_depth);
    $pixbuf->render_to_drawable($pixmap, $widget->style->fg_gc('normal'), 0, 0, 0, 0, $width, $height, 'max', 0, 0);
    $pixmap;
}

sub import_style_ressources() {
    if (!$::isInstall) {
        my $pl = Gtk3::CssProvider->new;
        $pl->load_from_path('/usr/share/libDrakX/themes-galaxy.css'); # FIXME DEBUG
        my $cx = Gtk3::StyleContext::add_provider_for_screen(Gtk3::Gdk::Screen::get_default(), $pl, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}

sub text_direction_rtl() {
    Gtk3::Widget::get_default_direction eq 'rtl';
}

sub _get_weakness_icon {
    my ($password_weakness) = @_;
    my %weakness_icon = (
        1 => gtknew('Pixbuf', file => 'security-low'),
        2 => gtknew('Pixbuf', file => 'security-low'),
        3 => gtknew('Pixbuf', file => 'security-medium'),
        4 => gtknew('Pixbuf', file => 'security-strong'),
        5 => gtknew('Pixbuf', file => 'security-strong'));
    my $weakness_icon = $weakness_icon{$password_weakness} || return undef;
    $weakness_icon;
}

sub _get_weakness_tooltip {
    my ($password_weakness) = @_;
    my %weakness_tooltip = (
        1 => N("Password is trivial to guess"),
        2 => N("Password is trivial to guess"),
        3 => N("Password should be resistant to basic attacks"),
        4 => N("Password seems secure"),
        5 => N("Password seems secure"));
    my $weakness_tooltip = $weakness_tooltip{$password_weakness} || return undef;
    return $weakness_tooltip;
}

package Gtk3::MDV_Notebook; # helper functions for installer & mcc
our @ISA = qw(Gtk3::Widget);

sub hide_selection {
    my ($w) = @_;
    $_->hide foreach $w->{selection_bar}, $w->{selection_arrow};
}

sub move_selection {
    my ($w, $label) = @_;
    my $layout = $w->{layout};
    $layout->{arrow_ydiff} ||=
      ($w->{selection_arrow}->get_pixbuf->get_height - $w->{selection_bar}->get_pixbuf->get_height)/2;
    my $bar_y = $label->get_allocation->y - ($w->{selection_bar}->get_pixbuf->get_height - $label->allocation->height)/2;
    $layout->move($w->{selection_bar}, 0, $bar_y);
    $layout->move($w->{selection_arrow}, $w->{arrow_x}, $bar_y - $layout->{arrow_ydiff}); # arrow is higer
    $_->show foreach $w->{selection_bar}, $w->{selection_arrow};
}

1;
