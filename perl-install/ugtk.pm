package ugtk;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $border $use_pixbuf $use_imlib);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    helpers => [ qw(createScrolledWindow create_menu create_notebook create_packtable create_hbox create_vbox create_adjustment create_box_with_title create_treeitem create_dialog destroy_window) ],
    wrappers => [ qw(gtksignal_connect gtkradio gtkpack gtkpack_ gtkpack__ gtkpack2 gtkpack3 gtkpack2_ gtkpack2__ gtkpowerpack gtkcombo_setpopdown_strings gtkset_editable gtksetstyle gtkset_text gtkset_tip gtkappenditems gtkappend gtkset_shadow_type gtkset_layout gtkset_relief gtkadd gtkexpand gtkput gtktext_insert gtkset_usize gtksize gtkset_justify gtkset_active gtkset_sensitive gtkset_visibility gtkset_modal gtkset_border_width gtkmove gtkresize gtkshow gtkhide gtkdestroy gtkflush gtkcolor gtkset_mousecursor gtkset_mousecursor_normal gtkset_mousecursor_wait gtkset_background gtkset_default_fontset gtkctree_children gtkxpm gtkpng create_pix_text get_text_coord fill_tiled gtkicons_labels_widget write_on_pixmap gtkcreate_xpm gtkcreate_png gtkcreate_png_pixbuf gtkbuttonset create_pixbutton gtkroot gtkentry compose_with_back compose_pixbufs) ],
    various => [ qw(add2notebook add_icon_path n_line_size) ],
);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use Gtk;

if (!$::no_ugtk_init) {
    !$ENV{DISPLAY} || system('/usr/X11R6/bin/xtest') and die "Cannot be run in console mode.\n";
    Gtk->init;
    eval { require Gtk::Gdk::Pixbuf; Gtk::Gdk::Pixbuf->init };
    $use_pixbuf = $@ ? 0 : 1;
}
eval { require Gtk::Gdk::ImlibImage; Gtk::Gdk::ImlibImage->init };
$use_imlib = $@ ? 0 : 1;

use c;
use log;
use common;

my @icon_paths;
sub add_icon_path { push @icon_paths, @_ }
sub icon_paths {
   (@icon_paths, $ENV{SHARE_PATH}, "$ENV{SHARE_PATH}/icons", "$ENV{SHARE_PATH}/libDrakX/pixmaps", "/usr/lib/libDrakX/icons", "pixmaps", 'standalone/icons');
}  

#-#######################
# gtk widgets wrappers
#-#######################

sub gtkdestroy                { $_[0] and $_[0]->destroy }
sub gtkflush                  { Gtk->main_iteration while Gtk->events_pending }
sub gtkhide                   { $_[0]->hide; $_[0] }
sub gtkmove                   { $_[0]->window->move($_[1], $_[2]); $_[0] }
sub gtkpack                   { gtkpowerpack(1, 1, @_) }
sub gtkpack_                  { gtkpowerpack('arg', 1, @_) }
sub gtkpack__                 { gtkpowerpack(0, 1, @_) }
sub gtkpack2                  { gtkpowerpack(1, 0, @_) }
sub gtkpack2_                 { gtkpowerpack('arg', 0, @_) }
sub gtkpack2__                { gtkpowerpack(0, 0, @_) }
sub gtkpack3                  { gtkpowerpack($a?1:0, 0, @_) }
sub gtkput                    { $_[0]->put(gtkshow($_[1]), $_[2], $_[3]); $_[0] }
sub gtkpixmap                 { new Gtk::Pixmap(gdkpixmap(@_)) }
sub gtkresize                 { $_[0]->window->resize($_[1], $_[2]); $_[0] }
sub gtkset_active             { $_[0]->set_active($_[1]); $_[0] }
sub gtkset_border_width       { $_[0]->set_border_width($_[1]); $_[0] }
sub gtkset_editable           { $_[0]->set_editable($_[1]); $_[0] }
sub gtkset_justify            { $_[0]->set_justify($_[1]); $_[0] }
sub gtkset_layout             { $_[0]->set_layout($_[1]); $_[0] }
sub gtkset_modal              { $_[0]->set_modal($_[1]); $_[0] }
sub gtkset_mousecursor_normal { gtkset_mousecursor(68, @_) }
sub gtkset_mousecursor_wait   { gtkset_mousecursor(150, @_) }
sub gtkset_relief             { $_[0]->set_relief($_[1]); $_[0] }
sub gtkset_sensitive          { $_[0]->set_sensitive($_[1]); $_[0] }
sub gtkset_visibility         { $_[0]->set_visibility($_[1]); $_[0] }
sub gtkset_tip                { $_[0]->set_tip($_[1], $_[2]) if $_[2]; $_[1] }
sub gtkset_shadow_type        { $_[0]->set_shadow_type($_[1]); $_[0] }
sub gtkset_style              { $_[0]->set_style($_[1]); $_[0] }
sub gtkset_usize              { $_[0]->set_usize($_[1],$_[2]); $_[0] }
sub gtkshow                   { $_[0]->show; $_[0] }
sub gtksize                   { $_[0]->size($_[1],$_[2]); $_[0] }
sub gtkexpand                 { $_[0]->expand; $_[0] }

sub gdkpixmap {
    my ($f, $w) = @_;
    $f =~ m|.png$| and return gtkcreate_png($f);
    $f =~ m|.xpm$| and return gtkcreate_xpm($w, $f);
}

sub gtkadd {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = new Gtk::Label($l);
	$w->add($l);
	$l->show;
    }
    $w
}

sub gtkappend {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = new Gtk::Label($l);
	$w->append($l);
	$l->show;
    }
    $w
}

sub gtkappenditems {
    my $w = shift;
    $_->show() foreach @_;
    $w->append_items(@_);
    $w
}

sub gtkbuttonset {
    gtkdestroy($_[0]->child);
    gtkadd($_[0], gtkshow($_[1]))
}

sub create_pixbutton {
    my ($label, $pix, $reverse_order) = @_;
    gtkadd(new Gtk::Button(), gtkpack_(new Gtk::HBox(0, 3), 1, "", $reverse_order ? (0, $label, $pix ? (0, $pix) : ()) : ($pix ? (0, $pix) : (), 0, $label), 1, ""));
}

sub gtkentry {
    my ($text) = @_;
    my $e = new Gtk::Entry;
    $e->set_text($text);
    $e;
}

sub gtksetstyle { 
    my ($w, $s) = @_;
    $w->set_style($s);
    $w;
}

sub gtkcolor {
    my ($r, $g, $b) = @_;
    my $color = bless { red => $r, green => $g, blue => $b }, 'Gtk::Gdk::Color';
    gtkroot()->get_colormap->color_alloc($color);
}

sub gtkradio {
    my $def = shift;
    my $radio;
    map { $radio = new Gtk::RadioButton($_, $radio ? $radio : ());
	  $radio->set_active($_ eq $def); $radio } @_;
}

sub gtkroot {
    Gtk->init;
    Gtk->set_locale;
    Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW);
}

sub gtkset_background {
    my ($r, $g, $b) = @_;
    my $root = gtkroot();
    my $gc = Gtk::Gdk::GC->new($root);
    my $color = gtkcolor($r, $g, $b);
    $gc->set_foreground($color);
    $root->set_background($color);
    my ($h, $w) = $root->get_size;
    $root->draw_rectangle($gc, 1, 0, 0, $w, $h);
}

sub gtktext_insert {
    my ($w, $t) = @_;
    $w->freeze;
    $w->backward_delete($w->get_length);
    if (ref($t) eq 'ARRAY') {
	$w->insert($_->[0], $_->[1], $_->[2], $_->[3]) foreach @$t;
    } else {
	$w->insert(undef, undef, undef, $t); 
    }
    #- DEPRECATED? needs \n otherwise in case of one line text the beginning is not shown (even with the vadj->set_value)
    $w->set_word_wrap(1);
#-    $w->vadj->set_value(0);
    $w->thaw;
    $w;
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

sub gtkappend_text {
    my ($w, $s) = @_;
    $w->append_text($s);
    $w;
}

sub gtkprepend_text {
    my ($w, $s) = @_;
    $w->prepend_text($s);
    $w;
}

sub gtkset_mousecursor {
    my ($type, $w) = @_;
    ($w || gtkroot())->set_cursor(Gtk::Gdk::Cursor->new($type));
}

sub gtksignal_connect {
    my $w = shift;
    $w->signal_connect(@_);
    $w;
}

#-#######################
# create widgets wrappers
#-#######################

sub create_adjustment {
    my ($val, $min, $max) = @_;
    new Gtk::Adjustment($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_box_with_title {
    my $o = shift;

    my $nbline = sum(map { round(length($_) / 60 + 1/2) } map { split "\n" } @_);
    my $box = new Gtk::VBox(0,0);
    return $box if $nbline == 0;

    $o->{box_size} = n_line_size($nbline, 'text', $box);
    if (@_ <= 2 && $nbline > 4) {
	$o->{icon} && !$::isWizard and 
	  eval { gtkpack__($box, gtkset_border_width(gtkpack_(new Gtk::HBox(0,0), 1, gtkpng($o->{icon})),5)) };
	my $wanted = $o->{box_size};
	$o->{box_size} = min(200, $o->{box_size});
	my $has_scroll = $o->{box_size} < $wanted;

	my $wtext = new Gtk::Text;
	$wtext->can_focus($has_scroll);
	chomp(my $text = join("\n", @_));
	my $scroll = createScrolledWindow(gtktext_insert($wtext, $text));
	$scroll->set_usize(400, $o->{box_size});
	gtkpack($box, $scroll);
    } else {
	my $a = !$::no_separator;
	undef $::no_separator;
	if ($o->{icon} && !$::isWizard) {
	    gtkpack__($box,
		      gtkpack_(new Gtk::HBox(0,0),
			       0, gtkset_usize(new Gtk::VBox(0,0), 15, 0),
			       0, eval { gtkpng($o->{icon}) },
			       0, gtkset_usize(new Gtk::VBox(0,0), 15, 0),
			       1, gtkpack_($o->{box_title} = new Gtk::VBox(0,0),
					   1, new Gtk::HBox(0,0),
					   (map {
					       my $w = ref $_ ? $_ : new Gtk::Label($_);
					       $::isWizard and $w->set_justify("left");
					       $w->set_name("Title");
					       (0, $w);
					   } map { ref $_ ? $_ : warp_text($_) } @_),
					   1, new Gtk::HBox(0,0),
					  )
			      ),
		      if_($a, new Gtk::HSeparator)
		     )
	} else {
	    gtkpack__($box,
		      (map {
			  my $w = ref $_ ? $_ : new Gtk::Label($_);
			  $::isWizard and $w->set_justify("left");
			  $w->set_name("Title");
			  $w;
		      } map { ref $_ ? $_ : warp_text($_) } @_),
		      if_($a, new Gtk::HSeparator)
		     )
	}
    }
}

# drakfloppy / logdrake
sub create_dialog {
    my ($label, $c) = @_;
    my $ret = 0;
    my $dialog = new Gtk::Dialog;
    $dialog->signal_connect (delete_event => sub { Gtk->main_quit() });
    $dialog->set_title(_("logdrake"));
    $dialog->border_width(10);
    $dialog->vbox->pack_start(new Gtk::Label($label),1,1,0);

    my $button = new Gtk::Button _("OK");
    $button->can_default(1);
    $button->signal_connect(clicked => sub { $ret = 1; $dialog->destroy(); Gtk->main_quit() });
    $dialog->action_area->pack_start($button, 1, 1, 0);
    $button->grab_default;

    if ($c) {
	my $button2 = new Gtk::Button _("Cancel");
	$button2->signal_connect(clicked => sub { $ret = 0; $dialog->destroy(); Gtk->main_quit() });
	$button2->can_default(1);
	$dialog->action_area->pack_start($button2, 1, 1, 0);
    }

    $dialog->show_all;
    Gtk->main();
    $ret;
}

# drakfloppy / logdrake
sub destroy_window {
	my($widget, $windowref, $w2) = @_;
	$$windowref = undef;
	$w2 = undef if defined $w2;
	0;
}

sub create_hbox { gtkset_layout(gtkset_border_width(new Gtk::HButtonBox, 3), $_[0] || 'spread') }

sub create_factory_menu_ {
    my ($type, $name, $window, @menu_items) = @_;
    my $widget = new Gtk::ItemFactory($type, $name, my $accel_group = new Gtk::AccelGroup);
    $widget->create_items(@menu_items);
    $window->add_accel_group($accel_group); #$accel_group->attach($main_win);
    $widget->get_widget($name); # return menu bar
}

sub create_factory_menu { create_factory_menu_('Gtk::MenuBar', '<main>', @_) }

sub create_menu {
    my $title = shift;
    my $w = new Gtk::MenuItem($title);
    $w->set_submenu(gtkshow(gtkappend(new Gtk::Menu, @_)));
    $w
}

sub create_notebook {
    my $n = new Gtk::Notebook;
    add2notebook($n, splice(@_, 0, 2)) while @_;
    $n
}

sub create_packtable {
    my ($options, @l) = @_;
    my $w = new Gtk::Table(0, 0, $options->{homogeneous} || 0);
    map_index {
	my ($i, $l) = ($_[0], $_);
	map_index {
	    my ($j) = @_;
	    if ($_) {
		ref $_ or $_ = new Gtk::Label($_);
		$j != $#$l ?
		  $w->attach($_, $j, $j + 1, $i, $i + 1, 'fill', 'fill', 5, 0) :
		  $w->attach($_, $j, $j + 1, $i, $i + 1, 1|4, ref($_) eq 'Gtk::ScrolledWindow' ? 1|4 : 0, 0, 0);
		$_->show;
	    }
	} @$l;
    } @l;
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    $w
}

sub createScrolledWindow {
    my ($W, $policy, $viewport_shadow) = @_;
    my $w = new Gtk::ScrolledWindow(undef, undef);
    $policy ||= [ 'automatic', 'automatic'];
    $w->set_policy(@{$policy});
    if (member(ref $W, qw(Gtk::CList Gtk::CTree Gtk::Text))) {
       $w->add($W)
    } else {
       $w->add_with_viewport($W);
       $viewport_shadow and gtkset_shadow_type($w->child, $viewport_shadow);
    }
    $W->can("set_focus_vadjustment") and $W->set_focus_vadjustment($w->get_vadjustment);
    $W->show;
    $w
}

sub create_treeitem {
    my ($name) = @_;
    
    my ($next_child, $left, $right, $up, $down);
    $next_child = sub {
	my ($c, $dir) = @_;
	my @childs = $c->parent->children;
	my $i; for ($i = 0; $i < @childs; $i++) { last if $childs[$i] == $c || $childs[$i]->subtree == $c }
	$i += $dir;
	0 <= $i && $i < @childs ? $childs[$i] : undef;
    };
    $left = sub { &$next_child($_[0]->parent, 0) };
    $right = sub { my ($c) = @_; $c->subtree and $c->expand, return ($c->subtree->children)[0]; $c };
    $down = sub {
	my ($c) = @_;
	return &$right($c) if ref $c eq "Gtk::TreeItem" && $c->subtree && $c->expanded;
	if (my $n = &$next_child($c, 1)) {
	    $n;
	} else {
	    return if ref $c->parent ne 'Gtk::Tree';	
	    &$down($c->parent);
	}
    };
    $up = sub {
	my ($c) = @_;
	if (my $n = &$next_child($c, -1)) {
	    $n = ($n->subtree->children)[-1] while ref $n eq "Gtk::TreeItem" && $n->subtree && $n->expanded;
	    $n;
	} else {
	    return if ref $c->parent ne 'Gtk::Tree';	
	    &$left($c);
	}
    };
    my $w = new Gtk::TreeItem($name);
    $w->signal_connect(key_press_event => sub {
        my (undef, $e) = @_;
        local $_ = chr ($e->{keyval});

	if ($e->{keyval} > 0x100) {
	    my $n;
	    $n = &$left($w)  if /[Q\xb4\x96]/;
	    $n = &$right($w) if /[S\xb6\x98]/;
	    $n = &$up($w)    if /[R\xb8\x97]/;
	    $n = &$down($w)  if /[T\xb2\x99]/;
	    if ($n) {
		$n->focus('up');
		$w->signal_emit_stop("key_press_event"); 
	    }
	    $w->expand if /[+\xab]/;
	    $w->collapse if /[-\xad]/;
	    do { 
		$w->expanded ? $w->collapse : $w->expand; 
		$w->signal_emit_stop("key_press_event"); 
	    } if /[\r\x8d]/;
	}
        1;
    });
    $w;
}

sub create_vbox { gtkset_layout(new Gtk::VButtonBox, $_[0] || 'spread') }

#-#######################
# public gtk routines
#-#######################

sub add2notebook {
    my ($n, $title, $book) = @_;
    my ($w1, $w2) = map { new Gtk::Label($_) } $title, $title;
    $book->{widget_title} = $w1;
    $n->append_page_menu($book, $w1, $w2);
    $book->show;
    $w1->show;
    $w2->show;
}


sub tree_set_icon {
    my ($node, $label, $icon) = @_;
    my $hbox = new Gtk::HBox(0,0);
    gtkpack__(1, $hbox, gtkshow(gtkpng($icon)), gtkshow(new Gtk::Label($label)));
    gtkadd($node, gtkshow($hbox));
}


sub ctree_set_icon {
    my ($tree, $node, $icon_pixmap, $icon_mask) = @_;

    my ($text, $spacing, undef, undef, undef, undef, $isleaf, $expanded) = $tree->get_node_info($node);
    $tree->set_node_info($node, $text, $spacing, $icon_pixmap, $icon_mask, $icon_pixmap, $icon_mask, $isleaf, $expanded);
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
    my $height_elem = $widget4style->style->font->ascent + $widget4style->style->font->descent;
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
	my $l = $widget4style->style->font->string_width($_ . (!$flag ? $wrap_char : ''));
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

sub gtkicons_labels_widget {
    my ($args, $w, $widget_for_font, $background,  $back_pixbuf, $x_back, $y_back, $x_round,
	$y_round, $x_back2, $y_back2, $icon_width, $icon_height, $exec_func, $exec_hash) = @_;

    my @tab;
    my $i = 0;
    my $cursor_hand = new Gtk::Gdk::Cursor 60;
    my $cursor_normal = new Gtk::Gdk::Cursor 68;
	my @args = @$args;
    foreach (@args) {
	my ($label, $tag) = ($_->[0], $_->[1]);
	die "$label 's icon is missing" unless $exec_hash->{$label};
	my ($dbl_area, $pix, $width, $height); # initialized in call back
	my $darea = new Gtk::DrawingArea;
	my ($icon, undef) = gtkcreate_png($tag);
	my $pixbuf = compose_with_back($tag, $back_pixbuf);
	my $pixbuf_h = compose_with_back($tag, $back_pixbuf, 170);

	my $draw = sub {
	    my ($widget, $event) = @_;
	    my ($dx, $dy) = ($darea->allocation->[2], $darea->allocation->[3]);
	    my $state = $darea->{state};
	    if (!defined($dbl_area)) {
		   ($pix, $width, $height) = create_pix_text($darea, $label, $widget_for_font->style->font, $x_round, 1,
										  1, 0, [$background, $background], $x_back2, $y_back2, 1, 0);
		   ($dx, $dy) = (max($width, $x_round), $y_round + $height);
		   $darea->set_usize($dx, $dy);
		   $dbl_area = new Gtk::Gdk::Pixmap($darea->window, max($width, $x_round), $y_round + $height);
	    }
	    # Redraw if state change (selected <=> not selected)
	    if (!$dbl_area->{state} || $state != $dbl_area->{state}) {
		   $dbl_area->{state} = $state;
		   fill_tiled($darea, $dbl_area, $background, $x_back2, $y_back2, $dx, $dy);
		   ($state ? $pixbuf_h : $pixbuf)
			  ->render_to_drawable($dbl_area, $darea->style->fg_gc('normal'), 0, 0, 0, 0,
							   $pixbuf->get_width, $pixbuf->get_height, 'normal', 0, 0);
		   $dbl_area->draw_pixmap($darea->style->bg_gc('normal'), ($state ? $pix->[1] : $pix->[0]),
							 0, 0, ($dx - $width)/2, $y_round, $width, $height);
	    }
	    $darea->window->draw_pixmap($darea->style->bg_gc('normal'), $dbl_area, 0, 0, 0, 0, $dx, $dy);
	    ($darea->{dx}, $darea->{dy}) = ($dx, $dy);

	};
	$darea->{state} = 0;
	$darea->signal_connect(expose_event => $draw);
	$darea->set_events(['exposure_mask', 'enter_notify_mask', 'leave_notify_mask', 'button_press_mask', 'button_release_mask' ]);
	$darea->signal_connect(enter_notify_event => sub {
				    if ($darea->{state} == 0) {
					$darea->{state} = 1;
					&$draw(@_);
				    }
				});
	$darea->signal_connect(leave_notify_event => sub {
				    if ($darea->{state} == 1) {
					$darea->{state} = 0;
					&$draw(@_);
				    }
				});
	$darea->signal_connect(button_release_event => sub {
				    $darea->{state} = 0;
				    $darea->draw(undef);
				    $exec_func->($tag, $exec_hash->{$label});
				});
	$darea->signal_connect(realize => sub { $darea->window->set_cursor($cursor_hand) });
	$tab[$i] = $darea;
	$i++;
    }
    my $fixed = new Gtk::Fixed;
    foreach (@tab) { $fixed->put($_, 75, 65) }
    my $w_ret = createScrolledWindow($fixed, undef, 'none');
    my $redraw_function;
    $redraw_function = sub { 
	$fixed->move(@$_) foreach compute_icons($fixed->allocation->[2]-22, $fixed->allocation->[3], 40, 15, 20, @tab);
    };
    $fixed->signal_connect(expose_event => $redraw_function);
    $fixed->signal_connect(realize => sub { $fixed->window->set_back_pixmap($background, 0) });
    $fixed->{redraw_function} = $redraw_function;

    $w_ret->vscrollbar->set_usize(19, undef);
    gtkhide($w_ret);
}

sub n_line_size {
    my ($nbline, $type, $widget) = @_;
    my $font = $widget->style->font;
    my $spacing = ${{ text => 0, various => 17 }}{$type};
    $nbline * ($font->ascent + $font->descent + $spacing) + 8;
}

sub write_on_pixmap {
    my ($pixmap, $x_pos, $y_pos, @text)=@_;
    my ($gdkpixmap, undef) = $pixmap->get();
    my ($width, $height) = (440, 250);
    my $gc = Gtk::Gdk::GC->new(gtkroot());
    $gc->set_foreground(gtkcolor(8448, 17664, 40191)); #- in hex : 33, 69, 157

    my $darea = new Gtk::DrawingArea();
    $darea->size($width, $height);
    $darea->set_usize($width, $height);
    my $draw = sub {
	my $style = new Gtk::Style;
	#- i18n : you can change the font.
	$style->font(Gtk::Gdk::Font->fontset_load(_("-adobe-times-bold-r-normal--17-*-100-100-p-*-iso8859-*,*-r-*")));
	my $y_pos2 = $y_pos;
  	foreach (@text) {
  	    $darea->window->draw_string($style->font, $gc, $x_pos, $y_pos2, $_);
  	    $y_pos2 += 20;
  	}
    };
    $darea->signal_connect(expose_event => sub { $darea->window->draw_rectangle($darea->style->white_gc, 1, 0, 0, $width, $height);
						 $darea->window->draw_pixmap
						   ($darea->style->white_gc,
						    $gdkpixmap, 0, 0,
						    ($darea->allocation->[2]-$width)/2, ($darea->allocation->[3]-$height)/2,
						    $width, $height);
						 &$draw();
					     });
    $darea;
}

#-#######################
# kind of private gtk routines
#-#######################

sub create_pix_text {
    #ref widget, txt, color_txt, [font], [width], [height], flag1, flag2, [ (background background_highlighted background_selecteded) backsize x y], centeredx, centeredy
    my ($w, $text, $font, $max_width, $max_height, $can_be_greater, $can_be_smaller, $backgrounds,  $x_back, $y_back, $centeredx, $centeredy) = @_;
    my $color_background;
    my $fake_darea = new Gtk::DrawingArea;
    my $style = $fake_darea->style->copy();
    if (ref($font) eq 'Gtk::Gdk::Font') {
	$style->font($font);
    } else {
	$font and $style->font(Gtk::Gdk::Font->fontset_load($font));
    }
    $fake_darea->set_style($style);
    my ($width, $height, $lines, $widths, $heights) = get_text_coord (
        $text, $fake_darea, $max_width, $max_height, $can_be_greater, $can_be_smaller, $centeredx, $centeredy);
    my $pix;
    my $j = 0;
    foreach (@$backgrounds) { 
	   $pix->[$j] = new Gtk::Gdk::Pixmap($w->window, $width, $height);
	   fill_tiled($w, $pix->[$j], $backgrounds->[$j], $x_back, $y_back, $width, $height);
	   $j++;
    }
    
    
    my $color_text = gtkcolor(0, 0, 0);
    my $gc_text = new Gtk::Gdk::GC($w->window);
    $gc_text->set_foreground($color_text);
    my $i = 0;
    foreach (@{$lines}) {
	$j = 0;
	foreach my $pix (@$pix) { 
	  $pix->draw_string($style->font, $gc_text, ${$widths}[$i], ${$heights}[$i], $_);
	  $pix->draw_string($style->font, $gc_text, ${$widths}[$i] + 1, ${$heights}[$i], $_) if $j;
	  $j++;
	}
	$i++;
    }
    ($pix, $width, $height);
}

sub gtkctree_children {
    my ($node) = @_;
    my @l;
    $node or return;
    for (my $p = $node->row->children; $p; $p = $p->row->sibling) {
	push @l, $p;
    }
    @l;
}




sub gtkpowerpack {
    #- Get Default Attributes (if any). 2 syntaxes allowed :
    #- gtkpowerpack( {expand => 1, fill => 0}, $box...) : the attributes are picked from a specified hash ref
    #- gtkpowerpack(1,0,1, $box, ...) : the attributes are picked from the non-ref list, in the order (expand, fill, padding, pack_end).
    my $RefDefaultAttrs;
    if (ref($_[0]) eq 'HASH') { $RefDefaultAttrs = shift }
    elsif (!ref($_[0])) {
	$RefDefaultAttrs = {};
	foreach ("expand", "fill", "padding", "pack_end") {
	    !ref($_[0]) ? $RefDefaultAttrs->{$_} = shift : last
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
	my %attr;
	my $RefAttrs;
	ref($_[0]) eq 'HASH' || ref($_[0]) eq 'ARRAY' and $RefAttrs = shift;
	foreach ("expand", "fill", "padding", "pack_end") {
	    if ($RefDefaultAttrs->{$_} eq 'arg') {
		ref ($_[0]) and die "error in packing definition\n";
		$attr{$_} = shift;
		ref($RefAttrs) eq 'ARRAY' and shift @$RefAttrs;
	    } elsif (ref($RefAttrs) eq 'HASH' && defined($RefAttrs->{$_})) {
		$attr{$_} = $RefAttrs->{$_};
	    } elsif (ref($RefAttrs) eq 'ARRAY') {
		$attr{$_} = shift @$RefAttrs;
	    } elsif (defined($RefDefaultAttrs->{$_})) {
		$attr{$_} = int $RefDefaultAttrs->{$_};
	    } else {
		$attr{$_} = 0;
	    }
	}
	#- Get and pack the widget (create it if necessary when it is a label...)
	my $widget = ref($_[0]) ? shift : new Gtk::Label(shift);
	if ($attr{pack_end}) { $box->pack_end($widget, $attr{expand}, $attr{fill}, $attr{padding})}
	else { $box->pack_start($widget, $attr{expand}, $attr{fill}, $attr{padding}) }
	$widget->show;
    }
    $box
}

sub gtkset_default_fontset {
    my ($fontset) = @_;
    my $style = Gtk::Widget->get_default_style;
    my $f = Gtk::Gdk::Font->fontset_load($fontset) or die '';
    $style->font($f);
    Gtk::Widget->set_default_style($style);
}

sub gtkcreate_imlib {
    my ($f) = shift;
    $f =~ m|.png$| or $f = "$f.png";
    if ($f !~ /\//) { -e "$_/$f" and $f = "$_/$f", last foreach icon_paths() }
    Gtk::Gdk::ImlibImage->load_image($f);
}

sub gtkxpm { new Gtk::Pixmap(gtkcreate_xpm(@_)) }
sub gtkpng { new Gtk::Pixmap(gtkcreate_png(@_)) }
sub gtkcreate_xpm {
    my ($f) = @_;
    my $rw = gtkroot();
    $f =~ m|.xpm$| or $f = "$f.xpm";
    if ($f !~ /\//) { -e "$_/$f" and $f = "$_/$f", last foreach icon_paths() }
    my @l = Gtk::Gdk::Pixmap->create_from_xpm($rw, new Gtk::Style->bg('normal'), $f) or die "gtkcreate_xpm: missing pixmap file $f";
    @l;
}

sub gtkcreate_png_pixbuf {
    my ($f) = shift;
    die 'gdk-pixbuf library is not available' unless ($use_pixbuf);
    $f =~ /\.(png|jpg)$/ or $f .= '.png';
    if ($f !~ /^\//) { -e "$_/$f" and $f = "$_/$f", last foreach icon_paths() }
    Gtk::Gdk::Pixbuf->new_from_file($f) or die "gtkcreate_png: missing png file $f";
}

sub gtkcreate_png {
    my ($f) = shift;
    $f =~ /\.png$/ or $f .= '.png';
    if ($f !~ /^\//) { -e "$_/$f" and $f = "$_/$f", last foreach icon_paths() }
    if ($use_imlib) {
	my $im = Gtk::Gdk::ImlibImage->load_image($f) or die "gtkcreate_png: missing png file $f";
	$im->render($im->rgb_width, $im->rgb_height);
	return ($im->move_image(), $im->move_mask);
    } elsif ($use_pixbuf) {
#	my $pixbuf = gtkcreate_png_pixbuf($f);
	my $pixbuf = Gtk::Gdk::Pixbuf->new_from_file($f) or die "gtkcreate_png: missing png file $f";
	my ($width, $height) = ($pixbuf->get_width(), $pixbuf->get_height);
	my $rw = gtkroot();
	my $pix = new Gtk::Gdk::Pixmap($rw, $width, $height, 16);
	$pixbuf->render_to_drawable_alpha($pix, 0, 0, 0, 0, $width, $height, 'bilevel', 127, 'normal', 0, 0);
 	my $bit = new Gtk::Gdk::Bitmap($rw, $width, $height, 1);
 	$pixbuf->render_threshold_alpha($bit, 0, 0, 0, 0, $width, $height, '127');
	return ($pix, $bit);
    } else {
	die "gtkcreate_png: cannot find a suitable library for rendering png (imlib1 or gdk_pixbuf)";
    }
}

sub compose_pixbufs {
    my ($pixbuf, $back_pixbuf_unaltered, $alpha_threshold) = @_;
    $alpha_threshold = 255 unless $alpha_threshold;
    my ($width, $height) = ($pixbuf->get_height, $pixbuf->get_width);
    my $back_pixbuf = Gtk::Gdk::Pixbuf->new('rgb', 0, 8, $height, $width);

    $back_pixbuf_unaltered->copy_area(0, 0, $height, $width, $back_pixbuf, 0, 0);
    $pixbuf->composite($back_pixbuf, 0, 0, $width, $height, 0, 0, 1, 1, 'nearest', $alpha_threshold);
    $back_pixbuf;
}

sub compose_with_back {
    my ($f, $back_pixbuf_unaltered, $alpha_threshold) = @_;
    compose_pixbufs(gtkcreate_png_pixbuf($f), $back_pixbuf_unaltered, $alpha_threshold);
}

sub xpm_d { my $w = shift; Gtk::Gdk::Pixmap->create_from_xpm_d($w->window, undef, @_) }

sub fill_tiled {
    my ($w, $pix, $bitmap, $x_back, $y_back, $width, $height) = @_;
    my ($x2, $y2) = (0, 0);
    while (1) {
	$x2 = 0;
	while (1) {
	    $pix->draw_pixmap($w->style->bg_gc('normal'),
			      $bitmap, 0, 0, $x2, $y2, $x_back, $y_back);
	    $x2 += $x_back;
	    $x2 >= $width and last;
	}
	$y2 += $y_back;
	$y2 >= $height and last;
    }
}

sub compute_icons {
    my ($fx, $fy, $decx, $decy, $interstice, @tab) = @_;
    my $nb = $#tab;
    my $nb_sav = $nb;
    my $index = 0;
    my @dx2;
    my @dx;
    my @dy;
    my $line_up = 0;
  bcl_init:
    @dx2 = undef;
  bcl:
    @dx = map{ $_->{dx} } @tab[$index..$index+$nb];
    $dy[$index] = max(map{ $_->{dy} } @tab[$index..$index+$nb]);
    foreach (0..$#dx) {
	if ($dx[$_] > $dx2[$_]) { $dx2[$_] = $dx[$_] } else { $dx[$_] = $dx2[$_] }
    }
    my $line_size = 0;
    $line_size = $decx + sum(@dx2) + $nb * $interstice;
    if ($line_size > $fx) {
	$index = 0; $nb--; goto bcl_init;
    }
    $nb and $line_up = ($fx-$line_size)/($nb+2);
    $index += $nb+1;
    $index <= $#tab and goto bcl;
    my @ret;
    my $n = 0;
    my $y = $decy;
    my $x = $decx/2 + $line_up;
    foreach (0..$nb_sav) {
	$ret[$_] = [$tab[$_], $x, $y];
	$x += $dx2[$n] + $interstice + $line_up;
	$n++;
	if ($n > $nb) {
	    $n = 0;
	    $x = $decx/2 + $line_up;
	    $y += int($dy[$_-$nb]/5)*5 + 15;
	}
    }
    @ret;
}

1;
