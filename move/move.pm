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

sub symlinkf_short {
    my ($dest, $file) = @_;
    if (my $l = readlink $dest) {
	$dest = $l if $l =~ m!^/!;
    }
    -d $file and log::l("$file already exists and is a directory! writing in directory may be needed, not overwriting"), return;
    symlinkf($dest, $file);
}

sub handle_etcfiles {
    my (@allowed_modes) = @_;
    #- non-trivial files listed from tools/scan-etc.pl
    foreach (chomp_(cat_('/image/move/etcfiles'))) {
        my $mode if 0;
        m|^# (\S+)| and $mode = $1;
        m|^/| && member($mode, @allowed_modes) and do {
            $mode eq 'READ' && !-e $_ and symlinkf_short("/image$_", $_);
            $mode eq 'OVERWRITE' and system("cp /image$_ $_");  #- need copy contents
            $mode eq 'DIR' and mkdir_p $_;
        }
    }

}

#- run very soon at stage2 start, setup things on tmpfs rw / that
#- were not necessary to start stage2 itself (there were setup
#- by stage1 of course)
sub init {
    my ($o) = @_;

    $::testing and goto drakx_stuff;

    #- rw things
    mkdir "/$_" foreach qw(home mnt root root/tmp etc var);

    mkdir "/etc/$_" foreach qw(X11);
    touch '/etc/modules.conf';
    symlinkf "/proc/mounts", "/etc/mtab";

    #- these files need be writable but we need a sensible first contents
    system("cp /image/etc/$_ /etc") foreach qw(passwd group sudoers fstab);

    mkdir_p("/etc/$_"), system("cp -R /image/etc/$_/* /etc/$_")
      foreach qw(cups profile.d sysconfig/network-scripts devfs/conf.d);

    #- directories we badly need as non-links because files will be written in
    handle_etcfiles('DIR');
 
    #- for /etc/sysconfig/networking/ifcfg-lo
    mkdir "/etc/sysconfig/networking";

    #- ro things
    symlinkf_short("/image/etc/$_", "/etc/$_")
      foreach qw(alternatives shadow man.config services shells pam.d security inputrc ld.so.conf 
                 DIR_COLORS bashrc profile rc.d init.d devfsd.conf gtk-2.0 pango fonts modules.devfs 
                 dynamic hotplug gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache openoffice xinetd.d xinetd.conf syslog.conf sysctl.conf sysconfig/networking/ifcfg-lo
                 ifplugd);
    symlinkf_short("/image/etc/X11/$_", "/etc/X11/$_")
      foreach qw(encodings.dir app-defaults applnk fs lbxproxy proxymngr rstart wmsession.d xinit.d xinit xkb xserver xsm);

    #- non-trivial files/directories that need be readable, files that will be overwritten
    handle_etcfiles('READ', 'OVERWRITE');

    #- create remaining /etc and /var subdirectories if not already copied or symlinked,
    #- because programs most often won't try to create the missing subdir before trying
    #- to write a file, leading to obscure unexpected failures
    -d $_ or mkdir_p $_ foreach chomp_(cat_('/image/move/directories-to-create'));


    #- free up stage1 memory
    fs::umount($_) foreach qw(/stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    run_program::run('/sbin/devfsd', '/dev');

    -d '/lib/modules/' . c::kernel_version() or warn("ERROR: kernel package " . c::kernel_version() . " not installed\n"), c::_exit(1);

    modules::load_category('multimedia/sound');

drakx_stuff:
    $o->{steps}{startMove} = { reachable => 1, text => "Start Move" };
    $o->{steps}{handleMoveKey} = { reachable => 1, text => "Handle Move Key" };
    $o->{orderedSteps_orig} = $o->{orderedSteps};
    $o->{orderedSteps} = [ qw(selectLanguage handleMoveKey acceptLicense selectMouse selectKeyboard startMove) ];
    
    member($_, @ALLOWED_LANGS) or delete $lang::langs{$_} foreach keys %lang::langs;
}

sub lomount_clp {
    my ($name, $needed_file) = @_;
    my ($clp, $dir) = ("/image_raw/live_tree_$name.clp", "/image_$name");

    -e "$dir$needed_file" and return;

    if (! -e $clp || cat_('/proc/cmdline') =~ /\blive\b/) {
	symlink "/image_raw/live_tree_$name", $dir;
	return;
    }

    log::l("lomount_clp: lomounting $name");

    mkdir_p($dir);
    my $dev = devices::find_free_loop();
    run_program::run('losetup', '-r', '-e', 'gz', $dev, $clp);
    run_program::run('mount', '-r', $dev, $dir);
}

sub install2::handleMoveKey {
    my $o = $::o;

    lomount_clp("always_i18n_$o->{locale}{lang}", '/usr');

    require detect_devices;
    require fsedit;
    require fs;

    my @keys = grep { $_->{usb_media_type} && index($_->{usb_media_type}, 'Mass Storage|') == 0 && $_->{media_type} eq 'hd' } detect_devices::get();

    foreach my $hd (@keys) {
	$hd->{file} = devices::make($hd->{device});
	fsedit::use_proc_partitions($hd);
    }

    my @parts = fsedit::get_fstab(@keys);
    each_index { $_->{mntpoint} = '/mnt/key' . ($::i || '') } @parts;

    fs::mount_part($_) foreach @parts;
}

sub install2::startMove {
    my $o = $::o;
    
    #- just in case
    lomount_clp("always_i18n_$o->{locale}{lang}", '/usr');

    if (cat_('/proc/cmdline') =~ /\buser=(\w+)/) {
	$o->{users} = [ { name => $1 } ];
    } else {
	require any;
	any::ask_user_one($o, $o->{users} ||= [], $o->{security},
			  additional_msg => N("BLA BLA user for move, password for screensaver"), noaccept => 1, needauser => 1, noicons => 1);
    }
    require install_steps;
    install_steps::addUser($o);

    my $w = $o->wait_message(N("Auto configuration"), N("Please wait, detecting and configuring devices..."));

    #- automatic printer, timezone, network configs
    require install_steps_interactive;
    install_steps_interactive::configureNetwork($o);
    install_steps_interactive::summaryBefore($o);

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

    $w = undef;

    $::WizardWindow->destroy if $::WizardWindow;
    require ugtk2;
    my $root = ugtk2::gtkroot();
    my $pixbuf = Gtk2::Gdk::Pixbuf->new_from_file('/usr/share/mdk/screensaver/3.png');
    my ($w, $h) = ($pixbuf->get_width, $pixbuf->get_height);
    $root->draw_pixbuf(Gtk2::Gdk::GC->new($root), $pixbuf, 0, 0, ($::rootwidth - $w) / 2, ($::rootheight - $h)/2, $w, $h, 'none', 0, 0);
    ugtk2::gtkflush();

    run_program::run('/sbin/service', 'syslog', 'start');
    run_program::run('killall', 'minilogd');  #- get rid of minilogd
    run_program::run('/sbin/service', 'syslog', 'restart');  #- otherwise minilogd will strike back

    my $username = $o->{users}[0]{name};
    output('/var/run/console.lock', $username);
    output("/var/run/console/$username", 1);
    run_program::run('pam_console_apply');

    if (fork()) {
	sleep 1;
        log::l("DrakX waves bye-bye");

	(undef, undef, my $uid, my $gid, undef, undef, undef, my $home, my $shell) = getpwnam($username);
	$( = $) = "$gid $gid";
	$< = $> = $uid;
	$ENV{LOGNAME} = $ENV{USER} = $username;
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
                                                     { allowNVIDIA_rpms => [], allowATI_rpms => [], allowFB => $o->{allowFB} });
}


1;
