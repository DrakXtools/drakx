package Xconfig::proprietary; # $Id$

use diagnostics;
use strict;

use common;


sub install_matrox_hal {
    my ($prefix) = @_;
    my $tmpdir = "$prefix/root/tmp";

    my $tar = "mgadrivers-2.0.tgz";
    my $dir_in_tar = "mgadrivers";
    my $dest_dir = "$prefix/usr/X11R6/lib/modules/drivers";

    #- already installed
    return if -e "$dest_dir/mga_hal_drv.o" || $::testing;

    system("wget -O $tmpdir/$tar ftp://ftp.matrox.com/pub/mga/archive/linux/2002/$tar") if !-e "$tmpdir/$tar";
    system("tar xzC $tmpdir -f $tmpdir/$tar");

    my $src_dir = "$tmpdir/$dir_in_tar/xfree86/4.2.1/drivers";
    foreach (all($src_dir)) {
	my $src = "$src_dir/$_";
	my $dest = "$dest_dir/$_";
	rename $dest, "$dest.non_hal";
	cp_af($src, $dest_dir);
    }
    rm_rf("$tmpdir/$tar");
    rm_rf("$tmpdir/$dir_in_tar");
}

1;

