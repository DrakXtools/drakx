#!/usr/bin/perl

use MDK::Common;
use lang;

foreach (lang::list()) {
    my $LANG = lang::lang2LANG($_);

    my $c = lang::during_install__lang2charset($_) or next;
    -e "usr/share/locale/$c" or warn("not handled language $_ ($LANG, $c)\n"), next;
    if (my $exist = readlink "usr/share/locale/$LANG") {
	$exist eq $c or die "symlink $LANG already exist and is $exist instead of $c\n";
    } else {
	symlink $c, "usr/share/locale/$LANG" or die "can't create symlink $LANG (for $_)";
    }
}
