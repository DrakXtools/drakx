package keyboard;

use diagnostics;
use strict;

use common qw(:common :system :file);
use run_program;
use log;
use c;


my $KMAP_MAGIC = 0x8B39C07F;

my %lang2keyboard =
(
  "en" => "us",
);

1;


# [1] = name for loadkeys, [2] = extension for Xmodmap
my @fields =
my %keyboards = (
 "be" => [ __("Belgian"),        "be-latin1",   "be" ],
 "bg" => [ __("Bulgarian"),      "bg",          "bg" ],
 "fr" => [ __("French"),         "fr-latin1",   "fr" ],
 "gr" => [ __("Greek"),          "gr-8859_7",   "gr" ],
 "pt" => [ __("Portuguese"),     "pt-latin1",   "pt" ],
# the xmodmap.pl has to be fixed to use latin2 keymaps
# "pl" => [ __("Polish"),         "pl-latin2",   "pl" ],
 "sk" => [ __("Slovakian"),      "sk-latin2",   "sk" ],
 "hu" => [ __("Hungarian"),      "hu-latin2",   "hu" ],
 "tr_f"  => [ __("Turkish (traditional \"F\" model)"), "tr_f-latin5", "tr_f" ],
 "tr_q" => [ __("Turkish (modern \"Q\" model)"), "tr_q-latin5", "tr_q" ],
 "cz" => [ __("Czech"),          "cz-latin2",   "cz" ],
 "qc" => [ __("Canadian (Quebec)"), "qc-latin1", "qc" ],
 "de" => [ __("German"),         "de-latin1",   "de" ],
 "il" => [ __("Israelian"),      "il-8859_8",   "il" ],
 "ru" => [ __("Russian"),        "ru-koi8",     "ru" ],
 "uk" => [ __("UK keyboard"),    "uk-latin1",   "uk" ],
 "us" => [ __("US keyboard"),    "us-latin",    "us" ],
 "dk" => [ __("Danish"),         "dk-latin1",   "dk" ],
 "is" => [ __("Icelandic"),      "is-latin1",   "is" ],
"dvorak" => [ __("Dvorak"),      "dvorak",      "dvorak" ],
 "la" => [ __("Latin American"), "la-latin1",   "la" ],
 "it" => [ __("Italian"),        "it-latin1",   "it" ],
 "sf" => [ __("Swiss (french layout)"), "sf-latin1", "sf" ],
 "yu" => [ __("Yugoslavian (latin layout)"), "yu-latin2", "yu" ],
 "fi" => [ __("Finnish"),        "fi-latin1",   "fi" ],
 "nl" => [ __("Dutch"),          "nl-latin1",   "nl" ],
 "sg" => [ __("Swiss (german layout)"), "sg-latin1", "sg" ],
 "no" => [ __("Norwegian"),      "no-latin1",   "no" ],
 "si" => [ __("Slovenian"),      "si-latin1",   "si" ],
# the xmodmap.th has to be fixed to use tis620 keymaps
# "th" => [ __("Thai keyboard"),  "th",          "th" ],
# armenian xmodmap have to be checked...
# "am" => [ __("Armenian"),       "am-armscii8",  "am" ],
# georgian keyboards have to be written...
#"ge_ru"=>[__("Georgian (\"Russian\" layout)","ge_ru-georgian_academy","ge_ru"],
#"ge_la"=>[__("Georgian ("\Latin\" layout)","ge_la-georgian_academy","ge_ru"], 
);

sub list { map { $_->[0] } values %keyboards }
sub keyboard2text { $keyboards{$_[0]} && $keyboards{$_[0]}[0] }
sub text2keyboard {
    my ($t) = @_;
    while (my ($k, $v) = each %keyboards) {
        lc($v->[0]) eq lc($t) and return $k;
    }
    die "unknown keyboard $t";
}

sub lang2keyboard($) {
    local ($_) = @_;
    $keyboards{$_} && $_ || $lang2keyboard{$_} || substr($_, 0, 2);    
}

sub load($) {
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
    log::l("loaded $count keymap tables");
}

sub setup($) {
    my ($keyboard) = @_;
    my $o = $keyboards{$keyboard} or return;

    my $file = "/usr/share/keymaps/$o->[1].kmap";
    if (-e $file) {
	log::l("loading keymap $o->[1]");
	load(cat_($file));
    }
    eval { run_program::run('xmodmap', "/usr/share/xmodmap/xmodmap.$o->[2]") };

    $keyboard;
}

sub write($$) {
    my ($prefix, $keyboard) = @_;
    my $o = $keyboards{$keyboard} or return;

    local *F;
    open F, ">$prefix/etc/sysconfig/keyboard" or die "failed to create keyboard configuration: $!";
    print F "KEYTABLE=$o->[1]\n" or die "failed to write keyboard configuration: $!";

    run_program::rooted($prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or die "dumpkeys failed";
}

sub read($) {
    my ($file) = @_;

    local *F;
    open F, "$file" or die "failed to read keyboard configuration";

    foreach (<F>) {
	($_) = /^KEYTABLE=(.*)/ or log::l("unrecognized entry in keyboard configuration file ($_)"), next;
	s/^\s*"(.*)"\s*$/$1/;
	s/\.[^.]*//; # remove extension
	return basename($_);
    }
    die "empty keyboard configuration file";
}
