package pkgs;

use diagnostics;
use strict;
use vars qw(*LOG);

use common qw(:common :file :functional);
use install_any;
use log;
use pkgs;
use fs;
use lang;
use c;

my @skip_list = qw(
XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 XFree86-Mach8 XFree86-Mono
XFree86-P9000 XFree86-S3 XFree86-S3V XFree86-SVGA XFree86-W32 XFree86-I128
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs kernel-BOOT
MySQL MySQL_GPL mod_php3 midgard postfix metroess metrotmpl
hackkernel hackkernel-BOOT hackkernel-fb hackkernel-headers
hackkernel-pcmcia-cs hackkernel-smp hackkernel-smp-fb autoirpm
);

my @preferred = qw(

);


my $A = 20471;
my $B = 16258;
sub correctSize { ($A - $_[0]) * $_[0] / $B } #- size correction in MB.
sub invCorrectSize { $A / 2 - sqrt(sqr($A) - 4 * $B * $_[0]) / 2 }

sub Package {
    my ($packages, $name) = @_;
    $packages->{$name} or log::l("unknown package `$name'") && undef;
}

sub allpackages {
    my ($packages) = @_;
    my %skip_list; @skip_list{@skip_list} = ();
    grep { !exists $skip_list{$_->{name}} } values %$packages;
}

sub select($$;$) {
    my ($packages, $p, $base) = @_;
    my ($n, $v);
    unless ($p->{installed}) { #- if the same or better version is installed, do not select.
	$p->{base} ||= $base;
	$p->{selected} = -1; #- selected by user
	my %l; @l{@{$p->{deps} || die "missing deps file"}} = ();
	while (do { my %l = %l; while (($n, $v) = each %l) { last if $v != 1; } $n }) {
	    $l{$n} = 1;
	    my $i = $packages->{$n};
	    if (!$i && $n =~ /\|/) {
		foreach (split '\|', $n) {
		    $i = Package($packages, $_);
		    last if $i && $i->{selected};
		}
	    }
	    $i->{base} ||= $base;
	    $i->{deps} or log::l("missing deps for $n");
	    unless ($i->{installed}) {
		unless ($i->{selected}) {
		    $l{$_} ||= 0 foreach @{$i->{deps} || []};
		}
		$i->{selected}++ unless $i->{selected} == -1;
	    }
	}
    }
    1;
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
    return if defined $size && $size <= 0;

#-    #- garbage collect for circular dependencies
#-    my $changed = 0; #1;
#-    while ($changed) {
#-	  $changed = 0;
#-	NEXT: foreach my $p (grep { $_->{selected} > 0 && !$_->{base} } values %$packages) {
#-	      my $set = set_new(@{$p->{provides}});
#-	      foreach (@{$set->{list}}) {
#-		  my $q = Package($packages, $_);
#-		  $q->{selected} == -1 || $q->{base} and next NEXT;
#-		  set_add($set, @{$q->{provides}}) if $q->{selected};
#-	      }
#-	      $p->{selected} = 0;
#-	      $changed = 1;
#-	  }
#-    }
}
sub toggle($$) {
    my ($packages, $p) = @_;
    $p->{selected} ? unselect($packages, $p) : &select($packages, $p);
}
sub set($$$) {
    my ($packages, $p, $val) = @_;
    $val ? &select($packages, $p) : unselect($packages, $p);
}

sub unselect_all($) {
    my ($packages) = @_;
    $_->{selected} = $_->{base} foreach values %$packages;
}

sub psUsingDirectory() {
    my $dirname = "/tmp/rhimage/Mandrake/RPMS";
    my %packages;

    log::l("scanning $dirname for packages");
    foreach (all("$dirname")) {
	my ($name, $version, $release) = /(.*)-([^-]+)-([^-]+)\.[^.]+\.rpm/ or log::l("skipping $_"), next;

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
	     version   => c::headerGetEntry($header, 'version'),
	     release   => c::headerGetEntry($header, 'release'),
	     size      => c::headerGetEntry($header, 'size'),
        };
    }
    log::l("psUsingHdlist read " . scalar keys(%packages) . " headers");

    \%packages;
}

sub chop_version($) {
    first($_[0] =~ /(.*)-[^-]+-[^-]+/) || $_[0];
}

sub getDeps($) {
    my ($packages) = @_;

    my $f = install_any::getFile("depslist") or die "can't find dependencies list";
    foreach (<$f>) {
	my ($name, $size, @deps) = split;
	($name, @deps) = map { join '|', map { chop_version($_) } split '\|' } ($name, @deps);
	$packages->{$name} or next;
	$packages->{$name}{size} = $size;
	$packages->{$name}{deps} = \@deps;
	map { push @{$packages->{$_}{provides}}, $name if $packages->{$_} } @deps;
    }
}

sub category2packages($) {
    my ($p) = @_;
    $p->{packages} || [ map { @{ category2packages($_) } } values %{$p->{childs}} ];
}

sub readCompss($) {
    my ($packages) = @_;
    my ($compss, $compss_, $ps) = { childs => {} };

    my $f = install_any::getFile("compss") or die "can't find compss";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S+)/) {
	    my $p = $compss;
	    my @l = split ':', $1;
	    pop @l if $l[-1] =~ /^(x11|console)$/;
	    foreach (@l) {
		$p->{childs}{$_} ||= { childs => {} };
		$p = $p->{childs}{$_};
	    }
	    $ps = $p->{packages} ||= [];
	    $compss_->{$1} = $p;
	} else {
	    /(\S+)/ or log::l("bad line in compss: $_"), next;
	    push @$ps, $packages->{$1} || do { log::l("unknown package $1 (in compss)"); next };
	}
    }
    ($compss, $compss_);
}

sub readCompssList($$$) {
    my ($packages, $compss_, $lang) = @_;
    my ($r, $s) = ('', '');
    if ($lang) { 
	local $SIG{__DIE__} = 'none';
	my ($l) = split ' ', lang::lang2text($lang);
	$r = "($lang";
	$r .= "|$1" if $lang =~ /(..)./;
	$r .= "|$l" if $l;
	$r .= ")";
    }
    my $f = install_any::getFile("compssList") or die "can't find compssList";
    local $_ = <$f>;
    my $level = [ split ];

    my $e;
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;

	/^packages\s*$/ and do { $e = $packages; $s = '-'; next };
	/^categories\s*$/ and do { $e = $compss_; $s = ':'; next };

	my ($name, @values) = split;

	$e or log::l("neither packages nor categories");
	my $p = $e->{$name} or log::l("unknown entry $name (in compssList)"), next;

	@values = map { $_ + 68 } @values if $name =~ /$s$r$/i;
	$p->{values} = \@values;
    }
    $level;
}

sub readCompssUsers {
    my ($packages, $compss) = @_;
    my (%compssUsers, $l);

    my $f = install_any::getFile("compssUsers") or die "can't find compssUsers";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    $compssUsers{$1} = $l = [];
	} elsif (/\s+\+(.*)/) {
	    push @$l, $packages->{$1} || do { log::l("unknown package $1 (in compssUsers)"); next };
	} elsif (/\s+(.*)/) {
	    my $p = $compss;
	    $p &&= $p->{childs}{$_} foreach split ':', $1;
	    $p or log::l("unknown category $1 (in compssUsers)"), next;
	    push @$l, @{ category2packages($p) };
	}
    }
    \%compssUsers;
}

sub isLangSensitive($$) {
    my ($name, $lang) = @_;
    local $SIG{__DIE__} = 'none';
    $name =~ /-([^-]*)$/ or return;
    $1 eq $lang || eval { lang::text2lang($1) eq $lang } && !$@;
}

sub setSelectedFromCompssList($$$$$$) {
    my ($compssListLevels, $packages, $size, $install_class, $lang, $isUpgrade) = @_;
    my ($level, $ind) = 100;

    my @packages = allpackages($packages);
    my @places = do {
	map_index { $ind = $::i if $_ eq $install_class } @{$compssListLevels};
	defined $ind or log::l("unknown install class $install_class in compssList"), return;

	my @values = map { $_->{values}[$ind] } @packages;
	sort { $values[$b] <=> $values[$a] } 0 .. $#packages;
    };
    foreach (@places) {
	my $p = $packages[$_];
	$level = min($level, $p->{values}[$ind]);
	last if $level == 0;

	&select($packages, $p) unless $isUpgrade;

	my $nb = 0; foreach (@packages) {
	    $nb += $_->{size} if $_->{selected};
	}
	if ($nb > $size) {
	    unselect($packages, $p, $nb - $size) unless $isUpgrade;
	    last;
	}
    }
    $ind, $level;
}

sub init_db {
    my ($prefix, $isUpgrade) = @_;

    my $f = "$prefix/root/install.log";
    open(LOG, "> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept.");
    *LOG or *LOG = log::F() or *LOG = *STDERR;
    CORE::select((CORE::select(LOG), $| = 1)[0]);
    c::rpmErrorSetCallback(fileno LOG);
#-    c::rpmSetVeryVerbose();

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    if ($isUpgrade) {
	c::rpmdbRebuild($prefix) or die "rebuilding of rpm database failed: ", c::rpmErrorString();
    }

    c::rpmdbInit($prefix, 0644) or die "creation of rpm database failed: ", c::rpmErrorString();
#-    $isUpgrade ? c::rpmdbRebuild($prefix) : c::rpmdbInit($prefix, 0644) or die "creation/rebuilding of rpm database failed: ", c::rpmErrorString();
}

sub done_db {
    log::l("closing install.log file");
    close LOG;
}

sub getHeader($) {
    my ($p) = @_;

    unless ($p->{header}) {
	my $f = install_any::getFile($p->{file}) or die "error opening package $p->{name} (file $p->{file})";
	$p->{header} = c::rpmReadPackageHeader(fileno $f) or die "bad package $p->{name}";
    }
    $p->{header};
}

sub selectPackagesToUpgrade($$$) {
    my ($packages, $prefix, $base) = @_;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpenForTraversal($prefix) or die "unable to open $prefix/var/lib/rpm/packages.rpm";
    my %installedFilesForUpgrade; #- help searching package to upgrade in regard to already installed files.

    #- mark all files which are not in /etc/rc.d/ for packages which are already installed but which
    #- are not in the packages list to upgrade.
    #- the 'installed' property will make a package unable to be selected, look at select.
    c::rpmdbTraverse($db, sub {
			 my ($header) = @_;
			 my $p = $packages->{c::headerGetEntry($header, 'name')};
			 if ($p) {
			     eval { getHeader($p) }; $@ && log::l("cannot get the header for package $p->{name}"); #- not having a header will cause using a bad test for version, should change but a header should always be available.
			     $p->{installed} = 1 if $p->{header} ? c::rpmVersionCompare($header, $p->{header}) >= 0 : c::headerGetEntry($header, 'version') ge $p->{version};
			 } else {
			     my @installedFiles = c::headerGetEntry($header, 'filenames');
			     @installedFilesForUpgrade{grep { $_ !~ m@^/etc/rc.d/@ } @installedFiles} = ();
			 }
		     });

    #- find new packages to upgrade.
    foreach (values %$packages) {
	my $p = $_;
	my $skipThis = 0;
	my $count = c::rpmdbNameTraverse($db, $p->{name}, sub {
					     my ($header) = @_;
					     $skipThis ||= $p->{installed};
					 });

	#- skip if not installed (package not found in current install).
	$skipThis ||= ($count == 0);

	#- select the package if it is already installed with a lower version or simply not installed.
	unless ($skipThis) {
	    my $cumulSize;

	    pkgs::select($packages, $p) unless $p->{selected};

	    #- keep in mind installed files which are not being updated. doing this costs in
	    #- execution time but use less memory, else hash all installed files and unhash
	    #- all file for package marked for upgrade.
	    c::rpmdbNameTraverse($db, $p->{name}, sub {
				     my ($header) = @_;
				     $cumulSize += c::headerGetEntry($header, 'size'); #- all these will be deleted on upgrade.
				     my @installedFiles = c::headerGetEntry($header, 'filenames');
				     @installedFilesForUpgrade{ grep { $_ !~ m@^/etc/rc.d/@ } @installedFiles} = ();
				 });
	    eval { getHeader($p) };
	    my @availFiles = $p->{header} ? c::headerGetEntry($p->{header}, 'filenames') : ();
	    map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m@^/etc/rc.d/@ } @availFiles;

	    #- keep in mind the cumul size of installed package since they will be deleted
	    #- on upgrade.
	    $p->{installedCumulSize} = $cumulSize;
	}
    }

    #- unmark all files for all packages marked for upgrade. it may not have been done above
    #- since some packages may have been selected by depsList.
    foreach (values %$packages) {
	my $p = $_;

	if ($p->{selected}) {
	    eval { getHeader($p) };
	    my @availFiles = $p->{header} ? c::headerGetEntry($p->{header}, 'filenames') : ();
	    map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m@^/etc/rc.d/@ } @availFiles;
	}
    }

    #- select packages which contains marked files, then unmark on selection.
    foreach (values %$packages) {
	my $p = $_;

	unless ($p->{selected}) {
	    eval { getHeader($p) };
	    my @availFiles = $p->{header} ? c::headerGetEntry($p->{header}, 'filenames') : ();
	    my $toSelect = 0;
	    map { if (exists $installedFilesForUpgrade{$_}) {
		$toSelect = 1; delete $installedFilesForUpgrade{$_} } } grep { $_ !~ m@^/etc/rc.d/@ } @availFiles;
	    pkgs::select($packages, $p) if ($toSelect);
	}
    }

    #- select packages which obseletes other package, obselete package are not removed,
    #- should we remove them ? this could be dangerous !
    foreach (values %$packages) {
	my $p = $_;

	eval { getHeader($p) };
	my @obsoletes = $p->{header} ? c::headerGetEntry(getHeader($p), 'obsoletes'): ();
	map { pkgs::select($packages, $p) if c::rpmdbNameTraverse($db, $_) > 0 } @obsoletes;
    }

    #- select all base packages which are not installed and not selected.
    foreach (@$base) {
	my $p = $packages->{$_} or log::l("missing base package $_"), next;
	log::l("base package $_ is not installed") unless $p->{installed} || $p->{selected}; #- installed not set on upgrade.
	pkgs::select($packages, $p, 1) unless $p->{selected}; #- if installed it cannot be selected.
    }

    #- close db, job finished !
    c::rpmdbClose($db);
    log::l("done selecting packages to upgrade");
}

sub install($$) {
    my ($prefix, $toInstall) = @_;
    my %packages;

    return if $::g_auto_install;

    c::rpmReadConfigFiles() or die "can't read rpm config files";

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	eval { getHeader($p) }; $@ and next;
	$p->{file} ||= sprintf "%s-%s-%s.%s.rpm",
	                       $p->{name}, $p->{version}, $p->{release},
			       c::headerGetEntry(getHeader($p), 'arch');
	$packages{$p->{name}} = $p;
	c::rpmtransAddPackage($trans, getHeader($p), $p->{name}, $p->{name} !~ /kernel/); #- TODO: replace `named kernel' by `provides kernel'
#	c::rpmtransAddPackage($trans, getHeader($p), $p->{file}, 1); #- TODO: replace `named kernel' by `provides kernel'
	$nb++;
	$total += $p->{size};
    }

    c::rpmdepOrder($trans) or
	cdie "error ordering package list: " . c::rpmErrorString(),
	  sub {
	      c::rpmdbClose($db);
	      c::rpmtransFree($trans);
	  };
    c::rpmtransSetScriptFd($trans, fileno LOG);

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) };

    #- if someone try to change the function log::ld or the parameters used,
    #- DON TRY THAT unless you have modified accordingly install_steps_gtk.
    #- because log::ld is catched, furthermore do not translate the messages used.
    log::l("starting installation: ", $nb, " packages, ", $total, " bytes");
    log::ld("starting installation: ", $nb, " packages, ", $total, " bytes");

    my $callbackOpen = sub {
	my $f = (my $p = $packages{$_[0]})->{file};
	print LOG "$f\n";
	my $fd = install_any::getFile($f) or log::l("bad file $f");
	$fd ? fileno $fd : -1;
    };
    my $callbackClose = sub { $packages{$_[0]}{installed} = 1; };
    my $callbackStart = sub { log::ld("starting installing package ", $_[0]) };
    my $callbackProgress = sub { log::ld("progressing installation ", $_[0], "/", $_[1]) };

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose,
					  $callbackStart, $callbackProgress, 0)) {
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

1;
