#!/usr/bin/perl -w

# Control-center

# Copyright (C) 2001 MandrakeSoft
# Yves Duret <yduret at mandrakesoft.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


use Gtk;
use my_gtk qw(:helpers :wrappers);
use common;
use Config;
init Gtk;
use POSIX;
use Locale::GetText;
use any;

my $path_to_pixmaps = "/usr/share/libDrakX/pixmaps";
setlocale (LC_ALL, "");
Locale::GetText::textdomain ("Drakboot");

import Locale::GetText I_;
*_ = *I_;

$::isEmbedded = ($::XID, $::CCPID) = "@ARGV" =~/--embedded (\S*) (\S*)/;
if ($::isEmbedded) {
  print "EMBED\n";
  print "XID: $::XID\n";
  print "CCPID:  $::CCPID\n";
}

local $_ = join '', @ARGV;

/-h/ and die _("no help implemented yet.\n");

my $x_mode = any::runlevel('') == 5;
my $a_mode = (-e "/etc/aurora/Monitor") ? 1 : 0;
my $l_mode = isAutologin();

my $window = $::isEmbedded ? new Gtk::Plug ($::XID) : new Gtk::Window ("toplevel");
$window->signal_connect(delete_event => sub { $::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0) });
$window->set_title(_("Boot Style Configuration"));
#$window->set_policy('automatic', 'automatic');
#$window->set_policy(0, 0, 0);
$window->border_width (10);
$window->realize;

# now for the pixmap from gdk

my ($t_pixmap, $t_mask) = gtkcreate_xpm($window, "$path_to_pixmaps/tradi.xpm");
my ($h_pixmap, $h_mask) = gtkcreate_xpm($window, "$path_to_pixmaps/hori.xpm");
my ($v_pixmap, $v_mask) = gtkcreate_xpm($window, "$path_to_pixmaps/verti.xpm");

# a pixmap widget to contain the pixmap
my $pixmap = new Gtk::Pixmap( $h_pixmap, $h_mask );
#my $h_pixmapwid = new Gtk::Pixmap( $h_pixmap, $h_mask );
#my $v_pixmapwid = new Gtk::Pixmap( $v_pixmap, $v_mask );
#my $t_pixmapwid = new Gtk::Pixmap( $t_pixmap, $t_mask );


### menus definition
# the menus are not shown
# but they provides shiny shortcut like C-q
my @menu_items = ( { path        => _("/_File"),
		     type        => '<Branch>' },
		   { path        => _("/File/_New"),
		     accelerator => _("<control>N"),
		     callback    => \&print_hello },
		   { path        => _("/File/_Open"),
		     accelerator => _("<control>O"),
		     callback    => \&print_hello },
		   { path        => _("/File/_Save"),
		     accelerator => _("<control>S"),
		     callback    => \&print_hello },
		   { path        => _("/File/Save _As") },
		   { path        => _("/File/-"),
		     type        => '<Separator>' },
		   { path        => _("/File/_Quit"),
		     accelerator => _("<control>Q"),
		     callback    => sub { $::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0) } },

		   { path        => _("/_Options"),
		     type        => '<Branch>' },
		   { path        => _("/Options/Test") },

		   { path        => _("/_Help"),
		     type        => '<LastBranch>' },
		   { path        => _("/Help/_About...") } );

my $menubar = get_main_menu( $window );

######### menus end

my $global_vbox = new Gtk::VBox();

$global_vbox->pack_start (new Gtk::Label(_("Boot style configuration")), 0, 0, 0);

######## aurora part
my $a_dedans = new Gtk::VBox( 0, 10 );
$a_dedans->border_width (5);
my $a_box = new Gtk::VBox(0, 0 );
my $a_button = new Gtk::CheckButton(_("Launch Aurora at boot time"));
$a_button->signal_connect( clicked => sub {
			     $a_box->set_sensitive(!$a_mode); 
			     $pixmap->set($a_mode ? ($t_pixmap, $t_mask) : ($h_pixmap, $h_mask));
			     $a_mode = !$a_mode;
			   });
$a_dedans->pack_start ($a_button, 0, 0, 0);

my $a_h_button = new Gtk::RadioButton _("horizontal nice looking aurora");
$a_h_button->signal_connect( clicked => sub { $pixmap->set($h_pixmap, $h_mask) });
$a_h_button->set_active(1);
$a_box->pack_start($a_h_button, 0, 0, 0);

my $a_v_button = new Gtk::RadioButton _("vertical traditional aurora"), $a_h_button;
$a_v_button->signal_connect( clicked => sub { $pixmap->set($v_pixmap, $v_mask) });
$a_box->pack_start($a_v_button, 0, 0, 0);

my $a_g_button = new Gtk::RadioButton _("gMonitor"), $a_h_button;
$a_box->pack_start($a_g_button, 0, 0, 0);

$a_dedans->pack_start ($a_box, 0, 0, 0);

my $a_main_hbox = new Gtk::HBox;
$a_main_hbox->pack_start ($a_dedans, 0, 0, 0);
my $a_pix_hbox = new Gtk::HBox;
$a_pix_hbox->border_width(10);

$a_pix_hbox->pack_start ($pixmap, 0, 0, 0);

$a_main_hbox->pack_end ($a_pix_hbox, 0, 0, 0);

my $aurora_frame = new Gtk::Frame _("Boot mode");
$aurora_frame->add($a_main_hbox);
$global_vbox->pack_start ($aurora_frame, 0, 0, 0);

### X mode
my $x_dedans = new Gtk::VBox( 0, 10 );
$x_dedans->border_width (5);
my $x_box = new Gtk::VBox(0, 0 );
$x_box->border_width (10);

my $x_button = new Gtk::CheckButton _("Launch the X-Window system at start");
$x_button->set_active($x_mode);
$x_button->signal_connect( clicked => sub {
			       $x_box->set_sensitive(!$x_mode);
			       $x_mode = !$x_mode;
			   });
$x_dedans->pack_start ($x_button, 0, 0, 0);

my $x_no_button = new Gtk::RadioButton _("no, I don't want autologin");
$x_no_button->set_active(!$l_mode);
$x_box->pack_start($x_no_button, 0, 0, 0);

my $user_dedans = new Gtk::HBox( 0, 10 );
$user_dedans->border_width (0);
my $x_yes_button = new Gtk::RadioButton _("yes, I want autologin with this (user, desktop)"), $x_no_button;
$x_yes_button->set_active($l_mode);
my $user_combo = new Gtk::Combo;
$user_combo->set_popdown_strings(parse_etc_passwd());
my $desktop_combo = new Gtk::Combo;
$user_dedans->pack_start($x_yes_button, 0, 0, 0);
$user_dedans->pack_start($user_combo, 0, 0, 0);
#$user_dedans->pack_start($desktop_combo, 0, 0, 0);
$x_box->pack_start ($user_dedans, 0, 0, 0);

$x_box->set_sensitive(!$x_mode);
$x_dedans->pack_start ($x_box, 0, 0, 0);
my $x_main_frame = new Gtk::Frame _("System mode");
$x_main_frame->add($x_dedans);
$global_vbox->pack_start ($x_main_frame, 1, 1, 0);

### final buttons
my $build_button = new Gtk::Button _("OK");
my $cancel_button = new Gtk::Button _("Cancel");
my $fin_hbox = new Gtk::HBox( 0, 0 );
$cancel_button->signal_connect( clicked => sub {$::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0)});
$build_button->signal_connect( clicked => sub { any::runlevel('', $x_mode ? 5 : 3); updateAutologin() });
$fin_hbox->pack_end($cancel_button, 0, 0, 0);
$fin_hbox->pack_end($build_button,  0, 0, 10);
$global_vbox->pack_start ($fin_hbox, 0, 0, 0);

### back to window
$window->add( $global_vbox );

$window->show_all();
print "---->$a_mode<----\n";

$a_button->set_active(!$a_mode);
$a_box->set_sensitive(!$a_mode);
$pixmap->set($a_mode ? ($h_pixmap, $h_mask) : ($t_pixmap, $t_mask));

if ($a_mode) {
    print "some where aurora exists ...\n";
#we need to choose acording the aurora style
} else { 
    print "here aurora does not exist..\n";
}

Gtk->main_iteration while Gtk->events_pending;
$::isEmbedded and kill USR2, $::CCPID;
Gtk->main;
#-------------------------------------------------------------
# get user names to put in combo  
#-------------------------------------------------------------

sub parse_etc_passwd {
    map { $_->[0] } grep { $_->[2] >= 500 } common::list_passwd();
}

#-------------------------------------------------------------
# menu callback functions
#-------------------------------------------------------------

sub print_hello {
  print( "mcdtg !\n" );
}

sub get_main_menu {
  my ($window) = @_;

  my $accel_group = new Gtk::AccelGroup();
  my $item_factory = new Gtk::ItemFactory( 'Gtk::MenuBar', '<main>', $accel_group );
  $item_factory->create_items(@menu_items);
  $window->add_accel_group($accel_group);
  return $item_factory->get_widget('<main>');
}


#-------------------------------------------------------------
# launch autologin functions
#-------------------------------------------------------------

sub isAutologin {
    ${{ common::getVarsFromSh("/etc/sysconfig/autologin") }}{AUTOLOGIN} eq 'yes';
}

sub updateAutologin
{    
    my ($autologin) = @_;
    substInFile { 
	s/^AUTOLOGIN=.*//; 
	$_ .= 'AUTOLOGIN=' . bool2yesno($autologin) . "\n" if eof;
    } '/etc/sysconfig/autologin';
}
 
