
package keyboard; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use detect_devices;
use run_program;
use log;
use c;


#-######################################################################################
#- Globals
#-######################################################################################
my $KMAP_MAGIC = 0x8B39C07F;

#- a best guess of the keyboard layout, based on the choosen locale
#- beware only the first 5 characters are used
my %lang2keyboard =
(
  'af' => 'us_intl',
#-'ar' => 'ar:80 ar_d:70 ar_azerty:60 ar_azerty_d:50',
  'az' => 'az:80 tr:10 us_intl:5',
'az_AZ'=> 'az:80 tr:10 us_intl:5',
  'be' => 'by:80 ru:50 ru_yawerty:40',
'be_BY'=> 'by:80 ru:50 ru_yawerty:40',
  'bg' => 'bg:90',
'bg_BG'=> 'bg:90',
  'br' => 'fr:90',
  'bs' => 'hr:60 yu:50 si:40',
  'ca' => 'es:89 fr:15',
'ca_ES'=> 'es:89 fr:15',
  'cs' => 'cz_qwerty:70 cz:50 cz_prog:10',
  'cy' => 'uk:90',
  'da' => 'dk:90',
'da_DK'=> 'dk:90',
  'de' => 'de_nodeadkeys:70 de:50',
'de_AT'=> 'de_nodeadkeys:70 de:50',
'de_BE'=> 'be:70 de_nodeadkeys:60 de:50',
'de_CH'=> 'ch_de:70 ch_fr:25 de_nodeadkeys:20 de:15',
'de_DE'=> 'de_nodeadkeys:70 de:50', 
'de_LU'=> 'de_nodeadkeys:70 de:50 fr:40 be:35', 
  'el' => 'gr:90',
'el_GR'=> 'gr:90',
  'en' => 'us:90 us_intl:50',
'en_US'=> 'us:90 us_intl:50',
'en_GB'=> 'uk:89 us:60 us_intl:50',
'en_IE'=> 'uk:89 us:60 us_intl:50',
  'eo' => 'us_intl:89 dvorak:20',
  'es' => 'es:85 la:80 us_intl:50',
'es@tr'=> 'es:85 la:80 us_intl:50',
'es_AR'=> 'la:80 us_intl:50 es:20',
'es_ES'=> 'es:90',
'es_MX'=> 'la:80 us_intl:50 es:20',
  'et' => 'ee:90',
  'eu' => 'es:89 fr:15',
'eu_ES'=> 'es:89 fr:15',
  'fa' => 'ir:90',
  'fi' => 'fi:90',
'fi_FI'=> 'fi:90',
  'fr' => 'fr:90',
'fr_BE'=> 'be:85 fr:5',
'fr_CA'=> 'qc:85 fr:5',
'fr_CH'=> 'ch_fr:70 ch_de:15 fr:10',
'fr_FR'=> 'fr:90',
'fr_LU'=> 'fr:70 de_nodeadkeys:50 de:40 be:35', 
  'ga' => 'uk:90',
'ga_IE'=> 'uk:90',
  'gd' => 'uk:90',
  'gl' => 'es:90',
  'gv' => 'uk:90',
  'he' => 'il:89 il_phonetic:10',
  'hr' => 'hr:80 si:50',
  'hu' => 'hu:90',
  'hy' => 'am:80 am_old:10 am_phonetic:5',
  'id' => 'us:90 us_intl:20',
  'is' => 'is:90',
  'iu' => 'iu:90',
'it_CH' => 'ch_fr:80 ch_de:60 it:50',
'it_IT' => 'it:90',
  'ja' => 'jp:80 us:50 us_intl:20',
  'ka' => 'ge_la:80 ge_ru:50',
'ka_GE'=> 'ge_la:80 ge_ru:50',
  'kl' => 'dk:80 us_intl:30',
  'ko' => 'kr:80 us:60',
  'kw' => 'uk:90',
  'lo' => 'us:60',
  'lt' => 'lt:80 lt_new:70 lt_b:60 lt_p:50',
  'lv' => 'lv:80 lt:40 lt_new:30 lt_b:20 lt_p:10 ee:5',
  'mi' => 'us_intl:60 uk:20 us:10',
  'mk' => 'mk:80',
  'ms' => 'us:90 us_intl:20',
  'nb' => 'no:85 dvorak_no:10',
'nl_BE'=> 'be:80 nl:10 us_intl:5',
'nl_NL'=> 'us_intl:80 nl:15 us:10 uk:5',
  'nn' => 'no:85 dvorak_no:10',
  'no' => 'no:85 dvorak_no:10',
  'oc' => 'fr:90',
'oc_FR'=> 'fr:90',
  'ph' => 'us:90 us_intl:20',
  'pl' => 'pl:80 pl2:60',
  'pp' => 'br:80 la:20 pt:10 us_intl:30',
'pt_BR'=> 'br:80 la:20 pt:10 us_intl:30',
'pt_PT'=> 'pt:80',
  'ro' => 'ro2:80 ro:40 us-intl:10',
  'ru' => 'ru:85 ru_yawerty:80',
'ru_RU'=> 'ru:85 ru_yawerty:80',
  'sk' => 'sk_qwerty:80 sk:70 sk_prog:50',
  'sl' => 'si:80 hr:50',
  'sp' => 'sr:80',
  'sq' => 'al:80',
  'sr' => 'yu:80',
  'sv' => 'se:85 fi:20',
'sv_FI'=> 'fi:85 sv:20',
'sv_SE'=> 'se:85 fi:20',
  'tg' => 'tj:80 ru_yawerty:40',
  'th' => 'th:90',
  'tr' => 'tr_q:85 tr_q:30',
  'tt' => 'ru:50 ru_yawerty:40',
  'uk' => 'ua:85 ru:50 ru_yawerty:40',
'uk_UA'=> 'ua:85 ru:50 ru_yawerty:40',
  'uz' => 'us:80',
  'vi' => 'vn:80 us:60 us_intl:50',
'vi_VN'=> 'vn us:60 us_intl:50',
  'wa' => 'be:85 fr:5',
'wa_BE'=> 'be:85 fr:5',
'zh_CN'=> 'us:60',
'zh_TW'=> 'us:60',
);

#- key = extension for Xmodmap file, [0] = description of the keyboard,
#- [1] = name for loadkeys, [2] = name for XKB
my %keyboards = (
arch() =~ /^sparc/ ? (
 "cz" => [ __("Czech (QWERTZ)"), "sunt5-cz-us", "cz" ],
 "de" => [ __("German"),         "sunt5-de-latin1", "de" ],
 "dvorak" => [ __("Dvorak"),     "sundvorak",   "dvorak" ],
 "es" => [ __("Spanish"),        "sunt5-es",    "es" ],
 "fi" => [ __("Finnish"),        "sunt5-fi-latin1", "fi" ],
 "fr" => [ __("French"),         "sunt5-fr-latin1", "fr" ],
 "no" => [ __("Norwegian"),      "sunt4-no-latin1", "no" ],
 "pl" => [ __("Polish"),         "sun-pl-altgraph", "pl" ],
 "ru" => [ __("Russian"),        "sunt5-ru",    "ru" ],
# TODO: check the console map
 "se" => [ __("Swedish"),        "sunt5-fi-latin1",    "se" ],
 "uk" => [ __("UK keyboard"),    "sunt5-uk",    "gb" ],
 "us" => [ __("US keyboard"),    "sunkeymap",   "us" ],
) : (
arch() eq "ppc" ? (
 "de_nodeadkeys" => [ __("German"), "mac-de-latin1-nodeadkeys", "de(nodeadkeys)" ],
 "fr" => [ __("French"),         "mac-fr2-ext",   "fr" ],
 "us" => [ __("US keyboard"),    "mac-us-ext",  "us" ],
) : (
 "al" => [ __("Albanian"), "al", "al" ],
 "am_old" => [ __("Armenian (old)"),	"am_old",	"am(old)" ],
 "am" => [ __("Armenian (typewriter)"),	"am-armscii8",	"am" ],
 "am_phonetic" => [ __("Armenian (phonetic)"), "am_phonetic", "am(phonetic)" ],
#-"ar_azerty" => [ __("Arabic (AZERTY)"),       "ar-8859_6",   "ar(azerty)" ],
#-"ar_azerty_d" => [ __("Arabic (AZERTY, arabic digits)"),"ar-8859_6","ar(azerty_digits)" ],
#-"ar" => [ __("Arabic (QWERTY)"),       "ar-8859_6",   "ar" ],
#-"ar_d" => [ __("Arabic (QWERTY, arabic digits)"),"ar-8859_6","ar(digits)" ],
 "az" => [ __("Azerbaidjani (latin)"), "az",	"az" ],
#"a3" => [ __("Azerbaidjani (cyrillic)"), "az-koi8k","az(cyrillic)" ],
 "be" => [ __("Belgian"),        "be2-latin1",   "be" ],
 "bg" => [ __("Bulgarian"),      "bg",          "bg" ],
 "br" => [ __("Brazilian (ABNT-2)"),      "br-abnt2",    "br" ],
 "by" => [ __("Belarusian"),      "by-cp1251",  "by" ],
 "ch_de" => [ __("Swiss (German layout)"), "sg-latin1", "de_CH" ],
 "ch_fr" => [ __("Swiss (French layout)"), "fr_CH-latin1", "fr_CH" ],
#"cz" => [ __("Czech (QWERTZ)"), "cz-latin2",   "czsk(cz_us_qwertz)" ],
#"cz_qwerty" => [ __("Czech (QWERTY)"), "cz-lat2", "czsk(cz_us_qwerty)" ],
#"cz_prog" => [ __("Czech (Programmers)"), "cz-lat2-prog", "czsk(us_cz_prog)" ],
 "cz" => [ __("Czech (QWERTZ)"), "cz-latin2",   "cz" ],
 "cz_qwerty" => [ __("Czech (QWERTY)"), "cz-lat2", "cz_qwerty" ],
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
 "gr" => [ __("Greek"),          "gr-8859_7",   "el" ],
 "hu" => [ __("Hungarian"),      "hu-latin2",   "hu" ],
 "hr" => [ __("Croatian"),	 "croat",	"hr" ],
 "il" => [ __("Israeli"),        "il-8859_8",   "il" ],
 "il_phonetic" => [ __("Israeli (Phonetic)"),"hebrew",   "il_phonetic" ],
 "ir" => [ __("Iranian"),        "ir-isiri3342","ir" ],
 "is" => [ __("Icelandic"),      "is-latin1",   "is" ],
 "it" => [ __("Italian"),        "it-latin1",   "it" ],
#"iu" => [ __("Inuktitut"),      "iu",		"iu" ],
 "jp" => [ __("Japanese 106 keys"), "jp106",	"jp" ],
 "kr" => [ __("Korean keyboard"),"us",	"kr" ],
 "la" => [ __("Latin American"), "la-latin1",   "la" ],
 "lt" => [ __("Lithuanian AZERTY (old)"), "lt-latin7","lt_a" ],
#- TODO: write a console kbd map for lt_new
 "lt_new" => [ __("Lithuanian AZERTY (new)"), "lt-latin7","lt_std" ],
 "lt_b" => [ __("Lithuanian \"number row\" QWERTY"), "ltb-latin7", "lt" ],
 "lt_p" => [ __("Lithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt_p" ],
 "lv" => [ __("Latvian"),	 "lv-latin7",   "lv" ],
 "mk" => [ __("Macedonian"),	 "mk",		"mk" ],
 "nl" => [ __("Dutch"),          "nl-latin1",   "nl" ],
 "no" => [ __("Norwegian"),      "no-latin1",   "no" ],
 "pl" => [ __("Polish (qwerty layout)"),        "pl", "pl" ],
 "pl2" => [ __("Polish (qwertz layout)"),       "pl-latin2", "pl2" ],
 "pt" => [ __("Portuguese"),     "pt-latin1",   "pt" ],
 "qc" => [ __("Canadian (Quebec)"), "qc-latin1","ca_enhanced" ],
#- TODO: write a console kbd map for ro2
 "ro2" => [ __("Romanian (qwertz)"),       "ro2",         "ro2" ],
 "ro" => [ __("Romanian (qwerty)"),       "ro",         "ro" ],
 "ru" => [ __("Russian"),        "ru4",         "ru(winkeys)" ],
 "ru_yawerty" => [ __("Russian (Yawerty)"),"ru-yawerty","ru_yawerty" ],
 "se" => [ __("Swedish"),        "se-latin1",   "se" ],
 "si" => [ __("Slovenian"),      "slovene",     "si" ],
# "sk" => [ __("Slovakian (QWERTZ)"), "sk-qwertz",   "czsk(sk_us_qwertz)" ],
# "sk_qwerty" => [ __("Slovakian (QWERTY)"), "sk-qwerty", "czsk(sk_us_qwerty)" ],
# "sk_prog" => [ __("Slovakian (Programmers)"), "sk-prog", "czsk(us_sk_prog" ],
 "sk" => [ __("Slovakian (QWERTZ)"), "sk-qwertz",   "sk" ],
 "sk_qwerty" => [ __("Slovakian (QWERTY)"), "sk-qwerty", "sk_qwerty" ],
# TODO: console map
 "sr" => [ __("Serbian (cyrillic)"), "yu", "sr" ],
 "th" => [ __("Thai keyboard"),  "th",          "th" ],
# TODO: console map
 "tj" => [ __("Tajik keyboard"),  "tj",          "tj" ],
 "tr_f" => [ __("Turkish (traditional \"F\" model)"), "trf", "tr_f" ],
 "tr_q" => [ __("Turkish (modern \"Q\" model)"), "tr_q-latin5", "tr" ],
 "ua" => [ __("Ukrainian"),      "ua",           "ua" ],
 "uk" => [ __("UK keyboard"),    "uk",           "gb" ],
 "us" => [ __("US keyboard"),    "us",           "us" ],
 "us_intl" => [ __("US keyboard (international)"), "us-latin1", "us_intl" ],
 "vn" => [ __("Vietnamese \"numeric row\" QWERTY"),"vn-tcvn", "vn(toggle)" ], 
 "yu" => [ __("Yugoslavian (latin)"), "yu", "hr" ],
)),
);

#-######################################################################################
#- Functions
#-######################################################################################
sub keyboards { keys %keyboards }
sub keyboard2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboard2kmap { $keyboards{$_[0]} && $keyboards{$_[0]}[1] }
sub keyboard2xkb  { $keyboards{$_[0]} && $keyboards{$_[0]}[2] }

sub loadkeys_files {
    my ($warn) = @_;
    my $archkbd = arch() =~ /^sparc/ ? "sun" : arch() =~ /i.86/ ? "i386" : arch() =~ /ppc/ ? "mac" : arch();
    my $p = "/usr/lib/kbd/keymaps/$archkbd";
    my $post = ".kmap.gz";
    my %trans = ("cz-latin2" => "cz-lat2");
    my %find_file;
    foreach my $dir (all($p)) {
	$find_file{$dir} = '';
	foreach (all("$p/$dir")) {
	    $find_file{$_} && $warn and warn "file $_ is both in $find_file{$_} and $dir\n";
	    $find_file{$_} = "$p/$dir/$_";
	}
    }
    my (@l, %l);
    foreach (values %keyboards) {
	local $_ = $trans{$_->[1]} || $_->[1];
	my $l = $find_file{"$_$post"} || $find_file{first(/(..)/) . $post};
	print STDERR "unknown $_\n" if $warn && !$l; $l or next;
	push @l, $l;
	foreach (`zgrep include $l | grep "^include"`) {
	    /include\s+"(.*)"/ or die "bad line $_";
	    @l{grep { -e $_ } ("$p/$1.inc.gz")} = ();
	}
    }
    @l, keys %l, grep { -e $_ } map { "$p/$_.inc.gz" } qw(compose euro windowkeys linux-keys-bare);
}

sub unpack_keyboards {
    my ($k) = @_ or return;
    [ grep { 
	my $b = $keyboards{$_->[0]};
	$b or log::l("bad keyboard $_->[0] in %keyboard::lang2keyboard");
	$b;
    } map { [ split ':' ] } split ' ', $k ];
}
sub lang2keyboards {
    my ($l) = @_;
    my $li = unpack_keyboards($lang2keyboard{substr($l, 0, 5)}) || [ $keyboards{$l} && $l || "us" ];
    $li->[0][1] ||= 100;
    $li;
}
sub lang2keyboard {
    my ($l) = @_;
    my $kb = lang2keyboards($l)->[0][0];
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
	eval {
	    require packdrake;
	    my $packer = new packdrake("$ENV{SHARE_PATH}/xmodmap.cz2", quiet => 1);
	    $packer->extract_archive("/tmp", "xmodmap.$keyboard");
	};
	$f = "/tmp/xmodmap.$keyboard";
    }
    -e $f && $f;
}

sub setup {
    return if arch() =~ /^sparc/;

    #- Xpmac doesn't map keys quite right
    if (arch() =~ /ppc/ && !$::testing && $ENV{DISPLAY}) {
	log::l("Fixing Mac keyboard");
	run_program::run('xmodmap', "-e",  "keycode 59 = BackSpace" );
	run_program::run('xmodmap', "-e",  "keycode 131 = Shift_R" );
	run_program::run('xmodmap', "-e",  "add shift = Shift_R" );
	return;
    }

    my ($keyboard) = @_;
    my $o = $keyboards{$keyboard} or return;

    log::l("loading keymap $o->[1]");
    if (-e (my $f = "$ENV{SHARE_PATH}/keymaps/$o->[1].bkmap")) {
	load(scalar cat_($f));
    } else {
	local *F;
	if (my $pid = open F, "-|") {
	    local $/ = undef;
	    eval { load(join('', <F>)) };
	    waitpid $pid, 0;
	} else {
	    eval {
		require packdrake;
		my $packer = new packdrake("$ENV{SHARE_PATH}/keymaps.cz2", quiet => 1);
		$packer->extract_archive(undef, "$o->[1].bkmap");
	    };
	    c::_exit(0);
	}
    }
    my $f = xmodmap_file($keyboard);
    eval { run_program::run('xmodmap', $f) } if $f && !$::testing && $ENV{DISPLAY};
}

sub write {
    my ($prefix, $keyboard, $charset, $isNotDelete) = @_;

    my $config = read_raw($prefix);
    put_in_hash($config, {
			  KEYTABLE => keyboard2kmap($keyboard), 
			  KBCHARSET => $charset,
			 });
    add2hash_($config, {
			DISABLE_WINDOWS_KEY => bool2yesno(detect_devices::isLaptop()),
			BACKSPACE => $isNotDelete ? "BackSpace" : "Delete",
		       });
    setVarsInSh("$prefix/etc/sysconfig/keyboard", $config);
    run_program::rooted($prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or log::l("dumpkeys failed");
}

sub read_raw {
    my ($prefix) = @_;
    my %config = getVarsFromSh("$prefix/etc/sysconfig/keyboard");
    \%config;
}

sub read {
    my ($prefix) = @_;
    my $keytable = read_raw($prefix)->{KEYTABLE};
    keyboard2kmap($_) eq $keytable and return $_ foreach keys %keyboards;
    $keyboards{$keytable} && $keytable; #- keep track of unknown keyboard.
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
