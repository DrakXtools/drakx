package install::pkgs;

use strict;
use feature 'state';

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

# Based on Rpmdrake::pkg::extract_header():
sub get_pkg_info {
    my ($p) = @_;

    my $urpm = $::o->{packages};
    my $name = $p->fullname;

    my $medium = URPM::pkg2media($urpm->{media}, $p);
    my ($local_source, %xml_info_pkgs, $description);
    my $dir = urpm::file_from_local_url($medium->{url});
    $local_source = "$dir/" . $p->filename if $dir;

    if (-s $local_source) {
	log::l("getting information from $dir...");
	$p->update_header($local_source) and $description = $p->description;
	log::l("Warning, could not extract header for $name from $medium!") if !$description;
    }
    if (!$description) {
	my $_w = $::o->wait_message(undef, N("Getting package information from XML meta-data..."));
	if (my $xml_info_file = eval { urpm::media::any_xml_info($urpm, $medium, 'info', undef, urpm::download::sync_logger) }) {
	    require urpm::xml_info;
	    require urpm::xml_info_pkg;
	    log::l("getting information from $xml_info_file");
	    my %nodes = eval { urpm::xml_info::get_nodes('info', $xml_info_file, [ $name ]) };
	    goto header_non_available if $@;
	    put_in_hash($xml_info_pkgs{$name} ||= {}, $nodes{$name});
	} else {
	    $urpm->{info}(N("No xml info for medium \"%s\", only partial result for package %s", $medium->{name}, $name));
	}
    }

    if (!$description && $xml_info_pkgs{$name}) {
	$description = $xml_info_pkgs{$name}{description};
    }
  header_non_available:
    $description || N("No description");
}

sub packagesProviding {
    my ($packages, $name) = @_;
    grep { $_->is_arch_compat } URPM::packages_providing($packages, $name);
}

#- search package with given name and compatible with current architecture.
#- take the best one found (most up-to-date).
# FIXME: reuse urpmi higher level code instead!
sub packageByName {
    my ($packages, $name) = @_;

    my @l =  sort { $b->id <=> $a->id } grep { $_->name eq $name } packagesProviding($packages, $name);

    my $best;
    foreach (@l) {
	if ($best && $best != $_) {
	    if ($best->fullname eq $_->fullname) {
		$best = $_ if $_->flag_installed;
	    } else {
	        $_->compare_pkg($best) > 0 and $best = $_;
            }
	} else {
	    $best = $_;
	}
    }
    $best or log::l("unknown package `$name'");
    $best;
}

sub _bestKernel_extensions {
    my ($o_match_all_hardware) = @_;

    $::o->{kernel_extension} ? $::o->{kernel_extension} :
    $o_match_all_hardware ? (arch() =~ /i.86/ ? '-desktop586' : '-desktop') :
      detect_devices::is_i586() ? '-desktop586' :
      arch() != /i.86/ && detect_devices::isServer() ? '-server' : '-desktop';
}

sub bestKernelPackage {
    my ($packages, $o_match_all_hardware) = @_;

    my @preferred_exts = _bestKernel_extensions($o_match_all_hardware);
    my @kernels = grep { $_ } map { packageByName($packages, "kernel$_-latest") } @preferred_exts;

    if (!@kernels) {
        #- fallback on most generic kernel if the suitable one is not available
        #- (only kernel-desktop586-latest is available on Dual ISO for i586)
        my @fallback_exts = _bestKernel_extensions('force');
        @kernels = grep { $_ } map { packageByName($packages, "kernel$_-latest") } @fallback_exts;
    }

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
    log::l("found " . scalar(@packages) . " packages to install: " . formatList(5, map { scalar $_->fullname } @packages));

    @packages;
}

sub _packageRequest {
    my ($packages, $pkg) = @_;

    #- check if the same or better version is installed,
    #- do not select in such case.
    $pkg && ($pkg->flag_upgrade || !$pkg->flag_installed) or return;

    #- check for medium selection, if the medium has not been
    #- selected, the package cannot be selected.
    my $medium = packageMedium($packages, $pkg);
    $medium && !$medium->{ignore} or return;

    +{ $pkg->id => 1 };
}

sub packageCallbackChoices {
    my ($urpm, $_db, $_state, $choices, $virtual_pkg_name, $prefered) = @_;
  
    if ($prefered && @$prefered) {
	@$prefered;
    } elsif (my @l = _packageCallbackChoices_($urpm, $choices, $virtual_pkg_name)) {
	@l;
    } else {
	log::l("packageCallbackChoices: default choice ('" . $choices->[0]->name . "') from " . join(",", map { $_->name } @$choices) . " for $virtual_pkg_name");
	$choices->[0];
    }
}

sub _packageCallbackChoices_ {
    my ($urpm, $choices, $virtual_pkg_name) = @_;

    my ($prefer, $_other) = urpm::select::get_preferred($urpm, $choices, $::o->{preferred_packages});
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

my @suggested_package_ids;
sub _resolve_requested_and_check {
    my ($packages, $state, $requested) = @_;

    my @l = $packages->resolve_requested($packages->{rpmdb}, $state, $requested,
					 callback_choices => \&packageCallbackChoices, no_suggests => $::o->{no_suggests});

    #- keep track of suggested packages so that theys could be unselected if the "no suggests" option is choosen later:
    if (!is_empty_hash_ref($state->{selected})) {
        my @new_ids = map { $packages->{depslist}[$_]->id } grep { $state->{selected}{$_}{suggested} } keys %{$state->{selected}};
        @recommended_package_ids = uniq(@recommended_package_ids, @new_ids);
    }

    my $error;
    if (find { !exists $state->{selected}{$_} } keys %$requested) {
	my @rejected = urpm::select::unselected_packages($state);
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
	my $to_select = $_->flag_base || $_->flag_installed && $_->flag_selected;
	# unselect suggested packages if minimal install:
	if ($::o->{no_suggests} && member($_->id, @suggested_package_ids)) {
	    log::l("unselecting suggested package " . $_->name);
	    undef $to_select;
	}
	if ($to_select) {
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


my (@errors, $push_errors);
sub start_pushing_error() {
    $push_errors = 1;
    undef @errors;
}

sub popup_errors() {
    if (@errors) {
	$::o->ask_warn(undef, N("An error occurred:") . "\n\n" . join("\n", @errors));
    }
    undef $push_errors;
}

sub empty_packages {
    my ($o_keep_unrequested_dependencies) = @_;
    my $packages = urpm->new;
    urpm::get_global_options($packages);
    urpm::set_files($packages, '/mnt');

    #- add additional fields used by DrakX.
    $packages->{media} = [];

    urpm::args::set_debug($packages) if $::o->{debug_urpmi};
    $packages->{log} = \&log::l;
    $packages->{info} = \&log::l;
    $packages->{fatal} = sub {
        log::l("urpmi error: $_[1] ($_[0])\n" . common::backtrace());
        $::o->ask_warn(undef, N("A fatal error occurred: %s.", "$_[1] ($_[0])"));
    };
    $packages->{error} = sub {
        log::l("urpmi error: $_[0]");
	if ($push_errors) {
	    push @errors, @_;
	    return;
	}
        $::o->ask_warn(undef, N("An error occurred:") . "\n\n" . $_[0]);
    };
    $packages->{root} = $::prefix;
    $packages->{prefer_vendor_list} = '/etc/urpmi/prefer.vendor.list';
    $packages->{keep_unrequested_dependencies} =
      defined($o_keep_unrequested_dependencies) ? $o_keep_unrequested_dependencies : 1;
    $urpm::args::options{force_transactions} = 20;
    $urpm::args::options{justdb} = $::o->{justdb};
    urpm::set_tune_rpm($packages, $::o->{'tune-rpm'}) if $::o->{'tune-rpm'};
    $::force = 1;
    $packages->{options}{ignoresize} = 1;
    # prevent priority upgrade (redundant for now as $urpm->{root} implies disabling it:
    $packages->{options}{'priority-upgrade'} = undef;
    # log $trans->add() faillure; FIXME: should we override *urpm::msg::sys_log?
    $packages->{debug} = $packages->{debug_URPM} = \&log::l;
    $packages->{options}{'curl-options'} = $::o->{curl_options} if $::o->{curl_options};

    $packages;
}

sub readCompssUsers {
    my ($file) = @_;

    my $f = common::open_file($file) or log::l("cannot find $file: $!"), return;
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

    my %pkgs;
    foreach my $p (@{$packages->{depslist}}) {
	my @flags = $p->rflags;
	next if
	  !$p->rate || $p->rate < $min_level || 
	  any { !any { /^!(.*)/ ? !$rpmsrate_flags_chosen->{$1} : $rpmsrate_flags_chosen->{$_} } split('\|\|') } @flags;	
	$pkgs{$p->rate} ||= {};
	$pkgs{$p->rate}{$p->id} = 1 if _packageRequest($packages, $p);
    }
    my %pkgswanted;
    foreach my $level (sort { $b <=> $a } keys %pkgs) {
	#- determine the packages that will be selected
	#- the packages are not selected.
	my $state = $packages->{state} ||= {};
	foreach my $p (keys %{$pkgs{$level}}) {
	    $pkgswanted{$p} = 1;
	}
	my ($l, $_error) = _resolve_requested_and_check($packages, $state, \%pkgswanted);
    
	#- this enable an incremental total size.
	my $old_nb = $nb;
	foreach (@$l) {
	    $nb += $_->size;
	}
	if ($max_size && $nb > $max_size) {
	    log::l("disabling selected packages because too big for level $level: $nb > $max_size");
	    $nb = $old_nb;
	    $min_level = $level;
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
    my @l = @{$packages->{depslist} || []};
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
			    @choices = map { $_->id } packageCallbackChoices($packages, undef, undef, \@choices_pkgs, $virtual, undef);
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

sub _rebuild_RPM_DB() {
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

sub rpmDbOpen {
    my ($b_rebuild_if_needed) = @_;

    my $need_rebuild = $b_rebuild_if_needed && !URPM::DB::verify($::prefix);

    _rebuild_RPM_DB() if $need_rebuild;

    my $db;
    if ($db = URPM::DB::open($::prefix)) {
	log::l("opened rpm database for examining existing packages");
    } else {
	log::l("unable to open rpm database, using empty rpm db emulation");
	$db = new URPM;
    }

    $db;
}

sub open_rpm_db_rw() {
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

    return if !@$toInstall;

    #- for root loopback'ed /boot
    my $loop_boot = fs::loopback::prepare_boot();

    #- first stage to extract some important information
    #- about the selected packages.
    my ($total, $nb);
    foreach my $pkg (@$toInstall) {
	$packages{$pkg->id} = $pkg;
	$nb++;
	$total += to_int($pkg->size); #- do not correct for upgrade!
    }

    log::l("install::pkgs::install $::prefix");
    log::l("install::pkgs::install the following: ", join(" ", map { $_->name } values %packages));

    URPM::read_config_files();
    # force loading libnss*
    getgrent();
    URPM::add_macro('__nofsync 1');
    my $LOG = _openInstallLog();

    $packages->{log} = $packages->{info} = $packages->{print} = sub {
        print $LOG "$_[0]\n";
    };

    #- do not modify/translate the message used with installCallback since
    #- these are keys during progressing installation, or change in other
    #- place (install::steps_gtk.pm,...).
    $callback->($packages, user => undef, install => $nb, $total);

    my $exit_code = _install_raw($packages, $isUpgrade, $callback, $LOG, 0);

    log::l("closing install.log file");
    close $LOG;

    # prevent urpmi from trying to install them again (CHECKME: maybe uneeded):
    $packages->{state} = {};

    fs::loopback::save_boot($loop_boot);

    $exit_code;
}

sub _unselect_package {
    my ($packages, $pkg) = @_;
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
}

sub is_package_installed {
    my ($db, $pkg) = @_;
    my $check_installed;
    $db->traverse_tag('name', [ $pkg->name ], sub {
                          my ($p) = @_;
                          $check_installed ||= $pkg->compare_pkg($p) == 0;
                      });
    return $check_installed;
}

sub _install_raw {
    my ($packages, $_isUpgrade, $callback, $LOG, $noscripts) = @_;

    # prevent warnings in install's logs:
    local $ENV{LC_ALL} = 'C';

    # let's be urpmi's compatible:
    local $packages->{options}{noscripts} = $noscripts;
    # leaks a fd per transaction (around ~100 for a typically gnome install, see #49097):
    # bug present in 2009.0, 2008.1, 2008.0, ... (probably since r11141 aka when switching to rpm-4.2 in URPM-0.83)
    local $packages->{options}{script_fd} = fileno $LOG;

    start_pushing_error();

    log::l("rpm transactions start");

    my $exit_code = urpm::main_loop::run($packages, $packages->{state}, undef, undef, {
        open_helper => $callback,
        close_helper => sub {
				my ($db, $packages, $_type, $id) = @_;
				&$callback;
				my $pkg = defined $id && $packages->{depslist}[$id] or return;
				print $LOG $pkg->fullname . "\n";
				my $check_installed = is_package_installed($db, $pkg);
                                if ($pkg->name eq 'mdv-rpm-summary' && $check_installed) {
                                    install::pkgs::setup_rpm_summary_translations();
                                }

				if ($check_installed) {
                                    _unselect_package($packages, $pkg);
                                } else {
                                    log::l($pkg->name . " not installed, " . URPM::rpmErrorString());
                                }
        }, inst => $callback,
        trans => $callback,
        # FIXME: implement already_installed_or_not_installable
        bad_signature => sub {
            my ($msg, $msg2) = @_;
            $msg =~ s/:$/\n\n/m; # FIXME: to be fixed in urpmi after 2008.0 (sic!)
            log::l($msg);
            log::l($msg2);
            return 0 if $packages->{options}{auto};
            state $do_not_ask;
            state $answer;
            return $answer if $do_not_ask;
            $answer = $::o->ask_from_({ messages => "$msg\n\n$msg2" }, [ 
                { val => \$do_not_ask,
                  type => 'bool', text => N("Do not ask again"),
              },
            ]);
        },
        copy_removable => sub {
            my ($medium) = @_;
            $::o->ask_change_cd($medium);
        },
        is_canceled => sub {
            return $install::pkgs::cancel_install;
        },
        trans_error_summary => sub {
            my ($nok, $errors) = @_;
            log::l($nok . " installation transactions failed");
            log::l(join("\n", @$errors));
            if (!$packages->{options}{auto}) {
                $::o->ask_warn(N("Error"), N("%d installation transactions failed", $nok) . "\n\n" .
                                 N("Installation of packages failed:") . "\n\n" . join("\n", @$errors));
            }
        },
        completed => sub {
            if (!$packages->{options}{auto}) {
                popup_errors();
            }
        },
        message => sub {
            my ($title, $message) = @_;
            log::l($message);
            $::o->ask_warn($title, $message);
        },
        ask_yes_or_no => sub {
            my ($title, $msg) = @_;
            log::l($msg);
            $::o->ask_yesorno($title, $msg);
        },
        ask_for_bad_or_missing => sub {
            my ($_title, $msg) = @_;
            log::l($msg);
            state $do_not_ask;
            state $answer;
            return $answer if $do_not_ask;
            $answer = $::o->ask_from_({ messages => $msg }, [
                { val => \$do_not_ask, type => 'bool', text => N("Do not ask again"),
              },
            ]);
        },
        # Uneeded callbacks: success_summary
    });
          
    log::l("transactions done, now trying to close still opened fd; exit code=$exit_code");
 
    $exit_code;
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
    URPM::add_macro('__nofsync 1');

    my $db = open_rpm_db_rw() or die "error opening RPM database: ", URPM::rpmErrorString();
    my $trans = $db->create_transaction;

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
