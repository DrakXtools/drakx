package install_any; # $Id$

use diagnostics;
use strict;

use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $boot_medium $current_medium $asked_medium @advertising_images);

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
use partition_table::raw;
use devices;
use fsedit;
use modules;
use detect_devices;
use lang;
use any;
use log;
use fs;

#- boot medium (the first medium to take into account).
$boot_medium = 1;
$current_medium = $boot_medium;
$asked_medium = $boot_medium;

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $cdrom;
sub useMedium($) {
    #- before ejecting the first CD, there are some files to copy!
    #- does nothing if the function has already been called.
    $_[0] > 1 and $::o->{method} eq 'cdrom' and setup_postinstall_rpms($::prefix, $::o->{packages});

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
    } while $@; #- really it is not allowed to die in changeMedium!!! or install will cores with rpmlib!!!
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
	if ($f =~ m|^http://|) {
	    require http;
	    http::getFile($f);
	} elsif ($method =~ /crypto|update/i) {
	    require crypto;
	    crypto::getFile($f);
	} elsif ($::o->{method} eq "ftp") {
	    require ftp;
	    ftp::getFile($rel);
	} elsif ($::o->{method} eq "http") {
	    require http;
	    http::getFile("$ENV{URLPREFIX}/$rel");
	} else {
	    #- try to open the file, but examine if it is present in the repository, this allow
	    #- handling changing a media when some of the file on the first CD has been copied
	    #- to other to avoid media change...
	    my $f2 = "$postinstall_rpms/$f";
	    $f2 = "/tmp/image/$rel" if !$postinstall_rpms || !-e $f2;
	    my $F; open $F, $f2 and $F;
	}
    } || errorOpeningFile($f);
}
sub getAndSaveFile {
    my ($file, $local) = @_ == 1 ? ("Mandrake/mdkinst$_[0]", $_[0]) : @_;
    local $/ = \ (16 * 1024);
    my $f = ref($file) ? $file : getFile($file) or return;
    open(my $F, ">$local") or return;
    local $_;
    while (<$f>) { syswrite $F, $_ }
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

    my %toCopy;
    #- compute closure of package that may be copied, use INSTALL category
    #- in rpmsrate.
    $packages->{rpmdb} ||= pkgs::rpmDbOpen($prefix);
    foreach (@{$packages->{needToCopy} || []}) {
	my $p = pkgs::packageByName($packages, $_) or next;
	pkgs::selectPackage($packages, $p, 0, \%toCopy);
    }
    delete $packages->{rpmdb};

    my @toCopy = grep { $_ && !$_->flag_selected } map { $packages->{depslist}[$_] } keys %toCopy;

    #- extract headers of package, this is necessary for getting
    #- the complete filename of each package.
    #- copy the package files in the postinstall RPMS directory.
    #- last arg is default medium '' known as the CD#1.
    #- cp_af doesn't handle correctly a missing file.
    eval { cp_af((grep { -r $_ } map { "/tmp/image/" . relGetFile($_->filename) } @toCopy), $postinstall_rpms) };

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
	foreach my $p (@{$packages->{depslist}}) {
	    my ($ext, $version, $release) = $p->name =~ /kernel[^-]*(-smp|-enterprise|-secure)?(?:-(\d.*?)\.(\d+mdk))?$/ or next;
	    $p->flag_available or next;
	    $version or ($version, $release) = ($p->version, $p->release);
	    my $name = "NVIDIA_kernel-$version-$release$ext";
	    pkgs::packageByName($packages, $name) or next;
	    push @rpms, $name;
	}
	@rpms > 0 or return;
	return [ @rpms, "NVIDIA_GLX" ];
    }
}

#-######################################################################################
#- Functions
#-######################################################################################
sub getNextStep {
    my ($s) = $::o->{steps}{first};
    $s = $::o->{steps}{$s}{next} while $::o->{steps}{$s}{done} || !$::o->{steps}{$s}{reachable};
    $s;
}

sub spawnShell {
    return if $::o->{localInstall} || $::testing;

    -x "/bin/sh" or die "cannot open shell - /bin/sh doesn't exist";

    fork() and return;

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
    exec { -e $busybox ? $busybox : "/bin/sh" } "/bin/sh" or log::l("exec of /bin/sh failed: $!");
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
    my $dir = -d "$prefix/usr" ? "$prefix/usr" : $prefix;
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
    add2hash($o->{timezone}, timezone::read()) if $o->{isUpgrade};

    $o->{timezone}{timezone} ||= timezone::bestTimezone(lang::lang2text($o->{lang}));

    my $utc = every { !isFat_or_NTFS($_) } @{$o->{fstab}};
    my $ntp = timezone::ntp_server($o->{prefix});
    add2hash_($o->{timezone}, { UTC => $utc, ntp => $ntp });
}

sub setPackages {
    my ($o, $rebuild_needed) = @_;

    require pkgs;
    if (!$o->{packages} || is_empty_array_ref($o->{packages}{depslist})) {
	$o->{packages} = pkgs::psUsingHdlists($o->{prefix}, $o->{method});

	#- open rpm db according to right mode needed.
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen($o->{prefix}, $rebuild_needed);

	pkgs::getDeps($o->{prefix}, $o->{packages});
	pkgs::selectPackage($o->{packages},
			    pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	#- always try to select basic kernel (else on upgrade, kernel will never be updated provided a kernel is already
	#- installed and provides what is necessary).
	pkgs::selectPackage($o->{packages},
			    pkgs::bestKernelPackage($o->{packages}) || die("missing kernel package"), 1);

	#- must be done after selecting base packages (to save memory)
	pkgs::getProvides($o->{packages});

	#- must be done after getProvides
	pkgs::read_rpmsrate($o->{packages}, getFile("Mandrake/base/rpmsrate"));
	($o->{compssUsers}, $o->{compssUsersSorted}) = pkgs::readCompssUsers($o->{meta_class});

	#- preselect default_packages and compssUsersChoices.
	setDefaultPackages($o);
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};
    } else {
	#- this has to be done to make sure necessary files for urpmi are
	#- present.
	pkgs::psUpdateHdlistsDeps($o->{prefix}, $o->{method}, $o->{packages});

	#- open rpm db (always without rebuilding db, it should be false at this point).
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen($o->{prefix});
    }
}

sub setDefaultPackages {
    my ($o, $clean) = @_;

    if ($clean) {
	delete $o->{$_} foreach qw(default_packages compssUsersChoice); #- clean modified variables.
    }

    push @{$o->{default_packages}}, "nfs-utils-clients" if $o->{method} eq "nfs";
    push @{$o->{default_packages}}, "numlock" if $o->{miscellaneous}{numlock};
    push @{$o->{default_packages}}, "kernel22" if !$::oem && c::kernel_version() =~ /^\Q2.2/;
    push @{$o->{default_packages}}, "raidtools" if !is_empty_array_ref($o->{all_hds}{raids});
    push @{$o->{default_packages}}, "lvm" if !is_empty_array_ref($o->{all_hds}{lvms});
    push @{$o->{default_packages}}, "alsa", "alsa-utils" if modules::get_alias("sound-slot-0") =~ /^snd-card-/;
    push @{$o->{default_packages}}, uniq(grep { $_ } map { fsedit::package_needed_for_partition_type($_) } @{$o->{fstab}});

    #- if no cleaning needed, populate by default, clean is used for second or more call to this function.
    unless ($clean) {
	if ($::auto_install && ($o->{compssUsersChoice} || {})->{ALL}) {
	    $o->{compssUsersChoice}{$_} = 1 foreach map { @{$o->{compssUsers}{$_}{flags}} } @{$o->{compssUsersSorted}};
	}
	if (!$o->{compssUsersChoice} && !$o->{isUpgrade}) {
	    #- by default, choose:
	    if ($o->{meta_class} eq 'server') {
		$o->{compssUsersChoice}{$_} = 1 foreach 'X', 'MONITORING', 'NETWORKING_REMOTE_ACCESS_SERVER';
	    } else {
		$o->{compssUsersChoice}{$_} = 1 foreach 'GNOME', 'KDE', 'CONFIG', 'X';
		$o->{lang} eq 'eu_ES' and $o->{compssUsersChoice}{KDE} = 0;
		$o->{compssUsersChoice}{$_} = 1
		  foreach map { @{$o->{compssUsers}{$_}{flags}} } 'Workstation|Office Workstation', 'Workstation|Internet station';
	    }
	}
    }
    $o->{compssUsersChoice}{uc($_)} = 1 foreach grep { modules::probe_category("multimedia/$_") } modules::sub_categories('multimedia');
    $o->{compssUsersChoice}{uc($_)} = 1 foreach map { $_->{driver} =~ /Flag:(.*)/ } detect_devices::probeall();
    $o->{compssUsersChoice}{SYSTEM} = 1;
    $o->{compssUsersChoice}{DOCS} = !$o->{excludedocs};
    $o->{compssUsersChoice}{BURNER} = 1 if detect_devices::burners();
    $o->{compssUsersChoice}{DVD} = 1 if detect_devices::dvdroms();
    $o->{compssUsersChoice}{USB} = 1 if modules::get_probeall("usb-interface");
    $o->{compssUsersChoice}{PCMCIA} = 1 if detect_devices::hasPCMCIA();
    $o->{compssUsersChoice}{HIGH_SECURITY} = 1 if $o->{security} > 3;
    $o->{compssUsersChoice}{BIGMEM} = 1 if !$::oem && availableRamMB() > 800 && arch() !~ /ia64/;
    $o->{compssUsersChoice}{SMP} = 1 if detect_devices::hasSMP();
    $o->{compssUsersChoice}{CDCOM} = 1 if any { $_->{descr} =~ /commercial/i } values %{$o->{packages}{mediums}};
    $o->{compssUsersChoice}{'3D'} = 1 if 
      detect_devices::matching_desc('Matrox.* G[245][05]0') ||
      detect_devices::matching_desc('Rage X[CL]') ||
      detect_devices::matching_desc('3D Rage (?:LT|Pro)') ||
      detect_devices::matching_desc('Voodoo [35]') ||
      detect_devices::matching_desc('Voodoo Banshee') ||
      detect_devices::matching_desc('8281[05].* CGC') ||
      detect_devices::matching_desc('Rage 128') ||
      detect_devices::matching_desc('Radeon ') && !detect_devices::matching_desc('Radeon 8500') ||
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
}

sub unselectMostPackages {
    my ($o) = @_;
    pkgs::unselectAllPackages($o->{packages});
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};
}

sub warnAboutNaughtyServers {
    my ($o) = @_;
    my @naughtyServers = pkgs::naughtyServers($o->{packages}) or return 1;
    my $r = $o->ask_from_list_('', 
formatAlaTeX(N("You have selected the following server(s): %s


These servers are activated by default. They don't have any known security
issues, but some new ones could be found. In that case, you must make sure
to upgrade as soon as possible.


Do you really want to install these servers?
", join(", ", @naughtyServers))), [ N_("Yes"), N_("No") ], 'Yes') or return;
    if ($r ne 'Yes') {
	log::l("unselecting naughty servers");
	pkgs::unselectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_)) foreach @naughtyServers;
    }
    1;
}

sub warnAboutRemovedPackages {
    my ($o, $packages) = @_;
    my @removedPackages = keys %{$packages->{state}{ask_remove} || {}} or return;
    if (!$o->ask_yesorno('', 
formatAlaTeX(N("The following packages will be removed to allow upgrading your system: %s


Do you really want to remove these packages?
", join(", ", @removedPackages))), 1)) {
	$packages->{state}{ask_remove} = {};
    }
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub setAuthentication {
    my ($o) = @_;
    my ($shadow, $ldap, $nis, $winbind, $winpass) = @{$o->{authentication} || {}}{qw(shadow LDAP NIS winbind winpass)};
    my $p = $o->{prefix};
    any::enableShadow($p) if $shadow;
    if ($ldap) {
	$o->pkg_install(qw(chkauth openldap-clients nss_ldap pam_ldap));
	run_program::rooted($o->{prefix}, "/usr/sbin/chkauth", "ldap", "-D", $o->{netc}{LDAPDOMAIN}, "-s", $ldap);
    } elsif ($nis) {
	#$o->pkg_install(qw(chkauth ypbind yp-tools net-tools));
	#run_program::rooted($o->{prefix}, "/usr/sbin/chkauth", "yp", $domain, "-s", $nis);
	$o->pkg_install("ypbind");
	my $domain = $o->{netc}{NISDOMAIN};
	$domain || $nis ne "broadcast" or die N("Can't use broadcast with no NIS domain");
	my $t = $domain ? "domain $domain" . ($nis ne "broadcast" && " server") : "ypserver";
	substInFile {
	    $_ = "#~$_" unless /^#/;
	    $_ .= "$t $nis\n" if eof;
	} "$p/etc/yp.conf";
	require network;
	network::write_conf("$p/etc/sysconfig/network", $o->{netc});
    } elsif ($winbind) {
	my $domain = $o->{netc}{WINDOMAIN};
	$domain =~ tr/a-z/A-Z/;

	$o->pkg_install(qw(samba-winbind samba-common));
	{   #- setup pam
	    my $f = "$o->{prefix}/etc/pam.d/system-auth";
	    cp_af($f, "$f.orig");
	    cp_af("$f-winbind", $f);
	}
	write_smb_conf($domain);
	run_program::rooted($o->{prefix}, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$o->{prefix}/home/$domain");
	
	#- defer running smbpassword - no network yet
	$winbind = $winbind . "%" . $winpass;
	addToBeDone {
	    require install_steps;
	    install_steps::upNetwork($o, 'pppAvoided');
	    run_program::rooted($o->{prefix}, "/usr/bin/smbpasswd", "-j", $domain, "-U", $winbind);
	} 'configureNetwork';
    }
}

sub write_smb_conf {
    my ($domain) = @_;

    #- was going to just have a canned config in samba-winbind
    #- and replace the domain, but sylvestre/buchan didn't bless it yet

    my $f = "$::prefix/etc/samba/smb.conf";
    rename $f, "$f.orig";
    output($f, "
[global]
	workgroup = $domain  
	server string = Samba Server %v
	security = domain  
	encrypt passwords = Yes
	password server = *
	log file = /var/log/samba/log.%m
	max log size = 50
	socket options = TCP_NODELAY SO_RCVBUF=8192 SO_SNDBUF=8192
	character set = ISO8859-15
	os level = 18
	local master = No
	dns proxy = No
	winbind uid = 10000-20000
	winbind gid = 10000-20000
	winbind separator = +
	template homedir = /home/%D/%U
	template shell = /bin/bash
	winbind use default domain = yes
");
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
	if ($@) { log::l("files still open: ", readlink($_)) foreach map { glob_("$_/fd/*") } glob_("/proc/*") }
	eval { 
	    my $dev = detect_devices::tryOpen($cdrom);	    
	    ioctl($dev, c::CDROMEJECT(), 1) if ioctl($dev, c::CDROM_DRIVE_STATUS(), 0) == c::CDS_DISC_OK();
	};
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
    bootloader::install($o->{bootloader}, $o->{fstab}, $o->{all_hds}{hds});
    1;
}

sub hdInstallPath() {
    my $tail = first(readlink("/tmp/image") =~ m|^/tmp/hdimage/(.*)|);
    my $head = first(readlink("/tmp/hdimage") =~ m|$::prefix(.*)|);
    $tail && ($head ? "$head/$tail" : "/mnt/hd/$tail");
}

sub install_urpmi {
    my ($prefix, $method, $packages, $mediums) = @_;

    #- rare case where urpmi cannot be installed (no hd install path).
    $method eq 'disk' && !hdInstallPath() and return;

    my @cfg;
    foreach (sort { $a->{medium} <=> $b->{medium} } values %$mediums) {
	my $name = $_->{fakemedium};
	if ($_->{ignored} || $_->{selected}) {
	    my $mask = umask 077;
	    open(my $LIST, ">$prefix/var/lib/urpmi/list.$name") or log::l("failed to write list.$name");
	    umask $mask;

	    my $dir = ($_->{prefix} || ${{ nfs => "file://mnt/nfs", 
					   disk => "file:/" . hdInstallPath(),
					   ftp => $ENV{URLPREFIX},
					   http => $ENV{URLPREFIX},
					   cdrom => "removable://mnt/cdrom" }}{$method} ||
		       #- for live_update or live_install script.
		       readlink "/tmp/image/Mandrake" =~ m,^(\/.*)\/Mandrake\/*$, && "removable:/$1") . "/$_->{rpmsdir}";

	    #- build list file using internal data, synthesis file should exists.
	    if ($_->{end} > $_->{start}) {
		#- WARNING this method of build only works because synthesis (or hdlist)
		#-         has been read.
		foreach (@{$packages->{depslist}}[$_->{start} .. $_->{end}]) {
		    print $LIST "$dir/".$_->filename."\n";
		}
	    } else {
		#- need to use another method here to build synthesis.
		open(my $F, "parsehdlist '$prefix/var/lib/urpmi/hdlist.$name.cz' |");
		local $_; 
		while (<$F>) {
		    print $LIST "$dir/$_";
		}
		close $F;
	    }
	    close $LIST;

	    #- build synthesis file if there are still not existing (ie not copied from mirror).
	    if (-s "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz" <= 32) {
		unlink "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
		run_program::rooted($prefix, "parsehdlist", ">", "/var/lib/urpmi/synthesis.hdlist.$name",
				    "--synthesis", "/var/lib/urpmi/hdlist.$name.cz");
		run_program::rooted($prefix, "gzip", "-S", ".cz", "/var/lib/urpmi/synthesis.hdlist.$name");
	    }

	    my ($qname, $qdir) = ($name, $dir);
	    $qname =~ s/(\s)/\\$1/g; $qdir =~ s/(\s)/\\$1/g;

	    #- output new urpmi.cfg format here.
	    push @cfg, "$qname " . ($dir !~ /^(ftp|http)/ && $qdir) . " {
  hdlist: hdlist.$name.cz
  with_hdlist: ../base/" . ($_->{update} ? "hdlist.cz" : $_->{hdlist}) . "
  list: list.$name" . ($dir =~ /removable:/ && "
  removable: /dev/cdrom") . ($_->{update} && "
  update") . "
}

";
	} else {
	    #- remove not selected media by removing hdlist and synthesis files copied.
	    unlink "$prefix/var/lib/urpmi/hdlist.$name.cz";
	    unlink "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
	}
    }
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
sub auto_inst_file() { ($::g_auto_install ? "/tmp" : "$::prefix/root/drakx") . "/auto_inst.cfg.pl" }

sub report_bug {
    my ($prefix) = @_;
    any::report_bug($prefix, 'auto_inst' => g_auto_install('', 1));
}

sub g_auto_install {
    my ($replay, $respect_privacy) = @_;
    my $o = {};

    require pkgs;
    $o->{default_packages} = pkgs::selected_leaves($::o->{packages});

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang authentication mouse netc timezone superuser intf keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security security_user libsafe netcnx useSupermount autoExitInstall mkbootdisk X services); #- TODO modules bootloader 

    if ($::o->{printer}) {
	$o->{printer}{$_} = $::o->{printer}{$_} foreach qw(SPOOLER DEFAULT BROWSEPOLLADDR BROWSEPOLLPORT MANUALCUPSCONFIG);
	$o->{printer}{configured} = {};
	foreach my $queue (keys %{$::o->{printer}{configured}}) {
	    my $val = $::o->{printer}{configured}{$queue}{queuedata};
	    exists $val->{$_} and $o->{printer}{configured}{$queue}{queuedata}{$_} = $val->{$_} foreach keys %{$val || {}};
	}
    }

    local $o->{partitioning}{auto_allocate} = !$replay;
    $o->{autoExitInstall} = !$replay;
    $o->{interactiveSteps} = [ 'doPartitionDisks', 'formatPartitions' ] if $replay;

    #- deep copy because we're modifying it below
    $o->{users} = [ @{$o->{users} || []} ];

    my @user_info_to_remove = (
	if_($respect_privacy, qw(name realname home pw)), 
	qw(oldu oldg password password2),
    );
    $_ = { %{$_ || {}} }, delete @$_{@user_info_to_remove} foreach $o->{superuser}, @{$o->{users} || []};

    if ($respect_privacy && $o->{netcnx}) {
	if (my $type = $o->{netcnx}{type}) {
	    my @netcnx_type_to_remove = qw(passwd passwd2 login phone_in phone_out);
	    $_ = { %{$_ || {}} }, delete @$_{@netcnx_type_to_remove} foreach $o->{netcnx}{$type};
	}
    }
    
    require Data::Dumper;
    my $str = join('', 
"#!/usr/bin/perl -cw
#
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
", Data::Dumper->Dump([$o], ['$o']), "\0");
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
	my $mountdir = "$o->{prefix}/tmp/mount"; mkdir_p($mountdir);
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
	my $imagefile = "$o->{prefix}/root/autoinst.img";
	my $mountdir = "$o->{prefix}/root/aif-mount"; -d $mountdir or mkdir $mountdir, 0755;

	my $param = 'kickstart=floppy ' . generate_automatic_stage1_params($o);

	getAndSaveInstallFloppy($o, $imagefile) or return;

	my $dev = devices::set_loop($imagefile) or log::l("couldn't set loopback device"), return;
        eval { fs::mount($dev, $mountdir, 'vfat', 0); 1 } or return;

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
	eval { output("$mountdir/auto_inst.cfg", g_auto_install($replay)) };
	$@ and log::l("Warning: <$@>");

	fs::umount($mountdir);
	rmdir $mountdir;
	devices::del_loop($dev);
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
	$o->ask_okcancel('', N("Insert a FAT formatted floppy in drive %s", $floppy), 1) or return;

	eval { fs::mount(devices::make($floppy), "/floppy", "vfat", 0) };
	last if !$@;
	$o->ask_warn('', N("This floppy is not FAT formatted"));
    }

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;
    output('/floppy/auto_inst.cfg', 
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n",
	   "# before testing.  To use it, boot with ``linux defcfg=floppy''\n",
	   $str, "\0");
    fs::umount("/floppy");

    $quiet or $o->ask_warn('', N("To use this saved packages selection, boot installation with ``linux defcfg=floppy''"));
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file();
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	unless ($::testing) {
	    fs::mount(devices::make(detect_devices::floppy()), "/mnt", (arch() =~ /sparc/ ? "romfs" : "vfat"), 'readonly');
	    $f = "/mnt/$f";
	}
	-e $f or $f .= '.pl';

	my $_b = before_leaving {
	    fs::umount("/mnt") unless $::testing;
	    modules::unload(qw(vfat fat));
	};
	$o = loadO($O, $f);
    } else {
	-e "$f.pl" and $f .= ".pl" unless -e $f;

	my $fh;
	if (-e $f) { open $fh, $f } else { $fh = getFile($f) or die N("Error reading file %s", $f) }
	{
	    local $/ = "\0";
	    no strict;
	    eval <$fh>;
	    close $fh;
	    $@ and die;
	}
	$O and add2hash_($o ||= {}, $O);
    }
    $O and bless $o, ref $O;
    $o;
}

sub generate_automatic_stage1_params {
    my ($o) = @_;

    my @ks = "method:$o->{method}";

    if ($o->{method} eq 'http') {
	$ENV{URLPREFIX} =~ m|http://([^/:]+)/(.*)| or die;
	push @ks, "server:$1", "directory:$2";
    } elsif ($o->{method} eq 'ftp') {
	push @ks,  "server:$ENV{HOST}", "directory:$ENV{PREFIX}", "user:$ENV{LOGIN}", "pass:$ENV{PASSWORD}";
    } elsif ($o->{method} eq 'nfs') {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/image nfs| or die;
	push @ks, "server:$1", "directory:$2";
    }

    if (member($o->{method}, qw(http ftp nfs))) {
	my ($intf) = values %{$o->{intf}};
	push @ks, "interface:$intf->{DEVICE}";
	if ($intf->{BOOTPROTO} eq 'dhcp') {
	    push @ks, "network:dhcp";
	} else {
	    require network;
	    push @ks, "network:static", "ip:$intf->{IPADDR}", "netmask:$intf->{NETMASK}", "gateway:$o->{netc}{GATEWAY}";
	    my @dnss = network::dnsServers($o->{netc});
	    push @ks, "dns:$dnss[0]" if @dnss;
	}
    }

    #- sync it with ../mdk-stage1/automatic.c
    my %aliases = (method => 'met', network => 'netw', interface => 'int', gateway => 'gat', netmask => 'netm',
		   adsluser => 'adslu', adslpass => 'adslp', hostname => 'hos', domain => 'dom', server => 'ser',
		   directory => 'dir', user => 'use', pass => 'pas', disk => 'dis', partition => 'par');
    
    'automatic='.join(',', map { /^([^:]+)(:.*)/ && $aliases{$1} ? $aliases{$1}.$2 : $_ } @ks);
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
    my $mnt = find { -e "$d/$l{$_}" } keys %l;
    $mnt ||= (stat("$d/.bashrc"))[4] ? '/root' : '/home/user' . ++$$user if -e "$d/.bashrc";
    $mnt ||= (any { -d $_ && (stat($_))[4] >= 500 && -e "$_/.bashrc" } glob_($d)) ? '/home' : '';
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
	fs::merge_info_from_fstab($fstab, $handle->{dir}, $uniq, 'loose') if $mnt eq '/';
    }
    $_->{mntpoint} and log::l("suggest_mount_points: $_->{device} -> $_->{mntpoint}") foreach @$fstab;
}

sub find_root_parts {
    my ($fstab, $prefix) = @_;
    map { 
	my $handle = any::inspect($_, $prefix);
	my $s = $handle && cat_("$handle->{dir}/etc/mandrake-release");
	if ($s) {
	    chomp($s);
	    $s =~ s/\s+for\s+\S+//;
	    log::l("find_root_parts found $_->{device}: $s");
	    { release => $s, part => $_ };
	} else { () }
    } @$fstab;
}
sub use_root_part {
    my ($all_hds, $part, $prefix) = @_;
    my $fstab = [ fsedit::get_really_all_fstab($all_hds) ];
    {
	my $handle = any::inspect($part, $prefix) or die;
	fs::merge_info_from_fstab($fstab, $handle->{dir}, 'uniq');
    }
    map { $_->{mntpoint} = 'swap' } grep { isSwap($_) } @$fstab; #- use all available swap.
}

sub getHds {
    my ($o, $in) = @_;

  getHds: 
    my $all_hds = fsedit::get_hds($o->{partitioning}, $in);
    my $hds = $all_hds->{hds};

    if (is_empty_array_ref($hds)) { #- no way
	die N("An error occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    #- try to figure out if the same number of hds is available, use them if ok.
    @{$o->{all_hds}{hds} || []} == @$hds and return 1;

    fs::get_raw_hds('', $all_hds);
    fs::add2all_hds($all_hds, @{$o->{manualFstab}});

    $o->{all_hds} = $all_hds;
    $o->{fstab} = [ fsedit::get_all_fstab($all_hds) ];
    fs::merge_info_from_mtab($o->{fstab});

    my @win = grep { isFat_or_NTFS($_) && isFat_or_NTFS({ type => fsedit::typeOfPart($_->{device}) }) } @{$o->{fstab}};
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

    1;
}

sub log_sizes {
    my ($o) = @_;
    my @df = MDK::Common::System::df($o->{prefix});
    log::l(sprintf "Installed: %s(df), %s(rpm)",
	   formatXiB($df[0] - $df[1], 1024),
	   formatXiB(sum(run_program::rooted_get_stdout($o->{prefix}, 'rpm', '-qa', '--queryformat', '%{size}\n')))) if -x "$o->{prefix}/bin/rpm";
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
	    s/\.png/\.pl/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/\.pl/_icon\.png/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/_icon\.png/\.png/;
	}
	@advertising_images = map { "$dir/$_" } @files;
    }
}

sub remove_advertising {
    my ($o) = @_;
    eval { rm_rf("$o->{prefix}/tmp/drakx-images") };
    @advertising_images = ();
}

sub disable_user_view {
    my ($prefix) = @_;
    substInFile { s/^UserView=.*/UserView=true/ } "$prefix/usr/share/config/kdm/kdmrc";
    substInFile { s/^Browser=.*/Browser=0/ } "$prefix/etc/X11/gdm/gdm.conf";
}

sub write_fstab {
    my ($o) = @_;
    fs::write_fstab($o->{all_hds}, $o->{prefix}) if !$::live && !$o->{isUpgrade};
}

my @bigseldom_used_groups = (
);

sub check_prog {
    my ($f) = @_;

    my @l = $f !~ m|^/| ?
        map { "$_/$f" } split(":", $ENV{PATH}) :
	$f;
    return if any { -x $_ } @l;

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
    if ($::o->isa('interactive::gtk')) {
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
    unlink "/usr/X11R6/lib/modules/xf86Wacom.so";
    unlink glob_("/usr/share/gtk/themes/$_*") foreach qw(marble3d);
    unlink(m|^/| ? $_ : "/usr/bin/$_") foreach 
      (map { @$_ } @bigseldom_used_groups),
      qw(pvcreate pvdisplay vgchange vgcreate vgdisplay vgextend vgremove vgscan lvcreate lvdisplay lvremove /lib/liblvm.so),
      qw(mkreiserfs resize_reiserfs mkfs.xfs fsck.jfs);
}

################################################################################
package pkgs_interactive;
use run_program;
use common;
use pkgs;

our @ISA = qw(); #- tell perl_checker this is a class

sub install_steps::do_pkgs {
    my ($o) = @_;
    bless { o => $o }, 'pkgs_interactive';
}

sub install {
    my ($do, @l) = @_;
    $do->{o}->pkg_install(@l);
}

sub ensure_is_installed {
    my ($do, $pkg, $file, $auto) = @_;

    if (! -e "$::prefix$file") {
	$do->{o}->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$auto;
	$do->{o}->do_pkgs->install($pkg);
    }
    if (! -e "$::prefix$file") {
	$do->{o}->ask_warn('', N("Mandatory package %s is missing", $pkg));
	return;
    }
    1;
}

sub what_provides {
    my ($do, $name) = @_;
    map { $do->{o}{packages}{depslist}[$_]->name } keys %{$do->{o}{packages}{provides}{$name} || {}};
}

sub is_installed {
    my ($do, @l) = @_;
    foreach (@l) {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	$p && $p->flag_available or return;
    }
    1;
}

sub are_installed {
    my ($do, @l) = @_;
    grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	$p && $p->flag_available;
    } @l;
}

sub remove {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	pkgs::unselectPackage($do->{o}{packages}, $p) if $p;
	$p;
    } @l;
    run_program::rooted($do->{o}{prefix}, 'rpm', '-e', @l);
}

sub remove_nodeps {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	if ($p) {
	    $p->set_flag_requested(0);
	    $p->set_flag_required(0);
	}
	$p;
    } @l;
    run_program::rooted($do->{o}{prefix}, 'rpm', '-e', '--nodeps', @l);
}
################################################################################

package install_any;

1;
