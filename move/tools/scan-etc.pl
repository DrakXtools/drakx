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

sub stat_ {
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat $_[0];
    [ $atime, max($mtime, $ctime) ];
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

