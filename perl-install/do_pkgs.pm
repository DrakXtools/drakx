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

    if (! $o_file || ! -e "$::prefix$o_file") {
	$do->in->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$b_auto;
	if (!$do->install($pkg)) {
	    $do->in->ask_warn(N("Error"), N("Could not install the %s package!", $pkg));
	    return;
	}
    }
    if ($o_file && ! -e "$::prefix$o_file") {
	$do->in->ask_warn('', N("Mandatory package %s is missing", $pkg));
	return;
    }
    1;
}

sub ensure_binary_is_installed {
    my ($do, $pkg, $binary, $b_auto) = @_;

    if (!whereis_binary($binary, $::prefix)) {
	$do->in->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$b_auto;
	if (!$do->install($pkg)) {
	    $do->in->ask_warn(N("Error"), N("Could not install the %s package!", $pkg));
	    return;
	}
    }
    if (!whereis_binary($binary, $::prefix)) {
	$do->in->ask_warn('', N("Mandatory package %s is missing", $pkg));
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

sub check_kernel_module_packages {
    my ($do, $base_name, $o_ext_name) = @_;
    
    require bootloader;
    my ($short_name) = $base_name =~ /^(.*)-kernel$/;
    my @rpms = $do->are_available("dkms-$short_name",
                                  map {
                                      $base_name . '-' . bootloader::vmlinuz2version($_);
                                  } bootloader::installed_vmlinuz());
    my @ext = $o_ext_name ? $do->are_available($o_ext_name) : ();

    log::l("found kernel module packages $_") foreach @rpms, @ext;

    #- we want at least a kernel package and the ext package if specified
    @rpms && (!$o_ext_name || @ext) && [ @rpms, @ext ];
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

sub in {
    my ($do) = @_;
    $do->{in};
}

sub install {
    my ($do, @l) = @_;
    log::l("do_pkgs_during_install::install");
    if ($::testing || $::globetrotter) {
	log::l("i would install packages " . join(' ', @l));
	return 1;
    } else {
	$do->{o}->pkg_install(@l);
    }
}

sub what_provides {
    my ($do, $name) = @_;
    map { $_->name } pkgs::packagesProviding($do->{o}{packages}, $name);
}

sub are_available {
    my ($do, @pkgs) = @_;
    grep { pkgs::packageByName($do->{o}{packages}, $_) } @pkgs;
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

sub new {
    my ($type, $o_in) = @_;
    bless { in => $o_in }, $type;
}

sub in {
    my ($do) = @_;
    $do->{in} ||= do {
	require interactive;
	interactive->vnew;
    };
    $do->{in};
}

sub install {
    my ($do, @l) = @_;

    return 1 if listlength(are_installed($do, @l)) == @l;

    if ($::testing) {
	log::l("i would install packages " . join(' ', @l));
	return 1;
    }

    my $_wait = $do->in->wait_message('', N("Installing packages..."));
    $do->in->suspend;
    log::explanations("installed packages @l");
    #- --expect-install added in urpmi 4.6.11
    my $ret = system('urpmi', '--allow-medium-change', '--auto', '--no-verify-rpm', '--gui', '--expect-install', @l) == 0;
    $do->in->resume;
    $ret;
}

sub are_available {
    my ($_do, @pkgs) = @_;
    my %pkgs = map { $_ => 1 } @pkgs;

    eval {
	local *_;
	require urpm;
	my $urpm = urpm->new;
	$urpm->read_config(nocheck_access => 1);
	foreach (grep { !$_->{ignore} } @{$urpm->{media} || []}) {
	    $urpm->parse_synthesis("$urpm->{statedir}/synthesis.$_->{hdlist}");
	}
	map { $_->name } grep { $pkgs{$_->name} } @{$urpm->{depslist} || []};
    };
    
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
    run_program::run('/bin/rpm', '>', \@l2, '-q', '--qf', "%{name}\n", @l); #- do not care about the return value
    intersection(\@l, [ chomp_(@l2) ]); #- can not return directly @l2 since it contains things like "package xxx is not installed"
}

sub remove {
    my ($do, @l) = @_;
    my $_wait = $do->in->wait_message('', N("Removing packages..."));
    $do->in->suspend;
    log::explanations("removed packages @l");
    my $ret = system('rpm', '-e', @l) == 0;
    $do->in->resume;
    $ret;
}

sub remove_nodeps {
    my ($do, @l) = @_;
    remove($do, '--nodeps', @l) == 0;
}
