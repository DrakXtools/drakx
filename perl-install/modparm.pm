package modparm;

use log;

my %modparm_hash;

sub read_modparm_file($) {
  my ($file) = @_;
  my @line;

  open F, $file;
  while (<F>) {
    chomp;
    @line = split ':';

    $modparm_hash{$line[0]}{$line[1]} = {
					 type => $line[2],
					 default => $line[3],
					 desc => $line [4],
					};
  }
  close F;
}

sub get_options_result($;$) {
  my ($module,$value) = @_;
  my @names = keys %{$modparm_hash{$module}};
  my $options;
  my $result;
  my $i;

  for $i (0..$#$value) {
    $result = $ {$value->[$i]};

    if ($result != "") {
      $options .= "$names[$i]=$result ";
    }
  }

  return $options;
}

sub get_options_name($) {
  my ($module) = @_;
  my @names = keys %{$modparm_hash{$module}};
  my @result;
  my $opttype;
  my $default;

  foreach (@names) {
    $opttype = $modparm_hash{$module}{$_}{type};
    $default = $modparm_hash{$module}{$_}{default};

    if (defined($default)) {
      push @result, _("$_ ($opttype)[$default]");
    } else {
      push @result, _("$_ ($opttype)");
    }
  }

  return \@result;
}

sub get_options_value($) {
  my ($module) = @_;
  my @names = keys %{$modparm_hash{$module}};
  my @result;

  for $i (0..$#names) {
    my $value = "";

    $result[$i] = \$value;
  }

  return \@result;
}

read_modparm_file("/tmp/modparm.txt");

1;
