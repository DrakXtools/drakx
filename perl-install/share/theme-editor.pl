#!/usr/bin/perl -w

use Gtk;
use lib qw(/usr/lib/libDrakX);
use my_gtk qw(:helpers :wrappers);
use common;

init Gtk;

my ($file) = "@ARGV" =~ /-f (.+)/;
$file ||= "themes-mdk.rc";
print "+++++++ $file\n";
my $window1 = new Gtk::Window -toplevel;
$window1->signal_connect ( delete_event => sub { Gtk->exit(0); });
$window1->set_title(_("Theme editor"));
$window1->set_policy(0, 1, 0);
$window1->set_border_width(5);
gtkadd($window1, my $vb = new Gtk::VBox(0,5));
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
#	print " - $_ - \n" foreach ($1, $2, $3, $4, $5);
	print " ++ $style \n";
	if ($do_style) {
	    $cpt == 0 and gtkpack__($vb, $hb = new Gtk::HBox(0,5));
	    $cpt++;
	    $cpt == 4 and $cpt = 0;
	    gtkpack__($hb,
		      gtkadd(gtkset_shadow_type($f = new Gtk::Frame(" $style "), 'etched_out'),
			     $vb2 = gtkset_border_width(new Gtk::VBox(0,5),5)
			    )
		     );
	    $do_style = 0;
	}
	my $c =my_gtk::gtkcolor($3*65535, $4*65535, $5*65535);
	$color{$style}{$1}{$2} = $c;
	my $gc = new Gtk::Gdk::GC($window1->window);
	$gc->set_foreground($c);
	gtkpack__($vb2,
		  gtkpack_(new Gtk::HBox(0,0),
			   1, gtkpack__(new Gtk::HBox(0,0),"$1 [$2] : "),
			   0, gtksignal_connect(gtkset_relief(my $b = new Gtk::Button(), 'none'), clicked => sub {
						    $c = change_color($c);
						    $gc->set_foreground($c);
						    $color{$style}{$1}{$2} = $c;
						    $_[0]->draw(undef);
						})
			  )
		 );
	$b->add(gtksignal_connect(gtksize(gtkset_usize(new Gtk::DrawingArea(), 60, 20), 60, 20), expose_event => sub{ $_[0]->window->draw_rectangle ($gc, 1, 0, 0, 60, 20)} ));
    }
    /\{/ and $ref++;
    if (/\}/) { $ref--; $ref == 0 and undef $style }
}
gtkpack__($vb,
	  gtkadd(gtkset_layout(new Gtk::HButtonBox, -end),
			      gtksignal_connect(new Gtk::Button(_("OK")), clicked => sub { doit(); Gtk->main_quit() }),
			      gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { Gtk->main_quit() }),
			     )
	 );

$window1->set_position(1);
$window1->show_all;
Gtk->main;
Gtk->exit(0);

sub doit {
    require Data::Dumper;
    print " --------------- \n " . Data::Dumper->Dump([%color],['color']) . "\n";
}
sub change_color {
    my ($color) = @_;
    my $window = new Gtk::Window -toplevel;
    my $doit;
    $window->signal_connect ( delete_event => sub { Gtk->main_quit() });
    $window->set_position(1);
    $window->set_title(_("Color configuration"));
    $window->set_border_width(5);
    gtkadd(gtkset_modal($window,1),
	   gtkpack_(new Gtk::VBox(0,5),
		    1, my $colorsel = new Gtk::ColorSelection,
		    0, gtkadd(gtkset_layout(new Gtk::HButtonBox, -end),
			      gtksignal_connect(new Gtk::Button(_("OK")), clicked => sub { $doit=1; Gtk->main_quit() }),
			      gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { Gtk->main_quit() }),
			     )
		   )
	  );
    $colorsel->set_color($color->red()/65535, $color->green()/65535, $color->blue()/65535, $color->pixel());
    $window->show_all();
    Gtk->main;
    $window->destroy();
    $doit or return $color;
    my (@color) = $colorsel->get_color();
    my_gtk::gtkcolor($color[0]*65535, $color[1]*65535, $color[2]*65535);
}
