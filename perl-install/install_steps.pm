package install_steps;

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
use raid;
use keyboard;
use log;
use fsedit;
use loopback;
use commands;
use network;
use any;
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
    $o->{langs} ||= [ $o->{lang} ];

    if ($o->{keyboard_unsafe} || !$o->{keyboard}) {
	$o->{keyboard_unsafe} = 1;
	$o->{keyboard} = keyboard::lang2keyboard($o->{lang});
	selectKeyboard($o);
    }
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup($o->{keyboard});
    lang::set_langs($o->{langs});
}
#------------------------------------------------------------------------------
sub selectPath {}
#------------------------------------------------------------------------------
sub selectInstallClass($@) {
    my ($o) = @_;
    $o->{installClass} ||= $::corporate ? "corporate" : "normal";
    $o->{security} ||= ${{
	normal    => 2,
	developer => 3,
	corporate => 3,
	server    => 4,
    }}{$o->{installClass}};
}
#------------------------------------------------------------------------------
sub setupSCSI { 
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
    eval { fs::umount_all($o->{fstab}, $o->{prefix}) } if $o->{fstab} && !$::testing && !$::live;

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
    fsedit::get_root($o->{fstab}) or die "Oops, no root partition";

    if (my $s = delete $o->{stage1_hd}) {
	my ($part) = grep { $_->{device} eq $s->{device} } @{$o->{fstab}};
	$part->{isMounted} ?
	  do { rmdir "/tmp/hdimage" ; symlinkf("$o->{prefix}$part->{mntpoint}", "/tmp/hdimage") } :
	  eval { fs::mount($s->{device}, "/tmp/hdimage", $s->{type}) };
    }

    cat_("/proc/mounts") =~ m|(\S+)\s+/tmp/rhimage nfs| &&
      !grep { $_->{mntpoint} eq "/mnt/nfs" } @{$o->{manualFstab} || []} and
	push @{$o->{manualFstab}}, { type => "nfs", mntpoint => "/mnt/nfs", device => $1, options => "noauto,ro,nosuid,rsize=8192,wsize=8192" };
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    install_any::getHds($o);

    if ($o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = fsedit::get_root($o->{fstab}) || first(install_any::find_root_parts($o->{hds}, $o->{prefix})) or die;
	install_any::use_root_part($o->{fstab}, $p, $o->{prefix});
    } elsif ($o->{partitioning}{auto_allocate}) {
	fsedit::auto_allocate($o->{hds}, $o->{partitions});
    }
}

#------------------------------------------------------------------------------

sub ask_mntpoint_s {
    my ($o, $fstab) = @_;

    #- TODO: set the mntpoints

    #- assure type is at least ext2
    (fsedit::get_root($fstab) || {})->{type} = 0x83;

    my %m; foreach (@$fstab) {
	my $m = $_->{mntpoint};

	next unless $m && $m ne 'swap'; #- there may be a lot of swap.

	$m{$m} and die _("Duplicate mount point %s", $m);
	$m{$m} = 1;

	#- in case the type does not correspond, force it to ext2
	$_->{type} = 0x83 if $m =~ m|^/| && !isFat($_);
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
}
sub selectPackagesToUpgrade {
    my ($o) = @_;
    pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix}, $o->{base}, $o->{toRemove}, $o->{toSave});
}

sub choosePackages {
    my ($o, $packages, $compss, $compssUsers, $compssUsersSorted, $first_time) = @_;

    #- now for upgrade, package that must be upgraded are
    #- selected first, after is used the same scheme as install.

    #- make sure we kept some space left for available else the system may
    #- not be able to start (xfs at least).
    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);
    log::l("available size $available (corrected $availableCorrected)");

    foreach (values %{$packages->[0]}) {
	pkgs::packageSetFlagSkip($_, 0);
	pkgs::packageSetFlagUnskip($_, 0);
    }

    #- avoid destroying user selection of packages. TOCHECK
    if ($first_time) {
	pkgs::unselectAllPackages($packages);
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};

	add2hash_($o, { compssListLevel => $::expert ? 90 : 80 }) unless $::auto_install;
	pkgs::setSelectedFromCompssList($o->{compssListLevels}, $packages, $o->{compssListLevel}, $availableCorrected, $o->{installClass}) if exists $o->{compssListLevel};
    }

    $availableCorrected;
}

sub beforeInstallPackages {
    my ($o) = @_;

    log::l("before install packages");
    #- save these files in case of upgrade failure.
    if ($o->{isUpgrade}) {
	foreach (@filesToSaveForUpgrade) {
	    unlink "$o->{prefix}/$_.mdkgisave";
	    if (-e "$o->{prefix}/$_") {
		eval { commands::cp("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
    }

    log::l("before install packages, after copy");
    #- some packages need such files for proper installation.
    any::writeandclean_ldsoconf($o->{prefix});
    log::l("before install packages, after writing ld.so.conf");
    $::live or fs::write($o->{prefix}, $o->{fstab}, $o->{manualFstab}, $o->{useSupermount});

    log::l("before install packages, after adding localhost in hosts");
    network::add2hosts("$o->{prefix}/etc/hosts", "localhost.localdomain", "127.0.0.1");

    log::l("before openning database");
    require pkgs;
    pkgs::init_db($o->{prefix}, $o->{isUpgrade});
    log::l("initialized database");
}

sub pkg_install {
    my ($o, @l) = @_;
    log::l("selecting packages");
    require pkgs;
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || die "$_ rpm not found") foreach @l;
    log::l("installing packages");
    $o->installPackages;
}

sub pkg_install_if_requires_satisfied {
    my ($o, @l) = @_;
    require pkgs;
    foreach (@l) {
	my %newSelection;
	my $pkg = pkgs::packageByName($o->{packages}, $_) || die "$_ rpm not found";
	pkgs::selectPackage($o->{packages}, $pkg, 0, \%newSelection) foreach @l;
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
		unlink "$o->{prefix}/$_.mdkgisave"; eval { commands::cp("$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave") };
	    }
	}
	pkgs::remove($o->{prefix}, $o->{toRemove});
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_.mdkgisave") {
		unlink "$o->{prefix}/$_"; rename "$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_";
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
    pkgs::install($o->{prefix}, $o->{isUpgrade}, \@toInstall, $packages->[1], $packages->[2]);
    delete $ENV{DURING_INSTALL};
    run_program::rooted($o->{prefix}, 'ldconfig') or die "ldconfig failed!";
    log::l("Install took: ", formatTimeRaw(time - $time));
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
    $o->pcmciaConfig();

    #- for mandrake_firstime
    touch "$o->{prefix}/var/lock/TMP_1ST";

    #- remove the nasty acon...
    run_program::rooted($o->{prefix}, "chkconfig", "--del", "acon") unless $ENV{LANGUAGE} =~ /ar/;

    #- make the mdk fonts last in available fonts for buggy kde
    run_program::rooted($o->{prefix}, "chkfontpath", "--remove", "/usr/X11R6/lib/X11/fonts/mdk");
    run_program::rooted($o->{prefix}, "chkfontpath", "--add", "/usr/X11R6/lib/X11/fonts/mdk");

    #- call update-menus at the end of package installation
    run_program::rooted($o->{prefix}, "update-menus");

    #- create /etc/sysconfig/desktop file according to user choice and presence of /usr/bin/kdm or /usr/bin/gdm.
    my $f = "$o->{prefix}/etc/sysconfig/desktop";
    if ($o->{compssUsersChoice}{KDE} && -x "$o->{prefix}/usr/bin/kdm") {
	log::l("setting desktop to KDE");
	output($f, "KDE\n");
    } elsif ($o->{compssUsersChoice}{Gnome} && -x "$o->{prefix}/usr/bin/gdm") {
	log::l("setting desktop to GNOME");
	output($f, "GNOME\n");
    }

    if ($o->{pcmcia}) {
	substInFile { s/.*(TaskBarShowAPMStatus).*/$1=1/ } "$o->{prefix}/usr/lib/X11/icewm/preferences";
	eval { commands::cp("$o->{prefix}/usr/share/applnk/System/kapm.kdelnk", 
			    "$o->{prefix}/etc/skel/Desktop/Autostart/kapm.kdelnk") };
    }

    my $msec = "$o->{prefix}/etc/security/msec";
    substInFile { s/^xgrp\n//; $_ .= "xgrp\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^audio\n//; $_ .= "audio\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^cdrom\n//; $_ .= "cdrom\n" if eof } "$msec/group.conf" if -d $msec;
    substInFile { s/^cdwriter\n//; $_ .= "cdwriter\n" if eof } "$msec/group.conf" if -d $msec;

    my $pkg = pkgs::packageByName($o->{packages}, 'urpmi');
    if ($pkg && pkgs::packageFlagSelected($pkg)) {
	install_any::install_urpmi($o->{prefix}, $o->{method}, $o->{packages}[2]);
	substInFile { s/^urpmi\n//; $_ .= "urpmi\n" if eof } "$msec/group.conf" if -d $msec;
    }

    #- update language and icons for KDE.
    update_userkderc($o->{prefix}, 'Locale', Language => "");
    log::l("updating kde icons according to available devices");
    install_any::kdeicons_postinstall($o->{prefix});

    my $welcome = _("Welcome to %s", "[HOSTNAME]");
    substInFile { s/^(GreetString)=.*/$1=$welcome/ } "$o->{prefix}/usr/share/config/kdmrc";
    substInFile { s/^(UserView)=false/$1=true/ } "$o->{prefix}/usr/share/config/kdmrc" if $o->{security} < 3;
    run_program::rooted($o->{prefix}, "kdeDesktopCleanup");

    #- konsole and gnome-terminal are lamers in exotic languages, link them to something better
    if ($o->{lang} =~ /ja|ko|zh/) {
	foreach ("konsole", "gnome-terminal") {
	    my $f = "$o->{prefix}/usr/bin/$_";
	    symlinkf("X11/rxvt.sh", $f) if -e $f;
	}
    }

#-    my $hasttf;
#-    my $dest = "/usr/X11R6/lib/X11/fonts/drakfont";
#-    foreach my $d (map { $_->{mntpoint} } grep { isFat($_) } @{$o->{fstab}}) {
#-	  foreach my $D (map { "$d/$_" } grep { m|^win|i } all("$o->{prefix}$d")) {
#-	      $D .= "/fonts";
#-	      -d "$o->{prefix}$D" or next;
#-	      log::l("found win font dir $D");
#-	      if (!$hasttf) {
#-		  $hasttf = $o->ask_okcancel('', 
#-_("Some true type fonts from windows have been found on your computer.
#-Do you want to use them? Be sure you have the right to use them under Linux."), 1) or goto nottf;
#-		  mkdir "$o->{prefix}$dest", 0755;
#-	      }
#-	      /(.*)\.ttf/i and symlink "$D/$_", "$o->{prefix}$dest/$1.ttf" foreach grep { /\.ttf/i } all("$o->{prefix}$D");
#-	  }
#-    }
#-  nottf:
#-    if ($hasttf) {
#-	  run_program::rooted($o->{prefix}, "ttmkfdir", "-d", $dest, "-o", "$dest/fonts.dir");
#-	  run_program::rooted($o->{prefix}, "chkfontpath", "--add", $dest);
#-    }

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

#------------------------------------------------------------------------------
sub pcmciaConfig($) {
    my ($o) = @_;
    my $t = $o->{pcmcia};

    #- should be set after installing the package above else the file will be renamed.
    setVarsInSh("$o->{prefix}/etc/sysconfig/pcmcia", {
	PCMCIA    => $t ? "yes" : "no",
	PCIC      => $t,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o, $f) = @_;
    require timezone;
    timezone::write($o->{prefix}, $o->{timezone}, $f);
}

#------------------------------------------------------------------------------
sub configureServices {
    my ($o) = @_;
    require services;
    services::doit($o, $o->{services}, $o->{prefix}) if $o->{services};
}
#------------------------------------------------------------------------------
sub configurePrinter {
    my($o) = @_;
    my ($use_cups, $use_lpr) = (0, 0);
    foreach (values %{$o->{printer}{configured} || {}}) {
	for ($_->{mode}) {
	    /cups/ and $use_cups++;
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
my @etc_pass_fields = qw(name pw uid gid realname home shell);
sub setRootPassword($) {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $u = $o->{superuser} ||= {};

    $u->{pw} ||= $u->{password} && any::crypt($u->{password}, $o->{authentication}{md5});

    my @lines = cat_(my $f = "$p/etc/passwd") or log::l("missing passwd file"), return;

    local *F;
    open F, "> $f" or die "failed to write file $f: $!\n";
    foreach (@lines) {
	if (/^root:/) {
	    chomp;
	    my %l; @l{@etc_pass_fields} = split ':';
	    add2hash($u, \%l);
	    $_ = join(':', @$u{@etc_pass_fields}) . "\n";
	}
	print F $_;
    }
}

#------------------------------------------------------------------------------

sub addUser($) {
    my ($o) = @_;
    my $p = $o->{prefix};

    my (%uids, %gids); 
    foreach (glob_("$p/home")) { my ($u, $g) = (stat($_))[4,5]; $uids{$u} = 1; $gids{$g} = 1; }

    my %done;
    my @l = grep {
	if (!$_->{name} || getpwnam($_->{name}) || $done{$_->{name}}) { 
	    0;
	} else {
	    $_->{home} ||= "/home/$_->{name}";

	    my $u = $_->{uid} || ($_->{oldu} = (stat("$p$_->{home}"))[4]);
	    my $g = $_->{gid} || ($_->{oldg} = (stat("$p$_->{home}"))[5]);
	    #- search for available uid above 501 else initscripts may fail to change language for KDE.
	    if (!$u || getpwuid($u)) { for ($u = 501; getpwuid($u) || $uids{$u}; $u++) {} }
	    if (!$g || getgrgid($g)) { for ($g = 501; getgrgid($g) || $gids{$g}; $g++) {} }

	    $_->{uid} = $u; $uids{$u} = 1;
	    $_->{gid} = $g; $gids{$g} = 1;
	    $_->{pw} ||= $_->{password} && any::crypt($_->{password}, $o->{authentication}{md5});
	    $_->{shell} ||= "/bin/bash";
	    $done{$_->{name}} = 1;
	}
    } @{$o->{users} || []};
    my @passwd = cat_("$p/etc/passwd");;

    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F join(':', @$_{@etc_pass_fields}), "\n" foreach @l;

    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$_->{name}:x:$_->{gid}:\n" foreach @l;

    foreach my $u (@l) {
	if (! -d "$p$u->{home}") {
	    my $mode = $o->{security} < 2 ? 0755 : 0750;
	    eval { commands::cp("-f", "$p/etc/skel", "$p$u->{home}") };
	    if ($@) {
		log::l("copying of skel failed: $@"); mkdir("$p$u->{home}", $mode); 
	    } else {
		chmod $mode, "$p$u->{home}";
	    }
	}
	eval { commands::chown_("-r", "$u->{uid}.$u->{gid}", "$p$u->{home}") }
	    if $u->{uid} != $u->{oldu} || $u->{gid} != $u->{oldg};
    }
    require any;
    any::addUsers($o->{prefix}, @l);
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
    foreach my $e (@{$o->{bootloader}{entries}}) {
	while (my $v = readlink "$o->{prefix}/$e->{kernel_or_dev}") {
	    $v = "/boot/$v" if $v !~ m|^/|;
	    log::l("testing for presence of file $o->{prefix}$v");
	    -e "$o->{prefix}$v" or last;
	    log::l("renaming /boot/$e->{kernel_or_dev} entry by $v");
	    $e->{kernel_or_dev} = $v;
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
	require bootloader;
	#- propose the default fb mode for kernel fb, if aurora is installed too.
        bootloader::suggest($o->{prefix}, $o->{bootloader}, $o->{hds}, $o->{fstab}, install_any::kernelVersion($o),
			    pkgs::packageFlagInstalled(pkgs::packageByName($o->{packages}, 'Aurora') || {}) && 785);
	if ($o->{miscellaneous}{profiles}) {
	    my $e = bootloader::get_label("linux", $o->{bootloader});
	    push @{$o->{bootloader}{entries}}, { %$e, label => "office", append => "$e->{append} prof=Office" };
	    $e->{append} .= " prof=Home";
	}
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
    if (!-e "$o->{prefix}/usr/X11R6/lib/X11/xkb/symbols/$xkb" && (my $f = keyboard::xmodmap_file($o->{keyboard}))) {
	commands::cp("-f", $f, "$o->{prefix}/etc/X11/xinit/Xmodmap");	
	$xkb = '';
    }
    $o->{X}{keyboard}{xkb_keymap} = $xkb;
    $o->{X}{mouse} = $o->{mouse};
    $o->{X}{wacom} = $o->{wacom};

    require Xconfig;
    Xconfig::getinfoFromDDC($o->{X});

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
      Xconfigurator::main($o->{prefix}, $o->{X}, class_discard->new, $o->{allowFB}, bool($o->{pcmcia}), sub {
         $o->pkg_install("XFree86-$_[0]");
      });
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
    $o->{miscellaneous}{CLEAN_TMP} ||= $s{CLEAN_TMP} if exists $s{CLEAN_TMP};
    $o->{security} ||= $s{SECURITY} if exists $s{SECURITY};

    $ENV{SECURE_LEVEL} = $o->{security};
    add2hash_ $o, { useSupermount => $o->{security} < 4 && arch() !~ /sparc/ && $o->{installClass} !~ /corporate|server/ };

    cat_("/proc/cmdline") =~ /.mem=(\S+)/; #- if /^mem/, it means that's the value grub gave
    add2hash_($o->{miscellaneous} ||= {}, { numlock => !$o->{pcmcia}, $1 ? (memsize => $1) : () });
}
sub miscellaneous {
    my ($o) = @_;

    local $_ = $o->{bootloader}{perImageAppend};
    if (my $ramsize = $o->{miscellaneous}{memsize} and !/mem=/) {
	$_ .= " mem=$ramsize";
    }
    if (my @l = detect_devices::getIDEBurners() and !/ide-scsi/) {
	$_ .= " " . join(" ", (map { "$_=ide-scsi" } @l), 
			 map { "$_->{device}=ide-floppy" } detect_devices::ide_zips());
    }
    if (my $m = detect_devices::hasUltra66()) {
	$_ .= " $m" if !/ide.=/;
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
sub exitInstall { install_any::unlockCdrom }

#------------------------------------------------------------------------------
sub hasNetwork {
    my ($o) = @_;

    $o->{intf} && $o->{netc}{NETWORKING} ne 'false' || $o->{netcnx}{modem};
}

#------------------------------------------------------------------------------
sub upNetwork {
    my ($o, $pppAvoided) = @_;

    foreach (qw(resolv.conf protocols services)) {
	symlinkf("$o->{prefix}/etc/$_", "/etc/$_");
    }

    modules::write_conf($o->{prefix});
    if ($o->{intf} && $o->{netc}{NETWORKING} ne 'false') {
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
    if (!$pppOnly && $o->{intf} && $o->{netc}{NETWORKING} ne 'false') {
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
