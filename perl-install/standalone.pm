package standalone; # $Id$

use c;

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");



################################################################################
package interactive_pkgs;

sub interactive::do_pkgs {
    my ($in) = @_;
    bless { in => $in }, 'interactive_pkgs';
}

sub install {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $ret = system('urpmi', '--auto', '--best-output', @l) == 0;
    $o->{in}->resume;
    $ret;
}

sub is_installed {
    my ($o, @l) = @_;
    system('rpm', '-q', @l) == 0;
}

sub remove {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $ret = system('rpm', '-e', @l) == 0;
    $o->{in}->resume;
    $ret;
}

sub remove_nodeps {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $ret = system('rpm', '-e', '--nodeps', @l) == 0;
    $o->{in}->resume;
    $ret;
}
################################################################################

package standalone;

1;
