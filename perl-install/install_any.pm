package install_any;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(versionString getNextStep spawnSync spawnShell addToBeDone) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use common qw(:common :system);
use pkgs;
use smp;
use log;

1;

sub relGetFile($) {
    local $_ = member($_[0], qw(compss compssList depslist hdlist)) ? "base" : "RPMS";
    $_ = "Mandrake/$_/$_[0]";
    s/i386/i586/;
    $_;
}
sub getFile($) { 
    open getFile, "/tmp/rhimage/" . relGetFile($_[0]) or return;
    \*getFile;
}

sub versionString {
    local $_ = readlink("$::o->{prefix}/boot/vmlinuz") or die "I couldn't find the kernel package!";
    first(/vmlinuz-(.*)/);
}


sub getNextStep {
    my ($s) = $::o->{steps}{first};
    $s = $::o->{steps}{$s}{next} while $::o->{steps}{$s}{done};
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

    open STDIN, "<&F" or die;
    open STDOUT, ">&F" or die;
    open STDERR, ">&F" or die;
    close F;

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    exec {"/bin/sh"} "-/bin/sh" or log::l("exec of /bin/sh failed: $!");
}

sub mouse_detect() {
    my %l;
    @l{qw(MOUSETYPE XMOUSETYPE DEVICE)} = split("\n", `mouseconfig --nointeractive 2>/dev/null`) or die "mouseconfig failed";
    \%l;
}

sub shells($) {
    my ($o) = @_;
    my @l = grep { -x "$o->{prefix}$_" } @{$o->{shells}};
    @l ? @l : "/bin/bash";
}

sub getAvailableSpace {
    my ($o) = @_;

    do { $_->{mntpoint} eq '/usr' and return $_->{size} << 9 } foreach @{$o->{fstab}};
    do { $_->{mntpoint} eq '/'    and return $_->{size} << 9 } foreach @{$o->{fstab}};

    if ($::testing) {
	log::l("taking 200MB for testing");
	return 200 << 20;
    }
    die "missing root partition";
}

sub setPackages {
    my ($o) = @_;

    unless ($o->{package}) {
	my $useHdlist = $o->{method} !~ /nfs|hd/;
	eval { $o->{packages} = pkgs::psUsingHdlist() }  if $useHdlist;
	$o->{packages} = pkgs::psUsingDirectory() if !$useHdlist || $@;

	pkgs::getDeps($o->{packages});
	
	$o->{compss}     = pkgs::readCompss    ($o->{packages});
	$o->{compssList} = pkgs::readCompssList($o->{packages});
	push @{$o->{base}}, "kernel-smp" if smp::detect();

	do {
	    my $p = $o->{packages}{$_} or log::l(), next;
	    pkgs::select($o->{packages}, $p, 1);
	} foreach @{$o->{base}};
    }	
    
    pkgs::setShowFromCompss($o->{compss}, $o->{installClass}, $o->{lang});
    pkgs::setSelectedFromCompssList($o->{compssList}, $o->{packages}, getAvailableSpace($o) * 0.7, $o->{installClass}, $o->{lang});
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub upgrFindInstall {
#    int rc;
#
#    if (!$::o->{table}.parts) { 
#	 rc = findAllPartitions(NULL, &$::o->{table});
#	 if (rc) return rc;
#    }
#
#    umountFilesystems(&$::o->{fstab});
#    
#    #  rootpath upgrade support 
#    if (strcmp($::o->{rootPath} ,"/mnt"))
#	 return INST_OKAY;
#    
#    #  this also turns on swap for us 
#    rc = readMountTable($::o->{table}, &$::o->{fstab});
#    if (rc) return rc;
#
#    if (!testing) {
#	 mountFilesystems(&$::o->{fstab});
#
#	 if ($::o->{method}->prepareMedia) {
#	     rc = $::o->{method}->prepareMedia($::o->{method}, &$::o->{fstab});
#	     if (rc) {
#		 umountFilesystems(&$::o->{fstab});
#		 return rc;
#	     }
#	 }
#    }
#
#    return 0;
}

sub upgrChoosePackages {
#    static int firstTime = 1;
#    char * rpmconvertbin;
#    int rc;
#    char * path;
#    char * argv[] = { NULL, NULL };
#    char buf[128];
#
#    if (testing)
#	 path = "/";
#    else
#	 path = $::o->{rootPath};
#
#    if (firstTime) {
#	 snprintf(buf, sizeof(buf), "%s%s", $::o->{rootPath},
#		  "/var/lib/rpm/packages.rpm");
#	 if (access(buf, R_OK)) {
#	 snprintf(buf, sizeof(buf), "%s%s", $::o->{rootPath},
#		  "/var/lib/rpm/packages");
#	     if (access(buf, R_OK)) {
#		 errorWindow("No RPM database exists!");
#		 return INST_ERROR;
#	     }
#
#	     if ($::o->{method}->getFile($::o->{method}, "rpmconvert", 
#		     &rpmconvertbin)) {
#		 return INST_ERROR;
#	     }
#
#	     symlink("/mnt/var", "/var");
#	     winStatus(35, 3, _("Upgrade"), _("Converting RPM database..."));
#	     chmod(rpmconvertbin, 0755);
#	     argv[0] = rpmconvertbin;
#	     rc = runProgram(RUN_LOG, rpmconvertbin, argv);
#	     if ($::o->{method}->rmFiles)
#		 unlink(rpmconvertbin);
#
#	     newtPopWindow();
#	     if (rc) return INST_ERROR;
#	 }
#	 winStatus(35, 3, "Upgrade", _("Finding packages to upgrade..."));
#	 rc = ugFindUpgradePackages(&$::o->{packages}, path);
#	 newtPopWindow();
#	 if (rc) return rc;
#	 firstTime = 0;
#	 psVerifyDependencies(&$::o->{packages}, 1);
#    }
#
#    return psSelectPackages(&$::o->{packages}, &$::o->{compss}, NULL, 0, 1);
}
