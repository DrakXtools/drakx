package modparm; # $Id$

use diagnostics;
use strict;
use modules;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use log;


sub get_options_result($@) {
    my ($module, @value) = @_;
    mapn {
	my ($a, $b) = @_;
	$b =~ s/^(\w+).*/$1/;
	$a ? "$b=$a" : ();
    } \@value, [get_options_name($module)];
}

sub get_options_name($) {
  my ($module) = @_;

  my @names;
  $modinfo = $::isStandalone ? '/sbin/modinfo' : '/usr/bin/modinfo';
  -e $modinfo or die _('modinfo is not available');
  if($::isStandalone) {
      my @line = `$modinfo -p $module`;
  } else {
      modules::extract_modules('/tmp', $module);
      my @line = `$modinfo -p /tmp/$module.o`;
  }
  foreach (@line) {
      chomp;
      s/int/: (integer/;
      s/string/: (string/;
      my ($f, $g) = /array \(min = (\d+), max = (\d+)\)/;
      my $c;
      if ($f == 1 && $g == 1) {
	  $c = _('1 character)');
      } else {
	  $c = sprintf("$f-$g %s)", _('characters'));
      }
      s/array \(min = \d+, max = \d+\)/$c/;
      if (/parm:\s+(.+)/) {
	  local $_ = $1;
	  s/\s+/ /;
	  s/, description /TOOLTIP=>/;
	  push @names, $_;
      }
  }
  print "yop : @names \n";
  @names;
}

1;
