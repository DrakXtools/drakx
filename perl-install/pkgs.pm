package pkgs;

use diagnostics;
use strict;
use vars qw($fd);

use common qw(:common :file);
use install_any;
use log;
use smp;
use pkgs;
use fs;
use lang;

1;


sub Package {
    my ($packages, $name) = @_;
    $packages->{$name} or log::l("unknown package $name") && undef;
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
	my $i = Package($packages, $n) or next;
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

sub psUsingDirectory() {
    my $dirname = "/tmp/rhimage/Mandrake/RPMS";
    my %packages;

    log::l("scanning $dirname for packages");
    foreach (all("$dirname")) {
	my ($name, $version, $release) = /(.*)-([^-]+)-([^-.]+)\.[^.]+\.rpm/ or log::l("skipping $_"), next;

	$packages{$name} = {
            name => $name, version => $version, release => $release,
	    file => $_, selected => 0, deps => [],
        };
    }
    \%packages;
}

sub psUsingHdlist() {
    my $f = install_any::getFile('hdlist') or die "no hdlist found";
    my %packages;

#    my ($noSeek, $end) = 0;
#    $end = sysseek F, 0, 2 or die "seek failed";
#    sysseek F, 0, 0 or die "seek failed";

    while (my $header = c::headerRead(fileno $f, 1)) {
#	 or die "error reading header at offset ", sysseek(F, 0, 1);
	my $name = c::headerGetEntry($header, 'name');

	$packages{$name} = {
             name => $name, version => c::headerGetEntry($header, 'version'), release => c::headerGetEntry($header, 'release'),
	     header => $header, selected => 0, deps => [],
        };
    }
    log::l("psUsingHdlist read " . scalar keys(%packages) . " headers");
    
    \%packages;
}

sub chop_version($) { 
    first($_[0] =~ /(.*)-[^-]+-[^-.]+/) || $_[0];
}

sub getDeps($) {
    my ($packages) = @_;

    my $f = install_any::getFile("depslist") or die "can't find dependencies list";
    foreach (<$f>) {
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

    my $f = install_any::getFile("compss") or die "can't find compss";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;
	my ($options, $name) = /^(\S*)\s+(.*?)\s*$/ or die "bad line in compss: $_";

	if ($name =~ /(.*):$/) {
	    push @compss, $category if $category;
	    $ps = [];
	    $category = { options => $options, name => $1, packages => $ps };
	} else {
	    my $p = $packages->{$name} or log::l("unknown package $name (in compss)"), next;
	    $p->{options} = $options;
	    push @$ps, $p;
	}
    }
    [ @compss, $category ];
}

sub setCompssSelected($$$$) {
    my ($compss, $packages, $install_class, $lang) = @_;

    my $l = substr($install_class, 0, 1);
    my $L = uc $l;

    my $verif_lang = sub {
	local $SIG{__DIE__} = 'none';
	$_[0] =~ /-([^-]*)$/;
	$1 eq $lang || eval { lang::text2lang($1) eq $lang } && !$@;
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
	my $f = install_any::getFile($p->{file}) or die "error opening package $p->{name} (file $p->{file})";
	$p->{header} = c::rpmReadPackageHeader(fileno $f);
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
	$p->{file} ||= sprintf "%s-%s-%s.%s.rpm",
	                       $p->{name}, $p->{version}, $p->{release}, 
			       c::headerGetEntry(getHeader($p), 'arch');
	c::rpmtransAddPackage($trans, getHeader($p), $p->{file}, $isUpgrade);
	$nb++;
	$total += $p->{size};
    }

    c::rpmdepOrder($trans) or c::rpmdbClose($db), c::rpmtransFree($trans), die "error ordering package list: ", c::rpmErrorString();
    c::rpmtransSetScriptFd($trans, $fd);

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) };

    log::ld("starting installation: ", $nb, " packages, ", $total, " bytes");

    # !! do not translate these messages, they are used when catched (cf install_steps_graphical)
    my $callbackOpen = sub { fileno install_any::getFile($_[0]) || log::l("bad file $_[0]") };
    my $callbackClose = sub { };
    my $callbackStart = sub { log::ld("starting installing package ", $_[0]) };
    my $callbackProgress = sub { log::ld("progressing installation ", $_[0], "/", $_[1]) };

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, 
					  $callbackStart, $callbackProgress, $force)) {
	die "installation of rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans); 
    c::rpmdbClose($db);
    log::l("rpm database closed");
}
