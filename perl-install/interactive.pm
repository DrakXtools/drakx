package interactive; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use do_pkgs;

#- minimal example using interactive:
#
#- > use lib qw(/usr/lib/libDrakX);
#- > use interactive;
#- > my $in = interactive->vnew;
#- > $in->ask_okcancel('title', 'question');
#- > $in->exit;

#- ask_from_ takes global options ($common):
#-  title                => window title
#-  messages             => message displayed in the upper part of the window
#-  advanced_messages    => message displayed when "Advanced" is pressed
#-  ok                   => force the name of the "Ok"/"Next" button
#-  cancel               => force the name of the "Cancel"/"Previous" button
#-  advanced_label       => force the name of the "Advanced" button
#-  advanced_label_close => force the name of the "Basic" button
#-  advanced_state       => if set to 1, force the "Advanced" part of the dialog to be opened initially
#-  focus_cancel         => force focus on the "Cancel" button
#-  focus_first          => force focus on the first entry
#-  callbacks            => functions called when something happen: complete canceled advanced changed focus_out ok_disabled

#- ask_from_ takes a list of entries with fields:
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
#-     bool (with "text" or "image" (which overrides text) giving an image filename)
#-     range (with min, max)
#-     combo (with list, not_edit, format)
#-     list (with list, icon2f (aka icon), separator (aka tree), format (aka pre_format function),
#-           help can be a hash or a function,
#-           tree_expanded boolean telling wether the tree should be wide open by default
#-           quit_if_double_click boolean
#-           allow_empty_list disables the special cases for 0 and 1 element lists
#-           image2f is a subroutine which takes a value of the list as parameter, and returns image_file_name
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
our @ISA = qw(do_pkgs);

sub new($) {
    my ($type) = @_;

    bless {}, ref($type) || $type;
}

sub vnew {
    my ($_type, $o_su, $o_icon) = @_;
    my $su = $o_su eq "su";
    if ($ENV{INTERACTIVE_HTTP}) {
	require interactive::http;
	return interactive::http->new;
    }
    require c;
    if ($su) {
	$ENV{PATH} = "/sbin:/usr/sbin:$ENV{PATH}";
	$su = '' if $::testing || $ENV{TESTING};
    }
    require_root_capability() if $su;
    if (check_for_xserver()) {
	eval { require interactive::gtk };
	if (!$@) {
	    my $o = interactive::gtk->new;
	    if ($o_icon && $o_icon ne 'default' && !$::isWizard) { $o->{icon} = $o_icon } else { undef $o->{icon} }
	    return $o;
	} elsif ($::testing) {
	    die;
	}
    }

    require 'log.pm'; #- "require log" causes some pb, perl thinking that "log" is the log() function
    undef *log::l;
    *log::l = sub {}; # otherwise, it will bother us :(
    require interactive::newt;
    interactive::newt->new;
}

sub ok { N_("Ok") }
sub cancel { N_("Cancel") }

sub enter_console {}
sub leave_console {}
sub suspend {}
sub resume {}
sub end {}
sub exit {
    if ($::isStandalone) {
        require standalone;
        standalone::exit($_[0]);
    } else {
        exit($_[0]);
    }
}


#-######################################################################################
#- Interactive functions
#-######################################################################################
sub ask_warn {
    my ($o, $title, $message) = @_;
    ask_warn_($o, { title => $title, messages => $message });
}
sub ask_yesorno {
    my ($o, $title, $message, $b_def) = @_;
    ask_yesorno_($o, { title => $title, messages => $message }, $b_def);
}
sub ask_okcancel {
    my ($o, $title, $message, $b_def) = @_;
    ask_okcancel_($o, { title => $title, messages => $message }, $b_def);
}

sub ask_warn_ {
    my ($o, $common) = @_;
    ask_from_listf_raw_no_check($o, $common, \&translate, [ $o->ok ]);
}

sub ask_yesorno_ {
    my ($o, $common, $b_def) = @_;
    $common->{cancel} = '';
    ask_from_listf_raw($o, $common, \&translate, [ N_("Yes"), N_("No") ], $b_def ? "Yes" : "No") eq "Yes";
}

sub ask_okcancel_ {
    my ($o, $common, $b_def) = @_;

    if ($::isWizard) {
	$::no_separator = 1;
	$common->{focus_cancel} = !$b_def;
    	ask_from_no_check($o, $common, []);
    } else {
	ask_from_listf_raw($o, $common, \&translate, [ $o->ok, $o->cancel ], $b_def ? $o->ok : $o->cancel) eq $o->ok;
    }
}

sub ask_filename {
    my ($o, $common) = @_;
    $common->{want_a_dir} = 0;
    $o->ask_fileW($common);
}

sub ask_directory {
    my ($o, $common) = @_;
    $common->{want_a_dir} = 1;
    $o->ask_fileW($common);
}

#- predecated
sub ask_file {
    my ($o, $title, $o_dir) = @_;
    $o->ask_fileW({ title => $title, want_a_dir => 0, directory => $o_dir });
}

sub ask_fileW {
    my ($o, $common) = @_;
    $o->ask_from_entry($common->{title}, $common->{message} || N("Choose a file"));
}

sub ask_from_list {
    my ($o, $title, $message, $l, $o_def) = @_;
    ask_from_listf($o, $title, $message, undef, $l, $o_def);
}

sub ask_from_list_ {
    my ($o, $title, $message, $l, $o_def) = @_;
    ask_from_listf($o, $title, $message, \&translate, $l, $o_def);
}

sub ask_from_listf_ {
    my ($o, $title, $message, $f, $l, $o_def) = @_;
    ask_from_listf($o, $title, $message, sub { translate($f->(@_)) }, $l, $o_def);
}
sub ask_from_listf {
    my ($o, $title, $message, $f, $l, $o_def) = @_;
    ask_from_listf_raw($o, { title => $title, messages => $message }, $f, $l, $o_def);
}
sub ask_from_listf_raw {
    my ($_o, $_common, $_f, $l, $_o_def) = @_;
    @$l == 0 and die "ask_from_list: empty list\n" . backtrace();
    @$l == 1 and return $l->[0];
    goto &ask_from_listf_raw_no_check;
}

sub ask_from_listf_raw_no_check {
    my ($o, $common, $f, $l, $o_def) = @_;

    if (@$l <= ($::isWizard ? 1 : 2)) {
	my ($ok, $cancel) = map { $_ && may_apply($f, $_) } @$l;
	if (length "$ok$cancel" < 70) {
	    my $ret = eval {
		put_in_hash($common, { ok => $ok, 
				       if_($cancel, cancel => $cancel, focus_cancel => $o_def eq $l->[1]) });
		ask_from_no_check($o, $common, []) ? $l->[0] : $l->[1];
	    };
	    die if $@ && $@ !~ /^wizcancel/;
	    return $@ ? undef : $ret;
	}
    }
    ask_from_no_check($o, $common, [ { val => \$o_def, type => 'list', list => $l, format => $f } ]) && $o_def;
}

sub ask_from_treelist {
    my ($o, $title, $message, $separator, $l, $o_def) = @_;
    ask_from_treelistf($o, $title, $message, $separator, undef, $l, $o_def);
}
sub ask_from_treelist_ {
    my ($o, $title, $message, $separator, $l, $o_def) = @_;
    my $transl = sub { join '|', map { translate($_) } split(quotemeta($separator), $_[0]) }; 
    ask_from_treelistf($o, $title, $message, $separator, $transl, $l, $o_def);
}
sub ask_from_treelistf {
    my ($o, $title, $message, $separator, $f, $l, $o_def) = @_;
    ask_from($o, $title, $message, [ { val => \$o_def, separator => $separator, list => $l, format => $f, sort => 1 } ]) or return;
    $o_def;
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

    $o->ask_from_({ title => $title, messages => $message, callbacks => \%callback, 
		    focus_first => 1 }, \@l) or return;
    map { ${$_->{val}} } @l;
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
	    return 1 if !$continue;
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
    my ($o, $common, $l) = @_;

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
	    $e->{type} = 'treelist' if $e->{separator} && $e->{type} ne 'combo';
	    add2hash_($e, { not_edit => 1 });
	    $e->{type} ||= 'combo';

	    if (!$e->{not_edit}) {
		die q(when using "not_edit" you must use strings, not a data structure) if ref(${$e->{val}}) || any { ref $_ } @$li;
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

    #- do not display empty lists and one element lists
    @$l = grep { 
	if ($_->{list} && $_->{not_edit} && !$_->{allow_empty_list}) {
	    if (!@{$_->{list}}) {
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
    $common->{interactive_help} ||= $o->{interactive_help};
    $common->{interactive_help} ||= $common->{interactive_help_id} && $o->interactive_help_sub_get_id($common->{interactive_help_id});
    $common->{advanced_label} ||= N("Advanced");
    $common->{advanced_label_close} ||= N("Basic");
    $common->{$_} = $common->{$_} ? [ deref($common->{$_}) ] : [] foreach qw(messages advanced_messages);
    add2hash_($common->{callbacks} ||= {}, { changed => sub {}, focus_out => sub {}, complete => sub { 0 }, canceled => sub { 0 }, advanced => sub {} });
}

sub ask_from_ {
    my ($o, $common, $l) = @_;
    ask_from_normalize($o, $common, $l);
    @$l or return 1;
    $common->{cancel} = '' if !defined wantarray();
    ask_from_real($o, $common, $l);
}
sub ask_from_no_check {
    my ($o, $common, $l) = @_;
    ask_from_normalize($o, $common, $l);
    $common->{cancel} = '' if !defined wantarray();
    my ($l1, $l2) = partition { !$_->{advanced} } @$l;
    $o->ask_fromW($common, $l1, $l2);
}
sub ask_from_real {
    my ($o, $common, $l) = @_;
    my ($l1, $l2) = partition { !$_->{advanced} } @$l;
    my $v = $o->ask_fromW($common, $l1, $l2);

    foreach my $e (@$l1, @$l2) {
	if ($e->{type} eq 'range') {
	    ${$e->{val}} = max($e->{min}, min(${$e->{val}}, $e->{max}));
	}
    }

    %$common = ();
    $v;
}


sub ask_browse_tree_info {
    my ($o, $title, $message, $common) = @_;
    $common->{interactive_help} ||= $common->{interactive_help_id} && $o->interactive_help_sub_get_id($common->{interactive_help_id});
    add2hash_($common, { ok => $::isWizard ? ($::Wizard_finished ? N("Finish") : N("Next")) : N("Ok"), 
			 cancel => $::isWizard ? N("Previous") : N("Cancel") });
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
    my ($o, $title, $message, $b_temp) = @_;

    my $w = $o->wait_messageW($title, [ N("Please wait"), deref($message) ]);
    push @tempory::objects, $w if $b_temp;
    my $b = before_leaving { $o->wait_message_endW($w) };

    #- enable access through set
    MDK::Common::Func::add_f4before_leaving(sub { $o->wait_message_nextW([ deref($_[1]) ], $w) }, $b, 'set');
    $b;
}


sub wait_message_with_progress_bar {
    my ($in) = @_;

    my ($w, $progress, $last_msg, $displayed);
    my $on_expose = sub { $displayed = 1; 0 }; #- declared here to workaround perl limitation
    $w, sub {
	my ($msg, $current, $total) = @_;
	if ($msg) {
	    $last_msg = $msg;
	    if (!$w) {
		$progress = Gtk2::ProgressBar->new if $in->isa('interactive::gtk');
		$w = $in->wait_message('', [ '', if_($progress, $progress) ]);
		if ($progress) {
		    #- don't show by default, only if we are given progress information
		    $progress->hide;
		    $progress->signal_connect(expose_event => $on_expose);
		}
	    }
	    $w->set($msg);
	} elsif ($total) {
	    if ($progress) {
		$progress->set_fraction($current / $total);
		$progress->show;
		$displayed = 0;
		mygtk2::flush() while !$displayed;
	    } else {
		$w->set([ $last_msg, "$current / $total" ]);
	    }
	}
    };
}

sub kill() {}



sub helper_separator_tree_to_tree {
    my ($separator, $list, $formatted_list) = @_;
    my $sep = quotemeta $separator;
    my $tree = {};
    
    each_index {
	my @l = split $sep;
	my $leaf = pop @l;
	my $node = $tree;
	foreach (@l) {
	    $node = $node->{$_} ||= do {
		my $r = {};
		push @{$node->{_order_}}, $_;
		$r;
	    };
	}
	push @{$node->{_leaves_}}, [ $leaf, $list->[$::i] ];
	();
    } @$formatted_list;

    $tree;
}


sub interactive_help_has_id {
    my ($_o, $id) = @_;
    exists $help::{$id};
}

sub interactive_help_get_id {
    my ($_o, @l) = @_;
    @l = map { 
	join("\n\n", map { s/\n/ /mg; $_ } split("\n\n", translate($help::{$_}->())));
    } grep { exists $help::{$_} } @l;
    join("\n\n\n", @l);
}

sub interactive_help_sub_get_id {
    my ($o, $id) = @_;
    $o->interactive_help_has_id($id) && sub { $o->interactive_help_get_id($id) };
}

sub interactive_help_sub_display_id {
    my ($o, $id) = @_;
    $o->interactive_help_has_id($id) && sub { $o->ask_warn(N("Help"), $o->interactive_help_get_id($id)) };
}

1;
