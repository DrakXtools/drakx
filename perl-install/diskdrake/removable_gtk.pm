package diskdrake::removable_gtk; # $Id$

use diagnostics;
use strict;

use my_gtk qw(:helpers :wrappers :ask);


sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;

    if ($entry) {
	my @l = (
		 _("Mount point") => \&raw_hd_mount_point,
		 _("Options") => \&raw_hd_options,
		 _("Type") => \&removable_type,
		);
	@buttons = map_each {
	    my ($txt, $f) = @_;
	    gtksignal_connect(new Gtk::Button($txt), clicked => sub { try_('', $f, $entry) });
	} group_by2 @l;

	gtkadd($box, gtkadd(new Gtk::Frame(_("Choose action")),
			    createScrolledWindow(gtkpack__(new Gtk::VBox(0,0), @buttons)))) if @buttons;
	    
    } else {
	my $txt = _("Please click on a medium");
	gtkpack($box, gtktext_insert(new Gtk::Text, $txt));
    }
}
