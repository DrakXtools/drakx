#!/usr/bin/perl

# touch fontconfig cache files so that fc-cache will not slow down starting of drakx

use MDK::Common;

my ($prefix) = @ARGV or die "usage: $0 <prefix>\n";

my @conf = cat_("$prefix/etc/fonts/fonts.conf");

print "touching fontconfig cache files...\n";
foreach my $line (@conf) {
    while ($line =~ m|<dir>([^<]+)</dir|g) {
        my $dir = $1;
        $dir =~ m|^/| or next;
        foreach my $d (chomp_(`find $prefix$dir -type d 2>/dev/null`)) {
            touch "$d/fonts.cache-1";
        }
    }
}

