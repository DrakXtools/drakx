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
              'abiro'   => 'Arpad Biro  <biro_arpad at yahoo.com>',
              'adelorbeau' => 'Arnaud de Lorbeau  <adelorbeau at mandrakesoft.com>',
              'adesmons'  => 'Arnaud Desmons',
              'aginies' => 'Antoine Ginies  <aginies at mandrakesoft.com> ',
              'alafox'  => 'Alice Lafox  <alice at lafox.com.ua>',
              'alemaire'  => 'Aurélien Lemaire',
              'alus'    => 'Arkadiusz Lipiec  <alipiec at elka.pw.edu.pl>',
              'amaury'   => 'Amaury Amblard-Ladurantie',
              'baudens' => 'David Baudens  <baudens at mandrakesoft.com>',
              'camille' => 'Camille Bégnis  <camille at mandrakesoft.com>',
              'cbelisle'  => 'Christian Belisle',
              'chmou'    => 'Chmouel Boudjnah',
              'chmouel'  => 'Chmouel Boudjnah',
              'croy'    => 'Christian Roy  <croy at mandrakesoft.com>',
              'damien'  => 'dam\'s  <dams at idm.fr>',
              'daouda'  => 'Daouda Lo  <daouda at mandrakesoft.com>',
              'dchaumette' => 'Damien Chaumette  <dchaumette at mandrakesoft.com>',
              'dindinx'  => 'David odin',
              'drdrake' => 'Dovix  <dovix2003 at yahoo.com>',
              'erwan'   => 'Erwan Velu  <erwan at mandrakesoft.com>',
              'fabman'  => 'Fabian Mandelbaum  <fabman at 2vias.com.ar>',
              'fcrozat' => 'Frederic Crozat  <fcrozat at mandrakesoft.com>',
              'flepied' => 'Frederic Lepied  <flepied at mandrakesoft.com>',
              'florin'  => 'Florin Grad  <florin at mandrakesoft.com>',
              'fpons'    => 'Fançois Pons',
              'fred'     => 'Frederic Bastok',
              'fwang'   => 'Funda Wang <fundawang at linux.net.cn>',
              'gb'      => 'Gwenole Beauchesne  <gbeauchesne at mandrakesoft.com>',
              'gbeauchesne' => 'Gwenole Beauchesne  <gbeauchesne at mandrakesoft.com>',
              'gc'      => 'Guillaume Cottenceau  <gc at mandrakesoft.com>',
              'hilbert' => '(Hilbert) <h at mandrake.org>',
              'install' => 'DrakX  <install at mandrakesoft.com>',
              'jdanjou'  => 'Julien Danjou',
              'jjorge'  => 'José JORGE <jjorge at free.fr>',
              'jpomerleau'  => 'Joel Pomerleau',
              'keld'    => 'Keld Jørn Simonsen  <keld at dkuug.dk>',
              'lmontel' => 'Laurent Montel  <lmontel at mandrakesoft.com>',
              'mscherer' => 'Michael Scherer  <mscherer at mandrake.org>',
              'nplanel' => 'Nicolas Planel  <nplanel at mandrakesoft.com>',
              'oblin' => 'Olivier Blin <oblin at mandrakesoft.com>',
              'othauvin' => 'Olivier Thauvin  <thauvin at aerov.jussieu.fr>',
              'pablo'   => 'Pablo Saratxaga  <pablo at mandrakesoft.com>',
              'peroyvind' => 'Per Øyvind Karlsen <peroyvind at linux-mandrake.com>',
              'phetroy'  => 'Philippe Libat',
              'philippe'  => 'Philippe Libat',
              'prigaux' => 'Pixel  <pixel at mandrakesoft.com>',
              'quintela' => 'Juan Quintela  <quintela at mandrakesoft.com>',
              'rchaillat'  => 'Renaud Chaillat',
	      'rdalverny' => 'Romain d\'Alverny  <rdalverny at mandrakesoft.com>',
	      'redhog'   => 'RedHog',
              'reinouts' => 'Reinout van Schouwen  <reinout at cs.vu.nl>',
              'rgarciasuarez' => 'Rafael Garcia-Suarez <rgarciasuarez at mandrakesoft.com>',
              'rvojta' => 'Robert Vojta <robert.vojta at mandrake.cz>',
              'sbenedict' => 'Stew Benedict  <sbenedict at mandrakesoft.com>',
              'sdetilly'  => 'Sylvain de Tilly',
              'siegel'  => 'Stefan Siegel  <siegel at linux-mandrake.com>',
              'tbacklund' => 'Thomas Backlund  <tmb at mandrake.org>',
              'tkamppeter' => 'Till Kamppeter  <till at mandrakesoft.com>',
              'tpittich' => 'Tibor Pittich  <Tibor.Pittich at phuture.sk>',
              'tsdgeos ' => 'Albert Astals Cid <astals11 at terra.es>',
              'tv' => 'Thierry Vignaud  <tvignaud at mandrakesoft.com>',
              'tvignaud' => 'Thierry Vignaud  <tvignaud at mandrakesoft.com>',
              'uid524'   => 'Chmouel Boudjnah',
              'vdanen'  => 'Vincent Danen  <vdanen at mandrakesoft.com>',
              'vguardiola' => 'Vincent Guardiola <vguardiola at mandrakesoft.com>',
              'warly'   => 'Warly  <warly at mandrakesoft.com>',
              'yduret'   => 'Yves Duret',
              'yoann'    => 'Yoann Vandoorselaere',
              'yrahal'  => 'Youcef Rabah Rahal <rahal at arabeyes.org>',
	     );
}
