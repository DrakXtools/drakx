#!/usr/bin/perl

use MDK::Common;

sub outpend { my $f = shift; local *F; open F, ">>$f" or die "outpend in file $f failed: $!\n"; print F foreach @_ }
sub logit { outpend "/var/log/etc-monitorer.log", sprintf("[%s] @_\n", chomp_(`date`)) }

my $machine_ident = cat_('/var/lib/machine_ident');
my $sysconf = "/home/.sysconf/$machine_ident";

foreach my $dir (@ARGV) {
    foreach (glob_("$dir/*")) {
        next if $_ eq '/etc/sudoers';  #- /etc/sudoers can't be a link
        if (-f && !-l) {
            my $dest = "/home/.sysconf/$machine_ident$_";
            mkdir_p(dirname($dest));  #- case of newly created directories
            logit("restoring broken symlink $_ -> $dest");
            system("mv $_ $dest");
            symlink($dest, $_);
        }
    }
}
