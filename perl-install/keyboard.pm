package keyboard;

use diagnostics;
use strict;
use vars qw($KMAP_MAGIC %defaultKeyboards %loadKeymap);

use common qw(:system :file);
use run_program;
use log;
use c;


$KMAP_MAGIC = 0x8B39C07F;

%defaultKeyboards = (
  "de" => "de-latin1",
  "fr" => "fr-latin1",
  "fi" => "fi-latin1",
  "se" => "se-latin1",
  "no" => "no-latin1",
  "cs" => "cz-lat2",
  "tr" => "trq",
);

1;


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

sub setup(;$) {
    my ($keyboard) = @_;
    my $t; 

    $keyboard ||= $defaultKeyboards{$ENV{LANG}} || "us";

    my $file = "/usr/share/keymaps/$keyboard.kmap";
    if (-e $file) {
	log::l("loading keymap $keyboard");
	load(cat_($file));
    }
    $keyboard;
}

sub write($$) {
    my ($prefix, $keymap) = @_;

    local *F;
    open F, ">$prefix/etc/sysconfig/keyboard" or die "failed to create keyboard configuration: $!";
    print F "KEYTABLE=$keymap\n" or die "failed to write keyboard configuration: $!";

    run_program::rooted($prefix, "dumpkeys > /etc/sysconfig/console/default.kmap") or die "dumpkeys failed";
}

sub read($) {
    my ($file) = @_;

    local *F;
    open F, "$file" or die "failed to read keyboard configuration";

    foreach (<F>) {
	($_) = /^KEYTABLE=(.*)/ or log::l("unrecognized entry in keyboard configuration file ($_)"), next;
	s/\"//g; 
	s/\.[^.]*//; # remove extension
	return basename($_);
    }
    die "empty keyboard configuration file";
}
