package interactive::newt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;
use log;
use Newt::Newt; #- !! provides Newt and not Newt::Newt

my ($width, $height) = (80, 25);
my @wait_messages;

sub new {
    if ($::isInstall) {
	system('unicode_start'); #- do not use run_program, we must do it on current console
	{ 
	    local $ENV{LC_CTYPE} = "en_US.UTF-8";
	    Newt::Init(1);
	}
	c::init_setlocale();
    } else {
	Newt::Init(0);
    }
    Newt::Cls();
    Newt::SetSuspendCallback();
    ($width, $height) = Newt::GetScreenSize();
    open STDERR, ">/dev/null" if $::isStandalone && !$::testing;
    bless {}, $_[0];
}

sub enter_console { Newt::Suspend() }
sub leave_console { Newt::Resume() }
sub suspend { Newt::Suspend() }
sub resume { Newt::Resume() }
sub end { Newt::Finished() }
sub exit { end(); exit($_[1]) }
END { end() }

sub messages { 
    my ($width, @messages) = @_;
    warp_text(join("\n", @messages), $width - 9);
}

sub myTextbox {
    my ($allow_scroll, $free_height, @messages) = @_;

    my @l = messages($width, @messages);
    my $h = min($free_height - 13, int @l);

    my $want_scroll;
    if ($h < @l) {
	if ($allow_scroll) {
	    $want_scroll = 1;
	} else {
	    # remove the text, no other way!
	    @l = @l[0 .. $h-1];
	}
    }

    my $mess = Newt::Component::Textbox(1, 0, my $w = max(map { length } @l) + 1, $h, $want_scroll);
    $mess->TextboxSetText(join("\n", @l));
    $mess, $w + 1, $h;
}

sub separator {
    my $blank = Newt::Component::Form(\undef, '', 0);
    $blank->FormSetWidth($_[0]);
    $blank->FormSetHeight($_[1]);
    $blank;
}
sub checkval { $_[0] && $_[0] ne ' '  ? '*' : ' ' }

sub ask_fromW {
    my ($o, $common, $l, $l2) = @_;

    if (@$l == 1 && $l->[0]{list} && @{$l->[0]{list}} == 2 && listlength(map { split "\n" } @{$common->{messages}}) > 20) {
	#- special ugly case, esp. for license agreement
	my $e = $l->[0];
	my $ok_disabled = $common->{callbacks} && delete $common->{callbacks}{ok_disabled};
	($common->{ok}, $common->{cancel}) = map { may_apply($e->{format}, $_) } @{$e->{list}};
	do {
	    ${$e->{val}} = ask_fromW_real($o, $common, [], $l2) ? $e->{list}[0] : $e->{list}[1];
	} while $ok_disabled && $ok_disabled->();
	1;
    } elsif ((any { $_->{type} ne 'button' } @$l) || @$l < 5) {
	&ask_fromW_real;
    } else {
	$common->{cancel} = N("Do") if $common->{cancel} eq '';
	my $r;
	do {
	    my @choices = map {
		my $s = simplify_string(may_apply($_->{format}, ${$_->{val}}));
		$s = "$_->{label}: $s" if $_->{label};
		{ label => $s, clicked_may_quit => $_->{clicked_may_quit} };
	    } @$l;
	    #- replace many buttons with a list
	    my $new_l = [ { val => \$r, type => 'list', list => \@choices, format => sub { $_[0]{label} }, sort => 0 } ];
	    ask_fromW_real($o, $common, $new_l, $l2) and return;
	} until $r->{clicked_may_quit}->();
	1;
    }
}

sub ask_fromW_real {
    my ($o, $common, $l, $l2) = @_;
    my $ignore; #-to handle recursivity
    my $old_focus = -2;

    my @l = $common->{advanced_state} ? @$l2 : @$l;
    my @messages = (@{$common->{messages}}, if_($common->{advanced_state}, @{$common->{advanced_messages}}));

    #-the widgets
    my (@widgets, $total_size, $has_scroll);

    my $label_width;
    my $get_label_width = sub {
	$label_width ||= max(map { length($_->{label}) } @l);
    };

    my $set_all = sub {
	$ignore = 1;
	$_->{set}->(${$_->{e}{val}}) foreach @widgets;
#	$_->{w}->set_sensitive(!$_->{e}{disabled}()) foreach @widgets;
	$ignore = 0;
    };
    my $get_all = sub {
	${$_->{e}{val}} = $_->{get}->() foreach @widgets;
    };
    my $create_widget = sub {
	my ($e, $ind) = @_;

	$e->{type} = 'list' if $e->{type} =~ /iconlist/;

	#- combo does not exist, fallback to a sensible default
	$e->{type} = $e->{not_edit} ? 'list' : 'entry' if $e->{type} eq 'combo';

	my $changed = sub {
	    return if $ignore;
	    return $old_focus++ if $old_focus == -2; #- handle special first case
	    $get_all->();

	    #- TODO: this is very rough :(
	    $common->{callbacks}{$old_focus == $ind ? 'changed' : 'focus_out'}->($ind);

	    $set_all->();
	    $old_focus = $ind;
	};

	my ($w, $real_w, $set, $get, $expand, $size, $invalid_choice, $extra_text);
	if ($e->{type} eq 'bool') {
	    my $subwidth = $width - $get_label_width->() - 9;
	    my @text = messages($subwidth, $e->{text} || '');
	    $size = @text;
	    $w = Newt::Component::Checkbox(shift(@text), checkval(${$e->{val}}), " *");
	    if (@text) {
		$extra_text = Newt::Component::Textbox(-1, -1, $subwidth, $size - 1, 0);
		$extra_text->TextboxSetText(join("\n", @text));
	    }
	    $set = sub { $w->CheckboxSetValue(checkval($_[0])) };
	    $get = sub { $w->CheckboxGetValue == ord '*' };
	} elsif ($e->{type} eq 'button') {
	    $w = Newt::Component::Button(simplify_string(may_apply($e->{format}, ${$e->{val}})));
	} elsif ($e->{type} eq 'treelist') {
	    $e->{formatted_list} = [ map { may_apply($e->{format}, $_) } @{$e->{list}} ];
	    my $data_tree = interactive::helper_separator_tree_to_tree($e->{separator}, $e->{list}, $e->{formatted_list});

	    my $count; $count = sub {
		my ($t) = @_;
		1 + ($t->{_leaves_} ? int @{$t->{_leaves_}} : 0) 
		  + ($t->{_order_} ? sum(map { $count->($t->{$_}) } @{$t->{_order_}}) : 0);
	    };
	    $size = $count->($data_tree);
	    
	    my $prefered_size = @l == 1 && $height > 30 ? 10 : 5;
	    my $scroll;
	    if ($size > $prefered_size && !$o->{no_individual_scroll}) {
		$has_scroll = $scroll = 1;
		$size = $prefered_size;
	    }

	    $w = Newt::Component::Tree($size, $scroll);

	    my $wi;
	    my $add_item = sub {
		my ($text, $index, $parents) = @_;
		$text = simplify_string($text, $width - 10);
		$wi = max($wi, length($text) + 3 * @$parents + 4);
		$w->TreeAdd($text, $index, $parents);
	    };

	    my @data = '';
	    my $populate; $populate = sub {
		my ($node, $parents) = @_;
		if (my $l = $node->{_order_}) {
		    each_index {
			$add_item->($_, 0, $parents);
			$populate->($node->{$_}, [ @$parents, $::i ]);
		    } @$l;
		}
		if (my $l = $node->{_leaves_}) {
		    foreach (@$l) {
			my ($leaf, $data) = @$_;
			$add_item->($leaf, int(@data), $parents);
			push @data, $data;
		    }
		}
	    };
	    $populate->($data_tree, []);

	    $w->TreeSetWidth($wi + 1);
	    $get = sub { 
		my $i = $w->TreeGetCurrent;
		$invalid_choice = $i == 0;
		$data[$i];
	    };
	    $set = sub {
		my ($data) = @_;
		eval { 
		    my $i = find_index { $_ eq $data } @data;
		    $w->TreeSetCurrent($i);
		} if $data;
		1;
	    };
	} elsif ($e->{type} =~ /list/) {
	    $size = @{$e->{list}};
	    my $prefered_size = @l == 1 && $height > 30 ? 10 : 5;
	    my $scroll;
	    if ($size > $prefered_size && !$o->{no_individual_scroll}) {
		$has_scroll = $scroll = 1;
		$size = $prefered_size;
	    }

	    $w = Newt::Component::Listbox($size, $scroll ? 1 << 2 : 0); #- NEWT_FLAG_SCROLL	    

	    my @l = map { 
		my $t = simplify_string(may_apply($e->{format}, $_), $width - 10);
		$w->ListboxAddEntry($t, $_);
		$t;
	    } @{$e->{list}};

	    $w->ListboxSetWidth(max(map { length($_) } @l) + 3); # 3 added for the scrollbar (?)
	    $get = sub { $w->ListboxGetCurrent };
	    $set = sub {
		my ($val) = @_;
		each_index {
		    $w->ListboxSetCurrent($::i) if $val eq $_;
		} @{$e->{list}};
	    };
	} else {
	    $w = Newt::Component::Entry('', 20, ($e->{hidden} && 1 << 11) | (1 << 2));
	    $get = sub { $w->EntryGetValue };
	    $set = sub { $w->EntrySet($_[0], 1) };
	}
	$total_size += $size || 1;

	#- !! callbacks must be kept otherwise perl will free them !!
	#- (better handling of addCallback needed)

	{ e => $e, w => $w, real_w => $real_w || $w, expand => $expand, callback => $changed,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {},
	  extra_text => $extra_text, invalid_choice => \$invalid_choice };
    };
    @widgets = map_index { $create_widget->($_, $::i) } @l;

    $_->{w}->addCallback($_->{callback}) foreach @widgets;

    $set_all->();

    my $grid = Newt::Grid::CreateGrid(3, max(1, sum(map { $_->{extra_text} ? 2 : 1 } @widgets)));
    my $i;
    foreach (@widgets) {
	$grid->GridSetField(0, $i, 1, ${Newt::Component::Label($_->{e}{label})}, 0, 0, 1, 0, 1, 0);
	$grid->GridSetField(1, $i, 1, ${$_->{real_w}}, 0, 0, 0, 0, 1, 0);
	$i++;
	if ($_->{extra_text}) {
	    $grid->GridSetField(0, $i, 1, ${Newt::Component::Label('')}, 0, 0, 1, 0, 1, 0);
	    $grid->GridSetField(1, $i, 1, ${$_->{extra_text}}, 0, 0, 0, 0, 1, 0);
	    $i++;
	}
    }

    my $listg = do {
	my $wanted_header_height = min(8, listlength(messages($width, @messages)));
	my $height_avail = $height - $wanted_header_height - 13;
	#- use a scrolled window if there is a lot of checkboxes (aka 
	#- ask_many_from_list) or a lot of widgets in general (aka
	#- options of a native PostScript printer in printerdrake)
	#- !! works badly together with list's (lists are one widget, so a
	#- big list window will not switch to scrollbar mode) :-(
	if (@l > 3 && $total_size > $height_avail) {
	    $grid->GridPlace(1, 1); #- Uh?? otherwise the size allocated is bad
	    if ($has_scroll) {
		#- trying again with no_individual_scroll set
		$o->{no_individual_scroll} and internal_error('no_individual_scroll already set, argh...');
		$o->{no_individual_scroll} = 1;
		goto &ask_fromW_real; #- same player shoot again!
	    }
	    $has_scroll = 1;
	    $total_size = $height_avail;

	    my $scroll = Newt::Component::VerticalScrollbar($height_avail, 9, 10); # 9=NEWT_COLORSET_CHECKBOX, 10=NEWT_COLORSET_ACTCHECKBOX
	    my $subf = $scroll->Form('', 0);
	    $subf->FormSetHeight($height_avail);
	    $subf->FormAddGrid($grid, 0);
	    Newt::Grid::HCloseStacked3($subf, separator(1, $height_avail-1), $scroll);
	} else {
	    $grid;
	}
    };

    my ($ok, $cancel) = ($common->{ok}, $common->{cancel});
    my ($need_to_die);
    if (!defined $cancel && !defined $ok) {
        $cancel = $::isWizard && !$::Wizard_no_previous ? N("Previous") : N("Cancel");
        $need_to_die = 1 if !($::isWizard && !$::Wizard_no_previous);
    }
    $ok ||= $::isWizard ? ($::Wizard_finished ? N("Finish") : N("Next")) : N("Ok");

    my @okcancel = grep { $_ } $ok, $cancel;
    @okcancel = reverse(@okcancel) if $::isWizard;
    my @buttons_text = (if_(@$l2, $common->{advanced_state} ? $common->{advanced_label_close} : $common->{advanced_label}), @okcancel);
    my ($buttonbar, @buttons) = Newt::Grid::ButtonBar(map { simplify_string($_) } @buttons_text);
    my $advanced_button = @$l2 && shift @buttons;
    @buttons = reverse(@buttons) if $::isWizard;
    my ($ok_button, $cancel_button) = @buttons;

    my $form = Newt::Component::Form(\undef, '', 0);
    my $window = Newt::Grid::GridBasicWindow(first(myTextbox(!$has_scroll, $height - $total_size, @messages)), $listg, $buttonbar);
    $window->GridWrappedWindow($common->{title} || '');
    $form->FormAddGrid($window, 1);

    my $check = sub {
	my ($f) = @_;

	my ($error, $_focus) = $f->();
	
	if ($error) {
	    $set_all->();
	}
	!$error;
    };

    my ($blocked, $canceled);
    while (1) {
	my $r = $form->RunForm;

	$get_all->();

	if ($advanced_button && $$r == $$advanced_button) {
	    invbool(\$common->{advanced_state});
	    $form->FormDestroy;
	    Newt::PopWindow();
	    return &ask_fromW_real;
	}

	$canceled = $cancel_button && $$r == $$cancel_button;

	next if !$canceled && any { ${$_->{invalid_choice}} } @widgets;

	$blocked = 
	  $$r == $$ok_button && 
	    $common->{callbacks}{ok_disabled} && 
	      do { $common->{callbacks}{ok_disabled}() };

	if (my $button = find { $$r == ${$_->{w}} } @widgets) {
	    my $v = $button->{e}{clicked_may_quit}();
	    $form->FormDestroy;
	    Newt::PopWindow();
	    return $v || &ask_fromW;
	}
	last if !$blocked && $check->($common->{callbacks}{$canceled ? 'canceled' : 'complete'});
    }

    $form->FormDestroy;
    Newt::PopWindow();
    die 'wizcancel' if $need_to_die && $canceled;
    !$canceled;
}


sub waitbox {
    my ($title, $messages) = @_;
    my ($t, $w, $h) = myTextbox(1, $height, @$messages);
    my $f = Newt::Component::Form(\undef, '', 0);
    Newt::CenteredWindow($w, $h, $title);
    $f->FormAddComponent($t);
    $f->DrawForm;
    Newt::Refresh();
    $f->FormDestroy;
    push @wait_messages, $f;
    $f;
}


sub wait_messageW {
    my ($_o, $title, $messages) = @_;
    { form => waitbox($title, $messages), title => $title };
}

sub wait_message_nextW {
    my ($o, $messages, $w) = @_;
    $o->wait_message_endW($w);
    $o->wait_messageW($w->{title}, $messages);
}
sub wait_message_endW {
    my ($_o, $_w) = @_;
    my $_wait = pop @wait_messages;
#    log::l("interactive_newt does not handle none stacked wait-messages") if $w->{form} != $wait;
    Newt::PopWindow();
}

sub simplify_string {
    my ($s, $o_width) = @_;
    $s =~ s/\n/ /g;
    $s = substr($s, 0, $o_width || 40); #- truncate if too long
    $s;
}

sub ok {
    N("Ok");
}

sub cancel {
    N("Cancel");
}

1;
