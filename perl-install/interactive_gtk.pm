package interactive_gtk;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common :functional);
use my_gtk qw(:helpers :wrappers);

1;

## redefine ask_warn
#sub ask_warn {
#    my $o = shift;
#    local $my_gtk::grab = 1;
#    $o->SUPER::ask_warn(@_);
#}

sub ask_from_entryW {
    my ($o, $title, $messages, $def) = @_;
    my $w = my_gtk->new($title, %$o);
    $w->_ask_from_entry(@$messages);
    $w->main;
}
sub ask_from_listW {
    my ($o, $title, $messages, $l, $def) = @_;

    if (@$l < 5 && sum(map { length $_ } @$l) < 70) {
	my $w = my_gtk->new($title, %$o);
	my $f = sub { $w->{retval} = $_[1]; Gtk->main_quit };
	gtkadd($w->{window},
	       gtkpack(create_box_with_title($w, @$messages),
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
	my $w = my_gtk->new($title);
	$w->_ask_from_list($messages, $l, $def);
	$w->main;
    }
}

sub ask_many_from_list_refW($$$$$) {
    my ($o, $title, $messages, $list, $val) = @_;
    my $n = 0;
    my $w = my_gtk->new('', %$o);
    gtkadd($w->{window}, 
	   gtkpack(create_box_with_title($w, @$messages),
		   gtkpack(new Gtk::VBox(0,0),
			   map { 
			       my $nn = $n++; 
			       my $o = Gtk::CheckButton->new($_);
			       $o->set_active(${$val->[$nn]});
			       $o->signal_connect(clicked => sub { ${$val->[$nn]} = !${$val->[$nn]} });
			       $o;
			   } @$list),
		   $w->create_okcancel,
		  )
	  );
    $w->{ok}->grab_focus;
    $w->main && $val;
}


sub ask_from_entries_refW {
    my ($o, $title, $messages, $l, $val, %hcallback) = @_;
    my $num_champs = @{$l};
    my $ignore = 0;

    my $w       = my_gtk->new($title, %$o);
    my @entries = map { new Gtk::Entry } @{$l};
    my $ok      = $w->create_okcancel;

    my @updates = mapn { 
	my ($entry, $ref) = @_;
	return sub { ${$ref} = $entry->get_text };
    } \@entries, $val;

    my @updates_inv = mapn { 
	my ($entry, $ref) = @_;
	sub { $entry->set_text(${$ref})
	};
    } \@entries, $val;


    for (my $i = 0; $i < $num_champs; $i++) {
	my $ind = $i;
	my $callback = sub {
	    return if $ignore; #handle recursive deadlock
	    &{$updates[$ind]};
	    if ($hcallback{changed}) {
		&{$hcallback{changed}}($ind);
		#update all the value
		$ignore = 1;
		foreach (@updates_inv) { &{$_};}
		$ignore = 0;
	    }
	};
	my $entry = $entries[$i];
	$entry->signal_connect(changed => $callback);
	$entry->signal_connect(activate => sub {
				   ($ind == ($num_champs -1)) ?
				     $w->{ok}->grab_focus() : $entries[$ind+1]->grab_focus();
			       });
	$entry->set_text(${$val->[$i]})  if ${$val->[$i]};
	$entry->set_visibility(0) if $_[0] =~ /password/i;
#	&{$updates[$i]};
    }
    my @entry_list = mapn { [($_[0], $_[1])]} $l, \@entries;
    gtkadd($w->{window}, 
	   gtkpack(
		   create_box_with_title($w, @$messages),
		   create_packtable({}, @entry_list),
		   $ok
		   ));
    
    $entries[0]->grab_focus();
    $w->main();
}


sub wait_messageW($$$) {
    my ($o, $title, $message) = @_;

    my $w = my_gtk->new(_("Resizing"), %$o, grab => 1);
    my $W = pop @$message;
    gtkadd($w->{window}, 
	   gtkpack(new Gtk::VBox(0,0), 
		   @$message, 
		   $w->{wait_messageW} = new Gtk::Label($W)));
    $w->sync;
    $w;
}
sub wait_message_nextW {
    my ($o, $message, $w) = @_;
    $w->{wait_messageW}->set($message);
    $w->sync;
}
sub wait_message_endW {
    my ($o, $w) = @_;
    $w->destroy;
}
