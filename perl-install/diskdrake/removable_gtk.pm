package diskdrake::removable_gtk; # $Id$

use diagnostics;
use strict;

use common;
use my_gtk qw(:helpers :wrappers :ask);


sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;

    if ($entry) {
	my @l = (
		 N("Mount point") => \&raw_hd_mount_point,
		 N("Options") => \&raw_hd_options,
		 N("Type") => \&removable_type,
		);
	my @buttons = map_each {
	    my ($txt, $f) = @_;
	    gtksignal_connect(new Gtk::Button($txt), clicked => sub { try_('', $f, $entry) });
	} group_by2 @l;

	gtkadd($box, gtkadd(new Gtk::Frame(N("Choose action")),
			    createScrolledWindow(gtkpack__(new Gtk::VBox(0,0), @buttons)))) if @buttons;
	    
    } else {
	my $txt = N("Please click on a medium");
	gtkpack($box, gtktext_insert(new Gtk::Text, $txt));
    }
}
