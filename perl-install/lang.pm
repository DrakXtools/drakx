package lang;

use diagnostics;
use strict;

use common qw(:file);
use commands;
use cpio;
use log;

my @fields =
my %languages = (
  "en" => [ "English",   undef,		undef,		"en_US" ],
  "fr" => [ "French",    "lat0-sun16",	"iso15",	"fr_FR" ],
  "de" => [ "German",    "lat0-sun16",	"iso15",	"de_DE" ],
  "hu" => [ "Hungarian", "lat2-sun16",  "iso02",	"hu_HU" ],
  "is" => [ "Icelandic", "lat0-sun16",	"iso15",	"is_IS" ],
  "it" => [ "Italian",   "lat0-sun16",	"iso15",	"it_IT" ],
  "no" => [ "Norwegian", "lat0-sun16",	"iso15",	"no_NO" ],
  "ro" => [ "Romanian",  "lat2-sun16",	"iso02",	"ro_RO" ],
  "sk" => [ "Slovak",    "lat2-sun16",	"iso02",	"sk_SK" ],
  "ru" => [ "Russian",   "Cyr_a8x16", 	"koi2alt",	"ru_SU" ],
  "uk" => [ "Ukrainian", "ruscii_8x16",	"koi2alt",	"uk_UA" ],
);

1;

sub list { map { $_->[0] } values %languages }
sub text2lang {
    my ($t) = @_;
    while (my ($k, $v) = each %languages) {
	lc($v->[0]) eq lc($t) and return $k;
    }
    die "unknown language $t";
}

sub set {
    my $lang = shift;

    if ($lang) {
	$ENV{LANG} = $ENV{LINGUAS} = $lang;
	$ENV{LC_ALL} = $languages{$lang}->[3];
	#if (my $f = $languages{$lang}->[1]) { load_font($f) }
    } else {
	# stick with the default (English) */
	delete $ENV{LANG};
	delete $ENV{LC_ALL};
	delete $ENV{LINGUAS};
    }
}

sub write {
    my ($prefix) = @_;
    my $lang = $ENV{LANG};

    $lang or return;
    local *F;
    open F, "> $prefix/etc/sysconfig/i18n" or die "failed to reset $prefix/etc/sysconfig/i18n for writing";
    my $f = sub { $_[1] and print F "$_[0]=$_[1]\n"; };

    &$f("LANG", $lang);
    &$f("LINGUAS", $lang);
    if (my $l = $languages{$lang}) {
	&$f("LC_ALL", $l->[3]);
	$l->[1] or return;
	&$f("SYSFONT", $l->[1]);
	&$f("SYSFONTACM", $l->[2]);

	my $p = "$prefix/usr/lib/kbd";
	commands::cp("-f", 
		     "$p/consolefonts/$l->[1].psf.gz", 
		     glob_("$p/consoletrans/$l->[2]*"), 
		     "$prefix/etc/sysconfig/console");
    }
}

sub load_font {
    my ($fontFile) = @_;
    log::l("loading font /usr/share/consolefonts/$fontFile.psf");
    c::loadFont("/tmp/$fontFile") or log::l("error in loadFont: one of PIO_FONT PIO_UNIMAPCLR PIO_UNIMAP PIO_UNISCRNMAP failed: $!");
    print STDERR "\033(K";
}
