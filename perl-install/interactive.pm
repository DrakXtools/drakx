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
    my ($_type, $su, $icon) = @_;
    $su = $su eq "su";
    if ($ENV{INTERACTIVE_HTTP}) {
	require interactive::http;
	return interactive::http->new;
    }
    require c;
    if ($su) {
	$ENV{PATH} = "/sbin:/usr/sbin:$ENV{PATH}";
	$su = '' if $::testing || $ENV{TESTING};
    }
    if ($ENV{DISPLAY} && system('/usr/X11R6/bin/xtest') == 0) {
	if ($su && $>) {
	    if (fuzzy_pidofs(qr/\bkwin\b/) > 0) {
		exec("kdesu", "-c", "$0 @ARGV") or die N("kdesu missing");
	    } else {
		exec { 'consolehelper' } $0, @ARGV or die N("consolehelper missing");
	    }
	}
	eval { require interactive::gtk };
	if (!$@) {
	    my $o = interactive::gtk->new;
	    if ($icon && $icon ne 'default' && !$::isWizard) { $o->{icon} = $icon } else { undef $o->{icon} }
	    return $o;
	}
    } else {
	if ($su && $>) {
	    exec { 'consolehelper' } $0, @ARGV or die N("consolehelper missing");
	}
    }

    if ($su && $>) {
	die "you must be root to run this program";
    }
    require 'log.pm'; #- "require log" causes some pb, perl thinking that "log" is the log() function
    undef *log::l;
    *log::l = sub {}; # otherwise, it will bother us :(
    require interactive::newt;
    interactive::newt->new;
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
    local $::isWizard = 0;
    ask_from_listf_no_check($o, $title, $message, undef, [ N("Ok") ]);
}

sub ask_yesorno {
    my ($o, $title, $message, $def, $help) = @_;
    ask_from_list_($o, $title, $message, [ N_("Yes"), N_("No") ], $def ? "Yes" : "No", $help) eq "Yes";
}

sub ask_okcancel {
    my ($o, $title, $message, $def, $help) = @_;

    if ($::isWizard) {
	$::no_separator = 1;
    	$o->ask_from_no_check({ title => $title, messages => $message, focus_cancel => !$def });
    } else {
	ask_from_list_($o, $title, $message, [ N_("Ok"), N_("Cancel") ], $def ? "Ok" : "Cancel", $help) eq "Ok";
    }
}

sub ask_file {
    my ($o, $title, $dir) = @_;
    $o->ask_fileW($title, $dir);
}
sub ask_fileW {
    my ($o, $title, $_dir) = @_;
    $o->ask_from_entry($title, N("Choose a file"));
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
    my ($_o, $_title, $_message, $_f, $l, $_def, $_help) = @_;
    @$l == 0 and die "ask_from_list: empty list\n" . backtrace();
    @$l == 1 and return $l->[0];
    goto &ask_from_listf_no_check;
}

sub ask_from_listf_no_check {
    my ($o, $title, $message, $f, $l, $def, $help) = @_;

    if (@$l <= 2 && !$::isWizard) {
	my ($ok, $cancel) = map { $_ && may_apply($f, $_) } @$l;
	if (length "$ok$cancel" < 70) {
	    my $ret = eval {
		ask_from_no_check($o, 
				  { title => $title, messages => $message, ok => $ok, 
				    if_($cancel, cancel => $cancel, focus_cancel => $def eq $l->[1]) }, []
				 ) ? $l->[0] : $l->[1];
	    };
	    die if $@ && $@ !~ /^wizcancel/;
	    return $@ ? undef : $ret;
	}
    }
    ask_from($o, $title, $message, [ { val => \$def, type => 'list', list => $l, help => $help, format => $f } ]) && $def;
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
    wantarray() ? @l : $l[0];
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

sub ask_from__add_modify_remove {
    my ($o, $title, $message, $l, %callback) = @_;
    die "ask_from__add_modify_remove only handles one item" if @$l != 1;

    $callback{$_} or internal_error("missing callback $_") foreach qw(Add Modify Remove);

    if ($o->can('ask_from__add_modify_removeW')) {
	$o->ask_from__add_modify_removeW($title, $message, $l, %callback);
    } else {
	my $e = $l->[0];
	my $chosen_element;
	put_in_hash($e, { allow_empty_list => 1, val => \$chosen_element, type => 'list' });

	while (1) {
	    my $continue;
	    my @l = (@$l, 
		     map { my $s = $_; { val => translate($_), clicked_may_quit => sub { 
					     my $r = $callback{$s}->($chosen_element);
					     defined $r or return;
					     $continue = 1;
					 } } }
		     N_("Add"), if_(@{$e->{list}} > 0, N_("Modify"), N_("Remove")));
	    $o->ask_from_({ title => $title, messages => $message, callbacks => \%callback }, \@l) or return;
	    return if !$continue;
	}
    }
}


#- can get a hash of callback: focus_out changed and complete
#- moreove if you pass a hash with a field list -> combo
#- if you pass a hash with a field hidden -> emulate stty -echo
sub ask_from {
    my ($o, $title, $message, $l, %callback) = @_;
    ask_from_($o, { title => $title, messages => $message, callbacks => \%callback }, $l);
}


sub ask_from_normalize {
    my ($_o, $common, $l) = @_;

    ref($l) eq 'ARRAY' or internal_error('ask_from_normalize');
    foreach my $e (@$l) {
	if (my $li = $e->{list}) {
	    ref($e->{val}) =~ /SCALAR|REF/ or internal_error($e->{val} ? "field {val} must be a reference (it is $e->{val})" : "field {val} is mandatory"); #-#
	    if ($e->{sort} || @$li > 10 && !exists $e->{sort}) {
		my @l2 = map { may_apply($e->{format}, $_) } @$li;
		my @places = sort { $l2[$a] cmp $l2[$b] } 0 .. $#l2;
		$e->{list} = $li = [ map { $li->[$_] } @places ];
	    }
	    $e->{type} = 'iconlist' if $e->{icon2f};
	    $e->{type} = 'treelist' if $e->{separator};
	    add2hash_($e, { not_edit => 1 });
	    $e->{type} ||= 'combo';

	    if (!$e->{not_edit}) {
		die q(when using "not_edit" you must use strings, not a data structure) if ref ${$e->{val}} || any { ref $_ } @$li;
	    }
	    if ($e->{type} ne 'combo' || $e->{not_edit}) {
		${$e->{val}} = $li->[0] if !member(may_apply($e->{format}, ${$e->{val}}), map { may_apply($e->{format}, $_) } @$li);
	    }
	} elsif ($e->{type} eq 'range') {
	    $e->{min} <= $e->{max} or die "bad range min $e->{min} > max $e->{max} (called from " . join(':', caller()) . ")";
	    ${$e->{val}} = max($e->{min}, min(${$e->{val}}, $e->{max}));
	} elsif ($e->{type} eq 'button' || $e->{clicked} || $e->{clicked_may_quit}) {
	    $e->{type} = 'button';
	    $e->{clicked_may_quit} ||= $e->{clicked} ? sub { $e->{clicked}(); 0 } : sub {};	    
	    $e->{val} = \ (my $_v = $e->{val}) if !ref($e->{val});
	} elsif ($e->{type} eq 'label' || !ref($e->{val})) {
	    $e->{type} = 'label';
	    $e->{val} = \ (my $_v = $e->{val}) if !ref($e->{val});
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
		    require 'log.pm'; #- "require log" causes some pb, perl thinking that "log" is the log() function
		    log::l("ask_from_normalize: empty list for $_->{label}\n" . backtrace());
		};
	    }
	    @{$_->{list}} > 1;
	} else {
	    1;
	}
    } @$l;

    if (!$common->{title} && $::isStandalone) {
	($common->{title} = $0) =~ s|.*/||;
    }
    $common->{advanced_label} ||= N("Advanced");
    $common->{advanced_label_close} ||= N("Basic");
    $common->{$_} = [ deref($common->{$_}) ] foreach qw(messages advanced_messages);
    add2hash_($common->{callbacks} ||= {}, { changed => sub {}, focus_out => sub {}, complete => sub { 0 }, canceled => sub { 0 }, advanced => sub {} });
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
    $o->ask_fromW($common, partition { !$_->{advanced} } @$l);
}
sub ask_from_real {
    my ($o, $common, $l) = @_;
    my $v = $o->ask_fromW($common, partition { !$_->{advanced} } @$l);
    %$common = ();
    $v;
}


sub ask_browse_tree_info {
    my ($o, $title, $message, $common) = @_;
    add2hash_($common, { ok => N("Ok"), cancel => N("Cancel") });
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

    my $w = $o->wait_messageW($title, [ N("Please wait"), deref($message) ]);
    push @tempory::objects, $w if $temp;
    my $b = before_leaving { $o->wait_message_endW($w) };

    #- enable access through set
    MDK::Common::Func::add_f4before_leaving(sub { $o->wait_message_nextW([ deref($_[1]) ], $w) }, $b, 'set');
    $b;
}

sub kill {}

1;
