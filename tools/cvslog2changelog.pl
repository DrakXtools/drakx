#!/usr/bin/perl

my %l;
{
my ($date, $user, $file);
local $_;
while (<>) {
    if (my $e = /^description:/ .. /^={77}/) {
	next if $e == 1 || $e =~ /E0/;
	if (/^-{28}/ .. /^date: /) {
	    if (/^date: (\S+)\s.*author: (\S+);/) {
		($date, $user) = ($1, $2);
	    }
	} elsif (!/^branches: / && !/file .* was initially added on branch/ && !/empty log message/ && !/no_comment/) {
	    $l{$date}{$user}{$file} .= $_;
	}
    } elsif (/Working file: (.*)/) {
	$file = $1;
    }
}
}


my %users;
foreach my $date (reverse sort keys %l) {
    foreach my $user (sort keys %{$l{$date}}) {
	next if $ENV{AUTHOR} && $ENV{AUTHOR} ne $user;

	my $fuser = $users{$user} || $user;
	print "$date  $fuser\n\n";
	my %inv;
	while (my ($file, $log) = each %{$l{$date}{$user}}) {
	    $log =~ s/^\s+( \*)?//ms;
	    $log =~ s/\s+$//ms;
	    $log = "\n$log" if $log =~ /^-/;
	    push @{$inv{$log}}, $file;
	}
	foreach my $log (keys %inv) {
	    my $line = join(', ', @{$inv{$log}}) . ($log !~ /^\(/ && ':') . " $log";
	    print "\t* ", join("\n\t", auto_fill($line, 72)), "\n\n";
	}
    }
}

1;

sub auto_fill {
    my ($line, $col) = @_;
    map {
	my @l;
	my $l = '';
	$_ = "  $_" if /^-/;
	while ($_) {
	    s/^(\s*)(\S*)//;
	    my $m = "$l$1$2";
	    if (length $m > $col) {
		push @l, $l;
		$l = $2;
	    } else {
		$l = $m
	    }
	}
	@l, $l;
    } split("\n", $line);
}

BEGIN {
    %users = (
	      'gc'      => 'Guillaume Cottenceau  <gc at mandrakesoft.com>',
	      'pablo'   => 'Pablo Saratxaga  <pablo at mandrakesoft.com>',
	      'damien'  => 'dam\'s  <dams at idm.fr>',
	      'install' => 'DrakX  <install at mandrakesoft.com>',
	      'prigaux' => 'Pixel  <pixel at mandrakesoft.com>',
	      'flepied' => 'Frederic Lepied  <flepied at mandrakesoft.com>',
	      'tvignaud' => 'Thierry Vignaud  <tvignaud at mandrakesoft.com>',
	      'sbenedict' => 'Stew Benedict  <sbenedict at mandrakesoft.com>',
	      'tkamppeter' => 'Till Kamppeter  <till at mandrakesoft.com>',
	      'daouda'  => 'Daouda Lo  <daouda at mandrakesoft.com>',
	      'dchaumette' => 'Damien Chaumette  <dchaumette at mandrakesoft.com>',
	      'warly'   => 'Warly  <warly at mandrakesoft.com>',
	      'fcrozat' => 'Frederic Crozat  <fcrozat at mandrakesoft.com>',
	      'baudens' => 'David Baudens  <baudens at mandrakesoft.com>',
	      'florin'  => 'Florin Grad  <florin at mandrakesoft.com>',
	      'alafox'  => 'Alice Lafox  <alice at lafox.com.ua>',
	      'alus'    => 'Arkadiusz Lipiec  <alipiec at elka.pw.edu.pl>',
	      'fabman'  => 'Fabian Mandelbaum  <fabman at 2vias.com.ar>',
              'erwan'   => 'Erwan Velu  <erwan at mandrakesoft.com>',
              'nplanel' => 'Nicolas Planel  <nplanel at mandrakesoft.com>',
              'rgarciasuarez' => 'Rafael Garcia-Suarez <rgarciasuarez at mandrakesoft.com>',
              'oblin' => 'Olivier Blin <oblin at mandrakesoft.com>',
              'vguardiola' => 'Vincent Guardiola <vguardiola at mandrakesoft.com>',
	     );
}
