#!/usr/bin/perl

use strict;
use MDK::Common;

#- there are programs/packages which fail when the directory
#- in which they try to write doesn't exist. better collect them
#- at build time so that drakx startup can create them.

chdir $ARGV[0];
foreach (`find etc var -type d`) {
    chomp;
    my @l = stat($_);
    printf "%o %d %d %s\n", $l[2] & 07777, $l[4], $l[5], $_;
}
