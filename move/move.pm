package move; # $Id$ $

use diagnostics;
use strict;

use modules;
use common;
use fs;
use run_program;
use log;
use lang;

my @ALLOWED_LANGS = qw(en_US fr es it de);

#- run very soon at stage2 start, setup things on tmpfs rw / that
#- were not necessary to start stage2 itself (there were setup
#- by stage1 of course)
sub init {
    my ($o) = @_;
    #- rw things
    mkdir "/$_" foreach qw(home mnt root etc var);
    mkdir_p "/var/$_" foreach qw(log run/console spool lib/xkb lock/subsys);
    mkdir_p "/etc/$_" foreach qw(X11);
    touch '/etc/modules.conf';
    symlinkf "/proc/mounts", "/etc/mtab";
 
    #- ro things
    symlinkf "/image/etc/$_", "/etc/$_" 
      foreach qw(alternatives shadow man.config services shells pam.d security inputrc ld.so.conf 
                 DIR_COLORS bashrc profile profile.d rc.d init.d devfsd.conf devfs gtk-2.0 pango fonts modules.devfs 
                 dynamic gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache);
    symlinkf "/image/etc/X11/$_", "/etc/X11/$_"
      foreach qw(encodings.dir app-defaults applnk fs lbxproxy proxymngr rstart wmsession.d xinit.d xinit xkb xserver xsm);

    #- to be able to adduser, one need to have /etc/passwd and /etc/group writable
    cp_af("/image/etc/$_", "/etc") foreach qw(passwd group);

    #- free up stage1 memory
    fs::umount($_) foreach qw(/stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    run_program::run('/sbin/devfsd', '/dev');

    modules::load_category('multimedia/sound');

    $o->{steps}{startMove} = { reachable => 1, text => "Start Move" };
    $o->{orderedSteps} = [ qw(selectLanguage acceptLicense selectMouse selectKeyboard startMove) ];
    
    member($_, @ALLOWED_LANGS) or delete $lang::langs{$_} foreach keys %lang::langs;
}

sub install2::startMove {
    my ($_o) = @_;
    run_program::run('adduser', 'mdk');

    output('/var/run/console.lock', 'mdk');
    output('/var/run/console/mdk', 1);
    run_program::run('pam_console_apply');

    fork() or exec 'gmessage', '...' or c::_exit(0);

    sleep 1;
    exec 'su', 'mdk', 'startkde';
}

sub automatic_xconf {
    my ($o) = @_;
    log::l('automatic XFree configuration');

    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure({ KEYBOARD => 'uk' }, $o->{mouse}); #- using uk instead of us for now to have less warnings

    require Xconfig::main;
    require class_discard;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {},
                                                     { allowNVIDIA_rpms => [], allowATI_rpms => [] });
}


1;
