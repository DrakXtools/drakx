package install_steps_auto_install;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common);
use install_steps;
use log;

sub enteringStep($$$) {
    my ($o, $step) = @_;
    print _("Entering step `%s'\n", $o->{steps}{$step}{text});
    $o->SUPER::enteringStep($step);
}

sub ask_warn {
    log::l(ref $_[1] ? join " ", @{$_[1]} : $_[1]);
}

sub errorInStep {
    print "error :(\n"; 
    print "switch to console f2 for a shell\n";
    print "Press <Enter> to reboot\n";
    <STDIN>;
    c::_exit(0);
}

sub exitInstall {
    print "Auto installation complete\n";
    print "Press <Enter> to reboot\n";
    <STDIN>;
}

1;
