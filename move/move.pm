package move; # $Id$ $

use diagnostics;
use strict;

use common;
use fs;
use run_program;


#- run very soon at stage2 start, setup things on tmpfs rw / that
#- were not necessary to start stage2 itself (there were setup
#- by stage1 of course)
sub init {
    mkdir "/$_" foreach qw(home mnt root etc var);
    mkdir_p "/var/$_" foreach qw(log run spool lib/xkb lock/subsys);
 
    symlinkf "/image/etc/$_", "/etc/$_" foreach qw(alternatives passwd group shadow man.config services shells pam.d security inputrc ld.so.conf DIR_COLORS bashrc profile profile.d rc.d init.d devfsd.conf devfs gtk-2.0 pango fonts);
    symlinkf "/proc/mounts", "/etc/mtab";

    fs::umount($_) foreach qw(/stage1/proc /stage1);
    fs::mount("none", "/dev", "devfs", 0);
    run_program::rooted('', '/sbin/devfsd', '/dev');
}


1;
