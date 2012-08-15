package partition_table::gpt; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(partition_table::raw);

use partition_table::raw;
use c;

my $nb_primary = 128;
#sub use_pt_type { 1 }

sub read_one {
    my ($hd, $_sector) = @_;
    my $info;

    c::get_disk_type($hd->{file}) eq "gpt" or die "$hd->{device} not a GPT disk ($hd->{file})";

    my %parts = map {
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
        $p{part_number} => \%p;
    } c::get_disk_partitions($hd->{file});

    my @pt = map {
	my $part_number = $_;
	if ($parts{$part_number}) {
	    $parts{$part_number};
	} else {
	    my %p;
	    $p{part_number} = $part_number;
	    \%p;
	}
    } (1..$nb_primary);

    [ @pt ], $info;
}

sub write {
    my ($hd, $_sector, $_pt, $_info) = @_;

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
sub adjustStart {}
sub adjustEnd {}

1;
