package install_any;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(getNextStep spawnSync spawnShell addToBeDone) ],
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
use lilo;
use detect_devices;
use pkgs;
use fs;
use log;


#-######################################################################################
#- Functions
#-######################################################################################
sub relGetFile($) {
    local $_ = $_[0];
    my $dir = m|/| ? "mdkinst" :
      (member($_, qw(compss compssList compssUsers depslist hdlist)) ? "base" : "RPMS");
    $_ = "Mandrake/$dir/$_";
    s/i386/i586/;
    $_;
}
sub getFile($) {
    local $^W = 0;
    if ($::o->{method} && $::o->{method} eq "ftp") {
	require 'ftp.pm';
	*install_any::getFile = \&ftp::getFile;
    } else {
	*install_any::getFile = sub($) {
	    open getFile, "/tmp/rhimage/" . relGetFile($_[0]) or return;
	    *getFile;
	};
    }
    goto &getFile;
}

sub kernelVersion {
    local $_ = readlink("$::o->{prefix}/boot/vmlinuz") || $::testing && "vmlinuz-2.2.testversion" or die "I couldn't find the kernel package!";
    first(/vmlinuz-(.*)/);
}


sub getNextStep {
    my ($s) = $::o->{steps}{first};
    $s = $::o->{steps}{$s}{next} while $::o->{steps}{$s}{done} || !$::o->{steps}{$s}{reachable};
    $s;
}

sub spawnSync {
    return if $::o->{localInstall} || $::testing;
    fork and return;
    while (1) { sleep(30); sync(); }
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
	log::l("taking 200MB for testing");
	return 200 << 20;
    }
    die "missing root partition";
}

sub setPackages($) {
    my ($o) = @_;

    if (is_empty_hash_ref($o->{packages})) {
	my $useHdlist = $o->{method} !~ /nfs|hd/ || $o->{isUpgrade};
	eval { $o->{packages} = pkgs::psUsingHdlist() }  if $useHdlist;
	$o->{packages} = pkgs::psUsingDirectory() if !$useHdlist || $@;

	$o->{packages}{$_}{selected} = 1 foreach @{$o->{default_packages} || []};

	pkgs::getDeps($o->{packages});

	my $c; ($o->{compss}, $c) = pkgs::readCompss($o->{packages});
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages}, $c, $o->{lang});
	$o->{compssUsers} = pkgs::readCompssUsers($o->{packages}, $o->{compss});
	push @{$o->{base}}, "kernel-smp" if detect_devices::hasSMP();
	push @{$o->{base}}, "kernel-pcmcia-cs" if $o->{pcmcia};
    } else {
    	$_->{selected} = 0 foreach values %{$o->{packages}};
    }


    #- this will be done if necessary in the selectPackagesToUpgrade,
    #- move the selection here ? this will remove the little window.
    unless ($o->{isUpgrade}) {
	do {
	    my $p = $o->{packages}{$_} or log::l("missing base package $_"), next;
	    pkgs::select($o->{packages}, $p, 1);
	} foreach @{$o->{base}};
    }
    return if $::auto_install;

    ($o->{packages_}{ind}, $o->{packages_}{select_level}) = pkgs::setSelectedFromCompssList($o->{compssListLevels}, $o->{packages}, getAvailableSpace($o) * 0.7, $o->{installClass}, $o->{lang}, $o->{isUpgrade});
}

sub selectPackagesToUpgrade($) {
    my ($o) = @_;

    pkgs::selectPackagesToUpgrade($o->{packages}, $o->{prefix}, $o->{base});
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
    add2hash_($o->{partitioning}, { readonly => 1 }) if partition_table_raw::typeOfMBR($drives[0]{device}) eq 'system_commander';

  getHds: 
    $o->{hds} = catch_cdie { fsedit::hds(\@drives, $o->{partitioning}) }
      sub {
	$o->ask_warn(_("Error"),
_("I can't read your partition table, it's too corrupted for me :(
I'll try to go on blanking bad partitions")) unless $o->{partitioning}{readonly};
	$ok = 0; 1 
    };

    if (is_empty_array_ref($o->{hds}) && $o->{autoSCSI}) {
	$o->setupSCSI; #- ask for an unautodetected scsi card
	goto getHds;
    }

    ($o->{hds}, $o->{fstab}, $ok2) = fsedit::verifyHds($o->{hds}, $o->{partitioning}{readonly}, $ok);

    fs::check_mounted($o->{fstab});

    $o->{partitioning}{clearall} and return 1;
    $o->ask_warn('', 
_("DiskDrake failed to read correctly the partition table.
Continue at your own risk!")) if !$ok2 && $ok && !$o->{partitioning}{readonly};

    $ok2;
}

sub searchAndMount4Upgrade {
    my ($o) = @_;
    my ($root, $found);

    $o->{partitioning}{readonly} = 1;

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
	
    log::l("Found root partition : $root->{device}");

    #- test if the partition has to be fschecked and remounted rw.
    if ($root->{realMntpoint}) {
	($o->{prefix}, $root->{mntpoint}) = ($root->{realMntpoint}, '/');
    } else {
	delete $root->{mntpoint};
	($Parts{$_->{device}} || {})->{mntpoint} = $_->{mntpoint} foreach @$found;

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
    my ($shadow, $md5, $nis, $nis_server) = @{$::o->{authentification} || {}}{qw(shadow md5 NIS NIS_server)};
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

    $::o->{authentification}{md5} ?
      c::crypt_md5($password, salt(8)) :
         crypt    ($password, salt(2));
}

sub lnx4win_postinstall {
    my ($prefix) = @_;
    my $dir = "/dos/lnx4win";
    my $kernel = "$dir/vmlinuz";
    rename $kernel, "$kernel.old";
    commands::dd("if=$prefix/boot/vmlinuz", "of=$kernel");
    run_program::run("rdev", $kernel, "/dev/loop7");

    unlink "$dir/size.txt";
    unlink "$dir/swapsize.txt";

    mkdir "$prefix/initrd", 0755;
    symlinkf "/initrd/dos", "$prefix/mnt/dos";
}

sub killCardServices {
    my $pid = chop_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub unlockCdroms {
    ioctl detect_devices::tryOpen($_->{device}), c::CDROM_LOCKDOOR(), 0
      foreach detect_devices::cdroms();
}

sub setupFB {
    my ($o, $vga) = @_;

    #- install needed packages for frame buffer.
    pkgs::select($o->{packages}, $o->{packages}{'kernel-fb'});
    pkgs::select($o->{packages}, $o->{packages}{'XFree86-FBDev'});
    $o->installPackages($o->{packages});

    #- update lilo entries with a new fb label. a bit hack.
    my $root = $o->{bootloader}{entries}{'/boot/vmlinuz'}{root};
    if (lilo::add_kernel($o->{prefix}, $o->{bootloader}, kernelVersion(), 'fb',
			 {
			  label => 'linux-fb',
			  root => $root,
			  vga => $vga || 785,
			 })) {
	$o->{bootloader}{default} = 'linux-fb';
	lilo::install($o->{prefix}, $o->{bootloader});
    } else {
	#- should deactivate X11 in such case.
	#- TODO
	die _("I can't access the kernel with frame buffer support.\nDisabling automatic X11 startup if any.");
    }
}

sub auto_inst_file() { "$::o->{prefix}/root/auto_inst.cfg.pl" }

sub g_auto_install(;$) {
    my ($f) = @_; $f ||= auto_inst_file;
    my $o = bless {};

    $o->{default_packages} = [ map { $_->{name} } grep { $_->{selected} && !$_->{base} } values %{$::o->{packages}} ];

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang autoSCSI authentification printer mouse netc timezone superuser intf keyboard mkbootdisk base users installClass partitioning); #- TODO modules bootloader 

#-    local $o->{partitioning}{clearall} = 1;

    $_ = { %{$_ || {}} }, delete @$_{qw(oldu oldg password password2)} foreach $o->{superuser}, @{$o->{users} || []};
    
    local *F;
    open F, ">$f" or log::l("can't output the auto_install script in $f"), return;
    print F Data::Dumper->Dump([$o], ['$o']), "\0";
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file;
    my $o;
    if ($f eq "floppy") {
	my $f = "auto_inst.cfg";
	unless ($::testing) {
	    fs::mount(devices::make("fd0"), "/mnt", "vfat", 0);
	    $f = "/mnt/$f";
	}
	-e $f or $f .= ".pl";
	$o = loadO($O, $f);
	fs::umount("/mnt") unless $::testing;
    } else {
	-e $f or $f .= ".pl";
	{
	    local *F;
	    open F, $f or die _("Error reading file $f");

	    local $/ = "\0";
	    eval <F>;
	}
	$@ and log::l _("Bad kickstart file %s (failed %s)", $f, $@);
	add2hash_($o, $O);
    }
    bless $o, ref $O;
}

sub pkg_install {
    my ($o, $name) = @_;
    pkgs::select($o->{packages}, $o->{packages}{$name} || die "$name rpm not found");
    install_steps::installPackages ($o, $o->{packages});
}

sub fsck_option() {
    my $y = $::o->{security} < 3 && $::beginner && "-y ";
    substInFile { s/^(\s*fsckoptions=)(-y )?/$1$y/ } "$::o->{prefix}/etc/rc.d/rc.sysinit";
}
