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


use MDK::Common;
use Gtk;
use Config;
init Gtk;
use POSIX;
use lib qw(/usr/lib/libDrakX);
use interactive;
use standalone;
use any;
use bootloader;
use fs;
use my_gtk qw(:helpers :wrappers :ask);

if ($::isEmbedded) {
  print "EMBED\n";
  print "XID : $::XID\n";
  print "CCPID :  $::CCPID\n";
}

my $in = 'interactive'->vnew('su', 'default');
local $_ = join '', @ARGV;

/-h/ and die _("no help implemented yet.\n");
/-version/ and die 'version: $Id$'."\n";

my @winm;
my @usernames;
parse_etc_passwd();

my $x_mode = isXlaunched();
my $a_mode = (-e "/etc/aurora/Monitor") ? 1 : 0;
my $l_mode = isAutologin();
my %auto_mode = get_autologin("");
my $inmain = 0;
my $lilogrub = chomp_(`detectloader -q`);

my $window = $::isEmbedded ? new Gtk::Plug ($::XID) : new Gtk::Window ("toplevel");
$window->signal_connect(delete_event => sub { $::isEmbedded ? kill('USR1', $::CCPID) : Gtk->exit(0) });
$window->set_title(_("Boot Style Configuration"));
$window->border_width(2);
#$window->realize;

# drakX mode
my ($t_pixmap, $t_mask) = gtkcreate_png("tradi.png");
my ($h_pixmap, $h_mask) = gtkcreate_png("hori.png");
my ($v_pixmap, $v_mask) = gtkcreate_png("verti.png");
my ($g_pixmap, $g_mask) = gtkcreate_png("gmon.png");
my ($c_pixmap, $c_mask) = gtkcreate_png("categ.png");

# a pixmap widget to contain the pixmap
my $pixmap = new Gtk::Pixmap($h_pixmap, $h_mask);

### menus definition
# the menus are not shown
# but they provides shiny shortcut like C-q
my @menu_items = ( { path => _("/_File"), type => '<Branch>' },
		   { path => _("/File/_Quit"), accelerator => _("<control>Q"), callback    => sub { $::isEmbedded ? kill('USR1', $::CCPID) : Gtk->exit(0) } },
		 );
my $menubar = get_main_menu($window);
######### menus end

my $user_combo = new Gtk::Combo;
$user_combo->set_popdown_strings(@usernames);
$user_combo->entry->set_text($auto_mode{autologin}) if ($auto_mode{autologin});
my $desktop_combo =new Gtk::Combo;
$desktop_combo->set_popdown_strings(get_wm());
$desktop_combo->entry->set_text($auto_mode{desktop}) if ($auto_mode{desktop});
my $a_c_button = new Gtk::RadioButton (_("NewStyle Categorizing Monitor"));
my $a_h_button = new Gtk::RadioButton _("NewStyle Monitor"), $a_c_button;
my $a_v_button = new Gtk::RadioButton _("Traditional Monitor"), $a_c_button;
my $a_g_button = new Gtk::RadioButton _("Traditional Gtk+ Monitor"),$a_c_button ;
my $a_button = new Gtk::CheckButton(_("Launch Aurora at boot time"));
my $a_box = new Gtk::VBox(0, 0);
my $x_box = new Gtk::VBox(0, 0);
my $disp_mode = arch() =~ /ppc/ ? _("Yaboot mode") : _("Lilo/grub mode");

my %themes = 	('path'=>'/usr/share/bootsplash/themes/',
		 'default'=>'Mandrake',
		 'def_thmb'=>'/usr/share/libDrakX/pixmaps/nosplash_thumb.png',
		 'lilo'=>{'file'=>'/lilo/message',
			  'thumb'=>'/lilo/thumb.png'} ,
		 'boot'=>{'path'=>'/images/',
			  'thumb'=>'/images/thumb.png',},
		 );
my ($cur_res) = cat_('/etc/lilo.conf') =~ /vga=(.*)/;

#- verify that current resolution is ok
if ( member( $cur_res, qw( 785 788 791 794) ) ) {
	($cur_res) = $bootloader::vga_modes{$cur_res} =~ /^([0-9x]+).*?$/;
} else {
	$no_bootsplash = 1;  #- we can't select any theme we're not in Framebuffer mode :-/
}

#- and check that lilo is the correct loader
$no_bootsplash ||= chomp_(`detectloader -q`) ne 'LILO';

my @thms;
my @lilo_thms = ($themes{'default'})?():qw(default);
my @boot_thms = ($themes{'default'})?():qw(default);
chdir($themes{'path'}); #- we must change directory for correct @thms assignement
foreach (all('.')) {
    if (-d $themes{'path'} . $_ && m/^[^.]/) {
	push @thms, $_;
	-f $themes{'path'} . $_ . $themes{'lilo'}{'file'} and push @lilo_thms, $_;
	-f $themes{'path'} . $_ . $themes{'boot'}{'path'} . "bootsplash-$cur_res.jpg" and push @boot_thms, $_;
    }
#       $_ eq $themes{'defaut'} and $default = $themes{'defaut'};
}
my %combo = ('thms'=> '','lilo'=> '','boot'=> '');
foreach (keys (%combo)) {
    $combo{$_} = new Gtk::Combo;
    $combo{$_}->set_value_in_list(1, 0);
}

$combo{'thms'}->set_popdown_strings(@thms);
$combo{'lilo'}->set_popdown_strings(@lilo_thms);
$combo{'boot'}->set_popdown_strings(@boot_thms);

my $lilo_pic = new Gtk::Pixmap(gtkcreate_png($themes{'def_thmb'}));
my $boot_pic = new Gtk::Pixmap(gtkcreate_png($themes{'def_thmb'}));
my $thm_button = new Gtk::Button(_("Install themes"));
my $logo_thm = new Gtk::CheckButton(_("Display theme under console"));
my $keep_logo = 1;
$logo_thm->set_active(1);
$logo_thm->signal_connect(clicked => sub { invbool(\$keep_logo) });

#- ******** action to take on changing combos values

$combo{'thms'}->entry->signal_connect(changed => sub {
    my $thm_txt = $combo{'thms'}->entry->get_text();
    $combo{'lilo'}->entry->set_text(member($thm_txt, @lilo_thms) ? $thm_txt : ($themes{'default'} || 'default'));
    $combo{'boot'}->entry->set_text(member($thm_txt, @boot_thms) ? $thm_txt : ($themes{'default'} || 'default'));
    
});

$combo{'lilo'}->entry->signal_connect(changed => sub {
    my $new_file = $themes{'path'} . $combo{'lilo'}->entry->get_text() . $themes{'lilo'}{'thumb'};
    $lilo_pic->set(gtkcreate_png(-r $new_file ? $new_file : $themes{'def_thmb'}));
});

$combo{'boot'}->entry->signal_connect( changed => sub {
    my $new_file = $themes{'path'}.$combo{'boot'}->entry->get_text().$themes{'boot'}{'thumb'};
    if (! -f $new_file && -f $themes{'path'}.$combo{'boot'}->entry->get_text().$themes{'boot'}{'path'}."bootsplash-$cur_res.jpg"){
	system("convert -scale 159x119 ".$themes{'path'}.$combo{'boot'}->entry->get_text().$themes{'boot'}{'path'}."bootsplash-$cur_res.jpg $new_file") and $in->ask_warn(_("Error"),_("Can't create Bootsplash preview"));
    }
    $boot_pic->set(gtkcreate_png(-r $new_file ? $new_file : $themes{'def_thmb'}));
});

$combo{'thms'}->entry->set_text($themes{'default'});

$thm_button->signal_connect('clicked',

sub {
        my $error = 0;
        my $boot_conf_file = '/etc/sysconfig/bootsplash';
	my $lilomsg = '/boot/lilo-graphic/message';
        #lilo installation
        if (-f $themes{'path'}.$combo{'lilo'}->entry->get_text() . $themes{'lilo'}{'file'}) {
	    use File::Copy;
	    ( copy($lilomsg,"/boot/lilo-graphic/message.old") 
	      and standalone::explanations(_("Backup %s to %s.old",$lilomsg,$lilomsg)) ) 
	      or $in->ask_warn(_("Error"), _("unable to backup lilo message"));
	    ( copy($themes{'path'} . $combo{'lilo'}->entry->get_text() . $themes{'lilo'}{'file'}, $lilomsg) 
	      and standalone::explanations(_("Copy %s to %s",$themes{'path'} . $combo{'lilo'}->entry->get_text() . $themes{'lilo'}{'file'},$lilomsg)) )
	      or $in->ask_warn(_("Error"), _("can't change lilo message"));
	} else {
            $error = 1;
            $in->ask_warn(_("Error"), _("Lilo message not found"));
        }
        #bootsplash install
        if ( -f $themes{'path'} . $combo{'boot'}->entry->get_text() . $themes{'boot'}{'path'} . "bootsplash-$cur_res.jpg") {
                $bootsplash_cont = "# -*- Mode: shell-script -*-
# Specify here if you want add the splash logo to initrd when
# generating an initrd. You can specify :
#
# SPLASH=no to don't have a splash screen
#
# SPLASH=auto to make autodetect the splash screen
#
# SPLASH=INT When Integer could be 800x600 1024x768 1280x1024
#
SPLASH=$cur_res
# Choose the themes. The should be based in
# /usr/share/bootsplash/themes/
THEME=" . $combo{'boot'}->entry->get_text() . "
# Say yes here if you want to leave the logo on the console.
# Three options :
#
# LOGO_CONSOLE=no don't display logo under console.
#
# LOGO_CONSOLE=yes display logo under console.
#
# LOGO_CONSOLE=theme leave the theme to decide.
#
LOGO_CONSOLE=" . ($keep_logo ? 'yes' : 'no') . "\n";
                if (-f $boot_conf_file) {
                        eval { output($boot_conf_file, $bootsplash_cont) };
			$@ and $in->ask_warn(_("Error"), _("Can't write /etc/sysconfig/bootsplash.")) or standalone::explanations(_("Write %s",$boot_conf_file));
                } else {
                    $in->ask_warn(_("Error"), _("Can't write /etc/sysconfig/bootsplash\nFile not found."));
                    $error = 1;
                }
        } else {
                $in->ask_warn("Error","BootSplash screen not found");
        }
        #here is mkinitrd time
        if (!$error) {
            foreach (map { if_(m|^initrd-(.*)\.img|, $1) } all('/boot')){
                if ( system("mkinitrd -f /boot/initrd-$_.img $_" ) ) {
                    $in->ask_warn(_("Error"),
				  _("Can't launch mkinitrd -f /boot/initrd-%s.img %s.", $_,$_));
                    $error = 1;
                } else { 
		  standalone::explanations(_("Make initrd 'mkinird -f /boot/initrd-%s.img %s'.", $_,$_));
		}
            }
        }
        if (system('lilo')) {
            $in->ask_warn(_("Error"),
_("Can't relaunch LiLo!
Launch \"lilo\" as root in command line to complete LiLo theme installation."));
            $error = 1;
        } else {
		standalone::explanations(_("Relaunch 'lilo'"));
	}
	$in->ask_warn(_(($error)?"Error":"Notice"),
		      _($error?"Theme installation failed!":"LiLo and Bootsplash themes installation successfull"));
    }
);

gtkadd($window,
       gtkpack__ (my $global_vbox = new Gtk::VBox(0,0),
		  gtkadd (new Gtk::Frame ("$disp_mode"),
#			  gtkpack__(new Gtk::VBox(0,0),
				    (gtkpack_(gtkset_border_width(new Gtk::HBox(0, 0),5),
					      1,_("You are currently using %s as your boot manager.
Click on Configure to launch the setup wizard.", $lilogrub),
					      0,gtksignal_connect(new Gtk::Button (_("Configure")), clicked => $::lilo_choice),
					     )),
#				    "" #we need some place under the button -- replaced by gtkset_border_width( for the moment
#				   )
				     
			 ),
                #Splash Selector
                gtkadd(my $thm_frame = new Gtk::Frame( _("Splash selection") ),
                       gtkpack__(gtkset_border_width(new Gtk::HBox(0,5),5),
                                 gtkpack__(new Gtk::VBox(0,5),
                                           _("Themes"),
                                           $combo{'thms'},
                                           _("\nSelect a theme for\nlilo and bootsplash,\nyou can choose\nthem separatly"),
                                           $logo_thm),
                                 gtkpack__(new Gtk::VBox(0,5),
                                           _("Lilo screen"),
                                           $combo{'lilo'},
                                           $lilo_pic),
                                 gtkpack__(new Gtk::VBox(0,5),
                                           _("Bootsplash"),
                                           $combo{'boot'},
                                           $boot_pic,
                                           $thm_button))
                      ),

		  # aurora
# 		  gtkadd (new Gtk::Frame (_("Boot mode")),
# 			  gtkpack__ (new Gtk::HBox(0,0),
# 				     gtkpack__ (new Gtk::VBox(0, 5),
# 						gtksignal_connect ($a_button, clicked => sub {
# 								       if ($inmain) {
# 									   $a_box->set_sensitive(!$a_mode);
# 									   $a_mode = !$a_mode;
# 									   if ($a_mode) {
# 									       $pixmap->set($c_pixmap, $c_mask) if $a_c_button->get_active();
# 									       $pixmap->set($h_pixmap, $h_mask) if $a_h_button->get_active();
# 									       $pixmap->set($v_pixmap, $v_mask) if $a_v_button->get_active();
# 									       $pixmap->set($g_pixmap, $g_mask) if $a_g_button->get_active();
# 									   } else {
# 									       $pixmap->set($t_pixmap, $t_mask);
# 									   }
# 										   }
# 								   }),
# 						gtkpack__ (gtkset_sensitive ($a_box, $a_mode),
# 							    gtksignal_connect ($a_c_button,clicked => sub{$pixmap->set($c_pixmap, $c_mask)}),
# 							    gtksignal_connect ($a_h_button,clicked => sub{$pixmap->set($h_pixmap, $h_mask)}),
# 							    gtksignal_connect ($a_v_button,clicked => sub{$pixmap->set($v_pixmap, $v_mask)}),
# 							    gtksignal_connect ($a_g_button,clicked => sub{$pixmap->set($g_pixmap, $g_mask)})
# 							  )
# 					      ),
# 				     gtkpack__ (new Gtk::HBox(0,0), $pixmap)
# 				    )
# 			 ),
		  # X
		  gtkadd (new Gtk::Frame (_("System mode")),
			  gtkpack__ (new Gtk::VBox(0, 5),
				     gtksignal_connect(gtkset_active(new Gtk::CheckButton (_("Launch the graphical environment when your system starts")), $x_mode), clicked => sub {
							   $x_box->set_sensitive(!$x_mode);
							   $x_mode = !$x_mode;
						       }),
				     gtkpack__ (gtkset_sensitive ($x_box, $x_mode),
						gtkset_active($x_no_button  = new Gtk::RadioButton (_("No, I don't want autologin")), !$l_mode),
						gtkpack__ (new Gtk::HBox(0, 10),
							   gtkset_active($x_yes_button = new Gtk::RadioButton((_("Yes, I want autologin with this (user, desktop)")), $x_no_button), $l_mode),
							   gtkpack__ (new Gtk::VBox(0, 10),
								      $user_combo,
								      $desktop_combo
								     )
							  )
					       )
				    )
			 ),
		 gtkadd (gtkset_layout(new Gtk::HButtonBox,-end),
			 gtksignal_connect(new Gtk::Button(_("OK")), clicked => sub{ updateInit(); updateAutologin(); updateAurora(); $::isEmbedded ? kill('USR1',$::CCPID) : Gtk->exit(0) }),
			 gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { $::isEmbedded ? kill('USR1', $::CCPID) : Gtk->exit(0) })
			)
	       )
      );

$a_button->set_active($a_mode); # up == false == "0"
if ($a_mode) {
    my $a = readlink "/etc/aurora/Monitor";
    $a =~ s#/lib/aurora/Monitors/##;
    if ($a eq "NewStyle-Categorizing-WsLib") { $a_c_button->set_active(1); $pixmap->set($c_pixmap, $c_mask) }
    if ($a eq "NewStyle-WsLib") { $a_h_button->set_active(1);  $pixmap->set($h_pixmap, $h_mask) }
    if ($a eq "Traditional-WsLib") { $a_v_button->set_active(1); $pixmap->set($v_pixmap, $v_mask) }  
    if ($a eq "Traditional-Gtk+") { $a_g_button->set_active(1); $pixmap->set($g_pixmap, $g_mask) }
} else {
    $pixmap->set($t_pixmap, $t_mask);
}

$window->show_all();
$no_bootsplash and $thm_frame->hide();
Gtk->main_iteration while Gtk->events_pending;
$::isEmbedded and kill 'USR2', $::CCPID;
$inmain=1;
Gtk->main;
Gtk->exit(0);

#-------------------------------------------------------------
# get user names to put in combo  
#-------------------------------------------------------------

sub parse_etc_passwd
{
    my ($uname, $uid);
    setpwent();
    do {
	@user_info = getpwent();
	($uname, $uid) = @user_info[0,2];
	push (@usernames, $uname) if ($uid > 500) and !($uname eq "nobody");
    } while (@user_info);
}

sub get_wm
{
    @winm = (split (' ', `/usr/sbin/chksession -l`));
}

#-------------------------------------------------------------
# menu callback functions
#-------------------------------------------------------------

sub print_hello {
  print("mcdtg !\n");
}

sub get_main_menu {
  my ($window) = @_;

  my $accel_group = new Gtk::AccelGroup();
  my $item_factory = new Gtk::ItemFactory('Gtk::MenuBar', '<main>', $accel_group);
  $item_factory->create_items(@menu_items);
  $window->add_accel_group($accel_group);
  return $item_factory->get_widget('<main>');
}

#-------------------------------------------------------------
# launch X functions
#-------------------------------------------------------------

sub isXlaunched {
    my $line;
    open INITTAB, "/etc/inittab" or die _("can not open /etc/inittab for reading: %s", $!);
    while (<INITTAB>) {
	if (/id:([1-6]):initdefault:/) { $line = $_; last }
    }
    close INITTAB;
    $line =~ s/id:([1-6]):initdefault:/$1/;
    return ($line-3);
}

sub updateInit {
    my $runlevel = ($x_mode) ? 5 : 3;
    substInFile { s/^id:\d:initdefault:\s*$/id:$runlevel:initdefault:\n/ } "/etc/inittab";
}

#-------------------------------------------------------------
# aurora functions
#-------------------------------------------------------------



sub updateAurora {
    if ($a_mode) {
        if ($a_c_button->get_active()) {
            symlinkf("/lib/aurora/Monitors/NewStyle-Categorizing-WsLib",    "/etc/aurora/Monitor");
            $in->do_pkgs->install(q(Aurora-Monitor-NewStyle-Categorizing-WsLib)) if !(-e "/lib/aurora/Monitors/NewStyle-Categorizing-WsLib");
        }
        if ($a_h_button->get_active()) {
            symlinkf("/lib/aurora/Monitors/NewStyle-WsLib",    "/etc/aurora/Monitor");
            $in->do_pkgs->install(q(Aurora-Monitor-NewStyle-WsLib)) if !(-e "/lib/aurora/Monitors/NewStyle-WsLib");
        }
        if ($a_v_button->get_active()) {
            symlinkf("/lib/aurora/Monitors/Traditional-WsLib", "/etc/aurora/Monitor");
            $in->do_pkgs->install(q(Aurora-Monitor-Traditional-WsLib)) if !(-e "/lib/aurora/Monitors/Traditional-WsLib");
        }
        if ($a_g_button->get_active()) {
            symlinkf("/lib/aurora/Monitors/Traditional-Gtk+",  "/etc/aurora/Monitor");
            $in->do_pkgs->install(q(Aurora-Monitor-Traditional-Gtk+)) if !(-e "/lib/aurora/Monitors/Traditional-Gtk+");
	}
    } else {
	unlink "/etc/aurora/Monitor";
    }
    
}

#-------------------------------------------------------------
# launch autologin functions
#-------------------------------------------------------------

sub isAutologin {
    my $line;
    open AUTOLOGIN, "/etc/sysconfig/autologin";
    while (<AUTOLOGIN>) {
	if (/AUTOLOGIN=(yes|no)/) { $line = $_; last }
    }
    close AUTOLOGIN;
    $line =~ s/AUTOLOGIN=(yes|no)/$1/;
    chomp ($line);
    $line =  ($line eq "yes");
    my %au = get_autologin('');
    return ($line && defined $au{autologin});
}

sub get_autologin {
    my ($prefix) = @_;
    my %o;
    my %l = getVarsFromSh("$prefix/etc/sysconfig/autologin");

    $o{autologin} = $l{USER};
    %l = getVarsFromSh("$prefix/etc/sysconfig/desktop");
    $o{desktop} = $l{DESKTOP};
    %o;
}

sub updateAutologin {
    my ($usern,$deskt)=($user_combo->entry->get_text(), $desktop_combo->entry->get_text());
    if ($x_yes_button->get_active()) {
	$in->do_pkgs->install('autologin') if $x_mode;
	set_autologin('',$usern,$deskt);
    } else {
	set_autologin('',undef) if ($x_no_button->get_active());
    }
}
 
sub set_autologin {
  my ($prefix, $user, $desktop) = @_;
  output "$prefix/etc/sysconfig/desktop", uc($desktop), "\n" if $user;
  setVarsInSh("$prefix/etc/sysconfig/autologin",
	      { USER => $user, AUTOLOGIN => bool2yesno($user), EXEC => "/usr/X11R6/bin/startx" });
  chmod 0600, "$prefix/etc/sysconfig/autologin";
#  log::l("cat $prefix/etc/sysconfig/autologin: ", cat_("$prefix/etc/sysconfig/autologin"));
}


