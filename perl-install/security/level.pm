package security::level;

use strict;
use common;

my %level_list = (
                  0 => N("Welcome To Crackers"),
                  1 => N("Poor"),
                  2 => N("Standard"),
                  3 => N("High"),
                  4 => N("Higher"),
                  5 => N("Paranoid"),
                  );

my @sec_levels = map { $level_list{$_} } (0..5); # enforce order


sub get_common_list {
    map { $level_list{$_} } (2, 3, 4);
}

sub get_full_list {
    
}

sub get {
    cat_("$::prefix/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.0 msec
    cat_("$::prefix/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.1 msec
      ${{ getVarsFromSh("$::prefix/etc/sysconfig/msec") }}{SECURE_LEVEL}  || #- 8.2 msec
	$ENV{SECURE_LEVEL};
}


sub get_string {
    return $sec_levels[get()] || 2
}

sub set {
    my %sec_levels = reverse %level_list;
    my $run_level = $sec_levels{$_[0]};
    print "set level: $_[0] -> $run_level\n";
    print $::prefix, "/usr/sbin/msec ", $run_level ? $run_level : 3, "\n";
    require run_program;
    run_program::rooted($::prefix, "/usr/sbin/msec", $run_level ? $run_level : 3);
}

1;
