package my_gtk;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(create_window create_yesorno createScrolledWindow create_menu create_notebook create_packtable create_hbox create_adjustment mymain my_signal_connect mypack mypack_ myappend myadd label_align myset_usize myset_justify myshow mysync myflush mydestroy) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use Gtk;

1;


sub new {
    my ($type, $title, @opts) = @_;

    Gtk->init;
    parse Gtk::Rc "$ENV{HOME}/etc/any/Gtkrc";
    my $o = bless { @opts }, $type;
    $o->{window} = $o->create_window($title);
    $o;
}
sub destroy($) { 
    my ($o) = @_;
    $o->{window}->destroy;
    myflush();
}

sub ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = new Gtk::Entry;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk->main_quit };

    myadd($o->{window},
	  mypack($o->create_box_with_title(@msgs),
		 my_signal_connect($entry, 'activate' => $f),
		 ($o->{hide_buttons} ? () : mypack(new Gtk::HBox(0,0),
			my_signal_connect(new Gtk::Button('Ok'), 'clicked' => $f),
			my_signal_connect(new Gtk::Button('Cancel'), 'clicked' => sub { $o->{retval} = undef; Gtk->main_quit }),
			)),
		 ),
	  );
    $entry->grab_focus();
    mymain($o);
}


sub ask_from_list($\@$@) {
    my ($o, $l, @msgs) = @_;
    my $f = sub { $o->{retval} = $_[1]; Gtk->main_quit };
    my @l = map { my_signal_connect(new Gtk::Button($_), "clicked" => $f, $_) } @$l;

#    myadd($o->{window}, 
#	   mypack_(myset_usize(new Gtk::VBox(0,0), 0, 200),
#		   0, $o->create_box_with_title(@msgs), 
#		   1, createScrolledWindow(mypack(new Gtk::VBox(0,0), @l))));
    myadd($o->{window}, 
	  mypack($o->create_box_with_title(@msgs), @l));
   $l[0]->grab_focus();
    mymain($o)
}


sub ask_warn($@) {
    my ($o, @msgs) = @_;

    myadd($o->{window},
	  mypack($o->create_box_with_title(@msgs),
		 my_signal_connect(my $w = new Gtk::Button("Ok"), "clicked" => sub { Gtk->main_quit }),
		 ),
	  );
    $w->grab_focus();
    mymain($o)
}

sub ask_yesorno($@) {
    my ($o, @msgs) = @_;

    myadd($o->{window},
	  mypack(create_box_with_title($o, @msgs),
		 create_yesorno($o),
		 )
	 );
    $o->{ok}->grab_focus();
    mymain($o)
}

sub create_window($$) {
    my ($o, $title) = @_;
    $o->{window} = new Gtk::Window;
    $o->{window}->set_title($title);
    $o->{window}->signal_connect("delete_event" => sub { $o->{retval} = undef; Gtk->main_quit });
    $o->{window}
}

sub create_yesorno($) {
    my ($w) = @_;

    myadd(create_hbox(),
	  my_signal_connect($w->{ok} = new Gtk::Button("Ok"), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
	  my_signal_connect(new Gtk::Button("Cancel"), "clicked" => sub { $w->{retval} = 0; Gtk->main_quit }),
	 );
}

sub create_box_with_title($@) {
    my $o = shift;
    $o->{box} = mypack(new Gtk::VBox(0,0),
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
    $w->set_submenu(myshow(myappend(new Gtk::Menu, @_)));
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

sub mymain($) {
    my $o = shift;

    $o->{window}->show;
    Gtk->main;
    $o->{window}->destroy;
    myflush();
    $o->{retval}
}

sub my_signal_connect($@) {
    my $w = shift;
    $w->signal_connect(@_);
    $w
}

sub mypack($@) {
    my $box = shift;
    foreach (@_) {
	my $l = $_; 
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, 1, 1, 0);
	$l->show;
    }
    $box
}

sub mypack_($@) {
    my $box = shift;
    for (my $i = 0; $i < @_; $i += 2) {
	my $l = $_[$i + 1]; 
	ref $l or $l = new Gtk::Label($l);
	$box->pack_start($l, $_[$i], 1, 0);
	$_[$i + 1]->show;
    }
    $box
}

sub myappend($@) {
    my $w = shift;
    foreach (@_) { 
	my $l = $_; 
	ref $l or $l = new Gtk::Label($l);
	$w->append($l); 
	$l->show;
    }
    $w
}
sub myadd($@) {
    my $w = shift;
    foreach (@_) {
	my $l = $_; 
	ref $l or $l = new Gtk::Label($l);
	$w->add($l);
	$l->show;
    }
    $w
}
sub myshow($) { $_[0]->show; $_[0] }

sub mysync(;$) {
    my ($o) = @_;
    $o and $o->{window}->show;

    my $h = Gtk->idle_add(sub { Gtk->main_quit; 1 });
    map { Gtk->main } (1..4);
    Gtk->idle_remove($h);
}
sub myflush(;$) {
    Gtk->main_iteration while Gtk::Gdk->events_pending;
}



sub bigsize($) { $_[0]->{window}->set_usize(600,400); }
sub myset_usize($$$) { $_[0]->set_usize($_[1],$_[2]); $_[0] }
sub myset_justify($$) { $_[0]->set_justify($_[1]); $_[0] }
sub mydestroy($) { $_[0] and $_[0]->destroy }

sub label_align($$) {
    my $w = shift;
    local $_ = shift;
    $w->set_alignment(!/W/i, !/N/i);
    $w
}
