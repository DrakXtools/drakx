package fs::partitioning_wizard; # $Id$

use diagnostics;
use strict;
use utf8;

use common;
use devices;
use fsedit;
use fs::type;
use fs::mount_point;
use partition_table;
use partition_table::raw;

#- unit of $mb is mega bytes, min and max are in sectors, this
#- function is used to convert back to sectors count the size of
#- a partition ($mb) given from the interface (on Resize or Create).
#- modified to take into account a true bounding with min and max.
sub from_Mb {
    my ($mb, $min, $max) = @_;
    $mb <= to_Mb($min) and return $min;
    $mb >= to_Mb($max) and return $max;
    MB($mb);
}
sub to_Mb {
    my ($size_sector) = @_;
    to_int($size_sector / 2048);
}

sub partition_with_diskdrake {
    my ($in, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab) = @_;
    my $ok; 

    do {
	$ok = 1;
	my $do_force_reload = sub {
            my $new_hds = fs::get::empty_all_hds();
            fs::any::get_hds($new_hds, $fstab, $manual_fstab, $partitioning_flags, $skip_mtab, $in);
            %$all_hds = %$new_hds;
            $all_hds;
	};
	require diskdrake::interactive;
	{
	    local $::expert = 0;
	    diskdrake::interactive::main($in, $all_hds, $do_force_reload);
	}
	my @fstab = fs::get::fstab($all_hds);
	
	unless (fs::get::root_(\@fstab)) {
	    $ok = 0;
	    $in->ask_okcancel(N("Partitioning"), N("You must have a root partition.
For this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'"), 1, 'banner-part') or return;
	}
	if (!any { isSwap($_) } @fstab) {
	    $ok &&= $in->ask_okcancel('', N("You do not have a swap partition.\n\nContinue anyway?"));
	}
	if (arch() =~ /ia64/ && !fs::get::has_mntpoint("/boot/efi", $all_hds)) {
	    $in->ask_warn('', N("You must have a FAT partition mounted in /boot/efi"));
	    $ok = '';
	}
    } until $ok;
    1;
}

sub partitionWizardSolutions {
    my ($in, $all_hds, $all_fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab) = @_;
    my $hds = $all_hds->{hds};
    my $fstab = [ fs::get::fstab($all_hds) ];
    my @wizlog;
    my (%solutions);

    my $min_linux = MB(400);
    my $max_linux = MB(2000);
    my $min_swap = MB(50);
    my $max_swap = MB(300);
    my $min_freewin = MB(100);

    # each solution is a [ score, text, function ], where the function retunrs true if succeeded

    my @hds_rw = grep { !$_->{readonly} } @$hds;
    my @hds_can_add = grep { $_->can_raw_add } @hds_rw;
    if (fs::get::hds_free_space(@hds_can_add) > $min_linux) {
	$solutions{free_space} = [ 20, N("Use free space"), sub { fsedit::auto_allocate($all_hds, $partitions); 1 } ];
    } else { 
	push @wizlog, N("Not enough free space to allocate new partitions") . ": " .
	  (@hds_can_add ? 
	   fs::get::hds_free_space(@hds_can_add) . " < $min_linux" :
	   "no harddrive on which partitions can be added");
    }

    if (my @truefs = grep { isTrueLocalFS($_) } @$fstab) {
	#- value twice the ext2 partitions
	$solutions{existing_part} = [ 6 + @truefs + @$fstab, N("Use existing partitions"), sub { fs::mount_point::ask_mount_points($in, $fstab, $all_hds) } ];
    } else {
	push @wizlog, N("There is no existing partition to use");
    }

    my @fats = grep { $_->{fs_type} eq 'vfat' } @$fstab;
    fs::df($_) foreach @fats;
    if (my @ok_forloopback = sort { $b->{free} <=> $a->{free} } grep { $_->{free} > $min_linux + $min_swap + $min_freewin } @fats) {
	$solutions{loopback} = 
	  [ -10 - @fats, N("Use the Microsoft Windows® partition for loopback"), 
	    sub { 
		my ($s_root, $s_swap);
		my $part = $in->ask_from_listf('', N("Which partition do you want to use for Linux4Win?"), \&partition_table::description, \@ok_forloopback) or return;
		$max_swap = $min_swap + 1 if $part->{free} - $max_swap < $min_linux;
		$in->ask_from('', N("Choose the sizes"), [ 
		   { label => N("Root partition size in MB: "), val => \$s_root, min => to_Mb($min_linux), max => to_Mb(min($part->{free} - $max_swap, $max_linux)), type => 'range' },
		   { label => N("Swap partition size in MB: "), val => \$s_swap, min => to_Mb($min_swap),  max => to_Mb($max_swap), type => 'range' },
		]) or return;
		push @{$part->{loopback}}, 
		  { fs_type => 'ext3', loopback_file => '/lnx4win/linuxsys.img', mntpoint => '/',    size => $s_root * 2048, loopback_device => $part, notFormatted => 1 },
		  { fs_type => 'swap', loopback_file => '/lnx4win/swapfile',     mntpoint => 'swap', size => $s_swap * 2048, loopback_device => $part, notFormatted => 1 };
		fsedit::recompute_loopbacks($all_hds);
		1;
	    } ];
    } else {
	push @wizlog, N("There is no FAT partition to use as loopback (or not enough space left)") .
	  (@fats ? "\nFAT partitions:" . join('', map { "\n  $_->{device} $_->{free} (" . ($min_linux + $min_swap + $min_freewin) . ")" } @fats) : '');
    }

    
    if (my @ok_for_resize_fat = grep { isFat_or_NTFS($_) && !fs::get::part2hd($_, $all_hds)->{readonly} } @$fstab) {
	$solutions{resize_fat} = 
	  [ 6 - @ok_for_resize_fat, N("Use the free space on the Microsoft Windows® partition"),
	    sub {
		my $part = $in->ask_from_listf_raw({ messages => N("Which partition do you want to resize?"),
						    interactive_help_id => 'resizeFATChoose',
						  }, \&partition_table::description, \@ok_for_resize_fat) or return;
		my $hd = fs::get::part2hd($part, $all_hds);
		my $resize_fat = eval {
		    my $pkg = $part->{fs_type} eq 'vfat' ? do { 
			require resize_fat::main;
			'resize_fat::main';
		    } : do {
			require diskdrake::resize_ntfs;
			'diskdrake::resize_ntfs';
		    };
		    $pkg->new($part->{device}, devices::make($part->{device}));
		};
		$@ and die N("The FAT resizer is unable to handle your partition, 
the following error occurred: %s", formatError($@));
		my $min_win = do {
		    my $_w = $in->wait_message(N("Resizing"), N("Computing the size of the Microsoft Windows® partition"));
		    $resize_fat->min_size;
		};
		#- make sure that even after normalizing the size to cylinder boundaries, the minimun will be saved,
		#- this save at least a cylinder (less than 8Mb).
		$min_win += partition_table::raw::cylinder_size($hd);

		$part->{size} > $min_linux + $min_swap + $min_freewin + $min_win or die N("Your Microsoft Windows® partition is too fragmented. Please reboot your computer under Microsoft Windows®, run the ``defrag'' utility, then restart the Mandriva Linux installation.");
		$in->ask_okcancel('', formatAlaTeX(
                                            #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                                            N("WARNING!


Your Microsoft Windows® partition will be now resized.


Be careful: this operation is dangerous. If you have not already done so, you first need to exit the installation, run \"chkdsk c:\" from a Command Prompt under Microsoft Windows® (beware, running graphical program \"scandisk\" is not enough, be sure to use \"chkdsk\" in a Command Prompt!), optionally run defrag, then restart the installation. You should also backup your data.


When sure, press %s.", N("Next")))) or return;

		my $mb_size = to_Mb($part->{size});
		$in->ask_from(N("Partitionning"), N("Which size do you want to keep for Microsoft Windows® on partition %s?", partition_table::description($part)), [
                   { label => N("Size"), val => \$mb_size, min => to_Mb($min_win), max => to_Mb($part->{size} - $min_linux - $min_swap), type => 'range' },
                ]) or return;

		my $oldsize = $part->{size};
		$part->{size} = from_Mb($mb_size, $min_win, $part->{size});

		$hd->adjustEnd($part);

		eval { 
		    my $_w = $in->wait_message(N("Resizing"), N("Resizing Microsoft Windows® partition"));
		    $resize_fat->resize($part->{size});
		};
		if (my $err = $@) {
		    $part->{size} = $oldsize;
		    die N("FAT resizing failed: %s", formatError($err));
		}

		$in->ask_warn('', N("To ensure data integrity after resizing the partition(s), 
filesystem checks will be run on your next boot into Microsoft Windows®")) if $part->{fs_type} ne 'vfat';

		set_isFormatted($part, 1);
		partition_table::will_tell_kernel($hd, resize => $part); #- down-sizing, write_partitions is not needed
		partition_table::adjust_local_extended($hd, $part);
		partition_table::adjust_main_extended($hd);

		fsedit::auto_allocate($all_hds, $partitions);
		1;
	    } ];
    } else {
	push @wizlog, N("There is no FAT partition to resize (or not enough space left)");
    }

    if (@$fstab && @hds_rw) {
	$solutions{wipe_drive} =
	  [ 10, fsedit::is_one_big_fat_or_NT($hds) ? N("Remove Microsoft Windows®") : N("Erase and use entire disk"), 
	    sub {
		my $hd = $in->ask_from_listf_raw({ messages => N("You have more than one hard drive, which one do you install linux on?"),
						  title => N("Partitioning"),
						  icon => 'banner-part',
						  interactive_help_id => 'takeOverHdChoose',
						},
						\&partition_table::description, \@hds_rw) or return;
		$in->ask_okcancel_({ messages => N("ALL existing partitions and their data will be lost on drive %s", partition_table::description($hd)),
				    title => N("Partitioning"),
				    icon => 'banner-part',
				    interactive_help_id => 'takeOverHdConfirm' }) or return;
		partition_table::raw::clear_and_dirty($hd);
		fsedit::auto_allocate($all_hds, $partitions);
		1;
	    } ];
    }

    if (@hds_rw || find { $_->isa('partition_table::lvm') } @$hds) {
	$solutions{diskdrake} = [ 0, N("Custom disk partitioning"), sub {
	    partition_with_diskdrake($in, $all_hds, $all_fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab);
        } ];
    }

    $solutions{fdisk} =
      [ -10, N("Use fdisk"), sub { 
	    $in->enter_console;
	    foreach (@$hds) {
		print "\n" x 10, N("You can now partition %s.
When you are done, do not forget to save using `w'", partition_table::description($_));
		print "\n\n";
		my $pid = 0;
		if (arch() =~ /ppc/) {
			$pid = fork() or exec "pdisk", devices::make($_->{device});
		} else {
			$pid = fork() or exec "fdisk", devices::make($_->{device});
		}			
		waitpid($pid, 0);
	    }
	    $in->leave_console;
	    0;
	} ] if $partitioning_flags->{fdisk};

    log::l("partitioning wizard log:\n", (map { ">>wizlog>>$_\n" } @wizlog));
    %solutions;
}

sub warn_reboot_needed {
    my ($in) = @_;
    $in->ask_warn(N("Partitioning"), N("You need to reboot for the partition table modifications to take place"), icon => 'banner-part');
}

sub main {
    my ($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, $b_nodiskdrake) = @_;

    my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab);

    delete $solutions{diskdrake} if $b_nodiskdrake;

    my @solutions = sort { $b->[0] <=> $a->[0] } values %solutions;

    my @sol = grep { $_->[0] >= 0 } @solutions;

    log::l(''  . "solutions found: " . join('', map { $_->[1] } @sol) . 
	   " (all solutions found: " . join('', map { $_->[1] } @solutions) . ")");

    @solutions = @sol if @sol > 1;
    log::l("solutions: ", int @solutions);
    @solutions or $o->ask_warn(N("Partitioning"), N("I can not find any room for installing"), icon => 'banner-part'), die 'already displayed';

    log::l('HERE: ', join(',', map { $_->[1] } @solutions));
    my $sol;
    $o->ask_from_({ messages => N("The DrakX Partitioning wizard found the following solutions:"),
		    title => N("Partitioning"),
		    icon => 'banner-part',
		    interactive_help_id => 'doPartitionDisks',
		  }, 
		  [ { val => \$sol, list => \@solutions, format => sub { $_[0][1] }, type => 'list' } ]);
    log::l("partitionWizard calling solution $sol->[1]");
    my $ok = eval { $sol->[2]->() };
    $@ and $o->ask_warn('', N("Partitioning failed: %s", formatError($@)));
    $ok or goto &main;
    1;
}

1;
