package interactive_gtk;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common :functional);
use my_gtk qw(:helpers :wrappers);

1;

#-#- redefine ask_warn
#-sub ask_warn {
#-    my $o = shift;
#-    local $my_gtk::grab = 1;
#-    $o->SUPER::ask_warn(@_);
#-}

sub ask_from_entryW {
    my ($o, $title, $messages, $def) = @_;
    my $w = my_gtk->new($title, %$o);
    $w->_ask_from_entry(@$messages);
    $w->main;
}
sub ask_from_listW {
    my ($o, $title, $messages, $l, $def) = @_;

    my $w = my_gtk->new($title, %$o);
    $w->{retval} = $def || $l->[0]; #- nearly especially for the X test case (see timeout in Xconfigurator.pm)
    if (@$l < 5 && sum(map { length $_ } @$l) < 70) {
	my $defW;
	my $f = sub { $w->{retval} = $_[1]; Gtk->main_quit };
	gtkadd($w->{window},
	       gtkpack(create_box_with_title($w, @$messages),
		       gtkadd((@$l < 3 ? create_hbox() : create_vbox()),
			      map {
				  my $b = new Gtk::Button($_);
				  $b->signal_connect(clicked => [ $f, $_ ]);
				  $_ eq $def and $defW = $b;
				  $b;
			      } @$l),
		       ),
	       );
	$defW->grab_focus if $defW;
	$w->main;
    } else {
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
    my $num_fields = @{$l};
    my $ignore = 0; #-to handle recursivity

    my $w = my_gtk->new($title, %$o);
    #-the widgets
    my @widgets = map {
	if ($_->{type} eq "list") {
	    my $w = new Gtk::Combo;
	    $w->set_use_arrows_always(1);
	    $w->entry->set_editable(!$_->{not_edit});
	    $w->set_popdown_strings(@{$_->{list}});
	    $w->disable_activate;
	    $_->{val} ||= $_->{list}[0];
	    $w;
	} elsif ($_->{type} eq "bool") {
	    my $w = Gtk::CheckButton->new($_->{text});
	    $w->set_active(${$_->{val}});
	    my $i = $_; $w->signal_connect(clicked => sub { $ignore or ${$i->{val}} = !${$i->{val}} });
	    $w;
	} else {
	    new Gtk::Entry;
	}
    } @{$val};
    my $ok      = $w->create_okcancel;

    sub widget {
	my ($w, $ref) = @_;
	($ref->{type} eq "list" && @{$ref->{list}}) ? $w->entry : $w
    }
    my @updates = mapn {
	my ($w, $ref) = @_;
	sub {
	    $ref->{type} eq "bool" and return;
	    ${$ref->{val}} = widget($w, $ref)->get_text;
	};
    } \@widgets, $val;

    my @updates_inv = mapn {
	my ($w, $ref) = @_;
	sub { 
	    $ref->{type} eq "bool" ? 
	      $w->set_active(${$ref->{val}}) :
	      widget($w, $ref)->set_text(${$ref->{val}})
	};
    } \@widgets, $val;


    for (my $i = 0; $i < $num_fields; $i++) {
	my $ind = $i; #-cos lexical bindings pb !!
	my $widget = widget($widgets[$i], $val->[$i]);
	my $changed_callback = sub {
	    return if $ignore; #-handle recursive deadlock
	    &{$updates[$ind]};
	    if ($hcallback{changed}) {
		&{$hcallback{changed}}($ind);
		#update all the value
		$ignore = 1;
		&$_ foreach @updates_inv;
		$ignore = 0;
	    };
	};
	if ($hcallback{focus_out}) {
	    my $focusout_callback = sub {
		return if $ignore;
		&{$hcallback{focus_out}}($ind);
		#update all the value
		$ignore = 1;
		&$_ foreach @updates_inv;
		$ignore = 0;
	    };
	    $widget->signal_connect(focus_out_event => $focusout_callback);
	}
	if (ref $widget eq "Gtk::Entry") {
	    $widget->signal_connect(changed => $changed_callback);
	    my $go_to_next = sub {
		if ($ind == ($num_fields -1)) {
		    $w->{ok}->grab_focus();
		} else {
		    widget($widgets[$ind+1],$val->[$ind+1])->grab_focus();
		}
	    };
	    $widget->signal_connect(activate => $go_to_next);
	    $widget->signal_connect(key_press_event => sub {
		my ($w, $e) = @_;
		#-don't know why it works, i believe that
		#-i must say before &$go_to_next, but with it doen't work HACK!
		$w->signal_emit_stop("key_press_event") if chr($e->{keyval}) eq "\x8d";
	    });
	    $widget->set_text(${$val->[$i]{val}})  if ${$val->[$i]{val}};
	    $widget->set_visibility(0) if $val->[$i]{hidden};
	}
	&{$updates[$i]};
    }

    my @entry_list = mapn { [($_[0], $_[1])]} $l, \@widgets;

    gtkadd($w->{window},
	   gtkpack(
		   create_box_with_title($w, @$messages),
		   create_packtable({}, @entry_list),
		   $ok
		   ));
    widget($widgets[0],$val->[0])->grab_focus();
    if ($hcallback{complete}) {
	my $callback = sub {
	    my ($error, $focus) = &{$hcallback{complete}};
	    #-update all the value
	    $ignore = 1;
	    foreach (@updates_inv) { &{$_};}
	    $ignore = 0;
	    if ($error) {
		$focus ||= 0;
		widget($widgets[$focus], $val->[$focus])->grab_focus();
	    } else {
		return 1;
	    }
	};
	#$w->{ok}->signal_connect(clicked => $callback)
	$w->main($callback);
    } else {
	$w->main();
    }
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

sub kill {
    my ($o) = @_;
    $o->{before_killing} ||= 0;
    while (@interactive::objects > $o->{before_killing}) {
	my $w = pop @interactive::objects;
	$w->destroy;
    }
    @my_gtk::grabbed = ();
    $o->{before_killing} = @interactive::objects;
}
