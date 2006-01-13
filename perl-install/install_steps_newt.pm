package install_steps_newt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive::newt);

#-######################################################################################
#- misc imports
#-######################################################################################
use install_steps_interactive;
use interactive::newt;
use install_any;
use devices;
use lang;
use common;

sub banner {
    my $banner = translate(N_("Mandriva Linux Installation %s"));
    my $l = first(Newt::GetScreenSize()) - length($banner) - length($_[0]) + 1;
    Newt::DrawRootText(0, 0, sprintf($banner, ' ' x $l . $_[0]));
    Newt::Refresh();
}

sub new {
    my ($type, $o) = @_;

    interactive::newt->new;

    #- unset DISPLAY so that code testing wether DISPLAY is set can know we don't have or use X
    delete $ENV{DISPLAY};

    banner('');
    Newt::PushHelpLine(
                       #-PO: This string must fit in a 80-char wide text screen
                       N("  <Tab>/<Alt-Tab> between elements  | <Space> selects | <F12> next screen "));

    (bless {}, ref($type) || $type)->SUPER::new($o);
}

sub charsetChanged {
    my ($o) = @_;
    lang::load_console_font($o->{locale});
}

sub enteringStep {
    my ($o, $step) = @_;
    $o->SUPER::enteringStep($step);
    banner(translate($o->{steps}{$step}{text}));
}

sub exitInstall { 
    &install_steps_interactive::exitInstall;
    interactive::newt::end();
}

1;

