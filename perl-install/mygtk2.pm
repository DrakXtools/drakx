package mygtk2;

use diagnostics;
use strict;
use lang;

our @ISA = qw(Exporter);
our @EXPORT = qw(gtknew gtkset gtkadd gtkval_register gtkval_modify);

use c;
use log;
use common;

use Gtk2;
use Gtk2::Gdk::Keysyms;

unless ($::no_ugtk_init) {
    !check_for_xserver() and print("Cannot be run in console mode.\n"), c::_exit(0);
    $::one_message_has_been_translated and warn("N() was called from $::one_message_has_been_translated BEFORE gtk2 initialisation, replace it with a N_() AND a translate() later.\n"), c::_exit(1);

    Gtk2->init;
    c::bind_textdomain_codeset($_, 'UTF8') foreach 'libDrakX', @::textdomains;
    $::need_utf8_i18n = 1;
}
Gtk2->croak_execeptions if (!$::no_ugtk_init || $::isInstall) && 0.95 < $Gtk2::VERSION;



sub gtknew {
    my $class = shift;
    if (@_ % 2 != 0) {
	internal_error("gtknew $class: bad options @_");
    }
    if (my $r = find { ref $_->[0] } group_by2(@_)) {
	internal_error("gtknew $class: $r should be a string in @_");
    }
    _gtk(undef, $class, 'gtknew', @_);
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
    $class =~ s/^Gtk2::(Gdk::)?// or internal_error("gtkset unknown class $class");
    
    _gtk($w, $class, 'gtkset', @_);
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
    $class =~ s/^Gtk2::(Gdk::)?// or internal_error("gtkadd unknown class $class");
    
    _gtk('gtkadd', $w, $class, @_);
}


my %refs;

sub gtkval_register {
    my ($w, $ref, $sub) = @_;
    $w->{_ref} = $ref;
    $w->signal_connect(destroy => sub { 
	delete $refs{$ref}{$w};
	delete $refs{$ref} if !%{$refs{$ref}};
    });
    push @{$refs{$ref}{$w}}, [ $sub, $w ];
}
sub gtkval_modify {
    my ($ref, $val, @to_skip) = @_;
    $$ref = $val;
    foreach (map { @$_ } values %{$refs{$ref} || {}}) {	
	my ($f, @para) = @$_;
	$f->(@para) if !member($f, @to_skip);
    }
}

my $global_tooltips;

sub _gtk {
    my ($w, $class, $action, %opts) = @_;

    if (my $f = $mygtk2::{"_gtk__$class"}) {
	$w = $f->($w, \%opts, $class, $action);
    } else {
	internal_error("$action $class: unknown class");
    }

    $w->set_size_request(delete $opts{width} || -1, delete $opts{height} || -1) if exists $opts{width} || exists $opts{height};
    if (my $position = delete $opts{position}) {
	$w->set_uposition($position->[0], $position->[1]);
    }
    $w->set_name(delete $opts{widget_name}) if exists $opts{widget_name};
    $w->can_focus(delete $opts{can_focus}) if exists $opts{can_focus};
    $w->can_default(delete $opts{can_default}) if exists $opts{can_default};
    $w->grab_focus if delete $opts{grab_focus};
    (delete $opts{size_group})->add_widget($w) if $opts{size_group};
    if (my $tip = delete $opts{tip}) {
	$global_tooltips ||= Gtk2::Tooltips->new;
	$global_tooltips->set_tip($w, $tip);
    }

    if (%opts && !$opts{allow_unknown_options}) {
	internal_error("$action $class: unknown option(s) " . join(', ', keys %opts));
    }
    $w;
}


sub _gtk__Button       { &_gtk_any_Button }
sub _gtk__ToggleButton { &_gtk_any_Button }
sub _gtk__CheckButton  { &_gtk_any_Button }
sub _gtk_any_Button {
    my ($w, $opts, $class) = @_;

    if (!$opts->{image}) {
	add2hash_($opts, { mnemonic => 1 });
    }

    if (!$w) {
	$w = $opts->{image} ? "Gtk2::$class"->new :
	  delete $opts->{mnemonic} ? "Gtk2::$class"->new_with_mnemonic(delete $opts->{text} || '') :
	    "Gtk2::$class"->new_with_label(delete $opts->{text} || '');

	$w->{format} = delete $opts->{format} if exists $opts->{format};
    }

    if (my $image = delete $opts->{image}) {
	$w->add($image);
	$image->show;
    }
    $w->set_sensitive(delete $opts->{sensitive}) if exists $opts->{sensitive};
    $w->set_relief(delete $opts->{relief}) if exists $opts->{relief};

    if (my $text_ref = delete $opts->{text_ref}) {
	my $set = sub {
	    eval { $w->set_label(may_apply($w->{format}, $$text_ref)) };
	};
	gtkval_register($w, $text_ref, $set);
	$set->();
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

	$w = $opts->{image} || !exists $opts->{text} ? "Gtk2::$class"->new :
	  delete $opts->{mnemonic} ? "Gtk2::$class"->new_with_label(delete $opts->{text}) :
	    "Gtk2::$class"->new_with_mnemonic(delete $opts->{text});
    }

    $w->set_active(delete $opts->{active}) if exists $opts->{active};
    $w->signal_connect(toggled => delete $opts->{toggled}) if exists $opts->{toggled};
    $w;
}

sub _gtk___SpinButton {
    my ($w, $opts) = @_;

    if (!$w) {
	$opts->{adjustment} ||= do {
	    add2hash_($opts, { step_increment => 1, page_increment => 5, page_size => 1, value => delete $opts->{lower} });
	    Gtk2::Adjustment->new(delete $opts->{value}, delete $opts->{lower}, delete $opts->{upper}, delete $opts->{step_increment}, delete $opts->{page_increment}, delete $opts->{page_size});
	};
	$w = Gtk2::SpinButton->new(delete $opts->{adjustment}, delete $opts->{climb_rate} || 0, delete $opts->{digits} || 0);
    }

    $w->signal_connect(value_changed => delete $opts->{value_changed}) if exists $opts->{value_changed};
    $w;
}

sub _gtk__HScale {
    my ($w, $opts) = @_;

    if (!$w) {
	$opts->{adjustment} ||= do {
	    add2hash_($opts, { step_increment => 1, page_increment => 5, page_size => 1, value => delete $opts->{lower} });
	    Gtk2::Adjustment->new(delete $opts->{value}, delete $opts->{lower}, (delete $opts->{upper}) + 1, delete $opts->{step_increment}, delete $opts->{page_increment}, delete $opts->{page_size});
	};
	$w = Gtk2::HScale->new(delete $opts->{adjustment});
    }

    $w->signal_connect(value_changed => delete $opts->{value_changed}) if exists $opts->{value_changed};
    $w;
}

sub _gtk__VSeparator { &_gtk_any_simple }
sub _gtk__HSeparator { &_gtk_any_simple }
sub _gtk__Calendar   { &_gtk_any_simple }

sub _gtk__DrawingArea {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk2::DrawingArea->new;
    }
    $w->signal_connect(expose_event => delete $opts->{expose_event}) if exists $opts->{expose_event};
    $w;
}

sub _gtk__Pixbuf {
    my ($w, $opts) = @_;

    if (!$w) {
	my $name = delete $opts->{file} or internal_error("missing file");
	my $file = _find_imgfile($name) or internal_error("can not find $name");
	$w = Gtk2::Gdk::Pixbuf->new_from_file($file);
    }
    $w;
}

sub _gtk__Image {
    my ($w, $opts, $class) = @_;

    if (!$w) {
	$w = "Gtk2::$class"->new;
	$w->{format} = delete $opts->{format} if exists $opts->{format};
    }

    if (my $name = delete $opts->{file}) {
	my $file = _find_imgfile(may_apply($w->{format}, $name)) or internal_error("can not find $name");
	$w->set_from_file($file);
    } elsif (my $file_ref = delete $opts->{file_ref}) {
	my $set = sub {
	    my $file = _find_imgfile(may_apply($w->{format}, $$file_ref)) or internal_error("can not find $$file_ref");
	    $w->set_from_file($file);
	};
	gtkval_register($w, $file_ref, $set);
	$set->();
    }
    $w;
}

sub _gtk__WrappedLabel {
    my ($w, $opts) = @_;
    
    $opts->{line_wrap} = 1;
    _gtk__Label($w, $opts);
}

sub _gtk__Label {
    my ($w, $opts) = @_;

    if ($w) {
	$w->set_text(delete $opts->{text}) if exists $opts->{text};
    } else {
	$w = exists $opts->{text} ? Gtk2::Label->new(delete $opts->{text}) : Gtk2::Label->new;
	$w->set_justify(delete $opts->{justify}) if exists $opts->{justify};
	$w->set_line_wrap(delete $opts->{line_wrap}) if exists $opts->{line_wrap};
	$w->set_alignment(@{delete $opts->{alignment}}) if exists $opts->{alignment};
	$w->modify_font(Gtk2::Pango::FontDescription->from_string(delete $opts->{font})) if exists $opts->{font};
    }

    $w->set_markup(delete $opts->{text_markup}) if exists $opts->{text_markup};
    $w;
}

sub _gtk__Entry {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk2::Entry->new;
	$w->set_editable(delete $opts->{editable}) if exists $opts->{editable};
    }

    $w->set_text(delete $opts->{text}) if exists $opts->{text};
    $w->signal_connect(key_press_event => delete $opts->{key_press_event}) if exists $opts->{key_press_event};
    $w;
}

sub _gtk__TextView {
    my ($w, $opts) = @_;
	
    if (!$w) {
	$w = Gtk2::TextView->new;
	$w->set_editable(delete $opts->{editable}) if exists $opts->{editable};
	$w->set_wrap_mode(delete $opts->{wrap_mode}) if exists $opts->{wrap_mode};
	$w->set_cursor_visible(delete $opts->{cursor_visible}) if exists $opts->{cursor_visible};
    }

    _text_insert($w, delete $opts->{text}) if exists $opts->{text};
    $w;
}

sub _gtk__ComboBox {
    my ($w, $opts, $_class, $action) = @_;

    if (!$w) {
	$w = Gtk2::ComboBox->new_text;
	$w->{format} = delete $opts->{format} if exists $opts->{format};

    }
    if (exists $opts->{list}) {
	$w->{list} = delete $opts->{list};
	$w->{formatted_list} = $w->{format} ? [ map { $w->{format}($_) } @{$w->{list}} ] : $w->{list};
	$w->append_text($_) foreach @{$w->{formatted_list}};
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
	$w = Gtk2::ScrolledWindow->new(undef, undef);
	$w->set_policy(delete $opts->{h_policy} || 'automatic', delete $opts->{v_policy} || 'automatic');
    }

    if (my $child = delete $opts->{child}) {
	if (member(ref($child), qw(Gtk2::Layout Gtk2::Text Gtk2::TextView Gtk2::TreeView))) {
	    $w->add($child);
	} else {
	    $w->add_with_viewport($child);
	}
	$child->set_focus_vadjustment($w->get_vadjustment) if $child->can('set_focus_vadjustment');
	$child->set_left_margin(6) if ref($child) =~ /Gtk2::TextView/;
	$child->show;

	$w->child->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};

	if ($action eq 'gtknew' && ref($child) =~ /Gtk2::TextView|Gtk2::TreeView/) {
	    $w = gtknew('Frame', shadow_type => 'in', child => $w);
	}
    }
    $w;
}

sub _gtk__Frame {
    my ($w, $opts) = @_;

    if ($w) {
	$w->set_label(delete $opts->{text}) if exists $opts->{text};
    } else {
	$w = Gtk2::Frame->new(delete $opts->{text});
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
	$w->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};
    }

    if (my $child = delete $opts->{child}) {
	$w->add($child);
	$child->show;
    }
    $w;
}

sub _gtk__Window { &_gtk_any_Window }
sub _gtk__Dialog { &_gtk_any_Window }
sub _gtk_any_Window {
    my ($w, $opts, $class) = @_;

    if (!$w) {
	if ($class eq 'Window') {
	    $w = "Gtk2::$class"->new(delete $opts->{type} || 'toplevel');
	} else {
	    $w = "Gtk2::$class"->new;
	}

	$w->set_modal(delete $opts->{modal}) if exists $opts->{modal};
	$w->set_transient_for(delete $opts->{transient_for}) if exists $opts->{transient_for};
	$w->set_border_width(delete $opts->{border_width}) if exists $opts->{border_width};
	$w->set_shadow_type(delete $opts->{shadow_type}) if exists $opts->{shadow_type};
	$w->set_position(delete $opts->{position_policy}) if exists $opts->{position_policy};
    }
    $w->set_title(delete $opts->{title}) if exists $opts->{title};

    if (my $child = delete $opts->{child}) {
	$w->add($child);
	$child->show;
    }
    $w;
}

sub _gtk__FileSelection {
    my ($w, $opts) = @_;

    if (!$w) {
	$w = Gtk2::FileSelection->new(delete $opts->{title} || '');
	gtkset($w->ok_button, %{delete $opts->{ok_button}}) if exists $opts->{ok_button};
	gtkset($w->cancel_button, %{delete $opts->{cancel_button}}) if exists $opts->{cancel_button};
    }
    $w;
}

sub _gtk__VBox { &_gtk_any_Box }
sub _gtk__HBox { &_gtk_any_Box }
sub _gtk_any_Box {
    my ($w, $opts, $class, $action) = @_;

    if (!$w) {
	$w = "Gtk2::$class"->new(0,0);
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
	$w = "Gtk2::$class"->new;
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
	$w = Gtk2::Notebook->new;
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

	$w = Gtk2::Table->new(0, 0, delete $opts->{homogeneous} || 0);
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
		ref $_ or $_ = Gtk2::WrappedLabel->new($_);
		$j != $#$l && !$w->{mcc} ?
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     'fill', 'fill', $w->{xpadding}, $w->{ypadding}) :
			       $w->attach($_, $j, $j + 1, $i, $i + 1,
					  ['expand', 'fill'], ref($_) eq 'Gtk2::ScrolledWindow' || $_->get_data('must_grow') ? ['expand', 'fill'] : [], 0, 0);
		$_->show;
	    }
	} @$l;
    } @{delete $opts->{children} || []};

    $w;
}

sub _gtk_any_simple {
    my ($w, $_opts, $class) = @_;

    $w ||= "Gtk2::$class"->new;
}

sub _gtknew_handle_children {
    my ($w, $opts) = @_;

    my @child = exists $opts->{children_tight} ? map { [ 0, $_ ] } @{delete $opts->{children_tight}} :
                exists $opts->{children_loose} ? map { [ 1, $_ ] } @{delete $opts->{children_loose}} :
	        exists $opts->{children} ? group_by2(@{delete $opts->{children}}) : ();

    my $padding = delete $opts->{padding};

    foreach (@child) {
	my ($fill, $child) = @$_;
	$fill eq '0' || $fill eq '1' or internal_error("odd {children} parameter must be 0 or 1 (got $fill)");
	ref $child or $child = Gtk2::WrappedLabel->new($child);
	$w->pack_start($child, $fill, $fill, $padding || 0);
	$child->show;
    }
}

sub _find_imgfile {
    my ($name) = @_;

    if ($name =~ m|/| && -f $name) {
	$name;
    } else {
	foreach my $path (_icon_paths()) {
	    foreach ('', '.png', '.xpm') {
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
        $opts{append} or $buffer->set_text('');
        foreach my $token (@$t) {
            my ($item, $tag) = @$token;
            my $iter1 = $buffer->get_end_iter;
            if ($item =~ /^Gtk2::Gdk::Pixbuf/) {
                $buffer->insert_pixbuf($iter1, $item);
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
        $buffer->set_text($t);
    }
    #- the following line is needed to move the cursor to the beginning, so that if the
    #- textview has a scrollbar, it will not scroll to the bottom when focusing (#3633)
    $buffer->place_cursor($buffer->get_start_iter);
    $textview->set_wrap_mode($opts{wrap_mode} || 'word');
    $textview->set_editable($opts{editable} || 0);
    $textview->set_cursor_visible($opts{visible} || 0);
    $textview;
}


my @icon_paths;
sub add_icon_path { push @icon_paths, @_ }
sub _icon_paths() {
   (@icon_paths, (exists $ENV{SHARE_PATH} ? ($ENV{SHARE_PATH}, "$ENV{SHARE_PATH}/icons", "$ENV{SHARE_PATH}/libDrakX/pixmaps") : ()),
    "/usr/lib/libDrakX/icons", "pixmaps", 'standalone/icons', '/usr/share/rpmdrake/icons');
}  

sub sync {
    my ($window) = @_;
    $window->show;
    flush();
}

sub flush() { 
    Gtk2->main_iteration while Gtk2->events_pending;
}

sub may_destroy {
    my ($w) = @_;
    $w->destroy if $w;
}

sub root_window() {
    my $root if 0;
    $root ||= Gtk2::Gdk->get_default_root_window;
}

sub rgb2color {
    my ($r, $g, $b) = @_;
    my $color = Gtk2::Gdk::Color->new($r, $g, $b);
    root_window()->get_colormap->rgb_find_color($color);
    $color;
}

sub set_root_window_background {
    my ($r, $g, $b) = @_;
    my $root = root_window();
    my $gc = Gtk2::Gdk::GC->new($root);
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

1;
