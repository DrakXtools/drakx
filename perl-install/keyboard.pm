
package keyboard; # $Id$

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
  'az' => 'az',
  'be' => 'by',
  'be_BY.CP1251' => 'by',
  'bg' => 'bg',
'bg_BG'=> 'bg',
  'br' => 'fr',
  'ca' => 'es',
  'cs' => 'cz_qwerty',
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
  'fa' => 'ir',
  'fi' => 'fi',
  'fr' => 'fr',
'fr_BE'=> 'be',
'fr_CA'=> 'qc',
'fr_CH'=> 'ch_fr',
'fr_FR'=> 'fr',
  'ga' => 'uk',
  'gl' => 'es',
  'he' => 'il',
  'hr' => 'hr',
  'hu' => 'hu',
  'hy' => 'am',
  'is' => 'is',
  'it' => 'it',
  'ja' => 'jp',
  'ka' => 'ge_la',
  'lt' => 'lt',
  'mk' => 'mk',
  'nb' => 'no',
  'nl' => 'nl',
'nl_BE'=> 'be',
'nl_NL'=> 'nl',
  'no' => 'no',
  'no@nynorsk' => 'no',
  'ny' => 'no',
  'oc' => 'fr',
  'pl' => 'pl',
  'pt' => 'pt',
'pt_BR'=> 'br',
'pt_PT'=> 'pt',
  'ru' => 'ru',
  'ru_RU.KOI8-R' => 'ru',
  'sk' => 'sk_qwerty',
  'sl' => 'si',
  'sr' => 'yu',
  'sv' => 'se',
  'sv@ny' => 'se',
  'sv@traditionell' => 'se',
  'th' => 'th',
  'tr' => 'tr_q',
  'uk' => 'ua',
'uk_UA' => 'ua',
  'vi' => 'vn',
'vi_VN.tcvn' => 'vn',
'vi_VN.viscii' => 'vn',
  'wa' => 'be',
);

#- key = extension for Xmodmap file, [0] = description of the keyboard,
#- [1] = name for loadkeys, [2] = name for XKB
my %keyboards = (
arch() =~ /^sparc/ ? (
 "cs" => [ __("Czech (QWERTZ)"), "sunt5-cz-us", "czsk(cz_us_qwertz)" ],
 "de" => [ __("German"),         "sunt5-de-latin1", "de" ],
 "dvorak" => [ __("Dvorak"),     "sundvorak",   "dvorak" ],
 "es" => [ __("Spanish"),        "sunt5-es",    "es" ],
 "fi" => [ __("Finnish"),        "sunt5-fi-latin1", "fi" ],
 "fr" => [ __("French"),         "sunt5-fr-latin1", "fr" ],
 "no" => [ __("Norwegian"),      "sunt4-no-latin1", "no" ],
 "pl" => [ __("Polish"),         "sun-pl-altgraph", "pl" ],
 "ru" => [ __("Russian"),        "sunt5-ru",    "ru" ],
 "uk" => [ __("UK keyboard"),    "sunt5-uk",    "gb" ],
 "us" => [ __("US keyboard"),    "sunkeymap",   "us" ],
) : (
arch() eq "ppc" ? (
 "us" => [ __("US keyboard"),    "mac-us-ext",  "us" ],
 "de_nodeadkeys" => [ __("German"), "mac-de-latin1-nodeadkeys", "de(nodeadkeys)" ],
 "fr" => [ __("French"),         "mac-fr2-ext",   "fr" ],
) : (
 "am_old" => [ __("Armenian (old)"),	"am_old",	"am(old)" ],
 "am" => [ __("Armenian (typewriter)"),	"am-armscii8",	"am" ],
 "am_phonetic" => [ __("Armenian (phonetic)"), "am_phonetic", "am(phonetic)" ],
#- only xmodmap is currently available
#-"ar" => [ __("Arabic"),        "ar-8859_6",   "ar" ],
 "az" => [ __("Azerbaidjani (latin)"), "az",	"az" ],
 "a3" => [ __("Azerbaidjani (cyrillic)"), "az-koi8c","az(cyrillic)" ],
 "be" => [ __("Belgian"),        "be-latin1",   "be" ],
 "bg" => [ __("Bulgarian"),      "bg",          "bg" ],
 "br" => [ __("Brazilian (ABNT-2)"),      "br-abnt2",    "br" ],
 "by" => [ __("Belarusian"),      "by-cp1251",  "byru" ],
 "ch_de" => [ __("Swiss (German layout)"), "sg-latin1", "de_CH" ],
 "ch_fr" => [ __("Swiss (French layout)"), "fr_CH-latin1", "fr_CH" ],
 "cz" => [ __("Czech (QWERTZ)"), "cz-latin2",   "czsk(cz_us_qwertz)" ],
 "cz_qwerty" => [ __("Czech (QWERTY)"), "cz-lat2", "czsk(cz_us_qwerty)" ],
 "cz_prog" => [ __("Czech (Programmers)"), "cz-lat2-prog", "czsk(us_cz_prog)" ],
 "de" => [ __("German"),         "de-latin1",   "de" ],
 "de_nodeadkeys" => [ __("German (no dead keys)"), "de-latin1-nodeadkeys", "de(nodeadkeys)" ],
 "dk" => [ __("Danish"),         "dk-latin1",   "dk" ],
 "dvorak" => [ __("Dvorak (US)"),     "pc-dvorak-latin1", "dvorak" ],
 "dvorak_no" => [ __("Dvorak (Norwegian)"),     "no-dvorak", "dvorak(no)" ],
 "ee" => [ __("Estonian"),       "ee-latin9",   "ee" ],
 "es" => [ __("Spanish"),        "es-latin1",   "es" ],
 "fi" => [ __("Finnish"),        "fi-latin1",   "fi" ],
 "fr" => [ __("French"),         "fr-latin1",   "fr" ],
 "ge_ru"=>[__("Georgian (\"Russian\" layout)"),"ge_ru-georgian_academy","ge_ru"],
 "ge_la"=>[__("Georgian (\"Latin\" layout)"),"ge_la-georgian_academy","ge_la"],
 "gr" => [ __("Greek"),          "gr-8859_7",   "gr" ],
 "hu" => [ __("Hungarian"),      "hu-latin2",   "hu" ],
 "hr" => [ __("Croatian"),	 "croat",	"yu" ],
 "il" => [ __("Israeli"),        "il-8859_8",   "il" ],
 "il_phonetic" => [ __("Israeli (Phonetic)"),"hebrew",   "il_phonetic" ],
 "ir" => [ __("Iranian"),        "ir-isiri3342","ir" ],
 "is" => [ __("Icelandic"),      "is-latin1",   "is" ],
 "it" => [ __("Italian"),        "it-latin1",   "it" ],
 "jp" => [ __("Japanese 106 keys"), "jp106",	"jp" ],
 "la" => [ __("Latin American"), "la-latin1",   "la" ],
#-"mk" => [ __("Macedonian"),	 "mk",		"mk" ],
 "nl" => [ __("Dutch"),          "nl-latin1",   "nl" ],
 "lt" => [ __("Lithuanian AZERTY (old)"), "lt-latin7","lt" ],
#- TODO: write a console kbd map for lt_new
 "lt_new" => [ __("Lithuanian AZERTY (new)"), "lt-latin7","lt_new" ],
 "lt_b" => [ __("Lithuanian \"number row\" QWERTY"), "ltb-latin7", "lt_b" ],
 "lt_p" => [ __("Lithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt_p" ],
 "no" => [ __("Norwegian"),      "no-latin1",   "no" ],
 "pl" => [ __("Polish (qwerty layout)"),        "pl", "pl" ],
 "pl2" => [ __("Polish (qwertz layout)"),       "pl-latin2", "pl2" ],
 "pt" => [ __("Portuguese"),     "pt-latin1",   "pt" ],
 "qc" => [ __("Canadian (Quebec)"), "qc-latin1","ca_enhanced" ],
 "ru" => [ __("Russian"),        "ru4",         "ru(winkeys)" ],
 "ru_yawerty" => [ __("Russian (Yawerty)"),"ru-yawerty","ru_yawerty" ],
 "se" => [ __("Swedish"),        "se-latin1",   "se" ],
 "si" => [ __("Slovenian"),      "slovene",     "si" ],
 "sk" => [ __("Slovakian (QWERTZ)"), "sk-qwertz",   "czsk(sk_us_qwertz)" ],
 "sk_qwerty" => [ __("Slovakian (QWERTY)"), "sk-qwerty", "czsk(sk_us_qwerty)" ],
 "sk_prog" => [ __("Slovakian (Programmers)"), "sk-prog", "czsk(us_sk_prog" ],
 "th" => [ __("Thai keyboard"),  "th",          "th" ],
 "tr_f" => [ __("Turkish (traditional \"F\" model)"), "trf", "tr_f" ],
 "tr_q" => [ __("Turkish (modern \"Q\" model)"), "tr_q-latin5", "tr_q" ],
 "ua" => [ __("Ukrainian"),      "ua",           "ua" ],
 "uk" => [ __("UK keyboard"),    "uk",           "gb" ],
 "us" => [ __("US keyboard"),    "us",           "us" ],
 "us_intl" => [ __("US keyboard (international)"), "us-latin1", "us_intl" ],
 "vn" => [ __("Vietnamese \"numeric row\" QWERTY"),"vn-tcvn", "vn" ], 
 "yu" => [ __("Yugoslavian (latin layout)"), "sr", "yu" ],
)),
);


#-######################################################################################
#- Functions
#-######################################################################################
sub xmodmaps { keys %keyboards }
sub keyboard2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboard2kmap { $keyboards{$_[0]} && $keyboards{$_[0]}[1] }
sub keyboard2xkb  { $keyboards{$_[0]} && $keyboards{$_[0]}[2] }

sub loadkeys_files {
    my $archkbd = arch() =~ /^sparc/ ? "sun" : arch() =~ /i.86/ ? "i386" : arch();
    my $p = "/usr/lib/kbd/keymaps/$archkbd";
    my $post = ".kmap.gz";
    my %trans = ("cz-latin2" => "cz-lat2");
    my (@l, %l);
    foreach (values %keyboards) {
	local $_ = $trans{$_->[1]} || $_->[1];
	my ($l) = grep { -e $_ } ("$p/$_$post");
	$l or /(..)/ and ($l) = grep { -e $_ } ("$p/$1$post");
	print STDERR "unknown $_\n" if $_[0] && !$l; $l or next;
	push @l, $l;
	foreach (`zgrep include $l | grep "^include"`) {
	    /include\s+"(.*)"/ or die "bad line $_";
	    @l{grep { -e $_ } ("$p/$1.inc.gz")} = ();
	}
    }        
    @l, keys %l, grep { -e $_ } map { "$p/$_.inc.gz" } qw(compose euro windowkeys linux-keys-bare);
}

sub lang2keyboard {
    my ($l) = @_;
    my $kb = $lang2keyboard{$l} || $keyboards{$l} && $l || "us";
    $keyboards{$kb} ? $kb : "us"; #- handle incorrect keyboad mapping to us.
}

sub load {
    my ($keymap) = @_;
    return if $::testing;

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
    my $f = "$ENV{SHARE_PATH}/xmodmap/xmodmap.$keyboard";
    if (! -e $f) {
	run_program::run("packdrake", "-x", "$ENV{SHARE_PATH}/xmodmap.cz2", '/tmp', "xmodmap.$keyboard");
	$f = "/tmp/xmodmap.$keyboard";
    }
    -e $f && $f;
}

sub setup {
    return if arch() =~ /^sparc/;
    my ($keyboard) = @_;
    my $o = $keyboards{$keyboard} or return;

    log::l("loading keymap $o->[1]");
    if (-e (my $f = "$ENV{SHARE_PATH}/keymaps/$o->[1].bkmap")) {
	load(scalar cat_($f));
    } else {
	local *F;
	open F, "packdrake -x $ENV{SHARE_PATH}/keymaps.cz2 '' $o->[1].bkmap |";
	local $/ = undef;
	eval { load(join('', <F>)) };
    }
    my $f = xmodmap_file($keyboard);
    eval { run_program::run('xmodmap', $f) } unless $::testing || !$f;
}

sub write {
    my ($prefix, $keyboard, $charset, $isNotDelete) = @_;

    setVarsInSh("$prefix/etc/sysconfig/keyboard", { KEYTABLE => keyboard2kmap($keyboard), 
						    KBCHARSET => $charset,
						    BACKSPACE => $isNotDelete ? "BackSpace" : "Delete" });
    run_program::rooted($prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or log::l("dumpkeys failed");
}

sub read {
    my ($prefix) = @_;
    my %keyf = getVarsFromSh("$prefix/etc/sysconfig/keyboard");
    my $keytable = $keyf{KEYTABLE};
    keyboard2kmap($_) eq $keytable and return $_ foreach keys %keyboards;
    $keyboards{$keytable} && $keytable; #- keep track of unknown keyboard.
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
