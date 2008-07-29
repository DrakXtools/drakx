package security::level;

use strict;
use common;
use run_program;


sub level_list() {
    (
     0 => N("Welcome To Crackers"),
     1 => N("Poor"),
     2 => N("Standard"),
     3 => N("High"),
     4 => N("Higher"),
     5 => N("Paranoid"),
    );
}

sub to_string { +{ level_list() }->{$_[0]} }
sub from_string { +{ reverse level_list() }->{$_[0]} || 2 }

sub get_string() { to_string(get() || 2) }
sub get_common_list() { map { to_string($_) } (1, 2, 3, 4, 5) }

sub get() {
    cat_("$::prefix/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.0 msec
    cat_("$::prefix/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.1 msec
      ${{ getVarsFromSh("$::prefix/etc/sysconfig/msec") }}{SECURE_LEVEL}  || #- 8.2 msec
	$ENV{SECURE_LEVEL} || 3;
}

sub set {
    my ($security) = @_;
    run_program::rooted($::prefix, 'msec', '-o', 'run_commands=0', '-o', 'log=stderr', $security || 3);
}

sub level_choose {
    my ($in, $security, $libsafe, $email) = @_;

    my %help = (
      0 => N("This level is to be used with care. It makes your system more easy to use,
but very sensitive. It must not be used for a machine connected to others
or to the Internet. There is no password access."),
      1 => N("Passwords are now enabled, but use as a networked computer is still not recommended."),
      2 => N("This is the standard security recommended for a computer that will be used to connect to the Internet as a client."),
      3 => N("There are already some restrictions, and more automatic checks are run every night."),
      4 => N("With this security level, the use of this system as a server becomes possible.
The security is now high enough to use the system as a server which can accept
connections from many clients. Note: if your machine is only a client on the Internet, you should choose a lower level."),
      5 => N("This is similar to the previous level, but the system is entirely closed and security features are at their maximum."),
    );

    my @l = 2 .. 5;

    $in->ask_from_({ title => $::isInstall ? N("Security") : N("DrakSec Basic Options"),
		     messages => N("Please choose the desired security level") . "\n\n" .
		                 join('', map { to_string($_) . ": " . formatAlaTeX($help{$_}) . "\n\n" } @l),
		     interactive_help_id => 'miscellaneous',
		   }, [
              { label => N("Security level"), val => $security, list => \@l, format => \&to_string },
                if_($in->do_pkgs->is_installed('libsafe') && arch() =~ /^i.86/,
                { label => N("Use libsafe for servers"), val => $libsafe, type => 'bool', text =>
                  N("A library which defends against buffer overflow and format string attacks.") }),
                { label => N("Security Administrator (login or email)"), val => $email, },
            ],
    );
}


1;
