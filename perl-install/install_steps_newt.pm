package install_steps_newt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive_newt);

#-######################################################################################
#- misc imports
#-######################################################################################
use install_steps_interactive;
use interactive_newt;
use install_any;
use devices;
use lang;
use common;

my $banner = __();

sub banner {
    my $banner = translate(__("Mandrake Linux Installation %s"));
    my $l = first(Newt::GetScreenSize) - length($banner) - length($_[0]) + 1;
    Newt::DrawRootText(0, 0, sprintf($banner, ' ' x $l . $_[0]));
    Newt::Refresh;
}

sub new($$) {
    my ($type, $o) = @_;

    interactive_newt->new;

    banner('');
    Newt::PushHelpLine(_("  <Tab>/<Alt-Tab> between elements  | <Space> selects | <F12> next screen "));

    (bless {}, ref $type || $type)->SUPER::new($o);
}

sub enteringStep {
    my ($o, $step) = @_;
    $o->SUPER::enteringStep($step);
    banner(translate($o->{steps}{$step}{text}));
}

sub exitInstall { 
    &install_steps_interactive::exitInstall;
    interactive_newt::end;
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o) = @_;
    $o->SUPER::selectLanguage;
    lang::load_console_font($o->{lang});
}


1;

