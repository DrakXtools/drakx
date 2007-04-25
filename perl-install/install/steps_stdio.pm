package install::steps_stdio; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install::steps_interactive interactive::stdio);

use common;
use interactive::stdio;
use install::steps_interactive;
use lang;

sub new($$) {
    my ($type, $o) = @_;

    (bless {}, ref($type) || $type)->SUPER::new($o);
}

sub charsetChanged {
    my ($o) = @_;
    lang::load_console_font($o->{locale});
}

sub enteringStep {
    my ($o, $step) = @_;
    print N("Entering step `%s'\n", translate($o->{steps}{$step}{text}));
    $o->SUPER::enteringStep($step);
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
    print "--------\n";
}

1;
