package interactive; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);

#- heritate from this class and you'll get all made interactivity for same steps.
#- for this you need to provide
#- - ask_from_listW(o, title, messages, arrayref, default) returns one string of arrayref
#- - ask_many_from_listW(o, title, messages, arrayref, arrayref2) returns many strings of arrayref
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
sub ask_warn($$$) {
    my ($o, $title, $message) = @_;
    ask_from_list2($o, $title, $message, [ _("Ok") ]);
}

sub ask_yesorno($$$;$) {
    my ($o, $title, $message, $def) = @_;
    ask_from_list_($o, $title, $message, [ __("Yes"), __("No") ], $def ? "Yes" : "No") eq "Yes";
}

sub ask_okcancel($$$;$) {
    my ($o, $title, $message, $def) = @_;
    ask_from_list_($o, $title, $message, [ __("Ok"), __("Cancel") ], $def ? "Ok" : "Cancel") eq "Ok";
}

sub ask_from_list_ {
    my ($o, $title, $message, $l, $def) = @_;
    ask_from_listf($o, $title, $message, sub { translate($_[0]) }, $l, $def);
}

sub ask_from_listf_ {
    my ($o, $title, $message, $f, $l, $def) = @_;
    ask_from_listf($o, $title, $message, sub { translate($f->(@_)) }, $l, $def);
}
sub ask_from_listf {
    my ($o, $title, $message, $f, $l, $def) = @_;
    my $def2;
    my (@l,%l); my $i = 0; foreach (@$l) {
	my $v = $f->($_, $i++);
	push @l, $v;
	$l{$v} = $_;
	$def2 = $v if $def && $_ eq $def;
    }
    $def2 ||= $f->($def) if $def;
    my $r = ask_from_list($o, $title, $message, \@l, $def2) or return;
    $l{$r};
}

sub ask_from_list {
    my ($o, $title, $message, $l, $def) = @_;
    @$l == 0 and die 'ask_from_list: empty list';
    @$l == 1 and return $l->[0];
    goto &ask_from_list2;
}

sub ask_from_list2($$$$;$) {
    my ($o, $title, $message, $l, $def) = @_;

    @$l > 10 and $l = [ sort @$l ];

    $o->ask_from_listW($title, [ deref($message) ], $l, $def || $l->[0]);
}

sub ask_from_list_with_help_ {
    my ($o, $title, $message, $l, $help, $def) = @_;
    @$l == 0 and die '';
    @$l == 1 and return $l->[0];
    goto &ask_from_list2_with_help_;
}

sub ask_from_list_with_help {
    my ($o, $title, $message, $l, $help, $def) = @_;
    @$l == 0 and die '';
    @$l == 1 and return $l->[0];
    goto &ask_from_list2_with_help;
}

#- defaults to simple ask_from_list
sub ask_from_list_with_helpW {
    my ($o, $title, $messages, $l, $help, $def) = @_;
    $o->ask_from_listW($o, $title, $messages, $l, $def);
}

sub ask_from_list2_with_help_($$$$$;$) {
    my ($o, $title, $message, $l, $help, $def) = @_;
    untranslate(
       ask_from_list_with_help($o, $title, $message, [ map { translate($_) } @$l ], $help, translate($def)),
       @$l);
}

sub ask_from_list2_with_help($$$$$;$) {
    my ($o, $title, $message, $l, $help, $def) = @_;

    @$l > 10 and $l = [ sort @$l ];

    $o->ask_from_list_with_helpW($title, [ deref($message) ], $l, $help, $def || $l->[0]);
}

sub ask_from_treelistf {
    my ($o, $title, $message, $separator, $f, $l, $def) = @_;
    my (@l,%l); my $i = 0; foreach (@$l) {
	my $v = $f->($_, $i++);
	push @l, $v;
	$l{$v} = $_;
    }
    my $r = ask_from_treelist($o, $title, $message, $separator, \@l, defined $def ? $f->($def) : $def) or return;
    $l{$r};
}

sub ask_from_treelist {
    my ($o, $title, $message, $separator, $l, $def) = @_;
    $o->ask_from_treelistW($title, [ deref($message) ], $separator, [ sort @$l ], $def || $l->[0]);
}
#- defaults to simple ask_from_list
sub ask_from_treelistW($$$$;$) {
    my ($o, $title, $message, $separator, $l, $def) = @_;
    $o->ask_from_listW($title, [ deref($message) ], $l, $def);
}


sub ask_many_from_list {
    my ($o, $title, $message, @l) = @_;
    @l = grep { @{$_->{list}} } @l or return '';
    foreach my $h (@l) {
	$h->{labels} ||= [ map { $h->{label} ? $h->{label}->($_) : $_ } @{$h->{list}} ];

	if ($h->{sort}) {
	    my @places = sort { $h->{labels}[$a] cmp $h->{labels}[$b] } 0 .. $#{$h->{labels}};
	    $h->{labels} = [ map { $h->{labels}[$_] } @places ];
	    $h->{list}   = [ map { $h->{list}[$_] } @places ];
	}
	$h->{ref} = [ map { 
	    $h->{ref} ? $h->{ref}->($_) : do {
		my $i = 
		  $h->{value} ? $h->{value}->($_) : 
		    $h->{values} ? member($_, @{$h->{values}}) : 0;
		\$i;
	    };
	} @{$h->{list}} ];

	$h->{help} = $h->{help} ? [ map { $h->{help}->($_) } @{$h->{list}} ] : [];
	$h->{icons} = $h->{icon2f} ? [ map { $h->{icon2f}->($_) } @{$h->{list}} ] : [];
    }
    $o->ask_many_from_listW($title, [ deref($message) ], @l) or return;

    @l = map {
	my $h = $_;
	[ grep_index { ${$h->{ref}[$::i]} } @{$h->{list}} ];
    } @l;
    wantarray ? @l : $l[0];
}

sub ask_from_entry {
    my ($o, $title, $message, $label, $def, %callback) = @_;

    first ($o->ask_from_entries($title, [ deref($message) ], [ $label ], [ $def ], %callback));
}

sub ask_from_entries($$$$;$%) {
    my ($o, $title, $message, $l, $def, %callback) = @_;

    my $val = [ map { my $i = $_; \$i } @{$def || [('') x @$l]} ];

    $o->ask_from_entries_ref($title, $message, $l, $val, %callback) ?
      map { $$_ } @$val :
      undef;
}

sub ask_from_entries_refH($$$;$%) {
    my ($o, $title, $message, $h, %callback) = @_;

    ask_from_entries_ref($o, $title, $message,
			 list2kv(@$h),
			 %callback);    
}

#- can get a hash of callback: focus_out changed and complete
#- moreove if you pass a hash with a field list -> combo
#- if you pass a hash with a field hidden -> emulate stty -echo
sub ask_from_entries_ref($$$$;$%) {
    my ($o, $title, $message, $l, $val, %callback) = @_;

    return unless @$l;

    $title = [ deref($title) ];
    $title->[2] ||= _("Cancel") unless $title->[1];
    $title->[1] ||= _("Ok");

    my $val_hash = [ map {
	if ((ref $_) eq "SCALAR") {
	    { val => $_ }
	} else {
	    if (@{$_->{list} || []} > 1) {
		add2hash_($_, { not_edit => 1, type => 'list' });
		${$_->{val}} = $_->{list}[0] if $_->{not_edit} && !member(${$_->{val}}, @{$_->{list}});
	    } elsif ($_->{type} eq 'range') {
		$_->{min} <= $_->{max} or die "bad range min $_->{min} > max $_->{max} (called from " . join(':', caller()) . ")";
		${$_->{val}} = max($_->{min}, min(${$_->{val}}, $_->{max}));
	    }
	    $_;
	}
    } @$val ];

    $o->ask_from_entries_refW($title, [ deref($message) ], $l, $val_hash, %callback)

}
sub wait_message($$$;$) {
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
