package diskdrake::removable; # $Id$

use diagnostics;
use strict;
use diskdrake::interactive;
use common;
use fsedit;
use fs;

sub main {
    my ($in, $all_hds, $raw_hd) = @_;
    my %actions = my @actions = actions();
    my $action;
    while ($action ne 'Done') {
	$action = $in->ask_from_list_('', 
					 diskdrake::interactive::format_raw_hd_info($raw_hd), 
					 [ map { $_->[0] } group_by2 @actions ], 'Done') or return;
	$actions{$action}->($in, $raw_hd, $all_hds);
    }
}

sub actions {
    (
     __("Mount point") => \&mount_point,
     __("Options") => \&options,
     __("Type") => \&type,
     __("Done") => \&done,
    );
}

sub done {
    my ($in, $raw_hd, $all_hds) = @_;
    diskdrake::interactive::Done($in, $all_hds);
}
sub options {
    my ($in, $raw_hd, $all_hds) = @_;
    diskdrake::interactive::Options($in, {}, $raw_hd, $all_hds);
}
sub mount_point { 
    my ($in, $raw_hd, $all_hds) = @_;
    diskdrake::interactive::Mount_point_raw_hd($in, $raw_hd, $all_hds);
}
sub type {
    my ($in, $raw_hd) = @_;
    my @fs = ('auto', fs::auto_fs());
    my $type = $raw_hd->{type};
    $in->ask_from(_("Change type"),
			      _("Which filesystem do you want?"),
			      [ { label => _("Type"), val => \$type, list => [@fs], not_edit => !$::expert } ]) or return;
    $raw_hd->{type} = $type;
}

1;
