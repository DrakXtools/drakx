package security::msec;

use strict;
use MDK::Common;


#-------------------------------------------------------------
# msec options managment methods


#-------------------------------------------------------------
# option defaults

sub load_defaults {
    my ($msec, $category) = @_;
    my $separator = $msec->{$category}{def_separator};
    map { 
        my ($opt, $val) = split(/$separator/, $_, 2);
        chop $val;
        if_($opt ne 'set_security_conf', $opt => $val);
    } cat_($msec->{$category}{defaults_file}), if_($category eq "checks", 'MAIL_USER');
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
    my ($msec, $category) = @_;
    my $separator = $msec->{$category}{val_separator};
    map {
        my ($opt, $val) = split /$separator/;
        chop $val;
        $val =~ s/[()]//g;
        chop $opt if $separator eq '\(';  # $opt =~ s/ //g if $separator eq '\(';
        if_(defined($val), $opt => $val);
    } cat_($msec->{$category}{values_file});
}


# get_XXX_value(check|function) -
#   return the value of the function|check passed in argument.
#   If no value is set, return "default".

sub get_function_value {
    my ($msec, $function) = @_;
    exists $msec->{functions}{value}{$function} ? $msec->{functions}{value}{$function} : "default";
}

sub get_check_value {
    my ($msec, $check) = @_;
    $msec->{checks}{value}{$check} || "default";
}



#-------------------------------------------------------------
# get list of check|functions

# list_(functions|checks) -
#   return a list of functions|checks handled by level.local|security.conf

sub raw_checks_list {
    my ($msec) = @_;
    keys %{$msec->{checks}{default}};
}

sub list_checks {
    my ($msec) = @_;
    difference2([ $msec->raw_checks_list ], [ qw(MAIL_WARN MAIL_USER) ]);
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
                         allow_root_login allow_user_list allow_xauth_from_root allow_x_connections allow_xserver_to_listen
                         authorize_services enable_at_crontab enable_console_log
                         enable_msec_cron enable_pam_wheel_for_su enable_password enable_security_check
                         enable_sulogin password_aging password_history password_length set_root_umask
                         set_shell_history_size set_shell_timeout set_user_umask)]);

    # get all function names; filter out those which are in the ignore
    # list, return what lefts.
    grep { !member($_, @ignore_list) && member($_, @{$options{$category}}) } keys %{$msec->{functions}{default}};
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
    my @list = sort($msec->list_functions('system'), $msec->list_functions('network'));
    touch($msec->{functions}{values_file}) if !-e $msec->{functions}{values_file};
    substInFile {
        foreach my $function (@list) { s/^$function.*\n// }
        if (eof) {
            $_ .= join("\n", if_(!$_, ''), (map { 
                my $value = $msec->get_function_value($_);
                if_($value ne 'default', "$_ ($value)");
            } @list), "");
        }
    } $msec->{functions}{values_file};
}

sub apply_checks {
    my ($msec) = @_;
    my @list =  sort $msec->raw_checks_list;
    setVarsInSh($msec->{checks}{values_file},
                {
                 map {
                     my $value = $msec->get_check_value($_);
                     if_($value ne 'default', $_ => $value);
                 } @list
                }
               );
}

sub reload {
    my ($msec) = @_;
    require security::level;
    my $num_level = security::level::get();
    $msec->{functions}{defaults_file} = "$::prefix/usr/share/msec/level.$num_level";
    $msec->{functions}{default} = { $msec->load_defaults('functions') };
}

sub new { 
    my ($type) = @_;
    my $msec = bless {}, $type;

    $msec->{functions}{values_file}   = "$::prefix/etc/security/msec/level.local";
    $msec->{checks}{values_file}      = "$::prefix/etc/security/msec/security.conf";
    $msec->{checks}{defaults_file}    = "$::prefix/var/lib/msec/security.conf";
    $msec->{checks}{val_separator}    = '=';
    $msec->{functions}{val_separator} = '\(';
    $msec->{checks}{def_separator}    = '=';
    $msec->{functions}{def_separator} = ' ';
    $msec->reload;

    $msec->{checks}{default}    = { $msec->load_defaults('checks') };
    $msec->{functions}{value}   = { $msec->load_values('functions') };
    $msec->{checks}{value}      = { $msec->load_values('checks') };
    $msec;
}

1;
