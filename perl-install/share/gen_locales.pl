#!/usr/bin/perl

use MDK::Common;
use lang;

foreach (lang::list_langs()) {
    my $c = lang::during_install__l2charset($_) or next;
    -e "usr/share/locale/$c" or warn("not handled lang $_ (charset $c)\n"), next;
    if (my $exist = readlink "usr/share/locale/$_") {
	$exist eq $c or die "symlink $_ already exist and is $exist instead of $c\n";
    } else {
	symlink $c, "usr/share/locale/$_" or die "can't create symlink $_";
    }
}
