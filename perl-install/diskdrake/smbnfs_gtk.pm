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

my ($all_hds, $in, $tree, $current_entry, $current_leaf, %icons);

sub main {
    ($in, $all_hds, my $type) = @_;
    my ($kind) = $type eq 'smb' ? smb2kind() : nfs2kind();
    {
	local $my_gtk::pop_it = 1;
	$kind->check($in) or return;
    }

    my $w = my_gtk->new('DiskDrake');

    add_smbnfs($w->{window}, $kind);
    $w->{rwindow}->set_default_size(400, 300) if $w->{rwindow}->can('set_default_size');
    $w->{window}->show_all;
    $w->main;
}

################################################################################
# nfs/smb: helpers
################################################################################
sub try {
    my ($kind, $name, @args) = @_;
    my $f = $diskdrake::interactive::{$name} or die "unknown function $name";
    try_($kind, $name, \&{$f}, @args);
}
sub try_ {
    my ($kind, $name, $f, @args) = @_;
    eval { $f->($in, @args, $all_hds); };
    if (my $err = $@) {
	$in->ask_warn(_("Error"), formatError($err));
    }
    update($kind);
    Gtk->main_quit if $name eq 'Done';
}

sub raw_hd_options {
    my ($in, $raw_hd) = @_;
    diskdrake::interactive::Options($in, {}, $raw_hd);
}
sub raw_hd_mount_point {
    my ($in, $raw_hd) = @_;
    diskdrake::interactive::Mount_point_raw_hd($in, $raw_hd, $all_hds);
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

sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;

    my @buttons;

    push @buttons, map {
	  my $s = $_;
	  gtksignal_connect(new Gtk::Button(translate($s)), clicked => sub { try($kind, $s, {}, $entry) });
      } (if_($entry->{isMounted}, __("Unmount")),
	 if_($entry->{mntpoint} && !$entry->{isMounted}, __("Mount"))) if $entry;

    my @l = (
	     if_($entry, __("Mount point") => \&raw_hd_mount_point),
	     if_($entry && $entry->{mntpoint}, __("Options") => \&raw_hd_options),
	     __("Export") => sub { any::fileshare_config($in, $kind->{type}) },
	     __("Done") => \&done,
	    );
    push @buttons, map {
	my ($txt, $f) = @$_;
	gtksignal_connect(new Gtk::Button(translate($txt)), clicked => sub { try_($kind, $txt, $f, $entry) });
    } group_by2(@l);

    gtkadd($box, gtkpack(new Gtk::HBox(0,0), @buttons));
}

sub done {
    my ($in) = @_;
    diskdrake::interactive::Done($in, $all_hds);
}

sub set_export_icon {
    my ($entry, $w) = @_;
    $entry ||= {};
    my $icon = $icons{$entry->{isMounted} ? 'mounted' : $entry->{mntpoint} ? 'has_mntpoint' : 'default'};
    my_gtk::ctree_set_icon($tree, $w, @$icon);
}

sub update {
    my ($kind) = @_;
    per_entry_action_box($kind->{action_box}, $kind, $current_entry);
    per_entry_info_box($kind->{info_box}, $kind, $current_entry);
    set_export_icon($current_entry, $current_leaf) if $current_entry;
}

sub find_fstab_entry {
    my ($kind, $e, $add_or_not) = @_;

    my $fs_entry = $kind->to_fstab_entry($e);

    if (my ($fs_entry_) = grep { $fs_entry->{device} eq $_->{device} } @{$kind->{val}}) {
	$fs_entry_;
    } elsif ($add_or_not) {
	push @{$kind->{val}}, $fs_entry;
	$fs_entry;
    } else {
	undef;
    }
}

sub import_ctree {
    my ($kind) = @_;
    my (%servers_displayed, %wservers, %wexports, $inside);

    $tree = Gtk::CTree->new(1, 0);
    $tree->set_column_auto_resize(0, 1);
    $tree->set_selection_mode('browse');
    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);

    foreach ('default', 'server', 'has_mntpoint', 'mounted') {
	$icons{$_} = [ gtkcreate_png("smbnfs_$_") ];
    }

    my $add_server = sub {
	my ($server) = @_;
	my $name = $server->{name} || $server->{ip};
	$servers_displayed{$name} ||= do {
	    my $w = $tree->insert_node(undef, undef, [$name], 5, (undef) x 4, 0, 0);
	    my_gtk::ctree_set_icon($tree, $w, @{$icons{server}});
	    $wservers{$w} = $server;
	    $w;
	};
    };

    my $add_exports = sub {
	my ($node) = @_;
	$tree->expand($node);
	foreach ($kind->find_exports($wservers{$node} || die '')) {
	    my $w = $tree->insert_node($node, undef, [$kind->to_string($_)], 5, (undef) x 4, 1, 0);
	    set_export_icon(find_fstab_entry($kind, $_), $w);
	    $wexports{$w->{_gtk}} = $_;
	}
    };

    my $click_here = $tree->insert_node(undef, undef, [_("click here")], 5, (undef) x 4, 0, 0);

    foreach (uniq(map { ($kind->from_dev($_->{device}))[0] } @{$kind->{val}})) {
	my $node = $add_server->({ name => $_ });
	$add_exports->($node);
    }

    $tree->signal_connect(tree_select_row => sub { 
	my $curr = $_[1];
	$inside and return;
	$inside = 1;
	if ($curr->row->is_leaf) {
	    $current_leaf = $curr;
	    $current_entry = find_fstab_entry($kind, $wexports{$curr->{_gtk}} || die(''), 'add');
	} else {
	    if (!$curr->row->children) {
		gtkset_mousecursor_wait($tree->window);
		my_gtk::flush();
		$tree->freeze;
		if ($curr == $click_here) {
		    $add_server->($_) foreach sort { $a->{name} cmp $b->{name} } $kind->find_servers;
		    $tree->remove_node($click_here);
		} else {
		    $add_exports->($curr);
		}
		$tree->thaw;
		gtkset_mousecursor_normal($tree->window);
	    }
	    $current_entry = undef;
	}
	update($kind);
	$inside = 0;
    });
    $tree;
}

sub add_smbnfs {
    my ($widget, $kind) = @_;
    die if $kind->{main_box};

    $kind->{display_box} = createScrolledWindow(import_ctree($kind));
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
    $current_entry = undef;
    update($kind);
    $kind;
}

sub nfs2kind {
    network::nfs->new({ type => 'nfs', name => 'NFS', val => $all_hds->{nfss}, no_auto => 1 });
}

sub smb2kind {
    network::smb->new({ type => 'smb', name => 'Samba', val => $all_hds->{smbs}, no_auto => 1 });
}


1;
