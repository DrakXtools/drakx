package Xconfig::xfree4; # $Id$

use diagnostics;
use strict;

use MDK::Common;
use Xconfig::parse;
use Xconfig::xfree;

our @ISA = 'Xconfig::xfreeX';

sub config_file { '/etc/X11/XF86Config-4' }


sub get_keyboard_section {
    my ($raw_X) = @_;
    my ($raw_kbd) = get_InputDevices($raw_X, 'Keyboard') or die "no keyboard section";
    $raw_kbd;
}

sub new_keyboard_section {
    my ($raw_X) = @_;
    my $raw_kbd = { Identifier => { val => 'Keyboard1' }, Driver => { val => 'Keyboard' } };
    $raw_X->add_Section('InputDevice', $raw_kbd);

    my $ServerLayout = get_ServerLayout($raw_X);
    push @{$ServerLayout->{InputDevice}}, { val => '"Keyboard1" "CoreKeyboard"' };

    $raw_kbd;
}

sub get_mouse_sections {
    my ($raw_X) = @_;
    get_InputDevices($raw_X, 'mouse');
}
sub new_mouse_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_InputDevices('mouse');

    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    @$layout = grep { $_->{val} !~ /^"Mouse/ } @$layout;

    $nb_new or return;

    my @l = map {
	my $h = { Identifier => { val => "Mouse$_" }, Driver => { val => 'mouse' } };
	$raw_X->add_Section('InputDevice', $h);
    } (1 .. $nb_new);

    push @$layout, { val => qq("Mouse1" "CorePointer") };
    push @$layout, { val => qq("Mouse$_" "SendCoreEvents") } foreach (2 .. $nb_new);

    @l;
}

sub set_Option {
    my ($raw_X, $category, $node, @names) = @_;
    
    if (member($category, 'keyboard', 'mouse')) {
	#- everything we export is an Option
	$_->{Option} = 1 foreach map { deref_array($node->{$_}) } @names;
    }
}


#-##############################################################################
#- helpers
#-##############################################################################
sub get_InputDevices {
    my ($raw_X, $Driver) = @_;
    $raw_X->get_Sections('InputDevice', sub { $_[0]{Driver}{val} eq $Driver });
}
sub remove_InputDevices {    
    my ($raw_X, $Driver) = @_;
    $raw_X->remove_Section('InputDevice', sub { $_[0]{Driver}{val} ne $Driver });
}

sub get_ServerLayout {
    my ($raw_X) = @_;
    $raw_X->get_Section('ServerLayout') ||
      $raw_X->add_Section('ServerLayout', { Identifier => { val => 'layout1' } });
}

1;
