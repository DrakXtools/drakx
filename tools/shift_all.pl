use MDK::Common;

my %shifts = (
'af' => 1,
'am' => 1,
'ar' => 0,
'az' => 1,
'be' => 2,
'bg' => 2,
'bn' => 1,
'br' => 2,
'bs' => 2,
'ca' => 2,
'cs' => 2,
'cy' => 2,
'da' => 2,
'de' => 2,
'el' => 2,
'en_GB' => 2,
'en_US' => 2,
'eo' => 2,
'es' => 2,
'et' => 2,
'eu' => 2,
'fa' => 0,
'fi' => 1,
'fo' => 2,
'fr' => 2,
'ga' => 2,
'gd' => 2,
'gl' => 2,
'gv' => 2,
'he' => 0,
'hi' => 1,
'hr' => 2,
'hu' => 2,
'hy' => 1,
'ia' => 2,
'id' => 1,
'is' => 1,
'it' => 1,
'iu' => 1,
'ja' => 3,
'ka' => 1,
'kn' => 1,
'ko' => 1,
'kw' => 0,
'lo' => 0,
'lt' => 0,
'lv' => 0,
'mi' => 0,
'mk' => 0,
'mn' => 0,
'mr' => 0,
'ms' => 0,
'mt' => 0,
'nb' => 0,
'nl' => 0,
'nn' => 0,
'no' => 0,
'oc' => 0,
'pl' => 0,
'pt_BR' => 0,
'pt' => 0,
'ro' => 0,
'ru' => 0,
'sk' => 0,
'sl' => 0,
'sp' => 0,
'sq' => 0,
'sr' => 0,
'sv' => 0,
'ta' => 1,
'te' => 1,
'tg' => 0,
'th' => 0,
'tr' => 0,
'tt' => 1,
'uk' => 0,
'ur' => 1,
'uz' => 0,
'vi' => 0,
'wa' => 0,
'yi' => 0,
'zh_CN' => 0,
'zh_TW' => 0,
);

foreach (glob("lang*.png")) {
    /lang-(.*)\.png/;
    exists $shifts{$1} or die "doesn't exist for $_";
    $shifts{$1} or next;
    print "./a.out $_ l.png $shifts{$1}\n";
    system("./a.out $_ l.png $shifts{$1}");
    renamef('l.png', $_);
}

















