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

   print "result is $result";
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
1;
