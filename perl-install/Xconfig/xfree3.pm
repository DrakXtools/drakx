package Xconfig::xfree3; # $Id$

use diagnostics;
use strict;

use MDK::Common;
use Xconfig::parse;
use Xconfig::xfreeX;

our @ISA = 'Xconfig::xfreeX';

sub config_file { '/etc/X11/XF86Config' }


sub get_keyboard_section {
    my ($raw_X) = @_;
    return $raw_X->get_Section('Keyboard') or die "no keyboard section";
}

sub new_keyboard_section {
    my ($raw_X) = @_;
    return $raw_X->add_Section('Keyboard', { Protocol => { val => 'Standard' } });
}

sub get_mouse_sections {
    my ($raw_X) = @_;
    my $main = $raw_X->get_Section('Pointer') or die "no mouse section";
    my $XInput = $raw_X->get_Section('XInput');    
    $main, if_($XInput, map { $_->{l} } @{$XInput->{Mouse} || []}); 
}

sub new_mouse_sections {
    my ($raw_X, $nb_new) = @_;

    $raw_X->remove_Section('Pointer');
    my $XInput = $raw_X->get_Section('XInput');
    delete $XInput->{Mouse} if $XInput;
    $raw_X->remove_Section('XInput') if $nb_new <= 1 && $XInput && !%$XInput;

    $nb_new or return;

    my $main = $raw_X->add_Section('Pointer', {});
    
    if ($nb_new == 1) {
	$main;
    } else {
	my @l = map { { DeviceName => { val => "Mouse$_" }, AlwaysCore => {} } } (2 .. $nb_new);
	$XInput ||= $raw_X->add_Section('XInput', {});
	$XInput->{Mouse} = [ map { { l => $_ } } @l ];
	$main, @l;
    }
}

sub set_Option {}

1;
