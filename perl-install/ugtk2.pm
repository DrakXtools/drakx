package ugtk2;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @icon_paths $force_center $force_focus $force_position $grab $pop_it $shape_width $border); #- leave it on one line, for automatic removal of the line at package creation

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    wrappers => [ qw(gtksignal_connect gtkradio gtkpack gtkpack_ gtkpack__ gtkpack2 gtkpack2_
      gtkpack2__ gtkpowerpack gtkcombo_setpopdown_strings gtkset_editable gtkset_selectable gtkentry 
      gtkset_text gtkset_tip gtkappenditems gtkappend  gtkset_shadow_type gtkset_layout gtkset_relief
      gtkadd gtkexpand gtkput gtktext_append gtktext_insert gtkset_size_request gtksize gtkset_justify gtkset_active
      gtkset_sensitive gtkset_visibility gtkset_modal gtkset_border_width gtkmove gtkresize gtkshow
      gtkhide gtkdestroy gtkflush gtkset_mousecursor gtkset_mousecursor_normal gtkset_markup gtkmodify_font gtkset_property
      gtkset_mousecursor_wait gtkappend_text gtkprepend_text gtkinsert_text gtkroot gtksetstyle gtkappend_page) ],
    helpers => [ qw(add2notebook add_icon_path n_line_size fill_tiled fill_tiled_coords string_size
      get_text_coord gtkcolor gtkset_background gtkfontinfo gtkcreate_img gtkcreate_pixbuf set_back_pixbuf) ],
    create => [ qw(create_box_with_title create_adjustment create_scrolled_window create_hbox create_vbox
      create_dialog destroy_window create_factory_menu create_menu create_notebook create_packtable
      create_vpaned create_hpaned create_okcancel) ],
    ask => [ qw(ask_warn ask_okcancel ask_yesorno ask_from_entry ask_browse_tree_info 
      ask_browse_tree_info_given_widgets ask_dir) ],
);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use c;
use log;
use common;

use Gtk2;

unless ($::no_ugtk_init) {
    !$ENV{DISPLAY} || system('/usr/X11R6/bin/xtest') and die "Cannot be run in console mode.\n";
    Gtk2->init(\@ARGV);
}

$border = 5;


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 wrappers
#
# Functional-style wrappers to existing Gtk functions; allows to program in
# a more functional way, and especially, first, to avoid using temp
# variables, and second, to "see" directly in the code the user interface
# you're building.

sub gtkdestroy                { $_[0] and $_[0]->destroy }
sub gtkflush                  { Gtk2->update_ui }
sub gtkhide                   { $_[0]->hide; $_[0] }
sub gtkmove                   { $_[0]->window->move($_[1], $_[2]); $_[0] }
sub gtkpack                   { gtkpowerpack(1, 1, @_) }
sub gtkpack_                  { gtkpowerpack('arg', 1, @_) }
sub gtkpack__                 { gtkpowerpack(0, 1, @_) }
sub gtkpack2                  { gtkpowerpack(1, 0, @_) }
sub gtkpack2_                 { gtkpowerpack('arg', 0, @_) }
sub gtkpack2__                { gtkpowerpack(0, 0, @_) }
sub gtkput                    { $_[0]->put(gtkshow($_[1]), $_[2], $_[3]); $_[0] }
sub gtkresize                 { $_[0]->window->resize($_[1], $_[2]); $_[0] }
sub gtkset_active             { $_[0]->set_active($_[1]); $_[0] }
sub gtkset_border_width       { $_[0]->set_border_width($_[1]); $_[0] }
sub gtkset_editable           { $_[0]->set_editable($_[1]); $_[0] }
sub gtkset_selectable         { $_[0]->set_selectable($_[1]); $_[0] }
sub gtkset_justify            { $_[0]->set_justify($_[1]); $_[0] }
sub gtkset_layout             { $_[0]->set_layout($_[1]); $_[0] }
sub gtkset_modal              { $_[0]->set_modal($_[1]); $_[0] }
sub gtkset_mousecursor_normal { gtkset_mousecursor('left-ptr', @_) }
sub gtkset_mousecursor_wait   { gtkset_mousecursor('watch', @_) }
sub gtkset_relief             { $_[0]->set_relief($_[1]); $_[0] }
sub gtkset_sensitive          { $_[0]->set_sensitive($_[1]); $_[0] }
sub gtkset_visibility         { $_[0]->set_visibility($_[1]); $_[0] }
sub gtkset_tip                { $_[0]->set_tip($_[1], $_[2]) if $_[2]; $_[1] }
sub gtkset_shadow_type        { $_[0]->set_shadow_type($_[1]); $_[0] }
sub gtkset_style              { $_[0]->set_style($_[1]); $_[0] }
sub gtkset_size_request       { $_[0]->set_size_request($_[1], $_[2]); $_[0] }
sub gtkshow                   { $_[0]->show; $_[0] }
sub gtksize                   { $_[0]->size($_[1], $_[2]); $_[0] }
sub gtkexpand                 { $_[0]->expand; $_[0] }
sub gtkset_markup             { $_[0]->set_markup($_[1]); $_[0] }

sub gtkadd {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = Gtk2::Label->new($l);
	$w->add(gtkshow($l));
    }
    $w
}

sub gtkappend {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = Gtk2::Label->new($l);
	$w->append(gtkshow($l));
    }
    $w
}

sub gtkappenditems {
    my $w = shift;
    $_->show foreach @_;
    $w->append_items(@_);
    $w
}

# append page to a notebook
sub gtkappend_page {
    my $w = shift;
    $w->append_page(@_);
    $w
}

sub gtkbuttonset {
    gtkdestroy($_[0]->child);
    gtkadd($_[0], gtkshow($_[1]))
}

sub gtkentry {
    my ($text) = @_;
    my $e = Gtk2::Entry->new;
    $text and $e->set_text($text);
    $e;
}

sub gtksetstyle { 
    my ($w, $s) = @_;
    $w->set_style($s);
    $w;
}

sub gtkradio {
    my $def = shift;
    my $radio;
    map { gtkset_active($radio = Gtk2::RadioButton->new($radio ? $radio->get_group : undef, $_), $_ eq $def) } @_;
}

sub gtkroot {
    my $root if 0;
    $root ||= Gtk2::Gdk::Window->foreign_new(Gtk2::Gdk->ROOT_WINDOW);
}

sub gtkset_text {
    my ($w, $s) = @_;
    $w->set_text($s);
    $w;
}

sub gtkcombo_setpopdown_strings {
    my $w = shift;
    $w->set_popdown_strings(@_);
    $w;
}

sub gtkinsert_text {
    my ($w, $text, $position) = @_;
    $w->insert_text($text, -1, $position);
    $w;
}

# compat with ugtk for gtk-1.2, don't use it
sub gtkappend_text {
    my ($w, $s) = @_;
    gtkinsert_text($w, $s, -1);
}

# compat with ugtk for gtk-1.2, don't use it
sub gtkprepend_text {
    my ($w, $s) = @_;
    gtkinsert_text($w, $s, 0);
}

sub gtkset_mousecursor {
    my ($type, $w) = @_;
    ($w || gtkroot())->set_cursor(my $c = Gtk2::Gdk::Cursor->new($type));
    $c->unref;
}

sub gtksignal_connect {
    my $w = shift;
    $w->signal_connect(@_);
    $w;
}

sub gtkpowerpack {
    #- Get Default Attributes (if any). 2 syntaxes allowed :
    #- gtkpowerpack( {expand => 1, fill => 0}, $box...) : the attributes are picked from a specified hash ref
    #- gtkpowerpack(1, 0, 1, $box, ...) : the attributes are picked from the non-ref list, in the order (expand, fill, padding, pack_end).
    my @attributes_list = qw(expand fill padding pack_end);
    my $default_attrs = {};
    if (ref($_[0]) eq 'HASH') {
	$default_attrs = shift;
    } elsif (!ref($_[0])) {
	foreach (@attributes_list) {
	    ref($_[0]) and last;
	    $default_attrs->{$_} = shift;
	}
    }
    my $box = shift;

    while (@_) {
	#- Get attributes (if specified). 4 syntaxes allowed (default values are undef ie. false...) :
	#- gtkpowerpack({defaultattrs}, $box, $widget1, $widget2, ...) : the attrs are picked from the default ones (if they exist)
	#- gtkpowerpack($box, {fill=>1, expand=>0, ...}, $widget1, ...) : the attributes are picked from a specified hash ref
	#- gtkpowerpack($box, [1,0,1], $widget1, ...) : the attributes are picked from the array ref : (expand, fill, padding, pack_end).
	#- gtkpowerpack({attr=>'arg'}, $box, 1, $widget1, 0, $widget2, etc...) : the 'arg' value will tell gtkpowerpack to always read the 
	#- attr value directly in the arg list (avoiding confusion between value 0 and Gtk::Label("0"). That can simplify some writings but
	#- this arg(s) MUST then be present...
	my (%attr, $attrs);
	ref($_[0]) eq 'HASH' || ref($_[0]) eq 'ARRAY' and $attrs = shift;
	foreach (@attributes_list) {
	    if (($default_attrs->{$_} || '') eq 'arg') {
		ref($_[0]) and die "error in packing definition\n";
		$attr{$_} = shift;
		ref($attrs) eq 'ARRAY' and shift @$attrs;
	    } elsif (ref($attrs) eq 'HASH' && defined($attrs->{$_})) {
		$attr{$_} = $attrs->{$_};
	    } elsif (ref($attrs) eq 'ARRAY') {
		$attr{$_} = shift @$attrs;
	    } elsif (defined($default_attrs->{$_})) {
		$attr{$_} = int $default_attrs->{$_};
	    } else {
		$attr{$_} = 0;
	    }
	}
	#- Get and pack the widget (create it if necessary to  a label...)
	my $widget = ref($_[0]) ? shift : Gtk2::Label->new(shift);
	my $pack_call = 'pack_'.($attr{pack_end} ? 'end' : 'start');
	$box->$pack_call($widget, $attr{expand}, $attr{fill}, $attr{padding});
	$widget->show;
    }
    return $box;
}

sub gtktreeview_children {
    my ($model, $iter) = @_;
    my @l;
    $model && $iter or return;
    for (my $p = $model->iter_children($iter); $p; $p = $model->iter_next($p)) {
	push @l, $p;
    }
    @l;
}



# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 create
#
# Helpers that allow omitting common operations on common widgets
# (e.g. create widgets with good default properties)

sub create_pixbutton {
    my ($label, $pix, $reverse_order) = @_;
    my @label_and_pix = (0, $label, if_($pix, 0, $pix));
    gtkadd(Gtk2::Button->new,
	   gtkpack_(Gtk2::HBox->new(0, 3),
		    1, "",
		    $reverse_order ? reverse(@label_and_pix) : @label_and_pix,
		    1, ""));
}

sub create_adjustment {
    my ($val, $min, $max) = @_;
    Gtk2::Adjustment->new($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_scrolled_window {
    my ($W, $policy, $viewport_shadow) = @_;
    my $w = Gtk2::ScrolledWindow->new(undef, undef);
    $policy ||= [ 'automatic', 'automatic' ];
    $w->set_policy(@{$policy});
    if (member(ref $W, qw(Gtk2::Layout Gtk2::Text Gtk2::TextView Gtk2::TreeView))) {
	$w->add($W)
    } else {
	$w->add_with_viewport($W);
    }
    $viewport_shadow and gtkset_shadow_type($w->child, $viewport_shadow);
    $W->can('set_focus_vadjustment') and $W->set_focus_vadjustment($w->get_vadjustment);
    $W->show;
    $w
}

sub n_line_size {
    my ($nbline, $type, $widget) = @_;
    my $spacing = ${{ text => 0, various => 17 }}{$type};
    my %fontinfo = gtkfontinfo($widget);
    round($nbline * ($fontinfo{ascent} + $fontinfo{descent} + $spacing) + 8);
}

sub create_box_with_title {
    my $o = shift;

    my $nbline = sum(map { round(length($_) / 60 + 1/2) } map { split "\n" } @_);
    my $box = Gtk2::VBox->new(0,0);
    return $box if $nbline == 0;

    $o->{box_size} = n_line_size($nbline, 'text', $box);
    if (@_ <= 2 && $nbline > 4) {
	$o->{icon} && !$::isWizard and 
	  eval { gtkpack__($box, gtkset_border_width(gtkpack_(Gtk2::HBox->new(0,0), 1, gtkcreate_img($o->{icon})),5)) };
	my $wanted = $o->{box_size};
	$o->{box_size} = min(200, $o->{box_size});
	my $has_scroll = $o->{box_size} < $wanted;

	my $wtext = Gtk2::TextView->new;
	$wtext->can_focus($has_scroll);
	chomp(my $text = join("\n", @_));
	my $scroll = create_scrolled_window(gtktext_insert($wtext, $text));
	$scroll->set_size_request(400, $o->{box_size});
	gtkpack($box, $scroll);
    } else {
	my $a = !$::no_separator;
	undef $::no_separator;
	if ($o->{icon} && (!$::isWizard || $::isInstall)) {
	    gtkpack__($box,
		      gtkpack_(Gtk2::HBox->new(0,0),
			       0, gtkset_size_request(Gtk2::VBox->new(0,0), 15, 0),
			       0, eval { gtkcreate_img($o->{icon}) },
			       0, gtkset_size_request(Gtk2::VBox->new(0,0), 15, 0),
			       1, gtkpack_($o->{box_title} = Gtk2::VBox->new(0,0),
					   1, Gtk2::HBox->new(0,0),
					   (map {
					       my $w = ref $_ ? $_ : Gtk2::Label->new($_);
					       $::isWizard and $w->set_justify("left");
					       $w->set_name("Title");
					       (0, $w);
					   } map { ref $_ ? $_ : warp_text($_) } @_),
					   1, Gtk2::HBox->new(0,0),
					  )
			      ),
		      if_($a, Gtk2::HSeparator->new)
		     )
	} else {
	    gtkpack__($box,
		      (map {
			  my $w = ref $_ ? $_ : Gtk2::Label->new($_);
			  $::isWizard and $w->set_justify("left");
			  $w->set_name("Title");
			  $w;
		      } map { ref $_ ? $_ : warp_text($_) } @_),
		      if_($a, Gtk2::HSeparator->new)
		     )
	}
    }
}

# drakfloppy / logdrake
sub create_dialog {
    my ($label, $c) = @_;
    my $ret = 0;
    my $dialog = Gtk2::Dialog->new;
    $dialog->signal_connect(delete_event => sub { Gtk2->main_quit });
    $dialog->set_title(N("logdrake"));
    $dialog->set_border_width(10);
    $dialog->set_position('center-on-parent');  # center-on-parent doesn't work
    $dialog->vbox->pack_start(Gtk2::Label->new($label), 1, 1, 0);

    my $button = Gtk2::Button->new(N("OK"));
    $button->can_default(1);
    $button->signal_connect(clicked => sub { $ret = 1; $dialog->destroy; Gtk2->main_quit });
    $dialog->action_area->pack_start($button, 1, 1, 0);
    $button->grab_default;

    if ($c) {
	my $button2 = Gtk2::Button->new(N("Cancel"));
	$button2->signal_connect(clicked => sub { $ret = 0; $dialog->destroy; Gtk2->main_quit });
	$button2->can_default(1);
	$dialog->action_area->pack_start($button2, 1, 1, 0);
    }

    $dialog->show_all;
    $dialog->set_modal(1);
    Gtk2->main;
    $ret;
}

# drakfloppy / logdrake
sub destroy_window {
    my ($_widget, $windowref, $w2) = @_;
    $$windowref = undef;
    $w2 = undef if defined $w2;
    0;
}

sub create_hbox { gtkset_layout(gtkset_border_width(Gtk2::HButtonBox->new, 3), $_[0] || 'spread') }
sub create_vbox { gtkset_layout(Gtk2::VButtonBox->new, $_[0] || 'spread') }

sub create_factory_menu_ {
    my ($type, $name, $window, @menu_items) = @_;
    my $widget = Gtk2::ItemFactory->new($type, $name, my $accel_group = Gtk2::AccelGroup->new);
    $widget->create_items([ @menu_items ]);
    $window->add_accel_group($accel_group);
    ($widget->get_widget($name), $widget);
}

sub create_factory_menu { create_factory_menu_(Gtk2::MenuBar->get_type, '<main>', @_) }

sub create_menu {
    my $title = shift;
    my $w = Gtk2::MenuItem->new($title);
    $w->set_submenu(gtkshow(gtkappend(Gtk2::Menu->new, @_)));
    $w
}

sub create_notebook {
    my $n = Gtk2::Notebook->new;
    add2notebook($n, splice(@_, 0, 2)) while @_;
    $n
}

sub create_packtable {
    my ($options, @l) = @_;
    my $w = Gtk2::Table->new(0, 0, $options->{homogeneous} || 0);
    each_index {
	my ($i, $l) = ($_[0], $_);
	each_index {
	    my ($j) = @_;
	    if ($_) {
		ref $_ or $_ = Gtk2::Label->new($_);
		$j != $#$l ?
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     'fill', 'fill', 5, 0) :
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     ['expand', 'fill'], ref($_) eq 'Gtk2::ScrolledWindow' || $_->get_data('must_grow') ? ['expand', 'fill'] : [], 0, 0);
		$_->show;
	    }
	} @$l;
    } @l;
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    $w
}

sub create_okcancel {
    my ($w, $ok, $cancel, $spread, @other) = @_;
    my $wizard_buttons = $::isWizard && !$pop_it;
    $spread ||= $wizard_buttons ? "end" : "spread";
    $cancel = $wizard_buttons ? N("<- Previous") : N("Cancel") if !defined $cancel && !defined $ok;
    $ok = $wizard_buttons ? ($::Wizard_finished ? N("Finish") : N("Next ->")) : N("Ok") if !defined $ok;
    my $b1 = gtksignal_connect($w->{ok} = Gtk2::Button->new($ok), clicked => $w->{ok_clicked} || sub { $w->{retval} = 1; Gtk2->main_quit });
    my $b2 = $cancel && gtksignal_connect($w->{cancel} = Gtk2::Button->new($cancel), clicked => $w->{cancel_clicked} || sub { log::l("default cancel_clicked"); undef $w->{retval}; Gtk2->main_quit });
    gtksignal_connect($w->{wizcancel} = Gtk2::Button->new(N("Cancel")), clicked => sub { die 'wizcancel' }) if $wizard_buttons && !$::isInstall;
    my @l = grep { $_ } $wizard_buttons ? (if_(!$::isInstall, $w->{wizcancel}), 
				       if_(!$::Wizard_no_previous, $b2), $b1) : ($b1, $b2);
    my @l2 = map { gtksignal_connect(Gtk2::Button->new($_->[0]), clicked => $_->[1]) } @other;

    $_->can_default($wizard_buttons) foreach @l2, @l;
    gtkadd(create_hbox($spread), @l2, @l);
}

sub _setup_paned {
    my ($paned, $child1, $child2, %options) = @_;
    $paned->pack1(gtkshow($child1), $options{resize1} || 0, $options{shrink1} || 1);
    $paned->pack2(gtkshow($child2), $options{resize2} || 1, $options{shrink2} || 1);
    gtkshow($paned);
}

sub create_vpaned {
    _setup_paned(Gtk2::VPaned->new, @_);
}

sub create_hpaned {
    _setup_paned(Gtk2::HPaned->new, @_);
}


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 helpers
#
# Functions that do typical operations on widgets, that you may need in
# several places of your programs.

sub _find_imgfile {
    my ($f, @extensions) = shift;
    @extensions or @extensions = qw(.png .xpm);
    if ($f !~ m|^/|) {
	foreach my $path (icon_paths()) {
	    -e "$path/$f$_" and $f = "$path/$f$_" foreach '', @extensions;
	}
    }
    return $f;
}

# use it if you want to display an icon/image in your app
sub gtkcreate_img {
    return Gtk2::Image->new_from_file(_find_imgfile(@_));
}

# use it if you want to draw an image onto a drawingarea
sub gtkcreate_pixbuf {
    return Gtk2::Gdk::Pixbuf->new_from_file(_find_imgfile(@_));
}

sub gtktext_append { gtktext_insert(@_, { 'append' => 1 }) }

# choose one of the two styles:
# - gtktext_insert($textview, "My text..");
# - gtktext_insert($textview, [ [ 'first text',  { 'foreground' => 'blue', 'background' => 'green', ... } ],
#			        [ 'second text' ],
#		                [ 'third', { 'font' => 'Serif 15', ... } ],
#                               ... ]);
sub gtktext_insert {
    my ($textview, $t, $opts) = @_;
    if (ref($t) eq 'ARRAY') {
	my $buffer = $textview->get_buffer;
	$opts->{append} or $buffer->set_text('', -1);
	foreach my $token (@$t) {
	    my $c = $buffer->get_char_count;
	    $buffer->insert($buffer->get_end_iter, $token->[0], -1);
	    if ($token->[1]) {
		my $tag = $buffer->create_tag(undef);
		$tag->set(%{$token->[1]});
		$buffer->apply_tag($tag, $buffer->get_iter_at_offset($c), $buffer->get_end_iter);
	    }
	}
    } else {
	$textview->get_buffer->set_text($t, -1);
    }
    $textview->set_wrap_mode($opts->{wrap_mode} || 'word');
    $textview->set_editable($opts->{editable} || 0);
    $textview->set_cursor_visible($opts->{visible} || 0);
    $textview;
}

# extracts interesting font metrics for a given widget
sub gtkfontinfo {
    my ($widget) = @_;
    my $context = $widget->get_pango_context;
    my $metrics = $context->get_metrics($widget->style->get_font_desc, $context->get_language);
    my %fontinfo;
    foreach (qw(ascent descent approximate_char_width approximate_digit_width)) {
	no strict;
	my $func = "get_$_";
	$fontinfo{$_} = Gtk2::Pango->PANGO_PIXELS($metrics->$func);
    }
    $metrics->unref;
    %fontinfo;
}

sub gtkmodify_font {
    my ($w, $arg) = @_;
    $w->modify_font(ref($arg) ? $arg : Gtk2::Pango::FontDescription->from_string($arg));
    $w;
}

sub gtkset_property {
    my ($w, $property, $value) = @_;
    $w->set_property($property, $value);
    $w;
}

sub set_back_pixbuf {
    my ($widget, $pixbuf) = @_;
    my $window = $widget->window;
    my ($width, $height) = ($pixbuf->get_width, $pixbuf->get_height);
    my $pixmap = Gtk2::Gdk::Pixmap->new($window, $width, $height, $window->get_depth);
    $pixbuf->render_to_drawable($pixmap, $widget->style->fg_gc('normal'), 0, 0, 0, 0, $width, $height, 'none', 0, 0);
    $window->set_back_pixmap($pixmap, 0);
}

sub fill_tiled_coords {
    my ($widget, $pixbuf, $x_back, $y_back, $width, $height) = @_;
    my ($x2, $y2) = (0, 0);
    while (1) {
	$x2 = 0;
	while (1) {
	    $pixbuf->render_to_drawable($widget->window, $widget->style->fg_gc('normal'),
					0, 0, $x2, $y2, $x_back, $y_back, 'none', 0, 0);
	    $x2 += $x_back;
	    $x2 >= $width and last;
	}
	$y2 += $y_back;
	$y2 >= $height and last;
    }
}

sub fill_tiled {
    my ($widget, $pixbuf) = @_;
    fill_tiled_coords($widget, $pixbuf, $pixbuf->get_width, $pixbuf->get_height, $widget->window->get_size);
}

sub add2notebook {
    my ($n, $title, $book) = @_;
    $n->append_page($book, gtkshow(Gtk2::Label->new($title)));
    $book->show;
}

sub string_size {
    my ($widget, $text) = @_;
    my $layout = $widget->create_pango_layout($text);
    my @size = $layout->get_pixel_size;
    $layout->unref;
    @size;
}

sub get_text_coord {
    my ($text, $widget4style, $max_width, $max_height, $can_be_greater, $can_be_smaller, $centeredx, $centeredy, $wrap_char) = @_;
    $wrap_char ||= ' ';
    my $idx = 0;
    my $real_width = 0;
    my $real_height = 0;
    my @lines;
    my @widths;
    my @heights;
    my %fontinfo = gtkfontinfo($widget4style);
    my $height_elem = $fontinfo{ascent} + $fontinfo{descent};
    $heights[0] = 0;
    my $max_width2 = $max_width;
    my $height = $heights[0] = $height_elem;
    my $width = 0;
    my $flag = 1;
    my @t = split($wrap_char, $text);
    my @t2;
    if ($::isInstall && $::o->{lang} =~ /ja|zh/) {
	@t = map { $_ . $wrap_char } @t;
	$wrap_char = '';
	foreach (@t) {
	    my @c = split('');
	    my $i = 0;
	    my $el = '';
	    while (1) {
		$i >= @c and last;
		$el .= $c[$i];
		if (ord($c[$i]) >= 128) { $el .= $c[$i+1]; $i++; push @t2, $el; $el = '' }
		$i++;
	    }
	    $el ne '' and push @t2, $el;
	}
    } else {
	@t2 = @t;
    }
    foreach (@t2) {
	my ($l, undef) = string_size($widget4style, $_ . (!$flag ? $wrap_char : ''));
	if ($width + $l > $max_width2 && !$flag) {
	    $flag = 1;
	    $height += $height_elem + 1;
	    $heights[$idx+1] = $height;
	    $widths[$idx] = $centeredx && !$can_be_smaller ? (max($max_width2-$width, 0))/2 : 0;
	    $width = 0;
	    $idx++;
	}
	$lines[$idx] = $flag ? $_ : $lines[$idx] . $wrap_char . $_;
	$width += $l;
	$flag = 0;
	$l <= $max_width2 or $max_width2 = $l;
	$width <= $real_width or $real_width = $width;
    }
    $height += $height_elem;
    $widths[$idx] = $centeredx && !$can_be_smaller ? (max($max_width2-$width, 0))/2 : 0;

    $height < $real_height or $real_height = $height;
    $width = $max_width;
    $height = $max_height;
    $real_width < $max_width && $can_be_smaller and $width = $real_width;
    $real_width > $max_width && $can_be_greater and $width = $real_width;
    $real_height < $max_height && $can_be_smaller and $height = $real_height;
    $real_height > $max_height && $can_be_greater and $height = $real_height;
    if ($centeredy) {
 	my $dh = ($height-$real_height)/2 + ($height_elem)/2;
 	@heights = map { $_ + $dh } @heights;
    }
    ($width, $height, \@lines, \@widths, \@heights)
}

sub gtkcolor {
    my ($r, $g, $b) = @_;
    my $color = Gtk2::Gdk::Color->new($r, $g, $b);
    gtkroot()->get_colormap->rgb_find_color($color);
    $color;
}

sub gtkset_background {
    my ($r, $g, $b) = @_;
    my $root = gtkroot();
    my $gc = Gtk2::Gdk::GC->new($root);
    my $color = gtkcolor($r, $g, $b);
    $gc->set_rgb_fg_color($color);
    $root->set_background($color);
    $root->draw_rectangle($gc, 1, 0, 0, $root->get_size);
    $gc->unref;
}

sub add_icon_path { push @icon_paths, @_ }
sub icon_paths {
   (@icon_paths, (exists $ENV{SHARE_PATH} ? ($ENV{SHARE_PATH}, "$ENV{SHARE_PATH}/icons", "$ENV{SHARE_PATH}/libDrakX/pixmaps") : ()),
    "/usr/lib/libDrakX/icons", "pixmaps", 'standalone/icons', '/usr/share/rpmdrake/icons');
}  
add_icon_path(@icon_paths,
	      exists $ENV{SHARE_PATH} ? "$ENV{SHARE_PATH}/libDrakX/pixmaps" : (),
	      '/usr/lib/libDrakX/icons', 'standalone/icons');



# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 toplevel window creation helper
#
# Use the 'new' function as a method constructor and then 'main' on it to
# launch the main loop. Use $o->{retval} to indicate that the window needs
# to terminate.
# Set $::isWizard to have a wizard appearance.
# Set $::isEmbedded, $::CCPID and $::XID so that the window will plug.

sub new {
    my ($type, $title, %opts) = @_;

    Gtk2->set_locale;

    my $o = bless { %opts }, $type;
    $o->_create_window($title);
    while (my $e = shift @tempory::objects) { $e->destroy }
    foreach (@interactive::objects) {
#	$_->{rwindow}->set_modal(0) if $_->{rwindow}->can('set_modal');      FIXME
    }
    push @interactive::objects, $o if !$opts{no_interactive_objects};
    $o->{rwindow}->set_position('center-always') if $::isStandalone;
    $o->{rwindow}->set_modal(1) if $grab || $o->{grab} || $o->{modal};
    $o->{rwindow}->set_transient_for($o->{transient}) if $o->{transient};
    
    if ($::isWizard && !$pop_it) {
	$o->{isWizard} = 1;
	$o->{window} = Gtk2::VBox->new(0,0);
	$o->{window}->set_border_width($::Wizard_splash ? 0 : 10);
	$o->{rwindow} = $o->{window};
	if (!defined($::WizardWindow)) {
	    $::WizardWindow = Gtk2::Window->new('toplevel');
	    $::WizardWindow->signal_connect(delete_event => sub { die 'wizcancel' });
	    $::WizardTable = Gtk2::Table->new(2, 2, 0);
	    $::WizardWindow->add($::WizardTable);

	    if ($::isInstall) {
		$::WizardTable->set_size_request($::windowwidth * 0.90, $::windowheight * 0.73);
		$::WizardWindow->set_uposition($::stepswidth + $::windowwidth * 0.04, $::logoheight + $::windowheight * 0.15);
		$::WizardWindow->signal_connect(key_press_event => sub {
		    my (undef, $event) = @_;
		    my $d = ${{ Gtk2::Gdk::Event::Key->Sym_F1  => 'help',
			        Gtk2::Gdk::Event::Key->Sym_F2  => 'screenshot' }}{$event->keyval};
		    
		    if ($d eq "help") {
			require install_gtk;
			install_gtk::create_big_help($::o);
		    } elsif ($d eq 'screenshot') {
			common::take_screenshot();
		    } elsif (chr($event->keyval) eq 'e' && member('mod1-mask', @{$event->state})) {  #- alt-e
			log::l("Switching to " . ($::expert ? "beginner" : "expert"));
			$::expert = !$::expert;
		    }
		});
	    } else {
		my $draw1 = Gtk2::DrawingArea->new;
		$draw1->set_size_request(540, 100);
		my $draw2 = Gtk2::DrawingArea->new;
		$draw2->set_size_request(100, 300);
		my $pixbuf_up = gtkcreate_pixbuf($::Wizard_pix_up || "wiz_default_up.png");
		my $pixbuf_left = gtkcreate_pixbuf($::Wizard_pix_left || "wiz_default_left.png");
		$draw1->modify_font(Gtk2::Pango::FontDescription->from_string(N("utopia 25")));
		$draw1->signal_connect(expose_event => sub {
					   my $height = $pixbuf_up->get_height;
					   for (my $i = 0; $i < 540/$height; $i++) {
					       $pixbuf_up->render_to_drawable($draw1->window,
									      $draw1->style->bg_gc('normal'),
									      0, 0, 0, $height*$i, -1, -1, 'none', 0, 0);
					       my $layout = $draw1->create_pango_layout($::Wizard_title);
					       $draw1->window->draw_layout($draw1->style->white_gc, 40, 62, $layout);
					       $layout->unref;
					   }
				       });
		$draw2->signal_connect(expose_event => sub {
					   my $height = $pixbuf_left->get_height;
					   for (my $i = 0; $i < 300/$height; $i++) {
					       $pixbuf_left->render_to_drawable($draw2->window,
										$draw2->style->bg_gc('normal'),
										0, 0, 0, $height*$i, -1, -1, 'none', 0, 0);
					   }
				       });

		$::WizardWindow->set_position('center_always');
		$::WizardTable->attach($draw1, 0, 2, 0, 1, 'fill', 'fill', 0, 0);
		$::WizardTable->set_size_request(540,420);
	    }
	    $::WizardWindow->show_all;
	    flush();
	}
	$::WizardTable->attach($o->{window}, 0, 2, 1, 2, ['fill', 'expand'], ['fill', 'expand'], 0, 0);
    }

    if ($::isEmbedded && !$pop_it && !eval { $::Plug && $::Plug->child }) {
	$o->{isEmbedded} = 1;
	$o->{window} = new Gtk2::HBox(0,0);
	$o->{rwindow} = $o->{window};
	$::Plug ||= new Gtk2::Plug($::XID);
	$::Plug->show;
	flush();
	$::Plug->add($o->{window});
    }
    $o;
}
sub main {
    my ($o, $completed, $canceled) = @_;
    gtkset_mousecursor_normal();
    $::CCPID and kill 'USR2', $::CCPID;
    my $timeout = Gtk2->timeout_add(1000, sub { gtkset_mousecursor_normal(); 1 });
    my $_b = MDK::Common::Func::before_leaving { Gtk2->timeout_remove($timeout) };
    $o->show;

    do {
	Gtk2->main;
    } while ($o->{retval} ? $completed && !$completed->() : $canceled && !$canceled->());
    $o->destroy;
    $o->{retval}
}
sub show($) {
    my ($o) = @_;
    $o->{window}->show;
    $o->{rwindow}->show;
}
sub destroy($) {
    my ($o) = @_;
    $o->{rwindow}->destroy if !$o->{destroyed};
    $o->{destroyed} = 1;  #- the perl DESTROY will call us, so avoid Gtk-CRITICAL if user explicitely called us before
    gtkset_mousecursor_wait();
    flush();
}
sub DESTROY { goto &destroy }
sub sync {
    my ($o) = @_;
    show($o);
    flush();
}
sub flush { gtkflush() }
sub exit {
    gtkset_mousecursor_normal(); #- for restoring a normal in any case
    flush();
    $::isEmbedded and kill 'USR1', $::CCPID;
    c::_exit($_[1]) #- workaround 
}

#- in case "exit" above was not called by the program
END { &exit() }

sub _create_window($$) {
    my ($o, $title) = @_;
    my $w = Gtk2::Window->new('toplevel');
    !$::isStandalone && !$::live && !$::g_auto_install and $shape_width = 3;
    my $inner = gtkadd(gtkset_shadow_type(Gtk2::Frame->new(undef), 'out'),
		       my $f = gtkset_border_width(gtkset_shadow_type(Gtk2::Frame->new(undef), 'none'), 3)
		      );
    my $table;
    if ($::isStandalone || $::live || $::g_auto_install || $::noShadow) { gtkadd($w, $inner) if !$::noBorder } else {
	my $gc = Gtk2::Gdk::GC->new(gtkroot());
	$gc->set_rgb_fg_color(gtkcolor(5120, 10752, 22784)); #- in hex : 20, 42, 89
	my $sqw = $shape_width;
	gtkadd($w, $table = Gtk2::Table->new(2, 2, 0));
	$table->attach($inner, 0, 1, 0, 1, ['expand', 'fill'], ['expand', 'fill'], 0, 0);
	$table->attach(gtksignal_connect(gtkset_size_request(Gtk2::DrawingArea->new, $sqw, 1), expose_event => sub {
					      $_[0]->window->draw_rectangle($_[0]->style->bg_gc('normal'), 1, 0, 0, $sqw, $sqw);
					      $_[0]->window->draw_rectangle($gc, 1, 0, $sqw, $sqw, $_[0]->allocation->height);
					  }),
			1, 2, 0, 1, 'fill', 'fill', 0, 0);
	$table->attach(gtksignal_connect(gtkset_size_request(Gtk2::DrawingArea->new, 1, $sqw), expose_event => sub {
					      $_[0]->window->draw_rectangle($_[0]->style->bg_gc('normal'), 1, 0, 0, $sqw, $sqw);
					      $_[0]->window->draw_rectangle($gc, 1, $sqw, 0, $_[0]->allocation->width, $sqw);
					  }),
			0, 1, 1, 2, 'fill', 'fill', 0, 0);
	$table->attach(gtksignal_connect(gtkset_size_request(Gtk2::DrawingArea->new, $sqw, $sqw), expose_event => sub {
					      $_[0]->window->draw_rectangle($gc, 1, 0, 0, $sqw, $sqw);
					  }),
			1, 2, 1, 2, 'fill', 'fill', 0, 0);
	$table->show_all;
	$w->signal_connect(delete_event => sub { $gc->unref });
    }
    $w->set_name("Title");
    $w->set_title($title);

    print STDERR "TODO: XSetInputFocus if force_focus\n";
#    $w->signal_connect(expose_event => sub { eval { $interactive::objects[-1]{rwindow} == $w and $w->window->XSetInputFocus } }) if $force_focus || $o->{force_focus};
    $w->signal_connect(delete_event => sub { if ($::isWizard) { $w->destroy; die 'wizcancel' } else { Gtk2->main_quit } });
    $w->set_uposition(@{$force_position || $o->{force_position}}) if $force_position || $o->{force_position};

    print STDERR "TODO: ensure focus stuff\n";
#    my $focusing;
#    $w->signal_connect(focus => sub { 
#        return 1 if $focusing;
#	$focusing = 1;
#	Gtk2->idle_add(sub { $w->ensure_focus($_[0]); $focusing = 0; 0 }, $_[1]);
#    }) if $w->can('ensure_focus');

    if ($::o->{mouse}{unsafe}) {
	$w->add_events('pointer-motion-mask');
	my $signal;  #- don't make this line part of next one, signal_disconnect won't be able to access $signal value
	$signal = $w->signal_connect(motion_notify_event => sub {
	    delete $::o->{mouse}{unsafe};
	    log::l("unsetting unsafe mouse");
	    $w->signal_disconnect($signal);
	});
    }

    my ($wi, $he);
    $w->signal_connect(size_allocate => sub {
	my (undef, $event) = @_;
	my $w_size = $event->values;
	return if $w_size->[2] == $wi && $w_size->[3] == $he;
	(undef, undef, $wi, $he) = @{$w_size};

	my ($X, $Y, $Wi, $He) = @{$force_center || $o->{force_center}};
        $w->set_uposition(max(0, $X + ($Wi - $wi) / 2), max(0, $Y + ($He - $he) / 2));

	if (!$::isStandalone && !$::live && !$::g_auto_install && !$::noShadow) {
	    my $sqw = $shape_width; #square width
	    my $wia = int(($wi+7)/8);
	    my $s = "\xFF" x ($wia*$he);
	    my $wib = $wia*8;
	    my $dif = $wib-$wi;
	    foreach my $y (0..$sqw-1) { vec($s, $wib-1-$dif-$_+$wib*$y, 1) = 0x0 foreach (0..$sqw-1) }
	    foreach my $y (0..$sqw-1) { vec($s, (($he-1)*$wib)-$wib*$y+$_, 1) = 0x0 foreach (0..$sqw-1) }
	    $w->realize;
	    my $b = Gtk2::Gdk::Bitmap->create_from_data($w->window, $s, $wib, $he);
	    $w->window->shape_combine_mask($b, 0, 0);
	}
    }) if ($force_center || $o->{force_center}) && !($force_position || $o->{force_position});

    $o->{window} = $::noBorder ? $w : $f;
    $o->{rwindow} = $w;
    $table and $table->queue_draw;
}


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 ask
#
# Full UI managed functions that will return to you the value that the
# user chose.

sub ask_warn       { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_warn(@_); main($w) }
sub ask_yesorno    { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Yes"), N("No")); main($w) }
sub ask_okcancel   { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Is this correct?"), N("Ok"), N("Cancel")); main($w) }
sub ask_from_entry { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_from_entry(@_); main($w) }
sub ask_dir        { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_dir(@_); main($w) }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = Gtk2::Entry->new;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk2->main_quit };
    $o->{ok_clicked} = $f;
    $o->{cancel_clicked} = sub { undef $o->{retval}; Gtk2->main_quit };

    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect($entry, 'activate' => $f),
		 ($o->{hide_buttons} ? () : create_okcancel($o))),
	  );
    $entry->grab_focus;
}

sub _ask_warn($@) {
    my ($o, @msgs) = @_;
    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect(my $w = Gtk2::Button->new(N("Ok")), "clicked" => sub { Gtk2->main_quit }),
		 ),
	  );
    $w->grab_focus;
}

sub _ask_okcancel($@) {
    my ($o, @msgs) = @_;
    my ($ok, $cancel) = splice @msgs, -2;

    gtkadd($o->{window},
	   gtkpack(create_box_with_title($o, @msgs),
		   create_okcancel($o, $ok, $cancel),
		 )
	 );
    $o->{ok}->grab_focus;
}


sub _ask_file {
    my ($o, $title, $path) = @_;
    my ($modality, $position) = ($o->{rwindow}->get_modal, $o->{rwindow}->window_position);
    my $f = $o->{rwindow} = Gtk2::FileSelection->new($title);
    $f->set_modal($modality);
    $f->set_position($position);
    $path and $f->set_filename($path);
    $f->ok_button->signal_connect(clicked => sub { $o->{retval} = $f->get_filename; Gtk2->main_quit });
    $f->cancel_button->signal_connect(clicked => sub { Gtk2->main_quit });
    $f->grab_focus;
    $f;
}

sub _ask_dir {
    my ($o) = @_;
    my $f = _ask_file(@_);
    $f->file_list->get_parent->hide;
    $f->selection_entry->get_parent->hide;
    $f->ok_button->signal_connect(clicked => sub {
				      my ($model, $iter) = $f->dir_list->get_selection->get_selected;
				      if ($model) { $o->{retval} .= $model->get($iter, 0); $iter->free }
				  });
}

sub ask_browse_tree_info {
    my ($common) = @_;

    my $w = ugtk2->new($common->{title});

    my $tree_model = Gtk2::TreeStore->new(Gtk2::GType->STRING, Gtk2::GType->OBJECT, Gtk2::GType->STRING);
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    $tree->append_column(my $textcolumn = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $tree->append_column(my $pixcolumn  = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererPixbuf->new, 'pixbuf' => 1));
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 2));
    $tree->set_headers_visible(0);
    $textcolumn->set_minmax_width(200);

    gtkadd($w->{window}, 
	   gtkpack_(Gtk2::VBox->new(0,5),
		    0, $common->{message},
		    1, gtkpack(Gtk2::HBox->new(0,0),
			       create_scrolled_window($tree),
			       gtkadd(gtkset_size_request(Gtk2::Frame->new(N("Info")), $::windowwidth - 490, 0),
				      create_scrolled_window(my $info = Gtk2::TextView->new),
				     )),
		    0, my $l = Gtk2::HBox->new(0,15),
		    0, gtkpack(Gtk2::HBox->new(0,10),
			       my $go = gtksignal_connect(Gtk2::Button->new($common->{ok}), clicked => sub {
							      $w->{retval} = 1;
							      Gtk2->main_quit }),
			       $common->{cancel} ? gtksignal_connect(Gtk2::Button->new($common->{cancel}), clicked => sub {
									  $w->{retval} = 0;
									  Gtk2->main_quit })
			                         : (),
			      )));
    gtkpack__($l, my $toolbar = Gtk2::Toolbar->new('horizontal', 'icons'));

    if ($common->{auto_deps}) {
	gtkpack__($l, gtksignal_connect(gtkset_active(Gtk2::CheckButton->new($common->{auto_deps}), $common->{state}{auto_deps}),
					clicked => sub { invbool \$common->{state}{auto_deps} }));
    }
    $l->pack_end(my $status = Gtk2::Label->new, 0, 1, 20);

    $w->{window}->set_size_request(map { $_ - 2 * $border - 4 } $::windowwidth, $::windowheight);
    $go->grab_focus;
    $w->{rwindow}->show_all;

    my @toolbar = (ftout  =>  [ N("Expand Tree"), sub { $tree->expand_all } ],
		   ftin   =>  [ N("Collapse Tree"), sub { $tree->collapse_all } ],
		   reload =>  [ N("Toggle between flat and group sorted"), sub { invbool(\$common->{state}{flat}); $common->{rebuild_tree}->() } ]);
    foreach my $ic (@{$common->{icons} || []}) {
	push @toolbar, ($ic->{icon} => [ $ic->{help}, sub {
					     if ($ic->{code}) {
						 my $_w = $ic->{wait_message} && $common->{wait_message}->('', $ic->{wait_message});
						 $ic->{code}();
						 $common->{rebuild_tree}->();
					     }
					 } ]);
    }
    my %toolbar = @toolbar;
    foreach (grep_index { $::i % 2 == 0 } @toolbar) {
	$toolbar->append_item(undef, $toolbar{$_}[0], undef, gtkcreate_img("$_.png"), $toolbar{$_}[1]);
    }

    my $widgets = { w => $w, tree => $tree, tree_model => $tree_model, textcolumn => $textcolumn, pixcolumn => $pixcolumn,
		    info => $info, status => $status };
    ask_browse_tree_info_given_widgets($common, $widgets);
}

sub ask_browse_tree_info_given_widgets {
    my ($common, $w) = @_;
    my ($curr, $prev_label, $idle, $mouse_toggle_pending);
    my (%wtree, %ptree, %pix, %node_state, %state_stats);
    my $update_size = sub {
	my $new_label = $common->{get_status}();
	$prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
    };
    
    my $set_node_state_flat = sub {
	my ($iter, $state) = @_;
	$state eq 'XXX' and return;
	$pix{$state} ||= gtkcreate_pixbuf($state);
	$w->{tree_model}->set($iter, [ 1 => $pix{$state} ]);
    };
    my $set_node_state_tree; $set_node_state_tree = sub {
	my ($iter, $state) = @_;
	my $iter_str = $w->{tree_model}->get_path_str($iter);
	$state eq 'XXX' and return;
	$pix{$state} ||= gtkcreate_pixbuf($state);
	if ($node_state{$iter_str} ne $state) {
	    my $parent;
	    if (!$w->{tree_model}->iter_has_child($iter) && ($parent = $w->{tree_model}->iter_parent($iter))) {
		my $parent_str = $w->{tree_model}->get_path_str($parent);
		my $stats = $state_stats{$parent_str} ||= {}; $stats->{$node_state{$iter_str}}--; $stats->{$state}++;
		my @list = grep { $stats->{$_} > 0 } keys %$stats;
		my $new_state = @list == 1 ? $list[0] : 'semiselected';
		$node_state{$parent_str} ne $new_state and $set_node_state_tree->($parent, $new_state);
		$parent->free;
	    }
	    $w->{tree_model}->set($iter, [ 1 => $pix{$state} ]);
	    $node_state{$iter_str} = $state;  #- cache for efficiency
	}
    };
    my $set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;

    my $set_leaf_state = sub {
	my ($leaf, $state) = @_;
	$set_node_state->($_, $state) foreach @{$ptree{$leaf}};
    };
    my $add_parent; $add_parent = sub {
	my ($root, $state) = @_;
	$root or return undef;
	if (my $w = $wtree{$root}) { return $w }
	my $s; foreach (split '\|', $root) {
	    my $s2 = $s ? "$s|$_" : $_;
	    $wtree{$s2} ||= do {
		my $iter = $w->{tree_model}->append_set($s ? $add_parent->($s, $state) : undef, [ 0 => $_ ]);
		$iter;
	    };
	    $s = $s2;
	}
	$set_node_state->($wtree{$s}, $state); #- use this state by default as tree is building.
	$wtree{$s};
    };
    my $add_node = sub {
	my ($leaf, $root, $options) = @_;
	my $state = $common->{node_state}($leaf) or return;
	if ($leaf) {
	    my $iter = $w->{tree_model}->append_set($add_parent->($root, $state), [ 0 => $leaf ]);
	    $set_node_state->($iter, $state);
	    push @{$ptree{$leaf}}, $iter;
	} else {
	    my $parent = $add_parent->($root, $state);
	    #- hackery for partial displaying of trees, used in rpmdrake:
	    #- if leaf is void, we may create the parent and one child (to have the [+] in front of the parent in the ctree)
	    #- though we use '' as the label of the child; then rpmdrake will connect on tree_expand, and whenever
	    #- the first child has '' as the label, it will remove the child and add all the "right" children
	    $options->{nochild} or $w->{tree_model}->append_set($parent, [ 0 => '' ])->free;
	}
    };
    my $clear_all_caches = sub {
	foreach (values %ptree) {
	    foreach my $n (@$_) {
		delete $node_state{$w->{tree_model}->get_path_str($n)};
		$n->free;
	    }
	}
	foreach (values %wtree) {
	    my $iter_str = $w->{tree_model}->get_path_str($_);
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
	    $_->free;
	}
	%ptree = %wtree = ();
    };
    $common->{delete_all} = sub {
	$clear_all_caches->();
	$w->{tree_model}->clear;
    };
    $common->{rebuild_tree} = sub {
	$common->{delete_all}->();
	$set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;
	$common->{build_tree}($add_node, $common->{state}{flat}, $common->{tree_mode});
	&$update_size;
    };
    $common->{delete_category} = sub {
	my ($cat) = @_;
	exists $wtree{$cat} or return;
	foreach (keys %ptree) {
	    my @to_remove;
	    foreach my $node (@{$ptree{$_}}) {
		my $category;
		my $parent = $node;
		while ($parent = $w->{tree_model}->iter_parent($parent)) {    #- LEAKS
		    my $parent_name = $w->{tree_model}->get($parent, 0);
		    $category = $category ? "$parent_name|$category" : $parent_name;
		}
		$cat eq $category and push @to_remove, $node;
	    }
	    foreach (@to_remove) {
		delete $node_state{$w->{tree_model}->get_path_str($_)};
		$_->free;
	    }
	    @{$ptree{$_}} = difference2($ptree{$_}, \@to_remove);
	}
	if (exists $wtree{$cat}) {
	    my $iter_str = $w->{tree_model}->get_path_str($wtree{$cat});
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
	    $w->{tree_model}->remove($wtree{$cat});
	    $wtree{$cat}->free;
	    delete $wtree{$cat};
	}
	&$update_size;
    };
    $common->{add_nodes} = sub {
	my (@nodes) = @_;
	$add_node->($_->[0], $_->[1], $_->[2]) foreach @nodes;
	&$update_size;
    };
    
    $common->{display_info} = sub { gtktext_insert($w->{info}, $common->{get_info}($curr)); 0 };
    my $children = sub { map { my $v = $w->{tree_model}->get($_, 0); $_->free; $v } gtktreeview_children($w->{tree_model}, $_[0]) };
    my $toggle = sub {
	if (ref $curr && !$_[0]) {
	    $w->{tree}->toggle_expansion(my $path = $w->{tree_model}->get_path($curr));
	    $path->free;
	} else {
	    if (ref $curr) {
		my @_a = $children->($curr);
		my @l = $common->{grep_allowed_to_toggle}($children->($curr)) or return;
		my @unsel = $common->{grep_unselected}(@l);
		my @p = @unsel ?
		  #- not all is selected, select all if no option to potentially override
		  (exists $common->{partialsel_unsel} && $common->{partialsel_unsel}->(\@unsel, \@l) ? difference2(\@l, \@unsel) : @unsel)
		  : @l;
		$common->{toggle_nodes}($set_leaf_state, @p);
		&$update_size;
	    } else {
		$common->{check_interactive_to_toggle}($curr) and $common->{toggle_nodes}($set_leaf_state, $curr);
		&$update_size;
	    }
	}
    };

    $w->{tree}->signal_connect(key_press_event => sub {
	my $c = chr($_[1]->keyval & 0xff);
	$toggle->(0) if $_[1]->keyval >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ';
	1;
    });
    $w->{tree}->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	Gtk2->timeout_remove($idle) if $idle;
	
	$curr->free if ref $curr;
	if (!$model->iter_has_child($iter)) {
	    $curr = $model->get($iter, 0);
	    $idle = Gtk2->timeout_add(100, $common->{display_info});
	} else {
	    $curr = $iter;
	}
	#- the following test for equality is because we can have a button_press_event first, then
	#- two changed events, the first being on a different row :/ (is it a bug in gtk2?) - that
	#- happens in rpmdrake when doing a "search" and directly trying to select a found package
	$toggle->(1), $mouse_toggle_pending = 0 if $mouse_toggle_pending eq $model->get($iter, 0);
    });
    $w->{tree}->signal_connect(button_press_event => sub {  #- not too good, but CellRendererPixbuf doesn't have the needed signals :(
	my ($returns, $path, $column) = $w->{tree}->get_path_at_pos($_[1]->x, $_[1]->y);
	if ($returns) {
	    Gtk2->equals($column, $w->{pixcolumn}) and $mouse_toggle_pending = $w->{tree_model}->get($path, 0);
	    $path->free;
	}
    });
    $common->{rebuild_tree}->();
    &$update_size;
    my $_b = before_leaving { $clear_all_caches->() };
    $w->{w}->main;
}


1;
