package security::main;

use diagnostics;
use strict;

use common;
use log;

use security::msec;
use security::libsafe;

sub show_page {
    my ($prefix, $in, $page) = @_;
    my $signal = 9;
    my $security = security::msec::get_secure_level('');
    my $key = '';
    my %options = ();
    my ($sec_user, $libsafe) = '';

    if($page == 0) {
        $libsafe = security::libsafe::config_libsafe('');
        $sec_user = security::msec::config_security_user('');
    }
    elsif($page == 1) { %options = security::msec::get_options('', "functions"); }
    elsif($page == 2) { %options = security::msec::get_options('', "checks"); }

    if ($page == 2) {
        if(security::msec::choose_checks($in, \%options, \$signal, $security)) {
            foreach $key (keys %options) {
                security::msec::set_check('', $key, $options{$key});
    } } }
   elsif ($page == 1) {
        if(security::msec::choose_options($in, \%options, \$signal, $security)) {
            foreach $key (keys %options) {
                security::msec::config_option('', $key, $options{$key});
    } } }
    elsif ($page == 0) {
        if(security::msec::choose_security_level($in, \$security, \$libsafe, \$sec_user, \$signal)) {
            security::libsafe::config_libsafe('', $libsafe);
            security::msec::config_security_user('', $sec_user);
            $ENV{LILO_PASSWORD} = ''; # make it non interactive
            log::l("[draksec] Setting security level to $security");
            system "/usr/sbin/msec", $security;
    } }

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

        $signal = show_page($prefix, $in, $signal);
     }
}

1;
