package diskdrake::smbnfs_gtk; # $Id$

use diagnostics;
use strict;

use any;
use fs;
use diskdrake::interactive;
use common;
use interactive;
use network::smb;
use network::nfs;
use my_gtk qw(:helpers :wrappers :ask);

my ($all_hds, $in);

sub main {
    ($in, $all_hds, my $type) = @_;
    my ($check, $create) = $type eq 'smb' ? (\&network::smb::check, \&smb_create) : (\&network::nfs::check, \&nfs_create);
    $check->($in) or return;

    my $w = my_gtk->new('DiskDrake');
    $create->($w->{window});
    $w->{rwindow}->set_default_size(400, 300);
    $w->{window}->show_all;
    $w->main;
}

################################################################################
# nfs/smb: helpers
################################################################################
sub try {
    my ($name, @args) = @_;
    my $f = $diskdrake::interactive::{$name} or die "unknown function $name";
    try_($name, \&{$f}, @args);
}
sub try_ {
    my ($name, $f, @args) = @_;
    eval { $f->($in, @args, $all_hds); };
    if (my $err = $@) {
	$in->ask_warn(_("Error"), formatError($err));
    }
    Gtk->main_quit if $name eq 'Done';
}

sub per_entry_info_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;
    my $info;
    if ($entry) {
	$info = diskdrake::interactive::format_raw_hd_info($entry);
    }
    gtkpack($box, gtkadd(new Gtk::Frame(_("Details")), gtkset_justify(new Gtk::Label($info), 'left')));
}

sub raw_hd_options {
    my ($in, $raw_hd) = @_;
    diskdrake::interactive::Options($in, {}, $raw_hd);
}
sub raw_hd_mount_point {
    my ($in, $raw_hd) = @_;
    diskdrake::interactive::Mount_point_raw_hd($in, $raw_hd, $all_hds);
}


sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;

    my @buttons = map {
	  my $s = $_;
	  gtksignal_connect(new Gtk::Button(translate($s)), clicked => sub { try($s, {}, $entry) });
      } (if_($entry->{isMounted}, __("Unmount")),
	 if_($entry->{mntpoint} && !$entry->{isMounted}, __("Mount"))) if $entry;

    my @l = (
	     if_($entry, __("Mount point") => \&raw_hd_mount_point),
	     if_($entry && $entry->{mntpoint}, __("Options") => \&raw_hd_options),
	     __("Export") => \&any::fileshare_config,
	     __("Done") => \&done,
	    );
    push @buttons, map {
	my ($txt, $f) = @$_;
	gtksignal_connect(new Gtk::Button(translate($txt)), clicked => sub { try_($txt, $f, $entry) });
    } group_by2(@l);

    gtkadd($box, gtkpack(new Gtk::HBox(0,0), @buttons));
}

sub done {
    my ($in) = @_;
    diskdrake::interactive::Done($in, $all_hds);
}

sub current_entry_changed {
    my ($kind, $entry) = @_;
    per_entry_action_box($kind->{action_box}, $kind, $entry);
    per_entry_info_box($kind->{info_box}, $kind, $entry);
}

sub import_ctree {
    my ($kind, $imported, $find_servers, $find_exports, $create) = @_;
    my (%name2server, %wservers, %name2export, $inside);

    my $tree = Gtk::CTree->new(1, 0);
    $tree->set_column_auto_resize(0, 1);
    $tree->set_selection_mode('browse');
    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);

    my $add_server = sub {
	my ($server) = @_;
	my $name = $server->{name} || $server->{ip};
	$name2server{$name} = $server;
	$wservers{$name} ||= $tree->insert_node(undef, undef, [$name], 5, (undef) x 4, 0, 0);
	$wservers{$name}
    };

    my $add_exports = sub {
	my ($node) = @_;
	$tree->expand($node);
	my $name = first $tree->node_get_pixtext($node, 0);
	foreach ($find_exports->($name2server{$name})) {
	    my $name = $_->{name} . ($_->{comment} ? " ($_->{comment})" : '');
	    $name2export{$name} = $_;
	    $tree->insert_node($node, undef, [$name], 5, (undef) x 4, 1, 0);
	}
    };

    my $click_here = $tree->insert_node(undef, undef, [_("click here")], 5, (undef) x 4, 0, 0);
    foreach (@$imported) {
	my $node = $add_server->($_->{server});
	$add_exports->($node);
    }

    $tree->signal_connect(tree_select_row => sub { 
	my $curr = $_[1];
	$inside and return;
	$inside = 1;
	if ($curr->row->is_leaf) {
	    my ($export) = $tree->node_get_pixtext($curr, 0);
	    $export =~ s/ \(.*?\)$//;
	    my ($server) = $tree->node_get_pixtext($curr->row->parent, 0);
	    my $entry = $create->($server, $export);
	    if (my ($e) = grep { $entry->{device} eq $_->{device} } @{$kind->{val}}) {
		$entry = $e;
	    } else {
		push @{$kind->{val}}, $entry;
	    }
	    current_entry_changed($kind, $entry);
	} elsif (!$curr->row->children) {
	    $tree->freeze;
	    if ($curr == $click_here) {
		$add_server->($_) foreach sort { $a->{name} cmp $b->{name} } $find_servers->();
		$tree->remove_node($click_here);
	    } else {
		$add_exports->($curr);
	    }
	    $tree->thaw;
	}
	$inside = 0;
    });
    $tree;
}

sub add_smbnfs {
    my ($widget, $kind, $find_servers, $find_exports, $create) = @_;
    die if $kind->{main_box};

    my $imported = [];

    $kind->{display_box} = createScrolledWindow(import_ctree($kind, $imported, $find_servers, $find_exports, $create));
    $kind->{action_box} = new Gtk::HBox(0,0);
    $kind->{info_box} = new Gtk::VBox(0,0);
    $kind->{main_box} =
      gtkpack_(new Gtk::VBox(0,7),
	       1, gtkpack(new Gtk::HBox(0,7),
			  gtkset_usize($kind->{display_box}, 200, 0),
			  $kind->{info_box}),
	       0, $kind->{action_box},
	     );

    $widget->add($kind->{main_box});
    current_entry_changed($kind, undef);
    $kind;
}

################################################################################
# nfs: helpers
################################################################################
sub nfs2kind {
    my ($l) = @_;
    { type => 'nfs', name => 'NFS', val => $l, no_auto => 1 };
}

sub nfs_create {
    my ($widget) = @_;

    my $find_servers = sub {
	my $w = $in->wait_message('', _("Scanning available nfs shared resource"));
	&network::nfs::find_servers;
    };
    my $find_exports = sub {
	my ($server) = @_;
	my $w = $in->wait_message('', _("Scanning available nfs shared resource of server %s", $server->{name}));
	&network::nfs::find_exports;
    };
    my $create = sub {
	my ($server, $export) = @_;

	my $nfs = { device => "$server:$export", type => 'nfs' };
	fs::set_default_options($nfs);
	$nfs;
    };
    add_smbnfs($widget, nfs2kind($all_hds->{nfss}), $find_servers, $find_exports, $create);
}

################################################################################
# smb: helpers
################################################################################
sub smb2kind {
    my ($l) = @_;
    { type => 'smb', name => 'Samba', val => $l, no_auto => 1 };
}

sub smb_create {
    my ($widget) = @_;

    my $find_servers = sub {
	my $w = $in->wait_message('', _("Scanning available samba shared resource"));
	&network::smb::find_servers;
    };
    my $find_exports = sub {
	my ($server) = @_;
	my $w = $in->wait_message('', _("Scanning available samba shared resource of server %s", $server->{name}));
	&network::smb::find_exports;
    };
    my $create = sub {
	my ($server, $export) = @_;

	my $smb = { device => "//$server/$export", type => 'smbfs', options => 'username=%' };
	fs::set_default_options($smb);
	$smb;
    };
    add_smbnfs($widget, smb2kind($all_hds->{smbs}), $find_servers, $find_exports, $create);
}

1;
