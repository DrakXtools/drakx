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
use common qw(:common :system :functional);
use commands;
use run_program;
use partition_table qw(:types);
use fsedit;
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
      (member($_, qw(compss compssList depslist hdlist)) ? "base" : "RPMS");
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
	    \*getFile;
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

sub setPackages($$) {
    my ($o, $install_classes) = @_;

    if ($o->{packages}) {
	$_->{selected} = 0 foreach values %{$o->{packages}};
    } else {
	my $useHdlist = $o->{method} !~ /nfs|hd/ || $o->{isUpgrade};
	eval { $o->{packages} = pkgs::psUsingHdlist() }  if $useHdlist;
	$o->{packages} = pkgs::psUsingDirectory() if !$useHdlist || $@;

	pkgs::getDeps($o->{packages});

	my $c; ($o->{compss}, $c) = pkgs::readCompss($o->{packages});
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages}, $c);
	$o->{compssListLevels} ||= $install_classes;
	push @{$o->{base}}, "kernel-smp" if detect_devices::hasSMP();
	push @{$o->{base}}, "kernel-pcmcia-cs" if $o->{pcmcia};
    }

    #- this will be done if necessary in the selectPackagesToUpgrade,
    #- move the selection here ? this will remove the little window.
    unless ($o->{isUpgrade}) {
	do {
	    my $p = $o->{packages}{$_} or log::l("missing base package $_"), next;
	    pkgs::select($o->{packages}, $p, 1);
	} foreach @{$o->{base}};
    }

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

sub install_cpio($$) {
    my ($dir, $name) = @_;

    return "$dir/$name" if -e "$dir/$name";

    my $cpio = "$dir.cpio.bz2";
    -e $cpio or return;

    eval { commands::rm("-r", $dir) };
    mkdir $dir, 0755;
    run_program::run("cd $dir ; bzip2 -cd $cpio | cpio -id $name $name/*");
    "$dir/$name";
}

sub getHds {
    my ($o) = @_;
    my ($ok, $ok2) = 1;

  getHds: 
    $o->{hds} = catch_cdie { fsedit::hds([ detect_devices::hds() ], $o->{partitioning}) }
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
