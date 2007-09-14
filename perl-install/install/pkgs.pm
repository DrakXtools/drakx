package install::pkgs; # $Id$

use strict;

BEGIN {
    # needed before "use URPM"
    mkdir '/etc/rpm';
    symlink '/tmp/stage2/etc/rpm/platform', '/etc/rpm/platform';
}

use URPM;
use URPM::Resolve;
use URPM::Signature;
use urpm::select;
use common;
use install::any;
use install::media qw(getFile_ getAndSaveFile_ packageMedium);
use run_program;
use detect_devices;
use log;
use fs;
use fs::loopback;
use c;


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


sub cleanHeaders() {
    rm_rf("$::prefix/tmp/headers") if -e "$::prefix/tmp/headers";
}

#- get all headers from an hdlist file.
sub extractHeaders {
    my ($pkgs, $media) = @_;
    cleanHeaders();

    foreach my $medium (@$media) {
	$medium->{selected} or next;

	my @l = grep { $_->id >= $medium->{start} && $_->id <= $medium->{end} } @$pkgs or next;
	eval {
	    require packdrake;
	    my $packer = new packdrake(install::media::hdlist_on_disk($medium), quiet => 1);
	    $packer->extract_archive("$::prefix/tmp/headers", map { $_->header_filename } @l);
	};
	$@ and log::l("packdrake failed: $@");
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

#- search package with given name and compatible with current architecture.
#- take the best one found (most up-to-date).
sub packageByName {
    my ($packages, $name) = @_;

    my @l = grep { $_->is_arch_compat && $_->name eq $name } packagesProviding($packages, $name);

    my $best;
    foreach (@l) {
	if ($best && $best != $_) {
	    $_->compare_pkg($best) > 0 and $best = $_;
	} else {
	    $best = $_;
	}
    }
    $best or log::l("unknown package `$name'");
    $best;
}

sub bestKernelPackage {
    my ($packages) = @_;

    my @preferred_exts =
      $::o->{match_all_hardware} ? (arch() =~ /i.86/ ? '-desktop586' : '-desktop') :
      detect_devices::is_xbox() ? '-xbox' :
      detect_devices::is_i586() ? '-desktop586' :
      detect_devices::isLaptop() ? '-laptop' :
      detect_devices::dmi_detect_memory() > 3.8 * 1024 ? '-server' :
      '-desktop';

    my @kernels = grep { $_ } map { packageByName($packages, "kernel$_-latest") } @preferred_exts;

    log::l("bestKernelPackage (" . join(':', @preferred_exts) . "): " . join(' ', map { $_->name } @kernels) . (@kernels > 1 ? ' (choosing the first)' : ''));

    $kernels[0];
}

sub packagesToInstall {
    my ($packages) = @_;
    my @packages;
    foreach (@{$packages->{media}}) {
	$_->{selected} or next;
	log::l("examining packagesToInstall of medium $_->{name}");
	push @packages, grep { $_->flag_selected } install::media::packagesOfMedium($packages, $_);
    }
    log::l("found " . scalar(@packages) . " packages to install");
    @packages;
}

sub packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    packageMedium($packages, $pkg)->{selected} or return;

    +{ $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $_db, $_state, $choices, $virtual_pkg_name, $prefered) = @_;
  
    if ($prefered && @$prefered) {
	@$prefered;
    } elsif (my @l = packageCallbackChoices_($urpm, $choices)) {
	@l;
    } else {
	log::l("packageCallbackChoices: default choice from " . join(",", map { $_->name } @$choices) . " for $virtual_pkg_name");
	$choices->[0];
    }
}

sub packageCallbackChoices_ {
    my ($urpm, $choices) = @_;

    my ($prefer, $_other) = urpm::select::get_preferred($urpm, $choices, '');
    if (@$prefer) {
	@$prefer;
    } elsif ($choices->[0]->name =~ /^kernel-(.*source-|.*-devel-)/) {
	my @l = grep {
	    if ($_->name =~ /^kernel-.*source-stripped-(.*)/) {
		my $version = quotemeta($1);
		find {
		    $_->name =~ /-$version$/ && ($_->flag_installed || $_->flag_selected);
		} packagesProviding($urpm, 'kernel');
	    } elsif ($_->name =~ /(kernel-.*)-devel-(.*)/) {
		my $kernel = "$1-$2";
		my $p = packageByName($urpm, $kernel);
		$p && ($p->flag_installed || $p->flag_selected);
	    } elsif ($_->name =~ /^kernel-.*source-/) {
		#- hopefully we don't have a media with kernel-source but not kernel-source-stripped nor kernel-.*-devel
		0;
	    } else {
		log::l("unknown kernel-source package " . $_->fullname);
		0;
	    }
	} @$choices;

	log::l("packageCallbackChoices: kernel source chosen ", join(",", map { $_->name } @l), " in ", join(",", map { $_->name } @$choices));

	@l;
    } else {
	();
    }
}

sub skip_packages {
    my ($packages, $skipped_packages) = @_;
    $packages->compute_flags($skipped_packages, skip => 1);
}

sub select_by_package_names {
    my ($packages, $names, $b_base) = @_;

    my @l;
    foreach (@$names) {
	my $p = packageByName($packages, $_) or next;
	push @l, selectPackage($packages, $p, $b_base);
    }
    @l;
}

sub select_by_package_names_or_die {
    my ($packages, $names, $b_base) = @_;

    foreach (@$names) {
	my $p = packageByName($packages, $_) or die "package $_ not found";
	!$p->flag_installed && !$p->flag_selected or next;
	selectPackage($packages, $p, $b_base) or die "package $_ can't be selected";
    }
}

sub resolve_requested_and_check {
    my ($packages, $state, $requested) = @_;

    my @l = $packages->resolve_requested($packages->{rpmdb}, $state, $requested,
					 callback_choices => \&packageCallbackChoices);

    if (find { !exists $state->{selected}{$_} } keys %$requested) {
	my @rejected = urpm::select::unselected_packages($packages, $state);
	log::l("ERROR: selection failed: " . urpm::select::translate_why_unselected($packages, $state, @rejected));
    }

    @l;
}

sub selectPackage {
    my ($packages, $pkg, $b_base) = @_;

    my $state = $packages->{state} ||= {};

    $packages->{rpmdb} ||= rpmDbOpen();

    my @l = resolve_requested_and_check($packages, $state, packageRequest($packages, $pkg) || {});

    if ($b_base) {
	$_->set_flag_base foreach @l;
    }
    @l;
}

sub unselectPackage {
    my ($packages, $pkg) = @_;

    #- base packages are not unselectable,
    #- and already unselected package are no more unselectable.
    $pkg->flag_base and return;
    $pkg->flag_selected or return;

    my $state = $packages->{state} ||= {};
    log::l("removing selection on package " . $pkg->fullname);
    my @l = $packages->disable_selected($packages->{rpmdb}, $state, $pkg);
    log::l("   removed selection on package " . $pkg->fullname . "gives " . join(',', map { scalar $_->fullname } @l));
}

sub unselectAllPackages {
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
    resolve_requested_and_check($packages, $packages->{state}, \%keep_selected);
}

sub empty_packages() {
    my $packages = new URPM;

    #- add additional fields used by DrakX.
    @$packages{qw(count media)} = (0, []);

    $packages->{log} = \&log::l;
    $packages->{prefer_vendor_list} = '/etc/urpmi/prefer.vendor.list';
    $packages->{keep_unrequested_dependencies} = 1;

    $packages;
}

sub read_rpmsrate {
    my ($packages, $rpmsrate_flags_chosen, $file, $match_all_hardware) = @_;
    require pkgs;
    pkgs::read_rpmsrate($packages, $rpmsrate_flags_chosen, $file, $match_all_hardware);
}

sub readCompssUsers {
    my ($file) = @_;

    my $f = common::open_file($file) or log::l("can not find $file: $!"), return;
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
    my $urpmidir = install::media::urpmidir();
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

	my @l = resolve_requested_and_check($packages, $state, packageRequest($packages, $p) || {});

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
    my (%group, %memo);

    log::l("install::pkgs::computeGroupSize");
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
		my @requires = map { [ $_, keys %{$packages->{provides}{$_} || {}} ] } $pkg->requires_nosense;
		foreach (sort { @$a <=> @$b } @requires) { #- sort on number of provides (it helps choosing "b" in: "a" requires both "b" and virtual={"b","c"})
		    my ($virtual, @choices) = @$_;
		    if (@choices <= 1) {
			#- only one choice :)
		    } elsif (find { exists $newSelection{$_} } @choices) {
			@choices = ();
		    } else {
			my @choices_pkgs = map { $packages->{depslist}[$_] } @choices;
			if (find { $_->flag_available } @choices_pkgs) {
			    @choices = (); #- one package is already selected (?)
			} else {
			    @choices = map { $_->id } packageCallbackChoices($packages, undef, undef, \@choices_pkgs, $virtual);
			}
		    }
		    push @l2, @choices;
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
    log::l("install::pkgs::computeGroupSize took: ", formatTimeRaw(time() - $time));
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
    my ($b_rebuild_needed, $o_rpm_dbapi) = @_;

    clean_rpmdb_shared_regions();
    
    if (my $wanted_dbapi = $o_rpm_dbapi) {
	log::l("setting %_dbapi to $wanted_dbapi");
	substInFile { s/%_dbapi.*//; $_ .= "%_dbapi $wanted_dbapi\n" if eof } "$::prefix/etc/rpm/macros";
	URPM::add_macro("_dbapi $wanted_dbapi");
    }

    if ($b_rebuild_needed && !$o_rpm_dbapi) {
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

sub clean_rpmdb_shared_regions() {
    unlink glob("$::prefix/var/lib/rpm/__db.*");
}

sub open_rpm_db_rw() {
    clean_rpmdb_shared_regions();
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

    $packages->compute_installed_flags($packages->{rpmdb});

    my %sizes;
    $packages->{rpmdb}->traverse(sub {
	my ($p) = @_;      
	$sizes{$p->name} += $p->size;
    });
    $packages->{sizes} = \%sizes;
}

sub selectPackagesToUpgrade {
    my ($packages, $o_medium) = @_;

    log::l("selecting packages to upgrade");

    my $state = $packages->{state} ||= {};
    $state->{selected} = {};

    my %selection;
    $packages->request_packages_to_upgrade($packages->{rpmdb}, $state, \%selection,
					   requested => undef,
					   $o_medium ? (start => $o_medium->{start}, end => $o_medium->{end}) : (),
					  );
    log::l("selected pkgs to upgrade: " . join(' ', map { $packages->{depslist}[$_]->name } keys %selection));

    log::l("resolving dependencies...");
    resolve_requested_and_check($packages, $state, \%selection);
    log::l("...done");
    log::l("finally selected pkgs: ", join(" ", sort map { $_->name } grep { $_->flag_selected } @{$packages->{depslist}}));
}

sub installTransactionClosure {
    my ($packages, $id2pkg, $isUpgrade) = @_;

    foreach (grep { !$_->{selected} } @{$packages->{media}}) {
	foreach ($_->{start} .. $_->{end}) {
	    delete $id2pkg->{$_};
	}
    }

    my @l = ikeys %$id2pkg;
    my $medium;

    #- search first usable medium (media are sorted).
    foreach (@{$packages->{media}}) {
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

    #- it is sure at least one package will be installed according to medium chosen.
    {
	my $pkg = $packages->{depslist}[$l[0]];
	my $rpm = install::media::rel_rpm_file($medium, $pkg->filename);
	if ($install::media::postinstall_rpms && -e "$install::media::postinstall_rpms/$rpm") {
	    #- very special case where the rpm has been copied on disk
	} elsif (!install::media::change_phys_medium($medium->{phys_medium}, $rpm, $packages)) {
	    #- keep in mind the asked medium has been refused.
	    #- this means it is no longer selected.
	    #- (but do not unselect supplementary CDs.)
	    $medium->{selected} = 0;
	}
    }

    my %closure;
    foreach my $id (@l) {
	my @l2 = $id;

	if ($isUpgrade && $id < 20) {
	    #- HACK for upgrading to 2006.0: for the 20 first main packages, upgrade one by one
	    #- why? well:
	    #- * librpm is fucked up when ordering pkgs, pkg "setup" is removed before being installed.
	    #-   the result is /etc/group.rpmsave and no /etc/group
	    #- * pkg locales requires basesystem, this is stupid, the result is a huge first transaction
	    #-   and it doesn't even help /usr/bin/locale_install.sh since it's not a requires(post)
	    $closure{$id} = undef;
	    last;
	}

	while (defined($id = shift @l2)) {
	    exists $closure{$id} and next;
	    $closure{$id} = undef;

	    my $pkg = $packages->{depslist}[$id];
	    foreach ($pkg->requires_nosense) {
		if (my $dep_id = find { $id2pkg->{$_} } keys %{$packages->{provides}{$_} || {}}) {
		    push @l2, $dep_id;
		}
	    }
	}

	keys %closure >= $limitMinTrans and last;
    }

    map { delete $id2pkg->{$_} } grep { $id2pkg->{$_} } ikeys %closure;
}

sub install {
    my ($isUpgrade, $toInstall, $packages, $callback) = @_;
    my %packages;

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.
    #- avoid potential problems with rpm db personality change
    clean_rpmdb_shared_regions();

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

    log::l("install::pkgs::install $::prefix");
    log::l("install::pkgs::install the following: ", join(" ", map { $_->name } values %packages));

    URPM::read_config_files();
    URPM::add_macro(join(' ', '__dbi_cdb', URPM::expand('%__dbi_cdb'), 'nofsync'));
    my $LOG = openInstallLog();

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install::steps_gtk.pm,...).
    $callback->($packages, user => undef, install => $nb, $total);

    do {
	my @transToInstall = installTransactionClosure($packages, \%packages, $isUpgrade);
	$nb = values %packages;

	#- added to exit typically after last media unselected.
	if ($nb == 0 && scalar(@transToInstall) == 0) {
	    cleanHeaders();

	    fs::loopback::save_boot($loop_boot);
	    return;
	}

	#- extract headers for parent as they are used by callback.
	extractHeaders(\@transToInstall, $packages->{media});

	my ($retry, $retry_count);
	while (@transToInstall) {
	    my $retry_pkg = $retry && $transToInstall[0];

	    if ($retry) {
		log::l("retrying installing package " . $retry_pkg->fullname . " alone in a transaction ($retry_count)");
	    }
	    _install_raw($packages, [ $retry ? $retry_pkg : @transToInstall ],
			 $isUpgrade, $callback, $LOG, $retry_pkg);

	    @transToInstall = grep {
		if ($_->flag_installed || !packageMedium($packages, $_)->{selected}) {
		    $_->free_header;
		    0;
		} else {
		    log::l("failed to install " . $_->fullname . " (will retry)") if !$retry;
		    1;
		}
	    } @transToInstall;

	    if (@transToInstall) {
		if (!$retry || $retry_pkg != $transToInstall[0]) {
		    #- go to next
		    $retry_count = 1;
		} elsif ($retry_pkg == $transToInstall[0] && $retry_count < 3) {
		    $retry_count++;
		} else {
		    log::l("failed to install " . $retry_pkg->fullname);

		    my $medium = packageMedium($packages, $retry_pkg);
		    my $name = $retry_pkg->fullname;
		    my $rc = cdie("error installing package list: $name $medium->{name}");
		    if ($rc eq 'retry') {
			$retry_count = 1;
		    } else {
			if ($rc eq 'disable_media') {
			    $medium->{selected} = 0;
			}
			$retry_pkg->set_flag_requested(0);
			$retry_pkg->set_flag_required(0);

			#- dropping it
			$retry_pkg->free_header;
			shift @transToInstall;
			$retry_count = 1;
		    }
		}
		$retry = 1;
	    }
	}
	cleanHeaders();
    } while $nb > 0 && !$install::pkgs::cancel_install;

    log::l("closing install.log file");
    close $LOG;

    cleanHeaders();
    clean_rpmdb_shared_regions(); #- workaround librpm which is buggy when using librpm rooted and the just installed rooted library

    fs::loopback::save_boot($loop_boot);
}

sub _install_raw {
    my ($packages, $transToInstall, $isUpgrade, $callback, $LOG, $noscripts) = @_;

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

    my $db = open_rpm_db_rw() or die "error opening RPM database: ", URPM::rpmErrorString();
    my $trans = $db->create_transaction($::prefix);

    log::l("opened rpm database for transaction of " . int(@$transToInstall) . " packages (isUpgrade=$isUpgrade)");
    foreach (@$transToInstall) {
	$trans->add($_, update => $isUpgrade ? 1 : 0)
	  or log::l("add failed for " . $_->fullname);
    }

    my @checks = $trans->check; @checks and log::l("check failed : " . join("\n               ", @checks));
    $trans->order or die "error ordering package list: " . URPM::rpmErrorString();
    $trans->set_script_fd(fileno $LOG);

    log::l("rpm transactions start");
    my $fd; #- since we return the "fileno", perl does not know we're still using it, and so closes it, and :-(
    my @probs = $trans->run($packages, force => 1, nosize => 1, 
			    if_($noscripts, noscripts => 1),
			    callback_open => sub {
				my ($packages, $_type, $id) = @_;
				&$callback;
				my $pkg = defined $id && $packages->{depslist}[$id];
				my $medium = packageMedium($packages, $pkg);
				my $f = $pkg && install::media::rel_rpm_file($medium, $pkg->filename);
				print $LOG "$f\n";
				undef $fd;
				$fd = getFile_($medium->{phys_medium}, $f);
				$fd ? fileno $fd : -1;
			    }, callback_close => sub {
				my ($packages, $_type, $id) = @_;
				&$callback;
				my $pkg = defined $id && $packages->{depslist}[$id] or return;
				my $check_installed;
				$db->traverse_tag('name', [ $pkg->name ], sub {
						      my ($p) = @_;
						      $check_installed ||= $pkg->compare_pkg($p) == 0;
						  });
				$check_installed or log::l($pkg->name . " not installed, " . URPM::rpmErrorString());
				$check_installed and $close->($pkg);
			    }, callback_inst => $callback,
			);
    log::l("transactions done, now trying to close still opened fd");

    @probs and die "installation of rpms failed:\n  ", join("\n  ", @probs);
}

sub upgrade_by_removing_pkgs {
    my ($packages, $callback, $extension, $upgrade_name) = @_;

    my $upgrade_data;
    if ($upgrade_name) {
	my @l = glob("$ENV{SHARE_PATH}/upgrade/$upgrade_name*");
	@l == 0 and log::l("upgrade_by_removing_pkgs: no special upgrade data");
	@l > 1 and log::l("upgrade_by_removing_pkgs: many special upgrade data (" . join(' ', @l) . ")");
	$upgrade_data = $l[0];
    }
    
    log::l("upgrade_by_removing_pkgs (extension=$extension, upgrade_data=$upgrade_data)");

    #- put the release file in /root/drakx so that we continue an upgrade even if the file has gone
    my $f = common::release_file($::prefix);
    if (dirname($f) eq '/etc') {
	output_p("$::prefix/root/drakx/" . basename($f) . '.upgrading', cat_("$::prefix$f"));
    }
    my $busy_var_tmp = "$::prefix/var/tmp/ensure-rpm-does-not-remove-this-dir";
    touch($busy_var_tmp);

    if ($upgrade_data) {
	foreach (glob("$upgrade_data/pre.*")) {
	    my $f = '/tmp/' . basename($_);
	    cp_af($_, "$::prefix$f");
	    run_program::rooted($::prefix, $f);
	    unlink "$::prefix$f";
	}
    }

    my @was_installed = remove_pkgs_to_upgrade($packages, $callback, $extension);

    {
	my @restore_files = qw(/etc/passwd /etc/group /etc/ld.so.conf);
	foreach (@restore_files) {
	    rename "$::prefix$_.rpmsave", "$::prefix$_";
	}
        install::any::create_minimal_files();
	unlink $busy_var_tmp;
    }

    my %map = map {
	chomp;
	my ($name, @new) = split;
	$name => \@new;
    } $upgrade_data ? cat_("$upgrade_data/map") : ();

    log::l("upgrade_by_removing_pkgs: map $upgrade_data/map gave " . (int keys %map) . " rules");

    my $log;
    my @to_install = uniq(map { 
	$log .= " $_=>" . join('+', @{$map{$_}}) if $map{$_};
	$map{$_} ? @{$map{$_}} : $_;
    } @was_installed);
    log::l("upgrade_by_removing_pkgs special maps:$log");
    log::l("upgrade_by_removing_pkgs: wanted packages: ", join(' ', sort @to_install));

    @to_install;
}

sub removed_pkgs_to_upgrade_file() { "$::prefix/root/drakx/removed_pkgs_to_upgrade" }

sub remove_pkgs_to_upgrade {
    my ($packages, $callback, $extension) = @_;

    my @to_remove;
    my @was_installed;
    {
	$packages->{rpmdb} ||= rpmDbOpen();
	$packages->{rpmdb}->traverse(sub {
	    my ($pkg) = @_;
	    if ($pkg->release =~ /$extension$/) {
		push @was_installed, $pkg->name;
		push @to_remove, scalar $pkg->fullname;
	    }
	});
    }
    if (-e removed_pkgs_to_upgrade_file()) {
	log::l("removed_pkgs_to_upgrade: using saved installed packages list ", removed_pkgs_to_upgrade_file());
	@was_installed = chomp_(cat_(removed_pkgs_to_upgrade_file()));
    } else {
	log::l("removed_pkgs_to_upgrade: saving (old) installed packages in ", removed_pkgs_to_upgrade_file());
	output_p(removed_pkgs_to_upgrade_file(), map { "$_\n" } @was_installed);
    }

    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.

    remove(\@to_remove, $callback, noscripts => 1);

    @was_installed;
}

sub remove_marked_ask_remove {
    my ($packages, $callback) = @_;

    my @to_remove = keys %{$packages->{state}{ask_remove}} or return;
    
    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    remove(\@to_remove, $callback, force => 1);

    delete $packages->{state}{ask_remove}{$_} foreach @to_remove;
}

sub remove_raw {
    my ($to_remove, $callback, %run_transaction_options) = @_;

    log::l("removing: " . join(' ', @$to_remove));

    URPM::read_config_files();
    URPM::add_macro(URPM::expand('__dbi_cdb %__dbi_cdb nofsync'));

    my $db = open_rpm_db_rw() or die "error opening RPM database: ", URPM::rpmErrorString();
    my $trans = $db->create_transaction($::prefix);

    #- stuff remove all packages that matches $p, not a problem since $p has name-version-release format.
    $trans->remove($_) foreach @$to_remove;

    $callback->($db, user => undef, remove => scalar @$to_remove);

    $trans->run(undef, %run_transaction_options, callback_uninst => $callback);
}
sub remove {
    my ($_to_remove, $_callback, %run_transaction_options) = @_;

    my @pbs = &remove_raw;
    if (@pbs && !$run_transaction_options{noscripts}) {
	$run_transaction_options{noscripts} = 1;
	@pbs = &remove_raw;
    }
    if (@pbs) {
	die "removing of old rpms failed:\n  ", join("\n  ", @pbs);
    }
}

sub selected_leaves {
    my ($packages) = @_;
    my $provides = $packages->{provides};

    my @l = grep { $_->flag_requested || $_->flag_installed } @{$packages->{depslist}};

    my %required_ids;
    foreach my $pkg (@l) {
	foreach my $req ($pkg->requires_nosense) {
	    my $h = $provides->{$req} or next;
	    my @provides = my ($provide) = keys %$h;
	    @provides == 1 or next;
	    if ($provide != (exists $required_ids{$pkg->id} ? $required_ids{$pkg->id} : $pkg->id)) {
#		log::l($packages->{depslist}[$provide]->name . " is not a leaf because required by " . $pkg->name . " (through require $req)"); 
		#- $pkg requires $req, provided by $provide, so we can skip $provide
		$required_ids{$provide} = $pkg->id;
	    }
	}
    }
    [ map { $_->name } grep { ! exists $required_ids{$_->id} } @l ];    
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
lisa
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

1;
