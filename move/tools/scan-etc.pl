#!/usr/bin/perl

# To be used replacing move::init handling of etc files with:
#
#    system("cp -a /image/etc /");
#    symlinkf "/proc/mounts", "/etc/mtab";
#    system("find /etc -type f > /tmp/filelist");
#    touch '/dummy';
#    m|^/var| && !-d $_ and mkdir_p $_ foreach chomp_(cat_('/image/move/directories-to-create'));
#    sleep 2;
#    goto meuh;

use MDK::Common;

sub date_to_raw {
    my ($y, $m, $d, $h, $mi, $s) = $_[0] =~ /\s(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)\./;
    ($y-1970)*32140800 + $m*2678400 + $d*86400 + $h*3600 + $mi*60 + $s;
}

sub stat_ {
    my ($f) = @_;

    my (undef, undef, undef, undef, $a, $m, $c) = `stat $f`;

    my $araw = date_to_raw($a);
    my $mraw = max(date_to_raw($m), date_to_raw($c));

    [ $araw, $mraw ];
}

our $reference = (stat_('/dummy'))->[0];

our @old_filelist = chomp_(cat_("/tmp/filelist"));
foreach (chomp_(`find /etc -type f`)) {
    if (!member($_, @old_filelist)) {
        push @new, $_;
    } else {
        $times = stat_($_);
        $times->[0] > $reference and push @read, $_;
        $times->[1] > $reference and push @wrote, $_;
    }
}

print "read:\n";
print "\t$_\n" foreach sort @read;

print "wrote:\n";
print "\t$_\n" foreach sort @wrote;

print "new:\n";
print "\t$_\n" foreach sort @new;

