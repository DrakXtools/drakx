 package lang;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system);
use commands;
use log;

#-######################################################################################
#- Globals
#-######################################################################################
#- key (to be used in $LC_ALL), [0] = english name, [1] = charset encoding,
#- [2] = value for $LANG, [3] = value for LANGUAGE (a list of possible
#- languages, carefully choosen)
my %languages = (
  'en'  => [ 'English (US)',		undef,	      'en', 'en_US:en' ],
'en_GB' => [ 'English (UK)',		'iso-8859-1', 'en', 'en_GB:en' ],
  'af'  => [ 'Afrikaans',		'iso-8859-1', 'af', 'af:en_ZA' ],
#-'ar'  => [ 'Arabic',			'iso-8859-6', 'ar', 'ar' ],
  'bg'  => [ 'Bulgarian',		'cp1251',     'bg', 'bg' ],
  'br'  => [ 'Brezhoneg',		'iso-8859-1', 'br', 'br:fr_FR:fr' ],
  'ca'  => [ 'Catalan',			'iso-8859-1', 'ca', 'ca:es_ES:es:fr_FR:fr' ],
  'cs'  => [ 'Czech',			'iso-8859-2', 'cs', 'cs' ],
  'cy'  => [ 'Cymraeg (Welsh)',		'iso-8859-14','cy', 'cy:en_GB:en' ],
  'da'  => [ 'Danish',			'iso-8859-1', 'da', 'da' ],		
'de_AT' => [ 'German (Austria)',	'iso-8859-1', 'de', 'de_AT:de' ],
'de_DE' => [ 'German (Germany)',	'iso-8859-1', 'de', 'de_DE:de' ],
  'el'  => [ 'Greek',                   'iso-8859-7', 'el', 'el' ],
  'eo'  => [ 'Esperanto',		'iso-8859-3', 'eo', 'eo' ],
'es_AR' => [ 'Spanish (Argentina)',	'iso-8859-1', 'es', 'es_AR:es_UY:es:es_ES' ],
'es_ES' => [ 'Spanish (Spain, modern sorting)',	'iso-8859-1', 'es', 'es' ],
'es@tradicional' => [ 'Spanish (Spain, traditional sorting)', 'iso-8859-1', 'es', 'es' ],
'es_MX' => [ 'Spanish (Mexico)',	'iso-8859-1', 'es', 'es_MX:es:es_ES' ],
  'et'  => [ 'Estonian',		'iso-8859-15','et', 'et' ],
  'eu'  => [ 'Euskara (Basque)',	'iso-8859-1', 'eu', 'eu:es_ES:fr_FR:es:fr' ],
#-'fa'  => [ 'Farsi (Iranian)',		'isiri-3342', 'fa', 'fa' ],
'fr_FR' => [ 'French (France)',		'iso-8859-1', 'fr', 'fr_FR:fr' ],
  'ga'  => [ 'Gaeilge (Irish)',		'iso-8859-14','ga', 'ga:en_IE:en' ],
  'gl'  => [ 'Galician',		'iso-8859-1', 'gl', 'gl:es_ES:pt_PT:pt_BR:es:pt' ],
#- 'iw' was the old code for hebrew language
#-'he'  => [ 'Hebrew',			'iso-8859-8', 'he', 'he:iw_IL' ],
  'hr'  => [ 'Croatian',		'iso-8859-2', 'hr', 'hr' ],
  'hu'  => [ 'Hungarian', 		'iso-8859-2', 'hu', 'hu' ],
  'hy'  => [ 'Armenian',                'armscii-8',  'hy', 'hy' ],
#- 'in' was the old code for indonesian language; by putting LANGUAGE=id:in_ID
#- we catch the few catalog files still using the wrong code
  'id'  => [ 'Indonesian',		'iso-8859-1', 'id', 'id:in_ID' ],
  'is'  => [ 'Icelandic', 		'iso-8859-1', 'is', 'is' ],
  'it'  => [ 'Italian',   		'iso-8859-1', 'it', 'it_IT:it' ],
  'ja'  => [ 'Japanese',		'jisx0208',   'ja', 'ja_JP.ujis:ja' ],
  'ka'  => [ 'Georgian',                'georgian-academy', 'ka', 'ka' ],
  'ko'  => [ 'Korean',                  'ksc5601',    'ko', 'ko' ],
  'lt'  => [ 'Lithuanian',		'iso-8859-13','lt', 'lt' ],
#- 'mk' => [ 'Macedonian',		'iso-8859-5', 'mk', 'mk:sr' ],
  'nl'  => [ 'Dutch (Netherlands)',	'iso-8859-1', 'nl', 'nl_NL:nl' ],
  'no'  => [ 'Norwegian (Bokmaal)',	'iso-8859-1', 'no', 'no:no@nynorsk' ],
'no@nynorsk' => [ 'Norwegian (Nynorsk)','iso-8859-1', 'no', 'no@nynorsk:no' ],
  'pl'  => [ 'Polish',			'iso-8859-2', 'pl', 'pl' ],
'pt_BR' => [ 'Portuguese (Brazil)',	'iso-8859-1', 'pt_BR', 'pt_BR:pt_PT:pt' ],
'pt_PT' => [ 'Portuguese (Portugal)',	'iso-8859-1', 'pt', 'pt_PT:pt:pt_BR' ],
  'ro'  => [ 'Romanian',  		'iso-8859-2', 'ro', 'ro' ],
  'ru'  => [ 'Russian',   		'koi8-r',     'ru', 'ru' ],
  'sk'  => [ 'Slovak',    		'iso-8859-2', 'sk', 'sk' ],
#- 'sr' => [ 'Serbian',			'iso-8859-5', 'sr', 'sr:sp' ],
  'th'  => [ 'Thai',                    'tis620',     'th', 'th' ],
  'tr'  => [ 'Turkish',	 		'iso-8859-9', 'tr', 'tr' ],
  'uk'  => [ 'Ukrainian', 		'koi8-u',     'uk', 'uk' ],
  'vi'  => [ 'Vietnamese (TCVN)',       'tcvn',       'vi',
					'vi_VN.tcvn:vi_VN.tcvn-5712:vi' ],
'vi_VN.viscii' => [ 'Vietnamese (VISCII)','viscii',   'vi',
				        'vi_VN.viscii:vi_VN.tcvn-viscii1.1-1:vi' ],
  'wa'  => [ 'Walon',     		'iso-8859-1', 'wa', 'wa:fr_BE:fr' ],
'zh_TW.Big5' => [ 'Chinese (Big5)',     'Big5', 'zh_TW.Big5', 'zh_TW.Big5:zh_TW.big5:zh' ],
'zh_CN' => [ 'Chinese (GuoBiao)',	'gb2312', 'zh_CN', 'zh_CN.gb2312:zh' ],	
);

my %xim = (
  'zh_TW.Big5' => { 
	ENC => 'big5',
	XIM => 'xcin',
	XMODIFIERS => '"@im=xcin"',
  },
  'zh_CN' => {
	ENC => 'gb',
	XIM => 'xcin-zh_CN',
	XMODIFIERS => '"@im=xcin-zh_CN"',
  },
  'ko' => {
	ENC => 'kr',
	XIM => 'Ami',
	XMODIFIERS => '"@im=Ami"',
  },
  'ja' => {
	ENC => 'eucj',
	XIM => 'kinput2',
	XMODIFIERS => '"@im=kinput2"',
  }
);

sub std2 { "-mdk-helvetica-medium-r-normal-*-*-$_[1]-*-*-*-*-$_[0]" }
sub std_ { std2($_[0], 100), std2($_[0], 100) }
sub std  { std2($_[0], 100), std2($_[0],  80) }

my %charsets = (
  "armscii-8"  => [ "arm8",		"armscii8", std_("armscii-8") ],
#- chinese needs special console driver for text mode
  "Big5"       => [ undef,            undef,
	"-*-*-*-*-*-*-*-*-*-*-*-*-big5-0" ],
  "gb2312"     => [ undef,            undef,
        "-isas-song ti-medium-r-normal--16-*-*-*-*-*-gb2312.1980-0" ],
  "iso-8859-1" => [ "lat0-sun16",	"iso15", std("iso8859-1") ],
  "iso-8859-2" => [ "lat2-sun16",	"iso02", std("iso8859-2") ],
  "iso-8859-3" => [ "iso03.f16",	"iso03", std_("iso8859-3") ],
  "iso-8859-4" => [ "lat4u-16",		"iso04", std_("iso8859-4") ],
  "iso-8859-5" => [ "iso05.f16",	"iso05", std("iso8859-5") ],
#- arabic needs special console driver for text mode [acon]
#- (and gtk support isn't done yet)
  "iso-8859-6" => [ "iso06.f16",	"iso06", std_("iso8859-6") ],
  "iso-8859-7" => [ "iso07.f16",	"iso07", std_("iso8859-7") ],
#- hebrew needs special console driver for text mode (none yet)
#- (and gtk support isn't done yet)
  "iso-8859-8" => [ "iso08.f16",	"iso08", std_("iso8859-8") ],
  "iso-8859-9" => [ "lat5-16",		"iso09", std("iso8859-9") ],
  "iso-8859-13" => [ undef,		undef,   std_("iso8859-13") ],
  "iso-8859-14" => [ undef,		undef,   std_("iso8859-14") ],
  "iso-8859-15" => [ "lat0-sun16",	"iso15", std("iso8859-15") ],
#- japanese needs special console driver for text mode [kon2]
  "jisx0208"   => [ undef,		undef, 
	"-*-*-*-*-*-*-*-*-*-*-*-*-jisx*.*-0" ],
  "koi8-r"     => [ "Cyr_a8x16",	"koi2alt", std("koi8-r") ],
  "koi8-u"     => [ "ruscii_8x16",	"koi2alt", std("koi8-u") ],
  "cp1251"     => [ undef,		undef, std2("microsoft-cp1251",100) ],
#- korean needs special console driver for text mode
  "ksc5601"    => [ undef,            undef,
	"-*-*-*-*-*-*-*-*-*-*-*-*-ksc5601.1987-*" ],
  "tis620"     => [ undef,		undef,  std2("tis620.2533-1",120) ],
  "tcvn"       => [ "tcvn8x16",		"tcvn", std2("tcvn-5712", 130), std2("tcvn-5712", 100) ],
  "viscii"     => [ "viscii10-8x16",	"viscii",
	"-*-*-*-*-*-*-*-*-*-*-*-*-viscii1.1-1" ],
#- Farsi (iranian) needs special console driver for text mode [patching acon ?]
#- (and gtk support isn't done yet)
  "isiri-3342" => [ undef,		undef,
	"-*-*-*-*-*-*-*-*-*-*-*-*-isiri-3342" ],
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
	$ENV{LINGUAS}   = $languages{$lang}[3];
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

    my $h = { LC_ALL => $lang };
    if (my $l = $languages{$lang}) {
	add2hash $h, { LANG => $l->[2], LANGUAGE => $l->[2], LINGUAS => $l->[3] };

	my $c = $charsets{$l->[1] || ''};
	if ($c && $c->[0] && $c->[1]) {	    
	    add2hash $h, { SYSFONT => $c->[0], SYSFONTACM => $c->[1] };

	    my $p = "$prefix/usr/lib/kbd";
	    commands::cp("-f",
		     "$p/consolefonts/$c->[0].psf.gz",
		     glob_("$p/consoletrans/$c->[1]*"),
		     "$prefix/etc/sysconfig/console");
	}
	add2hash $h, $xim{$lang};
    }
    setVarsInSh("$prefix/etc/sysconfig/i18n", $h);
}

sub load_po($) {
    my ($lang) = @_;
    my ($s, $from, $to, $state, $fuzzy);

    $s .= "package po::I18N;\n";
    $s .= "\%$lang = (";

#-  $lang = substr($lang, 0, 2);
    my $f; -e ($f = "$_/po/$lang.po") and last foreach @INC;
    unless (-e $f) {
	-e ($f = "$_") and last foreach @INC;
	$f = commands::install_cpio("$f/po", "$lang.po");
    }
    local *F; open F, $f; #- not returning here help avoiding reading the same multiple times.
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
