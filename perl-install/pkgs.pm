package pkgs; # $Id$

use diagnostics;
use strict;
use vars qw(*LOG @preferred $limitMinTrans %compssListDesc);

use common qw(:common :file :functional :system);
use install_any;
use commands;
use run_program;
use detect_devices;
use log;
use pkgs;
use fs;
use loopback;
use c;



@preferred = qw(perl-GTK postfix wu-ftpd ghostscript-X vim-minimal kernel ispell-en);

#- lower bound on the left ( aka 90 means [90-100[ )
%compssListDesc = (
   5 => __("must have"),
   4 => __("important"),
   3 => __("very nice"),
   2 => __("nice"),
   1 => __("maybe"),
);

#- constant for small transaction.
$limitMinTrans = 8;

#- constant for package accessor (via table).
my $FILE                 = 0;
my $FLAGS                = 1;
my $SIZE_DEPS            = 2;
my $MEDIUM               = 3;
my $PROVIDES             = 4;
my $VALUES               = 5;
my $HEADER               = 6;
my $INSTALLED_CUMUL_SIZE = 7;

#- constant for packing flags, see below.
my $PKGS_SELECTED  = 0x00ffffff;
my $PKGS_FORCE     = 0x01000000;
my $PKGS_INSTALLED = 0x02000000;
my $PKGS_BASE      = 0x04000000;
my $PKGS_UPGRADE   = 0x20000000;

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
sub packageHeaderFile   { $_[0]->[$FILE] }
sub packageName         { $_[0]->[$FILE] =~ /(.*)-[^-]+-[^-]+\..*/ ? $1 : die "invalid file `$_[0]->[$FILE]'" }
sub packageVersion      { $_[0]->[$FILE] =~ /.*-([^-]+)-[^-]+\..*/ ? $1 : die "invalid file `$_[0]->[$FILE]'" }
sub packageRelease      { $_[0]->[$FILE] =~ /.*-[^-]+-([^-]+)\..*/ ? $1 : die "invalid file `$_[0]->[$FILE]'" }
sub packageArch         { $_[0]->[$FILE] =~ /.*-[^-]+-[^-]+\.(.*)/ ? $1 : die "invalid file `$_[0]->[$FILE]'" }
sub packageFile         { $_[0]->[$FILE] . ".rpm" }

sub packageSize   { to_int($_[0]->[$SIZE_DEPS]) }
sub packageDepsId { split ' ', ($_[0]->[$SIZE_DEPS] =~ /^\d*\s*(.*)/)[0] }

sub packageFlagSelected  { $_[0]->[$FLAGS] & $PKGS_SELECTED }
sub packageFlagForce     { $_[0]->[$FLAGS] & $PKGS_FORCE }
sub packageFlagInstalled { $_[0]->[$FLAGS] & $PKGS_INSTALLED }
sub packageFlagBase      { $_[0]->[$FLAGS] & $PKGS_BASE }
sub packageFlagUpgrade   { $_[0]->[$FLAGS] & $PKGS_UPGRADE }

sub packageSetFlagSelected  { $_[0]->[$FLAGS] &= ~$PKGS_SELECTED; $_[0]->[$FLAGS] |= $_[1] & $PKGS_SELECTED; }

sub packageSetFlagForce     { $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_FORCE)     : ($_[0]->[$FLAGS] &= ~$PKGS_FORCE); }
sub packageSetFlagInstalled { $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_INSTALLED) : ($_[0]->[$FLAGS] &= ~$PKGS_INSTALLED); }
sub packageSetFlagBase      { $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_BASE)      : ($_[0]->[$FLAGS] &= ~$PKGS_BASE); }
sub packageSetFlagUpgrade   { $_[1] ? ($_[0]->[$FLAGS] |= $PKGS_UPGRADE)   : ($_[0]->[$FLAGS] &= ~$PKGS_UPGRADE); }

sub packageMedium { $_[0]->[$MEDIUM] }

sub packageProvides { map { $_[0]->{depslist}[$_] || die "unkown package id $_" } unpack "s*", $_[1]->[$PROVIDES] }

sub packageRate { substr($_[0]->[$VALUES], 0, 1) }

sub packageHeader     { $_[0]->[$HEADER] }
sub packageFreeHeader { c::headerFree(delete $_[0]->[$HEADER]) }

sub packageSelectedOrInstalled { packageFlagSelected($_[0]) || packageFlagInstalled($_[0]) }

sub packageId {
    my ($packages, $pkg) = @_;
    my $i = 0;
    foreach (@{$packages->{depslist}}) { return $i if $pkg == $packages->{depslist}[$i]; $i++ }
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

    eval {
	require packdrake;
	my $packer = new packdrake("/tmp/$medium->{hdlist}");
	$packer->extract_archive("$prefix/tmp/headers", map { packageHeaderFile($_) } @$pkgs);
    };
    #run_program::run("packdrake", "-x",
	#	     "/tmp/$medium->{hdlist}",
	#	     "$prefix/tmp/headers",
	#	     map { packageHeaderFile($_) } @$pkgs);

    foreach (@$pkgs) {
	my $f = "$prefix/tmp/headers/". packageHeaderFile($_);
	local *H;
	open H, $f or log::l("unable to open header file $f: $!"), next;
	$_->[$HEADER] = c::headerRead(fileno H, 1) or log::l("unable to read header of package ". packageHeaderFile($_));
    }
    @$pkgs = grep { $_->[$HEADER] } @$pkgs;
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
    foreach (values %{$packages->{names}}) {
	packageFlagSelected($_) && !packageFlagInstalled($_) and $size += packageSize($_) - ($_->[$INSTALLED_CUMUL_SIZE] || 0);
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
    $packages->{names}{$name} or log::l("unknown package `$name'") && undef;
}
sub packageById {
    my ($packages, $id) = @_;
    $packages->{depslist}[$id] or log::l("unknown package id $id") && undef;
}
sub packagesOfMedium {
    my ($packages, $mediumName) = @_;
    my $medium = $packages->{mediums}{$mediumName};
    grep { $_->[$MEDIUM] == $medium } @{$packages->{depslist}};
}
sub packagesToInstall {
    my ($packages) = @_;
    grep { $_->[$MEDIUM]{selected} && packageFlagSelected($_) && !packageFlagInstalled($_) } values %{$packages->{names}};
}

sub allMediums {
    my ($packages) = @_;
    keys %{$packages->{mediums}};
}
sub mediumDescr {
    my ($packages, $medium) = @_;
    $packages->{mediums}{$medium}{descr};
}

#- selection, unselection of package.
sub selectPackage { #($$;$$$)
    my ($packages, $pkg, $base, $otherOnly, $check_recursion) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    packageFlagInstalled($pkg) and return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    $pkg->[$MEDIUM]{selected} or return;

    #- avoid infinite recursion (mainly against badly generated depslist.ordered).
    $check_recursion ||= {}; exists $check_recursion->{$pkg->[$FILE]} and return; $check_recursion->{$pkg->[$FILE]} = undef;

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
    foreach my $provided ($pkg, packageProvides($packages, $pkg)) {
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
    foreach (values %{$packages->{names}}) {
	unless (packageFlagBase($_) || packageFlagUpgrade($_)) {
	    packageSetFlagSelected($_, 0);
	}
    }
}
sub unselectAllPackagesIncludingUpgradable($) {
    my ($packages, $removeUpgradeFlag) = @_;
    foreach (values %{$packages->{names}}) {
	unless (packageFlagBase($_)) {
	    packageSetFlagSelected($_, 0);
	    packageSetFlagUpgrade($_, 0);
	}
    }
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
	my $fakemedium = "$descr ($method$medium)";
	my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
	-e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
	install_any::getAndSaveFile("Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
	symlinkf $newf, "/tmp/$hdlist";
	++$medium;
    }

    #- this is necessary for urpmi.
    install_any::getAndSaveFile("Mandrake/base/$_", "$prefix/var/lib/urpmi/$_")
      foreach qw(depslist.ordered provides compss rpmsrate);
}

sub psUsingHdlists {
    my ($prefix, $method) = @_;
    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";
    my %packages = ( names => {}, depslist => [], mediums => {});

    #- parse hdlists file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";

	#- make sure the first medium is always selected!
	#- by default select all image.
	psUsingHdlist($prefix, $method, \%packages, $1, $medium, $2, $3, 1);

	++$medium;
    }

    log::l("psUsingHdlists read " . scalar keys(%{$packages{names}}) .
	   " headers on " . scalar keys(%{$packages{mediums}}) . " hdlists");

    \%packages;
}

sub psUsingHdlist {
    my ($prefix, $method, $packages, $hdlist, $medium, $rpmsdir, $descr, $selected, $fhdlist) = @_;
    my $fakemedium = "$descr ($method$medium)";
    log::l("trying to read $hdlist for medium $medium");

    #- if the medium already exist, use it.
    $packages->{mediums}{$medium} and return;

    my $m = $packages->{mediums}{$medium} = { hdlist     => $hdlist,
					      method     => $method,
					      medium     => $medium,
					      rpmsdir    => $rpmsdir, #- where is RPMS directory.
					      descr      => $descr,
					      fakemedium => $fakemedium,
					      min        => scalar keys %{$packages->{names}},
					      max        => -1, #- will be updated after reading current hdlist.
					      selected   => $selected, #- default value is only CD1, it is really the minimal.
					    };

    #- copy hdlist file directly to $prefix/var/lib/urpmi, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $newf = "$prefix/var/lib/urpmi/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    -e $newf and do { unlink $newf or die "cannot remove $newf: $!"; };
    install_any::getAndSaveFile($fhdlist || "Mandrake/base/$hdlist", $newf) or die "no $hdlist found";
    symlinkf $newf, "/tmp/$hdlist";

    #- avoid using more than one medium if Cd is not ejectable.
    #- but keep all medium here so that urpmi has the whole set.
    $method eq 'cdrom' && $medium > 1 && isCdNotEjectable() and return;

    #- extract filename from archive, this take advantage of verifying
    #- the archive too.
    eval {
	require packdrake;
	my $packer = new packdrake($newf);
	foreach (@{$packer->{files}}) {
	    $packer->{data}{$_}[0] eq 'f' or next;
	    #if (/^f\s+\d+\s+(.*)/) {
	    #my $pkg = [ (undef) x 8 ]; $pkg->[$FILE] = $1; $pkg->[$MEDIUM] = $m;
	    my $pkg = [ (undef) x 8 ]; $pkg->[$FILE] = $_; $pkg->[$MEDIUM] = $m;
	    my $specific_arch = packageArch($pkg);
	    if (!$specific_arch || compat_arch($specific_arch)) {
		my $old_pkg = $packages->{names}{packageName($pkg)};
		if ($old_pkg) {
		    if (packageVersion($pkg) eq packageVersion($old_pkg) && packageRelease($pkg) eq packageRelease($old_pkg)) {
			if (better_arch($specific_arch, packageArch($old_pkg))) {
			    log::l("replacing old package with package $_ with better arch: $specific_arch");
			    $packages->{names}{packageName($pkg)} = $pkg;
			} else {
			    log::l("keeping old package against package $_ with worse arch");
			}
		    } else {
		        log::l("ignoring package $_ already present in distribution with different version or release");
		    }
		} else {
		    $packages->{names}{packageName($pkg)} = $pkg;
		}
	    } else {
	        log::l("ignoring package $_ with incompatible arch: $specific_arch");
	    }
	}
    };

    #- update maximal index.
    $m->{max} = scalar(keys %{$packages->{names}}) - 1;
    $m->{max} >= $m->{min} or die "nothing found while parsing $newf";
    log::l("read " . ($m->{max} - $m->{min} + 1) . " headers in $hdlist");
    1;
}

sub getOtherDeps($$) {
    my ($packages, $f) = @_;

    #- this version of getDeps is customized for handling errors more easily and
    #- convert reference by name to deps id including closure computation.
    local $_;
    while (<$f>) {
	my ($name, $version, $release, $size, $deps) = /^(\S*)-([^-\s]+)-([^-\s]+)\s+(\d+)\s+(.*)/;
	my $pkg = $packages->{names}{$name};

	$pkg or log::l("ignoring package $name-$version-$release in depslist is not in hdlist"), next;
	$version eq packageVersion($pkg) and $release eq packageRelease($pkg)
	  or log::l("warning package $name-$version-$release in depslist mismatch version or release in hdlist ($version ne ",
		    packageVersion($pkg), " or $release ne ", packageRelease($pkg), ")"), next;

	my $index = scalar @{$packages->{depslist}};
	$index >= $pkg->[$MEDIUM]{min} && $index <= $pkg->[$MEDIUM]{max}
	  or log::l("ignoring package $name-$version-$release in depslist outside of hdlist indexation");

	#- here we have to translate referenced deps by name to id.
	#- this include a closure on deps too.
	my %closuredeps;
	@closuredeps{map { packageId($packages, $_), packageDepsId($_) }
		       grep { $_ }
			 map { packageByName($packages, $_) or do { log::l("unknown package $_ in depslist for closure"); undef } }
			   split /\s+/, $deps} = ();

	$pkg->[$SIZE_DEPS] = join " ", $size, keys %closuredeps;

	push @{$packages->{depslist}}, $pkg;
    }

    #- check for same number of package in depslist and hdlists, avoid being to hard.
    scalar(keys %{$packages->{names}}) == scalar(@{$packages->{depslist}})
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
    local *F; open F, "$prefix/var/lib/urpmi/depslist.ordered" or die "can't find dependancies list";
    local $_;
    while (<F>) {
	my ($name, $version, $release, $sizeDeps) = /^(\S*)-([^-\s]+)-([^-\s]+)\s+(.*)/;
	my $pkg = $packages->{names}{$name};

	#- these verification are necessary in case of error, but are no more fatal as
	#- in case of only one medium taken into account during install, there should be
	#- silent warning for package which are unknown at this point.
	$pkg or
	  log::l("ignoring $name-$version-$release in depslist is not in hdlist"), next;
	$version eq packageVersion($pkg) or
	  log::l("ignoring $name-$version-$release in depslist mismatch version in hdlist"), next;
	$release eq packageRelease($pkg) or
	  log::l("ignoring $name-$version-$release in depslist mismatch release in hdlist"), next;

	$pkg->[$SIZE_DEPS] = $sizeDeps;

	#- check position of package in depslist according to precomputed
	#- limit by hdlist, very strict :-)
	#- above warning have chance to raise an exception here, but may help
	#- for debugging.
	my $i = scalar @{$packages->{depslist}};
	$i >= $pkg->[$MEDIUM]{min} && $i <= $pkg->[$MEDIUM]{max} or
	  log::l("inconsistency in position for $name-$version-$release in depslist and hdlist"), $mismatch = 1;

	#- package are already sorted in depslist to enable small transaction and multiple medium.
	push @{$packages->{depslist}}, $pkg;
    }

    #- check for mismatching package, it should break with above die unless depslist has too many errors!
    $mismatch and die "depslist.ordered mismatch against hdlist files";

    #- check for same number of package in depslist and hdlists.
    scalar(keys %{$packages->{names}}) == scalar(@{$packages->{depslist}})
      or die "depslist.ordered has not same package as hdlist files";
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
    #- now using a packed of signed short, this means no more than 32768
    #- packages can be managed by DrakX (currently about 2000).
    my $i = 0;
    foreach my $pkg (@{$packages->{depslist}}) {
	unless (packageFlagBase($pkg)) {
	    foreach (map { split '\|' } grep { !/^NOTFOUND_/ } packageDepsId($pkg)) {
		my $provided = $packages->{depslist}[$_] or die "invalid package index $_";
		packageFlagBase($provided) or $provided->[$PROVIDES] = pack "s*", (unpack "s*", $provided->[$PROVIDES]), $i;
	    }
	}
	++$i;
    }
}

sub readCompss {
    my ($prefix, $packages) = @_;
    my ($p, @compss);

    #- this is necessary for urpmi.
    install_any::getAndSaveFile('Mandrake/base/compss', "$prefix/var/lib/urpmi/compss");

    local *F; open F, "$prefix/var/lib/urpmi/compss" or die "can't find compss";
    local $_;
    while (<F>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    $p = $1;
	} else {
	    /(\S+)/;
	    $packages->{names}{$1} or log::l("unknown package $1 in compss"), next;
	    push @compss, "$p/$1";
	}
    }
    \@compss;
}

sub read_rpmsrate {
    my ($packages, $f) = @_;
    my $line_nb = 0;
    my (@l);
    while (<$f>) {
	$line_nb++;
	/\t/ and die "tabulations not allowed at line $line_nb\n";
	s/#.*//; # comments

	my ($indent, $data) = /(\s*)(.*)/;
	next if !$data; # skip empty lines

	@l = grep { $_->[0] < length $indent } @l;

	my @m = @l ? @{$l[$#l][1]} : ();
	my ($t, $flag, @l2);
	while ($data =~ 
	       /^((
                   [1-5]
                   |
                   (?:            (?: !\s*)? [0-9A-Z_]+(?:".*?")?)
                   (?: \s*\|\|\s* (?: !\s*)? [0-9A-Z_]+(?:".*?")?)*
                  )
                  (?:\s+|$)
                 )(.*)/x) { #@")) {
	    ($t, $flag, $data) = ($1,$2,$3);
	    while ($flag =~ s,^\s*(("[^"]*"|[^"\s]*)*)\s+,$1,) {}
	    my $ok = 0;
	    $flag = join('||', grep { 
		if (my ($inv, $p) = /^(!)?PCI"(.*)"/) {
		    ($inv xor detect_devices::matching_desc($p)) and $ok = 1;
		    0;
		} else {
		    1;
		}
	    } split '\|\|', $flag);
	    push @m, $ok ? 'TRUE' : $flag || 'FALSE';
	    push @l2, [ length $indent, [ @m ] ];
	    $indent .= $t;
	}
	if ($data) {
	    # has packages on same line
	    my ($rate) = grep { /^\d$/ } @m or die sprintf qq(missing rate for "%s" at line %d (flags are %s)\n), $data, $line_nb, join('&&', @m);
	    foreach (split ' ', $data) {
		if ($packages) {
		    my $p = packageByName($packages, $_) or next;
		    $p->[$VALUES] = join("\t", $rate, grep { !/^\d$/ } @m);
		} else {
		    print "$_ = ", join(" && ", @m), "\n";
		}
	    }
	    push @l, @l2;
	} else {
	    push @l, [ $l2[0][0], $l2[$#l2][1] ];
	}
    }
}

sub readCompssUsers {
    my ($packages, $meta_class) = @_;
    my (%compssUsers, %compssUsersIcons, , %compssUsersDescr, @sorted, $l);
    my (%compss); 

    my $file = 'Mandrake/base/compssUsers';
    my $f = $meta_class && install_any::getFile("$file.$meta_class") || install_any::getFile($file) or die "can't find $file";
    local $_;
    while (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    my ($icon, $descr);
	    /^(.*?)\s*\[icon=(.*?)\](.*)/  and $_ = "$1$3", $icon  = $2;
	    /^(.*?)\s*\[descr=(.*?)\](.*)/ and $_ = "$1$3", $descr = $2;
	    $compssUsersIcons{$_} = $icon; 
	    $compssUsersDescr{$_} = $descr; 
	    push @sorted, $_;
	    $compssUsers{$_} = $l = [];
	} elsif (/^\s+(.*?)\s*$/) {
	    push @$l, $1;
	}
    }
    \%compssUsers, \@sorted, \%compssUsersIcons, \%compssUsersDescr;
}

sub setSelectedFromCompssList {
    my ($packages, $compssUsersChoice, $min_level, $max_size, $install_class) = @_;
    $compssUsersChoice->{TRUE} = 1; #- ensure TRUE is set
    my $nb = selectedSize($packages);
    foreach my $p (sort { substr($a,0,1) <=> substr($b,0,1) } values %{$packages->{names}}) {
	my ($rate, @flags) = split "\t", $p->[$VALUES];
	next if !$rate || $rate < $min_level || grep { !grep { /^!(.*)/ ? !$compssUsersChoice->{$1} : $compssUsersChoice->{$_} } split('\|\|') } @flags;

	#- determine the packages that will be selected when
	#- selecting $p. the packages are not selected.
	my %newSelection;
	selectPackage($packages, $p, 0, \%newSelection);

	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (grep { $newSelection{$_} } keys %newSelection) {
	    $nb += packageSize($packages->{names}{$_});
	}
	if ($max_size && $nb > $max_size) {
	    $nb = $old_nb;
	    $min_level = packageRate($p);
	    last;
	}

	#- at this point the package can safely be selected.
	selectPackage($packages, $p);
    }
    log::l("setSelectedFromCompssList: reached size ", formatXiB($nb), ", up to indice $min_level (less than ", formatXiB($max_size), ")");
    $min_level;
}

#- usefull to know the size it would take for a given min_level/max_size
#- just saves the selected packages, call setSelectedFromCompssList and restores the selected packages
sub saveSelected {
    my ($packages) = @_;
    my @l = values %{$packages->{names}};
    my @flags = map { pkgs::packageFlagSelected($_) } @l;
    [ $packages, \@l, \@flags ];
}
sub restoreSelected {
    my ($packages, $l, $flags) = @{$_[0]};
    mapn { pkgs::packageSetFlagSelected(@_) } $l, $flags;
}


sub init_db {
    my ($prefix) = @_;

    my $f = "$prefix/root/install.log";
    open(LOG, "> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept.");
    *LOG or *LOG = log::F() or *LOG = *STDERR;
    CORE::select((CORE::select(LOG), $| = 1)[0]);
    c::rpmErrorSetCallback(fileno LOG);
#-    c::rpmSetVeryVerbose();

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");
}

sub rebuild_db_open_for_traversal {
    my ($packages, $prefix) = @_;

    log::l("reading /usr/lib/rpm/rpmrc");
    c::rpmReadConfigFiles() or die "can't read rpm config files";
    log::l("\tdone");

    unless (exists $packages->{rebuild_db}) {
	if (my $pid = fork()) {
	    waitpid $pid, 0;
	    ($? & 0xff00) and die "rebuilding of rpm database failed";
	} else {
	    log::l("rebuilding rpm database");
	    my $rebuilddb_dir = "$prefix/var/lib/rpmrebuilddb.$$";
	    -d $rebuilddb_dir and log::l("removing stale directory $rebuilddb_dir"), commands::rm("-rf", $rebuilddb_dir);

	    my $failed;
	    c::rpmdbRebuild($prefix) or log::l("rebuilding of rpm database failed: ". c::rpmErrorString()), c::_exit(2);

	    foreach (qw(Basenames Conflictname Group Name Packages Providename Requirename Triggername)) {
		-s "$prefix/var/lib/rpm/$_" or $failed = 'failed';
	    }
	    #- rebuilding has been successfull, so remove old rpm database if any.
	    #- once we have checked the rpm4 db file are present and not null, in case
	    #- of doubt, avoid removing them...
	    unless ($failed) {
		log::l("rebuilding rpm database completed successfully");
		foreach (qw(conflictsindex.rpm fileindex.rpm groupindex.rpm nameindex.rpm packages.rpm
                        providesindex.rpm requiredby.rpm triggerindex.rpm)) {
		    -e "$prefix/var/lib/rpm/$_" or next;
		    log::l("removing old rpm file $_");
		    commands::rm("-f", "$prefix/var/lib/rpm/$_");
		}
	    }
	    c::_exit(0);
	}
	$packages->{rebuild_db} = undef;
    }

    my $db = c::rpmdbOpenForTraversal($prefix) or die "unable to open $prefix/var/lib/rpm/Packages";
    log::l("opened rpm database for examining existing packages");

    $db;
}

sub done_db {
    log::l("closing install.log file");
    close LOG;
}

sub versionCompare($$) {
    my ($a, $b) = @_;
    local $_;

    while ($a || $b) {
	my ($sb, $sa) =  map { $1 if $a =~ /^\W*\d/ ? s/^\W*0*(\d+)// : s/^\W*(\D*)// } ($b, $a);
	$_ = length($sa) cmp length($sb) || $sa cmp $sb and return $_;
	$sa eq '' && $sb eq '' and return $a cmp $b || 0;
    }
}

sub selectPackagesAlreadyInstalled {
    my ($packages, $prefix) = @_;
    my $db = rebuild_db_open_for_traversal($packages, $prefix);

    #- this method has only one objectif, check the presence of packages
    #- already installed and avoid installing them again. this is to be used
    #- with oem installation, if the database exists, preselect the packages
    #- installed WHATEVER their version/release (log if a problem is perceived
    #- is enough).
    c::rpmdbTraverse($db, sub {
			 my ($header) = @_;
			 my $p = $packages->{names}{c::headerGetEntry($header, 'name')};

			 if ($p) {
			     my $version_cmp = versionCompare(c::headerGetEntry($header, 'version'), packageVersion($p));
			     my $version_rel_test = $version_cmp > 0 || $version_cmp == 0 &&
			       versionCompare(c::headerGetEntry($header, 'release'), packageRelease($p)) >= 0;
			     $version_rel_test or log::l("keeping an older package, avoiding selecting $p->[$FILE]");
			     packageSetFlagInstalled($p, 1);
			 }
		     });

    #- close db, job finished !
    c::rpmdbClose($db);
    log::l("done selecting packages to upgrade");
}

sub selectPackagesToUpgrade($$$;$$) {
    my ($packages, $prefix, $base, $toRemove, $toSave) = @_;
    local $_; #- else perl complains on the map { ... } grep { ... } @...;

    local (*UPGRADE_INPUT, *UPGRADE_OUTPUT); pipe UPGRADE_INPUT, UPGRADE_OUTPUT;
    if (my $pid = fork()) {
	@{$toRemove || []} = (); #- reset this one.

	close UPGRADE_OUTPUT;
	while (<UPGRADE_INPUT>) {
	    chomp;
	    my ($action, $name) = /^([\w\d]*):(.*)/;
	    for ($action) {
		/remove/    and do { push @$toRemove, $name; next };
		/keepfiles/ and do { push @$toSave, $name; next };

		my $p = $packages->{names}{$name} or die "unable to find package ($name)";
		/^\d*$/     and do { $p->[$INSTALLED_CUMUL_SIZE] = $action; next };
		/installed/ and do { packageSetFlagInstalled($p, 1); next };
		/select/    and do { selectPackage($packages, $p); next };

		die "unknown action ($action)";
	    }
	}
	close UPGRADE_INPUT;
	waitpid $pid, 0;
    } else {
	close UPGRADE_INPUT;
	
	my $db = rebuild_db_open_for_traversal($packages, $prefix);
	#- used for package that are not correctly updated.
	#- should only be used when nothing else can be done correctly.
	my %upgradeNeedRemove = (
				 'libstdc++' => 1,
				 'compat-glibc' => 1,
				 'compat-libs' => 1,
				);

	#- generel purpose for forcing upgrade of package whatever version is.
	my %packageNeedUpgrade = (
				  'lilo' => 1, #- this package has been misnamed in 7.0.
				 );

	#- help removing package which may have different release numbering
	my %toRemove; map { $toRemove{$_} = 1 } @{$toRemove || []};

	#- help searching package to upgrade in regard to already installed files.
	my %installedFilesForUpgrade;

	#- help keeping memory by this set of package that have been obsoleted.
	my %obsoletedPackages;

	#- make a subprocess here for reading filelist, this is important
	#- not to waste a lot of memory for the main program which will fork
	#- latter for each transaction.
	local (*INPUT, *OUTPUT_CHILD); pipe INPUT, OUTPUT_CHILD;
	local (*INPUT_CHILD, *OUTPUT); pipe INPUT_CHILD, OUTPUT;
	if (my $pid = fork()) {
	    close INPUT_CHILD;
	    close OUTPUT_CHILD;
	    select((select(OUTPUT), $| = 1)[0]);

	    #- internal reading from interactive mode of parsehdlist.
	    #- takes a code to call with the line read, this avoid allocating
	    #- memory for that.
	    my $ask_child = sub {
		my ($name, $tag, $code) = @_;
		$code or die "no callback code for parsehdlist output";
		print OUTPUT "$name:$tag\n";

		local $_;
		while (<INPUT>) {
		    chomp;
		    /^\s*$/ and last;
		    $code->($_);
		}
	    };

	    #- select packages which obseletes other package, obselete package are not removed,
	    #- should we remove them ? this could be dangerous !
	    foreach my $p (values %{$packages->{names}}) {
		$ask_child->(packageName($p), "obsoletes", sub {
				 #- take care of flags and version and release if present
				 if ($_[0] =~ /^(\S*)\s*(\S*)\s*([^\s-]*)-?(\S*)/ && c::rpmdbNameTraverse($db, $1) > 0) {
				     $3 and eval(versionCompare(packageVersion($p), $3) . $2 . 0) or next;
				     $4 and eval(versionCompare(packageRelease($p), $4) . $2 . 0) or next;
				     log::l("selecting " . packageName($p) . " by selection on obsoletes");
				     $obsoletedPackages{$1} = undef;
				     selectPackage($packages, $p);
				 }
			     });
	    }

	    #- mark all files which are not in /etc/rc.d/ for packages which are already installed but which
	    #- are not in the packages list to upgrade.
	    #- the 'installed' property will make a package unable to be selected, look at select.
	    c::rpmdbTraverse($db, sub {
				 my ($header) = @_;
				 my $otherPackage = (c::headerGetEntry($header, 'release') !~ /mdk\w*$/ &&
						     (c::headerGetEntry($header, 'name'). '-' .
						      c::headerGetEntry($header, 'version'). '-' .
						      c::headerGetEntry($header, 'release')));
				 my $p = $packages->{names}{c::headerGetEntry($header, 'name')};

				 if ($p) {
				     my $version_cmp = versionCompare(c::headerGetEntry($header, 'version'), packageVersion($p));
				     my $version_rel_test = $version_cmp > 0 || $version_cmp == 0 &&
				       versionCompare(c::headerGetEntry($header, 'release'), packageRelease($p)) >= 0;
				     if ($packageNeedUpgrade{packageName($p)}) {
					 log::l("package ". packageName($p) ." need to be upgraded");
				     } elsif ($version_rel_test) { #- by default, package are upgraded whatever version is !
					 if ($otherPackage && $version_cmp <= 0) {
					     log::l("force upgrading $otherPackage since it will not be updated otherwise");
					 } else {
					     #- let the parent known this installed package.
					     print UPGRADE_OUTPUT "installed:" . packageName($p) . "\n";
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
				     if (! exists $obsoletedPackages{c::headerGetEntry($header, 'name')}) {
					 my @files = c::headerGetEntry($header, 'filenames');
					 @installedFilesForUpgrade{grep { ($_ !~ m|^/etc/rc.d/| && $_ !~ m|\.la$| &&
									   ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
				     }
				 }
			     });

	    #- find new packages to upgrade.
	    foreach my $p (values %{$packages->{names}}) {
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
					     $cumulSize += c::headerGetEntry($header, 'size');
					     my @files = c::headerGetEntry($header, 'filenames');
					     @installedFilesForUpgrade{grep { ($_ !~ m|^/etc/rc.d/| && $_ !~ m|\.la$| &&
									   ! -d "$prefix/$_" && ! -l "$prefix/$_") } @files} = ();
					 });

		    $ask_child->(packageName($p), "files", sub {
				     delete $installedFilesForUpgrade{$_[0]};
				 });

		    #- keep in mind the cumul size of installed package since they will be deleted
		    #- on upgrade, only for package that are allowed to be upgraded.
		    if (allowedToUpgrade(packageName($p))) {
			print UPGRADE_OUTPUT "$cumulSize:" . packageName($p) . "\n";
		    }
		}
	    }

	    #- unmark all files for all packages marked for upgrade. it may not have been done above
	    #- since some packages may have been selected by depsList.
	    foreach my $p (values %{$packages->{names}}) {
		if (packageFlagSelected($p)) {
		    $ask_child->(packageName($p), "files", sub {
				     delete $installedFilesForUpgrade{$_[0]};
				 });
		}
	    }

	    #- select packages which contains marked files, then unmark on selection.
	    #- a special case can be made here, the selection is done only for packages
	    #- requiring locales if the locales are selected.
	    #- another special case are for devel packages where fixes over the time has
	    #- made some files moving between the normal package and its devel couterpart.
	    #- if only one file is affected, no devel package is selected.
	    foreach my $p (values %{$packages->{names}}) {
		unless (packageFlagSelected($p)) {
		    my $toSelect = 0;
		    $ask_child->(packageName($p), "files", sub {
				     if ($_[0] !~  m|^/etc/rc.d/| &&  $_ !~ m|\.la$| && exists $installedFilesForUpgrade{$_[0]}) {
					 ++$toSelect if ! -d "$prefix/$_[0]" && ! -l "$prefix/$_[0]";
				     }
				     delete $installedFilesForUpgrade{$_[0]};
				 });
		    if ($toSelect) {
			if ($toSelect <= 1 && packageName($p) =~ /-devel/) {
			    log::l("avoid selecting " . packageName($p) . " as not enough files will be updated");
			} else {
			    #- default case is assumed to allow upgrade.
			    my @deps = map { my $p = $packages->{depslist}[$_];
					     $p && packageName($p) =~ /locales-/ ? ($p) : () } packageDepsId($p);
			    if (@deps == 0 || @deps > 0 && (grep { !packageFlagSelected($_) } @deps) == 0) {
				log::l("selecting " . packageName($p) . " by selection on files");
				selectPackage($packages, $p);
			    } else {
				log::l("avoid selecting " . packageName($p) . " as its locales language is not already selected");
			    }
			}
		    }
		}
	    }

	    #- clean memory...
	    %installedFilesForUpgrade = ();

	    #- no need to still use the child as this point, we can let him to terminate.
	    close OUTPUT;
	    close INPUT;
	    waitpid $pid, 0;
	} else {
	    close INPUT;
	    close OUTPUT;
	    open STDIN, "<&INPUT_CHILD";
	    open STDOUT, ">&OUTPUT_CHILD";
	    exec "parsehdlist", "--interactive", map { "/tmp/$_->{hdlist}" } values %{$packages->{mediums}}
	      or c::_exit(1);
	}

	#- let the parent known about what we found here!
	foreach my $p (values %{$packages->{names}}) {
	    print UPGRADE_OUTPUT "select:" . packageName($p) . "\n" if packageFlagSelected($p);
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
				     print UPGRADE_OUTPUT "remove:$otherPackage\n";
				     if (packageFlagBase($packages->{names}{c::headerGetEntry($header, 'name')})) {
					 delete $toRemove{$otherPackage}; #- keep it selected, but force upgrade.
				     } else {
					 my @files = c::headerGetEntry($header, 'filenames');
					 my @flags = c::headerGetEntry($header, 'fileflags');
					 for my $i (0..$#flags) {
					     if ($flags[$i] & c::RPMFILE_CONFIG()) {
						 print UPGRADE_OUTPUT "keepfiles:$files[$i]\n" unless $files[$i] =~ /kdelnk/;
					     }
					 }
				     }
				 }
			     });
	}

	#- close db, job finished !
	c::rpmdbClose($db);
	log::l("done selecting packages to upgrade");

	close UPGRADE_OUTPUT;
	c::_exit(0);
    }

    #- keep a track of packages that are been selected for being upgraded,
    #- these packages should not be unselected (unless expertise)
    foreach my $p (values %{$packages->{names}}) {
	packageSetFlagUpgrade($p, 1) if packageFlagSelected($p);
    }
}

sub allowedToUpgrade { $_[0] !~ /^(kernel|kernel-secure|kernel-smp|kernel-linus|hackkernel)$/ }

sub installCallback {
#    my $msg = shift;
#    log::l($msg .": ". join(',', @_));
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
	print LOG "$f $p->[$MEDIUM]{descr}\n";
	my $fd = install_any::getFile($f, $p->[$MEDIUM]{descr});
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
		    if ($dep->[$MEDIUM]{selected}) {
			push @transToInstall, $dep;
			foreach (map { split '\|' } packageDepsId($dep)) {
			    $min < $_ and $min = $_;
			}
		    } else {
			log::l("ignoring package $dep->[$FILE] as its medium is not selected");
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

	if ($media->{$medium}{method} eq 'cdrom') {
	    #- reset file descriptor open for main process but
	    #- make sure error trying to change from hdlist are
	    #- trown from main process too.
	    install_any::getFile(packageFile($transToInstall[0]), $transToInstall[0][$MEDIUM]{descr});
	}
	#- and make sure there are no staling open file descriptor too (before forking)!
	install_any::getFile('XXX');

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

		c::rpmtransAddPackage($trans, $_->[$HEADER], packageName($_), $isUpgrade && allowedToUpgrade(packageName($_)))
		    foreach @transToInstall;

		c::rpmdepOrder($trans) or die "error ordering package list: " . c::rpmErrorString();
		c::rpmtransSetScriptFd($trans, fileno LOG);

		log::l("rpmRunTransactions start");
		my @probs = c::rpmRunTransactions($trans, $callbackOpen,
						  sub { #- callbackClose
						      print OUTPUT "close:$_[0]\n"; },
						  sub { #- installCallback
						      print OUTPUT join(":", @_), "\n"; },
						  1);
		log::l("rpmRunTransactions done, now trying to close still opened fd");
		install_any::getFile('XXX'); #- close still opened fd.

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
	packageFreeHeader($_) foreach @transToInstall;
	cleanHeaders($prefix);

	if (my @badpkgs = grep { !packageFlagInstalled($_) && $_->[$MEDIUM]{selected} && !exists($ignoreBadPkg{packageName($_)}) } @transToInstall) {
	    foreach (@badpkgs) {
		log::l("bad package $_->[$FILE]");
		packageSetFlagSelected($_, 0);
	    }
	    cdie ("error installing package list: " . join(", ", map { $_->[$FILE] } @badpkgs));
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

    if (my @probs = c::rpmRunTransactions($trans, $callbackOpen, $callbackClose, \&installCallback, 1)) {
	die "removing of old rpms failed:\n  ", join("\n  ", @probs);
    }
    c::rpmtransFree($trans);
    c::rpmdbClose($db);
    log::l("rpm database closed");

    #- keep in mind removing of these packages by cleaning $toRemove.
    @{$toRemove || []} = ();
}

sub selected_leaves {
    my ($packages) = @_;
    my %l;
    $l{$_->[$FILE]} = 1 foreach grep { packageFlagSelected($_) && !packageFlagBase($_) } @{$packages->{depslist}};

    my %m = %l;
    foreach (@{$packages->{depslist}}) {
	delete $m{$_->[$FILE]} or next;

	foreach (map { split '\|' } grep { !/^NOTFOUND_/ } packageDepsId($_)) {
	    delete $l{$packages->{depslist}[$_][$FILE]};
	}
    }
    [ map {
	my @l; $l[$FILE] = $_;
	packageName(\@l);
    } grep { $l{$_} } keys %l ];
}

1;
