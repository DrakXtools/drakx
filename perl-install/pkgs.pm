package pkgs;

use diagnostics;
use strict;
use vars qw($fd);

use common qw(:common :file :functional);
use install_any;
use log;
use pkgs;
use fs;
use lang;
use c;

1;


sub Package {
    my ($packages, $name) = @_;
    $packages->{$name} or log::l("unknown package $name") && undef;
}

sub select($$;$) {
    my ($packages, $p, $base) = @_;
    $p->{base} ||= $base;
    $p->{selected} = -1; #- selected by user
    my @l = @{$p->{deps} || die "missing deps file"};
    while (@l) {
	my $n = shift @l;
	$n =~ /|/ and $n = first(split '\|', $n); #-TODO better handling of choice
	my $i = Package($packages, $n) or next;
	$i->{base} ||= $base;
	$i->{deps} or log::l("missing deps for $n");
	push @l, @{$i->{deps} || []} unless $i->{selected};
	$i->{selected}++ unless $i->{selected} == -1;
    }
}
sub unselect($$;$) {
    my ($packages, $p, $size) = @_;
    $p->{base} and return;
    my $set = set_new($p->{name});
    my $l = $set->{list};

    #- get the list of provided packages
    foreach my $q (@$l) {
	my $i = Package($packages, $q);
	$i->{selected} && !$i->{base} or next;
	$i->{selected} = 1; #- that way, its counter will be zero the first time
	set_add($set, @{$i->{provides} || []});
    }

    while (@$l) {
	my $n = shift @$l;
	my $i = Package($packages, $n);

	$i->{selected} <= 0 || $i->{base} and next;
	if (--$i->{selected} == 0) {
	    push @$l, @{$i->{deps} || []} if !$size || ($size -= $i->{size}) > 0;
	}
    }
    return if $size <= 0;

    #- garbage collect for circular dependencies
    my $changed = 1;
    while ($changed) {
	$changed = 0;
      NEXT: foreach my $p (grep { $_->{selected} > 0 && !$_->{base} } values %$packages) {
	    my $set = set_new(@{$p->{provides}});
	    foreach (@{$set->{list}}) {
		my $q = Package($packages, $_);
		$q->{selected} == -1 || $q->{base} and next NEXT;
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
             name => $name, header => $header, selected => 0, deps => [],
	     version => c::headerGetEntry($header, 'version'), 
	     release => c::headerGetEntry($header, 'release'),
	     size    => c::headerGetEntry($header, 'size'),
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
    my (@compss, $ps);

    my $f = install_any::getFile("compss") or die "can't find compss";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;
	my ($options, $name) = /^(\S*)\s+(.*?)\s*$/ or log::l("bad line in compss: $_"), next;

	if ($name =~ /(.*):$/) {
	    $ps = [];
	    push @compss, { options => $options, name => $1, packages => $ps };
	} else {
	    my $p = $packages->{$name} or log::l("unknown package $name (in compss)"), next;
	    $p->{options} = $options;
	    push @$ps, $p;
	}
    }
    \@compss;
}

sub readCompssList($) {
    my ($packages) = @_;
    my $level;

    my $f = install_any::getFile("compssList") or die "can't find compssList";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;

	my ($name, @values) = split;

	if ($name eq "package") {
	    $level = \@values;
	} else {
	    my $p = $packages->{$name} or log::l("unknown packages $name (in compssList)"), next;
	    $p->{values} = \@values;
	}
    }
    $level;
}

sub verif_lang($$) {
    my ($p, $lang) = @_;
    local $SIG{__DIE__} = 'none';
    $p->{options} =~ /l/ or return 1;
    $p->{name} =~ /-([^-]*)$/ or return 1;
    !($1 eq $lang || eval { lang::text2lang($1) eq $lang } && !$@);
}

sub setShowFromCompss($$$) {
    my ($compss, $install_class, $lang) = @_;

    my $l = substr($install_class, 0, 1);

    foreach my $c (@$compss) {
	$c->{show} = bool($c->{options} =~ /($l|\*)/);
	foreach my $p (@{$c->{packages}}) {
	    local $_ = $p->{options};
	    $p->{show} = /$l|\*/ && verif_lang($p, $lang);
	}
    }
}

sub setSelectedFromCompssList($$$$$) {
    my ($compssListLevels, $packages, $size, $install_class, $lang) = @_;

    my @packages = values %$packages;
    my @places = do {
	my $ind;
	map_index { $ind = $::i if $_ eq $install_class } @{$compssListLevels};
	defined $ind or log::l("unknown install class $install_class in compssList"), return;

	my @values = map { $_->{values}[$ind] } @packages;
	sort { $values[$b] <=> $values[$a] } 0 .. $#packages;
    };
    foreach (@places) {
	my $p = $packages[$_];
	verif_lang($p, $lang) or next;
	&select($packages, $p);

	my $nb = 0; foreach (@packages) {
	    $nb += $_->{size} if $_->{selected};
	}
	if ($nb > $size) {
	    unselect($packages, $p, $nb - $size);
	    last;
	}
    }
}

sub init_db {
    my ($prefix, $isUpgrade) = @_;

    my $f = "$prefix/root/" . ($isUpgrade ? "upgrade" : "install") . ".log";
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

    return if $::g_auto_install;

    c::rpmReadConfigFiles() or die "can't read rpm config files";

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	getHeader($p) or next;
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

    #- !! do not translate these messages, they are used when catched (cf install_steps_graphical)
    my $callbackOpen = sub { 
	my $fd = install_any::getFile($_[0]) or log::l("bad file $_[0]");
	$fd ? fileno $fd : -1;
    };
    my $callbackClose = sub { };
    my $callbackStart = sub { log::ld("starting installing package ", $_[0]) };
    my $callbackProgress = sub { log::ld("progressing installation ", $_[0], "/", $_[1]) };

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, 
					  $callbackStart, $callbackProgress, $force)) {
	my %parts;
	@probs = reverse grep {
	    if (s/(installing package) .* (needs (?:.*) on the (.*) filesystem)/$1 $2/) {
		$parts{$3} ? 0 : ($parts{$3} = 1);
	    } else { 1; }
	} reverse @probs;
	die "installation of rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans); 
    c::rpmdbClose($db);
    log::l("rpm database closed");
}
