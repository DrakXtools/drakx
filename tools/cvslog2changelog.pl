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
              'adelorbeau' => 'Arnaud de Lorbeau  <adelorbeau at mandriva.com>',
              'adesmons'  => 'Arnaud Desmons',
              'aginies' => 'Antoine Ginies  <aginies at mandriva.com> ',
              'alafox'  => 'Alice Lafox  <alice at lafox.com.ua>',
              'alemaire'  => 'Aurélien Lemaire',
              'alus'    => 'Arkadiusz Lipiec  <alipiec at elka.pw.edu.pl>',
              'amaury'   => 'Amaury Amblard-Ladurantie',
              'baudens' => 'David Baudens  <baudens at mandriva.com>',
              'camille' => 'Camille Bégnis  <camille at mandriva.com>',
              'cbelisle'  => 'Christian Belisle',
              'chmou'    => 'Chmouel Boudjnah',
              'chmouel'  => 'Chmouel Boudjnah',
              'croy'    => 'Christian Roy  <croy at mandriva.com>',
              'damien'  => 'dam\'s  <dams at idm.fr>',
              'daouda'  => 'Daouda Lo  <daouda at mandriva.com>',
              'dchaumette' => 'Damien Chaumette  <dchaumette at mandriva.com>',
              'dindinx'  => 'David odin',
              'drdrake' => 'Dovix  <dovix2003 at yahoo.com>',
              'erwan'   => 'Erwan Velu  <erwan at mandriva.com>',
              'fabman'  => 'Fabian Mandelbaum  <fabman at 2vias.com.ar>',
              'fcrozat' => 'Frederic Crozat  <fcrozat at mandriva.com>',
              'flepied' => 'Frederic Lepied  <flepied at mandriva.com>',
              'florin'  => 'Florin Grad  <florin at mandriva.com>',
              'fpons'    => 'Fançois Pons',
              'fred'     => 'Frederic Bastok',
              'fwang'   => 'Funda Wang <fundawang at linux.net.cn>',
              'gb'      => 'Gwenole Beauchesne  <gbeauchesne at mandriva.com>',
              'gbeauchesne' => 'Gwenole Beauchesne  <gbeauchesne at mandriva.com>',
              'gc'      => 'Guillaume Cottenceau  <gc at mandriva.com>',
              'hilbert' => '(Hilbert) <h at mandrake.org>',
              'install' => 'DrakX  <install at mandriva.com>',
              'jdanjou'  => 'Julien Danjou',
              'jjorge'  => 'José JORGE <jjorge at free.fr>',
              'jpomerleau'  => 'Joel Pomerleau',
              'keld'    => 'Keld Jørn Simonsen  <keld at dkuug.dk>',
              'lmontel' => 'Laurent Montel  <lmontel at mandriva.com>',
              'mscherer' => 'Michael Scherer  <mscherer at mandrake.org>',
              'nplanel' => 'Nicolas Planel  <nplanel at mandriva.com>',
              'oblin' => 'Olivier Blin <oblin at mandriva.com>',
              'othauvin' => 'Olivier Thauvin  <thauvin at aerov.jussieu.fr>',
              'pablo'   => 'Pablo Saratxaga  <pablo at mandriva.com>',
              'peroyvind' => 'Per Øyvind Karlsen <peroyvind at linux-mandrake.com>',
              'phetroy'  => 'Philippe Libat',
              'philippe'  => 'Philippe Libat',
              'prigaux' => 'Pixel  <pixel at mandriva.com>',
              'quintela' => 'Juan Quintela  <quintela at mandriva.com>',
              'rchaillat'  => 'Renaud Chaillat',
	      'rdalverny' => 'Romain d\'Alverny  <rdalverny at mandriva.com>',
	      'redhog'   => 'RedHog',
              'reinouts' => 'Reinout van Schouwen  <reinout at cs.vu.nl>',
              'rgarciasuarez' => 'Rafael Garcia-Suarez <rgarciasuarez at mandriva.com>',
              'rvojta' => 'Robert Vojta <robert.vojta at mandrake.cz>',
              'sbenedict' => 'Stew Benedict  <sbenedict at mandriva.com>',
              'sdetilly'  => 'Sylvain de Tilly',
              'siegel'  => 'Stefan Siegel  <siegel at linux-mandrake.com>',
              'tbacklund' => 'Thomas Backlund  <tmb at mandrake.org>',
              'tkamppeter' => 'Till Kamppeter  <till at mandriva.com>',
              'tpittich' => 'Tibor Pittich  <Tibor.Pittich at phuture.sk>',
              'tsdgeos ' => 'Albert Astals Cid <astals11 at terra.es>',
              'tv' => 'Thierry Vignaud  <tvignaud at mandriva.com>',
              'tvignaud' => 'Thierry Vignaud  <tvignaud at mandriva.com>',
              'uid524'   => 'Chmouel Boudjnah',
              'vdanen'  => 'Vincent Danen  <vdanen at mandriva.com>',
              'vguardiola' => 'Vincent Guardiola <vguardiola at mandriva.com>',
              'warly'   => 'Warly  <warly at mandriva.com>',
              'yduret'   => 'Yves Duret',
              'yoann'    => 'Yoann Vandoorselaere',
              'yrahal'  => 'Youcef Rabah Rahal <rahal at arabeyes.org>',
	     );
}
