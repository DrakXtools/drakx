package interactive_gtk;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common);
use my_gtk qw(:helpers :wrappers);

1;

sub ask_from_listW {
    my ($o, $title, $messages, $l, $def) = @_;

    if (@$l < 5 && sum(map { length $_ } @$l) < 70) {
	my $w = my_gtk->new($title);
	my $f = sub { $w->{retval} = $_[1]; Gtk->main_quit };
	gtkadd($w->{window},
	       gtkpack(create_box_with_title($o, @$messages),
		       gtkadd((@$l < 3 ? create_hbox() : create_vbox()),
			      map {
				  my $b = new Gtk::Button($_);
				  $b->signal_connect(clicked => [ $f, $_ ]);
				  $_ eq $def and $def = $b;
				  $b;
			      } @$l),
		       ),
	       );
	$def->grab_focus if $def;
	$w->main;
    } else {
	my_gtk::ask_from_list($title, $messages, $l, $def);
    }
}
