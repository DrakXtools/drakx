package interactive::gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
use mygtk3;
use ugtk3 qw(:helpers :wrappers :create);

my $forgetTime = 1000; #- in milli-seconds

sub new {
    my $w = &interactive::new;
    ($w->{windowwidth}, $w->{windowheight}) = mygtk3::root_window_size() if !$::isInstall;
    $w;
}
sub enter_console { my ($o) = @_; $o->{suspended} = common::setVirtual(1) }
sub leave_console { my ($o) = @_; common::setVirtual(delete $o->{suspended}) }
sub adapt_markup { 
    #- nothing needed, the default markup is gtk3's
    my ($_o, $s) = @_; return $s;
}

sub exit { ugtk3::exit(@_) }

sub ask_fileW {
    my ($in, $common) = @_;

    my $w = ugtk3::create_file_selector(%$common);

    my $file;
    $w->main(sub { 
	$file = $w->{chooser}->get_filename;
	my $err = ugtk3::file_selected_check($common->{save}, $common->{want_a_dir}, $file);
	$err and $in->ask_warn('', $err);
	!$err;
    }) && $file;
}

sub create_boxradio {
    my ($e, $onchange_f, $double_click) = @_;

    my $boxradio = gtkpack2__(Gtk3::VBox->new,
			      my @radios = gtkradio('', @{$e->{formatted_list}}));
    mapn {
	my ($txt, $w) = @_;
	# workaround infamous 6 years old gnome bug #101968:
	$w->get_child->set_size_request(mygtk3::get_label_width(), -1) if $e->{alignment} ne 'right' && !$e->{label};
	$w->signal_connect(button_press_event => $double_click) if $double_click;

	$w->signal_connect(key_press_event => $e->{may_go_to_next});
	$w->signal_connect(clicked => sub { 
	    ${$e->{val}} ne $txt or return;
	    $onchange_f->(sub { $txt });
	});
	if ($e->{help}) {
	    $w->set_tooltip_text(
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
    my ($e, $onchange_f, $double_click) = @_;
    my $curr;

    my $list = Gtk3::ListStore->new("Glib::String");
    my $list_tv = Gtk3::TreeView->new_with_model($list);
    $list_tv->set_headers_visible(0);
    $list_tv->get_selection->set_mode('browse');
    my $textcolumn = Gtk3::TreeViewColumn->new_with_attributes("", my $renderer = Gtk3::CellRendererText->new, 'text' => 0);
    $list_tv->append_column($textcolumn);
    $renderer->set_property('ellipsize', 'end');
    
    my $select = sub {
	my ($path) = @_;
	return if !$list_tv->get_model;
	$list_tv->set_cursor($path, undef, 0);
	Glib::Timeout->add(100, sub { $list_tv->scroll_to_cell($path, undef, 1, 0.5, 0); 0 });
    };

    my ($starting_word, $start_reg) = ('', '^');
    my $timeout;
    $list_tv->set_enable_search(0);
    $list_tv->signal_connect(key_press_event => sub {
        my ($_w, $event) = @_;
	my $c = chr($event->keyval & 0xff);

	Glib::Source->remove($timeout) if $timeout; $timeout = '';
	
	if ($event->keyval >= 0x100) {
	    $e->{may_go_to_next}(), return 1 if member($event->keyval, (Gtk3::Gdk::KEY_Return, Gtk3::Gdk::KEY_KP_Enter));
	    $starting_word = '' if !member($event->keyval, (Gtk3::Gdk::KEY_Control_L, Gtk3::Gdk::KEY_Control_R));
	} else {
	    if (member('control-mask', @{$event->state})) {
		$c eq 's' or return 1;
		$start_reg and $start_reg = '', return 1;
		$curr++;
	    } else {
		$e->{may_go_to_next}(), return 1 if $c eq ' ';

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
		$select->(Gtk3::TreePath->new_from_string(($j + $curr) % @l));
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
	$onchange_f->(sub {
	    my $row = $model->get_path_str($iter);
	    $e->{list}[$curr = $row];
	});
    });
    $list_tv->signal_connect(button_press_event => $double_click) if $double_click;

    $list_tv, sub {
	my ($v) = @_;
	eval {
	    my $nb = find_index { $_ eq $v } @{$e->{list}};
	    my ($old_path) = $list_tv->get_cursor;
	    if (!$old_path || $nb != $old_path->to_string) {
		$select->(Gtk3::TreePath->new_from_string($nb));
	    }
	    undef $old_path if $old_path;
	};
    };
}

sub __create_tree_model {
    my ($e) = @_;

    my $sep = quotemeta $e->{separator};
    my $tree_model = Gtk3::TreeStore->new("Glib::String", if_($e->{image2f}, "Gtk3::Gdk::Pixbuf"));

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
    my ($e, $onchange_f, $double_click) = @_;

    my $tree_model = __create_tree_model($e);
    my $tree = Gtk3::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    {
	my $col = Gtk3::TreeViewColumn->new;
	$col->pack_start(my $texrender = Gtk3::CellRendererText->new, 0);
	$col->add_attribute($texrender, text => 0);
	if ($e->{image2f}) {
	    $col->pack_start(my $pixrender = Gtk3::CellRendererPixbuf->new, 0);
	    $col->add_attribute($pixrender, pixbuf => 1);
	}
	$tree->append_column($col);
    }
    $tree->set_headers_visible(0);

    my $select = sub {
	my ($path_str) = @_;
	my $path = Gtk3::TreePath->new_from_string($path_str);
	$tree->expand_to_path($path);
	$tree->set_cursor($path, undef, 0);
        gtkflush();  #- workaround gtk3 bug not honouring centering on the given row if node was closed
	$tree->scroll_to_cell($path, undef, 1, 0.5, 0);
    };

    my $curr = $tree_model->get_iter_first; #- default value
    $tree->expand_all if $e->{tree_expanded};

    my $selected_via_click;

    $tree->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	undef $curr if ref $curr;
	my $path = $tree_model->get_path($curr = $iter);
	if (!$tree_model->iter_has_child($iter)) {
	    $onchange_f->(sub {
		my $path_str = $path->to_string;
		my $i = find_index { $path_str eq $_ } @{$tree_model->{path_str_list}};
		$e->{list}[$i];
	    });
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
	    &{$e->{may_go_to_next}};
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
	    &$toggle and return 1 if member($event->keyval, (Gtk3::Gdk::KEY_Return, Gtk3::Gdk::KEY_KP_Enter));
	    $starting_word = '' if !member($event->keyval, (Gtk3::Gdk::KEY_Control_L, Gtk3::Gdk::KEY_Control_R));
	} else {
	    my $next;
	    if (member('control-mask', @{$event->state})) {
		$c eq "s" or return 1;
		$start_reg and $start_reg = '', return 0;
		$next = 1;
	    } else {
		&$toggle and return 1 if $c eq ' ';
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

#- $actions is a ref list of $action
#- $action is a { kind => $kind, action => sub { ... }, button => Gtk3::Button->new(...) }
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
    ugtk3::gtk_set_treelist($treelist, [ map { may_apply($e->{format}, $_) } @{$e->{list}} ]);

    add_modify_remove_sensitive($buttons, $e);
    1;
}

sub add_padding {
    my ($w) = @_;
    gtknew('HBox', children => [
        0, gtknew('Alignment', width => $mygtk3::left_padding),
        1, $w
    ]);
}  

sub create_widget {
    my ($o, $common, $e, $onchange_f, $update, $ignore_ref) = @_;

    my $onchange = sub {
	my ($f) = @_;
	sub { $onchange_f->($f, @_) };
    };

    my ($w, $real_w, $focus_w, $set);
    if ($e->{type} eq 'iconlist') {
	$w = Gtk3::Button->new;
	$set = sub {
	    gtkdestroy($e->{icon});
	    my $f = $e->{icon2f}->($_[0]);
	    $e->{icon} = -e $f ?
	      gtkcreate_img($f) :
		Gtk3::WrappedLabel->new(may_apply($e->{format}, $_[0]));
	    $w->add(gtkshow($e->{icon}));
	};
	$w->signal_connect(clicked => sub {
			       $onchange_f->(sub { next_val_in_array(${$e->{val}}, $e->{list}) });
			       $set->(${$e->{val}});
			   });
        if ($e->{alignment} eq 'right') {
            $real_w = gtknew('HButtonBox', layout => 'start', children_tight => [ $w ]);
        } else {
            $real_w = gtkpack_(Gtk3::HBox->new(0,10), 1, Gtk3::HBox->new(0,0), 0, $w, 1, Gtk3::HBox->new(0,0));
        }
    } elsif ($e->{type} eq 'bool') {
	if ($e->{image}) {
	    $w = ugtk3::gtkadd(Gtk3::CheckButton->new, gtkshow(gtkcreate_img($e->{image})));
	} else {
	    #-		warn "\"text\" member should have been used instead of \"label\" one at:\n", common::backtrace(), "\n" if $e->{label} && !$e->{text};
	    $w = Gtk3::CheckButton->new_with_label($e->{text} || '');
	}
	$w->signal_connect(clicked => $onchange->(sub { $w->get_active }));
	${$e->{val}} ||= 0;
	$set = sub { $w->set_active($_[0] || 0) };
        $real_w = add_padding($w);
    } elsif ($e->{type} eq 'only_label') {
        my @common = (
            # workaround infamous 6 years old gnome bug #101968:
            if_($e->{alignment} ne 'right', width => mygtk3::get_label_width())
        );
	$w = $e->{title} ? 
	         gtknew('Title2', label => escape_text_for_TextView_markup_format(${$e->{val}}), @common) :
		 gtknew($e->{alignment} eq 'right' ? 'Label_Right' : 'Label_Left',
                        line_wrap => 1, text_markup => ${$e->{val}}, @common);
    } elsif ($e->{type} eq 'label') {
	$w = gtknew('WrappedLabel', text_markup => ${$e->{val}});
	$set = sub { $w->set($_[0]) };
    } elsif ($e->{type} eq 'empty') {
	$w = gtknew('HBox', height => $e->{height});
    } elsif ($e->{type} eq 'button') {
	$w = gtknew(($e->{install_button} ? 'Install_Button' : 'Button'), 
                    text => '', clicked => $e->{clicked_may_quit_cooked});
	$set = sub {
            my $w = $w->get_child;
            # handle Install_Buttons:
            if (ref($w) =~ /Gtk3::HBox/) {
                ($w) = find { ref($_) =~ /Gtk3::Label/ } $w->get_children;
            }
            # guard against 'advanced' widgets that are now in their own dialog
            # (instead of in another block child of an expander):
            return if !$w;
            $w->set_label(may_apply($e->{format}, $_[0])) };
    } elsif ($e->{type} eq 'range') {
	my $adj = Gtk3::Adjustment->new(${$e->{val}}, $e->{min}, $e->{max} + ($e->{SpinButton} ? 0 : 1), 1, ($e->{max} - $e->{min}) / 10, 1);
	$w = $e->{SpinButton} ? Gtk3::SpinButton->new($adj, 10, 0) : Gtk3::HScale->new($adj);
	$w->set_size_request($e->{SpinButton} ? 100 : 200, -1);
	$w->set_digits(0);
	$adj->signal_connect(value_changed => $onchange->(sub { $adj->get_value }));
	$w->signal_connect(key_press_event => $e->{may_go_to_next});
	$set = sub { $adj->set_value($_[0]) };
    } elsif ($e->{type} eq 'expander') {
	$e->{grow} = 'fill';
	my $children = [ if_($e->{message}, { type => 'only_label', no_indent => 1, val => \$e->{message} }), @{$e->{children}} ];
	create_widgets_block($o, $common, $children, $update, $ignore_ref);
	$w = gtknew('HBox', children_tight => [
            gtknew('Install_Button', text => $e->{text},
                   clicked => sub {
                       eval { ask_fromW($o, { title => $common->{advanced_title} || $common->{title} || N("Advanced") }, $children) };
		       if (my $err = $@) {
			   die $err if $err !~ /^wizcancel/;
		       }
		   }
               )
        ]);
    } elsif ($e->{type} =~ /list/) {

	$e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];

	if (my $actions = $e->{add_modify_remove}) {
	    my @buttons = (N_("Add"), N_("Modify"), N_("Remove"));
	    # Add Up/Down buttons if their actions are defined
            push @buttons, map { if_($actions->{$_}, 'gtk-go-' . $_) } qw(Up Down);
	    @buttons = map {
                my $button = /^gtk-/ ? gtknew('Button', image => gtknew('Image', stock => lc($_)))
                  : Gtk3::Button->new(translate($_));
		my $kind = $_;
		$kind =~ s/^gtk-go-//;
		{ kind => lc $kind, action => $actions->{$kind}, button => $button, real_kind => $_ };
	    } @buttons;
	    my $modify = find { $_->{kind} eq 'modify' } @buttons;

	    my $do_action = sub {
		my ($button) = @_;
		add_modify_remove_action($button, \@buttons, $e, $w) and $update->();
	    };

	    ($w, $set, $focus_w) = create_treeview_list($e, $onchange_f, 
							sub { $do_action->($modify) if $_[1]->type =~ /^2/ });

	    foreach my $button (@buttons) {
		$button->{button}->signal_connect(clicked => sub { $do_action->($button) });
	    }
	    add_modify_remove_sensitive(\@buttons, $e);

	    my ($images, $real_buttons) = partition { $_->{real_kind} =~ /^gtk-/ } @buttons;
	    $real_w = gtkpack_(Gtk3::HBox->new(0,0),
			       1, create_scrolled_window($w), 
			       0, gtkpack__(Gtk3::VBox->new(0,0),
                                            (map { $_->{button} } @$real_buttons),
                                            if_($images,
                                                gtknew('HButtonBox',
                                                       layout => 'spread',
                                                       children_loose => [ map { $_->{button} } @$images ]
                                                      )
                                            ),
                                        ),
                           );
	    $e->{grow} = 'expand';
	} else {
	    my $use_boxradio = exists $e->{gtk}{use_boxradio} ? $e->{gtk}{use_boxradio} : @{$e->{list}} <= 8;

	    if ($e->{help} || $use_boxradio && $e->{type} ne 'treelist') {
		#- used only when needed, as key bindings are dropped by List (ListStore does not seems to accepts Tooltips).
		($w, $set, $focus_w) = create_boxradio($e, $onchange_f, $e->{quit_if_double_click_cooked});
                $real_w = add_padding($w);
	    } elsif ($e->{type} eq 'treelist') {
		($w, $set) = create_treeview_tree($e, $onchange_f, $e->{quit_if_double_click_cooked});
	    } else {
		($w, $set, $focus_w) = create_treeview_list($e, $onchange_f, $e->{quit_if_double_click_cooked});
	    }
	    if (@{$e->{list}} > 10 || $e->{gtk}{use_scrolling}) {
		$real_w = create_scrolled_window($w);
		$e->{grow} = 'expand';
	    }
	}
    } else {
	if ($e->{type} eq "combo") {
	    my $model;

	    my @formatted_list = map { may_apply($e->{format}, $_) } @{$e->{list}};
	    $e->{formatted_list} = \@formatted_list;

	    if (!$e->{separator}) {
		if ($e->{not_edit}) {
		    $real_w = $w = Gtk3::ComboBoxText->new;
		    # FIXME: the following causes Gtk-CRITICAL but not solvable at realize time:
		    first($w->get_child->get_cells)->set_property('ellipsize', 'end') if !$e->{do_not_ellipsize};
		    $w->set_wrap_width($e->{gtk}{wrap_width}) if exists $e->{gtk}{wrap_width};
		} else {
		    $w = Gtk3::ComboBoxText->new_with_entry;
		    ($real_w, $w) = ($w, $w->get_child);
		}
		$real_w->set_popdown_strings(@formatted_list);
	    } else {
		$model = __create_tree_model($e);
		$real_w = $w = Gtk3::ComboBox->new_with_model($model);

		$w->pack_start(my $texrender = Gtk3::CellRendererText->new, 0);
		$w->add_attribute($texrender, text => 0);
		if ($e->{image2f}) {
		    $w->pack_start(my $pixrender = Gtk3::CellRendererPixbuf->new, 0);
		    $w->add_attribute($pixrender, pixbuf => 1);
		}
	    }

	    my $get = sub {
		my $i = $model ? do {
		    my (undef, $iter) = $w->get_active_iter;
		    my $s = $model->get_string_from_iter($iter);
		    eval { find_index { $s eq $_ } @{$model->{path_str_list}} };
		} : do {
		    my $s = $w->get_text;
		    eval { find_index { $s eq $_ } @formatted_list };
		};
		defined $i ? $e->{list}[$i] : $w->get_text;
	    };
	    $w->signal_connect(changed => $onchange->($get));

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
	} else {
	    if ($e->{weakness_check}) {
		$w = gtknew('WeaknessCheckEntry');
	    }
	    else {
		$w = Gtk3::Entry->new;
	    }
	    $w->signal_connect(changed => $onchange->(sub { $w->get_text }));
	    $w->signal_connect(focus_in_event => sub { $w->select_region(0, -1) });
	    $w->signal_connect(focus_out_event => sub { $w->select_region(0, 0) });
	    $set = sub { $w->set_text($_[0]) if $_[0] ne $w->get_text };
	    if ($e->{type} eq 'file') {
		my $button = gtksignal_connect(Gtk3::Button->new_from_stock('gtk-open'), clicked => sub {
						   my $file = $o->ask_fileW({
                                                       title => $e->{label},
                                                       want_a_dir => to_bool($e->{want_a_dir}),
                                                   });
						   $set->($file) if $file;
					       });
		$real_w = gtkpack_(Gtk3::HBox->new(0,0), 1, $w, 0, $button);
	    }
	}
	$w->signal_connect(key_press_event => $e->{may_go_to_next});
	if ($e->{hidden}) {
	    $w->set_visibility(0);
	    $w->signal_connect(key_press_event => sub {
		my (undef, $event) = @_;
		if (!$o->{capslock_warned} && member('lock-mask', @{$event->state}) && !$w->get_text) {
		    $o->{capslock_warned} = 1;
		    $o->ask_warn('', N("Beware, Caps Lock is enabled"));
		}
		0;
	    });
	}
    }

    if (my $focus_out = $e->{focus_out}) {
	$w->signal_connect(focus_out_event => sub { $update->($focus_out) });
    }
    $real_w ||= $w;

    $e->{w} = $w;
    $e->{real_w} = $real_w;
    $e->{focus_w} = $focus_w || $w if $e->{type} ne 'empty';
    $e->{set} = $set || sub {};
}

sub all_entries {
    my ($l) = @_;
    map { $_, if_($_->{children}, @{$_->{children}}) } @$l;
}

sub all_focusable_entries {
    my ($l) = @_;
    grep { $_->{focus_w} } @$l;
}

sub all_title_entries {
    my ($l) = @_;
    grep { $_->{title} } @$l;
}

sub create_widgets_block {
    my ($o, $common, $l, $update, $ignore_ref) = @_;

    my $label_sizegrp = Gtk3::SizeGroup->new('horizontal');
    my $right_label_sizegrp = Gtk3::SizeGroup->new('horizontal');
    my $realw_sizegrp = Gtk3::SizeGroup->new('horizontal');

    @$l = map_index {
	if ($::i && ($_->{type} eq 'expander' || $_->{title})) {
	    ({ type => 'empty', height => 4 }, $_);
	} else {
	    $_;
	}
    } @$l;

    foreach my $e (@$l) {
	my $onchange_f = sub {
	    my ($f, @para) = @_;
	    return if $$ignore_ref;
	    ${$e->{val}} = $f->(@para); 
	    $update->($e->{changed});
	};

	create_widget($o, $common, $e, $onchange_f, $update, $ignore_ref);

	my $label_w;
	if ($e->{label} || !$e->{no_indent}) {
	    $label_w = gtknew($e->{alignment} eq 'right' ? 'Label_Right' : 'Label_Left', text_markup => $e->{label} || '',
			      size_group => ($e->{alignment} eq 'right' ? $right_label_sizegrp : $label_sizegrp),
                          );
            $realw_sizegrp->add_widget($e->{real_w});
	}

	if ($e->{do_not_expand}) {
            $e->{real_w} = gtknew('HBox', children => [
                0, $e->{real_w},
                1, gtknew('Label'),
            ]);
	}

	my $eater = if_($e->{alignment} eq 'right' && !$label_w, gtknew('Label'));

	$e->{real_w} = gtkpack_(Gtk3::HBox->new,
				if_($e->{icon}, 0, eval { gtkcreate_img($e->{icon}) }),
				if_($eater, 1, $eater),
				if_($label_w, $e->{alignment} eq 'right', $label_w),
				(!$eater, $e->{real_w}),
			    );
    }
    gtknew('VBox', children => [ map { $_->{grow} || 0, $_->{real_w} } @$l ]);
}

sub create_widgets {
    my ($o, $common, $mainw, $l) = @_;

    my $ignore = 0; #-to handle recursivity
    my $set_all = sub {
	$ignore = 1;
	my @all = all_entries($l);
	$_->{set}->(${$_->{val}}, $_) foreach @all; #- nb: the parameter "$_" is needed for create_boxradio
	$_->{disabled} and $_->{real_w}->set_sensitive(!$_->{disabled}()) foreach @all;
	$_->{hidden} and $_->{w}->set_visibility(!(ref($_->{hidden}) eq 'CODE' ? $_->{hidden}() : $_->{hidden})) foreach @all;
	$mainw->{ok}->set_sensitive(!$common->{ok_disabled}()) if $common->{ok_disabled};
	$ignore = 0;
    };
    my $update = sub {
	my ($f) = @_;
	return if $ignore;
	$f->() if $f;
	$set_all->();
    };

    my $ok_clicked = sub { 
	!$mainw->{ok} || $mainw->{ok}->get_property('sensitive') or return;
	$mainw->{retval} = 1;
	Gtk3->main_quit;
    };

    my @all = all_entries($l);
    foreach (@all) {
	my $e = $_; #- for closures

	# we only consider real widgets (aka ignoring labels and Help/Release Notes/... buttons):
	if ((grep { !$_->{install_button} && $_->{type} ne 'only_label' } @all) == 1 || $e->{quit_if_double_click}) {
	    #- i'm the only one, double click means accepting
	    $e->{quit_if_double_click_cooked} = sub { $_[1]->type =~ /^2/ && $ok_clicked->() };
	}

	if ($e->{clicked_may_quit}) {
	    $e->{clicked_may_quit_cooked} = sub {
		$mainw->{rwindow}->hide;
		if (my $v = $e->{clicked_may_quit}()) {
		    $mainw->{retval} = $v;
		    Gtk3->main_quit;
		}
		$mainw->{rwindow}->show;
		$update->();
	    };
	}

	$e->{may_go_to_next} = sub {
	    my (undef, $event) = @_;
	    if (!$event || ($event->keyval & 0x7f) == 0xd) {
		my @current_all = all_focusable_entries($l);
		my $ind = eval { find_index { $_ == $e } @current_all };
		if (my $e_ = $current_all[$ind+1]) {
		    $e_->{focus_w}->grab_focus;
		} else {
		    @current_all == 1 ? $ok_clicked->() : $mainw->{ok}->grab_focus;
		}
		1; #- prevent an action on the just grabbed focus
	    } else {
		0;
	    }
	};
    }

    # add asterisks before titles when there're more than one:
    my @all_titles = all_title_entries($l);
    if (2 <= @all_titles) {
        ${$_->{val}} = mygtk3::asteriskize(${$_->{val}}) foreach @all_titles;
    }

    my $box = create_widgets_block($o, $common, $l, $update, \$ignore);

    foreach my $e (@all) {
	$e->{w}->set_tooltip_text($e->{help}) if $e->{help} && !ref($e->{help});
    }

    $box, $set_all;
}

sub add_modify_remove_sensitive {
    my ($buttons, $e) = @_;
    $_->{button}->set_sensitive(@{$e->{list}} != ()) foreach 
      grep { member($_->{kind}, 'modify', 'remove') } @$buttons;
}

sub filter_widgets {
    my ($l) = @_;

    foreach my $e (all_entries($l)) {
	$e->{no_indent} = 1 if member($e->{type}, 'list', 'treelist', 'expander', 'bool', 'only_label');
    }
}

my $help_path = "/usr/share/doc/installer-help";

sub is_help_file_exist {
    my ($_o, $id) = @_;
    # just ignore anchors:
    $id =~ s/#.*//;
    -e "$help_path/$id.html";
}

sub load_from_uri {
    my ($view, $url) = @_;
    $view->open(get_html_file($::o, $url));
}

sub get_html_file {
    my ($o, $url) = @_;
    my $anchor;
    ($url, $anchor) = $url =~ /(.*)#(.*)/ if $url =~ /#/;
    $url .= '.html' if $url !~ /\.html$/;
    $url = find { -e $_ } map { "$help_path/${_}" }
      map {
          my $id = $_;
          require lang;
          map { ("$_/$id") } map { $_, lc($_) } (split ':', lang::getLANGUAGE($o->{locale}{lang})), '';
      } $url;
    $url = "file://$url";
    $anchor ? "$url#$anchor" : $url;
}

sub display_help_window {
    my ($o, $common) = @_;
    if (my $file = $common->{interactive_help_id}) {
        require Gtk3::WebKit;
        my $view = gtknew('WebKit_View');

        load_from_uri($view, $file);

        my $w = ugtk3->new(N("Help"), modal => 1);
        gtkadd($w->{rwindow},
               gtkpack_(Gtk3::VBox->new,
                        1, create_scrolled_window(gtkset_border_width($view, 5),
                                                  [ 'never', 'automatic' ],
                                              ),
                        0, Gtk3::HSeparator->new,
                        0, gtkpack(create_hbox('end'),
                                   gtknew('Button', text => N("Close"), clicked => sub { Gtk3->main_quit })
                               ),
                    ),
           );
        mygtk3::set_main_window_size($w->{rwindow});
        $w->{real_window}->grab_focus;
        $w->{real_window}->show_all;
        $w->main;
        return;
    } elsif (my $message = $common->{interactive_help}->()) {
        $o->ask_warn(N("Help"), $message);
    }
}

sub display_help {
    my ($o, $common) = @_;
    # not very safe but we run in a restricted environment anyway:
    my $f = '/tmp/help.txt';
    if ($common->{interactive_help}) {
       output($f, $common->{interactive_help}->());
    }
    local $ENV{LC_ALL} = $::o->{locale}{lang} || 'C';
    system('display_installer_help', $common->{interactive_help_id} || $f, $o->{locale}{lang}); 
}

sub ask_fromW {
    my ($o, $common, $l) = @_;

    filter_widgets($l);

    my $mainw = ugtk3->new($common->{title}, %$o, if__($::main_window, transient => $::main_window),
                           if_($common->{icon}, icon => $common->{icon}), banner_title => $common->{banner_title},
		       );
 
    my ($box, $set_all) = create_widgets($o, $common, $mainw, $l);

    $mainw->{box_allow_grow} = 1;
    my $pack = create_box_with_title($mainw, @{$common->{messages}});
    mygtk3::set_main_window_size($mainw->{rwindow}) if $mainw->{pop_it} && !$common->{auto_window_size} && (@$l || $mainw->{box_size} == 200);

    my @more_buttons = (
			if_($common->{interactive_help} || $common->{interactive_help_id}, 
                            [ gtknew('Install_Button', text => N("Help"),
                                     clicked => sub { display_help($o, $common) }), undef, 1 ]),
			if_($common->{more_buttons}, @{$common->{more_buttons}}),
		       );
    my $buttons_pack = ($common->{ok} || !exists $common->{ok}) && $mainw->create_okcancel($common->{ok}, $common->{cancel}, '', @more_buttons);

    gtkpack_($pack, 1, gtknew('ScrolledWindow', shadow_type => 'none', child => $box)) if @$l;
	    
    if ($buttons_pack) {
	$pack->pack_end(gtkshow($buttons_pack), 0, 0, 0);
    }
    ugtk3::gtkadd($mainw->{window}, $pack);
    $set_all->();

    my $entry_to_focus = find { $_->{focus} && $_->{focus}() } @$l;
    my $widget_to_focus = $entry_to_focus ? $entry_to_focus->{focus_w} :
                          $common->{focus_cancel} ? $mainw->{cancel} :
			    @$l && (!$mainw->{ok} || @$l == 1 && member(ref($l->[0]{focus_w}), "Gtk3::TreeView", "Gtk3::RadioButton")) ? 
			      $l->[0]{focus_w} : 
			      $mainw->{ok};
    $widget_to_focus->grab_focus if $widget_to_focus;

    my $validate = sub {
	my @all = all_entries($l);
	my $e = find { $_->{validate} && !$_->{validate}->() } @all;
	$e ||= $common->{validate} && !$common->{validate}() && $all[0];
	if ($e) {
	    $set_all->();
	    $e->{focus_w}->grab_focus;
	}
	!$e;
    };

    $mainw->main($validate);
}


sub ask_browse_tree_info_refW {
    my ($o, $common) = @_;
    add2hash($common, { wait_message => sub { $o->wait_message(@_) } });
    ugtk3::ask_browse_tree_info($common);
}


sub ask_from__add_modify_removeW {
    my ($o, $title, $message, $l, %callback) = @_;

    my $e = $l->[0];
    my $chosen_element;
    put_in_hash($e, { allow_empty_list => 1, gtk => { use_boxradio => 0 }, sort => 0,
		      val => \$chosen_element, type => 'list', add_modify_remove => \%callback });

    $o->ask_from($title, $message, $l, %callback);
}

my $reuse_timeout;

sub wait_messageW {
    my ($o, $title, $message, $message_modifiable) = @_;

    my $to_modify = Gtk3::Label->new(scalar warp_text(ref $message_modifiable ? '' : $message_modifiable));

    Glib::Source->remove($reuse_timeout) if $reuse_timeout; $reuse_timeout = '';

    my $Window = gtknew('MagicWindow',
			if_($title, title => $title),
			pop_it => defined $o->{pop_wait_messages} ? $o->{pop_wait_messages} : 1, 
			pop_and_reuse => $::isInstall,
			modal => 1, 
			$::isInstall ? (banner => gtknew('Install_Title', text => $message)) : (),
			no_Window_Manager => exists $o->{no_Window_Manager} ? $o->{no_Window_Manager} : !$::isStandalone,
			child => gtknew('VBox', padding => 4, border_width => 10, children => [
			    1, $to_modify,
			    if_(ref($message_modifiable), 0, $message_modifiable),
			]),
		      );
    mygtk3::enable_sync_flush($Window);
    $Window->{wait_messageW} = $to_modify;
    mygtk3::sync_flush($Window);
    $Window;
}
sub wait_message_nextW {
    my ($_o, $message, $Window) = @_;
    return if $message eq $Window->{wait_messageW}->get_text; #- needed otherwise no draw :(
    $Window->{displayed} = 0;
    $Window->{wait_messageW}->set($message);
    mygtk3::sync($Window) while !$Window->{displayed};
}
sub wait_message_endW {
    my ($_o, $Window) = @_;
    if ($Window->{pop_and_reuse}) {
	$reuse_timeout = Glib::Timeout->add(100, sub {
	    mygtk3::destroy_previous_popped_and_reuse_window();
	});
    } else {
	mygtk3::may_destroy($Window);
	mygtk3::flush();
    }
}

sub wait_message_with_progress_bar {
    my ($in, $o_title) = @_;

    my $progress = gtknew('ProgressBar');
    my $w = $in->wait_message($o_title, $progress);
    my $displayed;
    $progress->signal_connect(draw => sub { $displayed = 1; 0 });
    $w, sub {
	my ($msg, $current, $total) = @_;
	if ($msg) {
	    $w->set($msg);
	}

	if ($total) {
	    $progress or internal_error('You must first give some text to display');
	    my $fraction = min(1, $current / $total);
	    if ($fraction != $progress->get_fraction) {
		$progress->set_fraction($fraction);
		$progress->show;
		$displayed = 0;
		mygtk3::flush() while !$displayed;
	    }
	} else {
	    $progress->hide;
	    mygtk3::flush();
	}
    };
}

sub kill {
    my ($_o) = @_;
    $_->destroy foreach $::WizardTable ? $::WizardTable->get_children : (), @tempory::objects;
    @tempory::objects = ();
}

1;
