package install_any; # $Id$

use diagnostics;
use strict;

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
use run_program;
use partition_table qw(:types);
use partition_table_raw;
use devices;
use fsedit;
use modules;
use detect_devices;
use any;
use log;
use fs;

#- package that have to be copied for proper installation (just to avoid changing cdrom)
#- here XFree86 is copied entirey if not already installed, maybe better to copy only server.
@needToCopy = qw(
XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 XFree86-Mach8 XFree86-Mono
XFree86-P9000 XFree86-S3 XFree86-S3V XFree86-SVGA XFree86-W32 XFree86-I128
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs XFree86-FBDev XFree86-server
XFree86 XFree86-glide-module Device3DFX Glide_V3-DRI Glide_V5 Mesa
dhcpcd pump dhcpxd dhcp-client isdn4net isdn4k-utils dev pptp-adsl-fr rp-pppoe ppp ypbind
rhs-printfilters lpr cups cups-drivers pnm2ppa Lexmark-1100-printer-driver__lm1100 samba ncpfs
);

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $current_medium = 1;
my $asked_medium = 1;
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
    m,^(Mandrake|lnx4win)/, and return $_;
    /\.img$/ and return "images/$_";
    my $dir = m|/| ? "Mandrake/mdkinst" : /^(?:compss|compssList|compssUsers|provides|filelist|depslist.*|hdlist.*|auto_inst.*)$/ ?
      "Mandrake/base/": "$::o->{packages}[2]{$asked_medium}{rpmsdir}/";
    "$dir$_";
}
sub askChangeMedium($$) {
    my ($method, $medium) = @_;
    my $allow;
    do {
	eval { $allow = changeMedium($method, $medium) };
    } while ($@); #- really it is not allowed to die in changeMedium!!! or install will cores with rpmlib!!!
    $allow;
}
sub errorOpeningFile($) {
    my ($file) = @_;
    $file eq 'XXX' and return; #- special case to force closing file after rpmlib transaction.
    $current_medium eq $asked_medium and log::l("errorOpeningFile $file"), return; #- nothing to do in such case.
    $::o->{packages}[2]{$asked_medium}{selected} or return; #- not selected means no need for worying about.

    my $max = 32; #- always refuse after $max tries.
    if ($::o->{method} eq "cdrom") {
	cat_("/proc/mounts") =~ m|(/tmp/\S+)\s+/tmp/rhimage| and $cdrom = $1;
	return unless $cdrom;
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

    #- on cancel, we can expect the current medium to be undefined too,
    #- this enable remounting if selecting a package back.
    $current_medium = 'unknown';

    return;
}
sub getFile {
    my ($f, $method) = @_;
    my $rel = relGetFile($f);
    log::l("getFile $f ($method) relGetFile $rel");
    do {
	if ($method =~ /crypto/i) {
	    require crypto;
	    log::l("crypto::getFile $f");
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
	    $f2 = "/tmp/rhimage/$rel" unless $postinstall_rpms && -e $f2;
	    log::l("local getFile $f2");
	    open GETFILE, $f2 and *GETFILE;
	}
    } || errorOpeningFile($f);
}
sub getAndSaveFile {
    my ($file, $local) = @_;
    log::l("getAndSaveFile $file $local");
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
    require commands;

    log::l("postinstall rpms directory set to $postinstall_rpms");
    commands::mkdir_('-p', $postinstall_rpms);

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
    pkgs::extractHeaders($prefix, \@toCopy, $packages->[2]{1});
    commands::cp((map { "/tmp/rhimage/" . relGetFile(pkgs::packageFile($_)) } @toCopy), $postinstall_rpms);
}
sub clean_postinstall_rpms() {
    require commands;
    $postinstall_rpms and -d $postinstall_rpms and commands::rm('-rf', $postinstall_rpms);
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

sub fsck_option {
    my ($o) = @_;
    my $y = $o->{security} < 3 && $::beginner ? "-y " : "";
    substInFile { s/^(\s*fsckoptions="?)(-y )?/$1$y/ } "$o->{prefix}/etc/rc.d/rc.sysinit";
}

sub getAvailableSpace {
    my ($o) = @_;

    #- make sure of this place to be available for installation, this could help a lot.
    #- currently doing a very small install use 36Mb of postinstall-rpm, but installing
    #- these packages may eat up to 90Mb (of course not all the server may be installed!).
    #- 50mb may be a good choice to avoid almost all problem of insuficient space left...
    my $minAvailableSize = 50 * sqr(1024);

    int ((!$::testing && 
	  getAvailableSpace_mounted($o->{prefix}) || 
	  getAvailableSpace_raw($o->{fstab}) * 512 / 1.07) - $minAvailableSize);
}

sub getAvailableSpace_mounted {
    my ($prefix) = @_;
    my $dir = -d "$prefix/usr" ? "$prefix/usr" : "$prefix";
    my (undef, $free) = common::df($dir) or return;
    log::l("getAvailableSpace_mounted $free");
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
	push @{$o->{default_packages}}, "reiserfs-utils" if grep { isReiserfs($_) } @{$o->{fstab}};
	push @{$o->{default_packages}}, "cdrecord" if detect_devices::getIDEBurners();
	push @{$o->{default_packages}}, "alsa", "alsa-utils" if modules::get_alias("snd-slot-0") =~ /^snd-card-/;

	pkgs::getDeps($o->{prefix}, $o->{packages});
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	#- some program that may be crazy on some conditions (hack waiting for Aurora to work if no fb).
	$o->{allowFB} or push @pkgs::skip_list, 'Aurora';

	#- must be done after selecting base packages (to save memory)
	pkgs::getProvides($o->{packages});

	$o->{compss} = pkgs::readCompss($o->{prefix}, $o->{packages});
	#- must be done after getProvides
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages});
	($o->{compssUsers}, $o->{compssUsersSorted}) = pkgs::readCompssUsers($o->{packages}, $o->{compss});

	my @l = ();
	push @l, "kapm", "kcmlaptop", "DrakProfile", "DrakSync" if $o->{pcmcia};
	push @l, "Glide_V5"  if detect_devices::matching_desc('Voodoo 5');
	push @l, "Glide_V3-DRI"  if detect_devices::matching_desc('Voodoo 3');
	push @l, "Device3Dfx", "XFree86-glide-module" if detect_devices::matching_desc('Voodoo');
	require timezone;
	require lang;
	push @l, "isdn4k-utils" if ($o->{timezone}{timezone} || timezone::bestTimezone(lang::lang2text($o->{lang}))) =~ /Europe/;
	$_->{values} = [ map { $_ + 50 } @{$_->{values}} ] foreach grep {$_} map { pkgs::packageByName($o->{packages}, $_) } @l;

    } else {
	#- this has to be done to make sure necessary files for urpmi are
	#- present.
	pkgs::psUpdateHdlistsDeps($o->{prefix}, $o->{method});

	#- remove upgrade flag with selection one. TOCHECK
	#pkgs::unselectAllPackagesIncludingUpgradable($o->{packages});
    }
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub setAuthentication {
    my ($o) = @_;
    my ($shadow, $md5, $nis) = @{$o->{authentication} || {}}{qw(shadow md5 NIS)};
    my $p = $o->{prefix};
    any::enableMD5Shadow($p, $shadow, $md5);
    any::enableShadow($p) if $shadow;
    if ($nis) {
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
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub hdInstallPath() {
    cat_("/proc/mounts") =~ m|/\w+/(\S+)\s+/tmp/hdimage| or return;
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

    $vga ||= 785; #- assume at least 640x480x16.

    require bootloader;
    #- update bootloader entries with vga, all kernel are now framebuffer.
    foreach (qw(vmlinuz vmlinuz-secure vmlinuz-smp vmlinuz-hack)) {
	if (my $e = bootloader::get("/boot/$_", $o->{bootloader})) {
	    $e->{vga} = $vga;
	}
    }
    bootloader::install($o->{prefix}, $o->{bootloader}, $o->{fstab}, $o->{hds});
    1;
}

sub install_urpmi {
    my ($prefix, $method, $mediums) = @_;

    my @cfg = map_index {
	my $name = $_->{fakemedium};

	local *LIST;
	open LIST, ">$prefix/var/lib/urpmi/list.$name" or log::l("failed to write list.$name"), return;

	my $dir = ${{ nfs => "file://mnt/nfs", 
                      hd => "file:/" . hdInstallPath(),
		      ftp => $ENV{URLPREFIX},
		      http => $ENV{URLPREFIX},
		      cdrom => "removable_cdrom_$::i://mnt/cdrom" }}{$method} . "/$_->{rpmsdir}";

	local *FILES; open FILES, "packdrake -c /tmp/$_->{hdlist} | parsehdlist - |";
	chop, print LIST "$dir/$_\n" foreach <FILES>;
	close FILES or log::l("parsehdlist failed"), return;
	close LIST;

	$dir .= " with ../base/$_->{hdlist}" if $method =~ /ftp|http/;
	"$name $dir\n";
    } values %$mediums;
    eval { output "$prefix/etc/urpmi/urpmi.cfg", @cfg };
}


#-###############################################################################
#- kde stuff
#-###############################################################################
sub kderc_largedisplay {
    my ($prefix) = @_;

    update_userkderc($prefix, 'KDE', 
		     Contrast => 7,
		     kfmIconStyle => "Large",
		     kpanelIconStyle => "Normal", #- to change to Large when icons looks better
		     KDEIconStyle => "Large");
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
    foreach (fs::read_fstab("$prefix/etc/fstab")) {

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

    my @l = list_skels($prefix, 'Desktop/Doc.kdelnk');
    if (my ($lang) = all("$prefix/usr/doc/mandrake")) {
	substInFile { s|^(URL=.*?)/?$|$1/$lang/index.html| } @l;
	substInFile { s|^(url=/usr/doc/mandrake/)$|$1$lang/index.html| } "$prefix/usr/lib/desktop-links/mandrake.links";
    } else {
	unlink @l;
	substInFile { $_ = '' if /^\[MDKsupport\]$/ .. /^\s*$/ } "$prefix/usr/lib/desktop-links/mandrake.links";
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
	unlink("$dir/Trash/$_") && rename("$dir/$_", "$dir/Trash/$_")
	    foreach grep { -e "$dir/$_" } @toMove, grep { /\.rpmorig$/ } all($dir)
    }
}


#-###############################################################################
#- auto_install stuff
#-###############################################################################
sub auto_inst_file() { ($::g_auto_install ? "/tmp" : "$::o->{prefix}/root") . "/auto_inst.cfg.pl" }

sub g_auto_install(;$) {
    my ($f) = @_; $f ||= auto_inst_file;
    my $o = {};

    $o->{default_packages} = [ map { pkgs::packageName($_) } grep { pkgs::packageFlagSelected($_) && !pkgs::packageFlagBase($_) } values %{$::o->{packages}[0]} ];

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang autoSCSI authentication printer mouse wacom netc timezone superuser intf keyboard mkbootdisk users installClass partitioning isUpgrade manualFstab nomouseprobe crypto security netcnx useSupermount autoExitInstall); #- TODO modules bootloader 

    if (my $card = $::o->{X}{card}) {
	$o->{X}{$_} = $::o->{X}{$_} foreach qw(default_depth resolution_wanted);
	if ($o->{X}{default_depth} and my $depth = $card->{depth}{$o->{X}{default_depth}}) {
	    $depth ||= [];
	    $o->{X}{resolution_wanted} ||= join "x", @{$depth->[0]} unless is_empty_array_ref($depth->[0]);
	    $o->{X}{monitor} = $::o->{X}{monitor} if $::o->{X}{monitor}{manual};
	}
    }

    local $o->{partitioning}{auto_allocate} = 1;
    local $o->{autoExitInstall} = 1;

    $_ = { %{$_ || {}} }, delete @$_{qw(oldu oldg password password2)} foreach $o->{superuser}, @{$o->{users} || []};
    
    output($f, 
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl' before testing\n",
	   Data::Dumper->Dump([$o], ['$o']), "\0");
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file;
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? "auto_inst.cfg" : "patch";
	unless ($::testing) {
	    fs::mount(devices::make("fd0"), "/mnt", (arch() =~ /sparc/ ? "romfs" : "vfat"), 'readonly');
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

sub generate_ks_cfg {
    my ($o) = @_;
    
    return if $o->{method} =~ /hd|cdrom/;

    my $ks;
    if ($o->{method} =~ /ftp|http/) {
	$ks .= "url --url $ENV{URLPREFIX}\n";
    } elsif ($o->{method} =~ /nfs/) {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/rhimage nfs| or die;
	$ks .= "nfs --server $1 --dir $2\n";
    }
    my %intf = %{$o->{intf}[0]};
    if ($intf{BOOTPROTO} =~ /^(dhcp|bootp)$/) {
	$ks .= "network --bootproto $intf{BOOTPROTO}\n";
    } else {
	require network;
	my %l = (ip => $intf{IPADDR}, netmask => $intf{NETMASK}, gateway => $o->{netc}{GATEWAY});
	$ks .= "network " . join(" ", map_each { $::b && "--$::a $::b" } %l);
	$ks .= " --nameserver $_" foreach network::dnsServers($o->{netc});
	$ks .= "\n";
    }
    $ks;
}

sub suggest_mount_points {
    my ($hds, $prefix, $uniq) = @_;
    my @parts = grep { isTrueFS($_) } fsedit::get_fstab(@$hds);

    my (%mntpoints, $user);

    my %l = (
	     '/'     => 'etc/fstab',
	     '/boot' => 'vmlinuz',
	     '/tmp'  => '.X11-unix',
	     '/usr'  => 'X11R6',
	     '/var'  => 'catman',
	    );

    foreach my $part (@parts) {
	$part->{mntpoint} && !$part->{unsafeMntpoint} and next; #- if already found via an fstab

	my $handle = any::inspect($part, $prefix) or return;
	my $d = $handle->{dir};
	my ($mnt) = grep { -e "$d/$l{$_}" } keys %l;
	$mnt ||= (stat("$d/.bashrc"))[4] ? '/root' : '/home/user' . ++$user if -e "$d/.bashrc";
	$mnt ||= (grep { -d $_ && (stat($_))[4] >= 500 && -e "$_/.bashrc" } glob_("$d")) ? '/home' : ''; 

	next if $uniq && fsedit::mntpoint2part($mnt, \@parts);
	$part->{mntpoint} = $mnt; delete $part->{unsafeMntpoint};

	#- try to find other mount points via fstab
	fs::get_mntpoints_from_fstab([ fsedit::get_fstab(@$hds) ], $d, $uniq) if $mnt eq '/' && $uniq;
    }
#-    $_->{mntpoint} || fsedit::suggest_part($_, $hds) foreach @parts;

    $_->{mntpoint} and log::l("suggest_mount_points: $_->{device} -> $_->{mntpoint}") foreach @parts;
}

#- mainly for finding the root partitions for upgrade
sub find_root_parts {
    my ($hds, $prefix) = @_;
    log::l("find_root_parts");
    suggest_mount_points($hds, $prefix);
    grep { delete($_->{mntpoint}) eq '/' } fsedit::get_fstab(@$hds);
}
sub use_root_part {
    my ($fstab, $part, $prefix) = @_;
    {
	my $handle = any::inspect($part, $prefix) or die;
	fs::get_mntpoints_from_fstab($fstab, $handle->{dir}, 'uniq');
    }
    map { $_->{mntpoint} = 'swap' } grep { isSwap($_) } @$fstab; #- use all available swap.
    fs::mount_all($fstab, $prefix);
}

sub getHds {
    my ($o, $f_err) = @_;
    my $ok = 1;
    my $flags = $o->{partitioning};

    my @drives = detect_devices::hds();
#    add2hash_($o->{partitioning}, { readonly => 1 }) if partition_table_raw::typeOfMBR($drives[0]{device}) eq 'system_commander';

  getHds: 
    $o->{hds} = catch_cdie { fsedit::hds(\@drives, $flags) }
      sub {
	  $ok = 0;
	  my $err = $@; $err =~ s/ at (.*?)$//;
	  log::l("error reading partition table: $err");
	  !$flags->{readonly} && $f_err and $f_err->($err);
      };

    if (is_empty_array_ref($o->{hds}) && $o->{autoSCSI}) {
	$o->setupSCSI; #- ask for an unautodetected scsi card
	goto getHds;
    }

    $ok = fsedit::verifyHds($o->{hds}, $flags->{readonly}, $ok)
        unless $flags->{clearall} || $flags->{clear};

    $o->{fstab} = [ fsedit::get_fstab(@{$o->{hds}}) ];
    fs::check_mounted($o->{fstab});
    fs::merge_fstabs($o->{fstab}, $o->{manualFstab});

    my @win = grep { isFat($_) && isFat({ type => fsedit::typeOfPart($_->{device}) }) } @{$o->{fstab}};
    log::l("win parts: ", join ",", map { $_->{device} } @win) if @win;
    if (@win == 1) {
	$win[0]{mntpoint} = "/mnt/windows";
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

1;
