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
sub hasExtended { 0 }
sub adjustStart {}
sub adjustEnd {}
sub write {}
sub cylinder_size { 
    my ($hd) = @_;
    $hd->{PE_size};
}

init();

sub init {
    eval { modules::load('lvm-mod') };
    run_program::run('vgscan') if !-e '/etc/lvmtab';
    run_program::run('vgchange', '-a', 'y');
}

sub run {
    if (my $r = run_program::run(@_)) {
	$r;
    } else {
	$? >> 8 == 98 or return;

	#- sometimes, it needs running vgscan again, doing so:
	run_program::run('vgscan');
	run_program::run(@_);
    }
}
sub run_or_die {
    my ($prog, @para) = @_;
    run($prog, @para) or die "$prog failed\n";
}

sub check {
    my ($in) = @_;

    my $f = '/sbin/pvcreate';
    -e $f or $in->do_pkgs->install('lvm');
    -e $f or $in->ask_warn('', "Mandatory package lvm is missing"), return;
    init();
    1;
}

sub get_vg {
    my ($part) = @_;
    my $dev = expand_symlinks(devices::make($part->{device}));
    (split(':', run_program::get_stdout('pvdisplay', '-c', $dev)))[1];
}

sub update_size {
    my ($lvm) = @_;
    my @l = split(':', run_program::get_stdout('vgdisplay', '-c', '-D', $lvm->{VG_name}));
    $lvm->{totalsectors} = ($lvm->{PE_size} = $l[12]) * $l[13];
}

sub get_lv_size {
    my ($lvm_device) = @_;
    my $info = run_program::get_stdout('lvdisplay', '-D', '-c', "/dev/$lvm_device");
    (split(':', $info))[6];
}

sub get_lvs {
    my ($lvm) = @_;
    my @l = run_program::get_stdout('vgdisplay', '-v', '-D', $lvm->{VG_name});
    $lvm->{primary}{normal} = 
      [
       map {
	   my $type = -e "/dev/$_" && fsedit::typeOfPart("/dev/$_");

	   { device => $_, 
	     type => $type || 0x83,
	     size => get_lv_size($_) }
       } map { if_(m|^LV Name\s+/dev/(\S+)|, $1) } @l
      ];
}

sub vg_add {
    my ($part) = @_;
    my $dev = expand_symlinks(devices::make($part->{device}));
    run_or_die('pvcreate', '-y', '-ff', $dev);
    my $prog = run('vgdisplay', $part->{lvm}) ? 'vgextend' : 'vgcreate';
    run_or_die($prog, $part->{lvm}, $dev);
}

sub vg_destroy {
    my ($lvm) = @_;

    is_empty_array_ref($lvm->{primary}{normal}) or die N("Remove the logical volumes first\n");
    run('vgchange', '-a', 'n', $lvm->{VG_name});
    run_or_die('vgremove', $lvm->{VG_name});
    foreach (@{$lvm->{disks}}) {
	delete $_->{lvm};
	$_->{isFormatted} = 0;
	$_->{notFormatted} = 1;	
    }
}

sub lv_delete {
    my ($lvm, $lv) = @_;

    run_or_die('lvremove', '-f', "/dev/$lv->{device}");

    my $list = $lvm->{primary}{normal};
    @$list = grep { $_ != $lv } @$list;
}

sub lv_create {
    my ($lvm, $lv) = @_;
    my $list = $lvm->{primary}{normal} ||= [];
    my $nb = 1 + max(map { basename($_->{device}) } @$list);
    $lv->{device} = "$lvm->{VG_name}/$nb";
    run_or_die('lvcreate', '--size', int($lv->{size} / 2) . 'k', '-n', $nb, $lvm->{VG_name});
    $lv->{size} = get_lv_size($lv->{device}); #- the created size is smaller than asked size
    $lv->{notFormatted} = 1;
    $lv->{isFormatted} = 0;
    push @$list, $lv;
}

sub lv_resize {
    my ($lv, $oldsize) = @_;
    run_or_die($oldsize > $lv->{size} ? ('lvreduce', '-f') : 'lvextend', 
	       '--size', int($lv->{size} / 2) . 'k', "/dev/$lv->{device}");
    $lv->{size} = get_lv_size($lv->{device}); #- the resized partition may not be the exact asked size
}

1;
