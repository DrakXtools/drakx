package fs::partitioning_wizard;

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
use partition_table::dos;
use POSIX qw(ceil);

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
    my ($in, $all_hds, $fstab, $manual_fstab, $_partitions, $partitioning_flags, $skip_mtab) = @_;
    my $ok;

    do {
	$ok = 1;
	my $do_force_reload = sub {
            require File::Temp;
            require fs::dmcrypt;
            my (undef, $tmp_file) = File::Temp::mkstemp('/tmp/crypttab.XXXXXXX');
            fs::dmcrypt::save_crypttab_($all_hds, $tmp_file);
            my $new_hds = fs::get::empty_all_hds();
            fs::any::get_hds($new_hds, $fstab, $manual_fstab, $partitioning_flags, $skip_mtab, $in);
            %$all_hds = %$new_hds;
            fs::dmcrypt::read_crypttab_($all_hds, $tmp_file);
            rm_rf($tmp_file);
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
To accomplish this, create a partition (or click on an existing one).
Then choose action ``Mount point'' and set it to `/'"), 1) or return;
	}

	if (!any { isSwap($_) } @fstab) {
	    $ok &&= $in->ask_okcancel('', N("You do not have a swap partition.\n\nContinue anyway?"));
	}
	if ( is_uefi() && !fs::get::has_mntpoint("/boot/EFI", $all_hds)) {
	    $in->ask_warn('', N("You must have a ESP FAT32 partition mounted in /boot/EFI"));
	    $ok = '';
	}
    } until $ok;
    1;
}

sub partitionWizardSolutions {
    my ($in, $all_hds, $all_fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, $o_target) = @_;
    my $hds = $all_hds->{hds};
    my $fstab;
    my $full_fstab = [ fs::get::fstab($all_hds) ];
    if ($o_target) {
        $hds = [ $o_target ];
        $fstab = [ grep { $_->{rootDevice} eq $o_target->{device} } fs::get::fstab($all_hds) ];
    } else {
        $fstab = $full_fstab;
    }

    my @wizlog;
    my (%solutions);

    my $min_linux = MB(600);
    my $min_swap = MB(50);
    my $min_freewin = MB(100);
    fsedit::init_efi_suggestions($full_fstab);

    # each solution is a [ score, text, function ], where the function retunrs true if succeeded

    my @hds_rw = grep { !$_->{readonly} } @$hds;
    my @hds_can_add = grep { $_->{type} ne 'hd' || $_->can_add } @hds_rw;
    if (fs::get::hds_free_space(@hds_can_add) > $min_linux) {
	$solutions{free_space} = [ 30, N("Use free space"), sub { fsedit::auto_allocate($all_hds, $partitions); 1 } ];
    } else { 
	push @wizlog, N("Not enough free space to allocate new partitions") . ": " .
	  (@hds_can_add ? 
	   fs::get::hds_free_space(@hds_can_add) . " < $min_linux" :
	   "no harddrive on which partitions can be added");
    }

    if (my @truefs = grep { isTrueLocalFS($_) } @$fstab) {
	#- value twice the ext2 partitions
	$solutions{existing_part} = [ 20 + @truefs + @$fstab, N("Use existing partitions"), sub { fs::mount_point::ask_mount_points($in, $full_fstab, $all_hds) } ];
    } else {
	push @wizlog, N("There is no existing partition to use");
    }

    if (my @ok_for_resize_fat = grep { isnormal_Fat_or_NTFS ($_) && !fs::get::part2hd($_, $all_hds)->{readonly}
					 && $_->{size} > $min_linux + $min_swap + $min_freewin } @$fstab) {
        @ok_for_resize_fat = map {
            my $part = $_;
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
            if ($@) {
                log::l("The FAT resizer is unable to handle $part->{device} partition%s", formatError($@));
                undef $part;
            }
            if ($part) {
                my $min_win = eval {
                    my $_w = $in->wait_message(N("Resizing"), N("Computing the size of the Microsoft Windows® partition"));
                    $resize_fat->min_size + $min_freewin;
                };
                if ($@) {
                    log::l("The FAT resizer is unable to get minimal size for $part->{device} partition %s", formatError($@));
                    undef $part;
                } else {
                    my $min_linux_all = $min_linux + $min_swap;
                    #- make sure that even after normalizing the size to cylinder boundaries, the minimun will be saved,
                    #- this save at least a cylinder (less than 8Mb).
                    $min_win += partition_table::raw::cylinder_size($hd);

                    if ($part->{size} <= $min_linux_all + $min_win) {
#                die N("Your Microsoft Windows® partition is too fragmented. Please reboot your computer under Microsoft Windows®, run the ``defrag'' utility, then restart the %s installation.", "Moondrake GNU/Linux");
                        undef $part;
                    } else {
                        $part->{resize_fat} = $resize_fat;
                        $part->{min_win} = $min_win;
                        $part->{min_linux} = $min_linux_all;
                        #- try to keep at least 1GB free for Windows
                        #- try to use from 20GB to 20% free space for Linux
                        my $suggested_size = max(
                            $part->{min_win} + 1 * MB(1024),
                            min(
                                $part->{size} - int(0.2 * ($part->{size} - $part->{min_win})),
                                $part->{size} - 20 * MB(1024),
                            ),
                        );
                        $part->{req_size} = max(min($suggested_size, $part->{size} - $part->{min_linux}), $part->{min_win});
                    }
                }
            }
            $part || ();
        } @ok_for_resize_fat;
	if (@ok_for_resize_fat) {
            $solutions{resize_fat} =
                [ 20 - @ok_for_resize_fat, N("Use the free space on a Microsoft Windows® partition"),
                  sub {
                      my $part;
                      if (!$in->isa('interactive::gtk')) {
                          $part = $in->ask_from_listf_raw({ messages => N("Which partition do you want to resize?"),
                                                               interactive_help_id => 'resizeFATChoose',
                                                             }, \&partition_table::description, \@ok_for_resize_fat) or return;
                          $part->{size} > $part->{min_linux} + $part->{min_win} or die N("Your Microsoft Windows® partition is too fragmented. Please reboot your computer under Microsoft Windows®, run the ``defrag'' utility, then restart the %s installation.", "Moondrake GNU/Linux");
                      } else {
                          my @selected = grep {
                              $_->{selected_for_resize} &&
                              $o_target->{device} eq $_->{rootDevice} # Not needed but let's be safe
                          } @ok_for_resize_fat;
                          my $nb_parts = @selected;
                          die N("Failed to find the partition to resize (%d choices)", $nb_parts) unless $nb_parts == 1;
                          $part = @selected[0];
                      }
                      my $resize_fat = $part->{resize_fat};
                      my $hd = fs::get::part2hd($part, $all_hds);
                      $in->ask_okcancel('', formatAlaTeX(
                                            #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                                            N("WARNING!


Your Microsoft Windows® partition will be now resized.


Be careful: this operation is dangerous. If you have not already done so, you first need to exit the installation, run \"chkdsk c:\" from a Command Prompt under Microsoft Windows® (beware, running graphical program \"scandisk\" is not enough, be sure to use \"chkdsk\" in a Command Prompt!), optionally run defrag, then restart the installation. You should also backup your data.


When sure, press %s.", N("Next")))) or return;

                      my $oldsize = $part->{size};
                      if (!$in->isa('interactive::gtk')) {
                          my $mb_size = to_Mb($part->{req_size});
                          my $max_win = $part->{size} - $part->{min_linux};
                          $in->ask_from(N("Partitionning"), N("Which size do you want to keep for Microsoft Windows® on partition %s?", partition_table::description($part)), [
                                        { label => N("Size"), val => \$mb_size, min => to_Mb($part->{min_win}), max => to_Mb($max_win), type => 'range' },
                                    ]) or return;
                          $part->{req_size} = from_Mb($mb_size, $part->{min_win}, $part->{max_win});
                      }
                      $part->{size} = $part->{req_size};

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
                  }, \@ok_for_resize_fat ];
        }
    } else {
	push @wizlog, N("There is no FAT partition to resize (or not enough space left)");
    }

    if (@$fstab && @hds_rw) {
	$solutions{wipe_drive} =
	  [ 10, fsedit::is_one_big_fat_or_NT($hds) ? N("Remove Microsoft Windows®") : N("Erase and use entire disk"),
	    sub {
                my $hd;
                if (!$in->isa('interactive::gtk')) {
                    $hd = $in->ask_from_listf_raw({ messages => N("You have more than one hard disk drive, which one do you want the installer to use?"),
                                                       title => N("Partitioning"),
                                                       interactive_help_id => 'takeOverHdChoose',
                                                     },
                                                     \&partition_table::description, \@hds_rw) or return;
                } else {
                    $hd = $o_target;
                }
		$in->ask_okcancel_({ messages => N("ALL existing partitions and their data will be lost on drive %s", partition_table::description($hd)),
				    title => N("Partitioning"),
				    interactive_help_id => 'takeOverHdConfirm' }) or return;
		fsedit::partition_table_clear_and_initialize($all_hds->{lvms}, $hd, $in);
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
		$pid = fork() or exec "fdisk", devices::make($_->{device});
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
    $in->ask_warn(N("Partitioning"), N("You need to reboot for the partition table modifications to take effect"));
}

sub create_display_box {
    my ($kind, $resize, $fill_empty, $button) = @_;

    # Hide empty space < 2MB, wehave such holes due to alignment
    my @parts = grep { $_->{size} > MB(2) || !isEmpty($_) } diskdrake::hd_gtk::kind2parts($kind);

    my $totalsectors = diskdrake::hd_gtk::kind2sectors($kind, @parts);

    my $width = 520;
    my $minwidth = 7;

    my $display_box = ugtk3::gtkset_size_request(Gtk3::HBox->new(0,0), -1, 26);

    my $sep_count = @parts - 1;
    #- ratio used to compute initial partition pixel width (each partition should be > min_width)
    #- though, the pixel/sectors ratio cannot be the same for all the partitions
    my $initial_ratio = $totalsectors ? ($width - @parts * $minwidth - $sep_count) / $totalsectors : 1;

    my $vbox = Gtk3::VBox->new;

    my $part_sep;
    my $desc;

    if ($resize) {
	my %resizable_parts;
	foreach my $entry (@$resize) {
	    # selected_for_resize may have been set on another disk, clear it
	    $entry->{selected_for_resize} = 0;
	    $resizable_parts{$entry->{device}} = $entry;
	}
	# find resizable parts on this disk
	my @choices = grep { $resizable_parts{$_->{device}} } @parts;
	my @sorted_resize = sort {
		($a->{size} - $a->{req_size}) <=> ($b->{size} - $b->{req_size})
	    } @choices;
	$sorted_resize[-1]->{selected_for_resize} = 1;
    }

    foreach my $entry (@parts) {
	my $part_info = Gtk3::Label->new($entry->{device_LABEL});
	my @colorized_fs_types = qw(ext2 ext3 ext4 xfs swap vfat ntfs ntfs-3g);
        my $part_widget = Gtk3::EventBox->new;
        $entry->{width} = int($entry->{size} * $initial_ratio) + $minwidth;
        if ($entry->{selected_for_resize}) {
            my $ratio;
            my $update_ratio = sub { $ratio = $entry->{width} / $entry->{size} };
            $update_ratio->();

            $part_widget->set_name("PART_vfat");
            $part_info->set_size_request(ceil($ratio * $entry->{min_win}), 0);

            my $mdv_widget = gtkadd(gtkset_name(Gtk3::EventBox->new, "PART_new"),
                                    gtkset_size_request(gtknew("Image", file => "small-logo"),
                                                        $ratio * MB(600), 0));

            my $hpane = Gtk3::HPaned->new;
            $hpane->pack1($part_widget, 1, 0);
            $hpane->pack2($mdv_widget, 1, 0);
            $hpane->set_position(ceil($ratio * $entry->{req_size}));
            ugtk3::gtkset_size_request($hpane, $entry->{width}, 0);
            ugtk3::gtkpack__($display_box, $hpane);

            my $add_part_size_info = sub {
                my ($name, $label) = @_;
                ugtk3::gtkpack__($desc,
                                 gtkadd(gtkset_name(Gtk3::EventBox->new, $name),
                                        Gtk3::Label->new(" " x 4)),
                                 gtkset_size_request(gtkset_alignment($label, 0, 0.5),
                                                     150, 20));
            };
            $desc = Gtk3::HBox->new(0,0);

            my $win_size_label = Gtk3::Label->new;
            $add_part_size_info->("PART_vfat", $win_size_label);

            my $mdv_size_label = Gtk3::Label->new;
            $add_part_size_info->("PART_new", $mdv_size_label);

            my $update_size_labels = sub {
                $win_size_label->set_label(" Windows (" . formatXiB($entry->{req_size}, 512) . ")");
                $mdv_size_label->set_label(" Moondrake (" . formatXiB($entry->{size} - $entry->{req_size}, 512) . ")");
                0;
            };
            my $update_req_size = sub {
                $entry->{req_size} = int($hpane->get_position / $ratio);
                $update_size_labels->();
            };
            my $button_activate = sub {
                $button->activate;
                0;
            };
            $hpane->signal_connect('size-allocate' => sub {
                my (undef, $alloc) = @_;
                $entry->{width} = $alloc->{width};
                $update_ratio->();
                0;
            });
            $update_size_labels->();
            $hpane->signal_connect('motion-notify-event' => $update_req_size);
            $hpane->signal_connect('move-handle' => $update_req_size);
            $hpane->signal_connect('button-press-event' => $button_activate);
            $vbox->signal_connect('button-press-event' => $button_activate);
            $button->signal_connect('focus-in-event' => sub {
                $hpane->grab_focus;
                0;
            });
        } else {
            if ($fill_empty && isEmpty($entry)) {
                $part_info = gtknew("Image", file => "small-logo");
                $part_widget->set_name("PART_new");
            } else {
                $part_widget->set_name("PART_" . (isEmpty($entry) ? 'empty' :
                                         $entry->{fs_type} && member($entry->{fs_type}, @colorized_fs_types) ? $entry->{fs_type} :
                                         'other'));
            }
            $part_widget->set_size_request($entry->{width}, 0);
            ugtk3::gtkpack($display_box, $part_widget);
        }
	$part_widget->add($part_info);

	$part_sep = gtkadd(Gtk3::EventBox->new,
                     gtkset_size_request(Gtk3::Label->new("."), 1, 0));
	gtkpack__($display_box, $part_sep);
    }
    $display_box->remove($part_sep) if $part_sep;
    unless ($resize || $fill_empty) {
        my @types = (N_("Ext2/3/4"), N_("XFS"), N_("Swap"), N_("Windows"),
                    N_("Other"), N_("Empty"));
        my %name2fs_type = ('Ext2/3/4' => 'ext3', 'XFS' => 'xfs', Swap => 'swap', Other => 'other', "Windows" => 'vfat', HFS => 'hfs');
        $desc = ugtk3::gtkpack(Gtk3::HBox->new,
                map {
                     my $t = $name2fs_type{$_};
                     my $ev = Gtk3::EventBox->new;
		     my $w = Gtk3::Label->new(translate($_));
	             $ev->add($w);
		     $ev->set_name('PART_' . ($t || 'empty'));
                     $ev;
                } @types);
    }

    $vbox->add($display_box);
    $vbox->add($desc) if $desc;

    $vbox;
}

sub display_choices {
    my ($o, $contentbox, $mainw, %solutions) = @_;
    my @solutions = sort { $solutions{$b}[0] <=> $solutions{$a}[0] } keys %solutions;
    my @sol = grep { $solutions{$_}[0] >= 0 } @solutions;

    log::l(''  . "solutions found: " . join(', ', map { $solutions{$_}[1] } @sol) .
           " (all solutions found: " . join(', ', map { $solutions{$_}[1] } @solutions) . ")");

    @solutions = @sol if @sol > 1;
    log::l("solutions: ", int @solutions);
    @solutions or $o->ask_warn(N("Partitioning"), N("I cannot find any room for installing")), die 'already displayed';

    log::l('HERE: ', join(',', map { $solutions{$_}[1] } @solutions));

    $contentbox->foreach(sub { $contentbox->remove($_[0]) });

    $mainw->{kind}{display_box} ||= create_display_box($mainw->{kind});
    ugtk3::gtkpack2__($contentbox, $mainw->{kind}{display_box});
    ugtk3::gtkpack__($contentbox, gtknew('Label',
                                         text => N("The DrakX Partitioning wizard found the following solutions:"),
                                         alignment => [0, 0]));

    my $choicesbox = gtknew('VBox');
    my $oldbutton;
    my $sep;
    foreach my $s (@solutions) {
        my $item;
        my $vbox = gtknew('VBox');
        my $button = gtknew('RadioButton', child => $vbox);
        if ($s eq 'free_space') {
            $item = create_display_box($mainw->{kind}, undef, 1);
        } elsif ($s eq 'resize_fat') {
            $item = create_display_box($mainw->{kind}, $solutions{$s}[3], undef, $button);
        } elsif ($s eq 'existing_part') {
        } elsif ($s eq 'wipe_drive') {
            $item = Gtk3::EventBox->new;
            my $b2 = gtknew("Image", file => "small-logo");
            $item->add($b2);
            $item->set_size_request(520,26);
            $item->set_name("PART_new");
        } elsif ($s eq 'diskdrake') {
        } else {
            log::l($s);
            next;
        }
        ugtk3::gtkpack($vbox, 
                       gtknew('Label',
                              text => $solutions{$s}[1],
                              alignment => [0, 0]));
        ugtk3::gtkpack($vbox, $item) if defined($item);
        $button->join_group($oldbutton) if $oldbutton;
        $oldbutton = $button;
        $button->signal_connect('toggled', sub { $mainw->{sol} = $solutions{$s} if $_[0]->get_active });
        ugtk3::gtkpack2__($choicesbox, $button);
        $sep = gtknew('HSeparator');
        ugtk3::gtkpack2__($choicesbox, $sep);
    }
    $choicesbox->remove($sep);
    ugtk3::gtkadd($contentbox, $choicesbox);
    $mainw->{sol} = $solutions{@solutions[0]};
}

sub main {
    my ($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, $b_nodiskdrake) = @_;

    my $sol;

    if ($o->isa('interactive::gtk')) {
        require mygtk3;
        mygtk3->import(qw(gtknew));
        require ugtk3;
        ugtk3->import(qw(:wrappers));

        my $mainw = ugtk3->new(N("Partitioning"), %$o, if__($::main_window, transient => $::main_window));
        $mainw->{box_allow_grow} = 1;

        mygtk3::set_main_window_size($mainw->{rwindow});

        require diskdrake::hd_gtk;
        diskdrake::hd_gtk::load_theme();

        my $mainbox = Gtk3::VBox->new;

        my @kinds = map { diskdrake::hd_gtk::hd2kind($_) } sort { $a->{is_removable} <=> $b->{is_removable} } @{ $all_hds->{hds} };
        #push @kinds, diskdrake::hd_gtk::raid2real_kind($_) foreach @{$all_hds->{raids}};
        push @kinds, map { diskdrake::hd_gtk::lvm2kind($_) } @{$all_hds->{lvms}};

        my $hdchoice = Gtk3::HBox->new;

        my $hdchoicelabel = Gtk3::Label->new(N("Here is the content of your disk drive "));

        my $combobox = Gtk3::ComboBoxText->new;
        foreach (@kinds) {
            my $info = $_->{val}{info} || $_->{val}{device};
            $info =~ s|^(?:.*/)?(.{24}).*|$1|;
            $info .= " (" . formatXiB($_->{val}{totalsectors}, 512) . ")" if $_->{val}{totalsectors};
            $combobox->append_text($info);
        }
        $combobox->set_active(0);

        ugtk3::gtkpack2__($hdchoice, $hdchoicelabel);
        $hdchoice->add($combobox);

        ugtk3::gtkpack2__($mainbox, $hdchoice);

        my $contentbox = Gtk3::VBox->new(0, 12);

        my $scroll = Gtk3::ScrolledWindow->new;
        $scroll->set_policy('automatic', 'automatic'),
        my $vp = Gtk3::Viewport->new;
        $vp->set_shadow_type('none');
        $vp->add($contentbox);
        $scroll->add($vp);
        $mainbox->add($scroll);

        my $kind = $kinds[$combobox->get_active];
        my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, diskdrake::hd_gtk::kind2hd($kind));
        delete $solutions{diskdrake} if $b_nodiskdrake;
        $mainw->{kind} = $kind;
        display_choices($o, $contentbox, $mainw, %solutions);

        $combobox->signal_connect("changed", sub {        
            $mainw->{kind} = $kinds[$combobox->get_active];
            my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab, diskdrake::hd_gtk::kind2hd($mainw->{kind}));
            delete $solutions{diskdrake} if $b_nodiskdrake;
            display_choices($o, $contentbox, $mainw, %solutions);
            $mainw->{window}->show_all;
        });

        my @more_buttons = (
            if_($::isInstall, 
            [ gtknew('Install_Button',
                     text => N("Help"),
                     clicked => sub { interactive::gtk::display_help($o, {interactive_help_id => 'doPartitionDisks' }) }),
              undef, 1 ]),
            );
        my $buttons_pack = $mainw->create_okcancel(N("Next"), undef, '', @more_buttons);
        $mainbox->pack_end($buttons_pack, 0, 0, 0);
        ugtk3::gtkadd($mainw->{window}, $mainbox);
        $mainw->{window}->show_all;

        $mainw->main;

        $sol=$mainw->{sol};
    } else {
        my %solutions = partitionWizardSolutions($o, $all_hds, $fstab, $manual_fstab, $partitions, $partitioning_flags, $skip_mtab);

        delete $solutions{diskdrake} if $b_nodiskdrake;

        my @solutions = sort { $b->[0] <=> $a->[0] } values %solutions;

        my @sol = grep { $_->[0] >= 0 } @solutions;
        log::l(''  . "solutions found: " . join(', ', map { $_->[1] } @sol) . 
               " (all solutions found: " . join(', ', map { $_->[1] } @solutions) . ")");
        @solutions = @sol if @sol > 1;
        log::l("solutions: ", int @solutions);
        @solutions or $o->ask_warn(N("Partitioning"), N("I cannot find any room for installing")), die 'already displayed';
        log::l('HERE: ', join(',', map { $_->[1] } @solutions));
        $o->ask_from_({ 
            title => N("Partitioning"),
            interactive_help_id => 'doPartitionDisks',
                      },
                      [
                       { label => N("The DrakX Partitioning wizard found the following solutions:"),  title => $::isInstall },
                       { val => \$sol, list => \@solutions, format => sub { $_[0][1] }, type => 'list' },
                      ]);
    }
    log::l("partitionWizard calling solution $sol->[1]");
    my $ok = eval { $sol->[2]->() };
    if (my $err = $@) {
        if ($err =~ /wizcancel/) {
            $_->destroy foreach $::WizardTable->get_children;
        } else {
            log::l("Partitioning failed: $err");
            $o->ask_warn('', N("Partitioning failed: %s", formatError($err)));
        }
    }
    $ok or goto &main;
    1;
}

1;
