 package lang;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:file);
use commands;
use log;

#-######################################################################################
#- Globals
#-######################################################################################
# key (to be used in $LC_ALL), [0] = english name, [1] = charset encoding,
# [2] = value for $LANG, [3] = value for LANGUAGE (a list of possible
# languages, carefully choosen)
my %languages = (
  'en'  => [ 'English',			undef,	      'en', 'en_US' ],
'fr_FR' => [ 'French (France)',		'iso-8859-1', 'fr', 'fr_FR' ],
'de_DE' => [ 'German (Germany)',	'iso-8859-1', 'de', 'de_DE' ],
  'hu'  => [ 'Hungarian', 		'iso-8859-2', 'hu', 'hu' ],
  'is'  => [ 'Icelandic', 		'iso-8859-1', 'is', 'is' ],
  'id'  => [ 'Indonesian',		'iso-8859-1', 'id', 'id' ],
  'it'  => [ 'Italian',   		'iso-8859-1', 'it', 'it_IT' ],
  'ja'  => [ 'Japanese',		'jisx0208',   'ja', 'ja_JP.ujis' ],
  'no'  => [ 'Norwegian (Bokmaal)',	'iso-8859-1', 'no', 'no:no@nynorsk' ],
'no@nynorsk' => [ 'Norwegian (Nynorsk)','iso-8859-1','no', 'no@nynorsk' ],
'pt_BR' => [ 'Portuguese (Brazil)',	'iso-8859-1', 'pt', 'pt_BR:pt_PT' ],
'pt_PT' => [ 'Portuguese (Portugal)',	'iso-8859-1', 'pt', 'pt_PT:pt_BR' ],
  'ro'  => [ 'Romanian',  		'iso-8859-2', 'ro', 'ro' ],
  'ru'  => [ 'Russian',   		'koi8-r',     'ru', 'ru' ],
  'sk'  => [ 'Slovak',    		'iso-8859-2', 'sk', 'sk' ],
'es_ES' => [ 'Spanish (Spain)',		'iso-8859-1', 'es', 'es' ],
  'tr'  => [ 'Turkish',	 		'iso-8859-9', 'tr', 'tr' ],
  'uk'  => [ 'Ukrainian', 		'koi8-u',     'uk', 'uk' ],
  'wa'  => [ 'Walon',     		'iso-8859-1', 'wa', 'wa:fr_BE' ],
);

my %charsets = (
  "armscii-8"  => [ "arm8.fnt",			"armscii8",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-*helv*-medium-r-normal--14-*-*-*-*-armscii-8" ],
  "iso-8859-1" => [ "lat0-sun16.psf",		"iso15", 
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1" ],
  "iso-8859-2" => [ "lat2-sun16.psf",		"iso02",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-2" ],
  "iso-8859-3" => [ "iso03.f16",		"iso03",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-3" ],
  "iso-8859-4" => [ "lat4u-16.psf",		"iso04",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-4" ],
  "iso-8859-5" => [ "iso05.f16",		"iso05",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-5" ],
# arabic needs special console driver for text mode [acon]
# (and gtk support isn't done yet)
  "iso-8859-6" => [ "iso06.f16",		"iso06",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-6" ],
  "iso-8859-7" => [ "iso07.f16",		"iso07",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-7" ],
# hebrew needs special console driver for text mode (none yet)
# (and gtk support isn't done yet)
  "iso-8859-8" => [ "iso08.f16",		"iso08",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-8" ],
  "iso-8859-9" => [ "lat5-16.psf",		"iso09",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-9" ],
  "iso-8859-15" => [ "lat0-sun16.psf",		"iso15",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-15" ],
# japanese needs special console driver for text mode [kon2]
  "jisx0208"   => [ "????",			"????",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"-*-*-medium-r-normal--14-*-*-*-*-*-jisx0208.1983-0," .
	"-*-*-medium-r-normal--14-*-*-*-*-*-jisx0201.1976-0" ],
  "koi8-r"     => [ "Cyr_a8x16.psf",		"koi2alt",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-koi8-r" ],
  "koi8-u"     => [ "ruscii_8x16.psf",		"koi2alt",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-koi8-u" ],
  "tcvn"       => [ "tcvn8x16.psf",		"tcvn",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-tcvn-5712" ],
  "viscii"     => [ "viscii10-8x16.psf",	"viscii",
	"*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1," .
	"*-helvetica-medium-r-normal--14-*-*-*-*-viscii1.1-1" ],
);

#-######################################################################################
#- Functions
#-######################################################################################

sub list { map { $_->[0] } values %languages }
sub lang2text { $languages{$_[0]} && $languages{$_[0]}[0] }
sub text2lang {
    my ($t) = @_;
    while (my ($k, $v) = each %languages) {
	lc($v->[0]) eq lc($t) and return $k;
    }
    die "unknown language $t";
}

sub set {
    my ($lang) = @_;

    if ($lang) {
	$ENV{LC_ALL}    = $lang;
	$ENV{LANG}      = $languages{$lang}[2]; 
	$ENV{LANGUAGES} = $languages{$lang}[3]; 
	if (my $f = $languages{$lang}[1]) { load_font($f) }
    } else {
	# stick with the default (English) */
	delete $ENV{LANG};
	delete $ENV{LC_ALL};
	delete $ENV{LINGUAS};
    }
}

sub write {
    my ($prefix) = @_;
    my $lang = $ENV{LC_ALL};

    $lang or return;
    local *F;
    open F, "> $prefix/etc/sysconfig/i18n" or die "failed to reset $prefix/etc/sysconfig/i18n for writing";
    my $f = sub { $_[1] and print F "$_[0]=$_[1]\n"; };

    &$f("LC_ALL", $lang);
    if (my $l = $languages{$lang}) {
	&$f("LANG", $l->[2]);
	&$f("LANGUAGE", $l->[3]);

	$l->[1] or return;
	if (my $c = $charsets{$l->[1]}) {
	    &$f("SYSFONT", $c->[0]);
	    &$f("SYSFONTACM", $c->[1]);

	    my $p = "$prefix/usr/lib/kbd";
	    commands::cp("-f", 
		     "$p/consolefonts/$c->[0].gz", 
		     glob_("$p/consoletrans/$c->[1]*"), 
		     "$prefix/etc/sysconfig/console");
	}
    }
}

sub load_font {
    my ($charset) = @_;
    my $fontFile = "lat0-sun16";
    my $fontSet = "*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1";

    if (my $c = $charsets{$charset}) {
	log::l("loading $charset font");
        $fontFile = $c->[0];
	$fontSet  = $c->[2]; 
    }

    # text mode font  
    log::l("loading font /usr/share/consolefonts/$fontFile");
    #c::loadFont("/tmp/$fontFile") or log::l("error in loadFont: one of PIO_FONT PIO_UNIMAPCLR PIO_UNIMAP PIO_UNISCRNMAP failed: $!");
    #print STDERR "\033(K";

    # X11 font
    log::l("fontset: " . $fontSet);
#    Gtk::Gdk::Font::fontset_load("*",$fontSet);
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; # 
