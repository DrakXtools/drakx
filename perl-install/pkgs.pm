package pkgs;

use diagnostics;
use strict;
use vars qw($fd);

use common qw(:common :file);
use log;
use smp;
use fs;

my @skipThesesPackages = qw(XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 
	XFree86-Mach8 XFree86-Mono XFree86-P9000 XFree86-S3 XFree86-S3V
	XFree86-SVGA XFree86-W32 XFree86-I128 XFree86-Sun XFree86-SunMono
	XFree86-Sun24 XFree86-3DLabs kernel-boot metroess metrotmpl);

1;

sub skipThisPackage { member($_[0], @skipThesesPackages) }

sub addInfosFromHeader($$) {
    my ($packages, $header) = @_;

    my $name = c::headerGetEntry($header, 'name');
    $packages->{$name} = {
        name => $name,
	header => $header, size => c::headerGetEntry($header, 'size'),
	group => c::headerGetEntry($header, 'group') || "(unknown group)",
    };
}

sub psUsingDirectory {
    my ($dirname) = @_;
    my %packages;

    log::l("scanning $dirname for packages");
    foreach (glob_("$dirname/*.rpm")) {
	my $basename = basename($_);
	local *F;
	open F, $_ or log::l("failed to open package $_: $!");
	my $header = c::rpmReadPackageHeader($_) or log::l("failed to rpmReadPackageHeader $basename: $!");
	my $name = c::headerGetEntry($header, 'name');
	addInfosFromHeader(\%packages, $header);
    }
    \%packages;
}

sub psReadComponentsFile {
    my ($compsfile, $packages) = @_;
    my (%comps, %current);

    local *F;
    open F, $compsfile or die "Cannot open components file: $!";

    <F> =~ /^0(\.1)?$/ or die "Comps file is not version 0.1 as expected";

    my $inComp = 0;
    my $n = 0;
    foreach (<F>) { $n++;
	chomp;
	s/^ +//;
	/^#/ and next;
	/^$/ and next;

	if ($inComp) { if (/^end$/) {
		$inComp = 0;
		$comps{$current{name}} = { %current };
	    } else {
		$packages->{$_} ? 
		  push @{$current{packages}}, $packages->{$_} :
		  log::w("package $_ does not exist (line $n of comps file)");
	    }
	} else {
	    my ($selected, $hidden, $name) = /^([01])\s*(--hide)?\s*(.*)/ or die "bad comps file at line $n";
	    %current = (selected => $selected, inmenu => !$hidden, name => $name);
	    $inComp = 1;
	}
    }
    log::l("read " . (scalar keys %comps) . " comps");
    \%comps;
}



sub psVerifyDependencies {
#    my ($packages, $fixup) = @_;
#
#    -r "/mnt/var/lib/rpm/packages.rpm" or die "can't find packages.rpm";
#
#    my $db = rpmdbOpenRWCreate("/mnt");
#    my $rpmdeps = rpmtransCreateSet($db, undef);
#
#    foreach (values %$packages) {
#	 $_->{selected} ?
#	     c::rpmtransAddPackage($rpmdeps, $_->{header}, undef, $_, 0, undef) :
#	     c::rpmtransAvailablePackage($rpmdeps, $_->{header}, $_);
#    }
#    my @conflicts = c::rpmdepCheck($rpmdeps);
#
#    rpmtransFree($rpmdeps);
#    rpmdbClose($db);
#
#    if ($fixup) {
#	 foreach (@conflicts) {
#	     $_->{suggestedPackage}->{selected} = 1;
#	 }
#	 rpmdepFreeConflicts(@conflicts);
#    }
#
#    1;
}

sub selectComponents {
    my ($csp, $psp, $doIndividual) = @_;

    return 0;
}

sub psFromHeaderListDesc {
    my ($fd, $noSeek) = @_;
    my %packages;
    my $end;

    unless ($noSeek) {
	my $current = sysseek $fd, 0, 1 or die "seek failed";
	$end = sysseek $fd, 0, 2 or die "seek failed";
	sysseek $fd, $current, 0 or die "seek failed";
    }

    while (1) {
	my $header = c::headerRead(fileno($fd), 1);
	unless ($header) {
	    $noSeek and last;
	    die "error reading header at offset ", sysseek($fd, 0, 1);
	}
	addInfosFromHeader(\%packages, $header);
	$noSeek or $end <= sysseek($fd, 0, 1) and last; 
    }

    log::l("psFromHeaderListDesc read " . scalar keys(%packages) . " headers");
    
    \%packages;
}

sub psFromHeaderListFile {
    my ($file) = @_;
    local *F;
    sysopen F, $file, 0 or die "error opening header file $file: $!";
    psFromHeaderListDesc(\*F, 0);
}

sub init_db {
    my ($prefix, $isUpgrade) = @_;

    my $f = "$prefix/tmp/" . ($isUpgrade ? "upgrade" : "install") . ".log";
    open(F, "> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept.");
    $fd = fileno(F) || log::fd() || 2;
    c::rpmErrorSetCallback($fd);
#    c::rpmSetVeryVerbose();
    
    $isUpgrade ? c::rpmdbRebuild($prefix) : c::rpmdbInit($prefix, 0644) or die "creation/rebuilding of rpm database failed: ", c::rpmErrorString();
}

sub install {
    my ($prefix, $method, $toInstall, $isUpgrade, $force) = @_;

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	my $fullname = sprintf "%s-%s-%s.%s.rpm", 
	                       map { c::headerGetEntry($p->{header}, $_) } qw(name version release arch);
	c::rpmtransAddPackage($trans, $p->{header}, $method->getFile($fullname) , $isUpgrade);
	$nb++;
	$total += $p->{size};
    }

    c::rpmdepOrder($trans) or c::rpmdbClose($db), c::rpmtransFree($trans), die "error ordering package list: ", c::rpmErrorString();
    c::rpmtransSetScriptFd($trans, $fd);

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) };

    log::ld("starting installation: ", $nb, " packages, ", $total, " bytes");

    # !! do not translate these messages, they are used when catched (cf install_steps_graphical)
    my $callbackStart = sub { log::ld("starting installing package ", $_[0]) };
    my $callbackProgress = sub { log::ld("progressing installation ", $_[0], "/", $_[1]) };

    if (my @probs = c::rpmRunTransactions($trans, $callbackStart, $callbackProgress, $force)) {
	die "installation of rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans); 
    c::rpmdbClose($db);
    log::l("rpm database closed");
}
