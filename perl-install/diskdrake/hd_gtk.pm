package diskdrake::hd_gtk; # $Id$

use diagnostics;
use strict;

use common;
use resize_fat::main;
use ugtk2 qw(:helpers :wrappers :create);
use partition_table qw(:types);
use partition_table::raw;
use detect_devices;
use diskdrake::interactive;
use run_program;
use loopback;
use devices;
use raid;
use any;
use log;
use fsedit;
use fs;

my ($width, $height, $minwidth) = (400, 50, 5);
my ($all_hds, $in, $do_force_reload, $current_kind, $current_entry, $update_all);
my ($w, @notebook, $done_button);

=begin


=head1 SYNOPSYS

struct {
  string name      # which is displayed in tab of the notebook
  bool no_auto     # wether the kind can disappear after creation
  string type      # one of { 'hd', 'raid', 'lvm', 'loopback', 'removable', 'nfs', 'smb' }
  hd | hd_lvm | part_raid[] | part_loopback[] | raw_hd[]  val

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
    ($in, $all_hds, my $nowizard, $do_force_reload) = @_;

    @notebook = ();

    local $in->{grab} = 1;

    $w = ugtk2->new('DiskDrake');
    my $rc = "/usr/share/libDrakX/diskdrake.rc";
    -r $rc or $rc = dirname(__FILE__) . "/../diskdrake.rc";
    -r $rc or $rc = dirname(__FILE__) . "/../share/diskdrake.rc";
    Gtk2::Rc->parse($rc);

    # TODO
#    is_empty_array_ref($all_hds->{raids}) or raid::stopAll;
#    updateLoopback();

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,7),
		    0, filesystems_button_box(),
		    1, (my $notebook_widget = Gtk2::Notebook->new),
		    0, (my $per_kind_action_box = Gtk2::HBox->new(0,0)),
		    0, (my $general_action_box  = Gtk2::HBox->new(0,0)),
		   ),
	  );
    my $lock;
    $update_all = sub {
	$lock and return;
	$lock = 1;
	partition_table::assign_device_numbers($_) foreach fsedit::all_hds($all_hds);
	create_automatic_notebooks($notebook_widget);
	general_action_box($general_action_box, $nowizard);
	per_kind_action_box($per_kind_action_box, $current_kind);
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
    $w->sync;
    $done_button->grab_focus;
    $ugtk2::pop_it = 1;
    $in->ask_okcancel(N("Read carefully!"), N("Please make a backup of your data first"), 1) or return
      if $::isStandalone;
    $in->ask_warn('', 
N("If you plan to use aboot, be carefull to leave a free space (2048 sectors is enough)
at the beginning of the disk")) if arch() eq 'alpha' and !$::isEmbedded;

    $w->main;
}

sub try {
    my ($name, @args) = @_;
    my $f = $diskdrake::interactive::{$name} or die "unknown function $name";
    try_($name, \&{$f}, @args);
}
sub try_ {
    my ($name, $f, @args) = @_;

    fsedit::undo_prepare($all_hds) if $name ne 'Undo';

    my $v = eval { $f->($in, @args, $all_hds) };
    if (my $err = $@) {
	$in->ask_warn(N("Error"), formatError($err));
    }
    if ($v eq 'force_reload') {	
	$all_hds = $do_force_reload->();
    }

    $current_entry = '' if !diskdrake::interactive::is_part_existing($current_entry, $all_hds);
    $update_all->();

    if ($v && member($name, 'Done', 'Wizard')) {
	$::isEmbedded ? kill('USR1', $::CCPID) : Gtk2->main_quit; 
    }
}

################################################################################
# generic: helpers
################################################################################
sub add_kind2notebook {
    my ($notebook_widget, $kind) = @_;
    die if $kind->{main_box};

    $kind->{display_box} = gtkset_size_request(Gtk2::HBox->new(0,0), $width, $height);
    $kind->{action_box} = gtkset_size_request(Gtk2::VBox->new(0,0), 150, 180);
    $kind->{info_box} = Gtk2::VBox->new(0,0);
    $kind->{main_box} =
      gtkpack_(Gtk2::VBox->new(0,7),
	       0, $kind->{display_box},
	       1, gtkpack_(Gtk2::HBox->new(0,7),
			   0, $kind->{action_box},
			   1, $kind->{info_box}));
    ugtk2::add2notebook($notebook_widget, $kind->{name}, $kind->{main_box});
    push @notebook, $kind;
    $kind;
}

sub general_action_box {
    my ($box, $nowizard) = @_;
    $_->widget->destroy foreach $box->children;
    my @actions = (if_($::isInstall && !$nowizard, N_("Wizard")), 
		   diskdrake::interactive::general_possible_actions($in, $all_hds), 
		   N_("Done"));
    foreach my $s (@actions) {
	my $button = Gtk2::Button->new(translate($s));
	$done_button = $button if $s eq 'Done';
	gtkadd($box, gtksignal_connect($button, clicked => sub { try($s) }));
    }
}
sub per_kind_action_box {
    my ($box, $kind) = @_;
    $_->widget->destroy foreach $box->children;

    $kind->{type} =~ /hd|lvm/ or return;

    foreach my $s (diskdrake::interactive::hd_possible_actions($in, kind2hd($kind), $all_hds)) {
	gtkadd($box, 
	       gtksignal_connect(Gtk2::Button->new(translate($s)),
				 clicked => sub { try($s, kind2hd($kind)) }));
    }
}
sub per_entry_action_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;

    if ($entry) {
	my @buttons = map { 
	    my $s = $_;
	    my $w = Gtk2::Button->new(translate($s));
	    $w->signal_connect(clicked => sub { try($s, kind2hd($kind), $entry) });
	    $w;
	} diskdrake::interactive::part_possible_actions($in, kind2hd($kind), $entry, $all_hds);

	gtkadd($box, gtkadd(Gtk2::Frame->new(N("Choose action")),
			    create_scrolled_window(gtkpack__(Gtk2::VBox->new(0,0), @buttons)))) if @buttons;
    } else {
	my $txt = !$::isStandalone && fsedit::is_one_big_fat($all_hds->{hds}) ?
N("You have one big FAT partition
(generally used by MicroSoft Dos/Windows).
I suggest you first resize that partition
(click on it, then click on \"Resize\")") : N("Please click on a partition");
	gtkpack($box, gtktext_insert(Gtk2::TextView->new, $txt));
    }
}

sub per_entry_info_box {
    my ($box, $kind, $entry) = @_;
    $_->widget->destroy foreach $box->children;
    my $info;
    if ($entry) {
	$info = diskdrake::interactive::format_part_info(kind2hd($kind), $entry);
    } elsif ($kind->{type} =~ /hd|lvm/) {
	$info = diskdrake::interactive::format_hd_info($kind->{val});
    }
    gtkpack($box, gtkadd(Gtk2::Frame->new(N("Details")), gtkset_justify(Gtk2::Label->new($info), 'left')));
}

sub current_kind_changed {
    my ($_in, $kind) = @_;

    $_->widget->destroy foreach $kind->{display_box}->children;

    my $v = $kind->{val};
    my @parts = 
      $kind->{type} eq 'raid' ? grep { $_ } @$v :
      $kind->{type} eq 'loopback' ? @$v : fsedit::get_fstab_and_holes($v);
    my $totalsectors = 
      $kind->{type} =~ /raid|loopback/ ? sum(map { $_->{size} } @parts) : $v->{totalsectors};
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
    $may_add->(raid2kind()) if grep { $_ } @{$all_hds->{raids}};
    $may_add->(loopback2kind()) if @{$all_hds->{loopbacks}};

    @notebook = grep_index {
	my $b = $_->{marked} or $notebook_widget->remove_page($::i);
	$b;
    } @notebook;
    @notebook or die N("No hard drives found");
}

################################################################################
# parts: helpers
################################################################################
sub create_buttons4partitions {
    my ($kind, $totalsectors, @parts) = @_;

    $width = max($width, 0.9 * second($w->{window}->window->get_size)) if $w->{window}->window;

    my $ratio = $totalsectors ? ($width - @parts * $minwidth) / $totalsectors : 1;
    while (1) {
	my $totalwidth = sum(map { $_->{size} * $ratio + $minwidth } @parts);
	$totalwidth <= $width and last;
	$ratio /= $totalwidth / $width * 1.1;
    }

    foreach my $entry (@parts) {
	my $w = Gtk2::Button->new($entry->{mntpoint} || '') or die '';
	$w->signal_connect(focus_in_event     => sub { current_entry_changed($kind, $entry) });
	$w->signal_connect(button_press_event => sub { current_entry_changed($kind, $entry) });
	$w->signal_connect(key_press_event => sub {
	    my (undef, $event) = @_;
	    member('control-mask', @{$event->state}) or return; 
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
	$w->set_name("PART_" . type2name($entry->{type}));
	$w->set_size_request($entry->{size} * $ratio + $minwidth, 0);
	gtkpack__($kind->{display_box}, $w);
	$w->grab_focus if $current_entry && fsedit::is_same_part($current_entry, $entry);
    }
}


################################################################################
# disks: helpers
################################################################################
sub current_hd { 
    $current_kind->{type} eq 'hd' or die 'current_hd called but $current_kind is not an hd';
    $current_kind->{val};
}
sub current_part {
    current_hd();
    $current_entry;
}

sub kind2hd {
    my ($kind) = @_;
    $kind->{type} =~ /hd|lvm/ ? $kind->{val} : {}
}

sub hd2kind {
    my ($hd) = @_;
    { type => 'hd', name => $hd->{device}, val => $hd };
}

sub filesystems_button_box() {
    my @types = (N_("Ext2"), N_("Journalised FS"), N_("Swap"), arch() =~ /sparc/ ? N_("SunOS") : arch() eq "ppc" ? N_("HFS") : N_("FAT"),
		 N_("Other"), N_("Empty"));
    my %name2type = (Ext2 => 0x83, 'Journalised FS' => 0x483, Swap => 0x82, Other => 1, FAT => 0xb, HFS => 0x402);

    gtkpack(Gtk2::HBox->new(0,0), 
	    N("Filesystem types:"),
	    map { my $w = Gtk2::Button->new(translate($_));
		  my $t = $name2type{$_};
		  $w->signal_connect(clicked => sub { try_('', \&createOrChangeType, $t, current_hd(), current_part()) });
		  $w->can_focus(0);
		  $w->set_name($_); 
		  $w;
	    } @types);
}

sub createOrChangeType {
    my ($in, $type, $hd, $part, $all_hds) = @_;

    $part ||= !fsedit::get_fstab($hd) && 
              { type => 0, start => 1, size => $hd->{totalsectors} - 1 };
    $part or return;
    if ($type == 1) {
	$in->ask_warn('', N("Use ``%s'' instead", $part->{type} ? N("Type") : N("Create")));
    } elsif (!$type) {
	$in->ask_warn('', N("Use ``%s'' instead", N("Delete"))) if $part->{type};
    } elsif ($part->{type}) {
	return if $type == $part->{type};
	$in->ask_warn('', isBusy($part) ? N("Use ``Unmount'' first") : N("Use ``%s'' instead", N("Type")));
    } else {
	$part->{type} = $type;
	diskdrake::interactive::Create($in, $hd, $part, $all_hds);
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
sub raid2kind {
    { type => 'raid', name => 'raid', val => $all_hds->{raids} };
}

################################################################################
# loopbacks: helpers
################################################################################
sub loopback2kind {
    { type => 'loopback', name => 'loopback', val => $all_hds->{loopbacks} };
}

1;
