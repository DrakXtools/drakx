package interactive_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
use my_gtk qw(:helpers :wrappers);

my $forgetTime = 1000; #- in milli-seconds

sub new {
    ($::windowheight, $::windowwidth) = my_gtk::gtkroot()->get_size if $::isStandalone;
    goto &interactive::new;
}
sub enter_console { my ($o) = @_; $o->{suspended} = common::setVirtual(1) }
sub leave_console { my ($o) = @_; common::setVirtual(delete $o->{suspended}) }

sub exit { 
    gtkset_mousecursor_normal(); #- for restoring a normal in any case on standalone
    my_gtk::flush();
    c::_exit($_[1]) #- workaround 
}

sub ask_warn {
    local $my_gtk::pop_it = 1;
    &interactive::ask_warn;
}

sub create_boxradio {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
    my @l = map { may_apply($e->{format}, $_) } @{$e->{list}};

    my $boxradio = gtkpack2__(new Gtk::VBox(0, 0),
			      my @radios = gtkradio('', @l));
    $boxradio->show;
    my $tips = new Gtk::Tooltips;
    mapn {
	my ($txt, $w) = @_;
	$w->signal_connect(button_press_event => $double_click) if $double_click;
	$w->signal_connect(clicked => sub {
 	    ${$e->{val}} = $txt;
	    &$changed;
        });
	if ($e->{help}) {
	    gtkset_tip($tips, $w,
		       ref($e->{help}) eq 'HASH' ? $e->{help}{$txt} :
		       ref($e->{help}) eq 'CODE' ? $e->{help}($txt) : $e->{help});
	}
    } $e->{list}, \@radios;

    $boxradio, sub {
	my ($v) = @_;
	mapn { $_[0]->set_active($_[1] eq $v) } \@radios, $e->{list};
    }
}

sub create_clist {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
    my $curr;
    my @l = map { may_apply($e->{format}, $_) } @{$e->{list}};

    my $list = new Gtk::CList(1);
    $list->set_selection_mode('browse');
    $list->set_column_auto_resize(0, 1);

    my $select = sub {
	$list->set_focus_row($_[0]);
	$list->select_row($_[0], 0);
	$list->moveto($_[0], 0, 0.5, 0) if $list->row_is_visible($_[0]) ne 'full';
    };

#    ref $title && !@okcancel ?
#      $list->signal_connect(button_release_event => $leave) :
#      $list->signal_connect(button_press_event => sub { &$leave if $_[1]{type} =~ /^2/ });

    my ($first_time, $starting_word, $start_reg) = (1, '', "^");
    my $timeout;
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

	    $timeout = Gtk->timeout_add($forgetTime, sub { $timeout = $starting_word = ''; 0 } );
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
    $list->signal_connect(button_press_event => $double_click) if $double_click;

    $list, sub {
	my ($v) = @_;
	eval {
	    $select->(find_index { $_ eq $v } @{$e->{list}});
	};
    };
}

sub create_ctree {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
    my @l = map { may_apply($e->{format}, $_) } @{$e->{list}};

    my $sep = quotemeta $e->{separator};
    my $tree = Gtk::CTree->new(1, 0);

    my (%wtree, %wleaves, $size, $selected_via_click);
    my $parent; $parent = sub {
	if (my $w = $wtree{"$_[0]$e->{separator}"}) { return $w }
	my $s;
	foreach (split $sep, $_[0]) {
	    $wtree{"$s$_$e->{separator}"} ||= 
	      $tree->insert_node($s ? $parent->($s) : undef, undef, [$_], 5, (undef) x 4, 0, 0);
	    $size++ if !$s;
	    $s .= "$_$e->{separator}";
	}
	$wtree{$s};
    };
    foreach (@l) {
	my ($root, $leaf) = /(.*)$sep(.+)/ ? ($1, $2) : ('', $_);
	$wleaves{$_} = $tree->insert_node($parent->($root), undef, [$leaf], 5, (undef) x 4, 1, 0);
    }
    undef %wtree;

    my $select = sub {
	my ($node) = @_;
	for (my $c = $node; $c; $c = $c->row->parent) { 
	    $tree->expand($c);
	}
	foreach (0 .. $#l) {
	    if ($tree->node_nth($_) == $node) {
		$tree->set_focus_row($_);
		last;
	    }
	}
	$tree->select($node);
	$tree->node_moveto($node, 0, 0.5, 0) if $tree->node_is_visible($node) ne 'full';
    };

    my $curr = $tree->node_nth(0); #- default value
    $tree->set_column_auto_resize(0, 1);
    $tree->set_selection_mode('browse');
    $tree->signal_connect(tree_select_row => sub { 
	$curr = $_[1]; 
	if ($curr->row->is_leaf) {
	    my @ll; for (my $c = $curr; $c; $c = $c->row->parent) { 
		unshift @ll, first $tree->node_get_pixtext($c, 0);
	    }
	    my $val = join $e->{separator}, @ll;
	    mapn {
		${$e->{val}} = $_[1] if $val eq $_[0]
	    } \@l, $e->{list};
	    &$changed;
	} else {
	    $tree->expand($curr) if $selected_via_click;
	}
    });
    my ($first_time, $starting_word, $start_reg) = (1, '', "^");
    my $timeout;

    my $toggle = sub { 
	$curr->row->is_leaf ? 
	  &$may_go_to_next :
	  $tree->toggle_expansion($curr);
    };
    $tree->signal_connect(key_press_event => sub {
        my ($w, $event) = @_;
	$selected_via_click = 0;
	my $c = chr($event->{keyval} & 0xff);
	$curr or return;
	Gtk->timeout_remove($timeout) if $timeout; $timeout = '';

	if ($event->{keyval} >= 0x100) {
	    &$toggle if $c eq "\r" || $c eq "\x8d";
	    $starting_word = '' if $event->{keyval} != 0xffe4; # control
	} else {
	    my $next;
	    if ($event->{state} & 4) {
		#- control pressed
		$c eq "s" or return 1;
		$start_reg and $start_reg = '', return 1;
		$next = 1;
	    } else {
		&$toggle if $c eq ' ';

		$next = 1 if $starting_word eq '' || $starting_word eq $c;
		$starting_word .= $c unless $starting_word eq $c;
	    }
	    my $word = quotemeta $starting_word;
	    my ($after, $best);

	    $tree->pre_recursive(undef, sub { 
		my ($tree, $node) = @_;
		$next &&= !$after;
		$after ||= $node == $curr;
		my ($t) = $tree->node_get_pixtext($node, 0);

		if ($t =~ /$start_reg$word/i) {
		    if ($after && !$next) {
			($best, $after) = ($node, 0);
		    } else {
			$best ||= $node;
		    }
		}
	    });
	    if (defined $best) {
		$select->($best);
	    } else {
		$starting_word = '';
	    }
	    $timeout = Gtk->timeout_add($forgetTime, sub { $timeout = $starting_word = ''; 0 });
	}
	1;
    });
    $tree->signal_connect(button_press_event => sub {
	$selected_via_click = 1;
	&$double_click if $curr->row->is_leaf && $double_click;
    });

    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);

    $tree, sub {
	my $v = may_apply($e->{format}, $_[0]);
	$select->($wleaves{$v} || return);
    }, $size;
}

sub create_list {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
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
	    gtkset_tip($tips, $item,
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
    $list->signal_connect(button_press_event => $double_click) if $double_click;

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
    my $update = sub {
	my ($f) = @_;
	return if $ignore;
	$get_all->();
	$f->();
	$set_all->();
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
	my $changed = sub { $update->(sub { $common->{callbacks}{changed}($ind) }) };

	my ($w, $real_w, $set, $get, $expand, $size);
	if ($e->{type} eq 'iconlist') {
	    $w = new Gtk::Button;
	    $set = sub {
		gtkdestroy($e->{icon});
		my $f = $e->{icon2f}->($_[0]);
		$e->{icon} = -e $f ?
		    gtkpng($f) :
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
	} elsif ($e->{type} eq 'label') {
	    $w = Gtk::Label->new(${$e->{val}});
	    $set = sub { $w->set($_[0]) };
	} elsif ($e->{type} eq 'button') {
	    $w = Gtk::Button->new('');
	    $w->signal_connect(clicked => sub {
		$get_all->();
		$mainw->{rwindow}->hide;
		$e->{clicked}();
		$mainw->{rwindow}->show;
		$set_all->();
	    });
	    $set = sub { $w->child->set(may_apply($e->{format}, $_[0])) };
	} elsif ($e->{type} eq 'range') {
	    my $adj = create_adjustment(${$e->{val}}, $e->{min}, $e->{max});
	    $adj->signal_connect(value_changed => $changed);
	    $w = new Gtk::HScale($adj);
	    $w->set_digits(0);
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $set = sub { $adj->set_value($_[0]) };
	    $get = sub { $adj->get_value };
	} elsif ($e->{type} =~ /list/) {

	    my $quit_if_double_click = 
	      #- i'm the only one, double click means accepting
	      @$l == 1 ? 
		sub { if ($_[1]{type} =~ /^2/) { $mainw->{retval} = 1; Gtk->main_quit } } : ''; 

	    my @para = ($e, $may_go_to_next, $changed, $quit_if_double_click);
	    my $use_boxradio = @{$e->{list}} <= 8;

	    if ($e->{help}) {
		#- used only when needed, as key bindings are dropped by List (CList does not seems to accepts Tooltips).
		($w, $set) = $use_boxradio ? create_boxradio(@para) : create_list(@para);
	    } elsif ($e->{type} eq 'treelist') {
		($w, $set, $size) = create_ctree(@para);
	    } else {
		($w, $set) = $use_boxradio ? create_boxradio(@para) : create_clist(@para);
	    }
	    if (@{$e->{list}} > 4) {
		$has_scroll = 1;
		$expand = 1;
		$real_w = createScrolledWindow($w);
		$size ||= @{$e->{list}};
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
            $update->(sub { $common->{callbacks}{focus_out}($ind) });
	});
	$tooltips->set_tip($w, $e->{help}) if $e->{help} && !ref($e->{help});

	$total_size += $size || 1;
    
	{ e => $e, w => $w, real_w => $real_w || $w, expand => $expand,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {},
	  icon_w => -e $e->{icon} ? gtkpng($e->{icon}) : '' };
    };
    @widgets_always   = map_index { $create_widget->($_, $::i      ) } @$l;
    my $always_total_size = $total_size;
    @widgets_advanced = map_index { $create_widget->($_, $::i + @$l) } @$l2;

    my $set_advanced = sub {
	($advanced) = @_;
	$advanced ? $advanced_pack->show : $advanced_pack->hide;
	@widgets = (@widgets_always, $advanced ? @widgets_advanced : ());
	$mainw->sync; #- for $set_all below (mainly for the set of clist)
	$set_all->(); #- must be done when showing advanced lists (to center selected value)
    };
    my $advanced_button = [ $common->{advanced_label}, sub { $set_advanced->(!$advanced) } ];

    my $create_widgets = sub {
	my $w = create_packtable({}, map { [($_->{icon_w}, $_->{e}{label}, $_->{real_w})]} @_);
	#- use a scrolled window if there is a lot of checkboxes (aka ask_many_from_list)
	my $has = (grep { $_->{e}{type} eq 'bool' } @_) > 4;
	$has_scroll ||= $has;
	$has ? createScrolledWindow($w) : $w;
    };

    my $pack = gtkpack_(create_box_with_title($mainw, @{$common->{messages}}),
		   1, $create_widgets->(@widgets_always),
		   if_($common->{ok} || $::isWizard, 
		       0, $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @$l2 ? $advanced_button : ())));
    my @adv = map { warp_text($_) } @{$common->{advanced_messages}};
    $always_total_size += $mainw->{box_size};
    $advanced_pack = 
      gtkpack_(new Gtk::VBox(0,0),
	       0, '',
	       (map {; 0, new Gtk::Label($_) } @adv),
	       0, new Gtk::HSeparator,
	       1, $create_widgets->(@widgets_advanced));

    $pack->pack_start($advanced_pack, 1, 1, 0);
    gtkadd($mainw->{window}, $pack);
    $mainw->{rwindow}->set_default_size(250, min(max(200, $always_total_size * 20), $::windowheight * 0.7)) if $has_scroll && !$::isEmbedded &&!$::isWizard;
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


sub ask_browse_tree_info_refW {
    my ($o, $common) = @_;
    my ($curr, $parent, $info_widget, $w_size, $prev_label, $go, $idle);
    my (%wtree, %ptree, %pix);

    my $w = my_gtk->new($common->{title});
    my $details = new Gtk::VBox(0,0);
    my $tree = Gtk::CTree->new(3, 0);
    $tree->set_selection_mode('browse');
    $tree->set_column_width(0, 200);
    $tree->set_column_auto_resize($_, 1) foreach 1..2;

    gtkadd($w->{window}, 
	   gtkpack_(new Gtk::VBox(0,5),
		    0, $common->{message},
		    1, gtkpack(new Gtk::HBox(0,0),
			       createScrolledWindow($tree),
			       gtkadd(gtkset_usize(new Gtk::Frame(_("Info")), $::windowwidth - 490, 0),
				      createScrolledWindow($info_widget = new Gtk::Text),
				     )),
		    0, my $l = new Gtk::HBox(0,15),
		    0, gtkpack(new Gtk::HBox(0,10),
			       $go = gtksignal_connect(new Gtk::Button($common->{ok}), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
			       $common->{cancel} ? (gtksignal_connect(new Gtk::Button($common->{cancel}), "clicked" => sub { $w->{retval} = 0; Gtk->main_quit })) : (),
			      )
    ));
    gtkpack__($l, my $toolbar = new Gtk::Toolbar('horizontal', 'icons'));
    if ($common->{auto_deps}) {
	gtkpack__($l, gtksignal_connect(gtkset_active(new Gtk::CheckButton($common->{auto_deps}), $common->{state}{auto_deps}), clicked => sub { invbool \$common->{state}{auto_deps} }));
    }
    $l->pack_end($w_size = new Gtk::Label($prev_label = $common->{state}{status_label}), 0, 1, 20);

    $w->{window}->set_usize(map { $_ - 2 * $my_gtk::border - 4 } $::windowwidth, $::windowheight);
    $go->grab_focus;
    $w->{rwindow}->show_all;

    my $update_size = sub {
	my $new_label = $common->{get_status}();
	$prev_label ne $new_label and $w_size->set($prev_label = $new_label);
    };
    
    my $set_node_state_flat = sub {
	my ($node, $state) = @_;
	unless ($pix{$state}) {
	    foreach ("$ENV{SHARE_PATH}/$state.png", "$ENV{SHARE_PATH}/rpm-$state.png") {
		if (-e $_) {
		    $pix{$state} = [ gtkcreate_png($_) ];
		    last;
		}
	    }
	    $pix{$state} or die "unable to find a pixmap for state $state";
	}
	$tree->node_set_pixmap($node, 1, $pix{$state}[0], $pix{$state}[1]);
    };
    my $set_node_state_tree; $set_node_state_tree = sub {
	my ($node, $state) = @_;
	unless ($pix{$state}) {
	    foreach ("$ENV{SHARE_PATH}/$state.png", "$ENV{SHARE_PATH}/rpm-$state.png") {
		if (-e $_) {
		    $pix{$state} = [ gtkcreate_png($_) ];
		    last;
		}
	    }
	    $pix{$state} or die "unable to find a pixmap for state $state";
	}
	if ($node->{state} ne $state) {
	    if ($node->row->is_leaf) {
		my $parent = $node->row->parent;
		my $stats = $parent->{state_stats} ||= {}; --$stats->{$node->{state}}; ++$stats->{$state};
		my @list = grep { $stats->{$_} > 0 } keys %$stats;
		my $new_state = @list == 1 ? $list[0] : 'semiselected';
		$parent->{state} ne $new_state and $set_node_state_tree->($parent, $new_state);
	    }
	    $tree->node_set_pixmap($node, 1, $pix{$state}[0], $pix{$state}[1]);
	    $node->{state} = $state; #- hack to to get this features efficiently.
	}
    };
    my $set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;

    my $set_leaf_state = sub {
	my ($leaf, $state) = @_;
	$set_node_state->($_, $state) foreach @{$ptree{$leaf}};
    };
    my $add_parent; $add_parent = sub {
	my ($root, $state) = @_;
	$root or return undef;
	if (my $w = $wtree{$root}) { return $w }
	my $s; foreach (split '\|', $root) {
	    my $s2 = $s ? "$s|$_" : $_;
	    $wtree{$s2} ||= do {
		my $n = $tree->insert_node($s ? $add_parent->($s, $state) : undef, undef, [$_, '', ''], 5, (undef) x 4, 0, 0);
		$n;
	    };
	    $s = $s2;
	}
	$set_node_state->($wtree{$s}, $state); #- use this state by default as tree is building.
	$wtree{$s};
    };
    my $add_node = sub {
	my ($leaf, $root) = @_;
	my $state = $common->{node_state}($leaf) or return;
	my $node = $tree->insert_node($add_parent->($root, $state), undef, [$leaf, '', ''], 5, (undef) x 4, 1, 0);
	$set_node_state->($node, $state);
	push @{$ptree{$leaf}}, $node;
    };
    my $add_nodes = sub {
	foreach (values %ptree) {
	    delete $_->{state} foreach @$_;
	}
	foreach (values %wtree) {
	    delete $_->{state};
	    delete $_->{state_stats};
	}
	%ptree = %wtree = ();

	$tree->freeze;
	while (1) { $tree->remove_node($tree->node_nth(0) || last) }

	$common->{state}{flat} = $_[0];
	$set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;
	$common->{build_tree}($add_node, $common->{state}{flat});

	$tree->thaw;
	&$update_size;
    };
    $add_nodes->($common->{state}{flat});

    my @toolbar = (ftout  =>  [ _("Expand Tree") , sub { $tree->expand_recursive(undef) } ],
		   ftin   =>  [ _("Collapse Tree") , sub { $tree->collapse_recursive(undef) } ],
		   reload =>  [ _("Toggle between flat and group sorted"), sub { $add_nodes->(!$common->{state}{flat}) } ]);
    foreach my $ic (@{$common->{icons} || []}) {
	push @toolbar, ( $ic->{icon} => [ $ic->{help}, sub {
					     if ($ic->{code}) {
						 my $w = $ic->{wait_message} && $o->wait_message('', $ic->{wait_message});
						 $ic->{code}();
						 $add_nodes->($common->{state}{flat});
					     }
					 } ]);
    }
    my %toolbar = @toolbar;
    $toolbar->set_button_relief("none");
    foreach (grep_index { $::i % 2 == 0 } @toolbar) {
	gtksignal_connect($toolbar->append_item(undef, $toolbar{$_}[0], undef, gtkpng("$ENV{SHARE_PATH}/$_.png")),
			  clicked => $toolbar{$_}[1]);
    }
    $toolbar->set_style("icons");

    my $display_info = sub { gtktext_insert($info_widget, $common->{get_info}($curr)); 0 };
    my $children = sub { map { ($tree->node_get_pixtext($_, 0))[0] } gtkctree_children($_[0]) };
    my $toggle = sub {
	if (ref $curr && ! $_[0]) {
	    $tree->toggle_expansion($curr);
	} else {
	    if (ref $curr) {
		my @l = $common->{grep_allowed_to_toggle}($children->($curr)) or return;
		my @unsel = $common->{grep_unselected}(@l);
		my @p = @unsel ?
		  @unsel : # not all is selected, select all
		    @l;
		$common->{toggle_nodes}($set_leaf_state, @p);
		&$update_size;
		$parent = $curr;
	    } else {
		$common->{check_interactive_to_toggle}($curr) and $common->{toggle_nodes}($set_leaf_state, $curr);
		&$update_size;
	    }
	}
    };

    $tree->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr($e->{keyval} & 0xff);
	$toggle->(0) if $e->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ';
	1;
    });
    $tree->signal_connect(tree_select_row => sub {
	Gtk->timeout_remove($idle) if $idle;

	if ($_[1]->row->is_leaf) {
	    ($curr) = $tree->node_get_pixtext($_[1], 0);
	    $parent = $_[1]->row->parent;
	    $idle = Gtk->timeout_add(100, $display_info);
	} else {
	    $curr = $_[1];
	}
	$toggle->(1) if $_[2] == 1;
    });
    &$update_size;
    my $b = before_leaving { #- ensure cleaning here.
	foreach (values %ptree) {
	    delete $_->{state} foreach @$_;
	}
	foreach (values %wtree) {
	    delete $_->{state};
	    delete $_->{state_stats};
	}
    };
    $w->main;
}

sub wait_messageW($$$) {
    my ($o, $title, $messages) = @_;

    my $w = my_gtk->new($title, %$o, grab => 1);
    gtkadd($w->{window}, my $hbox = new Gtk::HBox(0,0));
    $hbox->pack_start(my $box = new Gtk::VBox(0,0), 1, 1, 10);  
    $box->pack_start($_, 1, 1, 4) foreach my @l = map { new Gtk::Label($_) } @$messages;

    ($w->{wait_messageW} = $l[$#l])->signal_connect(expose_event => sub { $w->{displayed} = 1 });
    $w->{rwindow}->set_position('center') if ($::isStandalone && !$::isEmbedded && !$::isWizard);
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
