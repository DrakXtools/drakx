package install_steps_auto_install; # $Id$

use diagnostics;
use strict;
use lang;
use vars qw(@ISA);

@ISA = qw(install_steps);

use modules;


#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);
use install_steps;
use log;

my $graphical = 0;

sub new {
    my ($type, $o) = @_;

    if ($graphical) {
	require install_steps_gtk;
	undef *enteringStep; *enteringStep = \&install_steps_gtk::enteringStep;
	undef *installPackages; *installPackages = \&install_steps_gtk::installPackages;
	goto &install_steps_gtk::new;
    } else {
	(bless {}, ref $type || $type)->SUPER::new($o);
    }
}

sub configureNetwork {
    my ($o) = @_;
    modules::load_thiskind('net');
    goto &install_steps::configureNetwork;
}

sub enteringStep($$$) {
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

    if ($graphical) {
	my $O = bless $o, "install_steps_gtk";
	$O->exitInstall($alldone);
    } else {
	install_steps::exitInstall;
	print "\a";
	print "Auto installation complete (the postInstall is done yet though)\n";
	print "Press <Enter> to reboot\n";
	<STDIN>;
    }
}

1;
