package install_steps; # $Id$

use diagnostics;
use strict;
use vars qw(@filesToSaveForUpgrade @ISA);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use install_any qw(:all);
use partition_table qw(:types);
use detect_devices;
use modules;
use run_program;
use lang;
use keyboard;
use fsedit;
use loopback;
use pkgs;
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
	eval { cp_af("/tmp/ddebug.log", "$o->{prefix}/root") };
	output(install_any::auto_inst_file(), install_any::g_auto_install());
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
	keyboard::setup($o->{keyboard}) if !$::live;
    }

    addToBeDone {
	lang::write_langs($o->{prefix}, $o->{langs});
    } 'formatPartitions' unless $::g_auto_install;
    addToBeDone {
	lang::write($o->{prefix}, $o->{lang});
    } 'installPackages' unless $::g_auto_install;
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup($o->{keyboard});

    addToBeDone {
	keyboard::write($o->{prefix}, $o->{keyboard}, lang::lang2charset($o->{lang}));
    } 'installPackages' unless $::g_auto_install;
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
    eval { 
	close *pkgs::LOG;
	eval { fs::umount("$o->{prefix}/proc") };
	eval {          fs::umount_all($o->{fstab}, $o->{prefix}) };
	eval { sleep 1; fs::umount_all($o->{fstab}, $o->{prefix}) } if $@; #- HACK
    } if $o->{fstab} && !$::testing && !$::live;
}

#------------------------------------------------------------------------------
sub doPartitionDisksAfter {
    my ($o) = @_;

    if (!$::testing) {
	my $hds = $o->{all_hds}{hds};
	partition_table::write($_) foreach @$hds;
	$_->{rebootNeeded} and $o->rebootNeeded foreach @$hds;
    }

    fs::set_removable_mntpoints($o->{all_hds});
    fs::set_all_default_options($o->{all_hds}, $o->{useSupermount}, $o->{security}, lang::fs_options($o->{lang}))
	if !$o->{isUpgrade};

    $o->{fstab} = [ fsedit::get_all_fstab($o->{all_hds}) ];
    fsedit::get_root_($o->{fstab}) or die "Oops, no root partition";

    # do not use devfs with root software raid
    foreach ($o->{bootloader}{perImageAppend}) {
	$_ .= ' devfs=mount' if !/devfs=/;
    }
    
    if (arch() =~ /ppc/ && detect_devices::get_mac_generation =~ /NewWorld/) {
	die "Need bootstrap partition to boot system!" if !(defined $partition_table_mac::bootstrap_part);
    }
    
    if (arch() =~ /ia64/ && !fsedit::has_mntpoint("/boot/efi", $o->{all_hds})) {
	die _("You must have a FAT partition mounted in /boot/efi");
    }

    if ($o->{partitioning}{use_existing_root}) {
	#- ensure those partitions are mounted so that they are not proposed in choosePartitionsToFormat
	fs::mount_part($_, $o->{prefix}) foreach (sort { $a->{mntpoint} cmp $b->{mntpoint} }
						  grep { $_->{mntpoint} && maybeFormatted($_) } @{$o->{fstab}});
    }

    cat_("/proc/mounts") =~ m|(\S+)\s+/tmp/image nfs| &&
      !grep { $_->{mntpoint} eq "/mnt/nfs" } @{$o->{all_hds}{nfss}} and
	push @{$o->{all_hds}{nfss}}, { type => 'nfs', mntpoint => "/mnt/nfs", device => $1, options => "noauto,ro,nosuid,rsize=8192,wsize=8192" };
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    install_any::getHds($o);

    if ($o->{partitioning}{use_existing_root} || $o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = fsedit::get_root_($o->{fstab}) || first(install_any::find_root_parts($o->{fstab}, $o->{prefix})) or die;
	install_any::use_root_part($o->{fstab}, $p, $o->{prefix});
    } 
    if ($o->{partitioning}{auto_allocate}) {
	fsedit::auto_allocate($o->{all_hds}, $o->{partitions});
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
        $_->{toFormatUnsure} = member($_->{mntpoint}, '/', '/usr');

	if (!$_->{toFormat}) {
	    my $t = fsedit::typeOfPart($_->{device});
	    $_->{toFormatUnsure} ||=
	      #- if detected dos/win, it's not precise enough to just compare the types (too many of them)
	      (!$t || isOtherAvailableFS({ type => $t }) ? !isOtherAvailableFS($_) : $t != $_->{type});
	}
    }
}

sub formatMountPartitions {
    my ($o) = @_;
    fs::formatMount_all($o->{all_hds}{raids}, $o->{fstab}, $o->{prefix});
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
    my ($o, $packages, $compssUsers, $first_time) = @_;

    #- now for upgrade, package that must be upgraded are
    #- selected first, after is used the same scheme as install.

    #- make sure we kept some space left for available else the system may
    #- not be able to start (xfs at least).
    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);
    log::l(sprintf "available size %s (corrected %s)", formatXiB($available), formatXiB($availableCorrected));

    add2hash_($o, { compssListLevel => 5 }) if !$::auto_install;

    #- avoid destroying user selection of packages but only
    #- for expert, as they may have done individual selection before.
    if ($first_time || !$::expert) {
	install_any::unselectMostPackages($o);

	exists $o->{compssListLevel}
	  and pkgs::setSelectedFromCompssList($packages, $o->{compssUsersChoice}, $o->{compssListLevel}, $availableCorrected);
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
		eval { cp_af("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
    }

    #- some packages need such files for proper installation.
    install_any::write_fstab($o);

    require network;
    network::add2hosts("$o->{prefix}/etc/hosts", "localhost.localdomain", "127.0.0.1");
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
	if (scalar(keys %newSelection) == 1) {
	    pkgs::selectPackage($o->{packages}, $pkg);
	} else {
	    log::l("pkg_install_if_requires_satisfied: not selecting $_ because of ", join(", ", keys %newSelection));
	}
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
		eval { cp_af("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
	pkgs::remove($o->{prefix}, $o->{toRemove});
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_.mdkgisave") {
		renamef("$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_");
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
    run_program::rooted_or_die($o->{prefix}, 'ldconfig') unless $::g_auto_install;
    log::l("Install took: ", formatTimeRaw(time - $time));
    install_any::log_sizes($o);
    scalar(@toInstall); #- return number of packages installed.
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

    #-  why not? cuz weather is nice today :-) [pixel]
    common::sync(); common::sync();

    #- generate /etc/lvmtab needed for rc.sysinit
    run_program::rooted($o->{prefix}, 'vgscan') if -e '/etc/lvmtab';

    #- configure PCMCIA services if needed.
    modules::write_pcmcia($o->{prefix}, $o->{pcmcia});

    #- for mandrake_firstime
    touch "$o->{prefix}/var/lock/TMP_1ST";

    any::writeandclean_ldsoconf($o->{prefix});

    #- make sure wins is disabled in /etc/nsswitch.conf
    #- else if eth0 is not existing, glibc segfaults.
    substInFile { s/\s*wins// if /^\s*hosts\s*:/ } "$o->{prefix}/etc/nsswitch.conf";

    #- make sure some services have been enabled (or a catastrophic restart will occur).
    #- these are normally base package post install scripts or important services to start.
    run_program::rooted($o->{prefix}, "chkconfig", "--add", $_) foreach
			qw(random netfs network rawdevices sound kheader usb keytable syslog crond portmap);

    run_program::rooted($o->{prefix}, "chkconfig", "--del", "gpm") if $o->{mouse}{device} =~ /ttyS/;

    #- call update-menus at the end of package installation
    run_program::rooted($o->{prefix}, "update-menus");

    if ($o->{pcmcia}) {
	substInFile { s/.*(TaskBarShowAPMStatus).*/$1=1/ } "$o->{prefix}/usr/lib/X11/icewm/preferences";
	eval { cp_af("$o->{prefix}/usr/share/applnk/System/kapm.kdelnk",
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
	pkgs::saveCompssUsers($o->{prefix}, $o->{packages}, $o->{compssUsers}, $o->{compssUsersSorted});
    }

#    #- update language and icons for KDE.
#    update_gnomekderc($_, 'Locale', Language => "") foreach list_skels($o->{prefix}, '.kderc');
#    log::l("updating kde icons according to available devices");
#    install_any::kdeicons_postinstall($o->{prefix});

    if ($o->{lang} =~ /^(zh_TW|th|vi|be|bg)/) {
	#- skip since we don't have the right font (it badly fails at least for zh_TW)
    } elsif (my $LANG = lang::lang2LANG($o->{lang})) {
	my $kdmrc = "$o->{prefix}/usr/share/config/kdm/kdmrc";

	my $charset = lang::lang2charset($o->{lang});
	$charset = '' if member($charset, 'iso-8859-1', 'iso-8859-15'); #- keep the default for those
	$charset = 'jisx0208.1983-0' if $charset eq 'jisx0208';
	$charset = 'ksc5601.1987-0' if $charset eq 'ksc5601';

	my $welcome = c::to_utf8(_("Welcome to %s", '%n'));
	substInFile { 
	    s/^(GreetString)=.*/$1=$welcome/;
	    s/^(Language)=.*/$1=$LANG/;
	    if ($charset) {
		s/^(StdFont)=.*/$1=*,12,5,$charset,50,0/;
		s/^(FailFont)=.*/$1=*,12,5,$charset,75,0/;
		s/^(GreetFont)=.*/$1=*,24,5,$charset,50,0/;
	    }
	} "$o->{prefix}/usr/share/config/kdm/kdmrc";

    }
    install_any::disable_user_view($o->{prefix}) if $o->{security} >= 3 || $o->{authentication}{NIS};
    run_program::rooted($o->{prefix}, "kdeDesktopCleanup");

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
	my $pkg = pkgs::packageByName($o->{packages}, 'rpm');
	$pkg && pkgs::packageSelectedOrInstalled($pkg) && pkgs::versionCompare(pkgs::packageVersion($pkg), '4.0') >= 0 and
	  pkgs::clean_old_rpm_db($o->{prefix});

	log::l("moving previous desktop files that have been updated to Trash of each user");
	install_any::kdemove_desktop_file($o->{prefix});

	foreach (@filesToSaveForUpgrade) {
	    renamef("$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_.mdkgiorig")
	      if -e "$o->{prefix}$_.mdkgisave";
	}
    }

    if ($o->{blank} || $o->{updatemodules}) {
	my @l = detect_devices::floppies_dev();

	foreach (qw(blank updatemodules)) {
	    $o->{$_} eq "1" and $o->{$_} = $l[0] || die _("No floppy drive available");
	}

	$o->{blank} and $o->copyKernelFromFloppy();
	$o->{updatemodules} and $o->updateModulesFromFloppy();
    }
}

sub copyKernelFromFloppy {
    my ($o) = @_;
    return if $::testing || !$o->{blank};

    fs::mount($o->{blank}, "/floppy", "vfat", 0);
    eval { cp_af("/floppy/vmlinuz", "$o->{prefix}/boot/vmlinuz-default") };
    if ($@) {
	log::l("copying of /floppy/vmlinuz from blank modified disk failed: $@");
    }
    fs::umount("/floppy");
}

sub updateModulesFromFloppy {
    my ($o) = @_;
    return if $::testing || !$o->{updatemodules};

    fs::mount($o->{updatemodules}, "/floppy", "ext2", 0);
    foreach (glob_("$o->{prefix}/lib/modules/*")) {
	my ($kernelVersion) = m,lib/modules/(\S*),;
	log::l("examining updated modules for kernel $kernelVersion");
	if (-d "/floppy/$kernelVersion") {
	    my @src_files = glob_("/floppy/$kernelVersion/*");
	    my @dest_files = split "\n", `chroot $o->{prefix} find /lib/modules`;
	    foreach my $s (@src_files) {
		log::l("found updatable module $s");
		my ($sfile, $sext) = $s =~ /([^\/\.]*\.o)(?:\.gz|\.bz2)?$/;
		my $qsfile = quotemeta $sfile;
		my $qsext = quotemeta $sext;
		foreach my $target (@dest_files) {
		    $target =~ /$qsfile/ or next;
		    eval { cp_af($s, $target) };
		    if ($@) {
			log::l("updating module $target by $s failed: $@");
		    } else {
			log::l("updating module $target by $s");
		    }
		    if ($target !~ /$qsfile$qsext$/) {
			#- extension differ, first rename target file correctly,
			#- then uncompress source file, then compress it as expected.
			my ($basetarget, $text) = $target =~ /(.*?)(\.gz|\.bz2)$/;
			rename $target, "$basetarget$sext";
			$sext eq '.gz' and run_program::run("gzip", "-d", "$basetarget$sext");
			$sext eq '.bz2' and run_program::run("bzip2", "-d", "$basetarget$sext");
			$text eq '.gz' and run_program::run("gzip", $basetarget);
			$text eq '.bz2' and run_program::run("bzip2", $basetarget);
		    }
		}
	    }
	}
    }
    fs::umount("/floppy");
}

#------------------------------------------------------------------------------
sub selectMouse($) {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o) = @_;
    require network;
    network::configureNetwork2($o, $o->{prefix}, $o->{netc}, $o->{intf});
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
    configurePrinter($o) if $o->{printer};
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o) = @_;
    install_any::preConfigureTimezone($o);

    $o->pkg_install('ntp') if $o->{timezone}{ntp};

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
    $o->do_pkgs->install('foomatic', 'printer-utils','printer-testpages',
			 if_($o->do_pkgs->is_installed('gimp'), 'gimpprint'));
    
    require printer;
    eval { add2hash($o->{printer} ||= {}, printer::getinfo($o->{prefix})) }; #- get existing configuration.

    require printerdrake;
    printerdrake::install_spooler($o->{printer}, $o); #- not interactive...

    foreach (values %{$o->{printer}{configured} || {}}) {
	log::l("configuring printer queue " . $_->{queuedata}{queue} || $_->{QUEUE});
	#- when copy is so adulée (sorry french taste :-)
	#- and when there are some configuration in one place and in another place...
	$o->{printer}{currentqueue} = {};
	printer::copy_printer_params($_->{queuedata}, $o->{printer}{currentqueue});
	printer::copy_printer_params($_, $o->{printer});
	#- setup all configured queues, which is not the case interactively where
	#- only the working queue is setup on configuration.
	printer::configure_queue($o->{printer});
    }
}

#------------------------------------------------------------------------------
sub setRootPassword {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $u = $o->{superuser} ||= {};
    $o->{superuser}{name} = 'root';
    any::write_passwd_user($o->{prefix}, $o->{superuser}, $o->{authentication}{md5});
    delete $o->{superuser}{name};
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
	if (!$g                ) { for ($g = 501; getgrgid($g) || $gids{$g}; $g++) {} }
	
	$_->{uid} = $u; $uids{$u} = 1;
	$_->{gid} = $g; $gids{$g} = 1;
    }

    any::write_passwd_user($p, $_, $o->{authentication}{md5}) foreach @$users;

    local *F;
    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$_->{name}:x:$_->{gid}:\n" foreach grep { ! getgrgid($_->{gid}) } @$users;

    foreach my $u (@$users) {
	if (! -d "$p$u->{home}") {
	    my $mode = $o->{security} < 2 ? 0755 : 0750;
	    eval { cp_af("$p/etc/skel", "$p$u->{home}") };
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

    install_any::disable_user_view($p) if @$users == ();
}

#------------------------------------------------------------------------------
sub createBootdisk($) {
    my ($o) = @_;
    my $dev = $o->{mkbootdisk} or return;

    my @l = detect_devices::floppies_dev();

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
    add2hash($o->{bootloader} ||= {}, bootloader::read($o->{prefix}, arch() =~ /sparc/ ? "/etc/silo.conf" : arch() =~ /ppc/ ? "/etc/yaboot.conf" : "/etc/lilo.conf"));

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
	my $vga = $o->{allowFB} && (!detect_devices::matching_desc('3D Rage LT') &&
				    !detect_devices::matching_desc('Rage Mobility [PL]') &&
				    !detect_devices::matching_desc('i740') &&
				    !detect_devices::matching_desc('Matrox') &&
				    !detect_devices::matching_desc('Tseng.*ET6\d00') &&
				    !detect_devices::matching_desc('SiS.*SG86C2.5') &&
				    !detect_devices::matching_desc('SiS.*559[78]') &&
				    !detect_devices::matching_desc('SiS.*300') &&
				    !detect_devices::matching_desc('SiS.*540') &&
				    !detect_devices::matching_desc('SiS.*6C?326') &&
				    !detect_devices::matching_desc('SiS.*6C?236') &&
				    !detect_devices::matching_desc('Voodoo [35]|Voodoo Banshee') && #- 3d acceleration seems to bug in fb mode
				    !detect_devices::matching_desc('8281[05].* CGC') #- i810 now have FB support during install but we disable it afterwards
				   );
	my $force_vga = $o->{allowFB} && (detect_devices::matching_desc('SiS.*630') #- SiS 630 need frame buffer.
					 );

	require bootloader;
	#- propose the default fb mode for kernel fb, if aurora is installed too.
	my $has_aurora = do {
	    my $p = pkgs::packageByName($o->{packages}, 'Aurora');
	    $p && pkgs::packageFlagInstalled($p);
	};
        bootloader::suggest($o->{prefix}, $o->{bootloader}, $o->{all_hds}{hds}, $o->{fstab}, install_any::kernelVersion($o),
			    ($force_vga || $vga && $has_aurora) && $o->{vga});
	bootloader::suggest_floppy($o->{bootloader}) if $o->{security} <= 3 && arch() !~ /ppc/;

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
	bootloader::install($o->{prefix}, $o->{bootloader}, $o->{fstab}, $o->{all_hds}{hds});
    }
}

#------------------------------------------------------------------------------
sub configureXBefore {
    my ($o) = @_;
    my $xkb = $o->{X}{keyboard}{xkb_keymap} || keyboard::keyboard2xkb($o->{keyboard});
    $xkb = '' if !($xkb && $xkb =~ /([^(]*)/ && -e "$o->{prefix}/usr/X11R6/lib/X11/xkb/symbols/$1");
    if (!$xkb && (my $f = keyboard::xmodmap_file($o->{keyboard}))) {
	cp_af($f, "$o->{prefix}/etc/X11/xinit/Xmodmap");	
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
      Xconfigurator::main($o->{prefix}, $o->{X}, class_discard->new, $o->do_pkgs,
			  { allowFB          => $o->{allowFB},
			    allowNVIDIA_rpms => install_any::allowNVIDIA_rpms($o->{packages}),
			  });
    }
    $o->configureXAfter;
}
sub configureXAfter {
    my ($o) = @_;
    if ($o->{X}{card}{server} eq 'FBDev') {
	unless (install_any::setupFB($o, Xconfigurator::getVGAMode($o->{X}))) {
	    log::l("disabling automatic start-up of X11 if any as setup framebuffer failed");
	    any::runlevel($o->{prefix}, 3) unless $::testing; #- disable automatic start-up of X11 on error.
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
    add2hash_ $o, { useSupermount => 1 && $o->{security} < 4 && arch() !~ /sparc/ && !$::corporate };

    add2hash_($o->{miscellaneous} ||= {}, { numlock => !$o->{pcmcia} });
}
sub miscellaneous {
    my ($o) = @_;

    local $_ = $o->{bootloader}{perImageAppend};

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
sub exitInstall { 
    my ($o) = @_;
    eval { output "$o->{prefix}/root/report.bug", install_any::report_bug($o->{prefix}) };
    install_any::getAndSaveAutoInstallFloppy($o, 1, "$o->{prefix}/root/replay_install.img");
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
