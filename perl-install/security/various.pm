package security::various; # $Id$

use diagnostics;
use strict;

use common;

sub config_libsafe {
    my ($prefix, $libsafe) = @_;
    my %t = getVarsFromSh("$prefix/etc/sysconfig/system");
    if (@_ > 1) {
        $t{LIBSAFE} = bool2yesno($libsafe);
        setVarsInSh("$prefix/etc/sysconfig/system", \%t);
    }
    text2bool($t{LIBSAFE});
}

sub config_security_user {
    my ($prefix, $sec_user) = @_;
    my %t = getVarsFromSh("$prefix/etc/security/msec/security.conf");
    if (@_ > 1) {
        $t{MAIL_USER} = $sec_user;
	setVarsInSh("$prefix/etc/security/msec/security.conf", \%t);
    }
    $t{MAIL_USER};
}

1;
