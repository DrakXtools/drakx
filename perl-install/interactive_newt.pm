package interactive_newt;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common :functional);
use log;
use Newt::Newt; #- !! provides Newt and not Newt::Newt

my $width = 80;
my $height = 25;
my @wait_messages;

sub new() {
    Newt::Init;
    Newt::changeColors;
    Newt::Cls;
    Newt::SetSuspendCallback;
    open STDERR,">/dev/null" if $::isStandalone;
    bless {}, $_[0];
}

sub suspend { Newt::Suspend }
sub resume { Newt::Resume }
sub end() { Newt::Finished }
sub exit() { end; exit($_[0]) }
END { end() }

sub myTextbox {
    my @l = map { split "\n" } @_;
    my $mess = Newt::Component::Textbox(1, 0, my $w = max(map { length } @l) + 1, my $h = @l, 1 << 6);
    $mess->TextboxSetText(join("\n", @_));
    $mess, $w + 1, $h;
}

sub separator($$) {
    my $blank = Newt::Component::Form(\undef, '', 0);
    $blank->FormSetWidth ($_[0]);
    $blank->FormSetHeight($_[1]);
    $blank;
}
sub checkval($) { $_[0] && $_[0] ne ' '  ? '*' : ' ' }

sub ask_from_listW {
    my ($o, $title_, $messages, $l, $def) = @_;
    my ($title, @okcancel) = ref $title_ ? @$title_ : ($title_, _("Ok"), _("Cancel"));

    my $mesg = join("\n", @$messages);
    my $len = 0; $len += length($_) foreach @$l;

    if (@$l == 1) {
	Newt::WinMessage($title, @$l, $mesg);
	$l->[0];
#- because newt will not try to remove window if bigger than screen !
    } elsif (@$l == 2 && $len < 64) {
	$l->[Newt::WinChoice($title, @$l, $mesg) - 1];
#- because newt will not try to remove window if bigger than screen !
    } elsif (@$l == 3 && $len < 64) {
	$l->[Newt::WinTernary($title, @$l, $mesg) - 1];
    } else {
	my $special = !@okcancel;
	if ($special) {
	    $l = [ @$l ];
	    @okcancel = pop @$l;
	}
	my $i; map_index { $i = $::i if $def eq $_ } @$l;
	my ($r, $e) = Newt::WinMenu($title, $mesg, 40, 5, 5, 8, $l, $i, @okcancel);
	$r > 1 and die "ask_from_list cancel";
	if ($special) {
	    $r ? $okcancel[0] : $l->[$e];
	} else {
	    $l->[$e];
	}
    }
}

sub ask_many_from_list_refW($$$$$) {
    my ($o, $title, $messages, $list, $val) = @_;
    my $height = min(int @$list, 18);
    
    my $sb = Newt::Component::VerticalScrollbar(-1, -1, $height, 9, 10);
    my $checklist = $sb->Form('', 0);
    $checklist->FormSetHeight($height);
    $checklist->FormSetBackground(9);

    my @l = map_index {	
	Newt::Component::Checkbox(1, $::i + 1, $_, checkval(${$val->[$::i]} ||= ''), " *");
    } @$list;
    $checklist->FormAddComponent($_) foreach @l;

    my $listg = Newt::Grid::HCloseStacked($checklist, $height < @$list ? (separator(1, $height), $sb) : ());

    my ($buttons, $ok, $cancel) = Newt::Grid::ButtonBar(_("Ok"), _("Cancel"));

    my $form = Newt::Component::Form(\undef, '', 0);
    my $window = Newt::Grid::GridBasicWindow(first(myTextbox(@$messages)), $listg, $buttons);
    $window->GridWrappedWindow($title);
    $window->GridAddComponentsToForm($form, 1);
    my $r = $form->RunForm;

    $form->FormDestroy;
    Newt::PopWindow;

    $$r == $$cancel and return;

    mapn {
	my ($a, $b) = @_;
	$$a = $b->CheckboxGetValue == ord '*';
    } $val, \@l;

    1;
}


sub ask_from_entries_refW {
    my ($o, $title, $messages, $l, $val, %hcallback) = @_;
    my ($title_, @okcancel) = deref($title);
    my $ignore = 0; #-to handle recursivity

    #-the widgets
    my @widgets = map {
	$_->{type} = "entry" if $_->{type} eq "list" && !$_->{not_edit};
	${$_->{val}} ||= '';
	if ($_->{type} eq "list" && $_->{not_edit}) {	     
	    $_->{val} ||= $_->{list}[0];
	    my $w = Newt::Component::Listbox(-1, -1, 1, 0);
	    $w->ListboxSetWidth(20);
	    map_index { $w->ListboxAddEntry($_, $_) } @{$_->{list}};
	    $w;
	} elsif ($_->{type} eq "bool") {
	    Newt::Component::Checkbox(-1, -1, $_->{text} || '', checkval(${$_->{val}}), " *");
	} else {
	    Newt::Component::Entry(-1, -1, '', 20, ($_->{hidden} && 1 << 1) | 1 << 2);
	}
    } @$val;

    my @updates = mapn {
	 my ($w, $ref) = @_;
	 sub {
	     ${$ref->{val}} = 
	       $ref->{type} eq "bool" ?
	         $w->CheckboxGetValue == ord '*' :
	       $ref->{type} eq "list" ?
	         $w->ListboxGetCurrent :
		 $w->EntryGetValue;
	 };
    } \@widgets, $val;

    my @updates_inv = mapn {
	 my ($w, $ref) = @_;
	 my $val = ${$ref->{val}};
	 sub {
	     $ref->{type} eq "bool" ?
	       $w->CheckboxSetValue(checkval($val)) :
	     $ref->{type} eq "list" ?
	       $w->ListboxSetCurrentByKey($val) :
	       $w->EntrySet($val, 1);
	 };
    } \@widgets, $val;

    map { &{$updates_inv[$_]} } 0..$#widgets;

    my $grid = Newt::Grid::CreateGrid(3, int @$l);
    map_index {
	$grid->GridSetField(0, $::i, 1, ${Newt::Component::Label(-1, -1, $_)}, 0, 0, 1, 0, 1, 0);
	$grid->GridSetField(1, $::i, 1, ${$widgets[$::i]}, 0, 0, 0, 0, 1, 0);
    } @$l;

    my ($buttons, $ok, $cancel) = Newt::Grid::ButtonBar(@okcancel);

    my $form = Newt::Component::Form(\undef, '', 0);
    my $window = Newt::Grid::GridBasicWindow(first(myTextbox(@$messages)), $grid, $buttons);
    $window->GridWrappedWindow($title_);
    $window->GridAddComponentsToForm($form, 1);
    my $r = $form->RunForm;
    map { &{$updates[$_]} } 0..$#widgets;
    $form->FormDestroy;
    Newt::PopWindow;
    $$r != $$cancel;
}


sub waitbox($$) {
    my ($title, $messages) = @_;
    my ($t, $w, $h) = myTextbox(@$messages);
    my $f = Newt::Component::Form(\undef, '', 0);
    Newt::CenteredWindow($w, $h, $title);
    $f->FormAddComponent($t);
    $f->DrawForm;
    Newt::Refresh;
    $f->FormDestroy;
    push @wait_messages, $f;
    $f;
}


sub wait_messageW($$$) {
    my ($o, $title, $messages) = @_;
    { form => waitbox($title, $messages), title => $title };
}

sub wait_message_nextW {
    my ($o, $messages, $w) = @_;
    $o->wait_message_endW($w);
    $o->wait_messageW($w->{title}, $messages);
}
sub wait_message_endW {
    my ($o, $w) = @_;
    log::l("interactive_newt does not handle none stacked wait-messages") if $w->{form} != pop @wait_messages;
    Newt::PopWindow;
}

sub kill {
}


1;
