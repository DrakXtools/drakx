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
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs
MySQL MySQL_GPL mod_php3 midgard postfix metroess metrotmpl
kernel-linus kernel-secure kernel-fb kernel-BOOT
hackkernel hackkernel-BOOT hackkernel-fb hackkernel-headers
hackkernel-pcmcia-cs hackkernel-smp hackkernel-smp-fb 
autoirpm autoirpm-icons numlock 
);

my %by_lang = (
  ar    => [ 'acon' ],
  cs	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  hr	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  hu	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  ja    => [ 'rxvt-CLE', 'fonts-ttf-japanese', 'kterm' ],
  ko    => [ 'rxvt-CLE', 'fonts-ttf-korean' ],
  pl	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  ro	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  ru	=> [ 'XFree86-cyrillic-fonts' ],
  sk	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  sl	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  sr	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  'tr'	=> [ 'XFree86-ISO8859-9', 'XFree86-ISO8859-9-75dpi-fonts' ],
  zh_CN => [ 'rxvt-CLE', 'fonts-ttf-gb2312' ],
  'zh_TW.Big5' => [ 'rxvt-CLE', 'fonts-ttf-big5' ],
);

my @preferred = qw(perl-GTK postfix ghostscript-X);

my $A = 20471;
my $B = 16258;
sub correctSize { ($A - $_[0]) * $_[0] / $B } #- size correction in MB.
sub invCorrectSize { $A / 2 - sqrt(max(0, sqr($A) - 4 * $B * $_[0])) / 2 }

sub selectedSize {
    my ($packages) = @_;
    int (sum map { $_->{size} } grep { $_->{selected} } values %$packages) / sqr(1024);
}
sub correctedSelectedSize { correctSize(selectedSize($_[0])) }

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
    my %preferred; @preferred{@preferred} = ();
    my ($n, $v);
#   print "## $p->{name}\n";
    unless ($p->{installed}) { #- if the same or better version is installed, do not select.
	$p->{base} ||= $base;
	$p->{selected} = -1; #- selected by user
	my %l; @l{@{$p->{deps} || die "missing deps file"}} = ();
	while (do { my %l = %l; while (($n, $v) = each %l) { last if $v != 1; } $n }) {
	    $l{$n} = 1;
	    my $i = $packages->{$n};
	    if (!$i && $n =~ /\|/) {
		foreach (split '\|', $n) {
		    my $p = Package($packages, $_);
		    $i ||= $p;
		    $p && $p->{selected} and $i = $p, last;
		    $p && exists $preferred{$_} and $i = $p;
		}
	    }
	    $i->{base} ||= $base;
	    $i->{deps} or log::l("missing deps for $n");
	    unless ($i->{installed}) {
		unless ($i->{selected}) {
#		    print ">> $i->{name}\n";
#		    /gnome-games/ and print ">>> $i->{name}\n" foreach @{$i->{deps} || []};
		    $l{$_} ||= 0 foreach @{$i->{deps} || []};
		}
		$i->{selected}++ unless $i->{selected} == -1;
	    }
	}
    }
    1;
}
sub unselect($$) {
    my ($packages, $p) = @_;
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
	    push @$l, @{$i->{deps} || []};
	}
    }
    1;
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

sub size_selected {
    my ($packages) = @_;
    my $nb = 0; foreach (values %$packages) {
	$nb += $_->{size} if $_->{selected};
    }
    $nb;
}

sub skip_set {
    my ($packages, @l) = @_;
    $_->{skip} = 1 foreach @l, grep { $_ } map { Package($packages, $_) } map { @{$_->{provides} || []} } @l;
}

sub psUsingDirectory(;$) {
    my $dirname = $_[0] || "/tmp/rhimage/Mandrake/RPMS";
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

#-    my ($noSeek, $end) = 0;
#-    $end = sysseek F, 0, 2 or die "seek failed";
#-    sysseek F, 0, 0 or die "seek failed";

    while (my $header = c::headerRead(fileno $f, 1)) {
#-	 or die "error reading header at offset ", sysseek(F, 0, 1);
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
#- Why?	    pop @l if $l[-1] =~ /^(x11|console)$/;
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
    my ($packages, $compss_) = @_;
    my $f = install_any::getFile("compssList") or die "can't find compssList";
    local $_ = <$f>;
    my $level = [ split ];

    my $nb_values = 3;
    my $e;
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;

	/^packages\s*$/ and do { $e = $packages; next };
	/^categories\s*$/ and do { $e = $compss_; next };

	my ($name, @values) = split;

	$e or log::l("neither packages nor categories");
	my $p = $e->{$name} or log::l("unknown entry $name (in compssList)"), next;
	$p->{values} = \@values;
    }

    my %done;
    foreach (split ':', $ENV{RPM_INSTALL_LANG}) {
	my $p = $packages->{"locales-$_"} || {};
	foreach ("locales-$_", @{$p->{provides} || []}, @{$by_lang{$_} || []}) {
	    next if $done{$_}; $done{$_} = 1;
	    my $p = $packages->{$_} or next;
	    $p->{values} = [ map { $_ + 90 } @{$p->{values} || [ (0) x $nb_values ]} ];
	}
    }
    $level;
}

sub readCompssUsers {
    my ($packages, $compss) = @_;
    my (%compssUsers, @sorted, $l);

    my $f = install_any::getFile("compssUsers") or die "can't find compssUsers";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    push @sorted, $1;
	    $compssUsers{$1} = $l = [];
	} elsif (/\s+\+(\S+)/) {
	    push @$l, $packages->{$1} || do { log::l("unknown package $1 (in compssUsers)"); next };
	} elsif (/\s+(\S+)/) {
	    my $p = $compss;
	    $p &&= $p->{childs}{$_} foreach split ':', $1;
	    $p or log::l("unknown category $1 (in compssUsers)"), next;
	    push @$l, @{ category2packages($p) };
	}
    }
    \%compssUsers, \@sorted;
}

#- sub isLangSensitive($$) {
#-     my ($name, $lang) = @_;
#-     local $SIG{__DIE__} = 'none';
#-     $name =~ /-([^-]*)$/ or return;
#-     $1 eq $lang || eval { lang::text2lang($1) eq $lang } && !$@;
#- }

sub setSelectedFromCompssList {
    my ($compssListLevels, $packages, $min_level, $max_size, $install_class) = @_;
    my ($ind);

    my @packages = allpackages($packages);
    my @places = do {
	map_index { $ind = $::i if $_ eq $install_class } @$compssListLevels;
	defined $ind or log::l("unknown install class $install_class in compssList"), return;

	#- special case for /^k/ aka kde stuff
	my @values = map { $_->{values}[$ind] + ($_->{unskip} && $_->{name} !~ /^k/ ? 10 : 0) } @packages;
	sort { $values[$b] <=> $values[$a] } 0 .. $#packages;
    };
    foreach (@places) {
	my $p = $packages[$_];
	next if $p->{skip};
	last if $p->{values}[$ind] < $min_level;

	&select($packages, $p);

	my $nb = 0; foreach (@packages) {
	    $nb += $_->{size} if $_->{selected};
	}
	if ($max_size && $nb > $max_size) {
	    unselect($packages, $p);
	    $min_level = $p->{values}[$ind];
	    log::l("setSelectedFromCompssList: up to indice $min_level (reached size $max_size)");
	    last;
	}
    }
    $ind, $min_level;
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

sub versionCompare($$) {
    my ($a, $b) = @_;
    local $_;

    while ($a && $b) {
	my ($sb, $sa) =  map { $1 if $a =~ /^\W*\d/ ? s/^\W*0*(\d+)// : s/^\W*(\D+)// } ($b, $a);
	$_ = length($sa) cmp length($sb) || $sa cmp $sb and return $_;
    }
}

sub selectPackagesToUpgrade($$$;$$) {
    my ($packages, $prefix, $base, $toRemove, $toSave) = @_;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpenForTraversal($prefix) or die "unable to open $prefix/var/lib/rpm/packages.rpm";
    log::l("opened rpm database for examining existing packages");

    local $_; #- else perl complains on the map { ... } grep { ... } @...;
    my %installedFilesForUpgrade; #- help searching package to upgrade in regard to already installed files.

    #- used for package that are not correctly updated.
    my %upgradeNeedRemove = (
			     'compat-glibc' => 1,
			     'compat-libs' => 1,
			    );

    #- help removing package which may have different release numbering
    my %toRemove; map { $toRemove{$_} = 1 } @{$toRemove || []};

    #- mark all files which are not in /etc/rc.d/ for packages which are already installed but which
    #- are not in the packages list to upgrade.
    #- the 'installed' property will make a package unable to be selected, look at select.
    c::rpmdbTraverse($db, sub {
			 my ($header) = @_;
			 my $p = $packages->{c::headerGetEntry($header, 'name')};
			 my $otherPackage = (c::headerGetEntry($header, 'release') !~ /mdk\w*$/ &&
					     (c::headerGetEntry($header, 'name'). '-' .
					      c::headerGetEntry($header, 'version'). '-' .
					      c::headerGetEntry($header, 'release')));
			 if ($p) {
			     eval { getHeader($p) }; $@ && log::l("cannot get the header for package $p->{name}");
			     my $version_cmp = versionCompare(c::headerGetEntry($header, 'version'), $p->{version});
			     my $version_rel_test = $p->{header} ? c::rpmVersionCompare($header, $p->{header}) >= 0 :
			       ($version_cmp > 0 ||
				$version_cmp == 0 &&
				versionCompare(c::headerGetEntry($header, 'release'), $p->{release}) >= 0);
			     if ($version_rel_test) {
				 if ($otherPackage && $version_cmp <= 0) {
				     log::l("removing $otherPackage since it will not be updated otherwise");
				     $toRemove{$otherPackage} = 1; #- force removing for theses other packages, select our.
				 } else {
				     $p->{installed} = 1;
				 }
			     } elsif ($upgradeNeedRemove{$p->{name}}) {
				 my $otherPackage = (c::headerGetEntry($header, 'name'). '-' .
						     c::headerGetEntry($header, 'version'). '-' .
						     c::headerGetEntry($header, 'release'));
				 log::l("removing $otherPackage since it will not upgrade correctly!");
				 $toRemove{$otherPackage} = 1; #- force removing for theses other packages, select our.
			     }
			 } else {
			     my @files = c::headerGetEntry($header, 'filenames');
			     @installedFilesForUpgrade{grep { ($_ !~ m|^/etc/rc.d/| &&
							       ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
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
				     my $otherPackage = (c::headerGetEntry($header, 'release') !~ /mdk\w*$/ &&
							 (c::headerGetEntry($header, 'name'). '-' .
							  c::headerGetEntry($header, 'version'). '-' .
							  c::headerGetEntry($header, 'release')));
				     $cumulSize += c::headerGetEntry($header, 'size'); #- all these will be deleted on upgrade.
				     my @files = c::headerGetEntry($header, 'filenames');
				     @installedFilesForUpgrade{grep { ($_ !~ m|^/etc/rc.d/| &&
								       ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
				 });
	    eval { getHeader($p) };
	    my @availFiles = $p->{header} ? c::headerGetEntry($p->{header}, 'filenames') : ();
	    map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m|^/etc/rc.d/| } @availFiles;

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
	    map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m|^/etc/rc.d/| } @availFiles;
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
		$toSelect ||= ! -d "$prefix/$_" && ! -l "$prefix/$_"; delete $installedFilesForUpgrade{$_} }
	      } grep { $_ !~ m@^/etc/rc.d/@ } @availFiles;
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

    #- clean false value on toRemove.
    delete $toRemove{''};

    #- get filenames that should be saved for packages to remove.
    #- typically config files, but it may broke for packages that
    #- are very old when compabilty has been broken.
    #- but new version may saved to .rpmnew so it not so hard !
    if ($toSave && keys %toRemove) {
	c::rpmdbTraverse($db, sub {
			     my ($header) = @_;
			     my $otherPackage = (c::headerGetEntry($header, 'name'). '-' .
						 c::headerGetEntry($header, 'version'). '-' .
						 c::headerGetEntry($header, 'release'));
			     if ($toRemove{$otherPackage}) {
				 if ($packages->{c::headerGetEntry($header, 'name')}{base}) {
				     delete $toRemove{$otherPackage}; #- keep it selected, but force upgrade.
				 } else {
				     my @files = c::headerGetEntry($header, 'filenames');
				     my @flags = c::headerGetEntry($header, 'fileflags');
				     for my $i (0..$#flags) {
					 if ($flags[$i] & c::RPMFILE_CONFIG()) {
					     push @$toSave, $files[$i] unless $files[$i] =~ /kdelnk/; #- avoid doublons for KDE.
					 }
				     }
				 }
			     }
			 });
    }

    log::l("before closing db");
    #- close db, job finished !
    c::rpmdbClose($db);
    log::l("done selecting packages to upgrade");

    #- update external copy with local one.
    @{$toRemove || []} = keys %toRemove;
}

sub installCallback {
    my $msg = shift;

    log::l($msg .": ". join(',', @_));
}

sub install($$$;$) {
    my ($prefix, $isUpgrade, $toInstall) = @_;
    my %packages;

#-    foreach (@$toInstall) {
#-	  print "$_->{name}\n";
#-    }

    return if $::g_auto_install;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database for installing new packages");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    my ($total, $nb);

    foreach my $p (@$toInstall) {
	eval { getHeader($p) }; $@ and next;
	$p->{file} ||= sprintf "%s-%s-%s.%s.rpm",
	                       $p->{name}, $p->{version}, $p->{release},
			       c::headerGetEntry(getHeader($p), 'arch');
	$packages{$p->{name}} = $p;
	c::rpmtransAddPackage($trans, getHeader($p), $p->{name}, $isUpgrade && $p->{name} !~ /kernel/); #- TODO: replace `named kernel' by `provides kernel'
	$nb++;
	$total += $p->{size};
    }

    c::rpmdepOrder($trans) or
	cdie "error ordering package list: " . c::rpmErrorString(),
	  sub {
	      c::rpmtransFree($trans);
	      c::rpmdbClose($db);
	  };
    c::rpmtransSetScriptFd($trans, fileno LOG);

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    my $callbackOpen = sub {
	my $f = (my $p = $packages{$_[0]})->{file};
	print LOG "$f\n";
	my $fd = install_any::getFile($f) or log::l("ERROR: bad file $f");
	$fd ? fileno $fd : -1;
    };
    my $callbackClose = sub { $packages{$_[0]}{installed} = 1; };
    my $callbackMessage = \&pkgs::installCallback;

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    &$callbackMessage("Starting installation", $nb, $total);

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, $callbackMessage, 0)) {
	my %parts;
	@probs = reverse grep {
	    if (s/(installing package) .* (needs (?:.*) on the (.*) filesystem)/$1 $2/) {
		$parts{$3} ? 0 : ($parts{$3} = 1);
	    } else { 1; }
	} reverse @probs;

	c::rpmtransFree($trans);
	c::rpmdbClose($db);
#	if ($isUpgrade && !$useOnlyUpgrade && %parts) {
#	    #- recurse only once to try with only upgrade (including kernel).
#	    log::l("trying to upgrade all packages to save space");
#	    install($prefix,$isUpgrade,$toInstall,1);
#	}
	die "installation of rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans);
    c::rpmdbClose($db);
    log::l("rpm database closed");

    install_any::rewindGetFile(); #- make sure to reopen the connection, usefull for ftp.
}

sub remove($$) {
    my ($prefix, $toRemove) = @_;

    return if $::g_auto_install || !@{$toRemove || []};

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    log::l("opened rpm database for removing old packages");

    my $trans = c::rpmtransCreateSet($db, $prefix);

    foreach my $p (@$toRemove) {
	#- stuff remove all packages that matches $p, not a problem since $p has name-version-release format.
	c::rpmtransRemovePackages($db, $trans, $p) if $p !~ /kernel/;
    }

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    my $callbackOpen = sub { log::l("trying to open file from $_[0] which should not happen"); };
    my $callbackClose = sub { log::l("trying to close file from $_[0] which should not happen"); };
    my $callbackMessage = \&pkgs::installCallback;

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    &$callbackMessage("Starting removing other packages", scalar @$toRemove);

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, $callbackMessage, 0)) {
	die "removing of old rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans);
    c::rpmdbClose($db);
    log::l("rpm database closed");

    #- keep in mind removing of these packages by cleaning $toRemove.
    @{$toRemove || []} = ();
}

1;
