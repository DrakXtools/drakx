package install_steps;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:file :system :common);
use install_any qw(:all);
use partition_table qw(:types);
use detect_devices;
use timezone;
use modules;
use run_program;
use lilo;
use lang;
use keyboard;
use printer;
use pkgs;
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
    exec "true";
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
	fs::format_part($_) if $_->{toFormat};
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
    pkgs::init_db($o->{prefix}, $o->{isUpgrade});
}

sub installPackages($$) {
    my ($o, $packages) = @_;
    #- hack to ensure proper ordering for installation of packages.
    my @firstToInstall = qw(basesystem sed);
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
    pkgs::install($o->{prefix}, \@toInstall);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    #-  why not? cuz weather is nice today :-) [pixel]
    sync(); sync();

    $o->pcmciaConfig();
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
    #-res_init();		#- reinit the resolver so DNS changes take affect

    pppConfig($o);
}

#------------------------------------------------------------------------------
sub pppConfig {
    my ($o) = @_;
    $o->{modem} or return;

    symlinkf($o->{modem}{device}, "$o->{prefix}/dev/modem");
    install_any::pkg_install($o, "ppp");

    my %toreplace;
    $toreplace{$_} = $o->{modem}{$_} foreach qw(connection phone login passwd auth domain);
    $toreplace{phone} =~ s/[^\d]//g;
    $toreplace{dnsserver} = join '', map { "$o->{modem}{$_}," } "dns1", "dns2";
    
    foreach ("$o->{prefix}/root", "$o->{prefix}/etc/skel") {
	template2file("/usr/share/kppprc.in", "$_/.kde/share/config/kppprc", %toreplace) if -d "$_/.kde/share/config";
    }
}

#------------------------------------------------------------------------------
sub pcmciaConfig($) {
    my ($o) = @_;
    my $t = $o->{pcmcia};
    my $f = "$o->{prefix}/etc/sysconfig/pcmcia";

    #- should be set after installing the package above else the file will be renamed.
    setVarsInSh($f, {
	PCMCIA    => $t ? "yes" : "no",
	PCIC      => $t,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f) = @_;
    timezone::write($o->{prefix}, $o->{timezone}, $f);
}

#------------------------------------------------------------------------------
sub servicesConfig {}
#------------------------------------------------------------------------------
sub printerConfig {
    my($o) = @_;
    if ($o->{printer}{complete}) {

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
	    if (!$u || getpwuid($u)) { for ($u = 500; getpwuid($u) || $uids{$u}; $u++) {} }
	    if (!$g || getgrgid($g)) { for ($g = 500; getgrgid($g) || $gids{$g}; $g++) {} }

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
    print F "$_->{name}::$_->{gid}:\n" foreach @l;

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

    lilo::mkbootdisk($o->{prefix}, install_any::kernelVersion(), $dev);
    $o->{mkbootdisk} = $dev;
}

#------------------------------------------------------------------------------
sub readBootloaderConfigBeforeInstall {
    my ($o) = @_;
    my ($image, $v);
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
    lilo::suggest($o->{prefix}, $o->{bootloader}, $o->{hds}, $o->{fstab}, install_any::kernelVersion());
    $o->{bootloader}{keytable} ||= keyboard::kmap($o->{keyboard});
}

sub setupBootloader($) {
    my ($o) = @_;
    return if $::g_auto_install;
    lilo::install($o->{prefix}, $o->{bootloader});
}

#------------------------------------------------------------------------------
sub setupXfree {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub miscellaneous {
    my ($o) = @_;
    setVarsInSh("$o->{prefix}/etc/sysconfig/system", { 
	LAPTOP => bool2text($o->{miscellaneous}{LAPTOP}),
        HDPARM => $o->{miscellaneous}{HDPARM},
        TYPE => $o->{installClass},
        SECURITY => $o->{security},
    });
    setVarsInSh ("$o->{prefix}/etc/profile.d/proxy.sh",  $o->{miscellaneous}, qw(http_proxy ftp_proxy)); 
    setVarsInCsh("$o->{prefix}/etc/profile.d/proxy.csh", $o->{miscellaneous}, qw(http_proxy ftp_proxy)); 
}

#------------------------------------------------------------------------------
sub exitInstall { install_any::unlockCdroms }

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
