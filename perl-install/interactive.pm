package interactive;

use diagnostics;
use strict;

use common qw(:common :functional);

# heritate from this class and you'll get all made interactivity for same steps.
# for this you need to provide 
# - ask_from_listW(o, title, messages, arrayref, default) returns one string of arrayref
# - ask_many_from_listW(o, title, messages, arrayref, arrayref2) returns one string of arrayref
#
# where
# - o is the object
# - title is a string
# - messages is an refarray of strings
# - default is an optional string (default is in arrayref)
# - arrayref is an arrayref of strings
# - arrayref2 contains booleans telling the default state, 
#
# ask_from_list and ask_from_list_ are wrappers around ask_from_biglist and ask_from_smalllist
#
# ask_from_list_ just translate arrayref before calling ask_from_list and untranslate the result
#
# ask_from_listW should handle differently small lists and big ones.


1;


sub new($) {
    my ($type) = @_;

    bless {}, ref $type || $type;
}


sub ask_warn($$$) {
    my ($o, $title, $message) = @_;
    ask_from_list($o, $title, $message, [ _("Ok") ]);
}
sub ask_yesorno($$$;$) {
    my ($o, $title, $message, $def) = @_;
    ask_from_list_($o, $title, $message, [ __("Yes"), __("No") ], $def ? "No" : "Yes") eq "Yes";
}
sub ask_okcancel($$$;$) {
    my ($o, $title, $message, $def) = @_;
    ask_from_list_($o, $title, $message, [ __("Ok"), __("Cancel") ], $def ? "Cancel" : "Ok") eq "Ok";
}
sub ask_from_list_($$$$;$) {
    my ($o, $title, $message, $l, $def) = @_;
    untranslate(
       ask_from_list($o, $title, $message, [ map { translate($_) } @$l ], translate($def)),
       @$l);
}
sub ask_from_list($$$$;$) {
    my ($o, $title, $message, $l, $def) = @_;

    $message = ref $message ? $message : [ $message ];

    @$l > 10 and $l = [ sort @$l ];

    $o->ask_from_listW($title, $message, $l, $def || $l->[0]);
}
sub ask_many_from_list_ref($$$$;$) {
    my ($o, $title, $message, $l, $val) = @_;

    $message = ref $message ? $message : [ $message ];

    $o->ask_many_from_list_refW($title, $message, $l, $val);
}
sub ask_many_from_list($$$$;$) {
    my ($o, $title, $message, $l, $def) = @_;

    my $val = [ map { my $i = $_; \$i } @$def ];

    $o->ask_many_from_list_ref($title, $message, $l, $val) ?
      [ map { $$_ } @$val ] : undef;
}

sub ask_from_entry($$$;$) {
    my ($o, $title, $message, $def) = @_;

    $message = ref $message ? $message : [ $message ];

    $o->ask_from_entryW($title, $message, $def);
}

sub wait_message($$$) {
    my ($o, $title, $message) = @_;

    $message = ref $message ? $message : [ $message ];

    my $w = $o->wait_messageW($title, [ _("Please wait"), @$message ]);
    my $b = before_leaving { $o->wait_message_endW($w) };

    # enable access through set
    common::add_f4before_leaving(sub { $o->wait_message_nextW($_[1], $w) }, $b, 'set');
    $b;
}

sub kill {
    my ($o) = @_;
    while ($o->{before_killing} && @interactive::objects > $o->{before_killing}) {
	my $w = pop @interactive::objects;
	$w->destroy;
    }
    $o->{before_killing} = @interactive::objects;
}
