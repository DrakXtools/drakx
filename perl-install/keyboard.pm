package keyboard;

use diagnostics;
use strict;
use vars qw($KMAP_MAGIC %defaultKeyboards %loadKeymap);

use common qw(:system :file);
use log;


$KMAP_MAGIC = 0x8B39C07F;

%defaultKeyboards = (
  "de" => "de-latin1",
  "fi" => "fi-latin1",
  "se" => "se-latin1",
  "no" => "no-latin1",
  "cs" => "cz-lat2",
  "tr" => "trq",
);

1;


sub load($) {
    my ($keymap_raw) = @_;

    my ($magic, @keymaps) = unpack "i i" . c::MAX_NR_KEYMAPS() . "a*", $keymap_raw;
    $keymap_raw = pop @keymaps;

    $magic != $KMAP_MAGIC and die "failed to read kmap magic: $!";

    local *F;
    sysopen F, "/dev/console", 2 or die "failed to open /dev/console: $!";

    my $count = 0;
    foreach (0 .. c::MAX_NR_KEYMAPS() - 1) {
	$keymaps[$_] or next;

	my @keymap = unpack "s" . c::NR_KEYS() . "a*", $keymap_raw;
	$keymap_raw = pop @keymap;

	my $key = 0;
	foreach my $value (@keymap) {
	    c::KTYP($value) != c::KT_SPEC() or next;
	    ioctl(F, c::KDSKBENT(), pack("CCS", $_, $key++, $value)) or log::l("keymap ioctl failed: $!");
	    $key++;
	 }
	$count++;
    }
    log::l("loaded $count keymap tables");
    1;
}

sub setup($) {
    my ($defkbd) = @_;
    my $t; 

    #$::testing and return 1;

    $defkbd ||= $defaultKeyboards{$ENV{LANG}} || "us";

    local *F;
    open F, "/etc/keymaps" or die "cannot open /etc/keymaps: $!";

    my $format = "i2";
    read F, $t, psizeof($format) or die "failed to read keymaps header: $!";
    my ($magic, $numEntries) = unpack $format, $t;

    log::l("%d keymaps are available", $numEntries);

    my @infoTable;
    my $format2 = "i Z40";
    foreach (1..$numEntries) {
	read F, $t, psizeof($format2) or die "failed to read keymap information: $!";
	push @infoTable, [ unpack $format2, $t ];
    }

    foreach (@infoTable) {
	read F, $t, $_->[0] or log::l("error reading $_->[0] bytes from file: $!"), return;

	if ($defkbd eq $_->[1]) {
	    log::l("using keymap $_->[1]");
	    load($t) or return;
	    &write("/tmp", $_->[1]) or log::l("write keyboard config failed");
	    return $_->[1];
	}
    }
    undef;
}

sub write($$) {
    my ($prefix, $keymap) = @_;

    $keymap or return 1;
    $::testing and return 1;

    local *F;
    open F, ">$prefix/etc/sysconfig/keyboard" or die "failed to create keyboard configuration: $!";
    print F "KEYTABLE=$keymap\n" or die "failed to write keyboard configuration: $!";

    # write default keymap 
    if (fork) {
	wait;
	$? == 0 or log::l('dumpkeys failed');
    } else  {
	chroot $prefix;
	CORE::system("/usr/bin/dumpkeys > /etc/sysconfig/console/default.kmap 2>/dev/null");
	exit($?);
    }
}

sub read($) {
    my ($file) = @_;

    local *F;
    open F, "$file" or # fail silently -- old bootdisks won't create this 
	log::l("failed to read keyboard configuration (probably ok)"), return;

    foreach (<F>) {
	($_) = /^KEYTABLE=(.*)/ or die "unrecognized entry in keyboard configuration file";
	s/\"//g; 
	s/\.[^.]*//; # remove extension
	return basename($_);
    }
    log::l("empty keyboard configuration file");
    undef;
}
