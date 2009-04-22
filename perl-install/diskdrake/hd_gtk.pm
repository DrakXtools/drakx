package diskdrake::hd_gtk; # $Id$

use diagnostics;
use strict;

use common;
use mygtk2 qw(gtknew);
use ugtk2 qw(:helpers :wrappers :create);
use partition_table;
use fs::type;
use detect_devices;
use diskdrake::interactive;
use run_program;
use devices;
use log;
use fsedit;
use feature qw(state);

my ($width, $height, $minwidth) = (400, 50, 5);
my ($all_hds, $in, $do_force_reload, $current_kind, $current_entry, $update_all);
my ($w, @notebook, $done_button);

=begin


=head1 SYNOPSYS

struct {
  string name      # which is displayed in tab of the notebook
  bool no_auto     # wether the kind can disappear after creation
  string type      # one of { 'hd', 'raid', 'lvm', 'loopback', 'removable', 'nfs', 'smb' }
  hd | hd_lvm | part_raid[] | part_dmcrypt[] | part_loopback[] | raw_hd[]  val

  # 
  widget main_box
  widget display_box
  widget action_box
  widget info_box
} current_kind

part current_entry

notebook current_kind[]

=cut

sub main {
    ($in, $all_hds, $do_force_reload) = @_;

    @notebook = ();

    local $in->{grab} = 1;

    $w = ugtk2->new(N("Partitioning"));
    $::main_window = $w->{real_window} if !$::isEmbedded && !$::isInstall;
    my $rc = "/usr/share/libDrakX/diskdrake.rc";
    -r $rc or $rc = dirname(__FILE__) . "/../diskdrake.rc";
    -r $rc or $rc = dirname(__FILE__) . "/../share/diskdrake.rc";
    Gtk2::Rc->parse($rc);

    # TODO
#    is_empty_array_ref($all_hds->{raids}) or raid::stopAll;
#    updateLoopback();

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,7),
		    0, gtknew(($::isInstall ? ('Title1', 'label') : ('Label_Left', 'text'))
                                => N("Click on a partition, choose a filesystem type then choose an action"),
                              # workaround infamous 6 years old gnome bug #101968:
                              width => mygtk2::get_label_width()
                            ),
		    1, (my $notebook_widget = Gtk2::Notebook->new),
		    0, (my $per_kind_action_box = gtknew('HButtonBox', layout => 'edge')),
		    0, (my $per_kind_action_box2 = gtknew('HButtonBox', layout => 'end')),
		    0, Gtk2::HSeparator->new,
		    0, (my $general_action_box  = gtknew('HBox', spacing => 5)),
		   ),
	  );
    my ($lock, $initializing) = (undef, 1);
    $update_all = sub {
	state $not_first;
	return if $initializing && $not_first;
	$not_first = 1;
	$lock and return;
	$lock = 1;
	partition_table::assign_device_numbers($_) foreach fs::get::hds($all_hds);
	create_automatic_notebooks($notebook_widget);
	general_action_box($general_action_box);
	per_kind_action_box($per_kind_action_box, $per_kind_action_box2, $current_kind);
	current_kind_changed($in, $current_kind);
	current_entry_changed($current_kind, $current_entry);
	$lock = 0;
    };
    create_automatic_notebooks($notebook_widget);

    $notebook_widget->signal_connect(switch_page => sub {
	$current_kind = $notebook[$_[2]];
	$current_entry = '';
	$update_all->();
    });
    # ensure partitions bar is properlyz size on first display:
    $notebook_widget->signal_connect(realize => $update_all);
    $w->sync;
    $done_button->grab_focus;
    $in->ask_from_list_(N("Read carefully"), N("Please make a backup of your data first"), 
			[ N_("Exit"), N_("Continue") ], N_("Continue")) eq N_("Continue") or return
      if $::isStandalone;

    undef $initializing;
    $w->main;
}

sub try {
    my ($name, @args) = @_;
    my $f = $diskdrake::interactive::{$name} or die "unknown function $name";
    try_($name, \&$f, @args);
}
sub try_ {
    my ($name, $f, @args) = @_;

    my $v = eval { $f->($in, @args, $all_hds) };
    if (my $err = $@) {
	$in->ask_warn(N("Error"), formatError($err));
    }
    if ($v eq 'force_reload') {	
	$all_hds = $do_force_reload->();
    }

    $current_entry = '' if !diskdrake::interactive::is_part_existing($current_entry, $all_hds);
    $update_all->();

    Gtk2->main_quit if $v && member($name, 'Done');
}

sub get_action_box_size() {
    $::isStandalone ? 200 : 150, $::isEmbedded ? 150 : 180;
}

################################################################################
# generic: helpers
################################################################################
sub add_kind2notebook {
    my ($notebook_widget, $kind) = @_;
    die if $kind->{main_box};

    $kind->{display_box} = gtkset_size_request(Gtk2::HBox->new(0,0), $width, $height);
    $kind->{action_box} = gtkset_size_request(Gtk2::VBox->new(), get_action_box_size());
    $kind->{info_box} = Gtk2::VBox->new(0,0);
    my $box =
      gtkpack_(Gtk2::VBox->new(0,7),
	       0, $kind->{display_box},
	       0, filesystems_button_box(),
	       1, $kind->{info_box});
    $kind->{main_box} = gtknew('HBox', spacing => 5, children => [
        1, $box,
        0, $kind->{action_box},
    ]);
    ugtk2::add2notebook($notebook_widget, $kind->{name}, $kind->{main_box});
    push @notebook, $kind;
    $kind;
}

sub interactive_help() {
    if ($::isInstall) {
        $in->display_help({ interactive_help_id => 'diskdrake' }, $w);
    } else {
        require run_program;
        run_program::raw({ detach => 1 }, 'drakhelp', '--id', 'diskdrake');
    }
}

sub general_action_box {
    my ($box) = @_;
    $_->destroy foreach $box->get_children;

    my $box_start = gtknew('HButtonBox', layout => 'start', children_tight => [ 
        gtknew('Install_Button', text => N("Help"), clicked => \&interactive_help)
    ]);

    my @actions = (
		   diskdrake::interactive::general_possible_actions($in, $all_hds), 
		   N_("Done"));
    my $box_end = gtknew('HButtonBox', layout => 'end', spacing => 5);
    foreach my $s (@actions) {
	my $button = Gtk2::Button->new(translate($s));
	$done_button = $button if $s eq 'Done';
	gtkadd($box_end, gtksignal_connect($button, clicked => sub { try($s) }));
    }
    gtkadd($box, $box_start, $box_end);
}
sub per_kind_action_box {
    my ($box, $box2, $kind) = @_;
    $_->destroy foreach $box->get_children, $box2->get_children;

    $kind->{type} =~ /hd|lvm/ or return;

    foreach my $s (diskdrake::interactive::hd_possible_actions_base($in, kind2hd($kind), $all_hds)) {
	gtkadd($box, 
	       gtksignal_connect(Gtk2::Button->new(translate($s)),
				 clicked => sub { try($s, kind2hd($kind)) }));
    }
    foreach my $s (diskdrake::interactive::hd_possible_actions_extra($in, kind2hd($kind), $all_hds)) {
	gtkadd($box2, 
	       gtksignal_connect(Gtk2::Button->new(translate($s)),
				 clicked => sub { try($s, kind2hd($kind)) }));
    }
}
sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->destroy foreach $box->get_children;

    if ($entry) {
	my @buttons = map { 
	    my $s = $_;
	    my $w = Gtk2::Button->new(translate($s));
	    $w->signal_connect(clicked => sub { try($s, kind2hd($kind), $entry) });
	    $w;
	} diskdrake::interactive::part_possible_actions($in, kind2hd($kind), $entry, $all_hds);

	gtkadd($box, create_scrolled_window(gtkpack__(Gtk2::VBox->new(), @buttons), undef, 'none')) if @buttons;
    } else {
	my $txt = !$::isStandalone && fsedit::is_one_big_fat_or_NT($all_hds->{hds}) ?
N("You have one big Microsoft Windows partition.
I suggest you first resize that partition
(click on it, then click on \"Resize\")") : N("Please click on a partition");
	gtkpack($box, gtktext_insert(Gtk2::TextView->new, $txt));
    }
}

sub per_entry_info_box {
    my ($box, $kind, $entry) = @_;
    $_->destroy foreach $box->get_children;
    my $info;
    if ($entry) {
	$info = diskdrake::interactive::format_part_info(kind2hd($kind), $entry);
    } elsif ($kind->{type} =~ /hd|lvm/) {
	$info = diskdrake::interactive::format_hd_info($kind->{val});
    }
    gtkpack($box, gtkadd(gtkcreate_frame(N("Details")), 
                         gtknew('HBox', border_width => 5, children_loose => [
                         gtkset_alignment(gtkset_justify(Gtk2::Label->new($info), 'left'), 0, 0) ])));
}

sub current_kind_changed {
    my ($_in, $kind) = @_;

    $_->destroy foreach $kind->{display_box}->get_children;

    my $v = $kind->{val};
    my @parts = 
      $kind->{type} eq 'raid' ? grep { $_ } @$v :
      $kind->{type} eq 'dmcrypt' ? @$v :
      $kind->{type} eq 'loopback' ? @$v : fs::get::hds_fstab_and_holes($v);
    my $totalsectors = 
      $kind->{type} =~ /raid|dmcrypt|loopback/ ? sum(map { $_->{size} } @parts) : $v->{totalsectors};
    create_buttons4partitions($kind, $totalsectors, @parts);
}

sub current_entry_changed {
    my ($kind, $entry) = @_;
    $current_entry = $entry;
    if ($kind) {
	per_entry_action_box($kind->{action_box}, $kind, $entry);
	per_entry_info_box($kind->{info_box}, $kind, $entry);
    }
}

sub create_automatic_notebooks {
    my ($notebook_widget) = @_;

    $_->{marked} = 0 foreach @notebook;
    my $may_add = sub {
	my ($kind) = @_;
	my @l = grep { $kind->{val} == $_->{val} } @notebook;
	@l > 1 and log::l("weird: create_automatic_notebooks");
	$kind = $l[0] || add_kind2notebook($notebook_widget, $kind);
	$kind->{marked} = 1;
    };
    $may_add->(hd2kind($_)) foreach @{$all_hds->{hds}};
    $may_add->(lvm2kind($_)) foreach @{$all_hds->{lvms}};
    $may_add->(raid2kind()) if @{$all_hds->{raids}};
    $may_add->(dmcrypt2kind()) if @{$all_hds->{dmcrypts}};
    $may_add->(loopback2kind()) if @{$all_hds->{loopbacks}};

    @notebook = grep_index {
	my $b = $_->{marked} or $notebook_widget->remove_page($::i);
	$b;
    } @notebook;
    @notebook or $in->ask_warn(N("Error"), N("No hard drives found")), $in->exit(1);
}

################################################################################
# parts: helpers
################################################################################
sub create_buttons4partitions {
    my ($kind, $totalsectors, @parts) = @_;

    $width = first($w->{window}->window->get_size) - first(get_action_box_size()) - 25 if $w->{window}->window;

    my $ratio = $totalsectors ? ($width - @parts * $minwidth) / $totalsectors : 1;
    while (1) {
	my $totalwidth = sum(map { $_->{size} * $ratio + $minwidth } @parts);
	$totalwidth <= $width and last;
	$ratio /= $totalwidth / $width * 1.1;
    }

    my $current_button;
    my $set_current_button = sub {
	my ($w) = @_;
	$current_button->set_active(0) if $current_button;
	($current_button = $w)->set_active(1);
    };

    foreach my $entry (@parts) {
	my $info = $entry->{mntpoint} || $entry->{device_LABEL};
	$info .= "\n" . ($entry->{size} ? formatXiB($entry->{size}, 512) : N("Unknown")) if $info;
	my $w = Gtk2::ToggleButton->new_with_label($info) or internal_error('new_with_label');
	$w->signal_connect(clicked => sub { 
	    $current_button != $w or return;
	    current_entry_changed($kind, $entry); 
	    $set_current_button->($w);
	});
	$w->signal_connect(key_press_event => sub {
	    my (undef, $event) = @_;
	    member('control-mask', @{$event->state}) && $w == $current_button or return; 
	    my $c = chr $event->keyval;

	    foreach my $s (diskdrake::interactive::part_possible_actions($in, kind2hd($kind), $entry, $all_hds)) {
		${{
		    Create => 'c', Delete => 'd', Format => 'f', 
		    Loopback => 'l', Resize => 'r', Type => 't', 
		    Mount => 'M', Unmount => 'u', 'Mount point' => 'm',
		    'Add to LVM' => 'L', 'Remove from LVM' => 'L', 
		    'Add to RAID' => 'R', 'Remove from RAID' => 'R',
		}}{$s} eq $c or next;

		try($s, kind2hd($kind), $entry);
		last;
	    }
	});
	my @colorized_fs_types = qw(ext3 ext4 xfs swap vfat ntfs ntfs-3g);
	$w->set_name("PART_" . (isEmpty($entry) ? 'empty' : 
				$entry->{fs_type} && member($entry->{fs_type}, @colorized_fs_types) ? $entry->{fs_type} :
				'other'));
	$w->set_size_request($entry->{size} * $ratio + $minwidth, 0);
	gtkpack__($kind->{display_box}, $w);
	if ($current_entry && fsedit::are_same_partitions($current_entry, $entry)) {
	    $set_current_button->($w);
	    $w->grab_focus;
	}
    }
}


################################################################################
# disks: helpers
################################################################################
sub current_hd() { 
    $current_kind->{type} =~ /hd|lvm/ or die 'current_hd called but $current_kind is not an hd ('.$current_kind->{type}.')';
    $current_kind->{val};
}
sub current_part() {
    current_hd();
    $current_entry;
}

sub kind2hd {
    my ($kind) = @_;
    $kind->{type} =~ /hd|lvm/ ? $kind->{val} : bless({}, 'partition_table::raw');
}

sub hd2kind {
    my ($hd) = @_;
    { type => 'hd', name => $hd->{device}, val => $hd };
}

sub filesystems_button_box() {
    my @types = (N_("Ext3"), N_("XFS"), N_("Swap"), arch() =~ /sparc/ ? N_("SunOS") : arch() eq "ppc" ? N_("HFS") : N_("Windows"),
		 N_("Other"), N_("Empty"));
    my %name2fs_type = (Ext3 => 'ext3', Ext4 => 'ext4', 'XFS' => 'xfs', Swap => 'swap', Other => 'other', "Windows" => 'vfat', HFS => 'hfs');

    gtkpack(Gtk2::HBox->new(), 
	    map {
		  my $t = $name2fs_type{$_};
                  my $w = gtknew('Button', text => translate($_), widget_name => 'PART_' . ($t || 'empty'),
                                 tip => N("Filesystem types:"),
                                 clicked => sub { try_('', \&createOrChangeType, $t, current_hd(), current_part()) });
		  $w->can_focus(0);
		  $w;
	    } @types);
}

sub createOrChangeType {
    my ($in, $fs_type, $hd, $part, $all_hds) = @_;

    $part ||= !fs::get::hds_fstab($hd) && 
              { pt_type => 0, start => 1, size => $hd->{totalsectors} - 1 };
    $part or return;
    if ($fs_type eq 'other') {
        if (isEmpty($part)) {
            try('Create', $hd, $part);
        } else {
            try('Type', $hd, $part);
        }
    } elsif (!$fs_type) {
        if (isEmpty($part)) {
            $in->ask_warn(N("Warning"), N("This partition is already empty"));
        } else {
            try('Delete', $hd, $part);
        }
    } elsif (isEmpty($part)) {
	fs::type::set_fs_type($part, $fs_type);
	diskdrake::interactive::Create($in, $hd, $part, $all_hds);
    } else {
	return if $fs_type eq $part->{fs_type};
	$in->ask_warn('', isBusy($part) ? N("Use ``Unmount'' first") : N("Use ``%s'' instead (in expert mode)", N("Type")));
    }
}

################################################################################
# lvms: helpers
################################################################################
sub lvm2kind {
    my ($lvm) = @_;
    { type => 'lvm', name => $lvm->{VG_name}, val => $lvm };
}

################################################################################
# raids: helpers
################################################################################
sub raid2kind() {
    { type => 'raid', name => 'raid', val => $all_hds->{raids} };
}

################################################################################
# loopbacks: helpers
################################################################################
sub dmcrypt2kind() {
    { type => 'dmcrypt', name => 'dmcrypt', val => $all_hds->{dmcrypts} };
}

################################################################################
# loopbacks: helpers
################################################################################
sub loopback2kind() {
    { type => 'loopback', name => 'loopback', val => $all_hds->{loopbacks} };
}

1;
