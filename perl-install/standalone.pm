package standalone; # $Id$

use c;

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");



################################################################################
package pkgs_interactive;

sub interactive::do_pkgs {
    my ($in) = @_;
    bless { in => $in }, 'pkgs_interactive';
}

sub install {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $wait = $in->wait_message('', _("Installing packages..."));
    my $ret = system('urpmi', '--allow-medium-change', '--auto', '--best-output', @l) == 0;
    undef $wait;
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
