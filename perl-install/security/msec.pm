package security::msec;

use strict;
use MDK::Common::File;
use MDK::Common;


#-------------------------------------------------------------
# msec files

my $check_file    = "$::prefix/etc/security/msec/security.conf";
my $curr_sec_file = "$::prefix/var/lib/msec/security.conf";
my $options_file  = "$::prefix/etc/security/msec/level.local";


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
        chop $val;
        $val =~ s/[()]//g;
        chop $opt if $separator eq '\(';  # $opt =~ s/ //g if $separator eq '\(';
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




#-------------------------------------------------------------
# get list of functions

# list_(functions|checks) -
#   return a list of functions|checks handled by level.local|security.conf

sub list_checks {
    my ($msec) = @_;
    map { if_(!member($_, qw(MAIL_WARN MAIL_USER)), $_) } keys %{$msec->{checks}{default}};
}

sub list_functions {
    my ($msec, $category) = @_;

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

    # get all function names; filter out those which are in the ignore
    # list, return what lefts.
    map { if_(!member($_, @ignore_list) && member($_, @{$options{$category}}), $_) } keys %{$msec->{functions}{default}};
}


#-------------------------------------------------------------
# set back checks|functions values

sub set_function {
    my ($msec, $function, $value) = @_;
    $msec->{functions}{value}{$function} = $value;
}

sub set_check {
    my ($msec, $check, $value) = @_;
    $msec->{checks}{value}{$check} = $value;
}


#-------------------------------------------------------------
# apply configuration

# config_(check|function)(check|function, value) -
#   Apply the configuration to 'prefix'/etc/security/msec/security.conf||/etc/security/msec/level.local

sub apply_functions {
    my ($msec) = @_;
    my @list = ($msec->list_functions('system'), $msec->list_functions('network'));
    substInFile {
        foreach my $function (@list) { s/^$function.*\n// }
        if (eof) {
            print "\n", join("\n", map { 
                my $value = $msec->get_function_value($_);
                if_($value ne 'default', "$_ ($value)");
            } @list);
        }
    } $options_file;
}

sub apply_checks {
    my ($msec) = @_;
    my @list =  $msec->list_checks;
    substInFile {
        foreach my $check (@list) { s/^$check.*\n// }
        if (eof) {
            print "\n", join("\n", map { 
                my $value = $msec->get_check_value($_);
                if_($value ne 'default', $_ . '=' . $value);
            } @list), "\n";
        }
    } $check_file;
}

sub new { 
    my $type = shift;
    my $thing = {};
    $thing->{checks}{default}    = { load_defaults('checks') };
    $thing->{functions}{default} = { load_defaults('functions') };
    $thing->{functions}{value}   = { load_values('functions') };
    $thing->{checks}{value}      = { load_values('checks') };
    bless $thing, $type;
}

1;
