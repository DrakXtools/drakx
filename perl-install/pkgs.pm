package pkgs;

use diagnostics;
use strict;
use vars qw($fd);

use common qw(:common :file);
use install_any;
use log;
use smp;
use fs;
use lang;

my @skipThesesPackages = qw(XFree86-8514 XFree86-AGX XFree86-FBDev XFree86-Mach32 XFree86-Mach64 
	XFree86-Mach8 XFree86-Mono XFree86-P9000 XFree86-S3 XFree86-S3V
	XFree86-SVGA XFree86-VGA16 XFree86-W32 XFree86-I128 XFree86-Sun 
	XFree86-SunMono XFree86-Xnest postfix
	XFree86-Sun24 XFree86-3DLabs kernel-boot metroess metrotmpl);

1;

sub skipThisPackage { member($_[0], @skipThesesPackages) }

sub Package {
    my ($packages, $name) = @_;
    $packages->{$name} ;# or die "unknown package $name"; hack hack :(
}

sub select($$;$) {
    my ($packages, $p, $base) = @_;
    $p->{selected} = -1; # selected by user
    unless ($p->{deps}) {
	1;
    }
    my @l = @{$p->{deps}};
    while (@l) {
	my $n = shift @l;
	$n =~ /|/ and $n = first(split '\|', $n); #TODO better handling of choice
	my $i = Package($packages, $n);
	$i->{base} ||= $base;
	$i->{deps} or log::l("missing deps for $n");
	push @l, @{$i->{deps} || []} unless $i->{selected};
	$i->{selected}++ unless $i->{selected} == -1;
    }
}
sub unselect($$) {
    my ($packages, $p) = @_;
    $p->{base} and return;
    my $set = set_new($p->{name});
    my $l = $set->{list};

    # get the list of provided packages
    foreach my $q (@$l) {
	my $i = Package($packages, $q);
	$i->{selected} && !$i->{base} or next;
	$i->{selected} = 1; # that way, its counter will be zero the first time
	set_add($set, @{$i->{provides} || []});
    }

    while (@$l) {
	my $n = shift @$l;
	my $i = Package($packages, $n);

	$i->{selected} <= 0 || $i->{base} and next;
	if (--$i->{selected} == 0) {
	    push @$l, @{$i->{deps} || []};
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
    my ($packages, $p) = @_;
    $p->{selected} ? unselect($packages, $p) : &select($packages, $p);
}
sub set($$$) {
    my ($packages, $p, $val) = @_;
    $val ? &select($packages, $p) : unselect($packages, $p);
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

sub chop_version($) { 
    first($_[0] =~ /(.*)-[^-]+-[^-.]+/) || $_[0];
}

sub getDeps($) {
    my ($packages) = @_;

    local *F;
    open F, install_any::imageGetFile("depslist") or die "can't find dependencies list";
    foreach (<F>) {
	my ($name, $size, @deps) = split;
	($name, @deps) = map { chop_version($_) } ($name, @deps);
	$packages->{$name} or next;
	$packages->{$name}{size} = $size;
	$packages->{$name}{deps} = \@deps;
	map { push @{$packages->{$_}{provides}}, $name if $packages->{$_} } @deps;
    }
}

sub readCompss($) {
    my ($packages) = @_;
    my (@compss, $ps, $category);

    local *F;
    open F, install_any::imageGetFile("compss") or die "can't find compss";
    foreach (<F>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;
	my ($options, $name) = /^(\S*)\s+(.*?)\s*$/ or die "bad line in compss: $_";

	if ($name =~ /(.*):$/) {
	    if ($category) {
		push @compss, $category;
		$ps = [];
	    }
	    $category = { options => $options, name => $1, packages => $ps };
	} else {
	    my $p = $packages->{$name} or log::l("unknown package $name (in compss)"), next;
	    $p->{options} = $options;
	    push @$ps, $p;
	}
    }
    [ @compss, $category ];
}

sub setCompssSelected($$$) {
    my ($compss, $packages, $install_class, $select) = @_;

    my $l = substr($install_class, 0, 1);
    my $L = uc $l;

    my $verif_lang = sub {
	local $SIG{__DIE__} = 'none';
	$_[0] =~ /-([^-]*)$/;
	$1 eq $ENV{LANG} || eval { lang::text2lang($1) eq $ENV{LANG} } && !$@;
    };

    foreach my $c (@$compss) {
	$c->{show} = bool($c->{options} =~ /($l|\*)/);
	my $nb = 0;
	foreach my $p (@{$c->{packages}}) {
	    local $_ = $p->{options};
	    $p->{show} = ! (/$L/);

	    &select($packages, $p, $p->{base}), $nb++ 
	      if /$l|\*/ && (!/l/ || &$verif_lang($p->{name})) ||
		 $p->{base};
	}
	$c->{selected} = $nb;
    }
}

sub addHdlistInfos {
    my ($fd, $noSeek) = @_;
    my %packages;
    my $end;
    my $file;
    local *F;
    sysopen F, $file, 0 or die "error opening header file $file: $!";

    $end = sysseek $fd, 0, 2 or die "seek failed";
    sysseek $fd, 0, 0 or die "seek failed";

    while (sysseek($fd, 0, 1) <= $end) {
	my $header = c::headerRead(fileno($fd), 1);
	unless ($header) {
	    $noSeek and last;
	    die "error reading header at offset ", sysseek($fd, 0, 1);
	}

	c::headerGetEntry($header, 'name');

	$noSeek or $end <= sysseek($fd, 0, 1) and last; 
    }

    log::l("psFromHeaderListDesc read " . scalar keys(%packages) . " headers");
    
    \%packages;
}

sub init_db {
    my ($prefix, $isUpgrade) = @_;

    my $f = "$prefix/tmp/" . ($isUpgrade ? "upgrade" : "install") . ".log";
    open(F, "> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept.");
    $fd = fileno(F) || log::fd() || 2;
    c::rpmErrorSetCallback($fd);
#    c::rpmSetVeryVerbose();
    
    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    $isUpgrade ? c::rpmdbRebuild($prefix) : c::rpmdbInit($prefix, 0644) or die "creation/rebuilding of rpm database failed: ", c::rpmErrorString();
}

sub getHeader($) {
    my ($p) = @_;

    unless ($p->{header}) {
	local *F;
	open F, $p->{file} or die "error opening package $p->{name} (file $p->{file})";
	$p->{header} = c::rpmReadPackageHeader(fileno F);
    }
    $p->{header};
}

sub install {
    my ($prefix, $toInstall, $isUpgrade, $force) = @_;

    c::rpmReadConfigFiles() or die "can't read rpm config files";

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	$p->{installed} = 1;
	c::rpmtransAddPackage($trans, getHeader($p), $p->{file}, $isUpgrade);
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
