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

  if (!$::isStandalone && !$::testing) {
      ($module) = modules::extract_modules('/tmp', $module);
  }

  my @parameters;
  foreach (common::join_lines(run_program::get_stdout('modinfo', '-p', $module))) {
      chomp;
      next if /^warning:/;
      (my $name, $_) = /(\w+)(?::|\s+)(.*)/s or warn "modules::parameters::get_options_name($module): unknown line\n";
      if (c::kernel_version() =~ /^\Q2.6/) {
          push @parameters, [ $name, '', $_ ];
          next;
      }

      my $c_types = 'int|string|short|byte|char|long';
      my ($is_a_number, $description, $min, $max) = (0, '', 1, 1);
      if (/^($c_types) array \(min = (\d+), max = (\d+)\),?\s*(.*)/s) {
	  $_ = $4;
	  #- seems like "char" are buggy entries
	  ($is_a_number, $min, $max) = ($1 ne 'string', $2, $3) if $1 ne 'char'; 
      } elsif (/^($c_types),?\s*(.*)/s) {
	  $_ = $2;
	  #- here "char" really are size-limited strings, modinfo does not display the size limit (but since we do not care about it, it does not matter :)
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
