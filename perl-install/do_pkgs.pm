package do_pkgs; # $Id$

sub do_pkgs {
    my ($in) = @_;
    ($::isInstall ? 'do_pkgs_during_install' : 'do_pkgs_standalone')->new($in);
}

################################################################################
package do_pkgs_common;
use common;

sub ensure_is_installed {
    my ($do, $pkg, $o_file, $b_auto) = @_;

    if ($o_file ? -e "$::prefix$o_file" : $do->is_installed($pkg)) {
	return 1;
    }

	$do->in->ask_okcancel(N("Warning"), N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$b_auto && $do->in;

	if (!$do->install($pkg)) {
	    $do->in->ask_warn(N("Error"), N("Could not install the %s package!", $pkg)) if $do->in;
	    return;
	}

    if ($o_file && ! -e "$::prefix$o_file") {
	$do->in->ask_warn(N("Error"), N("Mandatory package %s is missing", $pkg)) if $do->in;
	return;
    }
    1;
}

sub ensure_are_installed {
    my ($do, $pkgs, $b_auto) = @_;

    my @not_installed = difference2($pkgs, [ $do->are_installed(@$pkgs) ]) or return 1;

    $do->in->ask_okcancel(N("Warning"), N("The following packages need to be installed:\n") . join(', ', @not_installed), 1)
	  or return if !$b_auto && $do->in;

    if (!$do->install(@not_installed)) {
	if ($do->in) {
	    $do->in->ask_warn(N("Error"), N("Could not install the %s package!", $not_installed[0]));
	} else {
	    log::l("Could not install packages: " . join(' ', @not_installed));
	}
	return;
    }
    1;
}

sub ensure_binary_is_installed {
    my ($do, $pkg, $binary, $b_auto) = @_;

    if (!whereis_binary($binary, $::prefix)) {
	$do->in->ask_okcancel(N("Warning"), N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$b_auto && $do->in;
	if (!$do->install($pkg)) {
            $do->in->ask_warn(N("Error"), N("Could not install the %s package!", $pkg)) if $do->in;
	    return;
	}
    }
    if (!whereis_binary($binary, $::prefix)) {
        $do->in->ask_warn(N("Error"), N("Mandatory package %s is missing", $pkg)) if $do->in;
	return;
    }
    1;
}

sub ensure_is_installed_if_available {
    my ($do, $pkg, $file) = @_;
    if (-e "$::prefix$file" || $::testing) {
	1;
    } else {
        $do->what_provides($pkg) && $do->install($pkg);
    }
}

sub is_available {
    my ($do, $name) = @_;
    $do->are_available($name);
}

sub is_installed {
    my ($do, $name) = @_;
    $do->are_installed($name);
}

#- takes something like "ati-kernel"
#- returns:
#- - the various ati-kernel-2.6.XX-XXmdk available for the installed kernels
#- - dkms-ati if available
sub check_kernel_module_packages {
    my ($do, $base_name) = @_;
    
    require bootloader;
    my @test_rpms = (
	'dkms-' . $base_name,
	map { $base_name . '-kernel-' . bootloader::vmlinuz2version($_) } bootloader::installed_vmlinuz()
    );
    @rpms = $do->are_available(@test_rpms);
    @rpms = $do->are_installed(@test_rpms) if !@rpms;
    @rpms or return;

    log::l("those kernel module packages can be installed: " . join(' ', @rpms));

    \@rpms;
}

################################################################################
package do_pkgs_during_install;
use run_program;
use common;

our @ISA = qw(do_pkgs_common);

sub new {
    my ($type, $in) = @_;

    $in->isa('interactive') or undef $in;

    require install::pkgs;
    bless { in => $in, o => $::o }, $type;
}

sub in {
    my ($do) = @_;
    $do->{in};
}

sub install {
    my ($do, @l) = @_;
    log::l("do_pkgs_during_install::install");
    if ($::testing) {
	log::l("i would install packages " . join(' ', @l));
	1;
    } else {
	$do->{o}->pkg_install(@l);
	1; #- HACK, need better fix in install::steps::pkg_install()
    }
}

sub what_provides {
    my ($do, $name) = @_;
    map { $_->name } install::pkgs::packagesProviding($do->{o}{packages}, $name);
}

sub are_available {
    my ($do, @pkgs) = @_;
    grep { install::pkgs::packageByName($do->{o}{packages}, $_) } @pkgs;
}

sub are_installed {
    my ($do, @l) = @_;
    grep {
	my $p = install::pkgs::packageByName($do->{o}{packages}, $_);
	$p && $p->flag_available;
    } @l;
}

sub remove {
    my ($do, @l) = @_;

    @l = grep {
	my $p = install::pkgs::packageByName($do->{o}{packages}, $_);
	install::pkgs::unselectPackage($do->{o}{packages}, $p) if $p;
	$p;
    } @l;
    run_program::rooted($::prefix, 'rpm', '-e', @l);
}

sub remove_nodeps {
    my ($do, @l) = @_;

    @l = grep {
	my $p = install::pkgs::packageByName($do->{o}{packages}, $_);
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

sub new {
    my ($type, $o_in) = @_;
    bless { in => $o_in }, $type;
}

sub in {
    my ($do) = @_;
    $do->{in};
}

sub install {
    my ($do, @l) = @_;

    return 1 if listlength(are_installed($do, @l)) == @l;

    if ($::testing) {
	log::l("i would install packages " . join(' ', @l));
	return 1;
    }

    my @options = ('--allow-medium-change', '--auto', '--no-verify-rpm', '--expect-install', @l);
    my $ret;
    if (check_for_xserver() && -x '/usr/bin/gurpmi') {
        $ret = system('gurpmi', @options) == 0;
    } else {
        my $_wait = $do->in && $do->in->wait_message(N("Please wait"), N("Installing packages..."));
        $do->in->suspend if $do->in;
        log::explanations("installing packages @l");
        #- --expect-install added in urpmi 4.6.11
        $ret = system('urpmi', '--gui', @options) == 0;
        $do->in->resume if $do->in;
    }
    $ret;
}

sub are_available {
    my ($_do, @pkgs) = @_;
    my %pkgs = map { $_ => 1 } @pkgs;

    eval {
	require urpm::media;
	my $urpm = urpm->new;
	$urpm->{log} = \&log::l;
	urpm::media::configure($urpm, 
			       nocheck_access => 1,
			       no_skiplist => 1,
			       no_second_pass => 1);
	map { $_->name } grep { $pkgs{$_->name} } @{$urpm->{depslist} || []};
    };
}

sub what_provides {
    my ($_do, $name) = @_;
    split('\|', chomp_(run_program::get_stdout('urpmq', $name)));
}

sub are_installed {
    my ($_do, @l) = @_;
    @l or return;

    my @l2;
    run_program::run('/bin/rpm', '>', \@l2, '-q', '--qf', "%{name}\n", @l); #- do not care about the return value
    intersection(\@l, [ chomp_(@l2) ]); #- can not return directly @l2 since it contains things like "package xxx is not installed"
}

sub remove {
    my ($do, @l) = @_;
    my $_wait = $do->in && $do->in->wait_message(N("Please wait"), N("Removing packages..."));
    $do->in->suspend if $do->in;
    log::explanations("removing packages @l");
    my $ret = system('rpm', '-e', @l) == 0;
    $do->in->resume if $do->in;
    $ret;
}

sub remove_nodeps {
    my ($do, @l) = @_;
    remove($do, '--nodeps', @l) == 0;
}
