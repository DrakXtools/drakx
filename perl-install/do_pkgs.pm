package do_pkgs;

=head1 SYNOPSYS

B<do_pkgs> enables to install packages (through urpmi) from our tools.
It works both during installer and in standalone tools.


=head1 Functions

=over

=cut

=item do_pkgs($in)

Returns a new B<do_pkgs> object from a L<interactive> object.

=cut

sub do_pkgs {
    my ($in) = @_;
    ($::isInstall ? 'do_pkgs_during_install' : 'do_pkgs_standalone')->new($in);
}

################################################################################
package do_pkgs_common;
use common;

=item ensure_is_installed($do, $pkg, $o_file, $b_auto)

Makes sure that the $pkg package is installed.
If $o_file is provided, the already installed check is I<way> faster.
If $b_auto is set, (g)urpmi will not ask any questions.

=cut

sub ensure_is_installed {
    my ($do, $pkg, $o_file, $b_auto) = @_;

    if ($do->is_installed($pkg)) {
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

=item ensure_are_installed($do, $pkgs, $b_auto)

Makes sure that the packages listed in $pkgs array ref are installed.
If $b_auto is set, (g)urpmi will not ask any questions.

It's quite costly, so it's better to use the B<ensure_files_are_installed> instead.

=cut

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

=item ensure_binary_is_installed($do, $pkg, $binary, $b_auto)

Makes sure that the $pkg package is installed.
$binary is looked for in $PATH. If not found, the package is installed.
If $b_auto is set, (g)urpmi will not ask any questions.

=cut

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

sub _find_file {
    my ($file) = @_;
    if ($file =~ m!/!) {
	-e "$::prefix$file";
    } else {
	# assume it's a binary to search in $PATH:
	whereis_binary($file, $::prefix);
    }
}

=item ensure_files_are_installed($do, $pkgs, $b_auto)

Takes a list of [ "package", "file" ] and installs package if file is not there.
If $b_auto is set, (g)urpmi will not ask any questions.

=cut

sub ensure_files_are_installed {
    my ($do, $pkgs, $b_auto) = @_;

    my @not_installed = map { my ($package, $file) = @$_; if_(!_find_file($file), $package) } @$pkgs;
    return 1 if !@not_installed;

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

=item ensure_is_installed_if_available($do, $pkg, $file) = @_;

Install $pkg if $file is not present and if $pkg is actually known to urpmi.

=cut

sub ensure_is_installed_if_available {
    my ($do, $pkg, $file) = @_;
    if (-e "$::prefix$file" || $::testing) {
	1;
    } else {
        $do->what_provides($pkg) && $do->install($pkg);
    }
}

=item is_available($do, $name)

=item are_available($do, @names)

Returns name(s) of package(s) that are available (aka known to urpmi).
This is somewhat costly (needs to parse urpmi synthesis...)

=cut

sub is_available {
    my ($do, $name) = @_;
    $do->are_available($name);
}

=item is_installed($do, $name)

=item are_installed($do, @names)

Returns name(s) of package(s) that are already installed on the system.
This is less costly (needs to query RPM DB)

=cut

sub is_installed {
    my ($do, $name, $o_file) = @_;
    $o_file ? -e "$::prefix$o_file" : $do->are_installed($name);
}

=item check_kernel_module_packages($do, $base_name)

Takes something like "C<ati-kernel>" and returns:

=over 4

=item * the various C<ati-kernel-3.Y.XX-ZZmga> available for the installed kernels

=item * C<dkms-ati> if available

=back

=cut

sub check_kernel_module_packages {
    my ($do, $base_name) = @_;
    
    require bootloader;
    my @test_rpms = (
	'dkms-' . $base_name,
	map { $base_name . '-kernel-' . bootloader::vmlinuz2version($_) } bootloader::installed_vmlinuz()
    );
    my @rpms = $do->are_available(@test_rpms);
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

=item new($type, $in)

Returns a C<do_pkg> object.

=cut

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
use feature qw(state);

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

    my @wrapper = $::isLiveInstall && $::prefix ? ('chroot', $::prefix) : ();
    my @options = ('--allow-medium-change', '--auto', '--no-verify-rpm', '--expect-install', @l);
    my $ret;
    if (check_for_xserver() && -x '/usr/bin/gurpmi') {
        $ret = system(@wrapper, 'gurpmi', @options) == 0;
    } else {
        my $_wait = $do->in && $do->in->wait_message(N("Please wait"), N("Installing packages..."));
        $do->in->suspend if $do->in;
        log::explanations("installing packages @l");
        $ret = system(@wrapper, 'urpmi', @options) == 0;
        $do->in->resume if $do->in;
    }
    $ret;
}

sub are_available {
    my ($_do, @pkgs) = @_;
    my %pkgs = map { $_ => 1 } @pkgs;

    require urpm::media;
    state $urpm;
    eval {
	if (!$urpm) {
	    $urpm = urpm->new;
	    $urpm->{log} = \&log::l;
	   
            # we dont want urpmi fatal errors to kill us
            local $urpm->{fatal} = $urpm->{error};

	    urpm::media::configure($urpm, 
				   nocheck_access => 1,
				   no_skiplist => 1,
				   no_second_pass => 1);
	}
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
    my $query_all = (any { /\*/ } @l) ? 'a' : '';
    run_program::run('/bin/rpm', '>', \@l2, '-q' . $query_all, '--qf', "%{name}\n", @l); #- do not care about the return value
    $query_all ? chomp_(@l2) : intersection(\@l, [ chomp_(@l2) ]); #- cannot return directly @l2 since it contains things like "package xxx is not installed"
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

=back

=cut
