#-########################################################################
#- Pixel's implementation of Perl-GTK  :-)  [DDX]
#-########################################################################
package my_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $border);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    helpers => [ qw(create_okcancel createScrolledWindow create_menu create_notebook create_packtable create_hbox create_vbox create_adjustment create_box_with_title create_treeitem) ],
    wrappers => [ qw(gtksignal_connect gtkpack gtkpack_ gtkpack__ gtkpack2 gtkpack3 gtkpack2_ gtkpack2__ gtksetstyle gtkappend gtkadd gtkput gtktext_insert gtkset_usize gtkset_justify gtkset_active gtkshow gtkdestroy gtkset_mousecursor gtkset_mousecursor_normal gtkset_mousecursor_wait gtkset_background gtkset_default_fontset gtkctree_children gtkxpm gtkpng gtkcreate_xpm gtkcreate_png) ],
    ask => [ qw(ask_warn ask_okcancel ask_yesorno ask_from_entry ask_file) ],
);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use Gtk;
use Gtk::Gdk::ImlibImage;
use c;
use log;
use common qw(:common :functional :file);

my $forgetTime = 1000; #- in milli-seconds
$border = 5;

1;

#-###############################################################################
#- OO stuff
#-###############################################################################
sub new {
    my ($type, $title, %opts) = @_;

    Gtk->init;
    init Gtk::Gdk::ImlibImage;
    Gtk->set_locale;
    my $o = bless { %opts }, $type;
    $o->_create_window($title);
    while (my $e = shift @tempory::objects) { $e->destroy }
    push @interactive::objects, $o unless $opts{no_interactive_objects};
    $o->{rwindow}->set_position('center_always') if $::isStandalone;
    $o->{rwindow}->set_modal(1) if $my_gtk::grab || $o->{grab};

    if ($::isWizard) {
	my $rc = "/etc/gtk/wizard.rc";
	-r $rc or $rc = dirname(__FILE__) . "/wizard.rc";
	Gtk::Rc->parse($rc);
	$o->{window} = new Gtk::VBox(0,0);
	$o->{window}->set_border_width(10);
	$o->{rwindow} = $o->{window};
	if (!defined($::WizardWindow)) {
	    $::WizardWindow = new Gtk::Window;
	    $::WizardWindow->set_position('center_always');
	    $::WizardTable = new Gtk::Table(2, 2, 0);
	    $::WizardWindow->add($::WizardTable);
	    my $draw1 = new Gtk::DrawingArea;
	    $draw1->set_usize(50,50);
	    my $draw2 = new Gtk::DrawingArea;
	    $draw1->set_usize(50,50);
	    my $draw3 = new Gtk::DrawingArea;
	    $draw1->set_usize(50,50);
	    $::WizardTable->attach($draw1, 0, 1, 0, 1, 'fill', 'fill', 0, 0);
	    $::WizardTable->attach($draw2, 0, 1, 1, 2, 'fill', 'fill', 0, 0);
	    $::WizardTable->attach($draw3, 1, 2, 0, 1, 'fill', 'fill', 0, 0);
	    $::WizardWindow->show_all;
	    flush();
	}
	$::WizardTable->attach($o->{window}, 1, 2, 1, 2, {'fill', 'expand'}, {'fill', 'expand'}, 0, 0);
    }

    $::isEmbedded or return $o;
    $o->{window} = new Gtk::VBox(0,0);
    $o->{rwindow} = $o->{window};
    defined($::Plug) or $::Plug = new Gtk::Plug ($::XID);
    $::Plug->show;
    flush();
    $::Plug->add($o->{window});
    $o;
}
sub main {
    my ($o, $completed, $canceled) = @_;
    gtkset_mousecursor_normal();
    my $timeout = Gtk->timeout_add(1000, sub { gtkset_mousecursor_normal(); 1 });
    my $b = before_leaving { Gtk->timeout_remove($timeout) };
    $o->show;

    do {
	local $::setstep = 1;
	Gtk->main;
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
    $o->{rwindow}->destroy;
    gtkset_mousecursor_wait();
    flush();
}
sub DESTROY { goto &destroy }
sub sync($) {
    my ($o) = @_;
    show($o);
    flush();
}
sub flush {
    Gtk->main_iteration while Gtk->events_pending;
}

sub gtkshow($)         { $_[0]->show; $_[0] }
sub gtkdestroy($)      { $_[0] and $_[0]->destroy }
sub gtkset_usize($$$)  { $_[0]->set_usize($_[1],$_[2]); $_[0] }
sub gtkset_justify($$) { $_[0]->set_justify($_[1]); $_[0] }
sub gtkset_active($$)  { $_[0]->set_active($_[1]); $_[0] }

sub gtksignal_connect($@) {
    my $w = shift;
    $w->signal_connect(@_);
    $w
}
sub gtkpack($@) {
    my $box = shift;
    gtkpack_($box, map {; 1, $_ } @_);
}
sub gtkpack__($@) {
    my $box = shift;
    gtkpack_($box, map {; 0, $_ } @_);
}
sub gtkpack_($@) {
    my $box = shift;
    for (my $i = 0; $i < @_; $i += 2) {
	my $l = $_[$i + 1];
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, $_[$i], 1, 0);
	$l->show;
    }
    $box
}
sub gtkpack2($@) {
    my $box = shift;
    gtkpack2_($box, map {; 1, $_ } @_);
}
sub gtkpack2__($@) {
    my $box = shift;
    gtkpack2_($box, map {; 0, $_ } @_);
}
sub gtkpack3 {
    my $a = shift;
    $a && goto \&gtkpack2__;
    goto \&gtkpack2;
}
sub gtkpack2_($@) {
    my $box = shift;
    for (my $i = 0; $i < @_; $i += 2) {
	my $l = $_[$i + 1];
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, $_[$i], 0, 0);
	$l->show;
    }
    $box
}
sub gtksetstyle {
    my ($w, $s) = @_;
    $w->set_style($s);
    $w;
}

sub gtkappend($@) {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = new Gtk::Label($l);
	$w->append($l);
	$l->show;
    }
    $w
}
sub gtkadd($@) {
    my $w = shift;
    foreach (@_) {
	my $l = $_;
	ref $l or $l = new Gtk::Label($l);
	$w->add($l);
	$l->show;
    }
    $w
}
sub gtkput {
    my ($w, $w2, $x, $y) = @_;
    $w->put($w2, $x, $y);
    $w2->show;
    $w
}

sub gtktext_insert {
    my ($w, $t) = @_;
    $w->freeze;
    $w->backward_delete($w->get_length);
    $w->insert(undef, undef, undef, $t); 
    #- DEPRECATED? needs \n otherwise in case of one line text the beginning is not shown (even with the vadj->set_value)
    $w->set_word_wrap(1);
#-    $w->vadj->set_value(0);
    $w->thaw;
    $w;
}

sub gtkroot {
    Gtk->init;
    Gtk->set_locale;
    Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW);
}

sub gtkcolor($$$) {
    my ($r, $g, $b) = @_;

    my $color = bless { red => $r, green => $g, blue => $b }, 'Gtk::Gdk::Color';
    gtkroot()->get_colormap->color_alloc($color);
}

sub gtkset_mousecursor {
    my ($type, $w) = @_;
    ($w || gtkroot())->set_cursor(Gtk::Gdk::Cursor->new($type));
}
sub gtkset_mousecursor_normal { gtkset_mousecursor(68, @_) }
sub gtkset_mousecursor_wait   { gtkset_mousecursor(150, @_) }

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

sub gtkset_default_fontset {
    my ($fontset) = @_;

    my $style = Gtk::Widget->get_default_style;
    my $f = Gtk::Gdk::Font->fontset_load($fontset) or die '';
    $style->font($f);
    Gtk::Widget->set_default_style($style);
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

sub gtkcreate_xpm {
    my ($w, $f) = @_;
    my @l = Gtk::Gdk::Pixmap->create_from_xpm($w->window, $w->style->bg('normal'), $f) or die "gtkcreate_xpm: missing pixmap file $f";
    @l;
}
sub gtkcreate_png {
    my ($f) = @_;
    my $im = load_image Gtk::Gdk::ImlibImage("$f");
    $im->render($im->rgb_width, $im->rgb_height);
    ($im->move_image(), $im->move_mask);
}
sub xpm_d { my $w = shift; Gtk::Gdk::Pixmap->create_from_xpm_d($w->window, undef, @_) }
sub gtkxpm { new Gtk::Pixmap(gtkcreate_xpm(@_)) }
sub gtkpng { new Gtk::Pixmap (gtkcreate_png(@_)) }
#-###############################################################################
#- createXXX functions

#- these functions return a widget
#-###############################################################################

sub create_okcancel {
    my ($w, $ok, $cancel, $spread, @other) = @_;
    my $one = ($ok xor $cancel);
    $spread ||= $::isWizard ? "end" : "spread";
    $ok ||= _("Ok");
    $::isWizard and $ok = _("Next ->");
    my $b1 = gtksignal_connect($w->{ok} = new Gtk::Button($ok), clicked => $w->{ok_clicked} || sub { $w->{retval} = 1; Gtk->main_quit });
    my $b2 = !$one && gtksignal_connect($w->{cancel} = new Gtk::Button($cancel || _("Cancel")), clicked => $w->{cancel_clicked} || sub { log::l("default cancel_clicked"); undef $w->{retval}; Gtk->main_quit });
    $::isWizard and my $b3 = gtksignal_connect($w->{previous} = new Gtk::Button(_("<- Previous")), clicked => $w->{previous_clicked} || sub { log::l("default previous_clicked"); $w->{retval} = -1; Gtk->main_quit });
    my @l = grep { $_ } $::isWizard ? ($b2, $b3, $b1): ($b1, $b2);
    push @l, map { gtksignal_connect(new Gtk::Button($_->[0]), clicked => $_->[1]) } @other;

    $_->can_default($::isWizard) foreach @l;
    gtkadd(create_hbox($spread), @l);
}

sub create_box_with_title($@) {
    my $o = shift;

    my $nb_lines = map { split "\n" } @_;
    $o->{box} = new Gtk::VBox(0,0);
    if (@_ <= 2 && $nb_lines > 4) {
	my $font = $o->{box}->style->font;
	chomp(my $text = join("\n", @_));
	my $scroll = createScrolledWindow(gtktext_insert(new Gtk::Text, $text));
	$scroll->set_usize(400, min(250, $nb_lines * ($font->ascent + $font->descent) + 7));
	gtkpack__($o->{box}, $scroll);
    } else {
	gtkpack__($o->{box},
		  (map {
		      my $w = ref $_ ? $_ : new Gtk::Label($_);
		      $w->set_name("Title");
		      $w;
		  } map { ref $_ ? $_ : warp_text($_) } @_),
		  new Gtk::HSeparator,
		 );
    }
}

sub createScrolledWindow {
    my ($W) = @_;
    my $w = new Gtk::ScrolledWindow(undef, undef);
    $w->set_policy('automatic', 'automatic');
    member(ref $W, qw(Gtk::CList Gtk::CTree Gtk::Text)) ?
      $w->add($W) :
      $w->add_with_viewport($W);
    $W->can("set_focus_vadjustment") and $W->set_focus_vadjustment($w->get_vadjustment);
    $W->show;
    $w
}

sub create_menu($@) {
    my $title = shift;
    my $w = new Gtk::MenuItem($title);
    $w->set_submenu(gtkshow(gtkappend(new Gtk::Menu, @_)));
    $w
}

sub add2notebook {
    my ($n, $title, $book) = @_;

    my ($w1, $w2) = map { new Gtk::Label($_) } $title, $title;
    $book->{widget_title} = $w1;
    $n->append_page_menu($book, $w1, $w2);
    $book->show;
    $w1->show;
    $w2->show;
}

sub create_notebook(@) {
    my $n = new Gtk::Notebook;
    add2notebook($n, splice(@_, 0, 2)) while @_;
    $n
}

sub create_adjustment($$$) {
    my ($val, $min, $max) = @_;
    new Gtk::Adjustment($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_packtable($@) {
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
		  $w->attach_raw($_, $j, $j + 1, $i, $i + 1, 1|5, ref($_) eq 'Gtk::ScrolledWindow' ? 1|5 : 0, 0, 0);
		$_->show;
	    }
	} @$l;
    } @l;
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    $w
}

sub create_hbox {
    my $w = new Gtk::HButtonBox;
    $w->set_layout($_[0] || "spread");
    $w;
}
sub create_vbox {
    my $w = new Gtk::VButtonBox;
    $w->set_layout(-spread);
    $w;
}


sub _create_window($$) {
    my ($o, $title) = @_;
    my $w = new Gtk::Window;
    my $f = new Gtk::Frame(undef);
    $w->set_name("Title");
    gtkadd($w, $f);

    $w->set_title($title);

    $w->signal_connect(expose_event => sub { c::XSetInputFocus($w->window->XWINDOW); }) if $my_gtk::force_focus || $o->{force_focus};
    $w->signal_connect(delete_event => sub { undef $o->{retval}; Gtk->main_quit });
    $w->set_uposition(@{$my_gtk::force_position || $o->{force_position}}) if $my_gtk::force_position || $o->{force_position};

    $w->signal_connect(focus => sub { Gtk->idle_add(sub { $w->ensure_focus($_[0]); 0 }, $_[1]) }) if $w->can('ensure_focus');

    if ($::o->{mouse}{unsafe}) {
	$w->set_events("pointer_motion_mask");
	my $signal;
	$signal = $w->signal_connect(motion_notify_event => sub {
	    delete $::o->{mouse}{unsafe};
	    log::l("unsetting unsafe mouse");
	    $w->signal_disconnect($signal);
	});
    }
    $w->signal_connect(key_press_event => sub {
	my $d = ${{ 65470 => 'help',
	            65481 => 'next',
		    65480 => 'previous' }}{$_[1]{keyval}};

	if ($d eq "help") {
	    require install_gtk;
	    install_gtk::create_big_help($::o);
	} elsif (chr($_[1]{keyval}) eq 'e' && $_[1]{state} & 8) {
	    log::l("Switching to " . ($::expert ? "beginner" : "expert"));
	    $::expert = !$::expert;
	} elsif ($d) {
	    #- previous field is created here :(
	    my $s; foreach (reverse @{$::o->{orderedSteps}}) {
		$s->{previous} = $_ if $s;
		$s = $::o->{steps}{$_};
	    }
	    $s = $::o->{step};
	    do { $s = $::o->{steps}{$s}{$d} } until !$s || $::o->{steps}{$s}{reachable};
	    $::setstep && $s and die "setstep $s\n";
	}
    });# if $::isInstall;

    $w->signal_connect(size_allocate => sub {
	my ($wi, $he) = @{$_[1]}[2,3];
	my ($X, $Y, $Wi, $He) = @{$my_gtk::force_center || $o->{force_center}};
        $w->set_uposition(max(0, $X + ($Wi - $wi) / 2), max(0, $Y + ($He - $he) / 2));
    }) if ($my_gtk::force_center || $o->{force_center}) && !($my_gtk::force_position || $o->{force_position}) ;

    $o->{window} = $f;
    $o->{rwindow} = $w;
}

my ($next_child, $left, $right, $up, $down);
{
    my $next_child = sub {
	my ($c, $dir) = @_;

	my @childs = $c->parent->children;
   
	my $i; for ($i = 0; $i < @childs; $i++) {
	    last if $childs[$i] == $c || $childs[$i]->subtree == $c;
	}
	$i += $dir;
	0 <= $i && $i < @childs ? $childs[$i] : undef;
    };
    $left = sub { &$next_child($_[0]->parent, 0); };
    $right = sub {
	my ($c) = @_;
	if ($c->subtree) {
	    $c->expand;
	    ($c->subtree->children)[0];
	} else {
	    $c;
	}
    };
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
}

sub create_treeitem($) {
    my ($name) = @_;
    
    my $w = new Gtk::TreeItem($name);
    $w->signal_connect(key_press_event => sub {
        my (undef, $e) = @_;
        local $_ = chr ($e->{keyval});

	if ($e->{keyval} > 0x100) {
	    my $n;
	    $n = &$left($w)  if /[Q�\x96]/;
	    $n = &$right($w) if /[S�\x98]/;
	    $n = &$up($w)    if /[R�\x97]/;
	    $n = &$down($w)  if /[T�\x99]/;
	    if ($n) {
		$n->focus('up');
		$w->signal_emit_stop("key_press_event"); 
	    }
	    $w->expand if /[+�]/;
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



#-###############################################################################
#- ask_XXX

#- just give a title and some args, and it will return the value given by the user
#-###############################################################################

sub ask_warn       { my $w = my_gtk->new(shift @_); $w->_ask_warn(@_); main($w); }
sub ask_yesorno    { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, _("Yes"), _("No")); main($w); }
sub ask_okcancel   { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, _("Is this correct?"), _("Ok"), _("Cancel")); main($w); }
sub ask_from_entry { my $w = my_gtk->new(shift @_); $w->_ask_from_entry(@_); main($w); }
sub ask_file       { my $w = my_gtk->new(''); $w->_ask_file(@_); main($w); }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = new Gtk::Entry;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk->main_quit };
    $o->{ok_clicked} = $f;
    $o->{cancel_clicked} = sub { undef $o->{retval}; Gtk->main_quit };

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
		 gtksignal_connect(my $w = new Gtk::Button(_("Ok")), "clicked" => sub { Gtk->main_quit }),
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


sub _ask_file($$) {
    my ($o, $title) = @_;
    my $f = $o->{rwindow} = new Gtk::FileSelection $title;
    $f->ok_button->signal_connect(clicked => sub { $o->{retval} = $f->get_filename ; Gtk->main_quit });
    $f->cancel_button->signal_connect(clicked => sub { Gtk->main_quit });
    $f->hide_fileop_buttons;
}

#-###############################################################################
#- rubbish
#-###############################################################################

#-sub label_align($$) {
#-    my $w = shift;
#-    local $_ = shift;
#-    $w->set_alignment(!/W/i, !/N/i);
#-    $w
#-}

