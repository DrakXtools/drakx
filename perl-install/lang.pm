package lang;

use diagnostics;
use strict;
use common;
use utf8;
use log;
use services;
use bootloader;

=head1 SYNOPSYS

B<lang> enables to manipulate the system or the user locale settings.

=head1 Data structures & functions

=head2 Languages

=over

=item our %lang

The key is the  lang name (locale name for some (~5) special cases needing
extra distinctions)

The fields are:

=over 4

=item 0 lang name in English

=item 1 transliterated locale name in the locale name (used for sorting)

=item 2 default locale name to use for that language if there is not
an existing locale for the combination language+country chosen

=item 3 geographic groups that this language belongs to (for displaying
in the menu grouped in smaller lists):

=over 4

=item 1=Europe,

=item 2=Asia,

=item 3=Africa,

=item 4=Oceania & Pacific,

=item 5=America

=back

If you wonder, it's the order used in the Olympic flag...

=item 4 special value for LANGUAGE variable (if different of the default
of 'll_CC:ll_DD:ll' (ll_CC: locale (if exist) resulting of the
combination of chosen lang (ll) and country (CC), ll_DD: the
default locale shown here (field [2]) and ll: the language (the key))

=back

Example:

  C<< 'fr' => [ 'French', 'Francais', 'fr_FR', '1 345', 'iso-8859-15' ], >>

=cut

our %langs = (
'af' =>    [ 'Afrikaans',           'Afrikaans',         'af_ZA', '  3  ', 'iso-8859-1' ],
'am' =>    [ 'Amharic',             'ZZ emarNa',         'am_ET', '  3  ', 'utf_ethi' ],
'ar' =>    [ 'Arabic',              'AA Arabic',         'ar_EG', ' 23  ', 'utf_ar' ],
'as' =>    [ 'Assamese',            'ZZ Assamese',       'as_IN', ' 2   ', 'utf_beng' ],
'ast' =>   [ 'Asturian',            'Asturianu',         'ast_ES', ' 1   ', 'unicode' ],
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
'en_ZA' => [ 'English (South Africa)', 'English (ZA)',   'en_ZA', '   3 ', 'iso-8859-1', 'en_ZA:en_GB:en' ],
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
'my' =>    [ 'Burmese',             'ZZ Bamaca',         'my', ' 2   ', 'utf_mymr', 'my_MM:my' ],
'nb' =>    [ 'Norwegian Bokmaal',   'Norsk, Bokmal',     'nb_NO', '1    ', 'iso-8859-15',  'nb:no' ],
'nds' =>   [ 'Low Saxon',           'Platduutsch',       'nds_DE', '1    ', 'utf_lat1', 'nds_DE:nds' ],
'ne' =>    [ 'Nepali',              'ZZ Nepali',         'ne_NP', ' 2   ', 'utf_deva' ],
'nl' =>    [ 'Dutch',               'Nederlands',        'nl_NL', '1    ', 'iso-8859-15' ],
'nn' =>    [ 'Norwegian Nynorsk',   'Norsk, Nynorsk',    'nn_NO', '1    ', 'iso-8859-15',  'nn:no@nynorsk:no_NY:no:nb' ],
'nr' =>    [ 'Ndebele',             'Ndebele',        'nr_ZA', '  3  ', 'utf_lat1', 'nr:en_ZA' ],
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
#- fallback, if "sr@Latn" is not there but a "sr" (which uses cyrillic)
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
'uz' => [ 'Uzbek',     'Ozbekcha',          'uz_UZ', ' 2   ', 'utf_cyr2', 'uz' ],
 'uz@cyrillic' =>    [ 'Uzbek (cyrillic)',    'Ozbekcha',          'uz_UZ@cyrillic', ' 2   ', 'utf_cyr2', 'uz@cyrillic' ],
've' =>    [ 'Venda',               'Tshivenda',         've_ZA', '  3  ', 'utf_lat1', 've:ven:en_ZA' ],
'vi' =>    [ 'Vietnamese',          'Tieng Viet',        'vi_VN', ' 2   ', 'utf_vi' ],
'wa' =>    [ 'Walon',               'Walon',             'wa_BE', '1    ', 'utf_lat1', 'wa:fr_BE:fr' ],
#- locale "wen_DE" not done yet, using "de_DE" instead
#- wen disabled until we have a perl-install/pixmaps/langs/lang-wen.png for it
#'wen' =>   [ 'Sorbian',             'Sorbian',           'de_DE', '1    ', 'utf_lat1', 'wen' ],
'xh' =>    [ 'Xhosa',               'Xhosa',          'xh_ZA', '  3  ', 'utf_lat1', 'xh:en_ZA' ],
'yi' =>    [ 'Yiddish',             'AA Yidish',         'yi_US', '1    ', 'utf_he' ],
'yo' =>    [ 'Yoruba',              'Yoruba',            'yo_NG', '  3  ', 'utf_yo', 'yo:en_NG' ],
'zh_CN' => [ 'Chinese Simplified',  'ZZ ZhongWen',       'zh_CN', ' 2   ', 'gb2312',      'zh_CN.GBK:zh_CN.GB2312:zh_CN:zh' ],
'zh_TW' => [ 'Chinese Traditional', 'ZZ ZhongWen',       'zh_TW', ' 2   ', 'Big5',        'zh_TW.Big5:zh_TW:zh_HK:zh' ],
'zu' =>    [ 'Zulu',                 'Zulu',          'zu_ZA', '  3  ', 'utf_lat1', 'xh:en_ZA' ],
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

sub is_locale_installed {
    my ($locale) = @_;
    my @ctypes = glob "/usr/share/locale/" . $locale . "{,.*}/LC_CTYPE";
    foreach my $ctype (@ctypes) { -e $ctype && return 1 }
    0;
}

sub list_langs {
    my (%options) = @_;
    my @l = keys %langs;
    $options{exclude_non_installed} ? grep { is_locale_installed(l2locale($_)) } @l : @l;
}

sub text_direction_rtl() {
#-PO: the string "default:LTR" can be translated *ONLY* as "default:LTR"
#-PO: or as "default:RTL", depending if your language is written from
#-PO: left to right, or from right to left; any other string is wrong.
       	N("default:LTR") eq "default:RTL";
}

=back

=head2 Countries

=over

=item my %countries;

The key is the ISO 639-1 country name code (that should be YY in xx_YY locale).

The fields are:

=over 4

=item 0: country name in natural language

=item 1: default locale for that country

=item 2: geographic groups that this country belongs to (for displaying
in the menu grouped in smaller lists):

=over 4

=item *1=Europe,

=item *2=Asia,

=item *3=Africa,

=item 4=Oceania & Pacific,

=item 5=America

=back

If you wonder, it's the order used in the Olympic flag.

=back

Note: for countries for which a glibc locale do not exist (yet) I tried to
put a locale that makes sense; and a '#' at the end of the line to show
the locale is not the "correct" one. 'en_US' is used when no good choice
is available.

Example:

   C<< 'FR' => [ N_("France"), 'fr_FR', '1' ], >>

=cut

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

=item c2name($country_code)

Returns the translated name for $country_code.

=cut

sub c2name   { exists $countries{$_[0]} && translate($countries{$_[0]}[0]) }

=item c2locale($country_code)

Returns default locale for that $country_code.

=cut

sub c2locale { exists $countries{$_[0]} && $countries{$_[0]}[1] }

=item list_countries()

Returns the full list of countries.

=cut

sub list_countries() {
    keys %countries;
}

=back

=head2 Locales

=over

=item our @locales;

The list of locales supported by glibc.

=cut

#- this list is built with the following command:
#- urpmf LC_CTYPE | egrep '/usr/share/locale/[a-z]' | cut -d'/' -f5 | sed 's/\.\(UTF-8\|ARM\|EUC\|GB.\|ISO\|KOI\|TCVN\).*\|\@\(euro\|iqtelif.*\)//' | sort -u | tr '\n' ' ';echo
our @locales = qw(aa_DJ aa_ER aa_ER@saaho aa_ET af_ZA ak_GH am_ET an_ES anp_IN ar_AE ar_BH ar_DZ ar_EG ar_IN ar_IQ ar_JO ar_KW ar_LB ar_LY ar_MA ar_OM ar_QA ar_SA ar_SD ar_SS ar_SY ar_TN ar_YE as_IN ast_ES ayc_PE az_AZ be_BY be_BY@latin bem_ZM ber_DZ ber_MA bg_BG bho_IN bn_BD bn_IN bo_CN bo_IN br_FR brx_IN bs_BA byn_ER ca_AD ca_ES ca_FR ca_IT cmn_TW crh_UA csb_PL cs_CZ cv_RU cy_GB da_DK de_AT de_BE de_CH de_DE de_LU doi_IN dv_MV dz_BT el_CY el_GR en_AG en_AU en_BE en_BW en_CA en_DK en_GB en_HK en_IE en_IN en_NG en_NZ en_PH en_SG en_US en_ZA en_ZM en_ZW eo_XX es_AR es_BO es_CL es_CO es_CR es_CU es_DO es_EC es_ES es_GT es_HN es_MX es_NI es_PA es_PE es_PR es_PY es_SV es@tradicional es_US es_UY es_VE et_EE eu_ES fa_IR ff_SN fi_FI fil_PH fo_FO fr_BE fr_CA fr_CH fr_FR fr_LU fur_IT fy_DE fy_NL ga_IE gd_GB gez_ER gez_ER@abegede gez_ET gez_ET@abegede gl_ES gu_IN gv_GB hak_TW ha_NG he_IL hi_IN hne_IN hr_HR hsb_DE ht_HT hu_HU hy_AM ia_FR id_ID ig_NG ik_CA is_IS it_CH it_IT iu_CA iw_IL ja_JP ka_GE kk_KZ kl_GL km_KH kn_IN kok_IN ko_KR ks_IN ks_IN@devanagari ku_TR kw_GB ky_KG lb_LU lg_UG li_BE lij_IT li_NL lo_LA lt_LT lv_LV lzh_TW mag_IN mai_IN mg_MG mhr_RU mi_NZ mk_MK ml_IN mni_IN mn_MN mr_IN ms_MY mt_MT my my_MM nan_TW nan_TW@latin nb_NO nds_DE nds_DE@traditional nds_NL ne_NP nhn_MX niu_NU niu_NZ nl_AW nl_BE nl_NL nn_NO nr_ZA nso_ZA oc_FR om_ET om_KE or_IN os_RU pa_IN pap_AN pap_AW pap_CW pa_PK pl_PL ps_AF pt_BR pt_PT quz_PE ro_RO ru_RU ru_UA rw_RW sa_IN sat_IN sc_IT sd_IN sd_IN@devanagari se_NO shs_CA sid_ET si_LK sk_SK sl_SI so_DJ so_ET so_KE so_SO sq_AL sq_MK sr_ME sr_CS sr_RS sr_RS@latin ss_ZA st_ZA sv_FI sv_SE sw_KE sw_TZ sw_XX szl_PL ta_IN ta_LK te_IN tg_TJ the_NP th_TH ti_ER ti_ET tig_ER tk_TM tl_PH tn_ZA tr_CY tr_TR ts_ZA tt_RU ug_CN uk_UA unm_US ur_IN ur_PK uz_UZ uz_UZ@cyrillic ve_ZA vi_VN wa_BE wae_CH wal_ET wo_SN xh_ZA yi_US yo_NG yue_HK zh_CN zh_HK zh_SG zh_TW zu_ZA);

# (cg) Taken from systemd/src/locale/localed.c
my @locale_conf_fields = qw(LANG LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION);

sub standard_locale {
    my ($lang, $country, $prefer_lang) = @_;

    my $lang_ = force_lang_country($lang, $country);
    if (member($lang_, @locales)) {
	$lang_;
    } elsif ($prefer_lang && member($lang, @locales)) {
	$lang;
    } else {
	'';
    }
}

sub force_lang_country {
    my ($lang, $country) = @_;
    my $h = analyse_locale_name($lang);
    $h->{country} = $country;
    analysed_to_lang($h);
}

sub force_lang_charset {
    my ($lang, $charset) = @_;
    my $h = analyse_locale_name($lang);
    $h->{charset} = $charset;
    analysed_to_lang($h);
}

=item analysed_to_lang($h)

The reverse of analyse_locale_name($lang), it takes a hash ref and returns
the standard ll_CC.cc@VV

=cut

sub analysed_to_lang {
    my ($h) = @_;
    $h->{main} . '_' . $h->{country} . 
      ($h->{charset} ? '.' . $h->{charset} : '') .
      ($h->{variant} ? '@' . $h->{variant} : '');
}

=item analyse_locale_name($lang)

Analyse a ll_CC.cc@VV locale and return a hash ref containing:

=over 4

=item * main (langage code)

=item * country code

=item * charset

=item * variant

=back

=cut

sub analyse_locale_name {
    my ($lang) = @_;
    $lang =~ /^(.*?) (?:_(.*?))? (?:\.(.*?))? (?:\@(.*?))? $/x &&
      { main => $1, country => $2, charset => $3, variant => $4 };
}

=item locale_to_main_locale($lang)

=cut

=item locale_to_main_locale($lang)

Returns the locale code from a ll_LL representation.

=cut

sub locale_to_main_locale {
    my ($lang) = @_;
    lc(analyse_locale_name($lang)->{main});
}

sub getlocale_for_lang {
    my ($lang, $country, $o_utf8) = @_;
    force_lang_charset(standard_locale($lang, $country, 'prefer_lang') || l2locale($lang), $o_utf8 && 'UTF-8');
}

sub getlocale_for_country {
    my ($lang, $country, $o_utf8) = @_;
    force_lang_charset(standard_locale($lang, $country, '') || c2locale($country), $o_utf8 && 'UTF-8');
}

sub getLANGUAGE {
    my ($lang, $o_country, $o_utf8) = @_;
    l2language($lang) || join(':', uniq(getlocale_for_lang($lang, $o_country, $o_utf8), 
					$lang, 
					locale_to_main_locale($lang)));
}

sub countries_to_locales {
    my (%options) = @_;

    my %country2locales;
    my $may_add = sub {
	my ($locale, $country) = @_;
	if ($options{exclude_non_installed}) {
	    is_locale_installed($locale) or return;
	}
	my $h = analyse_locale_name($locale) or internal_error();
	push @{$country2locales{$country || $h->{country}}}, $h;
    };

    # first add all real locales
    foreach (@locales) {
	$may_add->($_, undef);
    }
    # then add countries XX for which we use locale yy_ZZ and not yy_XX
    foreach my $country (list_countries()) {
	$may_add->(c2locale($country), $country);
    }
    \%country2locales;
}

#-------------------------------------------------------------
=back

=head2 Input Methods (IM)

Various hash tables enables to configure IMs.

=over

=item my @IM_i18n_fields;

This set generic IM fields:

=over 4

=item * B<XMODIFIERS>: is the environnement variable used by the X11 XIM protocol
it is of the form XIMODIFIERS="@im=foo"

=item * B<XIM>: is used by some programs, it usually is the like XIMODIFIERS
with the "@im=" part stripped

=item * B<GTK_IM_MODULE>: the module to use for Gtk programs ("xim" to use an X11
XIM server; or a a native gtk module if exists)

=item * B<XIM_PROGRAM>: the XIM program to run (usually the same as XIM value, but
in some cases different, particularly if parameters are needed;

=item * B<QT_IM_MODULE>: the module to use for Qt programs ("xim" to use an X11
XIM server; or a Qt plugin if exists)

=back

=cut

my @IM_i18n_fields = qw(XMODIFIERS XIM GTK_IM_MODULE XIM_PROGRAM QT_IM_MODULE);

my $is_plasma;

=item my %IM_config;

In order to configure an IM, one has to put generic configuration here.
Fields are :

=over 4

=item * B<GTK_IM_MODULE>: the Gtk+ IM module to use

=item * B<QT_IM_MODULE>: the Qt IM module to use

=item * B<XIM>: 

=item * B<XIM_PROGRAM>: the XIM program to use

=item * B<XMODIFIERS>: the X Modifiers (see X11 config), eg: C<'@im=gcin'>,

See above for those 5 parameters.

=item * B<default_for_lang>: the language codes for which it's the default IM
=item * B<langs>: 'zh',

=item * B<packages:> a hash ref that contains subroutine references:

=over 4

=item * B<generic>: packages that must be installed for all languages

=item * B<common>: packages that are shared between per language & generic packages

=item * eventually several B<code_lang> returning per language packages

=back

The I<packages> field must be kept in sync with meta-task's C<rpmsrate-raw>, especially for the per language package selection!

The actual packages list will consist of:

=over 4

=item * either per language package list or I<generic> list

=item * plus the packages returned by I<common>

=back

=back

=cut

my %IM_config =
  (
#   chinput => {
#               GTK_IM_MODULE => 'xim',
#               XIM => 'chinput',
#               XMODIFIERS => '@im=Chinput',
#	       XIM_PROGRAM => {
#		   'zh_CN' => 'chinput -gb',
#		   'en_SG' => 'chinput -gb',
#		   'zh_HK' => 'chinput -big5',
#		   'zh_TW' => 'chinput -big5',
#	       },	       
#	       langs => 'zh',
#	       packages => { generic => sub { 'miniChinput' } },
#              },
   fcitx => {
             GTK_IM_MODULE => 'fcitx',
             XIM => 'fcitx',
             XIM_PROGRAM => 'fcitx',
             XMODIFIERS => '@im=fcitx',
	     langs => 'zh',
	     packages => {
		     common => sub { if_($is_plasma, 'fcitx-qt5') },
		     generic => sub { qw(fcitx) },
	     },
            },
   gcin => {
             GTK_IM_MODULE => 'gcin',
             XIM => 'gcin',
             XIM_PROGRAM => 'gcin',
             XMODIFIERS => '@im=gcin',
	     langs => 'zh',
	     packages => {
		     common => sub { if_($is_plasma, 'gcin-qt5') },
		     generic => sub { qw(gcin) },
	     },
            },
   hime => {
             GTK_IM_MODULE => 'hime',
             XIM => 'hime',
             XIM_PROGRAM => 'hime',
             XMODIFIERS => '@im=hime',
	     langs => 'zh',
	     packages => {
		     common => sub { if_($is_plasma, 'hime-qt5') },
		     generic => sub { qw(hime) },
	     },
            },
   'im-ja' => {
               GTK_IM_MODULE => 'im-ja',
               QT_IM_MODULE => 'xim',
               XIM => 'im-ja-xim-server',
               XIM_PROGRAM => 'im-ja-xim-server',
               XMODIFIERS => '@im=im-ja-xim-server',
	       langs => 'ja',
              },

#   kinput2 => {   
#               GTK_IM_MODULE => 'xim',
#               XIM => 'kinput2',
#               XIM_PROGRAM => 'kinput2',
#               XMODIFIERS => '@im=kinput2',
#	       langs => 'ja',
#	       packages => { generic => sub { 'kinput2-wnn' } },
#              },
   nabi => {
            GTK_IM_MODULE => 'xim',
            XIM => 'nabi',
            XIM_PROGRAM => 'nabi',
            XMODIFIERS => '@im=nabi',
	    langs => 'ko',
           },

#   oxim => {
#       GTK_IM_MODULE => 'oxim',
#       XIM => 'oxim',
#       XIM_PROGRAM => 'oxim',
#       XMODIFIERS => '@im=oxim', # '@im=SCIM' is broken for now
#       langs => 'zh_TW',
#       packages => { generic => sub { 'oxim' } },
#   },
   'scim' => {
            GTK_IM_MODULE => 'scim',
	    QT_IM_MODULE => 'xim',
            XIM_PROGRAM => 'scim -d',
            XMODIFIERS => '@im=SCIM',
	    packages => {
		generic => sub { qw(scim-m17n scim-tables) },
		am => sub { qw(scim-tables) },
		ja => sub { qw(scim-anthy) },
		ko => sub { qw(scim-hangul) },
		th => sub { qw(scim-thai) },
		vi => sub { qw(scim-m17n) },
		zh => sub { qw(scim-tables-zh scim-chewing) },
	    },
           },

   'scim-bridge' => {
       GTK_IM_MODULE => 'scim-bridge',
       XIM_PROGRAM => 'scim-bridge',
       XMODIFIERS => '@im=SCIM',
       packages => {
           generic => sub { qw(scim-m17n scim-tables) },
           am => sub { qw(scim-tables) },
           ja => sub { qw(scim-anthy) },
           ko => sub { qw(scim-hangul) },
	   th => sub { qw(scim-thai) },
           vi => sub { qw(scim-m17n) },
           zh => sub { qw(scim-tables-zh scim-chewing) },
       },
   },
   'ibus' => {
	GTK_IM_MODULE => 'ibus',
	QT_IM_MODULE => 'ibus',
	XIM_PROGRAM => 'ibus-daemon -d -x',
	XMODIFIERS => '@im=ibus',
	default_for_lang => 'am ja ko th vi zh_CN zh_TW',
	packages => {
		generic => sub { qw(ibus-table ibus-m17n) },
		ja => sub { qw(ibus-mozc) },
		zh => sub { qw(ibus-libpinyin ibus-chewing) },
		ko => sub { qw(ibus-hangul) },
	},
   },
   uim => {
           GTK_IM_MODULE => 'uim',
           XIM => 'uim',
           XIM_PROGRAM => 'uim-xim',
           XMODIFIERS => '@im=uim',
	   langs => 'ja',
	   packages => {
		  generic => sub { qw(uim-gtk uim) },
	  },
          },
#   xcin => {
#            XIM => 'xcin',
#            XIM_PROGRAM => 'xcin',
#            XMODIFIERS => '@im=xcin-zh_TW',
#            GTK_IM_MODULE => 'xim',
#	    langs => 'zh',
#           },
   'x-unikey' => {
                  GTK_IM_MODULE => 'xim',
                  XMODIFIERS => '@im=unikey',
		  langs => 'vi',
                 },
);

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


=item get_ims ($lang)

Returns the IMs that are usable for $lang.

=cut

sub get_ims { 
    my ($lang) = @_;
    my $main_lang = analyse_locale_name($lang)->{main};

    sort grep {
	my $langs = $IM_config{$_}{langs};
	!$langs || intersection([ $lang, $main_lang ], 
				[ split(' ', $langs) ]);
    } keys %IM_config;
}          

=item get_default_im ($lang)

Returns the default IM to use for $lang.

=cut

sub get_default_im {
    my ($lang) = @_;
    find { 
	member($lang, split(' ', $IM_config{$_}{default_for_lang}));
    } keys %IM_config;
}

=item IM2packages ($locale)

Returns the packages to use for $locale if it's set to use an IM

=cut

sub IM2packages {
    my ($locale) = @_;
    if ($locale->{IM}) {
	require any;
	my @sessions = any::sessions();
	$is_plasma = any { /plasma/ } @sessions;
	my $per_lang = $IM_config{$locale->{IM}}{packages} || {};
	my $main_lang = analyse_locale_name($locale->{lang})->{main};
	my $packages = $per_lang->{$main_lang} || $per_lang->{generic};
	my @pkgs = ($packages ? $packages->() : $locale->{IM},
		    $per_lang->{common} ? $per_lang->{common}->() : ());
	@pkgs;
    } else { () }
}

=back

=head2 Charsets

=over

=item my %charsets;

Key is encoding. Fields are:

=over 4

=item 0: console font name

=item 1: unused

=item 2: console map (none if utf8)

=item 3: iocharset param for mount (utf8 if utf8)

=item 4: codepage parameter for mount (none if utf8)

=back

=cut

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

=item my %charset2kde_charset;

For special cases not handled magically

=cut

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

=item l2console_font ($locale, $during_install)

Returns console font name & console map (none if utf8 and if not during install);

=cut

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
    #- echo C $(rpm -qp --qf "%{name}\n" /RPMS/kde4-l10n-*  | sed 's/kde4-l10n-//')
    my @valid_kde_langs = qw(C
ar be bg ca cs csb da de el en_GB eo es et eu fa fi fr fy ga gl hi hu is it ja kk km ko ku lt lv mk ml nb nds ne nl nn pa pl pt pt_BR ro ru se sl sr sv ta th tr uk wa zh_CN zh_TW);
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

=item my %charset2kde_font;

Font+size for different charsets; the field [0] is the default,
others are overrridens for fixed(1), toolbar(2), menu(3) and taskbar(4)

This is needed because KDE historically doesn't use fontconfig...

=cut

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

=item my %charset2pango_font;

This define pango name fonts (like "NimbusSans L") depending
on the "charset" defined by language array. This allows to selecting
an appropriate font for each language for the installer only.

=cut

my %charset2pango_font = (
  'utf_geor' =>    "Sans 14",
  'utf_taml' =>    "TSCu_Paranar 14",
  'jisx0208' =>    "Sans 14",
  'utf_ar' =>      "Sans 15",
  'tis620' =>      "Norasi 20",
  'default' =>     "DejaVu Sans 12"
);

=item charset2pango_font ($charset)

Returns the font to use with $charset or the default one if non is set

=cut

sub charset2pango_font {
    my ($charset) = @_;
    
    $charset2pango_font{$charset} || $charset2pango_font{default};
}

=item charset2css_font ($charset)

Returns the font to use with $charset or the default one if non is set

=cut

sub charset2css_font {
    my ($charset) = @_;

    my $font = $charset2pango_font{$charset} || $charset2pango_font{default};
    my ($familly, $size) = $font =~ /(.*) (\d+)$/;
    return "font-family: $familly; font-size: ${size}pt;";
}

sub l2pango_font {
    my ($lang) = @_;

    my $charset = l2charset($lang) or log::l("no charset found for lang $lang!"), return;
    my $font = charset2pango_font($charset);
    log::l("lang:$lang charset:$charset font:$font consolefont:$charsets{$charset}[0]");
    
    return $font;
}

sub l2css_font {
    my ($lang) = @_;

    my $charset = l2charset($lang) or log::l("no charset found for lang $lang!"), return;
    my $font = charset2css_font($charset);
    log::l("lang:$lang charset:$charset font:$font consolefont:$charsets{$charset}[0]");

    return $font;
}

=back

=head1 Other functions

=over

=cut

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

sub lang_to_ourlocale {
    my ($lang) = @_;

    my $locale = system_locales_to_ourlocale($lang);
    $locale->{utf8} ||= utf8_should_be_needed($locale);
    lang_changed($locale);
    $locale;
}

sub lang_changed {
    my ($locale) = @_;
    my $h = analyse_locale_name(l2locale($locale->{lang}));
    $locale->{country} = $h->{country} if $h->{country};

    $locale->{IM} = get_default_im($locale->{lang});
}

=item read($b_user_only)

Read locale settings from files.
If $b_user_only is set, reads the user config, else read the system config.

=cut

sub read {
    my ($b_user_only) = @_;
    my $f1 = "$::prefix$ENV{HOME}/.i18n";
    my $f2 = "$::prefix/etc/locale.conf";
    # (cg) Only use the 'legacy' config name when the new one doesn't exist
    $f2 = "$::prefix/etc/sysconfig/i18n" if ! -e $f2 && -e "$::prefix/etc/sysconfig/i18n";
    my %h = getVarsFromSh($b_user_only && -e $f1 ? $f1 : $f2);
    # Fill in defaults (from LANG= variable)
    $h{$_} ||= $h{LANG} || 'en_US' foreach @locale_conf_fields;
    my $locale = system_locales_to_ourlocale($h{LC_MESSAGES}, $h{LC_MONETARY});
    
    if (find { $h{$_} } @IM_i18n_fields) {
        my $current_IM = find {
            my $i = $IM_config{$_};
            every { !defined $i->{$_} || $h{$_} eq $i->{$_} } ('GTK_IM_MODULE', 'XMODIFIERS', 'XIM_PROGRAM');
        } keys %IM_config;
        $locale->{IM} = $current_IM if $current_IM;
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
    services::restart("systemd-localed");
}

=item write ($locale, $b_user_only, $b_dont_touch_kde_files)

Save locale settings, either system ones or per user ones (if $b_user_only is set).

=cut

sub write { 
    my ($locale, $b_user_only, $b_dont_touch_kde_files) = @_;

    $locale && $locale->{lang} or return;

    my $h = i18n_env($locale);

    my ($name, $acm) = l2console_font($locale, 0);
    if ($name && !$b_user_only) {
	my $p = "$::prefix/lib/kbd";
	if ($name) {
	    eval {
		log::explanations(qq(Set system font to "$name"));
		cp_af(glob_("$p/consolefonts/$name.*"), "$::prefix/etc/sysconfig/console/consolefonts");
		add2hash $h, { FONT => $name };
	    };
	    $@ and log::explanations("missing console font $name");
	}
	if ($acm) {
	    eval {
		log::explanations(qq(Set application-charset map (Unicode mapping table) to "$name"));
		cp_af(glob_("$p/consoletrans/$acm*"), "$::prefix/etc/sysconfig/console/consoletrans");
		add2hash $h, { FONT_MAP => $acm };
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
	$h->{QT_IM_MODULE} ||= $h->{GTK_IM_MODULE};

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

    my $file = $b_user_only ? "$ENV{HOME}/.i18n" : "$ENV{HOME}/.config/locale.conf" && '/etc/locale.conf';
    log::explanations(qq(Setting l10n configuration in "$file"));
    setVarsInShMode($::prefix . $file, 0644, $h);

    if (!$b_user_only) {
        $file = '/etc/locale.conf';
        log::explanations(qq(Setting locale configuration in "$file"));
        # Only include valid fields and ommit any that are the same as LANG to make it cleaner
        # (cleanup logic copied from systemd)
        my @filtered_keys = grep { exists $h->{$_} && ($_ eq 'LANG' || !exists $h->{LANG} || $h->{$_} ne $h->{LANG}) } @locale_conf_fields;
        my @filtered_input = grep { exists $h->{$_} } @IM_i18n_fields;
        push @filtered_keys, @filtered_input;
        my $h2 = { map { $_ => $h->{$_} } @filtered_keys };
        setVarsInShMode($::prefix . $file, 0644, $h2);

        if ($h->{SYSFONT}) {
             $file = '/etc/vconsole.conf';
             $h2 = { 'FONT' => $h->{SYSFONT} };
             $h2->{FONT_UNIMAP} = $h->{SYSFONTACM} if $h->{SYSFONTACM};
             addVarsInShMode($::prefix . $file, 0644, $h2);
        }
    }

    bootloader::set_default_grub_var('locale.lang',$h->{LANG}) if !$b_user_only;
    
    my $charset = l2charset($locale->{lang});
    my $qtglobals = $b_user_only ? "$ENV{HOME}/.qt/qtrc" : "$::prefix/etc/qtrc";
    update_gnomekderc($qtglobals, General => (
       		      font => charset2kde_font($charset, 0),
       	          ));

    eval {
	my $confdir = $::prefix . ($b_user_only ? "$ENV{HOME}/.kde" : do {
	    my $kderc = $::prefix ? common::expand_symlinks_with_absolute_symlinks_in_prefix($::prefix, '/etc/kderc') : '/etc/kderc';
	    log::l("reading $kderc");
	    my %dir_defaults = read_gnomekderc($kderc, 'Directories-default');
	    first(split(',', $dir_defaults{prefixes})) || "/etc/kde";
	}) . '/share/config';

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

    #- update alternatives for OpenOffice/BrOffice if present
    foreach my $name (grep { /^oobr_bootstraprc/ } all("$::prefix/var/lib/alternatives/")) {
        my $alternative  = common::get_alternatives($name) or next;
        my $wanted = $locale->{lang} eq 'pt_BR' ? 'bootstraprc.bro' : 'bootstraprc.ooo';
        my $path = find { basename($_) eq $wanted } map { $_->{file} } @{$alternative->{alternatives}};
        common::symlinkf_update_alternatives($name, $path) if $path;
    }
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

=item bindtextdomain()

Binds the translation domains with the proper encoding (UTF-8).

=cut

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

=item load_mo ($o_lang)

Used by the installer: returns the firste existing .mo file to load according to $o_lang.
If it's not set, we rely on environment variables.

=cut

sub load_mo {
    my ($o_lang) = @_;

    my $localedir = bindtextdomain();
    my $suffix = 'LC_MESSAGES/libDrakX.mo';

    $o_lang ||= $ENV{LANGUAGE} || $ENV{LC_ALL} || $ENV{LC_MESSAGES} || $ENV{LANG};

    my @possible_langs = map { { name => $_, mofile => "$localedir/$_/$suffix" } } split ':', $o_lang;

    -s $_->{mofile} and return $_->{name} foreach @possible_langs;

    '';
}


=item console_font_files()

Used in share/list.xml during "make get_needed_files"

=cut

sub console_font_files() {
    map { -e $_ ? $_ : "$_.gz" }
      (map { my $p = "/lib/kbd/consolefonts/$_"; -e "$p.psfu" || -e "$p.psfu.gz" ? "$p.psfu" : "$p.psf" } uniq grep { $_ } map { $_->[0] } values %charsets),
      (map { "/lib/kbd/consoletrans/${_}_to_uni.trans" } uniq grep { $_ } map { $_->[2] } values %charsets);
}

=item load_console_font($locale)

Loads the console font...

=cut

sub load_console_font {
    my ($locale) = @_;
    return if $::local_install;

    my ($name, $acm) = l2console_font($locale, 1);

    require run_program;
    run_program::run('setfont', '-v', $name || 'lat0-16', if_($acm, '-m', $acm));
}

=item fs_options($locale)

Returns the options suitable for filesystems mounting according to $locale.

=cut

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

=item check()

Used by 'make check_full'.

=cut

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

=back

=cut

1;
