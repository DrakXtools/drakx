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
  'en'  => [ 'English (US)',		'iso-8859-1', 'en', 'en_US:en' ],
'en_GB' => [ 'English (UK)',		'iso-8859-1', 'en', 'en_GB:en' ],
  'af'  => [ 'Afrikaans',		'iso-8859-1', 'af', 'af:en_ZA' ],
  'ar'  => [ 'Arabic',			'iso-8859-6', 'ar', 'ar' ],
  'be'  => [ 'Belarussian',		'cp1251',     'be', 'be:be_BY.CP1251' ],
#- provide aliases for some not very standard names used in po files...
  'bg'  => [ 'Bulgarian',		'cp1251',     'bg', 'bg:bg.CP1251:bg_BG.CP1251' ],
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
  'fi'  => [ 'Suomi (Finnish)',		'iso-8859-15', 'fi', 'fi' ],
#-'fo'  => [ 'Faroese',			'iso-8859-1', 'fo', 'fo:??:??' ],
'fr_CA' => [ 'French (Canada)',		'iso-8859-1', 'fr', 'fr_CA:fr' ],
'fr_FR' => [ 'French (France)',		'iso-8859-1', 'fr', 'fr_FR:fr' ],
  'ga'  => [ 'Gaeilge (Irish)',		'iso-8859-14','ga', 'ga:en_IE:en' ],
#-'gd'  => [ 'Scottish gaelic',		'iso-8859-14','gd', 'gd:en_GB:en' ],
  'gl'  => [ 'Galician',		'iso-8859-1', 'gl', 'gl:es_ES:pt_PT:pt_BR:es:pt' ],
#-'gv'	=> [ 'Manx gaelic',		'iso-8859-14','gv', 'gv:en_GB:en' ],
#- 'iw' was the old code for hebrew language
  'he'  => [ 'Hebrew',			'iso-8859-8', 'he', 'he:iw_IL' ],
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
  'kl'  => [ 'Greenlandic (inuit)',	'iso-8859-1', 'kl', 'kl' ],
  'ko'  => [ 'Korean',                  'ksc5601',    'ko', 'ko' ],
#-'kw'	=> [ 'Cornish gaelic',		'iso-8859-14','kw', 'kw:en_GB:en' ],
#-'lo'  => [ 'Laotian',			'mulelao-1',  'lo', 'lo' ],
  'lt'  => [ 'Lithuanian',		'iso-8859-13','lt', 'lt' ],
  'lv'  => [ 'Latvian',			'iso-8859-13','lv', 'lv' ],   
#-'mk'  => [ 'Macedonian (Cyrillic)',	'iso-8859-5', 'mk', 'mk:sp:sr' ],
#-'mk_latin'=> [ 'Macedonian (Latin)',	'iso-8859-2', 'mk_latin', 'mk_latin:sr' ],
#-'ms'  => [ 'Malay',			'iso-8859-1', 'ms', 'ms' ],
  'nl'  => [ 'Dutch (Netherlands)',	'iso-8859-1', 'nl', 'nl_NL:nl' ],
  'no'  => [ 'Norwegian (Bokmaal)',	'iso-8859-1', 'no', 'no:no@nynorsk' ],
'no@nynorsk' => [ 'Norwegian (Nynorsk)','iso-8859-1', 'no', 'no@nynorsk:no' ],
#-'oc'  => [ 'Occitan',			'iso-8859-1', 'oc', 'oc:fr_FR' ],
#-'pd'	=> [ 'Plauttdietsch',		'iso-8859-1', 'pd', 'pd' ],
  'pl'  => [ 'Polish',			'iso-8859-2', 'pl', 'pl' ],
#-'pp'	=> [ 'Papiamento',		'iso-8859-1', 'pp', 'pp' ],
'pt_BR' => [ 'Portuguese (Brazil)',	'iso-8859-1', 'pt_BR', 'pt_BR:pt_PT:pt' ],
'pt_PT' => [ 'Portuguese (Portugal)',	'iso-8859-1', 'pt', 'pt_PT:pt:pt_BR' ],
  'ro'  => [ 'Romanian',  		'iso-8859-2', 'ro', 'ro' ],
  'ru'  => [ 'Russian',   		'koi8-r',     'ru', 'ru' ],
  'sk'  => [ 'Slovak',    		'iso-8859-2', 'sk', 'sk' ],
  'sl'  => [ 'Slovenian',		'iso-8859-2', 'sl', 'sl' ],
  'sp'  => [ 'Serbian (Cyrillic)',	'iso-8859-5', 'sp', 'sp:sr' ],
  'sr'  => [ 'Serbian (Latin)',		'iso-8859-2', 'sr', 'sr' ],
  'sv'  => [ 'Swedish',			'iso-8859-1', 'sv', 'sv' ],
  'th'  => [ 'Thai',                    'tis620',     'th', 'th' ],
  'tr'  => [ 'Turkish',	 		'iso-8859-9', 'tr', 'tr' ],
  'uk'  => [ 'Ukrainian', 		'koi8-u',     'uk', 'uk' ],
  'vi'  => [ 'Vietnamese (TCVN)',       'tcvn',       'vi',
					'vi_VN.tcvn:vi_VN.tcvn-5712:vi' ],
'vi_VN.viscii' => [ 'Vietnamese (VISCII)','viscii',   'vi',
				        'vi_VN.viscii:vi_VN.tcvn-viscii1.1-1:vi' ],
  'wa'  => [ 'Walon',     		'iso-8859-1', 'wa', 'wa:fr_BE:fr' ],
#-'yi'	=> [ 'Yiddish',			'cp1255',     'yi', 'yi' ],
'zh_TW.Big5' => [ 'Chinese (Big5)',     'Big5', 'zh_TW.Big5', 'zh_TW.Big5:zh_TW.big5:zh' ],
'zh_CN' => [ 'Chinese (GuoBiao)',	'gb2312', 'zh_CN', 'zh_CN:zh_CN.GB2312:zh_CN.gb2312:zh' ],
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

sub std2 { "-*-*-medium-r-normal-*-$_[1]-*-*-*-*-*-$_[0]" }
sub std_ { std2($_[0], 10), std2($_[0], 10) }
sub std  { std2($_[0], 10), std2($_[0],  8) }

#- [0]: console font name; [1]: unicode map for console font
#- [2]: acm file for console font; [3]: X11 fontset
my %charsets = (
  "armscii-8"  => [ "arm8",		"armscii8.uni",	"trivial.trans", 
	std_("armscii-8") ],
#- chinese needs special console driver for text mode
  "Big5"       => [ undef,		undef,		undef,
	"-*-*-*-*-*-*-*-*-*-*-*-*-big5-0" ],
  "gb2312"     => [ undef,		undef,		undef,
        "-*-*-*-*-*-*-*-*-*-*-*-*-gb2312.1980-0" ],
  "georgian-academy" => [ "t_geors",	"geors.uni",	"trivial.trans",
	"-*-*-*-*-*-*-*-*-*-*-*-*-georgian-academy" ],
  "georgian-ps" => [ "t_geors",		"geors.uni",	"geors_to_geops.trans",
	"-*-*-*-*-*-*-*-*-*-*-*-*-georgian-academy" ],
  "iso-8859-1" => [ "lat0-sun16",	undef,		"iso15",
	std("iso8859-1") ],
  "iso-8859-2" => [ "lat2-sun16",	undef,		"iso02",
	std("iso8859-2") ],
  "iso-8859-3" => [ "iso03.f16",	undef,		"iso03",
	std_("iso8859-3") ],
  "iso-8859-4" => [ "lat4u-16",		undef,		"iso04",
	std_("iso8859-4") ],
  "iso-8859-5" => [ "iso05.f16",	"iso05",	"trivial.trans",
	std("iso8859-5") ],
#- arabic needs special console driver for text mode [acon]
#- (and gtk support isn't done yet)
  "iso-8859-6" => [ "iso06.f16",	"iso06",	"trivial.trans",
	std_("iso8859-6") ],
  "iso-8859-7" => [ "iso07.f16",	"iso07",	"trivial.trans",
	std_("iso8859-7") ],
#- hebrew needs special console driver for text mode (none yet)
#- (and gtk support isn't done yet)
  "iso-8859-8" => [ "iso08.f16",	"iso08",	"trivial.trans",
	std_("iso8859-8") ],
  "iso-8859-9" => [ "iso09.f16",	"iso09",	"trivial.trans",
	std("iso8859-9") ],
  "iso-8859-13" => [ "tlat7",		"iso01",	"trivial.trans",
	std_("iso8859-13") ],
  "iso-8859-14" => [ "tlat8",		"iso01",	"trivial.trans",
	std_("iso8859-14") ],
  "iso-8859-15" => [ "lat0-sun16",	undef,		"iso15",
	std("iso8859-15") ],
#- japanese needs special console driver for text mode [kon2]
  "jisx0208"   => [ undef,		undef,		"trivial.trans",
	"-*-*-*-*-*-*-*-*-*-*-*-*-jisx*.*-0" ],
  "koi8-r"     => [ "koi8-8x16",	"koi8-r",	"trivial.trans",
	std("koi8-r") ],
  "koi8-u"     => [ "koi8u_8x16",	"koi8-r",	"trivial.trans",
	std("koi8-u") ],
  "cp1251"     => [ "iso05.f16",	"iso05",	"iso05_to_cp1251.trans",
	std("microsoft-cp1251") ],
#- Yiddish needs special console driver for text mode (none yet)
#- (and gtk support isn't done yet)
  "cp1255"     => [ "iso08.f16",        "iso08",        "trivial.trans",
	std_("microsoft-cp1255") ],
#- korean needs special console driver for text mode
  "ksc5601"    => [ undef,		undef,		undef,
	"-*-*-*-*-*-*-*-*-*-*-*-*-ksc5601.1987-*" ],
#- I have no console font for Thai...
  "tis620"     => [ undef,		undef,		"trivial.trans",
	std2("tis620.2533-1",12) ],
  "tcvn"       => [ "tcvn8x16",		"tcvn",		"trivial.trans",
	std2("tcvn-5712", 13), std2("tcvn-5712", 10) ],
  "viscii"     => [ "viscii10-8x16",	"viscii.uni",	"viscii1.0_to_viscii1.1.trans",
	"-*-*-*-*-*-*-*-*-*-*-*-*-viscii1.1-1" ],
#- Farsi (iranian) needs special console driver for text mode [patching acon ?]
#- (and gtk support isn't done yet)
  "isiri-3342" => [ undef,		undef,		"trivial.trans",
	"-*-*-*-*-*-*-*-*-*-*-*-*-isiri-3342" ],
);

#-######################################################################################
#- Functions
#-######################################################################################

sub list { sort { $a cmp $b } map { $_->[0] } values %languages }
sub lang2text { $languages{$_[0]} && $languages{$_[0]}[0] }
sub text2lang {
    my ($t) = @_;
    foreach (keys %languages) {
	lc($languages{$_}[0]) eq lc($t) and return $_;
    }
    die "unknown language $t";
}

sub set {
    my ($lang) = @_;

    if ($lang) {
	#- use extract_archive that follow symlinks and expand directory.
	#- it is necessary as there is a lot of symlinks inside locale.cz2,
	#- using a compressed cpio archive is nighmare to extract all files.
	#- reset locale environment variable to avoid any warnings by perl,
	#- so installation of new locale is done with empty locale ...
	unless (-e "$ENV{SHARE_PATH}/locale/".$languages{$lang}[2]) {
	    @ENV{qw(LANG LC_ALL LANGUAGE LINGUAS)} = ();

	    eval { commands::rm("-r", "$ENV{SHARE_PATH}/locale") };
	    require 'run_program.pm';
	    run_program::run("extract_archive", "$ENV{SHARE_PATH}/locale.cz2", "$ENV{SHARE_PATH}/locale", $languages{$lang}[2]);
	}

	$ENV{LC_ALL}    = $lang;
	$ENV{LANG}      = $languages{$lang}[2];
	$ENV{LANGUAGE}  = $languages{$lang}[3];
#- apparently autoconf/automake doesn't like LINGUAS having a list of values
#-	$ENV{LINGUAS}   = $languages{$lang}[3];
    } else {
	# stick with the default (English) */
	delete $ENV{LANG};
	delete $ENV{LC_ALL};
	delete $ENV{LINGUAGE};
	delete $ENV{LINGUAS};
	delete $ENV{RPM_INSTALL_LANG};
    }
}

sub set_langs {
    my ($l) = @_; 
    $l or return;
    $ENV{RPM_INSTALL_LANG} = member('all', @$l) ? 'all' :
      join ':', uniq(map { substr($languages{$_}[2], 0, 2) } @$l);
    log::l("RPM_INSTALL_LANG: $ENV{RPM_INSTALL_LANG}");
}

sub write {
    my ($prefix) = @_;
    my $lang = $ENV{LC_ALL};

    $lang or return;

    my $h = { LC_CTYPE => $lang };
    add2hash $h, { LC_COLLATE => $lang };
    add2hash $h, { LC_MESSAGES => $lang };
    add2hash $h, { LC_NUMERIC => $lang };
    add2hash $h, { LC_MONETARY => $lang };
    add2hash $h, { LC_TIME => $lang };
    if (my $l = $languages{$lang}) {
	add2hash $h, { LANG => $l->[2], LANGUAGE => $l->[3], RPM_INSTALL_LANG => $l->[3] };

	my $c = $charsets{$l->[1] || ''};
	if ($c && $c->[0] && $c->[1]) {	    
	    add2hash $h, { SYSFONT => $c->[0], UNIMAP => $c->[1], SYSFONTACM => $c->[2] };

	    my $p = "$prefix/usr/lib/kbd";
	    eval {
		commands::cp("-f",
		     "$p/consolefonts/$c->[0].psf.gz",
		     glob_("$p/consoletrans/$c->[1]*"),
		     glob_("$p/consoletrans/$c->[2]*"),
		     "$prefix/etc/sysconfig/console");
	    };
	    $@ and log::l("missing console $c->[0], $c->[1], $c->[2]");
	}
	add2hash $h, $xim{$lang};
    }
    setVarsInSh("$prefix/etc/sysconfig/i18n", $h);
}

sub load_po($) {
    my ($lang) = @_;
    my ($s, $from, $to, $state, $fuzzy);

    $s .= "package po::I18N;\n";
    $s .= "no strict;\n";
    $s .= "\%{'$lang'} = (";

    my $f; -e ($f = "$_/po/$lang.po") and last foreach @INC;

    local *F;
    unless ($f && -e $f) {
	-e ($f = "$_/po/$lang.po.bz2") and last foreach @INC;
	if (-e $f) {
	    open F, "bzip2 -dc $f 2>/dev/null |";
	} else {
	    -e ($f = "$_/po.cz2") and last foreach @INC;
	    log::l("trying to load $lang.po from $f");
	    open F, "extract_archive $f '' $lang.po 2>/dev/null |";
	}
    } else {
	open F, $f; #- not returning here help avoiding reading the same multiple times.
    }
    foreach (<F>) {
	/^msgstr/ and $state = 1;
	/^msgid/  && !$fuzzy and $state = 2;

	if (/^(#|$)/ && $state != 3) {
	    $state = 3;
	    if (my @l = $to =~ /%(\d+)\$/g) {
		$to =~ s/%(\d+)\$/%/g;
		$to = qq([ "$to", ) . join(",", map { $_ - 1 } @l) . " ],";
	    } else {
		$to = qq("$to");
	    }
	    $s .= qq("$from" => $to,\n) if $from;
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


sub load_console_font {
    my ($lang) = @_;
    my ($charset) = $languages{$lang}[1] ;
    my $f = "-f lat0-sun16";

    if (my $c = $charsets{$charset}) {
	   if ($c->[0]) { $f = "-f " . $c->[0] ; } 
	   if ($c->[1]) { $f = $f . " -u " . $c->[1] ; }
	   if ($c->[2]) { $f = $f . " -m " . $c->[2] ; }
    }

    log::l("loading console font: consolechars $f");
    system("consolechars $f"); 

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
#-    log::l("loading font $ENV{SHARE_PATH}/consolefonts/$fontFile");
#-    #c::loadFont("/tmp/$fontFile") or log::l("error in loadFont: one of PIO_FONT PIO_UNIMAPCLR PIO_UNIMAP PIO_UNISCRNMAP failed: $!");
#-    #print STDERR "\033(K";
#-
#-}

sub get_x_fontset {
    my ($lang) = @_;

    my $l = $languages{$lang}  or return;
    my $c = $charsets{$l->[1]} or return;
    @$c[3..4];
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
