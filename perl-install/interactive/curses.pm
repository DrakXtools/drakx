# implementer tree

# to debug, use something like
# PERLDB_OPTS=TTY=`tty` LC_ALL=fr_FR.UTF-8 xterm -geometry 80x25 -e sh -c 'DISPLAY= perl -d t.pl'

package interactive::curses; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
use log;
use Curses::UI;

my $SAVEERR;
my $stderr_file = "/tmp/curses-stderr.$$";
my $padleft = 1;
my $padright = 1;
my $indent = 1;
my $cui;

sub new {
    my ($class) = @_;
    if ($::isInstall && !$::local_install) {
	system('unicode_start'); #- do not use run_program, we must do it on current console
    }
    open $SAVEERR, ">&STDERR";
    open STDERR, ">", common::secured_file($stderr_file);

    $cui ||= Curses::UI->new('-color_support' => 1);
    bless { cui => $cui }, $class;
}

sub enter_console { &suspend }
sub leave_console { &end }
sub suspend { Curses::UI->leave_curses }
sub resume { Curses::UI->reset_curses }
sub end { &suspend; print $SAVEERR $_ foreach cat_($stderr_file); unlink $stderr_file }
sub exit { end(); CORE::exit($_[1] || 0) }
END { end() }

sub _messages { 
    my ($width, @messages) = @_;
    warp_text(join("\n", @messages), $width);
}

sub _enable_disable {
    my ($w, $disabled) = @_;

    if ($disabled ? $w->{'-is-disabled'} : !$w->{'-is-disabled'}) {
	return;
    }
    $w->{'-is-disabled'} = $disabled;

    if ($disabled) {
	add2hash_($w, { '-was-focusable' => $w->focusable, '-was-fg' => $w->{'-fg'}, '-was-bfg' => $w->{'-bfg'} });
	$w->focusable(0);
	$w->{'-fg'} = $w->{'-bfg'} = 'blue';
    } else {
	$w->focusable($w->{'-was-focusable'});
	$w->{'-fg'} = $w->{'-was-fg'};
	$w->{'-bfg'} = $w->{'-was-bfg'};
    }
    $w->intellidraw;
}

sub filter_widget {
    my ($e) = @_;

    if ($e->{title} || $e->{type} eq 'expander') {
	$e->{no_indent} = 1;
    }

    $e->{type} = 'list' if $e->{type} =~ /iconlist|treelist/;

    #- combo does not allow modifications
    $e->{type} = 'entry' if $e->{type} eq 'combo' && !$e->{not_edit};

    $e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];

    $e->{default_curses} ||= delete $e->{curses};
}
sub filter_widgets {
    my ($l) = @_;

    filter_widget($_) foreach @$l;

    map {
	if (@$_ > 1) {
	    my $e = { type => 'checkboxes', label => $_->[0]{label}, val => \ (my $_ignored),
		      list => [ map { $_->{text} } @$_ ], children => $_ };
	    filter_widget($e);
	    $e;
	} else {
	    @$_;
	}
    } common::group_by { !$_[0]{disabled} && 
			   $_[0]{type} eq 'bool' && $_[1]{type} eq 'bool'
			     && !$_[1]{label} } @$l;
}


sub heights {
    my ($best, @fallbacks) = @_;
    join(',', $best, grep { $_ < $best } @fallbacks);
}

sub entry_height {
    my ($e) = @_;
    to_int(max($e->{curses}{'-height'}, $e->{label_height} || 0));
}

sub compute_label_size {
    my ($e, $available_width, $o_fixed_width) = @_;

    $e->{label} or return;

    my @text = _messages(min(80, $o_fixed_width || $available_width), $e->{label});
    $e->{label_text_wrapped} = join("\n", @text);
    $e->{label_height} = int(@text);
    $e->{label_width} = $o_fixed_width || max(map { length } @text);
}
sub compute_label_sizes {
    my ($cui, $wanted_widgets) = @_;

    my $available_width = $cui->{'-width'} - 4;

    foreach (@$wanted_widgets) {
	compute_label_size($_, $available_width);
    }
}

sub compute_size {
    my ($e, $previous_e, $available_width, $o_labels_width) = @_;

    {
	my %c = %{$e->{default_curses} || {}};
	$e->{curses} = \%c;
    }
    #- if $o_labels_width is given, it will be used
    compute_label_size($e, $available_width, $o_labels_width);
    $e->{curses}{'-x'} ||= 
      $previous_e && $previous_e->{same_line} ? 1 + $previous_e->{curses}{'-x'} + $previous_e->{curses}{'-width'} :
      $e->{no_indent} ? $padleft :
      $padleft + $indent + ($e->{label_width} ? $e->{label_width} + 1 : 0);

    my $width_avail = $available_width - $e->{curses}{'-x'};

    if ($e->{type} eq 'bool') {
	my $indent = length("[X] ");
	my @text = _messages($width_avail - $indent, $e->{text} || '');
	$e->{curses}{'-height'} ||= heights(int(@text), 4);
	$e->{curses}{'-width'} ||= max(map { length } @text) + $indent + 1;
	$e->{curses}{'-label'} = join("\n", @text);
    } elsif ($e->{type} eq 'combo') {
	$e->{curses}{'-height'} ||= 1;
	$e->{curses}{'-width'} ||= max(map { length } @{$e->{formatted_list}}) + 3;	
    } elsif ($e->{type} eq 'checkboxes') {
	$e->{curses}{'-height'} ||= heights(map { $_ + 2 } int(@{$e->{formatted_list}}), 10, 4);
	$e->{curses}{'-width'} ||= max(map { length } @{$e->{formatted_list}}) + 7;
    } elsif ($e->{type} =~ /list/) {
	$e->{curses}{'-height'} ||= heights(map { $_ + 2 } int(@{$e->{formatted_list}}), 5, 4);
	$e->{curses}{'-width'} ||= max(map { length } @{$e->{formatted_list}}) + 3;	
    } elsif ($e->{type} eq 'button') {
	my $s = sprintf('< %s >', may_apply($e->{format}, ${$e->{val}}));
	$e->{curses}{'-width'} ||= length($s);
    } elsif ($e->{type} eq 'expander') {
	$e->{curses}{'-width'} ||= length("<+> $e->{text}");
    } elsif ($e->{type} eq 'text' || $e->{type} eq 'label' || $e->{type} eq 'only_label') {
	my @text = _messages(min(80, $width_avail - 1), ${$e->{val}}); #- -1 because of the scrollbar
	$e->{curses}{'-focusable'} = 0;
	$e->{curses}{'-height'} ||= heights(int(@text), 10, 4);
	$e->{curses}{'-width'} ||= 1 + max(map { length } @text);
    } else {
	$e->{curses}{'-width'} ||= 20;
    }
    $e->{curses}{'-height'} ||= 1;

}

sub compute_sizes {
    my ($cui, $wanted_widgets, $o_labels_width, $b_first_time) = @_;

    my ($available_width, $available_height) = ($cui->{'-width'} - 2, $cui->{'-height'} - 2);

    my $previous;
    foreach (@$wanted_widgets) {
	compute_size($_, $previous, $available_width, $o_labels_width);
	$previous = $_;
    }

    my $width = max(map { $_->{curses}{'-x'} + $_->{curses}{'-width'} } @$wanted_widgets);
    if ($width > $available_width) {
	log::l("oops, could not fit... (width $width > $available_width)\n");
	if ($o_labels_width && $b_first_time) {
	    log::l("retrying without aligning entries");
	    return compute_sizes($cui, $wanted_widgets);
	} elsif (!$o_labels_width) {
	    my $width_no_labels = 4 + max(map { $_->{label} ? $_->{curses}{'-width'} : 0 } @$wanted_widgets);
	    if ($width_no_labels < $available_width) {
		#- trying to force a smaller labels width
		log::l("retrying forcing a smaller size for labels ($available_width - $width_no_labels)");
		return compute_sizes($cui, $wanted_widgets, $available_width - $width_no_labels);
	    } else {
		log::l("going on even if labels are too wide ($width_no_labels >= $available_width");
	    }
	} else {
	    log::l("going on even if labels can't fit forced to $o_labels_width ($width < $available_width)");
	}
    }
    my $height;
    my $i = @$wanted_widgets;
  retry: while (1) {
	$height = sum(map { entry_height($_) } grep { !$_->{same_line} } @$wanted_widgets) + 1;
	$height > $available_height or last;
	while ($i--) {
	    if ($wanted_widgets->[$i]{curses}{'-height'} =~ s/\d+,//) {
#-		warn "retring after modifying $wanted_widgets->[$i]{type}\n";
		if ($wanted_widgets->[$i]{type} eq 'text') {
		    $wanted_widgets->[$i]{curses}{'-vscrollbar'} = 1;
		    $wanted_widgets->[$i]{curses}{'-focusable'} = 1;
		}
		goto retry;
	    }
	}
	log::l("oops, could not fit... (height $height > $available_height)\n");
	if ($o_labels_width) {
	    log::l("retrying without aligning entries");
	    compute_sizes($cui, $wanted_widgets);
	} else {
	    #- hum, we need to use expander to split things
	    my $nb;
	    my $height = 5; #- room from buttons and expander
	    foreach (@$wanted_widgets) {
		$height += to_int($_->{curses}{'-height'}) if !$_->{same_line};
		$height <= $available_height or die "too_many $nb\n";
		$nb++;
	    }
	    internal_error("should have died");
	}
    }

    +{
	'-x' => int(($available_width - $width) / 2 - 1),
	'-y' => int(($available_height - $height) / 2 - 1),
	'-width' => $width + 2,
	'-height' => $height + 2,
    };
}

sub compute_buttons {
    my ($common, $validate) = @_;

    my %buttons = (ok => $common->{ok}, cancel => $common->{cancel});
    if (!defined $buttons{cancel} && !defined $buttons{ok}) {
        $buttons{cancel} = $::isWizard && !$::Wizard_no_previous ? N("Previous") : N("Cancel");
#        $need_to_die = 1 if !($::isWizard && !$::Wizard_no_previous);
    }
    $buttons{ok} ||= $::isWizard ? ($::Wizard_finished ? N("Finish") : N("Next")) : N("Ok");

    my @button_names = grep { $buttons{$_} } 'ok', 'cancel';
    @button_names = reverse(@button_names) if $::isWizard;

    my $same_line = @button_names;

    my %buttons_e = map {
	my $name = $_;
	my $label = "< $buttons{$name} >";

	$name =>
	  { type => 'button', val => \$buttons{$name}, same_line => --$same_line, no_indent => 1,
	    default_curses => { '-height' => 1, '-width' => length($label) },
	    clicked_may_quit => $name eq 'ok' ? $validate : sub { '0 but true' },
	};
    } @button_names;

    $buttons_e{$common->{focus_cancel} ? 'cancel' : 'ok'}{focus} = sub { 1 };
    $buttons_e{ok}{disabled} = $common->{ok_disabled} if $common->{ok_disabled};

    map { $buttons_e{$_} } @button_names;
}

sub create_widget {
    my ($cui, $win, $e, $y, $changed, $focus_out) = @_;

    my $onchange = sub {
	my ($f) = @_;
	sub { 
	    ${$e->{val}} = $f->(); 
	    $changed->() if $changed;
	};
    };

    #- take the best remaining proposed height
    $e->{curses}{'-height'} = to_int($e->{curses}{'-height'});

    my %options = ('-y' => $y, %{$e->{curses}});

    if ($e->{label}) {
	$e->{label_w} = $win->add(undef, 
				  $e->{label_height} <= 1 ? 'Label' : 
				    ('TextViewer', 
				     '-width' => $e->{label_width},
				     '-focusable' => 0,
				     '-height' => $e->{label_height}),
				  '-text' => $e->{label_text_wrapped}, 
				  '-y' => $options{'-y'}, '-x' => $padleft + 1,
			      );
    }

    if (!$e->{same_line}) {
	delete $options{'-width'};
	$options{'-padright'} = $padright;
    }
    $options{'-onblur'} = $focus_out if $focus_out;

    my ($w, $set);
    if ($e->{type} eq 'bool') {
	$w = $win->add(
	    undef, 'Checkbox',
	    '-checked' => ${$e->{val}},
	    '-onchange' => $onchange->(sub { $w->get }),
	    %options);
	$set = sub { my $meth = $_[0] ? 'check' : 'uncheck'; $w->$meth; $w->intellidraw };
    } elsif ($e->{type} eq 'expander') {
	my $toggle_s = '<+> ';
	$e->{label_w} = $win->add(undef, 'Label', '-bold' => 1, '-text' => $toggle_s, %options);
	$options{'-x'} += length($toggle_s);
	$w = $win->add(undef, 'Buttonbox', '-buttons' => [ {
	    '-label' => $e->{text},
	    '-onpress' => sub { 
		my $common = { ok => "Close", cancel => '', messages => [ if_($e->{message}, $e->{message}) ] };
		ask_fromW_($cui, $common, $e->{children});
	    },
	} ], %options);
    } elsif ($e->{type} eq 'button') {
	my $clicked_may_quit = delete $options{clicked_may_quit};
	$w = $win->add(undef, 'Buttonbox', '-buttons' => [ {
	    '-onpress' => $clicked_may_quit || sub { 1 },
	} ], %options);
	$w->set_binding('focus-up', Curses::KEY_LEFT());
	$w->set_binding('focus-down', Curses::KEY_RIGHT());
	$set = sub { $w->set_label(0, sprintf('< %s >', may_apply($e->{format}, $_[0]))) };
    } elsif ($e->{type} eq 'list' || $e->{type} eq 'combo') {
	$w = $win->add(undef, $e->{type} eq 'combo' ? 'Popupmenu' : 'Listbox', 
		       '-values' => $e->{formatted_list},
		       '-onchange' => $onchange->(sub { $e->{list}[$w->id] }),
		       if_($e->{type} eq 'list',
			   '-vscrollbar' => 1,
			   '-onselchange' => sub {
			       #- we don't want selection AND active, so ensuring they are the same
			       $w->id == $w->get_active_id or $w->set_selection($w->get_active_id);
			   }),
		       %options);
	$set = sub {
	    my ($val) = @_;
	    my $s = may_apply($e->{format}, $val);
	    eval { 
		my $id = find_index { $s eq $_ } @{$e->{formatted_list}};
		$w->set_selection($id);
		if ($w->can('set_active_id')) {
		    $w->set_active_id($id);
		    $w->intellidraw;
		}
	    };
	};
    } elsif ($e->{type} eq 'checkboxes') {
	my @selection;
	$w = $win->add(undef, 'Listbox', 
		       '-values' => $e->{formatted_list},
		       '-vscrollbar' => 1,
		       '-multi' => 1,
		       '-onselchange' => sub {
			   my @new = $w->id;
			   my %ids = (
			       (map { $_ => 1 } difference2(\@new, \@selection)),
			       (map { $_ => 0 } difference2(\@selection, \@new)),
			   );
			   foreach (keys %ids) {
			       my $sub_e = $e->{children}[$_];
			       ${$sub_e->{val}} = $ids{$_};
			       $changed->() if $changed;
			   }
		       },			   
		       %options);
	$set = sub {
	    @selection = map_index { if_(${$_->{val}}, $::i) } @{$e->{children}};
	    $w->set_selection(@selection);
	};
    } elsif ($e->{type} eq 'only_label' && $e->{curses}{'-height'} == 1) {
	$w = $win->add(undef, 'Label', '-text' => ${$e->{val}}, 
		       if_($e->{title}, '-bold' => 1), 
		       %options);
    } elsif ($e->{type} eq 'label' && $e->{curses}{'-height'} == 1) {
	$w = $win->add(undef, 'Label', %options);
	$set = sub { $w->text($_[0] || '') };
    } elsif ($e->{type} eq 'label' || $e->{type} eq 'only_label' || $e->{type} eq 'text') {
	$w = $win->add(undef, 'TextViewer', %options);
	$set = sub { 
	    my ($text) = @_;
	    my $width = $w->{'-sw'} - ($w->{'-vscrollbar'} ? 1 : 0);
	    $w->text(join("\n", _messages($width, $text)));
	};
    } else {
	$w = $win->add(undef, $e->{hidden} ? 'PasswordEntry' : 'TextEntry', 
		       '-sbborder' => 1,
		       '-text' => '', 
		       '-onchange' => $onchange->(sub { $w->text }),
		       %options);
	$set = sub { $w->text($_[0] || '') };
    }

    $e->{w} = $w;
    $e->{set} = $set || sub {};
}

sub create_widgets {
    my ($cui, $win, $l) = @_;

    my $ignore; #-to handle recursivity
    my $set_all = sub {
	$ignore = 1;
	foreach my $e (@$l) {
	    $e->{set}->(${$e->{val}});
	    my $disabled = $e->{disabled} && $e->{disabled}();
	    _enable_disable($e->{w}, $disabled);
	    _enable_disable($e->{label_w}, $disabled) if $e->{label_w};
	}
	$ignore = 0;
    };
    my $sub_update = sub {
	my ($f) = @_;
	sub {
	    return if $ignore;
	    $f->() if $f;
	    $set_all->();
	};
    };

    my $to_focus;
    my $y = 1;
    foreach (@$l) {
	my $e = $_;

	$e->{curses}{clicked_may_quit} = sub {
	    if (my $v = $e->{clicked_may_quit}()) {
		die "exit_mainloop $v";
	    }
	    $set_all->();
	} if $e->{clicked_may_quit};

	create_widget($cui, $win, $e, $y, $sub_update->($e->{changed}), $sub_update->($e->{focus_out}));
	$to_focus ||= $e if $e->{focus} && $e->{focus}->();
	$y += entry_height($e) if !$e->{same_line};
    }

    ($to_focus || $l->[-1])->{w}->focus;

    $set_all->();

    $set_all;
}

sub all_entries {
    my ($l) = @_;
    map { $_, if_($_->{children}, @{$_->{children}}) } @$l;
}

sub ask_fromW {
    my ($o, $common, $l) = @_;
    ask_fromW_($o->{cui}, $common, $l);
}

sub ask_fromW_ {
    my ($cui, $common, $l) = @_;

    $l = [ filter_widgets($l) ];

    my $set_all;
    my $validate = sub {
	my @all = all_entries($l);
	my $e = find { $_->{validate} && !$_->{validate}->() } @all;
	$e ||= $common->{validate} && !$common->{validate}() && $all[0];
	if ($e) {
	    $set_all->();
	    $e->{w}->focus if $e->{w}; #- widget may not exist if it is inside an expander
	}
	!$e;
    };

    my @wanted_widgets = (
	if_(@{$common->{messages}}, { type => 'text', val => \(join("\n", @{$common->{messages}}, ' ')) }),
	@$l,
	{ type => 'label', val => \ (my $_ignore) },
	compute_buttons($common, $validate),
    );

    compute_label_sizes($cui, $l);
    my $labels_width = max(map { $_->{label_width} } @$l);
    my $window_size;
    eval { $window_size = compute_sizes($cui, \@wanted_widgets, $labels_width, 'first_time') } or do {
	my ($nb) = $@ =~ /^too_many (\d+)$/ or die;
	$nb -= 1; #- remove {messages}
	$nb != @$l or internal_error("dead-loop detected");

	my @l = (
	    (@$l)[0 .. $nb - 1], 
	    { type => 'expander', text => N("More"), children => [ (@$l)[$nb .. $#$l] ] },
	);
	return ask_fromW_($cui, $common, \@l);
    };

    my $win = $cui->add(undef, 'Window',
			     %$window_size,
			     '-border' => 1, 
			     '-bfg' => 'blue', '-tfg' => 'yellow', '-tbg' => 'blue', '-titlereverse' => 0,
			     '-focusable' => 1,
			     if_($common->{title}, '-title' => $common->{title}),
			 );

    $set_all = create_widgets($cui, $win, \@wanted_widgets);

    $win->set_binding(\&exit, "\cC");
    $win->set_binding(sub { suspend(); kill 19, $$ }, "\cZ");

    $cui->focus($win, 1);
    eval { $win->modalfocus };

    my $err = $@;
    $cui->delete_object($win);
    $cui->draw;

    my ($v) = $err =~ /^exit_mainloop (\S*)/ or die $err;

    $v eq '0 but true' ? 0 : $v;
}


sub wait_messageW {
    my ($o, $title, $message, $message_modifiable) = @_;

    my $w = { title => $title, message_header => $message };
    wait_message_nextW($o, $message_modifiable, $w);
    $w;
}

sub wait_message_nextW {
    my ($o, $message, $w) = @_;

    wait_message_endW($o, $w) if $w->{w};
    my $msg = join("\n", _messages($o->{cui}{'-width'}, $w->{message_header} . "\n" . $message));
    $w->{w} = $o->{cui}->add(undef, 'Dialog::Status', '-title' => $w->{title}, '-message' => $msg);
    $w->{w}->draw;
}
sub wait_message_endW {
    my ($o, $w) = @_;
    $o->{cui}->delete_object($w->{w});
    $o->{cui}->draw;
}

sub wait_message_with_progress_bar {
    my ($o, $o_title) = @_;

    my $w = {};
    my $b = before_leaving { $o->wait_message_endW($w) };
    $b, sub {
	my ($msg, $current, $total) = @_;
	if (!$w->{w} || $w->{total} != $total) {
	    $o->{cui}->delete_object($w->{w}) if $w->{w};

	    $w->{w} = $o->{cui}->add(undef, 
				     $total ? ('Dialog::Progress', '-max' => $total) : 'Dialog::Status', 
				     if_($o_title, '-title' => $o_title),
				     '-message' => $msg || $w->{msg});
	    $w->{total} = $total;
	    $w->{msg} = $msg;
	} elsif ($msg) {
	    $w->{w}->message($msg);
	}
	if ($current) {
	    $w->{w}->pos($current);
	}
	$o->{cui}->draw;
    };
}

1;
