package security::msec;

use strict;
use vars qw($VERSION);
use MDK::Common::File;
use MDK::Common;

$VERSION = "0.2";



my $check_file = "$::prefix/etc/security/msec/security.conf";



# ***********************************************
#              PRIVATE FUNCTIONS
# ***********************************************

my $num_level;

sub get_default {
    my ($option, $category) = @_;
    my $default_file = "";
    my $default_value = "";
    my $num_level = 0;

    if ($category eq "functions") {
        require security::level;
        $num_level ||= security::level::get();
        $default_file = "$::prefix/usr/share/msec/level.".$num_level;
    }
    elsif ($category eq "checks") { $default_file = "$::prefix/var/lib/msec/security.conf" }

    foreach (cat_($default_file)) {
	   if ($category eq 'functions') {
		  (undef, $default_value) = split / / if /^$option/;
	   } elsif ($category eq 'checks') {
		  (undef, $default_value) = split /=/ if /^$option/;
	   }
    }
    chop $default_value;
    $default_value;
}

sub get_value {
    my ($item, $category) = @_;
    my $value = '';
    my $item_file =
      $category eq 'functions' ? "$::prefix/etc/security/msec/level.local" :
      $category eq 'checks' ? $check_file : '';

    foreach (cat_($item_file)) {
	/^$item/ or next;

	if ($category eq 'functions') {
	    my $i = $_;
	    (undef, $_) = split /\(/;
	    s/[()]//g;
	    $value = $_;
	    $_ = $i;
	} elsif ($category eq 'checks') {
	    (undef, $value) = split(/=/, $_);
	}
	chop $value;
	return $value;
    }
    "default";
}

# ***********************************************
#               SPECIFIC OPTIONS
# ***********************************************


# ***********************************************
#         FUNCTIONS (level.local) RELATED
# ***********************************************

# get_functions() -
#   return a list of functions handled by level.local (see
#   man mseclib for more info).
sub get_functions {
    my (undef, $category) = @_;
    my @functions;

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
    my $function;

    # read mseclib.py to get each function's name and if it's
    # not in the ignore list, add it to the returned list.
    foreach (cat_($file)) {
        if (/^def/) {
            (undef, $function) = split / /;
            ($function, undef) = split(/\(/, $function);
            if (!member($function, @ignore_list) && member($function, @{$options{$category}})) {
                push(@functions, $function)
            }
        }
    }

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
    my (undef, $function, $value) = @_;
    my $options_file = "$::prefix/etc/security/msec/level.local";

    substInFile { s/^$function.*\n// } $options_file;
    append_to_file($options_file, "$function ($value)") if $value ne 'default';
}

# ***********************************************
#     PERIODIC CHECKS (security.conf) RELATED
# ***********************************************

# get_default_checks() -
#   return a list of periodic checks handled by security.conf
sub get_default_checks {
    map { if_(/(.*?)=/, $1) } cat_("$::prefix/var/lib/msec/security.conf");
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
    my (undef, $check, $value) = @_;
    if ($value eq 'default') {
	   substInFile { s/^$check.*\n// } $check_file;
    } else {
	   setVarsInSh($check_file, { $check => $value });
    }
}

sub new { shift }
1;
