package install_steps_stdio; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive::stdio);

use common;
use interactive::stdio;
use install_steps_interactive;
use lang;

sub new($$) {
    my ($type, $o) = @_;

    (bless {}, ref $type || $type)->SUPER::new($o);
}

sub enteringStep {
    my ($o, $step) = @_;
    print _("Entering step `%s'\n", translate($o->{steps}{$step}{text}));
    $o->SUPER::enteringStep($step);
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
    print "--------\n";
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o, $first_time) = @_;
    $o->SUPER::selectLanguage($first_time);
    lang::load_console_font($o->{lang});
}

1;
