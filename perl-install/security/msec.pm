package security::msec;

use strict;
use MDK::Common::File;
use MDK::Common;


#-------------------------------------------------------------
# msec files

my $check_file    = "$::prefix/etc/security/msec/security.conf";
my $curr_sec_file = "$::prefix/var/lib/msec/security.conf";
my $options_file  = "$::prefix/etc/security/msec/level.local";

# ***********************************************
#              PRIVATE FUNCTIONS
# ***********************************************

my $num_level;


#-------------------------------------------------------------
# msec options managment methods


#-------------------------------------------------------------
# option defaults

sub load_defaults {
    my ($category) = @_;
    my $default_file;
    my $num_level = 0;

    if ($category eq 'functions') {
        require security::level;
        $num_level ||= security::level::get();
        $default_file = "$::prefix/usr/share/msec/level.".$num_level;
    }
    elsif ($category eq 'checks') { $default_file = $curr_sec_file }

    my $separator = $category eq 'functions' ? ' ' : $category eq 'checks' ? '=' : undef;
    do { print "BACKTRACE:\n", backtrace(), "\n"; die 'wrong category' } unless $separator;
    map { 
        my ($opt, $val) = split /$separator/;
        chop $val;
        if_($opt ne 'set_security_conf', $opt => $val);
    } cat_($default_file);
}


# get_XXX_default(function) -
#   return the default of the function|check passed in argument.
#   If no default is set, return "default".

sub get_check_default {
    my ($msec, $check) = @_;
    $msec->{checks}{default}{$check};
}

sub get_function_default {
    my ($msec, $function) = @_;
    $msec->{functions}{default}{$function};
}



#-------------------------------------------------------------
# option values

sub load_values {
    my ($category) = @_;
    my $item_file =
      $category eq 'functions' ? $options_file :
      $category eq 'checks' ? $check_file : '';

    my $separator = $category eq 'functions' ? '\(' : $category eq 'checks' ? '=' : undef;
    do { print "BACKTRACE:\n", backtrace(), "\n"; die 'wrong category' } unless $separator;
    map {
        my ($opt, $val) = split /$separator/;
        $val =~ s/[()]//g;
        chop $opt if $separator eq '\(';   # $opt =~ s/ //g if $separator eq '\(';
        chop $val;
        $opt => $val;
    } cat_($item_file);
}


# get_XXX_value(function) -
#   return the value of the function|check passed in argument.
#   If no value is set, return "default".

sub get_function_value {
    my ($msec, $function) = @_;
    $msec->{functions}{value}{$function} || "default";
}

sub get_check_value {
    my ($msec, $check) = @_;
#    print "value for '$check' is '$msec->{checks}{value}{$check}'\n";
    $msec->{checks}{value}{$check} || "default";
}




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

# config_function(function, value) -
#   Apply the configuration to 'prefix'/etc/security/msec/level.local
sub config_function {
    my (undef, $function, $value) = @_;

    substInFile { s/^$function.*\n// } $options_file;
    append_to_file($options_file, "$function ($value)") if $value ne 'default';
}

# ***********************************************
#     PERIODIC CHECKS (security.conf) RELATED
# ***********************************************

# get_default_checks() -
#   return a list of periodic checks handled by security.conf
sub get_default_checks {
    my ($msec) = @_;
    keys %{$msec->{checks}{default}};
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

sub new { 
    my $type = shift;
    my $thing = {};
    $thing->{checks}{default}    = { load_defaults('checks') };
    $thing->{functions}{default} = { load_defaults('functions') };
    $thing->{functions}{value} = { load_values('functions') };
    $thing->{checks}{value}    = { load_values('checks') };
    bless $thing, $type;
}

1;
