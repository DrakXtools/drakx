package standalone; # $Id$

use c;

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");



package interactive_pkgs;

sub interactive::do_pkgs {
    my ($in) = @_;
    bless { in => $in }, 'interactive_pkgs';
}

sub install {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $ret = system('urpmi', '--auto', '--best-output', @l);
    $o->{in}->resume;
    $ret;
}

sub install_if {
    my ($o, $deps, @l) = @_;
    my @deps = deref($deps);
    system('rpm', '-q', @deps) == 0 or return;
    install($o, @l);
}

sub remove {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $ret = system('rpm', '-e ', @l);
    $o->{in}->resume;
    $ret;
}

1;
