package my_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $border);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    helpers => [ qw(create_okcancel createScrolledWindow create_menu create_notebook create_packtable create_hbox create_vbox create_adjustment create_box_with_title create_treeitem) ],
    wrappers => [ qw(gtksignal_connect gtkradio gtkpack gtkpack_ gtkpack__ gtkpack2 gtkpack3 gtkpack2_ gtkpack2__ gtkpowerpack gtkset_editable gtksetstyle gtkset_tip gtkappenditems gtkappend gtkset_shadow_type gtkset_layout gtkset_relief gtkadd gtkput gtktext_insert gtkset_usize gtksize gtkset_justify gtkset_active gtkset_sensitive gtkset_modal gtkset_border_width gtkmove gtkresize gtkshow gtkhide gtkdestroy gtkcolor gtkset_mousecursor gtkset_mousecursor_normal gtkset_mousecursor_wait gtkset_background gtkset_default_fontset gtkctree_children gtkxpm gtkpng create_pix_text get_text_coord fill_tiled gtkicons_labels_widget write_on_pixmap gtkcreate_xpm gtkcreate_png gtkbuttonset gtkroot gtkentry) ],
    ask => [ qw(ask_warn ask_okcancel ask_yesorno ask_from_entry ask_browse_tree_info ask_browse_tree_info_given_widgets ask_dir) ],
);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use ugtk qw(:helpers :wrappers :various);
use common;
use log;


my $forgetTime = 1000; #- in milli-seconds
$border = 5;

#-###############################################################################
#- OO stuff
#-###############################################################################

sub new {
    my ($type, $title, %opts) = @_;

    Gtk->init;
    Gtk->set_locale;

    my $o = bless { %opts }, $type;
    $o->_create_window($title);
    while (my $e = shift @tempory::objects) { $e->destroy }
    foreach (@interactive::objects) {
	$_->{rwindow}->set_modal(0) if $_->{rwindow}->can('set_modal');
    }
    push @interactive::objects, $o if !$opts{no_interactive_objects};
    $o->{rwindow}->set_position('center_always') if $::isStandalone;
    $o->{rwindow}->set_modal(1) if $my_gtk::grab || $o->{grab};
    
    if ($::isWizard && !$my_gtk::pop_it) {
	$o->{window} = new Gtk::VBox(0,0);
	$o->{window}->set_border_width($::Wizard_splash ? 0 : 10);
	$o->{rwindow} = $o->{window};
	if (!defined($::WizardWindow)) {
	    $::WizardWindow = new Gtk::Window;
	    $::WizardWindow->set_position('center_always');
	    $::WizardWindow->signal_connect(delete_event => sub { die 'wizcancel' });
	    $::WizardTable = new Gtk::Table(2, 2, 0);
	    $::WizardWindow->add($::WizardTable);
	    my $draw1 = new Gtk::DrawingArea;
	    $draw1->set_usize(540,100);
	    my $draw2 = new Gtk::DrawingArea;
	    $draw2->set_usize(100,300);
	    my ($im_up, $mask_up) = gtkcreate_png($::Wizard_pix_up || "wiz_default_up.png");
	    my ($y1, $x1) = $im_up->get_size;
	    my ($im_left, $mask_left) = gtkcreate_png($::Wizard_pix_left || "wiz_default_left.png");
	    my ($y2, $x2) = $im_left->get_size;
	    my $style = $draw1->style->copy();
	    $style->font(Gtk::Gdk::Font->fontset_load("-adobe-utopia-regular-r-*-*-25-*-*-*-p-*-iso8859-*"));
	    my $w = $style->font->string_width($::Wizard_title);
	    $draw1->signal_connect(expose_event => sub {
				       for (my $i = 0; $i < (540/$y1); $i++) {
					   $draw1->window->draw_pixmap ($draw1->style->bg_gc('normal'),
									$im_up, 0, 0, 0, $y1*$i,
									$x1 , $y1);
					   $draw1->window->draw_string(
								       $style->font,
								       $draw1->style->white_gc,
								       140+(380-$w)/2, 62,
								       ($::Wizard_title) );
				       }
				   });
	    $draw2->signal_connect(expose_event => sub {
				       for (my $i = 0; $i < (300/$y2); $i++) {
					   $draw2->window->draw_pixmap ($draw2->style->bg_gc('normal'),
									$im_left, 0, 0, 0, $y2*$i,
									$x2 , $y2);
				       }
				   });
	    $::WizardTable->attach($draw1, 0, 2, 0, 1, 'fill', 'fill', 0, 0);
	    #- $::WizardTable->attach($draw2, 0, 1, 1, 2, 'fill', 'fill', 0, 0);
	    $::WizardTable->set_usize(540,400);
	    $::WizardWindow->show_all;
	    flush();
	}
	$::WizardTable->attach($o->{window}, 0, 2, 1, 2, [-fill, -expand], [-fill, -expand], 0, 0);
    }

    if ($::isEmbedded && !$my_gtk::pop_it && !eval { $::Plug->child }) {
	$o->{window} = new Gtk::HBox(0,0);
	$o->{rwindow} = $o->{window};
	$::Plug ||= new Gtk::Plug ($::XID);
	$::Plug->show;
	flush();
	$::Plug->add($o->{window});
    }
    $::CCPID and kill 'USR2', $::CCPID;
    $o;
}
sub main {
    my ($o, $completed, $canceled) = @_;
    gtkset_mousecursor_normal();
    my $timeout = Gtk->timeout_add(1000, sub { gtkset_mousecursor_normal(); 1 });
    my $b = MDK::Common::Func::before_leaving { Gtk->timeout_remove($timeout) };
    $o->show;

    do {
	local $::setstep = 1;
	Gtk->main;
    } while ($o->{retval} ? $completed && !$completed->() : $canceled && !$canceled->());
    $o->destroy;
    $o->{retval}
}

sub show($) {
    my ($o) = @_;
    $o->{window}->show;
    $o->{rwindow}->show;
}
sub destroy($) {
    my ($o) = @_;
    $o->{rwindow} and $o->{rwindow}->destroy;
    gtkset_mousecursor_wait();
    flush();
}
sub DESTROY { goto &destroy }
sub sync {
    my ($o) = @_;
    show($o);
    flush();
}
sub flush { gtkflush() }
sub exit {
    gtkset_mousecursor_normal(); #- for restoring a normal in any case
    flush();
    $::isEmbedded and kill 'USR1', $::CCPID;
    c::_exit($_[1]) #- workaround 
}

#-###############################################################################
#- createXXX functions

#- these functions return a widget
#-###############################################################################

sub create_okcancel {
    my ($w, $ok, $cancel, $spread, @other) = @_;
    my $one = ($ok xor $cancel);
    $spread ||= $::isWizard ? "end" : "spread";
    $ok ||= $::isWizard ? ($::Wizard_finished ? _("Finish") : _("Next ->")) : _("Ok");
    $cancel ||= $::isWizard ? _("<- Previous") : _("Cancel");
    my $b1 = gtksignal_connect($w->{ok} = new Gtk::Button($ok), clicked => $w->{ok_clicked} || sub { $w->{retval} = 1; Gtk->main_quit });
    my $b2 = !$one && gtksignal_connect($w->{cancel} = new Gtk::Button($cancel), clicked => $w->{cancel_clicked} || sub { log::l("default cancel_clicked"); undef $w->{retval}; Gtk->main_quit });
    $::isWizard and gtksignal_connect($w->{wizcancel} = new Gtk::Button(_("Cancel")), clicked => sub { die 'wizcancel' });
    my @l = grep { $_ } $::isWizard ? ($w->{wizcancel}, $::Wizard_no_previous ? () : $b2, $b1): ($b1, $b2);
    push @l, map { gtksignal_connect(new Gtk::Button($_->[0]), clicked => $_->[1]) } @other;

    $_->can_default($::isWizard) foreach @l;
    gtkadd(create_hbox($spread), @l);
}


sub _create_window($$) {
    my ($o, $title) = @_;
    my $w = new Gtk::Window;
    my $gc = Gtk::Gdk::GC->new(gtkroot());
    !$::isStandalone && !$::live && !$::g_auto_install and $my_gtk::shape_width = 3;
#-  $gc->set_foreground(gtkcolor(8448, 17664, 40191)); #- in hex : 33, 69, 157
    $gc->set_foreground(gtkcolor(5120, 10752, 22784)); #- in hex : 20, 42, 89
#-    $gc->set_foreground(gtkcolor(16896, 16896, 16896)); #- in hex : 66, 66, 66
    my $inner = gtkadd(my $f_ = gtkset_shadow_type(new Gtk::Frame(undef), 'out'),
		       my $f = gtkset_border_width(gtkset_shadow_type(new Gtk::Frame(undef), 'none'), 3)
		      );
    my $table;
    if ($::isStandalone || $::live || $::g_auto_install || $::noShadow) { gtkadd($w, $inner) if !$::noBorder } else {
	my $sqw = $my_gtk::shape_width;
	gtkadd($w, $table = new Gtk::Table(2, 2, 0));
	$table->attach($inner, 0, 1, 0, 1, 1|4, 1|4, 0, 0);
	$table->attach(gtksignal_connect(gtkset_usize(new Gtk::DrawingArea, $sqw, 1), expose_event => sub {
					      $_[0]->window->draw_rectangle($_[0]->style->bg_gc('normal'), 1, 0, 0, $sqw, $sqw);
					      $_[0]->window->draw_rectangle($gc, 1, 0, $sqw, $sqw, $_[0]->allocation->[3]);
					  }),
			1, 2, 0, 1, 'fill', 'fill', 0, 0);
	$table->attach(gtksignal_connect(gtkset_usize(new Gtk::DrawingArea, 1, $sqw), expose_event => sub {
					      $_[0]->window->draw_rectangle($_[0]->style->bg_gc('normal'), 1, 0, 0, $sqw, $sqw);
					      $_[0]->window->draw_rectangle($gc, 1, $sqw, 0, $_[0]->allocation->[2], $sqw);
					  }),
			0, 1, 1, 2, 'fill', 'fill', 0, 0);
	$table->attach(gtksignal_connect(gtkset_usize(new Gtk::DrawingArea, $sqw, $sqw), expose_event => sub {
					      $_[0]->window->draw_rectangle($gc, 1, 0, 0, $sqw, $sqw);
					  }),
			1, 2, 1, 2, 'fill', 'fill', 0, 0);
	$table->show_all;
    }
    $w->set_name("Title");
    $w->set_title($title);

    $w->signal_connect(expose_event => sub { eval { $interactive::objects[-1]{rwindow} == $w and $w->window->XSetInputFocus } }) if $my_gtk::force_focus || $o->{force_focus};
    $w->signal_connect(delete_event => sub { $w->destroy; die 'wizcancel' });
    $w->set_uposition(@{$my_gtk::force_position || $o->{force_position}}) if $my_gtk::force_position || $o->{force_position};

    my $focusing;
    $w->signal_connect(focus => sub { 
        return 1 if $focusing;
	$focusing = 1;
	Gtk->idle_add(sub { $w->ensure_focus($_[0]); $focusing = 0; 0 }, $_[1]);
    }) if $w->can('ensure_focus');

    if ($::o->{mouse}{unsafe}) {
	$w->set_events("pointer_motion_mask");
	my $signal;
	$signal = $w->signal_connect(motion_notify_event => sub {
	    delete $::o->{mouse}{unsafe};
	    log::l("unsetting unsafe mouse");
	    $w->signal_disconnect($signal);
	});
    }
    $w->signal_connect(key_press_event => sub {
	my $d = ${{ 0xffbe => 'help',
		    0xffbf => 'screenshot',
		    0xffc2 => 'set_theme',
	            0xffc9 => 'next',
		    0xffc8 => 'previous' }}{$_[1]{keyval}};

	if ($d eq "help") {
	    require install_gtk;
	    install_gtk::create_big_help($::o);
	} elsif ($::isInstall && $d eq 'screenshot') {
	    common::take_screenshot($o);
	} elsif ($::isInstall && $d eq 'set_theme') {
	    $::setstep and die "set_theme\n"; #- set_theme is similar to setstep, don't raise one when not allowed to
	} elsif (chr($_[1]{keyval}) eq 'e' && $_[1]{state} & 8) {
	    log::l("Switching to " . ($::expert ? "beginner" : "expert"));
	    $::expert = !$::expert;
	} elsif ($d) {
	    #- previous field is created here :(
	    my $s; foreach (reverse @{$::o->{orderedSteps}}) {
		$s->{previous} = $_ if $s;
		$s = $::o->{steps}{$_};
	    }
	    $s = $::o->{step};
	    do { $s = $::o->{steps}{$s}{$d} } until !$s || $::o->{steps}{$s}{reachable};
	    $::setstep && $s and die "setstep $s\n";
	}
    }); #- if $::isInstall;

    $w->signal_connect(size_allocate => sub {
	my ($wi, $he) = @{$_[1]}[2,3];
	my ($X, $Y, $Wi, $He) = @{$my_gtk::force_center || $o->{force_center}};
        $w->set_uposition(max(0, $X + ($Wi - $wi) / 2), max(0, $Y + ($He - $he) / 2));

	if (!$::isStandalone && !$::live && !$::g_auto_install && !$::noShadow) {
	    my $sqw = $my_gtk::shape_width; #square width
	    my $wia = int(($wi+7)/8);
	    my $s = "\xFF" x ($wia*$he);
	    my $wib = $wia*8;
	    my $dif = $wib-$wi;
	    foreach my $y (0..$sqw-1) { vec($s, $wib-1-$dif-$_+$wib*$y, 1) = 0x0 foreach (0..$sqw-1) }
	    foreach my $y (0..$sqw-1) { vec($s, (($he-1)*$wib)-$wib*$y+$_, 1) = 0x0 foreach (0..$sqw-1) }
	    $w->realize;
	    my $b = Gtk::Gdk::Bitmap->create_from_data($w->window, $s, $wib, $he);
	    $w->window->shape_combine_mask($b, 0, 0);
	}
    }) if ($my_gtk::force_center || $o->{force_center}) && !($my_gtk::force_position || $o->{force_position}) ;

    $o->{window} = $::noBorder ? $w : $f;
    $o->{rwindow} = $w;
    $table and $table->draw(undef);
}

#-###############################################################################
#- ask_XXX

#- just give a title and some args, and it will return the value given by the user
#-###############################################################################

sub ask_warn       { my $w = my_gtk->new(shift @_); $w->_ask_warn(@_); main($w) }
sub ask_yesorno    { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, _("Yes"), _("No")); main($w) }
sub ask_okcancel   { my $w = my_gtk->new(shift @_); $w->_ask_okcancel(@_, _("Is this correct?"), _("Ok"), _("Cancel")); main($w) }
sub ask_from_entry { my $w = my_gtk->new(shift @_); $w->_ask_from_entry(@_); main($w) }
sub ask_dir        { my $w = my_gtk->new(shift @_); $w->_ask_dir(@_); main($w) }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = new Gtk::Entry;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk->main_quit };
    $o->{ok_clicked} = $f;
    $o->{cancel_clicked} = sub { undef $o->{retval}; Gtk->main_quit };

    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect($entry, 'activate' => $f),
		 ($o->{hide_buttons} ? () : create_okcancel($o))),
	  );
    $entry->grab_focus;
}

sub _ask_warn($@) {
    my ($o, @msgs) = @_;
    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect(my $w = new Gtk::Button(_("Ok")), "clicked" => sub { Gtk->main_quit }),
		 ),
	  );
    $w->grab_focus;
}

sub _ask_okcancel($@) {
    my ($o, @msgs) = @_;
    my ($ok, $cancel) = splice @msgs, -2;

    gtkadd($o->{window},
	   gtkpack(create_box_with_title($o, @msgs),
		   create_okcancel($o, $ok, $cancel),
		 )
	 );
    $o->{ok}->grab_focus;
}


sub _ask_file {
    my ($o, $title, $path) = @_;
    my $f = $o->{rwindow} = new Gtk::FileSelection $title;
    $f->set_filename($path);
    $f->ok_button->signal_connect(clicked => sub { $o->{retval} = $f->get_filename; Gtk->main_quit });
    $f->cancel_button->signal_connect(clicked => sub { Gtk->main_quit });
    $f->hide_fileop_buttons;
    $f;
}

sub _ask_dir {
    my $f = _ask_file(@_);
    $f->file_list->parent->hide;
    $f->selection_entry->parent->hide;
}

sub ask_browse_tree_info {
    my ($common) = @_;

    my $w = my_gtk->new($common->{title});
    my $tree = Gtk::CTree->new(3, 0);
    $tree->set_selection_mode('browse');
    $tree->set_column_auto_resize($_, 1) foreach 1..2;
    $tree->set_column_width(0, 200);

    gtkadd($w->{window}, 
	   gtkpack_(new Gtk::VBox(0,5),
		    0, $common->{message},
		    1, gtkpack(new Gtk::HBox(0,0),
			       createScrolledWindow($tree),
			       gtkadd(gtkset_usize(new Gtk::Frame(_("Info")), $::windowwidth - 490, 0),
				      createScrolledWindow(my $info = new Gtk::Text),
				     )),
		    0, my $l = new Gtk::HBox(0,15),
		    0, gtkpack(new Gtk::HBox(0,10),
			       my $go = gtksignal_connect(new Gtk::Button($common->{ok}), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
			       $common->{cancel} ? (gtksignal_connect(new Gtk::Button($common->{cancel}), "clicked" => sub { $w->{retval} = 0; Gtk->main_quit })) : (),
			      )
    ));
    gtkpack__($l, my $toolbar = new Gtk::Toolbar('horizontal', 'icons'));

    if ($common->{auto_deps}) {
	gtkpack__($l, gtksignal_connect(gtkset_active(new Gtk::CheckButton($common->{auto_deps}), $common->{state}{auto_deps}),
					clicked => sub { invbool \$common->{state}{auto_deps} }));
    }
    $l->pack_end(my $status = new Gtk::Label, 0, 1, 20);

    $w->{window}->set_usize(map { $_ - 2 * $my_gtk::border - 4 } $::windowwidth, $::windowheight);
    $go->grab_focus;
    $w->{rwindow}->show_all;

    my @toolbar = (ftout  =>  [ _("Expand Tree") , sub { $tree->expand_recursive(undef) } ],
		   ftin   =>  [ _("Collapse Tree") , sub { $tree->collapse_recursive(undef) } ],
		   reload =>  [ _("Toggle between flat and group sorted"), sub { invbool(\$common->{state}{flat}); $common->{rebuild_tree}->() } ]);
    foreach my $ic (@{$common->{icons} || []}) {
	push @toolbar, ($ic->{icon} => [ $ic->{help}, sub {
					     if ($ic->{code}) {
						 my $w = $ic->{wait_message} && $common->{wait_message}->('', $ic->{wait_message});
						 $ic->{code}();
						 $common->{rebuild_tree}->();
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

    my $widgets = { w => $w, tree => $tree, info => $info, status => $status };
    ask_browse_tree_info_given_widgets($common, $widgets);
}

sub ask_browse_tree_info_given_widgets {
    my ($common, $w) = @_;
    my ($curr, $parent, $prev_label, $idle);
    my (%wtree, %ptree, %pix);
    my $update_size = sub {
	my $new_label = $common->{get_status}();
	$prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
    };
    
    my $set_node_state_flat = sub {
	my ($node, $state) = @_;
	$state eq 'XXX' and return;
	$pix{$state} ||= [ gtkcreate_png($state) ];
	$w->{tree}->node_set_pixmap($node, 1, $pix{$state}[0], $pix{$state}[1]);
    };
    my $set_node_state_tree; $set_node_state_tree = sub {
	my ($node, $state) = @_;
	$state eq 'XXX' and return;
	$pix{$state} ||= [ gtkcreate_png($state) ];
	if ($node->{state} ne $state) {
	    if ($node->row->is_leaf) {
		my $parent = $node->row->parent;
		my $stats = $parent->{state_stats} ||= {}; --$stats->{$node->{state}}; ++$stats->{$state};
		my @list = grep { $stats->{$_} > 0 } keys %$stats;
		my $new_state = @list == 1 ? $list[0] : 'semiselected';
		$parent->{state} ne $new_state and $set_node_state_tree->($parent, $new_state);
	    }
	    $w->{tree}->node_set_pixmap($node, 1, $pix{$state}[0], $pix{$state}[1]);
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
		my $n = $w->{tree}->insert_node($s ? $add_parent->($s, $state) : undef, undef, [$_, '', ''], 5, (undef) x 4, 0, 0);
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
	if ($leaf) {
	    my $node = $w->{tree}->insert_node($add_parent->($root, $state), undef, [$leaf, '', ''], 5, (undef) x 4, 1, 0);
	    $set_node_state->($node, $state);
	    push @{$ptree{$leaf}}, $node;
	} else {
	    $add_parent->($root, $state);
	}
    };
    $common->{delete_all} = sub {
	foreach (values %ptree) {
	    delete $_->{state} foreach @$_;
	}
	foreach (values %wtree) {
	    delete $_->{state};
	    delete $_->{state_stats};
	}
	%ptree = %wtree = ();
	$w->{tree}->freeze; $w->{tree}->clear; $w->{tree}->thaw;
    };
    $common->{rebuild_tree} = sub {
	$common->{delete_all}->();
	$set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;
	$w->{tree}->freeze;
	$common->{build_tree}($add_node, $common->{state}{flat}, $common->{tree_mode});
	$w->{tree}->thaw;
	&$update_size;
    };
    $common->{delete_category} = sub {
	my ($cat) = @_;
	exists $wtree{$cat} or return;
	$w->{tree}->freeze;
	foreach (keys %ptree) {
	    my @to_remove;
	    foreach my $node (@{$ptree{$_}}) {
		my $category;
		my $parent = $node;
		while ($parent->row->parent) {
		    $parent = $parent->row->parent;
		    my $parent_name = ($w->{tree}->node_get_pixtext($parent, 0))[0];
		    $category = $category ? "$parent_name|$category" : $parent_name;
		}
		$cat eq $category and push @to_remove, $node;
	    }
	    delete $_->{state} foreach @to_remove;
	    @{$ptree{$_}} = difference2($ptree{$_}, \@to_remove);
	}
	if (exists $wtree{$cat}) {
	    delete $wtree{$cat}{$_} foreach qw(state state_stats);
	    $w->{tree}->remove_node($wtree{$cat});
	    delete $wtree{$cat};
	}
	$w->{tree}->thaw;
	&$update_size;
    };
    $common->{add_nodes} = sub {
	my (@nodes) = @_;
	$w->{tree}->freeze;
	$add_node->($_->[0], $_->[1], $_->[2]) foreach @nodes;
	$w->{tree}->thaw;
	&$update_size;
    };
    
    my $display_info = sub { gtktext_insert($w->{info}, $common->{get_info}($curr)); 0 };
    my $children = sub { map { ($w->{tree}->node_get_pixtext($_, 0))[0] } gtkctree_children($_[0]) };
    my $toggle = sub {
	if (ref $curr && ! $_[0]) {
	    $w->{tree}->toggle_expansion($curr);
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

    $w->{tree}->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr($e->{keyval} & 0xff);
	$toggle->(0) if $e->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ';
	1;
    });
    $w->{tree}->signal_connect(tree_select_row => sub {
	Gtk->timeout_remove($idle) if $idle;

	if ($_[1]->row->is_leaf) {
	    ($curr) = $w->{tree}->node_get_pixtext($_[1], 0);
	    $parent = $_[1]->row->parent;
	    $idle = Gtk->timeout_add(100, $display_info);
	} else {
	    $curr = $_[1];
	}
	$toggle->(1) if $_[2] == 1;
    });
    $common->{rebuild_tree}->();
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
    $w->{w}->main;
}

1;

#-###############################################################################
#- rubbish
#-###############################################################################

#-sub label_align($$) {
#-    my $w = shift;
#-    local $_ = shift;
#-    $w->set_alignment(!/W/i, !/N/i);
#-    $w
#-}

