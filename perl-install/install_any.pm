package install_any;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(versionString getNextStep doSuspend spawnSync spawnShell) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use common qw(:common :system);
use log;

1;

sub fileInBase { member($_[0], qw(compss depslist)); }

sub imageGetFile { 
    fileInBase($_[0]) and return "/tmp/rhimage/Mandrake/base/$_[0]";
    my $f = "/tmp/rhimage/Mandrake/RPMS/$_[0]";
    -r $f and return $f;
    $f =~ s/i386/i586/;
    $f;
}

sub versionString {
    my $kernel = $::o->{packages}->{kernel};
    $kernel && $kernel->{header} or die "I couldn't find the kernel package!";
    
    c::headerGetEntry($kernel->{header}, 'version') . "-" .
    c::headerGetEntry($kernel->{header}, 'release');
}


sub getNextStep {
    my ($lastStep) = @_;

    $::o->{direction} = 1;

    return $::o->{lastChoice} = $::o->{steps}->{$lastStep}->{next};
}

sub doSuspend {
    exit 1 if $::o->{localInstall} || $::testing;

    if (my $pid = fork) {
	waitpid $pid, 0;
    } else {
	print "\n\nType <exit> to return to the install program.\n\n";
	exec {"/bin/sh"} "-/bin/sh";
	warn "error execing /bin/sh";
	sleep 5;
	exit 1;
    }
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
    my ($type, $dev) = split("\n", `mouseconfig --nointeractive 2>/dev/null`) or die "mouseconfig failed";
    $type, $dev;
}

sub shells($) {
    my ($o) = @_;
    grep { -x "$o->{prefix}$_" } @{$o->{default}->{shells}};
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
