package install_steps_auto_install; # $Id$

use diagnostics;
use strict;
use lang;
use vars qw(@ISA $graphical @graphical_steps);

@ISA = qw(install_steps);

use modules;


#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use install_steps;
use log;

sub new {
    my ($type, $o) = @_;

    # Handle legacy options
    $o->{interactive} ||= 'gtk' if $graphical || !is_empty_array_ref($o->{interactiveSteps});
    $o->{interactiveSteps} ||= [ @graphical_steps ];
    push @{$o->{interactiveSteps}}, qw(formatPartitions installPackages);

    if ($o->{interactive}) {
        my $interactiveClass = "install_steps_$o->{interactive}";
	require"$interactiveClass.pm"; #- no space to skip perl2fcalls

	@ISA = ($interactiveClass, @ISA);

	#- remove our non-interactive stuff
	eval "undef *$_" foreach qw(configureNetwork enteringStep ask_warn wait_message errorInStep installPackages);

	my $f = $o->{steps}{first};
	do {
	    member($f, @{$o->{interactiveSteps}}) ? $o->{steps}{$f}{noauto} = 1 : $o->{steps}{$f}{auto} = 1;
	} while ($f = $o->{steps}{$f}{next});

	goto &{$::{$interactiveClass . "::"}{new}};
    } else {
	(bless {}, ref $type || $type)->SUPER::new($o);
    }
}

sub configureNetwork {
    my ($o) = @_;
    modules::load_thiskind('net');
    goto &install_steps::configureNetwork;
}

sub enteringStep {
    my ($o, $step) = @_;
    print _("Entering step `%s'\n", translate($o->{steps}{$step}{text}));
    $o->SUPER::enteringStep($step);
}

sub ask_warn {
    log::l(ref $_[1] ? join " ", @{$_[1]} : $_[1]);
}

sub wait_message {}

sub errorInStep {
    print "error :(\n"; 
    print "switch to console f2 for a shell\n";
    print "Press <Enter> to reboot\n";
    <STDIN>;
    c::_exit(0);
}


#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o) = @_;
    $o->SUPER::selectLanguage;
    lang::load_console_font($o->{lang});
}

sub installPackages {
    my ($o, $packages) = @_;
    catch_cdie { $o->install_steps::installPackages($packages) } sub { print "$@\n"; 1 }
}

sub exitInstall {
    my ($o, $alldone) = @_;
    return if $o->{autoExitInstall};

    if ($o->{interactive}) {
	(bless $o, "install_steps_$o->{interactive}")->exitInstall($alldone);
    } else {
	install_steps::exitInstall($o);
	print "\a";
	print "Auto installation complete (the postInstall is not done yet though)\n";
	print "Press <Enter> to reboot\n";
	<STDIN>;
    }
}

1;
