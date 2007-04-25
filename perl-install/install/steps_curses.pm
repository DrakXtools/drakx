package install::steps_curses; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install::steps_interactive interactive::curses);

#-######################################################################################
#- misc imports
#-######################################################################################
use install::steps_interactive;
use interactive::curses;
use install::any;
use devices;
use lang;
use common;

my $banner;
sub banner {
    my ($cui, $step) = @_;
    my $text = N("Mandriva Linux Installation %s", $step);
    $banner ||= do {
	my $win = $cui->add(undef, 'Window', '-x' => 1, '-y' => 0, '-height' => 1);
	$win->add(undef, 'Label');
    };
    $banner->text($text);
}

sub help_line {
    my ($cui) = @_;
    my $text = N("<Tab>/<Alt-Tab> between elements");
    my $win = $cui->add(undef, 'Window', '-x' => 1, '-y' => -1, '-height' => 1);
    $win->add(undef, 'Label', '-text' => $text);
}

sub new {
    my ($type, $o) = @_;

    add2hash($o, interactive::curses->new);

    #- unset DISPLAY so that code testing wether DISPLAY is set can know we don't have or use X
    delete $ENV{DISPLAY};

    banner($o->{cui}, '');
    help_line($o->{cui});

    (bless {}, ref($type) || $type)->SUPER::new($o);
}

sub charsetChanged {
    my ($o) = @_;
    lang::load_console_font($o->{locale});
}

sub enteringStep {
    my ($o, $step) = @_;
    $o->SUPER::enteringStep($step);
    banner($o->{cui}, translate($o->{steps}{$step}{text}));
}

sub exitInstall { 
    &install::steps_interactive::exitInstall;
    interactive::curses::end();
}

1;

