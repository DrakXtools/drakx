package diskdrake::interactive; # $Id$

use diagnostics;
use strict;

use common;
use partition_table qw(:types);
use partition_table::raw;
use detect_devices;
use run_program;
use loopback;
use devices;
use fsedit;
use raid;
use any;
use log;
use fs;


=begin

=head1 SYNOPSYS

struct part {
  int active            # one of { 0 | 0x80 }  x86 only, primary only
  int start             # in sectors
  int size              # in sectors
  int type              # 0x82, 0x83, 0x6 ...
  string device         # 'hda5', 'sdc1' ...
  string rootDevice     # 'sda', 'hdc' ... (can also be a VG_name)
  string real_mntpoint  # directly on real /, '/tmp/hdimage' ...
  string mntpoint       # '/', '/usr' ...
  string options        # 'defaults', 'noauto'
  string device_windobe # 'C', 'D' ...
  string encrypt_key    # [0-9A-Za-z./]{20,}
  string comment        # comment to have in fstab

  bool isMounted

  bool isFormatted
  bool notFormatted 
    #  isFormatted                  means the device is formatted
    # !isFormatted &&  notFormatted means the device is not formatted
    # !isFormatted && !notFormatted means we don't know which state we're in

  int raid          # for partitions of type isRawRAID and which isPartOfRAID, the raid device number
  string lvm        # partition used as a PV for the VG with {lvm} as VG_name  #-#
  loopback loopback[]   # loopback living on this partition

  # internal
  string real_device     # '/dev/loop0', '/dev/loop1' ...

  # internal CHS (Cylinder/Head/Sector)
  int start_cyl, start_head, start_sec, end_cyl, end_head, end_sec, 
}

struct part_allocate inherits part {
  int maxsize        # in sectors (alike "size")
  int ratio          # 
  string hd          # 'hda', 'hdc'
  string parts       # for creating raid partitions. eg: 'foo bar' where 'foo' and 'bar' are mntpoint
}

struct part_raid inherits part {
  string chunk-size  # usually '64k'
  string level       # one of { 0, 1, 4, 5, 'linear' }

  part disks[]

  # invalid: active, start, rootDevice, device_windobe?, CHS
}

struct part_loopback inherits part {
  string loopback_file   # absolute file name which is relative to the partition
  part loopback_device   # where the loopback file live

  # device is special here: it is the absolute filename of the loopback file.

  # invalid: active, start, rootDevice, device_windobe, CHS
}

struct part_lvm inherits part {
  # invalid: active, start, device_windobe, CHS
}


struct partition_table_elem {
  part normal[]     #
  part extended     # the main/next extended
  part raw[4]       # primary partitions
}

struct geom {
  int heads 
  int sectors
  int cylinders
  int totalcylinders # for SUN, forget it
  int start          # always 0, forget it
}

struct hd {
  int totalsectors      # size in sectors
  string device         # 'hda', 'sdc' ...
  string device_alias   # 'cdrom', 'floppy' ...
  string media_type     # one of { 'hd', 'cdrom', 'fd', 'tape' }
  string capacity       # contain of the strings of { 'burner', 'DVD' }
  string info           # name of the hd, eg: 'QUANTUM ATLAS IV 9 WLS'

  bool readonly         # is it allowed to modify the partition table
  bool getting_rid_of_readonly_allowed # is it forbidden to write because the partition table is badly handled, or is it because we MUST not change the partition table
  bool isDirty          # does it need to be written to the disk 
  bool needKernelReread # must we tell the kernel to reread the partition table
  bool hasBeenDirty     # for undo
  bool rebootNeeded     # happens when a kernel reread failed
  bool partitionsRenumbered # happens when you
                            # - remove an extended partition which is not the last one
                            # - add an extended partition which is the first extended partition
  int bus, id
  
  partition_table_elem primary
  partition_table_elem extended[]

  geom geom

  # internal
  string prefix         # for some RAID arrays device=>c0d0 and prefix=>c0d0p
  string file           # '/dev/hda' ...
}

struct hd_lvm inherits hd {
  int PE_size           # block size (granularity, similar to cylinder size on x86)
  string VG_name        # VG name

  part_lvm disks[]

  # invalid: bus, id, extended, geom
}

struct raw_hd inherits hd {
  string type       # 0x82, 0x83, 'nfs', ...
  string mntpoint   # '/', '/usr' ...
  string options    # 'defaults', 'noauto'

  # invalid: isDirty, needKernelReread, hasBeenDirty, rebootNeeded, primary, extended
}

struct all_hds {
  hd hds[]
  hd_lvm lvms[]
  part_raid raids[]     # indexed by number: raids[$n]{device} is "md$n"
  part_loopback loopbacks[]
  raw_hd raw_hds[]
  raw_hd nfss[]
  raw_hd smbs[]
  raw_hd davs[]
  raw_hd special[]

  # internal: if fstab_to_string($all_hds) eq current_fstab then no need to save
  string current_fstab
}


=cut


sub main {
    my ($in, $all_hds, $_nowizard, $do_force_reload) = @_;

    if ($in->isa('interactive::gtk')) {
	require diskdrake::hd_gtk;
	goto &diskdrake::hd_gtk::main;
    }

    my ($current_part, $current_hd);
    
    while (1) {
	my $choose_txt = $current_part ? N_("Choose another partition") : N_("Choose a partition");
	my $parts_and_holes = [ fsedit::get_all_fstab_and_holes($all_hds) ];
	my $choose_part = sub {
	    $current_part = $in->ask_from_listf('diskdrake', translate($choose_txt), sub { format_part_info_short(fsedit::part2hd($_[0], $all_hds), $_[0]) }, $parts_and_holes, $current_part) || return;
	    $current_hd = fsedit::part2hd($current_part, $all_hds);
	};

	$choose_part->() if !$current_part;
	return if !$current_part;

	my %actions = my @actions = (
            if_($current_part, 
          (map { my $s = $_; $_ => sub { $diskdrake::interactive::{$s}($in, $current_hd, $current_part, $all_hds) } } part_possible_actions($in, $current_hd, $current_part, $all_hds)),
		'____________________________' => sub {},
            ),
            if_(@$parts_and_holes > 1, $choose_txt => $choose_part),
	    if_($current_hd,
	  (map { my $s = $_; $_ => sub { $diskdrake::interactive::{$s}($in, $current_hd, $all_hds) } } hd_possible_actions_interactive($in, $current_hd, $all_hds)),
	    ), 
	  (map { my $s = $_; $_ => sub { $diskdrake::interactive::{$s}($in, $all_hds) } } general_possible_actions($in, $all_hds)),
        );
	my ($actions) = list2kv(@actions);
	my $a;
	if ($current_part) {
	    $in->ask_from_({
			    cancel => N("Exit"), 
			    title => 'diskdrake',
			    messages => format_part_info($current_hd, $current_part),
			   },
			   [ { val => \$a, list => $actions, format => \&translate, type => 'list', sort => 0, gtk => { use_boxradio => 0 } } ]) or last;
	    my $v = eval { $actions{$a}() };
	    if (my $err = $@) {
		$in->ask_warn(N("Error"), formatError($err));		
	    }
	    if ($v eq 'force_reload') {
		$all_hds = $do_force_reload->();
	    }
	    $current_hd = $current_part = '' if !is_part_existing($current_part, $all_hds);	    
	} else {
	    $choose_part->();
	}
	partition_table::assign_device_numbers($_) foreach fsedit::all_hds($all_hds);
    }
    return if eval { Done($in, $all_hds) };
    if (my $err = $@) {
    	$in->ask_warn(N("Error"), formatError($err));
    }
    goto &main;
}




################################################################################
# general actions
################################################################################
sub general_possible_actions {
    N_("Undo"), ($::expert ? N_("Toggle to normal mode") : N_("Toggle to expert mode"));
}


sub Undo {
    my ($_in, $all_hds) = @_;
    fsedit::undo($all_hds);
}

sub Wizard {
    $::o->{wizard} = 1;
    goto &Done;
}

sub Done {
    my ($in, $all_hds) = @_;
    eval { raid::verify($all_hds->{raids}) };
    if (my $err = $@) {
	$::expert or die;
	$in->ask_okcancel('', [ formatError($err), N("Continue anyway?") ]) or return;
    }
    foreach (@{$all_hds->{hds}}) {
	if (!write_partitions($in, $_)) {
	    return if !$::isStandalone;
	    $in->ask_yesorno(N("Quit without saving"), N("Quit without writing the partition table?"), 1) or return;
	}
    }
    if (!$::isInstall) {
	my $new = fs::fstab_to_string($all_hds);
	if ($new ne $all_hds->{current_fstab} && $in->ask_yesorno('', N("Do you want to save /etc/fstab modifications"), 1)) {
	    $all_hds->{current_fstab} = $new;
	    fs::write_fstab($all_hds);
	}
    }
    1;
}

################################################################################
# per-hd actions
################################################################################
sub hd_possible_actions {
    my ($_in, $hd, $_all_hds) = @_;
    ( 
     if_(!$hd->{readonly} || $hd->{getting_rid_of_readonly_allowed}, N_("Clear all")), 
     if_(!$hd->{readonly} && $::isInstall, N_("Auto allocate")),
     N_("More"),
    );
}
sub hd_possible_actions_interactive {
    my ($_in, $_hd, $_all_hds) = @_;
    &hd_possible_actions, N_("Hard drive information");
}

sub Clear_all {
    my ($in, $hd, $all_hds) = @_;

    my @parts = partition_table::get_normal_parts($hd);
    foreach (@parts) {
	RemoveFromLVM($in, $hd, $_, $all_hds) if isPartOfLVM($_);
	RemoveFromRAID($in, $hd, $_, $all_hds) if isPartOfRAID($_);
    }
    if (isLVM($hd)) {
	lvm::lv_delete($hd, $_) foreach @parts
    } else {
	$hd->{readonly} = 0; #- give a way out of readonly-ness. only allowed when getting_rid_of_readonly_allowed
	$hd->{getting_rid_of_readonly_allowed} = 0;
	partition_table::raw::zero_MBR_and_dirty($hd);
    }
}

sub Auto_allocate {
    my ($in, $hd, $all_hds) = @_;
    my $suggestions = partitions_suggestions($in) or return;

    my %all_hds_ = %$all_hds;
    $all_hds_{hds} = [ sort { $a == $hd ? -1 : 1 } @{$all_hds->{hds}} ];

    eval { fsedit::auto_allocate(\%all_hds_, $suggestions) };
    if ($@) {
	$@ =~ /partition table already full/ or die;

	$in->ask_warn("", [ 
			   N("All primary partitions are used"),
			   N("I can't add any more partition"), 
			   N("To have more partitions, please delete one to be able to create an extended partition"),
			  ]);
    }
}

sub More {
    my ($in, $hd) = @_;

    my $r;
    $in->ask_from('', '',
	    [
	     { val => N("Save partition table"),    clicked_may_quit => sub { SaveInFile($in, $hd);   1 } },
	     { val => N("Restore partition table"), clicked_may_quit => sub { ReadFromFile($in, $hd); 1 } },
	     { val => N("Rescue partition table"),  clicked_may_quit => sub { Rescuept($in, $hd);     1 } },
	         if_($::isInstall || 1, 
	     { val => N("Reload partition table"), clicked_may_quit => sub { $r = 'force_reload'; 1 } }),
	         if_($::isInstall, 
	     { text => N("Removable media automounting"), val => \$::o->{useSupermount}, type => 'bool' },
		 ),
	    ],
    ) && $r;
}

sub ReadFromFile {
    my ($in, $hd) = @_;

    my $file = $::isStandalone ? $in->ask_file(N("Select file")) : devices::make("fd0") or return;

    eval {
    catch_cdie { partition_table::load($hd, $file) }
      sub {
	  $@ =~ /bad totalsectors/ or return;
	  $in->ask_yesorno('',
N("The backup partition table has not the same size
Still continue?"), 0);
      };
    };
    if (my $err = $@) {
    	$in->ask_warn(N("Error"), formatError($err));
    }
}

sub SaveInFile {
    my ($in, $hd) = @_;

    my $file = $::isStandalone ?
		 $in->ask_file(N("Select file")) :
                 $in->ask_okcancel(N("Warning"),
N("Insert a floppy in drive
All data on this floppy will be lost"), 1) && devices::make(detect_devices::floppy()) or return;

    eval { partition_table::save($hd, $file) };
    if (my $err = $@) {
    	$in->ask_warn(N("Error"), formatError($err));
    }
}

sub Rescuept {
    my ($in, $hd) = @_;
    my $_w = $in->wait_message('', N("Trying to rescue partition table"));
    fsedit::rescuept($hd);
}

sub Hd_info {
    my ($in, $hd) = @_;
    $in->ask_warn('', [ N("Detailed information"), format_hd_info($hd) ]);
}

################################################################################
# per-part actions
################################################################################

sub part_possible_actions {
    my ($_in, $hd, $part, $_all_hds) = @_;
    $part or return;

    my %actions = my @l = (
        N_("Mount point")      => '($part->{real_mntpoint} && common::usingRamdisk()) || (!isBusy && !isSwap && !isNonMountable)',
        N_("Type")             => '!isBusy && $::expert && (!readonly || ($part->{type} & 0xff) == 0x83)',
        N_("Options")          => '$::expert',
        N_("Resize")	       => '!isBusy && !readonly && !isSpecial || isLVM($hd) && isMounted && isThisFs("xfs", $part)',
        N_("Move")             => '!isBusy && !readonly && !isSpecial && $::expert && 0', # disable for the moment
        N_("Format")           => '!isBusy && !readonly && ($::expert || $::isStandalone)',
        N_("Mount")            => '!isBusy && (hasMntpoint || isSwap) && maybeFormatted && ($::expert || $::isStandalone)',
        N_("Add to RAID")      => '!isBusy && isRawRAID && !isSpecial',
        N_("Add to LVM")       => '!isBusy && isRawLVM',
        N_("Unmount")          => '!$part->{real_mntpoint} && isMounted',
        N_("Delete")	       => '!isBusy && !readonly',
        N_("Remove from RAID") => 'isPartOfRAID',
        N_("Remove from LVM")  => 'isPartOfLVM',
        N_("Modify RAID")      => 'isPartOfRAID && !isMounted($all_hds->{raids}[$part->{raid}])',
        N_("Use for loopback") => '!$part->{real_mntpoint} && isMountableRW && !isSpecial && hasMntpoint && $::expert',
    );
    my ($actions_names) = list2kv(@l);
    my %macros = (
	readonly => '$hd->{readonly}',
        hasMntpoint => '$part->{mntpoint}',
        isPrimary => 'isPrimary($part, $hd)',
    );
    if ($part->{type} == 0) {
	if_(!$hd->{readonly}, N_("Create"));
    } else {
        grep { 
    	    my $cond = $actions{$_};
    	    while (my ($k, $v) = each %macros) {
    	        $cond =~ s/$k/qq(($v))/e;
    	    }
    	    $cond =~ s/(^|[^:\$]) \b ([a-z]\w{3,}) \b ($|[\s&\)])/$1 . $2 . '($part)' . $3/exg;
    	    eval $cond;
        } @$actions_names;
    }
}

sub Create {
    my ($in, $hd, $part, $all_hds) = @_;
    my ($def_start, $def_size, $max) = ($part->{start}, $part->{size}, $part->{start} + $part->{size});

    $part->{maxsize} = $part->{size}; $part->{size} = 0;
    if (!fsedit::suggest_part($part, $all_hds)) {
	$part->{size} = $part->{maxsize};
	$part->{type} ||= 0x483;
    }

    #- update adjustment for start and size, take into account the minimum partition size
    #- including one less sector for start due to a capacity to increase the adjustement by
    #- one.
    my ($primaryOrExtended, $migrate_files);
    my $type = type2name($part->{type});
    my $mb_size = $part->{size} >> 11;
    my $has_startsector = ($::expert || arch() !~ /i.86/) && !isLVM($hd);

    $in->ask_from(N("Create a new partition"), '',
        [
           if_($has_startsector,
         { label => N("Start sector: "), val => \$part->{start}, min => $def_start, max => ($max - min_partition_size($hd)), type => 'range' },
           ),
         { label => N("Size in MB: "), val => \$mb_size, min => min_partition_size($hd) >> 11, max => $def_size >> 11, type => 'range' },
         { label => N("Filesystem type: "), val => \$type, list => [ partition_table::important_types() ], sort => 0 },
         { label => N("Mount point: "), val => \$part->{mntpoint}, list => [ fsedit::suggestions_mntpoint($all_hds), '' ],
           disabled => sub { my $p = { type => name2type($type) }; isSwap($p) || isNonMountable($p) }, type => 'combo', not_edit => 0,
         },
           if_($::expert && $hd->hasExtended,
         { label => N("Preference: "), val => \$primaryOrExtended, list => [ '', "Extended", "Primary", if_($::expert, "Extended_0x85") ] },
           ),
        ], changed => sub {
	    if ($part->{start} + ($mb_size << 11) > $max) {
		if ($_[0] == 0) {
		    # Start sector changed => restricting Size
		    $mb_size = ($max - $part->{start}) >> 11; 
		} else {
		    # Size changed => restricting Start sector
		    $part->{start} = $max - ($mb_size << 11); 
		}
	    }
        }, complete => sub {
	    $part->{size} = from_Mb($mb_size, min_partition_size($hd), $max - $part->{start}); #- need this to be able to get back the approximation of using MB
	    $part->{type} = name2type($type);
	    $part->{mntpoint} = '' if isNonMountable($part);
	    $part->{mntpoint} = 'swap' if isSwap($part);
	    fs::set_default_options($part);

	    check($in, $hd, $part, $all_hds) or return 1;
	    $migrate_files = need_migration($in, $part->{mntpoint}) or return 1;

	    eval { fsedit::add($hd, $part, $all_hds, { force => 1, primaryOrExtended => $primaryOrExtended }) };
	    if (my $err = $@) {
		if ($err =~ /raw_add/ && $hd->hasExtended && !$hd->{primary}{extended}) {
		    $in->ask_warn(N("Error"), N("You can't create a new partition
(since you reached the maximal number of primary partitions).
First remove a primary partition and create an extended partition."));
		    return 0;
		} else {
		    $in->ask_warn(N("Error"), $@);
		    return 1;
		}
	    }
	    0;
	},
    ) or return;

    warn_if_renumbered($in, $hd);

    if ($migrate_files eq 'migrate') {
	format_($in, $hd, $part, $all_hds) or return;
	migrate_files($in, $hd, $part);
	fs::mount_part($part);
    }
}

sub Delete {
    my ($in, $hd, $part, $all_hds) = @_;
    if (isRAID($part)) {
	raid::delete($all_hds->{raids}, $part);
    } elsif (isLVM($hd)) {
	lvm::lv_delete($hd, $part);
    } elsif (isLoopback($part)) {
	my $f = "$part->{loopback_device}{mntpoint}$part->{loopback_file}";
	if (-e $f && $in->ask_yesorno('', N("Remove the loopback file?"))) {
	    unlink $f;
	}
	my $l = $part->{loopback_device}{loopback};
	@$l = grep { $_ != $part } @$l;
	delete $part->{loopback_device}{loopback} if @$l == 0;
	fsedit::recompute_loopbacks($all_hds);
    } else {
	if (arch() =~ /ppc/) {
	    undef $partition_table::mac::bootstrap_part if isAppleBootstrap($part) && ($part->{device} = $partition_table::mac::bootstrap_part);
	}
	partition_table::remove($hd, $part);
	warn_if_renumbered($in, $hd);
    }
}

sub Type {
    my ($in, $hd, $part) = @_;

    my $warn = sub { ask_alldatawillbelost($in, $part, N_("After changing type of partition %s, all data on this partition will be lost")) };

    #- for ext2, warn after choosing as ext2->ext3 can be achieved without loosing any data :)
    isExt2($part) or $warn->() or return;

    my @types = partition_table::important_types();

    #- when readonly, Type() is allowed only when changing between various { 0x83, 0x183, ... }
    @types = grep { (name2type($_) & 0xff) == 0x83 } @types if $hd->{readonly};

    my $type_name = type2name($part->{type});
    $in->ask_from(N("Change partition type"),
		  N("Which filesystem do you want?"),
		  [ { label => N("Type"), val => \$type_name, list => \@types, sort => 0, not_edit => !$::expert } ]) or return;

    my $type = $type_name && name2type($type_name);

    if (isExt2($part) && isThisFs('ext3', { type => $type })) {
	my $_w = $in->wait_message('', N("Switching from ext2 to ext3"));
	if (run_program::run("tune2fs", "-j", devices::make($part->{device}))) {
	    $part->{type} = $type;
	    $part->{isFormatted} = 1; #- assume that if tune2fs works, partition is formatted

	    #- disable the fsck (don't do it together with -j in case -j fails?)
	    fs::disable_forced_fsck($part->{device});	    
	    return;
	}
    }
    #- either we switch to non-ext3 or switching losslessly to ext3 failed
    !isExt2($part) or $warn->() or return;

    if (defined $type) {
	check_type($in, $type, $hd, $part) and fsedit::change_type($type, $hd, $part);
    }
}

sub Mount_point {
    my ($in, $hd, $part, $all_hds) = @_;

    my $migrate_files;
    my $mntpoint = $part->{mntpoint} || do {
	my $part_ = { %$part };
	if (fsedit::suggest_part($part_, $all_hds)) {
	    fsedit::has_mntpoint('/', $all_hds) || $part_->{mntpoint} eq '/boot' ? $part_->{mntpoint} : '/';
	} else { '' }
    };
    $in->ask_from(
        '',
        isLoopback($part) ? N("Where do you want to mount loopback file %s?", $part->{loopback_file}) :
			    N("Where do you want to mount device %s?", $part->{device}),
	[ { label => N("Mount point"), val => \$mntpoint, 
	    list => [ if_($mntpoint, $mntpoint), fsedit::suggestions_mntpoint($all_hds), '' ], 
	    not_edit => 0 } ],
	complete => sub {
	    !isPartOfLoopback($part) || $mntpoint or $in->ask_warn('', 
N("Can't unset mount point as this partition is used for loop back.
Remove the loopback first")), return 1;
	    $part->{mntpoint} eq $mntpoint || check_mntpoint($in, $mntpoint, $hd, $part, $all_hds) or return 1;
    	    $migrate_files = need_migration($in, $mntpoint) or return 1;
	    0;
	}
    ) or return;
    $part->{mntpoint} = $mntpoint;

    if ($migrate_files eq 'migrate') {
	format_($in, $hd, $part, $all_hds) or return;
	migrate_files($in, $hd, $part);
	fs::mount_part($part);
    }
}
sub Mount_point_raw_hd {
    my ($in, $part, $all_hds, @propositions) = @_;

    my $mntpoint = $part->{mntpoint} || shift @propositions;
    $in->ask_from(
        '',
        N("Where do you want to mount %s?", $part->{device}),
	[ { label => N("Mount point"), val => \$mntpoint, 
	    list => [ if_($mntpoint, $mntpoint), '', @propositions ], 
	    not_edit => 0 } ],
	complete => sub {
	    $part->{mntpoint} eq $mntpoint || check_mntpoint($in, $mntpoint, {}, $part, $all_hds) or return 1;
	    0;
	}
    ) or return;
    $part->{mntpoint} = $mntpoint;
}

sub Resize {
    my ($in, $hd, $part) = @_;
    my (%nice_resize, $block_count, $free_block, $block_size);
    my ($min, $max) = (min_partition_size($hd), partition_table::next_start($hd, $part) - $part->{start});

    if (maybeFormatted($part)) {
	# here we may have a non-formatted or a formatted partition
	# -> doing as if it was formatted

	if (isFat($part)) {
	    write_partitions($in, $hd) or return;
	    #- try to resize without losing data
	    my $_w = $in->wait_message(N("Resizing"), N("Computing FAT filesystem bounds"));

	    $nice_resize{fat} = resize_fat::main->new($part->{device}, devices::make($part->{device}));
	    $min = max($min, $nice_resize{fat}->min_size);
	    $max = min($max, $nice_resize{fat}->max_size);	    
	} elsif (isExt2($part) || isThisFs('ext3', $part)) {
	    write_partitions($in, $hd) or return;
	    $nice_resize{ext2} = devices::make($part->{device});
	    my $r = `dumpe2fs $nice_resize{ext2} 2>/dev/null`;
	    $r =~ /Block count:\s*(\d+)/ and $block_count = $1;
	    $r =~ /Free blocks:\s*(\d+)/ and $free_block = $1;
	    $r =~ /Block size:\s*(\d+)/ and $block_size = $1;
	    log::l("dumpe2fs $nice_resize{ext2} gives: Block_count=$block_count, Free_blocks=$free_block, Block_size=$block_size");
	    if ($block_count && $free_block && $block_size) {
		$min = max($min, ($block_count - $free_block) * $block_size / 512);
		$max = min($max, $block_count * $block_size / 512);
	    } else {
		delete $nice_resize{ext2};
	    }
	} elsif (isThisFs("reiserfs", $part)) {
	    write_partitions($in, $hd) or return;
	    if (defined(my $free = fs::df($part))) {
		$nice_resize{reiserfs} = 1;		  
		$min = max($min, $part->{size} - $free);
	    }
	} elsif (isThisFs('xfs', $part) && isLVM($hd) && $::isStandalone && isMounted($part)) {
	    $min = $part->{size}; #- ensure the user can only increase
	    $nice_resize{xfs} = 1;
	}
	#- make sure that even after normalizing the size to cylinder boundaries, the minimun will be saved,
	#- this save at least a cylinder (less than 8Mb).
	$min += partition_table::raw::cylinder_size($hd);
	$min >= $max and return $in->ask_warn('', N("This partition is not resizeable"));

	#- for these, we have tools to resize partition table
	#- without losing data (or at least we hope so :-)
	if (%nice_resize) {
	    ask_alldatamaybelost($in, $part, N_("All data on this partition should be backed-up")) or return;
	} else {
	    ask_alldatawillbelost($in, $part, N_("After resizing partition %s, all data on this partition will be lost")) or return;
	}
    }

    my $mb_size = $part->{size} >> 11;
    $in->ask_from(N("Resize"), N("Choose the new size"), [ 
		   { label => N("New size in MB: "), val => \$mb_size, min => $min >> 11, max => $max >> 11, type => 'range' },
		]) or return;


    my $size = from_Mb($mb_size, $min, $max);
    $part->{size} == $size and return;

    my $oldsize = $part->{size};
    $hd->{isDirty} = $hd->{needKernelReread} = 1;
    $part->{size} = $size;
    $hd->adjustEnd($part);

    undef $@;
    my $_b = before_leaving { $@ and $part->{size} = $oldsize };
    my $w = $in->wait_message(N("Resizing"), '');

    if (isLVM($hd)) {
	lvm::lv_resize($part, $oldsize) if $size > $oldsize;	
    }

    if ($nice_resize{fat}) {
	local *log::l = sub { $w->set(join(' ', @_)) };
	$nice_resize{fat}->resize($part->{size});
    } elsif ($nice_resize{ext2}) {
	my $s = int(($part->{size} << 9) / $block_size);
	log::l("resize2fs $nice_resize{ext2} to size $s in block of $block_size bytes");
	run_program::run("resize2fs", "-pf", $nice_resize{ext2}, $s);
    } elsif ($nice_resize{reiserfs}) {
	log::l("reiser resize to $part->{size} sectors");
	run_program::run("resize_reiserfs", "-f", "-q", "-s" . $part->{size}/2 . "K", devices::make($part->{device}));
    } elsif ($nice_resize{xfs}) {
	#- happens only with mounted LVM, see above
	run_program::run("xfs_growfs", $part->{mntpoint});
    }

    if (%nice_resize) {
	$part->{isFormatted} = 1;
    } else {
	$part->{notFormatted} = 1;
	$part->{isFormatted} = 0;
	partition_table::verifyParts($hd);
    }

    if (isLVM($hd)) {
	lvm::lv_resize($part, $oldsize) if $size < $oldsize;
    } else {
	partition_table::adjust_local_extended($hd, $part);
	partition_table::adjust_main_extended($hd);
    }
}
sub Move {
    my ($in, $hd, $part, $all_hds) = @_;
    my $hd2 = $in->ask_from_listf(N("Move"),
				  N("Which disk do you want to move it to?"), \&partition_table::description, @{$all_hds->{hds}}) or return;
    my $start2 = $in->ask_from_entry(N("Sector"),
				     N("Which sector do you want to move it to?"));
    defined $start2 or return;

    my $_w = $in->wait_message(N("Moving"), N("Moving partition..."));
    fsedit::move($hd, $part, $hd2, $start2);
}
sub Format {
    my ($in, $hd, $part, $all_hds) = @_;
    format_($in, $hd, $part, $all_hds);
}
sub Mount {
    my ($in, $hd, $part) = @_;
    write_partitions($in, $hd) or return;
    fs::mount_part($part);
}
sub Add2RAID {
    my ($in, $_hd, $part, $all_hds) = @_;
    my $raids = $all_hds->{raids};

    local $_ = @$raids == () ? "new" :
      $in->ask_from_list_('', N("Choose an existing RAID to add to"),
			  [ (grep { $_ } map_index { $_ && "md$::i" } @$raids), N_("new") ]) or return;

    if (/new/) {
	my $nb1 = raid::new($raids, $part);
	defined modifyRAID($in, $raids, $nb1) or return raid::delete($raids, $nb1);
    } else {
	raid::add($raids, $part, $_);
    }
    raid::update(@$raids);
}
sub Add2LVM {
    my ($in, $hd, $part, $all_hds) = @_;
    my $lvms = $all_hds->{lvms};
    write_partitions($in, $_) or return foreach isRAID($part) ? @{$all_hds->{hds}} : $hd;

    my $lvm = $in->ask_from_listf_('', N("Choose an existing LVM to add to"),
				  sub { ref $_[0] ? $_[0]{VG_name} : $_[0] },
				  [ @$lvms, N_("new") ]) or return;
    if (!ref $lvm) {
	# create new lvm
	my $name = $in->ask_from_entry('', N("LVM name?")) or return;
	$name =~ s/\W/_/g;
	$name = substr($name, 0, 63); # max length must be < NAME_LEN / 2  where NAME_LEN is 128
	$lvm = bless { disks => [], VG_name => $name }, 'lvm';
	push @$lvms, $lvm;
    }
    raid::make($all_hds->{raids}, $part) if isRAID($part);
    $part->{lvm} = $lvm->{VG_name};
    push @{$lvm->{disks}}, $part;
    delete $part->{mntpoint};

    require lvm;
    lvm::check($in) if $::isStandalone;
    lvm::vg_add($part);
    lvm::update_size($lvm);
}
sub Unmount {
    my ($_in, $_hd, $part) = @_;
    fs::umount_part($part);
}
sub RemoveFromRAID { 
    my ($_in, $_hd, $part, $all_hds) = @_;
    raid::removeDisk($all_hds->{raids}, $part);
}
sub RemoveFromLVM {
    my ($_in, $_hd, $part, $all_hds) = @_;
    my $lvms = $all_hds->{lvms};
    isPartOfLVM($part) or die;
    my ($lvm) = grep { $_->{VG_name} eq $part->{lvm} } @$lvms;
    lvm::vg_destroy($lvm);
    @$lvms = grep { $_ != $lvm } @$lvms;
}
sub ModifyRAID { 
    my ($in, $_hd, $part, $all_hds) = @_;
    modifyRAID($in, $all_hds->{raids}, $part->{raid});
}
sub Loopback {
    my ($in, $hd, $real_part, $all_hds) = @_;

    write_partitions($in, $hd) or return;

    my $handle = any::inspect($real_part) or $in->ask_warn('', N("This partition can't be used for loopback")), return;

    my ($min, $max) = (1, loopback::getFree($handle->{dir}, $real_part));
    $max = max($max, 1 << (31 - 9)) if isFat($real_part); #- FAT doesn't handle file size bigger than 2GB
    my $part = { maxsize => $max, size => 0, loopback_device => $real_part, notFormatted => 1 };
    if (!fsedit::suggest_part($part, $all_hds)) {
	$part->{size} = $part->{maxsize};
	$part->{type} ||= 0x483;
    }
    delete $part->{mntpoint}; # we don't want the suggested mntpoint

    my $type = type2name($part->{type});
    my $mb_size = $part->{size} >> 11;
    $in->ask_from(N("Loopback"), '', [
		  { label => N("Loopback file name: "), val => \$part->{loopback_file} },
		  { label => N("Size in MB: "), val => \$mb_size, min => $min >> 11, max => $max >> 11, type => 'range' },
		  { label => N("Filesystem type: "), val => \$type, list => [ partition_table::important_types() ], not_edit => !$::expert, sort => 0 },
             ],
	     complete => sub {
		 $part->{loopback_file} or $in->ask_warn('', N("Give a file name")), return 1, 0;
		 $part->{loopback_file} =~ s|^([^/])|/$1|;
		 if (my $size = loopback::verifFile($handle->{dir}, $part->{loopback_file}, $real_part)) {
		     $size == -1 and $in->ask_warn('', N("File already used by another loopback, choose another one")), return 1, 0;
		     $in->ask_yesorno('', N("File already exists. Use it?")) or return 1, 0;
		     delete $part->{notFormatted};
		     $part->{size} = divide($size, 512);
		 } else {
		     $part->{size} = from_Mb($mb_size, $min, $max);
		 }
		 0;
	     }) or return;
    $part->{type} = name2type($type);
    push @{$real_part->{loopback}}, $part;
    fsedit::recompute_loopbacks($all_hds);
}

sub Options {
    my ($in, $hd, $part, $all_hds) = @_;

    my @simple_options = qw(user noauto supermount);

    my (undef, $user_implies) = fs::mount_options();
    my ($options, $unknown) = fs::mount_options_unpack($part);
    my %help = fs::mount_options_help(keys %$options);

    my $prev_user = $options->{user};
    $in->ask_from(N("Mount options"),
		  '',
		  [ 
		   (map { 
			 { label => $_, text => scalar warp_text(formatAlaTeX($help{$_})), val => \$options->{$_}, 
			   advanced => !$part->{rootDevice} && !member($_, @simple_options), if_(!/=$/, type => 'bool'), }
		     } keys %$options),
		    { label => N("Various"), val => \$unknown, advanced => 1 },
		  ],
		  changed => sub {
		      if ($prev_user != $options->{user}) {
			  $prev_user = $options->{user};
			  $options->{$_} = $options->{user} foreach @$user_implies;
		      }
		      if ($options->{encrypted}) {
			  # modify $part->{options} for the check
			  local $part->{options};
			  fs::mount_options_pack($part, $options, $unknown);
			  if (!check($in, $hd, $part, $all_hds)) {
			      $options->{encrypted} = 0;
			  } elsif (!$part->{encrypt_key} && !isSwap($part)) {
			      if (my $encrypt_key = choose_encrypt_key($in)) {
				  $options->{'encryption='} = 'AES128';
				  $part->{encrypt_key} = $encrypt_key;
			      } else {
				  $options->{encrypted} = 0;
			      }
			  }
		      } else {
			  delete $options->{'encryption='};
			  delete $part->{encrypt_key};
		      }
		  },
		 ) or return;

    fs::mount_options_pack($part, $options, $unknown);
    1;
}


{ 
    no strict; 
    *{'Toggle to normal mode'} = sub { $::expert = 0 };
    *{'Toggle to expert mode'} = sub { $::expert = 1 };
    *{'Clear all'} = \&Clear_all;
    *{'Auto allocate'} = \&Auto_allocate;
    *{'Mount point'} = \&Mount_point;
    *{'Modify RAID'} = \&ModifyRAID;
    *{'Add to RAID'} = \&Add2RAID;
    *{'Remove from RAID'} = \&RemoveFromRAID; 
    *{'Add to LVM'} = \&Add2LVM;
    *{'Remove from LVM'} = \&RemoveFromLVM; 
    *{'Use for loopback'} = \&Loopback;
    *{'Hard drive information'} = \&Hd_info;
}


################################################################################
# helpers
################################################################################

sub is_part_existing {
    my ($part, $all_hds) = @_;
    $part && grep { fsedit::is_same_part($part, $_) } fsedit::get_all_fstab_and_holes($all_hds);
}

sub modifyRAID {
    my ($in, $raids, $nb) = @_;
    my $md = "md$nb";
    $in->ask_from('', '',
		  [
{ label => N("device"), val => \$md, list => [ map { "md$_" } grep { $nb == $_ || !$raids->[$_] } 0..8 ] },
{ label => N("level"), val => \$raids->[$nb]{level}, list => [ qw(0 1 4 5 linear) ] },
{ label => N("chunk size"), val => \$raids->[$nb]{'chunk-size'} },
		  ],
		 ) or return;
    raid::updateSize($raids->[$nb]); # changing the raid level changes the size available
    raid::changeNb($raids, $nb, first($md =~ /(\d+)/));
}


sub ask_alldatamaybelost {
    my ($in, $part, $msg) = @_;

    maybeFormatted($part) or return 1;

    #- here we may have a non-formatted or a formatted partition
    #- -> doing as if it was formatted
    $in->ask_okcancel(N("Read carefully!"), 
		      [ N("Be careful: this operation is dangerous."), sprintf(translate($msg), $part->{device}) ], 1);
}
sub ask_alldatawillbelost {
    my ($in, $part, $msg) = @_;

    maybeFormatted($part) or return 1;

    #- here we may have a non-formatted or a formatted partition
    #- -> doing as if it was formatted
    $in->ask_okcancel(N("Read carefully!"), sprintf(translate($msg), $part->{device}), 1);
}

sub partitions_suggestions {
    my ($in) = @_;
    my $t = $::expert ? 
      $in->ask_from_list_('', N("What type of partitioning?"), [ keys %fsedit::suggestions ]) :
      'simple';
    $fsedit::suggestions{$t};
}

sub check_type {
    my ($in, $type, $hd, $part) = @_;
    eval { fsedit::check_type($type, $hd, $part) };
    if (my $err = $@) {
	$in->ask_warn('', $err);
	return;
    }
    if ($::isStandalone) {
	if (my $pkg = fsedit::package_needed_for_partition_type({ type => $type })) {
	    my $fs = type2fs({ type => $type });
	    if (!-x "/sbin/mkfs.$fs") {
		$in->ask_yesorno('', N("The package %s is needed. Install it?", $pkg), 1) or return;
		$in->do_pkgs->install($pkg);
	    }
	    -x "/sbin/mkfs.$fs" or $in->ask_warn('', "Mandatory package $pkg is missing"), return;
	}
    }
    1;
}
sub check_mntpoint {
    my ($in, $mntpoint, $hd, $part, $all_hds) = @_;
    eval { fsedit::check_mntpoint($mntpoint, $hd, $part, $all_hds) };
    local $_ = $@;
    if (m|/boot ending on cylinder > 1024|) {
	$in->ask_warn('',
N("Sorry I won't accept to create /boot so far onto the drive (on a cylinder > 1024).
Either you use LILO and it won't work, or you don't use LILO and you don't need /boot"));
    } elsif (m|/ ending on cylinder > 1024|) {
	$in->ask_warn('',
N("The partition you've selected to add as root (/) is physically located beyond
the 1024th cylinder of the hard drive, and you have no /boot partition.
If you plan to use the LILO boot manager, be careful to add a /boot partition"));
	undef $_;
    } elsif (m|raid / with no /boot|) {
	$in->ask_warn('',
N("You've selected a software RAID partition as root (/).
No bootloader is able to handle this without a /boot partition.
So be careful to add a /boot partition"));
	undef $_;
    } elsif ($_) {
	$in->ask_warn('', formatError($_));
    }
    !$_;
}
sub check {
    my ($in, $hd, $part, $all_hds) = @_;
    check_type($in, $part->{type}, $hd, $part) &&
      check_mntpoint($in, $part->{mntpoint}, $hd, $part, $all_hds);
}

sub write_partitions {
    my ($in, $hd) = @_;
    $hd->{isDirty} or return 1;
    isLVM($hd) and return 1;

    $in->ask_okcancel(N("Read carefully!"), N("Partition table of drive %s is going to be written to disk!", $hd->{device}), 1) or return;
    if (!$::testing) {
	partition_table::write($hd);
    }
    $hd->{rebootNeeded} and die N("You'll need to reboot before the modification can take place");
    1;
}

sub unmount {
    my ($_hd, $part) = @_;
    fs::umount_part($part);
}
sub format_ {
    my ($in, $hd, $part, $all_hds) = @_;
    write_partitions($in, $_) or return foreach isRAID($part) ? @{$all_hds->{hds}} : $hd;
    ask_alldatawillbelost($in, $part, N_("After formatting partition %s, all data on this partition will be lost")) or return;
    $part->{isFormatted} = 0; #- force format;
    my $_w = $in->wait_message(N("Formatting"), 
			      isLoopback($part) ? N("Formatting loopback file %s", $part->{loopback_file}) :
			                          N("Formatting partition %s", $part->{device}));
    fs::format_part($all_hds->{raids}, $part);
    1;
}

sub need_migration {
    my ($in, $mntpoint) = @_;

    my @l = grep { $_ ne "lost+found" } all($mntpoint);
    if (@l && $::isStandalone) {
	my $choice;
	my @choices = (N_("Move files to the new partition"), N_("Hide files"));
	$in->ask_from('', N("Directory %s already contains data\n(%s)", $mntpoint, formatList(5, @l)), 
		      [ { val => \$choice, list => \@choices, type => 'list' } ]) or return;
	$choice eq $choices[0] ? 'migrate' : 'hide';
    } else {
	'hide';
    }    
}

sub migrate_files {
    my ($in, $_hd, $part, $_all_hds) = @_;

    my $wait = $in->wait_message('', N("Moving files to the new partition"));
    my $handle = any::inspect($part, '', 'rw');
    my @l = glob_("$part->{mntpoint}/*");
    foreach (@l) {
	$wait->set(N("Copying %s", $_)); 
	system("cp", "-a", $_, $handle->{dir});
    }
    foreach (@l) {
	$wait->set(N("Removing %s", $_)); 
	system("rm", "-rf", $_);
    }
}

sub warn_if_renumbered {
    my ($in, $hd) = @_;
    my $l = delete $hd->{partitionsRenumbered};
    return if is_empty_array_ref($l);

    my @l = map { N("partition %s is now known as %s", @$_) } @$l;
    $in->ask_warn('', join("\n", 'Partitions have been renumbered: ', @l));
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

sub format_part_info {
    my ($hd, $part) = @_;

    my $info = '';

    $info .= N("Mount point: ") . "$part->{mntpoint}\n" if $part->{mntpoint};
    $info .= N("Device: ") . "$part->{device}\n" if $part->{device} && !isLoopback($part);
    $info .= N("DOS drive letter: %s (just a guess)\n", $part->{device_windobe}) if $part->{device_windobe};
    if (arch() eq "ppc") {
      my $new_value = $part->{pType};
      $new_value =~ s/[^A-Za-z0-9_]//g;
      $info .= N("Type: ") . $new_value . ($::expert ? sprintf " (0x%x)", $part->{type} : '') . "\n";
      if (defined $part->{pName}) {
      	$new_value = $part->{pName};
      	$new_value =~ s/[^A-Za-z0-9_]//g;
      	$info .= N("Name: ") . $new_value . "\n";
      }
    } elsif ($part->{type}) {
	my $type = substr(type2name($part->{type}), 0, 40); # limit the length
	$info .= N("Type: ") . $type . ($::expert ? sprintf " (0x%x)", $part->{type} : '') . "\n";
    } else {
	$info .= N("Empty") . "\n";
    }
    $info .= N("Start: sector %s\n", $part->{start}) if $::expert && !isSpecial($part);
    $info .= N("Size: %s", formatXiB($part->{size}, 512));
    $info .= sprintf " (%s%%)", int 100 * $part->{size} / $hd->{totalsectors} if $hd->{totalsectors};
    $info .= N(", %s sectors", $part->{size}) if $::expert;
    $info .= "\n";
    $info .= N("Cylinder %d to %d\n", $part->{start} / $hd->cylinder_size(), ($part->{start} + $part->{size} - 1) / $hd->cylinder_size()) if ($::expert || !$part->{type}) && !isSpecial($part);
    $info .= N("Formatted\n") if $part->{isFormatted};
    $info .= N("Not formatted\n") if !$part->{isFormatted} && $part->{notFormatted};
    $info .= N("Mounted\n") if $part->{isMounted};
    $info .= N("RAID md%s\n", $part->{raid}) if isPartOfRAID($part);
    $info .= sprintf "LVM %s\n", $part->{lvm} if isPartOfLVM($part);
    $info .= N("Loopback file(s):\n   %s\n", join(", ", map { $_->{loopback_file} } @{$part->{loopback}})) if isPartOfLoopback($part);
    $info .= N("Partition booted by default\n    (for MS-DOS boot, not for lilo)\n") if $part->{active} && $::expert;
    if (isRAID($part)) {
	$info .= N("Level %s\n", $part->{level});
	$info .= N("Chunk size %s\n", $part->{'chunk-size'});
	$info .= N("RAID-disks %s\n", join ", ", map { $_->{device} } @{$part->{disks}});
    } elsif (isLoopback($part)) {
	$info .= N("Loopback file name: %s", $part->{loopback_file});
    }
    if (isApple($part)) {
	$info .= N("\nChances are, this partition is\na Driver partition, you should\nprobably leave it alone.\n");
    }
    if (isAppleBootstrap($part)) {
	$info .= N("\nThis special Bootstrap\npartition is for\ndual-booting your system.\n");
    }
    # restrict the length of the lines
    $info =~ s/(.{60}).*/$1.../mg;
    $info;
}

sub format_part_info_short { 
    my ($hd, $part) = @_;
    $part->{type} ? 
      partition_table::description($part) :
      format_part_info($hd, $part);
}

sub format_hd_info {
    my ($hd) = @_;

    my $info = '';
    $info .= N("Device: ") . "$hd->{device}\n";
    $info .= N("Read-only") . "\n" if $hd->{readonly};
    $info .= N("Size: %s\n", formatXiB($hd->{totalsectors}, 512)) if $hd->{totalsectors};
    $info .= N("Geometry: %s cylinders, %s heads, %s sectors\n", @{$hd->{geom}}{qw(cylinders heads sectors)}) if $::expert && $hd->{geom};
    $info .= N("Info: ") . ($hd->{info} || $hd->{media_type}) . "\n" if $::expert && ($hd->{info} || $hd->{media_type});
    $info .= N("LVM-disks %s\n", join ", ", map { $_->{device} } @{$hd->{disks}}) if isLVM($hd) && $hd->{disks};
    $info .= N("Partition table type: %s\n", $1) if $::expert && ref($hd) =~ /_([^_]+)$/;
    $info .= N("on channel %d id %d\n", $hd->{channel}, $hd->{id}) if $::expert && exists $hd->{channel};
    $info;
}

sub format_raw_hd_info {
    my ($raw_hd) = @_;

    my $info = '';
    $info .= N("Mount point: ") . "$raw_hd->{mntpoint}\n" if $raw_hd->{mntpoint};
    $info .= format_hd_info($raw_hd);
    if ($raw_hd->{type}) {
	my $type = substr(type2name($raw_hd->{type}), 0, 40); # limit the length
	$info .= N("Type: ") . $type . "\n";
    }
    $info .= N("Options: %s", $raw_hd->{options}) if $raw_hd->{options};
    $info;
}

#- get the minimal size of partition in sectors to help diskdrake on
#- limit cases, include a cylinder + start of a eventually following
#- logical partition.
sub min_partition_size { $_[0]->cylinder_size() + 2*$_[0]{geom}{sectors} }


sub choose_encrypt_key {
    my ($in) = @_;

    my ($encrypt_key, $encrypt_key2);
    $in->ask_from_(
		       {
         title => N("Filesystem encryption key"), 
	 messages => N("Choose your filesystem encryption key"),
	 callbacks => { 
	     complete => sub {
		 length $encrypt_key < 20 and $in->ask_warn('', N("This encryption key is too simple (must be at least %d characters long)", 20)), return (1,0);
		 $encrypt_key eq $encrypt_key2 or $in->ask_warn('', [ N("The encryption keys do not match"), N("Please try again") ]), return (1,1);
		 return 0
        } } }, [
{ label => N("Encryption key"), val => \$encrypt_key,  hidden => 1 },
{ label => N("Encryption key (again)"), val => \$encrypt_key2, hidden => 1 },
    ]) && $encrypt_key;
}
