package install_interactive;

use diagnostics;
use strict;

use vars;

use common qw(:common :functional);
use fs;
use fsedit;
use log;
use partition_table qw(:types);
use partition_table_raw;
use detect_devices;
use install_steps;
use devices;
use modules;


sub partition_with_diskdrake {
    my ($o, $hds) = @_;
    my $ok = 1;
    do {
	diskdrake::main($hds, $o->{raid}, interactive_gtk->new, $o->{partitions});
	delete $o->{wizard} and return partitionWizard($o);
	my @fstab = fsedit::get_fstab(@$hds);
	
	unless (fsedit::get_root(\@fstab)) {
	    $ok = 0;
	    $o->ask_okcancel('', _("You must have a root partition.
For this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'"), 1) or return;
	}
	if (!grep { isSwap($_) } @fstab) {
	    $o->ask_warn('', _("You must have a swap partition")), $ok=0 if $::beginner;
	    $ok &&= $::expert || $o->ask_okcancel('', _("You don't have a swap partition\n\nContinue anyway?"));
	}
    } until $ok;
    1;
}

sub partitionWizardSolutions {
    my ($o, $hds, $fstab, $readonly) = @_;
    my @wizlog;
    my (@solutions, %solutions);

    my $min_linux = 500 << 11;
    my $max_linux = 2500 << 11;
    my $min_swap = 50 << 11;
    my $max_swap = 300 << 11;
    my $min_freewin = 100 << 11;

    # each solution is a [ score, text, function ], where the function retunrs true if succeeded

    if (fsedit::free_space(grep { partition_table::can_raw_add($_) } @$hds) > $min_linux and !$readonly) {
	$solutions{free_space} = [ 20, _("Use free space"), sub { fsedit::auto_allocate($hds, $o->{partitions}); 1 } ]
    } else { 
	push @wizlog, _("Not enough free space to allocate new partitions");
    }

    if (@$fstab) {
	my $truefs = grep { isTrueFS($_) } @$fstab;
	#- value twice the ext2 partitions
	$solutions{existing_part} = [ 6 + $truefs + @$fstab, _("Use existing partition"), sub { $o->ask_mntpoint_s($fstab) } ]
    } else {
	push @wizlog, _("There is no existing partition to use");
    }

    my @fats = grep { isFat($_) } @$fstab;
    fs::df($_) foreach @fats;
    if (my @ok_forloopback = sort { $b->{free} <=> $a->{free} } grep { $_->{free} > $min_linux + $min_freewin } @fats) {
	$solutions{loopback} = 
	  [ 5 - @fats, _("Use the FAT partition for loopback"), 
	    sub { 
		my ($s_root, $s_swap);
		my $part = $o->ask_from_listf('', _("Which partition do you want to use to put Linux4Win?"), \&partition_table_raw::description, \@ok_forloopback) or return;
		$o->ask_from_entries_refH('', _("Choose the sizes"), [ 
		   _("Root partition size in MB: ") => { val => \$s_root, min => 1 + ($min_linux >> 11), max => min($part->{free} - 2 * $max_swap - $min_freewin, $max_linux) >> 11, type => 'range' },
		   _("Swap partition size in MB: ") => { val => \$s_swap, min => 1 + ($min_swap >> 11),  max => 2 * $max_swap >> 11, type => 'range' },
		]) or return;
		push @{$part->{loopback}}, 
		  { type => 0x83, loopback_file => '/lnx4win/linuxsys.img', mntpoint => '/',    size => $s_root << 11, device => $part, notFormatted => 1 },
		  { type => 0x82, loopback_file => '/lnx4win/swapfile',     mntpoint => 'swap', size => $s_swap << 11, device => $part, notFormatted => 1 };
		1;
	    } ];
	$solutions{resize_fat} = 
	  [ 6 - @fats, _("Use the free space on the FAT partition"),
	    sub {
		my $part = $o->ask_from_listf('', _("Which partition do you want to resize?"), \&partition_table_raw::description, \@ok_forloopback) or return;
		my $w = $o->wait_message(_("Resizing"), _("Computing FAT filesystem bounds"));
		my $resize_fat = eval { resize_fat::main->new($part->{device}, devices::make($part->{device})) };
		$@ and die _("The FAT resizer is unable to handle your partition, 
the following error occured: %s", $@);
		my $min_win = $resize_fat->min_size;
		$part->{size} > $min_linux + $min_freewin + $min_win or die _("Your windows partition is too fragmented, please run ``defrag'' first");
		$o->ask_okcancel('', _("WARNING!

DrakX will now resize your Windows partition. Be careful: this operation is
dangerous. If you have not already done so, you should first exit the
installation, run scandisk under Windows (and optionally run defrag), then
restart the installation. You should also backup your data.
When sure, press Ok.")) or return;

		my $size = $part->{size};
		$o->ask_from_entries_refH('', _("Which size do you want to keep for windows on"), [
                   _("partition %s", partition_table_raw::description($part)) => { val => \$size, min => 1 + ($min_win >> 11), max => ($part->{size} - $min_linux) >> 11, type => 'range' },
                ]) or return;
		$size <<= 11;

		local *log::l = sub { $w->set(join(' ', @_)) };
		eval { $resize_fat->resize($size) };
		$@ and die _("FAT resizing failed: %s", $@);

		$part->{size} = $size;
		$part->{isFormatted} = 1;
		
		my ($hd) = grep { $_->{device} eq $part->{rootDevice} } @$hds;
		$hd->{isDirty} = $hd->{needKernelReread} = 1;
		$hd->adjustEnd($part);
		partition_table::adjust_local_extended($hd, $part);
		partition_table::adjust_main_extended($hd);

		fsedit::auto_allocate($hds, $o->{partitions});
		1;
	    } ] if !$readonly;
    } else {
	push @wizlog, _("There is no FAT partitions to resize or to use as loopback (or not enough space left)");
    }

    if (@$fstab && !$readonly) {
	require diskdrake;
	$solutions{wipe_drive} =
	  [ 10, fsedit::is_one_big_fat($hds) ? _("Remove Windows(TM)") : _("Take over the hard drive"), 
	    sub {
		my $hd = $o->ask_from_listf('', _("You have more than one hard drive, which one do you install linux on?"),
					    \&partition_table_raw::description, $hds) or return;
		$o->ask_okcancel('', _("All existing partitions and their data will be lost on drive %s", $hd->{device})) or return;
		partition_table_raw::zero_MBR($hd);
		fsedit::auto_allocate($hds, $o->{partitions});
		1;
	    } ];
    }

    if (!$readonly && ref($o) =~ /gtk/) { #- diskdrake only available in gtk for now
	$solutions{diskdrake} = [ 0, _("Use diskdrake"), sub { partition_with_diskdrake($o, $hds) } ];
    }

    $solutions{fdisk} =
      [ -10, _("Use fdisk"), sub { 
	    $o->suspend;
	    foreach (@$hds) {
		print "\n" x 10, _("You can now partition %s.
When you are done, don't forget to save using `w'", partition_table_raw::description($_));
		print "\n\n";
		my $pid = fork or exec "fdisk", devices::make($_->{device});
		waitpid($pid, 0);
	    }
	    $o->resume;
	    0;
	} ] if $o->{partitioning}{fdisk};

    log::l("partitioning wizard log:\n", (map { ">>wizlog>>$_\n" } @wizlog));
    %solutions;
}

sub partitionWizard {
    my ($o) = @_;

    my %solutions = partitionWizardSolutions($o, $o->{hds}, $o->{fstab}, $o->{partitioning}{readonly});

    my @solutions = sort { $b->[0] <=> $a->[0] } values %solutions;

    my $level = $::beginner ? 2 : -9999;
    my @sol = grep { $_->[0] >= $level } @solutions;
    @solutions = @sol if @sol > 1;

    my $ok; while (!$ok) {
	my $sol = $o->ask_from_listf('', _("The DrakX Partitioning wizard found the following solutions:"), sub { $_->[1] }, \@solutions) or redo;
	eval { $ok = $sol->[2]->() };
	die if $@ =~ /setstep/;
	$ok &&= !$@;
	$@ and $o->ask_warn('', _("Partitioning failed: %s", $@));
    }
}

#--------------------------------------------------------------------------------
sub wait_load_module {
    my ($o, $type, $text, $module) = @_;
#-PO: the first %s is the card type (scsi, network, sound,...)
#-PO: the second is the vendor+model name
    $o->wait_message('',
		     [ _("Installing driver for %s card %s", $type, $text),
		       $::beginner ? () : _("(module %s)", $module)
		     ]);
}


sub load_module {
    my ($o, $type) = @_;
    my @options;

    my $m = $o->ask_from_listf('',
#-PO: the %s is the driver type (scsi, network, sound,...)
			       _("Which %s driver should I try?", $type),
			       \&modules::module2text,
			       [ modules::module_of_type($type) ]) or return;
    my $l = modules::module2text($m);
    require modparm;
    my @names = modparm::get_options_name($m);

    if ((@names != 0) && $o->ask_from_list_('',
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $l),
			      [ __("Autoprobe"), __("Specify options") ], "Autoprobe") ne "Autoprobe") {
      ASK:
	if (@names >= 0) {
	    my @l = $o->ask_from_entries('',
_("You may now provide its options to module %s.", $l),
					 \@names) or return;
	    @options = modparm::get_options_result($m, @l);
	} else {
	    @options = split ' ',
	      $o->ask_from_entry('',
_("You may now provide its options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $l),
				 _("Module options:"),
				);
	}
    }
    eval { 
	my $w = wait_load_module($o, $type, $l, $m);
	modules::load($m, $type, @options);
    };
    if ($@) {
	$o->ask_yesorno('',
_("Loading module %s failed.
Do you want to try again with other parameters?", $l), 1) or return;
	goto ASK;
    }
    $l;
}

#------------------------------------------------------------------------------
sub load_thiskind {
    my ($o, $type) = @_;
    my $pcmcia = $o->{pcmcia} if modules::pcmcia_need_config($o->{pcmcia}) && !$::noauto;
    my $w; $w = $o->wait_message(_("PCMCIA"), _("Configuring PCMCIA cards...")) if $pcmcia;
    modules::load_thiskind($type, $pcmcia, sub { $w = wait_load_module($o, $type, @_) });
}


#------------------------------------------------------------------------------
sub setup_thiskind {
    my ($o, $type, $auto, $at_least_one) = @_;

    return if arch() eq "ppc";

    my @l;
    if (!$::noauto) {
	@l = load_thiskind($o, $type);
	if (my @err = grep { $_ } map { $_->{error} } @l) {
	    $o->ask_warn('', join("\n", @err));
	}
	return @l if $auto && (@l || !$at_least_one);
    }
    @l = map { $_->{description} } @l;
    while (1) {
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", @l), $type),
	    _("Do you have another one?") ] :
	  _("Do you have any %s interfaces?", $type);

	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = "Yes";
	$r = $o->ask_from_list_('', $msg, $opt, "No") unless $at_least_one && @l == 0;
	if ($r eq "No") { return @l }
	if ($r eq "Yes") {
	    push @l, load_module($o, $type) || next;
	} else {
	    $o->ask_warn('', [ detect_devices::stringlist() ]);
	}
    }
}

#------------------------------------------------------------------------------
sub upNetwork {
    my ($o, $pppAvoided) = @_;
    my $w = $o->wait_message('', _("Bringing up the network"));
    install_steps::upNetwork($o, $pppAvoided);
}
sub downNetwork {
    my ($o, $pppOnly) = @_;
    my $w = $o->wait_message('', _("Bringing down the network"));
    install_steps::downNetwork($o, $pppOnly);
}



1;
