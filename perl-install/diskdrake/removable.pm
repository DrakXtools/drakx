package diskdrake::removable; # $Id$

use diagnostics;
use strict;
use diskdrake::interactive;
use common;
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

sub actions() {
    (
     N_("Mount point") => \&mount_point,
     N_("Options") => \&options,
     N_("Type") => \&type,
     N_("Done") => \&done,
    );
}

sub done {
    my ($in, $_raw_hd, $all_hds) = @_;
    diskdrake::interactive::Done($in, $all_hds);
}
sub options {
    my ($in, $raw_hd, $all_hds) = @_;
    diskdrake::interactive::Options($in, {}, $raw_hd, $all_hds);
}
sub mount_point { 
    my ($in, $raw_hd, $all_hds) = @_;
    diskdrake::interactive::Mount_point_raw_hd($in, $raw_hd, $all_hds, "/mnt/$raw_hd->{device}");
}
sub type {
    my ($in, $raw_hd) = @_;
    my @fs = ('auto', fs::type::guessed_by_mount());
    my $fs_type = $raw_hd->{fs_type};
    $in->ask_from(N("Change type"),
			      N("Which filesystem do you want?"),
			      [ { label => N("Type"), val => \$fs_type, list => [@fs], not_edit => !$::expert } ]) or return;
    $raw_hd->{fs_type} = $fs_type;
}

1;
