package pkgs; # $Id$

use diagnostics;
use strict;
use vars qw(*LOG %compssListDesc @skip_list %by_lang @preferred $limitMinTrans $PKGS_SELECTED $PKGS_FORCE $PKGS_INSTALLED $PKGS_BASE $PKGS_SKIP $PKGS_UPGRADE);

use common qw(:common :file :functional);
use install_any;
use commands;
use run_program;
use log;
use pkgs;
use fs;
use loopback;
use lang;
use c;

#- lower bound on the left ( aka 90 means [90-100[ )
%compssListDesc = (
 100 => __("mandatory"), #- do not use it, it's for base packages
  90 => __("must have"), #- every install have these packages (unless hand de-selected in expert, or not enough room)
  80 => __("important"), #- every beginner/custom install have these packages (unless not enough space)
		         #- has minimum X install (XFree86 + icewm)(normal)
  70 => __("very nice"), #- KDE(normal)
  60 => __("nice"),      #- gnome(normal)
  50 => __("interesting"),
  40 => __("interesting"),
  30 => __("maybe"),
  20 => __("maybe"),
  10 => __("maybe"),#__("useless"),
   0 => __("maybe"),#__("garbage"),
#- if the package requires locales-LANG and LANG is chosen, rating += 90
#- if the package is in %by_lang and the corresponding LANG is chosen, rating += 90   (see %by_lang below)
 -10 => __("i18n (important)"), #- every install in the corresponding lang have these packages
 -20 => __("i18n (very nice)"), #- every beginner/custom install in the corresponding lang have theses packages
 -30 => __("i18n (nice)"),
);
#- HACK: rating += 50 for some packages (like kapm, cf install_any::setPackages)

%by_lang = (
  'ar'	=> [ 'acon' ],
#'be_BE.CP1251' => [ 'fonts-ttf-cyrillic' ],
#'bg_BG' => [ 'fonts-ttf-cyrillic' ],
  'cs'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
# 'cy'  => iso8859-14 fonts
# 'el'	=> greek fonts
# 'eo'	=> iso8859-3 fonts
  'fa'  => [ 'acon' ],
  'he'  => [ 'acon' ],
  'hr'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  'hu'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  'hy'	=> [ 'fonts-ttf-armenian' ],
  'ja'	=> [ 'rxvt-CLE', 'fonts-ttf-japanese', 'kterm' ],
# 'ka'	=> georgian fonts
  'ko'	=> [ 'rxvt-CLE', 'fonts-ttf-korean' ],
  'lt'	=> [ 'fonts-type1-baltic' ],
  'lv'	=> [ 'fonts-type1-baltic' ],
  'mi'	=> [ 'fonts-type1-baltic' ],
# 'mk'	=> [ 'fonts-ttf-cyrillic' ],
  'pl'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  'ro'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
# 'ru'  => [ 'XFree86-cyrillic-fonts', 'fonts-ttf-cyrillic' ],
  'ru'  => [ 'XFree86-cyrillic-fonts' ],
  'ru_RU.KOI8-R' => [ 'XFree86-cyrillic-fonts' ],
  'sk'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
  'sl'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
# 'sp'	=> [ 'fonts-ttf-cyrillic' ],
  'sr'	=> [ 'XFree86-ISO8859-2', 'XFree86-ISO8859-2-75dpi-fonts' ],
# 'th'	=> thai fonts
  'tr'	=> [ 'XFree86-ISO8859-9', 'XFree86-ISO8859-9-75dpi-fonts' ],
#'uk_UA' => [ 'fonts-ttf-cyrillic' ],
# 'vi'	=> vietnamese fonts
  'yi'  => [ 'acon' ],
  'zh'  => [ 'rxvt-CLE', 'taipeifonts', 'fonts-ttf-big5', 'fonts-ttf-gb2312' ],
  'zh_CN.GB2312' => [ 'rxvt-CLE', 'fonts-ttf-gb2312' ],
  'zh_TW.Big5' => [ 'rxvt-CLE', 'taipeifonts', 'fonts-ttf-big5' ],
);

@skip_list = qw(
XFree86-8514 XFree86-AGX XFree86-Mach32 XFree86-Mach64 XFree86-Mach8 XFree86-Mono
XFree86-P9000 XFree86-S3 XFree86-S3V XFree86-SVGA XFree86-W32 XFree86-I128
XFree86-Sun XFree86-SunMono XFree86-Sun24 XFree86-3DLabs
MySQL MySQL_GPL mod_php3 midgard postfix metroess metrotmpl
kernel-linus kernel-secure kernel-BOOT
hackkernel hackkernel-BOOT hackkernel-headers
hackkernel-pcmcia-cs hackkernel-smp hackkernel-smp-fb 
autoirpm autoirpm-icons numlock 
);

@preferred = qw(perl-GTK postfix wu-ftpd ghostscript-X vim-minimal kernel ispell-en);

#- constant for small transaction.
$limitMinTrans = 8;

#- constant for packing flags, see below.
$PKGS_SELECTED  = 0x00ffffff;
$PKGS_FORCE     = 0x01000000;
$PKGS_INSTALLED = 0x02000000;
$PKGS_BASE      = 0x04000000;
$PKGS_SKIP      = 0x08000000;
$PKGS_UPGRADE   = 0x20000000;

#- package to ignore, typically in Application CD.
my %ignoreBadPkg = (
		    'civctp-demo'   => 1,
		    'eus-demo'      => 1,
		    'myth2-demo'    => 1,
		    'heretic2-demo' => 1,
		    'heroes3-demo'  => 1,
		    'rt2-demo'      => 1,
		   );

#- basic methods for extracting informations about packages.
#- to save memory, (name, version, release) are no more stored, they
#- are directly generated from (file).
#- all flags are grouped together into (flags), these includes the
#- following flags : selected, force, installed, base, skip.
#- size and deps are grouped to save memory too and make a much
#- simpler and faster depslist reader, this gets (sizeDeps).
sub packageHeaderFile   { my ($pkg) = @_; $pkg->{file} }
sub packageName         { my ($pkg) = @_; $pkg->{file} =~ /([^\(]*)(?:\([^\)]*\))?-[^-]+-[^-]+/ ? $1 : die "invalid file `$pkg->{file}'" }
sub packageSpecificArch { my ($pkg) = @_; $pkg->{file} =~ /[^\(]*(?:\(([^\)]*)\))?-[^-]+-[^-]+/ ? $1 : die "invalid file `$pkg->{file}'" }
sub packageVersion      { my ($pkg) = @_; $pkg->{file} =~ /.*-([^-]+)-[^-]+/ ? $1 : die "invalid file `$pkg->{file}'" }
sub packageRelease      { my ($pkg) = @_; $pkg->{file} =~ /.*-[^-]+-([^-]+)/ ? $1 : die "invalid file `$pkg->{file}'" }

sub packageSize   { my ($pkg) = @_; to_int($pkg->{sizeDeps}) }
sub packageDepsId { my ($pkg) = @_; split ' ', ($pkg->{sizeDeps} =~ /^\d*\s*(.*)/)[0] }

sub packageFlagSelected  { my ($pkg) = @_; $pkg->{flags} & $PKGS_SELECTED }
sub packageFlagForce     { my ($pkg) = @_; $pkg->{flags} & $PKGS_FORCE }
sub packageFlagInstalled { my ($pkg) = @_; $pkg->{flags} & $PKGS_INSTALLED }
sub packageFlagBase      { my ($pkg) = @_; $pkg->{flags} & $PKGS_BASE }
sub packageFlagSkip      { my ($pkg) = @_; $pkg->{flags} & $PKGS_SKIP }
sub packageFlagUpgrade   { my ($pkg) = @_; $pkg->{flags} & $PKGS_UPGRADE }

sub packageSetFlagSelected  { my ($pkg, $v) = @_; $pkg->{flags} &= ~$PKGS_SELECTED; $pkg->{flags} |= $v & $PKGS_SELECTED; }

sub packageSetFlagForce     { my ($pkg, $v) = @_; $v ? ($pkg->{flags} |= $PKGS_FORCE)     : ($pkg->{flags} &= ~$PKGS_FORCE); }
sub packageSetFlagInstalled { my ($pkg, $v) = @_; $v ? ($pkg->{flags} |= $PKGS_INSTALLED) : ($pkg->{flags} &= ~$PKGS_INSTALLED); }
sub packageSetFlagBase      { my ($pkg, $v) = @_; $v ? ($pkg->{flags} |= $PKGS_BASE)      : ($pkg->{flags} &= ~$PKGS_BASE); }
sub packageSetFlagSkip      { my ($pkg, $v) = @_; $v ? ($pkg->{flags} |= $PKGS_SKIP)      : ($pkg->{flags} &= ~$PKGS_SKIP); }
sub packageSetFlagUpgrade   { my ($pkg, $v) = @_; $v ? ($pkg->{flags} |= $PKGS_UPGRADE)   : ($pkg->{flags} &= ~$PKGS_UPGRADE); }

sub packageProvides { my ($pkg) = @_; @{$pkg->{provides} || []} }

sub packageFile { 
    my ($pkg) = @_; 
    $pkg->{header} or die "packageFile: missing header";
    $pkg->{file} =~ /([^\(]*)(?:\([^\)]*\))?(-[^-]+-[^-]+)/;
    "$1$2." . c::headerGetEntry($pkg->{header}, 'arch') . ".rpm";
}

sub packageId {
    my ($packages, $pkg) = @_;
    my $i = 0;
    foreach (@{$packages->[1]}) { return $i if $pkg == $packages->[1][$i]; $i++ }
    return;
}

sub cleanHeaders {
    my ($prefix) = @_;
    commands::rm("-rf", "$prefix/tmp/headers") if -e "$prefix/tmp/headers";
}

#- get all headers from an hdlist file.
sub extractHeaders($$$) {
    my ($prefix, $pkgs, $medium) = @_;

    cleanHeaders($prefix);

    run_program::run("packdrake", "-x",
		     "/tmp/$medium->{hdlist}",
		     "$prefix/tmp/headers",
		     map { packageHeaderFile($_) } @$pkgs);

    foreach (@$pkgs) {
	my $f = "$prefix/tmp/headers/". packageHeaderFile($_);
	local *H;
	open H, $f or log::l("unable to open header file $f: $!"), next;
	$_->{header} = c::headerRead(fileno H, 1) or log::l("unable to read header of package ". packageHeaderFile($_));
    }
    @$pkgs = grep { $_->{header} } @$pkgs;
}

#- size and correction size functions for packages.
#- invCorrectSize corrects size in the range 0 to 3Gb approximately, so
#- it should not be used outside these levels.
#- but since it is an inverted parabolic curve starting above 0, we can
#- get a solution where X=Y at approximately 9.3Gb. we use this point as
#- a limit to change the approximation to use a linear one.
#- for information above this point, we have the corrected size below the
#- original size wich is absurd, this point is named D below.
my $A = -121568/100000000000; # -1.21568e-05; #- because perl does like that on some language (TO BE FIXED QUICKLY)
my $B = 121561/100000; # 1.21561
my $C = -239889/10000; # -23.9889 #- doesn't take hdlist's into account as getAvailableSpace will do it.
my $D = (-sqrt(sqr($B - 1) - 4 * $A * $C) - ($B - 1)) / 2 / $A; #- $A is negative so a positive solution is with - sqrt ...
sub correctSize {
    my $csz = ($A * $_[0] + $B) * $_[0] + $C;
    $csz > $_[0] ? $csz : $_[0]; #- size correction (in MB) should be above input argument (as $A is negative).
}
sub invCorrectSize {
    my $sz = $_[0] < $D ? (sqrt(sqr($B) + 4 * $A * ($_[0] - $C)) - $B) / 2 / $A : $_[0];
    $sz < $_[0] ? $sz : $_[0];
}

sub selectedSize {
    my ($packages) = @_;
    my $size = 0;
    foreach (values %{$packages->[0]}) {
	packageFlagSelected($_) && !packageFlagInstalled($_) and $size += packageSize($_) - ($_->{installedCumulSize} || 0);
    }
    $size;
}
sub correctedSelectedSize { correctSize(selectedSize($_[0]) / sqr(1024)) }


#- searching and grouping methods.
#- package is a reference to list that contains
#- a hash to search by name and
#- a list to search by id.
sub packageByName {
    my ($packages, $name) = @_;
    $packages->[0]{$name} or log::l("unknown package `$name'") && undef;
}
sub packageById {
    my ($packages, $id) = @_;
    $packages->[1][$id] or log::l("unknown package id $id") && undef;
}
sub allPackages {
    my ($packages) = @_;
    my %skip_list; @skip_list{@skip_list} = ();
    grep { !exists $skip_list{packageName($_)} } values %{$packages->[0]};
}
sub packagesOfMedium {
    my ($packages, $mediumName) = @_;
    my $medium = $packages->[2]{$mediumName};
    grep { $_->{medium} == $medium } @{$packages->[1]};
}
sub packagesToInstall {
    my ($packages) = @_;
    grep { $_->{medium}{selected} && packageFlagSelected($_) && !packageFlagInstalled($_) } values %{$packages->[0]};
}

sub allMediums {
    my ($packages) = @_;
    keys %{$packages->[2]};
}
sub mediumDescr {
    my ($packages, $medium) = @_;
    $packages->[2]{$medium}{descr};
}

#- selection, unselection of package.
sub selectPackage { #($$;$$$)
    my ($packages, $pkg, $base, $otherOnly, $check_recursion) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    packageFlagInstalled($pkg) and return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    $pkg->{medium}{selected} or return;

    #- avoid infinite recursion (mainly against badly generated depslist.ordered).
    $check_recursion ||= {}; exists $check_recursion->{$pkg->{file}} and return; $check_recursion->{$pkg->{file}} = undef;

    #- make sure base package are set even if already selected.
    $base and packageSetFlagBase($pkg, 1);

    #- select package and dependancies, otherOnly may be a reference
    #- to a hash to indicate package that will strictly be selected
    #- when value is true, may be selected when value is false (this
    #- is only used for unselection, not selection)
    unless (packageFlagSelected($pkg)) {
	foreach (packageDepsId($pkg)) {
	    my $preferred;	    
	    if (/\|/) {
		#- choice deps should be reselected recursively as no
		#- closure on them is computed, this code is exactly the
		#- same as pixel's one.
		my %preferred; @preferred{@preferred} = ();
		foreach (split '\|') {
		    my $dep = packageById($packages, $_) or next;
		    $preferred ||= $dep;
		    packageFlagSelected($dep) and $preferred = $dep, last;
		    exists $preferred{packageName($dep)} and $preferred = $dep;
		}
		selectPackage($packages, $preferred, $base, $otherOnly, $check_recursion) if $preferred;
	    } else {
		#- deps have been closed except for choices, so no need to
		#- recursively apply selection, expand base on it.
		my $dep = packageById($packages, $_);
		$base and packageSetFlagBase($dep, 1);
		$otherOnly and !packageFlagSelected($dep) and $otherOnly->{packageName($dep)} = 1;
		$otherOnly or packageSetFlagSelected($dep, 1+packageFlagSelected($dep));
	    }
	}
    }
    $otherOnly and !packageFlagSelected($pkg) and $otherOnly->{packageName($pkg)} = 1;
    $otherOnly or packageSetFlagSelected($pkg, 1+packageFlagSelected($pkg));
    1;
}
sub unselectPackage($$;$) {
    my ($packages, $pkg, $otherOnly) = @_;

    #- base package are not unselectable,
    #- and already unselected package are no more unselectable.
    packageFlagBase($pkg) and return;
    packageFlagSelected($pkg) or return;

    #- dependancies may be used to propose package that may be not
    #- usefull for the user, since their counter is just one and
    #- they are not used any more by other packages.
    #- provides are closed and are taken into account to get possible
    #- unselection of package (value false on otherOnly) or strict
    #- unselection (value true on otherOnly).
    foreach my $provided ($pkg, packageProvides($pkg)) {
	packageFlagBase($provided) and die "a provided package cannot be a base package";
	if (packageFlagSelected($provided)) {
	    my $unselect_alone = 0;
	    foreach (packageDepsId($provided)) {
		if (/\|/) {
		    #- this package use a choice of other package, so we have to check
		    #- if our package is not included in the choice, if this is the
		    #- case, if must be checked one of the other package are selected.
		    foreach (split '\|') {
			my $dep = packageById($packages, $_);
			$dep == $pkg and $unselect_alone |= 1;
			packageFlagBase($dep) || packageFlagSelected($dep) and $unselect_alone |= 2;
		    }
		}
	    }
	    #- provided will not be unselect here if the two conditions are met.
	    $unselect_alone == 3 and next;
	    #- on the other hand, provided package have to be unselected.
	    $otherOnly or packageSetFlagSelected($provided, 0);
	    $otherOnly and $otherOnly->{packageName($provided)} = 1;
	}
	foreach (map { split '\|' } packageDepsId($provided)) {
	    my $dep = packageById($packages, $_);
	    packageFlagBase($dep) and next;
	    packageFlagSelected($dep) or next;
	    for (packageFlagSelected($dep)) {
		$_ == 1 and do { $otherOnly and $otherOnly->{packageName($dep)} ||= 0; };
		$_ >  1 and do { $otherOnly or packageSetFlagSelected($dep, $_-1); };
		last;
	    }
	}
    }
    1;
}
sub togglePackageSelection($$;$) {
    my ($packages, $pkg, $otherOnly) = @_;
    packageFlagSelected($pkg) ? unselectPackage($packages, $pkg, $otherOnly) : selectPackage($packages, $pkg, 0, $otherOnly);
}
sub setPackageSelection($$$) {
    my ($packages, $pkg, $value) = @_;
    $value ? selectPackage($packages, $pkg) : unselectPackage($packages, $pkg);
}

sub unselectAllPackages($) {
    my ($packages) = @_;
    foreach (values %{$packages->[0]}) {
	unless (packageFlagBase($_) || packageFlagUpgrade($_)) {
	    packageSetFlagSelected($_, 0);
	}
    }
}
sub unselectAllPackagesIncludingUpgradable($) {
    my ($packages, $removeUpgradeFlag) = @_;
    foreach (values %{$packages->[0]}) {
	unless (packageFlagBase($_)) {
	    packageSetFlagSelected($_, 0);
	    packageSetFlagUpgrade($_, 0);
	}
    }
}

sub skipSetWithProvides {
    my ($packages, @l) = @_;
    packageSetFlagSkip($_, 1) foreach grep { $_ } map { $_, packageProvides($_) } @l;
}

sub psUpdateHdlistsDeps {
    my ($prefix, $method) = @_;
    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";

    #- WARNING: this function should be kept in sync with functions
    #- psUsingHdlists and psUsingHdlist.
    #- it purpose it to update hdlist files on system to install.

    #- parse hdlist.list file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";
	my ($hdlist, $rpmsdir, $descr) = ($1, $2, $3);

	#- copy hdlist file directly to $prefix/var/lib/urpmi, this will be used
	#- for getting header of package during installation or after by urpmi.
	my $fakemedium = $method . $medium;
	my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz2" . ($hdlist =~ /\.cz2/ && "2");
	-e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
	install_any::getAndSaveFile("Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
	symlinkf $newf, "/tmp/$hdlist";
	++$medium;
    }

    #- this is necessary for urpmi.
    install_any::getAndSaveFile('Mandrake/base/depslist.ordered', "$prefix/var/lib/urpmi/depslist.ordered");
    install_any::getAndSaveFile('Mandrake/base/provides', "$prefix/var/lib/urpmi/provides");
    install_any::getAndSaveFile('Mandrake/base/compss', "$prefix/var/lib/urpmi/compss");
}

sub psUsingHdlists {
    my ($prefix, $method) = @_;
    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";
    my @packages = ({}, [], {});
    my @hdlists;

    #- parse hdlist.list file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";
	push @hdlists, [ $1, $medium, $2, $3 ];
	++$medium;
    }

    foreach (@hdlists) {
	my ($hdlist, $medium, $rpmsdir, $descr) = @$_;

	#- make sure the first medium is always selected!
	#- by default select all image.
	psUsingHdlist($prefix, $method, \@packages, $hdlist, $medium, $rpmsdir, $descr, 1);

    }

    log::l("psUsingHdlists read " . scalar keys(%{$packages[0]}) . " headers on " . scalar keys(%{$packages[2]}) . " hdlists");

    \@packages;
}

sub psUsingHdlist {
    my ($prefix, $method, $packages, $hdlist, $medium, $rpmsdir, $descr, $selected, $fhdlist) = @_;

    #- if the medium already exist, use it.
    $packages->[2]{$medium} and return;

    my $fakemedium = $method . $medium;
    my $m = $packages->[2]{$medium} = { hdlist     => $hdlist,
					medium     => $medium,
					rpmsdir    => $rpmsdir, #- where is RPMS directory.
					descr      => $descr,
					fakemedium => $fakemedium,
					min        => scalar keys %{$packages->[0]},
					max        => -1, #- will be updated after reading current hdlist.
					selected   => $selected, #- default value is only CD1, it is really the minimal.
				      };

    #- copy hdlist file directly to $prefix/var/lib/urpmi, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    -e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
    install_any::getAndSaveFile($fhdlist || "Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
    symlinkf $newf, "/tmp/$hdlist";

    #- extract filename from archive, this take advantage of verifying
    #- the archive too.
    open F, "packdrake $newf |";
    foreach (<F>) {
	chomp;
	/^[dlf]\s+/ or next;
	if (/^f\s+\d+\s+(.*)/) {
	    my $pkg = { file   => $1, #- rebuild filename according to header one
			flags  => 0,  #- flags
			medium => $m,
		      };
	    my $specific_arch = packageSpecificArch($pkg);
	    if (!$specific_arch || compat_arch($specific_arch)) {
		my $old_pkg = $packages->[0]{packageName($pkg)};
		if ($old_pkg) {
		    if (packageVersion($pkg) eq packageVersion($old_pkg) && packageRelease($pkg) eq packageRelease($old_pkg)) {
			if (better_arch($specific_arch, packageSpecificArch($old_pkg))) {
			    log::l("replacing old package with package $1 with better arch: $specific_arch");
			    $packages->[0]{packageName($pkg)} = $pkg;
			} else {
			    log::l("keeping old package against package $1 with worse arch");
			}
		    } else {
		        log::l("ignoring package $1 already present in distribution with different version or release");
		    }
		} else {
		    $packages->[0]{packageName($pkg)} = $pkg;
		}
	    } else {
	        log::l("ignoring package $1 with incompatible arch: $specific_arch");
	    }
	} else {
	    die "bad hdlist file: $newf";
	}
    }
    close F or die "unable to parse $newf";

    #- update maximal index.
    $m->{max} = scalar(keys %{$packages->[0]}) - 1;
    $m->{max} >= $m->{min} or die "nothing found while parsing $newf";
    log::l("read " . ($m->{max} - $m->{min} + 1) . " headers in $hdlist");
    1;
}

sub getOtherDeps($$) {
    my ($packages, $f) = @_;

    #- this version of getDeps is customized for handling errors more easily and
    #- convert reference by name to deps id including closure computation.
    foreach (<$f>) {
	my ($name, $version, $release, $size, $deps) = /^(\S*)-([^-\s]+)-([^-\s]+)\s+(\d+)\s+(.*)/;
	my $pkg = $packages->[0]{$name};

	$pkg or log::l("ignoring package $name-$version-$release in depslist is not in hdlist"), next;
	$version eq packageVersion($pkg) and $release eq packageRelease($pkg)
	  or log::l("warning package $name-$version-$release in depslist mismatch version or release in hdlist ($version ne ",
		    packageVersion($pkg), " or $release ne ", packageRelease($pkg), ")"), next;

	my $index = scalar @{$packages->[1]};
	$index >= $pkg->{medium}{min} && $index <= $pkg->{medium}{max}
	  or log::l("ignoring package $name-$version-$release in depslist outside of hdlist indexation");

	#- here we have to translate referenced deps by name to id.
	#- this include a closure on deps too.
	my %closuredeps;
	@closuredeps{map { packageId($packages, $_), packageDepsId($_) }
		       grep { $_ }
			 map { packageByName($packages, $_) or do { log::l("unknown package $_ in depslist for closure"); undef } }
			   split /\s+/, $deps} = ();

	$pkg->{sizeDeps} = join " ", $size, keys %closuredeps;

	push @{$packages->[1]}, $pkg;
    }

    #- check for same number of package in depslist and hdlists, avoid being to hard.
    scalar(keys %{$packages->[0]}) == scalar(@{$packages->[1]})
      or log::l("other depslist has not same package as hdlist file");
}

sub getDeps($) {
    my ($prefix, $packages) = @_;

    #- this is necessary for urpmi.
    install_any::getAndSaveFile('Mandrake/base/depslist.ordered', "$prefix/var/lib/urpmi/depslist.ordered");
    install_any::getAndSaveFile('Mandrake/base/provides', "$prefix/var/lib/urpmi/provides");

    #- beware of heavily mismatching depslist.ordered file against hdlist files.
    my $mismatch = 0;

    #- update dependencies list, provides attributes are updated later
    #- cross reference to be resolved on id (think of loop requires)
    #- provides should be updated after base flag has been set to save
    #- memory.
    local *F;
    open F, "$prefix/var/lib/urpmi/depslist.ordered" or die "cann't find dependancies list";
    foreach (<F>) {
	my ($name, $version, $release, $sizeDeps) = /^(\S*)-([^-\s]+)-([^-\s]+)\s+(.*)/;
	my $pkg = $packages->[0]{$name};

	$pkg or
	  log::l("ignoring $name-$version-$release in depslist is not in hdlist"), $mismatch = 1, next;
	$version eq packageVersion($pkg) and $release eq packageRelease($pkg) or
	  log::l("ignoring $name-$version-$release in depslist mismatch version or release in hdlist ($version ne ", packageVersion($pkg), " or $release ne ", packageRelease($pkg), ")"), $mismatch = 1, next;

	$pkg->{sizeDeps} = $sizeDeps;

	#- check position of package in depslist according to precomputed
	#- limit by hdlist, very strict :-)
	#- above warning have chance to raise an exception here, but may help
	#- for debugging.
	my $i = scalar @{$packages->[1]};
	$i >= $pkg->{medium}{min} && $i <= $pkg->{medium}{max} or $mismatch = 1;

	#- package are already sorted in depslist to enable small transaction and multiple medium.
	push @{$packages->[1]}, $pkg;
    }

    #- check for mismatching package, it should breaj with above die unless depslist has too many errors!
    $mismatch and die "depslist.ordered mismatch against hdlist files";

    #- check for same number of package in depslist and hdlists.
    scalar(keys %{$packages->[0]}) == scalar(@{$packages->[1]}) or die "depslist.ordered has not same package as hdlist files";
}

sub getProvides($) {
    my ($packages) = @_;

    #- update provides according to dependencies, here are stored
    #- reference to package directly and choice are included, this
    #- assume only 1 of the choice is selected, else on unselection
    #- the provided package will be deleted where other package still
    #- need it.
    #- base package are not updated because they cannot be unselected,
    #- this save certainly a lot of memory since most of them may be
    #- needed by a large number of package.

    foreach my $pkg (@{$packages->[1]}) {
	packageFlagBase($pkg) and next;
	map { my $provided = $packages->[1][$_] or die "invalid package index $_";
	      packageFlagBase($provided) or push @{$provided->{provides} ||= []}, $pkg;
	  } map { split '\|' } grep { !/^NOTFOUND_/ } packageDepsId($pkg);
    }
}

sub readCompss {
    my ($prefix, $packages) = @_;
    my ($p, @compss);

    #- this is necessary for urpmi.
    install_any::getAndSaveFile('Mandrake/base/compss', "$prefix/var/lib/urpmi/compss");

    local *F;
    open F, "$prefix/var/lib/urpmi/compss" or die "can't find compss";
    foreach (<F>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    $p = $1;
	} else {
	    /(\S+)/;
	    $packages->[0]{$1} or log::l("unknown package $1 in compss"), next;
	    push @compss, "$p/$1";
	}
    }
    \@compss;
}

sub readCompssList {
    my ($packages, $langs) = @_;
    my $f = install_any::getFile('Mandrake/base/compssList') or die "can't find compssList";
    my @levels = split ' ', <$f>;

    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	my ($name, @values) = split;
	my $p = packageByName($packages, $name) or log::l("unknown entry $name (in compssList)"), next;
	$p->{values} = \@values;
    }

    my %done;
    foreach (@$langs) {
	my $p = packageByName($packages, "locales-$_") or next;
	foreach ($p, @{$p->{provides} || []}, map { packageByName($packages, $_) } @{$by_lang{$_} || []}) {
	    next if !$_ || $done{$_}; $done{$_} = 1;
	    $_->{values} = [ map { $_ + 90 } @{$_->{values} || [ (0) x @levels ]} ];
	}
    }
    my $l = { map_index { $_ => $::i } @levels };
}

sub readCompssUsers {
    my ($packages, $compss, $meta_class) = @_;
    my (%compssUsers, %compssUsersIcons, , %compssUsersDescr, @sorted, $l);
    my (%compss); 
    foreach (@$compss) {
	local ($_, $a) = m|(.*)/(.*)|;
	do { push @{$compss{$_}}, $a } while s|/[^/]+||;
    }

    my $map = sub {
	$l or return;
	$_ = $packages->[0]{$_} or log::l("unknown package $_ (in compssUsers)") foreach @$l;
    };
    my $file = 'Mandrake/base/compssUsers';
    my $f = $meta_class && install_any::getFile("$file.$meta_class") || install_any::getFile($file) or die "can't find $file";
    foreach (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    &$map;
	    my ($icon, $descr);
	    /^(.*?)\s*\[icon=(.*?)\](.*)/  and $_ = "$1$3", $icon  = $2;
	    /^(.*?)\s*\[descr=(.*?)\](.*)/ and $_ = "$1$3", $descr = $2;
	    $compssUsersIcons{$_} = $icon; 
	    $compssUsersDescr{$_} = $descr; 
	    push @sorted, $_;
	    $compssUsers{$_} = $l = [];
	} elsif (/\s+\+(\S+)/) {
	    push @$l, $1;
	} elsif (/^\s+(.*?)\s*$/) {
	    push @$l, @{$compss{$1} || log::l("unknown category $1 (in compssUsers)") && []};
	}
    }
    &$map;
    \%compssUsers, \@sorted, \%compssUsersIcons, \%compssUsersDescr;
}

sub setSelectedFromCompssList {
    my ($compssListLevels, $packages, $min_level, $max_size, $install_class) = @_;
    my $ind = $compssListLevels->{$install_class}; defined $ind or log::l("unknown install class $install_class in compssList"), return;
    my $nb = selectedSize($packages);
    my @packages = allPackages($packages);
    my @places = do {
	#- special case for /^k/ aka kde stuff
	my @values = map { $_->{values}[$ind] } @packages;
	sort { $values[$b] <=> $values[$a] } 0 .. $#packages;
    };
    foreach (@places) {
	my $p = $packages[$_];
	next if packageFlagSkip($p);
	last if $p->{values}[$ind] < $min_level;

	#- determine the packages that will be selected when
	#- selecting $p. the packages are not selected.
	my %newSelection;
	selectPackage($packages, $p, 0, \%newSelection);

	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (grep { $newSelection{$_} } keys %newSelection) {
	    $nb += packageSize($packages->[0]{$_});
	}
	if ($max_size && $nb > $max_size) {
	    $nb = $old_nb;
	    $min_level = $p->{values}[$ind];
	    last;
	}

	#- at this point the package can safely be selected.
	selectPackage($packages, $p);
    }
    log::l("setSelectedFromCompssList: reached size $nb, up to indice $min_level (less than $max_size)");
    $ind, $min_level;
}

#- usefull to know the size it would take for a given min_level/max_size
#- just saves the selected packages, call setSelectedFromCompssList and restores the selected packages
sub saveSelected {
    my ($packages) = @_;
    my @l = values %{$packages->[0]};
    my @flags = map { pkgs::packageFlagSelected($_) } @l;
    [ $packages, \@l, \@flags ];
}
sub restoreSelected {
    my ($packages, $l, $flags) = @{$_[0]};
    mapn { pkgs::packageSetFlagSelected(@_) } $l, $flags;
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
    #- seems no more necessary to rpmdbInit ?
    #c::rpmdbOpen($prefix) or die "creation of rpm database failed: ", c::rpmErrorString();
}

sub done_db {
    log::l("closing install.log file");
    close LOG;
}

sub versionCompare($$) {
    my ($a, $b) = @_;
    local $_;

    while ($a || $b) {
	my ($sb, $sa) =  map { $1 if $a =~ /^\W*\d/ ? s/^\W*0*(\d+)// : s/^\W*(\D+)// } ($b, $a);
	$_ = length($sa) cmp length($sb) || $sa cmp $sb and return $_;
    }
}

sub selectPackagesAlreadyInstalled {
    my ($packages, $prefix) = @_;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpenForTraversal($prefix) or die "unable to open $prefix/var/lib/rpm/packages.rpm";
    log::l("opened rpm database for examining existing packages");

    #- this method has only one objectif, check the presence of packages
    #- already installed and avoid installing them again. this is to be used
    #- with oem installation, if the database exists, preselect the packages
    #- installed WHATEVER their version/release (log if a problem is perceived
    #- is enough).
    c::rpmdbTraverse($db, sub {
			 my ($header) = @_;
			 my $p = $packages->[0]{c::headerGetEntry($header, 'name')};

			 if ($p) {
			     my $version_cmp = versionCompare(c::headerGetEntry($header, 'version'), packageVersion($p));
			     my $version_rel_test = $version_cmp > 0 || $version_cmp == 0 &&
			       versionCompare(c::headerGetEntry($header, 'release'), packageRelease($p)) >= 0;
			     $version_rel_test or log::l("keeping an older package, avoiding selecting $p->{file}");
			     packageSetFlagInstalled($p, 1);
			 }
		     });

    log::l("before closing db");
    #- close db, job finished !
    c::rpmdbClose($db);
    log::l("done selecting packages to upgrade");

}

sub selectPackagesToUpgrade($$$;$$) {
    my ($packages, $prefix, $base, $toRemove, $toSave) = @_;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $db = c::rpmdbOpenForTraversal($prefix) or die "unable to open $prefix/var/lib/rpm/packages.rpm";
    log::l("opened rpm database for examining existing packages");

    #- get filelist of package to avoid getting all header into memory.
    my %filelist;
    my $current;
    my $f = install_any::getFile('Mandrake/base/filelist') or log::l("unable to get filelist of packages");
    foreach (<$f>) {
	chomp;
	if (/^#(.*)/) {
	    $current = $filelist{$1} = [];
	} else {
	    push @$current, $_;
	}
    }

    local $_; #- else perl complains on the map { ... } grep { ... } @...;
    my %installedFilesForUpgrade; #- help searching package to upgrade in regard to already installed files.

    #- used for package that are not correctly updated.
    #- should only be used when nothing else can be done correctly.
    my %upgradeNeedRemove = (
			     'libstdc++' => 1,
			     'compat-glibc' => 1,
			     'compat-libs' => 1,
			    );

    #- these package are not named as ours, need to be translated before working.
    #- a version may follow to setup a constraint 'installed version greater than'.
    my %otherPackageToRename = (
				'qt' => [ 'qt2', '2.0' ],
				'qt1x' => [ 'qt' ],
			       );
    #- generel purpose for forcing upgrade of package whatever version is.
    my %packageNeedUpgrade = (
			      'lilo' => 1, #- this package has been misnamed in 7.0.
			     );

    #- help removing package which may have different release numbering
    my %toRemove; map { $toRemove{$_} = 1 } @{$toRemove || []};

    #- mark all files which are not in /etc/rc.d/ for packages which are already installed but which
    #- are not in the packages list to upgrade.
    #- the 'installed' property will make a package unable to be selected, look at select.
    c::rpmdbTraverse($db, sub {
			 my ($header) = @_;
			 my $otherPackage = (c::headerGetEntry($header, 'release') !~ /mdk\w*$/ &&
					     (c::headerGetEntry($header, 'name'). '-' .
					      c::headerGetEntry($header, 'version'). '-' .
					      c::headerGetEntry($header, 'release')));
			 my $renaming = $otherPackage && $otherPackageToRename{c::headerGetEntry($header, 'name')};
			 my $name = $renaming &&
			   (!$renaming->[1] || versionCompare(c::headerGetEntry($header, 'version'), $renaming->[1]) >= 0) &&
			     $renaming->[0];
			 $name and $packageNeedUpgrade{$name} = 1; #- keep in mind to force upgrading this package.
			 my $p = $packages->[0]{$name || c::headerGetEntry($header, 'name')};

			 if ($p) {
			     my $version_cmp = versionCompare(c::headerGetEntry($header, 'version'), packageVersion($p));
			     my $version_rel_test = $version_cmp > 0 || $version_cmp == 0 &&
			       versionCompare(c::headerGetEntry($header, 'release'), packageRelease($p)) >= 0;
			     if ($version_rel_test) { #- by default, package selecting are upgrade whatever version is !
				 if ($otherPackage && $version_cmp <= 0) {
				     log::l("force upgrading $otherPackage since it will not be updated otherwise");
				 } else {
				     packageSetFlagInstalled($p, 1);
				 }
			     } elsif ($upgradeNeedRemove{packageName($p)}) {
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
    foreach (values %{$packages->[0]}) {
	my $p = $_;
	my $skipThis = 0;
	my $count = c::rpmdbNameTraverse($db, packageName($p), sub {
					     my ($header) = @_;
					     $skipThis ||= packageFlagInstalled($p);
					 });

	#- skip if not installed (package not found in current install).
	$skipThis ||= ($count == 0);

	#- make sure to upgrade package that have to be upgraded.
	$packageNeedUpgrade{packageName($p)} and $skipThis = 0;

	#- select the package if it is already installed with a lower version or simply not installed.
	unless ($skipThis) {
	    my $cumulSize;

	    selectPackage($packages, $p);

	    #- keep in mind installed files which are not being updated. doing this costs in
	    #- execution time but use less memory, else hash all installed files and unhash
	    #- all file for package marked for upgrade.
	    c::rpmdbNameTraverse($db, packageName($p), sub {
				     my ($header) = @_;
				     $cumulSize += c::headerGetEntry($header, 'size'); #- all these will be deleted on upgrade.
				     my @files = c::headerGetEntry($header, 'filenames');
				     @installedFilesForUpgrade{grep { ($_ !~ m|^/etc/rc.d/| &&
								       ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
				 });
	    if (my $list = $filelist{packageName($p)}) {
		my @commonparts = map { /^=(.*)/ ? ($1) : () } @$list;
		map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m|^/etc/rc.d/| }
		  map { /^(\d)(.*)/ ? ($commonparts[$1] . $2) : /^ (.*)/ ? ($1) : () } @$list;
	    }

	    #- keep in mind the cumul size of installed package since they will be deleted
	    #- on upgrade.
	    $p->{installedCumulSize} = $cumulSize;
	}
    }

    #- unmark all files for all packages marked for upgrade. it may not have been done above
    #- since some packages may have been selected by depsList.
    foreach (values %{$packages->[0]}) {
	my $p = $_;

	if (packageFlagSelected($p)) {
	    if (my $list = $filelist{packageName($p)}) {
		my @commonparts = map { /^=(.*)/ ? ($1) : () } @$list;
		map { delete $installedFilesForUpgrade{$_} } grep { $_ !~ m|^/etc/rc.d/| }
		  map { /^(\d)(.*)/ ? ($commonparts[$1] . $2) : /^ (.*)/ ? ($1) : () } @$list;
	    }
	}
    }

    #- select packages which contains marked files, then unmark on selection.
    foreach (values %{$packages->[0]}) {
	my $p = $_;

	unless (packageFlagSelected($p)) {
	    my $toSelect = 0;
	    if (my $list = $filelist{packageName($p)}) {
		my @commonparts = map { /^=(.*)/ ? ($1) : () } @$list;
		map { if (exists $installedFilesForUpgrade{$_}) {
		    $toSelect ||= ! -d "$prefix/$_" && ! -l "$prefix/$_"; delete $installedFilesForUpgrade{$_} }
		  } grep { $_ !~ m|^/etc/rc.d/| } map { /^(\d)(.*)/ ? ($commonparts[$1] . $2) : /^ (.*)/ ? ($1) : () } @$list;
	    }
	    selectPackage($packages, $p) if ($toSelect);
	}
    }

    #- select packages which obseletes other package, obselete package are not removed,
    #- should we remove them ? this could be dangerous !
    foreach (values %{$packages->[0]}) {
	my $p = $_;

	if (my $list = $filelist{packageName($p)}) {
	    my @obsoletes = map { /^\*(.*)/ ? ($1) : () } @$list;
	    map { selectPackage($packages, $p) if c::rpmdbNameTraverse($db, $_) > 0 } @obsoletes;
	}
    }

    #- keep a track of packages that are been selected for being upgraded,
    #- these packages should not be unselected.
    foreach (values %{$packages->[0]}) {
	my $p = $_;

	packageSetFlagUpgrade($p, 1) if packageFlagSelected($p);
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
				 if (packageFlagBase($packages->[0]{c::headerGetEntry($header, 'name')})) {
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

sub allowedToUpgrade { $_[0] !~ /^(kernel|kernel-secure|kernel-smp|kernel-linus|hackkernel)$/ }

sub installCallback {
    my $msg = shift;
    log::l($msg .": ". join(',', @_));
}

sub install($$$;$$) {
    my ($prefix, $isUpgrade, $toInstall, $depOrder, $media) = @_;
    my %packages;

    return if $::g_auto_install || !scalar(@$toInstall);

    #- for root loopback'ed /boot
    my $loop_boot = loopback::prepare_boot($prefix);

    #- first stage to extract some important informations
    #- about the packages selected. this is used to select
    #- one or many transaction.
    my ($total, $nb);
    foreach my $pkg (@$toInstall) {
	$packages{packageName($pkg)} = $pkg;
	$nb++;
	$total += packageSize($pkg);
    }

    log::l("pkgs::install $prefix");
    log::l("pkgs::install the following: ", join(" ", keys %packages));
    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    my $callbackOpen = sub {
	my $p = $packages{$_[0]};
	my $f = packageFile($p);
	print LOG "$f $p->{medium}{descr}\n";
	my $fd = install_any::getFile($f, $p->{medium}{descr});
	$fd ? fileno $fd : -1;
    };
    my $callbackClose = sub { packageSetFlagInstalled(delete $packages{$_[0]}, 1) };

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback("Starting installation", $nb, $total);

    my ($i, $min, $medium) = (0, 0, 1);
    do {
	my @transToInstall;

	if (!$depOrder || !$media) {
	    @transToInstall = values %packages;
	    $nb = 0;
	} else {
	    do {
		#- change current media if needed.
		if ($i > $media->{$medium}{max}) {
		    #- search for media that contains the desired package to install.
		    foreach (keys %$media) {
			$i >= $media->{$_}{min} && $i <= $media->{$_}{max} and $medium = $_, last;
		    }
		}
		$i >= $media->{$medium}{min} && $i <= $media->{$medium}{max} or die "unable to find right medium";
		install_any::useMedium($medium);

		while ($i <= $media->{$medium}{max} && ($i < $min || scalar @transToInstall < $limitMinTrans)) {
		    my $dep = $packages{packageName($depOrder->[$i++])} or next;
		    if ($dep->{medium}{selected}) {
			push @transToInstall, $dep;
			foreach (map { split '\|' } packageDepsId($dep)) {
			    $min < $_ and $min = $_;
			}
		    } else {
			log::l("ignoring package $dep->{file} as its medium is not selected");
		    }
		    --$nb; #- make sure the package is not taken into account as its medium is not selected.
		}
	    } while ($nb > 0 && scalar(@transToInstall) == 0); #- avoid null transaction, it a nop that cost a bit.
	}

	#- added to exit typically after last media unselected.
	if ($nb == 0 && scalar(@transToInstall) == 0) {
	    cleanHeaders($prefix);

	    loopback::save_boot($loop_boot);
	    return;
	}

	#- extract headers for parent as they are used by callback.
	extractHeaders($prefix, \@transToInstall, $media->{$medium});

	#- reset file descriptor open for main process but
	#- make sure error trying to change from hdlist are
	#- trown from main process too.
	install_any::getFile(packageFile($transToInstall[0]), $transToInstall[0]{medium}{descr});
	#- and make sure there are no staling open file descriptor too!
	install_any::getFile('XXX');

	#- reset ftp handlers before forking, otherwise well ;-(
	#require ftp;
	#ftp::rewindGetFile();

	local (*INPUT, *OUTPUT); pipe INPUT, OUTPUT;
	if (my $pid = fork()) {
	    close OUTPUT;
	    my $error_msg = '';
	    local $_;
	    while (<INPUT>) {
		if (/^die:(.*)/) {
		    $error_msg = $1;
		    last;
		} else {
		    chomp;
		    my @params = split ":";
		    if ($params[0] eq 'close') {
			&$callbackClose($params[1]);
		    } else {
			installCallback(@params);
		    }
		}
	    }
	    $error_msg and $error_msg .= join('', <INPUT>);
	    waitpid $pid, 0;
	    close INPUT;
	    $error_msg and die $error_msg;
	} else {
	    #- child process will run each transaction.
	    $SIG{SEGV} = sub { log::l("segmentation fault on transactions"); c::_exit(0) };
	    my $db;
	    eval {
		close INPUT;
		select((select(OUTPUT),  $| = 1)[0]);
		$db = c::rpmdbOpen($prefix) or die "error opening RPM database: ", c::rpmErrorString();
		my $trans = c::rpmtransCreateSet($db, $prefix);
		log::l("opened rpm database for transaction of ". scalar @transToInstall ." new packages, still $nb after that to do");

		c::rpmtransAddPackage($trans, $_->{header}, packageName($_), $isUpgrade && allowedToUpgrade(packageName($_)))
		    foreach @transToInstall;

		c::rpmdepOrder($trans) or
		    die "error ordering package list: " . c::rpmErrorString(), 
		      sub { c::rpmdbClose($db) };
		c::rpmtransSetScriptFd($trans, fileno LOG);

		log::l("rpmRunTransactions start");
		my @probs = c::rpmRunTransactions($trans, $callbackOpen,
						  sub { #- callbackClose
						      print OUTPUT "close:$_[0]\n"; },
						  sub { #- installCallback
						      print OUTPUT join(":", @_), "\n"; },
						  0);
		log::l("rpmRunTransactions done");

		if (@probs) {
		    my %parts;
		    @probs = reverse grep {
			if (s/(installing package) .* (needs (?:.*) on the (.*) filesystem)/$1 $2/) {
			    $parts{$3} ? 0 : ($parts{$3} = 1);
			} else { 1; }
		    } reverse map { s|/mnt||; $_ } @probs;

		    c::rpmdbClose($db);
		    die "installation of rpms failed:\n  ", join("\n  ", @probs);
		}
	    }; $@ and print OUTPUT "die:$@\n";

	    c::rpmdbClose($db);
	    log::l("rpm database closed");

	    close OUTPUT;
	    c::_exit(0);
	}
	c::headerFree(delete $_->{header}) foreach @transToInstall;
	cleanHeaders($prefix);

	if (my @badpkgs = grep { !packageFlagInstalled($_) && $_->{medium}{selected} && !exists($ignoreBadPkg{packageName($_)}) } @transToInstall) {
	    foreach (@badpkgs) {
		log::l("bad package $_->{file}");
		packageSetFlagSelected($_, 0);
	    }
	    cdie ("error installing package list: " . join(", ", map { $_->{file} } @badpkgs));
	}
    } while ($nb > 0 && !$pkgs::cancel_install);

    cleanHeaders($prefix);

    loopback::save_boot($loop_boot);
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
	c::rpmtransRemovePackages($db, $trans, $p) if allowedToUpgrade($p);
    }

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    my $callbackOpen = sub { log::l("trying to open file from $_[0] which should not happen"); };
    my $callbackClose = sub { log::l("trying to close file from $_[0] which should not happen"); };

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback("Starting removing other packages", scalar @$toRemove);

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, \&installCallback, 0)) {
	die "removing of old rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans);
    c::rpmdbClose($db);
    log::l("rpm database closed");

    #- keep in mind removing of these packages by cleaning $toRemove.
    @{$toRemove || []} = ();
}

1;
