package security::msec;

use strict;
use vars qw($VERSION);
use MDK::Common::File;

$VERSION = "0.2";

=head1 NAME

msec - Perl functions to handle msec configuration files

=head1 SYNOPSYS

    require security::msec;

    my $msec = new msec;

    $secure_level = get_secure_level;

    @functions = $msec->get_functions;
    foreach @functions { %options{$_} = $msec->get_function_value($_) }
    foreach @functions { %defaults{$_} = $msec->get_function_default($_) }
    foreach @functions { $msec->config_function($_, %options{$_}) }

    @checks = $msec->get_default_checks;
    foreach @checks { %options{$_} = $msec->get_check_value($_) }
    foreach @checks { %defaults{$_} = $msec->get_check_default($_) }
    foreach @checks { $msec->config_check($_, %options{$_}) }

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


my $check_file = "$::prefix/etc/security/msec/security.conf";

my @sec_levels = ("Dangerous",  "Poor", "Standard", "High",  "Higher", "Paranoid");
my %sec_levels = ("Dangerous" => 0,  "Poor" => 1, "Standard" => 2, "High" => 3,  "Higher" => 4, "Paranoid" => 5);


# ***********************************************
#              PRIVATE FUNCTIONS
# ***********************************************

sub get_default {
    my ($option, $category) = @_;
    my $default_file = "";
    my $default_value = "";
    my $num_level = 0;

    if ($category eq "functions") {
        my $word_level = get_secure_level();
	   $num_level = $sec_levels{$word_level};
        $default_file = "$::prefix/usr/share/msec/level.".$num_level;
    }
    elsif ($category eq "checks") { $default_file = "$::prefix/var/lib/msec/security.conf"; }

    open F, $default_file;
    while (<F>) {
	   if ($category eq 'functions') {
		  if ($_ =~ /^$option/) { (undef, $default_value) = split(/ /, $_) }
	   } elsif ($category eq 'checks') {
		  if ($_ =~ /^$option/) { (undef, $default_value) = split(/=/, $_) }
	   }
    }
    close F;
    chop $default_value;
    $default_value;
}

sub get_value {
    my ($item, $category) = @_;
    my $value = '';
    my $found = 0;
    my $item_file;
    $item_file = "$::prefix/etc/security/msec/level.local" if $category eq 'functions';
    $item_file = $check_file if $category eq 'checks';

    if (-e $item_file) {
        open F, $item_file;
        while (<F>) {
            if ($_ =~ /^$item/) {
			 if ($category eq 'functions') {
				my $i = $_;
				(undef, $_) = split /\(/;
				tr/()//d;
				$value = $_;
				$_ = $i;
			 } elsif ($category eq 'checks') {
                (undef, $value) = split(/=/, $_);
			 }
                chop $value;
                $found = 1;
			 close F;
            }
        }
        close F;
	   $value = "default" if $found == 0;
    }
    else { $value = "default" }
    $value;
}

# ***********************************************
#               SPECIFIC OPTIONS
# ***********************************************

# get_secure_level() - Get the secure level

# duplicated with some drakx code

sub get_secure_level {
    shift;
    my $num_level = 2;

    $num_level = cat_("$::prefix/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 ||
                cat_("$::prefix/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 ||
                ${{ getVarsFromSh("$::prefix/etc/sysconfig/msec") }}{SECURE_LEVEL};
		# || $ENV{SECURE_LEVEL};

    return $sec_levels[$num_level];
}

sub get_seclevel_list {
    qw(Standard High Higher Paranoid);
}

sub set_secure_level {
    my $word_level = $_[1];

    my $run_level = $sec_levels{$word_level};
    system "/usr/sbin/msec", $run_level ? $run_level : 3;
}

# ***********************************************
#         FUNCTIONS (level.local) RELATED
# ***********************************************

# get_functions() -
#   return a list of functions handled by level.local (see
#   man mseclib for more info).
sub get_functions {
    shift;
    my ($category) = @_;
    my @functions = ();
    my (@tmp_network_list, @tmp_system_list);

    ## TODO handle 3 last functions here so they can be removed from this list
    my @ignore_list = qw(indirect commit_changes closelog error initlog log set_secure_level
					set_security_conf set_server_level print_changes get_translation create_server_link);

    my %options = (
	    'network' => [qw(accept_bogus_error_responses accept_broadcasted_icmp_echo accept_icmp_echo
					enable_dns_spoofing_protection enable_ip_spoofing_protection
					enable_log_strange_packets enable_promisc_check no_password_aging_for)],
	    'system' =>  [qw(allow_autologin allow_issues allow_reboot allow_remote_root_login
                         allow_root_login allow_user_list allow_x_connections allow_xserver_to_listen
                         authorize_services enable_at_crontab enable_console_log
                         enable_msec_cron enable_pam_wheel_for_su enable_password enable_security_check
                         enable_sulogin password_aging password_history password_length set_root_umask
                         set_shell_history_size set_shell_timeout set_user_umask)]);

    my $file = "$::prefix/usr/share/msec/mseclib.py";
    my $function = '';

    # read mseclib.py to get each function's name and if it's
    # not in the ignore list, add it to the returned list.
    open F, $file;
    while (<F>) {
        if ($_ =~ /^def/) {
            (undef, $function) = split(/ /, $_);
            ($function, undef) = split(/\(/, $function);
            if (!(member($function, @ignore_list))) {
                push(@functions, $function) if (member($function, @{$options{$category}}));
            }
        }
    }
    close F;

    @functions;
}

# get_function_value(function) -
#   return the value of the function passed in argument. If no value is set,
#   return "default".
sub get_function_value {
    shift;
    get_value(@_, 'functions');
}

# get_function_default(function) -
#   return the default value of the function according to the security level
sub get_function_default {
    shift;
    return get_default(@_, "functions");
}

# config_function(function, value) -
#   Apply the configuration to 'prefix'/etc/security/msec/level.local
sub config_function {
    shift;
    my ($function, $value) = @_;
    my $options_file = "$::prefix/etc/security/msec/level.local";

    if ($value eq 'default') {
	   substInFile { s/^$function.*\n// } $options_file;
    } else {
	   substInFile { s/^$function.*\n// } $options_file;
	   append_to_file($options_file, "$function ($value)")
    }
}

# ***********************************************
#     PERIODIC CHECKS (security.conf) RELATED
# ***********************************************

# get_default_checks() -
#   return a list of periodic checks handled by security.conf
sub get_default_checks {
    my $check;
    my @checks = ();

    my $check_file = "$::prefix/var/lib/msec/security.conf";

    if (-e $check_file) {
        open F, $check_file;
        while (<F>) {
            ($check, undef) = split(/=/, $_);
            push @checks, $check if (!(member($check, qw(MAIL_USER))))
        }
        close F;
    }
    @checks;
}

# get_check_value(check)
#   return the value of the check passed in argument
sub get_check_value {
    shift;
    get_value(@_, 'checks');
}

# get_check_default(check)
#   Get the default value according to the security level
sub get_check_default {
    my ($check) = @_;
    return get_default($check, 'checks');
}

# config_check(check, value)
#   Apply the configuration to "$::prefix"/etc/security/msec/security.conf
sub config_check {
    shift;
    my ($check, $value) = @_;
    if ($value eq 'default') {
	   substInFile { s/^$check.*\n// } $check_file;
    } else {
	   setVarsInSh($check_file, { $check => $value });
    }
}

sub new { shift }
1;
