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
use Config;
init Gtk;
use POSIX;
use Locale::GetText;

my $path_to_pixmaps = "";
setlocale (LC_ALL, "");
Locale::GetText::textdomain ("c'est ton boot !");

import Locale::GetText I_;
*_ = *I_;

$::isEmbedded = ($::XID, $::CCPID) = "@ARGV" =~/--embedded (\S*) (\S*)/;
if ($::isEmbedded) {
  print "EMBED\n";
  print "XID : $::XID\n";
  print "CCPID :  $::CCPID\n";
}

local $_ = join '', @ARGV;

/-h/ and die _("no help implemented yet.\n");

my $x_mode = isXlaunched();
my $a_mode = (-e "/etc/aurora/Monitor") ? 1 : 0;
my $l_mode = isAutologin();

my $window = $::isEmbedded ? new Gtk::Plug ($::XID) : new Gtk::Window ("toplevel");
$window->signal_connect( 'delete_event', sub { $::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0) });
$window->set_title( I_("Boot Style Configuration") );
#$window->set_policy('automatic', 'automatic');
#$window->set_policy(0, 0, 0);
$window->border_width (10);
$window->realize;

# now for the pixmap from gdk

my ( $t_pixmap, $t_mask ) = Gtk::Gdk::Pixmap->create_from_xpm( $window->window, $window->get_style()->bg( 'normal' ), $path_to_pixmaps."tradi.xpm" );
my ( $h_pixmap, $h_mask ) = Gtk::Gdk::Pixmap->create_from_xpm( $window->window, $window->get_style()->bg( 'normal' ), $path_to_pixmaps."hori.xpm" );
my ( $v_pixmap, $v_mask ) = Gtk::Gdk::Pixmap->create_from_xpm( $window->window, $window->get_style()->bg( 'normal' ), $path_to_pixmaps."verti.xpm" );

# a pixmap widget to contain the pixmap
my $pixmap = new Gtk::Pixmap( $h_pixmap, $h_mask );
#my $h_pixmapwid = new Gtk::Pixmap( $h_pixmap, $h_mask );
#my $v_pixmapwid = new Gtk::Pixmap( $v_pixmap, $v_mask );
#my $t_pixmapwid = new Gtk::Pixmap( $t_pixmap, $t_mask );


### menus definition
# the menus are not shown
# but they provides shiny shortcut like C-q
my @menu_items = ( { path        => I_("/_File"),
		     type        => '<Branch>' },
		   { path        => I_("/File/_New"),
		     accelerator => I_("<control>N"),
		     callback    => \&print_hello },
		   { path        => I_("/File/_Open"),
		     accelerator => I_("<control>O"),
		     callback    => \&print_hello },
		   { path        => I_("/File/_Save"),
		     accelerator => I_("<control>S"),
		     callback    => \&print_hello },
		   { path        => I_("/File/Save _As") },
		   { path        => I_("/File/-"),
		     type        => '<Separator>' },
		   { path        => I_("/File/_Quit"),
		     accelerator => I_("<control>Q"),
		     callback    => sub { $::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0) } },

		   { path        => I_("/_Options"),
		     type        => '<Branch>' },
		   { path        => I_("/Options/Test") },

		   { path        => I_("/_Help"),
		     type        => '<LastBranch>' },
		   { path        => I_("/Help/_About...") } );

my $menubar = get_main_menu( $window );

######### menus end

my $global_vbox = new Gtk::VBox();

$global_vbox->pack_start (new Gtk::Label(_("Boot style configuration")), 0, 0, 0);

######## aurora part
my $a_dedans = new Gtk::VBox( 0, 10 );
$a_dedans->border_width (5);
my $a_box = new Gtk::VBox(0, 0 );
my $a_button = new Gtk::CheckButton( I_("Launch Aurora at boot time") );
$a_button->signal_connect( "clicked", sub {
			     if ($a_mode) { 
				 $a_box->set_sensitive(0); $pixmap->set($t_pixmap, $t_mask);
			     } else { 
				 $a_box->set_sensitive(1); $pixmap->set($h_pixmap, $h_mask);
			     }
			     $a_mode = !$a_mode;
			   });
$a_dedans->pack_start ($a_button, 0, 0, 0);

my $a_h_button = new Gtk::RadioButton _("horizontal nice looking aurora");
$a_h_button->signal_connect( "clicked", sub { $pixmap->set($h_pixmap, $h_mask) });
$a_h_button->set_active(1);
$a_box->pack_start($a_h_button, 0, 0, 0);

my $a_v_button = new Gtk::RadioButton _("vertical traditionnal aurora"), $a_h_button;
$a_v_button->signal_connect( "clicked", sub { $pixmap->set($v_pixmap, $v_mask) });
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
$x_button->signal_connect( "clicked", sub {
			       ($x_mode) ? $x_box->set_sensitive(0) : $x_box->set_sensitive(1);
			       $x_mode = !$x_mode;
			   });
$x_dedans->pack_start ($x_button, 0, 0, 0);

my $x_no_button = new Gtk::RadioButton _("no, I don't want autologin");
$x_no_button->set_active(!$l_mode);
$x_box->pack_start($x_no_button, 0, 0, 0);

my $user_dedans = new Gtk::HBox( 0, 10 );
$user_dedans->border_width (0);
my $x_yes_button = new Gtk::RadioButton _("yes, I want autologin with this user"), $x_no_button;
$x_yes_button->set_active($l_mode);
my $user_combo = new Gtk::Combo;
$user_combo->set_popdown_strings("you", "me", "rms", "linus");
$user_dedans->pack_start($x_yes_button, 0, 0, 0);
$user_dedans->pack_start($user_combo, 0, 0, 0);
$x_box->pack_start ($user_dedans, 0, 0, 0);

($x_mode) ? $x_box->set_sensitive(1) : $x_box->set_sensitive(0);
$x_dedans->pack_start ($x_box, 0, 0, 0);
my $x_main_frame = new Gtk::Frame _("System mode");
$x_main_frame->add($x_dedans);
$global_vbox->pack_start ($x_main_frame, 1, 1, 0);

### final buttons
my $build_button = new Gtk::Button _("OK");
my $cancel_button = new Gtk::Button _("Cancel");
my $fin_hbox = new Gtk::HBox( 0, 0 );
$cancel_button->signal_connect( 'clicked', sub {$::isEmbedded ? kill(USR1, $::CCPID) : Gtk->exit(0)});
$build_button->signal_connect('clicked', sub { updateInit(); updateAutologin();});
$fin_hbox->pack_end($cancel_button, 0, 0, 0);
$fin_hbox->pack_end($build_button,  0, 0, 10);
$global_vbox->pack_start ($fin_hbox, 0, 0, 0);

### back to window
$window->add( $global_vbox );

$window->show_all();
print "---->$a_mode<----\n";

if ($a_mode) {
    print "some where aurora exists ...\n";
    $a_button->set_active(1);
    $a_box->set_sensitive(1);
#we need to choose acording the aurora style
    $pixmap->set($h_pixmap, $h_mask);
} else { 
    print "here aurora does not exist..\n";
    $a_button->set_active(0);
    $a_box->set_sensitive(0); 
    $pixmap->set($t_pixmap, $t_mask)
}

main Gtk;

#-------------------------------------------------------------
# menu callback functions
#-------------------------------------------------------------

sub print_hello {
  print( "mcdtg !\n" );
}

sub get_main_menu {
  my ( $window ) = @_;

  my $accel_group = new Gtk::AccelGroup();
  my $item_factory = new Gtk::ItemFactory( 'Gtk::MenuBar', '<main>', $accel_group );
  $item_factory->create_items( @menu_items );
  $window->add_accel_group( $accel_group );
  return ( $item_factory->get_widget( '<main>' ) );
}

#-------------------------------------------------------------
# launch X functions
#-------------------------------------------------------------

sub isXlaunched
{
    my $line;
    
    open INITTAB, "/etc/inittab" or die _("can not open /etc/inittab for reading : $!");
    while (<INITTAB>) {
	if (/id:([1-6]):initdefault:/) { $line = $_; last; }
    }
    close INITTAB;
    $line =~ s/id:([1-6]):initdefault:/$1/;
    return ($line-3);
}

sub updateInit
{
    my $level = ($x_mode) ? 5 : 3;
    system ("perl -pi -e 's/id:([1-6]):initdefault:/id:$level:initdefault:/' /etc/inittab");
}


#-------------------------------------------------------------
# launch autologin functions
#-------------------------------------------------------------

sub isAutologin
{
    my $line;
    
    open AUTOLOGIN, "/etc/sysconfig/autologin" or die _("can not open /etc/sysconfig/autologin for reading : $!");
    while (<AUTOLOGIN>) {
	if (/AUTOLOGIN=(yes|no)/) { $line = $_; last; }
    }
    close AUTOLOGIN;
    $line =~ s/AUTOLOGIN=(yes|no)/$1/;
    chomp ($line);
    $line =  ($line eq "yes");
    return ($line);
}

sub updateAutologin
{
    $l_mode = $x_yes_button->get_active();
    my $level = ($l_mode) ? "yes" : "no";
    system ("perl -pi -e 's/AUTOLOGIN=(yes|no)/AUTOLOGIN=$level/' /etc/sysconfig/autologin");
}
 
