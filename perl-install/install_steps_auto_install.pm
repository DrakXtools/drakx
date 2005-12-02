package install_steps_auto_install; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA $graphical @graphical_steps);

@ISA = qw(install_steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use install_steps;

sub new {
    my ($type, $o) = @_;

    # Handle legacy options
    $o->{interactive} ||= 'gtk' if $graphical || !is_empty_array_ref($o->{interactiveSteps});
    push @{$o->{interactiveSteps}}, qw(installPackages exitInstall configureNetwork), @graphical_steps;

    if ($o->{interactive}) {
        my $interactiveClass = "install_steps_$o->{interactive}";
	require "$interactiveClass.pm";

	@ISA = ($interactiveClass, @ISA);

	foreach my $f (@{$o->{orderedSteps}}) {
	    $o->{steps}{$f}{auto} = 1 if !member($f, @{$o->{interactiveSteps}});
	}

	goto &{$::{$interactiveClass . "::"}{new}};
    } else {
	@ISA = ('install_steps_auto_install_non_interactive', @ISA);
	(bless {}, ref($type) || $type)->install_steps::new($o);
    }
}

sub exitInstall {
    my ($o, $alldone) = @_;
    return if $o->{autoExitInstall};

    if ($o->{interactive}) {
	$o->SUPER::exitInstall($alldone);
    } else {
	install_steps::exitInstall($o);
	print "\a";
	print "Auto installation complete (the postInstall is not done yet though)\n";
	print "Press <Enter> to reboot\n";
	<STDIN>;
    }
}


#-######################################################################################
#- install_steps_auto_install_non_interactive package
#-######################################################################################
package install_steps_auto_install_non_interactive;

use install_steps;
use lang;
use modules;
use common;
use log;

sub enteringStep {
    my ($o, $step) = @_;
    my ($s, $t) = (N_("Entering step `%s'\n"), $o->{steps}{$step}{text});
    ($s, $t) = (translate($s), translate($t)) if $ENV{LANG} !~ /ja|ko|zh/;
    print sprintf($s, $t);
    $o->install_steps::enteringStep($step);
}

sub rebootNeeded {
    my ($o) = @_;
    errorInStep($o, <<EOF);
While partitioning, the partition table re-read failed, needing a reboot
This is plain wrong for an auto_install
EOF
}

sub ask_warn {
    log::l(ref($_[1]) ? join " ", @{$_[1]} : $_[1]);
}

sub wait_message {
    my ($_o, $_title, $_message) = @_;
}

sub charsetChanged {
    my ($o) = @_;
    lang::load_console_font($o->{locale});
}

sub errorInStep {
    my ($_o, $err) = @_;
    print "error :(\n"; 
    print "$err\n\n";
    print "switch to console f2 for a shell\n";
    print "Press <Enter> to reboot\n";

    my $answer = <STDIN>;
    if ($answer =~ /restart/i) {
	log::l("restarting install");
	c::_exit(0x35);
    }
    c::_exit(0);
}


#-######################################################################################
#- Steps Functions
#-######################################################################################
sub installPackages {
    my ($o, $packages) = @_;
    catch_cdie { $o->install_steps::installPackages($packages) } sub { print formatError($@), "\n"; 1 };
}

1;
