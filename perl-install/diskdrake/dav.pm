package diskdrake::dav; # $Id$

use diagnostics;
use strict;
use diskdrake::interactive;
use common;
use fsedit;
use fs;

sub main {
    my ($in, $all_hds) = @_;
    my $davs = $all_hds->{davs};

    $in->do_pkgs->ensure_is_installed('davfs', '/sbin/mount.davfs') or return;
    
    my $quit;
    do {
	$in->ask_from_({ ok => '' },
		       [ 
			(map { 
			    my $dav = $_;
			    { label => $dav->{device}, val => $dav->{mntpoint}, clicked_may_quit => sub { config($in, $dav, $all_hds); 1 } } } @$davs),
			 { val => _("New"), clicked_may_quit => sub { create($in, $all_hds); 1 } },
			 { val => _("Quit"), icon => "exit", clicked_may_quit => sub { $quit = 1 } },
		       ]);
    } until ($quit);

    diskdrake::interactive::Done($in, $all_hds);
}

sub create {
    my ($in, $all_hds) = @_;

    my $dav = { type => 'davfs' };
    ask_server($in, $dav, $all_hds) or return;
    push @{$all_hds->{davs}}, $dav;
    config($in, $dav, $all_hds);
}

sub config {
    my ($in, $dav_, $all_hds) = @_;

    my $dav = { %$dav_ }; #- working on a local copy so that "Cancel" works

    my %actions = my @actions = actions();
    my $action;
    while ($action ne 'Done') {
	$action = $in->ask_from_list_('', format_dav_info($dav), 
					 [ map { $_->[0] } group_by2 @actions ], 'Done') or return;
	$actions{$action}->($in, $dav, $all_hds);    
    }
    %$dav_ = %$dav; #- applying
}

sub actions {
    (
     __("Server") => \&ask_server,
     __("Mount point") => \&mount_point,
     __("Options") => \&options,
     __("Done") => sub {},
    );
}

sub ask_server {
    my ($in, $dav, $all_hds) = @_;

    my $server = $dav->{device};
    $in->ask_from('', _("Please enter the WebDAV server URL"),
		  [ { val => \$server } ],
		  complete => sub {
		      $server =~ m!https?://! or $in->ask_warn('', _("The URL must begin with http:// or https://")), return 1;
		      0;
		  },
		 ) or return;
    $dav->{device} = $server;
}

sub options {
    my ($in, $dav, $all_hds) = @_;
    diskdrake::interactive::Options($in, {}, $dav, $all_hds);
}
sub mount_point { 
    my ($in, $dav, $all_hds) = @_;
    my $proposition = $dav->{device} =~ /(\w+)/ ? "/mnt/$1" : "/mnt/dav";
    diskdrake::interactive::Mount_point_raw_hd($in, $dav, $all_hds, $proposition);
}

sub format_dav_info {
    my ($dav) = @_;

    my $info = '';
    $info .= _("Server: ") . "$dav->{device}\n" if $dav->{device};
    $info .= _("Mount point: ") . "$dav->{mntpoint}\n" if $dav->{mntpoint};
    $info .= _("Options: %s", $dav->{options}) if $dav->{options};
    $info;
}

1;
