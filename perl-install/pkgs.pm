package pkgs;

use diagnostics;
use strict;

use common qw(:common :file);
use log;
use smp;
use fs;

my @skipList = qw(XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 XFree86-Mach8 XFree86-Mono
		  XFree86-P9000 XFree86-S3 XFree86-S3V XFree86-SVGA XFree86-W32 XFree86-I128
		  XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs kernel-boot
		  metroess metrotmpl);

1;


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

	$packages{lc $name} = { 
	    header => $header, selected => 0, manuallySelected => 0, name => $name,
	    size => c::headerGetEntry($header, 'size'),
	    group => c::headerGetEntry($header, 'group') || "(unknown group)",
	    inmenu => skipPackage($name),
	};
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
		$comps{lc $current{name}} = { %current };
	    } else {
		push @{$current{packages}}, $packages->{lc $_} || log::w "package $_ does not exist (line $n of comps file)";
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
	
	my $name = c::headerGetEntry($header, 'name');

	$packages{lc $name} = { 
	    header => $header, size => c::headerGetEntry($header, 'size'),
	    inmenu => skipPackage($name), name => $name, 
	    group => c::headerGetEntry($header, 'group') || "(unknown group)",
	};

	$noSeek or $end <= sysseek($fd, 0, 1) and last; 
    }

    log::l("psFromHeaderListDesc read " . scalar keys(%packages) . " headers");
    
    \%packages;
}

sub psFromHeaderListFile {
    my ($file) = @_;
    local *F;
    sysopen F, $file, 0 or die "error opening header file: $!";
    psFromHeaderListDesc(\*F, 0);
}

sub skipPackage { member($_[0], @skipList) }

sub printSize { } 
sub printGroup { } 
sub printPkg { } 
sub selectPackagesByGroup { } 
sub showPackageInfo { }
sub queryIndividual { }


sub install {
    my ($rootPath, $method, $packages, $isUpgrade, $force) = @_;

    my $f = "$rootPath/tmp/" . ($isUpgrade ? "upgrade" : "install") . ".log";
    local *F;
    open(F, "> $f") ? log::l("opened $f") : log::l("Failed to open $f. No upgrade log will be kept.");
    my $fd = fileno(F) || log::fd() || 2;
    c::rpmErrorSetCallback($fd);
#    c::rpmSetVeryVerbose();
    
    # FIXME: we ought to read /mnt/us/lib/rpmrc if we're in the midst of an upgrade, but it's not obvious how to get RPM to do that. 
    # if we set netshared path to "" then we get no files installed 
    # addMacro(&globalMacroContext, "_netsharedpath", NULL, netSharedPath ? netSharedPath : "" , RMIL_RPMRC);    
    
    $isUpgrade ? c::rpmdbRebuild($rootPath) : c::rpmdbInit($rootPath, 0644) or die "creation/rebuilding of rpm database failed: ", c::rpmErrorString();

    my $db = c::rpmdbOpen($rootPath) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $rootPath);

    my ($total, $nb);

    foreach my $p ($packages->{basesystem}, 
	     grep { $_->{selected} && $_->{name} ne "basesystem" } values %$packages) {
	my $fullname = sprintf "%s-%s-%s.%s.rpm", 
	                       $p->{name},
	                       map { c::headerGetEntry($p->{header}, $_) } qw(version release arch);
	c::rpmtransAddPackage($trans, $p->{header}, $method->getFile($fullname) , $isUpgrade);
	$nb++;
	$total += $p->{size};
    }

    c::rpmdepOrder($trans) or c::rpmdbClose($db), c::rpmtransFree($trans), die "error ordering package list: ", c::rpmErrorString();
    c::rpmtransSetScriptFd($trans, $fd);

    eval { fs::mount("/proc", "$rootPath/proc", "proc", 0) };

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
