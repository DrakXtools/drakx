package interactive;

use diagnostics;
use strict;

use common qw(:common);

1;

sub new($$) {
    my ($type) = @_;

    bless {}, ref $type || $type;
}


sub ask_warn($$$) {
    my ($o, $title, $message) = @_;
    ask_from_list($o, $title, $message, [ _("Ok") ]);
}
sub ask_yesorno($$$) {
    my ($o, $title, $message, $def) = @_;
    ask_from_list_($o, $title, $message, [ __("Yes"), __("No") ], $def ? "No" : "Yes") eq "Yes";
}
sub ask_okcancel($$$) {
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
sub ask_many_from_list($$$$;$) {
    my ($o, $title, $message, $l, $def) = @_;

    $message = ref $message ? $message : [ $message ];

    $o->ask_many_from_listW($title, $message, $l, $def);
}

sub ask_from_entry($$$;$) {
    my ($o, $title, $message, $def) = @_;

    $message = ref $message ? $message : [ $message ];

    $o->ask_from_entryW($title, $message, $def);
}
