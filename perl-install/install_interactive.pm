package install_interactive; # $Id$

use diagnostics;
use strict;

use common;
use partition_table qw(:types);
use partition_table::raw;
use detect_devices;
use install_steps;
use install_any;
use devices;
use fsedit;
use log;
use fs;


sub tellAboutProprietaryModules {
    my ($o) = @_;
    my @l = grep { $_ } map { $_->{driver} =~ /^Bad:(.*)/ && $1 } detect_devices::probeall();
    $o->ask_warn('', formatAlaTeX(
N("Some hardware on your computer needs ``proprietary'' drivers to work.
You can find some information about them at: %s", join(", ", @l)))) if @l;
}

#- unit of $mb is mega bytes, min and max are in sectors, this
#- function is used to convert back to sectors count the size of
#- a partition ($mb) given from the interface (on Resize or Create).
#- modified to take into account a true bounding with min and max.
sub from_Mb {
    my ($mb, $min, $max) = @_;
    $mb <= $min >> 11 and return $min;
    $mb >= $max >> 11 and return $max;
    $mb * 2048;
}

sub partition_with_diskdrake {
    my ($o, $all_hds, $nowizard) = @_;
    my $ok; 

    $o->set_help('partition_with_diskdrake');
    do {
	$ok = 1;
	my $do_force_reload = sub {
	    $o->{all_hds} = fsedit::empty_all_hds();
	    install_any::getHds($o, $o);
	    $all_hds = $o->{all_hds};
	    $o->{all_hds};
	};
	require diskdrake::interactive;
	{
	    local $::expert = $::expert;
	    diskdrake::interactive::main($o, $all_hds, $nowizard, $do_force_reload);
	}
	if (delete $o->{wizard}) {
	    partitionWizard($o, 'nodiskdrake') or redo;
	    return 1;
	}
	my @fstab = fsedit::get_all_fstab($all_hds);
	
	unless (fsedit::get_root_(\@fstab)) {
	    $ok = 0;
	    $o->ask_okcancel('', N("You must have a root partition.
For this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'"), 1) or return;
	}
	if (!any { isSwap($_) } @fstab) {
	    $ok &&= $o->ask_okcancel('', N("You don't have a swap partition.\n\nContinue anyway?"));
	}
	if (arch() =~ /ia64/ && !fsedit::has_mntpoint("/boot/efi", $all_hds)) {
	    $o->ask_warn('', N("You must have a FAT partition mounted in /boot/efi"));
	    $ok = '';
	}
    } until $ok;
    1;
}

sub partitionWizardSolutions {
    my ($o, $all_hds) = @_;
    my $hds = $all_hds->{hds};
    my $fstab = [ fsedit::get_all_fstab($all_hds) ];
    my @wizlog;
    my (%solutions);

    my $min_linux = 400 << 11;
    my $max_linux = 3000 << 11;
    my $min_swap = 50 << 11;
    my $max_swap = 300 << 11;
    my $min_freewin = 100 << 11;

    # each solution is a [ score, text, function ], where the function retunrs true if succeeded

    my @hds_rw = grep { !$_->{readonly} } @$hds;
    my @hds_can_add = grep { $_->can_raw_add } @hds_rw;
    if (fsedit::free_space(@hds_can_add) > $min_linux) {
	$solutions{free_space} = [ 20, N("Use free space"), sub { fsedit::auto_allocate($all_hds); 1 } ]
    } else { 
	push @wizlog, N("Not enough free space to allocate new partitions") . ": " .
	  (@hds_can_add ? 
	   fsedit::free_space(@hds_can_add) . " < $min_linux" :
	   "no harddrive on which partitions can be added");
    }

    if (my @truefs = grep { isTrueFS($_) } @$fstab) {
	#- value twice the ext2 partitions
	$solutions{existing_part} = [ 6 + @truefs + @$fstab, N("Use existing partitions"), sub { $o->ask_mntpoint_s($fstab) } ]
    } else {
	push @wizlog, N("There is no existing partition to use");
    }

    my @fats = grep { isFat($_) } @$fstab;
    fs::df($_) foreach @fats;
    if (my @ok_forloopback = sort { $b->{free} <=> $a->{free} } grep { $_->{free} > $min_linux + $min_swap + $min_freewin } @fats) {
	$solutions{loopback} = 
	  [ -10 - @fats, N("Use the Windows partition for loopback"), 
	    sub { 
		my ($s_root, $s_swap);
		my $part = $o->ask_from_listf('', N("Which partition do you want to use for Linux4Win?"), \&partition_table::description, \@ok_forloopback) or return;
		$max_swap = $min_swap + 1 if $part->{free} - $max_swap < $min_linux;
		$o->ask_from('', N("Choose the sizes"), [ 
		   { label => N("Root partition size in MB: "), val => \$s_root, min => $min_linux >> 11, max => min($part->{free} - $max_swap, $max_linux) >> 11, type => 'range' },
		   { label => N("Swap partition size in MB: "), val => \$s_swap, min => $min_swap >> 11,  max => $max_swap >> 11, type => 'range' },
		]) or return;
		push @{$part->{loopback}}, 
		  { type =>0x483, loopback_file => '/lnx4win/linuxsys.img', mntpoint => '/',    size => $s_root << 11, loopback_device => $part, notFormatted => 1 },
		  { type => 0x82, loopback_file => '/lnx4win/swapfile',     mntpoint => 'swap', size => $s_swap << 11, loopback_device => $part, notFormatted => 1 };
		fsedit::recompute_loopbacks($all_hds);
		1;
	    } ];
	my @ok_for_resize_fat = grep { !fsedit::part2hd($_, $all_hds)->{readonly} } @ok_forloopback;
	$solutions{resize_fat} = 
	  [ 6 - @fats, N("Use the free space on the Windows partition"),
	    sub {
		$o->set_help('resizeFATChoose');
		my $part = $o->ask_from_listf('', N("Which partition do you want to resize?"), \&partition_table::description, \@ok_for_resize_fat) or return;
		$o->set_help('resizeFATWait');
		my $w = $o->wait_message(N("Resizing"), N("Resizing Windows partition"));
		require resize_fat::main;
		my $resize_fat = eval { resize_fat::main->new($part->{device}, devices::make($part->{device})) };
		$@ and die N("The FAT resizer is unable to handle your partition, 
the following error occured: %s", $@);
		my $min_win = $resize_fat->min_size;
		$part->{size} > $min_linux + $min_swap + $min_freewin + $min_win or die N("Your Windows partition is too fragmented. Please reboot your computer under Windows, run the ``defrag'' utility, then restart the Mandrake Linux installation.");
		$o->ask_okcancel('', N("WARNING!

DrakX will now resize your Windows partition. Be careful:
this operation is dangerous. If you have not already done
so, you should first exit the installation, run scandisk
under Windows (and optionally run defrag), then restart the
installation. You should also backup your data.
When sure, press Ok.")) or return;

		my $mb_size = $part->{size} >> 11;
		$o->ask_from('', N("Which size do you want to keep for Windows on"), [
                   { label => N("partition %s", partition_table::description($part)), val => \$mb_size, min => $min_win >> 11, max => ($part->{size} - $min_linux - $min_swap) >> 11, type => 'range' },
                ]) or return;

		my $size = from_Mb($mb_size, $min_win, $part->{size});

		local *log::l = sub { $w->set(join(' ', @_)) };
		eval { $resize_fat->resize($size) };
		$@ and die N("FAT resizing failed: %s", $@);

		$part->{size} = $size;
		$part->{isFormatted} = 1;
		
		my $hd = fsedit::part2hd($part, $all_hds);
		$hd->{isDirty} = $hd->{needKernelReread} = 1;
		$hd->adjustEnd($part);
		partition_table::adjust_local_extended($hd, $part);
		partition_table::adjust_main_extended($hd);

		fsedit::auto_allocate($all_hds);
		1;
	    } ] if @ok_for_resize_fat;
    } else {
	push @wizlog, N("There is no FAT partition to resize or to use as loopback (or not enough space left)") .
	  @fats ? "\nFAT partitions:" . join('', map { "\n  $_->{device} $_->{free} (" . ($min_linux + $min_swap + $min_freewin) . ")" } @fats) : '';
    }

    if (@$fstab && @hds_rw) {
	$solutions{wipe_drive} =
	  [ 10, fsedit::is_one_big_fat($hds) ? N("Remove Windows(TM)") : N("Erase entire disk"), 
	    sub {
		$o->set_help('takeOverHdChoose');
		my $hd = $o->ask_from_listf('', N("You have more than one hard drive, which one do you install linux on?"),
					    \&partition_table::description, \@hds_rw) or return;
		$o->set_help('takeOverHdConfirm');
		$o->ask_okcancel('', N("ALL existing partitions and their data will be lost on drive %s", partition_table::description($hd))) or return;
		partition_table::raw::zero_MBR($hd);
		fsedit::auto_allocate($all_hds);
		1;
	    } ];
    }

    if (@hds_rw) {
	$solutions{diskdrake} = [ 0, N("Custom disk partitioning"), sub { partition_with_diskdrake($o, $all_hds, 'nowizard') } ];
    }

    $solutions{fdisk} =
      [ -10, N("Use fdisk"), sub { 
	    $o->enter_console;
	    foreach (@$hds) {
		print "\n" x 10, N("You can now partition %s.
When you are done, don't forget to save using `w'", partition_table::description($_));
		print "\n\n";
		my $pid = 0;
		if (arch() =~ /ppc/) {
			$pid = fork() or exec "pdisk", devices::make($_->{device});
		} else {
			$pid = fork() or exec "fdisk", devices::make($_->{device});
		}			
		waitpid($pid, 0);
	    }
	    $o->leave_console;
	    0;
	} ] if $o->{partitioning}{fdisk};

    log::l("partitioning wizard log:\n", (map { ">>wizlog>>$_\n" } @wizlog));
    %solutions;
}

sub partitionWizard {
    my ($o, $nodiskdrake) = @_;

    $o->set_help('doPartitionDisks');

    my %solutions = partitionWizardSolutions($o, $o->{all_hds});
    if ($o->{lnx4win}) {
	if ($solutions{loopback}) {
	    %solutions = (loopback => $solutions{loopback});
	} else {
	    $o->ask_warn('', N("You don't have enough free space on your Windows partition")) if any { isFat($_) } fsedit::get_all_fstab($o->{all_hds});
	}
    }

    delete $solutions{diskdrake} if $nodiskdrake;

    my @solutions = sort { $b->[0] <=> $a->[0] } values %solutions;

    my $level = $::expert ? -9999 : 0;
    my @sol = grep { $_->[0] >= $level } @solutions;

    log::l(''  . "solutions found: " . join('', map { $_->[1] } @sol) . 
	   " (all solutions found: " . join('', map { $_->[1] } @solutions) . ")");

    @solutions = @sol if @sol > 1;
    log::l("solutions: ", int @solutions);
    @solutions or $o->ask_warn('', N("I can't find any room for installing")), die 'already displayed';

    log::l('HERE: ', join(',', map { $_->[1] } @solutions));
    if (my $sol = $o->ask_from_listf('', N("The DrakX Partitioning wizard found the following solutions:"), sub { $_[0][1] }, \@solutions)) {
	log::l("partitionWizard calling solution $sol->[1]");
	my $ok = eval { $sol->[2]->() };
	$@ and $o->ask_warn('', N("Partitioning failed: %s", $@));
	$ok or goto &partitionWizard;
	1;
    } else {
	0;
    }
}

sub upNetwork {
    my ($o, $pppAvoided) = @_;
    my $_w = $o->wait_message('', N("Bringing up the network"));
    install_steps::upNetwork($o, $pppAvoided);
}
sub downNetwork {
    my ($o, $pppOnly) = @_;
    my $_w = $o->wait_message('', N("Bringing down the network"));
    install_steps::downNetwork($o, $pppOnly);
}



1;
