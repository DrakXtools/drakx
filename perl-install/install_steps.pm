package install_steps; # $Id$

use diagnostics;
use strict;
use vars qw(@filesToSaveForUpgrade);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:file :system :common :functional);
use install_any qw(:all);
use install_interactive;
use partition_table qw(:types);
use detect_devices;
use modules;
use run_program;
use lang;
use keyboard;
use fsedit;
use loopback;
#use commands;
use any;
use log;
use fs;

@filesToSaveForUpgrade = qw(
/etc/ld.so.conf /etc/fstab /etc/hosts /etc/conf.modules /etc/modules.conf
);


#-######################################################################################
#- OO Stuff
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    bless $o, ref $type || $type;
    return $o;
}

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub enteringStep {
    my ($o, $step) = @_;
    log::l("starting step `$step'");
}
sub leavingStep {
    my ($o, $step) = @_;
    log::l("step `$step' finished");

    if (-d "$o->{prefix}/root") {
	eval { commands::cp('-f', "/tmp/ddebug.log", "$o->{prefix}/root") };
	install_any::g_auto_install();
    }

    for (my $s = $o->{steps}{first}; $s; $s = $o->{steps}{$s}{next}) {
	#- the reachability property must be recomputed each time to take
	#- into account failed step.
	next if $o->{steps}{$s}{done} && !$o->{steps}{$s}{redoable};

	my $reachable = 1;
	if (my $needs = $o->{steps}{$s}{needs}) {
	    my @l = ref $needs ? @$needs : $needs;
	    $reachable = min(map { $o->{steps}{$_}{done} || 0 } @l);
	}
	$o->{steps}{$s}{reachable} = 1 if $reachable;
    }
    $o->{steps}{$step}{reachable} = $o->{steps}{$step}{redoable};

    while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
	eval { &$f() };
	$o->ask_warn(_("Error"), [
_("An error occurred, but I don't know how to handle it nicely.
Continue at your own risk."), $@ ]) if $@;
    }
}

sub errorInStep($$) { print "error :(\n"; c::_exit(1) }
sub kill_action {}
sub set_help { 1 }

#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;
    lang::set($o->{lang});
    $o->{langs} ||= { $o->{lang} => 1 };

    log::l("selectLanguage: pack_langs ", lang::pack_langs($o->{langs}));

    if ($o->{keyboard_unsafe} || !$o->{keyboard}) {
	$o->{keyboard_unsafe} = 1;
	$o->{keyboard} = keyboard::lang2keyboard($o->{lang});
	selectKeyboard($o) if !$::live;
    }
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup($o->{keyboard});
}
#------------------------------------------------------------------------------
sub selectPath {}
#------------------------------------------------------------------------------
sub selectInstallClass {}
#------------------------------------------------------------------------------
sub setupSCSI {
    my ($o) = @_;
    modules::configure_pcmcia($o->{pcmcia}) if $o->{pcmcia};
    modules::load_ide();
    modules::load_thiskind('scsi|disk');
}

#------------------------------------------------------------------------------
sub doPartitionDisksBefore {
    my ($o) = @_;

    if (cat_("/proc/mounts") =~ m|/\w+/(\S+)\s+/tmp/hdimage\s+(\S+)| && !$o->{partitioning}{readonly}) {
	$o->{stage1_hd} = { device => $1, type => $2 };
	install_any::getFile("XXX"); #- close still opened filehandle
	eval { fs::umount("/tmp/hdimage") };
    }
    eval { 
	close *pkgs::LOG;
	eval { fs::umount("$o->{prefix}/proc") };
	eval {          fs::umount_all($o->{fstab}, $o->{prefix}) };
	eval { sleep 1; fs::umount_all($o->{fstab}, $o->{prefix}) } if $@; #- HACK
    } if $o->{fstab} && !$::testing && !$::live;

    $o->{raid} ||= {};
}

#------------------------------------------------------------------------------
sub doPartitionDisksAfter {
    my ($o) = @_;
    unless ($::testing) {
	partition_table::write($_) foreach @{$o->{hds}};
	$_->{rebootNeeded} and $o->rebootNeeded foreach @{$o->{hds}};
    }

    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}, $o->{raid}) ];
    fsedit::get_root_($o->{fstab}) or die "Oops, no root partition";

    if ($o->{partitioning}{use_existing_root}) {
	#- ensure those partitions are mounted so that they are not proposed in choosePartitionsToFormat
	fs::mount_part($_, $o->{prefix}) foreach grep { $_->{mntpoint} && !$_->{notFormatted} } @{$o->{fstab}};
    }

    if (my $s = delete $o->{stage1_hd}) {
	my ($part) = grep { $_->{device} eq $s->{device} } @{$o->{fstab}};
	$part->{isMounted} ?
	  do { rmdir "/tmp/hdimage" ; symlinkf("$o->{prefix}$part->{mntpoint}", "/tmp/hdimage") } :
	  eval { 
	      fs::mount($s->{device}, "/tmp/hdimage", $s->{type});
	      $part->{isMounted} = 1;
	  };
    }

    cat_("/proc/mounts") =~ m|(\S+)\s+/tmp/image nfs| &&
      !grep { $_->{mntpoint} eq "/mnt/nfs" } @{$o->{manualFstab} || []} and
	push @{$o->{manualFstab}}, { type => "nfs", mntpoint => "/mnt/nfs", device => $1, options => "noauto,ro,nosuid,rsize=8192,wsize=8192" };
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    install_any::getHds($o);

    if ($o->{partitioning}{use_existing_root} || $o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = fsedit::get_root_($o->{fstab}) || first(install_any::find_root_parts($o->{hds}, $o->{prefix})) or die;
	install_any::use_root_part($o->{fstab}, $p, $o->{prefix});
    } 
    if ($o->{partitioning}{auto_allocate}) {
	fsedit::auto_allocate($o->{hds}, $o->{partitions});
    }
}

#------------------------------------------------------------------------------

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;

    #- TODO: set the mntpoints

    my %m; foreach (@$fstab) {
	my $m = $_->{mntpoint};

	next unless $m && $m ne 'swap'; #- there may be a lot of swap.

	$m{$m} and die _("Duplicate mount point %s", $m);
	$m{$m} = 1;

	#- in case the type does not correspond, force it to ext2
	$_->{type} = 0x83 if $m =~ m|^/| && !isFat($_) && !isTrueFS($_);
    }
    1;
}


sub rebootNeeded($) {
    my ($o) = @_;
    log::l("Rebooting...");
    c::_exit(0);
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    foreach (@$fstab) {
	$_->{mntpoint} = "swap" if isSwap($_);
	$_->{mntpoint} or next;
	
	add2hash_($_, { toFormat => $_->{notFormatted} });
	if (!$_->{toFormat}) {
	    my $t = isLoopback($_) ? 
	      eval { fsedit::typeOfPart($o->{prefix} . loopback::file($_)) } :
	      fsedit::typeOfPart($_->{device});
	    $_->{toFormatUnsure} = $_->{mntpoint} eq "/" ||
	      #- if detected dos/win, it's not precise enough to just compare the types (too many of them)
	      (!$t || isOtherAvailableFS({ type => $t }) ? !isOtherAvailableFS($_) : $t != $_->{type});
	}
    }
}

sub formatMountPartitions {
    my ($o) = @_;
    fs::formatMount_all($o->{raid}, $o->{fstab}, $o->{prefix});
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;
    install_any::setPackages($o);
    pkgs::selectPackagesAlreadyInstalled($o->{packages}, $o->{prefix})
	if !$o->{isUpgrade} && (-r "$o->{prefix}/var/lib/rpm/packages.rpm" || -r "$o->{prefix}/var/lib/rpm/Packages");
}
sub selectPackagesToUpgrade {
    my ($o) = @_;
    pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix}, $o->{base}, $o->{toRemove}, $o->{toSave});
}

sub choosePackages {
    my ($o, $packages, $compss, $compssUsers, $first_time) = @_;

    #- now for upgrade, package that must be upgraded are
    #- selected first, after is used the same scheme as install.

    #- make sure we kept some space left for available else the system may
    #- not be able to start (xfs at least).
    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);
    log::l(sprintf "available size %s (corrected %s)", formatXiB($available), formatXiB($availableCorrected));

    #- avoid destroying user selection of packages but only
    #- for expert, as they may have done individual selection before.
    if ($first_time || !$::expert) {
	pkgs::unselectAllPackages($packages);
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};

	unless ($::expert) {
	    add2hash_($o, { compssListLevel => 5 }) unless $::auto_install;
	    exists $o->{compssListLevel}
	      and pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $o->{compssListLevel}, $availableCorrected);
	}
    }

    $availableCorrected;
}

sub beforeInstallPackages {
    my ($o) = @_;

    #- save these files in case of upgrade failure.
    if ($o->{isUpgrade}) {
	foreach (@filesToSaveForUpgrade) {
	    unlink "$o->{prefix}/$_.mdkgisave";
	    if (-e "$o->{prefix}/$_") {
		eval { commands::cp("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
    }

    #- some packages need such files for proper installation.
    $::live or fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});

    require network;
    network::add2hosts("$o->{prefix}/etc/hosts", "localhost.localdomain", "127.0.0.1");

    require pkgs;
    pkgs::init_db($o->{prefix});
}

sub pkg_install {
    my ($o, @l) = @_;
    log::l("selecting packages");
    require pkgs;
    if ($::testing) {
	log::l("selecting package \"$_\"") foreach @l;
    } else {
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || die "$_ rpm not found") foreach @l;
    }
    my @toInstall = pkgs::packagesToInstall($o->{packages});
    if (@toInstall) {
	log::l("installing packages");
	$o->installPackages;
    } else {
	log::l("all packages selected are already installed, nothing to do")
    }
}

sub pkg_install_if_requires_satisfied {
    my ($o, @l) = @_;
    require pkgs;
    foreach (@l) {
	my %newSelection;
	my $pkg = pkgs::packageByName($o->{packages}, $_) || die "$_ rpm not found";
	pkgs::selectPackage($o->{packages}, $pkg, 0, \%newSelection);
	scalar(keys %newSelection) == 1 and pkgs::selectPackage($o->{packages}, $pkg);
    }
    $o->installPackages;
}

sub installPackages($$) { #- complete REWORK, TODO and TOCHECK!
    my ($o) = @_;
    my $packages = $o->{packages};

    if (@{$o->{toRemove} || []}) {
	#- hack to ensure proper upgrade of packages from other distribution,
	#- as release number are not mandrake based. this causes save of
	#- important files and restore them after.
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_") {
		unlink "$o->{prefix}/$_.mdkgisave"; 
		eval { commands::cp("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
	pkgs::remove($o->{prefix}, $o->{toRemove});
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_.mdkgisave") {
		unlink "$o->{prefix}/$_"; 
		rename "$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_";
	    }
	}
	$o->{toSave} = [];

	#- hack for compat-glibc to upgrade properly :-(
	if (pkgs::packageFlagSelected(pkgs::packageByName($packages, 'compat-glibc')) &&
	    !pkgs::packageFlagInstalled(pkgs::packageByName($packages, 'compat-glibc'))) {
	    rename "$o->{prefix}/usr/i386-glibc20-linux", "$o->{prefix}/usr/i386-glibc20-linux.mdkgisave";
	}
    }

    #- small transaction will be built based on this selection and depslist.
    my @toInstall = pkgs::packagesToInstall($packages);

    my $time = time;
    $ENV{DURING_INSTALL} = 1;
    pkgs::install($o->{prefix}, $o->{isUpgrade}, \@toInstall, $packages->{depslist}, $packages->{mediums});
    delete $ENV{DURING_INSTALL};
    run_program::rooted($o->{prefix}, 'ldconfig') or die "ldconfig failed!" unless $::g_auto_install;
    log::l("Install took: ", formatTimeRaw(time - $time));
    install_any::log_sizes($o);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    return if $::g_auto_install;

    die _("Some important packages didn't get installed properly.
Either your cdrom drive or your cdrom is defective.
Check the cdrom on an installed computer using \"rpm -qpl Mandrake/RPMS/*.rpm\"
") if grep { m|read failed: Input/output error| } cat_("$o->{prefix}/root/install.log");

    if (arch() !~ /^sparc/) { #- TODO restore it as may be needed for sparc
	-x "$o->{prefix}/usr/bin/dumpkeys" or $::testing or die 
"Some important packages didn't get installed properly.

Please switch to console 2 (using ctrl-alt-f2)
and look at the log file /tmp/ddebug.log

Consoles 1,3,4,7 may also contain interesting information";
    }

    pkgs::done_db();

    #-  why not? cuz weather is nice today :-) [pixel]
    sync(); sync();

    #- configure PCMCIA services if needed.
    modules::write_pcmcia($o->{prefix}, $o->{pcmcia});

    #- for mandrake_firstime
    touch "$o->{prefix}/var/lock/TMP_1ST";

    any::writeandclean_ldsoconf($o->{prefix});
    log::l("before install packages, after writing ld.so.conf");

    #- make sure some services have been enabled (or a catastrophic restart will occur).
    #- these are normally base package post install scripts or important services to start.
    run_program::rooted($o->{prefix}, "chkconfig", "--add", $_) foreach
			qw(random netfs network rawdevices sound kheader usb keytable syslog crond portmap);

    #- call update-menus at the end of package installation
    run_program::rooted($o->{prefix}, "update-menus");

    if ($o->{pcmcia}) {
	substInFile { s/.*(TaskBarShowAPMStatus).*/$1=1/ } "$o->{prefix}/usr/lib/X11/icewm/preferences";
	eval { commands::cp("$o->{prefix}/usr/share/applnk/System/kapm.kdelnk",
			    "$o->{prefix}/etc/skel/Desktop/Autostart/kapm.kdelnk") };
    }

    my $msec = "$o->{prefix}/etc/security/msec";
    substInFile { s/^usb\n//; $_ .= "usb\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^xgrp\n//; $_ .= "xgrp\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^audio\n//; $_ .= "audio\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^cdrom\n//; $_ .= "cdrom\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^cdwriter\n//; $_ .= "cdwriter\n" if eof } "$msec/group.conf" if -d $msec;

    my $pkg = pkgs::packageByName($o->{packages}, 'urpmi');
    if ($pkg && pkgs::packageSelectedOrInstalled($pkg)) {
	install_any::install_urpmi($o->{prefix}, 
				   $::oem ? 'cdrom' : $o->{method}, #- HACK
				   $o->{packages}{mediums});
    }
    if (my $charset = lang::charset($o->{lang}, $o->{prefix})) {
	eval { update_userkderc("$o->{prefix}/usr/share/config/kdeglobals", 'Locale', Charset => $charset) };
    }

#    #- update language and icons for KDE.
#    update_userkderc($_, 'Locale', Language => "") foreach list_skels($o->{prefix}, '.kderc');
#    log::l("updating kde icons according to available devices");
#    install_any::kdeicons_postinstall($o->{prefix});

    my $welcome = _("Welcome to %s", "HOSTNAME");
    substInFile { s/^(GreetString)=.*/$1=$welcome/ } "$o->{prefix}/usr/share/config/kdmrc";
    substInFile { s/^(UserView)=true/$1=false/ } "$o->{prefix}/usr/share/config/kdmrc" if $o->{security} >= 3;
    run_program::rooted($o->{prefix}, "kdeDesktopCleanup");

    #- konsole and gnome-terminal are lamers in exotic languages, link them to something better
    if ($o->{lang} =~ /ja|ko|zh/) {
	foreach ("konsole", "gnome-terminal") {
	    my $f = "$o->{prefix}/usr/bin/$_";
	    symlinkf("X11/rxvt.sh", $f) if -e $f;
	}
    }
    foreach (list_skels($o->{prefix}, '.kde/share/config/kfmrc')) {
	my $found;
	substInFile {
	    $found ||= /KFM Misc Defaults/;
	    $_ .= 
"[KFM Misc Defaults]
GridWidth=85
GridHeight=70
" if eof && !$found;
	} $_ 
    }

    #- move some file after an upgrade that may be seriously annoying.
    #- and rename saved files to .mdkgiorig.
    if ($o->{isUpgrade}) {
	log::l("moving previous desktop files that have been updated to Trash of each user");
	install_any::kdemove_desktop_file($o->{prefix});

	foreach (@filesToSaveForUpgrade) {
	    if (-e "$o->{prefix}$_.mdkgisave") {
		unlink "$o->{prefix}$_.mdkgiorig"; rename "$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_.mdkgiorig";
	    }
	}
    }
}

#------------------------------------------------------------------------------
sub selectMouse($) {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o) = @_;
    require network;
    network::configureNetwork2($o->{prefix}, $o->{netc}, $o->{intf}, sub { $o->pkg_install(@_) });
}

#------------------------------------------------------------------------------
sub installCrypto {
    my ($o) = @_;
    my $u = $o->{crypto} or return; $u->{mirror} && $u->{packages} or return;

    upNetwork($o);
    require crypto;
    my @crypto_packages = crypto::getPackages($o->{prefix}, $o->{packages}, $u->{mirror});
    $o->pkg_install(@{$u->{packages}});
}

sub summary {
    my ($o) = @_;
    configureTimezone($o);
    configurePrinter($o);
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o) = @_;
    install_any::preConfigureTimezone($o);

    require timezone;
    timezone::write($o->{prefix}, $o->{timezone});
}

#------------------------------------------------------------------------------
sub configureServices {
    my ($o) = @_;
    if ($o->{services}) {
	require services;
	services::doit($o, $o->{services}, $o->{prefix});
    }
}
#------------------------------------------------------------------------------
sub configurePrinter {
    my($o) = @_;
    my ($use_cups, $use_lpr) = (0, 0);
    foreach (values %{$o->{printer}{configured} || {}}) {
	for ($_->{mode}) {
	    /CUPS/ and $use_cups++;
	    /lpr/  and $use_lpr++;
	}
    }
    #- if at least one queue is configured, configure it.
    if ($use_cups || $use_lpr) {
	$o->pkg_install(($use_cups ? ('cups-drivers') : ()), ($use_lpr ? ('rhs-printfilters') : ()));

	require printer;
	eval { add2hash($o->{printer}, printer::getinfo($o->{prefix})) }; #- get existing configuration.
	$use_cups and printer::poll_ppd_base();
	$use_lpr and printer::read_printer_db();
	foreach (keys %{$o->{printer}{configured} || {}}) {
	    log::l("configuring printer queue $_->{queue} for $_->{mode}");
	    printer::copy_printer_params($_, $o->{printer});
	    #- setup all configured queues, which is not the case interactively where
	    #- only the working queue is setup on configuration.
	    printer::configure_queue($o->{printer});
	}
    }
}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $u = $o->{superuser} ||= {};
    local $o->{superuser}{name} = 'root';
    any::write_passwd_user($o->{prefix}, $o->{superuser}, $o->{authentication}{md5});
}

#------------------------------------------------------------------------------

sub addUser {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $users = $o->{users} ||= [];

    my (%uids, %gids); 
    foreach (glob_("$p/home")) { my ($u, $g) = (stat($_))[4,5]; $uids{$u} = 1; $gids{$g} = 1; }

    foreach (@$users) {
	$_->{home} ||= "/home/$_->{name}";

	my $u = $_->{uid} || ($_->{oldu} = (stat("$p$_->{home}"))[4]);
	my $g = $_->{gid} || ($_->{oldg} = (stat("$p$_->{home}"))[5]);
	#- search for available uid above 501 else initscripts may fail to change language for KDE.
	if (!$u || getpwuid($u)) { for ($u = 501; getpwuid($u) || $uids{$u}; $u++) {} }
	if (!$g || getgrgid($g)) { for ($g = 501; getgrgid($g) || $gids{$g}; $g++) {} }
	
	$_->{uid} = $u; $uids{$u} = 1;
	$_->{gid} = $g; $gids{$g} = 1;
    }

    any::write_passwd_user($p, $_, $o->{authentication}{md5}) foreach @$users;

    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$_->{name}:x:$_->{gid}:\n" foreach @$users;

    foreach my $u (@$users) {
	if (! -d "$p$u->{home}") {
	    my $mode = $o->{security} < 2 ? 0755 : 0750;
	    eval { commands::cp("-f", "$p/etc/skel", "$p$u->{home}") };
	    if ($@) {
		log::l("copying of skel failed: $@"); mkdir("$p$u->{home}", $mode); 
	    } else {
		chmod $mode, "$p$u->{home}";
	    }
	}
	require commands;
	eval { commands::chown_("-r", "$u->{uid}.$u->{gid}", "$p$u->{home}") }
	    if $u->{uid} != $u->{oldu} || $u->{gid} != $u->{oldg};
    }
    any::addUsers($p, $users);

    $o->pkg_install("autologin") if $o->{autologin};
    any::set_autologin($p, $o->{autologin}, $o->{desktop});

    install_any::setAuthentication($o);
}

#------------------------------------------------------------------------------
sub createBootdisk($) {
    my ($o) = @_;
    my $dev = $o->{mkbootdisk} or return;

    my @l = detect_devices::floppies();

    $dev = shift @l || die _("No floppy drive available")
      if $dev eq "1"; #- special case meaning autochoose

    return if $::testing;

    require bootloader;
    bootloader::mkbootdisk($o->{prefix}, install_any::kernelVersion($o), $dev, $o->{bootloader}{perImageAppend});
    $o->{mkbootdisk} = $dev;
}

#------------------------------------------------------------------------------
sub readBootloaderConfigBeforeInstall {
    my ($o) = @_;
    my ($image, $v);

    require bootloader;
    add2hash($o->{bootloader} ||= {}, bootloader::read($o->{prefix}, arch() =~ /sparc/ ? "/etc/silo.conf" : "/etc/lilo.conf"));

    #- since kernel or kernel-smp may not be upgraded, it should be checked
    #- if there is a need to update existing lilo.conf entries by following
    #- symlinks before kernel or other packages get installed.
    #- update everything that could be a filename (for following symlink).
    foreach my $e (@{$o->{bootloader}{entries}}) {
	while (my $v = readlink "$o->{prefix}/$e->{kernel_or_dev}") {
	    $v = "/boot/$v" if $v !~ m|^/|; -e "$o->{prefix}$v" or last;
	    log::l("renaming /boot/$e->{kernel_or_dev} entry by $v");
	    $e->{kernel_or_dev} = $v;
	}
	while (my $v = readlink "$o->{prefix}/$e->{initrd}") {
	    $v = "/boot/$v" if $v !~ m|^/|; -e "$o->{prefix}$v" or last;
	    log::l("renaming /boot/$e->{initrd} entry by $v");
	    $e->{initrd} = $v;
	}
    }
}

sub setupBootloaderBefore {
    my ($o) = @_;
    if (arch() =~ /alpha/) {
	if (my $dev = fsedit::get_root($o->{fstab})) {
	    $o->{bootloader}{boot} ||= "/dev/$dev->{rootDevice}";
	    $o->{bootloader}{root} ||= "/dev/$dev->{device}";
	    $o->{bootloader}{part_nb} ||= first($dev->{device} =~ /(\d+)/);
	}
    } else {
	#- check for valid fb mode to enable a default boot with frame buffer.
	my $vga = $o->{allowFB} && (!detect_devices::matching_desc('Rage LT') &&
				    !detect_devices::matching_desc('SiS') &&
				    !detect_devices::matching_desc('Rage Mobility')) && $o->{vga};

	require bootloader;
	#- propose the default fb mode for kernel fb, if aurora is installed too.
        bootloader::suggest($o->{prefix}, $o->{bootloader}, $o->{hds}, $o->{fstab}, install_any::kernelVersion($o),
			    pkgs::packageFlagInstalled(pkgs::packageByName($o->{packages}, 'Aurora') || {}) && $vga);
        bootloader::suggest_floppy($o->{bootloader}) if $o->{security} <= 3;
	$o->{bootloader}{keytable} ||= keyboard::keyboard2kmap($o->{keyboard});
    }
}

sub setupBootloader($) {
    my ($o) = @_;
    return if $::g_auto_install;

    if (arch() =~ /alpha/) {
	return if $::testing;
	my $b = $o->{bootloader};
	$b->{boot} or $o->ask_warn('', "Can't install aboot, not a bsd disklabel"), return;
		
	run_program::rooted($o->{prefix}, "swriteboot", $b->{boot}, "/boot/bootlx") or do {
	    cdie "swriteboot failed";
	    run_program::rooted($o->{prefix}, "swriteboot", "-f1", $b->{boot}, "/boot/bootlx");
	};
	run_program::rooted($o->{prefix}, "abootconf", $b->{boot}, $b->{part_nb});
 
        modules::load('loop');
	output "$o->{prefix}/etc/aboot.conf", 
	map_index { -e "$o->{prefix}/boot/initrd-$_->[1]" ? 
			    "$::i:$b->{part_nb}$_->[0] root=$b->{root} initrd=/boot/initrd-$_->[1] $b->{perImageAppend}\n" :
			    "$::i:$b->{part_nb}$_->[0] root=$b->{root} $b->{perImageAppend}\n" }
	map { run_program::rooted($o->{prefix}, "mkinitrd", "-f", "/boot/initrd-$_->[1]", "--ifneeded", $_->[1]) ;#or
	  #unlink "$o->{prefix}/boot/initrd-$_->[1]";$_ } grep { $_->[0] && $_->[1] }
	  $_ } grep { $_->[0] && $_->[1] }
	map { [ m|$o->{prefix}(/boot/vmlinux-(.*))| ] } glob_("$o->{prefix}/boot/vmlinux-*");
#	output "$o->{prefix}/etc/aboot.conf", 
#	  map_index { "$::i:$b->{part_nb}$_ root=$b->{root} $b->{perImageAppend}\n" }
#	    map { /$o->{prefix}(.*)/ } eval { glob_("$o->{prefix}/boot/vmlinux*") };
    } else {
	require bootloader;
	bootloader::install($o->{prefix}, $o->{bootloader}, $o->{fstab}, $o->{hds});
    }
}

#------------------------------------------------------------------------------
sub configureXBefore {
    my ($o) = @_;
    my $xkb = $o->{X}{keyboard}{xkb_keymap} || keyboard::keyboard2xkb($o->{keyboard});
    $xkb = '' if !($xkb && -e "$o->{prefix}/usr/X11R6/lib/X11/xkb/symbols/$xkb");
    if (!$xkb && (my $f = keyboard::xmodmap_file($o->{keyboard}))) {
	require commands;
	commands::cp("-f", $f, "$o->{prefix}/etc/X11/xinit/Xmodmap");	
	$xkb = '';

    }
    {
	my $f = "$o->{prefix}/etc/sysconfig/i18n";
	setVarsInSh($f, add2hash_({ XKB_IN_USE => $xkb ? '': 'no' }, { getVarsFromSh($f) }));
    }
    $o->{X}{keyboard}{xkb_keymap} = $xkb;
    $o->{X}{mouse} = $o->{mouse};
    $o->{X}{wacom} = $o->{wacom};

    require Xconfig;
    Xconfig::getinfoFromDDC($o->{X});
    Xconfig::getinfoFromXF86Config($o->{X}, $o->{prefix}); #- take default from here at least.

    #- keep this here if the package has to be updated.
    $o->pkg_install("XFree86");
}
sub configureX {
    my ($o) = @_;
    $o->configureXBefore;

    require Xconfigurator;
    require class_discard;
    { local $::testing = 0; #- unset testing
      local $::auto = 1;
      $o->{X}{skiptest} = 1;
      Xconfigurator::main($o->{prefix}, $o->{X}, class_discard->new, $o->{allowFB}, sub { $o->pkg_install(@_) });
    }
    $o->configureXAfter;
}
sub configureXAfter {
    my ($o) = @_;
    if ($o->{X}{card}{server} eq 'FBDev') {
	unless (install_any::setupFB($o, Xconfigurator::getVGAMode($o->{X}))) {
	    log::l("disabling automatic start-up of X11 if any as setup framebuffer failed");
	    Xconfigurator::rewriteInittab(3) unless $::testing; #- disable automatic start-up of X11 on error.
	}
    }
    if ($o->{X}{default_depth} >= 16 && $o->{X}{card}{default_wres} >= 1024) {
	log::l("setting large icon style for kde");
	install_any::kderc_largedisplay($o->{prefix});
    }
}

#------------------------------------------------------------------------------
sub miscellaneousBefore {
    my ($o) = @_;

    my %s = getVarsFromSh("$o->{prefix}/etc/sysconfig/system");
    $o->{miscellaneous}{HDPARM} ||= $s{HDPARM} if exists $s{HDPARM};
    $o->{security} ||= $s{SECURITY} if exists $s{SECURITY};

    $ENV{SECURE_LEVEL} = $o->{security};
    add2hash_ $o, { useSupermount => $o->{security} < 4 && arch() !~ /sparc/ && !$::corporate };

    add2hash_($o->{miscellaneous} ||= {}, { numlock => !$o->{pcmcia} });
}
sub miscellaneous {
    my ($o) = @_;

    local $_ = $o->{bootloader}{perImageAppend};

    if ($o->{lnx4win} and !/mem=/) {
	$_ .= ' mem=' . availableRamMB() . 'M';
    }
    if (my @l = detect_devices::IDEburners() and !/ide-scsi/) {
	$_ .= " " . join(" ", (map { "$_->{device}=ide-scsi" } @l), 
			 #- in that case, also add ide-floppy otherwise ide-scsi will be used!
			 map { "$_->{device}=ide-floppy" } detect_devices::ide_zips());
    }
    if ($o->{miscellaneous}{HDPARM}) {
	$_ .= join('', map { " $_=autotune" } grep { /ide.*/ } all("/proc/ide")) if !/ide.=autotune/;
    }
    #- keep some given parameters
    #-TODO

    log::l("perImageAppend: $_");
    $o->{bootloader}{perImageAppend} = $_;
}

#------------------------------------------------------------------------------
sub generateAutoInstFloppy($) {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub exitInstall { 
    my ($o) = @_;
    eval { output "$o->{prefix}/root/report.bug", commands::report_bug() };
    install_any::unlockCdrom;
    install_any::log_sizes($o);
}

#------------------------------------------------------------------------------
sub hasNetwork {
    my ($o) = @_;

    $o->{intf} && $o->{netc}{NETWORKING} ne 'no' || $o->{netcnx}{modem};
}

#------------------------------------------------------------------------------
sub upNetwork {
    my ($o, $pppAvoided) = @_;

    foreach (qw(resolv.conf protocols services)) {
	symlinkf("$o->{prefix}/etc/$_", "/etc/$_");
    }

    modules::write_conf($o->{prefix});
    if ($o->{intf} && $o->{netc}{NETWORKING} ne 'no') {
	network::up_it($o->{prefix}, $o->{intf});
    } elsif (!$pppAvoided && $o->{netcnx}{modem} && !$o->{netcnx}{modem}{isUp}) {
	eval { modules::load_multi(qw(serial ppp bsd_comp ppp_deflate)) };
	run_program::rooted($o->{prefix}, "/etc/rc.d/init.d/syslog", "start");
	run_program::rooted($o->{prefix}, "ifup", "ppp0");
	$o->{netcnx}{modem}{isUp} = 1;
    } else {
	$::testing or return;
    }
    1;
}

#------------------------------------------------------------------------------
sub downNetwork {
    my ($o, $pppOnly) = @_;

    modules::write_conf($o->{prefix});
    if (!$pppOnly && $o->{intf} && $o->{netc}{NETWORKING} ne 'no') {
	network::down_it($o->{prefix}, $o->{intf});
    } elsif ($o->{netcnx}{modem} && $o->{netcnx}{modem}{isUp}) {
	run_program::rooted($o->{prefix}, "ifdown", "ppp0");
	run_program::rooted($o->{prefix}, "/etc/rc.d/init.d/syslog", "stop");
	eval { modules::unload($_) foreach qw(ppp_deflate bsd_comp ppp serial) };
	$o->{netcnx}{modem}{isUp} = 0;
    } else {
	$::testing or return;
    }
    1;
}

#------------------------------------------------------------------------------
sub cleanIfFailedUpgrade($) {
    my ($o) = @_;

    #- if an upgrade has failed, there should be .mdkgisave files around.
    if ($o->{isUpgrade}) {
	foreach (@filesToSaveForUpgrade) {
	    if (-e "$o->{prefix}/$_" && -e "$o->{prefix}/$_.mdkgisave") {
		rename "$o->{prefix}/$_", "$o->{prefix}/$_.mdkginew"; #- keep new files around in case !
		rename "$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_";
	    }
	}
    }
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
