package security::libsafe;

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

1;
