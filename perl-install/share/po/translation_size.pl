#!/usr/bin/perl -w

#
# Guillaume Cottenceau (gc@mandrakesoft.com)
#
# Copyright 2003 Mandrakesoft
#
# This software may be freely redistributed under the terms of the GNU
# public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#

# Tool to check translations sizes
#
# cd to this directory to have the "use lib" works and grab install_gtk successfully


use lib qw(../..);
use common;
use ugtk2;
use install_gtk;

!@ARGV and die "Usage: LANGUAGE=lang_to_test $0 string_to_translate\n(for example: LANGUAGE=ja $0 Advanced)\n";

install_gtk::load_font({ locale => { lang => 'en_US' } });
$l1 = Gtk2::Label->new($ARGV[0]);
my $v = Gtk2::VBox->new(1, 0);
$v->pack_start($l1, 0, 0, 0);
my $window = Gtk2::Window->new('toplevel');
$window->set_size_request(200, 50);
$window->set_position('center');
$window->signal_connect(key_press_event => sub { Gtk2->main_quit });
$window->add($v);
$window->show_all;

install_gtk::load_font({ locale => { lang => $ENV{LANGUAGE} } });
$l2 = Gtk2::Label->new(translate($ARGV[0]));
$v->pack_start($l2, 0, 0, 0);
$window->show_all;

Gtk2->main;

