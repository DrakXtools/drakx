package modules::parameters;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use modules;


sub parameters {
  my ($module) = @_;

  map {
      chomp;
      (my $name, $_) = /(\w+):(.*)/s or warn "modules::parameters::parameters($module): unknown line\n";
      [ $name, $_ ];
  } common::join_lines(run_program::get_stdout('modinfo', '-p', $module));
}

1;
