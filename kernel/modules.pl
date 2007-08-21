use strict;


BEGIN {
    #- for testing purpose
    (my $f = __FILE__) =~ s|/[^/]*$||;
    push @INC, $f;
}

use MDK::Common;
use list_modules;


sub flatten_and_check {
    my ($h) = @_;
    map { 
	my $category = $_;
	my @l = @{$h->{$category}};
	if (my @bad = difference2(\@l, [ list_modules::category2modules_raw($category) ])) {
	    foreach (@bad) {
		if (my $cat = module2category($_)) {
		    warn "ERROR in modules.pl: module $_ is in category $cat, not in $category\n";
		} else {
		    warn "ERROR in modules.pl: unknown module $_\n";
		}
	    }
	    exit 1;
	}
	@l;
    } keys %$h;
}

my $images_cat = 'fs/* disk/* bus/* network/* input/* various/*'; #- ie everything except multimedia

my $verbose = $ARGV[0] eq '-v' && shift;
my ($f, @para) = @ARGV;
$::{$f}->(@para);

sub modules() {
    map { category2modules($_) } split(' ', $images_cat);
}

sub remove_unneeded_modules {
    my ($kern_ver) = @_;

    #- need creating a first time the modules.dep for all modules
    filter_modules_dep($kern_ver);
    load_dependencies("all.kernels/$kern_ver/modules.dep");

    my @all = modules();
    my @all_with_deps = map { dependencies_closure($_) } @all;
    my %wanted_modules = map { (list_modules::modname2filename($_) . ".ko.gz" => 1) } @all_with_deps;
    foreach (all("all.kernels/$kern_ver/modules")) {
	$wanted_modules{$_} or unlink "all.kernels/$kern_ver/modules/$_";	
    }
}

sub make_modules_per_image {
    my ($kern_ver) = @_;

    my $dir = "all.kernels/$kern_ver/modules";

    system("cd $dir ; tar cf ../all_modules.tar *.ko.gz") == 0 or die "tar failed\n";
}

sub filter_modules_dep {
    my ($kern_ver) = @_;

    my @l = cat_("all.kernels/$kern_ver/modules.dep");

    @l = map {
	    my ($f, $d) = split ':';
	    my ($module, @deps) = map { m!.*/(.*)\.k?o(\.gz)$! && $1 } $f, split(' ', $d);
	    if (member($module, 'plip', 'ppa', 'imm')) {
		@deps = map { $_ eq 'parport' ? 'parport_pc' : $_ } @deps;
	    } elsif ($module eq 'vfat') {
		push @deps, 'nls_cp437', 'nls_iso8859-1';
	    }
	    join(' ', "$module:", @deps);
    } @l;

    output("all.kernels/$kern_ver/modules.dep", map { "$_\n" } @l);
}

sub get_main_modules() {
    my $base = dirname($0);
    my $main = chomp_(cat_("$base/RPMS/.main"));
    chomp_(`tar tf $base/all.kernels/$main/all_modules.tar`);
}

sub pci_modules4stage1 {
    my ($category) = @_;
    my @modules = difference2([ category2modules($category) ]);
    print "$_\n" foreach uniq(map { dependencies_closure($_) } @modules);
}

sub check() {
    my $error;
    my %listed;
    while (my ($t1, $l) = each %list_modules::l) {
	while (my ($t2, $l) = each %$l) {
	    ref $l or die "bad $l in $t1/$t2";
	    foreach (@$l) {
		$listed{$_} = "$t1/$t2"; 
	    }
	}
    }

    my %module2category;
    my %deprecated_modules = %listed;
    my $not_listed = sub {
	my ($msg, $verbose, @l) = @_;
	my %not_listed;
	foreach (@l) {
	    my ($mod) = m|([^/]*)\.k?o(\.gz)?$| or next;
	    delete $deprecated_modules{$mod};
	    next if $listed{$mod};
	    s|.*?mdk/||;
	    s|kernel/||; s|drivers/||; s|3rdparty/||;
	    $_ = dirname $_;
	    $_ = dirname $_ if $mod eq basename($_);
	    $module2category{$mod} = $_;
	    push @{$not_listed{$_}}, $mod;
	}
	if ($verbose) {
	    print "$msg $_: ", join(" ", @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	}
    };
    $not_listed->('NOT LISTED', 1, get_main_modules());
    $not_listed->('not listed', $verbose, chomp_(`rpm -qpl RPMS/kernel-*2.6*`));
    if (%deprecated_modules) {
	my %per_cat;
	push @{$per_cat{$listed{$_}}}, $_ foreach keys %deprecated_modules;
	foreach my $cat (sort keys %per_cat) {
	    print "bad/old modules ($cat) : ", join(" ", sort @{$per_cat{$cat}}), "\n";
	}
    }

    {
	require '/usr/bin/merge2pcitable.pl';
	my $pcitable = read_pcitable("/usr/share/ldetect-lst/pcitable");
	my $usbtable = read_pcitable("/usr/share/ldetect-lst/usbtable");

	my @l1 = uniq grep { !/:/ && $_ ne 'unknown' } map { $_->[0] } values %$pcitable;
	if (my @l = difference2(\@l1, [ keys %listed ])) {
	    my %not_listed;
	    push @{$not_listed{$module2category{$_}}}, $_ foreach @l;
	    if (my $l = delete $not_listed{''}) {
		print "bad/old pcitable modules : ", join(" ", @$l), "\n";
	    }
	    print STDERR "PCITABLE MODULES NOT LISTED $_: ", join(" ", sort @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	    #$error = 1;
	}

	my @l2 = uniq grep { !/:/ && $_ ne 'unknown' } map { $_->[0] } values %$usbtable;
	if (my @l = difference2(\@l2, [ keys %listed ])) {
	    my %not_listed;
	    push @{$not_listed{$module2category{$_}}}, $_ foreach @l;
	    print STDERR "usbtable modules not listed $_: ", join(" ", sort @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	}
    }

    exit $error;
}
