package my_gtk;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(ask_warn ask_okcancel ask_yesorno ask_from_entry ask_from_list create_okcancel createScrolledWindow create_menu create_notebook create_packtable create_hbox create_adjustment gtksignal_connect gtkpack gtkpack_ gtkappend gtkadd gtkset_usize gtkset_justify gtkshow gtkdestroy) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use Gtk;
use c;

1;

################################################################################
# OO stuff
################################################################################
sub new {
    my ($type, $title, @opts) = @_;

    Gtk->init;
    parse Gtk::Rc "$ENV{HOME}/etc/any/Gtkrc";
    my $o = bless { @opts }, $type;
    $o->{window} = $o->_create_window($title);
    $o;
}
sub main($;$) {
    my ($o, $f) = @_;
    $o->show;
    do { Gtk->main } while ($o->{retval} && $f && !&$f());
    $o->destroy;
    $o->{retval}
}
sub show($) {
    my ($o) = @_;
    $o->{window}->show;
}
sub destroy($) { 
    my ($o) = @_;
    $o->{window}->destroy;
    flush();
}
sub sync($) {
    my ($o) = @_;
    $o->{window}->show;

    my $h = Gtk->idle_add(sub { Gtk->main_quit; 1 });
    map { Gtk->main } (1..4);
    Gtk->idle_remove($h);
}
sub flush(;$) {
    Gtk->main_iteration while Gtk::Gdk->events_pending;
}
sub bigsize($) { 
    $_[0]->{window}->set_usize(600,400); 
}


sub gtkshow($) { $_[0]->show; $_[0] }
sub gtkdestroy($) { $_[0] and $_[0]->destroy }
sub gtkset_usize($$$) { $_[0]->set_usize($_[1],$_[2]); $_[0] }
sub gtkset_justify($$) { $_[0]->set_justify($_[1]); $_[0] }

sub gtksignal_connect($@) {
    my $w = shift;
    $w->signal_connect(@_);
    $w
}
sub gtkpack($@) {
    my $box = shift;
    foreach (@_) {
	my $l = $_; 
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, 1, 1, 0);
	$l->show;
    }
    $box
}
sub gtkpack_($@) {
    my $box = shift;
    for (my $i = 0; $i < @_; $i += 2) {
	my $l = $_[$i + 1]; 
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, $_[$i], 1, 0);
	$_[$i + 1]->show;
    }
    $box
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




################################################################################
# createXXX functions

# these functions return a widget
################################################################################

sub create_okcancel($;$$) {
    my ($w, $ok, $cancel) = @_;

    gtkadd(create_hbox(),
	  gtksignal_connect($w->{ok} = new Gtk::Button($ok || "Ok"), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
	  gtksignal_connect(new Gtk::Button($cancel || "Cancel"), "clicked" => sub { $w->{retval} = 0; Gtk->main_quit }),
	 );
}

sub create_box_with_title($@) {
    my $o = shift;
    $o->{box} = gtkpack(new Gtk::VBox(0,0),
		       map({ new Gtk::Label("  $_  ") } @_),
		       new Gtk::HSeparator,
		       )
}

sub createScrolledWindow($) {
    my $w = new Gtk::ScrolledWindow(undef, undef);
    $w->set_policy('automatic', 'automatic');
    $w->add_with_viewport($_[0]);
    $_[0]->show;
    $w
}

sub create_menu($@) {
    my $title = shift;
    my $w = new Gtk::MenuItem($title);
    $w->set_submenu(gtkshow(gtkappend(new Gtk::Menu, @_)));
    $w
}

sub create_notebook(@) {
    my $n = new Gtk::Notebook;
    while (@_) {
	my $title = shift;
	my $book = shift;

	my ($w1, $w2) = map { new Gtk::Label($_) } $title, $title;
	$n->append_page_menu($book, $w1, $w2);
	$book->show;
	$w1->show;
	$w2->show;
    }
    $n
}

sub create_adjustment($$$) {
    my ($val, $min, $max) = @_;
    new Gtk::Adjustment($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_packtable($@) {
    my $options = shift;
    my $w = new Gtk::Table(0, 0, $options->{homogeneous} || 0);
    my $i = 0; foreach (@_) {
	for (my $j = 0; $j < @$_; $j++) {
	    if (defined $_->[$j]) {
		my $l = $_->[$j]; 
		ref $l or $l = new Gtk::Label($l);
		$w->attach_defaults($l, $j, $j + 1, $i, $i + 1);
		$l->show;
	    }
	}
	$i++;
    }
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    $w
}

sub create_hbox {
    my $w = new Gtk::HButtonBox;
    $w->set_layout(-spread);
    $w;
}


sub _create_window($$) {
    my ($o, $title) = @_;
    $o->{window} = new Gtk::Window;
    $o->{window}->set_title($title);
    $o->{window}->signal_connect("expose_event" => sub { c::XSetInputFocus($o->{window}->window->XWINDOW) }) if $my_gtk::force_focus; 
    $o->{window}->signal_connect("delete_event" => sub { $o->{retval} = undef; Gtk->main_quit });
    $o->{window}
}




################################################################################
# ask_XXX

# just give a title and some args, and it will return the value given by the user
################################################################################

sub ask_warn       { my $w = my_gtk->new(shift @_); $w->_ask_warn(@_); main($w); }
sub ask_yesorno    { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, "Yes", "No"); main($w); }
sub ask_okcancel   { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, "Is it ok?", "Ok", "Cancel"); main($w); }
sub ask_from_entry { my $w = my_gtk->new(shift @_); $w->_ask_from_entry(@_); main($w); }
sub ask_from_list  { my $w = my_gtk->new(shift @_); $w->_ask_from_list(pop @_, @_); main($w); }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = new Gtk::Entry;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk->main_quit };

    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect($entry, 'activate' => $f),
		 ($o->{hide_buttons} ? () : gtkpack(new Gtk::HBox(0,0),
			gtksignal_connect(new Gtk::Button('Ok'), 'clicked' => $f),
			gtksignal_connect(new Gtk::Button('Cancel'), 'clicked' => sub { $o->{retval} = undef; Gtk->main_quit }),
			)),
		 ),
	  );
    $entry->grab_focus();
}
sub _ask_from_list($\@$@) {
    my ($o, $l, @msgs) = @_;
    my $f = sub { $o->{retval} = $_[1]; Gtk->main_quit };
    my $list = new Gtk::List();
    map { gtksignal_connect(gtkadd($list, new Gtk::ListItem($_)), selection_changed => $f, $_) } @$l;

#    myadd($o->{window}, 
#	   mypack_(myset_usize(new Gtk::VBox(0,0), 0, 200),
#		   0, $o->create_box_with_title(@msgs), 
#		   1, createScrolledWindow(mypack(new Gtk::VBox(0,0), @l))));
    gtkadd($o->{window}, gtkpack($o->create_box_with_title(@msgs), $list));
}

sub _ask_warn($@) {
    my ($o, @msgs) = @_;
    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect(my $w = new Gtk::Button("Ok"), "clicked" => sub { Gtk->main_quit }),
		 ),
	  );
    $w->grab_focus();
}

sub _ask_okcancel($@) {
    my ($o, @msgs) = @_;
    my ($ok, $cancel) = splice @msgs, -2;

    gtkadd($o->{window},
	   gtkpack(create_box_with_title($o, @msgs),
		   create_okcancel($o, $ok, $cancel),
		 )
	 );
    $o->{ok}->grab_focus();
}


################################################################################
# rubbish
################################################################################

#sub label_align($$) {
#    my $w = shift;
#    local $_ = shift;
#    $w->set_alignment(!/W/i, !/N/i);
#    $w
#}
