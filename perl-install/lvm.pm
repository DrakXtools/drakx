package lvm; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;
use fsedit;
use devices;
use run_program;

#- for partition_table_xxx emulation
sub new {
    my ($class, $name) = @_;
    $name =~ s/\W/_/g;
    $name = substr($name, 0, 63); # max length must be < NAME_LEN / 2  where NAME_LEN is 128
    bless { disks => [], VG_name => $name }, $class;
}
sub hasExtended { 0 }
sub adjustStart {}
sub adjustEnd {}
sub write {}
sub cylinder_size { 
    my ($hd) = @_;
    $hd->{extent_size};
}

init();

sub init() {
    eval { modules::load('dm-mod') };
    devices::make('urandom');
    my $control = '/dev/mapper/control';
    if (! -e $control) {
	my ($major) = cat_('/proc/devices') =~ /(\d+) misc$/m or die "device-mapper error";
	my ($minor) = cat_('/proc/misc') =~ /(\d+) device-mapper$/m or die "device-mapper error";
	mkdir_p(dirname($control));
	syscall_('mknod', $control, c::S_IFCHR() | 0600, makedev($major, $minor)) or die "mknod $control failed: $!";	
    }
    run_program::run('lvm2', 'vgscan') if !-e '/etc/lvmtab';
    run_program::run('lvm2', 'vgchange', '-a', 'y');
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
    my ($in) = @_;

    $in->do_pkgs->ensure_is_installed('lvm2', '/sbin/lvm2') or return;
    init();
    1;
}

sub get_vg {
    my ($part) = @_;
    my $dev = expand_symlinks(devices::make($part->{device}));
    run_program::get_stdout('lvm2', 'pvs', '--noheadings', '-o', 'vg_name', $dev) =~ /(\S+)/ && $1;
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

sub get_lvs {
    my ($lvm) = @_;
    my @l = run_program::get_stdout('lvm2', 'lvs', '--noheadings', '--nosuffix', '--units', 's', '-o', 'lv_name', $lvm->{VG_name}) =~ /(\S+)/g;
    $lvm->{primary}{normal} = 
      [
       map {
	   my $device = "$lvm->{VG_name}/$_";
	   my $pt_type = -e "/dev/$device" && fsedit::typeOfPart($device);

	   { device => $device, 
	     type => $pt_type || 0x83,
	     size => get_lv_size($device) }
       } @l
      ];
}

sub vg_add {
    my ($part) = @_;
    my $dev = expand_symlinks(devices::make($part->{device}));
    lvm_cmd_or_die('pvcreate', '-y', '-ff', $dev);
    my $prog = lvm_cmd('vgs', $part->{lvm}) ? 'vgextend' : 'vgcreate';
    lvm_cmd_or_die($prog, $part->{lvm}, $dev);
}

sub vg_destroy {
    my ($lvm) = @_;

    is_empty_array_ref($lvm->{primary}{normal}) or die N("Remove the logical volumes first\n");
    lvm_cmd('vgchange', '-a', 'n', $lvm->{VG_name});
    lvm_cmd_or_die('vgremove', $lvm->{VG_name});
    foreach (@{$lvm->{disks}}) {
	delete $_->{lvm};
	$_->{isFormatted} = 0;
	$_->{notFormatted} = 1;	
    }
}

sub lv_delete {
    my ($lvm, $lv) = @_;

    lvm_cmd_or_die('lvremove', '-f', "/dev/$lv->{device}");

    my $list = $lvm->{primary}{normal};
    @$list = grep { $_ != $lv } @$list;
}

sub lv_create {
    my ($lvm, $lv) = @_;
    my $list = $lvm->{primary}{normal} ||= [];
    $lv->{lv_name} ||= 1 + max(map { if_($_->{device} =~ /(\d+)$/, $1) } @$list);
    $lv->{device} = "$lvm->{VG_name}/$lv->{lv_name}";
    lvm_cmd_or_die('lvcreate', '--size', int($lv->{size} / 2) . 'k', '-n', $lv->{lv_name}, $lvm->{VG_name});
    $lv->{size} = get_lv_size($lv->{device}); #- the created size is smaller than asked size
    $lv->{notFormatted} = 1;
    $lv->{isFormatted} = 0;
    push @$list, $lv;
}

sub lv_resize {
    my ($lv, $oldsize) = @_;
    lvm_cmd_or_die($oldsize > $lv->{size} ? ('lvreduce', '-f') : 'lvextend', 
		   '--size', int($lv->{size} / 2) . 'k', "/dev/$lv->{device}");
    $lv->{size} = get_lv_size($lv->{device}); #- the resized partition may not be the exact asked size
}

1;
