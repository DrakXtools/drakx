package interactive::gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
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
    my ($_o, $title, $dir) = @_;
    my $w = ugtk2->new($title);
    $dir .= '/' if $dir !~ m|/$|;
    ugtk2::_ask_file($w, $title, $dir); 
    $w->main;
}

sub create_boxradio {
    my ($e, $may_go_to_next, $changed, $double_click) = @_;

    my $boxradio = gtkshow(gtkpack2__(Gtk2::VBox->new(0, 0),
                                      my @radios = gtkradio('', @{$e->{formatted_list}})));
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

sub create_treeview_tree {
    my ($e, $may_go_to_next, $changed, $double_click, $tree_expanded) = @_;

    $tree_expanded = to_bool($tree_expanded); #- to reduce "Use of uninitialized value", especially when debugging

    my $sep = quotemeta $e->{separator};
    my $tree_model = Gtk2::TreeStore->new("Glib::String", "Gtk2::Gdk::Pixbuf", "Glib::String");
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererPixbuf->new, 'pixbuf' => 1));
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 2));
    $tree->set_headers_visible(0);

    my ($build_value, $clean_image);
    if (exists $e->{image2f}) {
	my $to_unref;
	$build_value = sub {
	    my ($text, $image) = $e->{image2f}->($_[0]);
	    [ $text  ? (0 => $text) : @{[]},
	      $image ? (1 => $to_unref = gtkcreate_pixbuf($image)) : @{[]} ];
	};
	$clean_image = sub { undef $to_unref };
    } else {
	$build_value = sub { [ 0 => $_[0] ] };
	$clean_image = sub {};
    }

    my (%wtree, %wleaves, $size, $selected_via_click);
    my $parent; $parent = sub {
	if (my $w = $wtree{"$_[0]$e->{separator}"}) { return $w }
	my $s = '';
	foreach (split $sep, $_[0]) {
	    $wtree{"$s$_$e->{separator}"} ||= 
	      $tree_model->append_set($s ? $parent->($s) : undef, $build_value->($_));
	    $clean_image->();
	    $size++ if !$s;
	    $s .= "$_$e->{separator}";
	}
	$wtree{$s};
    };

    #- do some precomputing to not slowdown selection change and key press
    my (%precomp, @ordered_keys);
    mapn {
	my ($root, $leaf) = $_[0] =~ /(.*)$sep(.+)/ ? ($1, $2) : ('', $_[0]);
	my $iter = $tree_model->append_set($parent->($root), $build_value->($leaf));
	$clean_image->();
	my $pathstr = $tree_model->get_path_str($iter);
	$precomp{$pathstr} = { value => $leaf, fullvalue => $_[0], listvalue => $_[1] };
	push @ordered_keys, $pathstr;
	$wleaves{$_[0]} = $pathstr;
    } $e->{formatted_list}, $e->{list};
    undef $_ foreach values %wtree;
    undef %wtree;

    my $select = sub {
	my ($path_str) = @_;
	$tree->expand_to_path(Gtk2::TreePath->new_from_string($path_str));
	my $path = Gtk2::TreePath->new_from_string($path_str);
	$tree->set_cursor($path, undef, 0);
        gtkflush();  #- workaround gtk2 bug not honouring centering on the given row if node was closed
	$tree->scroll_to_cell($path, undef, 1, 0.5, 0);
    };

    my $curr = $tree_model->get_iter_first; #- default value
    $tree->expand_all if $tree_expanded;

    $tree->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	undef $curr if ref $curr;
	my $path = $tree_model->get_path($curr = $iter);
	if (!$tree_model->iter_has_child($iter)) {
	    ${$e->{val}} = $precomp{$path->to_string}{listvalue};
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

    $tree->signal_connect(key_press_event => sub {
        my ($_w, $event) = @_;
	$selected_via_click = 0;
	my $c = chr($event->keyval & 0xff);
	$curr or return;
	Glib::Source->remove($timeout) if $timeout; $timeout = '';

	if ($event->keyval >= 0x100) {
	    &$toggle if member($event->keyval, ($Gtk2::Gdk::Keysyms{Return}, $Gtk2::Gdk::Keysyms{KP_Enter}));
	    $starting_word = '' if !member($event->keyval, ($Gtk2::Gdk::Keysyms{Control_L}, $Gtk2::Gdk::Keysyms{Control_R}));
	} else {
	    my $next;
	    if (member('control-mask', @{$event->state})) {
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

	    my $currpath = $tree_model->get_path_str($curr);
	    foreach my $v (@ordered_keys) { 
		$next &&= !$after;
		$after ||= $v eq $currpath;
		if ($precomp{$v}{value} =~ /$start_reg$word/i) {
		    if ($after && !$next) {
			($best, $after) = ($v, 0);
		    } else {
			$best ||= $v;
		    }
		}
	    }

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
	&$double_click if !$tree_model->iter_has_child($curr) && $double_click;
    });

    $tree, sub {
	my $v = may_apply($e->{format}, $_[0]);
	my ($model, $iter) = $tree->get_selection->get_selected;
	$select->($wleaves{$v} || return) if !$model || $wleaves{$v} ne $model->get_path_str($iter);
	undef $iter if ref $iter;
    }, $size;
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

sub ask_fromW {
    my ($o, $common, $l, $l2) = @_;
    my $ignore = 0; #-to handle recursivity

    my $mainw = ugtk2->new($common->{title}, %$o, if__($::main_window, transient => $::main_window));
 
    #-the widgets
    my (@widgets, @widgets_always, @widgets_advanced, $advanced, $advanced_pack, $has_horiz_scroll, $has_scroll);
    my $max_width = 0;
    my $total_size = 0;
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

	my ($w, $real_w, $focus_w, $set, $get, $expand, $size);
	my $width = 0;
	if ($e->{type} eq 'iconlist') {
	    $w = Gtk2::Button->new;
	    $set = sub {
		gtkdestroy($e->{icon});
		my $f = $e->{icon2f}->($_[0]);
		$e->{icon} = -e $f ?
		    gtkcreate_img($f) :
		    Gtk2::Label->new(may_apply($e->{format}, $_[0]));
		$w->add(gtkshow($e->{icon}));
	    };
	    $w->signal_connect(clicked => sub {
		$set->(${$e->{val}} = next_val_in_array(${$e->{val}}, $e->{list}));
		$changed->();
	    });
	    $real_w = gtkpack_(Gtk2::HBox->new(0,10), 1, Gtk2::HBox->new(0,0), 0, $w, 1, Gtk2::HBox->new(0,0));
	} elsif ($e->{type} eq 'bool') {
	    if ($e->{image}) {
		$w = gtkadd(Gtk2::CheckButton->new, gtkshow(gtkcreate_img($e->{image})));
	    } else {
#-		warn "\"text\" member should have been used instead of \"label\" one at:\n", common::backtrace(), "\n" if $e->{label} && !$e->{text};
		$w = Gtk2::CheckButton->new_with_label($e->{text});
	    }
	    $w->signal_connect(clicked => $changed);
	    $set = sub { $w->set_active($_[0]) };
	    $get = sub { $w->get_active };
	    $width = length $e->{text};
	} elsif ($e->{type} eq 'label') {
	    $w = Gtk2::Label->new(${$e->{val}});
	    $set = sub { $w->set($_[0]) };
	    $width = length ${$e->{val}};
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
	    $width = length may_apply($e->{format}, ${$e->{val}});
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
	    $size = 2;
	} elsif ($e->{type} =~ /list/) {

	    $e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];
	    $width = max(map { length } @{$e->{list}});

	    if (my $actions = $e->{add_modify_remove}) {
		my %buttons;
		my $do_action = sub {
		    @{$e->{list}} || $_[0] eq 'Add' or return;
		    my $r = $actions->{$_[0]}->(${$e->{val}});
		    defined $r or return;

		    if ($_[0] eq 'Add') {
			${$e->{val}} = $r;
		    } elsif ($_[0] eq 'Remove') {
			${$e->{val}} = $e->{list}[0];
		    }
		    $e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];
		    my $list = $w->get_model;
		    $list->clear;
		    $list->append_set([ 0 => $_ ]) foreach @{$e->{formatted_list}};
		    $changed->();
		    $buttons{$_}->set_sensitive(@{$e->{list}} != ()) foreach 'Modify', 'Remove';
		};
		my @actions = (N_("Add"), N_("Modify"), N_("Remove"));

		$width += max(map { length(translate($_)) } @actions);
		$has_scroll = $expand = 1;
		$size = 6;
		($w, $set, $focus_w) = create_treeview_list($e, $may_go_to_next, $changed, 
							    sub { $do_action->('Modify') if $_[1]->type =~ /^2/ });
		$e->{saved_default_val} = ${$e->{val}};

		%buttons = map {
		    my $action = $_;
		    $action => gtksignal_connect(Gtk2::Button->new(translate($action)),
						 clicked => sub { $do_action->($action) });
		} @actions;
		$w->set_size_request(400, -1);
		$real_w = gtkpack_(Gtk2::HBox->new(0,0),
				   1, create_scrolled_window($w), 
				   0, gtkpack__(Gtk2::VBox->new(0,0), map { $buttons{$_} } @actions));
		$real_w->set_data(must_grow => 1)
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
		    ($w, $set, $size) = create_treeview_tree(@para, $e->{tree_expanded});
		    $e->{saved_default_val} = ${$e->{val}}; #- during realization, signals will mess up the default val :(
		} else {
		    if ($use_boxradio) {
			($w, $set, $focus_w) = create_boxradio(@para);
		    } else {
			($w, $set, $focus_w) = create_treeview_list(@para);
			$e->{saved_default_val} = ${$e->{val}};
		    }
		}
		if (@{$e->{list}} > (@$l == 1 ? 10 : 4) || $e->{add_modify_remove}) {
		    $has_scroll = $expand = 1;
		    $real_w = create_scrolled_window($w);
		    $size = (@$l == 1 ? 10 : 4);
		} else {
		    $size ||= @{$e->{list}};
		}
	    }
	} else {
	    if ($e->{type} eq "combo") {

		my @formatted_list = map { may_apply($e->{format}, $_) } @{$e->{list}};

		my @l = sort { $b <=> $a } map { length } @formatted_list;
		$width = $l[@l / 16]; # take the third octile (think quartile)

		if ($e->{not_edit} && $width < 60) { #- OptionMenus do not have an horizontal scroll-bar. This can cause havoc for long strings (eg: diskdrake Create dialog box in expert mode)
		    $w = Gtk2::OptionMenu->new;
		} else {
		    $w = Gtk2::Combo->new;
		    $w->set_use_arrows_always(1);
		    $w->entry->set_editable(!$e->{not_edit});
		    $w->disable_activate;
		    $has_horiz_scroll = 1;
		}

		$w->set_popdown_strings(@formatted_list);
		($real_w, $w) = ($w, $w->entry);

		#- FIXME workaround gtk suckiness (set_text generates two 'change' signals, one when removing the whole, one for inserting the replacement..)
		my $idle;
		$w->signal_connect(changed => sub {
		    $idle ||= Glib::Idle->add(sub { undef $idle; $changed->(); 0 });
		});

		$set = sub {
		    my $s = may_apply($e->{format}, $_[0]);
		    $w->set_text($s) if $s ne $w->get_text && $_[0] ne $w->get_text;
		};
		$get = sub { 
		    my $s = $w->get_text;
		    my $i = eval { find_index { $s eq $_ } @formatted_list };
		    defined $i ? $e->{list}[$i] : $s;
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

	$max_width = max($max_width, $width);
	$total_size += $size || 1;
    
	{ e => $e, w => $w, real_w => $real_w || $w, focus_w => $focus_w || $w, expand => $expand,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {},
	  icon_w => $e->{icon} && eval { gtkcreate_img($e->{icon}) } };
    };
    @widgets_always   = map_index { $create_widget->($_, $::i)       } @$l;
    my $always_total_size = $total_size;
    @widgets_advanced = map_index { $create_widget->($_, $::i + @$l) } @$l2;
    my $advanced_total_size = $total_size - $always_total_size;


    my $pack = create_box_with_title($mainw, @{$common->{messages}});
    my ($totalwidth, $totalheight) = (0, $mainw->{box_size});

    my $set_default_size = sub {
	if (($has_scroll || $has_horiz_scroll) && !$mainw->{isEmbedded} && !$mainw->{isWizard}) {
	    $mainw->{rwindow}->set_default_size($totalwidth+6+$ugtk2::shape_width, $has_scroll ? $totalheight+6+3+$ugtk2::shape_width : -1);
	}
    };

    my $set_advanced_raw = sub {
        ($advanced) = @_;
        $advanced ? $advanced_pack->show : $advanced_pack->hide;
    };
    my $first_time = 1;
    my $set_advanced = sub {
	($advanced) = @_;
	$set_default_size->() if $advanced;
	$update->($common->{callbacks}{advanced}) if $advanced && !$first_time;
	$set_advanced_raw->($advanced);
	@widgets = (@widgets_always, if_($advanced, @widgets_advanced));
	$mainw->sync; #- for $set_all below (mainly for the set of clist)
	$first_time = 0;
	$set_all->(); #- must be done when showing advanced lists (to center selected value)
    };
    my $advanced_button = [ $common->{advanced_label}, 
			    sub { 
				my ($w) = @_;
				$set_advanced->(!$advanced);
				$w->child->set_label($advanced ? $common->{advanced_label_close} : $common->{advanced_label});
			    } ];

    my $create_widgets = sub {
	my ($size, @widgets) = @_;
	my $w = create_packtable({}, map { [($_->{icon_w}, $_->{e}{label}, $_->{real_w})] } @widgets);

	$size && $total_size or return $w; #- do not bother computing stupid/bad things
	my $ratio = max($size / $total_size, 0.2);

	my ($possibleheight, $possiblewidth) = $mainw->{isEmbedded} ? (450, 380) : ($::windowheight * 0.8, $::windowwidth * 0.8);
	$possibleheight -= $mainw->{box_size};

	my $wantedwidth = max(250, $max_width * 5);
	my $width = min($possiblewidth, $wantedwidth);

	my $wantedheight = ugtk2::n_line_size($size, 'various', $mainw->{rwindow});
	my $height = min($possibleheight * $ratio, max(200, $wantedheight));

	$totalheight += $height;
	$totalwidth = max($width, $totalwidth);

	my $has = $wantedwidth > $width || $wantedheight > $height;
	$has_scroll ||= $has;
	$has ? create_scrolled_window($w) : $w;
    };

    my $always_pack = $create_widgets->($always_total_size, @widgets_always);
    my $has_scroll_always = $has_scroll;

    my @adv = map { warp_text($_) } @{$common->{advanced_messages}};
    $advanced_pack = 
      gtkpack_(Gtk2::VBox->new(0,0),
	       0, '',
	       (map { (0, Gtk2::Label->new($_)) } @adv),
	       0, Gtk2::HSeparator->new,
	       1, $create_widgets->($advanced_total_size, @widgets_advanced));

    my @help = if_($common->{interactive_help}, 
		   [ N("Help"), sub { 
			 my $message = $common->{interactive_help}->() or return;
			 $o->ask_warn(N("Help"), $message);
		     }, 1 ]);
    if ($::expert && @$l2) {
        $common->{advanced_state} = 1;
        $advanced_button->[0] = $common->{advanced_label_close};
    }
    my $buttons_pack = ($common->{ok} || !exists $common->{ok}) && $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @help, if_(@$l2, $advanced_button));

    $pack->pack_start(gtkshow($always_pack), 1, 1, 0);
    $advanced_pack = create_scrolled_window($advanced_pack, [ 'never', 'automatic' ], 'none');
    $pack->pack_start($advanced_pack, 1, 1, 0) if @widgets_advanced;
    if ($buttons_pack) {
	if ($::isWizard && !$mainw->{pop_it} && $::isInstall) {
	    $buttons_pack->set_size_request($::windowwidth * 0.9 - 20, -1);
	    $buttons_pack = gtkpack__(Gtk2::HBox->new(0,0), $buttons_pack);
	}
	$pack->pack_start(gtkshow($buttons_pack), 0, 0, 0);
    }
    gtkadd($mainw->{window}, $pack);
    $set_default_size->() if $has_scroll_always;
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
	}
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

sub wait_messageW($$$) {
    my ($o, $title, $messages) = @_;
    local $::isEmbedded = 0; # to prevent sub window embedding

    my @l = map { Gtk2::Label->new(scalar warp_text($_)) } @$messages;
    my $w = ugtk2->new($title, %$o, grab => 1, if__($::main_window, transient => $::main_window));
    gtkadd($w->{window}, my $hbox = Gtk2::HBox->new(0,0));
    $hbox->pack_start(my $box = Gtk2::VBox->new(0,0), 1, 1, 10);  
    $box->pack_start(shift @l, 0, 0, 4);
    $box->pack_start($_, 1, 1, 4) foreach @l;

    ($w->{wait_messageW} = $l[-1])->signal_connect(expose_event => sub { $w->{displayed} = 1; 0 });
    $w->{rwindow}->set_position('center') if $::isStandalone && !$w->{isEmbedded} && !$w->{isWizard};
    $w->{window}->show_all;
    $w->sync until $w->{displayed};
    $w;
}
sub wait_message_nextW {
    my ($_o, $messages, $w) = @_;
    my $msg = warp_text(join "\n", @$messages);
    return if $msg eq $w->{wait_messageW}->get; #- needed otherwise no expose_event :(
    $w->{displayed} = 0;
    $w->{wait_messageW}->set($msg);
    $w->flush until $w->{displayed};
}
sub wait_message_endW {
    my ($_o, $w) = @_;
    $w->destroy;
}

sub kill {
    my ($_o) = @_;
    $_->destroy foreach $::WizardTable ? $::WizardTable->get_children : (), @tempory::objects, @interactive::objects;
    @tempory::objects = @interactive::objects = ();
}

sub ok {
    N("Ok");
}

sub cancel {
    N("Cancel");
}

1;
