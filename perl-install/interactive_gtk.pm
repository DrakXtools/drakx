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
sub ask_from_listW {
    my ($o, $title, $messages, $l, $def, $help) = @_;
    my $r;

    my $w = my_gtk->new(first(deref($title)), %$o);
    test_embedded($w);
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
    test_embedded($w);
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

sub create_list {
    my ($e, $may_go_to_next_) = @_;
    my $list = new Gtk::List();
    $list->set_selection_mode('browse');
    my ($curr);
    my $l = $e->{list};

    my $select = sub {
	$list->select_item($_[0]);
    };
    my $tips = new Gtk::Tooltips;
    my $toselect;
    my @widgets = map_index {
	my $item = new Gtk::ListItem($_);
	$item->signal_connect(key_press_event => sub {
    	    my ($w, $e) = @_;
    	    my $c = chr($e->{keyval} & 0xff);
	    $may_go_to_next_->($e) if $e->{keyval} < 0x100 ? $c eq ' ' : $c eq "\r" || $c eq "\x8d";
    	    1;
    	});
	$list->append_items($item);
	if ($e->{help}) {
	    $tips->set_tip($item,
			   ref($e->{help}) eq 'HASH' ? $e->{help}{$_} :
			   ref($e->{help}) eq 'CODE' ? $e->{help}($_) : $e->{help});
	}
	$item->show;
	$toselect = $::i if ${$e->{val}} && $_ eq ${$e->{val}};
	$item->grab_focus if ${$e->{val}} && $_ eq ${$e->{val}};
	$item;
    } @$l;

    &$select($toselect);

    #- signal_connect after append_items otherwise it is called and destroys the default value
    $list->signal_connect(select_child => sub {
	my ($w, $row) = @_;
	${$e->{val}} = $l->[$list->child_position($row)];
    });

    may_createScrolledWindow(@$l > 15, $list, 200, min(350, $::windowheight - 60)), 
      $list,
	sub { $list->select_item(find_index { $_ eq ${$e->{val}} } @$l) };
}

sub ask_from_entries_refW {
    my ($o, $common, $l, $l2) = @_;
    my $ignore = 0; #-to handle recursivity

    my $mainw = my_gtk->new($common->{title}, %$o);
    test_embedded($mainw);
    $mainw->sync; # for XPM's creation

    #-the widgets
    my (@widgets, @widgets_always, @widgets_advanced, $advanced, $advanced_pack);
    my $tooltips = new Gtk::Tooltips;

    my $set_all = sub {
	$ignore = 1;
	$_->{set}->(${$_->{e}{val}}) foreach @widgets_always, @widgets_advanced;
	$ignore = 0;
    };
    my $get_all = sub {
	${$_->{e}{val}} = $_->{get}->() foreach @widgets_always, @widgets_advanced;
    };
    my $create_widget = sub {
	my ($e, $ind) = @_;

	my $may_go_to_next = sub {
	    my ($w, $e) = @_;
	    if (!$e || ($e->{keyval} & 0x7f) == 0xd) {
		$w->signal_emit_stop("key_press_event") if $e;
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

	my ($w, $real_w, $set, $get);
	if ($e->{type} eq "iconlist") {
	    $w = new Gtk::Button;
	    $set = sub {
		gtkdestroy($e->{icon});
		my $f = $e->{icon2f}->($_[0]);
		$e->{icon} = -e $f ?
		  new Gtk::Pixmap(gtkcreate_xpm($mainw->{window}, $f)) :
		    new Gtk::Label(translate($_[0]));
		$w->add($e->{icon});
		$e->{icon}->show;
	    };
	    $w->signal_connect(clicked => sub {		
		$set->(${$e->{val}} = next_val_in_array(${$e->{val}}, $e->{list}));
		$changed->();
	    });
	    $real_w = gtkpack_(new Gtk::HBox(0,10), 1, new Gtk::HBox(0,0), 0, $w, 1, new Gtk::HBox(0,0), );
	} elsif ($e->{type} eq "bool") {
	    $w = Gtk::CheckButton->new($e->{text});
	    $w->signal_connect(clicked => $changed);
	    $set = sub { $w->set_active($_[0]) };
	    $get = sub { $w->get_active };
	} elsif ($e->{type} eq "range") {
	    my $adj = create_adjustment(${$e->{val}}, $e->{min}, $e->{max});
	    $adj->signal_connect(value_changed => $changed);
	    $w = new Gtk::HScale($adj);
	    $w->set_digits(0);
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $set = sub { $adj->set_value($_[0]) };
	    $get = sub { $adj->get_value };
	} elsif ($e->{type} eq "list") {
	    #- use only when needed, as key bindings are dropped by List (CList does not seems to accepts Tooltips).
#	    if ($e->{help}) {
		($real_w, $w, $set) = create_list($e, $may_go_to_next);
#	     } else {
#		 die;
#	     }
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
    
	{ e => $e, w => $w, real_w => $real_w || $w, 
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

    $set_all->();
    gtkadd($mainw->{window},
	   gtkpack(create_box_with_title($mainw, @{$common->{messages}}),
		   may_createScrolledWindow(@widgets_always > 8, create_packtable({}, map { [($_->{icon_w}, $_->{e}{label}, $_->{real_w})]} @widgets_always), 200, min(350, $::windowheight - 60)),
		   new Gtk::HSeparator,
		   $advanced_pack = create_packtable({}, map { [($_->{icon_w}, $_->{e}{label}, $_->{real_w})]} @widgets_advanced),
		   $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @$l2 ? $advanced_button : ())));
    $set_advanced->(0);
    (@widgets ? $widgets[0]{w} : $mainw->{ok})->grab_focus();

    $mainw->main(sub {
        $get_all->();
        my ($error, $focus) = $common->{callbacks}{complete}->();
	
	if ($error) {
	    $set_all->();
	    $widgets[$focus || 0]{w}->grab_focus();
	}
	!$error;
    });
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
