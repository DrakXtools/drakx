package security::various;

use diagnostics;
use strict;

use common;

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
