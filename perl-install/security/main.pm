package security::main;

use diagnostics;
use strict;

use common;
use log;

use security::msec;
use security::libsafe;

sub basic_page {
    my ($prefix, $in) = @_;
    my $security = security::msec::get_secure_level('');
    my $libsafe = security::libsafe::config_libsafe('');
    my $sec_user = security::msec::config_security_user('');
    my $signal = 9;

    if(security::msec::choose_security_level($in, \$security, \$libsafe, \$sec_user, \$signal)) {
        log::l("[draksec] Setting libsafe activation variable to $libsafe");
        security::libsafe::config_libsafe('', $libsafe);

        log::l("[draksec] Setting security administrator contact to $sec_user");
        security::msec::config_security_user('', $sec_user);

#        my $w = $in->wait_message('', _("Setting security level"));
#        $in->suspend;
        $ENV{LILO_PASSWORD} = ''; # make it non interactive
        log::l("[draksec] Setting security level to $security");
        system "/usr/sbin/msec", $security;
#       $in->resume;
    }
    $signal;
}

sub functions_page {
    my ($prefix, $in) = @_;
    my $signal = 9;
    my $security = security::msec::get_secure_level('');
    my %functions = security::msec::get_options('', $security);
    my $key = '';

    if(security::msec::choose_options($in, \%functions, \$signal, $security)) {
        foreach $key (keys %functions) {
            security::msec::set_option('', $key, $functions{$key});
        }
    }
    $signal;
}

sub main {
    my ($prefix, $in)  = @_;
    my $signal = 0;

    while ($signal != 9) {
        # signal 0 = basic page
	# signal 1 = first advanced page (functions)
	# signal 2 = checks page
	# signal 3 = permissions page
	# signal 4 = firewall page
	# signal 5 = users page
	# signal 9 = quit

        if ($signal == 0) { $signal = basic_page($prefix, $in); }
        elsif ($signal == 1) { $signal = functions_page($prefix, $in); }
    }
}

1;
