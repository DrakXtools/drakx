package lang;

use diagnostics;
use strict;

use common qw(:file);
use commands;
use cpio;
use log;

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
"uk_UA"=> [ "Ukrainian", "RUSCII_8x16",	"koi2alt",	"uk_UA" ],
);

1;

sub set {
    my $lang = shift;

    if ($lang) {
	$ENV{LANG} = $ENV{LINGUAS} = $lang;
	$ENV{LC_ALL} = $languages{$lang}->[3];
	my $f = $languages{$lang}->[1]; $f and load_font($f);
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

    $::testing || !$lang and return 0;
    local *F;
    open F, "> $prefix/etc/sysconfig/i18n";

    my $f = sub { $_[1] and print F "$_[0]=$_[1]\n"; };
    &$f("LANG", $lang);
    &$f("LINGUAS", $lang);
    if (my $l = $languages{$lang}) {
	&$f("LC_ALL", $l->{lc_all});
	&$f("SYSFONT", $l->{font});
	&$f("SYSFONTACM", $l->{map});

	my $p = "$prefix/usr/lib/kbd";
	commands::cp("-f", 
		     "$p/consolefonts/$l->{font}.psf.gz", 
		     glob_("$p/consoletrans/$l->{map}*"), 
		     "$prefix/etc/sysconfig/console");
    }
    1;
}

sub load_font {
    my ($fontFile) = @_;
    cpio::installCpioFile("/etc/fonts.cgz", $fontFile, "/tmp/font", 1) or die "error extracting $fontFile from /etc/fonts.cfz";
    c::loadFont('/tmp/font') or log::l("error in loadFont: one of PIO_FONT PIO_UNIMAPCLR PIO_UNIMAP PIO_UNISCRNMAP failed: $!");
    print STDERR "\033(K";
}
