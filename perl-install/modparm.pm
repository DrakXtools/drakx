package modparm;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);
use log;



#-######################################################################################
#- Functions
#-######################################################################################
sub read_modparm_file {
  my $file = -e "modparm.lst" ? "modparm.lst" : "$ENV{SHARE_PATH}/modparm.lst";
  my @line;

  my %modparm_hash;
  local *F;
  open F, $file or log::l("missing $file: $!"), return;
  foreach (<F>) {
    chomp;
    @line = split ':';

    $modparm_hash{$line[0]}{$line[1]} = {
					 type => $line[2],
					 default => $line[3],
					 desc => $line [4],
					};
  }
  \%modparm_hash;
}

sub get_options_result($@) {
  my ($module, @value) = @_;
  my $modparm_hash = modparm::read_modparm_file;

  mapn {
      my ($a, $b) = @_;
      $a ? "$b=$a" : ()
  } \@value, [ keys %{$modparm_hash->{$module}} ];
}

sub get_options_name($) {
  my ($module) = @_;
  my @names;
  my $modparm_hash = modparm::read_modparm_file;

  while (my ($k, $v) = each %{$modparm_hash->{$module} || {}}) {
       my $opttype = $v->{type};
       my $default = $v->{default};
       push @names, "$k ($v->{type})" . (defined($v->{default}) && "[$v->{default}]");
  }
  @names;
}

1;
