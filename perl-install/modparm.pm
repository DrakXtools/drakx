package modparm; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use log;


sub get_options_result($@) {
    my ($module, @value) = @_;
    mapn {
	my ($a, $b) = @_;
	$b =~ s/^(\w).*/$1/;
	$a ? "$b=$a" : ();
    } \@value, [get_options_name($module)];
}

sub get_options_name($) {
  my ($module) = @_;

  my @names;
  my @line = `/sbin/modinfo -p $module`;
  foreach (@line) {
      chomp;
      s/int/i/;
      s/string/string/;
      s/short/h/;
      s/long/l/;
      s/(\S) array \(min = (\d+), max = (\d+)\)/$2-$3$1/;
      s/(\d)-\1i/$1i/;
      if (/parm:\s+(.+)/) {
	  my ($name, $type) = split '\s', $1;
	  push @names, "$name ($type)";
      }
  }
  @names;
}

1;
