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
	      'gc'      => 'Guillaume Cottenceau  <gc@mandrakesoft.com>',
	      'fpons'   => 'François Pons  <fpons@mandrakesoft.com>',
	      'pablo'   => 'Pablo Saratxaga <pablo@mandrakesoft.com>',
	      'damien'  => 'dam\'s  <damien@mandrakesoft.com>',
	      'install' => 'DrakX <install@mandrakesoft.com>',
	      'prigaux' => 'Pixel  <pixel@mandrakesoft.com>',
	      'flepied' => 'Frederic Lepied  <flepied@mandrakesoft.com>',
	      'chmouel' => 'Chmouel Boudjnah  <chmouel@mandrakesoft.com>',
	      'uid526'  => 'dam\'s  <damien@mandrakesoft.com>',
	      'uid533'  => 'François Pons  <fpons@mandrakesoft.com>',
	      'uid535'  => 'Guillaume Cottenceau  <gc@mandrakesoft.com>',
	      'uid553'  => 'Pixel  <pixel@mandrakesoft.com>',
	      'tvignaud' => 'Thierry Vignaud  <tvignaud@mandrakesoft.com>',
	      'sbenedict'=>'Stew Benedict  <sbenedict@mandrakesoft.com>',
	      'tkamppeter' => 'Till Kamppeter <till@mandrakesoft.com>',
	      'yduret' => 'Yves Duret <yduret@mandrakesoft.com>'
	     );
}
