package Xconfig::xfree4; # $Id$

use diagnostics;
use strict;

use common;
use Xconfig::parse;
use Xconfig::xfree;

our @ISA = 'Xconfig::xfreeX';

sub name { 'xfree4' }
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

    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    push @$layout, { val => '"Keyboard1" "CoreKeyboard"' };

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

sub set_wacoms {
    my ($raw_X, @wacoms) = @_;
    $raw_X->remove_InputDevices('wacom');

    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    @$layout = grep { $_->{val} !~ /^"(Stylus|Eraser|Cursor)/ } @$layout;

    @wacoms or return;

    my %Modes = (Stylus => 'Absolute', Eraser => 'Absolute', Cursor => 'Relative');

    each_index {
	my $wacom = $_;
	foreach (keys %Modes) {
	    my $identifier = $_ . ($::i + 1);
	    my $h = { Identifier => { val => $identifier }, 
		      Driver => { val => 'wacom' },
		      Type => { val => lc $_, Option => 1 },
		      Device => { val => $wacom->{Device}, Option => 1 },
		      Mode => { val => $Modes{$_}, Option => 1 },
		      if_($wacom->{USB}, USB => { Option => 1 })
		    };
	    $raw_X->add_Section('InputDevice', $h);
	    push @$layout, { val => qq("$identifier" "AlwaysCore") };
	}
    } @wacoms;
}

sub depths { 8, 15, 16, 24 }
sub set_resolution {
    my ($raw_X, $resolution, $Screen) = @_;

    $resolution = +{ %$resolution };
    if (my $Screen_ = $Screen || $raw_X->get_default_screen) {
	#- use framebuffer if corresponding Device has Driver framebuffer
	my $Device = $raw_X->get_Section_by_Identifier('Device', val($Screen_->{Device})) or internal_error("no device named $Screen_->{Device}");
	$resolution->{fbdev} = 1 if val($Device->{Driver}) eq 'fbdev';
    }
    #- XFree4 doesn't like depth 32, silently replacing it with 24
    $resolution->{Depth} = 24 if $resolution->{Depth} eq '32';

    $raw_X->SUPER::set_resolution($resolution, $Screen);
}

sub get_device_section_fields {
    qw(VendorName BoardName Driver VideoRam Screen BusID); #-);
}

sub new_device_sections {
    my ($raw_X, $nb_new) = @_;
    my @l = $raw_X->SUPER::new_device_sections($nb_new);
    $_->{DPMS} = { Option => 1 } foreach @l;
    @l;
}

sub new_screen_sections {
    my ($raw_X, $nb_new) = @_;
    my @l = $raw_X->SUPER::new_screen_sections($nb_new);
    each_index { $_->{Identifier} = { val => "screen" . ($::i+1) } } @l;

    get_ServerLayout($raw_X)->{Screen} = [ 
	{ val => qq("screen1") }, #-)
	map { { val => sprintf('"screen%d" RightOf "screen%d"', $_, $_ - 1) } } (2 .. $nb_new)
    ];

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
    $raw_X->get_Sections('InputDevice', sub { val($_[0]{Driver}) eq $Driver });
}
sub remove_InputDevices {    
    my ($raw_X, $Driver) = @_;
    $raw_X->remove_Section('InputDevice', sub { val($_[0]{Driver}) ne $Driver });
}

sub get_ServerLayout {
    my ($raw_X) = @_;
    $raw_X->get_Section('ServerLayout') ||
      $raw_X->add_Section('ServerLayout', { Identifier => { val => 'layout1' } });
}

sub val {
    my ($ref) = @_;
    $ref && $ref->{val};
}

1;
