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
#- beware only the first 5 characters of the locale are used
my %lang2keyboard =
(
  'af' => 'us_intl',
#-'ar' => 'ar:80 ar_d:70 ar_azerty:60 ar_azerty_d:50',
  'az' => 'az:80 tr_q:10 us_intl:5',
  'be' => 'by:80 ru:50 ru_yawerty:40',
  'bg' => 'bg_phonetic:60 bg:50',
  'bn' => 'ben:80 dev:20 us_intl:5',
  'br' => 'fr:90',
  'bs' => 'bs:90',
  'ca' => 'es:89 fr:15',
  'cs' => 'cz_qwerty:70 cz:50',
  'cy' => 'uk:90',
  'da' => 'dk:90',
  'de' => 'de_nodeadkeys:70 de:50',
'de_AT'=> 'de_nodeadkeys:70 de:50',
'de_BE'=> 'be:70 de_nodeadkeys:60 de:50',
'de_CH'=> 'ch_de:70 ch_fr:25 de_nodeadkeys:20 de:15',
'de_DE'=> 'de_nodeadkeys:70 de:50', 
'de_LU'=> 'de_nodeadkeys:70 de:50 fr:40 be:35', 
  'el' => 'gr:90',
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
  'fa' => 'ir:90',
  'fi' => 'fi:90',
  'fr' => 'fr:90',
'fr_BE'=> 'be:85 fr:5',
'fr_CA'=> 'qc:85 fr:5',
'fr_CH'=> 'ch_fr:70 ch_de:15 fr:10',
'fr_FR'=> 'fr:90',
'fr_LU'=> 'fr:70 de_nodeadkeys:50 de:40 be:35', 
  'ga' => 'uk:90',
  'gd' => 'uk:90',
  'gl' => 'es:90',
  'gu' => 'guj:90',
  'gv' => 'uk:90',
  'he' => 'il:89 il_phonetic:10',
  'hi' => 'dev:90',
  'hr' => 'hr:80 si:50',
  'hu' => 'hu:90',
  'hy' => 'am:80 am_old:10 am_phonetic:5',
  'id' => 'us:90 us_intl:20',
  'is' => 'is:90',
  'iu' => 'iu:90',
  'it' => 'it:90',
'it_CH'=> 'ch_fr:80 ch_de:60 it:50',
'it_IT'=> 'it:90',
  'ja' => 'jp:80 us:50 us_intl:20',
  'ka' => 'ge_la:80 ge_ru:50',
  'kl' => 'dk:80 us_intl:30',
  'ko' => 'kr:80 us:60',
  'kw' => 'uk:90',
  'lo' => 'lao:90',
  'lt' => 'lt:80 lt_new:70 lt_b:60 lt_p:50',
  'lv' => 'lv:80 lt:40 lt_new:30 lt_b:20 lt_p:10 ee:5',
  'mi' => 'us_intl:60 uk:20 us:10',
  'mk' => 'mk:80',
  'mn' => 'mng:75 ru:20 ru_yawerty:5',
  'mr' => 'dev:90',
  'ms' => 'us:90 us_intl:20',
  'mt' => 'mt:55 mt_us:35 us_intl:10',
  'my' => 'mm:90',
  'nb' => 'no:85 dvorak_no:10',
'nl_BE'=> 'be:80 nl:10 us_intl:5',
'nl_NL'=> 'us_intl:80 nl:15 us:10 uk:5',
  'nn' => 'no:85 dvorak_no:10',
  'no' => 'no:85 dvorak_no:10',
  'oc' => 'fr:90',
  'pa' => 'gur:90',
  'ph' => 'us:90 us_intl:20',
  'pl' => 'pl:80 pl2:60',
  'pp' => 'br:80 la:20 pt:10 us_intl:30',
'pt_BR'=> 'br:80 la:20 pt:10 us_intl:30',
'pt_PT'=> 'pt:80',
  'ro' => 'ro2:80 ro:40 us_intl:10',
  'ru' => 'ru:85 ru_yawerty:80',
'ru_RU'=> 'ru:85 ru_yawerty:80',
'ru_UA'=> 'ua:50 ru:40 ru_yawerty:30',
  'sk' => 'sk_qwerty:80 sk:70',
  'sl' => 'si:80 hr:50',
  'sp' => 'sr:80',
'sp_YU'=> 'sr:80',
  'sq' => 'al:80',
  'sr' => 'yu:80',
'sr_YU'=> 'yu:80',
  'sv' => 'se:85 fi:30 dvorak_se:10',
'sv_FI'=> 'fi:85 sv:20',
'sv_SE'=> 'se:85 fi:20',
  'ta' => 'tscii:80 tml:20',
  'tg' => 'tj:80 ru_yawerty:40',
  'th' => 'th:90',
  'tr' => 'tr_q:85 tr_q:30',
  'tt' => 'ru:50 ru_yawerty:40',
  'uk' => 'ua:85 ru:50 ru_yawerty:40',
  'uz' => 'us:80',
  'vi' => 'vn:80 us:60 us_intl:50',
  'wa' => 'be:85 fr:5',
'zh_CN'=> 'us:60',
'zh_HK'=> 'us:60',
'zh_TW'=> 'us:60',
);

# USB kbd table
# The numeric values are the bCountryCode field (5th byte)  of HID descriptor
my @usb2keyboard =
(
  qw(SKIP ar_SKIP be ca_SKIP qc cz dk fi fr de gr il hu us_intl it jp),
#- 0x10
  qw(kr la nl no ir pl pt ru sk es se ch_de ch_de ch_de tw_SKIP tr_q),
#- 0x20
  qw(uk us yu tr_f),
#- higher codes not attribued as of 2002-02
);

#- key = extension for Xmodmap file, [0] = description of the keyboard,
#- [1] = name for loadkeys, [2] = name for XKB, [3] = "1" if it is
#- a multigroup layout (eg: one with latin/non-latin letters)
my %keyboards = (
arch() =~ /^sparc/ ? (
 "cz" => [ __("Czech (QWERTZ)"), "sunt5-cz-us",	    "cz",    0 ],
 "de" => [ __("German"),         "sunt5-de-latin1", "de",    0 ],
 "dvorak" => [ __("Dvorak"),     "sundvorak",       "dvorak",0 ],
 "es" => [ __("Spanish"),        "sunt5-es",        "es",    0 ],
 "fi" => [ __("Finnish"),        "sunt5-fi-latin1", "fi",    0 ],
 "fr" => [ __("French"),         "sunt5-fr-latin1", "fr",    0 ],
 "no" => [ __("Norwegian"),      "sunt4-no-latin1", "no",    0 ],
 "pl" => [ __("Polish"),         "sun-pl-altgraph", "pl",    0 ],
 "ru" => [ __("Russian"),        "sunt5-ru",        "ru",    1 ],
# TODO: check the console map
 "se" => [ __("Swedish"),        "sunt5-fi-latin1", "se",    0 ],
 "uk" => [ __("UK keyboard"),    "sunt5-uk",        "gb",    0 ],
 "us" => [ __("US keyboard"),    "sunkeymap",       "us",    0 ],
) : (
 "al" => [ __("Albanian"),       "al",              "al",    0 ],
 "am_old" => [ __("Armenian (old)"),"am_old",	    "am(old)", 1 ],
 "am" => [ __("Armenian (typewriter)"),"am-armscii8","am",   1 ],
 "am_phonetic" => [ __("Armenian (phonetic)"),"am_phonetic","am(phonetic)",1 ],
#-"ar_azerty" => [ __("Arabic (AZERTY)"),"ar-8859_6","ar(azerty)",1 ],
#-"ar_azerty_d" => [ __("Arabic (AZERTY, arabic digits)"),"ar-8859_6","ar(azerty_digits)",1 ],
#-"ar" => [ __("Arabic (QWERTY)"),"ar-8859_6",      "ar",    1 ],
#-"ar_d" => [ __("Arabic (QWERTY, arabic digits)"),"ar-8859_6","ar(digits)",1 ],
 "az" => [ __("Azerbaidjani (latin)"),"az",         "az",    0 ],
#"a3" => [ __("Azerbaidjani (cyrillic)"), "az-koi8k","az(cyrillic)",1 ],
 "be" => [ __("Belgian"),        "be2-latin1",      "be",    0 ],
 "ben"=> [ __("Bengali"),        "us",              "ben",   1 ],
"bg_phonetic" => [ __("Bulgarian (phonetic)"),"bg", "bg(phonetic)", 1 ],
 "bg" => [ __("Bulgarian (BDS)"), "bg",             "bg",    1 ],
 "br" => [ __("Brazilian (ABNT-2)"),"br-abnt2",     "br",    0 ],
#- Bosnia and Croatia use the same layout, but people are confused if there
#- isn't an antry for their country
 "bs" => [ __("Bosnian"),	 "croat",           "hr",    0 ],
 "by" => [ __("Belarusian"),      "by-cp1251",      "by",    1 ],
 "ch_de" => [ __("Swiss (German layout)"), "sg-latin1", "de_CH", 0 ],
 "ch_fr" => [ __("Swiss (French layout)"), "fr_CH-latin1", "fr_CH", 0 ],
 "cz" => [ __("Czech (QWERTZ)"), "cz-latin2",       "cz",    0 ],
 "cz_qwerty" => [ __("Czech (QWERTY)"), "cz-lat2", "cz_qwerty", 0 ],
 "de" => [ __("German"),         "de-latin1",       "de",    0 ],
 "de_nodeadkeys" => [ __("German (no dead keys)"), "de-latin1-nodeadkeys", "de(nodeadkeys)", 0 ],
 "dev" => [ __("Devanagari"),     "us",              "dev",   0 ],
 "dk" => [ __("Danish"),         "dk-latin1",       "dk",    0 ],
 "dvorak" => [ __("Dvorak (US)"), "pc-dvorak-latin1", "dvorak", 0 ],
 "dvorak_no" => [ __("Dvorak (Norwegian)"), "no-dvorak", "dvorak(no)", 0 ],
 "dvorak_se" => [ __("Dvorak (Swedish)"), "se-dvorak", "dvorak(se)", 0 ],
 "ee" => [ __("Estonian"),       "ee-latin9",       "ee",    0 ],
 "es" => [ __("Spanish"),        "es-latin1",       "es",    0 ],
 "fi" => [ __("Finnish"),        "fi-latin1",       "fi",    0 ],
 "fr" => [ __("French"),         "fr-latin1",       "fr",    0 ],
 "ge_ru"=>[__("Georgian (\"Russian\" layout)"),"ge_ru-georgian_academy","ge_ru",1],
 "ge_la"=>[__("Georgian (\"Latin\" layout)"),"ge_la-georgian_academy","ge_la",1],
 "gr" => [ __("Greek"),          "gr-8859_7",       "el",    1 ],
 "guj"=> [ __("Gujarati"),       "us",              "guj",   1 ],
 "gur"=> [ __("Gurmukhi"),       "us",              "gur",   1 ],
 "hu" => [ __("Hungarian"),      "hu-latin2",       "hu",    0 ],
 "hr" => [ __("Croatian"),	 "croat",           "hr",    0 ],
 "il" => [ __("Israeli"),        "il-8859_8",       "il",    1 ],
 "il_phonetic" => [ __("Israeli (Phonetic)"), "hebrew", "il_phonetic", 1 ],
 "ir" => [ __("Iranian"),        "ir-isiri_3342",   "ir",    1 ],
 "is" => [ __("Icelandic"),      "is-latin1",       "is",    0 ],
 "it" => [ __("Italian"),        "it-latin1",       "it",    0 ],
 "iu" => [ __("Inuktitut"),      "us",              "iu",    1 ],
 "jp" => [ __("Japanese 106 keys"), "jp106",        "jp",    1 ],
#There is no XKB korean file yet; but using xmodmap one disables
# some functioanlity; "us" used for XKB until this is fixed
 "kr" => [ __("Korean keyboard"), "us",             "us",    1 ],
 "la" => [ __("Latin American"), "la-latin1",       "la",    0 ],
 "lao"=> [ __("Laotian"),	 "us",	            "lao",   1 ], 
 "lt" => [ __("Lithuanian AZERTY (old)"), "lt-latin7", "lt_a", 0 ],
#- TODO: write a console kbd map for lt_new
 "lt_new" => [ __("Lithuanian AZERTY (new)"), "lt-latin7", "lt_std", 0 ],
 "lt_b" => [ __("Lithuanian \"number row\" QWERTY"), "ltb-latin7", "lt", 0 ],
 "lt_p" => [ __("Lithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt_p", 0 ],
 "lv" => [ __("Latvian"),	 "lv-latin7",       "lv",    0 ],
 "mk" => [ __("Macedonian"),	 "mk",              "mk",    1 ],
 "mm" => [ __("Myanmar (Burmese)"),"us",            "mm",    1 ],
 "mng"=> [ __("Mongolian (cyrillic)"),"us",         "mng",   1 ],
 "mt" => [ __("Maltese (UK)"),   "uk",              "mt",    0 ],
 "mt_us" => [ __("Maltese (US)"),"us",              "mt_us", 0 ],
 "nl" => [ __("Dutch"),          "nl-latin1",       "nl",    0 ],
 "no" => [ __("Norwegian"),      "no-latin1",       "no",    0 ],
 "pl" => [ __("Polish (qwerty layout)"), "pl",      "pl",    0 ],
 "pl2" => [ __("Polish (qwertz layout)"), "pl-latin2", "pl2", 0 ],
 "pt" => [ __("Portuguese"),     "pt-latin1",       "pt",    0 ],
 "qc" => [ __("Canadian (Quebec)"), "qc-latin1", "ca_enhanced", 0 ],
#- TODO: write a console kbd map for ro2
 "ro2" => [ __("Romanian (qwertz)"), "ro2",         "ro2",   0 ],
 "ro" => [ __("Romanian (qwerty)"), "ro",           "ro",    0 ],
 "ru" => [ __("Russian"),        "ru4",             "ru(winkeys)", 1 ],
 "ru_yawerty" => [ __("Russian (Yawerty)"), "ru-yawerty", "ru_yawerty", 1 ],
 "se" => [ __("Swedish"),        "se-latin1",       "se",    0 ],
 "si" => [ __("Slovenian"),      "slovene",         "si",    0 ],
 "sk" => [ __("Slovakian (QWERTZ)"), "sk-qwertz",   "sk",    0 ],
 "sk_qwerty" => [ __("Slovakian (QWERTY)"), "sk-qwerty", "sk_qwerty", 0 ],
# TODO: console map
 "sr" => [ __("Serbian (cyrillic)"), "sr",          "sr",    0 ],
# no console kbd that I'm aware of
 "tml" => [ __("Tamil (Unicode)"), "us",            "tml",   1 ],
 "tscii" => [ __("Tamil (TSCII)"), "us",            "tscii", 1 ],
 "th" => [ __("Thai keyboard"),  "th",              "th",    1 ],
# TODO: console map
 "tj" => [ __("Tajik keyboard"), "ru4",             "tj",    1 ],
 "tr_f" => [ __("Turkish (traditional \"F\" model)"), "trf", "tr_f", 0 ],
 "tr_q" => [ __("Turkish (modern \"Q\" model)"), "tr_q-latin5", "tr", 0 ],
#-"tw => [ __("Chineses bopomofo"), "tw",           "tw",    1 ],
 "ua" => [ __("Ukrainian"),      "ua",              "ua",    1 ],
 "uk" => [ __("UK keyboard"),    "uk",              "gb",    0 ],
 "us" => [ __("US keyboard"),    "us",              "us",    0 ],
 "us_intl" => [ __("US keyboard (international)"), "us-latin1", "us_intl", 0 ],
 "vn" => [ __("Vietnamese \"numeric row\" QWERTY"),"vn-tcvn", "vn(toggle)", 0 ], 
 "yu" => [ __("Yugoslavian (latin)"), "sr",         "yu",    0 ],
),
);

#- list of  possible choices for the key combinations to toggle XKB groups
#- (eg in X86Config file: XkbOptions "grp:toggle")
my %grp_toggles = (
    toggle => _("Right Alt key"),
    shift_toggle => _("Both Shift keys simultaneously"),
    ctrl_shift_toggle => _("Control and Shift keys simultaneously"),
    caps_toggle => _("CapsLock key"),
    ctrl_alt_toggle => _("Ctrl and Alt keys simultaneously"),
    alt_shift_toggle => _("Alt and Shift keys simultaneously"),
    menu_toggle => _("\"Menu\" key"),
    lwin_toggle => _("Left \"Windows\" key"),
    rwin_toggle => _("Right \"Windows\" key"),
);


#-######################################################################################
#- Functions
#-######################################################################################
sub KEYBOARDs { keys %keyboards }
sub KEYBOARD2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboards { map { { KEYBOARD => $_ } } keys %keyboards }
sub keyboard2one {
    my ($keyboard, $nb) = @_;
    ref $keyboard or internal_error();
    my $l = $keyboards{$keyboard->{KEYBOARD}} or return;
    $l->[$nb];
}
sub keyboard2text { keyboard2one($_[0], 0) }
sub keyboard2kmap { keyboard2one($_[0], 1) }
sub keyboard2xkb  { keyboard2one($_[0], 2) }

sub grp_toggles {
    my ($keyboard) = @_;
    keyboard2one($keyboard, 3) or return;
    \%grp_toggles;
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
	#- first try with the 5 first chars of LANG; if it fails then try with
	#- with the 2 first chars of LANG before resorting to default. 
	unpack_keyboards($lang2keyboard{substr($_, 0, 5)}) || unpack_keyboards($lang2keyboard{substr($_, 0, 2)}) || [ [ ($keyboards{$_} ? $_ : "us") => 100 ] ];
    } @_;
    \@li;
}
sub lang2keyboard {
    my ($l) = @_;
    my $kb = lang2keyboards($l)->[0][0];
    { KEYBOARD => $keyboards{$kb} ? $kb : 'us' }; #- handle incorrect keyboard mapping to us.
}

sub from_usb {
    return if $::noauto;
    my ($usb_kbd) = detect_devices::usbKeyboards() or return;
    my $country_code = detect_devices::usbKeyboard2country_code($usb_kbd) or return;
    my $keyboard = $usb2keyboard[$country_code];
    $keyboard !~ /SKIP/ && { KEYBOARD => $keyboard };
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
    my $KEYBOARD = $keyboard->{KEYBOARD};
    my $f = "$ENV{SHARE_PATH}/xmodmap/xmodmap.$KEYBOARD";
    if (! -e $f) {
	eval {
	    require packdrake;
	    my $packer = new packdrake("$ENV{SHARE_PATH}/xmodmap.cz2", quiet => 1);
	    $packer->extract_archive("/tmp", "xmodmap.$KEYBOARD");
	};
	$f = "/tmp/xmodmap.$KEYBOARD";
    }
    -e $f && $f;
}

sub setup {
    my ($keyboard) = @_;

    return if arch() =~ /^sparc/;

    #- Xpmac doesn't map keys quite right
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
		$packer->extract_archive(undef, "$kmap.bkmap");
	    };
	    c::_exit(0);
	}
    }
    my $f = xmodmap_file($keyboard);
    eval { run_program::run('xmodmap', $f) } if $f && !$::testing && $ENV{DISPLAY};
}

sub write {
    my ($keyboard) = @_;
    log::l("keyboard::write $keyboard->{KEYBOARD}");

    $keyboard = { %$keyboard };
    delete $keyboard->{unsafe};
    $keyboard->{KEYTABLE} = keyboard2kmap($keyboard);

    setVarsInSh("$::prefix/etc/sysconfig/keyboard", $keyboard);
    run_program::rooted($::prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or log::l("dumpkeys failed");
    if (arch() =~ /ppc/) {
	my $s = "dev.mac_hid.keyboard_sends_linux_keycodes = 1\n";
	substInFile { 
            $_ = '' if /^\Qdev.mac_hid.keyboard_sends_linux_keycodes/;
            $_ .= $s if eof;
        } "$::prefix/etc/sysctl.conf";
    }
}

sub read {
    my %keyboard = getVarsFromSh("$::prefix/etc/sysconfig/keyboard") or return {};
    if (!$keyboard{KEYBOARD}) {
	add2hash(\%keyboard, grep { keyboard2kmap($_) eq $keyboard{KEYTABLE} } keyboards());
    }
    $keyboard{DISABLE_WINDOWS_KEY} = bool2yesno(detect_devices::isLaptop());

    keyboard2text(\%keyboard) ? \%keyboard : {};
}

sub check {
    require lang;
    $^W = 0;

    my $ok = 1;
    my $warn = sub {
	print STDERR "$_[0]\n";
    };
    my $err = sub {
	&$warn;
	$ok = 0;
    };

    if (my @l = grep { is_empty_array_ref(lang2keyboards($_)) } lang::list()) {
	$warn->("no keyboard for langs " . join(" ", @l));
    }
    foreach my $lang (lang::list()) {
	my $l = lang2keyboards($lang);
	foreach (@$l) {
	    0 <= $_->[1] && $_->[1] <= 100 or $err->("invalid value $_->[1] in $lang2keyboard{$lang} for $lang in \%lang2keyboard keyboard.pm");
	    $keyboards{$_->[0]} or $err->("invalid keyboard $_->[0] in $lang2keyboard{$lang} for $lang in \%lang2keyboard keyboard.pm");
	}
    }
    /SKIP/ || $keyboards{$_} or $err->("invalid keyboard $_ in \@usb2keyboard keyboard.pm") foreach @usb2keyboard;
    $usb2keyboard[0x21] eq 'us' or $err->("\@usb2keyboard is badly modified, 0x21 is not us keyboard");

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

    exit($ok ? 0 : 1);
}

1;
