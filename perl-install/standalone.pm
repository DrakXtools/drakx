package standalone; # $Id$

$::isStandalone = 1;


sub pkgs_install {
    my ($in, @l) = @_;
    $in->suspend;
    system('urpmi --auto --best-output ' . join(' ', @l));
    $in->resume;
}

1;
