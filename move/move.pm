package move; # $Id$ $

use diagnostics;
use strict;

use common;
use fs;
use run_program;
use log;


#- run very soon at stage2 start, setup things on tmpfs rw / that
#- were not necessary to start stage2 itself (there were setup
#- by stage1 of course)
sub init {
    #- rw things
    mkdir "/$_" foreach qw(home mnt root etc var);
    mkdir_p "/var/$_" foreach qw(log run spool lib/xkb lock/subsys);
    mkdir_p "/etc/$_" foreach qw(X11);
    touch '/etc/modules.conf';
    symlinkf "/proc/mounts", "/etc/mtab";
 
    #- ro things
    symlinkf "/image/etc/$_", "/etc/$_" 
      foreach qw(alternatives passwd group shadow man.config services shells pam.d security inputrc ld.so.conf 
                 DIR_COLORS bashrc profile profile.d rc.d init.d devfsd.conf devfs gtk-2.0 pango fonts modules.devfs 
                 dynamic gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache);

    #- free up stage1 memory
    fs::umount($_) foreach qw(/stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    run_program::rooted('', '/sbin/devfsd', '/dev');
}


sub automatic_xconf {
    my ($o) = @_;
    log::l('automatic XFree configuration');

    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure({ KEYBOARD => 'us' }, $o->{mouse});

    require Xconfig::main;
    require class_discard;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {},
                                                     { allowNVIDIA_rpms => [], allowATI_rpms => [] });
}


1;
