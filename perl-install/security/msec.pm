package security::msec;

use strict;
use vars qw($VERSION);

$VERSION = "0.2";

=head1 NAME

msec - Perl functions to handle msec configuration files

=head1 SYNOPSYS

    require security::msec;

    my $msec = new msec;

    $secure_level = get_secure_level($prefix);

    @functions = $msec->get_functions($prefix);
    foreach @functions { %options{$_} = $msec->get_function_value($prefix, $_) }
    foreach @functions { %defaults{$_} = $msec->get_function_default($prefix, $_) }
    foreach @functions { $msec->config_function($prefix, $_, %options{$_}) }

    @checks = $msec->get_checks($prefix);
    foreach @checks { %options{$_} = $msec->get_check_value($prefix, $_) }
    foreach @checks { %defaults{$_} = $msec->get_check_default($prefix, $_) }
    foreach @checks { $msec->config_check($prefix, $_, %options{$_}) }

=head1 DESCRIPTION

C<msec> is a perl module used by draksec to customize the different options
that can be set in msec's configuration files.

=head1 COPYRIGHT

Copyright (C) 2000,2001,2002 MandrakeSoft <cbelisle@mandrakesoft.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

use MDK::Common;

# ***********************************************
#              PRIVATE FUNCTIONS
# ***********************************************
sub config_option {
    my ($prefix, $option, $value, $category) =@_;
    my %options_hash = ( );
    my $key = "";
    my $options_file = "";

    if($category eq "functions") { $options_file = "$prefix/etc/security/msec/level.local"; }
    elsif($category eq "checks") { $options_file ="$prefix/etc/security/msec/security.conf"; }

    if(-e $options_file) {
        open F, $options_file;
        if($category eq "functions") {
            while(<F>) {
               if (!($_ =~ /^from mseclib/) && $_ ne "\n") {
                   my ($name, $value_set) = split (/\(/, $_);
                   chop $value_set; chop $value_set;
                   $options_hash{$name} = $value_set;
               }
            }
        }
        elsif($category eq "checks") {
            %options_hash = getVarsFromSh($options_file);
        }
        close F;
    }

    $options_hash{$option} = $value;

    open F, '>'.$options_file;
    if ($category eq "functions") { print F "from mseclib import *\n\n"; }
    foreach $key (keys %options_hash) {
        if ($options_hash{$key} ne "default") {
            if($category eq "functions") { print F "$key"."($options_hash{$key})\n"; }
            elsif($category eq "checks") { print F "$key=$options_hash{$key}\n"; }
        }
    }
    close F;
}

sub get_default {
    my ($prefix, $option, $category) = @_;
    my $default_file = "";
    my $default_value = "";
    my $num_level = 0;

    if ($category eq "functions") {
        my $word_level = get_secure_level($prefix);
        if ($word_level eq "Dangerous") { $num_level = 0 }
        elsif ($word_level eq "Poor") { $num_level = 1 }
        elsif ($word_level eq "Standard") { $num_level = 2 }
        elsif ($word_level eq "High") { $num_level = 3 }
        elsif ($word_level eq "Higher") { $num_level = 4 }
        elsif ($word_level eq "Paranoid") { $num_level = 5 }
        $default_file = "$prefix/usr/share/msec/level.".$num_level;
    }
    elsif ($category eq "checks") { $default_file = "$prefix/var/lib/msec/security.conf"; }

    open F, $default_file;
    if($category eq "functions") {
        while(<F>) {
            if ($_ =~ /^$option/) { (undef, $default_value) = split(/ /, $_); }
	}
    }
    elsif ($category eq "checks") {
        while(<F>) {
            if ($_ =~ /^$option/) { (undef, $default_value) = split(/=/, $_); }
	}
    }
    close F;
    chop $default_value;

    $default_value;
}

# ***********************************************
#                 EXPLANATIONS
# ***********************************************
sub seclevel_explain {
"Standard: This is the standard security recommended for a computer that will be used to connect
               to the Internet as a client.

High:       There are already some restrictions, and more automatic checks are run every night.

Higher:    The security is now high enough to use the system as a server which can accept
              connections from many clients. If your machine is only a client on the Internet, you
	      should choose a lower level.

Paranoid:  This is similar to the previous level, but the system is entirely closed and security
                features are at their maximum

Security Administrator:
               If the 'Security Alerts' option is set, security alerts will be sent to this user (username or
	       email)";
}

# ***********************************************
#               SPECIFIC OPTIONS
# ***********************************************

# get_secure_level(prefix) - Get the secure level
sub get_secure_level {
    shift @_;
    my $prefix = $_;
    my $num_level = 2;

    $num_level = cat_("$prefix/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 ||
                cat_("$prefix/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 ||
                ${{ getVarsFromSh("$prefix/etc/sysconfig/msec") }}{SECURE_LEVEL};
		# || $ENV{SECURE_LEVEL};

    if ($num_level == 0) { return "Dangerous" }
    elsif ($num_level == 1) { return "Poor" }
    elsif ($num_level == 2) { return "Standard" }
    elsif ($num_level == 3) { return "High" }
    elsif ($num_level == 4) { return "Higher" }
    elsif ($num_level == 5) { return "Paranoid" }
}

sub get_seclevel_list {
    qw(Standard High Higher Paranoid);
}

sub set_secure_level {
    my $word_level = $_[1];
    my $num_level = 0;

    if ($word_level eq "Dangerous") { $num_level = 0 }
    elsif ($word_level eq "Poor") { $num_level = 1 }
    elsif ($word_level eq "Standard") { $num_level = 2 }
    elsif ($word_level eq "High") { $num_level = 3 }
    elsif ($word_level eq "Higher") { $num_level = 4 }
    elsif ($word_level eq "Paranoid") { $num_level = 5 }

    system "/usr/sbin/msec", $num_level;
}

# ***********************************************
#         FUNCTIONS (level.local) RELATED
# ***********************************************

# get_functions(prefix) -
#   return a list of functions handled by level.local (see
#   man mseclib for more info).
sub get_functions {
    shift;
    my ($prefix, $category) = @_;
    my @functions = ();
    my (@tmp_network_list, @tmp_system_list);

    ## TODO handle 3 last functions here so they can be removed from this list
    my @ignore_list = qw(indirect commit_changes closelog error initlog log set_secure_level
                                       set_security_conf set_server_level print_changes get_translation
                                       create_server_link);

    my @network_list = qw(accept_bogus_error_responses accept_broadcasted_icmp_echo accept_icmp_echo
                          enable_dns_spoofing_protection enable_ip_spoofing_protection
                          enable_log_strange_packets enable_promisc_check no_password_aging_for);

    my @system_list = qw(allow_autologin allow_issues allow_reboot allow_remote_root_login
                         allow_root_login allow_user_list allow_x_connections allow_xserver_to_listen
                         authorize_services enable_at_crontab enable_console_log enable_libsafe
                         enable_msec_cron enable_pam_wheel_for_su enable_password enable_security_check
                         enable_sulogin password_aging password_history password_length set_root_umask
                         set_shell_history_size set_shell_timeout set_user_umask);

    my $file = "$prefix/usr/share/msec/mseclib.py";
    my $function = '';

    print "$prefix\n";
    # read mseclib.py to get each function's name and if it's
    # not in the ignore list, add it to the returned list.
    open F, $file;
    while (<F>) {
        if ($_ =~ /^def/) {
            (undef, $function) = split(/ /, $_);
            ($function, undef) = split(/\(/, $function);
            if (!(member($function, @ignore_list))) {
                if($category eq "network" && member($function, @network_list)) { push(@functions, $function) }
                elsif($category eq "system" && member($function, @system_list)) { push(@functions, $function) }
            }
        }
    }
    close F;

    @functions;
}

# get_function_value(prefix, function) -
#   return the value of the function passed in argument. If no value is set,
#   return "default".
sub get_function_value {
    my ($prefix, $function) = @_;
    my $value = '';
    my $msec_options = "$prefix/etc/security/msec/level.local";
    my $found = 0;

    if (-e $msec_options) {
        open F, $msec_options;
        while(<F>) {
            if($_ =~ /^$function/) {
                (undef, $value) = split(/\(/, $_);
                chop $value; chop $value;
                $found = 1;
            }
        }
        close F;
	if ($found == 0) { $value = "default" }
    }
    else { $value = "default" }

    $value;
}

# get_function_default(prefix, function) -
#   return the default value of the function according to the security level
sub get_function_default {
    shift;
    my ($prefix, $function) = @_;
    return get_default($prefix, $function, "functions");
}

# config_function(prefix, function, value) -
#   Apply the configuration to 'prefix'/etc/security/msec/level.local
sub config_function {
    my ($prefix, $function, $value) = @_;
    config_option($prefix, $function, $value, "functions");
}

# ***********************************************
#     PERIODIC CHECKS (security.conf) RELATED
# ***********************************************

# get_checks(prefix) -
#   return a list of periodic checks handled by security.conf
sub get_checks {
    my $prefix = $_;
    my $check;
    my @checks = ();

    my $check_file = "$prefix/var/lib/msec/security.conf";
    my @ignore_list = qw(MAIL_USER);

    if (-e $check_file) {
        open F, $check_file;
        while (<F>) {
            ($check, undef) = split(/=/, $_);
            if(!(member($check, @ignore_list))) { push(@checks, $check) }
        }
        close F;
    }

    @checks;
}

# get_check_value(prefix, check)
#   return the value of the check passed in argument
sub get_check_value {
    shift @_;
    my ($prefix, $check) = @_;
    my $check_file = "$prefix/etc/security/msec/security.conf";
    my $value = '';
    my $found = 0;

    if (-e $check_file) {
        open F, $check_file;
	while(<F>) {
            if($_ =~ /^$check/) {
                (undef, $value) = split(/=/, $_);
		chop $value;
		$found = 1;
            }
        }
	close F;
	if ($found == 0) { $value = "default" }
    }
    else { $value = "default" }

    $value;
}

# get_check_default(prefix, check)
#   Get the default value according to the security level
sub get_check_default {
    my ($prefix, $check) = @_;
    return get_default($prefix, $check, "checks");
}

# config_check(prefix, check, value)
#   Apply the configuration to "prefix"/etc/security/msec/security.conf
sub config_check {
    shift @_;
    my ($prefix, $check, $value) = @_;
    config_option($prefix, $check, $value, "checks");
}

sub new { shift }
1;
