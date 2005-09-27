use do_pkgs;
package do_pkgs_common;

undef *ensure_are_installed;
*ensure_are_installed = sub {
    my ($do, $pkgs, $b_auto) = @_;

    my @not_installed = difference2($pkgs, [ $do->are_installed(@$pkgs) ]) or return 1;

    if (!$do->install(@not_installed)) {
	$do->in->ask_warn(N("Error"), N("Could not install the %s package!", $not_installed[0]));
	return;
    }
    1;
};

