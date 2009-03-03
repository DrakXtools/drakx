package install::pkgs; # $Id$

use strict;

BEGIN {
    # needed before "use URPM"
    mkdir '/etc/rpm';
    symlink "/tmp/stage2/etc/rpm/$_", "/etc/rpm/$_" foreach 'macros.d';
}

use URPM;
use URPM::Resolve;
use URPM::Signature;
use urpm;
use urpm::args;
use urpm::main_loop;
use urpm::select;
use common;
use install::any;
use install::media qw(getFile_ getAndSaveFile_ packageMedium);
use run_program;
use detect_devices;
use log;
use fs;
use fs::any;
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

#- search package with given name and compatible with current architecture.
#- take the best one found (most up-to-date).
sub packageByName {
    my ($packages, $name) = @_;

    my @l = grep { $_->is_arch_compat && $_->name eq $name } URPM::packages_providing($packages, $name);

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

sub _bestKernel_extensions {
    my ($o_match_all_hardware) = @_;

    $o_match_all_hardware ? (arch() =~ /i.86/ ? '-desktop586' : '-desktop') :
      detect_devices::is_xbox() ? '-xbox' :
      detect_devices::is_i586() ? '-desktop586' :
      arch() =~ /i.86/ && detect_devices::dmi_detect_memory() > 3.8 * 1024 || detect_devices::isServer() ? '-server' :
      '-desktop';
}

sub bestKernelPackage {
    my ($packages, $o_match_all_hardware) = @_;

    my @preferred_exts = _bestKernel_extensions($o_match_all_hardware);
    my @kernels = grep { $_ } map { packageByName($packages, "kernel$_-latest") } @preferred_exts;

    log::l("bestKernelPackage (" . join(':', @preferred_exts) . "): " . join(' ', map { $_->name } @kernels) . (@kernels > 1 ? ' (choosing the first)' : ''));

    $kernels[0];
}

sub packagesToInstall {
    my ($packages) = @_;
    my @packages;
    foreach (@{$packages->{media}}) {
	!$_->{ignore} or next;
	log::l("examining packagesToInstall of medium $_->{name}");
	push @packages, grep { $_->flag_selected } install::media::packagesOfMedium($packages, $_);
    }
    log::l("found " . scalar(@packages) . " packages to install");
    @packages;
}

sub _packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    !packageMedium($packages, $pkg)->{ignore} or return;

    +{ $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $_db, $_state, $choices, $virtual_pkg_name, $prefered) = @_;
  
    if ($prefered && @$prefered) {
	@$prefered;
    } elsif (my @l = _packageCallbackChoices_($urpm, $choices, $virtual_pkg_name)) {
	@l;
    } else {
	log::l("packageCallbackChoices: default choice from " . join(",", map { $_->name } @$choices) . " for $virtual_pkg_name");
	$choices->[0];
    }
}

sub _packageCallbackChoices_ {
    my ($urpm, $choices, $virtual_pkg_name) = @_;

    my ($prefer, $_other) = urpm::select::get_preferred($urpm, $choices, '');
    if (@$prefer) {
	@$prefer;
    } elsif ($virtual_pkg_name eq 'kernel') {
	my $re = join('|', map { "kernel\Q$_-2" } _bestKernel_extensions());
	my @l = grep { $_->name =~ $re } @$choices;
	log::l("packageCallbackChoices: kernel chosen ", join(",", map { $_->name } @l), " in ", join(",", map { $_->name } @$choices));
	@l;
    } elsif ($choices->[0]->name =~ /^kernel-(.*source-|.*-devel-)/) {
	my @l = grep {
	    if ($_->name =~ /^kernel-.*source-stripped-(.*)/) {
		my $version = quotemeta($1);
		find {
		    $_->name =~ /-$version$/ && ($_->flag_installed || $_->flag_selected);
		} $urpm->packages_providing('kernel');
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
	my ($_pkgs, $error) = _selectPackage_with_error($packages, $p, $b_base);
	$error and die N("Some packages requested by %s cannot be installed:\n%s", $_, $error);
    }
}

sub _resolve_requested_and_check {
    my ($packages, $state, $requested) = @_;

    my @l = $packages->resolve_requested($packages->{rpmdb}, $state, $requested,
					 callback_choices => \&packageCallbackChoices);

    my $error;
    if (find { !exists $state->{selected}{$_} } keys %$requested) {
	my @rejected = urpm::select::unselected_packages($packages, $state);
	$error = urpm::select::translate_why_unselected($packages, $state, @rejected);
	log::l("ERROR: selection failed: $error");
    }

    \@l, $error;
}

sub selectPackage {
    my ($packages, $pkg, $b_base) = @_;
    my ($pkgs, $_error) = _selectPackage_with_error($packages, $pkg, $b_base);
    @$pkgs;
}

sub _selectPackage_with_error {
    my ($packages, $pkg, $b_base) = @_;

    my $state = $packages->{state} ||= {};

    $packages->{rpmdb} ||= rpmDbOpen();

    my ($pkgs, $error) = _resolve_requested_and_check($packages, $state, _packageRequest($packages, $pkg) || {});

    if ($b_base) {
	$_->set_flag_base foreach @$pkgs;
    }
    ($pkgs, $error);
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
    _resolve_requested_and_check($packages, $packages->{state}, \%keep_selected);
}

sub empty_packages {
    my ($o_keep_unrequested_dependencies) = @_;
    my $packages = urpm->new;
    urpm::get_global_options($packages);
    urpm::set_files($packages, '/mnt');

    #- add additional fields used by DrakX.
    @$packages{qw(count media)} = (0, []);

    $packages->{log} = \&log::l;
    $packages->{info} = \&log::l;
    $packages->{error} = sub { $::o->ask_warn(undef, $_[0]) };
    $packages->{fatal} = sub { $::o->ask_warn(undef, $_[0]) };
    $packages->{root} = $::prefix;
    $packages->{prefer_vendor_list} = '/etc/urpmi/prefer.vendor.list';
    $packages->{keep_unrequested_dependencies} =
      defined($o_keep_unrequested_dependencies) ? $o_keep_unrequested_dependencies : 1;

    $packages;
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

	my ($l, $_error) = _resolve_requested_and_check($packages, $state, _packageRequest($packages, $p) || {});

	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (@$l) {
	    $nb += $_->size;
	}
	if ($max_size && $nb > $max_size) {
	    $nb = $old_nb;
	    $min_level = $p->rate;
	    $packages->disable_selected($packages->{rpmdb}, $state, @$l);
	    last;
	}
    }
    my @flags = map_each { if_($::b, $::a) } %$rpmsrate_flags_chosen;
    log::l("setSelectedFromCompssList: reached size ", int($nb / 1024/1024), "MB, up to indice $min_level (less than ", formatXiB($max_size), ") for flags ", join(' ', sort @flags));
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

sub _inside {
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

sub _or_ify {
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
sub _or_clean {
    my ($flags) = @_;
    my @l = split("\t", $flags);
    @l = map { [ sort split('&&') ] } @l;
    my @r;
  B: while (@l) {
        my $e = shift @l;
        foreach (@r, @l) {
            _inside($_, $e) and next B;
        }
        push @r, $e;
    }
    join("\t", map { join('&&', @$_) } @r);
}


sub computeGroupSize {
    my ($packages, $min_level) = @_;
    my (%group, %memo);

    my %or_ify_cache;
    my $or_ify_cached = sub {
	$or_ify_cache{$_[0]} ||= join("\t", _or_ify(split("\t", $_[0])));
    };

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
		my @deps = map { [ $_, keys %{$packages->{provides}{$_} || {}} ] } $pkg->requires_nosense, $pkg->suggests;
		foreach (sort { @$a <=> @$b } @deps) { #- sort on number of provides (it helps choosing "b" in: "a" requires both "b" and virtual={"b","c"})
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
	    $group{$p->name} = ($memo{$m} ||= _or_clean($m));
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


sub _openInstallLog() {
    my $f = "$::prefix/root/drakx/install.log";
    open(my $LOG, ">> $f") ? log::l("opened $f") : log::l("Failed to open $f. No install log will be kept."); #-#
    CORE::select((CORE::select($LOG), $| = 1)[0]);
    URPM::rpmErrorWriteTo(fileno $LOG);
    $LOG;
}

sub rpmDbOpen {
    my ($b_rebuild_if_needed) = @_;

    clean_rpmdb_shared_regions();

    my $need_rebuild = $b_rebuild_if_needed && !URPM::DB::verify($::prefix);

    if ($need_rebuild) {
	if (my $pid = fork()) {
	    waitpid $pid, 0;
	    $? & 0xff00 and die "rebuilding of rpm database failed";
	} else {
	    log::l("rebuilding rpm database");
	    my $rebuilddb_dir = "$::prefix/var/lib/rpmrebuilddb.$$";
	    if (-d $rebuilddb_dir) {
                log::l("removing stale directory $rebuilddb_dir");
                rm_rf($rebuilddb_dir);
            }

	    if (!URPM::DB::rebuild($::prefix)) {
                log::l("rebuilding of rpm database failed: " . URPM::rpmErrorString());
                c::_exit(2);
            }

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
    _resolve_requested_and_check($packages, $state, \%selection);
    log::l("...done");
    log::l("finally selected pkgs: ", join(" ", sort map { $_->name } grep { $_->flag_selected } @{$packages->{depslist}}));
}

sub _filter_packages {
    my ($retry, $packages, @packages) = @_;
    grep {
        if ($_->flag_installed || packageMedium($packages, $_)->{ignore}) {
            if ($_->name eq 'mdv-rpm-summary' && $_->flag_installed) {
                install::pkgs::setup_rpm_summary_translations();
            }
            $_->free_header;
          0;
        } else {
            log::l("failed to install " . $_->fullname . " (will retry)") if !$retry;
            1;
        }
    } @packages;
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
    my $LOG = _openInstallLog();

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install::steps_gtk.pm,...).
    $callback->($packages, user => undef, install => $nb, $total);

    _install_raw($packages, $isUpgrade, $callback, $LOG, 0);

    log::l("closing install.log file");
    close $LOG;

    clean_rpmdb_shared_regions(); #- workaround librpm which is buggy when using librpm rooted and the just installed rooted library

    fs::loopback::save_boot($loop_boot);
}

sub _install_raw {
    my ($packages, $isUpgrade, $callback, $LOG, $noscripts) = @_;

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



    # let's be urpmi's compatible:
    local $packages->{options}{noscripts} = $noscripts;
    $urpm::args::options{force_transactions} = 1;
    local $packages->{options}{ignoresize} = 1;
    local $packages->{options}{script_fd} = fileno $LOG;
    local $packages->{options}{'priority-upgrade'};  # prevent priority upgrade
    # log $trans->add() faillure; FIXME: should we override *urpm::msg::sys_log?
    local $packages->{error} = \&log::l;
    local $packages->{debug} = \&log::l;

    # FIXME: package signature checking is disabled for now due to URPM always complaining
    local $packages->{options}{'verify-rpm'} = 0;

    my ($retry, $retry_count);

    log::l("rpm transactions start");
    my $fd; #- since we return the "fileno", perl does not know we're still using it, and so closes it, and :-(

    my $exit_code = urpm::main_loop::run($packages, $packages->{state}, undef, undef, undef, {
        open_unused => sub {
				my ($packages, $_type, $id) = @_;
				&$callback;
				my $pkg = defined $id && $packages->{depslist}[$id];
				my $medium = packageMedium($packages, $pkg);
				my $f = $pkg && install::media::rel_rpm_file($medium, $pkg->filename);
				print $LOG "$f\n";
				undef $fd;
				$fd = getFile_($medium->{phys_medium}, $f);
				$fd ? fileno $fd : -1;
        }, close_unused => sub {
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
        }, inst => $callback,
        trans => $callback,
        # FIXME: implement already_installed_or_not_installable
        bad_signature => sub {
            my ($msg, $msg2) = @_;
            $msg =~ s/:$/\n\n/m; # FIXME: to be fixed in urpmi after 2008.0 (sic!)
            $::o->ask_yesorno(N("Warning"), "$msg\n\n$msg2");
        },
        ask_retry => sub {
        },
        copy_removable => sub {
            my ($medium) = @_;
            $::o->ask_change_cd($medium);
        },
        trans_error_summary => sub {
            my ($nok, $errors) = @_;
            log::l($nok . " installation transactions failed");
            die "installation of rpms failed:\n  " . join("\n", @$errors);
        },
        message => sub {
            my ($title, $message) = @_;
            $o->in and $o->in->ask_warn($title, $message);
        },
        ask_yes_or_no => sub {
            my ($title, $msg) = @_;
            $o->in and $o->in->ask_yesorno($title, $msg);
        },
        # Uneeded callbacks: success_summary
    });
          
    log::l("transactions done, now trying to close still opened fd");
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

    my @was_installed = _remove_pkgs_to_upgrade($packages, $callback, $extension);

    {
	my @restore_files = qw(/etc/passwd /etc/group /etc/ld.so.conf);
	foreach (@restore_files) {
	    rename "$::prefix$_.rpmsave", "$::prefix$_";
	}
	fs::any::create_minimal_files();
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

sub _remove_pkgs_to_upgrade {
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

    _remove(\@to_remove, $callback, noscripts => 1);

    @was_installed;
}

sub remove_marked_ask_remove {
    my ($packages, $callback) = @_;

    my @to_remove = keys %{$packages->{state}{ask_remove}} or return;
    
    delete $packages->{rpmdb}; #- make sure rpmdb is closed before.

    #- we are not checking depends since it should come when
    #- upgrading a system. although we may remove some functionalities ?

    _remove(\@to_remove, $callback, force => 1);

    delete $packages->{state}{ask_remove}{$_} foreach @to_remove;
}

sub _remove_raw {
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
sub _remove {
    my ($_to_remove, $_callback, %run_transaction_options) = @_;

    my @pbs = &_remove_raw;
    if (@pbs && !$run_transaction_options{noscripts}) {
	$run_transaction_options{noscripts} = 1;
	@pbs = &_remove_raw;
    }
    if (@pbs) {
	die "removing of old rpms failed:\n  ", join("\n  ", @pbs);
    }
}

sub setup_rpm_summary_translations() {
    my @domains = qw(rpm-summary-contrib rpm-summary-devel rpm-summary-main);
    push @::textdomains, @domains;
    foreach (@domains) {
	Locale::gettext::bind_textdomain_codeset($_, 'UTF-8');
	Locale::gettext::bindtextdomain($_, "$::prefix/usr/share/locale");
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

1;
