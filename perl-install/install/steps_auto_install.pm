package install::steps_auto_install; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA $graphical @graphical_steps);

@ISA = qw(install::steps);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use install::steps;
use install::steps_gtk;

sub new {
    my ($type, $o) = @_;

    # Handle legacy options
    $o->{interactive} ||= 'gtk' if $graphical || !is_empty_array_ref($o->{interactiveSteps});
    push @{$o->{interactiveSteps}}, qw(installPackages configureNetwork), @graphical_steps, if_(!$o->{autoExitInstall}, 'exitInstall');

    if ($o->{interactive}) {
	require "install/steps_$o->{interactive}.pm";

	@ISA = ('install::steps_' . $o->{interactive}, @ISA);

	foreach my $f (@{$o->{orderedSteps}}) {
	    $o->{steps}{$f}{auto} = 1 if !member($f, @{$o->{interactiveSteps}});
	}

	goto &{$install::{'steps_' . $o->{interactive} . '::'}{new}};
    } else {
	@ISA = ('install::steps_auto_install_non_interactive', @ISA);
	(bless {}, ref($type) || $type)->install::steps::new($o);
    }
}

sub exitInstall {
    my ($o, $alldone) = @_;

    if ($o->{interactive}) {
	$o->SUPER::exitInstall($alldone);
    } else {
	install::steps::exitInstall($o);
	return if $o->{autoExitInstall};
	print "\a";
	print "Auto installation complete\n";
	print "Press <Enter>" , $::local_install ? '' : " to reboot", "\n";
	<STDIN>;
    }
}


#-######################################################################################
#- install::steps_auto_install_non_interactive package
#-######################################################################################
package install::steps_auto_install_non_interactive;

use install::steps;
use lang;
use modules;
use common;
use log;

my $iocharset;

sub enteringStep {
    my ($o, $step) = @_;

    my ($s, $t) = (N_("Entering step `%s'\n"), common::remove_translate_context($o->{steps}{$step}{text}));
    my $txt;
    if ($iocharset && !$::local_install) {
	$txt = sprintf(translate($s), translate($t));
	$txt = Locale::gettext::iconv($txt, "utf-8", $iocharset);
    } else {
	$txt = sprintf($s, $t);
    }
    print $txt;

    $o->install::steps::enteringStep($step);
}

sub rebootNeeded {
    my ($o) = @_;
    errorInStep($o, <<EOF);
While partitioning, the partition table re-read failed, needing a reboot
This is plain wrong for an auto_install
EOF
}

sub ask_warn {
    my ($_o, $_title, $message) = @_;
    log::l(join(" ", deref_array($message)) . ' ' . backtrace());
}

sub wait_message {
    my ($_o, $_title, $_message) = @_;
}
sub wait_message_with_progress_bar {
    my ($_o, $_title) = @_;
    undef, sub {};
}

sub charsetChanged {
    my ($o) = @_;
    lang::load_console_font($o->{locale});

    my ($name, $acm) = lang::l2console_font($o->{locale}, 1);
    my %fs_options = lang::fs_options($o->{locale});
    $iocharset = $name && $acm && $fs_options{iocharset} ne 'utf8' ? $fs_options{iocharset} : '';
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
    c::_exit(1);
}


#-######################################################################################
#- Steps Functions
#-######################################################################################
sub installPackages {
    my ($o, $packages) = @_;
    catch_cdie { $o->install::steps::installPackages($packages) } sub { print formatError($@), "\n"; 1 };
}

1;
