#!/usr/bin/perl

@ARGV == 1 or die "usage $0: <cvslog2changelog script>\n";

($script) = @ARGV;

$date = (split('/', `grep ChangeLog perl-install/CVS/Entries`))[3];

@changelog = `(cvs log -d ">$date" docs mdk-stage1 rescue tools ; cd perl-install; cvs log -d ">$date") | $script`;
@before = `cat perl-install/ChangeLog`;

open F, ">perl-install/ChangeLog";
print F foreach @changelog, @before;

#`cvs commit -m '' perl-install/ChangeLog` =~ /new revision: (.*?);/;

print "$1\n";
print foreach @changelog;
