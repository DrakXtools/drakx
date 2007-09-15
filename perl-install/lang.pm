package lang; # $Id$

use diagnostics;
use strict;
use common;
use utf8;
use log;
use any;

#- key: lang name (locale name for some (~5) special cases needing
#-      extra distinctions)
#- [0]: lang name in english
#- [1]: transliterated locale name in the locale name (used for sorting)
#- [2]: default locale name to use for that language if there is not
#-      an existing locale for the combination language+country choosen
#- [3]: geographic groups that this language belongs to (for displaying
#-      in the menu grouped in smaller lists), 1=Europe, 2=Asia, 3=Africa,
#-      4=Oceania&Pacific, 5=America (if you wonder, it's the order
#-      used in the olympic flag)
#- [4]: special value for LANGUAGE variable (if different of the default
#-      of 'll_CC:ll_DD:ll' (ll_CC: locale (if exist) resulting of the
#-      combination of chosen lang (ll) and country (CC), ll_DD: the
#-      default locale shown here (field [2]) and ll: the language (the key))
our %langs = (
'af' =>    [ 'Afrikaans',           'Afrikaans',         'af_ZA', '  3  ', 'iso-8859-1' ],
'am' =>    [ 'Amharic',             'ZZ emarNa',         'am_ET', '  3  ', 'utf_ethi' ],
'ar' =>    [ 'Arabic',              'AA Arabic',         'ar_EG', ' 23  ', 'utf_ar' ],
'as' =>    [ 'Assamese',            'ZZ Assamese',       'as_IN', ' 2   ', 'utf_beng' ],
'az' =>    [ 'Azeri (Latin)',       'Azerbaycanca',      'az_AZ', ' 2   ', 'utf_az' ],
'be' =>    [ 'Belarussian',         'Belaruskaya',       'be_BY', '1    ', 'utf_cyr1' ],
'ber' =>   [ 'Berber',              'ZZ Tamazight',      'ber_MA', '  3  ', 'utf_tfng', 'ber_MA:ber:fr' ],
'bg' =>    [ 'Bulgarian',           'Blgarski',          'bg_BG', '1    ', 'cp1251' ],
'bn' =>    [ 'Bengali',             'ZZ Bengali',        'bn_BD', ' 2   ', 'utf_beng' ],
#- bo_CN not yet done, using dz_BT locale instead
'bo' =>    [ 'Tibetan',             'ZZ Bod skad',       'dz_BT', ' 2   ', 'utf_tibt', 'bo' ],
'br' =>    [ 'Breton',              'Brezhoneg',         'br_FR', '1    ', 'iso-8859-15', 'br:fr_FR:fr' ],
'bs' =>    [ 'Bosnian',             'Bosanski',          'bs_BA', '1    ', 'iso-8859-2' ],
'ca' =>    [ 'Catalan',             'Catala',            'ca_ES', '1    ', 'iso-8859-15', 'ca:es_ES:es' ],
'ca@valencian' =>  [ 'Catalan (Valencian)', 'Catala (Valencia)', 'ca_ES', '1    ', 'iso-8859-15', 'ca_ES@valencian:ca@valencian:ca:es_ES:es' ],
'cs' =>    [ 'Czech',               'Cestina',           'cs_CZ', '1    ', 'iso-8859-2' ],
'cy' =>    [ 'Welsh',               'Cymraeg',           'cy_GB', '1    ', 'utf_lat8',    'cy:en_GB:en' ],
'da' =>    [ 'Danish',              'Dansk',             'da_DK', '1    ', 'iso-8859-15' ],
'de' =>    [ 'German',              'Deutsch',           'de_DE', '1    ', 'iso-8859-15' ],
'dz' =>    [ 'Buthanese',           'ZZ Dzhonka',        'dz_BT', ' 2   ', 'utf_tibt' ],
'el' =>    [ 'Greek',               'Ellynika',          'el_GR', '1    ', 'iso-8859-7' ],
'en_AU' => [ 'English (Australia)', 'English (AU)',      'en_AU', '   4 ', 'iso-8859-1', 'en_AU:en_GB:en' ],
'en_CA' => [ 'English (Canada)',    'English (Canada)',  'en_CA', '    5', 'iso-8859-15', 'en_CA:en_GB:en' ],
'en_GB' => [ 'English',             'English',           'en_GB', '123 5', 'iso-8859-15' ],
'en_IE' => [ 'English (Ireland)',   'English (Ireland)', 'en_IE', '1    ', 'iso-8859-15', 'en_IE:en_GB:en' ],
'en_NZ' => [ 'English (New-Zealand)', 'English (NZ)',    'en_NZ', '   4 ', 'iso-8859-1', 'en_NZ:en_AU:en_GB:en' ],
'en_US' => [ 'English (American)', 'English (American)', 'en_US', '    5', 'C' ],
'eo' =>    [ 'Esperanto',           'Esperanto',         'eo_XX', '12345', 'unicode' ],
'es' =>    [ 'Spanish',             'Espanol',           'es_ES', '1 3 5', 'iso-8859-15' ],
'et' =>    [ 'Estonian',            'Eesti',             'et_EE', '1    ', 'iso-8859-15' ],
'eu' =>    [ 'Euskara (Basque)',    'Euskara',           'eu_ES', '1    ', 'utf_lat1' ],
'fa' =>    [ 'Farsi (Iranian)',     'AA Farsi',          'fa_IR', ' 2   ', 'utf_ar' ],
'fi' =>    [ 'Finnish (Suomi)',     'Suomi',             'fi_FI', '1    ', 'iso-8859-15' ],
#- 'tl' in priority position for now, as 'fil' is not much used.
#- Monolingual window managers will not see the menus otherwise
'fil' =>   [ 'Filipino',            'Filipino',          'fil_PH', ' 2   ', 'utf_lat1',  'tl:fil' ],
'fo' =>    [ 'Faroese',             'Foroyskt',          'fo_FO', '1    ', 'utf_lat1' ],
'fr' =>    [ 'French',              'Francais',          'fr_FR', '1 345', 'iso-8859-15' ],
'fur' =>   [ 'Furlan',              'Furlan',            'fur_IT', '1    ', 'utf_lat1', 'fur:it_IT:it' ],
'fy' =>    [ 'Frisian',             'Frysk',             'fy_NL', '1    ', 'utf_lat1' ],
'ga' =>    [ 'Gaelic (Irish)',      'Gaeilge',           'ga_IE', '1    ', 'utf_lat1', 'ga:en_IE:en_GB:en' ],
#'gd' =>   [ 'Gaelic (Scottish)',   'Gaidhlig',          'gd_GB', '1    ', 'utf_lat8',    'gd:en_GB:en' ],
'gl' =>    [ 'Galician',            'Galego',            'gl_ES', '1    ', 'iso-8859-15', 'gl:es_ES:es:pt:pt_BR' ],
#- gn_PY not yet done, using es_PY locale instead
'gn' =>    [ 'Guarani',             'Avane-e',           'es_PY', '    5', 'utf_lat1',    'gn:es_PY:es' ],
'gu' =>    [ 'Gujarati',            'ZZ Gujarati',       'gu_IN', ' 2   ', 'unicode' ],
#'gv' =>   [ 'Gaelic (Manx)',       'Gaelg',             'gv_GB', '1    ', 'utf_lat8',    'gv:en_GB:en' ],
'ha' =>    [ 'Hausa',               'Hausa',             'ha_NG', '  3  ', 'utf_yo', 'ha:en_NG' ],
'he' =>    [ 'Hebrew',              'AA Ivrit',          'he_IL', ' 2   ', 'utf_he' ],
'hi' =>    [ 'Hindi',               'ZZ Hindi',          'hi_IN', ' 2   ', 'utf_deva' ],
'hr' =>    [ 'Croatian',            'Hrvatski',          'hr_HR', '1    ', 'iso-8859-2' ],
'hu' =>    [ 'Hungarian',           'Magyar',            'hu_HU', '1    ', 'iso-8859-2' ],
'hy' =>    [ 'Armenian',            'ZZ Armenian',       'hy_AM', ' 2   ', 'utf_armn' ],
# locale not done yet
#'ia' =>   [ 'Interlingua',         'Interlingua',       'ia_XX', '1   5', 'utf_lat1' ],
'id' =>    [ 'Indonesian',          'Bahasa Indonesia',  'id_ID', ' 2   ', 'utf_lat1' ],
'ig' =>    [ 'Igbo',                'Igbo',              'ig_NG', '  3  ', 'utf_yo', 'ig:en_NG' ],
'is' =>    [ 'Icelandic',           'Islenska',          'is_IS', '1    ', 'iso-8859-15' ],
'it' =>    [ 'Italian',             'Italiano',          'it_IT', '1    ', 'iso-8859-15' ],
'iu' =>    [ 'Inuktitut',           'ZZ Inuktitut',      'iu_CA', '    5', 'utf_iu' ],
'ja' =>    [ 'Japanese',            'ZZ Nihongo',        'ja_JP', ' 2   ', 'jisx0208' ],
'ka' =>    [ 'Georgian',            'ZZ Georgian',       'ka_GE', ' 2   ', 'utf_geor' ],
'kk' =>    [ 'Kazakh',              'Kazak',             'kk_KZ', ' 2   ', 'utf_cyr2' ],
'kl' =>    [ 'Greenlandic (inuit)', 'Kalaallisut',       'kl_GL', '    5', 'utf_lat1' ],
'km' =>    [ 'Khmer',               'ZZ Khmer',          'km_KH', ' 2   ', 'utf_khmr' ],
'kn' =>    [ 'Kannada',             'ZZ Kannada',        'kn_IN', ' 2   ', 'utf_knda' ],
'ko' =>    [ 'Korean',              'ZZ Korea',          'ko_KR', ' 2   ', 'ksc5601' ],
'ku' =>    [ 'Kurdish',             'Kurdi',             'ku_TR', ' 2   ', 'utf_lat5' ],
#-'kw' =>  [ 'Cornish',             'Kernewek',          'kw_GB', '1    ', 'utf_lat8',    'kw:en_GB:en' ],
'ky' =>    [ 'Kyrgyz',              'Kyrgyz',            'ky_KG', ' 2   ', 'utf_cyr2' ],
#- lb_LU not yet done, using de_LU locale instead
'lb' =>    [ 'Luxembourgish',       'Letzebuergesch',    'de_LU', '1    ', 'utf_lat1', 'lb:de_LU' ],
'li' =>    [ 'Limbourgish',         'Limburgs',          'li_NL', '1    ', 'utf_lat1' ],
'lo' =>    [ 'Laotian',             'Laotian',           'lo_LA', ' 2   ', 'utf_laoo' ],
'lt' =>    [ 'Lithuanian',          'Lietuviskai',       'lt_LT', '1    ', 'iso-8859-13' ],
#- ltg_LV locale not done yet, using lv_LV for now
#- "ltg" is not a standard lang code, ISO-639 code was refused;
#- LTG_LV should be used instead (uppercase is for non-standard
#- langcodes, as defined by locale naming standard
'ltg' =>   [ 'Latgalian',           'Latgalisu',         'lv_LV', '1    ', 'utf_lat7', 'ltg:LTG:lv' ],
#'lu' =>    [ 'Luganda',             'Luganda',           'lg_UG', '  3  ', 'utf_lat1' ],
'lv' =>    [ 'Latvian',             'Latviesu',          'lv_LV', '1    ', 'iso-8859-13' ],
'mi' =>    [ 'Maori',               'Maori',             'mi_NZ', '   4 ', 'utf_lat7' ],
'mk' =>    [ 'Macedonian',          'Makedonski',        'mk_MK', '1    ', 'utf_cyr1' ],
'ml' =>    [ 'Malayalam',           'ZZ Malayalam',      'ml_IN', ' 2   ', 'utf_mlym' ],
'mn' =>    [ 'Mongolian',           'Mongol',            'mn_MN', ' 2   ', 'utf_cyr2' ],
'mr' =>    [ 'Marathi',             'ZZ Marathi',        'mr_IN', ' 2   ', 'utf_deva' ],
'ms' =>    [ 'Malay',               'Bahasa Melayu',     'ms_MY', ' 2   ', 'utf_lat1' ],
'mt' =>    [ 'Maltese',             'Maltin',            'mt_MT', '1 3  ', 'unicode' ],
#- "my_MM" not yet done, using "en_US" for now
'my' =>    [ 'Burmese',             'ZZ Bamaca',         'en_US', ' 2   ', 'utf_mymr', 'my_MM:my' ],
'nb' =>    [ 'Norwegian Bokmaal',   'Norsk, Bokmal',     'nb_NO', '1    ', 'iso-8859-15',  'nb:no' ],
'nds' =>   [ 'Low Saxon',           'Platduutsch',       'nds_DE', '1    ', 'utf_lat1', 'nds_DE:nds' ],
'ne' =>    [ 'Nepali',              'ZZ Nepali',         'ne_NP', ' 2   ', 'utf_deva' ],
'nl' =>    [ 'Dutch',               'Nederlands',        'nl_NL', '1    ', 'iso-8859-15' ],
'nn' =>    [ 'Norwegian Nynorsk',   'Norsk, Nynorsk',    'nn_NO', '1    ', 'iso-8859-15',  'nn:no@nynorsk:no_NY:no:nb' ],
'nr' =>    [ 'Ndebele',             'IsiNdebele',        'nr_ZA', '  3  ', 'utf_lat1', 'nr:en_ZA' ],
'nso' =>   [ 'Northern Sotho',      'Sesotho sa Leboa',  'nso_ZA', '  3  ', 'utf_lat1', 'st:nso:en_ZA' ],
'oc' =>    [ 'Occitan',             'Occitan',           'oc_FR', '1    ', 'utf_lat1',  'oc:fr_FR:fr' ],
'pa_IN' => [ 'Punjabi (gurmukhi)',  'ZZ Punjabi',        'pa_IN', ' 2   ', 'utf_guru' ],
'pl' =>    [ 'Polish',              'Polski',            'pl_PL', '1    ', 'iso-8859-2' ],
'pt' =>    [ 'Portuguese',          'Portugues',         'pt_PT', '1 3  ', 'iso-8859-15', 'pt_PT:pt:pt_BR' ],
'pt_BR' => [ 'Portuguese Brazil', 'Portugues do Brasil', 'pt_BR', '    5', 'iso-8859-1',  'pt_BR:pt_PT:pt' ],
#- qu_PE not yet done, using es_PE locale instead
'qu' =>    [ 'Quichua',             'Runa Simi',         'es_PE', '    5', 'utf_lat1', 'qu:es_PE:es' ],
'ro' =>    [ 'Romanian',            'Romana',            'ro_RO', '1    ', 'iso-8859-2' ],
'ru' =>    [ 'Russian',             'Russkij',           'ru_RU', '12   ', 'koi8-u' ],
'rw' =>    [ 'Kinyarwanda',         'Kinyarwanda',       'rw_RW', '  3  ', 'utf_lat1', 'rw' ],
'sc' =>    [ 'Sardinian',           'Sardu',             'sc_IT', '1    ', 'utf_lat1', 'sc:it_IT:it' ],
'se' =>    [ 'Saami',               'Samegiella',        'se_NO', '1    ', 'unicode' ], 
'sk' =>    [ 'Slovak',              'Slovencina',        'sk_SK', '1    ', 'iso-8859-2' ],
'sl' =>    [ 'Slovenian',           'Slovenscina',       'sl_SI', '1    ', 'iso-8859-2' ],
'so' =>    [ 'Somali',              'Soomaali',          'so_SO', '  3  ', 'utf_lat1' ], 
'sq' =>    [ 'Albanian',            'Shqip',             'sq_AL', '1    ', 'iso-8859-1' ], 
'sr' =>    [ 'Serbian Cyrillic',    'Srpska',            'sr_CS', '1    ', 'utf_cyr1', 'sp:sr' ],
#- "sh" comes first, because otherwise, due to the way glibc does language
#- fallback, if "sr@Latn" is not there but a "sr" (whichs uses cyrillic)
#- is there, "sh" will never be used.
'sr@Latn' => [ 'Serbian Latin',     'Srpska',            'sr_CS', '1    ', 'unicode',  'sh:sr@Latn' ], 
'ss' =>    [ 'Swati',               'SiSwati',           'ss_ZA', '  3  ', 'utf_lat1', 'ss:en_ZA' ],
'st' =>    [ 'Sotho',               'Sesotho',           'st_ZA', '  3  ', 'utf_lat1', 'st:nso:en_ZA' ],
'sv' =>    [ 'Swedish',             'Svenska',           'sv_SE', '1    ', 'iso-8859-15' ],
'ta' =>    [ 'Tamil',               'ZZ Tamil',          'ta_IN', ' 2   ', 'utf_taml' ],
'te' =>    [ 'Telugu',              'ZZ Telugu',         'te_IN', ' 2   ', 'unicode' ],
'tg' =>    [ 'Tajik',               'Tojiki',            'tg_TJ', ' 2   ', 'utf_cyr2' ],
'th' =>    [ 'Thai',                'ZZ Thai',           'th_TH', ' 2   ', 'tis620' ],
'tk' =>    [ 'Turkmen',             'Turkmence',         'tk_TM', ' 2   ', 'utf_az' ],
'tn' =>    [ 'Tswana',              'Setswana',          'tn_ZA', '  3  ', 'utf_lat1', 'tn:en_ZA' ],
'tr' =>    [ 'Turkish',             'Turkce',            'tr_TR', '12   ', 'iso-8859-9' ],
'ts' =>    [ 'Tsonga',              'Xitsonga',          'ts_ZA', '  3  ', 'utf_lat1', 'ts:en_ZA' ],
'tt' =>    [ 'Tatar',               'Tatarca',           'tt_RU', ' 2   ', 'utf_lat5' ],
'ug' =>    [ 'Uyghur',              'AA Uyghur',         'ug_CN', ' 2   ', 'utf_ar', 'ug' ],  
'uk' =>    [ 'Ukrainian',           'Ukrayinska',        'uk_UA', '1    ', 'koi8-u' ],
'ur' =>    [ 'Urdu',                'AA Urdu',           'ur_PK', ' 2   ', 'utf_ar' ],  
'uz@Latn' => [ 'Uzbek (latin)',     'Ozbekcha',          'uz_UZ', ' 2   ', 'utf_cyr2', 'uz@Latn:uz' ],
'uz' =>    [ 'Uzbek (cyrillic)',    'Ozbekcha',          'uz_UZ', ' 2   ', 'utf_cyr2', 'uz@Cyrl:uz' ],
've' =>    [ 'Venda',               'Tshivenda',         've_ZA', '  3  ', 'utf_lat1', 've:ven:en_ZA' ],
'vi' =>    [ 'Vietnamese',          'Tieng Viet',        'vi_VN', ' 2   ', 'utf_vi' ],
'wa' =>    [ 'Walon',               'Walon',             'wa_BE', '1    ', 'utf_lat1', 'wa:fr_BE:fr' ],
#- locale "wen_DE" not done yet, using "de_DE" instead
#- wen disabled until we have a perl-install/pixmaps/langs/lang-wen.png for it
#'wen' =>   [ 'Sorbian',             'Sorbian',           'de_DE', '1    ', 'utf_lat1', 'wen' ],
'xh' =>    [ 'Xhosa',               'IsiXhosa',          'xh_ZA', '  3  ', 'utf_lat1', 'xh:en_ZA' ],
'yi' =>    [ 'Yiddish',             'AA Yidish',         'yi_US', '1    ', 'utf_he' ],
'yo' =>    [ 'Yoruba',              'Yoruba',            'yo_NG', '  3  ', 'utf_yo', 'yo:en_NG' ],
'zh_CN' => [ 'Chinese Simplified',  'ZZ ZhongWen',       'zh_CN', ' 2   ', 'gb2312',      'zh_CN.GBK:zh_CN.GB2312:zh_CN:zh' ],
'zh_TW' => [ 'Chinese Traditional', 'ZZ ZhongWen',       'zh_TW', ' 2   ', 'Big5',        'zh_TW.Big5:zh_TW:zh_HK:zh' ],
'zu' =>    [ 'Zulu',                 'IsiZulu',          'zu_ZA', '  3  ', 'utf_lat1', 'xh:en_ZA' ],
);
sub l2name           { exists $langs{$_[0]} && $langs{$_[0]}[0] }
sub l2transliterated { exists $langs{$_[0]} && $langs{$_[0]}[1] }
sub l2locale         { exists $langs{$_[0]} && $langs{$_[0]}[2] }
sub l2location {
    my ($lang) = @_;
    my %geo = (1 => 'Europe', 2 => 'Asia', 3 => 'Africa', 4 => 'Oceania/Pacific', 5 => 'America');
    map { $geo{$_} } grep { $langs{$lang} && $langs{$lang}[3] =~ $_ } 1..5;
}
sub l2charset        { exists $langs{$_[0]} && $langs{$_[0]}[4] }
sub l2language       { exists $langs{$_[0]} && $langs{$_[0]}[5] }
sub list_langs {
    my (%options) = @_;
    my @l = keys %langs;
    $options{exclude_non_installed} ? grep { -e "/usr/share/locale/" . l2locale($_) . "/LC_CTYPE" } @l : @l;
}

sub text_direction_rtl() {
#-PO: the string "default:LTR" can be translated *ONLY* as "default:LTR"
#-PO: or as "default:RTL", depending if your language is written from
#-PO: left to right, or from right to left; any other string is wrong.
       	N("default:LTR") eq "default:RTL";
}


#- key: country name (that should be YY in xx_YY locale)
#- [0]: country name in natural language
#- [1]: default locale for that country 
#- [2]: geographic groups that this country belongs to (for displaying
#-      in the menu grouped in smaller lists), 1=Europe, 2=Asia, 3=Africa,
#-      4=Oceania&Pacific, 5=America (if you wonder, it's the order
#-      used in the olympic flag)
#-
#- Note: for countries for which a glibc locale do not exist (yet) I tried to
#- put a locale that makes sense; and a '#' at the end of the line to show
#- the locale is not the "correct" one. 'en_US' is used when no good choice
#- is available.
my %countries = (
'AD' => [ N_("Andorra"),        'ca_AD', '1' ],
'AE' => [ N_("United Arab Emirates"), 'ar_AE', '2' ],
'AF' => [ N_("Afghanistan"),    'en_US', '2' ], #
'AG' => [ N_("Antigua and Barbuda"), 'en_US', '5' ], #
'AI' => [ N_("Anguilla"),       'en_US', '5' ], #
'AL' => [ N_("Albania"),        'sq_AL', '1' ],
'AM' => [ N_("Armenia"),        'hy_AM', '2' ],
'AN' => [ N_("Netherlands Antilles"), 'en_US', '5' ], #
'AO' => [ N_("Angola"),         'pt_PT', '3' ], #
'AQ' => [ N_("Antarctica"),     'en_US', '4' ], #
'AR' => [ N_("Argentina"),      'es_AR', '5' ],
'AS' => [ N_("American Samoa"), 'en_US', '4' ], #
'AT' => [ N_("Austria"),        'de_AT', '1' ],
'AU' => [ N_("Australia"),      'en_AU', '4' ],
'AW' => [ N_("Aruba"),          'en_US', '5' ], #
'AZ' => [ N_("Azerbaijan"),     'az_AZ', '1' ],
'BA' => [ N_("Bosnia and Herzegovina"), 'bs_BA', '1' ],
'BB' => [ N_("Barbados"),       'en_US', '5' ], #
'BD' => [ N_("Bangladesh"),     'bn_BD', '2' ],
'BE' => [ N_("Belgium"),        'fr_BE', '1' ],
'BF' => [ N_("Burkina Faso"),   'en_US', '3' ], #
'BG' => [ N_("Bulgaria"),       'bg_BG', '1' ],
'BH' => [ N_("Bahrain"),        'ar_BH', '2' ],
'BI' => [ N_("Burundi"),        'en_US', '3' ], #
'BJ' => [ N_("Benin"),          'fr_FR', '3' ], #
'BM' => [ N_("Bermuda"),        'en_US', '5' ], #
'BN' => [ N_("Brunei Darussalam"), 'ar_EG', '2' ], #
'BO' => [ N_("Bolivia"),        'es_BO', '5' ],
'BR' => [ N_("Brazil"),         'pt_BR', '5' ],
'BS' => [ N_("Bahamas"),        'en_US', '5' ], #
'BT' => [ N_("Bhutan"),         'dz_BT', '2' ],
'BV' => [ N_("Bouvet Island"),  'en_US', '3' ], #
'BW' => [ N_("Botswana"),       'en_BW', '3' ],
'BY' => [ N_("Belarus"),        'be_BY', '1' ],
'BZ' => [ N_("Belize"),         'en_US', '5' ], #
'CA' => [ N_("Canada"),         'en_CA', '5' ],
'CC' => [ N_("Cocos (Keeling) Islands"), 'en_US', '4' ], #
'CD' => [ N_("Congo (Kinshasa)"), 'fr_FR', '3' ], #
'CF' => [ N_("Central African Republic"), 'fr_FR', '3' ], #
'CG' => [ N_("Congo (Brazzaville)"), 'fr_FR', '3' ], #
'CH' => [ N_("Switzerland"),    'de_CH', '1' ],
'CI' => [ N_("Cote d'Ivoire"),  'fr_FR', '3' ], #
'CK' => [ N_("Cook Islands"),   'en_US', '4' ], #
'CL' => [ N_("Chile"),          'es_CL', '5' ],
'CM' => [ N_("Cameroon"),       'fr_FR', '3' ], #
'CN' => [ N_("China"),          'zh_CN', '2' ],
'CO' => [ N_("Colombia"),       'es_CO', '5' ],
'CR' => [ N_("Costa Rica"),     'es_CR', '5' ],
'CS' => [ N_("Serbia & Montenegro"), 'sr_CS', '1' ],
'CU' => [ N_("Cuba"),           'es_DO', '5' ], #
'CV' => [ N_("Cape Verde"),     'pt_PT', '3' ], #
'CX' => [ N_("Christmas Island"), 'en_US', '4' ], #
'CY' => [ N_("Cyprus"),         'el_CY', '1' ],
'CZ' => [ N_("Czech Republic"), 'cs_CZ', '2' ],
'DE' => [ N_("Germany"),        'de_DE', '1' ],
'DJ' => [ N_("Djibouti"),       'en_US', '3' ], #
'DK' => [ N_("Denmark"),        'da_DK', '1' ],
'DM' => [ N_("Dominica"),       'en_US', '5' ], #
'DO' => [ N_("Dominican Republic"), 'es_DO', '5' ],
'DZ' => [ N_("Algeria"),        'ar_DZ', '3' ],
'EC' => [ N_("Ecuador"),        'es_EC', '5' ],
'EE' => [ N_("Estonia"),        'et_EE', '1' ],
'EG' => [ N_("Egypt"),          'ar_EG', '3' ],
'EH' => [ N_("Western Sahara"), 'ar_MA', '3' ], #
'ER' => [ N_("Eritrea"),        'ti_ER', '3' ],
'ES' => [ N_("Spain"),          'es_ES', '1' ],
'ET' => [ N_("Ethiopia"),       'am_ET', '3' ],
'FI' => [ N_("Finland"),        'fi_FI', '1' ],
'FJ' => [ N_("Fiji"),           'en_US', '4' ], #
'FK' => [ N_("Falkland Islands (Malvinas)"), 'en_GB', '5' ], #
'FM' => [ N_("Micronesia"),     'en_US', '4' ], #
'FO' => [ N_("Faroe Islands"),  'fo_FO', '1' ],
'FR' => [ N_("France"),         'fr_FR', '1' ],
'GA' => [ N_("Gabon"),          'fr_FR', '3' ], #
'GB' => [ N_("United Kingdom"), 'en_GB', '1' ],
'GD' => [ N_("Grenada"),        'en_US', '5' ], #
'GE' => [ N_("Georgia"),        'ka_GE', '2' ],
'GF' => [ N_("French Guiana"),  'fr_FR', '5' ], #
'GH' => [ N_("Ghana"),          'en_GB', '3' ], #
'GI' => [ N_("Gibraltar"),      'en_GB', '1' ], #
'GL' => [ N_("Greenland"),      'kl_GL', '5' ],
'GM' => [ N_("Gambia"),         'en_US', '3' ], #
'GN' => [ N_("Guinea"),         'en_US', '3' ], #
'GP' => [ N_("Guadeloupe"),     'fr_FR', '5' ], #
'GQ' => [ N_("Equatorial Guinea"), 'en_US', '3' ], #
'GR' => [ N_("Greece"),         'el_GR', '1' ],
'GS' => [ N_("South Georgia and the South Sandwich Islands"), 'en_US', '4' ], #
'GT' => [ N_("Guatemala"),      'es_GT', '5' ],
'GU' => [ N_("Guam"),           'en_US', '4' ], #
'GW' => [ N_("Guinea-Bissau"),  'pt_PT', '3' ], #
'GY' => [ N_("Guyana"),         'en_US', '5' ], #
'HK' => [ N_("Hong Kong SAR (China)"),      'zh_HK', '2' ],
'HM' => [ N_("Heard and McDonald Islands"), 'en_US', '4' ], #
'HN' => [ N_("Honduras"),       'es_HN', '5' ],
'HR' => [ N_("Croatia"),        'hr_HR', '1' ],
'HT' => [ N_("Haiti"),          'fr_FR', '5' ], #
'HU' => [ N_("Hungary"),        'hu_HU', '1' ],
'ID' => [ N_("Indonesia"),      'id_ID', '2' ],
'IE' => [ N_("Ireland"),        'en_IE', '1' ],
'IL' => [ N_("Israel"),         'he_IL', '2' ],
'IN' => [ N_("India"),          'hi_IN', '2' ],
'IO' => [ N_("British Indian Ocean Territory"), 'en_GB', '2' ], #
'IQ' => [ N_("Iraq"),           'ar_IQ', '2' ],
'IR' => [ N_("Iran"),           'fa_IR', '2' ],
'IS' => [ N_("Iceland"),        'is_IS', '1' ],
'IT' => [ N_("Italy"),          'it_IT', '1' ],
'JM' => [ N_("Jamaica"),        'en_US', '5' ], #
'JO' => [ N_("Jordan"),         'ar_JO', '2' ],
'JP' => [ N_("Japan"),          'ja_JP', '2' ],
'KE' => [ N_("Kenya"),          'en_ZW', '3' ], #
'KG' => [ N_("Kyrgyzstan"),     'ky_KG', '2' ],
'KH' => [ N_("Cambodia"),       'km_KH', '2' ],
'KI' => [ N_("Kiribati"),       'en_US', '3' ], #
'KM' => [ N_("Comoros"),        'en_US', '2' ], #
'KN' => [ N_("Saint Kitts and Nevis"), 'en_US', '5' ], #
'KP' => [ N_("Korea (North)"),  'ko_KR', '2' ], #
'KR' => [ N_("Korea"),          'ko_KR', '2' ],
'KW' => [ N_("Kuwait"),         'ar_KW', '2' ],
'KY' => [ N_("Cayman Islands"), 'en_US', '5' ], #
'KZ' => [ N_("Kazakhstan"),     'kk_KZ', '2' ],
'LA' => [ N_("Laos"),           'lo_LA', '2' ],
'LB' => [ N_("Lebanon"),        'ar_LB', '2' ],
'LC' => [ N_("Saint Lucia"),    'en_US', '5' ], #
'LI' => [ N_("Liechtenstein"),  'de_CH', '1' ], #
'LK' => [ N_("Sri Lanka"),      'si_LK', '2' ],
'LR' => [ N_("Liberia"),        'en_US', '3' ], #
'LS' => [ N_("Lesotho"),        'en_BW', '3' ], #
'LT' => [ N_("Lithuania"),      'lt_LT', '1' ],
'LU' => [ N_("Luxembourg"),     'de_LU', '1' ], # lb_LU
'LV' => [ N_("Latvia"),         'lv_LV', '1' ],
'LY' => [ N_("Libya"),          'ar_LY', '3' ],
'MA' => [ N_("Morocco"),        'ar_MA', '3' ],
'MC' => [ N_("Monaco"),         'fr_FR', '1' ], #
'MD' => [ N_("Moldova"),        'ro_RO', '1' ], #
'MG' => [ N_("Madagascar"),     'mg_MG', '3' ],
'MH' => [ N_("Marshall Islands"), 'en_US', '4' ], #
'MK' => [ N_("Macedonia"),      'mk_MK', '1' ],
'ML' => [ N_("Mali"),           'en_US', '3' ], #
'MM' => [ N_("Myanmar"),        'en_US', '2' ], # my_MM
'MN' => [ N_("Mongolia"),       'mn_MN', '2' ],
'MP' => [ N_("Northern Mariana Islands"), 'en_US', '2' ], #
'MQ' => [ N_("Martinique"),     'fr_FR', '5' ], #
'MR' => [ N_("Mauritania"),     'en_US', '3' ], #
'MS' => [ N_("Montserrat"),     'en_US', '5' ], #
'MT' => [ N_("Malta"),          'mt_MT', '1' ],
'MU' => [ N_("Mauritius"),      'en_US', '3' ], #
'MV' => [ N_("Maldives"),       'en_US', '4' ], #
'MW' => [ N_("Malawi"),         'en_US', '3' ], #
'MX' => [ N_("Mexico"),         'es_MX', '5' ],
'MY' => [ N_("Malaysia"),       'ms_MY', '2' ],
'MZ' => [ N_("Mozambique"),     'pt_PT', '3' ], #
'NA' => [ N_("Namibia"),        'en_US', '3' ], #
'NC' => [ N_("New Caledonia"),  'fr_FR', '4' ], #
'NE' => [ N_("Niger"),          'en_US', '3' ], #
'NF' => [ N_("Norfolk Island"), 'en_GB', '4' ], #
'NG' => [ N_("Nigeria"),        'en_NG', '3' ],
'NI' => [ N_("Nicaragua"),      'es_NI', '5' ],
'NL' => [ N_("Netherlands"),    'nl_NL', '1' ],
'NO' => [ N_("Norway"),         'nb_NO', '1' ],
'NP' => [ N_("Nepal"),          'ne_NP', '2' ],
'NR' => [ N_("Nauru"),          'en_US', '4' ], #
'NU' => [ N_("Niue"),           'en_US', '4' ], #
'NZ' => [ N_("New Zealand"),    'en_NZ', '4' ],
'OM' => [ N_("Oman"),           'ar_OM', '2' ],
'PA' => [ N_("Panama"),         'es_PA', '5' ],
'PE' => [ N_("Peru"),           'es_PE', '5' ],
'PF' => [ N_("French Polynesia"), 'fr_FR', '4' ], #
'PG' => [ N_("Papua New Guinea"), 'en_NZ', '4' ], #
'PH' => [ N_("Philippines"),    'fil_PH', '2' ],
'PK' => [ N_("Pakistan"),       'ur_PK', '2' ],
'PL' => [ N_("Poland"),         'pl_PL', '1' ],
'PM' => [ N_("Saint Pierre and Miquelon"), 'fr_CA', '5' ], #
'PN' => [ N_("Pitcairn"),      'en_US', '4' ], #
'PR' => [ N_("Puerto Rico"),    'es_PR', '5' ],
'PS' => [ N_("Palestine"),      'ar_JO', '2' ], #
'PT' => [ N_("Portugal"),       'pt_PT', '1' ],
'PY' => [ N_("Paraguay"),       'es_PY', '5' ],
'PW' => [ N_("Palau"),          'en_US', '2' ], #
'QA' => [ N_("Qatar"),          'ar_QA', '2' ],
'RE' => [ N_("Reunion"),        'fr_FR', '2' ], #
'RO' => [ N_("Romania"),        'ro_RO', '1' ],
'RU' => [ N_("Russia"),         'ru_RU', '1' ],
'RW' => [ N_("Rwanda"),         'rw_RW', '3' ],
'SA' => [ N_("Saudi Arabia"),   'ar_SA', '2' ],
'SB' => [ N_("Solomon Islands"), 'en_US', '4' ], #
'SC' => [ N_("Seychelles"),     'en_US', '4' ], #
'SD' => [ N_("Sudan"),          'ar_SD', '5' ],
'SE' => [ N_("Sweden"),         'sv_SE', '1' ],
'SG' => [ N_("Singapore"),      'en_SG', '2' ],
'SH' => [ N_("Saint Helena"),   'en_GB', '5' ], #
'SI' => [ N_("Slovenia"),       'sl_SI', '1' ],
'SJ' => [ N_("Svalbard and Jan Mayen Islands"), 'en_US', '1' ], #
'SK' => [ N_("Slovakia"),       'sk_SK', '1' ],
'SL' => [ N_("Sierra Leone"),   'en_US', '3' ], #
'SM' => [ N_("San Marino"),     'it_IT', '1' ], #
'SN' => [ N_("Senegal"),        'fr_FR', '3' ], #
'SO' => [ N_("Somalia"),        'so_SO', '3' ],
'SR' => [ N_("Suriname"),       'nl_NL', '5' ], #
'ST' => [ N_("Sao Tome and Principe"), 'en_US', '5' ], #
'SV' => [ N_("El Salvador"),    'es_SV', '5' ],
'SY' => [ N_("Syria"),          'ar_SY', '2' ],
'SZ' => [ N_("Swaziland"),      'en_BW', '3' ], #
'TC' => [ N_("Turks and Caicos Islands"), 'en_US', '5' ], #
'TD' => [ N_("Chad"),           'en_US', '3' ], #
'TF' => [ N_("French Southern Territories"), 'fr_FR', '4' ], #
'TG' => [ N_("Togo"),           'fr_FR', '3' ], #
'TH' => [ N_("Thailand"),       'th_TH', '2' ],
'TJ' => [ N_("Tajikistan"),     'tg_TJ', '2' ],
'TK' => [ N_("Tokelau"),        'en_US', '4' ], #
'TL' => [ N_("East Timor"),     'pt_PT', '4' ], #
'TM' => [ N_("Turkmenistan"),   'tk_TM', '2' ],
'TN' => [ N_("Tunisia"),        'ar_TN', '5' ],
'TO' => [ N_("Tonga"),          'en_US', '3' ], #
'TR' => [ N_("Turkey"),         'tr_TR', '2' ],
'TT' => [ N_("Trinidad and Tobago"), 'en_US', '5' ], #
'TV' => [ N_("Tuvalu"),         'en_US', '4' ], #
'TW' => [ N_("Taiwan"),         'zh_TW', '2' ],
'TZ' => [ N_("Tanzania"),       'en_US', '3' ], #
'UA' => [ N_("Ukraine"),        'uk_UA', '1' ],
'UG' => [ N_("Uganda"),         'lg_UG', '3' ],
'UM' => [ N_("United States Minor Outlying Islands"), 'en_US', '5' ], #
'US' => [ N_("United States"),  'en_US', '5' ],
'UY' => [ N_("Uruguay"),        'es_UY', '5' ],
'UZ' => [ N_("Uzbekistan"),     'uz_UZ', '2' ],
'VA' => [ N_("Vatican"),        'it_IT', '1' ], #
'VC' => [ N_("Saint Vincent and the Grenadines"), 'en_US', '5' ], 
'VE' => [ N_("Venezuela"),      'es_VE', '5' ],
'VG' => [ N_("Virgin Islands (British)"), 'en_GB', '5' ], #
'VI' => [ N_("Virgin Islands (U.S.)"), 'en_US', '5' ], #
'VN' => [ N_("Vietnam"),        'vi_VN', '2' ],
'VU' => [ N_("Vanuatu"),        'en_US', '4' ], #
'WF' => [ N_("Wallis and Futuna"), 'fr_FR', '4' ], #
'WS' => [ N_("Samoa"),          'en_US', '4' ], #
'YE' => [ N_("Yemen"),          'ar_YE', '2' ],
'YT' => [ N_("Mayotte"),        'fr_FR', '3' ], #
'ZA' => [ N_("South Africa"),   'en_ZA', '5' ],
'ZM' => [ N_("Zambia"),         'en_US', '3' ], #
'ZW' => [ N_("Zimbabwe"),       'en_ZW', '5' ],
);
sub c2name   { exists $countries{$_[0]} && translate($countries{$_[0]}[0]) }
sub c2locale { exists $countries{$_[0]} && $countries{$_[0]}[1] }
sub list_countries {
    my (%options) = @_;
    my @l = keys %countries;
    $options{exclude_non_installed} ? grep { -e "/usr/share/locale/" . c2locale($_) . "/LC_CTYPE" } @l : @l;
}

#- this list is built with the following command on the compile cluster:
#- rpm -qpl /cooker/RPMS/locales-* | grep LC_CTYPE | grep '\.UTF-8' | cut -d'/' -f5 | sed 's/.UTF-8//' | sort | tr '\n' ' ' ; echo
our @locales = qw(aa_DJ aa_ER aa_ER@saaho aa_ET af_ZA am_ET an_ES ar_AE ar_BH ar_DZ ar_EG ar_IN ar_IQ ar_JO ar_KW ar_LB ar_LY ar_MA ar_OM ar_QA ar_SA ar_SD ar_SY ar_TN ar_YE as_IN az_AZ be_BY ber_DZ ber_MA bg_BG bn_BD bn_IN br_FR bs_BA byn_ER ca_AD ca_ES ca_FR ca_IT cs_CZ cy_GB da_DK de_AT de_BE de_CH de_DE de_LU dz_BT el_CY el_GR en_AU en_BE en_BW en_CA en_DK en_GB en_HK en_IE en_IN en_NG en_NZ en_PH en_SG en_US en_ZA en_ZW eo_XX es_AR es_BO es_CL es_CO es_CR es_DO es_EC es_ES es_GT es_HN es_MX es_NI es_PA es_PE es_PR es_PY es_SV es_US es_UY es_VE et_EE eu_ES fa_IR fi_FI fil_PH fo_FO fr_BE fr_CA fr_CH fr_FR fr_LU fur_IT fy_DE fy_NL ga_IE gd_GB gez_ER gez_ER@abegede gez_ET gez_ET@abegede gl_ES gu_IN gv_GB ha_NG he_IL hi_IN hr_HR hsb_DE hu_HU hy_AM id_ID ig_NG ik_CA is_IS it_CH it_IT iu_CA ja_JP ka_GE kk_KZ kl_GL km_KH kn_IN ko_KR ku_TR kw_GB ky_KG lg_UG li_BE li_NL lo_LA lt_LT lv_LV mg_MG mi_NZ mk_MK ml_IN mn_MN mr_IN ms_MY mt_MT nb_NO nds_DE nds_DE@traditional nds_NL ne_NP nl_BE nl_NL nn_NO no_NO nr_ZA nso_ZA oc_FR om_ET om_KE pa_IN pa_PK ph_PH pl_PL pt_BR pt_PT ro_RO ru_RU ru_UA rw_RW sc_IT se_NO sh_YU sid_ET si_LK sk_SK sl_SI so_DJ so_ET so_KE so_SO sq_AL sr_CS sr_CS@Latn sr_YU sr_YU@Latn ss_ZA st_ZA sv_FI sv_SE sw_XX ta_IN te_IN tg_TJ th_TH ti_ER ti_ET tig_ER tk_TM tl_PH tn_ZA tr_CY tr_TR ts_ZA tt_RU ug_CN uk_UA ur_PK uz_UZ uz_UZ@Cyrl uz_UZ@Latn ve_ZA vi_VN wa_BE wal_ET xh_ZA yi_US yo_NG zh_CN zh_HK zh_SG zh_TW zu_ZA);
	
sub standard_locale {
    my ($lang, $country, $prefer_lang) = @_;
    member("${lang}_${country}", @locales) and return "${lang}_${country}";
    $prefer_lang && member($lang, @locales) and return $lang;
    my $main_locale = locale_to_main_locale($lang);
    if ($main_locale ne $lang) {
	standard_locale($main_locale, $country, $prefer_lang);
    }
    '';
}

sub fix_variant {
    my ($locale) = @_;
    #- uz@Cyrl_UZ -> uz_UZ@Cyrl
    $locale =~ s/(.*)(\@\w+)(_.*)/$1$3$2/;
    $locale;
}

sub analyse_locale_name {
    my ($locale) = @_;
    $locale =~ /^(.*?) (?:_(.*?))? (?:\.(.*?))? (?:\@(.*?))? $/x &&
      { main => $1, country => $2, charset => $3, variant => $4 };
}

sub locale_to_main_locale {
    my ($locale) = @_;
    lc(analyse_locale_name($locale)->{main});
}

sub getlocale_for_lang {
    my ($lang, $country, $o_utf8) = @_;
    fix_variant((standard_locale($lang, $country, 'prefer_lang') || l2locale($lang)) . ($o_utf8 ? '.UTF-8' : ''));
}

sub getlocale_for_country {
    my ($lang, $country, $o_utf8) = @_;
    fix_variant((standard_locale($lang, $country, '') || c2locale($country)) . ($o_utf8 ? '.UTF-8' : ''));
}

sub getLANGUAGE {
    my ($lang, $o_country, $o_utf8) = @_;
    l2language($lang) || join(':', uniq(getlocale_for_lang($lang, $o_country, $o_utf8), 
					$lang, 
					locale_to_main_locale($lang)));
}

#-------------------------------------------------------------
#
# IM configuration hash tables
#
# in order to configure an IM, one has to:
# - put generic configuration in %IM_config


# This set generic IM fields.
my @IM_i18n_fields = (
 'XMODIFIERS', 
#-      is the environnement variable used by the X11 XIM protocol
#-	it is of the form XIMODIFIERS="@im=foo"
 'XIM', 
#-      is used by some programs, it usually is the like XIMODIFIERS
#-	with the "@im=" part stripped
 'GTK_IM_MODULE', 
#-      the module to use for Gtk programs ("xim" to use an X11
#-	XIM server; or a a native gtk module if exists)
 'XIM_PROGRAM',
#-      the XIM program to run (usually the same as XIM value, but
#-	in some cases different, particularly if parameters are needed;
 'QT_IM_MODULE',
#-     the module to use for Qt programs ("xim" to use an X11
#-     XIM server; or a Qt plugin if exists)
);

my @sessions = any::sessions();
my $is_kde = member('KDE', @sessions);
my $is_gtk = any { !/KDE/i } @sessions;

sub packages_if_desktop {
    my ($packages, $cdt, $extra_pkg) = @_;
    join(' ', $packages, if_($cdt, $extra_pkg));
}

# keep the 'packages' field in sync with share/rpmsrate:
my %IM_config =
  (
   ami => {
           XIM => 'Ami',
           #- NOTE: there are several possible versions of ami, for the different
           #- desktops (kde, gnome, etc). So XIM_PROGRAM is not defined; it will
           #- be the xinitrc script, XIM section, that will choose the right one 
           #- XIM_PROGRAM => 'ami',
           XMODIFIERS => '@im=Ami',
           GTK_IM_MODULE => 'xim',
           QT_IM_MODULE => 'xim',
          },
   chinput => {
               GTK_IM_MODULE => 'xim',
               QT_IM_MODULE => 'xim',
               XIM => 'chinput',
               XMODIFIERS => '@im=Chinput',
	       XIM_PROGRAM => {
		   'zh_CN' => 'chinput -gb',
		   'en_SG' => 'chinput -gb',
		   'zh_HK' => 'chinput -big5',
		   'zh_TW' => 'chinput -big5',
	       },	       
	       packages => { generic => 'miniChinput' },
              },
   fcitx => {
             GTK_IM_MODULE => 'xim',
             QT_IM_MODULE => 'xim',
             XIM => 'fcitx',
             XIM_PROGRAM => 'fcitx',
             XMODIFIERS => '@im=fcitx',
            },
   gcin => {
             GTK_IM_MODULE => 'gcin',
             QT_IM_MODULE => 'gcin',
             XIM => 'gcin',
             XIM_PROGRAM => 'gcin',
             XMODIFIERS => '@im=gcin',
            },
   'im-ja' => {
               GTK_IM_MODULE => 'im-ja',
               QT_IM_MODULE => 'xim',
               XIM => 'im-ja-xim-server',
               XIM_PROGRAM => 'im-ja-xim-server',
               XMODIFIERS => '@im=im-ja-xim-server',
              },

   kinput2 => {   
               GTK_IM_MODULE => 'xim',
               QT_IM_MODULE => 'xim',
               XIM => 'kinput2',
               XIM_PROGRAM => 'kinput2',
               XMODIFIERS => '@im=kinput2',
	       packages => { generic => 'kinput2-wnn' },
              },
   nabi => {
            GTK_IM_MODULE => 'xim',
            QT_IM_MODULE => 'xim',
            XIM => 'nabi',
            XIM_PROGRAM => 'nabi',
            XMODIFIERS => '@im=nabi',
           },

   oxim => {
       GTK_IM_MODULE => 'oxim',
       QT_IM_MODULE => 'oxim',
       XIM => 'oxim',
       XIM_PROGRAM => 'oxim',
       XMODIFIERS => '@im=oxim', # '@im=SCIM' is broken for now
       packages => { generic => 'oxim' },
   },
   'scim+(default)' => {
            GTK_IM_MODULE => 'scim',
            QT_IM_MODULE => 'scim',
            XIM_PROGRAM => 'scim -d',
            XMODIFIERS => '@im=SCIM',
	    default_for_lang => 'am ja ko vi zh_CN zh_TW',
	    packages => {
		generic => 'scim scim-m17n scim-tables',
		am => 'scim scim-tables ',
		ja => 'scim-anthy scim-input-pad scim-tomoe',
		ko => 'scim-hangul',
          vi => 'scim-m17n',
		zh => 'scim-pinyin scim-tables scim-chewing',
	    },
           },

   (map {
       ("scim+$_" => {
            GTK_IM_MODULE => 'scim',
	    QT_IM_MODULE => 'scim',
            XIM_PROGRAM => 'scim -d',
            XMODIFIERS => '@im=SCIM',
	    packages => { generic => "scim-$_" },
       });
   } qw(anthy canna ccinput fcitx m17n prime pinyin skk uim)), # enable to select extra SCIM combinations

   'scim-bridge' => {
       GTK_IM_MODULE => 'scim-bridge',
       QT_IM_MODULE => 'scim-bridge',
       XIM_PROGRAM => 'scim -d',
       XMODIFIERS => '@im=SCIM',
       default_for_lang => 'am ja ko vi zh_CN zh_TW',
       packages => {
           generic => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-m17n scim-tables'),
           am => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-tables'),
           ja => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-anthy scim-input-pad scim-tomoe'),
           ko => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-hangul'),
           vi => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-m17n'),
           zh => join(' ', if_($is_kde, 'scim-bridge-qt3'), ' scim-pinyin scim-tables scim-chewing'),
       },
   },
   skim => {
            GTK_IM_MODULE => 'scim',
            QT_IM_MODULE => 'scim',
            XIM_PROGRAM => 'skim -d',
            XMODIFIERS => '@im=SCIM',
           },
   uim => {
           GTK_IM_MODULE => 'uim',
           QT_IM_MODULE => 'uim',
           XIM => 'uim',
           XIM_PROGRAM => 'uim-xim',
           XMODIFIERS => '@im=uim',
	   packages => { generic => 'uim-gtk uim' },
          },
   xcin => {
            XIM => 'xcin',
            XIM_PROGRAM => 'xcin',
            XMODIFIERS => '@im=xcin-zh_TW',
            GTK_IM_MODULE => 'xim',
            QT_IM_MODULE => 'xim',
           },
   'x-unikey' => {
                  GTK_IM_MODULE => 'xim',
                  QT_IM_MODULE => 'xim',
                  XMODIFIERS => '@im=unikey',
                 },
);

sub get_ims() { keys %IM_config }
           


#-------------------------------------------------------------
#
# Locale configuration regarding encoding/IM

#- ENC is used by some versions or rxvt
my %locale2ENC = (
                       'ja' => 'eucj',
                       'ko' => 'kr',
                       'zh_CN' => 'gb',
                       # zh_SG zh_HK were reported as missing by make check:
                       'zh_HK' => 'big5',
                       'zh_SG' => 'gb',
                       'zh_TW' => 'big5',
                      );

my %IM_locale_specific_config = (
           #-XFree86 has an internal XIM for Thai that enables syntax checking etc.
           #-'Passthroug' is no check at all, 'BasicCheck' accepts bad sequences
           #-and convert them to right ones, 'Strict' refuses bad sequences
           'th' => {
                       XIM_PROGRAM => '/bin/true', #- it's an internal module
                       XMODIFIERS => '"@im=BasicCheck"',
                      },
          );


sub get_default_im {
    my ($lang) = @_;
    find { 
	member($lang, split(' ', $IM_config{$_}{default_for_lang}));
    } keys %IM_config;
}

sub IM2packages {
    my ($locale) = @_;
    if ($locale->{IM}) {
	my $per_lang = $IM_config{$locale->{IM}}{packages} || {};
	my $lang = analyse_locale_name($locale->{lang})->{main};
	split(' ', $per_lang->{$lang} || $per_lang->{generic} || $locale->{IM});
    } else { () }
}

#- [0]: console font name
#- [1]: unused
#- [2]: console map (none if utf8)
#- [3]: iocharset param for mount (utf8 if utf8)
#- [4]: codepage parameter for mount (none if utf8)
my %charsets = (
#- chinese needs special console driver for text mode
"Big5"        => [ undef,         undef,   undef,           "big5",       "950" ],
"gb2312"      => [ undef,         undef,   undef,           "gb2312",     "936" ],
"gbk"         => [ undef,         undef,   undef,           "gb2312",     "936" ],
"C"           => [ "lat0-16",     undef,   "8859-15",         "iso8859-1",  "850" ],
"iso-8859-1"  => [ "lat1-16",     undef,   "8859-1",         "iso8859-1",  "850" ],
"iso-8859-2"  => [ "lat2-16",  undef,   "8859-2",         "iso8859-2",  "852" ],
"iso-8859-5"  => [ "UniCyr_8x16", undef,   "8859-5",         "iso8859-5",  "866" ],
"iso-8859-7"  => [ "iso07u-16",   undef,   "8859-7",         "iso8859-7",  "869" ],
"iso-8859-9"  => [ "lat5-16",    undef,   "8859-9",         "iso8859-9",  "857" ],
"iso-8859-13" => [ "tlat7",       undef,   "8859-13",         "iso8859-13", "775" ],
"iso-8859-15" => [ "lat0-16",     undef,   "8859-15",         "iso8859-15", "850" ],
#- japanese needs special console driver for text mode [kon2]
"jisx0208"    => [ undef,         undef,   undef, "euc-jp",     "932" ],
"koi8-r"      => [ "UniCyr_8x16", undef,   "koi8-r",        "koi8-r",     "866" ],
"koi8-u"      => [ "UniCyr_8x16", undef,   "koi8-u",        "koi8-u",     "866" ],
"cp1251"      => [ "UniCyr_8x16", undef,   "cp1251",        "cp1251",     "866" ],
#- korean needs special console driver for text mode
"ksc5601"     => [ undef,         undef,   undef,           "euc-kr",     "949" ],
#- I have no console font for Thai...
"tis620"      => [ undef,         undef,   undef, "tis-620",    "874" ],
# UTF-8 encodings here; they differ in the console font mainly.
"utf_ar"      => [ undef,      undef,   undef,      "utf8",    undef ],
"utf_armn"    => [ undef,           undef,   undef,      "utf8",    undef ],
"utf_az"      => [ "tiso09e",        undef,   undef,      "utf8",    undef ],
"utf_beng"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_cyr1"    => [ "UniCyr_8x16",    undef,   undef,      "utf8",    undef ],
"utf_cyr2"    => [ "koi8-k",         undef,   undef,      "utf8",    undef ],
"utf_deva"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_ethi"    => [ "Agafari-16",     undef,   undef,      "utf8",    undef ],
"utf_geor"    => [ "t_geors",        undef,   undef,      "utf8",    undef ],
"utf_guru"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_he"      => [ undef,      undef,   undef,      "utf8",    undef ],
"utf_iu"      => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_khmr"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_knda"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_laoo"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_lat1"    => [ "lat0-16",        undef,   undef,      "utf8",    undef ],
"utf_lat5"    => [ undef,       undef,   undef,      "utf8",    undef ],
"utf_lat7"    => [ "tlat7",          undef,   undef,      "utf8",    undef ],
"utf_lat8"    => [ undef,      undef,   undef,      "utf8",    undef ],
"utf_mlym"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_mymr"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_taml"    => [ "tamil",          undef,   undef,      "utf8",    undef ],
# console font still to do
"utf_tfng"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_tibt"    => [ undef,            undef,   undef,      "utf8",    undef ],
"utf_vi"      => [ "tcvn8x16",       undef,   undef,      "utf8",    undef ],
"utf_yo"      => [ undef,            undef,   undef,      "utf8",    undef ],
# default for utf-8 encodings
"unicode"     => [ "LatArCyrHeb-16", undef,   undef,      "utf8",    undef ],
);

#- for special cases not handled magically
my %charset2kde_charset = (
    gb2312 => 'gb2312.1980-0',
    gbk => 'gb2312.1980-0',
    jisx0208 => 'jisx0208.1983-0',
    ksc5601 => 'ksc5601.1987-0',
    Big5 => 'big5-0',
    cp1251 => 'microsoft-cp1251',
    utf8 => 'iso10646-1',
    tis620 => 'tis620-0',
);

#- -------------------

sub l2console_font {
    my ($locale, $during_install) = @_;
    my $c = $charsets{l2charset($locale->{lang}) || return} or return;
    my ($name, $_sfm, $acm) = @$c;
    undef $acm if $locale->{utf8} && !$during_install;
    ($name, $acm);
}

sub get_kde_lang {
    my ($locale, $o_default) = @_;

    #- get it using 
    #- echo C $(rpm -qp --qf "%{name}\n" /RPMS/kde-i18n-*  | sed 's/kde-i18n-//')
    my @valid_kde_langs = qw(C
af ar az be bg bn br bs ca cs cy da de el en_GB eo es et eu fa fi fo fr ga gl he hi hr hsb hu id is it ja ko ku lo lt lv mi mk mn ms mt nb nds nl nn nso oc pa pl pt pt_BR ro ru se sk sl sr ss sv ta tg th tr uk uz ven vi wa wen xh zh_CN zh_TW zu);
    my %valid_kde_langs; @valid_kde_langs{@valid_kde_langs} = ();

    my $valid_lang = sub {
	my ($lang) = @_;
	#- fast & dirty solution to ensure bad entries do not happen
        my %fixlangs = (en => 'C', en_US => 'C',
                        en_AU => 'en_GB', en_CA => 'en_GB',
                        en_IE => 'en_GB', en_NZ => 'en_GB',
                        pa_IN => 'pa',
                        'sr@Latn' => 'sr',
                        ve => 'ven',
                        zh_CN => 'zh_CN', zh_SG => 'zh_CN',
		       	zh_TW => 'zh_TW', zh_HK => 'zh_TW');
        exists $fixlangs{$lang} ? $fixlangs{$lang} :
	  exists $valid_kde_langs{$lang} ? $lang :
	  exists $valid_kde_langs{locale_to_main_locale($lang)} ? locale_to_main_locale($lang) : '';
    };

    my $r;
    $r ||= $valid_lang->($locale->{lang});
    $r ||= find { $valid_lang->($_) } split(':', getlocale_for_lang($locale->{lang}, $locale->{country}));
    $r || $o_default || 'C';
}

sub charset2kde_charset {
    my ($charset, $o_default) = @_;
    my $iocharset = ($charsets{$charset} || [])->[3];

    my @valid_kde_charsets = qw(big5-0 gb2312.1980-0 iso10646-1 iso8859-1 iso8859-4 iso8859-6 iso8859-8 iso8859-13 iso8859-14 iso8859-15 iso8859-2 iso8859-3 iso8859-5 iso8859-7 iso8859-9 koi8-r koi8-u ksc5601.1987-0 jisx0208.1983-0 microsoft-cp1251 tis620-0);
    my %valid_kde_charsets; @valid_kde_charsets{@valid_kde_charsets} = ();

    my $valid_charset = sub {
	my ($charset) = @_;
	#- fast & dirty solution to ensure bad entries do not happen
	exists $valid_kde_charsets{$charset} && $charset;
    };

    my $r;
    $r ||= $valid_charset->($charset2kde_charset{$charset});
    $r ||= $valid_charset->($charset2kde_charset{$iocharset});
    $r ||= $valid_charset->($iocharset);
    $r || $o_default || 'iso10646-1';
}

#- font+size for different charsets; the field [0] is the default,
#- others are overrridens for fixed(1), toolbar(2), menu(3) and taskbar(4)
my %charset2kde_font = (
  'C' => [ "Sans,10", "Monospace,10" ],
  'iso-8859-1'  => [ "Sans,10", "Monospace,10" ],
  'iso-8859-2'  => [ "Sans,10", "Monospace,10" ],
  'iso-8859-7'  => [ "DejaVu Sans,10", "FreeMono,10" ],
  'iso-8859-9'  => [ "Sans,10", "Monospace,10" ],
  'iso-8859-13' => [ "Sans,10", "Monospace,10" ],
  'iso-8859-15' => [ "Sans,10", "Monospace,10" ],
  'jisx0208' => [ "UmePlus P Gothic,12", "UmePlus Gothic,12" ],
  'ksc5601' => [ "Baekmuk Gulim,12" ],
  'gb2312' => [ "Sans,10", "Monospace,10" ],
  'Big5' => [ "Sans,10", "Monospace,10" ],
  'tis620' => [ "Norasi,16", "Norasi,15" ],
  'koi8-u' => [ "DejaVu Sans,10", "FreeMono,10" ],
  'utf_ar' => [ "DejaVu Sans,11", "Courier New,13" ],
  'utf_az' => [ "DejaVu Sans,10", "FreeMono,10" ],
  'utf_he' => [ "DejaVu Sans,10", "FreeMono,10" ],
#-'utf_iu' => [ "????,14", ],
  'utf_vi' => [ "DejaVu Sans,12", "FreeMono,11", "DejaVu Sans,11" ],
  'utf_yo' => [ "DejaVu Sans,12", "FreeMono,11", "DejaVu Sans,11" ],
  #- script based
  'utf_armn' => [ "DejaVu Sans,11", "FreeMono,11" ],
  'utf_cyr2' => [ "DejaVu Sans,10", "FreeMono,10" ],
  'utf_beng' => [ "Mukti Narrow,13", "Mitra Mono,13", "Mukti Narrow,12" ],
  'utf_deva' => [ "Raghindi,12", ],
  'utf_ethi' => [ "GF Zemen Unicode,13" ],
  'utf_guru' => [ "Lohit Punjab,14", ],
#-'utf_khmr' => [ "????,14", ],
  'utf_knda' => [ "Sampige,14", ],
  'utf_lat1' => [ "Sans,10", "Monospace,10" ],
  'utf_lat5' => [ "Sans,10", "Monospace,10" ],
  'utf_lat7' => [ "Sans,10", "Monospace,10" ],
  'utf_lat8' => [ "DejaVu Sans,10", "FreeMono,10" ],
  'utf_mlym' => [ "malayalam,12", ],
#-'utf_mymr' => [ "????,14", ],
  'utf_taml' => [ "TSCu_Paranar,14", "Tsc_avarangalfxd,14", "TSCu_Paranar,13", ],
  'utf_tfng' => [ "Hapax Berbère,12", ],
  'utf_tibt' => [ "Tibetan Machine Uni,14", ],
  #- the following should be changed to better defaults when better fonts
  #- get available
  'utf_geor' => [ "ClearlyU,13" ],
  'utf_laoo' => [ "DejaVu Sans,11", "ClearlyU,13" ],
  'default'  => [ "DejaVu Sans,12", "FreeMono,11", "DejaVu Sans,11" ],
);

sub charset2kde_font {
    my ($charset, $type) = @_;

    my $font = $charset2kde_font{$charset} || $charset2kde_font{default};
    my $r = $font->[$type] || $font->[0];

    #- the format is "font-name,size,-1,5,0,0,0,0,0,0" I have no idea of the
    #- meaning of that "5"...
    "$r,-1,5,0,0,0,0,0,0";
}

# this define pango name fonts (like "NimbusSans L") depending
# on the "charset" defined by language array. This allows to selecting
# an appropriate font for each language for the installer only.
my %charset2pango_font = (
  'utf_geor' =>    "Sans 14",
  'utf_taml' =>    "TSCu_Paranar 14",
  'jisx0208' =>    "Sans 14",
  'utf_ar' =>      "Sans 15",
  'tis620' =>      "Norasi 20",
  'default' =>     "DejaVu Sans 12"
);

sub charset2pango_font {
    my ($charset) = @_;
    
    $charset2pango_font{exists $charset2pango_font{$charset} ? $charset : 'default'};
}

sub l2pango_font {
    my ($lang) = @_;

    my $charset = l2charset($lang) or log::l("no charset found for lang $lang!"), return;
    my $font = charset2pango_font($charset);
    log::l("lang:$lang charset:$charset font:$font consolefont:$charsets{$charset}[0]");
    
    return $font;
}

sub set {
    my ($locale, $b_translate_for_console) = @_;
    
    put_in_hash(\%ENV, i18n_env($locale));

    if (!$::isInstall) {
	bindtextdomain();
    } else {
	$ENV{LC_NUMERIC} = 'C'; #- otherwise eval "1.5" returns 1 in fr_FR
    
	if ($b_translate_for_console && $locale->{lang} =~ /^(ko|ja|zh|th)/) {
	    log::l("not translating in console");
	    $ENV{LANGUAGE}  = 'C';
	}
	load_mo();
    }
}

sub langs {
    my ($l) = @_;
    $l->{all} ? list_langs() : grep { $l->{$_} } keys %$l;
}

sub langsLANGUAGE {
    my ($l, $o_c) = @_;
    uniq(map { split ':', getLANGUAGE($_, $o_c) } langs($l));
}

sub utf8_should_be_needed {
    my ($_locale) = @_; 
    1;
}

sub pack_langs { 
    my ($l) = @_; 
    my $s = $l->{all} ? 'all' : join ':', uniq(map { getLANGUAGE($_) } langs($l));
    $s;
}

sub system_locales_to_ourlocale {
    my ($locale_lang, $locale_country) = @_;
    my $locale = {};
    my $h = analyse_locale_name($locale_lang);
    my $locale_lang_no_encoding = join('_', $h->{main}, if_($h->{country}, $h->{country}));
    $locale->{lang} = member($locale_lang_no_encoding, list_langs()) ?
	$locale_lang_no_encoding : #- special lang's such as en_US pt_BR
	$h->{main};
    $locale->{lang} .= '@' . $h->{variant} if $h->{variant};
    $locale->{country} = analyse_locale_name($locale_country)->{country};
    $locale->{utf8} = $h->{charset} && $h->{charset} eq 'UTF-8';
    #- safe fallbacks
    $locale->{lang} ||= 'en_US';
    $locale->{country} ||= 'US';
    $locale;
}

sub lang_changed {
    my ($locale) = @_;
    my $h = analyse_locale_name(l2locale($locale->{lang}));
    $locale->{country} = $h->{country} if $h->{country};

    $locale->{IM} = get_default_im($locale->{lang});
}

sub read {
    my ($b_user_only) = @_;
    my ($f1, $f2) = ("$::prefix$ENV{HOME}/.i18n", "$::prefix/etc/sysconfig/i18n");
    my %h = getVarsFromSh($b_user_only && -e $f1 ? $f1 : $f2);
    my $locale = system_locales_to_ourlocale($h{LC_MESSAGES} || 'en_US', $h{LC_MONETARY} || 'en_US');
    
    if (find { $h{$_} } @IM_i18n_fields) {
	my @l = grep { !/^scim/ || /\(default\)/ } keys %IM_config;
	foreach my $field ('XMODIFIERS', 'XIM_PROGRAM') {
	    $h{$field} or next;
	    my @m = grep { $h{$field} eq $IM_config{$_}{$field} } @l or last;
	    @l = @m;
	}
	$locale->{IM} = $l[0] if @l;
    }
    $locale;
}

sub write_langs {
    my ($langs) = @_;
    my $s = pack_langs($langs);
    symlink "$::prefix/etc/rpm/macros", "/etc/rpm/macros" if $::prefix;
    require URPM;
    URPM::add_macro("_install_langs $s");
    substInFile { s/%_install_langs.*//; $_ .= "%_install_langs $s\n" if eof && $s } "$::prefix/etc/rpm/macros";
}

sub i18n_env {
    my ($locale) = @_;

    my $locale_lang = getlocale_for_lang($locale->{lang}, $locale->{country}, $locale->{utf8});
    my $locale_country = getlocale_for_country($locale->{lang}, $locale->{country}, $locale->{utf8});

    my $h = {
	XKB_IN_USE => '',
	(map { $_ => $locale_lang } qw(LANG LC_COLLATE LC_CTYPE LC_MESSAGES LC_TIME)),
	LANGUAGE => getLANGUAGE($locale->{lang}, $locale->{country}, $locale->{utf8}),
	(map { $_ => $locale_country } qw(LC_NUMERIC LC_MONETARY LC_ADDRESS LC_MEASUREMENT LC_NAME LC_PAPER LC_IDENTIFICATION LC_TELEPHONE))
    };

    log::l("i18n_env: lang:$locale->{lang} country:$locale->{country} locale|lang:$locale_lang locale|country:$locale_country LANGUAGE:$h->{LANGUAGE}");

    $h;
}

sub write_and_install {
    my ($locale, $do_pkgs, $b_user_only, $b_dont_touch_kde_files) = @_;

    my @packages = IM2packages($locale);
    if (@packages && !$b_user_only) {
	log::explanations("Installing IM packages: ", join(', ', @packages));
	$do_pkgs->ensure_are_installed(\@packages, 1);
    }
    &write($locale, $b_user_only, $b_dont_touch_kde_files);
}

sub write { 
    my ($locale, $b_user_only, $b_dont_touch_kde_files) = @_;

    $locale && $locale->{lang} or return;

    my $h = i18n_env($locale);

    my ($name, $acm) = l2console_font($locale, 0);
    if ($name && !$b_user_only) {
	my $p = "$::prefix/usr/lib/kbd";
	if ($name) {
	    eval {
		log::explanations(qq(Set system font to "$name"));
		cp_af(glob_("$p/consolefonts/$name.*"), "$::prefix/etc/sysconfig/console/consolefonts");
		add2hash $h, { SYSFONT => $name };
	    };
	    $@ and log::explanations("missing console font $name");
	}
	if ($acm) {
	    eval {
		log::explanations(qq(Set application-charset map (Unicode mapping table) to "$name"));
		cp_af(glob_("$p/consoletrans/$acm*"), "$::prefix/etc/sysconfig/console/consoletrans");
		add2hash $h, { SYSFONTACM => $acm };
	    };
	    $@ and log::explanations("missing console acm file $acm");
	}
	
    }

    add2hash($h, $IM_locale_specific_config{$locale->{lang}});
    $h->{ENC} = $locale2ENC{$locale->{lang}};
    $h->{ENC} = 'utf8' if $h->{ENC} && $locale->{utf8};

    if ($locale->{IM}) {
        log::explanations(qq(Configuring "$locale->{IM}" IM));
	foreach (@IM_i18n_fields) {
	    $h->{$_} = $IM_config{$locale->{IM}}{$_};
	}
 #       $h->{QT_IM_MODULE} = $h->{GTK_IM_MODULE};

	if (ref $h->{XIM_PROGRAM}) {
	    $h->{XIM_PROGRAM} = 
	      $h->{XIM_PROGRAM}{$locale->{lang}} ||
		$h->{XIM_PROGRAM}{getlocale_for_country($locale->{lang}, $locale->{country})};
	}
    }

    #- deactivate translations on console for most CJK, RTL and complex languages
    if (member($locale->{lang}, qw(ar bn fa he hi ja kn ko pa_IN ug ur yi zh_TW zh_CN))) {
        #- CONSOLE_NOT_LOCALIZED if defined to yes, disables translations on console
        #-	it is needed for languages not supported by the linux console
        log::explanations(qq(Disabling translation on console since "$locale->{lang}" is not supported by the console));
        add2hash($h, { CONSOLE_NOT_LOCALIZED => 'yes' });
    }

    my $file = $b_user_only ? "$ENV{HOME}/.i18n" : '/etc/sysconfig/i18n';
    log::explanations(qq(Setting l10n configuration in "$file"));
    setVarsInSh($::prefix . $file, $h);

    configure_hal($locale) if !$b_user_only;

    run_program::rooted($::prefix, 'grub-gfxmenu', '--quiet', '--lang', $locale->{lang}) if !$b_user_only;
    
    my $charset = l2charset($locale->{lang});
    my $qtglobals = $b_user_only ? "$ENV{HOME}/.qt/qtrc" : "$::prefix/etc/qtrc";
    update_gnomekderc($qtglobals, General => (
       		      font => charset2kde_font($charset, 0),
       	          ));

    eval {
	my %dir_defaults = read_gnomekderc("$::prefix/etc/kderc", 'Directories-default');
	my $confdir = $::prefix . ($b_user_only ? "$ENV{HOME}/.kde" : first(split(',', $dir_defaults{prefixes})) || "/etc/kde") . '/share/config';

	-d $confdir or die 'not configuring kde config files since it is not installed/used';

	configure_kdeglobals($locale, $confdir);

	my %qt_xim = (zh => 'Over The Spot', ko => 'On The Spot', ja => 'On The Spot');
	if ($b_user_only && (my $qt_xim = $qt_xim{locale_to_main_locale($locale->{lang})})) {
         log::explanations(qq(Setting XIM input style to "$qt_xim"));
	    update_gnomekderc("$ENV{HOME}/.qt/qtrc", General => (XIMInputStyle => $qt_xim));
	}

	if (!$b_user_only) {
	    my $kde_charset = charset2kde_charset(l2charset($locale->{lang}));
	    my $welcome = common::to_utf8(N("Welcome to %s", '%n'));
         log::explanations(qq(Configuring KDM/MdkKDM));
	    substInFile { 
		s/^(GreetString)=.*/$1=$welcome/;
		s/^(Language)=.*/$1=$locale->{lang}/;
		if (!member($kde_charset, 'iso8859-1', 'iso8859-15')) { 
		    #- do not keep the default for those
    		    my $font_list = $charset2kde_font{l2charset($locale->{lang})} || $charset2kde_font{default};
		    my $font_small = $font_list->[0];
		    my $font_huge = $font_small;
		    $font_huge =~ s/(.*?),\d+/$1,24/;
		    s/^(StdFont)=.*/$1=$font_small,5,$kde_charset,50,0/;
		    s/^(FailFont)=.*/$1=$font_small,5,$kde_charset,75,0/;
		    s/^(GreetFont)=.*/$1=$font_huge,5,$kde_charset,50,0/;
		}
	    } "$::prefix/etc/kde/kdm/kdmrc";
	}

    } if !$b_dont_touch_kde_files;
}

sub configure_hal {
    my ($locale) = @_;
    my $option = sub {
	my ($cat, $val) = @_;
	qq(\t\t<merge key="$cat.policy.mount_option.$val" type="bool">true</merge>);
    };
    my %options = (fs_options($locale), utf8 => 1);
    my %known_options = (
	auto  => [ 'iocharset', 'codepage' ],
	vfat  => [ 'iocharset', 'codepage' ],
	msdos => [ 'iocharset', 'codepage' ],
	ntfs  => [ 'iocharset', 'utf8' ],
	cdrom => [ 'iocharset', 'codepage', 'utf8' ],
    );
    my $options = sub {
	my ($cat, $name) = @_;
	join("\n", map { 
	    $option->($cat, $_ eq 'utf8' ? $_ : "$_=$options{$_}");
	} grep { $options{$_} } @{$known_options{$name}});
    };
    my $options_per_fs = join('', map {
	my $s = $options->('volume', $_);
	$s && sprintf(<<'EOF', $_, $s);
	<match key="volume.fstype" string="%s">
%s
	</match>
EOF
    } 'auto', 'vfat', 'msdos', 'ntfs');
    
    output_p("$::prefix/usr/share/hal/fdi/30osvendor/locale-policy.fdi", 
	     sprintf(<<'EOF', $options_per_fs, $options->('storage', 'cdrom')));
<?xml version="1.0" encoding="UTF-8"?> <!-- -*- SGML -*- --> 

<deviceinfo version="0.2">

  <device>
    <match key="block.is_volume" bool="true">
      <match key="volume.fsusage" string="filesystem">

%s 
      </match>
    </match>

    <match key="storage.drive_type" string="cdrom">
%s
    </match>    
  </device>

</deviceinfo>
EOF
}

sub configure_kdeglobals {
    my ($locale, $confdir) = @_;
    my $kdeglobals = "$confdir/kdeglobals";

    my $charset = l2charset($locale->{lang});
    my $kde_charset = charset2kde_charset($charset);

    mkdir_p($confdir);

    my $lang = get_kde_lang($locale);
    log::explanations("Configuring KDE regarding charset ($kde_charset), language ($lang) and country ($locale->{country})");
    update_gnomekderc($kdeglobals, Locale => (
    	      Charset => $kde_charset,
    	      Country => lc($locale->{country}),
    	      Language => getLANGUAGE($locale->{lang}, $locale->{country}, $locale->{utf8}),
    	  ));

    log::explanations("Configuring KDE regarding fonts");
        update_gnomekderc($kdeglobals, WM => (
       		      activeFont => charset2kde_font($charset,0),
       		  ));
        update_gnomekderc($kdeglobals, General => (
       		      fixed => charset2kde_font($charset, 1),
       		      font => charset2kde_font($charset, 0),
       		      menuFont => charset2kde_font($charset, 3),
       		      taskbarFont => charset2kde_font($charset, 4),
       		      toolBarFont => charset2kde_font($charset, 2),
       	          ));
        update_gnomekderc("$confdir/konquerorrc", FMSettings => (
       		      StandardFont => charset2kde_font($charset, 0),
       		  ));
        update_gnomekderc("$confdir/kdesktoprc", FMSettings => (
       		      StandardFont => charset2kde_font($charset, 0),
       		  ));
}

sub bindtextdomain() {
    #- if $::prefix is set, search for libDrakX.mo in locale_special
    #- NB: not using $::isInstall to make it work more easily at install and standalone
    my $localedir = "$ENV{SHARE_PATH}/locale" . ($::prefix ? "_special" : '');

    c::init_setlocale();
    foreach (@::textdomains, 'libDrakX') {
	Locale::gettext::bind_textdomain_codeset($_, 'UTF-8');
	Locale::gettext::bindtextdomain($_, $localedir);
    }

    $localedir;
}

sub load_mo {
    my ($o_lang) = @_;

    my $localedir = bindtextdomain();
    my $suffix = 'LC_MESSAGES/libDrakX.mo';

    $o_lang ||= $ENV{LANGUAGE} || $ENV{LC_ALL} || $ENV{LC_MESSAGES} || $ENV{LANG};

    my @possible_langs = map { { name => $_, mofile => "$localedir/$_/$suffix" } } split ':', $o_lang;

    -s $_->{mofile} and return $_->{name} foreach @possible_langs;

    '';
}


#- used in share/list.xml during "make get_needed_files"
sub console_font_files() {
    map { -e $_ ? $_ : "$_.gz" }
      (map { my $p = "/usr/lib/kbd/consolefonts/$_"; -e "$p.psfu" || -e "$p.psfu.gz" ? "$p.psfu" : "$p.psf" } uniq grep { $_ } map { $_->[0] } values %charsets),
      (map { "/usr/lib/kbd/consoletrans/${_}_to_uni.trans" } uniq grep { $_ } map { $_->[2] } values %charsets);
}

sub load_console_font {
    my ($locale) = @_;
    return if $::local_install;

    my ($name, $acm) = l2console_font($locale, 1);

    require run_program;
    run_program::run('setfont', '-v', $name || 'lat0-16', if_($acm, '-m', $acm));
}

sub fs_options {
    my ($locale) = @_;
    if ($locale->{utf8}) {
	(iocharset => 'utf8', codepage => undef);
    } else {
	my $c = $charsets{l2charset($locale->{lang}) || return} or return;
	my ($iocharset, $codepage) = @$c[3..4];
	(iocharset => $iocharset, codepage => $codepage);
    }
}

sub check() {
    $^W = 0;
    my ($warnings, $errors) = (0, 0);
    my $warn = sub {
	my ($msg, $b_is_error) = @_;
	if ($b_is_error) {
	    print STDERR "\tErrors:\n" if !$errors++;
	} else {
	    print STDERR "\tWarnings:\n" if !$warnings++;
	}
	print STDERR "$msg\n";
    };
    my $err = sub { $warn->($_[0], 'error') };
    
    my @wanted_charsets = uniq map { l2charset($_) } list_langs();
    $warn->("unused charset $_ (given in \%charsets, but not used in \%langs)") foreach difference2([ keys %charsets ], \@wanted_charsets);

    $warn->("unused entry $_ in \%xim") foreach grep { !/UTF-8/ } difference2([ keys %IM_locale_specific_config ], [ map { l2locale($_) } list_langs() ]);

    #- consolefonts are checked during build via console_font_files()

    if (my @l = difference2([ 'default', keys %charsets ], [ keys %charset2kde_font ])) {
	$warn->("no kde font for charset " . join(" ", @l));
    }

    if (my @l = grep { get_kde_lang({ lang => $_, country => 'US' }, 'err') eq 'err' } list_langs()) {
	$warn->("no KDE lang for langs " . join(" ", @l));
    }
    if (my @l = grep { charset2kde_charset($_, 'err') eq 'err' } keys %charsets) {
	$warn->("no KDE charset for charsets " . join(" ", @l));
    }

    $warn->("no country corresponding to default locale $_->[1] of lang $_->[0]")
      foreach grep { $_->[1] =~ /.._(..)/ && !exists $countries{$1} } map { [ $_, l2locale($_) ] } list_langs();

    $err->("invalid charset $_ ($_ does not exist in \%charsets)") foreach difference2(\@wanted_charsets, [ keys %charsets ]);
    $err->("invalid charset $_ in \%charset2kde_font ($_ does not exist in \%charsets)") foreach difference2([ keys %charset2kde_font ], [ 'default', keys %charsets ]);

    $err->("default locale $_->[1] of lang $_->[0] is not listed in \@locales")
      foreach grep { !member($_->[1], @locales) } map { [ $_, l2locale($_) ] } list_langs();

    $err->("lang image for lang $_->[0] is missing (file $_->[1])")
      foreach grep { !(-e $_->[1]) } map { [ $_, "install/pixmaps/langs/lang-$_.png" ] } list_langs();

    $err->("default locale $_->[1] of country $_->[0] is not listed in \@locales")
      foreach grep { !member($_->[1], @locales) } map { [ $_, c2locale($_) ] } list_countries();


    exit($errors ? 1 : 0);
}

1;
