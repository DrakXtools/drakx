#!/usr/bin/perl

while (<>) {
    if ($e = /^description:/ .. /^={77}/) {
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

foreach $date (reverse sort keys %l) {
    foreach $user (sort keys %{$l{$date}}) {
	$fuser = $users{$user} || $user;
	print "$date  $fuser\n\n";
	my %inv;
	while (($file, $log) = each %{$l{$date}{$user}}) {
	    $log =~ s/^\s+( \*)?//ms;
	    $log =~ s/\s+$//ms;
	    $log = "\n$log" if $log =~ /^-/;
	    push @{$inv{$log}}, $file;
	}
	foreach $log (keys %inv) {
	    $line = join(', ', @{$inv{$log}}) . ($log !~ /^\(/ && ':') . " $log";
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
	      'fpons'   => 'Fran�ois Pons  <fpons at mandrakesoft.com>',
	      'pablo'   => 'Pablo Saratxaga  <pablo at mandrakesoft.com>',
	      'damien'  => 'dam\'s  <dams at idm.fr>',
	      'install' => 'DrakX  <install at mandrakesoft.com>',
	      'prigaux' => 'Pixel  <pixel at mandrakesoft.com>',
	      'flepied' => 'Frederic Lepied  <flepied at mandrakesoft.com>',
	      'chmouel' => 'Chmouel Boudjnah  <chmouel at mandrakesoft.com>',
	      'uid526'  => 'dam\'s  <damien at mandrakesoft.com>',
	      'uid533'  => 'Fran�ois Pons  <fpons at mandrakesoft.com>',
	      'uid535'  => 'Guillaume Cottenceau  <gc at mandrakesoft.com>',
	      'uid553'  => 'Pixel  <pixel at mandrakesoft.com>',
	      'tvignaud' =>'Thierry Vignaud  <tvignaud at mandrakesoft.com>',
	      'sbenedict'=>'Stew Benedict  <sbenedict at mandrakesoft.com>',
	      'tkamppeter'=>'Till Kamppeter  <till at mandrakesoft.com>',
	      'yduret'  => 'Yves Duret  <yduret at mandrakesoft.com>',
	      'daouda'  => 'Daouda Lo  <daouda at mandrakesoft.com>',
	      'dchaumette' => 'Damien Chaumette  <dchaumette at mandrakesoft.com>',
	      'cbelisle' =>'Christian Belisle  <cbelisle at mandrakesoft.com>',
	      'warly'   => 'Warly  <warly at mandrakesoft.com>',
	      'jgotti'  => 'Jonathan Gotti  <jgotti at mandrakesoft.com>',
	      'fcrozat' => 'Frederic Crozat  <fcrozat at mandrakesoft.com>',
	      'baudens' => 'David Baudens  <baudens at mandrakesoft.com>',
	      'florin'  => 'Florin Grad  <florin at mandrakesoft.com>',
	      'alafox'  => 'Alice Lafox  <alice at lafox.com.ua>',
	      'alus'    => 'Arkadiusz Lipiec  <alipiec at elka.pw.edu.pl>',
	      'fabman'  => 'Fabian Mandelbaum  <fabman at 2vias.com.ar>',
	     );
}
