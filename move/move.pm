package move; # $Id$ $

#- Copyright (c) 2003-2004 MandrakeSoft
#-
#- This program is free software; you can redistribute it and/or modify
#- it under the terms of the GNU General Public License as published by
#- the Free Software Foundation; either version 2, or (at your option)
#- any later version.
#-
#- This program is distributed in the hope that it will be useful,
#- but WITHOUT ANY WARRANTY; without even the implied warranty of
#- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#- GNU General Public License for more details.
#-
#- You should have received a copy of the GNU General Public License
#- along with this program; if not, write to the Free Software
#- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

use diagnostics;
use strict;

use modules;
use common;
use fs;
use fsedit;
use run_program;
use partition_table qw(:types);
use swap;
use log;
use lang;
use Digest::MD5 qw(md5_hex);

my $key_disabled;

my ($using_existing_user_config, $using_existing_host_config);
my $key_sysconf = '/home/.sysconf';
my $key_part;
my $virtual_key_part;
my $key_mountopts = 'umask=077,uid=501,gid=501,shortname=mixed,nobadchars';

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
    my ($mode, $allowed);
    foreach (chomp_(cat_('/image/move/etcfiles'))) {
        if (m|^# (\S+)|) {
	    $mode = $1;
	    $allowed = member($mode, @allowed_modes);
	} elsif (m|^/| && $allowed) {
            if ($mode eq 'READ') {
                mkdir_p(dirname($_));
		symlinkf_short("/image$_", $_) if !-e $_;
	    } elsif ($mode eq 'OVERWRITE') {
                mkdir_p(dirname($_));
                cp_f("/image$_", $_);  #- need copy contents
            } elsif ($mode eq 'DIR') {
		mkdir_p $_;
	    }
        }
    }

}

sub handle_virtual_key() {
    return if $key_disabled;
    if (my ($device, $file, $options) = cat_('/proc/cmdline') =~ /\bvirtual_key=([^,\s]+),([^,\s]+)(,\S+)?/) {
        log::l("using device=$device file=$file as a virtual key with options $options");
        my $dir = '/virtual_key_mount';
        mkdir $dir;
        run_program::run('mount', $device, $dir);
        if ($options =~ /format/) {
	    if (! -e "$dir$file") {
		require commands;
		commands::dd("if=/dev/zero", "of=$dir$file", "bs=1M", "count=40");
	    }
	    run_program::run('mkdosfs', "$dir$file");
	}
        require devices;
        my $loop = devices::find_free_loop();
        run_program::run('losetup', $loop, "$dir$file");
        run_program::run('mount', $loop, '/home', '-o', $key_mountopts);
	$virtual_key_part = { device => $loop, mntpoint => '/home', type => 0xc, isMounted => 1 };
    }
}

sub setup_userconf {
    my ($o) = @_;
    if (is_empty_array_ref($o->{users}) && `getent passwd 501` =~ /([^:]+):/) {
        log::l("passwd/501 is $1");
        $o->{users} = [ { name => $1 } ];
	$ENV{HOME} = "/home/$1"; #- used by lang::read()  :-/
        print "using existing user configuration\n";
        $using_existing_user_config = 1;
    }
}

sub lang2move_clp_name {
    my ($lang) = @_;
    my $dir = '/usr/share/locale/' . lang::l2locale($lang);
    -d $dir or return 'ERROR';
    my $link = readlink($dir) or return;
    my ($name) = $link =~ m!image_(i18n_.*?)/! or log::l("ERROR: bad link $link for $dir"), return 'ERROR';
    $name;
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
    touch '/etc/modprobe.conf';
    cp_f('/proc/mounts', '/etc/mtab');

    #- these files need be writable but we need a sensible first contents
    cp_f("/image/etc/$_", '/etc') foreach qw(passwd passwd- group sudoers fstab);

    #- these files are typically opened in read-write mode, we need them copied
    mkdir_p("/etc/$_"), cp_f(glob_("/image/etc/$_/*"), "/etc/$_")
      foreach qw(cups profile.d sysconfig devfs/conf.d);

    #- TODO: cp_af is broken for symlinks to directories
    #- replace below with cp_af is fixed in perl-MDK-Common
    run_program::run('cp', '-a', glob("/image/etc/rc[0-6].d"), '/etc');

    #- directories we badly need as non-links because files will be written in
    handle_etcfiles('DIR');
 
    #- for /etc/sysconfig/networking/ifcfg-lo
    mkdir "/etc/sysconfig/networking";

    #- ro things
    symlinkf_short("/image/etc/$_", "/etc/$_")
      foreach qw(alternatives man.config services shells pam.d inputrc ld.so.conf 
                 DIR_COLORS bashrc profile init.d devfsd.conf gtk-2.0 pango fonts modules.devfs 
                 dynamic hotplug gnome-vfs-2.0 gnome-vfs-mime-magic gtk gconf menu menu-methods nsswitch.conf default login.defs 
                 skel ld.so.cache openoffice xinetd.d xinetd.conf syslog.conf sysctl.conf sysconfig/networking/ifcfg-lo
                 ifplugd);
    symlinkf_short("/image/etc/X11/$_", "/etc/X11/$_")
      foreach qw(encodings.dir app-defaults applnk fs lbxproxy proxymngr rstart wmsession.d xinit xkb xserver xsm);
    symlinkf_short("/image/root/$_", "/root/$_") foreach qw(.bashrc);

    mkdir_p(dirname("/var/$_")), symlinkf_short("/image/var/$_", "/var/$_") foreach qw(lib/samba lib/rpm cache/gstreamer-0.6);

    #- non-trivial files/directories that need be readable, files that will be overwritten
    handle_etcfiles('READ', 'OVERWRITE');

    run_program::run('chown', 'clamav.clamav', '/var/log/clamav/freshclam.log');

    #- create remaining /etc and /var subdirectories if not already copied or symlinked,
    #- because programs most often won't try to create the missing subdir before trying
    #- to write a file, leading to obscure unexpected failures
    foreach (cat_('/image/move/directories-to-create')) {
	my ($mode, $uid, $gid, $name) = split;
	next if -d $name;
	mkdir($name);
	chmod(oct($mode), $name);
	chown($uid, $gid, $name);
    }

    chmod 01777, '/tmp', '/var/tmp';  #- /var/tmp -> badly needed for printing from OOo

    #- remaining non existent /etc files are symlinked from the RO volume,
    #- better to have them RO than non existent.
    #- PB: problems arise when programs try to open then in O_WRONLY
    #- or O_RDWR -> in that case, they should be handled in the
    #- OVERWRITE section of data/etcfiles)
    foreach (chomp_(cat_('/image/move/all-etcfiles'))) {
        -f $_ or symlinkf_short("/image$_", $_);
    }

    #- free up stage1 memory
    eval { fs::umount($_) } foreach qw(/stage1/proc/bus/usb /stage1/proc /stage1);

    #- devfsd needed for devices accessed by old names
    fs::mount("none", "/dev", "devfs", 0);
    fs::mount("none", "/dev/pts", "devpts", 0);
    run_program::run('/sbin/devfsd', '/dev');

    -d '/lib/modules/' . c::kernel_version() or warn("ERROR: kernel package " . c::kernel_version() . " not installed\n"), c::_exit(1);

    $key_disabled = !-e '/cdrom/live_tree_nvidia.clp' && cat_('/proc/mounts') !~ /nfs/;

    run_program::run('/sbin/service', 'syslog', 'start');
    run_program::run('sysctl', '-w', 'kernel.hotplug=/bin/true');
    modules::load_category('bus/usb'); 
    eval { modules::load('usb-storage', 'sd_mod') };
    handle_virtual_key();
    $o->{pcmcia} ||= !$::noauto && c::pcmcia_probe();
    cat_('/proc/cmdline') =~ /\bwaitkey\b/ and sleep 15;
    install_steps::setupSCSI($o);
    run_program::run('sysctl', '-w', 'kernel.hotplug=/sbin/hotplug');

    key_mount($o);
    cat_('/proc/cmdline') =~ /\bcleankey\b/ and eval { rm_rf $key_sysconf, glob_('/home/.mdkmove*') };
    key_installfiles('simple');
    setup_userconf($o);
    if (-f '/etc/X11/X') {
        print "using existing host configuration\n";
        $using_existing_host_config = 1;

	#- so that /etc/devfsd/conf.d/mouse.conf is used and /dev/mouse created
	run_program::run('/sbin/service', 'devfsd', 'reload');
    }
    if (-s '/etc/sysconfig/i18n') {
        lang::set($o->{locale} = lang::read('', 0)); #- read ~/.i18n first if it exists
    }

    touch '/var/run/rebootctl';

drakx_stuff:
    $o->{steps}{$_} = { reachable => 1, text => $_ }
      foreach qw(initGraphical autoSelectLanguage verifyKey configMove startMove);
    $o->{orderedSteps_orig} = $o->{orderedSteps};
    $o->{orderedSteps} = [ $using_existing_host_config ?
                           qw(initGraphical verifyKey startMove)
                         : $using_existing_user_config ?
                           qw(initGraphical autoSelectLanguage verifyKey selectMouse selectKeyboard configMove startMove)
                         : qw(initGraphical selectLanguage acceptLicense verifyKey selectMouse selectKeyboard configMove startMove) ];
    $o->{steps}{first} = $o->{orderedSteps}[0];

    #- don't use shadow passwords since pwconv overwrites /etc/shadow hence contents will be lost for usb key
    delete $o->{authentication}{shadow};

    foreach my $lang (keys %lang::langs) {
	my $clp_name = lang2move_clp_name($lang) or next;
	if (! -e "/cdrom/live_tree_$clp_name.clp") {
	    log::l("disabling lang $lang");
	    delete $lang::langs{$lang};
	}
    }
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

    install_steps::selectLanguage($o);
}

sub handleI18NClp {
    my ($lang) = @_;

    my $clp_name = lang2move_clp_name($lang) or return;
    log::l("move: handleI18NClp (lang=$lang, clp_name=$clp_name)");
    lomount_clp($clp_name, '/usr');
    lomount_clp("always_$clp_name", '/usr');
}

sub key_parts {
    my ($o) = @_;

    return () if $key_disabled;

    my @keys = grep { detect_devices::isKeyUsb($_) } @{$o->{all_hds}{hds}};
    my @parts = (fsedit::get_fstab(@keys), grep { detect_devices::isKeyUsb($_) } @{$o->{all_hds}{raw_hds}});
    grep { isFat({ type => fsedit::typeOfPart($_->{device}) }) } @parts;
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
	$key_part = $virtual_key_part;
	return;
    }

    foreach (key_parts($o)) {
	if ($key_part) {
	    log::l("trying another usb key partition than $key_part->{device}");
	    fs::umount_part($key_part);
	    delete $key_part->{mntpoint};
	    undef $key_part;
	}
	$_->{mntpoint} = '/home';
	$_->{options} = "$key_mountopts,sync";
	my $ok = eval { fs::mount_part($_); 1 };
	if ($ok) {
	    my ($kb_size) = MDK::Common::System::df('/home');
	    log::l("$_->{device} is $kb_size KB");
	    $ok = $kb_size > 10 * 1024; #- at least 10 MB
	    fs::umount_part($_) if !$ok;
	}
	if ($ok) {
	    $key_part = $_;
	    last if -e $key_sysconf;
	} else {
	    delete $_->{mntpoint};
	}
    } 

    
}

sub machine_ident() {
    #- , c::get_hw_address('eth0');       before detect of network :(
    md5_hex(join '', (map { (split)[1] } cat_('/proc/bus/pci/devices')));
}

sub key_installfiles {
    my ($mode) = @_;

    my $done if 0;
    $done and return;

    mkdir $key_sysconf;
    my $sysconf = "$key_sysconf/" . machine_ident();

    my $copy_userinfo = sub {
        my (@files) = @_;
        my @etcpasswords = glob("$key_sysconf/*/etc/passwd");
        if (@etcpasswords > 1) {
            print "inconsistency: more than one /etc/passwd on key! can't proceed, please clean the key\n";
            exit 1;
        }
        return if !@etcpasswords;
        my ($path) = $etcpasswords[0] =~ m|(.*)/etc/passwd|;
        run_program::run('cp', '-f', "$path$_", $_) foreach @files;
        run_program::run('rm', '-f', $etcpasswords[0]);
    };

    if (!-d $sysconf) {
        if ($mode eq 'full') {
            log::l("key_installfiles: installing config files in $sysconf");
            mkdir $sysconf;
            foreach (chomp_(cat_('/image/move/keyfiles'))) {
                mkdir_p($sysconf . dirname($_));
                my @l = /\*$/ ? glob_($_) : $_;
		foreach (@l) {
		    eval { cp_f($_, "$sysconf$_") };
                    symlinkf("$sysconf$_", $_);
                }
            }
            eval { cp_f('/image/move/README.adding.more.files', $key_sysconf) };
            $done = 1;
        } else {
            #- not in full mode and no host directory, grab user config from first existing host directory if possible
            log::l("key_installfiles: only looking for user config files");
            $copy_userinfo->(qw(/etc/passwd /etc/group /etc/sysconfig/i18n));
        }
    } else {
        log::l("key_installfiles: installing symlinks to key");
        if (!-e "$sysconf/etc/passwd") {
            log::l("key_installfiles: /etc/passwd not here, trying to copy from previous host boot");
            $copy_userinfo->(qw(/etc/passwd /etc/group));
        }
        foreach (chomp_(`find $sysconf -type f`)) {
            my ($path) = /^\Q$sysconf\E(.*)/;
            mkdir_p(dirname($path));
            symlinkf($_, $path);
        }
        $done = 1;
        $::o->{steps}{configMove}{done} = 1;
    }

    #- /etc/sudoers can't be a link
    unlink($_), cp_f("/image$_", $_) foreach qw(/etc/sudoers);
}

sub reboot() {
    output('/var/run/rebootctl', "reboot");  #- tell X_move to not respawn
    run_program::run('killall', 'X');  #- kill it ourselves to be sure that it won't lock console when killed by our init
    exit 0;
}


sub check_key {
    my ($o) = @_;

    if ($key_part) {
	my $tmp = '/home/.touched';
	#- can we write?
	if (eval { output($tmp, 'foo'); cat_($tmp) eq 'foo' && unlink $tmp }) {
	    return 1;
	}

	#- argh, key is read-only
	#- try umounting
	if (eval { fs::umount_part($key_part); undef $key_part; 1 }) {
	    modules::unload('usb-storage');  #- it won't notice change on write protection otherwise :/

	    $o->ask_okcancel_({ title => N("Key isn't writable"), 
				messages => formatAlaTeX(
N("The USB key seems to have write protection enabled. Please
unplug it, remove write protection, and then plug it again.")),
				ok => N("Retry"),
				cancel => N("Continue without USB key") }) or return;

	    modules::load('usb-storage');
	    sleep 2;
	} else {
	    #- this case happens when the user boots with a write-protected key containing
	    #- all user and host data, /etc/X11/X which is on key busyfies it
	    $o->ask_okcancel_({ title => N("Key isn't writable"), 
				messages => formatAlaTeX(
N("The USB key seems to have write protection enabled, but we can't safely
unplug it now.


Click the button to reboot the machine, unplug it, remove write protection,
plug the key again, and launch Mandrake Move again.")),
				ok => N("Reboot") });
	    reboot();
	}
    } else {
	my $message = key_parts($o) ? 
N("Your USB key doesn't have any valid Windows (FAT) partitions.
We need one to continue (beside, it's more standard so that you
will be able to move and access your files from machines
running Windows). Please plug in an USB key containing a
Windows partition instead.


You may also proceed without an USB key - you'll still be
able to use Mandrake Move as a normal live Mandrake
Operating System.") :
N("We didn't detect any USB key on your system. If you
plug in an USB key now, Mandrake Move will have the ability
to transparently save the data in your home directory and
system wide configuration, for next boot on this computer
or another one. Note: if you plug in a key now, wait several
seconds before detecting again.


You may also proceed without an USB key - you'll still be
able to use Mandrake Move as a normal live Mandrake
Operating System.");
	$o->ask_okcancel_({ title => N("Need a key to save your data"), 
			    messages => formatAlaTeX($message),
			    ok => N("Detect USB key again"),
			    cancel => N("Continue without USB key") }) or return;

    }
    key_mount($o, 'reread');
    check_key($o);
}

sub install2::verifyKey {
    my $o = $::o;

    log::l("automatic transparent key support is disabled"), return if $key_disabled;

    check_key($o) or return;

    my $_wait = $using_existing_host_config
                || $o->wait_message(N("Setting up USB key"), N("Please wait, setting up system configuration files on USB key..."));

    if (eval { fs::umount_part($key_part); 1 }) {
	log::l("remounting without sync option");
	$key_part->{options} = $key_mountopts;
	fs::mount_part($key_part);
    }

    key_installfiles('full');

    setup_userconf($o);
}

sub enable_service {
    run_program::run('/sbin/chkconfig', '--level', 5, $_[0], 'on');
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

    $::noauto and goto after_autoconf;

    my $_wait = $o->wait_message(N("Auto configuration"), N("Please wait, detecting and configuring devices..."));

    #- automatic printer, timezone, network configs
    require install_steps_interactive;
    if (cat_('/proc/mounts') !~ /nfs/) {
        install_steps_interactive::configureNetwork($o);
	touch('/etc/resolv.conf');
        enable_service('network');
    }
    enable_service('netfs');
    install_steps_interactive::summaryBefore($o);

    modules::load_category('multimedia/sound');
    enable_service('sound');

    detect_devices::isLaptop() or enable_service('numlock');

after_autoconf:
    require timezone;
    timezone::write($o->{timezone});

    $o->{useSupermount} = 'magicdev';
    fs::set_removable_mntpoints($o->{all_hds});    
    fs::set_all_default_options($o->{all_hds}, %$o, lang::fs_options($o->{locale}));

    require install_any;
    install_any::write_fstab($o);

    modules::write_conf();
    require mouse;
    mouse::write_conf($o, $o->{mouse}, 1);  #- write xfree mouse conf
    detect_devices::install_addons('');

    {
	my $user = $o->{users}[0]{name};
	my $confdir = "/home/$user/.kde/share/config";
	mkdir_p($confdir);
	output("$confdir/kdeglobals", cat_("/usr/share/config/kdeglobals"));
	lang::configure_kdeglobals($o->{locale}, $confdir);

        run_program::run('chown', '-R', "$user.$user", "/home/$user/.kde");
    }

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

	$ENV{XAUTHORITY} = "$dir/.Xauthority";
	$ENV{ICEAUTHORITY} = "$dir/.ICEauthority";
    }
}

sub errorInStep {
    my ($o, $err) = @_;

    if (!fsedit::mntpoint2part('/home', $o->{fstab})) {
        $o->ask_warn(N("Error"), [ N("An error occurred"), formatError($err) ]);
        return;
    }

    $o->ask_okcancel_({ title => N("Error"), 
                        messages => formatAlaTeX(
N("An error occurred:


%s

This may come from corrupted system configuration files
on the USB key, in this case removing them and then
rebooting Mandrake Move would fix the problem. To do
so, click on the corresponding button.


You may also want to reboot and remove the USB key, or
examine its contents under another OS, or even have
a look at log files in console #3 and #4 to try to
guess what's happening.", formatError($err))),
                            ok => N("Remove system config files"),
                            cancel => N("Simply reboot") }) or goto reboot;
    eval { rm_rf $key_sysconf };
reboot:
    reboot();
}

sub install2::initGraphical {
    my $xdim = $::rootwidth;
    $xdim < 800 and $xdim = 800;
    $xdim > 1600 and $xdim = 1600;
    run_program::run('qiv', '--root', "/image/move/BOOT-$xdim-MOVE.jpg");
    
    undef *install_steps_interactive::errorInStep;
    *install_steps_interactive::errorInStep = \&errorInStep;
}

sub install2::startMove {
    my $o = $::o;

    $::WizardWindow->destroy if $::WizardWindow;
    require ugtk2;
    ugtk2::flush();

    #- get info from existing fstab. This won't do anything if we already wrote fstab in configMove
    fs::get_info_from_fstab($o->{all_hds}, '');
    foreach (fsedit::get_really_all_fstab($o->{all_hds})) {
	if (isSwap($_)) {
	    eval { swap::swapon($_->{device}) };
	} elsif ($_->{mntpoint} && !$_->{isMounted} && !$::noauto) {
	    mkdir_p($_->{mntpoint});
	    run_program::run('mount', $_->{mntpoint}) if $_->{options} !~ /noauto/;
	}
    }

    symlinkf("/usr/share/services/ksycoca-$o->{locale}{lang}", '/etc/X11/ksycoca');
    
    install_TrueFS_in_home($o);

    my $username = $o->{users}[0]{name} or die 'no user';
    output('/var/run/console.lock', $username);
    output("/var/run/console/$username", 1);
    run_program::run('pam_console_apply');

    run_program::run('hwclock', '-s', '--localtime');
    run_program::run('chown', "$username.root", '/var/run/rebootctl');
    substInFile { $_ = '' if m!\s/home\s! } $_ foreach '/etc/fstab', '/etc/mtab';

    touch '/var/run/utmp';
    run_program::run('runlevel_set', '5');
    foreach (glob('/etc/rc.d/rc5.d/*')) {
        next if member($_, qw(xfs dm devfsd syslog));
        next if /~$/;
        run_program::run($_, 'start');
    }

    #- allow user customisation of startup through /etc/rc.d/rc.local
    run_program::run('/etc/rc.d/rc.local');

    if ($key_part) {
        output '/var/lib/machine_ident', machine_ident();
        run_program::run('/usr/bin/etc-monitorer.pl', uniq map { dirname($_) } (chomp_(`find /etc -type f`),
                                                                                grep { readlink($_) !~ m|^/| } chomp_(`find /etc -type l`)));
        run_program::raw({ detach => 1 }, '/usr/bin/dnotify', '-MCRD', '/etc', '-r', '-e', '/usr/bin/etc-monitorer.pl', '{}') or die "dnotify not found!";
    }

    #- password in screensaver doesn't make sense if we keep the shell
    if (cat_('/proc/cmdline') !~ /\bshell\b/) {
        kill 9, cat_('/var/run/drakx_shell.pid');
        output('/dev/tty2', "Killed\n");
    }

    if (fork()) {
	sleep 1;
        log::l("DrakX waves bye-bye");

        open STDOUT, ">>/tmp/.kde-errors";  #- don't display startkde shit on first console
        open STDERR, ">>/tmp/.kde-errors";
        
	my (undef, undef, $uid, $gid, undef, undef, undef, $home, $shell) = getpwnam($username);
	$( = $) = "$gid $gid";
	$< = $> = $uid;
	$ENV{LOGNAME} = $ENV{USER} = $username;
	$ENV{HOME} = $home;
	$ENV{SHELL} = $shell;
        $ENV{XDM_MANAGED} = '/var/run/rebootctl,maysd,mayfn,sched';  #- for reboot/halt availability of "logout" by kde
        $ENV{GDMSESSION} = 1;  #- disable ~/.xsession-errors in Xsession (waste of usb key writes)
	$ENV{LD_LIBRARY_PATH} = "$home/lib";
        chdir $home;
	exec 'startkde_move';
    } else {
	exec 'xwait', '-permanent' or c::_exit(0);
    }
}

sub automatic_xconf {
    my ($o) = @_;

    if (!$using_existing_host_config) {
    
	log::l('automatic XFree configuration');
        
	any::devfssymlinkf($o->{mouse}, 'mouse');
	local $o->{mouse}{device} = 'mouse';

	require Xconfig::default;
	$o->{raw_X} = Xconfig::default::configure({ KEYBOARD => 'uk' }, $o->{mouse}); #- using uk instead of us for now to have less warnings
    
	require Xconfig::main;
	require class_discard;

	Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {}, install_any::X_options_from_o($o));
    }

    modules::load_category('various/agpgart'); 

    my $file = '/etc/X11/XF86Config';
    $file = "$file-4" if -e "$file-4";
    my ($Driver) = cat_($file) =~ /Section "Device".*Driver\s*"(.*?)"/s;
    if ($Driver eq 'nvidia') {
        modules::load('nvidia');
	lomount_clp('nvidia', '/usr/lib/libGLcore.so.1');
    }
    my $lib = 'libGL.so.1';
    symlinkf_short(-e "/usr/lib/$lib.$Driver" ? "/usr/lib/$lib.$Driver" : "/usr/X11R6/lib/$lib", "/etc/X11/$lib");
}


1;
