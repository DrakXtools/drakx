package diskdrake::smbnfs_gtk;

use diagnostics;
use strict;

use fs::get;
use diskdrake::interactive;
use common;
use interactive;
use fs::remote::smb;
use fs::remote::nfs;
use mygtk3 qw(gtknew gtkset);
use ugtk3 qw(:helpers :wrappers :create);

my ($all_hds, $in, $tree_model, $current_entry, $current_leaf, %icons);

sub main {
    ($in, $all_hds, my $type) = @_;
    my ($kind) = $type eq 'smb' ? smb2kind() : nfs2kind();
    $kind->check($in) or return;

    my $w = ugtk3->new(N("Partitioning"));

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
    try_($kind, $name, \&$f, @args);
}
sub try_ {
    my ($kind, $name, $f, @args) = @_;
    eval { $f->($in, @args, $all_hds) };
    if (my $err = $@) {
	$in->ask_warn(N("Error"), formatError($err));
    }
    update($kind);
    Gtk3->main_quit if member($name, 'Cancel', 'Done');
}

sub raw_hd_options {
    my ($in, $raw_hd) = @_;
    diskdrake::interactive::Options($in, {}, $raw_hd, fs::get::empty_all_hds());
}
sub raw_hd_mount_point {
    my ($in, $raw_hd) = @_;
    my ($default) = $raw_hd->{device} =~ m|([^/]+)$|;
    $default =~ s/\s+/-/g;
    diskdrake::interactive::Mount_point_raw_hd($in, $raw_hd, $all_hds, "/mnt/$default");
}

sub per_entry_info_box {
    my ($box, $kind, $entry) = @_;
    my $info = $entry ? diskdrake::interactive::format_raw_hd_info($entry) : '';
    $kind->{per_entry_info_box}->destroy if $kind->{per_entry_info_box};
    gtkpack($box, $kind->{per_entry_info_box} = gtknew('Frame', text => N("Details"), child => gtknew('Label', text => $info, justify => 'left')));
}

sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->destroy foreach $box->get_children;

    my @buttons;

    push @buttons, map {
	  my $s = $_;
	  gtknew('Button', text => translate($s), clicked => sub { try($kind, $s, {}, $entry) });
      } (if_($entry->{isMounted}, N_("Unmount")),
	 if_($entry->{mntpoint} && !$entry->{isMounted}, N_("Mount"))) if $entry;

    my @l = (
	     if_($entry, N_("Mount point") => \&raw_hd_mount_point),
	     if_($entry && $entry->{mntpoint}, N_("Options") => \&raw_hd_options),
	     N_("Cancel") => sub {},
	     N_("Done") => \&done,
	    );
    push @buttons, map {
        my ($txt, $f) = @$_;
        $f ? gtknew('Button', text => translate($txt), clicked => sub { try_($kind, $txt, $f, $entry) })
          : gtknew('Label', text => "");
    } group_by2(@l);
    
    gtkadd($box, gtknew('HBox', children_loose => \@buttons));
}

sub done {
    my ($in) = @_;
    diskdrake::interactive::Done($in, $all_hds);
}

sub export_icon {
    my ($entry) = @_;
    $entry ||= {};
    $icons{$entry->{isMounted} ? 'mounted' : $entry->{mntpoint} ? 'has_mntpoint' : 'default'};
}

sub update {
    my ($kind) = @_;
    per_entry_action_box($kind->{action_box}, $kind, $current_entry);
    per_entry_info_box($kind->{info_box}, $kind, $current_entry);
    $tree_model->set($current_leaf, 0 => export_icon($current_entry)) if $current_entry;
}

sub find_fstab_entry {
    my ($kind, $e, $b_add_or_not) = @_;

    my $fs_entry = $kind->to_fstab_entry($e);

    if (my $fs_entry_ = find { $fs_entry->{device} eq $_->{device} } @{$kind->{val}}) {
	$fs_entry_;
    } elsif ($b_add_or_not) {
	push @{$kind->{val}}, $fs_entry;
	$fs_entry;
    } else {
	undef;
    }
}

sub import_tree {
    my ($kind, $info_box) = @_;
    my (%servers_displayed, %wservers, %wexports);

    $tree_model = Gtk3::TreeStore->new("Gtk3::Gdk::Pixbuf", "Glib::String");
    my $tree = Gtk3::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');

    my $col = Gtk3::TreeViewColumn->new;
    $col->pack_start(my $pixrender = Gtk3::CellRendererPixbuf->new, 0);
    $col->add_attribute($pixrender, 'pixbuf', 0);
    $col->pack_start(my $texrender = Gtk3::CellRendererText->new, 1);
    $col->add_attribute($texrender, 'text', 1);
    $tree->append_column($col);

    $tree->set_headers_visible(0);

    foreach ('default', 'server', 'has_mntpoint', 'mounted') {
	$icons{$_} = gtknew('Pixbuf', file => "smbnfs_$_");
    }

    my $add_server = sub {
	my ($server) = @_;
	my $identifier = $server->{ip} || $server->{name};
	my $name = $server->{name} || $server->{ip};
	$servers_displayed{$identifier} ||= do {
	    my $w = $tree_model->append_set(undef, [ 0 => $icons{server}, 1 => $name ]);
	    $wservers{$tree_model->get_path_str($w)} = $server;
	    $w;
	};
    };

    my $find_exports; $find_exports = sub {
	my ($server) = @_;
	my @l = eval { $kind->find_exports($server) };
	return @l if !$@;

	if ($server->{username}) {
	    $in->ask_warn('', N("Cannot login using username %s (bad password?)", $server->{username}));
	    fs::remote::smb::remove_bad_credentials($server);
	} else {
	    if (my @l = fs::remote::smb::authentications_available($server)) {
		my $user = $in->ask_from_list_(N("Domain Authentication Required"),
					       N("Which username"), [ @l, N_("Another one") ]) or return;
		if ($user ne 'Another one') {
		    fs::remote::smb::read_credentials($server, $user);
		    goto $find_exports;
		}
	    }
	}

	if ($in->ask_from(N("Domain Authentication Required"),
		      N("Please enter your username, password and domain name to access this host."),
		      [ 
		       { label => N("Username"), val => \$server->{username} },
		       { label => N("Password"), val => \$server->{password}, hidden => 1 },
		       { label => N("Domain"), val => \$server->{domain} },
		      ])) {
	    goto $find_exports;
	} else {
	    delete $server->{username};
	    ();
	}	
    };

    my $add_exports = sub {
	my ($node) = @_;

	my $path = $tree_model->get_path($node);
	$tree->expand_row($path, 0);

	foreach ($find_exports->($wservers{$tree_model->get_path_str($node)} || return)) { #- cannot die here since insert_node provoque a tree_select_row before the %wservers is filled
	    my $s = $kind->to_string($_);
	    my $w = $tree_model->append_set($node, [ 0 => export_icon(find_fstab_entry($kind, $_)), 
						     1 => $s ]);
	    $wexports{$tree_model->get_path_str($w)} = $_;
	}
    };

    { 
	my $search = gtknew('Button', text => N("Search servers"));
	gtkpack__($info_box, 
		  gtksignal_connect($search,
				    clicked => sub {
					$add_server->($_) foreach sort { $a->{name} cmp $b->{name} } $kind->find_servers;
					gtkset($search, text => N("Search for new servers"));
				    }));
    }

    foreach (uniq(map { ($kind->from_dev($_->{device}))[0] } @{$kind->{val}})) {
	my $node = $add_server->({ name => $_ });
	$add_exports->($node);
    }

    $tree->get_selection->signal_connect(changed => sub {
	my ($_model, $curr) = $_[0]->get_selected;
	$curr or return;

	if ($tree_model->iter_parent($curr)) {
	    $current_leaf = $curr;
	    $current_entry = find_fstab_entry($kind, $wexports{$tree_model->get_path_str($curr)} || die(''), 'add');
	} else {
	    if (!$tree_model->iter_has_child($curr)) {
		gtkset_mousecursor_wait($tree->get_window);
		ugtk3::flush();
		$add_exports->($curr);		
		gtkset_mousecursor_normal($tree->get_window);
	    }
	    $current_entry = undef;
	}
	update($kind);
    });
    $tree;
}

sub add_smbnfs {
    my ($widget, $kind) = @_;
    die if $kind->{main_box};

    $kind->{info_box} = gtknew('VBox');
    $kind->{display_box} = gtknew('ScrolledWindow', child => import_tree($kind, $kind->{info_box}));
    $kind->{action_box} = gtknew('HBox');
    $kind->{main_box} =
      gtknew('VBox', spacing => 7, children => [
	       1, gtknew('HBox', spacing => 7, children_loose => [
			  gtkset($kind->{display_box}, width => 200),
			  $kind->{info_box} ]),
	       0, $kind->{action_box},
	     ]);

    $widget->add($kind->{main_box});
    $current_entry = undef;
    update($kind);
    $kind;
}

sub nfs2kind() {
    fs::remote::nfs->new({ type => 'nfs', name => 'NFS', val => $all_hds->{nfss}, no_auto => 1 });
}

sub smb2kind() {
    fs::remote::smb->new({ type => 'smb', name => 'Samba', val => $all_hds->{smbs}, no_auto => 1 });
}


1;
