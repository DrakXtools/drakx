package interactive::gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
use mygtk2;
use ugtk2 qw(:helpers :wrappers :create);
use Gtk2::Gdk::Keysyms;

my $forgetTime = 1000; #- in milli-seconds

sub new {
    ($::windowwidth, $::windowheight) = gtkroot()->get_size if !$::isInstall;
    goto &interactive::new;
}
sub enter_console { my ($o) = @_; $o->{suspended} = common::setVirtual(1) }
sub leave_console { my ($o) = @_; common::setVirtual(delete $o->{suspended}) }

sub exit { ugtk2::exit(@_) }

sub ask_fileW {
    my ($in, $common) = @_;

    my $w = ugtk2::create_file_selector(%$common);

    my $file;
    $w->main(sub { 
	$file = $w->{chooser}->get_filename;
	my $err = ugtk2::file_selected_check($common->{save}, $common->{want_a_dir}, $file);
	$err and $in->ask_warn('', $err);
	!$err;
    }) && $file;
}

sub create_boxradio {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;

    my $boxradio = gtkpack2__(Gtk2::VBox->new(0, 0),
			      my @radios = gtkradio('', @{$e->{formatted_list}}));
    my $tips = Gtk2::Tooltips->new;
    mapn {
	my ($txt, $w) = @_;
	$w->signal_connect(button_press_event => $double_click) if $double_click;

	$w->signal_connect(key_press_event => sub {
	    &$may_go_to_next;
	});
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
	my ($v, $full_struct) = @_;
	mapn { 
	    $_[0]->set_active($_[1] eq $v);
	    $full_struct->{focus_w} = $_[0] if $_[1] eq $v;
	} \@radios, $e->{list};
    }, $radios[0];
}

sub create_treeview_list {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
    my $curr;

    my $list = Gtk2::ListStore->new("Glib::String");
    my $list_tv = Gtk2::TreeView->new_with_model($list);
    $list_tv->set_headers_visible(0);
    $list_tv->get_selection->set_mode('browse');
    my $textcolumn = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0);
    $list_tv->append_column($textcolumn);
    
    my $select = sub {
	$list_tv->set_cursor($_[0], undef, 0);
    	$list_tv->scroll_to_cell($_[0], undef, 1, 0.5, 0);
    };

    my ($starting_word, $start_reg) = ('', '^');
    my $timeout;
    $list_tv->set_enable_search(0);
    $list_tv->signal_connect(key_press_event => sub {
        my ($_w, $event) = @_;
	my $c = chr($event->keyval & 0xff);

	Glib::Source->remove($timeout) if $timeout; $timeout = '';
	
	if ($event->keyval >= 0x100) {
	    &$may_go_to_next if member($event->keyval, ($Gtk2::Gdk::Keysyms{Return}, $Gtk2::Gdk::Keysyms{KP_Enter}));
	    $starting_word = '' if !member($event->keyval, ($Gtk2::Gdk::Keysyms{Control_L}, $Gtk2::Gdk::Keysyms{Control_R}));
	} else {
	    if (member('control-mask', @{$event->state})) {
		$c eq 's' or return 1;
		$start_reg and $start_reg = '', return 1;
		$curr++;
	    } else {
		&$may_go_to_next if $c eq ' ';

		$curr++ if $starting_word eq '' || $starting_word eq $c;
		$starting_word .= $c unless $starting_word eq $c;
	    }
	    my @l = @{$e->{formatted_list}};
	    my $word = quotemeta $starting_word;
	    my $j; for ($j = 0; $j < @l; $j++) {
		 $l[($j + $curr) % @l] =~ /$start_reg$word/i and last;
	    }
	    if ($j == @l) {
		$starting_word = '';
	    } else {
		$select->(Gtk2::TreePath->new_from_string(($j + $curr) % @l));
	    }

	    $timeout = Glib::Timeout->add($forgetTime, sub { $timeout = $starting_word = ''; 0 });
	}
	0;
    });
    $list_tv->show;

    $list->append_set([ 0 => $_ ]) foreach @{$e->{formatted_list}};

    $list_tv->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	my $row = $model->get_path_str($iter);
	${$e->{val}} = $e->{list}[$curr = $row];
	&$changed;
    });
    $list_tv->signal_connect(button_press_event => $double_click) if $double_click;

    $list_tv, sub {
	my ($v) = @_;
	eval {
	    my $nb = find_index { $_ eq $v } @{$e->{list}};
	    my ($old_path) = $list_tv->get_cursor;
	    if (!$old_path || $nb != $old_path->to_string) {
		$select->(Gtk2::TreePath->new_from_string($nb));
	    }
	    undef $old_path if $old_path;
	};
    };
}

sub __create_tree_model {
    my ($e) = @_;

    my $sep = quotemeta $e->{separator};
    my $tree_model = Gtk2::TreeStore->new("Glib::String", if_($e->{image2f}, "Gtk2::Gdk::Pixbuf"));

    my $build_value = sub {
	my ($v) = @_;
	my $type = 0;
	if ($e->{image2f}) {
	    my $image = $e->{image2f}->($_[0]);
	    ($type, $v) = (1, gtkcreate_pixbuf($image)) if $image; 
	}
	[ $type => $v ];
    };

    my (%wtree, $parent);
    $parent = sub {
	if (my $w = $wtree{"$_[0]$e->{separator}"}) { return $w }
	my $s = '';
	foreach (split $sep, $_[0]) {
	    $wtree{"$s$_$e->{separator}"} ||= 
	      $tree_model->append_set($s ? $parent->($s) : undef, $build_value->($_));
	    $s .= "$_$e->{separator}";
	}
	$wtree{$s};
    };

    $tree_model->{path_str_list} = [ map {
	my ($root, $leaf) = /(.*)$sep(.+)/ ? ($1, $2) : ('', $_);
	my $iter = $tree_model->append_set($parent->($root), $build_value->($leaf));

	$tree_model->get_path_str($iter);
    } @{$e->{formatted_list}} ];

    undef $_ foreach values %wtree;
    undef %wtree;

    $tree_model;
}

sub create_treeview_tree {
    my ($e, $may_go_to_next, $changed, $double_click, $tree_expanded) = @_;

    my $tree_model = __create_tree_model($e);
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    {
	my $col = Gtk2::TreeViewColumn->new;
	$col->pack_start(my $texrender = Gtk2::CellRendererText->new, 0);
	$col->add_attribute($texrender, text => 0);
	if ($e->{image2f}) {
	    $col->pack_start(my $pixrender = Gtk2::CellRendererPixbuf->new, 0);
	    $col->add_attribute($pixrender, pixbuf => 1);
	}
	$tree->append_column($col);
    }
    $tree->set_headers_visible(0);

    my $select = sub {
	my ($path_str) = @_;
	my $path = Gtk2::TreePath->new_from_string($path_str);
	$tree->expand_to_path($path);
	$tree->set_cursor($path, undef, 0);
        gtkflush();  #- workaround gtk2 bug not honouring centering on the given row if node was closed
	$tree->scroll_to_cell($path, undef, 1, 0.5, 0);
    };

    my $curr = $tree_model->get_iter_first; #- default value
    $tree->expand_all if $tree_expanded;

    my $selected_via_click;

    $tree->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	undef $curr if ref $curr;
	my $path = $tree_model->get_path($curr = $iter);
	if (!$tree_model->iter_has_child($iter)) {
	    my $path_str = $path->to_string;
	    my $i = find_index { $path_str eq $_ } @{$tree_model->{path_str_list}};
	    ${$e->{val}} = $e->{list}[$i];
	    &$changed;
	} else {
	    $tree->expand_row($path, 0) if $selected_via_click;
	}
    });
    my ($starting_word, $start_reg) = ('', "^");
    my $timeout;

    my $toggle = sub {
	if ($tree_model->iter_has_child($curr)) {
	    $tree->toggle_expansion($tree_model->get_path($curr), 0);

	} else {
	    &$may_go_to_next;
	}
    };

    $tree->set_enable_search(0);
    $tree->signal_connect(key_press_event => sub {
        my ($_w, $event) = @_;
	$selected_via_click = 0;
	my $c = chr($event->keyval & 0xff);
	$curr or return 0;
	Glib::Source->remove($timeout) if $timeout; $timeout = '';

	if ($event->keyval >= 0x100) {
	    &$toggle if member($event->keyval, ($Gtk2::Gdk::Keysyms{Return}, $Gtk2::Gdk::Keysyms{KP_Enter}));
	    $starting_word = '' if !member($event->keyval, ($Gtk2::Gdk::Keysyms{Control_L}, $Gtk2::Gdk::Keysyms{Control_R}));
	} else {
	    my $next;
	    if (member('control-mask', @{$event->state})) {
		$c eq "s" or return 1;
		$start_reg and $start_reg = '', return 0;
		$next = 1;
	    } else {
		&$toggle if $c eq ' ';
		$next = 1 if $starting_word eq '' || $starting_word eq $c;
		$starting_word .= $c unless $starting_word eq $c;
	    }
	    my $word = quotemeta $starting_word;
	    my ($after, $best);

	    my $sep = quotemeta $e->{separator};
	    my $currpath = $tree_model->get_path_str($curr);
	    mapn {
		my ($path_str, $v) = @_;
		$next &&= !$after;
		$after ||= $path_str eq $currpath;
		$v =~ s/.*$sep//;
		if ($v =~ /$start_reg$word/i) {
		    if ($after && !$next) {
			($best, $after) = ($path_str, 0);
		    } else {
			$best ||= $path_str;
		    }
		}
	    } $tree_model->{path_str_list}, $e->{formatted_list};

	    if (defined $best) {
		$select->($best);
	    } else {
		$starting_word = '';
	    }

	    $timeout = Glib::Timeout->add($forgetTime, sub { $timeout = $starting_word = ''; 0 });
	}
	0;
    });
    $tree->signal_connect(button_press_event => sub {
	$selected_via_click = 1;
	&$double_click if $curr && !$tree_model->iter_has_child($curr) && $double_click;
    });

    $tree, sub {
        my $v = may_apply($e->{format}, $_[0]);
        eval {
            my $i = find_index { $v eq $_ } @{$e->{formatted_list}};

            my ($model, $iter) = $tree->get_selection->get_selected;

            my $new_path_str = $tree_model->{path_str_list}[$i];
            my $old_path_str = $model && $tree_model->get_path_str($iter);

            $select->($new_path_str) if $new_path_str ne $old_path_str;
            undef $iter if ref $iter;
        };
    };
}

sub create_list {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;
    my $l = $e->{list};
    my $list = Gtk2::List->new;
    $list->set_selection_mode('browse');

    my $select = sub {
	$list->select_item($_[0]);
    };

    my $tips = Gtk2::Tooltips->new;
    each_index {
	my $item = Gtk2::ListItem->new(may_apply($e->{format}, $_));
	$item->signal_connect(key_press_event => sub {
    	    my ($_w, $event) = @_;
    	    my $c = chr($event->keyval & 0xff);
	    &$may_go_to_next if $event->keyval < 0x100 ? $c eq ' ' : $c eq "\r" || $c eq "\x8d";
    	    0;
    	});
	$list->append_items(gtkshow($item));
	if ($e->{help}) {
	    gtkset_tip($tips, $item,
		       ref($e->{help}) eq 'HASH' ? $e->{help}{$_} :
		       ref($e->{help}) eq 'CODE' ? $e->{help}($_) : $e->{help});
	}
	$item->grab_focus if ${$e->{val}} && $_ eq ${$e->{val}};
    } @$l;

    #- signal_connect'ed after append_items otherwise it is called and destroys the default value
    $list->signal_connect(select_child => sub {
	my ($_w, $row) = @_;
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

#- $actions is a ref list of $action
#- $action is a { kind => $kind, action => sub { ... }, button => Gtk2::Button->new(...) }
#-   where $kind is one of '', 'modify', 'remove', 'add'
sub add_modify_remove_action {
    my ($button, $buttons, $e, $treelist) = @_;

    if (member($button->{kind}, 'modify', 'remove')) {
	@{$e->{list}} or return;
    }
    my $r = $button->{action}->(${$e->{val}});
    defined $r or return;
    
    if ($button->{kind} eq 'add') {
	${$e->{val}} = $r;
    } elsif ($button->{kind} eq 'remove') {
	${$e->{val}} = $e->{list}[0];
    }
    ugtk2::gtk_set_treelist($treelist, [ map { may_apply($e->{format}, $_) } @{$e->{list}} ]);

    add_modify_remove_sensitive($buttons, $e);
    1;
}

sub add_modify_remove_sensitive {
    my ($buttons, $e) = @_;
    $_->{button}->set_sensitive(@{$e->{list}} != ()) foreach 
      grep { member($_->{kind}, 'modify', 'remove') } @$buttons;
}

sub ask_fromW {
    my ($o, $common, $l, $l2) = @_;
    my $ignore = 0; #-to handle recursivity

    my $mainw = ugtk2->new($common->{title}, %$o, modal => 1, if__($::main_window, transient => $::main_window), if_($common->{icon}, icon => $common->{icon}));
 
    #-the widgets
    my (@widgets, @widgets_always, @widgets_advanced, $advanced);
    my $tooltips = Gtk2::Tooltips->new;
    my $ok_clicked = sub { 
	!$mainw->{ok} || $mainw->{ok}->get_property('sensitive') or return;
	$mainw->{retval} = 1;
	Gtk2->main_quit;
    };
    my $set_all = sub {
	$ignore = 1;
	$_->{set}->(${$_->{e}{val}}, $_) foreach @widgets_always, @widgets_advanced;
	$_->{real_w}->set_sensitive(!$_->{e}{disabled}()) foreach @widgets_always, @widgets_advanced;
	$mainw->{ok}->set_sensitive(!$common->{callbacks}{ok_disabled}()) if $common->{callbacks}{ok_disabled};
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

    my @label_sizegrp = map { Gtk2::SizeGroup->new('horizontal') } 0 .. 1;
    my @realw_sizegrp = map { Gtk2::SizeGroup->new('horizontal') } 0 .. 1;

    my $create_widget = sub {
	my ($e, $ind) = @_;

	my $may_go_to_next = sub {
	    my (undef, $event) = @_;
	    if (!$event || ($event->keyval & 0x7f) == 0xd) {
		if ($ind == $#widgets) {
		    @widgets == 1 ? $ok_clicked->() : $mainw->{ok}->grab_focus;
		} else {
		    $widgets[$ind+1]{focus_w}->grab_focus;
		}
		return 1;  #- prevent an action on the just grabbed focus
	    }
	};
	my $changed = sub { $update->(sub { $common->{callbacks}{changed}($ind) }) };

	my ($w, $real_w, $focus_w, $set, $get, $grow);
	if ($e->{type} eq 'iconlist') {
	    $w = Gtk2::Button->new;
	    $set = sub {
		gtkdestroy($e->{icon});
		my $f = $e->{icon2f}->($_[0]);
		$e->{icon} = -e $f ?
		    gtkcreate_img($f) :
		    Gtk2::WrappedLabel->new(may_apply($e->{format}, $_[0]));
		$w->add(gtkshow($e->{icon}));
	    };
	    $w->signal_connect(clicked => sub {
		$set->(${$e->{val}} = next_val_in_array(${$e->{val}}, $e->{list}));
		$changed->();
	    });
	    $real_w = gtkpack_(Gtk2::HBox->new(0,10), 1, Gtk2::HBox->new(0,0), 0, $w, 1, Gtk2::HBox->new(0,0));
	} elsif ($e->{type} eq 'bool') {
	    if ($e->{image}) {
		$w = ugtk2::gtkadd(Gtk2::CheckButton->new, gtkshow(gtkcreate_img($e->{image})));
	    } else {
#-		warn "\"text\" member should have been used instead of \"label\" one at:\n", common::backtrace(), "\n" if $e->{label} && !$e->{text};
		$w = Gtk2::CheckButton->new_with_label($e->{text});
	    }
	    $w->signal_connect(clicked => $changed);
	    $set = sub { $w->set_active($_[0]) };
	    $get = sub { $w->get_active };
	} elsif ($e->{type} eq 'label') {
	    $w = Gtk2::WrappedLabel->new(${$e->{val}});
	    $set = sub { $w->set($_[0]) };
	} elsif ($e->{type} eq 'button') {
	    $w = Gtk2::Button->new_with_label('');
	    $w->signal_connect(clicked => sub {
		$get_all->();
		$mainw->{rwindow}->hide;
		if (my $v = $e->{clicked_may_quit}()) {
		    $mainw->{retval} = $v;
		    Gtk2->main_quit;
		}
		$mainw->{rwindow}->show;
		$set_all->();
	    });
	    $set = sub { $w->child->set_label(may_apply($e->{format}, $_[0])) };
	} elsif ($e->{type} eq 'range') {
	    my $want_scale = !$::expert;
	    my $adj = Gtk2::Adjustment->new(${$e->{val}}, $e->{min}, $e->{max} + ($want_scale ? 1 : 0), 1, ($e->{max} - $e->{min}) / 10, 1);
	    $adj->signal_connect(value_changed => $changed);
	    $w = $want_scale ? Gtk2::HScale->new($adj) : Gtk2::SpinButton->new($adj, 10, 0);
	    $w->set_size_request($want_scale ? 200 : 100, -1);
	    $w->set_digits(0);
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $set = sub { $adj->set_value($_[0]) };
	    $get = sub { $adj->get_value };
	} elsif ($e->{type} =~ /list/) {

	    $e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];

	    if (my $actions = $e->{add_modify_remove}) {
		my @buttons = map {
		    { kind => lc $_, action => $actions->{$_}, button => Gtk2::Button->new(translate($_)) };
		} N_("Add"), N_("Modify"), N_("Remove");
		my $modify = find { $_->{kind} eq 'modify' } @buttons;

		my $do_action = sub {
		    my ($button) = @_;
		    add_modify_remove_action($button, \@buttons, $e, $w) and $changed->();
		};

		($w, $set, $focus_w) = create_treeview_list($e, $may_go_to_next, $changed, 
							    sub { $do_action->($modify) if $_[1]->type =~ /^2/ });
		$e->{saved_default_val} = ${$e->{val}};

		foreach my $button (@buttons) {
		    $button->{button}->signal_connect(clicked => sub { $do_action->($button) });
		}
		add_modify_remove_sensitive(\@buttons, $e);

		$real_w = gtkpack_(Gtk2::HBox->new(0,0),
				   1, create_scrolled_window($w), 
				   0, gtkpack__(Gtk2::VBox->new(0,0), map { $_->{button} } @buttons));
		$grow = 1;
	    } else {

		my $quit_if_double_click = 
		  #- i'm the only one, double click means accepting
		  @$l == 1 || $e->{quit_if_double_click} ? 
		    sub { $_[1]->type =~ /^2/ && $ok_clicked->() } : ''; 

		my @para = ($e, $may_go_to_next, $changed, $quit_if_double_click);
		my $use_boxradio = exists $e->{gtk}{use_boxradio} ? $e->{gtk}{use_boxradio} : @{$e->{list}} <= 8;

		if ($e->{help}) {
		    #- used only when needed, as key bindings are dropped by List (ListStore does not seems to accepts Tooltips).
		    ($w, $set, $focus_w) = $use_boxradio ? create_boxradio(@para) : create_list(@para);
		} elsif ($e->{type} eq 'treelist') {
		    ($w, $set) = create_treeview_tree(@para, $e->{tree_expanded});
		    $e->{saved_default_val} = ${$e->{val}}; #- during realization, signals will mess up the default val :(
		} else {
		    if ($use_boxradio) {
			($w, $set, $focus_w) = create_boxradio(@para);
		    } else {
			($w, $set, $focus_w) = create_treeview_list(@para);
			$e->{saved_default_val} = ${$e->{val}};
		    }
		}
		if (@{$e->{list}} > 10) {
		    $real_w = create_scrolled_window($w);
		    $grow = 1;
		}
	    }
	} else {
	    if ($e->{type} eq "combo") {
		my $model;

		my @formatted_list = map { may_apply($e->{format}, $_) } @{$e->{list}};
		$e->{formatted_list} = \@formatted_list;

		my @l = sort { $b <=> $a } map { length } @formatted_list;
		my $width = $l[@l / 16]; # take the third octile (think quartile)

		if (!$e->{separator}) {
		    if ($e->{not_edit} && $width < 160) { #- ComboBoxes do not have an horizontal scroll-bar. This can cause havoc for long strings (eg: diskdrake Create dialog box in expert mode)
			$w = Gtk2::ComboBox->new_text;
		    } else {
			$w = Gtk2::Combo->new;
			$w->set_use_arrows_always(1);
			$w->entry->set_editable(!$e->{not_edit});
			$w->disable_activate;
		    }
		    $w->set_popdown_strings(@formatted_list);
		    $w->set_text(ref($e->{val}) ? may_apply($e->{format}, ${$e->{val}}) : $formatted_list[0]) if $w->isa('Gtk2::ComboBox');
		} else {
		    $model = __create_tree_model($e);
		    $w = Gtk2::ComboBox->new_with_model($model);

		    $w->pack_start(my $texrender = Gtk2::CellRendererText->new, 0);
		    $w->add_attribute($texrender, text => 0);
		    if ($e->{image2f}) {
			$w->pack_start(my $pixrender = Gtk2::CellRendererPixbuf->new, 0);
			$w->add_attribute($pixrender, pixbuf => 1);
		    }
		}
		($real_w, $w) = ($w, $w->entry);

		#- FIXME workaround gtk suckiness (set_text generates two 'change' signals, one when removing the whole, one for inserting the replacement..)
		my $idle;
		$w->signal_connect(changed => sub {
		    $idle ||= Glib::Idle->add(sub { undef $idle; $changed->(); 0 });
		});

		$set = sub {
		    my $s = may_apply($e->{format}, $_[0]);
		    if ($model) {
			eval {
			    my $i = find_index { $s eq $_ } @{$e->{formatted_list}};
			    my $path_str = $model->{path_str_list}[$i];
			    $w->set_active_iter($model->get_iter_from_string($path_str));
			};
		    } else {
			$w->set_text($s) if $s ne $w->get_text && $_[0] ne $w->get_text;
		    }
		};
		$get = sub {
		    my $i = $model ? do {
			my $s = $model->get_string_from_iter($w->get_active_iter);
			eval { find_index { $s eq $_ } @{$model->{path_str_list}} };
		    } : do {
			my $s = $w->get_text;
			eval { find_index { $s eq $_ } @formatted_list };
		    };
		    defined $i ? $e->{list}[$i] : $w->get_text;
		};
	    } else {
                $w = Gtk2::Entry->new;
		$w->signal_connect(changed => $changed);
		$w->signal_connect(focus_in_event => sub { $w->select_region(0, -1) });
		$w->signal_connect(focus_out_event => sub { $w->select_region(0, 0) });
		$set = sub { $w->set_text($_[0]) if $_[0] ne $w->get_text };
		$get = sub { $w->get_text };
	    }
	    $w->signal_connect(key_press_event => $may_go_to_next);
	    $w->set_visibility(0) if $e->{hidden};
	}
	$w->signal_connect(focus_out_event => sub { 
            $update->(sub { $common->{callbacks}{focus_out}($ind) });
	});
	$tooltips->set_tip($w, $e->{help}) if $e->{help} && !ref($e->{help});

	$real_w ||= $w;
	$real_w = gtkpack_(Gtk2::HBox->new,
			   if_($e->{icon}, 0, eval { gtkcreate_img($e->{icon}) }),
			   0, gtkadd_widget($label_sizegrp[$e->{advanced} ? 1 : 0], $e->{label}),
			   1, gtkadd_widget($realw_sizegrp[$e->{advanced} ? 1 : 0], $real_w),
			  ) if !$real_w->isa("Gtk2::CheckButton") || $e->{icon} || $e->{label};

	{ e => $e, w => $w, real_w => $real_w, focus_w => $focus_w || $w,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {}, grow => $grow };
    };
    @widgets_always   = map_index { $create_widget->($_, $::i)       } @$l;
    @widgets_advanced = map_index { $create_widget->($_, $::i + @$l) } @$l2;

    $mainw->{box_allow_grow} = 1;
    my $pack = create_box_with_title($mainw, @{$common->{messages}});
    mygtk2::set_main_window_size($mainw->{rwindow}) if $mainw->{pop_it} && (@$l || $mainw->{box_size} == 200);

    my @before_widgets_advanced = (
	  (map { { grow => 0, real_w => Gtk2::WrappedLabel->new($_) } } @{$common->{advanced_messages}}),
	    { grow => 0, real_w => Gtk2::HSeparator->new },
    );

    my $first_time = 1;
    my $set_advanced = sub {
	($advanced) = @_;
	$update->($common->{callbacks}{advanced}) if $advanced && !$first_time;
	foreach (@before_widgets_advanced, @widgets_advanced) {
	    my $w = $_->{embed_scroll} || $_->{real_w};
	    $advanced ? $w->show : $w->hide;
	}	    
	@widgets = (@widgets_always, if_($advanced, @widgets_advanced));
	$first_time = 0;
	$set_all->(); #- must be done when showing advanced lists (to center selected value)
    };
    if ($::expert && @$l2) {
        $common->{advanced_state} = 1;
    }
    my $advanced_button = [ $common->{advanced_state} ? $common->{advanced_label_close} : $common->{advanced_label},
			    sub { 
				my ($w) = @_;
				$set_advanced->(!$advanced);
				$w->child->set_label($advanced ? $common->{advanced_label_close} : $common->{advanced_label});
			    } ];

    my @more_buttons = (
			if_($common->{interactive_help}, 
			    [ N("Help"), sub { 
				  my $message = $common->{interactive_help}->() or return;
				  $o->ask_warn(N("Help"), $message);
			      }, 1 ]),
			if_($common->{more_buttons}, @{$common->{more_buttons}}),
		       );
    my $buttons_pack = ($common->{ok} || !exists $common->{ok}) && $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @more_buttons, if_(@$l2, $advanced_button));
    
    my @widgets_to_pack;
    foreach my $l (\@widgets_always, if_(@widgets_advanced, [ @before_widgets_advanced, @widgets_advanced ])) {
	my @grouped;
	my $add_grouped = sub {
	    if (@grouped == 0) {
	    } elsif (@grouped == 1) {
		push @widgets_to_pack, 0 => $grouped[0]{real_w};
	    } else {
		my $scroll = create_scrolled_window(gtkpack__(Gtk2::VBox->new(0,0), map { $_->{real_w} } @grouped),
						    [ 'automatic', 'automatic' ], 'none');
		$_->{embed_scroll} = $scroll foreach @grouped;
		push @widgets_to_pack, 1 => $scroll;
	    }
	    @grouped = ();
	};
	foreach (@$l) {
	    if ($_->{grow}) {
		$add_grouped->();
		push @widgets_to_pack, 1 => $_->{real_w};
	    } else {
		push @grouped, $_;
	    }
	}
	$add_grouped->();
    }

    gtkpack_($pack, @widgets_to_pack);
	    
    if ($buttons_pack) {
	$pack->pack_end(gtkshow($buttons_pack), 0, 0, 0);
    }
    ugtk2::gtkadd($mainw->{window}, $pack);
    $set_advanced->($common->{advanced_state});
    
    my $widget_to_focus =
      $common->{focus_cancel} ? $mainw->{cancel} :
	@widgets && ($common->{focus_first} || !$mainw->{ok} || @widgets == 1 && member(ref($widgets[0]{focus_w}), "Gtk2::TreeView", "Gtk2::RadioButton")) ? 
	  $widgets[0]{focus_w} : 
	    $mainw->{ok};
    $widget_to_focus->grab_focus if $widget_to_focus;

    my $check = sub {
	my ($f) = @_;
	sub {
	    $get_all->();
	    my ($error, $focus) = $f->();
	
	    if ($error) {
		$set_all->();
		if (my $to_focus = $widgets[$focus || 0]) {
		    $to_focus->{focus_w}->grab_focus;
		} else {
		    log::l("ERROR: bad entry number given to focus " . backtrace());
		}
	    }
	    !$error;
	};
    };

    $_->{set}->($_->{e}{saved_default_val} || next) foreach @widgets_always, @widgets_advanced;
    $mainw->main(map { $check->($common->{callbacks}{$_}) } 'complete', 'canceled');
}


sub ask_browse_tree_info_refW {
    my ($o, $common) = @_;
    add2hash($common, { wait_message => sub { $o->wait_message(@_) } });
    ugtk2::ask_browse_tree_info($common);
}


sub ask_from__add_modify_removeW {
    my ($o, $title, $message, $l, %callback) = @_;

    my $e = $l->[0];
    my $chosen_element;
    put_in_hash($e, { allow_empty_list => 1, gtk => { use_boxradio => 0 }, sort => 0,
		      val => \$chosen_element, type => 'list', add_modify_remove => \%callback });

    $o->ask_from($title, $message, $l, %callback);
}

sub wait_messageW {
    my ($_o, $title, $messages) = @_;

    my $to_modify;
    my @l = map { ref $_ ? (0, $_) : (1, $to_modify = Gtk2::Label->new(scalar warp_text($_))) } @$messages;
    $l[0] = 0; #- force first one

    my $Window = gtknew('MagicWindow',
			title => $title,
			pop_it => !$::isInstall, 
			modal => 1, 
			if__($::main_window, transient_for => $::main_window),
			child => gtknew('VBox', padding => 4, border_width => 10, children => \@l),
		      );
    $Window->signal_connect(expose_event => sub { $Window->{displayed} = 1; 0 });
    $Window->{wait_messageW} = $to_modify;
    mygtk2::sync($Window) while !$Window->{displayed};
    $Window;
}
sub wait_message_nextW {
    my ($_o, $messages, $Window) = @_;
    my $msg = warp_text(join "\n", @$messages);
    return if $msg eq $Window->{wait_messageW}->get_text; #- needed otherwise no expose_event :(
    $Window->{displayed} = 0;
    $Window->{wait_messageW}->set($msg);
    mygtk2::sync($Window) while !$Window->{displayed};
}
sub wait_message_endW {
    my ($_o, $Window) = @_;
    mygtk2::may_destroy($Window);
    mygtk2::flush();
}

sub kill {
    my ($_o) = @_;
    $_->destroy foreach $::WizardTable ? $::WizardTable->get_children : (), @tempory::objects;
    @tempory::objects = ();
}

1;
