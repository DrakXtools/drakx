#!/usr/bin/perl

# check if files are more recent (fc-cache will slow down starting of drakx)

use MDK::Common;

sub stat_ {
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat $_[0];
    max($mtime, $ctime);
}

my $prefix = $ARGV[0] || '/tmp/live_tree';

my @conf = cat_("$prefix/etc/fonts/fonts.conf");

foreach my $line (@conf) {
    while ($line =~ m|<dir>([^<]+)</dir|g) {
        my $dir = $1;
        $dir =~ m|^/| or next;
        print "dir $prefix$dir\n";
        foreach my $d (chomp_(`find $prefix$dir -type d 2>/dev/null`)) {
            my $ref = stat_("$d/fonts.cache-1");
            stat_($_) > $ref and print "\t$_\n" foreach glob("$d/*");
        }
    }
}

