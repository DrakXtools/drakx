package Xconfig::default; # $Id$

use diagnostics;
use strict;

use Xconfig::xfree;
use keyboard;
use common;
use mouse;
use modules::any_conf;


sub configure {
    my ($do_pkgs, $o_keyboard, $o_mouse) = @_;

    my $keyboard = $o_keyboard || keyboard::read_or_default();
    my $mouse = $o_mouse || do {
	my $mouse = mouse::read(); 
	add2hash($mouse, mouse::detect(modules::any_conf->read)) if !$::noauto;
	$mouse;
    };

    my $raw_X = Xconfig::xfree->empty_config;

    $raw_X->add_load_module($_) foreach qw(dbe v4l extmod type1 freetype);

    config_keyboard($raw_X, $keyboard);
    config_mouse($raw_X, $do_pkgs, $mouse);

    $raw_X;
}

sub config_mouse {
    my ($raw_X, $do_pkgs, $mouse) = @_;
    mouse::set_xfree_conf($mouse, $raw_X);
    mouse::various_xfree_conf($do_pkgs, $mouse);
}

sub config_keyboard {
    my ($raw_X, $keyboard) = @_;
    $raw_X->set_keyboard(keyboard::keyboard2full_xkb($keyboard));
}

1;

