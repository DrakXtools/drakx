#!/usr/bin/perl

use strict;
use MDK::Common;

#- there are programs/packages which fail when the directory
#- in which they try to write doesn't exist. better collect them
#- at build time so that drakx startup can create them.

my @list = map { if_(m|^\Q$ARGV[0]\E(.*)$|, $1) } `find $ARGV[0]/{etc,var} -type d`;
my @final;
foreach my $e (sort { length($b) <=> length($a) } @list) {
    any { /^\Q$e\E/ } @final and next;
    push @final, $e;
}

print "$_\n" foreach sort @final;
