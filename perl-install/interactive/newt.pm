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

sub new() {
    Newt::Init();
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
sub end() { Newt::Finished() }
sub exit() { end(); exit($_[1]) }
END { end() }

sub myTextbox {
    my $allow_scroll = shift;

    my $width = $width - 9;
    my @l = map { /(.{1,$width})/g } map { split "\n" } @_;
    my $h = min($height - 13, int @l);
    my $flag = 1 << 6; 
    if ($h < @l) {
	if ($allow_scroll) {
	    $flag |= 1 << 2; #- NEWT_FLAG_SCROLL
	} else {
	    # remove the text, no other way!
	    @l = @l[0 .. $h-1];
	}
    }
    my $mess = Newt::Component::Textbox(1, 0, my $w = max(map { length } @l) + 1, $h, $flag);
    $mess->TextboxSetText(join("\n", @_));
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

    if (grep { $_->{type} ne 'button' } @$l or @$l < 5) {
	&ask_fromW_real;
    } else {
	my $r;
	do {
	    my @choices = map {
		my $s = simplify_string(may_apply($_->{format}, ${$_->{val}}));
		$s = "$_->{label}: $s" if $_->{label};
		{ label => $s, clicked_may_quit => $_->{clicked_may_quit} }
	    } @$l;
	    #- replace many buttons with a list
	    my $new_l = [ { val => \$r, type => 'list', list => \@choices, format => sub { $_[0]{label} }, sort => 0 } ];
	    ask_fromW_real($o, $common, $new_l, $l2) or return;
	} until $r->{clicked_may_quit}->();
	1;
    }
}

sub ask_fromW_real {
    my ($_o, $common, $l, $_l2) = @_;
    my $ignore; #-to handle recursivity
    my $old_focus = -2;

    #-the widgets
    my (@widgets, $total_size);

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

	$e->{type} = 'list' if $e->{type} =~ /(icon|tree)list/;

	#- combo doesn't exist, fallback to a sensible default
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

	my ($w, $real_w, $set, $get, $expand, $size);
	if ($e->{type} eq 'bool') {
	    $w = Newt::Component::Checkbox(-1, -1, $e->{text} || '', checkval(${$e->{val}}), " *");
	    $set = sub { $w->CheckboxSetValue(checkval($_[0])) };
	    $get = sub { $w->CheckboxGetValue == ord '*' };
	} elsif ($e->{type} eq 'button') {
	    $w = Newt::Component::Button(-1, -1, simplify_string(may_apply($e->{format}, ${$e->{val}})));
	} elsif ($e->{type} =~ /list/) {
	    my ($h, $wi) = (@$l == 1 && $height > 30 ? 10 : 5, 20);
	    my $scroll = @{$e->{list}} > $h ? 1 << 2 : 0;
	    $size = min(int @{$e->{list}}, $h);

	    $w = Newt::Component::Listbox(-1, -1, $h, $scroll); #- NEWT_FLAG_SCROLL	    
	    foreach (@{$e->{list}}) {
		my $t = simplify_string(may_apply($e->{format}, $_));
		$w->ListboxAddEntry($t, $_);
		$wi = max($wi, length $t);
	    }
	    $w->ListboxSetWidth(min($wi + 3, $width - 7)); # 3 added for the scrollbar (?)
	    $get = sub { $w->ListboxGetCurrent };
	    $set = sub {
		my ($val) = @_;
		each_index {
		    $w->ListboxSetCurrent($::i) if $val eq $_;
		} @{$e->{list}};
	    };
	} else {
	    $w = Newt::Component::Entry(-1, -1, '', 20, ($e->{hidden} && 1 << 11) | (1 << 2));
	    $get = sub { $w->EntryGetValue };
	    $set = sub { $w->EntrySet($_[0], 1) };
	}
	$total_size += $size || 1;

	#- !! callbacks must be kept otherwise perl will free them !!
	#- (better handling of addCallback needed)

	{ e => $e, w => $w, real_w => $real_w || $w, expand => $expand, callback => $changed,
	  get => $get || sub { ${$e->{val}} }, set => $set || sub {} };
    };
    @widgets = map_index { $create_widget->($_, $::i) } @$l;

    $_->{w}->addCallback($_->{callback}) foreach @widgets;

    $set_all->();

    my $grid = Newt::Grid::CreateGrid(3, max(1, int @$l));
    each_index {
	$grid->GridSetField(0, $::i, 1, ${Newt::Component::Label(-1, -1, $_->{e}{label})}, 0, 0, 1, 0, 1, 0);
	$grid->GridSetField(1, $::i, 1, ${$_->{real_w}}, 0, 0, 0, 0, 1, 0);
    } @widgets;

    my $listg = do {
	my $height = 18;
	#- use a scrolled window if there is a lot of checkboxes (aka 
	#- ask_many_from_list) or a lot of widgets in general (aka
	#- options of a native PostScript printer in printerdrake)
	#- !! works badly together with list's (lists are one widget, so a
	#- big list window will not switch to scrollbar mode) :-(
	if (@$l > 3 && $total_size > $height) {
	    $grid->GridPlace(1, 1); #- Uh?? otherwise the size allocated is bad

	    my $scroll = Newt::Component::VerticalScrollbar(-1, -1, $height, 9, 10); # 9=NEWT_COLORSET_CHECKBOX, 10=NEWT_COLORSET_ACTCHECKBOX
	    my $subf = $scroll->Form('', 0);
	    $subf->FormSetHeight($height);
	    $subf->FormAddGrid($grid, 0);
	    Newt::Grid::HCloseStacked3($subf, separator(1, $height-1), $scroll);
	} else {
	    $grid;
	}
    };

    my ($b1, $b2) = map { simplify_string($_) }
      (exists $common->{ok} ? 
       ($common->{ok}, $common->{cancel}) :
       ($::isWizard ? N("Next") : N("Ok"), $common->{cancel} || ($::isWizard ? N("<- Previous") : N("Cancel"))));
    #- b1 is always displayed, so giving it some label :-(
    $b1 ||= $::isWizard ? N("Next") : N("Ok");
    my @b2 = if_($b2, $b2);
    my ($buttons, $ok, $cancel) = Newt::Grid::ButtonBar($::isWizard ? (@b2, $b1) : ($b1, @b2));
    ($ok, $cancel) = ($cancel, $ok) if $::isWizard;

    my $form = Newt::Component::Form(\undef, '', 0);
    my $window = Newt::Grid::GridBasicWindow(first(myTextbox(@widgets == 0, @{$common->{messages}})), $listg, $buttons);
    $window->GridWrappedWindow($common->{title} || '');
    $form->FormAddGrid($window, 1);

    my $check = sub {
	my ($f) = @_;

	$get_all->();
	my ($error, $_focus) = $f->();
	
	if ($error) {
	    $set_all->();
	}
	!$error;
    };

    my ($canceled);
    do {
	my $r = do {
	    local $::setstep = 1;
	    $form->RunForm;
	};
	$canceled = $cancel && $$r == $$cancel;

	if (my ($button) = grep { $$r == ${$_->{w}} } @widgets) {
	    $get_all->();
	    my $v = do {
		local $::setstep = 1;
		$button->{e}{clicked_may_quit}();
	    };
	    $form->FormDestroy;
	    Newt::PopWindow();
	    return $v || &ask_fromW;
	}
    } until $check->($common->{callbacks}{$canceled ? 'canceled' : 'complete'});

    $form->FormDestroy;
    Newt::PopWindow();
    !$canceled;
}


sub waitbox {
    my ($title, $messages) = @_;
    my ($t, $w, $h) = myTextbox(1, @$messages);
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
    my ($s) = @_;
    $s =~ s/\n/ /g;
    $s = substr($s, 0, 40); #- truncate if too long
    $s;
}

1;
