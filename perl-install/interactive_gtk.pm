package interactive_gtk;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common :functional);
use my_gtk qw(:helpers :wrappers);

1;

sub new {
    $::windowheight ||= 400 if $::isStandalone;
    goto &interactive::new;
}

#-#- redefine ask_warn
#-sub ask_warn {
#-    my $o = shift;
#-    local $my_gtk::grab = 1;
#-    $o->SUPER::ask_warn(@_);
#-}

sub exit { 
    c::_exit($_[0]) #- workaround 
}

sub ask_from_listW {
    my ($o, $title, $messages, $l, $def) = @_;
    ask_from_list_with_helpW($o, $title, $messages, $l, undef, $def);
}

sub ask_from_list_with_helpW {
    my ($o, $title, $messages, $l, $help, $def) = @_;
    my $r;

    my $w = my_gtk->new(first(deref($title)), %$o);
    $w->{retval} = $def || $l->[0]; #- nearly especially for the X test case (see timeout in Xconfigurator.pm)
    if (@$l < 5) {
	my $defW;
	my $tips = new Gtk::Tooltips;
	my $f = sub { $w->{retval} = $_[1]; Gtk->main_quit };
	gtkadd($w->{window},
	       gtkpack(create_box_with_title($w, @$messages),
		       gtkadd(@$l < 3 && sum(map { length $_ } @$l) < 60 ? create_hbox() : create_vbox(),
			      map {
				  my $b = new Gtk::Button($_);
				  $tips->set_tip($b, $help->{$_}) if $help && $help->{$_};
				  $b->signal_connect(clicked => [ $f, $_ ]);
				  $_ eq $def and $defW = $b;
				  $b;
			      } @$l),
		       ),
	       );
	$defW->grab_focus if $defW;
	$w->{rwindow}->set_position('center') if $::isStandalone;
	$r = $w->main;
    } else {
	#- use ask_from_list_with_help only when needed, as key bindings are
	#- dropped by List (CList does not seems to accepts Tooltips).
	$help ? $w->_ask_from_list_with_help($title, $messages, $l, $help, $def) :
	  $w->_ask_from_list($title, $messages, $l, $def);
	$r = $w->main;
    }
    $r or die "ask_from_list cancel";
}

sub ask_from_treelistW {
    my ($o, $title, $messages, $separator, $l, $def) = @_;
    my $sep = quotemeta $separator;
    my $w = my_gtk->new($title);
    my $tree = Gtk::CTree->new(1, 0);

    my %wtree;
    my $parent; $parent = sub {
	if (my $w = $wtree{"$_[0]$separator"}) { return $w }
	my $s;
	foreach (split $sep, $_[0]) {
	    $wtree{"$s$_$separator"} ||= 
	      $tree->insert_node($s ? $parent->($s) : undef, undef, [$_], 5, (undef) x 4, 0, 0);
	    $s .= "$_$separator";
	}
	$wtree{$s};
    };
    my ($root, $leaf, $wdef, $ndef);
    foreach (@$l) {
	($root, $leaf) = /(.*)$sep(.+)/ or ($root, $leaf) = ('', $_);
	my $node = $tree->insert_node($parent->($root), undef, [$leaf], 5, (undef) x 4, 1, 0);

	if ($def eq $_) {
	    $wdef = $node;
	    my $s; $tree->expand($wtree{$s .= "$_$separator"}) foreach split $sep, $root;
	    foreach my $nb (1 .. @$l) {
		if ($tree->node_nth($nb) == $node) {
		    $tree->set_focus_row($ndef = $nb);
		    last;
		}
	    }
	}
    }
    undef %wtree;

    my $curr;
    my $leave = sub { 
	$curr->row->is_leaf or return;
	my @l; for (; $curr; $curr = $curr->row->parent) { 
	    unshift @l, first $tree->node_get_pixtext($curr, 0);
	}
	$w->{retval} = join $separator, @l;
	Gtk->main_quit;
    };
    $w->{ok_clicked} = $leave;
    $w->{cancel_clicked} = sub { $w->destroy; die "ask_from_list cancel" }; #- make sure windows doesn't live any more.
    gtkadd($w->{window},
	   gtkpack($w->create_box_with_title(@$messages),
		   gtkpack_(new Gtk::VBox(0,7),
			    1, gtkset_usize(createScrolledWindow($tree), 300, min(350, $::windowheight - 60)),
			    0, $w->create_okcancel)));
    $tree->set_column_auto_resize(0, 1);
    $tree->set_selection_mode('browse');
    $tree->signal_connect(tree_select_row => sub { $curr = $_[1]; });
    $tree->signal_connect(button_press_event => sub { &$leave if $_[1]{type} =~ /^2/ });
    $tree->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr($e->{keyval} & 0xff);
	$curr or return;
	if ($e->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ') {
	    if ($curr->row->is_leaf) { &$leave }
	    else { $tree->toggle_expansion($curr) }
	}
	1;
    });

    $tree->grab_focus;
    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);
    $w->{rwindow}->show;

    if ($wdef) {
	$tree->select($wdef);
	$tree->node_moveto($wdef, 0, 0.5, 0);
    }


    $w->main or die "ask_from_list cancel";
}

sub ask_many_from_list_with_help_refW {
    my ($o, $title, $messages, @L) = @_;
    my $w = my_gtk->new('', %$o);
    my $tips = new Gtk::Tooltips;
    my @boxes = map {
	my $l = $_;
	my $box = gtkpack(new Gtk::VBox(0,0),
		map_index {
		    my $i = $::i;
		    my $o = Gtk::CheckButton->new($_);
		    $tips->set_tip($o, $l->[1][$i]) if $l->[1][$i];
		    $o->set_active(${$l->[2][$i]});
		    $o->signal_connect(clicked => sub { invbool $l->[2][$i] });
		    $o;
		} @{$l->[0]});
	@{$l->[0]} > 11 ? gtkset_usize(createScrolledWindow($box), 0, 250) : $box;
    } @L;
    gtkadd($w->{window},
	   gtkpack_(create_box_with_title($w, @$messages),
		    (map {; 1, $_ } @boxes),
		    0, $w->create_okcancel,
		   )
	  );
    $w->{ok}->grab_focus;
    $w->main;
}

sub ask_from_entries_refW {
    my ($o, $title, $messages, $l, $val, %hcallback) = @_;
    my ($title_, @okcancel) = deref($title);
    my $ignore = 0; #-to handle recursivity

    my $w = my_gtk->new($title_, %$o);
    #-the widgets
    my @widgets = map {
	if ($_->{type} eq "list") {
	    my $w = new Gtk::Combo;
	    $w->set_use_arrows_always(1);
	    $w->entry->set_editable(!$_->{not_edit});
	    $w->set_popdown_strings(@{$_->{list}});
	    $w->disable_activate;
	    $w;
	} elsif ($_->{type} eq "bool") {
	    my $w = Gtk::CheckButton->new($_->{text});
	    $w->set_active(${$_->{val}});
	    my $i = $_; $w->signal_connect(clicked => sub { $ignore or invbool \${$i->{val}} });
	    $w;
	} else {
	    new Gtk::Entry;
	}
    } @{$val};
    my $ok = $w->create_okcancel(@okcancel);

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


    for (my $i = 0; $i < @$l; $i++) {
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
		if ($ind == $#$l) {
		    @$l == 1 ? $w->{ok}->clicked : $w->{ok}->grab_focus();
		} else {
		    widget($widgets[$ind+1],$val->[$ind+1])->grab_focus();
		}
	    };
	    $widget->signal_connect(activate => $go_to_next);
	    $widget->signal_connect(key_press_event => sub {
		my ($w, $e) = @_;
		#-don't know why it works, i believe that
		#-i must say before &$go_to_next, but with it doen't work HACK!
		$w->signal_emit_stop("key_press_event") if chr($e->{keyval} & 0xff) eq "\x8d";
	    });
	    $widget->set_text(${$val->[$i]{val}});
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
    my ($o, $title, $messages) = @_;

    my $w = my_gtk->new($title, %$o, grab => 1);
    gtkadd($w->{window}, my $hbox = new Gtk::HBox(0,0));
    $hbox->pack_start(my $box = new Gtk::VBox(0,0), 1, 1, 10);  
    $box->pack_start($_, 1, 1, 4) foreach my @l = map { new Gtk::Label($_) } @$messages;

    ($w->{wait_messageW} = $l[$#l])->signal_connect(expose_event => sub { $w->{displayed} = 1 });
    $w->{rwindow}->set_position('center') if $::isStandalone;
    $w->{window}->show_all;
    $w->sync until $w->{displayed};
    $w;
}
sub wait_message_nextW {
    my ($o, $messages, $w) = @_;
    my $msg = join "\n", @$messages;
    return if $msg eq $w->{wait_messageW}->get; #- needed otherwise no expose_event :(
    $w->{displayed} = 0;
    $w->{wait_messageW}->set($msg);
    $w->flush until $w->{displayed};
}
sub wait_message_endW {
    my ($o, $w) = @_;
    $w->destroy;
}

sub kill {
    my ($o) = @_;
    $o->{before_killing} ||= 0;

    while (my $e = shift @tempory::objects) { $e->destroy }
    while (@interactive::objects > $o->{before_killing}) {
	my $w = pop @interactive::objects;
	$w->destroy;
    }
    @my_gtk::grabbed = ();
    $o->{before_killing} = @interactive::objects;
}
