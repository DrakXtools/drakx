package install_any;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(versionString getNextStep spawnSync spawnShell addToBeDone) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system);
use run_program;
use detect_devices;
use pkgs;
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
	    print ">>>>>> /tmp/rhimage/" . relGetFile($_[0]), "\n";
	    open getFile, "/tmp/rhimage/" . relGetFile($_[0]) or sleep(1000), return;
	    \*getFile;
	};
    }
    goto &getFile;
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

    open STDIN, "<&F" or die '';
    open STDOUT, ">&F" or die '';
    open STDERR, ">&F" or die '';
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

sub setPackages($$) {
    my ($o, $install_classes) = @_;

    unless ($o->{packages}) {
	my $useHdlist = $o->{method} !~ /nfs|hd/;
	eval { $o->{packages} = pkgs::psUsingHdlist() }  if $useHdlist;
	$o->{packages} = pkgs::psUsingDirectory() if !$useHdlist || $@;

	pkgs::getDeps($o->{packages});
	
	$o->{compss}     = pkgs::readCompss    ($o->{packages});
	$o->{compssListLevels} = pkgs::readCompssList($o->{packages});
	$o->{compssListLevels} ||= $install_classes;
	push @{$o->{base}}, "kernel-smp" if detect_devices::hasSMP();

	do {
	    my $p = $o->{packages}{$_} or log::l(), next;
	    pkgs::select($o->{packages}, $p, 1);
	} foreach @{$o->{base}};
    }
    
    pkgs::setShowFromCompss($o->{compss}, $o->{installClass}, $o->{lang});
    pkgs::setSelectedFromCompssList($o->{compssListLevels}, $o->{packages}, getAvailableSpace($o) * 0.7, $o->{installClass}, $o->{lang});
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub install_cpio {
    my ($dir, $name) = @_;

    return "$dir/$name" if -e "$dir/$name";

    my $cpio = "$dir.cpio.bz2";
    -e $cpio or return;

    eval { commands::rm "-r", $dir };
    mkdir $dir, 0755;
    run_program::run("cd $dir ; bzip2 -cd $cpio | cpio -id $name $name/*");
    "$dir/$name";
}
