package partition_table::gpt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use partition_table::raw;
use c;

#sub use_pt_type { 1 }

sub read_one {
    my ($hd, $sector) = @_;
    my $info;

    c::get_disk_type($hd->{file}) eq "gpt" or die "not a GPT disk";
    my @pt = map {
        my %p;
        print $_;
        if (/^([^ ]*) ([^ ]*) ([^ ]*) (.*) \((\d*),(\d*),(\d*)\)$/) {
            $p{part_number} = $1;
            $p{real_device} = $2;
            $p{fs_type} = $3;
            $p{pt_type} = 0xba;
            $p{start} = $5;
            $p{size} = $7;
        }
        \%p;
    } c::get_disk_partitions($hd->{file});

    [ @pt ], $info;
}

sub write {
    my ($hd, $sector, $pt, $info) = @_;

    # Initialize the disk if current partition table is not gpt
    if (c::get_disk_type($hd->{file}) ne "gpt") {
        c::set_disk_type($hd->{file}, "gpt");
    }

    foreach (@{$hd->{will_tell_kernel}}) {
        my ($action, $part_number, $o_start, $o_size) = @$_;
        my $part;
        print "($action, $part_number, $o_start, $o_size)\n";
        if ($action eq 'add') {
            c::disk_add_partition($hd->{file}, $o_start, $o_size, $part->{fs_type}) or die "failed to add partition";
        } elsif ($action eq 'del') {
            c::disk_del_partition($hd->{file}, $part_number) or die "failed to del partition";
        }
    }
    common::sync();
    1;
}

sub initialize {
    my ($class, $hd) = @_;
    $hd->{primary} = { raw => [] };
    bless $hd, $class;
}

sub can_add { &can_raw_add }
sub can_raw_add { 1 }
sub raw_add {
    my ($hd, $raw, $part) = @_;
    $hd->can_raw_add or die "raw_add: partition table already full";
    push @$raw, $part;
}

sub adjustStart {}
sub adjustEnd {}

1;
