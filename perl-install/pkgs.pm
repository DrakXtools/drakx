package pkgs;

use diagnostics;
use strict;
use vars qw($fd);

use common qw(:common :file);
use install_any;
use log;
use smp;
use fs;

my @skipThesesPackages = qw(XFree86-8514 XFree86-AGX XFree86-FBDev XFree86-Mach32 XFree86-Mach64 
	XFree86-Mach8 XFree86-Mono XFree86-P9000 XFree86-S3 XFree86-S3V
	XFree86-SVGA XFree86-VGA16 XFree86-W32 XFree86-I128 XFree86-Sun 
	XFree86-SunMono XFree86-Xnest postfix
	XFree86-Sun24 XFree86-3DLabs kernel-boot metroess metrotmpl);

1;

sub skipThisPackage { member($_[0], @skipThesesPackages) }


sub Package {
    my ($packages, $name) = @_;
    $packages->{$name} or die "unknown package $name";
}
sub select($$) {
    my ($packages, $name) = @_;
    my $p = Package($packages, $name);
    $p->{selected} = -1; # selected by user
    my @l = @{$p->{deps}};
    while (@l) {
	my $n = shift @l;
	my $i = Package($packages, $n);
	push @l, @{$i->{deps}} unless $i->{selected};
	$i->{selected}++ unless $i->{selected} == -1;
    }
}
sub unselect($$) {
    my ($packages, $name) = @_;
    my $p = Package($packages, $name);
    my $set = set_new($name);
    my $l = $set->{list};

    # get the list of provided packages
    foreach my $q (@$l) {
	my $i = Package($packages, $q);
	$i->{selected} or next;
	$i->{selected} = 1; # that way, its counter will be zero the first time
	set_add($set, @{$i->{provides} || []});
    }

    while (@$l) {
	my $n = shift @$l;
	my $i = Package($packages, $n);

	$i->{selected} <= 0 and next;
	if (--$i->{selected} == 0) {
	    push @$l, @{$i->{deps}};
	}
    }

    # garbage collect for circular dependencies
    my $changed = 1;
    while ($changed) {
	$changed = 0;
      NEXT: foreach my $p (grep { $_->{selected} > 0 } values %$packages) {
	    my $set = set_new(@{$p->{provides}});
	    foreach (@{$set->{list}}) {
		my $q = Package($packages, $_);
		$q->{selected} == -1 and next NEXT;
		set_add($set, @{$q->{provides}}) if $q->{selected};
	    }
	    $p->{selected} = 0;
	    $changed = 1;
	}
    }
}
sub toggle($$) {
    my ($packages, $name) = @_;
    Package($packages, $name)->{selected} ? unselect($packages, $name) : &select($packages, $name);
}
sub set($$$) {
    my ($packages, $name, $val) = @_;
    $val ? &select($packages, $name) : unselect($packages, $name);
}

sub addInfosFromHeader($$;$) {
    my ($packages, $header, $file) = @_;

    my $name = c::headerGetEntry($header, 'name');
    $packages->{$name} = {
        name => $name, file => $file, selected => 0, deps => [],
	header => $header, size => c::headerGetEntry($header, 'size'),
    };
}

sub psUsingDirectory(;$) {
    my ($dirname) = @_;
    my %packages;

    $dirname ||= install_any::imageGetFile('');
    log::l("scanning $dirname for packages");
    foreach (all("$dirname")) {
	my ($name, $version, $release) = /(.*)-([^-]+)-([^-.]+)\.[^.]+\.rpm/ or log::l("skipping $_"), next;
	$packages{$name} = {
            name => $name, version => $version, release => $release,
	    file => "$dirname/$_", selected => 0, deps => [],
        };
    }
    \%packages;
}

sub getDeps($) {
    my ($packages) = @_;

    local *F;
    open F, install_any::imageGetFile("depslist"); # or die "can't find dependencies list";
    foreach (<F>) {
	my ($name, $size, @deps) = split;
	$packages->{$name}->{size} = $size;
	$packages->{$name}->{deps} = \@deps;
	map { push @{$packages->{$_}->{provides}}, $name } @deps;
    }
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
    my ($prefix, $toInstall, $isUpgrade, $force) = @_;

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	local *F;
	open F, $p->{file} or die "error opening package $p->{name} (file $p->{file})";
	$p->{header} = c::rpmReadPackageHeader(fileno F);

	c::rpmtransAddPackage($trans, $p->{header}, $p->{file}, $isUpgrade);
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
