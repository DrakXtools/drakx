package do_pkgs; # $Id$

sub do_pkgs {
    my ($in) = @_;
    ($::isInstall ? 'do_pkgs_during_install' : 'do_pkgs_standalone')->new($in);
}

################################################################################
package do_pkgs_common;
use common;

sub new {
    my ($type, $in) = @_;
    bless { in => $in }, $type;
}

sub ensure_is_installed {
    my ($do, $pkg, $o_file, $b_auto) = @_;

    if (! $o_file || ! -e "$::prefix$o_file") {
	$do->{in}->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$b_auto;
	$do->install($pkg) or return;
    }
    if ($o_file && ! -e "$::prefix$o_file") {
	$do->{in}->ask_warn('', N("Mandatory package %s is missing", $pkg));
	return;
    }
    1;
}

sub ensure_is_installed_if_availlable {
    my ($do, $pkg, $file) = @_;
    if (! -e "$::prefix$file" && !$::testing) {
        $do->{in}->do_pkgs->what_provides($pkg) and $do->{in}->do_pkgs->install($pkg);
    }
}
    
sub is_installed {
    my ($do, $name) = @_;
    $do->are_installed($name);
}

################################################################################
package do_pkgs_during_install;
use run_program;
use common;

our @ISA = qw(do_pkgs_common);

sub new {
    my ($type, $in) = @_;
    require pkgs;
    bless { in => $in, o => $::o }, $type;
}

sub install {
    my ($do, @l) = @_;
    log::l("do_pkgs_during_install::install");
    if ($::testing) {
	log::l("i would install packages " . join(' ', @l));
	return 1;
    } else {
	$do->{o}->pkg_install(@l);
    }
}

sub check_kernel_module_packages {
    my ($do, $base_name, $o_ext_name) = @_;

    if (!$o_ext_name || pkgs::packageByName($do->{o}{packages}, $o_ext_name)) {
	my @rpms = map {
	    my $name = $base_name . $_->{ext} . '-' . $_->{version};
	    if ($_->{pkg}->flag_available && pkgs::packageByName($do->{o}{packages}, $name)) {
		log::l("found kernel module packages $name");
		$name;
	    } else {
		();
	    }
	} pkgs::packages2kernels($do->{o}{packages});

	@rpms and return [ @rpms, if_($o_ext_name, $o_ext_name) ];
    }
    return undef;
}

sub what_provides {
    my ($do, $name) = @_;
    map { $do->{o}{packages}{depslist}[$_]->name } keys %{$do->{o}{packages}{provides}{$name} || {}};
}

sub are_installed {
    my ($do, @l) = @_;
    grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	$p && $p->flag_available;
    } @l;
}

sub remove {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	pkgs::unselectPackage($do->{o}{packages}, $p) if $p;
	$p;
    } @l;
    run_program::rooted($::prefix, 'rpm', '-e', @l);
}

sub remove_nodeps {
    my ($do, @l) = @_;

    @l = grep {
	my $p = pkgs::packageByName($do->{o}{packages}, $_);
	if ($p) {
	    $p->set_flag_requested(0);
	    $p->set_flag_required(0);
	}
	$p;
    } @l;
    run_program::rooted($::prefix, 'rpm', '-e', '--nodeps', @l);
}

################################################################################
package do_pkgs_standalone;
use run_program;
use common;
use log;

our @ISA = qw(do_pkgs_common);

sub install {
    my ($do, @l) = @_;

    return 1 if listlength(are_installed($do, @l)) == @l;

    if ($::testing) {
	log::l("i would install packages " . join(' ', @l));
	return 1;
    }

    my $_wait = $do->{in}->wait_message('', N("Installing packages..."));
    $do->{in}->suspend;
    log::explanations("installed packages @l");
    my $ret = system('urpmi', '--allow-medium-change', '--auto', '--best-output', '--no-verify-rpm', @l) == 0;
    $do->{in}->resume;
    $ret;
}

sub check_kernel_module_packages {
    my ($_do, $base_name, $o_ext_name) = @_;
    my ($result, %list, %select);
    my @rpm_qa if 0;

    #- initialize only once from rpm -qa output...
    @rpm_qa or @rpm_qa = `rpm -qa`;

    eval {
	local *_;
	require urpm;
	my $urpm = urpm->new;
	$urpm->read_config(nocheck_access => 1);
	foreach (grep { !$_->{ignore} } @{$urpm->{media} || []}) {
	    $urpm->parse_synthesis("$urpm->{statedir}/synthesis.$_->{hdlist}");
	}
	foreach (@{$urpm->{depslist} || []}) {
	    $_->name eq $o_ext_name and $list{$_->name} = 1;
	    $_->name =~ /$base_name/ and $list{$_->name} = 1;
	}
	foreach (@rpm_qa) {
	    my ($name) = /(.*?)-[^-]*-[^-]*$/ or next;
	    $name eq $o_ext_name and $list{$name} = 0;
	    $name =~ /$base_name/ and $list{$name} = 0;
	}
    };
    if (!$o_ext_name || exists $list{$o_ext_name}) {
	eval {
	    my ($version_release, $ext);
	    if (c::kernel_version() =~ /([^-]*)-([^-]*mdk)(\S*)/) {
		$version_release = "$1.$2";
		$ext = $3 ? "-$3" : "";
		exists $list{"$base_name$ext-$version_release"} or die "no $base_name for current kernel";
		$list{"$base_name$ext-$version_release"} and $select{"$base_name$ext-$version_release"} = 1;
	    } else {
		#- kernel version is not recognized, what to do ?
	    }
	    foreach (@rpm_qa) {
		($ext, $version_release) = /kernel[^\-]*(-smp|-enterprise|-secure)?(?:-([^\-]+))$/;
		$list{"$base_name$ext-$version_release"} and $select{"$base_name$ext-$version_release"} = 1;
	    }
	    $result = [ keys(%select), if_($o_ext_name, $o_ext_name) ];
	}
    }
    return $result;
}

sub what_provides {
    my ($_do, $name) = @_;
    split('\|', chomp_(run_program::get_stdout('urpmq', $name)));
}

sub is_installed {
    my ($do, $name) = @_;
    are_installed($do, $name);
}

sub are_installed {
    my ($_do, @l) = @_;
    my @l2;
    run_program::run('/bin/rpm', '>', \@l2, '-q', '--qf', "%{name}\n", @l); #- don't care about the return value
    intersection(\@l, [ chomp_(@l2) ]); #- can't return directly @l2 since it contains things like "package xxx is not installed"
}

sub remove {
    my ($do, @l) = @_;
    my $_wait = $do->{in}->wait_message('', N("Removing packages..."));
    $do->{in}->suspend;
    log::explanations("removed packages @l");
    my $ret = system('rpm', '-e', @l) == 0;
    $do->{in}->resume;
    $ret;
}

sub remove_nodeps {
    my ($do, @l) = @_;
    remove($do, '--nodeps', @l) == 0;
}
