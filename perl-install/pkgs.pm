package pkgs; # $Id$

use diagnostics;
use strict;

use MDK::Common::System;
use URPM;
use URPM::Resolve;
use URPM::Signature;
use common;
use install_any;
use run_program;
use detect_devices;
use log;
use fs;
use loopback;
use c;


our %preferred = map { $_ => undef } qw(perl-base XFree86-libs gstreamer-oss openjade ctags glibc curl sane-backends perl-GTK postfix mdkkdm gcc gcc-cpp gcc-c++ proftpd ghostscript-X vim-minimal kernel db1 db2 libxpm4 zlib1 libncurses5 harddrake cups apache);

#- lower bound on the left ( aka 90 means [90-100[ )
our %compssListDesc = (
   5 => N_("must have"),
   4 => N_("important"),
   3 => N_("very nice"),
   2 => N_("nice"),
   1 => N_("maybe"),
);

#- constant for small transaction.
our $limitMinTrans = 13;


#- package to ignore, typically in Application CD. OBSOLETED ?
my %ignoreBadPkg = (
		    'civctp-demo'   => 1,
		    'eus-demo'      => 1,
		    'myth2-demo'    => 1,
		    'heretic2-demo' => 1,
		    'heroes3-demo'  => 1,
		    'rt2-demo'      => 1,
		   );

sub packageMedium { my ($packages, $p) = @_; $p or die "invalid package from\n" . backtrace();
		    foreach (values %{$packages->{mediums}}) {
			defined $_->{start} && defined $_->{end} or next;
			$p->id >= $_->{start} && $p->id <= $_->{end} and return $_;
		    }
		    return }

sub cleanHeaders {
    my ($prefix) = @_;
    rm_rf("$prefix/tmp/headers") if -e "$prefix/tmp/headers";
}

#- get all headers from an hdlist file.
sub extractHeaders {
    my ($prefix, $pkgs, $media) = @_;
    my %medium2pkgs;

    cleanHeaders($prefix);

    foreach (@$pkgs) {
	foreach my $medium (values %$media) {
	    $_->id >= $medium->{start} && $_->id <= $medium->{end} or next;
	    push @{$medium2pkgs{$medium->{medium}} ||= []}, $_;
	}
    }

    foreach (keys %medium2pkgs) {
	my $medium = $media->{$_};

	eval {
	    require packdrake;
	    my $packer = new packdrake("/tmp/$medium->{hdlist}", quiet => 1);
	    $packer->extract_archive("$prefix/tmp/headers", map { $_->header_filename } @{$medium2pkgs{$_}});
	};
    }

    foreach (@$pkgs) {
	my $f = "$prefix/tmp/headers/" . $_->header_filename;
	$_->update_header($f) or log::l("unable to open header file $f"), next;
	log::l("read header file $f");
    }
}

#- TODO BEFORE TODO
#- size and correction size functions for packages.
my $B = 1.20873;
my $C = 4.98663; #- doesn't take hdlist's into account as getAvailableSpace will do it.
sub correctSize { $B * $_[0] + $C }
sub invCorrectSize { ($_[0] - $C) / $B }

sub selectedSize {
    my ($packages) = @_;
    my $size = 0;
    my %skip;
    #- take care of packages selected...
    foreach (@{$packages->{depslist}}) {
	if ($_->flag_selected) {
	    $size += $_->size;
	    #- if a package is obsoleted with the same name it should
	    #- have been selected, so a selected new package obsoletes
	    #- all the old package.
	    exists $skip{$_->name} and next; $skip{$_->name} = undef;
	    $size -= $packages->{sizes}{$_->name};
	}
    }
    #- but remove size of package being obsoleted or removed.
    foreach (keys %{$packages->{state}{rejected}}) {
	my ($name) = /(.*)-[^\-]*-[^\-]*$/ or next;
	exists $skip{$name} and next; $skip{$name} = undef;
	$size -= $packages->{sizes}{$name};
    }
    $size;
}
sub correctedSelectedSize { correctSize(selectedSize($_[0]) / sqr(1024)) }

sub size2time {
    my ($x, $max) = @_;
    my $A = 7e-07;
    my $limit = min($max * 3 / 4, 9e8);
    if ($x < $limit) {
	$A * $x;
    } else { 
	$x -= $limit;
	my $B = 6e-16;
	my $C = 15e-07;
	$B * $x ** 2 + $C * $x + $A * $limit;
    }
}


#- searching and grouping methods.
#- package is a reference to list that contains
#- a hash to search by name and
#- a list to search by id.
sub packageByName {
    my ($packages, $name) = @_;
    #- search package with given name and compatible with current architecture.
    #- take the best one found (most up-to-date).
    my @packages;
    foreach (keys %{$packages->{provides}{$name} || {}}) {
	my $pkg = $packages->{depslist}[$_];
	$pkg->is_arch_compat or next;
	$pkg->name eq $name or next;
	push @packages, $pkg;
    }
    my $best;
    foreach (@packages) {
	if ($best && $best != $_) {
	    $_->compare_pkg($best) > 0 and $best = $_;
	} else {
	    $best = $_;
	}
    }
    $best or log::l("unknown package `$name'") && undef;
}
sub packageById {
    my ($packages, $id) = @_;
    my $pkg = $packages->{depslist}[$id]; #- do not log as id unsupported are still in depslist.
    $pkg->is_arch_compat && $pkg;
}

sub bestKernelPackage {
    my ($packages) = @_;
    my $best;

    foreach (keys %{$packages->{provides}{kernel}}) {
	my $pkg = $packages->{depslist}[$_] or next;
	$pkg->name =~ /kernel-\d/ or next;
	!$best || $pkg->compare_pkg($best) > 0 and $best = $pkg;
    }

    $best;
}

sub packagesOfMedium {
    my ($packages, $medium) = @_;
    defined $medium->{start} && defined $medium->{end} ? @{$packages->{depslist}}[$medium->{start} .. $medium->{end}] : ();
}
sub packagesToInstall {
    my ($packages) = @_;
    my @packages;
    foreach (values %{$packages->{mediums}}) {
	$_->{selected} or next;
	log::l("examining packagesToInstall of medium $_->{descr}");
	push @packages, grep { $_->flag_selected } packagesOfMedium($packages, $_);
    }
    log::l("found " . scalar(@packages) . " packages to install");
    @packages;
}

sub allMediums {
    my ($packages) = @_;
    sort { $a <=> $b } keys %{$packages->{mediums}};
}
sub mediumDescr {
    my ($packages, $medium) = @_;
    $packages->{mediums}{$medium}{descr};
}

sub packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    foreach (values %{$packages->{mediums}}) {
	!$_->{selected} && $pkg->id >= $_->{start} && $pkg->id <= $_->{end} and return;
    }

    return { $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $_db, $state, $choices) = @_;
    if (my $prefer = find { exists $preferred{$_->name} } @$choices) {
	$prefer;
    } else {
	my @l = grep {
	    #- or if a kernel has to be chosen, chose the basic one.
	    $_->name =~ /kernel-\d/ and return $_;

	    #- or even if a package requires a specific locales which
	    #- is already selected.
	    find {
		/locales-/ && do {
		    my $p = packageByName($urpm, $_);
		    $p && $p->flag_available;
		};
	    } $_->requires_nosense;
	} @$choices;
	if (!@l) {
	    push @l, $choices->[0];
	    log::l("packageCallbackChoices: default choice from ", join(",", map { $urpm->{depslist}[$_]->name } keys %{$state->{selected}}), " in ", join(",", map { $_->name } @$choices));
	}
	#-log::l("packageCallbackChoices: chosen " . join(" ", map { $_->name } @l));
	@l;
    }
}

#- selection, unselection of package.
sub selectPackage {
    my ($packages, $pkg, $b_base, $o_otherOnly) = @_;

    #- select package and dependancies, o_otherOnly may be a reference
    #- to a hash to indicate package that will strictly be selected
    #- when value is true, may be selected when value is false (this
    #- is only used for unselection, not selection)
    my $state = $packages->{state} ||= {};

    my @l = $packages->resolve_requested($packages->{rpmdb}, $state, packageRequest($packages, $pkg) || {},
					 callback_choices => \&packageCallbackChoices);

    if ($b_base || $o_otherOnly) {
	foreach (@l) {
	    $b_base and $_->set_flag_base;
	    $o_otherOnly and $o_otherOnly->{$_->id} = $_->flag_requested;
	}
	$o_otherOnly and $packages->disable_selected($packages->{rpmdb}, $state, @l);
    }
    1;
}

sub unselectPackage($$;$) {
    my ($packages, $pkg, $o_otherOnly) = @_;

    #- base package are not unselectable,
    #- and already unselected package are no more unselectable.
    $pkg->flag_base and return;
    $pkg->flag_selected or return;

    my $state = $packages->{state} ||= {};
    log::l("removing selection on package ".$pkg->fullname);
    my @l = $packages->disable_selected($packages->{rpmdb}, $state, $pkg);
    log::l("   removed selection on package " . $pkg->fullname . "gives " . join(',', map { scalar $_->fullname } @l));
    if ($o_otherOnly) {
	foreach (@l) {
	    $o_otherOnly->{$_->id} = undef;
	}
	log::l("   reselecting removed selection...");
	$packages->resolve_requested($packages->{rpmdb}, $state, $o_otherOnly, callback_choices => \&packageCallbackChoices);
	log::l("   done");
    }
    1;
}
sub togglePackageSelection($$;$) {
    my ($packages, $pkg, $o_otherOnly) = @_;
    $pkg->flag_selected ? unselectPackage($packages, $pkg, $o_otherOnly) : selectPackage($packages, $pkg, 0, $o_otherOnly);
}
sub setPackageSelection($$$) {
    my ($packages, $pkg, $value) = @_;
    $value ? selectPackage($packages, $pkg) : unselectPackage($packages, $pkg);
}

sub unselectAllPackages($) {
    my ($packages) = @_;
    my %keep_selected;
    log::l("unselecting all packages...");
    foreach (@{$packages->{depslist}}) {
	if ($_->flag_base || $_->flag_installed && $_->flag_selected) {
	    #- keep track of package that should be kept selected.
	    $keep_selected{$_->id} = $_;
	    log::l("...keeping ".$_->fullname);
	} else {
	    #- deselect all packages except base or packages that need to be upgraded.
	    $_->set_flag_required(0);
	    $_->set_flag_requested(0);
	}
    }
    #- clean staten, in order to start with a brand new set...
    $packages->{state} = {};
    $packages->resolve_requested($packages->{rpmdb}, $packages->{state}, \%keep_selected,
				 callback_choices => \&packageCallbackChoices);
}

sub psUpdateHdlistsDeps {
    my ($prefix, $_method, $packages) = @_;
    my $need_copy = 0;

    #- check if current configuration is still up-to-date and do not need to be updated.
    foreach (values %{$packages->{mediums}}) {
	$_->{selected} || $_->{ignored} or next;
	my $urpmidir = -w "$prefix/var/lib/urpmi" ? "$prefix/var/lib/urpmi" : "/tmp";
	my $hdlistf = "$urpmidir/hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	my $synthesisf = "$urpmidir/synthesis.hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	if (-s $hdlistf != $_->{hdlist_size}) {
	    install_any::getAndSaveFile("Mandrake/base/$_->{hdlist}", $hdlistf) or die "no $_->{hdlist} found";
	    symlinkf $hdlistf, "/tmp/$_->{hdlist}";
	    ++$need_copy;
	}
	if (-s $synthesisf != $_->{synthesis_hdlist_size}) {
	    install_any::getAndSaveFile("Mandrake/base/synthesis.$_->{hdlist}", $synthesisf);
	    -s $synthesisf > 0 or unlink $synthesisf;
	}
    }

    if ($need_copy) {
	#- this is necessary for urpmi.
	my $urpmidir = -w "$prefix/var/lib/urpmi" ? "$prefix/var/lib/urpmi" : "/tmp";
	install_any::getAndSaveFile("Mandrake/base/$_", "$urpmidir/$_") foreach qw(rpmsrate);
    }
}

sub psUsingHdlists {
    my ($prefix, $method) = @_;
    my $listf = install_any::getFile('Mandrake/base/hdlists') or die "no hdlists found";
    my $packages = new URPM;

    #- add additional fields used by DrakX.
    @$packages{qw(count mediums)} = (0, {});

    #- parse hdlists file.
    my $medium = 1;
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	m/^\s*(noauto:)?(hdlist\S*\.cz2?)\s+(\S+)\s*(.*)$/ or die "invalid hdlist description \"$_\" in hdlists file";

	#- make sure the first medium is always selected!
	#- by default select all image.
	psUsingHdlist($prefix, $method, $packages, $2, $medium, $3, $4, !$1);

	++$medium;
    }

    log::l("psUsingHdlists read " . int(@{$packages->{depslist}}) .
	   " headers on " . int(keys %{$packages->{mediums}}) . " hdlists");

    $packages;
}

sub psUsingHdlist {
    my ($prefix, $method, $packages, $hdlist, $medium, $rpmsdir, $descr, $selected, $o_fhdlist) = @_;
    my $fakemedium = "$descr ($method$medium)";
    my $urpmidir = -w "$prefix/var/lib/urpmi" ? "$prefix/var/lib/urpmi" : "/tmp";
    log::l("trying to read $hdlist for medium $medium");

    #- if the medium already exist, use it.
    $packages->{mediums}{$medium} and return $packages->{mediums}{$medium};

    my $m = { hdlist     => $hdlist,
	      method     => $method,
	      medium     => $medium,
	      rpmsdir    => $rpmsdir, #- where is RPMS directory.
	      descr      => $descr,
	      fakemedium => $fakemedium,
	      selected   => $selected, #- default value is only CD1, it is really the minimal.
	      ignored    => !$selected, #- keep track of ignored medium by DrakX.
	      pubkey     => [], #- all pubkey block here
	    };

    #- copy hdlist file directly to urpmi directory, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $newf = "$urpmidir/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    -e $newf and do { unlink $newf or die "cannot remove $newf: $!" };
    install_any::getAndSaveFile($o_fhdlist || "Mandrake/base/$hdlist", $newf) or do { unlink $newf; die "no $hdlist found" };
    $m->{hdlist_size} = -s $newf; #- keep track of size for post-check.
    symlinkf $newf, "/tmp/$hdlist";

    #- if $o_fhdlist is defined, this is preferable not to try to find the associated synthesis.
    my $newsf = "$urpmidir/synthesis.hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    unless ($o_fhdlist) {
	#- copy existing synthesis file too.
	install_any::getAndSaveFile("Mandrake/base/synthesis.$hdlist", $newsf);
	$m->{synthesis_hdlist_size} = -s $newsf; #- keep track of size for post-check.
	-s $newsf > 0 or unlink $newsf;
    }

    #- get all keys corresponding in the right pubkey file,
    #- they will be added in rpmdb later if not found.
    my $pubkey = install_any::getFile("Mandrake/base/pubkey" . ($hdlist =~ /hdlist(\S*)\.cz2?/ && $1));
    $m->{pubkey} = [ $packages->parse_armored_file($pubkey) ];

    #- integrate medium in media list, only here to avoid download error (update) to be propagated.
    $packages->{mediums}{$medium} = $m;

    #- avoid using more than one medium if Cd is not ejectable.
    #- but keep all medium here so that urpmi has the whole set.
    $m->{ignored} ||= $method eq 'cdrom' && $medium > 1 && !common::usingRamdisk();

    #- parse synthesis (if available) of directly hdlist (with packing).
    if ($m->{ignored}) {
	log::l("ignoring packages in $hdlist");
    } else {
	if (-s $newsf) {
	    ($m->{start}, $m->{end}) = $packages->parse_synthesis($newsf);
	} elsif (-s $newf) {
	    ($m->{start}, $m->{end}) = $packages->parse_hdlist($newf, 1);
	} else {
	    delete $packages->{mediums}{$medium};
	    unlink $newf;
	    $o_fhdlist or unlink $newsf;
	    die "fatal: no hdlist nor synthesis to read for $fakemedium";
	}
	$m->{start} > $m->{end} and do { delete $packages->{mediums}{$medium};
					 unlink $newf;
					 $o_fhdlist or unlink $newsf;
					 die "fatal: nothing read in hdlist or synthesis for $fakemedium" };
	log::l("read " . ($m->{end} - $m->{start} + 1) . " packages in $hdlist");
    }
    $m;
}

sub read_rpmsrate {
    my ($packages, $f) = @_;
    my $line_nb = 0;
    my $fatal_error;
    my (@l);
    local $_;
    while (<$f>) {
	$line_nb++;
	/\t/ and die "tabulations not allowed at line $line_nb\n";
	s/#.*//; # comments

	my ($indent, $data) = /(\s*)(.*)/;
	next if !$data; # skip empty lines

	@l = grep { $_->[0] < length $indent } @l;

	my @m = @l ? @{$l[-1][1]} : ();
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
		if (my ($inv, $p) = /^(!)?HW"(.*)"/) {
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
	    my $rate = find { /^\d$/ } @m or die sprintf qq(missing rate for "%s" at line %d (flags are %s)\n), $data, $line_nb, join('&&', @m);
	    foreach (split ' ', $data) {
		if ($packages) {
		    my $p = packageByName($packages, $_) or next;
		    my @m2 = map { if_(/locales-(.*)/, qq(LOCALES"$1")) } $p->requires_nosense;
		    my @m3 = ((grep { !/^\d$/ } @m), @m2);
		    if (member('INSTALL', @m3)) {
			member('NOCOPY', @m3) or push @{$packages->{needToCopy} ||= []}, $_;
			next; #- don't need to put INSTALL flag for a package.
		    }
		    if ($p->rate) {
			my @m4 = $p->rflags;
			if (@m3 > 1 || @m4 > 1) {
			    log::l("can't handle complicate flags for packages appearing twice ($_)");
			    $fatal_error++;
			}
			log::l("package $_ appearing twice with different rates ($rate != ".$p->rate.")") if $rate != $p->rate;
			$p->set_rate($rate);
			$p->set_rflags("$m3[0]||$m4[0]");
		    } else {
			$p->set_rate($rate);
			$p->set_rflags(@m3);
		    }
		} else {
		    print "$_ = ", join(" && ", @m), "\n";
		}
	    }
	    push @l, @l2;
	} else {
	    push @l, [ $l2[0][0], $l2[-1][1] ];
	}
    }
    $fatal_error and die "$fatal_error fatal errors in rpmsrate";
}

sub readCompssUsers {
    my ($meta_class) = @_;
    my (%compssUsers, @sorted, $l);

    my $file = 'Mandrake/base/compssUsers';
    my $f = $meta_class && install_any::getFile("$file.$meta_class") || install_any::getFile($file) or die "can't find $file";
    local $_;
    while (<$f>) {
	/^\s*$/ || /^#/ and next;
	s/#.*//;

	if (/^(\S.*)/) {
	    my $verbatim = $_;
	    my ($icon, $descr, $path, $selected);
	    /^(.*?)\s*\[path=(.*?)\](.*)/  and $_ = "$1$3", $path  = $2;
	    /^(.*?)\s*\[icon=(.*?)\](.*)/  and $_ = "$1$3", $icon  = $2;
	    /^(.*?)\s*\[descr=(.*?)\](.*)/ and $_ = "$1$3", $descr = $2;
	    /^(.*?)\s*\[selected=(.*?)\](.*)/ and $_ = "$1$3", $selected = $2;
	    $compssUsers{"$path|$_"} = { label => $_, verbatim => $verbatim,
					 path => $path, icons => $icon, descr => $descr,
					 if_(defined $selected, selected => [ split /[\s,]+/, $selected ]), flags => $l = [] };
	    push @sorted, "$path|$_";
	} elsif (/^\s+(.*?)\s*$/) {
	    push @$l, $1;
	}
    }
    \%compssUsers, \@sorted;
}
sub saveCompssUsers {
    my ($prefix, $packages, $compssUsers, $sorted) = @_;
    my $flat;
    foreach (@$sorted) {
	my @fl = @{$compssUsers->{$_}{flags}};
	my %fl; $fl{$_} = 1 foreach @fl;
	$flat .= $compssUsers->{$_}{verbatim};
	foreach my $p (@{$packages->{depslist}}) {
	    my @flags = $p->rflags;
	    if ($p->rate && any { any { !/^!/ && $fl{$_} } split('\|\|') } @flags) {
		$flat .= sprintf "\t%d %s\n", $p->rate, $p->name;
	    }
	}
    }
    my $urpmidir = -w "$prefix/var/lib/urpmi" ? "$prefix/var/lib/urpmi" : "/tmp";
    output "$urpmidir/compssUsers.flat", $flat;
}

sub setSelectedFromCompssList {
    my ($packages, $compssUsersChoice, $min_level, $max_size) = @_;
    $compssUsersChoice->{TRUE} = 1; #- ensure TRUE is set
    my $nb = selectedSize($packages);
    foreach my $p (sort { $b->rate <=> $a->rate } @{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if 
	  !$p->rate || $p->rate < $min_level || 
	  any { !any { /^!(.*)/ ? !$compssUsersChoice->{$1} : $compssUsersChoice->{$_} } split('\|\|') } @flags;

	#- determine the packages that will be selected when
	#- selecting $p. the packages are not selected.
	my $state = $packages->{state} ||= {};

	my @l = $packages->resolve_requested($packages->{rpmdb}, $state, packageRequest($packages, $p) || {},
					     callback_choices => \&packageCallbackChoices);

	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (@l) {
	    $nb += $_->size;
	}
	if ($max_size && $nb > $max_size) {
	    $nb = $old_nb;
	    $min_level = $p->rate;
	    $packages->disable_selected($packages->{rpmdb}, $state, @l);
	    last;
	}
    }
    log::l("setSelectedFromCompssList: reached size ", formatXiB($nb), ", up to indice $min_level (less than ", formatXiB($max_size), ")");
    log::l("setSelectedFromCompssList: ", join(" ", sort map { $_->name } grep { $_->flag_selected } @{$packages->{depslist}}));
    $min_level;
}

#- usefull to know the size it would take for a given min_level/max_size
#- just saves the selected packages, call setSelectedFromCompssList and restores the selected packages
sub saveSelected {
    my ($packages) = @_;
    my $state = delete $packages->{state};
    my @l = @{$packages->{depslist}};
    my @flags = map { ($_->flag_requested && 1) + ($_->flag_required && 2) + ($_->flag_upgrade && 4) } @l;
    [ $packages, $state, \@l, \@flags ];
}
sub restoreSelected {
    my ($packages, $state, $l, $flags) = @{$_[0]};
    $packages->{state} = $state;
    mapn { my ($pkg, $flag) = @_;
	   $pkg->set_flag_requested($flag & 1);
	   $pkg->set_flag_required($flag & 2);
	   $pkg->set_flag_upgrade($flag & 4);
         } $l, $flags;
}

sub computeGroupSize {
    my ($packages, $min_level) = @_;

    sub inside {
	my ($l1, $l2) = @_;
	my $i = 0;
	return if @$l1 > @$l2;
	foreach (@$l1) {
	    my $c;
	    while ($c = $l2->[$i++] cmp $_) {
		return if $c == 1 || $i > @$l2;
	    }
	}
	1;
    }

    sub or_ify {
	my ($first, @other) = @_;
	my @l = split('\|\|', $first);
	foreach (@other) {
	    @l = map {
		my $n = $_;
		map { "$_&&$n" } @l;
	    } split('\|\|');
	}
	#- HACK, remove LOCALES & CHARSET, too costly
	grep { !/LOCALES|CHARSET/ } @l;
    }
    sub or_clean {
	my (@l) = map { [ sort split('&&') ] } @_ or return '';
	my @r;
	B: while (@l) {
	    my $e = shift @l;
	    foreach (@r, @l) {
		inside($e, $_) and next B;
	    }
	    push @r, $e;
	}
	join("\t", map { join('&&', @$_) } @r);
    }
    my (%group, %memo, $slowpart_counter);

    foreach my $p (@{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if !$p->rate || $p->rate < $min_level;

	my $flags = join("\t", @flags = or_ify(@flags));
	$group{$p->name} = ($memo{$flags} ||= or_clean(@flags));

	#- determine the packages that will be selected when selecting $p.
	#- make a fast selection (but potentially erroneous).
	#- installed and upgrade flags must have been computed (see compute_installed_flags).
	my %newSelection;
	unless ($p->flag_available) {
	    my @l2 = $p->id;
	    my $id;

	    while (defined($id = shift @l2)) {
		exists $newSelection{$id} and next;
		$newSelection{$id} = undef;

		my $pkg = $packages->{depslist}[$id];
		foreach ($pkg->requires_nosense) {
		    my @choices = keys %{$packages->{provides}{$_} || {}};
		    if (@choices <= 1) {
			push @l2, @choices;
		    } elsif (! find { exists $newSelection{$_} } @choices) {
			my ($candidate_id, $prefer_id);
			foreach (@choices) {
			    ++$slowpart_counter;
			    my $ppkg = $packages->{depslist}[$_] or next;
			    $ppkg->flag_available and $prefer_id = $candidate_id = undef, last;
			    exists $preferred{$ppkg->name} and $prefer_id = $_;
			    $ppkg->name =~ /kernel-\d/ and $prefer_id ||= $_;
			    foreach my $l ($ppkg->requires_nosense) {
				/locales-/ or next;
				my $pppkg = packageByName($packages, $l) or next;
				$pppkg->flag_available and $prefer_id ||= $_;
			    }
			    $candidate_id = $_;
			}
			if (defined $prefer_id || defined $candidate_id) {
			    push @l2, defined $prefer_id ? $prefer_id : $candidate_id;
			}
		    }
		}
	    }
	}

	foreach (keys %newSelection) {
	    my $p = $packages->{depslist}[$_] or next;
	    my $s = $group{$p->name} || do {
		join("\t", or_ify($p->rflags));
	    };
	    next if length($s) > 120; # HACK, truncated too complicated expressions, too costly
	    my $m = "$flags\t$s";
	    $group{$p->name} = ($memo{$m} ||= or_clean(@flags, split("\t", $s)));
	}
    }
    my (%sizes, %pkgs);
    while (my ($k, $v) = each %group) {
	my $pkg = packageByName($packages, $k) or next;
	push @{$pkgs{$v}}, $k;
	$sizes{$v} += $pkg->size - $packages->{sizes}{$pkg->name};
    }
    log::l(sprintf "%s %dMB %s", $_, $sizes{$_} / sqr(1024), join(',', @{$pkgs{$_}})) foreach keys %sizes;
    \%sizes, \%pkgs;
}


sub openInstallLog {
    my ($prefix) = @_;

    my $f = "$prefix/root/drakx/install.log";
    open(my $LOG, ">> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept."); #-#
    CORE::select((CORE::select($LOG), $| = 1)[0]);
    c::rpmErrorSetCallback(fileno $LOG);
#-    c::rpmSetVeryVerbose();
    $LOG;
}

sub rpmDbOpen {
    my ($prefix, $o_rebuild_needed) = @_;

    if ($o_rebuild_needed) {
	if (my $pid = fork()) {
	    waitpid $pid, 0;
	    $? & 0xff00 and die "rebuilding of rpm database failed";
	} else {
	    log::l("rebuilding rpm database");
	    my $rebuilddb_dir = "$prefix/var/lib/rpmrebuilddb.$$";
	    -d $rebuilddb_dir and log::l("removing stale directory $rebuilddb_dir"), rm_rf($rebuilddb_dir);

	    URPM::DB::rebuild($prefix) or log::l("rebuilding of rpm database failed: " . c::rpmErrorString()), c::_exit(2);

	    c::_exit(0);
	}
    }

    my $db;
    if ($db = URPM::DB::open($prefix)) {
	log::l("opened rpm database for examining existing packages");
    } else {
	log::l("unable to open rpm database, using empty rpm db emulation");
	$db = new URPM;
    }

    $db;
}

sub rpmDbOpenForInstall {
    my ($prefix) = @_;

    #- there is a bug in rpm 4.2 where all operations for accessing rpmdb files are not
    #- always done using prefix, we need to setup a symlink in /var/lib/rpm for that ...
    unless (-e "/var/lib/rpm") {
	#- check if at some time a /var/lib directory has been made.
	if (-d "/var/lib") {
	    symlinkf "$prefix/var/lib/rpm", "/var/lib/rpm";
	} else {
	    symlinkf "$prefix/var/lib", "/var/lib";
	}
    }

    my $db = URPM::DB::open($prefix, 1);
    $db and log::l("opened rpmdb for writing in $prefix");
    $db;
}

sub cleanOldRpmDb {
    my ($prefix) = @_;
    my $failed;

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
	    rm_rf("$prefix/var/lib/rpm/$_");
	}
    }
}

sub selectPackagesAlreadyInstalled {
    my ($packages, $_prefix) = @_;

    log::l("computing installed flags and size of installed packages");
    $packages->{sizes} = $packages->compute_installed_flags($packages->{rpmdb});
}

sub selectPackagesToUpgrade {
    my ($packages, $_prefix, $o_medium) = @_;

    #- check before that if medium is given, it should be valid.
    $o_medium && (! defined $o_medium->{start} || ! defined $o_medium->{end}) and return;

    log::l("selecting packages to upgrade");

    my $state = $packages->{state} ||= {};
    $state->{selected} = {};

    my %selection;
    $packages->request_packages_to_upgrade($packages->{rpmdb}, $state, \%selection,
					   requested => undef,
					   $o_medium ? (start => $o_medium->{start}, end => $o_medium->{end}) : (),
					  );
    log::l("resolving dependencies...");
    $packages->resolve_requested($packages->{rpmdb}, $state, \%selection,
				 callback_choices => \&packageCallbackChoices);
    log::l("...done");
}

sub allowedToUpgrade { $_[0] !~ /^(kernel|kernel22|kernel2.2|kernel-secure|kernel-smp|kernel-linus|kernel-linus2.2|hackkernel|kernel-enterprise)$/ }

sub installTransactionClosure {
    my ($packages, $id2pkg) = @_;
    my ($id, %closure, @l, $medium, $min_id, $max_id);

    @l = sort { $a <=> $b } keys %$id2pkg;

    #- search first usable medium (sorted by medium ordering).
    foreach (sort { $a->{start} <=> $b->{start} } values %{$packages->{mediums}}) {
	unless ($_->{selected}) {
	    #- this medium is not selected, but we have to make sure no package are left
	    #- in $id2pkg.
	    if (defined $_->{start} && defined $_->{end}) {
		foreach ($_->{start} .. $_->{end}) {
		    delete $id2pkg->{$_};
		}
	    }
	    #- anyway, examine the next one.
	    next;
	}
	if ($l[0] <= $_->{end}) {
	    #- we have a candidate medium, it could be the right one containing
	    #- the first package of @l...
	    $l[0] >= $_->{start} and $medium = $_, last;
	    #- ... but it could be necessary to find the first
	    #- medium containing package of @l.
	    foreach my $id (@l) {
		$id >= $_->{start} && $id <= $_->{end} and $medium = $_, last;
	    }
	    $medium and last;
	}
    }
    $medium or return (); #- no more medium usable -> end of installation by returning empty list.
    ($min_id, $max_id) = ($medium->{start}, $medium->{end});

    #- it is sure at least one package will be installed according to medium chosen.
    install_any::useMedium($medium->{medium});
    if ($medium->{method} eq 'cdrom') {
	my $pkg = $packages->{depslist}[$l[0]];

	#- force changeCD callback to be called from main process.
	install_any::getFile($pkg->filename, $medium->{descr});
	#- close opened handle above.
	install_any::getFile('XXX');
    }

    while (defined($id = shift @l)) {
	my @l2 = $id;

	while (defined($id = shift @l2)) {
	    exists $closure{$id} and next;
	    $id >= $min_id && $id <= $max_id or next;
	    $closure{$id} = undef;

	    my $pkg = $packages->{depslist}[$id];
	    foreach ($pkg->requires_nosense) {
		foreach (keys %{$packages->{provides}{$_} || {}}) {
		    if ($id2pkg->{$_}) {
			push @l2, $_;
			last;
		    }
		}
	    }
	}

	keys %closure >= $limitMinTrans and last;
    }

    map { delete $id2pkg->{$_} } grep { $id2pkg->{$_} } sort { $a <=> $b } keys %closure;
}

sub installCallback {
#    my $msg = shift;
#    log::l($msg .": ". join(',', @_));
}

sub install($$$;$$) {
    my ($prefix, $isUpgrade, $toInstall, $packages) = @_;
    my %packages;

    return if $::g_auto_install || !scalar(@$toInstall);

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.

    #- for root loopback'ed /boot
    my $loop_boot = loopback::prepare_boot();

    #- first stage to extract some important informations
    #- about the packages selected. this is used to select
    #- one or many transaction.
    my ($total, $nb);
    foreach my $pkg (@$toInstall) {
	$packages{$pkg->id} = $pkg;
	$nb++;
	$total += to_int($pkg->size); #- do not correct for upgrade!
    }

    log::l("pkgs::install $prefix");
    log::l("pkgs::install the following: ", join(" ", map { $_->name } values %packages));
    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    URPM::read_config_files();
    my $LOG = openInstallLog($prefix);

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($packages, 'user', undef, 'install', $nb, $total);

    do {
	my @transToInstall = installTransactionClosure($packages, \%packages);
	$nb = values %packages;

	#- added to exit typically after last media unselected.
	if ($nb == 0 && scalar(@transToInstall) == 0) {
	    cleanHeaders($prefix);

	    loopback::save_boot($loop_boot);
	    return;
	}

	#- extract headers for parent as they are used by callback.
	extractHeaders($prefix, \@transToInstall, $packages->{mediums});

	my ($retry_pkg, $retry_count);
	while ($retry_pkg || @transToInstall) {
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
			    my $pkg = $packages->{depslist}[$params[1]];
			    #- update flag associated to package.
			    $pkg->set_flag_installed(1);
			    $pkg->set_flag_upgrade(0);
			    #- update obsoleted entry.
			    foreach (keys %{$packages->{state}{rejected}}) {
				if (exists $packages->{state}{rejected}{$_}{closure}{$pkg->fullname}) {
				    delete $packages->{state}{rejected}{$_}{closure}{$pkg->fullname};
				    %{$packages->{state}{rejected}{$_}{closure}} or delete $packages->{state}{rejected}{$_};
				}
			    }
			} else {
			    installCallback($packages, @params);
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
		my @prev_pids = grep { /^\d+$/ } all("/proc");
		close INPUT;
		select((select(OUTPUT), $| = 1)[0]);
		if ($::testing) {
		    my $size_typical = $nb ? int($total/$nb) : 0;
		    foreach (@transToInstall) {
			log::l("i would install ", $_->name, " now");
			my $id = $_->id;
			print OUTPUT "inst:$id:start:0:$size_typical\ninst:$id:progress:0:$size_typical\nclose:$id\n";
		    }
		} else { eval {
		    my $db = rpmDbOpenForInstall($prefix) or die "error opening RPM database: ", c::rpmErrorString();
		    my $trans = $db->create_transaction($prefix);
		    if ($retry_pkg) {
			log::l("opened rpm database for retry transaction of 1 package only");
			$trans->add($retry_pkg, $isUpgrade && allowedToUpgrade($retry_pkg->name));
		    } else {
			log::l("opened rpm database for transaction of " . int(@transToInstall) .
			       " new packages, still $nb after that to do");
			$trans->add($_, $isUpgrade && allowedToUpgrade($_->name))
			  foreach @transToInstall;
		    }

		    my @checks = $trans->check; @checks and log::l("check failed : ".join("\n               ", @checks));
		    $trans->order or die "error ordering package list: " . c::rpmErrorString();
		    $trans->set_script_fd(fileno $LOG);

		    log::l("rpm transactions start");
		    my $fd; #- since we return the "fileno", perl doesn't know we're still using it, and so closes it, and :-(
		    my @probs = $trans->run($packages, force => 1, nosize => 1, callback_open => sub {
						my ($data, $_type, $id) = @_;
						my $pkg = defined $id && $data->{depslist}[$id];
						my $medium = packageMedium($packages, $pkg);
						my $f = $pkg && $pkg->filename;
						print $LOG "$f\n";
						$fd = install_any::getFile($f, $medium->{descr});
						$fd ? fileno $fd : -1;
					    }, callback_close => sub {
						my ($data, $_type, $id) = @_;
						my $pkg = defined $id && $data->{depslist}[$id] or return;
						my $check_installed;
						$db->traverse_tag('name', [ $pkg->name ], sub {
								      my ($p) = @_;
								      $check_installed ||= $pkg->compare_pkg($p) == 0;
								  });
						$check_installed and print OUTPUT "close:$id\n";
					    }, callback_inst => sub {
						my ($_data, $type, $id, $subtype, $amount, $total) = @_;
						print OUTPUT "$type:$id:$subtype:$amount:$total\n";
					    });
		    log::l("transactions done, now trying to close still opened fd");
		    install_any::getFile('XXX'); #- close still opened fd.

		    @probs and die "installation of rpms failed:\n  ", join("\n  ", @probs);
		}; $@ and print OUTPUT "die:$@\n" }
		close OUTPUT;

		#- now search for child process which may be locking the cdrom, making it unable to be ejected.
		my @allpids = grep { /^\d+$/ } all("/proc");
		my %ppids;
		foreach (@allpids) {
		    push @{$ppids{$1 || 1}}, $_
		      if cat_("/proc/$_/status") =~ /^PPid:\s+(\d+)/m;
		}
		my @killpid = difference2(\@allpids, [ @prev_pids, 
						       difference2([ $$, hashtree2list(getppid(), \%ppids) ],
								   [ hashtree2list($$, \%ppids) ]) ]);
	
		if (@killpid) {
		    foreach (@killpid) {
			my ($prog, @para) = split("\0", cat_("/proc/$_/cmdline"));
			log::l("ERROR: DrakX should not have to clean the packages shit. Killing $_: " . join(' ', $prog, @para) . ".");
		    }
		    kill 15, @killpid;
		    sleep 2;
		    kill 9, @killpid;
		}

		c::_exit(0);
	    }

	    #- if we are using a retry mode, this means we have to split the transaction with only
	    #- one package for each real transaction.
	    if (!$retry_pkg) {
		my @badPackages;
		foreach (@transToInstall) {
		    if (!$_->flag_installed && packageMedium($packages, $_)->{selected} && !exists($ignoreBadPkg{$_->name})) {
			push @badPackages, $_;
			log::l("bad package ".$_->fullname);
		    } else {
			$_->free_header;
		    }
		}
		@transToInstall = @badPackages;
		#- if we are in retry mode, we have to fetch only one package at a time.
		$retry_pkg = shift @transToInstall;
		$retry_count = 3;
	    } else {
		my $name;
		if (!$retry_pkg->flag_installed && packageMedium($packages, $retry_pkg)->{selected} && !exists($ignoreBadPkg{$retry_pkg->name})) {
		    if ($retry_count) {
			log::l("retrying installing package ".$retry_pkg->fullname." alone in a transaction");
			--$retry_count;
		    } else {
			log::l("bad package " . $retry_pkg->fullname . " unable to be installed");
			$retry_pkg->set_flag_requested(0);
			$retry_pkg->set_flag_required(0);
			#- keep name to display (problem of displaying ?).
			$name = $retry_pkg->fullname;
			$retry_pkg->free_header;
			$retry_pkg = shift @transToInstall;
			$retry_count = 3;
			#- now it could be safe to display error message ?
			cdie("error installing package list: $name");
		    }
		}
		#- check if name has been set (so that the following code has been executed already).
		if (!$name && ($retry_pkg->flag_installed || !$retry_pkg->flag_selected)) {
		    $retry_pkg->free_header;
		    $retry_pkg = shift @transToInstall;
		    $retry_count = 3;
		}
	    }
	}
	cleanHeaders($prefix);
    } while $nb > 0 && !$pkgs::cancel_install;

    log::l("closing install.log file");
    close $LOG;

    cleanHeaders($prefix);

    loopback::save_boot($loop_boot);
}

sub remove {
    my ($prefix, $toRemove, $packages) = @_;

    return if $::g_auto_install || !@{$toRemove || []};

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.
    my $db = rpmDbOpenForInstall($prefix) or die "error opening RPM database: ", c::rpmErrorString();
    my $trans = $db->create_transaction($prefix);

    foreach my $p (@$toRemove) {
	#- stuff remove all packages that matches $p, not a problem since $p has name-version-release format.
	$trans->remove($p);
    }

    eval { fs::mount("/proc", "$prefix/proc", "proc", 0) } unless -e "$prefix/proc/cpuinfo";

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($db, 'user', undef, 'remove', scalar @$toRemove);

    if (my @probs = $trans->run(undef, force => 1)) {
	die "removing of old rpms failed:\n  ", join("\n  ", @probs);
    } else {
	#- clean ask_remove according to package marked to be deleted.
	if ($packages) {
	    foreach my $p (@$toRemove) {
		delete $packages->{state}{ask_remove}{$p};
	    }
	}
    }

    #- keep in mind removing of these packages by cleaning $toRemove.
    @{$toRemove || []} = ();
}

sub selected_leaves {
    my ($packages) = @_;
    my @leaves;

    foreach (@{$packages->{depslist}}) {
	$_->flag_requested && !$_->flag_base and push @leaves, $_->name;
    }
    \@leaves;
}


sub naughtyServers {
    my ($packages) = @_;

    my @_old_81 = qw(
freeswan
);
    my @_old_82 = qw(
vnc-server
postgresql-server
mon
);

    my @new_80 = qw(
jabber
FreeWnn
MySQL
am-utils
apache
boa
cfengine
cups
drakxtools-http
finger-server
imap
leafnode
lpr
ntp
openssh-server
pidentd
postfix
proftpd
rwall
rwho
squid
webmin
wu-ftpd
ypbind
); # nfs-utils-clients portmap
   # X server

    my @new_81 = qw(
apache-mod_perl
ftp-server-krb5
mcserv
samba
telnet-server-krb5
ypserv
);

    my @new_82 = qw(
LPRng
bind
httpd-naat
ibod
inn
netatalk
nfs-utils
rusers-server
samba-swat
tftp-server
ucd-snmp
);

    my @naughtyServers = (@new_80, @new_81, @new_82);

    grep {
	my $p = packageByName($packages, $_);
	$p && $p->flag_selected;
    } @naughtyServers;
}

sub hashtree2list {
    my ($e, $h) = @_;
    my @l;
    my @todo = $e;
    while (@todo) {
	my $e = shift @todo;
	push @l, $e;
	push @todo, @{$h->{$e} || []};
    }
    @l;
}

1;
