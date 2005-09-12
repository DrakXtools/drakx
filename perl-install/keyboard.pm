package keyboard; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use detect_devices;
use run_program;
use lang;
use log;
use c;


#-######################################################################################
#- Globals
#-######################################################################################
my $KMAP_MAGIC = 0x8B39C07F;

#- a best guess of the keyboard layout, based on the choosen locale
#- beware only the first 5 characters of the locale are used
our %lang2keyboard =
(
  'af'  => 'us_intl',
  'am'  => 'us:90',
  'ar'  => 'ar:90',
  'as'  => 'ben:90 ben2:80 us_intl:5',
  'az'  => 'az:90 tr_q:10 us_intl:5',
'az_IR' => 'ir:90',
  'be'  => 'by:90 ru:50 ru_yawerty:40',
# 'ber' => 'tifinagh:80 tifinagh_p:70',
  'ber' => 'tifinagh_p:90',
  'bg'  => 'bg_phonetic:60 bg:50',
  'bn'  => 'ben:90 ben2:80 dev:20 us_intl:5',
  'bo'	=> 'dz',
  'br'  => 'fr:90',
  'bs'  => 'bs:90',
  'ca'  => 'es:90 fr:15',
  'chr' => 'chr:80 us:60 us_intl:60',
  'cs'  => 'cz_qwerty:70 cz:50',
  'cy'  => 'uk:90',
  'da'  => 'dk:90',
  'de'  => 'de_nodeadkeys:70 de:50 be:50 ch_de:50',
  'dz'	=> 'dz',
  'el'  => 'gr:90',
  'en'  => 'us:89 us_intl:50 qc:50 uk:50',
'en_IE' => 'ie:80 uk:70 dvorak_gb:10',
'en_US' => 'us:90 us_intl:50 dvorak:10',
'en_GB' => 'uk:89 us:60 us_intl:50 dvorak_gb:10',
  'eo'  => 'us_intl:89 dvorak_eo:30 dvorak:10',
  'es'  => 'es:85 la:80 us_intl:50',
  'et'  => 'ee:90',
  'eu'  => 'es:90 fr:15',
  'fa'  => 'ir:90',
  'fi'  => 'fi:90',
  'fo'  => 'fo:80 is:70 dk:60',
  'fr'  => 'fr:89 qc:85 be:85 ch_fr:70 dvorak_fr:20',
  'fur' => 'it:90',
  'ga'  => 'ie:80 uk:70 dvorak_gb:10',
  'gd'  => 'uk:80 ie:70 dvorak_gb:10',
  'gl'  => 'es:90',
  'gn'  => 'la:85 es:80 us_intl:50',
  'gu'  => 'guj:90',
  'gv'  => 'uk:80 ie:70',
  'he'  => 'il:90 il_phonetic:10',
  'hi'  => 'dev:90',
  'hr'  => 'hr:90 si:50',
  'hu'  => 'hu:90',
  'hy'  => 'am:90 am_old:10 am_phonetic:5',
  'ia'  => 'us:90 us_intl:20',
  'id'  => 'us:90 us_intl:20',
  'is'  => 'is:90',
  'it'  => 'it:90 ch_fr:50 ch_de:50',
  'iu'  => 'iu:90',
  'ja'  => 'jp:90 us:50 us_intl:20',
  'ka'  => 'ge_la:90 ge_ru:50',
  'kl'  => 'dk:80 us_intl:30',
  'kn'  => 'kan:90',
  'ko'  => 'kr:90 us:60',
  'ku'  => 'tr_q:90 tr_f:30',
'ku_IQ' => 'ku:90',
  'kw'  => 'uk:80 ie:70',
  'ky'  => 'ky:90 ru_yawerty:40',
  'lb'  => 'ch_fr:89 be:85 us_intl:70 fr:60 dvorak_fr:20',
  'li'  => 'us_intl:80 be:70 nl:10 us:5',
  'lo'  => 'lao:90',
  'lt'  => 'lt:80 lt_new:70 lt_b:60 lt_p:50',
  'ltg' => 'lv:90 lt:40 lt_new:30 lt_b:20 lt_p:10 ee:5',
  'lv'  => 'lv:90 lt:40 lt_new:30 lt_b:20 lt_p:10 ee:5',
  'mi'  => 'us_intl:90 uk:20 us:10',
  'mk'  => 'mk:90',
  'ml'  => 'mal:90',
  'mn'  => 'mng:90 ru:20 ru_yawerty:5',
  'mr'  => 'dev:90',
  'ms'  => 'us:90 us_intl:20',
  'mt'  => 'mt:90 mt_us:35 us_intl:10',
  'my'  => 'mm:90',
  'nb'  => 'no:90 dvorak_no:10',
  'nds' => 'de_nodeadkeys:70 de:50 us_intl:40 nl:10 us:5',
  'ne'  => 'dev:90',
  'nl'  => 'us_intl:80 be:70 nl:10 us:5',
  'nn'  => 'no:90 dvorak_no:10',
  'no'  => 'no:90 dvorak_no:10', # for compatiblity only
  'oc'  => 'fr:90',
  'or'  => 'ori:90',
  'pa'  => 'gur:90',
  'ph'  => 'us:90 us_intl:20',
  'pl'  => 'pl:90 pl2:60 dvorak_pl:10',
  'pp'  => 'br:80 la:20 pt:10 us_intl:30',
  'ps'  => 'ps:80 sd:60',
'pt_BR' => 'br:90 la:20 pt:10 us_intl:30',
  'pt'  => 'pt:90',
  'ro'  => 'ro2:80 ro:40 us_intl:10',
  'ru'  => 'ru:85 ru_yawerty:80 ua:50',
  'sc'  => 'it:90',
  'sd'  => 'sd:80 ar:20',
  'se'  => 'sapmi:70 sapmi_sefi:50',
  'sh'  => 'yu:80',
  'sk'  => 'sk_qwerty:80 sk:70',
  'sl'  => 'si:90 hr:50',
  'sq'  => 'al:90',
  'sr'  => 'sr:80',
  'ss'  => 'us_intl',
  'st'  => 'us_intl',
  'sv'  => 'se:90 fi:30 dvorak_se:10',
  'ta'  => 'tscii:80 tml:20',
  'te'  => 'tel:90',
  'tg'  => 'tj:90 ru_yawerty:40',
  'th'  => 'th:80 th_pat:50 th_tis:60',
  'tk'  => 'tk:80 tr_q:50 tr_f:40',
  'tl'  => 'us:90 us_intl:20',
  'tr'  => 'tr_q:90 tr_f:30',
  'tt'  => 'ru:50 ru_yawerty:40',
  'uk'  => 'ua:90 ru:50 ru_yawerty:40',
  'ur'  => 'ur:80 sd:60 ar:20',
  'uz'  => 'uz:80 ru_yawerty:40',
  'uz\@Cyrl'  => 'uz:80 ru_yawerty:40',
  'uz\@Latn'  => 'us:80 uz:80',
  've'  => 'us_intl',
  'vi'  => 'vn:80 us:70 us_intl:60',
  'wa'  => 'be:90 fr:5',
  'xh'  => 'us_intl',
  'yi'  => 'il_phonetic:90 il:10 us_intl:10',
'zh_CN' => 'us:90',
'zh_TW' => 'us:90',
  'zu'  => 'us_intl',
);

# USB kbd table
# The numeric values are the bCountryCode field (5th byte)  of HID descriptor
# NOTE: we do not trust when the layout is declared as US layout (0x21)
# as most manufacturers just use that value when selling physical devices
# with different layouts printed on the keys.
my @usb2keyboard =
(
  qw(SKIP ar_SKIP be ca_SKIP qc cz dk fi fr de gr il hu us_intl it jp),
#- 0x10
  qw(kr la nl no ir pl pt ru sk es se ch_de ch_de ch_de tw_SKIP tr_q),
#- 0x20
  qw(uk us_SKIP yu tr_f),
#- higher codes not attribued as of 2002-02
);

#- key = extension for Xmodmap file, [0] = description of the keyboard,
#- [1] = name for loadkeys, [2] = name for XKB, [3] = "1" if it is
#- a multigroup layout (eg: one with latin/non-latin letters)
my %keyboards = (
arch() =~ /^sparc/ ? (
 "cz" => [ N_("_: keyboard\nCzech (QWERTZ)"), "sunt5-cz-us",	 "cz",    0 ],
 "de" => [ N_("_: keyboard\nGerman"),         "sunt5-de-latin1", "de",    0 ],
 "dvorak" => [ N_("_: keyboard\nDvorak"),     "sundvorak",       "dvorak",0 ],
 "es" => [ N_("_: keyboard\nSpanish"),        "sunt5-es",        "es",    0 ],
 "fi" => [ N_("_: keyboard\nFinnish"),        "sunt5-fi-latin1", "fi",    0 ],
 "fr" => [ N_("_: keyboard\nFrench"),         "sunt5-fr-latin1", "fr",    0 ],
 "no" => [ N_("_: keyboard\nNorwegian"),      "sunt4-no-latin1", "no",    0 ],
 "pl" => [ N_("_: keyboard\nPolish"),         "sun-pl-altgraph", "pl",    0 ],
 "ru" => [ N_("_: keyboard\nRussian"),        "sunt5-ru",        "ru",    1 ],
# TODO: check the console map
 "se" => [ N_("_: keyboard\nSwedish"),        "sunt5-fi-latin1", "se",    0 ],
 "uk" => [ N_("UK keyboard"),    "sunt5-uk",        "gb",    0 ],
 "us" => [ N_("US keyboard"),    "sunkeymap",       "us",    0 ],
) : (
 "al" => [ N_("_: keyboard\nAlbanian"),       "al",              "al",    0 ],
 "am_old" => [ N_("_: keyboard\nArmenian (old)"), "am_old",	 "am(old)", 1 ],
 "am" => [ N_("_: keyboard\nArmenian (typewriter)"), "am-armscii8", "am",   1 ],
 "am_phonetic" => [ N_("_: keyboard\nArmenian (phonetic)"), "am_phonetic", "am(phonetic)",1 ],
 "ar" => [ N_("_: keyboard\nArabic"),          "us",             "ar(digits)",   1 ],
 "az" => [ N_("_: keyboard\nAzerbaidjani (latin)"), "az",        "az",    0 ],
 "be" => [ N_("_: keyboard\nBelgian"),        "be2-latin1",      "be",    0 ],
 "ben" => [ N_("_: keyboard\nBengali (Inscript-layout)"), "us",  "ben",   1 ],
 "ben2" => [ N_("_: keyboard\nBengali (Probhat)"), "us", "ben(probhat)",  1 ],
"bg_phonetic" => [ N_("_: keyboard\nBulgarian (phonetic)"), "bg", "bg(phonetic)", 1 ],
 "bg" => [ N_("_: keyboard\nBulgarian (BDS)"), "bg",             "bg",    1 ],
 "br" => [ N_("_: keyboard\nBrazilian (ABNT-2)"), "br-abnt2",    "br",    0 ],
 "bs" => [ N_("_: keyboard\nBosnian"),	 "croat",           "bs",    0 ],
 "by" => [ N_("_: keyboard\nBelarusian"),     "by-cp1251",       "by",    1 ],
# old XKB layout
 "ch_de" => [ N_("_: keyboard\nSwiss (German layout)"), "sg-latin1", "de_CH", 0 ],
# old XKB layout
 "ch_fr" => [ N_("_: keyboard\nSwiss (French layout)"), "fr_CH-latin1", "fr_CH", 0 ],
# TODO: console map
 "chr" => [ N_("_: keyboard\nCherokee syllabics"), "us",         "chr",   1 ],
 "cz" => [ N_("_: keyboard\nCzech (QWERTZ)"), "cz",              "cz",    0 ],
 "cz_qwerty" => [ N_("_: keyboard\nCzech (QWERTY)"), "cz-lat2", "cz_qwerty", 0 ],
 "de" => [ N_("_: keyboard\nGerman"),         "de-latin1",       "de",    0 ],
 "de_nodeadkeys" => [ N_("_: keyboard\nGerman (no dead keys)"), "de-latin1-nodeadkeys", "de(nodeadkeys)", 0 ],
 "dev" => [ N_("_: keyboard\nDevanagari"),     "us",             "dev",   0 ],
 "dk" => [ N_("_: keyboard\nDanish"),         "dk-latin1",       "dk",    0 ],
 "dvorak" => [ N_("_: keyboard\nDvorak (US)"), "pc-dvorak-latin1", "dvorak", 0 ],
# TODO: console map
 "dvorak_eo" => [ N_("_: keyboard\nDvorak (Esperanto)"), "us",   "dvorak(eo)", 0 ],
# TODO: console map
 "dvorak_fr" => [ N_("_: keyboard\nDvorak (French)"),    "us",   "dvorak(fr)", 0 ],
# TODO: console map
 "dvorak_gb" => [ N_("_: keyboard\nDvorak (UK)"),        "pc-dvorak-latin1", "dvorak(gb)", 0 ],
 "dvorak_no" => [ N_("_: keyboard\nDvorak (Norwegian)"), "no-dvorak", "dvorak(no)", 0 ],
# TODO: console map
 "dvorak_pl" => [ N_("_: keyboard\nDvorak (Polish)"),    "us",   "dvorak(pl)", 0 ],
 "dvorak_se" => [ N_("_: keyboard\nDvorak (Swedish)"), "se-dvorak", "dvorak(se)", 0 ],
 "dz" => [ N_("_: keyboard\nDzongkha/Tibetan"), "us",            "dz",    1 ],
 "ee" => [ N_("_: keyboard\nEstonian"),       "ee-latin9",       "ee",    0 ],
 "es" => [ N_("_: keyboard\nSpanish"),        "es-latin1",       "es",    0 ],
 "fi" => [ N_("_: keyboard\nFinnish"),        "fi-latin1",       "fi",    0 ],
# there used to be a "fo" layout in XFree86...
 "fo" => [ N_("_: keyboard\nFaroese"),        "is",              "is",    0 ],
 "fr" => [ N_("_: keyboard\nFrench"),         "fr-latin1",       "fr",    0 ],
 "ge_ru" => [N_("_: keyboard\nGeorgian (\"Russian\" layout)"), "ge_ru-georgian_academy", "ge_ru",1],
 "ge_la" => [N_("_: keyboard\nGeorgian (\"Latin\" layout)"), "ge_la-georgian_academy", "ge_la",1],
 "gr" => [ N_("_: keyboard\nGreek"),          "gr-8859_7",       "el(extended)",  1 ],
 "gr_pl" => [ N_("_: keyboard\nGreek (polytonic)"), "gr-8859_7", "el(polytonic)", 1 ],
 "guj" => [ N_("_: keyboard\nGujarati"),      "us",              "guj",   1 ],
 "gur" => [ N_("_: keyboard\nGurmukhi"),      "us",              "gur",   1 ],
 "hr" => [ N_("_: keyboard\nCroatian"),       "croat",           "hr",    0 ],
 "hu" => [ N_("_: keyboard\nHungarian"),      "hu-latin2",       "hu",    0 ],
 "ie" => [ N_("_: keyboard\nIrish"),          "uk",              "ie",    0 ],
 "il" => [ N_("_: keyboard\nIsraeli"),        "il-8859_8",       "il",    1 ],
 "il_phonetic" => [ N_("_: keyboard\nIsraeli (phonetic)"), "hebrew", "il_phonetic", 1 ],
 "ir" => [ N_("_: keyboard\nIranian"),        "ir-isiri_3342",   "ir",    1 ],
 "is" => [ N_("_: keyboard\nIcelandic"),      "is-latin1",       "is",    0 ],
 "it" => [ N_("_: keyboard\nItalian"),        "it-latin1",       "it",    0 ],
 "iu" => [ N_("_: keyboard\nInuktitut"),      "us",              "iu",    1 ],
# old XKB layout
# Japanese keyboard is dual latin/kana; but telling it here shows a
# message to choose the switching key that is misleading, as input methods
# are not automatically enabled when typing in kana
 "jp" => [ N_("_: keyboard\nJapanese 106 keys"), "jp106",        "jp",    0 ],
 "kan" => [ N_("_: keyboard\nKannada"),        "us",              "kan",  1 ],
# There is no XKB korean file yet; but using xmodmap one disables
# some functionality; "us" used for XKB until this is fixed
 "kr" => [ N_("_: keyboard\nKorean"),          "us",             "us",    1 ],
# TODO: console map
 "ku" => [ N_("_: keyboard\nKurdish (arabic script)"), "us",     "ku",    1 ],
 "ky" => [ N_("_: keyboard\nKyrgyz"),          "ky",             "ky",    1 ],
 "la" => [ N_("_: keyboard\nLatin American"), "la-latin1",       "la",    0 ],
# TODO: console map
 "lao" => [ N_("_: keyboard\nLaotian"),	 "us",	            "lo",    1 ], 
 "lt" => [ N_("_: keyboard\nLithuanian AZERTY (old)"), "lt-latin7", "lt(lt_a)", 0 ],
#- TODO: write a console kbd map for lt_new
 "lt_new" => [ N_("_: keyboard\nLithuanian AZERTY (new)"), "lt-latin7", "lt(lt_std)", 0 ],
 "lt_b" => [ N_("_: keyboard\nLithuanian \"number row\" QWERTY"), "ltb-latin7", "lt(lt_us)", 1 ],
 "lt_p" => [ N_("_: keyboard\nLithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt(phonetic)", 0 ],
 "lv" => [ N_("_: keyboard\nLatvian"),	 "lv-latin7",       "lv",    0 ],
 "mal" => [ N_("_: keyboard\nMalayalam"),	 "us",              "ml(mlplusnum)", 1 ],
 "mk" => [ N_("_: keyboard\nMacedonian"),	 "mk",              "mk",    1 ],
 "mm" => [ N_("_: keyboard\nMyanmar (Burmese)"), "us",           "mm",    1 ],
 "mng" => [ N_("_: keyboard\nMongolian (cyrillic)"), "us",       "mng",   1 ],
 "mt" => [ N_("_: keyboard\nMaltese (UK)"),   "uk",              "mt",    0 ],
 "mt_us" => [ N_("_: keyboard\nMaltese (US)"), "us",             "mt_us", 0 ],
 "nl" => [ N_("_: keyboard\nDutch"),          "nl-latin1",       "nl",    0 ],
 "no" => [ N_("_: keyboard\nNorwegian"),      "no-latin1",       "no",    0 ],
 "ori" => [ N_("_: keyboard\nOriya"),         "us",              "ori",   1 ],
 "pl" => [ N_("_: keyboard\nPolish (qwerty layout)"), "pl",      "pl",    0 ],
 "pl2" => [ N_("_: keyboard\nPolish (qwertz layout)"), "pl-latin2", "pl2", 0 ],
# TODO: console map
 "ps" => [ N_("_: keyboard\nPashto"),         "us",              "ps",    1 ],
 "pt" => [ N_("_: keyboard\nPortuguese"),     "pt-latin1",       "pt",    0 ],
# old XKB layout; change "ca_enhanced" -> "ca" once we ship new XKB
 "qc" => [ N_("_: keyboard\nCanadian (Quebec)"), "qc-latin1", "ca_enhanced", 0 ],
#- TODO: write a console kbd map for ro2
 "ro2" => [ N_("_: keyboard\nRomanian (qwertz)"), "ro2",         "ro",    0 ],
 "ro" => [ N_("_: keyboard\nRomanian (qwerty)"), "ro",           "ro(us_ro)", 0 ],
 "ru" => [ N_("_: keyboard\nRussian"),        "ru4",             "ru(winkeys)", 1 ],
 "ru_yawerty" => [ N_("_: keyboard\nRussian (phonetic)"), "ru-yawerty", "ru(phonetic)", 1 ],
 "sapmi" => [ N_("_: keyboard\nSaami (norwegian)"), "no-latin1",  "sapmi", 0 ],
 "sapmi_sefi" => [ N_("_: keyboard\nSaami (swedish/finnish)"), "se-latin1", "sapmi(sefi)", 0 ],
# TODO: console map
 "sd" => [ N_("_: keyboard\nSindhi"),         "us",              "sd",    1 ],
 "se" => [ N_("_: keyboard\nSwedish"),        "se-latin1",       "se",    0 ],
 "si" => [ N_("_: keyboard\nSlovenian"),      "slovene",         "si",    0 ],
# TODO: console map
 "sin" => [ N_("_: keyboard\nSinhala"),       "us",              "sin",   1 ],
 "sk" => [ N_("_: keyboard\nSlovakian (QWERTZ)"), "sk-qwertz",   "sk",    0 ],
 "sk_qwerty" => [ N_("_: keyboard\nSlovakian (QWERTY)"), "sk-qwerty", "sk_qwerty", 0 ],
# TODO: console map
 "sr" => [ N_("_: keyboard\nSerbian (cyrillic)"), "sr",          "yu,sr",    1 ],
 "syr" => [ N_("_: keyboard\nSyriac"),         "us",             "syr",  1 ],
 "syr_p" => [ N_("_: keyboard\nSyriac (phonetic)"), "us",        "syr_phonetic",  1 ],
 "tel" => [ N_("_: keyboard\nTelugu"),         "us",             "tel",  1 ],
# no console kbd that I'm aware of
 "tml" => [ N_("_: keyboard\nTamil (ISCII-layout)"), "us",       "tml(INSCRIPT)",   1 ],
 "tscii" => [ N_("_: keyboard\nTamil (Typewriter-layout)"), "us", "tml(UNI)", 1 ],
 "th" => [ N_("_: keyboard\nThai (Kedmanee)"), "th",             "th",    1 ],
 "th_tis" => [ N_("_: keyboard\nThai (TIS-820)"), "th",          "th_tis", 1 ],
# TODO: console map
 "th_pat" => [ N_("_: keyboard\nThai (Pattachote)"), "us",       "th_pat", 1 ],
# TODO: console map
# NOTE: we define a triple layout here
 "tifinagh" => [ N_("_: keyboard\nTifinagh (moroccan layout) (+latin/arabic)"), "fr", "fr,tifinagh,ar(azerty)", 1 ],
 "tifinagh_p" => [ N_("_: keyboard\nTifinagh (phonetic) (+latin/arabic)"), "fr", "fr,tifinagh(phonetic),ar(azerty)", 1 ],
# TODO: console map
 "tj" => [ N_("_: keyboard\nTajik"),         "ru4",             "tj",    1 ],
# TODO: console map
 "tk" => [ N_("_: keyboard\nTurkmen"),        "us",              "tk",    0 ],
 "tr_f" => [ N_("_: keyboard\nTurkish (traditional \"F\" model)"), "trf", "tr(tr_f)", 0 ],
 "tr_q" => [ N_("_: keyboard\nTurkish (modern \"Q\" model)"), "tr_q-latin5", "tr", 0 ],
#-"tw => [ N_("_: keyboard\nChineses bopomofo"), "tw",           "tw",    1 ],
 "ua" => [ N_("_: keyboard\nUkrainian"),      "ua",              "ua",    1 ],
 "uk" => [ N_("UK keyboard"),    "uk",              "gb",    0 ],
# TODO: console map
 "ur" => [ N_("_: keyboard\nUrdu keyboard"),  "us",              "ur",    1 ],
 "us" => [ N_("US keyboard"),    "us",              "en_US", 0 ],
 "us_intl" => [ N_("US keyboard (international)"), "us-intl", "us_intl", 0 ],
 "uz" => [ N_("_: keyboard\nUzbek (cyrillic)"), "uz.uni",         "uz",    1 ],
# old XKB layout
 "vn" => [ N_("_: keyboard\nVietnamese \"numeric row\" QWERTY"), "vn-tcvn", "vn(toggle)", 0 ], 
 "yu" => [ N_("_: keyboard\nYugoslavian (latin)"), "sr",         "yu",    0 ],
),
);

#- list of  possible choices for the key combinations to toggle XKB groups
#- (eg in X86Config file: XkbOptions "grp:toggle")
my %grp_toggles = (
    toggle => N_("Right Alt key"),
    shifts_toggle => N_("Both Shift keys simultaneously"),
    ctrl_shift_toggle => N_("Control and Shift keys simultaneously"),
    caps_toggle => N_("CapsLock key"),
    shift_caps_toggle => N_("Shift and CapsLock keys simultaneously"),
    ctrl_alt_toggle => N_("Ctrl and Alt keys simultaneously"),
    alt_shift_toggle => N_("Alt and Shift keys simultaneously"),
    menu_toggle => N_("\"Menu\" key"),
    lwin_toggle => N_("Left \"Windows\" key"),
    rwin_toggle => N_("Right \"Windows\" key"),
    ctrls_toggle => N_("Both Control keys simultaneously"),
    alts_toggle => N_("Both Alt keys simultaneously"),
    lshift_toggle => N_("Left Shift key"),
    rshift_toggle => N_("Right Shift key"),
    lalt_toggle => N_("Left Alt key"),
    lctrl_toggle => N_("Left Control key"),
    rctrl_toggle => N_("Right Control key"),
);


#-######################################################################################
#- Functions
#-######################################################################################
sub KEYBOARDs() { keys %keyboards }
sub KEYBOARD2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboards() { map { { KEYBOARD => $_ } } keys %keyboards }
sub keyboard2one {
    my ($keyboard, $nb) = @_;
    ref $keyboard or (detect_devices::is_xbox() ? return undef : internal_error());
    my $l = $keyboards{$keyboard->{KEYBOARD}} or return;
    $l->[$nb];
}
sub keyboard2text { keyboard2one($_[0], 0) }
sub keyboard2kmap { keyboard2one($_[0], 1) }
sub keyboard2xkb  { keyboard2one($_[0], 2) }

sub xkb_models() {
    my $models = parse_xkb_rules()->{model};
    [ map { $_->[0] } @$models ], { map { @$_ } @$models };
}

sub grp_toggles {
    my ($keyboard) = @_;
    keyboard2one($keyboard, 3) or return;
    \%grp_toggles;
}

sub group_toggle_choose {
    my ($in, $keyboard) = @_;

    if (my $grp_toggles = grp_toggles($keyboard)) {
	my $GRP_TOGGLE = $keyboard->{GRP_TOGGLE} || 'caps_toggle';
	$GRP_TOGGLE = $in->ask_from_listf('', N("Here you can choose the key or key combination that will 
allow switching between the different keyboard layouts
(eg: latin and non latin)"), sub { translate($grp_toggles->{$_[0]}) }, [ sort keys %$grp_toggles ], $GRP_TOGGLE) or return;

        $GRP_TOGGLE ne 'rctrl_toggle' and $in->ask_warn(N("Warning"), formatAlaTeX(
N("This setting will be activated after the installation.
During installation, you will need to use the Right Control
key to switch between the different keyboard layouts.")));
        log::l("GRP_TOGGLE: $GRP_TOGGLE");
        $keyboard->{GRP_TOGGLE} = $GRP_TOGGLE;
    } else {
        $keyboard->{GRP_TOGGLE} = '';
    }
    1;
}

sub loadkeys_files {
    my ($err) = @_;
    my $archkbd = arch() =~ /^sparc/ ? "sun" : arch() =~ /i.86/ ? "i386" : arch() =~ /ppc/ ? "mac" : arch();
    my $p = "/usr/lib/kbd/keymaps/$archkbd";
    my $post = ".kmap.gz";
    my %trans = ("cz-latin2" => "cz-lat2");
    my %find_file;
    foreach my $dir (all($p)) {
	$find_file{$dir} = '';
	foreach (all("$p/$dir")) {
	    $find_file{$_} and $err->("file $_ is both in $find_file{$_} and $dir") if $err;
	    $find_file{$_} = "$p/$dir/$_";
	}
    }
    my (@l, %l);
    foreach (values %keyboards) {
	local $_ = $trans{$_->[1]} || $_->[1];
	my $l = $find_file{"$_$post"} || $find_file{first(/(..)/) . $post};
	if ($l) {
	    push @l, $l;
	    foreach (`zgrep include $l | grep "^include"`) {
		/include\s+"(.*)"/ or die "bad line $_";
		@l{grep { -e $_ } ("$p/$1.inc.gz")} = ();
	    }
	} else {
	    $err->("invalid loadkeys keytable $_") if $err;
	}
    }
    uniq(@l, keys %l, grep { -e $_ } map { "$p/$_.inc.gz" } qw(compose euro windowkeys linux-keys-bare));
}

sub unpack_keyboards {
    my ($k) = @_; $k or return;
    [ grep { 
	my $b = $keyboards{$_->[0]};
	$b or log::l("bad keyboard $_->[0] in %keyboard::lang2keyboard");
	$b;
    } map { [ split ':' ] } split ' ', $k ];
}
sub lang2keyboards {
    my @li = sort { $b->[1] <=> $a->[1] } map { @$_ } map {
	my $h = lang::analyse_locale_name($_);
	#- example: pt_BR and pt
	my @l = (if_($h->{country}, $h->{main} . '_' . $h->{country}), $h->{main}, 'en');
	my $k = find { $_ } map { $lang2keyboard{$_} } @l;
	unpack_keyboards($k) || internal_error();
    } @_;
    \@li;
}
sub lang2keyboard {
    my ($l) = @_;

    my $kb = lang2keyboards($l)->[0][0];
    { KEYBOARD => $keyboards{$kb} ? $kb : 'us' }; #- handle incorrect keyboard mapping to us.
}

sub default {
    my ($o_locale) = @_;

    my $keyboard = from_usb() || lang2keyboard(($o_locale || lang::read())->{lang});
    add2hash($keyboard, from_DMI());
    $keyboard;
}

sub from_usb() {
    return if $::noauto;
    my ($usb_kbd) = detect_devices::usbKeyboards() or return;
    my $country_code = detect_devices::usbKeyboard2country_code($usb_kbd) or return;
    my $keyboard = $usb2keyboard[$country_code];
    $keyboard !~ /SKIP/ && { KEYBOARD => $keyboard };
}

sub from_DMI() {
    my $XkbModel = detect_devices::probe_unique_name('XkbModel');
    $XkbModel && { XkbModel => $XkbModel };
}

sub builtin_loadkeys {
    my ($keymap) = @_;
    return if $::testing;

    my ($magic, $tables_given, @tables) = common::unpack_with_refs('I' . 
								   'i' . c::MAX_NR_KEYMAPS() . 
								   's' . c::NR_KEYS() . '*',
								   $keymap);
    $magic != $KMAP_MAGIC and die "failed to read kmap magic";

    sysopen(my $F, "/dev/console", 2) or die "failed to open /dev/console: $!";

    my $i_tables = 0;
    each_index {
	my $table_index = $::i;
	if (!$_) {
	    #- deallocate table
	    ioctl($F, c::KDSKBENT(), pack("CCS", $table_index, 0, c::K_NOSUCHMAP())) or log::l("removing table $table_index failed: $!");
	} else {
	    each_index {
		ioctl($F, c::KDSKBENT(), pack("CCS", $table_index, $::i, $_)) or log::l("keymap ioctl failed ($table_index $::i $_): $!");
	    } @{$tables[$i_tables++]};
	}
    } @$tables_given;
}

sub parse_xkb_rules() {
    my $cat;
    my %l;
    my $lst_file = "$::prefix/usr/X11R6/lib/X11/xkb/rules/xorg.lst";
    foreach (cat_($lst_file)) {
	next if m!^\s*//! || m!^\s*$!;
	chomp;
	if (/^!\s*(\S+)$/) {
	    $cat = $1;
	} elsif (/^\s*(\w\S*)\s+(.*)/) {
	    push @{$l{$cat}}, [ $1, $2 ];
	} else {
	    log::l("parse_xkb_rules:$lst_file: bad line $_");
	}
    }
    \%l;
}

sub keyboard2full_xkb {
    my ($keyboard) = @_;

    my $Layout = keyboard2xkb($keyboard) or return { XkbDisable => '' };
    if ($keyboard->{GRP_TOGGLE} && $Layout !~ /,/) {
	$Layout = join(',', 'us', $Layout);
    }

    my $Model = $keyboard->{XkbModel} ||
      (arch() =~ /sparc/ ? 'sun' :
	$Layout eq 'jp' ? 'jp106' : 
	$Layout eq 'br' ? 'abnt2' : 'pc105');

    my $Options = join(',', 
	if_($keyboard->{GRP_TOGGLE}, "grp:$keyboard->{GRP_TOGGLE}", 'grp_led:scroll'),
	if_($keyboard->{GRP_TOGGLE} ne 'rwin_toggle', 'compose:rwin'), 
    );

    { XkbModel => $Model, XkbLayout => $Layout, XkbOptions => $Options };
}

sub xmodmap_file {
    my ($keyboard) = @_;
    my $f = "$ENV{SHARE_PATH}/xmodmap/xmodmap.$keyboard->{KEYBOARD}";
    -e $f && $f;
}

sub setxkbmap {
    my ($keyboard) = @_;
    my $xkb = keyboard2full_xkb($keyboard) or return;
    run_program::run('setxkbmap', '-option', '') if $xkb->{XkbOptions}; #- need re-initialised other toggles are cumulated
    run_program::run('setxkbmap', $xkb->{XkbLayout}, '-model' => $xkb->{XkbModel}, '-option' => $xkb->{XkbOptions} || '', '-compat' => $xkb->{XkbCompat} || '');
}

sub setup_install {
    my ($keyboard) = @_;

    return if arch() =~ /^sparc/;

    #- Xpmac does not map keys quite right
    if (arch() =~ /ppc/ && !$::testing && $ENV{DISPLAY}) {
	log::l("Fixing Mac keyboard");
	run_program::run('xmodmap', "-e",  "keycode 59 = BackSpace");
	run_program::run('xmodmap', "-e",  "keycode 131 = Shift_R");
	run_program::run('xmodmap', "-e",  "add shift = Shift_R");
	return;
    }

    my $kmap = keyboard2kmap($keyboard) or return;

    log::l("loading keymap $kmap");
    if (-e (my $f = "$ENV{SHARE_PATH}/keymaps/$kmap.bkmap")) {
	builtin_loadkeys(scalar cat_($f));
    } elsif (-x '/bin/loadkeys') {
	run_program::run('loadkeys', $kmap);
    } else {
	log::l("ERROR: can not load keymap");
    }

    if (-x "/usr/X11R6/bin/setxkbmap") {
	setxkbmap($keyboard);
    } else {
	my $f = xmodmap_file($keyboard);
	#- timeout is needed for drakx-in-chroot to kill xmodmap when it gets crazy with:
	#- please release the following keys within 2 seconds: Alt_L (keysym 0xffe9, keycode 64)
	eval { run_program::raw({ timeout => 3 }, 'xmodmap', $f) } if $f && !$::testing && $ENV{DISPLAY};
    }
}

sub write {
    my ($keyboard) = @_;
    log::l("keyboard::write $keyboard->{KEYBOARD}");

    $keyboard = { %$keyboard };
    delete $keyboard->{unsafe};
    $keyboard->{KEYTABLE} = keyboard2kmap($keyboard);

    setVarsInSh("$::prefix/etc/sysconfig/keyboard", $keyboard);
    if (arch() =~ /ppc/) {
	my $s = "dev.mac_hid.keyboard_sends_linux_keycodes = 1\n";
	substInFile { 
            $_ = '' if /^\Qdev.mac_hid.keyboard_sends_linux_keycodes/;
            $_ .= $s if eof;
        } "$::prefix/etc/sysctl.conf";
    } else {
	run_program::rooted($::prefix, 'dumpkeys', '>', '/etc/sysconfig/console/default.kmap') or log::l("dumpkeys failed");
    }
}

sub configure_xorg {
    my ($keyboard) = @_;

    require Xconfig::default;
    my $xfree_conf = Xconfig::xfree->read;
    if (!is_empty_array_ref($xfree_conf)) {
	Xconfig::default::config_keyboard($xfree_conf, $keyboard);
	$xfree_conf->write;
    }
}

sub read() {
    my %keyboard = getVarsFromSh("$::prefix/etc/sysconfig/keyboard") or return;
    if (!$keyboard{KEYBOARD}) {
	add2hash(\%keyboard, grep { keyboard2kmap($_) eq $keyboard{KEYTABLE} } keyboards());
    }
    keyboard2text(\%keyboard) ? \%keyboard : {};
}

sub check() {
    $^W = 0;

    my $not_ok = 0;
    my $warn = sub {
	print STDERR "$_[0]\n";
    };
    my $err = sub {
	&$warn;
	$not_ok = 1;
    };

    if (my @l = grep { is_empty_array_ref(lang2keyboards($_)) } lang::list_langs()) {
	$warn->("no keyboard for langs " . join(" ", @l));
    }
    foreach my $lang (lang::list_langs()) {
	my $l = lang2keyboards($lang);
	foreach (@$l) {
	    0 <= $_->[1] && $_->[1] <= 100 or $err->("invalid value $_->[1] in $lang2keyboard{$lang} for $lang in \%lang2keyboard keyboard.pm");
	    $keyboards{$_->[0]} or $err->("invalid keyboard $_->[0] in $lang2keyboard{$lang} for $lang in \%lang2keyboard keyboard.pm");
	}
    }
    /SKIP/ || $keyboards{$_} or $err->("invalid keyboard $_ in \@usb2keyboard keyboard.pm") foreach @usb2keyboard;
    $usb2keyboard[0x21] eq 'us_SKIP' or $err->('@usb2keyboard is badly modified, 0x21 is not us keyboard');

    my @xkb_groups = map { if_(/grp:(\S+)/, $1) } cat_('/usr/lib/X11/xkb/rules/xfree86.lst');
    $err->("invalid xkb group toggle '$_' in \%grp_toggles") foreach difference2([ keys %grp_toggles ], \@xkb_groups);
    $warn->("unused xkb group toggle '$_'") foreach grep { !/switch/ } difference2(\@xkb_groups, [ keys %grp_toggles ]);

    my @xkb_layouts = (#- (map { (split)[0] } grep { /^! layout/ .. /^\s*$/ } cat_('/usr/lib/X11/xkb/rules/xfree86.lst')),
		       all('/usr/lib/X11/xkb/symbols'),
		       (map { (split)[2] } cat_('/usr/lib/X11/xkb/symbols.dir')));
    $err->("invalid xkb layout $_") foreach difference2([ map { keyboard2xkb($_) } keyboards() ], \@xkb_layouts);

    my @kmaps_available = map { if_(m|.*/(.*)\.bkmap|, $1) } `tar tfj share/keymaps.tar.bz2`;
    my @kmaps_wanted = map { keyboard2kmap($_) } keyboards();
    $err->("missing KEYTABLE $_ (either share/keymaps.tar.bz2 need updating or $_ is bad)") foreach difference2(\@kmaps_wanted, \@kmaps_available);
    $err->("unused KEYTABLE $_ (update share/keymaps.tar.bz2 using share/keymaps_generate)") foreach difference2(\@kmaps_available, \@kmaps_wanted);

    loadkeys_files($err);

    exit($not_ok);
}

1;
