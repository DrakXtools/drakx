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
    (split(':', `pvdisplay -c $dev`))[1];
}

sub update_size {
    my ($lvm) = @_;
    my @l = split(':', `vgdisplay -c -D $lvm->{LVMname}`);
    $lvm->{totalsectors} = ($lvm->{PE_size} = $l[12]) * $l[13];
}

sub get_lvs {
    my ($lvm) = @_;
    $lvm->{primary}{normal} = 
      [
       map {
	   my $type = -e "/dev/$_" && fsedit::typeOfPart("/dev/$_");
	   { device => $_, 
	     type => $type || 0x83,
	     size => (split(':', `lvdisplay -D -c /dev/$_`))[6] }
       } map { m|^LV Name\s+/dev/(\S+)| ? $1 : () } `vgdisplay -v -D $lvm->{LVMname}`
      ];
}

sub vg_add {
    my ($part) = @_;
    if (my $old_name = get_vg($part)) {
	run_program::run('vgchange', '-a', 'n', $old_name);
	run_program::run('vgremove', $old_name);	
    }
    my $dev = expand_symlinks(devices::make($part->{device}));
    run_program::run_or_die('pvcreate', '-y', '-ff', $dev);
    my $prog = run_program::run('vgdisplay', $part->{lvm}) ? 'vgextend' : 'vgcreate';
    run_program::run_or_die($prog, $part->{lvm}, $dev);
}

sub vg_destroy {
    my ($lvm) = @_;

    is_empty_array_ref($lvm->{primary}{normal}) or die _("Remove the logical volumes first\n");
    run_program::run('vgchange', '-a', 'n', $lvm->{LVMname});
    run_program::run_or_die('vgremove', $lvm->{LVMname});
    foreach (@{$lvm->{disks}}) {
	delete $_->{lvm};
	$_->{isFormatted} = 0;
	$_->{notFormatted} = 1;	
    }
}

sub lv_delete {
    my ($lvm, $lv) = @_;

    run_program::run_or_die('lvremove', '-f', "/dev/$lv->{device}");

    my $list = $lvm->{primary}{normal};
    @$list = grep { $_ != $lv } @$list;
}

sub lv_create {
    my ($lvm, $lv) = @_;
    my $list = $lvm->{primary}{normal};
    my $nb = 1 + max(map { basename($_->{device}) } @$list);
    $lv->{device} = "$lvm->{LVMname}/$nb";
    run_program::run_or_die('lvcreate', '--size', int($lv->{size} / 2) . 'k', '-n', $nb, $lvm->{LVMname});
    $lv->{notFormatted} = 1;
    $lv->{isFormatted} = 0;
    push @$list, $lv;
}

sub lv_resize {
    my ($lv, $oldsize) = @_;
    run_program::run_or_die($oldsize > $lv->{size} ? ('lvreduce', '-f') : 'lvextend', 
			    '--size', int($lv->{size} / 2) . 'k', "/dev/$lv->{device}");
}

1;
