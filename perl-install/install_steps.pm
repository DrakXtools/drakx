package install_steps;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:file :system :common :functional);
use install_any qw(:all);
use partition_table qw(:types);
use detect_devices;
use modules;
use run_program;
use lang;
use raid;
use keyboard;
use log;
use fsedit;
use commands;
use network;
use fs;


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

sub errorInStep($$) { print "error :(\n"; exit 1 }
sub kill_action {}


#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;
    lang::set($o->{lang});

    if ($o->{keyboard_unsafe} || !$o->{keyboard}) {
	$o->{keyboard_unsafe} = 1;
	$o->{keyboard} = keyboard::lang2keyboard($o->{lang});
	selectKeyboard($o);
    }
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup($o->{keyboard})
}
#------------------------------------------------------------------------------
sub selectPath {}
#------------------------------------------------------------------------------
sub selectInstallClass($@) {
    my ($o) = @_;
    $o->{installClass} ||= "normal";
    $o->{security} ||= ${{
	normal    => 2,
	developer => 3,
	server    => 4,
    }}{$o->{installClass}};
}
#------------------------------------------------------------------------------
sub setupSCSI { modules::load_thiskind('scsi') }
#------------------------------------------------------------------------------
sub doPartitionDisks($$) {
    my ($o, $hds) = @_;
    return if $::testing;
    partition_table::write($_) foreach @$hds;
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

	unless ($_->{toFormat} = $_->{notFormatted} || $o->{partitioning}{autoformat}) {
	    my $t = fsedit::typeOfPart($_->{device});
	    $_->{toFormatUnsure} = $_->{mntpoint} eq "/" ||
	      #- if detected dos/win, it's not precise enough to just compare the types (too many of them)
	      (isFat({ type => $t }) ? !isFat($_) : $t != $_->{type});
	}
    }
}

sub formatPartitions {
    my $o = shift;
    foreach (@_) {
	raid::format_part($o->{raid}, $_) if $_->{toFormat};
    }
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;
    install_any::setPackages($o);
}
sub selectPackagesToUpgrade {
    my ($o) = @_;
    install_any::selectPackagesToUpgrade($o);
}

sub choosePackages($$$$) {
    my ($o, $packages, $compss, $compssUsers) = @_;
}

sub beforeInstallPackages {
    my ($o) = @_;

    network::add2hosts("$o->{prefix}/etc/hosts", "localhost.localdomain", "127.0.0.1");
    require pkgs;
    pkgs::init_db($o->{prefix}, $o->{isUpgrade});
}

sub beforeRemoveOtherPackages($) {
    my ($prefix) = @_;

    #- hack to save some files that may be removed during installation of other packages.
    do {
	unlink "$prefix/$_.mdkgisave"; rename "$prefix/$_", "$prefix/$_.mdkgisave";
    } foreach qw(/etc/passwd);
}

sub afterRemoveOtherPackages($) {
    my ($prefix) = @_;

    #- hack to restore what have been saved before removing other packages.
    do {
	unlink "$prefix/$_"; rename "$prefix/$_.mdkgisave", "$prefix/$_";
    } foreach qw(/etc/passwd);
}

sub installPackages($$) {
    my ($o, $packages) = @_;

    if (@{$o->{toRemove} || []}) {
	#- hack to ensure proper upgrade of packages from other distribution,
	#- as release number are not mandrake based. this causes save of
	#- important files and restore them after.
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_") {
		unlink "$o->{prefix}/$_.mdkgisave"; rename "$o->{prefix}/$_", "$o->{prefix}/$_.mdkgisave";
	    }
	}
	pkgs::remove($o->{prefix}, $o->{toRemove});
	foreach (@{$o->{toSave} || []}) {
	    if (-e "$o->{prefix}/$_.mdkgisave") {
		unlink "$o->{prefix}/$_"; rename "$o->{prefix}/$_.mdkgisave", "$o->{prefix}/$_";
	    }
	}
	$o->{toSave} = [];
    }

    #- hack to ensure proper ordering for installation of packages.
    my @firstToInstall = qw(setup basesystem sed);
    my %firstInstalled;
    my @toInstall;
    foreach (@firstToInstall) {
	if ($packages->{$_}{selected} && !$packages->{$_}{installed}) {
	    push @toInstall, $packages->{$_};
	    $firstInstalled{$_} = 1; #- avoid installing twice a package.
	}
    }
    push @toInstall, grep { $_->{base} && $_->{selected} && !$_->{installed} && !$firstInstalled{$_->{name}} } values %$packages;
    push @toInstall, grep { !$_->{base} && $_->{selected} && !$_->{installed} && !$firstInstalled{$_->{name}} } values %$packages;
    pkgs::install($o->{prefix}, $o->{isUpgrade}, \@toInstall);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    pkgs::done_db();

    #-  why not? cuz weather is nice today :-) [pixel]
    sync(); sync();

    $o->pcmciaConfig();

    #- remove the nasty acon...
    run_program::rooted($o->{prefix}, "chkconfig", "--del", "acon") unless $ENV{LANGUAGE} =~ /ar/;

    #- miscellaneous
    addToBeDone {
	setVarsInSh("$o->{prefix}/etc/sysconfig/system", { 
            HDPARM => $o->{miscellaneous}{HDPARM},
            TYPE => $o->{installClass},
            SECURITY => $o->{security},
        });
	install_any::fsck_option();
    } 'doInstallStep';

    if ($o->{pcmcia}) {
	substInFile { s/.*(TaskBarShowAPMStatus).*/$1=1/ } "$o->{prefix}/usr/lib/X11/icewm/preferences";
	eval { commands::cp("$o->{prefix}/usr/share/applnk/System/kapm.kdelnk", 
			    "$o->{prefix}/etc/skel/Desktop/Autostart/kapm.kdelnk") };
    }

    my $p = $o->{packages}{urpmi};
    install_any::install_urpmi($o->{prefix}, $o->{method}) if $p && $p->{selected};
}

#------------------------------------------------------------------------------
sub selectMouse($) {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o) = @_;
    my $etc = "$o->{prefix}/etc";

    network::write_conf("$etc/sysconfig/network", $o->{netc});
    network::write_resolv_conf("$etc/resolv.conf", $o->{netc});
    network::write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_->{DEVICE}", $_) foreach @{$o->{intf}};
    network::add2hosts("$etc/hosts", $o->{netc}{HOSTNAME}, map { $_->{IPADDR} } @{$o->{intf}});
    network::sethostname($o->{netc}) unless $::testing;
    network::addDefaultRoute($o->{netc}) unless $::testing;

    install_any::pkg_install($o, "dhcpcd") if grep { $_->{BOOTPROTO} =~ /^(dhcp|bootp)$/ } @{$o->{intf}};
    # Handle also pump (this is still in initscripts no?)
    install_any::pkg_install($o, "pump") if grep { $_->{BOOTPROTO} =~ /^(pump)$/ } @{$o->{intf}};
    #-res_init();		#- reinit the resolver so DNS changes take affect

    miscellaneousNetwork($o);
}

#------------------------------------------------------------------------------
sub pppConfig {
    my ($o) = @_;
    $o->{modem} or return;

    symlinkf($o->{modem}{device}, "$o->{prefix}/dev/modem") or log::l("creation of $o->{prefix}/dev/modem failed");
    install_any::pkg_install($o, "ppp");

    my %toreplace;
    $toreplace{$_} = $o->{modem}{$_} foreach qw(connection phone login passwd auth domain);
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, PAP => 1, 'Terminal-based' => 2, CHAP => 3, }}{$o->{modem}{auth}}; #'
    $toreplace{phone} =~ s/[^\d]//g;
    $toreplace{dnsserver} = join '', map { "$o->{modem}{$_}," } "dns1", "dns2";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{intf} ||= 'ppp0';

    if ($o->{modem}{auth} eq 'PAP') {
	template2file("/usr/share/ifcfg-ppp.pap.in", "$o->{prefix}/etc/sysconfig/network-scripts/ifcfg-ppp0", %toreplace);
	template2file("/usr/share/chat-ppp.pap.in", "$o->{prefix}/etc/sysconfig/network-scripts/chat-ppp0", %toreplace);

	my @l = cat_("$o->{prefix}/etc/ppp/pap-secrets");
	my $replaced = 0;
	do { $replaced ||= 1
	       if s/^\s*$toreplace{login}\s+ppp0\s+(\S+)/$toreplace{login}  ppp0  $toreplace{passwd}/; } foreach @l;
	if ($replaced) {
	    open F, ">$o->{prefix}/etc/ppp/pap-secrets" or die "Can't open $o->{prefix}/etc/ppp/pap-secrets $!";
	    print F @l;
	} else {
	    open F, ">>$o->{prefix}/etc/ppp/pap-secrets" or die "Can't open $o->{prefix}/etc/ppp/pap-secrets $!";
	    print F "$toreplace{login}  ppp0  $toreplace{passwd}\n";
	}
    } elsif ($o->{modem}{auth} eq 'Terminal-based' || $o->{modem}{auth} eq 'Script-based') {
	template2file("/usr/share/ifcfg-ppp.script.in", "$o->{prefix}/etc/sysconfig/network-scripts/ifcfg-ppp0", %toreplace);
	template2file("/usr/share/chat-ppp.script.in", "$o->{prefix}/etc/sysconfig/network-scripts/chat-ppp0", %toreplace);
    } #- no CHAP currently.

    #- build /etc/resolv.conf according to ppp configuration since there is no other network configuration.
    open F, ">$o->{prefix}/etc/resolv.conf" or die "Can't open $o->{prefix}/etc/resolv.conf $!";
    print F "domain $o->{modem}{domain}\n";
    print F "nameserver $o->{modem}{dns1}\n" if $o->{modem}{dns1};
    print F "nameserver $o->{modem}{dns2}\n" if $o->{modem}{dns2};
    close F;

    install_any::template2userfile($o->{prefix}, "/usr/share/kppprc.in", ".kde/share/config/kppprc", 1, %toreplace);

    miscellaneousNetwork($o);
}

#------------------------------------------------------------------------------
sub installCrypto {
    my ($o) = @_;
    my $u = $o->{crypto} or return; $u->{mirror} or return;
    my ($packages, %done);
    my $dir = "$o->{prefix}/tmp";
    network::up_it($o->{prefix}, $o->{intf}) if $o->{intf};

    local *install_any::getFile = sub {
	local *F;
	open F, "$dir/$_[0]" or return;
	*F;
    };
    require crypto;
    require pkgs;
    while (crypto::get($u->{mirror}, $dir, 
		       grep { !$done{$_} && ($done{$_} = $u->{packages}{$_}) } %{$u->{packages}})) {
	$packages = pkgs::psUsingDirectory($dir);
	foreach (values %$packages) {
	    foreach (c::headerGetEntry(pkgs::getHeader($_), 'requires')) {
		my $r = crypto::require2package($_);
		/^$r-\d/ and $u->{packages}{$_} = 1 foreach keys %{$u->{packages}};
	    }
	}
    }
    pkgs::install($o->{prefix}, $o->{isUpgrade}, [ values %$packages ]);
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
sub timeConfig {
    my ($o, $f) = @_;
    require timezone;
    timezone::write($o->{prefix}, $o->{timezone}, $f);
}

#------------------------------------------------------------------------------
sub servicesConfig {}
#------------------------------------------------------------------------------
sub printerConfig {
    my($o) = @_;
    if ($o->{printer}{complete}) {
	require printer;
	require pkgs;
	pkgs::select($o->{packages}, $o->{packages}{'rhs-printfilters'});
	$o->installPackages($o->{packages});

	printer::configure_queue($o->{printer});
    }
}

#------------------------------------------------------------------------------
my @etc_pass_fields = qw(name pw uid gid realname home shell);
sub setRootPassword($) {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $u = $o->{superuser} ||= {};

    $u->{pw} ||= $u->{password} && install_any::crypt($u->{password});

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
	    my $u = $_->{uid} || ($_->{oldu} = (stat("$p$_->{home}"))[4]);
	    my $g = $_->{gid} || ($_->{oldg} = (stat("$p$_->{home}"))[5]);
	    #- search for available uid above 501 else initscripts may fail to change language for KDE.
	    if (!$u || getpwuid($u)) { for ($u = 501; getpwuid($u) || $uids{$u}; $u++) {} }
	    if (!$g || getgrgid($g)) { for ($g = 501; getgrgid($g) || $gids{$g}; $g++) {} }

	    $_->{home} ||= "/home/$_->{name}";
	    $_->{uid} = $u; $uids{$u} = 1;
	    $_->{gid} = $g; $gids{$g} = 1;
	    $_->{pw} ||= $_->{password} && install_any::crypt($_->{password});
	    $done{$_->{name}} = 1;
	}
    } @{$o->{users} || []};
    my @passwd = cat_("$p/etc/passwd");;

    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F join(':', @$_{@etc_pass_fields}), "\n" foreach @l;

    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$_->{name}:x:$_->{gid}:\n" foreach @l;

    foreach (@l) {
	if (! -d "$p$_->{home}") {
	    my $mode = $o->{security} < 2 ? 0755 : 0750;
	    eval { commands::cp("-f", "$p/etc/skel", "$p$_->{home}") };
	    if ($@) {
		log::l("copying of skel failed: $@"); mkdir("$p$_->{home}", $mode); 
	    } else {
		chmod $mode, "$p$_->{home}";
	    }
	}
	commands::chown_("-r", "$_->{uid}.$_->{gid}", "$p$_->{home}")
	    if $_->{uid} != $_->{oldu} || $_->{gid} != $_->{oldg};

	run_program::rooted($p, "usermod", "-G", "urpmi", $_->{name}) if $o->{security} < 3;
    }
}

#------------------------------------------------------------------------------
sub createBootdisk($) {
    my ($o) = @_;
    my $dev = $o->{mkbootdisk} or return;

    my @l = detect_devices::floppies();

    $dev = shift @l || die _("No floppy drive available")
      if $dev eq "1"; #- special case meaning autochoose

    return if $::testing;

    require lilo;
    lilo::mkbootdisk($o->{prefix}, install_any::kernelVersion(), $dev);
    $o->{mkbootdisk} = $dev;
}

#------------------------------------------------------------------------------
sub readBootloaderConfigBeforeInstall {
    my ($o) = @_;
    my ($image, $v);
    require lilo;
    add2hash($o->{bootloader} ||= {}, lilo::read($o->{prefix}, "/etc/lilo.conf"));

    #- since kernel or kernel-smp may not be upgraded, it should be checked
    #- if there is a need to update existing lilo.conf entries by using that
    #- hash.
    my %ofpkgs = (
		  'vmlinuz' => 'kernel',
		  'vmlinuz-smp' => 'kernel-smp',
		 );

    #- change the /boot/vmlinuz or /boot/vmlinuz-smp entries to follow symlink.
    foreach $image (keys %ofpkgs) {
	if ($o->{bootloader}{entries}{"/boot/$image"} && $o->{packages}{$ofpkgs{$image}}{selected}) {
	    $v = readlink "$o->{prefix}/boot/$image";
	    if ($v) {
		$v = "/boot/$v" if $v !~ m|^/|;
		if (-e "$o->{prefix}$v") {
		    $o->{bootloader}{entries}{$v} = $o->{bootloader}{entries}{"/boot/$image"};
		    delete $o->{bootloader}{entries}{"/boot/$image"};
		    log::l("renaming /boot/$image entry by $v");
		}
	    }
	}
    }
}

sub setupBootloaderBefore {
    my ($o) = @_;
    $o->{bootloader}{perImageAppend} = "mem=$o->{miscellaneous}{memsize}" if $o->{miscellaneous}{memsize};
    require lilo;
    lilo::suggest($o->{prefix}, $o->{bootloader}, $o->{hds}, $o->{fstab}, install_any::kernelVersion());
    $o->{bootloader}{keytable} ||= keyboard::keyboard2kmap($o->{keyboard});
}

sub setupBootloader($) {
    my ($o) = @_;
    return if $::g_auto_install;
    lilo::install($o->{prefix}, $o->{bootloader});
}

#------------------------------------------------------------------------------
sub setupXfreeBefore {
    my ($o) = @_;
    $o->{X}{keyboard}{xkb_keymap} ||= keyboard::keyboard2xkb($o->{keyboard});
    $o->{X}{mouse} = $o->{mouse};

    require Xconfig;
    Xconfig::getinfoFromDDC($o->{X});

    #- keep this here if the package has to be updated.
    install_any::pkg_install($o, "XFree86");
}
sub setupXfree {
    my ($o) = @_;
    $o->setupXfreeBefore;

    require Xconfigurator;
    require class_discard;
    { local $::testing = 0; #- unset testing
      local $::auto = 1;
      local $::skiptest = 1;
      Xconfigurator::main($o->{prefix}, $o->{X}, class_discard->new, $o->{allowFB}, sub {
         install_any::pkg_install($o, "XFree86-$_[0]");
      });
    }
    $o->setupXfreeAfter;
}
sub setupXfreeAfter {
    my ($o) = @_;
    if ($o->{X}{card}{server} eq 'FBDev') {
	unless (install_any::setupFB($o, Xconfigurator::getVGAMode($o->{X}))) {
	    log::l("disabling automatic start-up of X11 if any as setup framebuffer failed");
	    Xconfigurator::rewriteInittab(3) unless $::testing; #- disable automatic start-up of X11 on error.
	}
    }
    if ($o->{X}{card}{default_depth} >= 16 && $o->{X}{card}{default_wres} >= 1024) {
	log::l("setting large icon style for kde");
	install_any::kderc_largedisplay($o->{prefix});
    }
}

#------------------------------------------------------------------------------
sub miscellaneousNetwork {
    my ($o) = @_;
    setVarsInSh ("$o->{prefix}/etc/profile.d/proxy.sh",  $o->{miscellaneous}, qw(http_proxy ftp_proxy));
    setVarsInCsh("$o->{prefix}/etc/profile.d/proxy.csh", $o->{miscellaneous}, qw(http_proxy ftp_proxy));
}

#------------------------------------------------------------------------------
sub miscellaneous {
    my ($o) = @_;
    $ENV{SECURE_LEVEL} = $o->{security};
    add2hash_ $o, { useSupermount => $o->{security} < 4 };

    cat_("/proc/cmdline") =~ /mem=(\S+)/;
    add2hash_($o->{miscellaneous} ||= {}, { numlock => !$o->{pcmcia}, $1 ? (memsize => $1) : () });
}

#------------------------------------------------------------------------------
sub exitInstall { install_any::ejectCdrom }

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
