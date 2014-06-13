package diskdrake::resize_ext2;

use diagnostics;
use strict;

use run_program;
use common;


sub new {
    my ($type, $_device, $dev) = @_;

    my $o = bless { dev => $dev }, $type;

    my $r = run_program::get_stdout('dumpe2fs', $dev);
    $o->{block_count} = $r =~ /^Block count:\s*(\d+)/m && $1;
    $o->{free_block} = $r =~ /^Free blocks:\s*(\d+)/m && $1;
    $o->{block_size} = $r =~ /^Block size:\s*(\d+)/m && $1;
    log::l("dumpe2fs $dev gives: Block_count=$o->{block_count}, Free_blocks=$o->{free_block}, Block_size=$o->{block_size}");

    $o->{block_size} && $o;
}

sub min_size {
    my ($o) = @_;
    ($o->{block_count} - $o->{free_block}) * ($o->{block_size} / 512);
}

sub resize {
    my ($o, $size) = @_;

    my $s = int($size / ($o->{block_size} / 512));
    log::l("resize2fs $o->{dev} to size $s in block of $o->{block_size} bytes");
    run_program::raw({ timeout => 60 * 60 }, "resize2fs", "-pf", $o->{dev}, $s) or die "resize2fs failed";
}

1;
