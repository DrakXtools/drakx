#!/usr/bin/perl

use MDK::Common;

sub outpend { my $f = shift; local *F; open F, ">>$f" or die "outpend in file $f failed: $!\n"; print F foreach @_ }
sub logit { outpend "/var/log/etc-monitorer.log", sprintf("[%s] @_\n", chomp_(`date`)) }

my $machine_ident = cat_('/var/lib/machine_ident');
my $sysconf = "/home/.sysconf/$machine_ident";

foreach my $dir (@ARGV) {
    my $destdir = "/home/.sysconf/$machine_ident";
    my @etcfiles = glob_("$dir/*");
    foreach (@etcfiles) {
        next if $_ eq '/etc/sudoers';  #- /etc/sudoers can't be a link
        if (-f && !-l) {
            my $dest = "$destdir$_";
            mkdir_p(dirname($dest));  #- case of newly created directories
            logit("restoring broken symlink $_ -> $dest");
            system("mv $_ $dest 2>/dev/null");
            symlink($dest, $_);
        }
    }
    foreach (difference2([ grep { -f && s/^\Q$destdir\E// } glob_("$destdir$dir/*") ], [ @etcfiles ])) {
        logit("removing $destdir$_ because of deleted $_");
        unlink "$destdir$_";
    }
}
