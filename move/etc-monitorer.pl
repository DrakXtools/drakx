#!/usr/bin/perl

use MDK::Common;

sub outpend { my $f = shift; local *F; open F, ">>$f" or die "outpend in file $f failed: $!\n"; print F foreach @_ }
sub logit { outpend "/var/log/etc-monitorer.log", sprintf("[%s] @_\n", chomp_(`date`)) }

foreach my $dir (@ARGV) {
    my $destdir = '/home/.sysconf/' . cat_('/var/lib/machine_ident');
    my @etcfiles = glob_("$dir/*");
    foreach (@etcfiles) {
        if ($_ eq '/etc/sudoers'           #- /etc/sudoers can't be a link
	    || $_ eq '/etc/mtab'           #- same for /etc/mtab
            || !-f                                 
            || -l && readlink =~ m|^/|) {  #- we want to trap relative symlinks only
            next;
        }
        my $dest = "$destdir$_";
        mkdir_p(dirname($dest));  #- case of newly created directories
        logit("restoring broken symlink $_ -> $dest");
        if (-l) {
            system("cp $_ $dest 2>/dev/null");
        } else {
            system("mv $_ $dest 2>/dev/null");
        }
        symlinkf($dest, $_);
    }
    foreach (difference2([ grep { -f && s/^\Q$destdir\E// } glob_("$destdir$dir/*") ], [ @etcfiles ])) {
        logit("removing $destdir$_ because of deleted $_");
        unlink "$destdir$_";
    }
}
