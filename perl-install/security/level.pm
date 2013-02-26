package security::level;

use strict;
use common;
use run_program;
# perl_checker: require interactive

sub level_list() {
    (
     0 => N("Disable msec"),
     1 => N("Standard"),
     2 => N("Secure"),
    );
}

sub to_string { +{ level_list() }->{$_[0]} }
sub from_string { +{ reverse level_list() }->{$_[0]} || 2 }

sub get_string() { to_string(get() || 2) }
sub get_common_list() { map { to_string($_) } (1, 2, 3, 4, 5) }

sub get() {
    ${{ getVarsFromSh("$::prefix/etc/security/msec/security.conf") }}{BASE_LEVEL}  || #- 2009.1 msec
    1;
}

sub set {
    my ($security) = @_;
    my @levelnames = ('none', 'standard', 'secure');
    # use Standard level if specified level is out of range
    $security = 1 if $security > $#levelnames;
    run_program::rooted($::prefix, 'msec', '-q', '-f', $levelnames[$security]);
    run_program::rooted($::prefix, 'msecperms', '-q', '-e', $levelnames[$security]);
}

sub level_choose {
    my ($in, $security, $email) = @_; # perl_checker: $in = interactive->new

    my %help = (
      0 => N("This level is to be used with care, as it disables all additional security
provided by msec. Use it only when you want to take care of all aspects of system security
on your own."),
      1 => N("This is the standard security recommended for a computer that will be used to connect to the Internet as a client."),
      2 => N("With this security level, the use of this system as a server becomes possible.
The security is now high enough to use the system as a server which can accept
connections from many clients. Note: if your machine is only a client on the Internet, you should choose a lower level."),
    );

    my @l = 1 .. 2;

    $in->ask_from_({ title => $::isInstall ? N("Security") : N("DrakSec Basic Options"),
             interactive_help_id => 'misc-params#draxid-miscellaneous',
           }, [
              { label => N("Please choose the desired security level"), title => 1 },
              { val => $security, list => \@l, 
                format => sub {
                    #-PO: this string is used to properly format "<security level>: <level description>"
                    N("%s: %s", to_string($_[0]), formatAlaTeX($help{$_[0]}));
                },
                type => 'list', gtk => { use_boxradio => 1 } },
                { label => N("Security Administrator:"), title => 1 },
                { label => N("Login or email:"), val => $email, },
            ],
    );
}


1;
