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
#- key (to be used in $LC_ALL), [0] = english name, [1] = charset encoding,
#- [2] = value for $LANG, [3] = value for LANGUAGE (a list of possible
#- languages, carefully choosen)
my %languages = (
  'en'  => [ 'English',			undef,	      'en', 'en_US' ],
'de_DE' => [ 'German (Germany)',	'iso-8859-1', 'de', 'de_DE' ],
  'el'  => [ 'Greek',                   'iso-8859-7', 'el', 'el' ],
'es_ES' => [ 'Spanish (Spain)',		'iso-8859-1', 'es', 'es' ],
'fr_FR' => [ 'French (France)',		'iso-8859-1', 'fr', 'fr_FR' ],
#- Galician users may want to also have spanish and portuguese languages 
  'gl'  => [ 'Galician',		'iso-8859-1', 'gl', 'gl:es:pt' ],
  'hu'  => [ 'Hungarian', 		'iso-8859-2', 'hu', 'hu' ],
  'hy'  => [ 'Armenian',                'armscii-8',  'hy', 'hy' ],
#- 'in' was the old code for indonesian language; by putting LANGUAGE=id:in
#- we catch the few catalog files still using the wrong code
  'id'  => [ 'Indonesian',		'iso-8859-1', 'id', 'id:in' ],
  'is'  => [ 'Icelandic', 		'iso-8859-1', 'is', 'is' ],
  'it'  => [ 'Italian',   		'iso-8859-1', 'it', 'it_IT' ],
  'ja'  => [ 'Japanese',		'jisx0208',   'ja', 'ja_JP.ujis' ],
  'ka'  => [ 'Georgian',                'georgian-academy', 'ka', 'ka' ],
  'ko'  => [ 'Korean',                  'ksc5601',    'ko', 'ko' ],
  'no'  => [ 'Norwegian (Bokmaal)',	'iso-8859-1', 'no', 'no:no@nynorsk' ],
'no@nynorsk' => [ 'Norwegian (Nynorsk)','iso-8859-1','no', 'no@nynorsk' ],
'pt_BR' => [ 'Portuguese (Brazil)',	'iso-8859-1', 'pt', 'pt_BR:pt_PT' ],
'pt_PT' => [ 'Portuguese (Portugal)',	'iso-8859-1', 'pt', 'pt_PT:pt_BR' ],
  'ro'  => [ 'Romanian',  		'iso-8859-2', 'ro', 'ro' ],
  'ru'  => [ 'Russian',   		'koi8-r',     'ru', 'ru' ],
  'sk'  => [ 'Slovak',    		'iso-8859-2', 'sk', 'sk' ],
  'tr'  => [ 'Turkish',	 		'iso-8859-9', 'tr', 'tr' ],
  'uk'  => [ 'Ukrainian', 		'koi8-u',     'uk', 'uk' ],
  'vi'  => [ 'Vietnamese (TCVN)',       'tcvn',       'vi',
					'vi_VN.tcvn:vi_VN.tcvn-5712' ],
'vi_VN.viscii' => [ 'Vietnamese (VISCII)','viscii',   'vi',
				        'vi_VN.viscii:vi_VN.tcvn-viscii1.1-1' ],
  'wa'  => [ 'Walon',     		'iso-8859-1', 'wa', 'wa:fr_BE' ],
'zh_TW.Big5' => [ 'Chinese (Big5)',     'Big5', 'zh_TW.Big5', 'zh_TW.Big5:zh_TW.big5' ],
);

sub std2 { "-mdk-helvetica-medium-r-normal-*-*-$_[1]-*-*-*-*-$_[0]" }
sub std_ { std2($_[0], 100), std2($_[0], 100) }
sub std  { std2($_[0], 100), std2($_[0],  80) }

my %charsets = (
  "armscii-8"  => [ "arm8",			"armscii8", std_("armscii-8") ],
#- chinese needs special console driver for text mode
  "Big5"       => [ "?????",                    "????",
	"-*-*-*-*-*-*-*-*-*-*-*-*-big5-0" ],
  "iso-8859-1" => [ "lat0-sun16",		"iso15", std("iso8859-1") ],
  "iso-8859-2" => [ "lat2-sun16",		"iso02", std("iso8859-2") ],
  "iso-8859-3" => [ "iso03.f16",		"iso03", std_("iso8859-3") ],
  "iso-8859-4" => [ "lat4u-16",		        "iso04", std_("iso8859-4") ],
  "iso-8859-5" => [ "iso05.f16",		"iso05", std("iso8859-5") ],
#- arabic needs special console driver for text mode [acon]
#- (and gtk support isn't done yet)
  "iso-8859-6" => [ "iso06.f16",		"iso06", std_("iso8859-6") ],
  "iso-8859-7" => [ "iso07.f16",		"iso07", std_("iso8859-7") ],
#- hebrew needs special console driver for text mode (none yet)
#- (and gtk support isn't done yet)
  "iso-8859-8" => [ "iso08.f16",		"iso08", std_("iso8859-8") ],
  "iso-8859-9" => [ "lat5-16",		        "iso09", std("iso8859-9") ],
  "iso-8859-13" => [ "??????",			"?????", std_("iso8859-13") ],
  "iso-8859-14" => [ "??????",			"?????", std_("iso8859-14") ],
  "iso-8859-15" => [ "lat0-sun16",		"iso15", std("iso8859-15") ],
#- japanese needs special console driver for text mode [kon2]
  "jisx0208"   => [ "????",			"????", 
	"-*-*-*-*-*-*-*-*-*-*-*-*-jisx*.*-0" ],
  "koi8-r"     => [ "Cyr_a8x16",		"koi2alt", std("koi8-r") ],
  "koi8-u"     => [ "ruscii_8x16",		"koi2alt", std("koi2-u") ],
#- korean needs special console driver for text mode
  "ksc5601"    => [ "?????",                    "?????",
	"-*-*-*-*-*-*-*-*-*-*-*-*-ksc5601.1987-*" ],
  "tcvn"       => [ "tcvn8x16",		        "tcvn", std2("tcvn-5712", 130), std2("tcvn-5712", 100) ],
  "viscii"     => [ "viscii10-8x16",	        "viscii",
	"-*-*-*-*-*-*-*-*-*-*-*-*-viscii*.*-*" ],
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
    my ($lang, $prefix) = @_;

    if ($lang) {
	$ENV{LC_ALL}    = $lang;
	$ENV{LANG}      = $languages{$lang}[2];
	$ENV{LANGUAGE}  = $languages{$lang}[3];
    } else {
	# stick with the default (English) */
	delete $ENV{LANG};
	delete $ENV{LC_ALL};
	delete $ENV{LINGUAS};
    }
    commands::install_cpio("/usr/share/locale", $lang);
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
		     "$p/consolefonts/$c->[0].psf.gz",
		     glob_("$p/consoletrans/$c->[1]*"),
		     "$prefix/etc/sysconfig/console");
	}
    }
}

sub load_po($) {
    my ($lang) = @_;
    my ($s, $from, $to, $state, $fuzzy);

    $s .= "package po::I18N;\n";
    $s .= "\%$lang = (";

    my $f; -e ($f = "$_/po/$lang.po") and last foreach @INC;
    unless (-e $f) {
	-e ($f = "$_") and last foreach @INC;
	$f = commands::install_cpio("$f/po", "$lang.po");
    }
    local *F; open F, $f or return;
    foreach (<F>) {
	/^msgstr/ and $state = 1;
	/^msgid/  && !$fuzzy and $state = 2;

	if (/^(#|$)/ && $state != 3) {
	    $state = 3;
	    $s .= qq("$from" => "$to",\n) if $from;
	    $from = $to = '';
	}
	$to .= (/"(.*)"/)[0] if $state == 1;
	$from .= (/"(.*)"/)[0] if $state == 2;

	$fuzzy = /^#, fuzzy/;
    }
    $s .= ");";
    no strict "vars";
    eval $s;
    !$@;
}


#-sub load_font {
#-    my ($charset) = @_;
#-    my $fontFile = "lat0-sun16";
#-
#-    if (my $c = $charsets{$charset}) {
#-	   log::l("loading $charset font");
#-	   $fontFile = $c->[0];
#-    }
#-
#-    # text mode font
#-    log::l("loading font /usr/share/consolefonts/$fontFile");
#-    #c::loadFont("/tmp/$fontFile") or log::l("error in loadFont: one of PIO_FONT PIO_UNIMAPCLR PIO_UNIMAP PIO_UNISCRNMAP failed: $!");
#-    #print STDERR "\033(K";
#-
#-}

sub get_x_fontset {
    my ($lang) = @_;

    my $l = $languages{$lang}  or return;
    my $c = $charsets{$l->[1]} or return;
    @$c[2..3];
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
