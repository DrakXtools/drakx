package interactive_gtk; # $Id$

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
sub enter_console { my ($o) = @_; $o->{suspended} = common::setVirtual(1) }
sub leave_console { my ($o) = @_; common::setVirtual(delete $o->{suspended}) }

sub suspend {}
sub resume {}

sub exit { 
    gtkset_mousecursor_normal(); #- for restoring a normal in any case on standalone
    my_gtk::flush();
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
#gtkset_usize(createScrolledWindow($tree), 300, min(350, $::windowheight - 60)),
    $w->{retval} = $def || $l->[0]; #- nearly especially for the X test case (see timeout in Xconfigurator.pm)
    $w->{rwindow}->set_policy(0, 0, 1)  if $::isWizard;
    if (@$l < 5 or $::isWizard) {
	my $defW;
	my $tips = new Gtk::Tooltips;
	my $g = sub { $w->{retval} = $_[1]; };
	my $f = sub { $w->{retval} = $_[1]; Gtk->main_quit };
	my $b;
	$w->sync;
	$::isWizard and my $pixmap = new Gtk::Pixmap( gtkcreate_xpm($w->{window}, $::wizard_xpm)) || die "pixmap $! not found.";
	if ($::isWizard) {
	    gtkset_usize($w->{rwindow}, 500, 400);
	}
	gtkadd($w->{window},
	       gtkpack2_(create_box_with_title($w, @$messages),
			 1,
			 gtkpack3( $::isWizard,
				   new Gtk::HBox(0,0),
				   $::isWizard ? ($pixmap, gtkset_usize(new Gtk::VBox(0,0),30, 0)) : (),
				   gtkpack2__( $::isWizard ? new Gtk::VBox(0,0): ( @$l < 3 && sum(map { length $_ } @$l) < 60 ? create_hbox() : create_vbox()),
					      $::isWizard ? gtkset_usize(new Gtk::VBox(0,0), 0, 30) : (),
						  map {
						      $::isWizard ? $b = new Gtk::RadioButton($b ? ($_, $b) : $_) : ($b = new Gtk::Button($_));
						      $tips->set_tip($b, $help->{$_}) if $help && $help->{$_};
						      $_ eq $def and $defW = $b;
						      $b->signal_connect(clicked => [ $::isWizard ? $g : $f, $_ ]);
						      $b;
						  } @$l, )),
			 0, new Gtk::HSeparator,
			 $::isWizard ? (0, $w->create_okcancel()) : (),
			),
	      );

	$defW->grab_focus if $defW;
	$r = $w->main;
    } else {
	#- use ask_from_list_with_help only when needed, as key bindings are
	#- dropped by List (CList does not seems to accepts Tooltips).
	$help ? $w->_ask_from_list_with_help($title, $messages, $l, $help, $def) :
	  $w->_ask_from_list($title, $messages, $l, $def);
	$r = $w->main;
    }
    $r or $::isWizard ? 0 : die "ask_from_list cancel";
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

sub ask_many_from_listW {
    my ($o, $title, $messages, @l) = @_;
    my $w = my_gtk->new('', %$o);
    $w->sync; # for XPM's creation

    my $tips = new Gtk::Tooltips;
    my @boxes; @boxes = map {
	my $l = $_;
	my $box = gtkpack(new Gtk::VBox(0, @{$l->{icons}} ? 10 : 0),
		map_index {
		    my $i = $::i;

		    my $o = Gtk::CheckButton->new($_);
		    $tips->set_tip($o, $l->{help}[$i]) if $l->{help}[$i];
		    $o->set_active(${$l->{ref}[$i]});
		    $o->signal_connect(clicked => sub { 
		        my $v = invbool($l->{ref}[$i]);
			$boxes[$l->{shadow}]->set_sensitive(!$v) if exists $l->{shadow};
		    });

		    my $f = $l->{icons}[$i];
		    -e $f ? gtkpack_(new Gtk::HBox(0,10), 0, new Gtk::Pixmap(gtkcreate_xpm($w->{window}, $f)), 1, $o) : $o;
		} @{$l->{labels}});
	@{$l->{labels}} > (@{$l->{icons}} ? 5 : 11) ? gtkset_usize(createScrolledWindow($box), @{$l->{icons}} ? 350 : 0, $::windowheight - 200) : $box;
    } @l;
    gtkadd($w->{window},
	   gtkpack_(create_box_with_title($w, @$messages),
		    (map {; 1, $_, 0, '' } @boxes),
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
    $w->sync; # for XPM's creation

    my $set_icon = sub {
	my ($i, $button) = @_;
	gtkdestroy($i->{icon});
	my $f = $i->{icon2f}->(${$i->{val}});
	$i->{icon} = -e $f ?
	  new Gtk::Pixmap(gtkcreate_xpm($w->{window}, $f)) :
	  new Gtk::Label(translate(${$i->{val}}));
	$button->add($i->{icon});
	$i->{icon}->show;
    };

    #-the widgets
    my @widgets = map {
	my $i = $_;

	$i->{type} = "iconlist" if $i->{type} eq "list" && $i->{not_edit} && $i->{icon2f};

	if ($i->{type} eq "list") {
	    my $w = new Gtk::Combo;
	    $w->set_use_arrows_always(1);
	    $w->entry->set_editable(!$i->{not_edit});
	    $w->set_popdown_strings(@{$i->{list}});
	    $w->disable_activate;
	    $w;
	} elsif ($i->{type} eq "iconlist") {
	    my $w = new Gtk::Button;
	    $w->signal_connect(clicked => sub {
		${$i->{val}} = next_val_in_array(${$i->{val}}, $i->{list});
		$set_icon->($i, $w);
	    });
	    $set_icon->($i, $w);
	    gtkpack_(new Gtk::HBox(0,10), 1, new Gtk::HBox(0,0), 0, $w, 1, new Gtk::HBox(0,0), );
	} elsif ($i->{type} eq "bool") {
	    my $w = Gtk::CheckButton->new($i->{text});
	    $w->set_active(${$i->{val}});
	    $w->signal_connect(clicked => sub { $ignore or invbool \${$i->{val}} });
	    $w;
	} elsif ($i->{type} eq "range") {
	    my $adj = create_adjustment(${$i->{val}}, $i->{min}, $i->{max});
	    $adj->signal_connect(value_changed => sub { ${$i->{val}} = $adj->get_value });
	    my $w = new Gtk::HScale($adj);
	    $w->set_digits(0);
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
	    $ref->{type} =~ /bool|range|iconlist/ and return;
	    ${$ref->{val}} = widget($w, $ref)->get_text;
	};
    } \@widgets, $val;

    my @updates_inv = mapn {
	my ($w, $ref) = @_;
	sub { 
	    $ref->{type} =~ /iconlist/ and return;
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
	my $may_go_to_next = sub {
	    my ($W, $e) = @_;
	    if (($e->{keyval} & 0x7f) == 0xd) {
		$W->signal_emit_stop("key_press_event");
		if ($ind == $#$l) {
		    @$l == 1 ? $w->{ok}->clicked : $w->{ok}->grab_focus;
		} else {
		    widget($widgets[$ind+1],$val->[$ind+1])->grab_focus;
		}
	    }
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
	if (ref $widget eq "Gtk::HScale") {
	    $widget->signal_connect(key_press_event => $may_go_to_next);
	}
	if (ref $widget eq "Gtk::Entry") {
	    $widget->signal_connect(changed => $changed_callback);
	    $widget->signal_connect(key_press_event => $may_go_to_next);
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
    $o->{before_killing} = @interactive::objects;
}
