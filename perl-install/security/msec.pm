package security::msec;

use common;
use log;

sub get_user_list {
   my @user_list = ();

   open(PASSWD, "/etc/passwd");
   while(<PASSWD>) {
      my ($login_name, undef, $uid) = split(/:/,$_);
      if($uid >= 500) { push(@user_list, $login_name); }
   }
   @user_list;
}

sub add_config {
   my ($prefix, $config_option, @values) = @_;
   my $tmp_file = "$prefix/etc/security/msec/level.local.tmp";
   my $result = "";

   $result = $config_option.'(';
   foreach $value (@values) {
      $result .= $value.',';
   }
   chop $result;
   $result .= ')';

   open(TMP_CONFIG, '>>'.$tmp_file);
   print TMP_CONFIG "$result\n";
   close TMP_CONFIG;
}

sub commit_changes {
   my ($prefix) = $_;
   my $tmp_file = "$prefix/etc/security/msec/level.local.tmp";
   my $config_file = "$prefix/etc/security/msec/level.local";
   my %config_data;
   my $config_option = "";

   open (TMP_CONFIG, $tmp_file);

   if (!(-x $config_file)) {
      open(CONFIG_FILE, '>'.$config_file);
      print CONFIG_FILE "from mseclib import *\n\n";
      while(<TMP_CONFIG>) { print CONFIG_FILE $_; }
   }
   else {
      open(CONFIG_FILE, $config_file);
      while(<CONFIG_FILE>) {
         if($_ =~ /\(/) {
            ($config_option, undef) = split(/\(/, $_);
            (undef, $config_data{$config_option}) = split(/\(/, $_);
	 }
      }
      close CONFIG_FILE;
      
      while(<TMP_CONFIG>) {
	 ($config_option, undef) = split(/\(/, $_);
	 (undef, $config_data{$config_option}) = split(/\(/, $_);
      }

      open(CONFIG_FILE, '>'.$config_file);
      print CONFIG_FILE "from mseclib import *\n\n";
      foreach $config_option (keys %config_data) {
         print CONFIG_FILE $config_option.'('.$config_data{$config_option}.'\n';
      }   
   }

   close CONFIG_FILE;
   close TMP_CONFIG;

   standalone::rm_rf($tmp_file);
} 

sub get_config {
    my ($prefix, $security) = @_;

    my (%net_options_defaults) = (
       accept_bogus_error_responses => [ "no", "no", "no", "no", "yes", "yes" ],
       accept_icmp_echo => [ "yes", "yes", "yes", "yes", "no", "no" ],
       enable_ip_spoofing_protection => [ "no", "no", "no", "yes", "yes", "yes" ],
       enable_log_strange_packets => [ "no", "no", "no", "yes", "yes", "yes" ] );

    my (%user_options_defaults) = (
       allow_autologin => [ "yes", "yes", "yes", "no", "no", "no" ],
       allow_issues => [ "ALL", "ALL", "ALL", "LOCAL", "LOCAL", "NONE" ],
       allow_reboot => [ "yes", "yes", "yes", "yes", "no", "no" ],
       allow_root_login => [ "yes", "yes", "yes", "yes", "no", "no" ],
       allow_user_list => [ "yes", "yes", "yes", "yes", "no", "no" ],
       enable_at_crontab => [ "yes", "yes", "yes", "yes", "no", "no" ],
       enable_pam_wheel_for_su => [ "no", "no", "no", "no", "no", "yes" ],
       enable_password => [ "no", "yes", "yes", "yes", "yes", "yes" ],
       enable_sulogin => [ "no", "no", "no", "no", "yes", "yes" ],
       password_aging => [ "99999,-1", "99999,-1", "99999,-1", "99999,-1", "60,-1", "30,-1" ],
       password_length => [ "0,0,0", "0,0,0", "0,0,0", "0,0,0", "0,0,0", "0,0,0" ],
       set_root_umask => [ "002", "002", "022", "022", "022", "077" ],
       set_user_umask => [ "002", "002", "022", "022", "077", "077" ],
       set_shell_history_size => [ "-1", "-1", "-1", "-1", "10", "10" ],
       set_shell_timeout => [ "0", "0", "0", "0", "3600", "900" ] );

    my (%server_options_defaults) = (
       allow_x_connections => [ "ALL,yes", "LOCAL,yes", "LOCAL,yes", "LOCAL,yes", "LOCAL,no", "NONE,no" ],
       authorize_services => [ "ALL", "ALL", "ALL", "ALL", "LOCAL", "NONE" ],
       enable_libsafe => [ "no", "no", "no", "no", "no", "no" ] );

    my (%net_options_matrix) = (
       accept_bogus_error_responses => { label => _("Accept/Refuse bogus IPV4 error messages"),
                                         val => $net_options_defaults{accept_bogus_error_responses}[$security],
					 list => [ "yes", "no" ] },
       accept_icmp_echo => { label => _("Accept/Refuse ICMP echo"),
                             val => $net_options_defaults{accept_icmp_echo}[$security],
			     list => [ "yes", "no" ] },
       enable_ip_spoofing_protection => { label => _("Enable/Disable IP spoofing protection. If alert is true, also reports to syslog"),
                                          val => $net_options_defaults{enable_ip_spoofing_protection}[$security],
					  list => [ "yes", "no" ] },
       enable_log_strange_packets => { label => _("Enable/Disable the logging of IPv4 strange packets"),
                                       val => $net_options_defaults{enable_log_strange_packets}[$security],
				       list => [ "yes", "no" ] }
    );

    my (%user_options_matrix) = (
       allow_autologin => { label => _("Allow/Forbid autologin"),
                            val => $user_options_defaults{allow_autologin}[$security] },
       allow_issues => { label => _("Allow/Forbid pre-login message : If ALL, allow remote and local pre-login message (/etc/issue[.net]). If LOCAL, allow local pre-login message (/etc/issue). If NONE, disable pre-login message."),
                         val => $user_options_defaults{allow_issues}[$security] },
       allow_reboot => { label => _("Allow/Forbid reboot by the console user"),
                         val => $user_options_defaults{allow_reboot}[$security] },
       allow_root_login => { label => _("Allow/Forbid direct root login"),
                             val => $user_options_defaults{allow_root_login}[$security] },
       allow_user_list => { label => _("Allow/Forbid the list of users on the system in the display managers (kdm and gdm)"),
                            val => $user_options_defaults{allow_user_list}[$security] },
       enable_at_crontab => { label => _("Enable/Disable crontab and at for users. Put allowed users in /etc/cron.allow and /etc/at.allow (see at(1) and crontab(1))"),
                              val => $user_options_defaults{enable_at_crontab}[$security] },
       enable_pam_wheel_for_su => { label => _("Enable su only for members of the wheel group or allow su from any user"),
                                    val => $user_options_defaults{enable_pam_wheel_for_su}[$security] },
       enable_password => { label => _("Use password to authenticate users"),
                            val => $user_options_defaults{enable_password}[$security] },
       enable_sulogin => { label => _("Enable/Disable sulogin in single user level (see sulogin(8))"),
                           val => $user_options_defaults{enable_sulogin}[$security] },
       password_aging => { label => _("Set password aging to max days (99999 to disable password aging"),
                           val => $user_options_defaults{password_aging}[$security] },
       password_length => { label => _("Set the password minimum length, the minimum number of digits and the minimum number of capitalized letters"),
                            val => $user_options_defaults{password_length}[$security] },
       set_root_umask => { label => _("Set the root umask"),
                           val => $user_options_defaults{set_root_umask}[$security] },
       set_user_umask => { label => _("Set the user umask"),
                           val => $user_options_defaults{set_user_umask}[$security] },
       set_shell_history_size => { label => _("Set shell commands history size (-1 for unlimited)"),
                                   val => $user_options_defaults{set_shell_history_size}[$security] },
       set_shell_timeout => { label => _("Set the shell timeout in seconds (0 for unlimited)"),
                              val => $user_options_defaults{set_shell_timeout}[$security] }
    );
       
    my (%server_options_matrix) = (
       allow_x_connections => { label => ("Allow/Forbid X connections : If ALL, all connections allowed. If LOCAL, local connections allowed. If NONE, only console connections allowed"),
                                val => $server_options_defaults{allow_x_connections}[$security] },
       authorize_services => { label => _("Allow/Forbid services : If ALL, authorize all services. If LOCAL, authorize only local services. If NONE, disable all services. (see hosts.deny(5)). To authorize a service, see hosts.allow(5)."),
                               val => $server_options_defaults{authorize_services}[$security] },
       enable_libsafe => { label => _("Enable/Disable libsafe if it's installed on the system."),
                           val => $server_options_defaults{enable_libsafe}[$security] },
   );

   my $config_file = "$prefix/etc/security/msec/level.local";
   my $values = "";
   my $config_option = "";

   open CONFIGFILE, $config_file;
   while(<CONFIGFILE>) {
       if($_ =~ /\(/) {
           ($config_option, undef) = split(/\(/, $_);
	   (undef, $values) = split(/\(/, $_);
	   chop $values;

	   if ($config_option ne "set_security_conf") {
	       if ($net_options_matrix{$config_option}{description} eq "") {
                   (undef, $net_options_matrix{$config_option}{value}) = $values;
	       } elsif ($user_options_matrix{$config_option}{description} eq "") {
                   (undef, $user_options_matrix{$config_option}{value}) = $values;
	       } elsif ($server_options_matrix{$config_option}{description} eq "") {
                   (undef, $server_options_matrix{$config_option}{value}) = $values;
	       }
	   }
	   else {
	       # TODO : Add code to handle set_security_conf
	   }
       }
   }

   close CONFIGFILE;

   return (\%net_options_matrix, \%user_options_matrix, \%server_options_matrix);
}

1;
