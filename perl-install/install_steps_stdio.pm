package install_steps_stdio;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive_stdio);

use common qw(:common);
use devices;
use run_program;
use interactive_stdio;
use install_steps_interactive;
use install_any;
use log;

1;

sub enteringStep($$$) {
    my ($o, $step) = @_;
    print _("Entering step `%s'\n", $o->{steps}{$step}{text});
}
sub leavingStep {
    my ($o) = @_;
    print "--------\n";
}

sub installPackages {
    my $o = shift;

    my $old = \&log::ld;
    local *log::ld = sub {
	my $m = shift;
	if ($m =~ /^starting installing/) {
	    my $name = first($_[0] =~ m|([^/]*)-.+?-|);
	    print("installing package $name");
	} else { goto $old }
    };
    $o->SUPER::installPackages(@_);
}


sub setRootPassword($) {
    my ($o) = @_;

    my (%w);
    do {
	$w{password} and print "You must enter the same password, please try again\n";
	print "Password: "; $w{password} = $o->readln();
	print "Password (again for confirmation): ";
    } until ($w{password} eq $o->readln());

    $o->{default}{rootPassword} = $w{password};
    $o->SUPER::setRootPassword;
}

sub addUser($) {
    my ($o) = @_;
    my %w;
    print "\nCreating a normal user account:\n";
    print "Name: "; $w{name} = $o->readln() or return;
    do {
	$w{password} and print "You must enter the same password, please try again\n";
	print "Password: "; $w{password} = $o->readln();
	print "Password (again for confirmation): ";
    } until ($w{password} eq $o->readln());
    print "Real name: "; $w{realname} = $o->readln();

    $w{shell} = $o->ask_from_list('', 'Shell', [ install_any::shells($o) ], "/bin/bash");

    $o->{default}{user} = { map { $_ => $w{$_}->get_text } qw(name password realname shell) };
    $o->SUPER::addUser;
}
