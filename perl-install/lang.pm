package lang; # $Id$

use diagnostics;
use strict;
use common;
use log;

#- key: lang name (locale name for some (~5) special cases needing
#-      extra distinctions)
#- [0]: language name (localized, used for sorting, the display is done
#-      with a lang-%s.png image, with %s being the key)
#- [1]: transliterated locale name in the locale name (used for sorting)
#- [2]: default locale name to use for that language if there isn't
#-      an existing locale for the combination language+country choosen
#- [3]: geographic groups that this language belongs to (for displaying
#-      in the menu grouped in smaller lists), 1=Europe, 2=Asia, 3=Africa,
#-      4=Oceania&Pacific, 5=America (if you wonder, it's the order
#-      used in the olympic flag)
#- [4]: special value for LANGUAGE variable (if different of the default
#-      of 'll_CC:ll_DD:ll' (ll_CC: locale (if exist) resulting of the
#-      combination of chosen lang (ll) and country (CC), ll_DD: the
#-      default locale shown here (field [2]) and ll: the language (the key))
my %langs = (
'en_US' => [ 'English (American)',  'American English',  'en_US', '    5', 'C' ],
'en_GB' => [ 'English',             'British English',   'en_GB', '12345', 'iso-8859-15' ],
'af' =>    [ 'Afrikaans',           'Afrikaans',         'af_ZA', '  3  ', 'iso-8859-1' ],
'am' =>    [ 'Amharic',             'ZZ emarNa',         'am_ET', '  3  ', 'utf_am' ],
'ar' =>    [ 'Arabic',              'AA Arabic',         'ar_EG', ' 23  ', 'utf_ar' ],
'az' =>    [ 'Azeri (Latin)',       'Azerbaycanca',      'az_AZ', ' 2   ', 'utf_az' ],
'be' =>    [ 'Belarussian',         '_Belarussian',      'be_BY', '1    ', 'cp1251' ],
'bg' =>    [ 'Bulgarian',           'Blgarski',          'bg_BG', '1    ', 'cp1251' ],
'br' =>    [ 'Brezhoneg',           'Brezhoneg',         'br_FR', '1    ', 'iso-8859-15', 'br:fr_FR:fr' ],
'bs' =>    [ 'Bosnian',             'Bosanski',          'bs_BA', '1    ', 'iso-8859-2' ],
'ca' =>    [ 'Catalan',             'Catala',            'ca_ES', '1    ', 'iso-8859-15', 'ca:es_ES:es' ],
'cs' =>    [ 'Czech',               'Cestina',           'cs_CZ', '1    ', 'iso-8859-2' ],
'cy' =>    [ 'Cymraeg (Welsh)',     'Cymraeg',           'cy_GB', '1    ', 'utf_lat8', 'cy:en_GB:en' ],
'da' =>    [ 'Danish',              'Dansk',             'da_DK', '1    ', 'iso-8859-15' ],
'de' =>    [ 'German',              'Deutsch',           'de_DE', '1    ', 'iso-8859-15' ],
'el' =>    [ 'Greek',               'Ellynika',          'el_GR', '1    ', 'iso-8859-7' ],
'eo' =>    [ 'Esperanto',           'Esperanto',         'eo_XX', '12345', 'unicode' ],
'es' =>    [ 'Spanish',             'Espanol',           'es_ES', '1 3 5', 'iso-8859-15' ],
'et' =>    [ 'Estonian',            'Eesti',             'et_EE', '1    ', 'iso-8859-15' ],
'eu' =>    [ 'Euskara (Basque)',    'Euskara',           'eu_ES', '1    ', 'iso-8859-15' ],
'fa' =>    [ 'Farsi (Iranian)',     'AA Farsi',          'fa_IR', ' 2   ', 'utf_ar' ],
'fi' =>    [ 'Finnish (Suomi)',     'Suomi',             'fi_FI', '1    ', 'iso-8859-15' ],
#'fo' =>   [ 'Faroese',             'Foroyskt',          'fo_FO', '1    ', 'iso-8859-1' ],
'fr' =>    [ 'French',              'Francais',          'fr_FR', '1 345', 'iso-8859-15' ],
'ga' =>    [ 'Gaeilge (Irish)',     'Gaeilge',           'ga_IE', '1    ', 'iso-8859-15', 'ga:en_IE:en_GB:en' ],
#'gd' =>   [ 'Scottish gaelic',     'Gaidhlig',          'gb_GB', '1    ', 'utf_lat8', 'gd:en_GB:en' ],
'gl' =>    [ 'Galego (Galician)',   'Galego',            'gl_ES', '1    ', 'iso-8859-15', 'gl:es_ES:es:pt:pt_BR' ],
#'gv' =>   [ 'Manx gaelic',         'Gaelg',             'gv_GB', '1    ', 'utf_lat8', 'gv:en_GB:en' ],
'he' =>    [ 'Hebrew',              'AA Ivrit',          'he_IL', ' 2   ', 'utf_he' ],
#waiting-for-image 'hi' =>    [ 'Hindi',               'ZZ Hindi',          'hi_IN', ' 2   ', 'unicode' ],
'hr' =>    [ 'Croatian',            'Hrvatski',          'hr_HR', '1    ', 'iso-8859-2' ],
'hu' =>    [ 'Hungarian',           'Magyar',            'hu_HU', '1    ', 'iso-8859-2' ],
'hy' =>    [ 'Armenian',            'ZZ Armenian',       'hy_AM', ' 2   ', 'utf_hy' ],
#'ia' =>   [ 'Interlingua',         'Interlingua',       'ia_XX', '1   5', 'utf8' ],
'id' =>    [ 'Indonesian',          'Bahasa Indonesia',  'id_ID', ' 2   ', 'iso-8859-1' ],
'is' =>    [ 'Icelandic',           'Islenska',          'is_IS', '1    ', 'iso-8859-1' ],
'it' =>    [ 'Italian',             'Italiano',          'it_IT', '1    ', 'iso-8859-15' ],
#-'iu' =>  [ 'Inuktitut',           'ZZ Inuktitut',      'iu_CA', '    5', 'utf_iu' ],
'ja' =>    [ 'Japanese',            'ZZ Nihongo',        'ja_JP', ' 2   ', 'jisx0208' ],
'ka' =>    [ 'Georgian',            'ZZ Georgian',       'ka_GE', ' 2   ', 'utf_ka' ],
#-'kl' =>  [ 'Greenlandic (inuit)', 'ZZ Inuit',          'kl_GL', '    5', 'iso-8859-1' ],
#-'kn' =>  [ 'Kannada',             'ZZ Kannada',        'kn_IN', ' 2   ', 'unicode' ],
'ko' =>    [ 'Korean',              'ZZ Korea',          'ko_KR', ' 2   ', 'ksc5601' ],
#-'kw' =>  [ 'Cornish gaelic',      'Kernewek',          'kw_GB', '1    ', 'utf_lat8', 'kw:en_GB:en' ],
#waiting-for-image 'lo' => [ 'Laotian',  'lo_LA', ' 2   ', 'utf_lo' ],
'lt' =>    [ 'Lithuanian',          'Lietuviskai',       'lt_LT', '1    ', 'iso-8859-13' ],
'lv' =>    [ 'Latvian',             'Latviesu',          'lv_LV', '1    ', 'iso-8859-13' ],
'mi' =>    [ 'Maori',               'Maori',             'mi_NZ', '   4 ', 'unicode' ],
'mk' =>    [ 'Macedonian',          'Makedonski',        'mk_MK', '1    ', 'utf_cyr1' ],
#waiting-for-image'mn' =>    [ 'Mongolian',           'Mongol',            'mn_MN', ' 2   ', 'utf_cyr2' ],
'ms' =>    [ 'Malay',               'Bahasa Melayu',     'ms_MY', ' 2   ', 'iso-8859-1' ],
'mt' =>    [ 'Maltese',             'Maltin',            'mt_MT', '1 3  ', 'unicode' ],
'nb' =>    [ 'Norwegian Bokmaal',   'Norsk, Bokmal',     'no_NO', '1    ', 'iso-8859-1',  'nb:no' ],
'nl' =>    [ 'Dutch',               'Nederlands',        'nl_NL', '1    ', 'iso-8859-15' ],
'nn' =>    [ 'Norwegian Nynorsk',   'Norsk, Nynorsk',    'nn_NO', '1    ', 'iso-8859-1',  'nn:no@nynorsk:no_NY:no:nb' ],
#-'oc' =>  [ 'Occitan',             'Occitan',           'oc_FR', '1    ', 'iso-8859-1', 'oc:fr_FR:fr' ],
#-'ph' =>  [ 'Pilipino',            'Pilipino',          'ph_PH', ' 2   ', 'iso-8859-1', 'ph:tl' ],
'pl' =>    [ 'Polish',              'Polski',            'pl_PL', '1    ', 'iso-8859-2' ],
'pt' =>    [ 'Portuguese',          'Portugues',         'pt_PT', '1 3  ', 'iso-8859-15', 'pt_PT:pt:pt_BR' ],
'pt_BR' => [ 'Portuguese Brazil', 'Portugues do Brasil', 'pt_BR', '    5', 'iso-8859-1',  'pt_BR:pt_PT:pt' ],
'ro' =>    [ 'Romanian',            'Romana',            'ro_RO', '1    ', 'iso-8859-2' ],
'ru' =>    [ 'Russian',             'Russkij',           'ru_RU', '12   ', 'koi8-r' ],
'sk' =>    [ 'Slovak',              'Slovencina',        'sk_SK', '1    ', 'iso-8859-2' ],
'sl' =>    [ 'Slovenian',           'Slovenscina',       'sl_SI', '1    ', 'iso-8859-2' ],
'sp' =>    [ 'Serbian Cyrillic',    'Srpska',            'sp_YU', '1    ', 'iso-8859-5',      'sp:sr' ],
'sq' =>    [ 'Albanian',            'Shqip',             'sq_AL', '1    ', 'iso-8859-1' ], 
'sr' =>    [ 'Serbian Latin',       'Srpska',            'sr_YU', '1    ', 'iso-8859-2' ], 
'sv' =>    [ 'Swedish',             'Svenska',           'sv_SE', '1    ', 'iso-8859-1' ],
'ta' =>    [ 'Tamil',               'ZZ Tamil',          'ta_IN', ' 2   ', 'utf_ta' ],
'tg' =>    [ 'Tajik',               'Tojiki',            'tg_TJ', ' 2   ', 'utf_cyr2' ],
'th' =>    [ 'Thai',                'ZZ Thai',           'th_TH', ' 2   ', 'tis620' ],
'tr' =>    [ 'Turkish',             'Turkce',            'tr_TR', ' 2   ', 'iso-8859-9' ],
#-'tt' =>  [ 'Tatar',               'Tatar',             'tt_RU', ' 2   ', 'utf_cyr2' ],
'uk' =>    [ 'Ukrainian',           'Ukrayinska',        'uk_UA', '1    ', 'koi8-u' ],
#-'ur' =>  [ 'Urdu',                'AA Urdu',           'ur_PK', ' 2   ', 'utf_ar' ],  
'uz' =>    [ 'Uzbek',               'Ozbekcha',          'uz_UZ', ' 2   ', 'unicode' ],
'vi' =>    [ 'Vietnamese',          'Tieng Viet',        'vi_VN', ' 2   ', 'utf_vi' ],
'wa' =>    [ 'Walon',               'Walon',             'wa_BE', '1    ', 'iso-8859-15', 'wa:fr_BE:fr' ],
#-'yi' =>  [ 'Yiddish',             'AA Yidish',         'yi_US', '1   5', 'utf_he' ],
'zh_TW' => [ 'Chinese Traditional', 'ZZ ZhongWen',       'zh_TW', ' 2   ', 'Big5',        'zh_TW.Big5:zh_TW:zh_HK:zh' ],
'zh_CN' => [ 'Chinese Simplified',  'ZZ ZhongWen',       'zh_CN', ' 2   ', 'gb2312',      'zh_CN.GB2312:zh_CN:zh' ],
);
sub l2name           { exists $langs{$_[0]} && $langs{$_[0]}[0] }
sub l2transliterated { exists $langs{$_[0]} && $langs{$_[0]}[1] }
sub l2locale         { exists $langs{$_[0]} && $langs{$_[0]}[2] }
sub l2location {
    my %geo = (1 => 'Europe', 2 => 'Asia', 3 => 'Africa', 4 => 'Oceania/Pacific', 5 => 'America');
    map { if_($langs{$_[0]}[3] =~ $_, $geo{$_}) } 1..5;
}
sub l2charset        { exists $langs{$_[0]} && $langs{$_[0]}[4] }
sub l2language       { exists $langs{$_[0]} && $langs{$_[0]}[5] }
sub list_langs {
    my (%options) = @_;
    my @l = keys %langs;
    $options{exclude_non_installed} ? grep { -e "/usr/share/locale/".l2locale($_)."/LC_CTYPE" } @l : @l;
}

#- key: country name (that should be YY in xx_YY locale)
#- [0]: country name in natural language
#- [1]: default locale for that country 
#- [2]: geographic groups that this country belongs to (for displaying
#-      in the menu grouped in smaller lists), 1=Europe, 2=Asia, 3=Africa,
#-      4=Oceania&Pacific, 5=America (if you wonder, it's the order
#-      used in the olympic flag)
#-
#- Note: for countries for which a glibc locale don't exist (yet) I tried to
#- put a locale that makes sense; and a '#' at the end of the line to show
#- the locale is not the "correct" one. 'en_US' is used when no good choice
#- is available.
my %countries = (
'AF' => [ N("Afghanistan"),    'en_US', '2' ], #
'AD' => [ N("Andorra"),        'ca_ES', '1' ], #
'AE' => [ N("United Arab Emirates"), 'ar_AE', '2' ],
'AG' => [ N("Antigua and Barbuda"), 'en_US', '5' ], #
'AI' => [ N("Anguilla"),       'en_US', '5' ], #
'AL' => [ N("Albania"),        'sq_AL', '1' ],
'AM' => [ N("Armenia"),        'hy_AM', '2' ],
'AN' => [ N("Netherlands Antilles"), 'en_US', '5' ], #
'AO' => [ N("Angola"),         'pt_PT', '3' ], #
'AQ' => [ N("Antarctica"),     'en_US', '4' ], #
'AR' => [ N("Argentina"),      'es_AR', '5' ],
'AS' => [ N("American Samoa"), 'en_US', '4' ], #
'AT' => [ N("Austria"),        'de_AT', '1' ],
'AU' => [ N("Australia"),      'en_AU', '4' ],
'AW' => [ N("Aruba"),          'en_US', '?' ], #
'AZ' => [ N("Azerbaijan"),     'az_AZ', '1' ],
'BA' => [ N("Bosnia and Herzegovina"), 'bs_BA', '1' ],
'BB' => [ N("Barbados"),       'en_US', '5' ], #
'BD' => [ N("Bangladesh"),     'bn_BD', '2' ],
'BE' => [ N("Belgium"),        'fr_BE', '1' ],
'BF' => [ N("Burkina Faso"),   'en_US', '3' ], #
'BG' => [ N("Bulgaria"),       'bg_BG', '1' ],
'BH' => [ N("Bahrain"),        'ar_BH', '2' ],
'BI' => [ N("Burundi"),        'en_US', '3' ], #
'BJ' => [ N("Benin"),          'fr_FR', '3' ], #
'BM' => [ N("Bermuda"),        'en_US', '5' ], #
'BN' => [ N("Brunei Darussalam"), 'ar_EG', '2' ], #
'BO' => [ N("Bolivia"),        'es_BO', '5' ],
'BR' => [ N("Brazil"),         'pt_BR', '5' ],
'BS' => [ N("Bahamas"),        'en_US', '5' ], #
'BT' => [ N("Bhutan"),         'en_IN', '2' ], #
'BV' => [ N("Bouvet Island"),  'en_US', '?' ], #
'BW' => [ N("Botswana"),       'en_BW', '3' ],
'BY' => [ N("Belarus"),        'be_BY', '1' ],
'BZ' => [ N("Belize"),         'en_US', '5' ], #
'CA' => [ N("Canada"),         'en_CA', '5' ],
'CC' => [ N("Cocos (Keeling) Islands"), 'en_US', '?' ], #
'CD' => [ N("Congo (Kinshasa)"), 'fr_FR', '3' ], #
'CF' => [ N("Central African Republic"), 'fr_FR', '3' ], #
'CG' => [ N("Congo (Brazzaville)"), 'fr_FR', '3' ], #
'CH' => [ N("Switzerland"),    'de_CH', '1' ],
'CI' => [ N("Cote d'Ivoire"),  'fr_FR', '3' ], #
'CK' => [ N("Cook Islands"),   'en_US', '?' ], #
'CL' => [ N("Chile"),          'es_CL', '5' ],
'CM' => [ N("Cameroon"),       'fr_FR', '3' ], #
'CN' => [ N("China"),          'zh_CN', '2' ],
'CO' => [ N("Colombia"),       'es_CO', '5' ],
'CR' => [ N("Costa Rica"),     'es_CR', '5' ],
'CU' => [ N("Cuba"),           'es_DO', '5' ], #
'CV' => [ N("Cape Verde"),     'pt_PT', '3' ], #
'CX' => [ N("Christmas Island"), 'en_US', '?' ], #
'CY' => [ N("Cyprus"),         'en_US', '1' ], #
'CZ' => [ N("Czech Republic"), 'cs_CZ', '2' ],
'DE' => [ N("Germany"),        'de_DE', '1' ],
'DJ' => [ N("Djibouti"),       'en_US', '3' ], #
'DK' => [ N("Denmark"),        'da_DK', '1' ],
'DM' => [ N("Dominica"),       'en_US', '5' ], #
'DO' => [ N("Dominican Republic"), 'es_DO', '5' ],
'DZ' => [ N("Algeria"),        'ar_DZ', '3' ],
'EC' => [ N("Ecuador"),        'es_EC', '5' ],
'EE' => [ N("Estonia"),        'et_EE', '1' ],
'EG' => [ N("Egypt"),          'ar_EG', '3' ],
'EH' => [ N("Western Sahara"), 'ar_MA', '3' ], #
'ER' => [ N("Eritrea"),        'ti_ER', '3' ],
'ES' => [ N("Spain"),          'es_ES', '1' ],
'ET' => [ N("Ethiopia"),       'am_ET', '3' ],
'FI' => [ N("Finland"),        'fi_FI', '1' ],
'FJ' => [ N("Fiji"),           'en_US', '4' ], #
'FK' => [ N("Falkland Islands (Malvinas)"), 'en_GB', '5' ], #
'FM' => [ N("Micronesia"),     'en_US', '4' ], #
'FO' => [ N("Faroe Islands"),  'fo_FO', '1' ],
'FR' => [ N("France"),         'fr_FR', '1' ],
'GA' => [ N("Gabon"),          'fr_FR', '3' ], #
'GB' => [ N("United Kingdom"), 'en_GB', '1' ],
'GD' => [ N("Grenada"),        'en_US', '5' ], #
'GE' => [ N("Georgia"),        'ka_GE', '2' ],
'GF' => [ N("French Guiana"),  'fr_FR', '5' ], #
'GH' => [ N("Ghana"),          'fr_FR', '3' ], #
'GI' => [ N("Gibraltar"),      'en_GB', '1' ], #
'GL' => [ N("Greenland"),      'kl_GL', '5' ],
'GM' => [ N("Gambia"),         'en_US', '3' ], #
'GN' => [ N("Guinea"),         'en_US', '3' ], #
'GP' => [ N("Guadeloupe"),     'fr_FR', '5' ], #
'GQ' => [ N("Equatorial Guinea"), 'en_US', '3' ], #
'GR' => [ N("Greece"),         'el_GR', '1' ],
'GS' => [ N("South Georgia and the South Sandwich Islands"), 'en_US', '?' ], #
'GT' => [ N("Guatemala"),      'es_GT', '5' ],
'GU' => [ N("Guam"),           'en_US', '4' ], #
'GW' => [ N("Guinea-Bissau"),  'pt_PT', '3' ], #
'GY' => [ N("Guyana"),         'en_US', '5' ], #
'HK' => [ N("Hong Kong"),      'zh_HK', '2' ],
'HM' => [ N("Heard and McDonald Islands"), 'en_US', '?' ], #
'HN' => [ N("Honduras"),       'es_HN', '5' ],
'HR' => [ N("Croatia"),        'hr_HR', '1' ],
'HT' => [ N("Haiti"),          'fr_FR', '5' ], #
'HU' => [ N("Hungary"),        'hu_HU', '1' ],
'ID' => [ N("Indonesia"),      'id_ID', '2' ],
'IE' => [ N("Ireland"),        'en_IE', '1' ],
'IL' => [ N("Israel"),         'he_IL', '2' ],
'IN' => [ N("India"),          'hi_IN', '2' ],
'IO' => [ N("British Indian Ocean Territory"), 'en_GB', '2' ], #
'IQ' => [ N("Iraq"),           'ar_IQ', '2' ],
'IR' => [ N("Iran"),           'fa_IR', '2' ],
'IS' => [ N("Iceland"),        'is_IS', '1' ],
'IT' => [ N("Italy"),          'it_IT', '1' ],
'JM' => [ N("Jamaica"),        'en_US', '5' ], #
'JO' => [ N("Jordan"),         'ar_JO', '2' ],
'JP' => [ N("Japan"),          'ja_JP', '2' ],
'KE' => [ N("Kenya"),          'en_ZW', '3' ], #
'KG' => [ N("Kyrgyzstan"),     'en_US', '2' ], #
'KH' => [ N("Cambodia"),       'en_US', '2' ], # kh_KH not released yet
'KI' => [ N("Kiribati"),       'en_US', '3' ], #
'KM' => [ N("Comoros"),        'en_US', '2' ], #
'KN' => [ N("Saint Kitts and Nevis"), 'en_US', '?' ], #
'KP' => [ N("Korea (North)"),  'ko_KR', '2' ], #
'KR' => [ N("Korea"),          'ko_KR', '2' ],
'KW' => [ N("Kuwait"),         'ar_KW', '2' ],
'KY' => [ N("Cayman Islands"), 'en_US', '5' ], #
'KZ' => [ N("Kazakhstan"),     'ru_RU', '2' ], #
'LA' => [ N("Laos"),           'lo_LA', '2' ],
'LB' => [ N("Lebanon"),        'ar_LB', '2' ],
'LC' => [ N("Saint Lucia"),    'en_US', '5' ], #
'LI' => [ N("Liechtenstein"),  'de_CH', '1' ], #
'LK' => [ N("Sri Lanka"),      'en_IN', '2' ], #
'LR' => [ N("Liberia"),        'en_US', '3' ], #
'LS' => [ N("Lesotho"),        'en_BW', '3' ], #
'LT' => [ N("Lithuania"),      'lt_LT', '1' ],
'LU' => [ N("Luxembourg"),     'de_LU', '1' ],
'LV' => [ N("Latvia"),         'lv_LV', '1' ],
'LY' => [ N("Libya"),          'ar_LY', '3' ],
'MA' => [ N("Morocco"),        'ar_MA', '3' ],
'MC' => [ N("Monaco"),         'fr_FR', '1' ], #
'MD' => [ N("Moldova"),        'ro_RO', '1' ], #
'MG' => [ N("Madagascar"),     'fr_FR', '3' ], #
'MH' => [ N("Marshall Islands"), 'en_US', '4' ], #
'MK' => [ N("Macedonia"),      'mk_MK', '1' ],
'ML' => [ N("Mali"),           'en_US', '3' ], #
'MM' => [ N("Myanmar"),        'en_US', '2' ], #
'MN' => [ N("Mongolia"),       'mn_MN', '2' ],
'MP' => [ N("Northern Mariana Islands"), 'en_US', '?' ], #
'MQ' => [ N("Martinique"),     'fr_FR', '5' ], #
'MR' => [ N("Mauritania"),     'en_US', '3' ], #
'MS' => [ N("Montserrat"),     'en_US', '?' ], #
'MT' => [ N("Malta"),          'mt_MT', '1' ],
'MU' => [ N("Mauritius"),      'en_US', '?' ], #
'MV' => [ N("Maldives"),       'en_US', '4' ], #
'MW' => [ N("Malawi"),         'en_US', '3' ], #
'MX' => [ N("Mexico"),         'es_MX', '5' ],
'MY' => [ N("Malaysia"),       'ms_MY', '2' ],
'MZ' => [ N("Mozambique"),     'pt_PT', '3' ], #
'NA' => [ N("Namibia"),        'en_US', '3' ], #
'NC' => [ N("New Caledonia"),  'fr_FR', '4' ], #
'NE' => [ N("Niger"),          'en_US', '3' ], #
'NF' => [ N("Norfolk Island"), 'en_GB', '?' ], #
'NG' => [ N("Nigeria"),        'en_US', '3' ], #
'NI' => [ N("Nicaragua"),      'es_NI', '5' ],
'NL' => [ N("Netherlands"),    'nl_NL', '1' ],
'NO' => [ N("Norway"),         'no_NO', '1' ],
'NP' => [ N("Nepal"),          'en_IN', '2' ], #
'NR' => [ N("Nauru"),          'en_US', '?' ], #
'NU' => [ N("Niue"),           'en_US', '?' ], #
'NZ' => [ N("New Zealand"),    'en_NZ', '4' ],
'OM' => [ N("Oman"),           'ar_OM', '2' ],
'PA' => [ N("Panama"),         'es_PA', '5' ],
'PE' => [ N("Peru"),           'es_PE', '5' ],
'PF' => [ N("French Polynesia"), 'fr_FR', '4' ], #
'PG' => [ N("Papua New Guinea"), 'en_NZ', '4' ], #
'PH' => [ N("Philippines"),    'ph_PH', '2' ],
'PK' => [ N("Pakistan"),       'ur_PK', '2' ],
'PL' => [ N("Poland"),         'pl_PL', '1' ],
'PM' => [ N("Saint Pierre and Miquelon"), 'fr_CA', '5' ], #
'PN' => [ N("Pitcairn"),      'en_US', '4' ], #
'PR' => [ N("Puerto Rico"),    'es_PR', '5' ],
'PS' => [ N("Palestine"),      'ar_JO', '2' ], #
'PT' => [ N("Portugal"),       'pt_PT', '1' ],
'PY' => [ N("Paraguay"),       'es_PY', '5' ],
'PW' => [ N("Palau"),          'en_US', '?' ], #
'QA' => [ N("Qatar"),          'ar_QA', '2' ],
'RE' => [ N("Reunion"),        'fr_FR', '?' ], #
'RO' => [ N("Romania"),        'ro_RO', '1' ],
'RU' => [ N("Russia"),         'ru_RU', '1' ],
'RW' => [ N("Rwanda"),         'fr_FR', '3' ], #
'SA' => [ N("Saudi Arabia"),   'ar_SA', '2' ],
'SB' => [ N("Solomon Islands"), 'en_US', '4' ], #
'SC' => [ N("Seychelles"),     'en_US', '4' ], #
'SD' => [ N("Sudan"),          'ar_SD', '5' ],
'SE' => [ N("Sweden"),         'sv_SE', '1' ],
'SG' => [ N("Singapore"),      'en_SG', '2' ],
'SH' => [ N("Saint Helena"),   'en_GB', '5' ], #
'SI' => [ N("Slovenia"),       'sl_SI', '1' ],
'SJ' => [ N("Svalbard and Jan Mayen Islands"), 'en_US', '?' ], #
'SK' => [ N("Slovakia"),       'sk_SK', '1' ],
'SL' => [ N("Sierra Leone"),   'en_US', '3' ], #
'SM' => [ N("San Marino"),     'it_IT', '1' ], #
'SN' => [ N("Senegal"),        'fr_FR', '3' ], #
'SO' => [ N("Somalia"),        'en_US', '3' ], #
'SR' => [ N("Suriname"),       'nl_NL', '5' ], #
'ST' => [ N("Sao Tome and Principe"), 'en_US', '5' ], #
'SV' => [ N("El Salvador"),    'es_SV', '5' ],
'SY' => [ N("Syria"),          'ar_SY', '2' ],
'SZ' => [ N("Swaziland"),      'en_BW', '3' ], #
'TC' => [ N("Turks and Caicos Islands"), 'en_US', '?' ], #
'TD' => [ N("Chad"),           'en_US', '3' ], #
'TF' => [ N("French Southern Territories"), 'fr_FR', '?' ], #
'TG' => [ N("Togo"),           'fr_FR', '3' ], #
'TH' => [ N("Thailand"),       'th_TH', '2' ],
'TJ' => [ N("Tajikistan"),     'tg_TJ', '2' ],
'TK' => [ N("Tokelau"),        'en_US', '?' ], #
'TL' => [ N("East Timor"),     'pt_PT', '4' ], #
'TM' => [ N("Turkmenistan"),   'en_US', '2' ], #
'TN' => [ N("Tunisia"),        'ar_TN', '5' ],
'TO' => [ N("Tonga"),          'en_US', '3' ], #
'TR' => [ N("Turkey"),         'tr_TR', '2' ],
'TT' => [ N("Trinidad and Tobago"), 'en_US', '5' ], #
'TV' => [ N("Tuvalu"),         'en_US', '?' ], #
'TW' => [ N("Taiwan"),         'zh_TW', '2' ],
'TZ' => [ N("Tanzania"),       'en_US', '3' ], #
'UA' => [ N("Ukraine"),        'uk_UA', '1' ],
'UG' => [ N("Uganda"),         'en_US', '3' ], #
'UM' => [ N("United States Minor Outlying Islands"), 'en_US', '?' ], #
'US' => [ N("United States"),  'en_US', '5' ],
'UY' => [ N("Uruguay"),        'es_UY', '5' ],
'UZ' => [ N("Uzbekistan"),     'uz_UZ', '2' ],
'VA' => [ N("Vatican"),       'it_IT', '1' ], #
'VC' => [ N("Saint Vincent and the Grenadines"), 'en_US', '5' ], 
'VE' => [ N("Venezuela"),      'es_VE', '5' ],
'VG' => [ N("Virgin Islands (British)"), 'en_GB', '5' ], #
'VI' => [ N("Virgin Islands (U.S.)"), 'en_US', '5' ], #
'VN' => [ N("Vietnam"),        'vi_VN', '2' ],
'VU' => [ N("Vanuatu"),        'en_US', '?' ], #
'WF' => [ N("Wallis and Futuna"), 'fr_FR', '4' ], #
'WS' => [ N("Samoa"),          'en_US', '4' ], #
'YE' => [ N("Yemen"),          'ar_YE', '2' ],
'YT' => [ N("Mayotte"),        'fr_FR', '?' ], #
'YU' => [ N("Serbia"),         'sp_YU', '1' ],
'ZA' => [ N("South Africa"),   'en_ZA', '5' ],
'ZM' => [ N("Zambia"),         'en_US', '3' ], #
'ZW' => [ N("Zimbabwe"),       'en_ZW', '5' ],
);
sub c2name   { exists $countries{$_[0]} && $countries{$_[0]}[0] }
sub c2locale { exists $countries{$_[0]} && $countries{$_[0]}[1] }
sub list_countries {
    my (%options) = @_;
    my @l = keys %countries;
    $options{exclude_non_installed} ? grep { -e "/usr/share/locale/".c2locale($_)."/LC_CTYPE" } @l : @l;
}

#- this list is built with 'cd /usr/share/i18n/locales ; echo ??_??'
#- plus sp_YU, eo_XX, mn_MN, lo_LA, ph_PH, en_BE
our @locales = qw(af_ZA am_ET ar_AE ar_BH ar_DZ ar_EG ar_IN ar_IQ ar_JO ar_KW ar_LB ar_LY ar_MA ar_OM ar_QA ar_SA ar_SD ar_SY ar_TN ar_YE az_AZ be_BY bg_BG bn_BD bn_IN br_FR bs_BA ca_ES cs_CZ cy_GB da_DK de_AT de_BE de_CH de_DE de_LU el_GR en_AU en_BW en_CA en_DK en_GB en_HK en_IE en_IN en_NZ en_PH en_SG en_US en_ZA en_ZW es_AR es_BO es_CL es_CO es_CR es_DO es_EC es_ES es_GT es_HN es_MX es_NI es_PA es_PE es_PR es_PY es_SV es_US es_UY es_VE et_EE eu_ES fa_IR fi_FI fo_FO fr_BE fr_CA fr_CH fr_FR fr_LU ga_IE gd_GB gl_ES gv_GB he_IL hi_IN hr_HR hu_HU hy_AM id_ID is_IS it_CH it_IT iw_IL ja_JP ka_GE kl_GL ko_KR kw_GB lt_LT lv_LV mi_NZ mk_MK mr_IN ms_MY mt_MT nl_BE nl_NL nn_NO no_NO oc_FR pl_PL pt_BR pt_PT ro_RO ru_RU ru_UA se_NO sk_SK sl_SI sq_AL sr_YU sv_FI sv_SE ta_IN te_IN tg_TJ th_TH ti_ER ti_ET tl_PH tr_TR tt_RU uk_UA ur_PK uz_UZ vi_VN wa_BE yi_US zh_CN zh_HK zh_SG zh_TW sp_YU eo_XX mn_MN lo_LA ph_PH en_BE);

sub standard_locale {
    my ($lang, $country, $utf8) = @_;
  retry:
    member("${lang}_${country}", @locales) and return "${lang}_${country}".($utf8 ? '.UTF-8' : '');
    length($lang) > 2 and $lang =~ s/^(..).*/$1/, goto retry;
}
    
sub getlocale_for_lang {
    my ($lang, $country, $utf8) = @_;
    standard_locale($lang, $country, $utf8) || l2locale($lang).($utf8 ? '.UTF-8' : '');
}

sub getlocale_for_country {
    my ($lang, $country, $utf8) = @_;
    standard_locale($lang, $country, $utf8) || c2locale($country).($utf8 ? '.UTF-8' : '');
}

sub getLANGUAGE {
    my ($lang, $country, $utf8) = @_;
    l2language($lang) || join(':', uniq(getlocale_for_lang($lang, $country, $utf8), $lang, if_($lang =~ /^(..)_/, $1)));
}

my %xim = (
  'zh_TW' => { 
 	ENC => 'big5',
 	XIM => 'xcin',
 	XIM_PROGRAM => 'xcin',
 	XMODIFIERS => '"@im=xcin"',
 	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'zh_TW.UTF-8' => {
	ENC => 'utf8',
	XIM => 'Chinput',
	XIM_PROGRAM => 'chinput',
	XMODIFIERS => '"@im=Chinput"',
	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'zh_CN' => {
	ENC => 'gb',
	XIM => 'Chinput',
	XIM_PROGRAM => 'chinput',
	XMODIFIERS => '"@im=Chinput"',
	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'zh_CN.UTF-8' => {
	ENC => 'utf8',
	XIM => 'Chinput',
	XIM_PROGRAM => 'chinput',
	XMODIFIERS => '"@im=Chinput"',
	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'ko_KR' => {
	ENC => 'kr',
	XIM => 'Ami',
	#- NOTE: there are several possible versions of ami, for the different
	#- desktops (kde, gnome, etc). So XIM_PROGRAM isn't defined; it will
	#- be the xinitrc script, XIM section, that will choose the right one 
	#- XIM_PROGRAM => 'ami',
	XMODIFIERS => '"@im=Ami"',
	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'ko_KR.UTF-8' => {
	ENC => 'utf8',
	XIM => 'Ami',
	#- NOTE: there are several possible versions of ami, for the different
	#- desktops (kde, gnome, etc). So XIM_PROGRAM isn't defined; it will
	#- be the xinitrc script, XIM section, that will choose the right one 
	#- XIM_PROGRAM => 'ami',
	XMODIFIERS => '"@im=Ami"',
	CONSOLE_NOT_LOCALIZED => 'yes',
  },
  'ja_JP' => {
	ENC => 'eucj',
	XIM => 'kinput2',
	XIM_PROGRAM => 'kinput2',
	XMODIFIERS => '"@im=kinput2"',
  },
  'ja_JP.UTF-8' => {
	ENC => 'utf8',
	XIM => 'kinput2',
	XIM_PROGRAM => 'kinput2',
	XMODIFIERS => '"@im=kinput2"',
  },
  #- XFree86 has an internal XIM for Thai that enables syntax checking etc.
  #- 'Passthroug' is no check at all, 'BasicCheck' accepts bad sequences
  #- and convert them to right ones, 'Strict' refuses bad sequences
  'th_TH' => {
	XIM_PROGRAM => '/bin/true', #- it's an internal module
	XMODIFIERS => '"@im=BasicCheck"',
  },
  #- xvnkb is not an XIM input method; but an input method of another
  #- kind, only XIM_PROGRAM needs to be defined
  #- ! xvnkb doesn't work in UTF-8 !
#-  'vi_VN.VISCII' => {
#-	XIM_PROGRAM => 'xvnkb',
#-  },
);

#- [0]: console font name
#- [1]: sfm map for console font (if needed)
#- [2]: acm file for console font (none if utf8)
#- [3]: iocharset param for mount (utf8 if utf8)
#- [4]: codepage parameter for mount (none if utf8)
my %charsets = (
#- chinese needs special console driver for text mode
"Big5"        => [ undef,         undef,   undef,           "big5",       "950" ],
"gb2312"      => [ undef,         undef,   undef,           "gb2312",     "936" ],
"C"           => [ "lat0-16",     undef,   "iso15",         "iso8859-1",  "850" ],
"iso-8859-1"  => [ "lat1-16",     undef,   "iso01",         "iso8859-1",  "850" ],
"iso-8859-2"  => [ "lat2-sun16",  undef,   "iso02",         "iso8859-2",  "852" ],
"iso-8859-5"  => [ "UniCyr_8x16", undef,   "iso05",         "iso8859-5",  "866" ],
"iso-8859-7"  => [ "iso07.f16",   undef,   "iso07",         "iso8859-7",  "869" ],
"iso-8859-9"  => [ "lat5u-16",    undef,   "iso09",         "iso8859-9",  "857" ],
"iso-8859-13" => [ "tlat7",       undef,   "iso13",         "iso8859-13", "775" ],
"iso-8859-15" => [ "lat0-16",     undef,   "iso15",         "iso8859-15", "850" ],
#- japanese needs special console driver for text mode [kon2]
"jisx0208"    => [ undef,         undef,   "trivial.trans", "euc-jp",     "932" ],
"koi8-r"      => [ "UniCyr_8x16", undef,   "koi8-r",        "koi8-r",     "866" ],
"koi8-u"      => [ "UniCyr_8x16", undef,   "koi8-u",        "koi8-u",     "866" ],
"cp1251"      => [ "UniCyr_8x16", undef,   "cp1251",        "cp1251",     "866" ],
#- korean needs special console driver for text mode
"ksc5601"     => [ undef,         undef,   undef,           "euc-kr",     "949" ],
#- I have no console font for Thai...
"tis620"      => [ undef,         undef,   "trivial.trans", "tis-620",    "874" ],
# UTF-8 encodings here; they differ in the console font mainly.
"utf_am"      => [ "Agafari-16",     undef,   undef,      "utf8",    undef ],
"utf_ar"      => [ "iso06.f16",      undef,   undef,      "utf8",    undef ],
"utf_az"      => [ "tiso09e",        undef,   undef,      "utf8",    undef ],
"utf_cyr1"    => [ "UniCyr_8x16",    undef,   undef,      "utf8",    undef ],
"utf_cyr2"    => [ "koi8-k",         undef,   undef,      "utf8",    undef ],
"utf_he"      => [ "iso08.f16",      undef,   undef,      "utf8",    undef ],
"utf_hy"      => [ "arm8",           undef,   undef,      "utf8",    undef ],
"utf_ka"      => [ "t_geors",        undef,   undef,      "utf8",    undef ],
"utf_ta"      => [ "tamil",          undef,   undef,      "utf8",    undef ],
"utf_vi"      => [ "tcvn8x16",       undef,   undef,      "utf8",    undef ],
"utf_lat8"    => [ "iso14.f16",      undef,   undef,      "utf8",    undef ],
# default for utf-8 encodings
"unicode"     => [ "LatArCyrHeb-16", undef,   undef,      "utf8",    undef ],
);

#- for special cases not handled magically
my %charset2kde_charset = (
    gb2312 => 'gb2312.1980-0',
    jisx0208 => 'jisx0208.1983-0',
    ksc5601 => 'ksc5601.1987-0',
    Big5 => 'big5-0',
    cp1251 => 'microsoft-cp1251',
    utf8 => 'iso10646-1',
    tis620 => 'tis620-0',
    #- Tamil KDE translations still use TSCII, and KDE know it as iso-8859-1
    utf_ta => 'iso8859-1',
);

my @during_install__lang_having_their_LC_CTYPE = qw(ja ko ta);


#- -------------------

sub list { 
    my (%options) = @_;
    my @l = list_langs();
    if ($options{exclude_non_installed_langs}) {
	@l = grep { -e "/usr/share/locale/$_/LC_CTYPE" } @l;
    }
    @l;
}

sub l2console_font {
    my ($locale) = @_;
    my $c = $charsets{l2charset($locale->{lang}) || return} or return;
    my ($name, $sfm, $acm) = @$c;
    undef $acm if $locale->{utf8};
    ($name, $sfm, $acm);
}

sub get_kde_lang {
    my ($locale, $default) = @_;

    #- get it using 
    #- echo C $(rpm -qp --qf "%{name}\n" /RPMS/kde-i18n-*  | sed 's/kde-i18n-//')
    my @valid_kde_langs = qw(C af ar az bg ca cs da de el en_GB eo es et fi fr he hu is it ja ko lt lv mt nb nl nn pl pt pt_BR ro ru sk sl sr sv ta th tr uk xh zh_CN.GB2312 zh_TW.Big5);
    my %valid_kde_langs; @valid_kde_langs{@valid_kde_langs} = ();

    my $valid_lang = sub {
	my ($lang) = @_;
	#- fast & dirty solution to ensure bad entries do not happen
	$lang eq 'en' ? 'C' :
	$lang eq 'en_US' ? 'C' :
	$lang eq 'no' ? 'nb' :
	$lang eq 'sp' ? 'sr' :
	$lang eq 'zh_CN' ? 'zh_CN.GB2312' :
	$lang eq 'zh_TW' ? 'zh_TW.Big5' :
	  exists $valid_kde_langs{$lang} ? $lang :
	  exists $valid_kde_langs{substr($lang, 0, 2)} ? substr($lang, 0, 2) : '';
    };

    my $r;
    $r ||= $valid_lang->($locale->{lang});
    $r ||= find { $valid_lang->($_) } split(':', getlocale_for_lang($locale->{lang}, $locale->{country}));
    $r || $default || 'C';
}

sub charset2kde_charset {
    my ($charset, $default) = @_;
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
    $r || $default || 'iso10646-1';
}

#- font+size for different charsets; the field [0] is the default,
#- others are overrridens for fixed(1), toolbar(2), menu(3) and taskbar(4)
my %charset2kde_font = (
  'C' => [ "adobe-helvetica,12", "courier,10", "adobe-helvetica,11" ],
  'iso-8859-1'  => [ "adobe-helvetica,12", "courier,10", "adobe-helvetica,11" ],
  'iso-8859-2'  => [ "adobe-helvetica,12", "courier,10", "adobe-helvetica,11" ],
  'iso-8859-9'  => [ "adobe-helvetica,12", "courier,10", "adobe-helvetica,11" ],
  'iso-8859-15' => [ "adobe-helvetica,12", "courier,10", "adobe-helvetica,11" ],
  'jisx0208' => [ "misc-fixed,14", "Kochi-Gothic,13" ],
  'ksc5601' => [ "daewoo-gothic,16" ],
  'gb2312' => [ "default-ming,16" ],
  'Big5' => [ "taipei-fixed,16" ],
  'tis620' => [ "misc-norasi,17", ],
  #- the following should be changed to better defaults when better fonts
  #- get available
  'utf_am' => [ "clearlyu,17" ],
  'utf_hy' => [ "clearlyu,17" ],
  'utf_ka' => [ "clearlyu,17" ],
  'utf_ta' => [ "TSCu_Paranar,14", "TSC_Avarangalfxd,10", "TSCu_Paranar,12", ],
  'utf_vi' => [ "misc-fixed,13", "misc-fixed,13", "misc-fixed,10", ],
  'default' => [ "misc-fixed,13", "misc-fixed,13", "misc-fixed,10", ],
);

sub charset2kde_font {
    my ($charset, $type) = @_;
    my $kdecharset = charset2kde_charset($charset);
    
    my $font = $charset2kde_font{$charset} || $charset2kde_font{default};
    my $r = $font->[$type] || $font->[0];

    #- the format is "font-name,size,5,kdecharset,0,0" I have no idea of the
    #- meaning of that "5"...
    "$r,5,$kdecharset,0,0";
}

# this define pango name fonts (like "NimbusSans L") depending
# on the "charset" defined by language array. This allows to selecting
# an appropriate font for each language.
my %charset2pango_font = (
  'tis620' =>      "Norasi",
  'utf_ar' =>      "KacstBook",
  'utf_cyr2' =>    "URW Bookman L",
  'utf_he' =>      "ClearlyU",
  'utf_hy' =>      "Artsounk",
  'utf_ka' =>      "ClearlyU",
  'utf_ta' =>      "TSCu_Paranar",
  'utf_vi' =>      "ClearlyU",
  'iso-8859-7' =>  "Kerkis",
  #- Nimbus Sans L is missing some chars used by some cyrillic languages,
  #- but tose haven't yet DrakX translations; it also misses vietnamese
  #- latin chars; all other latin and cyrillic are covered.
  'default' =>     "Nimbus Sans L"
);

sub charset2pango_font {
    my ($charset) = @_;
    
    $charset2pango_font{exists $charset2pango_font{$charset} ? $charset : 'default'};
}

sub l2pango_font {
    my ($lang) = @_;

    my $charset = l2charset($lang) or log::l("no charset found for lang $lang!"), return;
    my $font = charset2pango_font($charset);
    log::l("charset:$charset font:$font sfm:$charsets{$charset}[0]");

    if (common::usingRamdisk()) {
	if ($charsets{$charset}[0] !~ /lat|koi|UniCyr/) {
	    install_any::remove_bigseldom_used();
	    unlink glob_('/usr/share/langs/*');  #- remove langs images
	    my @generic_fontfiles = qw(/usr/X11R6/lib/X11/fonts/12x13mdk.pcf.gz /usr/X11R6/lib/X11/fonts/18x18mdk.pcf.gz);
	    #- need to unlink first because the files actually exist (and are void); they must exist
	    #- because if not, when gtk starts, pango will recompute its cache file and exclude them
	    unlink($_), install_any::getAndSaveFile($_) foreach @generic_fontfiles;
	}

	my %pango_modules = (arabic => 'ar|fa|ur', hangul => 'ko', hebrew => 'he|yi', indic => 'hi|bn|ta|te|mr', thai => 'th');
	foreach my $module (keys %pango_modules) {
	    next if $lang !~ /$pango_modules{$module}/;
	    install_any::remove_bigseldom_used();
	    my ($pango_modules_dir) = glob('/usr/lib/pango/*/modules');
	    install_any::getAndSaveFile("$pango_modules_dir/pango-$module-xft.so");
	}
    }
    
    return $font;
}

sub set {
    my ($lang, $translate_for_console) = @_;

    exists $langs{$lang} or log::l("lang::set: trying to set to $lang but I don't know it!"), return;

    my $dir = "$ENV{SHARE_PATH}/locale";
    if (!-e "$dir/$lang" && common::usingRamdisk()) {
	@ENV{qw(LANG LC_ALL LANGUAGE LINGUAS)} = ();

	my @LCs = qw(LC_ADDRESS LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME);
	
	my $charset = during_install__l2charset($lang) || $lang;
	
	#- there are 3 main charsets containing everything for all locales, except LC_CTYPE
	#- by default, there is UTF-8.
	#- when asked for GB2312 or BIG5, removing the other main charsets
	my $main_charset = member($charset, 'GB2312', 'BIG5') ? $charset : 'UTF-8';
	
	#- removing everything
	#- except in main charset: only removing LC_CTYPE if it is there
	eval { rm_rf($_ eq $main_charset ? "$dir/$_/LC_CTYPE" : "$dir/$_") } foreach all($dir);
	
	if (!-e "$dir/$main_charset") {
	    #- getting the main charset
	    mkdir "$dir/$main_charset";
	    mkdir "$dir/$main_charset/LC_MESSAGES";
	    install_any::getAndSaveFile("$dir/$main_charset/$_") foreach @LCs, 'LC_MESSAGES/SYS_LC_MESSAGES';
	}
	mkdir "$dir/$lang";
	
	#- linking to the main charset
	symlink "../$main_charset/$_", "$dir/$lang/$_" foreach @LCs, 'LC_MESSAGES';	    
	
	#- getting LC_CTYPE (putting it directly in $lang)
	install_any::getAndSaveFile("Mandrake/mdkinst$dir/$charset/LC_CTYPE", "$dir/$lang/LC_CTYPE");
    }
    
    #- set all LC_* variables to a unique locale ("C"), and only redefine
    #- LC_CTYPE (for X11 choosing the fontset) and LANGUAGE (for the po files)
    $ENV{$_} = 'C' foreach qw(LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION);
    
    $ENV{LC_CTYPE}    = $lang;
    $ENV{LC_MESSAGES} = $lang;
    $ENV{LANG}        = $lang;
    
    if ($translate_for_console && $lang =~ /^(ko|ja|zh|th)/) {
	log::l("not translating in console");
	$ENV{LANGUAGE}  = 'C';
    } else {
	$ENV{LANGUAGE}  = getLANGUAGE($lang);
    }
    load_mo();
    $lang;
}

sub langs {
    my ($l) = @_;
    $l->{all} ? list_langs() : grep { $l->{$_} } keys %$l;
}

sub langsLANGUAGE {
    my ($l, $c) = @_;
    uniq(map { split ':', getLANGUAGE($_, $c) } langs($l));
}

sub pack_langs { 
    my ($l) = @_; 
    my $s = $l->{all} ? 'all' : join ':', uniq(map { getLANGUAGE($_) } langs($l));
    $ENV{RPM_INSTALL_LANG} = $s;
    $s;
}

sub system_locales_to_ourlocale {
    my ($locale_lang, $locale_country) = @_;
    my $locale;
    if (member($locale_lang, list_langs())) {
	#- special lang's such as en_US pt_BR
	$locale->{lang} = $locale_lang;
    } else {
	($locale->{lang}) = $locale_lang =~ /^(..)/;
    }
    ($locale->{country}) = $locale_country =~ /^.._(..)/;
    $locale->{utf8} = $locale_lang =~ /UTF-8/;
    #- safe fallbacks
    $locale->{lang} ||= 'en_US';
    $locale->{country} ||= 'US';
    $locale;
}

sub read {
    my ($prefix, $user_only) = @_;
    my ($f1, $f2) = ("$prefix$ENV{HOME}/.i18n", "$prefix/etc/sysconfig/i18n");
    my %h = getVarsFromSh($user_only && -e $f1 ? $f1 : $f2);
    system_locales_to_ourlocale($h{LC_MESSAGES} || 'en_US', $h{LC_MONETARY} || 'en_US');
}

sub write_langs {
    my ($prefix, $langs) = @_;
    my $s = pack_langs($langs);
    symlink "$prefix/etc/rpm", "/etc/rpm" if $prefix;
    substInFile { s/%_install_langs.*//; $_ .= "%_install_langs $s\n" if eof && $s } "$prefix/etc/rpm/macros";
}

sub write { 
    my ($prefix, $locale, $user_only, $dont_touch_kde_files) = @_;

    $locale && $locale->{lang} or return;

    $locale->{utf8} ||= l2charset($locale->{lang}) =~ /utf|unicode/
			|| any { l2charset($_) ne l2charset($locale->{lang}) } langs($locale->{langs});
    my $locale_lang = getlocale_for_lang($locale->{lang}, $locale->{country}, $locale->{utf8});
    my $locale_country = getlocale_for_country($locale->{lang}, $locale->{country}, $locale->{utf8});

    my $h = {
	XKB_IN_USE => '',
	(map { $_ => $locale_lang } qw(LANG LC_COLLATE LC_CTYPE LC_MESSAGES LC_TIME)),
	LANGUAGE => getLANGUAGE($locale->{lang}, $locale->{country}, $locale->{utf8}),
	(map { $_ => $locale_country } qw(LC_NUMERIC LC_MONETARY LC_ADDRESS LC_MEASUREMENT LC_NAME LC_PAPER LC_IDENTIFICATION LC_TELEPHONE))
    };
    log::l("lang::write: lang:$locale->{lang} country:$locale->{country} locale|lang:$locale_lang locale|country:$locale_country language:$h->{LANGUAGE}");

    my ($name, $sfm, $acm) = l2console_font($locale);
    if ($name && !$user_only) {
	my $p = "$prefix/usr/lib/kbd";
	if ($name) {
	    eval {
		cp_af("$p/consolefonts/$name.psf.gz", "$prefix/etc/sysconfig/console/consolefonts");
		add2hash $h, { SYSFONT => $name };
	    };
	    $@ and log::l("missing console font $name");
	}
	if ($sfm) {
	    eval {
		cp_af(glob_("$p/consoletrans/$sfm*"), "$prefix/etc/sysconfig/console/consoletrans");
		add2hash $h, { UNIMAP => $sfm };
	    };
	    $@ and log::l("missing console unimap file $sfm");
	}
	if ($acm) {
	    eval {
		cp_af(glob_("$p/consoletrans/$acm*"), "$prefix/etc/sysconfig/console/consoletrans");
		add2hash $h, { SYSFONTACM => $acm };
	    };
	    $@ and log::l("missing console acm file $acm");
	}
	
    }
    add2hash $h, $xim{$locale_lang};

    setVarsInSh($prefix . ($user_only ? "$ENV{HOME}/.i18n" : '/etc/sysconfig/i18n'), $h);

    eval {
	my $charset = l2charset($locale->{lang});
	my $confdir = $prefix . ($user_only ? "$ENV{HOME}/.kde" : '/usr') . '/share/config';
	my ($prev_kde_charset) = cat_("$confdir/kdeglobals") =~ /^Charset=(.*)/mi;

	mkdir_p($confdir);

	update_gnomekderc("$confdir/kdeglobals", Locale => (
			      Charset => charset2kde_charset($charset),
			      Country => lc($locale->{country}),
			      Language => get_kde_lang($locale),
			  ));

        if ($prev_kde_charset ne charset2kde_charset($charset)) {
	    update_gnomekderc("$confdir/kdeglobals", WM => (
	    		      activeFont => charset2kde_font($charset,0),
	    		  ));
	    update_gnomekderc("$confdir/kdeglobals", General => (
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
    } if !$dont_touch_kde_files;
}

sub bindtextdomain() {
    my $localedir = "$ENV{SHARE_PATH}/locale";
    $localedir .= "_special" if $::isInstall;

    c::setlocale();
    c::bind_textdomain_codeset('libDrakX', 'UTF-8');
    $::need_utf8_i18n = 1;
    c::bindtextdomain('libDrakX', $localedir);

    $localedir;
}

sub load_mo {
    my ($lang) = @_;

    my $localedir = bindtextdomain();
    my $suffix = 'LC_MESSAGES/libDrakX.mo';

    $lang ||= $ENV{LANGUAGE} || $ENV{LC_ALL} || $ENV{LC_MESSAGES} || $ENV{LANG};

    foreach (split ':', $lang) {
	my $f = "$localedir/$_/$suffix";
	-s $f and return $_;

	if ($::isInstall && common::usingRamdisk()) {
	    #- cleanup
	    eval { rm_rf($localedir) };
	    eval { mkdir_p(dirname("$localedir/$_/$suffix")) };
	    install_any::getAndSaveFile("$localedir/$_/$suffix");

	    -s $f and return $_;
	}
    }
    '';
}


#- used in Makefile during "make get_needed_files"
sub console_font_files {
    map { -e $_ ? $_ : "$_.gz" }
      (map { "/usr/lib/kbd/consolefonts/$_.psf" } uniq grep { $_ } map { $_->[0] } values %charsets),
      (map { -e $_ ? $_ : "$_.sfm" } map { "/usr/lib/kbd/consoletrans/$_" } uniq grep { $_ } map { $_->[1] } values %charsets),
      (map { -e $_ ? $_ : "$_.acm" } map { "/usr/lib/kbd/consoletrans/$_" } uniq grep { $_ } map { $_->[2] } values %charsets),
}

sub load_console_font {
    my ($locale) = @_;
    my ($name, $sfm, $acm) = l2console_font($locale);

    require run_program;
    run_program::run(if_($ENV{LD_LOADER}, $ENV{LD_LOADER}), 
		     'consolechars', '-v', '-f', $name || 'lat0-sun16',
		     if_($sfm, '-u', $sfm), if_($acm, '-m', $acm));

    #- in console mode install, ensure we'll get translations in the right codeset
    #- (charset of locales reported by the glibc are UTF-8 during install)
    if ($acm) {
	c::bind_textdomain_codeset('libDrakX', l2charset($locale->{lang}));
	$::need_utf8_i18n = 0;
    }
}

sub fs_options {
    my ($locale) = @_;
    if ($locale->{utf8}) {
	('utf8', undef);
    } else {
	my $c = $charsets{l2charset($locale->{lang}) || return} or return;
	my ($iocharset, $codepage) = @$c[3..4];
	$iocharset, $codepage;
    }
}

sub during_install__l2charset {
    my ($lang) = @_;
    return if member($lang, @during_install__lang_having_their_LC_CTYPE);

    my ($c) = l2charset($lang) or die "bad lang $lang\n";
    $c = 'UTF-8' if member($c, 'tis620', 'C');
    $c = 'UTF-8' if $c =~ /koi8-/;
    $c = 'UTF-8' if $c =~ /iso-8859/;
    $c = 'UTF-8' if $c =~ /cp125/;
    $c = 'UTF-8' if $c =~ /utf_/;
    uc($c);
}


sub check {
    $^W = 0;
    my $ok = 1;
    my $warn = sub {
	print STDERR "$_[0]\n";
    };
    my $err = sub {
	&$warn;
	$ok = 0;
    };
    
    my @wanted_charsets = uniq map { l2charset($_) } list_langs();
    $err->("invalid charset $_ ($_ does not exist in \%charsets)") foreach difference2(\@wanted_charsets, [ keys %charsets ]);
    $err->("invalid charset $_ in \%charset2kde_font ($_ does not exist in \%charsets)") foreach difference2([ keys %charset2kde_font ], [ 'default', keys %charsets ]);
    $warn->("unused charset $_ (given in \%charsets, but not used in \%langs)") foreach difference2([ keys %charsets ], \@wanted_charsets);

    $warn->("unused entry $_ in \%xim") foreach grep { !/UTF-8/ } difference2([ keys %xim ], [ map { l2locale($_) } list_langs() ]);

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

    $err->("default locale $_->[1] of lang $_->[0] isn't listed in \@locales")
      foreach grep { !member($_->[1], @locales) } map { [ $_, l2locale($_) ] } list_langs();

    $err->("default locale $_->[1] of country $_->[0] isn't listed in \@locales")
      foreach grep { !member($_->[1], @locales) } map { [ $_, c2locale($_) ] } list_countries();

    $warn->("no country corresponding to default locale $_->[1] of lang $_->[0]")
      foreach grep { $_->[1] =~ /^.._(..)/ && !exists $countries{$1} } map { [ $_, l2locale($_) ] } list_langs();

    exit($ok ? 0 : 1);
}

1;
