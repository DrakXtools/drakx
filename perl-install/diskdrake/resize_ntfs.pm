package diskdrake::resize_ntfs;

use diagnostics;
use strict;

use run_program;
use common;


sub new {
    my ($type, $_device, $dev) = @_;
    bless { dev => $dev }, $type;
}

sub check_prog {
    my ($in) = @_;
    #- ensure_binary_is_installed checks binary chrooted, whereas we run the binary non-chrooted (pb for Mandriva One)
    $::isInstall || whereis_binary('ntfsresize') || $in->do_pkgs->ensure_binary_is_installed('ntfsprogs', 'ntfsresize');
}

sub min_size {
    my ($o) = @_;
    my $r;
    run_program::run('ntfsresize', '>', \$r, '-f', '-i', $o->{dev}) or die "ntfsresize failed:\n$r\n";
    $r =~ /minimal size: (\d+) KiB/ && $1 * 2; 
}

sub resize {
    my ($o, $size) = @_;
    my @l = ('-ff', '-s' . int($size / 2) . 'ki', $o->{dev});
    my $r;
    run_program::run('ntfsresize', '>', \$r, '-n', @l) or die "ntfsresize failed: $r\n";
    run_program::raw({ timeout => 'never' }, 'ntfsresize', '>', \$r, @l) or die "ntfsresize failed: $r\n";
}

1;
