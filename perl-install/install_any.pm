package install_any; # $Id$

use diagnostics;
use strict;

use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @needToCopy @needToCopyIfRequiresSatisfied $boot_medium @advertising_images);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(getNextStep spawnShell addToBeDone) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-######################################################################################
#- misc imports
#-######################################################################################
use MDK::Common::System;
use common;
use run_program;
use partition_table qw(:types);
use partition_table_raw;
use devices;
use fsedit;
use modules;
use detect_devices;
use lang;
use any;
use log;
use fs;

#- package that have to be copied for proper installation (just to avoid changing cdrom)
#- here XFree86 is copied entirey if not already installed, maybe better to copy only server.
#- considered obsoletes :
#- XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach8 XFree86-Mono XFree86-P9000 
#- XFree86-W32 XFree86-I128 XFree86-VGA16 XFree86-3DLabs 
@needToCopy = qw(
XFree86-Mach64 XFree86-S3 XFree86-S3V XFree86-SVGA 
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-FBDev XFree86-server
XFree86 XFree86-glide-module Device3Dfx Glide_V3-DRI Glide_V5 Mesa
dhcpcd pump dhcpxd dhcp-client isdn-light isdn4net isdn4k-utils dev pptp-adsl rp-pppoe ppp ypbind
autologin
foomatic printer-utils printer-testpages gimpprint rlpr samba-client ncpfs nc
cups xpp qtcups kups cups-drivers lpr LPRng pdq ImageMagick
);
#- package that have to be copied only if all their requires are satisfied.
@needToCopyIfRequiresSatisfied = qw(
Mesa-common
);

#- boot medium (the first medium to take into account).
$boot_medium = 1;

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $current_medium = $boot_medium;
my $asked_medium = $boot_medium;
my $cdrom = undef;
sub useMedium($) {
    #- before ejecting the first CD, there are some files to copy!
    #- does nothing if the function has already been called.
    $_[0] > 1 and $::o->{method} eq 'cdrom' and setup_postinstall_rpms($::o->{prefix}, $::o->{packages});

    $asked_medium eq $_[0] or log::l("selecting new medium '$_[0]'");
    $asked_medium = $_[0];
}
sub changeMedium($$) {
    my ($method, $medium) = @_;
    log::l("change to medium $medium for method $method (refused by default)");
    0;
}
sub relGetFile($) {
    local $_ = $_[0];
    m|\.rpm$| ? "$::o->{packages}{mediums}{$asked_medium}{rpmsdir}/$_" : $_;
}
sub askChangeMedium($$) {
    my ($method, $medium) = @_;
    my $allow;
    do {
	eval { $allow = changeMedium($method, $medium) };
    } while ($@); #- really it is not allowed to die in changeMedium!!! or install will cores with rpmlib!!!
    log::l($allow ? "accepting medium $medium" : "refusing medium $medium");
    $allow;
}
sub errorOpeningFile($) {
    my ($file) = @_;
    $file eq 'XXX' and return; #- special case to force closing file after rpmlib transaction.
    $current_medium eq $asked_medium and log::l("errorOpeningFile $file"), return; #- nothing to do in such case.
    $::o->{packages}{mediums}{$asked_medium}{selected} or return; #- not selected means no need for worying about.

    my $max = 32; #- always refuse after $max tries.
    if ($::o->{method} eq "cdrom") {
	cat_("/proc/mounts") =~ m,(/(?:dev|tmp)/\S+)\s+(?:/mnt/cdrom|/tmp/image), and $cdrom = $1;
	return unless $cdrom;
	ejectCdrom($cdrom);
	while ($max > 0 && askChangeMedium($::o->{method}, $asked_medium)) {
	    $current_medium = $asked_medium;
	    eval { fs::mount($cdrom, "/tmp/image", "iso9660", 'readonly') };
	    my $getFile = getFile($file); 
	    $getFile && @advertising_images and copy_advertising($::o);
	    $getFile and return $getFile;
	    $current_medium = 'unknown'; #- don't know what CD is inserted now.
	    ejectCdrom($cdrom);
	    --$max;
	}
    } else {
	while ($max > 0 && askChangeMedium($::o->{method}, $asked_medium)) {
	    $current_medium = $asked_medium;
	    my $getFile = getFile($file); $getFile and return $getFile;
	    $current_medium = 'unknown'; #- don't know what CD image has been copied.
	    --$max;
	}
    }

    #- keep in mind the asked medium has been refused on this way.
    #- this means it is no more selected.
    $::o->{packages}{mediums}{$asked_medium}{selected} = undef;

    #- on cancel, we can expect the current medium to be undefined too,
    #- this enable remounting if selecting a package back.
    $current_medium = 'unknown';

    return;
}
sub getFile {
    my ($f, $method) = @_;
    log::l("getFile $f:$method");
    my $rel = relGetFile($f);
    do {
	if ($method =~ /crypto/i) {
	    require crypto;
	    crypto::getFile($f);
	} elsif ($::o->{method} eq "ftp") {
	    require ftp;
	    ftp::getFile($rel);
	} elsif ($::o->{method} eq "http") {
	    require http;
	    http::getFile($rel);
	} else {
	    #- try to open the file, but examine if it is present in the repository, this allow
	    #- handling changing a media when some of the file on the first CD has been copied
	    #- to other to avoid media change...
	    my $f2 = "$postinstall_rpms/$f";
	    $f2 = "/tmp/image/$rel" unless $postinstall_rpms && -e $f2;
	    open GETFILE, $f2 and *GETFILE;
	}
    } || errorOpeningFile($f);
}
sub getAndSaveFile {
    my ($file, $local) = @_ == 1 ? ("Mandrake/mdkinst$_[0]", $_[0]) : @_;
    local *F; open F, ">$local" or return;
    local $/ = \ (16 * 1024);
    my $f = ref($file) ? $file : getFile($file) or return;
    local $_;
    while (<$f>) { syswrite F, $_ }
    1;
}


#-######################################################################################
#- Post installation RPMS from cdrom only, functions
#-######################################################################################
sub setup_postinstall_rpms($$) {
    my ($prefix, $packages) = @_;

    $postinstall_rpms and return;
    $postinstall_rpms = "$prefix/usr/postinstall-rpm";

    require pkgs;

    log::l("postinstall rpms directory set to $postinstall_rpms");
    clean_postinstall_rpms(); #- make sure in case of previous upgrade problem.
    mkdir_p($postinstall_rpms);

    #- compute closure of unselected package that may be copied,
    #- don't complain if package does not exists as it may happen
    #- for the various architecture taken into account (X servers).
    my %toCopy;
    foreach (@needToCopy) {
	my $pkg = pkgs::packageByName($packages, $_);
	pkgs::selectPackage($packages, $pkg, 0, \%toCopy) if $pkg;
    }
    @toCopy{@needToCopyIfRequiresSatisfied} = ();

    my @toCopy = map { pkgs::packageByName($packages, $_) } keys %toCopy;

    #- extract headers of package, this is necessary for getting
    #- the complete filename of each package.
    #- copy the package files in the postinstall RPMS directory.
    #- last arg is default medium '' known as the CD#1.
    pkgs::extractHeaders($prefix, \@toCopy, $packages->{mediums}{$boot_medium});
    cp_af((map { "/tmp/image/" . relGetFile(pkgs::packageFile($_)) } @toCopy), $postinstall_rpms);

    log::l("copying Auto Install Floppy");
    getAndSaveInstallFloppy($::o, "$postinstall_rpms/auto_install.img");
}

sub clean_postinstall_rpms() {
    $postinstall_rpms and -d $postinstall_rpms and rm_rf($postinstall_rpms);
}


#-######################################################################################
#- Specific Hardware to take into account and associated rpms to install
#-######################################################################################
sub allowNVIDIA_rpms {
    my ($packages) = @_;
    require pkgs;
    if (pkgs::packageByName($packages, "NVIDIA_GLX")) {
	#- at this point, we can allow using NVIDIA 3D acceleration packages.
	my @rpms;
	foreach (qw(kernel kernel-smp kernel-entreprise kernel22 kernel22-smp kernel22-secure)) {
	    my $p = pkgs::packageByName($packages, $_);
	    pkgs::packageSelectedOrInstalled($p) or next;
	    my $name = "NVIDIA_kernel-" . pkgs::packageVersion($p) . "-" . pkgs::packageRelease($p) . (/(-.*)/ && $1);
	    pkgs::packageByName($packages, $name) or return;
	    push @rpms, $name;
	}
	@rpms > 0 or return;
	return [ @rpms, "NVIDIA_GLX" ];
    }
}

#-######################################################################################
#- Functions
#-######################################################################################
sub kernelVersion {
    my ($o) = @_;
    require pkgs;
    my $p = pkgs::packageByName($o->{packages}, "kernel");
    $p  ||= pkgs::packageByName($o->{packages}, "kernel22");
    $p or die "I couldn't find the kernel package!";
    pkgs::packageVersion($p) . "-" . pkgs::packageRelease($p);
}


sub getNextStep {
    my ($s) = $::o->{steps}{first};
    $s = $::o->{steps}{$s}{next} while $::o->{steps}{$s}{done} || !$::o->{steps}{$s}{reachable};
    $s;
}

sub spawnShell {
    return if $::o->{localInstall} || $::testing;

    -x "/bin/sh" or die "cannot open shell - /bin/sh doesn't exist";

    fork and return;

    $ENV{DISPLAY} ||= ":0"; #- why not :pp

    local *F;
    sysopen F, "/dev/tty2", 2 or die "cannot open /dev/tty2 -- no shell will be provided";

    open STDIN, "<&F" or die '';
    open STDOUT, ">&F" or die '';
    open STDERR, ">&F" or die '';
    close F;

    print any::drakx_version(), "\n";

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    my $busybox = "/usr/bin/busybox";
    exec {-e $busybox ? $busybox : "/bin/sh"} "/bin/sh" or log::l("exec of /bin/sh failed: $!");
}

sub fsck_option {
    my ($o) = @_;
    my $y = $o->{security} < 3 && !$::expert && "-y ";
    substInFile { s/^(\s*fsckoptions="?)(-y )?/$1$y/ } "$o->{prefix}/etc/rc.d/rc.sysinit"; #- " help po, DONT REMOVE
}

sub getAvailableSpace {
    my ($o) = @_;

    #- make sure of this place to be available for installation, this could help a lot.
    #- currently doing a very small install use 36Mb of postinstall-rpm, but installing
    #- these packages may eat up to 90Mb (of course not all the server may be installed!).
    #- 65mb may be a good choice to avoid almost all problem of insuficient space left...
    my $minAvailableSize = 65 * sqr(1024);

    my $n = !$::testing && getAvailableSpace_mounted($o->{prefix}) || 
            getAvailableSpace_raw($o->{fstab}) * 512 / 1.07;
    $n - max(0.1 * $n, $minAvailableSize);
}

sub getAvailableSpace_mounted {
    my ($prefix) = @_;
    my $dir = -d "$prefix/usr" ? "$prefix/usr" : "$prefix";
    my (undef, $free) = MDK::Common::System::df($dir) or return;
    log::l("getAvailableSpace_mounted $free KB");
    $free * 1024 || 1;
}
sub getAvailableSpace_raw {
    my ($fstab) = @_;

    do { $_->{mntpoint} eq '/usr' and return $_->{size} } foreach @$fstab;
    do { $_->{mntpoint} eq '/'    and return $_->{size} } foreach @$fstab;

    if ($::testing) {
	my $nb = 450;
	log::l("taking ${nb}MB for testing");
	return $nb << 11;
    }
    die "missing root partition";
}

sub preConfigureTimezone {
    my ($o) = @_;
    require timezone;
   
    #- can't be done in install cuz' timeconfig %post creates funny things
    add2hash($o->{timezone}, { timezone::read($o->{prefix}) }) if $o->{isUpgrade};

    $o->{timezone}{timezone} ||= timezone::bestTimezone(lang::lang2text($o->{lang}));

    my $utc = $::expert && !grep { isFat($_) || isNT($_) } @{$o->{fstab}};
    my $ntp = timezone::ntp_server($o->{prefix});
    add2hash_($o->{timezone}, { UTC => $utc, ntp => $ntp });
}

sub setPackages {
    my ($o) = @_;

    require pkgs;
    if (!$o->{packages} || is_empty_hash_ref($o->{packages}{names})) {
	$o->{packages} = pkgs::psUsingHdlists($o->{prefix}, $o->{method});

	push @{$o->{default_packages}}, "nfs-utils-clients" if $o->{method} eq "nfs";
	push @{$o->{default_packages}}, "numlock" if $o->{miscellaneous}{numlock};
	push @{$o->{default_packages}}, "kernel-enterprise" if !$::oem && (availableRamMB() > 800) && (arch() !~ /ia64/);
	push @{$o->{default_packages}}, "kernel22" if !$::oem && c::kernel_version() =~ /^\Q2.2/;
	push @{$o->{default_packages}}, "kernel-smp" if detect_devices::hasSMP();
	push @{$o->{default_packages}}, "kernel-pcmcia-cs" if $o->{pcmcia};
	push @{$o->{default_packages}}, "raidtools" if !is_empty_array_ref($o->{all_hds}{raids});
	push @{$o->{default_packages}}, "lvm" if !is_empty_array_ref($o->{all_hds}{lvms});
	push @{$o->{default_packages}}, "usbd", "hotplug" if modules::get_alias("usb-interface");
	push @{$o->{default_packages}}, "reiserfsprogs" if grep { isThisFs("reiserfs", $_) } @{$o->{fstab}};
	push @{$o->{default_packages}}, "xfsprogs" if grep { isThisFs("xfs", $_) } @{$o->{fstab}};
	push @{$o->{default_packages}}, "jfsprogs" if grep { isThisFs("jfs", $_) } @{$o->{fstab}};
	push @{$o->{default_packages}}, "alsa", "alsa-utils" if modules::get_alias("sound-slot-0") =~ /^snd-card-/;
	push @{$o->{default_packages}}, "imwheel" if $o->{mouse}{nbuttons} > 3;

	pkgs::getDeps($o->{prefix}, $o->{packages});
	pkgs::selectPackage($o->{packages},
			    pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	#- must be done after selecting base packages (to save memory)
	pkgs::getProvides($o->{packages});

	#- must be done after getProvides
	pkgs::read_rpmsrate($o->{packages}, getFile("Mandrake/base/rpmsrate"));
	($o->{compssUsers}, $o->{compssUsersSorted}) = pkgs::readCompssUsers($o->{meta_class});

	if ($::auto_install && $o->{compssUsersChoice}{ALL}) {
	    $o->{compssUsersChoice}{$_} = 1 foreach map { @{$o->{compssUsers}{$_}{flags}} } @{$o->{compssUsersSorted}};
	}
	if (!$o->{compssUsersChoice} && !$o->{isUpgrade}) {
	    #- by default, choose:
	    $o->{compssUsersChoice}{$_} = 1 foreach 'GNOME', 'KDE', 'CONFIG', 'X';
	    $o->{compssUsersChoice}{$_} = 1 
	      foreach map { @{$o->{compssUsers}{$_}{flags}} } 'Workstation|Office Workstation', 'Workstation|Internet station';
	}
	$o->{compssUsersChoice}{uc($_)} = 1 foreach grep { modules::get_that_type($_) } ('tv', 'scanner', 'photo', 'sound');
	$o->{compssUsersChoice}{uc($_)} = 1 foreach map { $_->{driver} =~ /Flag:(.*)/ } detect_devices::probeall();
	$o->{compssUsersChoice}{SYSTEM} = 1;
	$o->{compssUsersChoice}{BURNER} = 1 if detect_devices::burners();
	$o->{compssUsersChoice}{DVD} = 1 if detect_devices::dvdroms();
	$o->{compssUsersChoice}{PCMCIA} = 1 if detect_devices::hasPCMCIA();
	$o->{compssUsersChoice}{HIGH_SECURITY} = 1 if $o->{security} > 3;
	$o->{compssUsersChoice}{'3D'} = 1 if 
	    detect_devices::matching_desc('Matrox.* G[245][05]0') ||
	    detect_devices::matching_desc('Riva.*128') ||
	    detect_devices::matching_desc('Rage X[CL]') ||
	    detect_devices::matching_desc('Rage Mobility [PL]') ||
	    detect_devices::matching_desc('3D Rage (?:LT|Pro)') ||
	    detect_devices::matching_desc('Voodoo [35]') ||
	    detect_devices::matching_desc('Voodoo Banshee') ||
	    detect_devices::matching_desc('8281[05].* CGC') ||
	    detect_devices::matching_desc('Rage 128') ||
	    detect_devices::matching_desc('Radeon ') ||
	    detect_devices::matching_desc('[nN]Vidia.*T[nN]T2') || #- TNT2 cards
	    detect_devices::matching_desc('[nN]Vidia.*NV[56]') ||
	    detect_devices::matching_desc('[nN]Vidia.*Vanta') ||
	    detect_devices::matching_desc('[nN]Vidia.*GeForce') || #- GeForce cards
	    detect_devices::matching_desc('[nN]Vidia.*NV1[15]') ||
	    detect_devices::matching_desc('[nN]Vidia.*Quadro');


	foreach (map { substr($_, 0, 2) } lang::langs($o->{langs})) {
	    pkgs::packageByName($o->{packages}, "locales-$_") or next;
	    push @{$o->{default_packages}}, "locales-$_";
	    $o->{compssUsersChoice}{qq(LOCALES"$_")} = 1; #- mainly for zh in case of zh_TW.Big5
	}
	foreach (lang::langsLANGUAGE($o->{langs})) {
	    $o->{compssUsersChoice}{qq(LOCALES"$_")} = 1;
	}
	$o->{compssUsersChoice}{'CHARSET"' . lang::lang2charset($o->{lang}) . '"'} = 1;
    } else {
	#- this has to be done to make sure necessary files for urpmi are
	#- present.
	pkgs::psUpdateHdlistsDeps($o->{prefix}, $o->{method});
    }
}

sub unselectMostPackages {
    my ($o) = @_;
    pkgs::unselectAllPackages($o->{packages});
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};
}

sub warnAboutNaughtyServers {
    my ($o) = @_;
    my @naughtyServers = pkgs::naughtyServers($o->{packages}) or return 1;
    if (!$o->ask_yesorno('', 
formatAlaTeX(_("You have selected the following server(s): %s


These servers are activated by default. They don't have any known security
issues, but some new could be found. In that case, you must make sure to upgrade
as soon as possible.


Do you really want to install these servers?
", join(", ", @naughtyServers))), 1)) {
	pkgs::unselectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_)) foreach @naughtyServers;
    }
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub setAuthentication {
    my ($o) = @_;
    my ($shadow, $md5, $ldap, $nis) = @{$o->{authentication} || {}}{qw(shadow md5 LDAP NIS)};
    my $p = $o->{prefix};
    #- obsoleted always enabled (in /etc/pam.d/system-auth furthermore) #any::enableMD5Shadow($p, $shadow, $md5);
    any::enableShadow($p) if $shadow;
    if ($ldap) {
	$o->pkg_install(qw(chkauth openldap-clients nss_ldap pam_ldap));
	run_program::rooted($o->{prefix}, "/usr/sbin/chkauth", "ldap", "-D", $o->{netc}{LDAPDOMAIN}, "-s", $ldap);
    } elsif ($nis) {
	#$o->pkg_install(qw(chkauth ypbind yp-tools net-tools));
	#run_program::rooted($o->{prefix}, "/usr/sbin/chkauth", "yp", $domain, "-s", $nis);
	$o->pkg_install("ypbind");
	my $domain = $o->{netc}{NISDOMAIN};
	$domain || $nis ne "broadcast" or die _("Can't use broadcast with no NIS domain");
	my $t = $domain ? "domain $domain" . ($nis ne "broadcast" && " server")
	                : "ypserver";
	substInFile {
	    $_ = "#~$_" unless /^#/;
	    $_ .= "$t $nis\n" if eof;
	} "$p/etc/yp.conf";
	require network;
	network::write_conf("$p/etc/sysconfig/network", $o->{netc});
    }
}

sub killCardServices {
    my $pid = chomp_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub unlockCdrom(;$) {
    my ($cdrom) = @_;
    $cdrom or cat_("/proc/mounts") =~ m,(/(?:dev|tmp)/\S+)\s+(?:/mnt/cdrom|/tmp/image), and $cdrom = $1;
    eval { $cdrom and ioctl detect_devices::tryOpen($1), c::CDROM_LOCKDOOR(), 0 };
}
sub ejectCdrom(;$) {
    my ($cdrom) = @_;
    getFile("XXX"); #- close still opened filehandle
    $cdrom ||= $1 if cat_("/proc/mounts") =~ m,(/(?:dev|tmp)/\S+)\s+(?:/mnt/cdrom|/tmp/image),;
    if ($cdrom) {
	#- umount BEFORE opening the cdrom device otherwise the umount will
	#- D state if the cdrom is already removed
	eval { fs::umount("/tmp/image") };
	eval { ioctl detect_devices::tryOpen($cdrom), c::CDROMEJECT(), 1 };	
    }
}

sub setupFB {
    my ($o, $vga) = @_;

    $vga ||= 785; #- assume at least 640x480x16.

    require bootloader;
    #- update bootloader entries with vga, all kernel are now framebuffer.
    foreach (qw(vmlinuz vmlinuz-secure vmlinuz-smp vmlinuz-hack)) {
	if (my $e = bootloader::get("/boot/$_", $o->{bootloader})) {
	    $e->{vga} = $vga;
	}
    }
    bootloader::install($o->{prefix}, $o->{bootloader}, $o->{fstab}, $o->{all_hds}{hds});
    1;
}

sub hdInstallPath() {
    my $tail = first(readlink("/tmp/image") =~ m|^/tmp/hdimage/(.*)|);
    my $head = first(readlink("/tmp/hdimage") =~ m|$::o->{prefix}(.*)|);
    $tail && ($head ? "$head/$tail" : "/mnt/hd/$tail");
}

sub install_urpmi {
    my ($prefix, $method, $mediums) = @_;

    #- rare case where urpmi cannot be installed (no hd install path).
    $method eq 'disk' && !hdInstallPath() and return;

    my @cfg = map_index {
	my $name = $_->{fakemedium};

	#- build synthesis file at install, this will improve performance greatly.
	run_program::rooted($prefix, "parsehdlist", ">", "/var/lib/urpmi/synthesis.hdlist.$name",
			    "--compact", "--provides", "--requires", "/var/lib/urpmi/hdlist.$name.cz");
	run_program::rooted($prefix, "gzip", "-S", ".cz", "/var/lib/urpmi/synthesis.hdlist.$name");
	#- safe guard correct generation of synthesis file.
	-s "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz" > 24 or unlink "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";

	local *LIST;
	my $mask = umask 077;
	open LIST, ">$prefix/var/lib/urpmi/list.$name" or log::l("failed to write list.$name");
	umask $mask;

	my $dir = ${{ nfs => "file://mnt/nfs", 
                      disk => "file:/" . hdInstallPath(),
		      ftp => $ENV{URLPREFIX},
		      http => $ENV{URLPREFIX},
		      cdrom => "removable_cdrom://mnt/cdrom" }}{$method} . "/$_->{rpmsdir}";

	local *FILES; open FILES, "$ENV{LD_LOADER} parsehdlist /tmp/$_->{hdlist} |";
	print LIST "$dir/$_\n" foreach chomp_(<FILES>);
	close FILES or log::l("parsehdlist failed"), return;
	close LIST;

	my ($qname, $qdir) = ($name, $dir);
	$qname =~ s/(\s)/\\$1/g; $qdir =~ s/(\s)/\\$1/g;

	#- output new urpmi.cfg format here.
	"$qname " . ($dir !~ /^(ftp|http)/ && $qdir) . " {
  hdlist: hdlist.$name.cz
  with_hdlist: ../base/$_->{hdlist}
  list: list.$name" . ($dir =~ /removable_([^\s:_]*)/ && "
  removable: /dev/$1") . "
}

";
    } values %$mediums;
    eval { output "$prefix/etc/urpmi/urpmi.cfg", @cfg };
}


#-###############################################################################
#- kde stuff
#-###############################################################################
sub kderc_largedisplay {
    my ($prefix) = @_;

    update_gnomekderc($_, 'KDE', 
		     Contrast => 7,
		     kfmIconStyle => "Large",
		     kpanelIconStyle => "Normal", #- to change to Large when icons looks better
		     KDEIconStyle => "Large") foreach list_skels($prefix, '.kderc');

    substInFile {
	s/^(GridWidth)=85/$1=100/;
	s/^(GridHeight)=70/$1=75/;
    } $_ foreach list_skels($prefix, '.kde/share/config/kfmrc');
}

sub kdeicons_postinstall {
    my ($prefix) = @_;

    #- parse etc/fstab file to search for dos/win, floppy, zip, cdroms icons.
    #- handle both supermount and fsdev usage.
    my %l = (
	     'cdrom' => [ 'cdrom', 'Cd-Rom' ],
	     'zip' => [ 'zip', 'Zip' ],
	     'floppy-ls' => [ 'floppy', 'LS-120' ],
	     'floppy' => [ 'floppy', 'Floppy' ],
    );
    foreach (fs::read_fstab($prefix, "/etc/fstab")) {

	my ($name_, $nb) = $_->{mntpoint} =~ m|.*/(\S+?)(\d*)$/|;
	my ($name, $text) = @{$l{$name_} || []};

	my $f = ${{
	    supermount => sub { $name .= '.fsdev' if $name },
	    vfat => sub { $name = 'Dos_'; $text = $name_ },
	}}{$_->{type}};
	&$f if $f;

	template2userfile($prefix, 
			  "$ENV{SHARE_PATH}/$name.kdelnk.in",
			  "Desktop/$text" .  ($nb && " $nb"). ".kdelnk",
			  1, %$_) if $name;
    }

    # rename the .kdelnk to the name found in the .kdelnk as kde doesn't use it
    # for displaying
    foreach my $dir (grep { -d $_ } list_skels($prefix, 'Desktop')) {
	foreach (grep { /\.kdelnk$/ } all($dir)) {
	    cat_("$dir/$_") =~ /^Name\[\Q$ENV{LANG}\E\]=(.{2,14})$/m
	      and rename "$dir/$_", "$dir/$1.kdelnk";
	}
    }
}

sub kdemove_desktop_file {
    my ($prefix) = @_;
    my @toMove = qw(doc.kdelnk news.kdelnk updates.kdelnk home.kdelnk printer.kdelnk floppy.kdelnk cdrom.kdelnk FLOPPY.kdelnk CDROM.kdelnk);

    #- remove any existing save in Trash of each user and
    #- move appropriate file there after an upgrade.
    foreach my $dir (grep { -d $_ } list_skels($prefix, 'Desktop')) {
	renamef("$dir/$_", "$dir/Trash/$_") 
	  foreach grep { -e "$dir/$_" } @toMove, grep { /\.rpmorig$/ } all($dir)
    }
}


#-###############################################################################
#- auto_install stuff
#-###############################################################################
sub auto_inst_file() { ($::g_auto_install ? "/tmp" : "$::o->{prefix}/root") . "/auto_inst.cfg.pl" }

sub report_bug {
    my ($prefix) = @_;
    any::report_bug($prefix, 'auto_inst' => g_auto_install());
}

sub g_auto_install {
    my ($replay) = @_;
    my $o = {};

    require pkgs;
    $o->{default_packages} = pkgs::selected_leaves($::o->{packages});

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang authentication mouse wacom netc timezone superuser intf keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security netcnx useSupermount autoExitInstall mkbootdisk); #- TODO modules bootloader 

    if (my $printer = $::o->{printer}) {
	$o->{printer}{$_} = $::o->{printer}{$_} foreach qw(SPOOLER DEFAULT BROWSEPOLLADDR BROWSEPOLLPORT MANUALCUPSCONFIG);
	$o->{printer}{configured} = {};
	foreach my $queue (keys %{$::o->{printer}{configured}}) {
	    my $val = $::o->{printer}{configured}{$queue}{queuedata};
	    exists $val->{$_} and $o->{printer}{configured}{$queue}{queuedata}{$_} = $val->{$_} foreach keys %{$val || {}};
	}
    }

    if (my $card = $::o->{X}{card}) {
	$o->{X}{$_} = $::o->{X}{$_} foreach qw(default_depth resolution_wanted);
	if ($o->{X}{default_depth} and my $depth = $card->{depth}{$o->{X}{default_depth}}) {
	    $depth ||= [];
	    $o->{X}{resolution_wanted} ||= join "x", @{$depth->[0]} unless is_empty_array_ref($depth->[0]);
	    $o->{X}{monitor} = $::o->{X}{monitor} if $::o->{X}{monitor}{manual};
	}
    }

    local $o->{partitioning}{auto_allocate} = !$replay;
    local $o->{autoExitInstall} = !$replay;

    #- deep copy because we're modifying it below
    $o->{users} = [ @{$o->{users} || []} ];

    $_ = { %{$_ || {}} }, delete @$_{qw(oldu oldg password password2)} foreach $o->{superuser}, @{$o->{users} || []};
    
    require Data::Dumper;
    my $str = join('', 
"#!/usr/bin/perl -cw
#
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
", 
	 Data::Dumper->Dump([$o], ['$o']), if_($replay, 
qq(\npackage install_steps_auto_install;), q(
$graphical = 1;
push @graphical_steps, 'doPartitionDisks', 'formatPartitions';
)), "\0");
    $str =~ s/ {8}/\t/g; #- replace all 8 space char by only one tabulation, this reduces file size so much :-)
    $str;
}

sub getAndSaveInstallFloppy {
    my ($o, $where) = @_;
    if ($postinstall_rpms && -d $postinstall_rpms && -r "$postinstall_rpms/auto_install.img") {
	log::l("getAndSaveInstallFloppy: using file saved as $postinstall_rpms/auto_install.img");
	cp_af("$postinstall_rpms/auto_install.img", $where);
    } else {
	my $image = cat_("/proc/cmdline") =~ /pcmcia/ ? "pcmcia" :
	  ${{ disk => 'hd', cdrom => 'cdrom', ftp => 'network', nfs => 'network', http => 'network' }}{$o->{method}};
	$image .= arch() =~ /sparc64/ && "64"; #- for sparc64 there are a specific set of image.
	getAndSaveFile("images/$image.img", $where) or log::l("failed to write Install Floppy ($image.img) to $where"), return;
    }
    1;
}

sub getAndSaveAutoInstallFloppy {
    my ($o, $replay, $where) = @_;

    eval { modules::load('loop') };

    if (arch() =~ /sparc/) {
	my $imagefile = "$o->{prefix}/tmp/autoinst.img";
	my $mountdir = "$o->{prefix}/tmp/mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $workdir = "$o->{prefix}/tmp/work"; -d $workdir or rmdir $workdir;

	getAndSaveInstallFloppy($o, $imagefile) or return;
        devices::make($_) foreach qw(/dev/loop6 /dev/ram);

        run_program::run("losetup", "/dev/loop6", $imagefile);
        fs::mount("/dev/loop6", $mountdir, "romfs", 'readonly');
        cp_af($mountdir, $workdir);
        fs::umount($mountdir);
        run_program::run("losetup", "-d", "/dev/loop6");

	substInFile { s/timeout.*//; s/^(\s*append\s*=\s*\".*)\"/$1 kickstart=floppy\"/ } "$workdir/silo.conf"; #" for po
#-TODO	output "$workdir/ks.cfg", generate_ks_cfg($o);
	output "$workdir/boot.msg", "\n7m",
"!! If you press enter, an auto-install is going to start.
    ALL data on this computer is going to be lost,
    including any Windows partitions !!
", "7m\n";

	local $o->{partitioning}{clearall} = 1;
	output("$workdir/auto_inst.cfg", g_auto_install());

        run_program::run("genromfs", "-d", $workdir, "-f", "/dev/ram", "-A", "2048,/..", "-a", "512", "-V", "DrakX autoinst");
        fs::mount("/dev/ram", $mountdir, 'romfs', 0);
        run_program::run("silo", "-r", $mountdir, "-F", "-i", "/fd.b", "-b", "/second.b", "-C", "/silo.conf");
        fs::umount($mountdir);
	require commands;
        commands::dd("if=/dev/ram", "of=$where", "bs=1440", "count=1024");

        rm_rf($workdir, $mountdir, $imagefile);
    } elsif (arch() =~ /ia64/) {
	#- nothing yet
    } else {
	my $imagefile = "$o->{prefix}/tmp/autoinst.img";
	my $mountdir = "$o->{prefix}/tmp/aif-mount"; -d $mountdir or mkdir $mountdir, 0755;

	my $param = 'kickstart=floppy ' . generate_automatic_stage1_params($o);

	getAndSaveInstallFloppy($o, $imagefile) or return;

	my $dev = devices::set_loop($imagefile) or log::l("couldn't set loopback device"), return;
        fs::mount($dev, $mountdir, 'vfat', 0);

	substInFile { 
	    s/timeout.*/$replay ? 'timeout 1' : ''/e;
	    s/^(\s*append)/$1 $param/ 
	} "$mountdir/syslinux.cfg";

	unlink "$mountdir/help.msg";
	output "$mountdir/boot.msg", "\n0c",
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost,
   including any Windows partitions !!
", "07\n" if !$replay;

	local $o->{partitioning}{clearall} = !$replay;
	output("$mountdir/auto_inst.cfg", g_auto_install($replay));

	fs::umount($mountdir);
	rmdir $mountdir;
	c::del_loop($dev);
	require commands;
	commands::dd("if=$imagefile", "of=$where", "bs=1440", "count=1024");
	unlink $imagefile;
    }
    1;
}


sub g_default_packages {
    my ($o, $quiet) = @_;

    my $floppy = detect_devices::floppy();

    while (1) {
	$o->ask_okcancel('', _("Insert a FAT formatted floppy in drive %s", $floppy), 1) or return;

	eval { fs::mount(devices::make($floppy), "/floppy", "vfat", 0) };
	last if !$@;
	$o->ask_warn('', _("This floppy is not FAT formatted"));
    }

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;
    output('/floppy/auto_inst.cfg', 
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n",
	   "# before testing.  To use it, boot with ``linux defcfg=floppy''\n",
	   $str, "\0");
    fs::umount("/floppy");

    $quiet or $o->ask_warn('', _("To use this saved packages selection, boot installation with ``linux defcfg=floppy''"));
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file;
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	unless ($::testing) {
	    fs::mount(devices::make(detect_devices::floppy()), "/mnt", (arch() =~ /sparc/ ? "romfs" : "vfat"), 'readonly');
	    $f = "/mnt/$f";
	}
	-e $f or $f .= '.pl';

	my $b = before_leaving {
	    fs::umount("/mnt") unless $::testing;
	    modules::unload($_) foreach qw(vfat fat);
	};
	$o = loadO($O, $f);
    } else {
	-e "$f.pl" and $f .= ".pl" unless -e $f;

	my $fh = -e $f ? do { local *F; open F, $f; *F } : getFile($f) or die _("Error reading file %s", $f);
	{
	    local $/ = "\0";
	    no strict;
	    eval <$fh>;
	    close $fh;
	    $@ and die;
	}
	add2hash_($o ||= {}, $O);
    }
    bless $o, ref $O;
}

sub generate_automatic_stage1_params {
    my ($o) = @_;

    my @ks = "method:$o->{method}";

    if ($o->{method} =~ /http/) {
	"$ENV{URLPREFIX}" =~ m|http://(.*)/(.*)| or die;
	push @ks, "server:$1", "directory:$2";
    } elsif ($o->{method} =~ /ftp/) {
	push @ks,  "server:$ENV{HOST}", "directory:$ENV{PREFIX}", "user:$ENV{LOGIN}", "pass:$ENV{PASSWORD}";
    } elsif ($o->{method} =~ /nfs/) {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/image nfs| or die;
	push @ks, "server:$1", "directory:$2";
    }

    my ($intf) = values %{$o->{intf}};
    if ($intf->{BOOTPROTO} =~ /dhcp/) {
	push @ks, "network:dhcp";
    } else {
	require network;
	push @ks, "network:static", "ip:$intf->{IPADDR}", "netmask:$intf->{NETMASK}", "gateway:$o->{netc}{GATEWAY}";
	my @dnss = network::dnsServers($o->{netc});
	push @ks, "dns:$dnss[0]" if @dnss;
    }
    "automatic=".join(',', @ks);
}

sub guess_mount_point {
    my ($part, $prefix, $user) = @_;

    my %l = (
	     '/'     => 'etc/fstab',
	     '/boot' => 'vmlinuz',
	     '/tmp'  => '.X11-unix',
	     '/usr'  => 'X11R6',
	     '/var'  => 'catman',
	    );

    my $handle = any::inspect($part, $prefix) or return;
    my $d = $handle->{dir};
    my ($mnt) = grep { -e "$d/$l{$_}" } keys %l;
    $mnt ||= (stat("$d/.bashrc"))[4] ? '/root' : '/home/user' . ++$$user if -e "$d/.bashrc";
    $mnt ||= (grep { -d $_ && (stat($_))[4] >= 500 && -e "$_/.bashrc" } glob_("$d")) ? '/home' : '';
    ($mnt, $handle);
}

sub suggest_mount_points {
    my ($fstab, $prefix, $uniq) = @_;

    my $user;
    foreach my $part (grep { isTrueFS($_) } @$fstab) {
	$part->{mntpoint} && !$part->{unsafeMntpoint} and next; #- if already found via an fstab

	my ($mnt, $handle) = guess_mount_point($part, $prefix, \$user) or next;

	next if $uniq && fsedit::mntpoint2part($mnt, $fstab);
	$part->{mntpoint} = $mnt; delete $part->{unsafeMntpoint};

	#- try to find other mount points via fstab
	fs::merge_info_from_fstab($fstab, $handle->{dir}, $uniq) if $mnt eq '/';
    }
    $_->{mntpoint} and log::l("suggest_mount_points: $_->{device} -> $_->{mntpoint}") foreach @$fstab;
}

#- mainly for finding the root partitions for upgrade
sub find_root_parts {
    my ($fstab, $prefix) = @_;
    log::l("find_root_parts");
    my $user;
    grep { 
	my ($mnt) = guess_mount_point($_, $prefix, \$user);
	$mnt eq '/';
    } @$fstab;
}
sub use_root_part {
    my ($fstab, $part, $prefix) = @_;
    {
	my $handle = any::inspect($part, $prefix) or die;
	fs::merge_info_from_fstab($fstab, $handle->{dir}, 'uniq');
    }
    map { $_->{mntpoint} = 'swap' } grep { isSwap($_) } @$fstab; #- use all available swap.
}

sub getHds {
    my ($o, $f_err) = @_;
    my $ok = 1;
    my $try_scsi = !$::expert;
    my $flags = $o->{partitioning};

    my @drives = detect_devices::hds();
#    add2hash_($o->{partitioning}, { readonly => 1 }) if partition_table_raw::typeOfMBR($drives[0]{device}) eq 'system_commander';

  getHds: 
    my $all_hds = catch_cdie { fsedit::hds(\@drives, $flags) }
      sub {
	  $ok = 0;
	  my $err = $@; $err =~ s/ at (.*?)$//;
	  log::l("error reading partition table: $err");
	  !$flags->{readonly} && $f_err and $f_err->($err);
      };
    my $hds = $all_hds->{hds};

    if (is_empty_array_ref($hds) && $try_scsi) {
	$try_scsi = 0;
	$o->setupSCSI; #- ask for an unautodetected scsi card
	goto getHds;
    }
    if (!$::testing) {
	@$hds = grep { partition_table_raw::test_for_bad_drives($_) } @$hds;
    }

    $ok = fsedit::verifyHds($hds, $flags->{readonly}, $ok)
        if !($flags->{clearall} || $flags->{clear});

    #- try to figure out if the same number of hds is available, use them if ok.
    $ok && $hds && @$hds > 0 && @{$o->{all_hds}{hds} || []} == @$hds and return $ok;

    fs::get_raw_hds('', $all_hds);
    fs::add2all_hds($all_hds, @{$o->{manualFstab}});

    $o->{all_hds} = $all_hds;
    $o->{fstab} = [ fsedit::get_all_fstab($all_hds) ];
    fs::merge_info_from_mtab($o->{fstab});

    my @win = grep { isFat($_) && isFat({ type => fsedit::typeOfPart($_->{device}) }) } @{$o->{fstab}};
    log::l("win parts: ", join ",", map { $_->{device} } @win) if @win;
    if (@win == 1) {
	#- Suggest /boot/efi on ia64.
	$win[0]{mntpoint} = arch() =~ /ia64/ ? "/boot/efi" : "/mnt/windows";
    } else {
	my %w; foreach (@win) {
	    my $v = $w{$_->{device_windobe}}++;
	    $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/win_" . lc($_->{device_windobe}) . ($v ? $v+1 : ''); #- lc cuz of StartOffice(!) cf dadou
	}
    }

    my @sunos = grep { isSunOS($_) && type2name($_->{type}) =~ /root/i } @{$o->{fstab}}; #- take only into account root partitions.
    if (@sunos) {
	my $v = '';
	map { $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/sunos" . ($v && ++$v) } @sunos;
    }
    #- a good job is to mount SunOS root partition, and to use mount point described here in /etc/vfstab.

    $ok;
}

sub log_sizes {
    my ($o) = @_;
    my @df = MDK::Common::System::df($o->{prefix});
    log::l(sprintf "Installed: %s(df), %s(rpm)",
	   formatXiB($df[0] - $df[1], 1024),
	   formatXiB(sum(`$ENV{LD_LOADER} rpm --root $o->{prefix}/ -qa --queryformat "%{size}\n"`))) if -x "$o->{prefix}/bin/rpm";
}

sub copy_advertising {
    my ($o) = @_;

    return if $::rootwidth < 800;

    my $f;
    my $source_dir = "Mandrake/share/advertising";
    foreach ("." . $o->{lang}, "." . substr($o->{lang},0,2), '') {
	$f = getFile("$source_dir$_/list") or next;
	$source_dir = "$source_dir$_";
    }
    if (my @files = <$f>) {
	my $dir = "$o->{prefix}/tmp/drakx-images";
	mkdir $dir;
	unlink glob_("$dir/*");
	foreach (@files) {
	    chomp;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	}
	@advertising_images = map { "$dir/$_" } @files;
    }
}
sub remove_advertising {
    my ($o) = @_;
    unlink @advertising_images;
    rmdir "$o->{prefix}/tmp/drakx-images";
    @advertising_images = ();
}

sub disable_user_view {
    my ($prefix) = @_;
    substInFile { s/^UserView=.*/UserView=true/ } "$prefix/usr/share/config/kdm/kdmrc";
    substInFile { s/^Browser=.*/Browser=0/ } "$prefix/etc/X11/gdm/gdm.conf";
}

sub write_fstab {
    my ($o) = @_;
    fs::write_fstab($o->{all_hds}, $o->{prefix}) if !$::live;
}

my @bigseldom_used_groups = (
  [ qw(pvcreate pvdisplay vgchange vgcreate vgdisplay vgextend vgremove vgscan lvcreate lvdisplay lvremove /lib/liblvm.so) ],
);

sub check_prog {
    my ($f) = @_;

    my @l = $f !~ m|^/| ?
        map { "$_/$f" } split(":", $ENV{PATH}) :
	$f;
    return if grep { -x $_ } @l;

    common::usingRamdisk() or log::l("ERROR: check_prog can't find the program $f and we're not using ramdisk"), return;

    my ($f_) = map { m|^/| ? $_ : "/usr/bin/$_" } $f;
    remove_bigseldom_used();
    foreach (@bigseldom_used_groups) {
	my (@l) = map { m|^/| ? $_ : "/usr/bin/$_" } @$_;
	if (member($f_, @l)) {
	    foreach (@l) {
		getAndSaveFile($_);
		chmod 0755, $_;
	    }
	    return;
	}
    }
    getAndSaveFile($f_);
    chmod 0755, $f_;
}

sub remove_unused {
    $::testing and return;
    if ($::o->isa('interactive_gtk')) {
	unlink glob_("/lib/lib$_*") foreach qw(slang newt);
	unlink "/usr/bin/perl-install/auto/Newt/Newt.so";
    } else {
	unlink glob_("/usr/X11R6/bin/XF*");
    }
}

sub remove_bigseldom_used {
    log::l("remove_bigseldom_used");
    $::testing and return;
    remove_unused();
    unlink glob_("/usr/share/gtk/themes/$_*") foreach qw(DarkMarble marble3d);
    unlink(m|^/| ? $_ : "/usr/bin/$_") foreach 
      ((map { @$_ } @bigseldom_used_groups),
       qw(mkreiserfs resize_reiserfs),
      );
}

################################################################################
package pkgs_interactive;
use run_program;
use common;
use pkgs;

sub install_steps::do_pkgs {
    my ($o) = @_;
    bless { o => $o }, 'pkgs_interactive';
}

sub install {
    my ($do, @l) = @_;
    $do->{o}->pkg_install(@l);
}

sub is_installed {
    my ($do, @l) = @_;
    foreach (@l) {
	my $p = pkgs::packageByName($do->{o}->{packages}, $_);
	$p && pkgs::packageFlagSelected($p) or return;
    }
    1;
}

sub remove {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}->{packages}, $_);
	pkgs::unselectPackage($do->{o}->{packages}, $p) if $p;
	$p;
    } @l;
    run_program::rooted($do->{o}->{prefix}, 'rpm', '-e', @l);
}

sub remove_nodeps {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}->{packages}, $_);
	pkgs::packageSetFlagSelected($p, 0) if $p;
	$p;
    } @l;
    run_program::rooted($do->{o}->{prefix}, 'rpm', '-e', '--nodeps', @l);
}
################################################################################

package install_any;

1;
