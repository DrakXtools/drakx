package security::msec;

use diagnostics;
use strict;

use common;
use log;

sub get_secure_level {
    my ($prefix) = @_;
         
    cat_("$prefix/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.0 msec
    cat_("$prefix/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.1 msec
    ${{ getVarsFromSh("$prefix/etc/sysconfig/msec") }}{SECURE_LEVEL}  || #- 8.2 msec
        $ENV{SECURE_LEVEL};
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

sub get_options {
    my ($prefix, $security) = @_;
    my %options = ();
    
    %options;
}

sub choose_security_level {
    my ($in, $security, $libsafe, $email) = @_;

    my %l = (
        0 => _("Welcome To Crackers"),
        1 => _("Poor"),
        2 => _("Standard"),
        3 => _("High"), 
        4 => _("Higher"),
        5 => _("Paranoid"),
    );          

    my %help = (
        0 => _("This level is to be used with care. It makes your system more easy to use,
                but very sensitive: it must not be used for a machine connected to others
                or to the Internet. There is no password access."),
        1 => _("Password are now enabled, but use as a networked computer is still not recommended."),
        2 => _("This is the standard security recommended for a computer that will be used to connect to the Internet as a client."),
        3 => _("There are already some restrictions, and more automatic checks are run every night."),
        4 => _("With this security level, the use of this system as a server becomes possible.
                The security is now high enough to use the system as a server which can accept
                connections from many clients. Note: if your machine is only a client on the Internet, you should choose a lower level."),
        5 => _("This is similar to the previous level, but the system is entirely closed and security features are at their maximum."),
    );                
 
    delete @l{0,1}; 
    delete $l{5} if !$::expert;
																        
    $in->ask_from(
        ("DrakSec Basic Options"),
        ("Please choose the desired security level") . "\n\n" .
          join('', map { "$l{$_}: " . formatAlaTeX($help{$_}) . "\n\n" } keys %l),
        [
            { label => _("Security level"), val => $security, list => [ sort keys %l ], format => sub { $l{$_} } },
            if_($in->do_pkgs->is_installed('libsafe') && arch() =~ /^i.86/,
            { label => _("Use libsafe for servers"), val => $libsafe, type => 'bool', text =>
              _("A library which defends against buffer overflow and format string attacks.") } ),
            { label => _("Security Administrator (login or email)"), val => $email },
	    { label => _("Advanced Options"), type => 'button', clicked => sub { sec_options($in, $security) } }
        ],
    );    
}

sub sec_options {
    my ($in, $security) = @_;
    my %options = get_options('', $security);
    
    $in->ask_from(
        ("DrakSec Advanced Options"),
	("For explanations on the following options, click on the Help button"),
	[
	    %options
	],
    );
}

1;
