package interactive; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);

#- ask_from_entries takes:
#-  val      => reference to the value
#-  label    => description
#-  icon     => icon to put before the description
#-  help     => tooltip
#-  advanced => wether it is shown in by default or only in advanced mode
#-  disabled => function returning wether it should be disabled (grayed)
#-  type     => 
#-     bool (with text)
#-     range (with min, max)
#-     combo (with list, not_edit)
#-     list (with list, icon2f (aka icon), separator (aka tree), format (aka pre_format function),
#-           help can be a hash or a function)
#-     entry (the default) (with hidden)
#
#- heritate from this class and you'll get all made interactivity for same steps.
#- for this you need to provide
#- - ask_from_listW(o, title, messages, arrayref, default) returns one string of arrayref
#-
#- where
#- - o is the object
#- - title is a string
#- - messages is an refarray of strings
#- - default is an optional string (default is in arrayref)
#- - arrayref is an arrayref of strings
#- - arrayref2 contains booleans telling the default state,
#-
#- ask_from_list and ask_from_list_ are wrappers around ask_from_biglist and ask_from_smalllist
#-
#- ask_from_list_ just translate arrayref before calling ask_from_list and untranslate the result
#-
#- ask_from_listW should handle differently small lists and big ones.
#-


#-######################################################################################
#- OO Stuff
#-######################################################################################
sub new($) {
    my ($type) = @_;

    bless {}, ref $type || $type;
}

sub vnew {
    my ($type, $su) = @_;
    $su = $su eq "su";
    require c;
    if ($ENV{DISPLAY} && c::Xtest($ENV{DISPLAY})) {
	if ($su) {
	    $ENV{PATH} = "/sbin:/usr/sbin:$ENV{PATH}";
	    $> and exec "kdesu", "-c", "$0 @ARGV";	    
	}
	require interactive_gtk;
	interactive_gtk->new;
    } else {
	if ($su && $>) {
	    die "you must be root to run this program";
	}
	require 'log.pm';
	undef *log::l;
	*log::l = sub {}; # otherwise, it will bother us :(
	require interactive_newt;
	interactive_newt->new;
    }
}

sub enter_console {}
sub leave_console {}
sub suspend {}
sub resume {}
sub end {}
sub exit { exit($_[0]) }

#-######################################################################################
#- Interactive functions
#-######################################################################################
sub ask_warn {
    my ($o, $title, $message) = @_;
    ask_from_listf_no_check($o, $title, $message, undef, [ _("Ok") ]);
}

sub ask_yesorno {
    my ($o, $title, $message, $def, $help) = @_;
    ask_from_list_($o, $title, $message, [ __("Yes"), __("No") ], $def ? "Yes" : "No", $help) eq "Yes";
}

sub ask_okcancel {
    my ($o, $title, $message, $def, $help) = @_;
    ask_from_list_($o, $title, $message, [ __("Ok"), __("Cancel") ], $def ? "Ok" : "Cancel", $help) eq "Ok";
}

sub ask_from_list {
    my ($o, $title, $message, $l, $def, $help) = @_;
    ask_from_listf($o, $title, $message, undef, $l, $def, $help);
}

sub ask_from_list_ {
    my ($o, $title, $message, $l, $def, $help) = @_;
    ask_from_listf($o, $title, $message, sub { translate($_[0]) }, $l, $def, $help);
}

sub ask_from_listf_ {
    my ($o, $title, $message, $f, $l, $def, $help) = @_;
    ask_from_listf($o, $title, $message, sub { translate($f->(@_)) }, $l, $def, $help);
}
sub ask_from_listf {
    my ($o, $title, $message, $f, $l, $def, $help) = @_;
    @$l == 0 and die 'ask_from_list: empty list';
    @$l == 1 and return $l->[0];
    goto &ask_from_listf_no_check;
}

sub ask_from_listf_no_check {
    my ($o, $title, $message, $f, $l, $def, $help) = @_;

    if (@$l <= 2) {
	ask_from_entries_refH_powered_no_check($o, 
	  { title => $title, messages => $message, ok => $l->[0] && may_apply($f, $l->[0]), 
	    if_($l->[1], cancel => may_apply($f, $l->[1]), focus_cancel => $def eq $l->[1]) }, []
        ) ? $l->[0] : $l->[1];
    } else {
	ask_from_entries_refH($o, $title, $message, [ { val => \$def, type => 'list', list => $l, help => $help, format => $f } ]);
	$def;
    }
}

sub ask_from_treelist {
    my ($o, $title, $message, $separator, $l, $def) = @_;
    ask_from_treelistf($o, $title, $message, $separator, undef, $l, $def);
}
sub ask_from_treelist_ {
    my ($o, $title, $message, $separator, $l, $def) = @_;
    my $transl = sub { join '|', map { translate($_) } split(quotemeta($separator), $_[0]) }; 
    ask_from_treelistf($o, $title, $message, $separator, $transl, $l, $def);
}
sub ask_from_treelistf {
    my ($o, $title, $message, $separator, $f, $l, $def) = @_;
    ask_from_entries_refH($o, $title, $message, [ { val => \$def, separator => $separator, list => $l, format => $f } ]);
    $def;
}

sub ask_many_from_list {
    my ($o, $title, $message, @l) = @_;
    @l = grep { @{$_->{list}} } @l or return '';
    foreach my $h (@l) {
	$h->{e}{$_} = {
	    text => may_apply($h->{label}, $_),
	    val => $h->{val} ? $h->{val}->($_) : do {
		my $i =
		  $h->{value} ? $h->{value}->($_) : 
		    $h->{values} ? member($_, @{$h->{values}}) : 0;
		\$i;
	    },
	    type => 'bool',
	    help => may_apply($h->{help}, $_, ''),
	    icon => may_apply($h->{icon2f}, $_, ''),
	} foreach @{$h->{list}};
	if ($h->{sort}) {
	    $h->{list} = [ sort { $h->{e}{$a}{label} cmp $h->{e}{$b}{label} } @{$h->{list}} ];
	}
    }
    $o->ask_from_entries_refH($title, $message, [ map { my $h = $_; map { $h->{e}{$_} } @{$h->{list}} } @l ]) or return;

    @l = map {
	my $h = $_;
	[ grep { ${$h->{e}{$_}{val}} } @{$h->{list}} ];
    } @l;
    wantarray ? @l : $l[0];
}

sub ask_from_entry {
    my ($o, $title, $message, %callback) = @_;
    first(ask_from_entries($o, $title, $message, [''], %callback));
}
sub ask_from_entries {
    my ($o, $title, $message, $l, %callback) = @_;

    my @l = map { my $i = ''; { label => $_, val => \$i } } @$l;

    $o->ask_from_entries_refH($title, $message, \@l, %callback) ?
      map { ${$_->{val}} } @l :
      undef;
}

#- can get a hash of callback: focus_out changed and complete
#- moreove if you pass a hash with a field list -> combo
#- if you pass a hash with a field hidden -> emulate stty -echo
sub ask_from_entries_refH {
    my ($o, $title, $message, $l, %callback) = @_;
    ask_from_entries_refH_powered($o, { title => $title, messages => $message, callbacks => \%callback }, $l);
}


sub ask_from_entries_refH_powered_normalize {
    my ($o, $common, $l) = @_;

    foreach my $e (@$l) {
	if (my $l = $e->{list}) {
	    if ($e->{sort} || @$l > 10 && !$e->{sort}) {
		my @l2 = map { may_apply($e->{format}, $_) } @$l;
		my @places = sort { $l2[$a] cmp $l2[$b] } 0 .. $#l2;
		$e->{list} = $l = [ map { $l->[$_] } @places ];
	    }
	    $e->{type} = 'iconlist' if $e->{icon2f};
	    $e->{type} = 'treelist' if $e->{separator};
	    add2hash_($e, { not_edit => 1, type => 'combo' });
	    ${$e->{val}} = $l->[0] if ($e->{type} ne 'combo' || $e->{not_edit}) && !member(${$e->{val}}, @$l);
	} elsif ($e->{type} eq 'range') {
	    $e->{min} <= $e->{max} or die "bad range min $e->{min} > max $e->{max} (called from " . join(':', caller()) . ")";
	    ${$e->{val}} = max($e->{min}, min(${$e->{val}}, $e->{max}));
	}
	$e->{disabled} ||= sub { 0 };
    }

    #- don't display empty lists
    @$l = grep { !($_->{list} && @{$_->{list}} == () && $_->{not_edit}) } @$l;

    $common->{$_} = [ deref($common->{$_}) ] foreach qw(messages advanced_messages);
    add2hash_($common, { ok => _("Ok"), cancel => _("Cancel") }) if !exists $common->{ok};
    add2hash_($common->{callbacks} ||= {}, { changed => sub {}, focus_out => sub {}, complete => sub { 0 }, canceled => sub { 0 } });
}

sub ask_from_entries_refH_powered {
    my ($o, $common, $l) = @_;
    ask_from_entries_refH_powered_normalize($o, $common, $l);
    @$l or return 1;
    $o->ask_from_entries_refW($common, [ grep { !$_->{advanced} } @$l ], [ grep { $_->{advanced} } @$l ]);
}
sub ask_from_entries_refH_powered_no_check {
    my ($o, $common, $l) = @_;
    ask_from_entries_refH_powered_normalize($o, $common, $l);
    $o->ask_from_entries_refW($common, [ grep { !$_->{advanced} } @$l ], [ grep { $_->{advanced} } @$l ]);
}


sub wait_message {
    my ($o, $title, $message, $temp) = @_;

    my $w = $o->wait_messageW($title, [ _("Please wait"), deref($message) ]);
    push @tempory::objects, $w if $temp;
    my $b = before_leaving { $o->wait_message_endW($w) };

    #- enable access through set
    common::add_f4before_leaving(sub { $o->wait_message_nextW([ deref($_[1]) ], $w) }, $b, 'set');
    $b;
}

sub kill {}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
