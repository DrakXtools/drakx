package interactive; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use MDK::Common::Func;
use common;

#- minimal example using interactive:
#
#- > use lib qw(/usr/lib/libDrakX);
#- > use interactive;
#- > my $in = interactive->vnew;
#- > $in->ask_okcancel('title', 'question');
#- > $in->exit;

#- ask_from_entries takes:
#-  val      => reference to the value
#-  label    => description
#-  icon     => icon to put before the description
#-  help     => tooltip
#-  advanced => wether it is shown in by default or only in advanced mode
#-  disabled => function returning wether it should be disabled (grayed)
#-  gtk      => gtk preferences
#-  type     => 
#-     button => (with clicked or clicked_may_quit)
#-               (type defaults to button if clicked or clicked_may_quit is there)
#-               (val need not be a reference) (if clicked_may_quit return true, it's as if "Ok" was pressed)
#-     label => (val need not be a reference) (type defaults to label if val is not a reference) 
#-     bool (with text)
#-     range (with min, max)
#-     combo (with list, not_edit, format)
#-     list (with list, icon2f (aka icon), separator (aka tree), format (aka pre_format function),
#-           help can be a hash or a function,
#-           tree_expanded boolean telling wether the tree should be wide open by default
#-           quit_if_double_click boolean
#-           allow_empty_list disables the special cases for 0 and 1 element lists)
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
    my ($type, $su, $icon) = @_;
    $su = $su eq "su";
    if ($ENV{INTERACTIVE_HTTP}) {
	require interactive_http;
	return interactive_http->new;
    }
    require c;
    if ($ENV{DISPLAY} && system('/usr/X11R6/bin/xtest') == 0) {
	if ($su) {
	    $ENV{PATH} = "/sbin:/usr/sbin:$ENV{PATH}";
	    if ($>) {
		exec("kdesu", "-c", "$0 @ARGV") or die _("kdesu missing");
	    }
	}
	eval { require interactive_gtk };
	if (!$@) {
	    my $o = interactive_gtk->new;
	    if ($icon && $icon ne 'default' && !$::isWizard) { $o->{icon} = $icon } else { undef $o->{icon} }
	    return $o;
	}
    }

    if ($su && $>) {
	die "you must be root to run this program";
    }
    require 'log.pm';
    undef *log::l;
    *log::l = sub {}; # otherwise, it will bother us :(
    require interactive_newt;
    interactive_newt->new;
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
    local $::isWizard=0;
    ask_from_listf_no_check($o, $title, $message, undef, [ _("Ok") ]);
}

sub ask_yesorno {
    my ($o, $title, $message, $def, $help) = @_;
    ask_from_list_($o, $title, $message, [ __("Yes"), __("No") ], $def ? "Yes" : "No", $help) eq "Yes";
}

sub ask_okcancel {
    my ($o, $title, $message, $def, $help) = @_;

    if ($::isWizard) {
	$::no_separator = 1;
    	$o->ask_from_no_check({ title => $title, messages => $message, focus_cancel => !$def });
    } else {
	ask_from_list_($o, $title, $message, [ __("Ok"), __("Cancel") ], $def ? "Ok" : "Cancel", $help) eq "Ok";
    }
}

sub ask_file {
    my ($o, $title, $dir) = @_;
    $o->ask_fileW($title, $dir);
}
sub ask_fileW {
    my ($o, $title, $dir) = @_;
    $o->ask_from_entry($title, _("Choose a file"));
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
    @$l == 0 and die "ask_from_list: empty list\n" . common::backtrace();
    @$l == 1 and return $l->[0];
    goto &ask_from_listf_no_check;
}

sub ask_from_listf_no_check {
    my ($o, $title, $message, $f, $l, $def, $help) = @_;

    if (@$l <= 2 && !$::isWizard) {
	my $ret = eval {
	    ask_from_no_check($o, 
	      { title => $title, messages => $message, ok => $l->[0] && may_apply($f, $l->[0]), 
		if_($l->[1], cancel => may_apply($f, $l->[1]), focus_cancel => $def eq $l->[1]) }, []
            ) ? $l->[0] : $l->[1];
	};
	die if $@ && $@ !~ /^wizcancel/;
	$@ ? undef : $ret;
    } else {
	ask_from($o, $title, $message, [ { val => \$def, type => 'list', list => $l, help => $help, format => $f } ]) && $def;
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
    ask_from($o, $title, $message, [ { val => \$def, separator => $separator, list => $l, format => $f, sort => 1 } ]) or return;
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
	    $h->{list} = [ sort { $h->{e}{$a}{text} cmp $h->{e}{$b}{text} } @{$h->{list}} ];
	}
    }
    $o->ask_from($title, $message, [ map { my $h = $_; map { $h->{e}{$_} } @{$h->{list}} } @l ]) or return;

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

    $o->ask_from($title, $message, \@l, %callback) ?
      map { ${$_->{val}} } @l :
      undef;
}

#- can get a hash of callback: focus_out changed and complete
#- moreove if you pass a hash with a field list -> combo
#- if you pass a hash with a field hidden -> emulate stty -echo
sub ask_from {
    my ($o, $title, $message, $l, %callback) = @_;
    ask_from_($o, { title => $title, messages => $message, callbacks => \%callback }, $l);
}


sub ask_from_normalize {
    my ($o, $common, $l) = @_;

    foreach my $e (@$l) {
	if (my $l = $e->{list}) {
	    if ($e->{sort} || @$l > 10 && !exists $e->{sort}) {
		my @l2 = map { may_apply($e->{format}, $_) } @$l;
		my @places = sort { $l2[$a] cmp $l2[$b] } 0 .. $#l2;
		$e->{list} = $l = [ map { $l->[$_] } @places ];
	    }
	    $e->{type} = 'iconlist' if $e->{icon2f};
	    $e->{type} = 'treelist' if $e->{separator};
	    add2hash_($e, { not_edit => 1, type => 'combo' });
	    ${$e->{val}} = $l->[0] if ($e->{type} ne 'combo' || $e->{not_edit}) && !member(${$e->{val}}, @$l);
	    if ($e->{type} eq 'combo' && $e->{format}) {
		my @l = map { $e->{format}->($_) } @{$e->{list}};
		each_index {
		    ${$e->{val}} = $l[$::i] if $_ eq ${$e->{val}};
		} @{$e->{list}};
		($e->{list}, $e->{saved_list}) = (\@l, $e->{list});
	    }
	} elsif ($e->{type} eq 'range') {
	    $e->{min} <= $e->{max} or die "bad range min $e->{min} > max $e->{max} (called from " . join(':', caller()) . ")";
	    ${$e->{val}} = max($e->{min}, min(${$e->{val}}, $e->{max}));
	} elsif ($e->{type} eq 'button' || $e->{clicked} || $e->{clicked_may_quit}) {
	    $e->{type} = 'button';
	    $e->{clicked_may_quit} ||= $e->{clicked} ? sub { $e->{clicked}(); 0 } : sub {};	    
	    $e->{val} = \ (my $v = $e->{val}) if !ref($e->{val});
	} elsif ($e->{type} eq 'label' || !ref($e->{val})) {
	    $e->{type} = 'label';
	    $e->{val} = \ (my $v = $e->{val}) if !ref($e->{val});
	} else {
	    $e->{type} ||= 'entry';
	}
	$e->{disabled} ||= sub { 0 };
    }

    #- don't display empty lists and one element lists
    @$l = grep { 
	if ($_->{list} && $_->{not_edit} && !$_->{allow_empty_list}) {
	    if (@{$_->{list}} == ()) {
		eval {
		    require log;
		    log::l("ask_from_normalize: empty list for $_->{label}\n" . common::backtrace());
		};
	    }
	    @{$_->{list}} > 1;
	} else {
	    1;
	}
    } @$l;

    $common->{advanced_label} ||= _("Advanced");
    $common->{advanced_label_close} ||= _("Basic");
    $common->{$_} = [ deref($common->{$_}) ] foreach qw(messages advanced_messages);
    add2hash_($common, { ok => _("Ok"), cancel => _("Cancel") }) if !exists $common->{ok} && !$::isWizard;
    add2hash_($common->{callbacks} ||= {}, { changed => sub {}, focus_out => sub {}, complete => sub { 0 }, canceled => sub { 0 } });
}

sub ask_from_ {
    my ($o, $common, $l) = @_;
    ask_from_normalize($o, $common, $l);
    @$l or return 1;
    ask_from_real($o, $common, $l);
}
sub ask_from_no_check {
    my ($o, $common, $l) = @_;
    ask_from_normalize($o, $common, $l);
    $o->ask_fromW($common, [ grep { !$_->{advanced} } @$l ], [ grep { $_->{advanced} } @$l ]);
}
sub ask_from_real {
    my ($o, $common, $l) = @_;
    my $v = $o->ask_fromW($common, [ grep { !$_->{advanced} } @$l ], [ grep { $_->{advanced} } @$l ]);
    %$common = ();
    foreach my $e (@$l) {
	my $l = delete $e->{saved_list} or next;
	each_index {
	    ${$e->{val}} = $l->[$::i] if $_ eq ${$e->{val}};
	} @{$e->{list}};
	$e->{list} = $l;
    }
    $v;
}


sub ask_browse_tree_info {
    my ($o, $title, $message, $common) = @_;
    add2hash_($common, { ok => _("Ok"), cancel => _("Cancel") });
    add2hash_($common, { title => $title, message => $message });
    add2hash_($common, { grep_allowed_to_toggle      => sub { @_ },
			 grep_unselected             => sub { grep { $common->{node_state}($_) eq 'unselected' } @_ },
			 check_interactive_to_toggle => sub { 1 },
			 toggle_nodes                => sub {
			     my ($set_state, @nodes) = @_;
			     my $new_state = !$common->{grep_unselected}($nodes[0]) ? 'selected' : 'unselected';
			     $set_state->($_, $new_state) foreach @nodes;
			 },
		       });
    $o->ask_browse_tree_info_refW($common);
}
sub ask_browse_tree_info_refW { #- default definition, do not use with too many items (memory consuming)
    my ($o, $common) = @_;
    my ($l, $v, $h) = ([], [], {});
    $common->{build_tree}(sub {
			      my ($node) = $common->{grep_allowed_to_toggle}(@_);
			      if (my $state = $node && $common->{node_state}($node)) {
				  push @$l, $node;
				  $state eq 'selected' and push @$v, $node;
				  $h->{$node} = $state eq 'selected';
			      }
			  }, 'flat');
    add2hash_($common, { list   => $l, #- TODO interactivity of toggle is missing
			 values => $v,
			 help   => sub { $common->{get_info}($_[0]) },
		       });
    my ($new_v) = $o->ask_many_from_list($common->{title}, $common->{message}, $common) or return;
    $common->{toggle_nodes}(sub {}, grep { ! delete $h->{$_} } @$new_v);
    $common->{toggle_nodes}(sub {}, grep { $h->{$_} } keys %$h);
    1;
}

sub wait_message {
    my ($o, $title, $message, $temp) = @_;

    my $w = $o->wait_messageW($title, [ _("Please wait"), deref($message) ]);
    push @tempory::objects, $w if $temp;
    my $b = before_leaving { $o->wait_message_endW($w) };

    #- enable access through set
    MDK::Common::Func::add_f4before_leaving(sub { $o->wait_message_nextW([ deref($_[1]) ], $w) }, $b, 'set');
    $b;
}

sub kill {}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
