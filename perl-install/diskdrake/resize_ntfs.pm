package diskdrake::resize_ntfs;

use diagnostics;
use strict;

use run_program;
use common;


sub new {
    my ($type, $_device, $dev) = @_;
    bless { dev => $dev }, $type;
}

sub min_size {
    my ($o) = @_;
    my $r = run_program::get_stdout('ntfsresize', '-f', '-i', $o->{dev});
    $r =~ /minimal size: (\d+) KiB/ && $1 * 2 
}

sub resize {
    my ($o, $size) = @_;
    run_program::run_or_die('ntfsresize', '-ff', '-s' . int($size / 2) . 'ki', $o->{dev});
}

1;
