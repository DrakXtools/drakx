package security::security;

use diagnostics
use strict;

use common;
use security::msec;
use log;

sub config_libsafe {
    my ($prefix, $libsafe) = @_;
    my %t = getVarsFromSh("$prefix/etc/sysconfig/system");
    if (@_ > 1) {
        $t{LIBSAFE} = bool2yesno($libsafe);
        setVarsInSh("$prefix/etc/sysconfig/system", \%t);
    }
    text2bool($t{LIBSAFE});
}           

sub main {
    my ($in, $security, $libsafe, $sec_user) = @_;
 
    if (security::msec::choose_security_level($in, \$security, \$libsafe, \$sec_user)) {
        log::l("[draksec] Setting libsafe activation variable to $libsafe");
        config_libsafe('', $libsafe);
				    
        log::l("[draksec] Setting security administrator contact to $sec_user");
	security::msec::config_security_user('', $sec_user);

        my $w = $in->wait_message('', _("Setting security level"));
        $in->suspend;
        $ENV{LILO_PASSWORD} = ''; # make it non interactive
        log::l("[draksec] Setting security level to $security");
        system "/usr/sbin/msec", $security;
        $in->resume;
    }   
}
												    
1;
