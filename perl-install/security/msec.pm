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

sub get_functions {
    my $prefix = $_;
    my @functions = ();
    ## TODO handle 3 last functions here so they can be removed from this list
    my @ignore_list = qw(indirect commit_changes closelog error initlog log set_secure_level
                                       set_security_conf set_server_level print_changes get_translation
                                       enable_libsafe password_aging password_length create_server_link);
    my $file = "$prefix/usr/share/msec/mseclib.py";
    my $function = '';

    open F, $file;
    while (<F>) {
        if ($_ =~ /^def/) {
            (undef, $function) = split(/ /, $_);
            ($function, undef) = split(/\(/, $function);
            if (!(member($function, @ignore_list))) { push(@functions, $function); }
        }
    }
    close F;

    @functions;
}

sub get_value {
    my ($prefix, $function) = @_;
    my $value = '';
    my $msec_options = "$prefix/etc/security/msec/level.local";
    my $msec_defaults = "$prefix/etc/security/msec/msec.defaults";
    my $found = 0;

    if (-e $msec_options) {
        open F, $msec_options;
        while(<F>) {
            if($_ =~ /^$function/) {
                (undef, $value) = split(/\(/, $_);
                chop $value; chop $value;
                $found = 1;
            }
            if ($found == 0) { $value = "default"; }
        }
        close F;
    }
    else { $value = "default"; }
    $value;
}

sub get_checks {
    my ($prefix) = $_;
    my %checks = ();
    my $check_file = "$prefix/etc/security/msec/security.conf";
    my $def_check = "$prefix/var/lib/msec/security.conf";
    my @ignore_list = qw(MAIL_USER);
    my $key = '';

    open F, $def_check;
    while (<F>) {
        ($key, undef) = split(/=/, $_);
        if(!(member($key, @ignore_list))) { $checks{$key} = "default"; }
    }
    close F;

    if (-e $check_file) {
        open F, $check_file;
        while (<F>) {
            ($key, undef) = split(/=/, $_);
            if(!(member($key, @ignore_list))) {
                (undef, $checks{$key}) = split(/=/, $_);
                chop $checks{$key};
            }
        }
        close F;
    }

    %checks;
}

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

sub get_options {
    my ($prefix, $category) = @_;
    my %options = ();
    my @functions = ();
    my @checks = ();
    my $key = "";

    if ($category eq "functions") {
        @functions = get_functions($prefix);
        foreach $key (@functions) {
            $options{$key} = get_value($prefix, $key);
        }
    }
    elsif ($category eq "checks") {
        %options = get_checks($prefix);
    }

    %options;
}

sub get_default {
    my ($prefix, $function, $security) = @_;
    my $default_file = "$prefix/usr/share/msec/level.".$security;
    my $default_value = "";

    open F, $default_file;
    while(<F>) {
        if ($_ =~ /^$function/) { (undef, $default_value) = split(/ /, $_); }
    }
    close F;
    chop $default_value;
    $default_value;
}

sub choose_security_level {
    my ($in, $security, $libsafe, $email, $signal) = @_;

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
            { val => _("Advanced Options"), type => 'button', clicked_may_quit => sub { $$signal = 1; } }
        ],
    );
}

sub choose_functions {
    my ($in, $rfunctions, $signal, $security) = @_;
    my $i = 0;
    my @display = ();
    my $key = "";
    my $default = "";

    foreach $key (keys %$rfunctions) {
        $default = get_default('', $key, $security);
        if ($default eq "yes" || $default eq "no") {
            $display[$i] = { label => $key." (default=$default)", val =>\$$rfunctions{$key}, list => ["yes", "no", "default"] };
        }
        elsif ($default eq "ALL" || $default eq "NONE" || $default eq "LOCAL") {
            $display[$i] = { label => $key." (default=$default)", val =>\$$rfunctions{$key}, list => ["ALL", "NONE", "LOCAL", "default"] };
        }
        else {
            $display[$i] = { label => $key." (default=$default)", val => \$$rfunctions{$key} };
        }
        $i++;
    }

    # TODO find a way to add the button outside of the scrolling zone
    $in->ask_from(
        ("DrakSec - Advanced Options"),
        ("You can customize the following options. For more information, see the mseclib manual page."),
        [
        { val => _("Basic Options"), type => 'button', clicked_may_quit => sub { $$signal = 0; print ""; } },
        { val => _("Security Checks"), type => 'button', clicked_may_quit => sub {$$signal = 2; print ""; } },
        @display
        ],
    );
}

sub choose_checks {
    my ($in, $roptions, $signal, $security) = @_;
    my $i = 0;
    my @display = ();
    my $key = '';
    my $def_checks = "/var/lib/msec/security.conf";

    my %defaults = getVarsFromSh($def_checks);

    foreach $key (keys %$roptions) {
        if ($defaults{$key} eq "yes" || $defaults{$key} eq "no") {
            $display[$i] = { label => $key." (default=$defaults{$key})", val => \$$roptions{$key}, list => ["yes", "no", "default"] };
        }
        else { $display[$i] = { label => $key." (default=$defaults{$key})", val => \$$roptions{$key} };
        }
        $i++;
    }

    $in->ask_from(
            ("DrakSec - Security Checks"),
            ("You can customize the following security checks. For more information, see the mseclib manual page."),
            [
            { val => _("Basic Options"), type => 'button', clicked_may_quit => sub { $$signal = 0; print ""; } },
            { val => _("Advanced Options"), type => 'button', clicked_may_quit => sub { $$signal = 1; print ""; } },
#	    { val => _("Firewall Configuration"), type => 'button', clicked_may_quit => sub { $$signal = 3; print ""; } },
            @display
            ],
    );
}

1;
