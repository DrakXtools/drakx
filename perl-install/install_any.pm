package install_any;

use diagnostics;
use strict;
use Config;

use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @needToCopy);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(getNextStep spawnShell addToBeDone) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :functional :file);
use commands;
use run_program;
use partition_table qw(:types);
use partition_table_raw;
use devices;
use fsedit;
use network;
use modules;
use detect_devices;
use fs;
use log;

#- package that have to be copied for proper installation (just to avoid changing cdrom)
#- here XFree86 is copied entirey if not already installed, maybe better to copy only server.
@needToCopy = qw(
XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 XFree86-Mach8 XFree86-Mono
XFree86-P9000 XFree86-S3 XFree86-S3V XFree86-SVGA XFree86-W32 XFree86-I128
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs
XFree86 dhcpxd pump ppp ypbind rhs-printfilters samba ncpfs kernel-fb
);

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $current_medium = '';
my $asked_medium = '';
sub useMedium($) {
    #- before ejecting the first CD, there are some files to copy!
    #- does nothing if the function has already been called.
    $_[0] and $::o->{method} eq 'cdrom' and setup_postinstall_rpms($::o->{prefix}, $::o->{packages});

    $asked_medium eq $_[0] or log::l("selecting new medium \"$_[0]\"");
    $asked_medium = $_[0];
}
sub changeMedium($$) {
    my ($method, $medium) = @_;
    log::l("change to medium $medium for method $method (refused by default)");
    0;
}
sub relGetFile($) {
    local $_ = $_[0];
    m,^(Mandrake|lnx4win)/, and return $_;
    /\.img$/ and return "images/$_";
    my $dir = m|/| ? "mdkinst" : /^(?:compss|compssList|compssUsers|filelist|depslist.*|hdlist.*)$/ ?
      "base/": "RPMS$asked_medium/";
    "Mandrake/$dir$_";
}
sub askChangeMedium($$) {
    my ($method, $medium) = @_;
    my $allow;
    do {
	local $::no_theme_change = 1; #- avoid changing theme here!
	eval { $allow = changeMedium($method, $medium) };
    } while ($@); #- really it is not allowed to die in changeMedium!!! or install will cores with rpmlib!!!
    $allow;
}
sub errorOpeningFile($) {
    my ($file) = @_;
    $file eq 'XXX' and return; #- special case to force closing file after rpmlib transaction.
    $current_medium eq $asked_medium and return; #- nothing to do in such case.
    $::o->{packages}[2]{$asked_medium}{selected} or return; #- not selected means no need for worying about.

    my $max = 32; #- always refuse after $max tries.
    if ($::o->{method} eq "cdrom") {
	cat_("/proc/mounts") =~ m|(/tmp/\S+)\s+/tmp/rhimage| or return;
	my $cdrom = $1;
	ejectCdrom($cdrom);
	while ($max > 0 && askChangeMedium($::o->{method}, $asked_medium)) {
	    $current_medium = $asked_medium;
	    eval { fs::mount($cdrom, "/tmp/rhimage", "iso9660", 'readonly') };
	    my $getFile = getFile($file); $getFile and return $getFile;
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
    $::o->{packages}[2]{$asked_medium}{selected} = undef;

    return;
}
sub getFile {
    local $^W = 0;
    if ($::o->{method} && $::o->{method} eq "ftp") {
	require ftp;
	*install_any::getFile = sub { ftp::getFile($_[0]) or errorOpeningFile($_[0]) };
    } elsif ($::o->{method} && $::o->{method} eq "http") {
	require http;
	*install_any::getFile = sub { http::getFile($_[0]) or errorOpeningFile($_[0]) };
    } else {
	*install_any::getFile = sub {
	    #- try to open the file, but examine if it is present in the repository, this allow
	    #- handling changing a media when some of the file on the first CD has been copied
	    #- to other to avoid media change...
	    open getFile, "/tmp/rhimage/" . relGetFile($_[0]) or
	      $postinstall_rpms and open getFile, "$postinstall_rpms/$_[0]" or return errorOpeningFile($_[0]);
	    *getFile;
	};
    }
    goto &getFile;
}
sub getAndSaveFile {
    my ($file, $local) = @_;
    local *F; open F, ">$local" or return;
    local $/ = \ (16 * 1024);
    my $f = getFile($file) or return;
    syswrite F, $_ foreach <$f>;
    1;
}


#-######################################################################################
#- Post installation RPMS from cdrom only, functions
#-######################################################################################
sub setup_postinstall_rpms($$) {
    my ($prefix, $packages) = @_;

    $postinstall_rpms and return;
    $postinstall_rpms = "$prefix/usr/postinstall-rpm";

    log::l("postinstall rpms directory set to $postinstall_rpms");
    commands::mkdir_('-p', $postinstall_rpms);

    require pkgs;

    #- compute closure of unselected package that may be copied,
    #- don't complain if package does not exists as it may happen
    #- for the various architecture taken into account (X servers).
    my %toCopy;
    foreach (@needToCopy) {
	my $pkg = pkgs::packageByName($packages, $_);
	pkgs::selectPackage($packages, $pkg, 0, \%toCopy) if $pkg;
    }

    my @toCopy; push @toCopy, map { pkgs::packageByName($packages, $_) } keys %toCopy;

    #- extract headers of package, this is necessary for getting
    #- the complete filename of each package.
    #- copy the package files in the postinstall RPMS directory.
    #- last arg is default medium '' known as the CD#1.
    pkgs::extractHeaders($prefix, \@toCopy, $packages->[2]{''});
    commands::cp((map { "/tmp/rhimage/" . relGetFile(pkgs::packageFile($_)) } @toCopy), $postinstall_rpms);
}
sub clean_postinstall_rpms() {
    $postinstall_rpms and commands::rm('-rf', $postinstall_rpms);
}

#-######################################################################################
#- Functions
#-######################################################################################
sub kernelVersion {
    my ($o) = @_;
    local $_ = readlink("$::o->{prefix}/boot/vmlinuz") and return first(/vmlinuz-(.*)/);

    my $p = pkgs::packageByName($o->{packages}, "kernel") or die "I couldn't find the kernel package!";
    pkgs::packageVersion($p) . "-" . pkgs::packageRelease($p);
}


sub getNextStep {
    my ($s) = $::o->{steps}{first};
    $s = $::o->{steps}{$s}{next} while $::o->{steps}{$s}{done} || !$::o->{steps}{$s}{reachable};
    $s;
}

sub spawnShell {
    return if $::o->{localInstall} || $::testing;

    -x "/bin/sh" or die "cannot open shell - /usr/bin/sh doesn't exist";

    fork and return;

    local *F;
    sysopen F, "/dev/tty2", 2 or die "cannot open /dev/tty2 -- no shell will be provided";

    open STDIN, "<&F" or die '';
    open STDOUT, ">&F" or die '';
    open STDERR, ">&F" or die '';
    close F;

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    exec {"/bin/sh"} "-/bin/sh" or log::l("exec of /bin/sh failed: $!");
}

sub shells($) {
    my ($o) = @_;
    my @l = grep { -x "$o->{prefix}$_" } @{$o->{shells}};
    @l ? @l : "/bin/bash";
}

sub getAvailableSpace {
    my ($o) = @_;

    do { $_->{mntpoint} eq '/usr' and return int($_->{size} * 512 / 1.07) } foreach @{$o->{fstab}};
    do { $_->{mntpoint} eq '/'    and return int($_->{size} * 512 / 1.07) } foreach @{$o->{fstab}};

    if ($::testing) {
	my $nb = 1350;
	log::l("taking ${nb}MB for testing");
	return $nb << 20;
    }
    die "missing root partition";
}

sub setPackages($) {
    my ($o) = @_;

    require pkgs;
    if (!$o->{packages} || is_empty_hash_ref($o->{packages}[0])) {
	$o->{packages} = pkgs::psUsingHdlists($o->{prefix}, $o->{method});

	push @{$o->{default_packages}}, "nfs-utils-clients" if $o->{method} eq "nfs";
	push @{$o->{default_packages}}, "numlock" if $o->{miscellaneous}{numlock};
	push @{$o->{default_packages}}, "kernel-secure" if $o->{security} > 3;
	push @{$o->{default_packages}}, "kernel-smp" if $o->{security} <= 3 && detect_devices::hasSMP(); #- no need for kernel-smp if we have kernel-secure which is smp
	push @{$o->{default_packages}}, "kernel-pcmcia-cs" if $o->{pcmcia};
	push @{$o->{default_packages}}, "apmd" if $o->{pcmcia};
	push @{$o->{default_packages}}, "raidtools" if $o->{raid} && !is_empty_array_ref($o->{raid}{raid});
	push @{$o->{default_packages}}, "cdrecord" if detect_devices::getIDEBurners();
	push @{$o->{default_packages}}, "alsa" if modules::get_alias("sound") =~ /^snd-card-/;

	pkgs::getDeps($o->{packages});

	$o->{compss} = pkgs::readCompss($o->{packages});
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages}, $o->{compss});
	($o->{compssUsers}, $o->{compssUsersSorted}) = pkgs::readCompssUsers($o->{packages}, $o->{compss});

	my @l = ();
	push @l, "kapm" if $o->{pcmcia};
	require timezone;
	require lang;
	push @l, "isdn4k-utils" if ($o->{timezone}{timezone} || timezone::bestTimezone(lang::lang2text($o->{lang}))) =~ /Europe/;
	$_->{values} = [ map { $_ + 50 } @{$_->{values}} ] foreach grep {$_} map { $o->{packages}{$_} } @l;

	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	#- must be done after selecting base packages (to save memory)
	pkgs::getProvides($o->{packages});

    } else {
	pkgs::unselectAllPackages($o->{packages});
    }

    #- this will be done if necessary in the selectPackagesToUpgrade,
    #- move the selection here ? this will remove the little window.
    unless ($o->{isUpgrade}) {
	foreach (@{$o->{default_packages}}) {
	    my $p = pkgs::packageByName($o->{packages}, $_) or log::l("missing add-on package $_"), next;
	    pkgs::selectPackage($o->{packages}, $p);
	}
    }
}

sub selectPackagesToUpgrade($) {
    my ($o) = @_;

    require pkgs;
    pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix}, $o->{base}, $o->{toRemove}, $o->{toSave});
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub getHds {
    my ($o) = @_;
    my ($ok, $ok2) = 1;

    my @drives = detect_devices::hds();
#    add2hash_($o->{partitioning}, { readonly => 1 }) if partition_table_raw::typeOfMBR($drives[0]{device}) eq 'system_commander';

  getHds: 
    $o->{hds} = catch_cdie { fsedit::hds(\@drives, $o->{partitioning}) }
      sub {
	my ($err) = $@ =~ /(.*) at /;
	$@ =~ /overlapping/ and $o->ask_warn('', $@), return 1;
	$o->ask_okcancel(_("Error"),
[_("I can't read your partition table, it's too corrupted for me :(
I'll try to go on blanking bad partitions"), $err]) unless $o->{partitioning}{readonly};
	$ok = 0; 1 
    };

    if (is_empty_array_ref($o->{hds}) && $o->{autoSCSI}) {
	$o->setupSCSI; #- ask for an unautodetected scsi card
	goto getHds;
    }

    ($o->{hds}, $o->{fstab}, $ok2) = fsedit::verifyHds($o->{hds}, $o->{partitioning}{readonly}, $ok);

    fs::check_mounted($o->{fstab});
    fs::merge_fstabs($o->{fstab}, $o->{manualFstab});

    $o->{partitioning}{clearall} and return 1;
    $o->ask_warn('', 
_("DiskDrake failed to read correctly the partition table.
Continue at your own risk!")) if !$ok2 && $ok && !$o->{partitioning}{readonly};

    my @win = grep { isFat($_) && isFat({ type => fsedit::typeOfPart($_->{device}) }) } @{$o->{fstab}};
    my @nt  = grep { isNT($_)  && isNT( { type => fsedit::typeOfPart($_->{device}) }) } @{$o->{fstab}};
    log::l("win parts: ", join ",", map { $_->{device} } @win) if @win;
    log::l("nt parts: ",  join ",", map { $_->{device} } @nt) if @nt;
    $_->{mntpoint} = @win == 1 ? "/mnt/windows" : "/mnt/win_$_->{device_windobe}" foreach @win;
    $_->{mntpoint} = @nt  == 1 ? "/mnt/nt"      : "/mnt/nt_$_->{device_windobe}"  foreach @nt;

    $ok2;
}

sub searchAndMount4Upgrade {
    my ($o) = @_;
    my ($root, $found);

    my $w = $::beginner && $o->wait_message('', _("Searching root partition."));

    #- try to find the partition where the system is installed if beginner
    #- else ask the user the right partition, and test it after.
    getHds($o);

    #- get all ext2 partition that may be root partition.
    my %Parts = my %parts = map { $_->{device} => $_ } grep { isExt2($_) } @{$o->{fstab}};
    while (keys(%parts) > 0) {
	$root = $::beginner ? first(%parts) : $o->selectRootPartition(keys %parts);
	$root = delete $parts{$root};

	my $r; unless ($r = $root->{realMntpoint}) {
	    $r = $o->{prefix};
	    $root->{mntpoint} = "/"; 
	    log::l("trying to mount partition $root->{device}");
	    eval { fs::mount_part($root, $o->{prefix}, 'readonly') };
	    $r = "/*ERROR*" if $@;
	}
	$found = -d "$r/etc/sysconfig" && [ fs::read_fstab("$r/etc/fstab") ];

	unless ($root->{realMntpoint}) {
	    log::l("umounting partition $root->{device}");
	    eval { fs::umount_part($root, $o->{prefix}) };
	}

	last if !is_empty_array_ref($found);

	delete $root->{mntpoint};
	$o->ask_warn(_("Information"), 
		     _("%s: This is not a root partition, please select another one.", $root->{device})) unless $::beginner;
    }
    is_empty_array_ref($found) and die _("No root partition found");
	
    log::l("found root partition : $root->{device}");

    #- test if the partition has to be fsck'ed and remounted rw.
    if ($root->{realMntpoint}) {
	($o->{prefix}, $root->{mntpoint}) = ($root->{realMntpoint}, '/');
    } else {
	delete $root->{mntpoint};
	($Parts{$_->{device}} || {})->{mntpoint} = $_->{mntpoint} foreach @$found;
	map { $_->{mntpoint} = 'swap_upgrade' } grep { isSwap($_) } @{$o->{fstab}}; #- use all available swap.

	#- TODO fsck, create check_mount_all ?
	fs::mount_all([ grep { isExt2($_) || isSwap($_) } @{$o->{fstab}} ], $o->{prefix});
    }
}

sub write_ldsoconf {
    my ($prefix) = @_;
    my $file = "$prefix/etc/ld.so.conf";

    #- write a minimal ld.so.conf file unless it already exists.
    unless (-s "$file") {
	local *F;
	open F, ">$file" or die "unable to open for writing $file";
	print F "/usr/lib\n";
    }
}

sub setAuthentication() {
    my ($shadow, $md5, $nis, $nis_server) = @{$::o->{authentication} || {}}{qw(shadow md5 NIS NIS_server)};
    my $p = $::o->{prefix};
    enableMD5Shadow($p, $shadow, $md5);
    enableShadow() if $shadow;
    if ($nis) {
	pkg_install($::o, "ypbind");
	my $domain = $::o->{netc}{NISDOMAIN};
	$domain || $nis_server ne "broadcast" or die _("Can't use broadcast with no NIS domain");
	my $t = $domain ? "domain $domain" . ($nis_server ne "broadcast" && " server")
	                : "ypserver";
	substInFile {
	    $_ = "#~$_" unless /^#/;
	    $_ .= "$t $nis_server\n" if eof;
	} "$p/etc/yp.conf";
	network::write_conf("$p/etc/sysconfig/network", $::o->{netc});
    }
}

sub enableShadow() {
    my $p = $::o->{prefix};
    run_program::rooted($p, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($p, "grpconv") or log::l("grpconv failed");

#-    my $chpasswd = sub {
#-	  my ($name, $password) = @_;
#-	  $password =~ s/"/\\"/;
#-
#-	  local *log::l = sub {}; #- disable the logging (otherwise password visible in the log)
#-	  run_program::rooted($p, qq((echo "$password" ; sleep 1 ; echo "$password") | passwd $name));
#-#-	run_program::rooted($p, "echo $name:$password | chpasswd");
#-    };
#-    &$chpasswd("root", $::o->{superuser}{password});
#-    &$chpasswd($_->{name}, $_->{password}) foreach @{$::o->{users} || []};
}

sub enableMD5Shadow($$$) {
    my ($prefix, $shadow, $md5) = @_;
    substInFile {
	if (/^password.*pam_pwdb.so/) {
	    s/\s*shadow//; s/\s*md5//;
	    s/$/ shadow/ if $shadow;
	    s/$/ md5/ if $md5;
	}
    } grep { -r $_ } map { "$prefix/etc/pam.d/$_" } qw(login rlogin passwd);
}

sub crypt($) {
    my ($password) = @_;

    $::o->{authentication}{md5} ?
      c::crypt_md5($password, salt(8)) :
         crypt    ($password, salt(2));
}

sub killCardServices {
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub hdInstallPath() {
    cat_("/proc/mounts") =~ m|/tmp/(\S+)\s+/tmp/hdimage| or return;
    my ($part) = grep { $_->{device} eq $1 } @{$::o->{fstab}};    
    $part->{mntpoint} or grep { $_->{mntpoint} eq "/mnt/hd" } @{$::o->{fstab}} and return;
    $part->{mntpoint} ||= "/mnt/hd";
    $part->{mntpoint} . first(readlink("/tmp/rhimage") =~ m|^/tmp/hdimage/(.*)|);
}

sub unlockCdrom(;$) {
    my ($cdrom) = @_;
    $cdrom or cat_("/proc/mounts") =~ m|(/tmp/\S+)\s+/tmp/rhimage| and $cdrom = $1;
    eval { $cdrom and ioctl detect_devices::tryOpen($1), c::CDROM_LOCKDOOR(), 0 };
}
sub ejectCdrom(;$) {
    my ($cdrom) = @_;
    $cdrom or cat_("/proc/mounts") =~ m|(/tmp/\S+)\s+/tmp/rhimage| and $cdrom = $1;
    my $f = eval { $cdrom && detect_devices::tryOpen($cdrom) } or return;
    getFile("XXX"); #- close still opened filehandle
    eval { fs::umount("/tmp/rhimage") };
    ioctl $f, c::CDROMEJECT(), 1;
}

sub setupFB {
    my ($o, $vga) = @_;

    #- install needed packages for frame buffer.
    require pkgs;
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_)) foreach (qw(kernel-fb XFree86-FBDev));
    $o->installPackages($o->{packages});

    $vga ||= 785; #- assume at least 640x480x16.

    require lilo;
    #- update lilo entries with a new fb label. a bit hack unless
    #- a frame buffer kernel is used, in such case we use it instead
    #- with the right mode, nothing more to do.
    foreach (qw(secure smp)) {
	if (my $e = lilo::get("/boot/vmlinuz-$_", $o->{bootloader})) {
	    if ($_ eq 'secure') {
		log::l("warning: kernel-secure is not fb, using a kernel-fb instead");
		#- nothing done, fall through linux-fb.
	    } else {
		$e->{vga} = $vga;
		lilo::install($o->{prefix}, $o->{bootloader});
		return 1;
	    }
	}
    }
    if (lilo::add_kernel($o->{prefix}, $o->{bootloader}, kernelVersion($o), 'fb',
			 {
			  label => 'linux-fb',
			  root => lilo::get("/boot/vmlinuz", $o->{bootloader})->{root},
			  vga => $vga,
			 })) {
	$o->{bootloader}{default} = 'linux-fb';
	lilo::install($o->{prefix}, $o->{bootloader});
    } else {
	log::l("unable to install kernel with frame buffer support, disabling");
	return 0;
    }
    1;
}

sub auto_inst_file() { ($::g_auto_install ? "/tmp" : "$::o->{prefix}/root") . "/auto_inst.cfg.pl" }

sub g_auto_install(;$) {
    my ($f) = @_; $f ||= auto_inst_file;
    my $o = {};

    $o->{default_packages} = [ map { pkgs::packageName($_) } grep { pkgs::packageFlagSelected($_) && !pkgs::packageFlagBase($_) } values %{$::o->{packages}[0]} ];

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang autoSCSI authentication printer mouse wacom netc timezone superuser intf keyboard mkbootdisk users installClass partitioning isUpgrade manualFstab nomouseprobe crypto security modem useSupermount autoExitInstall); #- TODO modules bootloader 

    if (my $card = $::o->{X}{card}) {
	$o->{X}{card}{$_} = $card->{$_} foreach qw(default_depth);
	if ($card->{default_depth} and my $depth = $card->{depth}{$card->{default_depth}}) {
	    $depth ||= [];
	    $o->{X}{card}{resolution_wanted} ||= join "x", @{$depth->[0]} unless is_empty_array_ref($depth->[0]);
	}
    }

    local $o->{partitioning}{auto_allocate} = 1;

    $_ = { %{$_ || {}} }, delete @$_{qw(oldu oldg password password2)} foreach $o->{superuser}, @{$o->{users} || []};
    
    local *F;
    open F, ">$f" or log::l("can't output the auto_install script in $f"), return;
    print F Data::Dumper->Dump([$o], ['$o']), "\0";
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file;
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? "auto_inst.cfg" : "patch";
	unless ($::testing) {
	    fs::mount(devices::make("fd0"), "/mnt", "vfat", 'readonly');
	    $f = "/mnt/$f";
	}
	-e $f or $f .= ".pl";

	my $b = before_leaving {
	    fs::umount("/mnt") unless $::testing;
	    modules::unload($_) foreach qw(vfat fat);
	};
	$o = loadO($O, $f);
    } else {
	-e "$f.pl" and $f .= ".pl" unless -e $f;

	my $fh = -e $f ? do { local *F; open F, $f; *F } : getFile($f) or die _("Error reading file $f");
	{
	    local $/ = "\0";
	    no strict;
	    eval <$fh>;
	    close $fh;
	    $@ and log::l("Bad kickstart file $f (failed $@)");
	}
	add2hash_($o ||= {}, $O);
    }
    bless $o, ref $O;
}

sub pkg_install {
    my ($o, $name) = @_;
    require pkgs;
    require install_steps;
    print "trying to pkg_install $name\n";
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $name) || die "$name rpm not found");
    print "trying to pkg_install $name : done selection\n";
    install_steps::installPackages($o, $o->{packages});
    print "trying to pkg_install $name : done installed\n";
}

sub fsck_option() {
    my $y = $::o->{security} < 3 && $::beginner ? "-y " : "";
    substInFile { s/^(\s*fsckoptions="?)(-y )?/$1$y/ } "$::o->{prefix}/etc/rc.d/rc.sysinit";
}

sub install_urpmi {
    my ($prefix, $method, $mediums) = @_;

    getAndSaveFile("depslist", "$prefix/var/lib/urpmi/depslist");

    my @cfg = map_index {
	my $name = $_->{fakemedium};

	local *LIST;
	open LIST, ">$prefix/var/lib/urpmi/list.$name" or log::l("failed to write list.$name"), return;

	my $dir = ${{ nfs => "file://mnt/nfs", 
                      hd => "file:/" . hdInstallPath(),
		      ftp => $ENV{URLPREFIX},
		      http => $ENV{URLPREFIX},
		      cdrom => "removable_cdrom_$::i://mnt/cdrom" }}{$method} . "/Mandrake/RPMS$_->{medium}";

	local *FILES; open FILES, "bzip2 -dc /tmp/$_->{hdlist} 2>/dev/null | hdlist2names - |";
	chop, print LIST "$dir/$_\n" foreach <FILES>;
	close FILES or log::l("hdlist2names failed"), return;
	close LIST;

	$dir .= " with ../base/$_->{hdlist}" if $method =~ /ftp|http/;
	"$name $dir\n";
    } values %$mediums;
    eval { output "$prefix/etc/urpmi/urpmi.cfg", @cfg };
}

sub list_passwd() {
    my ($e, @l);

    setpwent();
    while (@{$e = [ getpwent() ]}) { push @l, $e }
    endpwent();

    @l;
}

sub list_home() {
    map { $_->[7] } grep { $_->[2] >= 500 } list_passwd();
}
sub list_skels() { "/etc/skel", "/root", list_home() }

sub template2userfile($$$$%) {
    my ($prefix, $inputfile, $outputrelfile, $force, %toreplace) = @_;

    foreach (list_skels()) {
	my $outputfile = "$prefix/$_/$outputrelfile";
	if (-d dirname($outputfile) && ($force || ! -e $outputfile)) {
	    log::l("generating $outputfile from template $inputfile");
	    template2file($inputfile, $outputfile, %toreplace);
	    m|/home/(.*)| and commands::chown_($1, $outputfile);
	}
    }
}

sub update_userkderc($$$) {
    my ($prefix, $cat, $subst) = @_;

    foreach (list_skels()) {
	my ($inputfile, $outputfile) = ("$prefix$_/.kderc", "$prefix$_/.kderc.new");
	my %tosubst = (%$subst);
	local *INFILE; local *OUTFILE;
	open INFILE, $inputfile or return;
	open OUTFILE, ">$outputfile" or return;

	print OUTFILE map {
	    if (my $i = /^\s*\[$cat\]/i ... /^\s*\[/) {
		if (/^\s*(\w*)=/ && $tosubst{lc($1)}) {
		    delete $tosubst{lc($1)};
		} else {
		    ($i > 1 && /^\s*\[/ && join '', map { delete $tosubst{$_} } keys %tosubst). $_;
		}
	    } else {
		$_;
	    }
	} <INFILE>;
	print OUTFILE "[$cat]\n", values %tosubst if values %tosubst; #- if categorie has not been found above.

	unlink $inputfile;
	rename $outputfile, $inputfile;
    }
}

sub kderc_largedisplay($) {
    my ($prefix) = @_;

    update_userkderc($prefix, 'KDE', {
				      contrast => "Contrast=7\n",
				      kfmiconstyle => "kfmIconStyle=Large\n",
				      kpaneliconstyle => "kpanelIconStyle=Normal\n", #- to change to Large when icons looks better
				      kdeiconstyle => "KDEIconStyle=Large\n",
				     });
    foreach (list_skels()) {
	substInFile {
	    s/^(GridWidth)=85/$1=100/;
	    s/^(GridHeight)=70/$1=75/;
	} "$prefix$_/.kde/share/config/kfmrc" 
    }
}

sub kdelang_postinstall($) {
    my ($prefix) = @_;
    my %i18n = getVarsFromSh("$prefix/etc/sysconfig/i18n");

    #- remove existing reference to $lang.
    update_userkderc($prefix, 'Locale', { language => "Language=\n" });
}

sub kdeicons_postinstall($) {
    my ($prefix) = @_;

    #- parse etc/fstab file to search for dos/win, floppy, zip, cdroms icons.
    #- handle both supermount and fsdev usage.
    local *F;
    open F, "$prefix/etc/fstab" or log::l("failed to read $prefix/etc/fstab"), return;

    foreach (<F>) {
	if (m|^/dev/(\S+)\s+/mnt/cdrom(\d*)\s+|) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/cdrom.fsdev.kdelnk.in", "Desktop/Cd-Rom". ($2 && " $2") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/dev/(\S+)\s+/mnt/zip(\d*)\s+|) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/zip.fsdev.kdelnk.in", "Desktop/Zip". ($2 && " $2") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/dev/(\S+)\s+/mnt/floppy-ls(\d*)\s+|) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/floppy.fsdev.kdelnk.in", "Desktop/LS-120". ($2 && " $2") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/dev/(\S+)\s+/mnt/floppy(\d*)\s+|) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/floppy.fsdev.kdelnk.in", "Desktop/Floppy". ($2 && " $2") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/mnt/cdrom(\d*)\s+/mnt/cdrom\d*\s+supermount|) {
	    my %toreplace = ( id => $1 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/cdrom.kdelnk.in", "Desktop/Cd-Rom". ($1 && " $1") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/mnt/zip(\d*)\s+/mnt/zip\d*\s+supermount|) {
	    my %toreplace = ( id => $1 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/zip.kdelnk.in", "Desktop/Zip". ($1 && " $1") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/mnt/floppy-ls(\d*)\s+/mnt/floppy-ls\d*\s+supermount|) {
	    my %toreplace = ( id => $1 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/floppy.kdelnk.in", "Desktop/LS-120". ($1 && " $1") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/mnt/floppy(\d*)\s+/mnt/floppy\d*\s+supermount|) {
	    my %toreplace = ( id => $1 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/floppy.kdelnk.in", "Desktop/Floppy". ($1 && " $1") .".kdelnk",
			      1, %toreplace);
	} elsif (m|^/dev/(\S+)\s+(/mnt/DOS_\S*)\s+|) {
	    my %toreplace = ( device => $1, id => $1, mntpoint => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/Dos_.kdelnk.in", "Desktop/Dos_$1.kdelnk", 1, %toreplace);
	    symlink "hd_umount.xpm", "$prefix/usr/share/icons/hd_unmount.xpm";
	    symlink "hd_umount.xpm", "$prefix/usr/share/icons/large/hd_unmount.xpm";
	} elsif (m|^/dev/(\S+)\s+(\S*)\s+vfat\s+|) {
	    my %toreplace = ( device => $1, id => $1, mntpoint => $2 );
	    template2userfile($prefix, "$ENV{SHARE_PATH}/Dos_.kdelnk.in", "Desktop/Dos_$1.kdelnk", 1, %toreplace);
	    symlink "hd_umount.xpm", "$prefix/usr/share/icons/hd_unmount.xpm";
	    symlink "hd_umount.xpm", "$prefix/usr/share/icons/large/hd_unmount.xpm";
	}
    }

    my @l = map { "$prefix$_/Desktop/Doc.kdelnk" } list_skels();
    if (my ($lang) = eval { all("$prefix/usr/doc/mandrake") }) {
	substInFile { s|^(URL=.*?)/?$|$1/$lang| } @l;
	substInFile { s|^(url=/usr/doc/mandrake/)$|$1$lang/index.html| } "$prefix/usr/lib/desktop-links/mandrake.links";
    } else {
	unlink @l;
	substInFile { $_ = '' if /^\[MDKsupport\]$/ .. /^\s*$/ } "$prefix/usr/lib/desktop-links/mandrake.links";
    }

    my $lang = quotemeta $ENV{LANG};
    foreach my $dir (map { "$prefix$_/Desktop" } list_skels()) {
	-d $dir or next;
	foreach (grep { /\.kdelnk$/ } all($dir)) {
	    cat_("$dir/$_") =~ /^Name\[$lang\]=(.{2,14})$/m
	      and rename "$dir/$_", "$dir/$1.kdelnk";
	}
    }
}

sub move_desktop_file($) {
    my ($prefix) = @_;
    my @toMove = qw(doc.kdelnk news.kdelnk updates.kdelnk home.kdelnk printer.kdelnk floppy.kdelnk cdrom.kdelnk FLOPPY.kdelnk CDROM.kdelnk);

    foreach (list_skels()) {
	my $dir = "$prefix$_";
	if (-d "$dir/Desktop") {
	    my @toSubst = glob_("$dir/Desktop/*rpmorig");

	    push @toSubst, "$dir/Desktop/$_" foreach @toMove;

	    #- remove any existing save in Trash of each user and
	    #- move appropriate file there after an upgrade.
	    foreach (@toSubst) {
		if (-e $_) {
		    my $basename = basename($_);

		    unlink "$dir/Desktop/Trash/$basename";
		    rename $_, "$dir/Desktop/Trash/$basename";
		}
	    }
	}
    }
}

sub generate_ks_cfg {
    my ($o) = @_;
    
    return if $o->{method} =~ /hd|cdrom/;

    my $ks;
    if ($o->{method} =~ /ftp|http/) {
	$ks .= "url --url $ENV{URLPREFIX}\n";
    } elsif ($o->{method} =~ /nfs/) {
	cat_("/proc/mounts") =~ m|(\S+:\S+)\s+/tmp/rhimage nfs| or die;
	$ks .= "nfs --server $1 --dir $2\n";
    }
    my %intf = %{$o->{intf}[0]};
    if ($intf{BOOTPROTO} =~ /^(dhcp|bootp)$/) {
	$ks .= "network --bootproto $intf{BOOTPROTO}\n";
    } else {
	my %l = (ip => $intf{IPADDR}, netmask => $intf{NETMASK}, gateway => $o->{netc}{GATEWAY});
	$ks .= "network " . join(" ", map_each { $::b && "--$::a $::b" } %l);
	$ks .= "--nameserver $_" foreach network::dnsServers($o->{netc});
	$ks .= "\n";
    }
    $ks;
}

1;
