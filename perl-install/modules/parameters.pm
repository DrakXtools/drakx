package modules::parameters; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;


sub parameters {
  my ($module) = @_;

  my $modinfo = find { -x $_ } qw(/sbin/modiInfo /usr/bin/modinfo) or die N("modinfo is not available");

  if (!$::isStandalone && !$::testing) {
      modules::extract_modules('/tmp', $module);
      $module = "/tmp/$module.o";
  }

  my @parameters;
  foreach (common::join_lines(`$modinfo -p $module`)) {
      chomp;
      next if /^warning:/;
      (my $name, $_) = /(\S+)\s+(.*)/s or warn "modules::parameters::get_options_name($module): unknown line\n";

      my $c_types = 'int|string|short|byte|char|long';
      my ($is_a_number, $description, $min, $max) = (0, '', 1, 1);
      if (/^($c_types) array \(min = (\d+), max = (\d+)\),?\s*(.*)/s) {
	  $_ = $4;
	  #- seems like "char" are buggy entries
	  ($is_a_number, $min, $max) = ($1 ne 'string', $2, $3) if $1 ne 'char'; 
      } elsif (/^($c_types),?\s*(.*)/s) {
	  $_ = $2;
	  #- here "char" really are size-limited strings, modinfo doesn't display the size limit (but since we don't care about it, it doesn't matter :)
	  $is_a_number = $1 ne 'string' if $1 ne 'char';
      } else {
	  #- for things like "no format character" or "unknown format character"
      }
      if (/^description "(.*)",?\s*/s) {
	  ($description, $_) = ($1, $2);
      }
      #- print "STILL HAVE ($_)\n" if $_;

	 my $format = $min == 1 && $max == 1 ?
		($is_a_number ? N("a number") : '') :
		$min == $max ? 
		($is_a_number ? N("%d comma separated numbers", $min) : N("%d comma separated strings", $min)) :
		$min == 1 ?
		($is_a_number ? N("comma separated numbers") : N("comma separated strings")) :
		''; #- too weird and buggy, do not display it
    push @parameters, [ $name, $format, $description ];
  }
  @parameters;
}

1;
