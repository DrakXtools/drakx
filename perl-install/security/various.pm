package security::various; # $Id$

use diagnostics;
use strict;

use common;

sub config_libsafe {
    my $setting = @_ > 1;
    my ($prefix, $libsafe) = @_;
    if ($setting) {
        addVarsInSh("$prefix/etc/sysconfig/system", { LIBSAFE => bool2yesno($libsafe) });
    } else {
	my %t = getVarsFromSh("$prefix/etc/sysconfig/system");
	text2bool($t{LIBSAFE});
    }
}

sub config_security_user {
    my $setting = @_ > 1;
    my ($prefix, $sec_user) = @_;
    if ($setting) {
	addVarsInSh("$prefix/etc/security/msec/security.conf", { MAIL_USER => $sec_user });
    } else {
	my %t = getVarsFromSh("$prefix/etc/security/msec/security.conf");
	$t{MAIL_USER};
    }
}

1;
