
package keyboard;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file);
use run_program;
use commands;
use log;
use c;


#-######################################################################################
#- Globals
#-######################################################################################
my $KMAP_MAGIC = 0x8B39C07F;

#- a best guess of the keyboard layout, based on the choosen locale
my %lang2keyboard =
(
  'af' => 'us_intl',
  'bg' => 'bg',
  'br' => 'fr',
  'ca' => 'es',
  'cs' => 'cz',
  'cy' => 'uk',
  'da' => 'dk',
  'de' => 'de',
'de_AT'=> 'de',
'de_CH'=> 'ch_de',
'de_DE'=> 'de', 
  'el' => 'gr',
  'en' => 'us',
'en_US'=> 'us',
'en_GB'=> 'uk',
  'eo' => 'us_intl',
  'es' => 'es',
  'es@tradicional' => 'es',
'es_AR'=> 'la',
'es_ES'=> 'es',
'es_MX'=> 'la',
  'et' => 'ee',
  'eu' => 'es',
  'fi' => 'fi',
  'fr' => 'fr',
'fr_BE'=> 'be',
'fr_CA'=> 'qc',
'fr_CH'=> 'ch_fr',
'fr_FR'=> 'fr',
  'ga' => 'uk',
  'gl' => 'es',
  'he' => 'il',
  'hr' => 'si',
  'hu' => 'hu',
  'hy' => 'am',
  'is' => 'is',
  'it' => 'it',
  'ka' => 'ge_la',
  'lt' => 'lt',
  'nl' => 'nl',
'nl_BE'=> 'be',
'nl_NL'=> 'nl',
  'no' => 'no',
  'no@nynorsk' => 'no',
  'oc' => 'fr',
  'pl' => 'pl',
  'pt' => 'pt',
'pt_BR'=> 'br',
'pt_PT'=> 'pt',
  'ru' => 'ru',
  'sk' => 'sk',
  'sl' => 'si',
  'sr' => 'yu',
  'sv' => 'se',
  'th' => 'th',
  'tr' => 'tr_q',
  'uk' => 'ua',
  'wa' => 'be',
);

#- key = extension for Xmodmap file, [0] = description of the keyboard,
#- [1] = name for loadkeys, [2] = name for XKB
my %keyboards = (
arch() =~ /^sparc/ ? (
 "cs" => [ __("Czech"),          "sunt5-us-cz", "cs" ],
 "de" => [ __("German"),         "sunt5-de-latin1", "de" ],
 "dvorak" => [ __("Dvorak"),     "sundvorak",   "dvorak" ],
 "es" => [ __("Spanish"),        "sunt5-es",    "es" ],
 "fi" => [ __("Finnish"),        "sunt5-fi-latin1", "fi" ],
 "fr" => [ __("French"),         "sunt5-fr-latin1", "fr" ],
 "no" => [ __("Norwegian"),      "sunt4-no-latin1", "no" ],
 "pl" => [ __("Polish"),         "sun-pl-altgraph", "pl" ],
 "ru" => [ __("Russian"),        "sunt5-ru",    "ru" ],
 "uk" => [ __("UK keyboard"),    "sunt5-uk",    "us" ],
 "us" => [ __("US keyboard"),    "sunkeymap",   "us" ],
) : (
 "am" => [ __("Armenian"),       "am-armscii8", "am" ],
 "be" => [ __("Belgian"),        "be-latin1",   "be" ],
 "bg" => [ __("Bulgarian"),      "bg",          "bg" ],
 "br" => [ __("Brazilian"),      "br-abnt2",    "br" ],
 "ch_de" => [ __("Swiss (French layout)"), "fr_CH-latin1", "fr_CH" ],
 "ch_fr" => [ __("Swiss (German layout)"), "sg-latin1", "de_CH" ],
 "cz" => [ __("Czech"),          "cz-latin2",   "cs" ],
 "de" => [ __("German"),         "de-latin1",   "de" ],
 "de_nodeadkeys" => [ __("German (no dead keys)"), "de-latin1-nodeadkeys", "de" ],
 "dk" => [ __("Danish"),         "dk-latin1",   "dk" ],
 "dvorak" => [ __("Dvorak"),     "pc-dvorak-latin1", "dvorak" ],
 "ee" => [ __("Estonian"),       "ee-latin9",   "ee" ],
 "es" => [ __("Spanish"),        "es-latin1",   "es" ],
 "fi" => [ __("Finnish"),        "fi-latin1",   "fi" ],
 "fr" => [ __("French"),         "fr-latin1",   "fr" ],
 "ge_ru"=>[__("Georgian (\"Russian\" layout)"),"ge_ru-georgian_academy","ge_ru"],
 "ge_la"=>[__("Georgian (\"Latin\" layout)"),"ge_la-georgian_academy","ge_la"],
 "gr" => [ __("Greek"),          "gr-8859_7",   "gr" ],
 "hu" => [ __("Hungarian"),      "hu-latin2",   "hu" ],
 "il" => [ __("Israeli"),        "il-8859_8",   "il" ],
 "il_phonetic" => [ __("Israeli (Phonetic)"),"hebrew",   "il_phonetic" ],
 "is" => [ __("Icelandic"),      "is-latin1",   "is" ],
 "it" => [ __("Italian"),        "it-latin1",   "it" ],
 "la" => [ __("Latin American"), "la-latin1",   "la" ],
 "nl" => [ __("Dutch"),          "nl-latin1",   "nl" ],
 "lt" => [ __("Lithuanian AZERTY"), "lt-latin7","lt" ],
 "lt_b" => [ __("Lithuanian \"number row\" QWERTY"), "ltb-latin7", "lt_b" ],
 "lt_p" => [ __("Lithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt_p" ],
 "no" => [ __("Norwegian"),      "no-latin1",   "no" ],
 "pl" => [ __("Polish (qwerty layout)"),        "pl", "pl" ],
 "pl2" => [ __("Polish (qwertz layout)"),       "pl-latin2", "pl" ],
 "pt" => [ __("Portuguese"),     "pt-latin1",   "pt" ],
 "qc" => [ __("Canadian (Quebec)"), "qc-latin1","ca_enhanced" ],
 "ru" => [ __("Russian"),        "ru4",         "ru" ],
 "ru_yawerty" => [ __("Russian (Yawerty)"),"ru-yawerty","ru_yawerty" ],
 "se" => [ __("Swedish"),        "se-latin1",   "se_SE" ],
 "si" => [ __("Slovenian"),      "slovene",     "si" ],
 "sk" => [ __("Slovakian"),      "sk-qwertz",   "czsk" ],
 "th" => [ __("Thai keyboard"),  "th",          "th" ],
 "tr_f" => [ __("Turkish (traditional \"F\" model)"), "trf", "tr_f" ],
 "tr_q" => [ __("Turkish (modern \"Q\" model)"), "tr_q-latin5", "tr_q" ],
 "ua" => [ __("Ukrainian"),      "ua",           "ua" ],
 "uk" => [ __("UK keyboard"),    "uk",           "gb" ],
 "us" => [ __("US keyboard"),    "us",           "us" ],
 "us_intl" => [ __("US keyboard (international)"), "us-latin1", "us_intl" ],
 "yu" => [ __("Yugoslavian (latin layout)"), "sr", "yu" ],
),
);

#-######################################################################################
#- Functions
#-######################################################################################
sub list { map { $_->[0] } values %keyboards }
sub xmodmaps { keys %keyboards }
sub keyboard2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboard2kmap { $keyboards{$_[0]} && $keyboards{$_[0]}[1] }
sub keyboard2xkb  { $keyboards{$_[0]} && $keyboards{$_[0]}[2] }
sub text2keyboard {
    my ($t) = @_;
    while (my ($k, $v) = each %keyboards) {
        lc($v->[0]) eq lc($t) and return $k;
    }
    die "unknown keyboard $t";
}


sub lang2keyboard($) {
    local ($_) = @_;
    my $kb = $lang2keyboard{$_} || $keyboards{$_} && $_ || "us";
    $keyboards{$kb} ? $kb : "us"; #- handle incorrect keyboad mapping to us.
}

sub load($) {
    return if arch() =~ /^sparc/;
    my ($keymap) = @_;

    my ($magic, @keymaps) = unpack "I i" . c::MAX_NR_KEYMAPS() . "a*", $keymap;
    $keymap = pop @keymaps;

    $magic != $KMAP_MAGIC and die "failed to read kmap magic";

    local *F;
    sysopen F, "/dev/console", 2 or die "failed to open /dev/console: $!";

    my $count = 0;
    foreach (0 .. c::MAX_NR_KEYMAPS() - 1) {
	$keymaps[$_] or next;

	my @keymap = unpack "s" . c::NR_KEYS() . "a*", $keymap;
	$keymap = pop @keymap;

	my $key = -1;
	foreach my $value (@keymap) {
	    $key++;
	    c::KTYP($value) != c::KT_SPEC() or next;
	    ioctl(F, c::KDSKBENT(), pack("CCS", $_, $key, $value)) or die "keymap ioctl failed ($_ $key $value): $!";
	 }
	$count++;
    }
    #- log::l("loaded $count keymap tables");
}

sub xmodmap_file {
    my ($keyboard) = @_;
    my $f = "/usr/share/xmodmap/xmodmap.$keyboard";
    if (! -e $f) {
	run_program::run("extract_archive", "/usr/share/xmodmap", '/tmp', "xmodmap.$keyboard");
	$f = "/tmp/xmodmap.$keyboard";
    }
    $f;
}

sub setup($) {
    my ($keyboard) = @_;
    my $o = $keyboards{$keyboard} or return;

    log::l("loading keymap $o->[1]");
    if (-e (my $f = "/usr/share/keymaps/$o->[1].kmap")) {
	load(cat_($f));
    } else {
	local *F;
	open F, "extract_archive /usr/share/keymaps '' $o->[1].kmap |";
	local $/ = undef;
	eval { load(<F>) };
    }
    my $f = xmodmap_file($keyboard);
    #eval { run_program::run('xmodmap', $f) } unless $::testing || !$f;
}

sub write($$;$) {
    my ($prefix, $keyboard, $isNotDelete) = @_;

    setVarsInSh("$prefix/etc/sysconfig/keyboard", { KEYTABLE => keyboard2kmap($keyboard), $isNotDelete ? () : (BACKSPACE => "Delete") });
    run_program::rooted($prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or die "dumpkeys failed";
}

sub read($) {
    my ($prefix) = @_;

    my %keyf = getVarsFromSh("$prefix/etc/sysconfig/keyboard");
    map { keyboard2kmap($_) eq $keyf{KEYTABLE} || $_ eq $keyf{KEYTABLE} ? $_ : (); } keys %keyboards;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
