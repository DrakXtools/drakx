package standalone; # $Id$

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";


sub pkgs_install {
    my ($in, @l) = @_;
    $in->suspend;
    my $ret = system('urpmi --auto --best-output ' . join(' ', @l));
    $in->resume;
    $ret;
}

1;
