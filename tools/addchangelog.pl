#!/usr/bin/perl

@ARGV == 2 or die "usage $0: <dir> <cvslog2changelog script>\n";

($dir, $script) = @ARGV;

chomp(my $cwd = `pwd`);
$script = "$cwd/$script" if $script !~ m|^/|;

chdir $dir;
$date = (split('/', `grep ChangeLog CVS/Entries`))[3];

@changelog = `cvs log -d ">$date" | $script`;
@before = `cat ChangeLog`;

print foreach @changelog;

open F, ">ChangeLog";
print F foreach @changelog, @before;

system(q(cvs commit -m "New snapshot uploaded" ChangeLog));
