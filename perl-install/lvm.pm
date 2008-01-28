package lvm; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;
use devices;
use fs::type;
use run_program;

#- for partition_table_xxx emulation
sub new {
    my ($class, $name) = @_;
    $name =~ s/[^\w-]/_/g;
    $name = substr($name, 0, 63); # max length must be < NAME_LEN / 2  where NAME_LEN is 128
    bless { disks => [], VG_name => $name }, $class;
}
sub use_pt_type { 0 }
sub hasExtended { 0 }
sub adjustStart {}
sub adjustEnd {}
sub write {}
sub cylinder_size { 
    my ($hd) = @_;
    $hd->{extent_size};
}

init() or log::l("lvm::init failed");

sub init() {
    devices::init_device_mapper();
    if ($::isInstall) {
	run_program::run('lvm2', 'vgscan');
	run_program::run('lvm2', 'vgchange', '-a', 'y');
    }
    1;
}

sub lvm_cmd {
    if (my $r = run_program::run('lvm2', @_)) {
	$r;
    } else {
	$? >> 8 == 98 or return;

	#- sometimes, it needs running vgscan again, doing so:
	run_program::run('lvm2', 'vgscan');
	run_program::run('lvm2', @_);
    }
}
sub lvm_cmd_or_die {
    my ($prog, @para) = @_;
    lvm_cmd($prog, @para) or die "$prog failed\n";
}

sub check {
    my ($do_pkgs) = @_;

    $do_pkgs->ensure_binary_is_installed('lvm2', 'lvm2') or return;
    init();
    1;
}

sub get_pv_field {
    my ($pv, $field) = @_;
    my $dev = expand_symlinks(devices::make($pv->{device}));
    run_program::get_stdout('lvm2', 'pvs', '--noheadings', '--nosuffix', '-o', $field, $dev);
}
sub pv_physical_extents {
    my ($pv) = @_;
    split(' ', lvm::get_pv_field($pv, 'pv_pe_alloc_count,pv_pe_count'));
}
sub pv_to_vg {
    my ($pv) = @_;
    get_pv_field($pv, 'vg_name') =~ /(\S+)/ && $1;
}

sub pv_move {
    my ($pv) = @_;
    my $dev = expand_symlinks(devices::make($pv->{device}));
    lvm_cmd('pvmove', '-v', $dev) or die N("Moving used physical extents to other physical volumes failed");
}

sub update_size {
    my ($lvm) = @_;
    $lvm->{extent_size} = to_int(run_program::get_stdout('lvm2', 'vgs', '--noheadings', '--nosuffix', '--units', 's', '-o', 'vg_extent_size', $lvm->{VG_name}));
    $lvm->{totalsectors} = to_int(run_program::get_stdout('lvm2', 'vgs', '--noheadings', '--nosuffix', '--units', 's', '-o', 'vg_size', $lvm->{VG_name}));
}

sub get_lv_size {
    my ($lvm_device) = @_;
    to_int(run_program::get_stdout('lvm2', 'lvs', '--noheadings', '--nosuffix', '--units', 's', '-o', 'lv_size', "/dev/$lvm_device"));
}

sub lv_to_pvs {
    my ($lv) = @_;
    map { m!(\S+)\(! } run_program::get_stdout('lvm2', 'lvs', '--noheadings', '-o', 'devices', "/dev/$lv->{device}");
}
sub lv_nb_pvs {
    my ($lv) = @_;
    listlength(lv_to_pvs($lv));      
}

sub get_lvs {
    my ($lvm) = @_;
    my @l = run_program::get_stdout('lvm2', 'lvs', '--noheadings', '--nosuffix', '--units', 's', '-o', 'lv_name', $lvm->{VG_name}) =~ /(\S+)/g;
    $lvm->{primary}{normal} = 
      [
       map {
	   my $device = "$lvm->{VG_name}/$_";
	   my $part = {
	     device => $device, 
	     lv_name => $_,
	     rootDevice => $lvm->{VG_name},
	     size => get_lv_size($device) };
	   if (my $type = -e "/dev/$device" && fs::type::type_subpart_from_magic($part)) {
                put_in_hash($part, $type); 	       
	   } else {
	       $part->{fs_type} = 'ext2';
	   }
	   $part;
       } @l
      ];
}

sub vg_add {
    my ($part) = @_;
    my $dev = expand_symlinks(devices::make($part->{device}));
    output($dev, '\0' x 512); #- help pvcreate
    lvm_cmd_or_die('pvcreate', '-y', '-ff', $dev);
    my $prog = lvm_cmd('vgs', $part->{lvm}) ? 'vgextend' : 'vgcreate';
    lvm_cmd_or_die($prog, $part->{lvm}, $dev);
}

sub vg_reduce {
    my ($lvm_vg, $part_pv) = @_;

    lvm_cmd('vgreduce', $lvm_vg->{VG_name}, devices::make($part_pv->{device})) or die N("Physical volume %s is still in use", $part_pv->{device});
    @{$lvm_vg->{disks}} = difference2($lvm_vg->{disks}, [ $part_pv ]);
    update_size($lvm_vg);
    delete $part_pv->{lvm};
    set_isFormatted($part_pv, 0);
}

sub vg_destroy {
    my ($lvm) = @_;

    is_empty_array_ref($lvm->{primary}{normal}) or die N("Remove the logical volumes first\n");
    lvm_cmd('vgchange', '-a', 'n', $lvm->{VG_name});
    lvm_cmd_or_die('vgremove', $lvm->{VG_name});
    foreach (@{$lvm->{disks}}) {
	lvm_cmd_or_die('pvremove', devices::make($_->{device}));
	delete $_->{lvm};
	set_isFormatted($_, 0);
    }
}

sub lv_delete {
    my ($lvm, $lv) = @_;

    lvm_cmd_or_die('lvremove', '-f', "/dev/$lv->{device}");

    my $list = $lvm->{primary}{normal};
    @$list = grep { $_ != $lv } @$list;
}

sub suggest_lv_name {
    my ($lvm, $lv) = @_;
    my $list = $lvm->{primary}{normal} ||= [];
    $lv->{lv_name} ||= 1 + max(map { if_($_->{device} =~ /(\d+)$/, $1) } @$list);
}

sub lv_create {
    my ($lvm, $lv) = @_;
    suggest_lv_name($lvm, $lv);
    $lv->{device} = "$lvm->{VG_name}/$lv->{lv_name}";
    lvm_cmd_or_die('lvcreate', '--size', int($lv->{size} / 2) . 'k', '-n', $lv->{lv_name}, $lvm->{VG_name});

    if ($lv->{mntpoint} eq '/boot' && lv_nb_pvs($lv) > 1) {
	lvm_cmd_or_die('lvremove', '-f', "/dev/$lv->{device}");
	die N("The bootloader can't handle /boot on multiple physical volumes");
    }

    $lv->{size} = get_lv_size($lv->{device}); #- the created size is smaller than asked size
    set_isFormatted($lv, 0);
    my $list = $lvm->{primary}{normal} ||= [];
    push @$list, $lv;
}

sub lv_resize {
    my ($lv, $oldsize) = @_;
    lvm_cmd_or_die($oldsize > $lv->{size} ? ('lvreduce', '-f') : 'lvextend', 
		   '--size', int($lv->{size} / 2) . 'k', "/dev/$lv->{device}");
    $lv->{size} = get_lv_size($lv->{device}); #- the resized partition may not be the exact asked size
}

sub add_to_VG {
    my ($part, $lvm) = @_;

    $part->{lvm} = $lvm->{VG_name};
    push @{$lvm->{disks}}, $part;
    delete $part->{mntpoint};

    vg_add($part);
    update_size($lvm);
}

sub create_singleton_vg {
    my ($lvms, $part) = @_;

    my %existing = map { $_->{VG_name} => 1 } @$lvms;
    my $VG_name = find { !$existing{$_} } map { "VG$_" } 1 .. 100 or internal_error();    

    my $lvm = new lvm($VG_name);
    push @$lvms, $lvm;

    add_to_VG($part, $lvm);
}

1;
