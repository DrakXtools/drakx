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

    $::testing and goto drakx_stuff;

    #- rw things
    mkdir "/$_" foreach qw(home mnt root etc var);
    mkdir_p "/var/$_" foreach qw(log run/console spool lib/xkb lock/subsys);
    mkdir_p "/etc/$_" foreach qw(X11);
    touch '/etc/modules.conf';
    symlinkf "/proc/mounts", "/etc/mtab";
    mkdir_p $_ foreach qw(/etc/devfs/conf.d /etc/rpm /etc/sysconfig /etc/sysconfig/console/consoletrans /etc/sysconfig/console/consolefonts);
 
    #- ro things
    symlinkf "/image/etc/$_", "/etc/$_" 
      foreach qw(alternatives shadow man.config services shells pam.d security inputrc ld.so.conf 
                 DIR_COLORS bashrc profile profile.d rc.d init.d devfsd.conf gtk-2.0 pango fonts modules.devfs 
                 dynamic gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache openoffice);
    symlinkf "/image/etc/X11/$_", "/etc/X11/$_"
      foreach qw(encodings.dir app-defaults applnk fs lbxproxy proxymngr rstart wmsession.d xinit.d xinit xkb xserver xsm);

    #- to be able to adduser, one need to have /etc/passwd and /etc/group writable
    #- sudoers must a file, not a symlink
    system("cp /image/etc/{passwd,group,sudoers} /etc");

    #- free up stage1 memory
    fs::umount($_) foreach qw(/stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    run_program::run('/sbin/devfsd', '/dev');

    modules::load_category('multimedia/sound');

drakx_stuff:
    $o->{steps}{startMove} = { reachable => 1, text => "Start Move" };
    $o->{orderedSteps_orig} = $o->{orderedSteps};
    $o->{orderedSteps} = [ qw(selectLanguage acceptLicense selectMouse selectKeyboard startMove) ];
    
    member($_, @ALLOWED_LANGS) or delete $lang::langs{$_} foreach keys %lang::langs;
}

sub install2::startMove {
    my $o = $::o;
    
    require any;
    any::ask_user_one($o, $o->{users} ||= [], $o->{security},
                      additional_msg => N("BLA BLA user for move, password for screensaver"), noaccept => 1, needauser => 1, noicons => 1);
    require install_steps;
    install_steps::addUser($o);

    require install_any;
    install_any::write_fstab($o);
    modules::write_conf('');
    detect_devices::install_addons('');

    foreach my $step (@{$o->{orderedSteps_orig}}) {
        next if member($step, @{$o->{orderedSteps}});
        while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
            log::l("doing remaining toBeDone for undone step $step");
            eval { &$f() };
            $o->ask_warn(N("Error"), [
N("An error occurred, but I don't know how to handle it nicely.
Continue at your own risk."), formatError($@) ]) if $@;
        }
    }

    $::WizardWindow->destroy if $::WizardWindow;
    require ugtk2;
    my $root = ugtk2::gtkroot();
    my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file('/usr/share/mdk/screensaver/3.png');
    my ($w, $h) = ($pixbuf->get_width, $pixbuf->get_height);
    $root->draw_pixbuf(Gtk2::Gdk::GC->new($root), $pixbuf, 0, 0, ($::rootwidth - $w) / 2, ($::rootheight - $h)/2, $w, $h, 'none', 0, 0);
    ugtk2::gtkflush();

    run_program::run('/sbin/service', 'syslog', 'start');  #- otherwise minilogd will strike
    run_program::run('killall', 'minilogd');  #- get rid of minilogd

    run_program::run('adduser', 'mdk');

    output('/var/run/console.lock', 'mdk');
    output('/var/run/console/mdk', 1);
    run_program::run('pam_console_apply');

    if (fork()) {
	sleep 1;
        log::l("DrakX waves bye-bye");

	(undef, undef, my $uid, my $gid, undef, undef, undef, my $home, my $shell) = getpwnam('mdk');
	$( = $) = "$gid $gid";
	$< = $> = $uid;
	$ENV{LOGNAME} = $ENV{USER} = 'mdk';
	$ENV{HOME} = $home;
	$ENV{SHELL} = $shell;
	exec 'startkde';
    } else {
	exec 'xwait' or c::_exit(0);
    }
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
