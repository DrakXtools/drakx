package install_any;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

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
	require ftp;
	*install_any::getFile = \&ftp::getFile;
    } elsif ($::o->{method} && $::o->{method} eq "http") {
	require http;
	*install_any::getFile = \&http::getFile;
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

    require pkgs;
    if (is_empty_hash_ref($o->{packages})) {
	my $useHdlist = $o->{method} !~ /nfs|hd/ || $o->{isUpgrade};
	eval { $o->{packages} = pkgs::psUsingHdlist() }  if $useHdlist;
	$o->{packages} = pkgs::psUsingDirectory() if !$useHdlist || $@;

	push @{$o->{default_packages}}, "nfs-utils-clients" if $o->{method} eq "nfs";
	push @{$o->{default_packages}}, "numlock" if $o->{miscellaneous}{numlock};
	push @{$o->{default_packages}}, "kernel-secure" if $o->{security} > 3;
	push @{$o->{default_packages}}, "kernel-smp" if $o->{security} <= 3 && detect_devices::hasSMP(); #- no need for kernel-smp if we have kernel-secure which is smp
	push @{$o->{default_packages}}, "kernel-pcmcia-cs" if $o->{pcmcia};
	push @{$o->{default_packages}}, "raidtools" if !is_empty_hash_ref($o->{raid});

	pkgs::getDeps($o->{packages});

	my $c; ($o->{compss}, $c) = pkgs::readCompss($o->{packages});
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages}, $c, $o->{lang});
	$o->{compssUsers} = pkgs::readCompssUsers($o->{packages}, $o->{compss});

	grep { !$o->{packages}{$_} && log::l("missing base package $_") } @{$o->{base}} and die "missing some base packages";
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
	do {
	    my $p = $o->{packages}{$_} or log::l("missing add-on package $_"), next;
	    pkgs::select($o->{packages}, $p);
	} foreach @{$o->{default_packages}};
    }
}

sub selectPackagesToUpgrade($) {
    my ($o) = @_;

    require pkgs;
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

    $o->{partitioning}{clearall} and return 1;
    $o->ask_warn('', 
_("DiskDrake failed to read correctly the partition table.
Continue at your own risk!")) if !$ok2 && $ok && !$o->{partitioning}{readonly};

    $ok2;
}

sub searchAndMount4Upgrade {
    my ($o) = @_;
    my ($root, $found);

    my $w = $::beginner && $o->wait_message('', _("Searching root partition."));

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
	
    log::l("found root partition : $root->{device}");

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

sub unlockCdrom() {
    cat_("/proc/mounts") =~ m|/tmp/(\S+)\s+/tmp/rhimage|;
    eval { ioctl detect_devices::tryOpen($1), c::CDROM_LOCKDOOR(), 0 };
}
sub ejectCdrom() {
    cat_("/proc/mounts") =~ m|/tmp/(\S+)\s+/tmp/rhimage|;
    my $f = eval { detect_devices::tryOpen($1) } or return;
    getFile("XXX"); #- close still opened filehandle
    eval { fs::umount("/tmp/rhimage") };
    ioctl $f, c::CDROMEJECT(), 1;
}

sub setupFB {
    my ($o, $vga) = @_;

    #- install needed packages for frame buffer.
    require pkgs;
    pkgs::select($o->{packages}, $o->{packages}{'kernel-fb'});
    pkgs::select($o->{packages}, $o->{packages}{'XFree86-FBDev'});
    $o->installPackages($o->{packages});

    $vga ||= 785; #- assume at least 640x480x16.

    require lilo;
    #- update lilo entries with a new fb label. a bit hack unless
    #- a frame buffer kernel is used, in such case we use it instead
    #- with the right mode, nothing more to do.
    foreach (qw(secure smp)) {
	if ($o->{bootloader}{entries}{"/boot/vmlinuz-$_"}) {
	    $o->{bootloader}{entries}{"/boot/vmlinuz-$_"}{vga} = $vga;
	    lilo::install($o->{prefix}, $o->{bootloader});
	    return 1;
	}
    }
    my $root = $o->{bootloader}{entries}{'/boot/vmlinuz'}{root};
    if (lilo::add_kernel($o->{prefix}, $o->{bootloader}, kernelVersion(), 'fb',
			 {
			  label => 'linux-fb',
			  root => $root,
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

    $o->{default_packages} = [ map { $_->{name} } grep { $_->{selected} && !$_->{base} } values %{$::o->{packages}} ];

    my @fields = qw(mntpoint type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(lang autoSCSI authentication printer mouse netc timezone superuser intf keyboard mkbootdisk base users installClass partitioning isUpgrade manualFstab nomouseprobe crypto modem); #- TODO modules bootloader 

    if (my $card = $::o->{X}{card}) {
	$o->{X}{card}{$_} = $card->{$_} foreach qw(default_depth);
	$o->{X}{card}{resolution_wanted} ||= join "x", @{$card->{depth}{$card->{default_depth}}[0]} if $card->{depth};
    }

#-    local $o->{partitioning}{clearall} = 1;

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
	    fs::mount(devices::make("fd0"), "/mnt", "vfat", 0);
	    $f = "/mnt/$f";
	}
	-e $f or $f .= ".pl";

	my $b = before_leaving {
	    fs::umount("/mnt") unless $::testing;
	    modules::unload($_) foreach qw(vfat fat);
	};
	$o = loadO($O, $f);
    } else {
	-e $f or $f .= ".pl";
	{
	    local *F;
	    open F, $f or die _("Error reading file $f");

	    local $/ = "\0";
	    no strict;
	    eval <F>;
	}
	$@ and log::l _("Bad kickstart file %s (failed %s)", $f, $@);
	add2hash_($o ||= {}, $O);
    }
    bless $o, ref $O;
}

sub pkg_install {
    my ($o, $name) = @_;
    require pkgs;
    pkgs::select($o->{packages}, $o->{packages}{$name} || die "$name rpm not found");
    install_steps::installPackages ($o, $o->{packages});
}

sub fsck_option() {
    my $y = $::o->{security} < 3 && $::beginner ? "-y " : "";
    substInFile { s/^(\s*fsckoptions="?)(-y )?/$1$y/ } "$::o->{prefix}/etc/rc.d/rc.sysinit";
}

sub install_urpmi {
    my ($prefix, $method) = @_;

    (my $name = _("installation")) =~ s/\s/_/g; #- in case translators are too good :-/

    my $f = "$prefix/etc/urpmi/hdlist.$name";
    {
	my $fd = getFile("hdlist") or return;
	local *OUT;
	open OUT, ">$f" or log::l("failed to write $f"), return;
	local $/ = \ (16 * 1024);
	print OUT foreach <$fd>;
    }
    {
	local *F = getFile("depslist");
	output("$prefix/etc/urpmi/depslist", <F>);
    }
    {
	local *LIST;
	open LIST, ">$prefix/etc/urpmi/list.$name" or log::l("failed to write list.$name"), return;

	my $dir = ${{ nfs => "file://mnt/nfs", 
		      ftp => $ENV{URLPREFIX}, 
		      http => $ENV{URLPREFIX}, 
		      cdrom => "removable_cdrom_1://mnt/cdrom" }}{$method};
	local *FILES; open FILES, "hdlist2files $f|";
	chop, print LIST "$dir/Mandrake/RPMS/$_\n" foreach <FILES>;
	close FILES or die "hdlist2files failed";

	$dir .= "/Mandrake/RPMS with ../base/hdlist" if $method =~ /ftp|http/;
	eval { output "$prefix/etc/urpmi/urpmi.cfg", "$name $dir\n" };
    }
}

sub list_home($) {
    my ($prefix) = @_;
    local *F; open F, "$prefix/etc/passwd";
    map { $_->[5] } grep { $_->[2] > 501 } map { [ split ':' ] } <F>;
}

sub template2userfile($$$$%) {
    my ($prefix, $inputfile, $outputrelfile, $force, %toreplace) = @_;

    foreach ("/etc/skel", "/root", list_home($prefix)) {
	my $outputfile = "$prefix/$_/$outputrelfile";
	if (-d dirname($outputfile) && ($force || ! -e $outputfile)) {
	    log::l("generating $outputfile from template $inputfile");
	    template2file($inputfile, $outputfile, %toreplace);
	}
    }
}

sub kderc_largedisplay($) {
    my ($prefix) = @_;

    foreach ("/etc/skel", "/root", list_home($prefix)) {
	my ($inputfile, $outputfile) = ("$prefix$_/.kderc", "$prefix$_/.kderc.new");
	my %subst = ( contrast => "Contrast=7\n",
		      kfmiconstyle => "kfmIconStyle=Large\n",
		      kpaneliconstyle => "kpanelIconStyle=Large\n",
		      kdeiconstyle => "KDEIconStyle=Large\n",
		    );

	local *INFILE; local *OUTFILE;
	open INFILE, $inputfile or return;
	open OUTFILE, ">$outputfile" or return;

	print OUTFILE map {
	    if (my $i = /^\s*\[KDE\]/ ... /^\s*\[/) {
		if (/^\s*(\w*)=/ && $subst{lc($1)}) {
		    delete $subst{lc($1)};
		} else {
		    ($i > 1 && /^\s*\[/ && join '', values %subst). $_;
		}
	    } else {
		$_;
	    }
	} <INFILE>;

	unlink $inputfile;
	rename $outputfile, $inputfile;
    }
}

sub kdeicons_postinstall($) {
    my ($prefix) = @_;

    #- parse etc/fstab file to search for dos/win, zip, cdroms icons.
    #- avoid rewriting existing file.
    local *F;
    open F, "$prefix/etc/fstab" or log::l("failed to read $prefix/etc/fstab"), return;

    foreach (<F>) {
	if (/^\/dev\/(\S+)\s+\/mnt\/cdrom (\d*)\s+/x) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "/usr/share/cdrom.kdelnk.in", "Desktop/cdrom$2.kdelnk", 0, %toreplace);
	} elsif (/^\/dev\/(\S+)\s+\/mnt\/zip (\d*)\s+/x) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "/usr/share/zip.kdelnk.in", "Desktop/zip$2.kdelnk", 0, %toreplace);
	} elsif (/^\/dev\/(\S+)\s+\/mnt\/DOS_ (\S*)\s+/x) {
	    my %toreplace = ( device => $1, id => $2 );
	    template2userfile($prefix, "/usr/share/Dos_.kdelnk.in", "Desktop/Dos_$2.kdelnk", 0, %toreplace);
	}
    }
}

1;
