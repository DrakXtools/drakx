#!/usr/bin/perl -w

# Theme editor

# Copyright (C) 1999 damien@mandrakesoft.com
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


use lib qw(/usr/lib/libDrakX);

use common;
use ugtk2 qw(:all);

#- languages that can't be displayed with gtk1, so we unset translations
#- for them until this tool is ported to gtk2
if ($ENV{LANGUAGE} =~ /\b(ar|he|hi|ta)/) { $ENV{LANGUAGE} = "C" };


if ("@ARGV" =~ /-h/) {
    print q(DrakX theme editor by dam's.

Options :
    -f specify the input theme file. Default is themes-mdk.rc
    -o specify the output file. Default is input file.
    -h print this help.
)
}
my ($file) = "@ARGV" =~ /-f (.+)/;
my ($file2) = "@ARGV" =~ /-o (.+)/;
$file ||= "themes-mdk.rc";
$file2 ||= $file;
my $window1 = new Gtk2::Window -toplevel;
$window1->signal_connect ( delete_event => sub { Gtk2->exit(0); });
$window1->set_title(N("Theme editor"));
$window1->set_border_width(5);
gtkadd($window1, my $vb = new Gtk2::VBox(0,5));
$window1->show_all;
$window1->realize;
my $f;
my $vb2;
my $hb;
my $style;
my $ref = 0;
my %color;
my $cpt = 0;
my $do_style;
foreach (cat_($file)) {
    chomp;
    if(/style "(.*)"/) {
	$style = $1;
	print " -- $style \n";
	$do_style = 1;
    }
    if(/(\w+)\[(\w+)\]\s*=\s*\{\s*([0-9\.]+)\s*,\s*([0-9\.]+)\s*,\s*([0-9\.]+)\s*\}/) {
	my ($a1, $a2) = ($1, $2);
	my $style2 = $style;
	if ($do_style) {
	    $cpt == 0 and gtkpack__($vb, $hb = new Gtk2::HBox(0,5));
	    $cpt++;
	    $cpt == 4 and $cpt = 0;
	    gtkpack__($hb,
		      gtkadd(gtkset_shadow_type($f = new Gtk2::Frame(" $style "), 'etched_out'),
			     $vb2 = gtkset_border_width(new Gtk2::VBox(0,5),5)
			    )
		     );
	    $do_style = 0;
	}
	my $c =ugtk2::gtkcolor($3*65535, $4*65535, $5*65535);
	$color{$style}{$1}{$2} = $c;
	my $gc = new Gtk2::Gdk::GC($window1->window);
	$gc->set_foreground($c);
	gtkpack__($vb2,
		  gtkpack_(new Gtk2::HBox(0,0),
			   1, gtkpack__(new Gtk2::HBox(0,0),"$1 [$2] : "),
			   0, gtksignal_connect(gtkset_relief(my $b = new Gtk2::Button(), 'none'), clicked => sub {
						    $c = change_color($c);
						    $gc->set_foreground($c);
						    $color{$style2}{$a1}{$a2} = $c;
						    $_[0]->queue_draw;
						})
			  )
		 );
	$b->add(gtksignal_connect(gtksize(gtkset_size_request(new Gtk2::DrawingArea(), 60, 20), 60, 20), expose_event => sub{ $_[0]->window->draw_rectangle ($gc, 1, 0, 0, 60, 20)} ));
    }
    /\{/ and $ref++;
    if (/\}/) { $ref--; $ref == 0 and undef $style }
}
gtkpack__($vb,
	  gtkadd(gtkset_layout(new Gtk2::HButtonBox, 'end'),
			      gtksignal_connect(new Gtk2::Button(N("OK")), clicked => sub { doit(); Gtk2->main_quit() }),
			      gtksignal_connect(new Gtk2::Button(N("Cancel")), clicked => sub { Gtk2->main_quit() }),
			     )
	 );

$window1->set_position('center');
$window1->show_all;
Gtk2->main;
Gtk2->exit(0);

sub doit {
    system("rm -f /tmp/plop");
    foreach (cat_($file)) {
	my $output;
	chomp;
	if(/style "(.*)"/) {
	    $style = $1;
	    $do_style = 1;
	}
	if(/(\w+)\[(\w+)\]\s*=\s*\{\s*([0-9\.]+)\s*,\s*([0-9\.]+)\s*,\s*([0-9\.]+)\s*\}/) {
	    #	print " - $_ - \n" foreach ($1, $2, $3, $4, $5);
	    my ($a1, $a2) = ($1, $2);
	    my $c = $color{$style}{$1}{$2};
	    $output = $1 . "[" . $2 . "] = { " .
	      round($c->red()/65535*100)/100 . ", " . round($c->green()/65535*100)/100 . ", " . round($c->blue()/65535*100)/100 . " }";
	}
	/\{/ and $ref++;
	if (/\}/) { $ref--; $ref == 0 and undef $style }
	$output ||= $_;
	$output =~ s/ 1 / 1.0 /;
	$output =~ s/ 1, / 1.0, /;
	$output =~ s/ 1, / 1.0, /;
	system("echo '$output' >> /tmp/plop");
    }
    system("mv -f /tmp/plop $file2");
}

sub change_color {
    my ($color) = @_;
    my $window = new Gtk2::Window -toplevel;
    my $doit;
    $window->signal_connect ( delete_event => sub { Gtk2->main_quit() });
    $window->set_position('center');
    $window->set_title(N("Color configuration"));
    $window->set_border_width(5);
    gtkadd(gtkset_modal($window,1),
	   gtkpack_(new Gtk2::VBox(0,5),
		    1, my $colorsel = new Gtk2::ColorSelection,
		    0, gtkadd(gtkset_layout(new Gtk2::HButtonBox, 'end'),
			      gtksignal_connect(new Gtk2::Button(N("OK")), clicked => sub { $doit=1; Gtk2->main_quit() }),
			      gtksignal_connect(new Gtk2::Button(N("Cancel")), clicked => sub { Gtk2->main_quit() }),
			     )
		   )
	  );
    $colorsel->set_current_color($color);
    $window->show_all();
    Gtk2->main;
    $window->destroy();
    $doit or return $color;
    my (@color) = $colorsel->get_current_color();
    ugtk2::gtkcolor($color[0]*65535, $color[1]*65535, $color[2]*65535);
}
