
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
  'az' => 'az:80 tr:10 us_intl:5',
  'be' => 'by:80 ru:50 ru_yawerty:40',
  'bg' => 'bg_phonetic:60 bg:50',
  'br' => 'fr:90',
  'bs' => 'hr:60 yu:50 si:40',
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
  'gv' => 'uk:90',
  'he' => 'il:89 il_phonetic:10',
  'hr' => 'hr:80 si:50',
  'hu' => 'hu:90',
  'hy' => 'am:80 am_old:10 am_phonetic:5',
  'id' => 'us:90 us_intl:20',
  'is' => 'is:90',
  'iu' => 'iu:90',
  'it' => 'it:90',
'it_CH' => 'ch_fr:80 ch_de:60 it:50',
'it_IT' => 'it:90',
  'ja' => 'jp:80 us:50 us_intl:20',
  'ka' => 'ge_la:80 ge_ru:50',
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
  'sq' => 'al:80',
  'sr' => 'yu:80',
  'sv' => 'se:85 fi:30 dvorak_se:10',
'sv_FI'=> 'fi:85 sv:20',
'sv_SE'=> 'se:85 fi:20',
  'ta' => 'tml:80',
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
my %usb2drakxkbd =
(
  0x00 => undef, #- the keyboard don't tell its layout
#-0x01 => 'ar',
  0x02 => 'be',
#-0x03 => 'ca', #- "Canadian bilingual" ??
  0x04 => 'qc', #- Canadian French
  0x05 => 'cz',
  0x06 => 'dk',
  0x07 => 'fi',
  0x08 => 'fr',
  0x09 => 'de',
  0x0a => 'gr',
  0x0b => 'il',
  0x0c => 'hu',
  0x0d => 'us_intl', #- "international ISO" ??
  0x0e => 'it',
  0x0f => 'jp',
  0x10 => 'kr', #- Korean
  0x11 => 'la',
  0x12 => 'nl',
  0x13 => 'no',
  0x14 => 'ir',
  0x15 => 'pl',
  0x16 => 'pt',
  0x17 => 'ru',
  0x18 => 'sk',
  0x19 => 'es',
  0x1a => 'se',
  0x1b => 'ch_de',
  0x1c => 'ch_de',
  0x1d => 'ch_de', #- USB spec says just "Swiss"
#-0x1e => 'tw', # Taiwan
  0x1f => 'tr_q',
  0x20 => 'uk',
  0x21 => 'us',
  0x22 => 'yu',
  0x23 => 'tr_f',
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
"bg_phonetic" => [ __("Bulgarian (phonetic)"),"bg", "bg(phonetic)", 1 ],
 "bg" => [ __("Bulgarian (BDS)"), "bg",             "bg",    1 ],
 "br" => [ __("Brazilian (ABNT-2)"),"br-abnt2",     "br",    0 ],
 "by" => [ __("Belarusian"),      "by-cp1251",      "by",    1 ],
 "ch_de" => [ __("Swiss (German layout)"), "sg-latin1", "de_CH", 0 ],
 "ch_fr" => [ __("Swiss (French layout)"), "fr_CH-latin1", "fr_CH", 0 ],
 "cz" => [ __("Czech (QWERTZ)"), "cz-latin2",       "cz",    0 ],
 "cz_qwerty" => [ __("Czech (QWERTY)"), "cz-lat2", "cz_qwerty", 0 ],
 "de" => [ __("German"),         "de-latin1",       "de",    0 ],
 "de_nodeadkeys" => [ __("German (no dead keys)"), "de-latin1-nodeadkeys", "de(nodeadkeys)", 0 ],
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
 "hu" => [ __("Hungarian"),      "hu-latin2",       "hu",    0 ],
 "hr" => [ __("Croatian"),	 "croat",           "hr",    0 ],
 "il" => [ __("Israeli"),        "il-8859_8",       "il",    1 ],
 "il_phonetic" => [ __("Israeli (Phonetic)"), "hebrew", "il_phonetic", 1 ],
 "ir" => [ __("Iranian"),        "ir-isiri_3342",   "ir",    1 ],
 "is" => [ __("Icelandic"),      "is-latin1",       "is",    0 ],
 "it" => [ __("Italian"),        "it-latin1",       "it",    0 ],
#"iu" => [ __("Inuktitut"),      "iu",              "iu",    1 ],
 "jp" => [ __("Japanese 106 keys"), "jp106",        "jp",    1 ],
#There is no XKB korean file yet; but using xmodmap one disables
# some functioanlity; "us" used for XKB until this is fixed
 "kr" => [ __("Korean keyboard"), "us",             "us",    1 ],
 "la" => [ __("Latin American"), "la-latin1",       "la",    0 ],
 "lt" => [ __("Lithuanian AZERTY (old)"), "lt-latin7", "lt_a", 0 ],
#- TODO: write a console kbd map for lt_new
 "lt_new" => [ __("Lithuanian AZERTY (new)"), "lt-latin7", "lt_std", 0 ],
 "lt_b" => [ __("Lithuanian \"number row\" QWERTY"), "ltb-latin7", "lt", 0 ],
 "lt_p" => [ __("Lithuanian \"phonetic\" QWERTY"), "ltp-latin7", "lt_p", 0 ],
 "lv" => [ __("Latvian"),	 "lv-latin7",       "lv",    0 ],
 "mk" => [ __("Macedonian"),	 "mk",              "mk",    1 ],
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
 "tml" => [ __("Tamil"),	 "us",              "tml",   1 ],
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
my %kbdgrptoggle =
(
  'toggle' => _("Right Alt key"),
  'shift_toggle' => _("Both Shift keys simultaneously"),
  'ctrl_shift_toggle' => _("Control and Shift keys simultaneously"),
  'caps_toggle' => _("CapsLock key"),
  'ctrl_alt_toggle' => _("Ctrl and Alt keys simultaneously"),
  'alt_shift_toggle' => _("Alt and Shift keys simultaneously"),
  'menu_toggle' => _("\"Menu\" key"),
  'lwin_toggle' => _("Left \"Windows\" key"),
  'rwin_toggle' => _("Right \"Windows\" key"),
);


#-######################################################################################
#- Functions
#-######################################################################################
sub keyboards { keys %keyboards }
sub keyboard2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub keyboard2kmap { $keyboards{$_[0]} && $keyboards{$_[0]}[1] }
sub keyboard2xkb  { $keyboards{$_[0]} && $keyboards{$_[0]}[2] }

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
    $li->[0][1] ||= 100 if @$li;
    $li;
}
sub lang2keyboard {
    my ($l) = @_;
    my $kb = lang2keyboards($l)->[0][0];
    $keyboards{$kb} ? $kb : "us"; #- handle incorrect keyboad mapping to us.
}
sub usb2drakxkbd {
    my ($cc) = @_;
    my $kb = $usb2drakxkbd{$cc};
#- TODO: detect when undef is returned because it is actualy not defined
#- ($cc == 0) and when it is because of an unknown/not listed number;
#- in that last case it would be nice to display a dialog telling the
#- user to report the number to us.
    $kb;
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
    if (arch() =~ /ppc/) {
	my $s = "dev.mac_hid.keyboard_sends_linux_keycodes = 1\n";
	substInFile { 
            $_ = '' if /^\Qdev.mac_hid.keyboard_sends_linux_keycodes/;
            $_ .= $s if eof;
        } "$prefix/etc/sysctl.conf";
    }
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
    !$_ || $keyboards{$_} or $err->("invalid keyboard $_ in \%usb2drakxkbd keyboard.pm") foreach values %usb2drakxkbd;

    my @xkb_groups = map { if_(/grp:(\S+)/, $1) } cat_('/usr/lib/X11/xkb/rules/xfree86.lst');
    $err->("invalid xkb group toggle '$_' in \%kbdgrptoggle") foreach difference2([ keys %kbdgrptoggle ], \@xkb_groups);
    $warn->("unused xkb group toggle '$_'") foreach difference2(\@xkb_groups, [ keys %kbdgrptoggle ]);

    my @xkb_layouts = (#- (map { (split)[0] } grep { /^! layout/ .. /^\s*$/ } cat_('/usr/lib/X11/xkb/rules/xfree86.lst')),
		       all('/usr/lib/X11/xkb/symbols'),
		       (map { (split)[2] } cat_('/usr/lib/X11/xkb/symbols.dir')));
    $err->("invalid xkb layout $_") foreach difference2([ map { keyboard2xkb($_) } keyboards() ], \@xkb_layouts);

    loadkeys_files($err);

    exit($ok ? 0 : 1);
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
