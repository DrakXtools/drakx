package move; # $Id$ $

use diagnostics;
use strict;

use modules;
use common;
use fs;
use fsedit;
use run_program;
use log;
use lang;
use Digest::MD5 qw(md5_hex);

my @ALLOWED_LANGS = qw(en_US fr es it de);
our ($using_existing_user_config, $using_existing_host_config);
my $key_sysconf = '/home/.sysconf';
my $virtual_key_part;

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

sub handle_virtual_key {
    if (my ($device, $file) = cat_('/proc/cmdline') =~ /\bvirtual_key=(\S+),(\S+)/) {
        log::l("using device=$device file=$file as a virtual key");
        my $dir = '/virtual_key_mount';
        mkdir $dir;
        run_program::run('mount', $device, $dir);
        require devices;
        my $loop = devices::find_free_loop();
        run_program::run('losetup', $loop, "$dir$file");
        run_program::run('mount', $loop, '/home', '-o', 'umask=077,uid=501,gid=501,shortname=mixed');
	$virtual_key_part = { device => $loop, mntpoint => '/home', type => 0xc, isMounted => 1 };
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
    system("cp /image/etc/$_ /etc") foreach qw(passwd passwd- group sudoers fstab);

    #- these files are typically opened in read-write mode, we need them copied
    mkdir_p("/etc/$_"), system("cp -R /image/etc/$_/* /etc/$_")
      foreach qw(cups profile.d sysconfig devfs/conf.d);

    #- directories we badly need as non-links because files will be written in
    handle_etcfiles('DIR');
 
    #- for /etc/sysconfig/networking/ifcfg-lo
    mkdir "/etc/sysconfig/networking";

    #- ro things
    symlinkf_short("/image/etc/$_", "/etc/$_")
      foreach qw(alternatives man.config services shells pam.d security inputrc ld.so.conf 
                 DIR_COLORS bashrc profile rc.d init.d devfsd.conf gtk-2.0 pango fonts modules.devfs 
                 dynamic hotplug gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache openoffice xinetd.d xinetd.conf syslog.conf sysctl.conf sysconfig/networking/ifcfg-lo
                 ifplugd);
    symlinkf_short("/image/etc/X11/$_", "/etc/X11/$_")
      foreach qw(encodings.dir app-defaults applnk fs lbxproxy proxymngr rstart wmsession.d xinit.d xinit xkb xserver xsm);
    symlinkf_short("/image/root/$_", "/root/$_") foreach qw(.bashrc);

    #- non-trivial files/directories that need be readable, files that will be overwritten
    handle_etcfiles('READ', 'OVERWRITE');

    #- create remaining /etc and /var subdirectories if not already copied or symlinked,
    #- because programs most often won't try to create the missing subdir before trying
    #- to write a file, leading to obscure unexpected failures
    -d $_ or mkdir_p $_ foreach chomp_(cat_('/image/move/directories-to-create'));

    #- remaining non existent /etc files are symlinked from the RO volume,
    #- better to have them RO than non existent.
    #- PB: problems arise when programs try to open then in O_WRONLY
    #- or O_RDWR -> in that case, they should be handled in the
    #- OVERWRITE section of data/etcfiles)
    foreach (chomp_(cat_('/image/move/all-etcfiles'))) {
        -f or symlinkf_short("/image/$_", $_);
    }

    #- free up stage1 memory
    fs::umount($_) foreach qw(/stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    run_program::run('/sbin/devfsd', '/dev');

    -d '/lib/modules/' . c::kernel_version() or warn("ERROR: kernel package " . c::kernel_version() . " not installed\n"), c::_exit(1);

    system('sysctl -w kernel.hotplug="/bin/true"');
    modules::load_category('bus/usb'); 
    eval { modules::load('usb-storage', 'sd_mod') };
    handle_virtual_key();
    install_steps::setupSCSI($o);
    system('sysctl -w kernel.hotplug="/sbin/hotplug"');

    key_mount($o);
    cat_('/proc/cmdline') =~ /\bcleankey\b/ and eval { rm_rf $key_sysconf };
    key_installfiles('simple');
    if (`getent passwd 501` =~ /([^:]+):/) {
        $o->{users} = [ { name => $1 } ];
        print "Using existing user configuration\n";
        $using_existing_user_config = 1;
    }
    if (-f '/etc/X11/XF86Config') {
        print "Using existing host configuration\n";
        $using_existing_host_config = 1;
    }

drakx_stuff:
    $o->{steps}{autoSelectLanguage} = { reachable => 1, text => "Automatic Language Selection" };
    $o->{steps}{handleI18NClp} = { reachable => 1, text => "Handle I18N CLP" };
    $o->{steps}{verifyKey} = { reachable => 1, text => "Verify Key" };
    $o->{steps}{configMove} = { reachable => 1, text => "Configure Move" };
    $o->{steps}{startMove} = { reachable => 1, text => "Start Move" };
    $o->{orderedSteps_orig} = $o->{orderedSteps};
    $o->{orderedSteps} = [ $using_existing_host_config ?
                           qw(handleI18NClp verifyKey startMove)
                         : $using_existing_user_config ?
                           qw(autoSelectLanguage handleI18NClp verifyKey selectMouse selectKeyboard configMove startMove)
                         : qw(selectLanguage handleI18NClp acceptLicense verifyKey selectMouse selectKeyboard configMove startMove) ];
    $o->{steps}{first} = $o->{orderedSteps}[0];

    #- don't use shadow passwords since pwconv overwrites /etc/shadow hence contents will be lost for usb key
    delete $o->{authentication}{shadow};

    member($_, @ALLOWED_LANGS) or delete $lang::langs{$_} foreach keys %lang::langs;
}

sub lomount_clp {
    my ($name, $needed_file) = @_;
    my ($clp, $dir) = ("/cdrom/live_tree_$name.clp", "/image_$name");

    -e "$dir$needed_file" and return;

    if (! -e $clp || cat_('/proc/cmdline') =~ /\blive\b/) {
	symlink "/cdrom/live_tree_$name", $dir;
	return;
    }

    log::l("lomount_clp: lomounting $name");

    mkdir_p($dir);
    my $dev = devices::find_free_loop();
    run_program::run('losetup', '-r', '-e', 'gz', $dev, $clp);
    run_program::run('mount', '-r', $dev, $dir);
}

sub install2::autoSelectLanguage {
    my $o = $::o;

    $o->{locale} = lang::read('', 0);
    install_steps::selectLanguage($o);
}

sub install2::handleI18NClp {
    my $o = $::o;

    lomount_clp("always_i18n_$o->{locale}{lang}", '/usr');
}

sub key_parts {
    my ($o) = @_;

    my @keys = grep { $_->{usb_media_type} && index($_->{usb_media_type}, 'Mass Storage|') == 0 && $_->{media_type} eq 'hd' } @{$o->{all_hds}{hds}};
    map_index { 
	$_->{mntpoint} = $::i ? "/mnt/key$::i" : '/home';
	$_->{options} = 'umask=077,uid=501,gid=501,shortname=mixed';
        $_;
    } fsedit::get_fstab(@keys);
}
    
sub key_mount {
    my ($o, $o_reread) = @_;

    if ($o_reread) {
        $o->{all_hds} = fsedit::empty_all_hds();
        install_any::getHds($o, $o);
    }
    if ($virtual_key_part) {
        #- :/ merge_from_mtab didn't got my virtual key, need to add it manually
        push @{$o->{fstab}}, $virtual_key_part;
    }

    require fs;
    fs::mount_part($_) foreach key_parts($o);
}

sub key_umount {
    my ($o) = @_;
    eval { fs::umount_part($_) foreach key_parts($o); 1 };
}

sub machine_ident {
    #- , c::get_hw_address('eth0');       before detect of network :(
    md5_hex(join '', (map { (split)[1] } cat_('/proc/bus/pci/devices')));
}

sub key_installfiles {
    my ($mode) = @_;

    my $done if 0;
    $done and return;

    mkdir $key_sysconf;
    my $sysconf = "$key_sysconf/" . machine_ident();

    if (!-d $sysconf) {
        if ($mode eq 'full') {
            log::l("key_installfiles: installing config files in $sysconf");
            mkdir $sysconf;
            foreach (chomp_(cat_('/image/move/keyfiles'))) {
                my $target_dir = "$sysconf/" . dirname($_);
                mkdir_p($target_dir);
                if (/\*$/) {
                    system("cp $_ $target_dir");
                    symlinkf("$sysconf$_", $_) foreach glob($_);
                } else {
                    system("cp $_ $sysconf$_");
                    symlinkf("$sysconf$_", $_);
                }
            }
            system("cp /image/move/README.adding.more.files $key_sysconf");
            $done = 1;
        } else {
            #- not in full mode and no host directory, grab user config from first existing host directory if possible
            log::l("key_installfiles: only looking for user config files");
            foreach (qw(/etc/passwd /etc/group /etc/sysconfig/i18n)) {
                my $first_available = first(glob("$key_sysconf/*$_")) or next;
                system("cp $first_available $_");
            }
        }
    } else {
        log::l("key_installfiles: installing symlinks to key");
        foreach (chomp_(`find $sysconf -type f`)) {
            my ($path) = /^\Q$sysconf\E(.*)/;
            mkdir_p(dirname($path));
            symlinkf($_, $path);
        }
        $done = 1;
    }

    #- /etc/sudoers can't be a link
    unlink($_), system("cp /image/$_ $_") foreach qw(/etc/sudoers);
}


sub install2::verifyKey {
    my ($o) = $::o;

    while (cat_('/proc/mounts') !~ m|\s/home\s|) {
        
        $o->ask_okcancel_({ title => N("Need a key to save your data"), 
                            messages => formatAlaTeX(
N("We didn't detect any USB key on your system. If you
plug in an USB key now, Mandrake Move will have the ability
to transparently save the data in your home directory and
system wide configuration, for next boot on this computer
or another one. Note: if you plug in a key now, wait several
seconds before detecting again.


You may also proceed without an USB key - you'll still be
able to use Mandrake Move as a normal live Mandrake
Operating System.")),
                            ok => N("Detect again USB key"),
                            cancel => N("Continue without USB key") }) or return;

        key_mount($o, 'reread');
    }

    local *F;
    while (!open F, '>/home/.touched') {

        if (!key_umount($o)) {
            #- this case happens when the user boots with a write-protected key containing
            #- all user and host data, /etc/X11/X which is on key busyfies it
            $o->ask_okcancel_({ title => N("Key isn't writable"), 
                                messages => formatAlaTeX(
N("The USB key seems to have write protection enabled, but we can't safely
unplug it now.


Click the button to reboot the machine, unplug it, remove write protection,
plug the key again, and launch Mandrake Move again.")),
                            ok => N("Reboot") });
            exit(0);
        }

        modules::unload('usb-storage');  #- it won't notice change on write protection otherwise :/

        $o->ask_okcancel_({ title => N("Key isn't writable"), 
                            messages => formatAlaTeX(
N("The USB key seems to have write protection enabled. Please
unplug it, remove write protection, and then plug it again.")),
                            ok => N("Retry"),
                            cancel => N("Continue without USB key") }) or return;

        modules::load('usb-storage');
        sleep 2;
        key_mount($o, 'reread');
    }
    close F;
    unlink '/home/.touched';

    my $wait = $using_existing_host_config
               || $o->wait_message(N("Setting up USB key"), N("Please wait, setting up system configuration files on USB key..."));
    key_installfiles('full');
}

sub install2::configMove {
    my $o = $::o;

    #- just in case
    lomount_clp("always_i18n_$o->{locale}{lang}", '/usr');

    if (!$using_existing_user_config) {
        if (cat_('/proc/cmdline') =~ /\buser=(\w+)/) {
            $o->{users} = [ { name => $1 } ];
        } else {
            require any;
            any::ask_user_one($o, $o->{users} ||= [], $o->{security},
                              additional_msg => N("Enter your user information, password will be used for screensaver"), noaccept => 1, needauser => 1, noicons => 1);
        }
        #- force uid/gid to 501 as it was used when mounting key, addUser may choose 502 when key already holds user data
        put_in_hash($o->{users}[0], { uid => 501, gid => 501 });
        require install_steps;
        install_steps::addUser($o);
    }

    my $wait = $o->wait_message(N("Auto configuration"), N("Please wait, detecting and configuring devices..."));

    #- automatic printer, timezone, network configs
    require install_steps_interactive;
    if (cat_('/proc/mounts') !~ /nfs/) {
        install_steps_interactive::configureNetwork($o);
        #- seems that applications have trouble with the loopback interface
        #- after successful network configuration if we don't do that
        run_program::run('/sbin/service', 'network', 'restart');
    }
    install_steps_interactive::summaryBefore($o);

    modules::load_category('multimedia/sound');
    run_program::raw({ detach => 1 }, 'service', 'sound', 'start');

    $o->{useSupermount} = 1;
    fs::set_removable_mntpoints($o->{all_hds});    
    fs::set_all_default_options($o->{all_hds}, %$o, lang::fs_options($o->{locale}));

    require install_any;
    install_any::write_fstab($o);

    modules::write_conf('');
    require mouse;
    mouse::write_conf($o, $o->{mouse}, 1);  #- write xfree mouse conf
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
}

sub install_TrueFS_in_home {
    my ($o) = @_;

    require fsedit;
    my $home = fsedit::mntpoint2part('/home', $o->{fstab}) or return;

    my %loopbacks = map {
	my $part = { 
		type => 0x83, 
		device => "/home/.mdkmove-$_",
	        loopback_file => "/.mdkmove-$_", loopback_device => $home,
		mntpoint => "/home/$_/.mdkmove-truefs", size => 6 << 11,
		toFormat => ! -e "/home/.mdkmove-$_",
	};
	$_ => $part;
    } list_users();
    $home->{loopback} = [ values %loopbacks ];
    fsedit::recompute_loopbacks($o->{all_hds});
    fs::formatMount_all([], $home->{loopback}, $o->{prefix});

    foreach my $user (keys %loopbacks) {
	my $dir = $loopbacks{$user}{mntpoint};

	foreach (qw(.kde .openoffice)) {
	    if (-d "/home/$user/$_" && ! -d "$dir/$_") {
		run_program::run('mv', "/home/$user/$_", "$dir/$_");
	    }
	    mkdir $_ foreach "/home/$user/$_", "$dir/$_";

	    run_program::run('mount', '-o', 'bind', "$dir/$_", "/home/$user/$_");
	}

	my $cache = "/tmp/.$user-cache";
	foreach (qw(.kde/share/cache)) {
	    mkdir_p("$cache/$_");
	    mkdir_p("/home/$user/" . dirname($_));
	    symlink "$cache/$_", "/home/$user/$_";
	}
        run_program::run('chown', '-R', "$user.$user", $dir);
        run_program::run('chown', '-R', "$user.$user", $cache);

	$ENV{ICEAUTHORITY} = "$dir/.ICEauthority";
    }
}

sub install2::startMove {
    my $o = $::o;

    $::WizardWindow->destroy if $::WizardWindow;
    require ugtk2;
    my $root = ugtk2::gtkroot();
    my $pixbuf = eval { Gtk2::Gdk::Pixbuf->new_from_file("/image/move/BOOT-$::rootwidth-MOVE.jpg") };
    $pixbuf ||= Gtk2::Gdk::Pixbuf->new_from_file('/usr/share/mdk/screensaver/3.png');
    my ($w, $h) = ($pixbuf->get_width, $pixbuf->get_height);
    $root->draw_pixbuf(Gtk2::Gdk::GC->new($root), $pixbuf, 0, 0, ($::rootwidth - $w) / 2, ($::rootheight - $h)/2, $w, $h, 'none', 0, 0);
    ugtk2::gtkflush();

    #- get info from existing fstab. This won't do anything if we already wrote fstab in configMove
    fs::get_info_from_fstab($o->{all_hds}, '');
    foreach (fsedit::get_really_all_fstab($o->{all_hds})) {
	$_->{mntpoint} && !$_->{isMounted} && $_->{options} !~ /\bnoauto\b/ or next;
	mkdir_p($_->{mntpoint});
	run_program::run('mount', $_->{mntpoint});
    }
    
    install_TrueFS_in_home($o);

    run_program::run('/sbin/service', 'syslog', 'start');
    run_program::run('killall', 'minilogd');  #- get rid of minilogd
    run_program::run('/sbin/service', 'syslog', 'restart');  #- otherwise minilogd will strike back

    my $username = $o->{users}[0]{name};
    output('/var/run/console.lock', $username);
    output("/var/run/console/$username", 1);
    run_program::run('pam_console_apply');

    if (cat_('/proc/mounts') =~ m|\s/home\s|) {
        output '/var/lib/machine_ident', machine_ident();
        run_program::run('/usr/bin/etc-monitorer.pl', uniq map { dirname($_) } chomp_(`find /etc -type f`));
        run_program::raw({ detach => 1 }, '/usr/bin/dnotify', '-MCRD', '/etc', '-r', '-e', '/usr/bin/etc-monitorer.pl', '{}') or die "dnotify not found!";
    }

    #- allow user customisation of startup through /etc/rc.d/rc.local
    run_program::run('/etc/rc.d/rc.local');

    if (fork()) {
	sleep 1;
        log::l("DrakX waves bye-bye");

	my (undef, undef, $uid, $gid, undef, undef, undef, $home, $shell) = getpwnam($username);
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

    $using_existing_host_config and return;
    
    log::l('automatic XFree configuration');
        
    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure({ KEYBOARD => 'uk' }, $o->{mouse}); #- using uk instead of us for now to have less warnings
    
    require Xconfig::main;
    require class_discard;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {},
                                                     { allowNVIDIA_rpms => [], allowATI_rpms => [], allowFB => $o->{allowFB} });
}


1;
