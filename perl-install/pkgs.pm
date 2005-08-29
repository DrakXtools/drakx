package pkgs; # $Id$

use strict;

use URPM;
use URPM::Resolve;
use URPM::Signature;
use common;
use install_any;
use run_program;
use detect_devices;
use log;
use fs;
use fs::loopback;
use c;

our %preferred = map { $_ => undef } qw(lilo perl-base gstreamer-oss openjade ctags glibc curl sane-backends postfix mdkkdm gcc gcc-cpp gcc-c++ proftpd ghostscript-X vim-minimal kernel db1 db2 libxpm4 zlib1 libncurses5 harddrake cups apache);

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

sub packageMedium {
   my ($packages, $p) = @_; $p or die "invalid package from\n" . backtrace();
   foreach (values %{$packages->{mediums}}) {
       defined $_->{start} && defined $_->{end} or next;
       $p->id >= $_->{start} && $p->id <= $_->{end} and return $_;
   }
   return {};
}

sub cleanHeaders() {
    rm_rf("$::prefix/tmp/headers") if -e "$::prefix/tmp/headers";
}

#- get all headers from an hdlist file.
sub extractHeaders {
    my ($pkgs, $media) = @_;
    my %medium2pkgs;

    cleanHeaders();

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
	    $packer->extract_archive("$::prefix/tmp/headers", map { $_->header_filename } @{$medium2pkgs{$_}});
	};
    }

    foreach (@$pkgs) {
	my $f = "$::prefix/tmp/headers/" . $_->header_filename;
	$_->update_header($f) or log::l("unable to open header file $f"), next;
	log::l("read header file $f");
    }
}

#- TODO BEFORE TODO
#- size and correction size functions for packages.
my $B = 1.20873;
my $C = 4.98663; #- does not take hdlist's into account as getAvailableSpace will do it.
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


sub packagesProviding {
    my ($packages, $name) = @_;
    map { $packages->{depslist}[$_] } keys %{$packages->{provides}{$name} || {}};
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
    foreach my $pkg (packagesProviding($packages, $name)) {
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
    $best or log::l("unknown package `$name'");
    $best;
}

sub analyse_kernel_name {
    my $kernels = join('|', map { "-$_" }
	'(p3|i586|i686)-(up|smp)-(1GB|4GB|64GB)', 
	qw(enterprise secure smp multimedia multimedia-smp xbox),
    );
    my @l = $_[0] =~ /kernel[^\-]*($kernels)?(-([^\-]+))?$/ or return;
    $l[0], $l[-1];
}

sub packages2kernels {
    my ($packages) = @_;

     sort { 
	$a->{ext} cmp $b->{ext} || URPM::rpmvercmp($b->{version}, $a->{version});
    } map { 
	if (my ($ext, $version) = analyse_kernel_name($_->name)) {
	    { pkg => $_, ext => $ext, version => $version };
	} else {
	    log::l("ERROR: unknown package " . $_->name . " providing kernel");
	    ();
	}
    } packagesProviding($packages, 'kernel');
}

sub bestKernelPackage {
    my ($packages) = @_;

    my @kernels = packages2kernels($packages) or internal_error('no kernel available');
    my ($version_BOOT) = c::kernel_version() =~ /^(\d+\.\d+)/;
    if (my @l = grep { $_->{version} =~ /\Q$version_BOOT/ } @kernels) {
	#- favour versions corresponding to current BOOT version
	@kernels = @l;
    }
    my @preferred_exts =
      $::build_globetrotter ? '' :
      detect_devices::is_xbox() ? '-xbox' :
      detect_devices::is_i586() ? '-i586-up-1GB' :
      !detect_devices::has_cpu_flag('pae') ? ('-i686-up-4GB', '-i586-up-1GB') :
      detect_devices::hasSMP() ? '-smp' :
      '';
    foreach my $prefered_ext (@preferred_exts, '') {
	if (my @l = grep { $_->{ext} eq $prefered_ext } @kernels) {
	    @kernels = @l;
	}
    }

    log::l("bestKernelPackage (" . join(':', @preferred_exts) . "): " . join(' ', map { $_->{pkg}->name } @kernels) . (@kernels > 1 ? ' (choosing the first)' : ''));
    $preferred{'kernel-source-' . $kernels[0]{version}} = undef;
    $kernels[0]{pkg};
}

sub packagesOfMedium {
    my ($packages, $medium) = @_;
    defined $medium->{start} && defined $medium->{end} ? @{$packages->{depslist}}[$medium->{start} .. $medium->{end}] : ();
}
sub packagesToInstall {
    my ($packages) = @_;
    my @packages;
    foreach (values %{$packages->{mediums}}) {
	$_->selected or next;
	log::l("examining packagesToInstall of medium $_->{descr}");
	push @packages, grep { $_->flag_selected } packagesOfMedium($packages, $_);
    }
    log::l("found " . scalar(@packages) . " packages to install");
    @packages;
}

sub allMediums {
    my ($packages) = @_;
    sort {
	#- put supplementary media at the end
	my @x = ($a, $b);
	foreach (@x) { install_medium::by_id($_, $packages)->is_suppl and $_ += 100 }
	$x[0] <=> $x[1];
    } keys %{$packages->{mediums}};
}

sub packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    foreach (values %{$packages->{mediums}}) {
	#- XXX $_ should always be an object here
	!$_->{selected} && $pkg->id >= $_->{start} && $pkg->id <= $_->{end} and return;
    }

    return { $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $_db, $state, $choices) = @_;
    if (my $prefer = find { $_->arch ne 'src' && exists $preferred{$_->name} } @$choices) {
	$prefer;
    } else {
	my @l = grep {
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

    #- base packages are not unselectable,
    #- and already unselected package are no more unselectable.
    $pkg->flag_base and return;
    $pkg->flag_selected or return;

    my $state = $packages->{state} ||= {};
    log::l("removing selection on package " . $pkg->fullname);
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

sub unselectAllPackages($) {
    my ($packages) = @_;
    my %keep_selected;
    log::l("unselecting all packages...");
    foreach (@{$packages->{depslist}}) {
	if ($_->flag_base || $_->flag_installed && $_->flag_selected) {
	    #- keep track of packages that should be kept selected.
	    $keep_selected{$_->id} = $_;
	} else {
	    #- deselect all packages except base or packages that need to be upgraded.
	    $_->set_flag_required(0);
	    $_->set_flag_requested(0);
	}
    }
    #- clean state, in order to start with a brand new set...
    $packages->{state} = {};
    $packages->resolve_requested($packages->{rpmdb}, $packages->{state}, \%keep_selected,
				 callback_choices => \&packageCallbackChoices);
}

sub urpmidir() {
    my $v = "$::prefix/var/lib/urpmi";
    -l $v && !-e _ and unlink $v and mkdir $v, 0755; #- dangling symlink
    -w $v ? $v : '/tmp';
}

sub psUpdateHdlistsDeps {
    my ($packages) = @_;
    my $need_copy = 0;
    my $urpmidir = urpmidir();

    #- check if current configuration is still up-to-date and do not need to be updated.
    foreach (values %{$packages->{mediums}}) {
	$_->selected || $_->ignored or next;
	my $hdlistf = "$urpmidir/hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	my $synthesisf = "$urpmidir/synthesis.hdlist.$_->{fakemedium}.cz" . ($_->{hdlist} =~ /\.cz2/ && "2");
	if (-s $hdlistf != $_->{hdlist_size}) {
	    install_any::getAndSaveFile("media/media_info/$_->{hdlist}", $hdlistf) or die "no $_->{hdlist} found";
	    symlinkf $hdlistf, "/tmp/$_->{hdlist}";
	    ++$need_copy;
	    chown 0, 0, $hdlistf;
	}
	if (-s $synthesisf != $_->{synthesis_hdlist_size}) {
	    install_any::getAndSaveFile("media/media_info/synthesis.$_->{hdlist}", $synthesisf);
	    if (-s $synthesisf > 0) { chown 0, 0, $synthesisf } else { unlink $synthesisf }
	}
    }

    if ($need_copy) {
	#- this is necessary for urpmi.
	install_any::getAndSaveFile("media/media_info/$_", "$urpmidir/$_") && chown 0, 0, "$urpmidir/$_" foreach qw(rpmsrate);
    }
}

sub psUsingHdlists {
    my ($o, $method, $o_hdlistsprefix, $o_packages, $o_initialmedium, $o_callback) = @_;
    my $is_ftp = $o_hdlistsprefix =~ /^ftp:/;
    my $listf = install_any::getFile($o_hdlistsprefix && !$is_ftp ? "$o_hdlistsprefix/media/media_info/hdlists" : 'media/media_info/hdlists')
	or die "no hdlists found";
    my ($suppl_CDs, $deselectionAllowed) = ($o->{supplmedia} || 0, $o->{askmedia} || 0);
    if (!$o_packages) {
	$o_packages = new URPM;
	#- add additional fields used by DrakX.
	@$o_packages{qw(count mediums)} = (0, {});
    }

    #- parse hdlists file.
    my $medium_name = $o_initialmedium || 1;
    my (@hdlists, %mediumsize);
    foreach (<$listf>) {
	chomp;
	s/\s*#.*$//;
	/^\s*$/ and next;
	#- we'll ask afterwards for supplementary CDs, if the hdlists file contains
	#- a line that begins with "suppl"
	if (/^suppl/) { $suppl_CDs = 1; next }
	#- if the hdlists contains a line "askmedia", deletion of media found
	#- in this hdlist is allowed
	if (/^askmedia/) { $deselectionAllowed = 1; next }
	my $cdsuppl = index($medium_name, 's') >= 0;
	my ($noauto, $hdlist, $rpmsdir, $descr, $size) = m/^\s*(noauto:)?(hdlist\S*\.cz2?)\s+(\S+)\s*([^(]*)(\(.+\))?$/
	    or die qq(invalid hdlist description "$_" in hdlists file);
	$descr =~ s/\s+$//;
	push @hdlists, [ $hdlist, $medium_name, $rpmsdir, $descr, !$noauto, 
	    #- hdlist path, suppl CDs are mounted on /mnt/cdrom :
	    $o_hdlistsprefix ? ($is_ftp ? "media/media_info/$hdlist" : "$o_hdlistsprefix/media/media_info/$hdlist") : undef,
	];
	if ($size) {
	    ($mediumsize{$hdlist}) = $size =~ /(\d+)/; #- XXX assume Mo
	} else {
	    $mediumsize{$hdlist} = 0;
	}
	$cdsuppl ? ($medium_name = ($medium_name + 1) . 's') : ++$medium_name;
    }
    my $copy_rpms_on_disk = 0;
    if ($deselectionAllowed && !defined $o_initialmedium) {
	(my $finalhdlists, $copy_rpms_on_disk) = $o->deselectFoundMedia(\@hdlists, \%mediumsize);
	@hdlists = @$finalhdlists;
    }

    foreach my $h (@hdlists) {
	my $medium = psUsingHdlist($method, $o_packages, @$h);
	$o_callback and $o_callback->($medium, $o_hdlistsprefix, $method);
    }

    log::l("psUsingHdlists read " . int(@{$o_packages->{depslist}}) .
	   " headers on " . int(keys %{$o_packages->{mediums}}) . " hdlists");

    return $o_packages, $suppl_CDs, $copy_rpms_on_disk;
}

sub psUsingHdlist {
    my ($method, $packages, $hdlist, $medium_name, $rpmsdir, $descr, $selected, $o_fhdlist, $o_pubkey, $o_nocopy) = @_;
    my $fakemedium = "$descr ($method$medium_name)";
    my $urpmidir = urpmidir();
    log::l("trying to read $hdlist for medium $medium_name");

    my $m = install_medium->new(
	hdlist     => $hdlist,
	method     => $method,
	medium     => $medium_name,
	rpmsdir    => $rpmsdir, #- where is RPMS directory.
	descr      => $descr,
	fakemedium => $fakemedium,
	selected   => $selected, #- default value is only CD1, it is really the minimal.
	ignored    => !$selected, #- keep track of ignored medium by DrakX.
	pubkey     => [], #- all pubkey blocks here
    );

    #- copy hdlist file directly to urpmi directory, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $newf = "$urpmidir/hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    unless ($o_nocopy) {
	my $w_wait;
	$w_wait = $::o->wait_message(N("Please wait"), N("Downloading file %s...", $hdlist)) if $method =~ /^(?:ftp|http|nfs)$/;
	-e $newf and do { unlink $newf or die "cannot remove $newf: $!" };
	install_any::getAndSaveFile($o_fhdlist || "media/media_info/$hdlist", $newf) or do { unlink $newf; die "no $hdlist found" };
	$m->{hdlist_size} = -s $newf; #- keep track of size for post-check.
	symlinkf $newf, "/tmp/$hdlist";
	undef $w_wait;
    }

    my $newsf = "$urpmidir/synthesis.hdlist.$fakemedium.cz" . ($hdlist =~ /\.cz2/ && "2");
    #- if $o_fhdlist is a filehandle, it's preferable not to try to find the associated synthesis.
    if (!$o_nocopy && !ref $o_fhdlist) {
	#- copy existing synthesis file too.
	my $synth;
	if ($o_fhdlist) {
	    $synth = $o_fhdlist;
	    $synth =~ s/hdlist/synthesis.hdlist/ or $synth = undef;
	}
	$synth ||= "media/media_info/synthesis.$hdlist";
	install_any::getAndSaveFile($synth, $newsf);
	$m->{synthesis_hdlist_size} = -s $newsf; #- keep track of size for post-check.
	-s $newsf > 0 or unlink $newsf;
    }

    chown 0, 0, $newf, $newsf;

    #- get all keys corresponding in the right pubkey file,
    #- they will be added in rpmdb later if not found.
    if (!$o_fhdlist || $o_pubkey) {
	$m->{pubkey} = $o_pubkey;
	unless ($m->{pubkey}) {
	    my $pubkey = install_any::getFile("media/media_info/pubkey" . ($hdlist =~ /hdlist(\S*)\.cz2?/ && $1));
	    $m->{pubkey} = [ $packages->parse_armored_file($pubkey) ];
	}
    }

    #- integrate medium in media list, only here to avoid download error (update) to be propagated.
    $packages->{mediums}{$medium_name} = $m;

    #- parse synthesis (if available) of directly hdlist (with packing).
    if ($m->ignored) {
	log::l("ignoring packages in $hdlist");
    } else {
	my $nb_suppl_pkg_skipped = 0;
	my $callback = sub {
	    my (undef, $p) = @_;
	    our %uniq_pkg_seen;
	    if ($uniq_pkg_seen{$p->fullname}++) {
		log::l("skipping " . scalar $p->fullname);
		++$nb_suppl_pkg_skipped;
		return 0;
	    } else {
		return 1;
	    }
	};
	if (-s $newsf) {
	    ($m->{start}, $m->{end}) = $packages->parse_synthesis($newsf, callback => $callback);
	} elsif (-s $newf) {
	    ($m->{start}, $m->{end}) = $packages->parse_hdlist($newf, callback => $callback);
	} else {
	    delete $packages->{mediums}{$medium_name};
	    unlink $newf;
	    $o_fhdlist or unlink $newsf;
	    die "fatal: no hdlist nor synthesis to read for $fakemedium";
	}
	$m->{start} > $m->{end} and do { delete $packages->{mediums}{$medium_name};
					 unlink $newf;
					 $o_fhdlist or unlink $newsf;
					 die "fatal: nothing read in hdlist or synthesis for $fakemedium" };
	log::l("read " . ($m->{end} - $m->{start} + 1) . " packages in $hdlist, $nb_suppl_pkg_skipped skipped");
    }
    $m;
}

sub read_rpmsrate_raw {
    my ($f) = @_;
    my $line_nb = 0;
    my $fatal_error;
    my (%flags, %rates, @need_to_copy);
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
	    push @m, $flag;
	    push @l2, [ length $indent, [ @m ] ];
	    $indent .= $t;
	}
	if ($data) {
	    # has packages on same line
	    my ($rates, $flags) = partition { /^\d$/ } @m;
	    my ($rate) = @$rates or die sprintf qq(missing rate for "%s" at line %d (flags are %s)\n), $data, $line_nb, join('&&', @m);
	    foreach my $name (split ' ', $data) {
		if (member('INSTALL', @$flags)) {
		    push @need_to_copy, $name if !member('NOCOPY', @$flags);
		    next;    #- do not need to put INSTALL flag for a package.
		}
		if (member('PRINTER', @$flags)) {
		    push @need_to_copy, $name;
		}
		my @new_flags = @$flags;
		if (my $previous = $flags{$name}) {
		    my @common = intersection($flags, $previous);
		    my @diff1 = difference2($flags, \@common);
		    my @diff2 = difference2($previous, \@common);
		    if (!@diff1 || !@diff2) {
			@new_flags = @common;
		    } elsif (@diff1 == 1 && @diff2 == 1) {
			@new_flags = (@common, join('||', $diff1[0], $diff2[0]));
		    } else {
			log::l("can not handle complicate flags for packages appearing twice ($name)");
			$fatal_error++;
		    }
		    log::l("package $name appearing twice with different rates ($rate != " . $rates{$name} . ")") if $rate != $rates{$name};
		}
		$rates{$name} = $rate;
		$flags{$name} = \@new_flags;
	    }
	    push @l, @l2;
	} else {
	    push @l, [ $l2[0][0], $l2[-1][1] ];
	}
    }
    $fatal_error and die "$fatal_error fatal errors in rpmsrate";
    \%rates, \%flags, \@need_to_copy;
}

sub read_rpmsrate {
    my ($packages, $rpmsrate_flags_chosen, $f) = @_;

    my ($rates, $flags, $need_to_copy) = read_rpmsrate_raw($f);
    
    foreach (keys %$flags) {
	my $p = packageByName($packages, $_) or next;
	my @flags = (@{$flags->{$_}}, map { if_(/locales-(.*)/, qq(LOCALES"$1")) } $p->requires_nosense);

	@flags = map {
	    my ($user_flags, $known_flags) = partition { /^!?CAT_/ } split('\|\|', $_);
	    my $ok = find {
		my $inv = s/^!//;
		$inv xor do {
		    if (my ($p) = /^HW"(.*)"/) {
			detect_devices::matching_desc__regexp($p);
		    } elsif (($p) = /^HW_CAT"(.*)"/) {
			modules::probe_category($p);
		    } elsif (($p) = /^DRIVER"(.*)"/) {
			detect_devices::matching_driver__regexp($p);
		    } elsif (($p) = /^TYPE"(.*)"/) {
			detect_devices::matching_type($p);
		    } else {
			$rpmsrate_flags_chosen->{$_};
		    }
		};
	    } @$known_flags;
	    $ok ? 'TRUE' : @$user_flags ? join('||', @$user_flags) : 'FALSE';
	} @flags;

	$p->set_rate($rates->{$_});
	$p->set_rflags(member('FALSE', @flags) ? 'FALSE' : @flags);
    }
    push @{$packages->{needToCopy} ||= []}, @$need_to_copy;
}

sub readCompssUsers {
    my ($file) = @_;

    my $f = -e $file ? install_any::getLocalFile($file) : install_any::getFile($file)
	or do { log::l("can not find $file: $!"); return undef, undef };
    my ($compssUsers, $gtk_display_compssUsers) = eval join('', <$f>);
    if ($@) {
	log::l("ERROR: bad $file: $@");
    } else {
	log::l("compssUsers.pl got: ", join(', ', map { qq("$_->{path}|$_->{label}") } @$compssUsers));
    }
    ($compssUsers, $gtk_display_compssUsers);
}

sub saveCompssUsers {
    my ($packages, $compssUsers) = @_;
    my $flat;
    foreach (@$compssUsers) {
	my %fl = map { ("CAT_$_" => 1) } @{$_->{flags}};
	$flat .= "$_->{label} [icon=xxx] [path=$_->{path}]\n";
	foreach my $p (@{$packages->{depslist}}) {
	    my @flags = $p->rflags;
	    if ($p->rate && any { any { !/^!/ && $fl{$_} } split('\|\|') } @flags) {
		$flat .= sprintf "\t%d %s\n", $p->rate, $p->name;
	    }
	}
    }
    my $urpmidir = urpmidir();
    output "$urpmidir/compssUsers.flat", $flat;
}

sub setSelectedFromCompssList {
    my ($packages, $rpmsrate_flags_chosen, $min_level, $max_size) = @_;
    $rpmsrate_flags_chosen->{TRUE} = 1; #- ensure TRUE is set
    my $nb = selectedSize($packages);
    foreach my $p (sort { $b->rate <=> $a->rate } @{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if 
	  !$p->rate || $p->rate < $min_level || 
	  any { !any { /^!(.*)/ ? !$rpmsrate_flags_chosen->{$1} : $rpmsrate_flags_chosen->{$_} } split('\|\|') } @flags;

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
    my @flags = map_each { if_($::b, $::a) } %$rpmsrate_flags_chosen;
    log::l("setSelectedFromCompssList: reached size ", formatXiB($nb), ", up to indice $min_level (less than ", formatXiB($max_size), ") for flags ", join(' ', sort @flags));
    log::l("setSelectedFromCompssList: ", join(" ", sort map { $_->name } grep { $_->flag_selected } @{$packages->{depslist}}));
    $min_level;
}

#- useful to know the size it would take for a given min_level/max_size
#- just save the selected packages, call setSelectedFromCompssList, and restore the selected packages
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
	@l;
    }
    my %or_ify_cache;
    my $or_ify_cached = sub {
	$or_ify_cache{$_[0]} ||= join("\t", or_ify(split("\t", $_[0])));
    };
    sub or_clean {
	my ($flags) = @_;
	my @l = split("\t", $flags);
	@l = map { [ sort split('&&') ] } @l;
	my @r;
	B: while (@l) {
	    my $e = shift @l;
	    foreach (@r, @l) {
		inside($_, $e) and next B;
	    }
	    push @r, $e;
	}
	join("\t", map { join('&&', @$_) } @r);
    }
    my (%group, %memo, $slowpart_counter);

    log::l("pkgs::computeGroupSize");
    my $time = time();

    my %pkgs_with_same_rflags;
    foreach (@{$packages->{depslist}}) {
	next if !$_->rate || $_->rate < $min_level || $_->flag_available;
	my $flags = join("\t", $_->rflags);
	next if $flags eq 'FALSE';
	push @{$pkgs_with_same_rflags{$flags}}, $_;
    }

    foreach my $raw_flags (keys %pkgs_with_same_rflags) {
	my $flags = $or_ify_cached->($raw_flags);
	my @pkgs = @{$pkgs_with_same_rflags{$raw_flags}};
  
	#- determine the packages that will be selected when selecting $p.
	#- make a fast selection (but potentially erroneous).
	#- installed and upgrade flags must have been computed (see compute_installed_flags).
	my %newSelection;
			 
	my @l2 = map { $_->id } @pkgs;
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

	foreach (keys %newSelection) {
	    my $p = $packages->{depslist}[$_] or next;
	    next if $p->flag_selected; #- always installed (accounted in system_size)
	    my $s = $group{$p->name} || $or_ify_cached->(join("\t", $p->rflags));
	    my $m = "$flags\t$s";
	    $group{$p->name} = ($memo{$m} ||= or_clean($m));
	}
    }
    my (%sizes, %pkgs);
    while (my ($k, $v) = each %group) {
	my $pkg = packageByName($packages, $k) or next;
	push @{$pkgs{$v}}, $k;
	$sizes{$v} += $pkg->size - $packages->{sizes}{$pkg->name};
    }
    log::l("pkgs::computeGroupSize took: ", formatTimeRaw(time() - $time));
    log::l(sprintf "%s %dMB %s", $_, $sizes{$_} / sqr(1024), join(',', @{$pkgs{$_}})) foreach keys %sizes;
    \%sizes, \%pkgs;
}


sub openInstallLog() {
    my $f = "$::prefix/root/drakx/install.log";
    open(my $LOG, ">> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept."); #-#
    CORE::select((CORE::select($LOG), $| = 1)[0]);
    URPM::rpmErrorWriteTo(fileno $LOG);
    $LOG;
}

sub rpmDbOpen {
    my ($o_rebuild_needed) = @_;

    if ($o_rebuild_needed) {
	if (my $pid = fork()) {
	    waitpid $pid, 0;
	    $? & 0xff00 and die "rebuilding of rpm database failed";
	} else {
	    log::l("rebuilding rpm database");
	    my $rebuilddb_dir = "$::prefix/var/lib/rpmrebuilddb.$$";
	    -d $rebuilddb_dir and log::l("removing stale directory $rebuilddb_dir"), rm_rf($rebuilddb_dir);

	    URPM::DB::rebuild($::prefix) or log::l("rebuilding of rpm database failed: " . URPM::rpmErrorString()), c::_exit(2);

	    c::_exit(0);
	}
    }

    my $db;
    if ($db = URPM::DB::open($::prefix)) {
	log::l("opened rpm database for examining existing packages");
    } else {
	log::l("unable to open rpm database, using empty rpm db emulation");
	$db = new URPM;
    }

    $db;
}

sub rpmDbCleanLogs() {
    unlink glob("$::prefix/var/lib/rpm/__db.*");
}

sub rpmDbOpenForInstall() {
    my $db = URPM::DB::open($::prefix, 1);
    $db and log::l("opened rpmdb for writing in $::prefix");
    $db;
}

sub cleanOldRpmDb() {
    my $failed;

    foreach (qw(Basenames Conflictname Group Name Packages Providename Requirename Triggername)) {
	-s "$::prefix/var/lib/rpm/$_" or $failed = 'failed';
    }
    #- rebuilding has been successfull, so remove old rpm database if any.
    #- once we have checked the rpm4 db file are present and not null, in case
    #- of doubt, avoid removing them...
    unless ($failed) {
	log::l("rebuilding rpm database completed successfully");
	foreach (qw(conflictsindex.rpm fileindex.rpm groupindex.rpm nameindex.rpm packages.rpm
                    providesindex.rpm requiredby.rpm triggerindex.rpm)) {
	    -e "$::prefix/var/lib/rpm/$_" or next;
	    log::l("removing old rpm file $_");
	    rm_rf("$::prefix/var/lib/rpm/$_");
	}
    }
}

sub selectPackagesAlreadyInstalled {
    my ($packages) = @_;

    log::l("computing installed flags and size of installed packages");
    $packages->{sizes} = $packages->compute_installed_flags($packages->{rpmdb});
}

sub selectPackagesToUpgrade {
    my ($packages, $o_medium) = @_;

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

sub supplCDMountPoint() { install_medium::by_id(1)->method eq 'cdrom' ? "/tmp/image" : "/mnt/cdrom" }

sub installTransactionClosure {
    my ($packages, $id2pkg) = @_;
    my ($id, %closure, @l, $medium, $min_id, $max_id);

    @l = sort { $a <=> $b } keys %$id2pkg;

    #- search first usable medium (sorted by medium ordering).
    foreach (sort { $a->{start} <=> $b->{start} } values %{$packages->{mediums}}) {
	unless ($_->selected) {
	    #- this medium is not selected, but we have to make sure no package is left
	    #- in $id2pkg.
	    if (defined $_->{start} && defined $_->{end}) {
		foreach ($_->{start} .. $_->{end}) {
		    delete $id2pkg->{$_};
		}
		@l = sort { $a <=> $b } keys %$id2pkg;
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

    #- Supplementary CD : switch temporarily to "cdrom" method
    my $suppl_CD = $medium->is_suppl_cd;
    local $::o->{method} = do {
	my $cdrom;
	cat_("/proc/mounts") =~ m,(/dev/\S+)\s+(?:/mnt/cdrom|/tmp/image), and $cdrom = $1;
	if (!defined $cdrom) {
	    (my $cdromdev) = detect_devices::cdroms();
	    $cdrom = $cdromdev->{device};
	    log::l("cdrom redetected at $cdrom");
	    devices::make($cdrom);
	    install_any::ejectCdrom($cdrom) if $::o->{method} eq 'cdrom';
	    install_any::mountCdrom(supplCDMountPoint(), $cdrom);
	} else { log::l("cdrom already found at $cdrom") }
	'cdrom';
    } if $suppl_CD;
    #- it is sure at least one package will be installed according to medium chosen.
    install_any::useMedium($medium->{medium});
    if (install_any::method_allows_medium_change($medium->method)) {
	my $pkg = $packages->{depslist}[$l[0]];

	#- force changeCD callback to be called from main process.
	install_any::getFile($pkg->filename, $::o->{method}, $suppl_CD ? supplCDMountPoint() : undef);
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
#    my (undef, $msg, @para) = @_;
#    log::l("$msg: " . join(',', @para));
}

sub install {
    my ($isUpgrade, $toInstall, $packages) = @_;
    my %packages;

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.
    #- avoid potential problems with rpm db personality change
    rpmDbCleanLogs();

    return if !@$toInstall;

    #- for root loopback'ed /boot
    my $loop_boot = fs::loopback::prepare_boot();

    #- first stage to extract some important information
    #- about the selected packages. This is used to select
    #- one or many transactions.
    my ($total, $nb);
    foreach my $pkg (@$toInstall) {
	$packages{$pkg->id} = $pkg;
	$nb++;
	$total += to_int($pkg->size); #- do not correct for upgrade!
    }

    log::l("pkgs::install $::prefix");
    log::l("pkgs::install the following: ", join(" ", map { $_->name } values %packages));

    URPM::read_config_files();
    URPM::add_macro(join(' ', '__dbi_cdb', URPM::expand('%__dbi_cdb'), 'nofsync'));
    my $LOG = openInstallLog();

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($packages, user => undef, install => $nb, $total);

    do {
	my @transToInstall = installTransactionClosure($packages, \%packages);
	$nb = values %packages;

	#- added to exit typically after last media unselected.
	if ($nb == 0 && scalar(@transToInstall) == 0) {
	    cleanHeaders();

	    fs::loopback::save_boot($loop_boot);
	    return;
	}

	#- extract headers for parent as they are used by callback.
	extractHeaders(\@transToInstall, $packages->{mediums});

	my $close = sub {
	    my ($pkg) = @_;
	    #- update flag associated to package.
	    $pkg->set_flag_installed(1);
	    $pkg->set_flag_upgrade(0);
	    #- update obsoleted entry.
	    my $rejected = $packages->{state}{rejected};
	    foreach (keys %$rejected) {
		if (delete $rejected->{$_}{closure}{$pkg->fullname}) {
		    %{$rejected->{$_}{closure}} or delete $rejected->{$_};
		}
	    }
	};

	my ($retry_pkg, $retry_count);
	while ($retry_pkg || @transToInstall) {

		if ($::testing) {
		    my $size_typical = $nb ? int($total/$nb) : 0;
		    foreach (@transToInstall) {
			log::l("i would install ", $_->name, " now");
			my $id = $_->id;
			installCallback($packages, inst => $id, start => 0, $size_typical);
			installCallback($packages, inst => $id, progress => 0, $size_typical);
			$close->($_);
		    }
		} else {
		    my $db = rpmDbOpenForInstall() or die "error opening RPM database: ", URPM::rpmErrorString();
		    my $trans = $db->create_transaction($::prefix);
		    if ($retry_pkg) {
			log::l("opened rpm database for retry transaction of 1 package only");
			$trans->add($retry_pkg, $isUpgrade && allowedToUpgrade($retry_pkg->name))
			    or log::l("add failed for " . $retry_pkg->fullname);
		    } else {
			log::l("opened rpm database for transaction of " . int(@transToInstall) .
			       " new packages, still $nb after that to do");
			$trans->add($_, $isUpgrade && allowedToUpgrade($_->name))
			  foreach @transToInstall;
		    }

		    my @checks = $trans->check; @checks and log::l("check failed : " . join("\n               ", @checks));
		    $trans->order or die "error ordering package list: " . URPM::rpmErrorString();
		    $trans->set_script_fd(fileno $LOG);

		    log::l("rpm transactions start");
		    my $fd; #- since we return the "fileno", perl does not know we're still using it, and so closes it, and :-(
		    my @probs = $trans->run($packages, force => 1, nosize => 1, callback_open => sub {
						my ($packages, $_type, $id) = @_;
						my $pkg = defined $id && $packages->{depslist}[$id];
						my $medium = packageMedium($packages, $pkg);
						my $f = $pkg && $pkg->filename;
						print $LOG "$f\n";
						if ($medium->is_suppl_cd) {
						    $fd = install_any::getFile($f, $::o->{method}, supplCDMountPoint());
						} else {
						    $fd = install_any::getFile($f, $::o->{method}, $medium->{prefix});
						}
						$fd ? fileno $fd : -1;
					    }, callback_close => sub {
						my ($packages, $_type, $id) = @_;
						my $pkg = defined $id && $packages->{depslist}[$id] or return;
						my $check_installed;
						$db->traverse_tag('name', [ $pkg->name ], sub {
								      my ($p) = @_;
								      $check_installed ||= $pkg->compare_pkg($p) == 0;
								  });
						$check_installed or log::l($pkg->name . " not installed, " . URPM::rpmErrorString());
						$check_installed and $close->($pkg);
					    }, callback_inst => \&installCallback,
					);
		    log::l("transactions done, now trying to close still opened fd");
		    install_any::getFile('XXX'); #- close still opened fd.

		    @probs and die "installation of rpms failed:\n  ", join("\n  ", @probs);
		}

	    #- if we are using a retry mode, this means we have to split the transaction with only
	    #- one package for each real transaction.
	    if (!$retry_pkg) {
		my @badPackages;
		foreach (@transToInstall) {
		    if (!$_->flag_installed && packageMedium($packages, $_)->selected && !exists($ignoreBadPkg{$_->name})) {
			push @badPackages, $_;
			log::l("bad package " . $_->fullname);
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
		if (!$retry_pkg->flag_installed && packageMedium($packages, $retry_pkg)->selected && !exists($ignoreBadPkg{$retry_pkg->name})) {
		    if ($retry_count) {
			log::l("retrying installing package " . $retry_pkg->fullname . " alone in a transaction");
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
	cleanHeaders();
    } while $nb > 0 && !$pkgs::cancel_install;

    log::l("closing install.log file");
    close $LOG;
    eval { fs::mount::umount("/mnt/cdrom") };

    cleanHeaders();

    fs::loopback::save_boot($loop_boot);
}

sub remove {
    my ($toRemove, $packages) = @_;

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.

    return if !@{$toRemove || []};

    my $db = rpmDbOpenForInstall() or die "error opening RPM database: ", URPM::rpmErrorString();
    my $trans = $db->create_transaction($::prefix);

    foreach my $p (@$toRemove) {
	#- stuff remove all packages that matches $p, not a problem since $p has name-version-release format.
	$trans->remove($p);
    }

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install_steps_gtk.pm,...).
    installCallback($db, user => undef, remove => scalar @$toRemove);

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
    my $provides = $packages->{provides};

    my @l = grep { ($_->flag_requested || $_->flag_installed) && !$_->flag_base } @{$packages->{depslist}};

    my %required_ids;
    foreach (@l) {
	foreach ($_->requires_nosense) {
	    my $h = $provides->{$_} or next;
	    my @provides = keys %$h;
	    $required_ids{$provides[0]} = 1 if @provides == 1;
	}
    }
    [ map { $_->name } grep { !$required_ids{$_->id} } @l ];    
}

sub naughtyServers_list {
    my ($quiet) = @_;

    my @_old_81 = qw(
freeswan
);
    my @_old_82 = qw(
vnc-server
postgresql-server
);

    my @_old_92 = qw(
postfix ypbind bind ibod
);

    my @_removed_92 = qw(
mcserv
samba
lpr
);

    my @_moved_to_contrib_92 = qw(
boa
LPRng
wu-ftpd
am-utils
);

    my @new_80 = qw(
jabber
am-utils
boa
cups
drakxtools-http
finger-server
imap
leafnode
ntp
openssh-server
pidentd
proftpd
rwall
squid
webmin
wu-ftpd
);

    my @new_81 = qw(
ftp-server-krb5
telnet-server-krb5
ypserv
);

    my @new_82 = qw(
LPRng
inn
netatalk
nfs-utils
rusers-server
samba-swat
tftp-server
ucd-snmp
);

    my @new_92 = qw(
clusternfs
gkrellm-server
lisa
mon
net-snmp
openldap-servers
samba-server
saned
vsftpd
);

    my @new_2006 = qw(
apache-conf
bpalogin
cfengine-cfservd
freeradius
mDNSResponder
openslp
pxe
routed
sendmail
spamassassin-spamd
);

    my @not_warned = qw(
nfs-utils-clients
portmap
howl
); # X server

    (@new_80, @new_81, @new_82, @new_92, @new_2006, if_(!$quiet, @not_warned));
}

sub naughtyServers {
    my ($packages) = @_;

    grep {
	my $p = packageByName($packages, $_);
	$p && $p->flag_selected;
    } naughtyServers_list('quiet');
}

package install_medium;

use strict;

#- list of fields :
#-	descr (text description)
#-	end (last rpm id)
#-	fakemedium ("$descr ($method$medium_name)", used locally by urpmi)
#-	hdlist
#-	hdlist_size
#-	ignored
#-	issuppl (is a supplementary media)
#-	key_ids (hashref, values are key ids)
#-	medium (number of the medium)
#-	method
#-	prefix
#-	finalprefix (for install_urpmi)
#-	pubkey
#-	rpmsdir
#-	selected
#-	start (first rpm id)
#-	synthesis_hdlist_size
#-	update (for install_urpmi)
#-	with_hdlist (for install_urpmi)

#- create a new medium
sub new { my ($class, %h) = @_; bless \%h, $class }

#- retrieve medium by id (usually a number) or an empty placeholder
sub by_id {
    my ($medium_id, $o_packages) = @_;
    $o_packages = $::o->{packages} unless defined $o_packages;
    defined $o_packages->{mediums}{$medium_id}
	? $o_packages->{mediums}{$medium_id}
	#- if the medium is not known, return a placeholder
	: bless { invalid => 1, medium => $medium_id };
}

#- is this medium a supplementary medium ?
sub is_suppl { my ($self) = @_; $self->{issuppl} }

sub mark_suppl { my ($self) = @_; $self->{issuppl} = 1 }

#- is this medium a supplementary CD ?
sub is_suppl_cd { my ($self) = @_; $self->{method} eq 'cdrom' && $self->is_suppl }

sub method {
    my ($self) = @_;
    $self->{method};
}

sub selected { my ($self) = @_; $self->{selected} }
sub select   { my ($self) = @_; $self->{selected} = 1 }
#- unselect, keep it mind it was unselected
sub refuse   { my ($self) = @_; $self->{selected} = undef }

#- XXX this function seems to be obsolete
sub ignored  { my ($self) = @_; $self->{ignored} }

#- guess the CD number for this media.
#- XXX lots of heuristics here, must design this properly
sub get_cd_number {
    my ($self) = @_;
    my $description = $self->{descr};
    (my $cd) = $description =~ /\b(?:CD|DVD) ?(\d+)\b/i;
    if (!$cd) { #- test for single unnumbered DVD
	$cd = 1 if $description =~ /\bDVD\b/i;
    }
    if (!$cd) { #- test for mini-ISO
	$cd = 1 if $description =~ /\bmini.?cd\b/i;
    }
    #- don't mix suppl. cds with regular ones
    if ($description =~ /suppl/i) { $cd += 100 }
    $cd;
}

1;
