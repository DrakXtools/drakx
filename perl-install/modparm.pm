package modparm;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);
use log;


#-#####################################################################################
#- Globals
#-#####################################################################################
my %modparm_hash;

#-######################################################################################
#- Functions
#-######################################################################################
sub read_modparm_file($) {
  my ($file) = @_;
  my @line;

  local *F;
  open F, $file or log::l("missing $file: $!"), return;
  while (<F>) {
    chomp;
    @line = split ':';

    $modparm_hash{$line[0]}{$line[1]} = {
					 type => $line[2],
					 default => $line[3],
					 desc => $line [4],
					};
  }
}

sub get_options_result($@) {
  my ($module, @value) = @_;

  mapn {
      my ($a, $b) = @_;
      $a ? "$b=$a" : ()
  } \@value, [ keys %{$modparm_hash{$module}} ];
}

sub get_options_name($) {
  my ($module) = @_;
  my @names;

  %modparm_hash or return;

  while (my ($k, $v) = each %{$modparm_hash{$module} || {}}) {
       my $opttype = $v->{type};
       my $default = $v->{default};
       push @names, "$k ($v->{type})" . (defined($v->{default}) && "[$v->{default}]");
  }
  @names;
}

1;
