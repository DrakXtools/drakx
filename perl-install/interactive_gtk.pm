package interactive_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common :functional);
use my_gtk qw(:helpers :wrappers);

my $forgetTime = 1000; #- in milli-seconds

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

sub test_embedded {
    my ($w) = @_;
    $::isEmbedded or return;
    $w->{window} = new Gtk::VBox(0,0);
    $w->{rwindow} = $w->{window};
    defined($::Plug) ? $::Plug->child->destroy() : ($::Plug = new Gtk::Plug ($::XID));
    $::Plug->show;
    my_gtk::flush();
    $::Plug->add($w->{window});
    $w->{window}->add($w->{rwindow});
}

sub create_clist {
    my ($e, $may_go_to_next, $changed) = @_;
    my ($first_time, $starting_word, $start_reg) = (1, '', "^");
    my (@widgets, $timeout, $curr);
    my @l = map { may_apply($e->{format}, $_) } @{$e->{list}};

    my $list = new Gtk::CList(1);
    $list->set_selection_mode('browse');
    $list->set_column_auto_resize(0, 1);

    my $select = sub {
	$list->set_focus_row($_[0]);
	$list->select_row($_[0], 0);
	$list->moveto($_[0], 0, 0.5, 0);
    };

#    ref $title && !@okcancel ?
#      $list->signal_connect(button_release_event => $leave) :
#      $list->signal_connect(button_press_event => sub { &$leave if $_[1]{type} =~ /^2/ });

    $list->signal_connect(key_press_event => sub {
        my ($w, $event) = @_;
	my $c = chr($event->{keyval} & 0xff);

	Gtk->timeout_remove($timeout) if $timeout; $timeout = '';
	
	if ($event->{keyval} >= 0x100) {
	    &$may_go_to_next if $c eq "\r" || $c eq "\x8d";
	    $starting_word = '' if $event->{keyval} != 0xffe4; # control
	} else {
	    if ($event->{state} & 4) {
		#- control pressed
		$c eq "s" or return 1;
		$start_reg and $start_reg = '', return 1;
		$curr++;
	    } else {
		&$may_go_to_next if $c eq ' ';

		$curr++ if $starting_word eq '' || $starting_word eq $c;
		$starting_word .= $c unless $starting_word eq $c;
	    }
	    my $word = quotemeta $starting_word;
	    my $j; for ($j = 0; $j < @l; $j++) {
		 $l[($j + $curr) % @l] =~ /$start_reg$word/i and last;
	    }
	    $j == @l ?
	      $starting_word = '' :
	      $select->(($j + $curr) % @l);

	    $w->{timeout} = $timeout = Gtk->timeout_add($forgetTime, sub { $timeout = $starting_word = ''; 0 } );
	}
	1;
    });
    $list->show;

    $list->append($_) foreach @l;

    $list->signal_connect(select_row => sub {
	my ($w, $row) = @_;
	${$e->{val}} = $e->{list}[$curr = $row];
	&$changed;
    });

    $list, sub {
	my ($v) = @_;
	eval { 
	    $select->(find_index { $_ eq $v } @{$e->{list}});
	};
    };
}

sub create_ctree {
    my ($e, $may_go_to_next, $changed) = @_;
    my @l = map { may_apply($e->{format}, $_) } @{$e->{list}};

    my $sep = quotemeta $e->{separator};
    my $tree = Gtk::CTree->new(1, 0);

    my (%wtree, %wleaves);
    my $parent; $parent = sub {
	if (my $w = $wtree{"$_[0]$e->{separator}"}) { return $w }
	my $s;
	foreach (split $sep, $_[0]) {
	    $wtree{"$s$_$e->{separator}"} ||= 
	      $tree->insert_node($s ? $parent->($s) : undef, undef, [$_], 5, (undef) x 4, 0, 0);
	    $s .= "$_$e->{separator}";
	}
	$wtree{$s};
    };
    foreach (@l) {
	my ($root, $leaf) = /(.*)$sep(.+)/ ? ($1, $2) : ('', $_);
	$wleaves{$_} = $tree->insert_node($parent->($root), undef, [$leaf], 5, (undef) x 4, 1, 0);
    }
    undef %wtree;

    my $curr;
    $tree->set_column_auto_resize(0, 1);
    $tree->set_selection_mode('browse');
    $tree->signal_connect(tree_select_row => sub { 
	$curr = $_[1]; 
	$curr->row->is_leaf or return;
	my @l; for (my $c = $curr; $c; $c = $c->row->parent) { 
	    unshift @l, first $tree->node_get_pixtext($c, 0);
	}
	${$e->{val}} = join $e->{separator}, @l;
	&$changed;
    });
#    $tree->signal_connect(button_press_event => sub { &$leave if $_[1]{type} =~ /^2/ });
    $tree->signal_connect(key_press_event => sub {
        my ($w, $event) = @_;
	my $c = chr($event->{keyval} & 0xff);
	$curr or return;
	if ($event->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ') {
	    if ($curr->row->is_leaf) { &$may_go_to_next }
	    else { $tree->toggle_expansion($curr) }
	}
	1;
    });
    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);

    $tree, sub {
	my $v = may_apply($e->{format}, $_[0]);
	my $node = $wleaves{$v} or return;

	for (my $c = $node; $c; $c = $c->row->parent) { 
	    $tree->expand($c);
	}
	$tree->select($node);
	$tree->node_moveto($node, 0, 0.5, 0);

	foreach (1 .. @l) {
	    if ($tree->node_nth($_) == $node) {
		$tree->set_focus_row($_);
		last;
	    }
	}
    };
}

sub create_list {
    my ($e, $may_go_to_next, $changed) = @_;
    my $l = $e->{list};
    my $list = new Gtk::List();
    $list->set_selection_mode('browse');

    my $select = sub {
	$list->select_item($_[0]);
    };

    my $tips = new Gtk::Tooltips;
    my $toselect;
    map_index {
	my $item = new Gtk::ListItem(may_apply($e->{format}, $_));
	$item->signal_connect(key_press_event => sub {
    	    my ($w, $event) = @_;
    	    my $c = chr($event->{keyval} & 0xff);
	    $may_go_to_next->($event) if $event->{keyval} < 0x100 ? $c eq ' ' : $c eq "\r" || $c eq "\x8d";
    	    1;
    	});
	$list->append_items($item);
	$item->show;
	if ($e->{help}) {
	    $tips->set_tip($item,
			   ref($e->{help}) eq 'HASH' ? $e->{help}{$_} :
			   ref($e->{help}) eq 'CODE' ? $e->{help}($_) : $e->{help});
	}
	$item->grab_focus if ${$e->{val}} && $_ eq ${$e->{val}};
    } @$l;

    #- signal_connect'ed after append_items otherwise it is called and destroys the default value
    $list->signal_connect(select_child => sub {
	my ($w, $row) = @_;
	${$e->{val}} = $l->[$list->child_position($row)];
	&$changed;
    });
    $list, sub { 
	my ($v) = @_;
	eval { 
	    $select->(find_index { $_ eq $v } @$l);
	};
    };
}

sub ask_from_entries_refW {
    my ($o, $common, $l, $l2) = @_;
    my $ignore = 0; #-to handle recursivity

    my $mainw = my_gtk->new($common->{title}, %$o);
    test_embedded($mainw);
    $mainw->sync; # for XPM's creation

    #-the widgets
    my (@widgets, @widgets_always, @widgets_advanced, $advanced, $advanced_pack, $has_scroll, $total_size);
    my $tooltips = new Gtk::Tooltips;

    my $set_all = sub {
	$ignore = 1;
	$_->{set}->(${$_->{e}{val}}) foreach @widgets_always, @widgets_advanced;
	$_->{w}->set_sensitive(!$_->{e}{disabled}()) foreach @widgets_always, @widgets_advanced;
	$ignore = 0;
    };
    my $get_all = sub {
	${$_->{e}{val}} = $_->{get}->() foreach @widgets_always, @widgets_advanced;
    };
    my $create_widget = sub {
	my ($e, $ind) = @_;

	my $may_go_to_next = sub {
	    my ($w, $event) = @_;
	    if (!$event || ($event->{keyval} & 0x7f) == 0xd) {
		$w->signal_emit_stop("key_press_event") if $event;
		if ($ind == $#widgets) {
		    @widgets == 1 ? $mainw->{ok}->clicked : $mainw->{ok}->grab_focus;
		} else {
		    $widgets[$ind+1]{w}->grab_focus;
		}
	    }
	};
	my $changed = sub {
	    return if $ignore;
	    $get_all->();
	    $common->{callbacks}{changed}->($ind);
	    $set_all->();
	};

	my ($w, $real_w, $set, $get, $expand, $size);
	if ($e->{type} eq 'iconlist') {
	    $w = new Gtk::Button;
	    $set = sub {
		gtkdestroy($e->{icon});
		my $f = $e->{icon2f}->($_[0]);
		$e->{icon} = -e $f ?
		  new Gtk::Pixmap(gtkcreate_xpm($mainw->{window}, $f)) :
		    new Gtk::Label(may_apply($e->{format}, $_[0]));
		$w->add($e->{icon});
		$e->{icon}->show;
	    };
	    $w->signal_connect(clicked => sub {		
		$set->(${$e->{val}} = next_val_in_array(${$e->{val}}, $e->{list}));
		$changed->();
	    });
	    $real_w = gtkpack_(new Gtk::HBox(0,10), 1, new Gtk::HBox(0,0), 0, $w, 1, new Gtk::HBox(0,0), );
	} elsif ($e->{type} eq 'bool') {
	    $w = Gtk::CheckButton->new($e->{text});
	    $w->signal_connect(clicked => $changed);
	    $set = sub { $w->set_active($_[0]) };
	    $get = sub { $w->get_active };
	} elsif ($e->{type} eq 'range') {
	    my $adj = create_adjustment(${$e->{val}}, $e->{min}, $e->{max});
	    $adj->signal_connect(value_changed => $changed);
	    $w = new Gtk::HScale($adj);
	    $w->set_digits(0);
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $set = sub { $adj->set_value($_[0]) };
	    $get = sub { $adj->get_value };
	} elsif ($e->{type} =~ /list/) {
	    if ($e->{help}) {
		#- used only when needed, as key bindings are dropped by List (CList does not seems to accepts Tooltips).
		($w, $set) = create_list($e, $may_go_to_next, $changed);
	    } elsif ($e->{type} eq 'treelist') {
		($w, $set) = create_ctree($e, $may_go_to_next, $changed);
	    } else {
		($w, $set) = create_clist($e, $may_go_to_next, $changed);
	    }
	    if (@{$e->{list}} > 4) {
		$has_scroll = 1;
		$expand = 1;
		$real_w = createScrolledWindow($w);
		$size += @{$e->{list}};
	    }
	} else {
	    if ($e->{type} eq "combo") {
		$w = new Gtk::Combo;
		$w->set_use_arrows_always(1);
		$w->entry->set_editable(!$e->{not_edit});
		$w->set_popdown_strings(@{$e->{list}});
		$w->disable_activate;
		($real_w, $w) = ($w, $w->entry);
	    } else {
		$w = new Gtk::Entry(${$e->{val}});
	    }
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $w->signal_connect(changed => $changed);
	    $w->set_visibility(0) if $e->{hidden};
	    $set = sub { $w->set_text($_[0]) };
	    $get = sub { $w->get_text };
	}
	$w->signal_connect(focus_out_event => sub {
	    return if $ignore;
	    $get_all->();
	    $common->{callbacks}{focus_out}->($ind);
	    $set_all->();
	});
	$tooltips->set_tip($w, $e->{help}) if $e->{help} && !ref($e->{help});

	$total_size += $size || 1;
    
	{ e => $e, w => $w, real_w => $real_w || $w, expand => $expand,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {},
	  icon_w => -e $e->{icon} ? new Gtk::Pixmap(gtkcreate_xpm($mainw->{window}, $e->{icon})) : '' };
    };
    @widgets_always   = map_index { $create_widget->($_, $::i      ) } @$l;
    @widgets_advanced = map_index { $create_widget->($_, $::i + @$l) } @$l2;

    my $set_advanced = sub {
	($advanced) = @_;
	$advanced ? $advanced_pack->show : $advanced_pack->hide;
	@widgets = (@widgets_always, $advanced ? @widgets_advanced : ());
    };
    my $advanced_button = [ _("Advanced"), sub { $set_advanced->(!$advanced) } ];

    my $create_widgets = sub {
	my $w = create_packtable({}, map { [($_->{icon_w}, $_->{e}{label}, $_->{real_w})]} @_);
	#- use a scrolled window if there is a lot of checkboxes (aka ask_many_from_list)
	my $has = (grep { $_->{e}{type} eq 'bool' } @_) > 4;
	$has_scroll ||= $has;
	$has ? createScrolledWindow($w) : $w;
    };

    my $pack = gtkpack_(create_box_with_title($mainw, @{$common->{messages}}),
		   1, $create_widgets->(@widgets_always),
		   0, $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @$l2 ? $advanced_button : ()));
    $advanced_pack = 
      gtkpack_(new Gtk::VBox(0,0),
	       0, '',
	       (map {; 0, new Gtk::Label($_) } map { warp_text($_) } @{$common->{advanced_messages}}),
	       0, new Gtk::HSeparator,
	       1, $create_widgets->(@widgets_advanced));

    $pack->pack_start($advanced_pack, 1, 1, 0);
    gtkadd($mainw->{window}, $pack);
    $mainw->{window}->set_usize(0, min($total_size > 10 ? 350 : 200, $::windowheight - 60)) if $has_scroll;
    $mainw->sync; #- for $set_all below (mainly for the set of clist)
    $set_all->();
    $set_advanced->(0);
    (@widgets ? $widgets[0]{w} : $common->{focus_cancel} ? $mainw->{cancel} : $mainw->{ok})->grab_focus();

    my $check = sub {
	my ($f) = @_;
	sub {
	    $get_all->();
	    my ($error, $focus) = $f->();
	
	    if ($error) {
		$set_all->();
		$widgets[$focus || 0]{w}->grab_focus();
	    }
	    !$error;
	}
    };
    $mainw->main(map { $check->($common->{callbacks}{$_}) } 'complete', 'canceled');
}


sub wait_messageW($$$) {
    my ($o, $title, $messages) = @_;

    my $w = my_gtk->new($title, %$o, grab => 1);
    test_embedded($w);
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

1;
