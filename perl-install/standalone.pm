package standalone; # $Id$

use c;

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");


sub pkgs_install {
    my ($in, @l) = @_;
    $in->suspend;
    my $ret = system('urpmi --auto --best-output ' . join(' ', @l));
    $in->resume;
    $ret;
}

1;
