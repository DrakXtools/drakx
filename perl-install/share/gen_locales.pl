#!/usr/bin/perl

use MDK::Common;
use lang;

foreach (lang::list_langs()) {
    if (my $exist = readlink "usr/share/locale/$_") {
	die "symlink $_ already exist and is $exist\n";
    } else {
	symlink "en_US.UTF-8", "usr/share/locale/$_" or die "can't create symlink $_";
    }
}
