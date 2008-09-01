package harddrake::autoconf;

use common;

sub xconf {
    my ($modules_conf, $o) = @_;

    log::l('automatic XFree configuration');
    
    require Xconfig::default;
    require do_pkgs;
    my $do_pkgs = do_pkgs_standalone->new;
    $o->{raw_X} = Xconfig::default::configure($do_pkgs);
    
    require Xconfig::main;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, $do_pkgs, {}, { allowFB => listlength(cat_("/proc/fb")) });

    #- always disable compositing desktop effects when configuring a new video card
    require Xconfig::glx;
    Xconfig::glx::write({});

    modules::load_category($modules_conf, 'various/agpgart'); 
}

sub network_conf {
    my ($obj) = @_;
    require network::network;
    network::network::easy_dhcp($obj->{net}, $obj->{modules_conf});
}

sub mouse_conf {
    my ($modules_conf) = @_;
    require do_pkgs;
    require mouse;
    mouse::write_conf(do_pkgs_standalone->new, $modules_conf, my $mouse = mouse::detect($modules_conf), 1);
    mouse::load_modules($mouse);
}

sub pcmcia {
    my ($pcic) = @_;
    require modules;
    modules::set_preload_modules("pcmcia", if_($pcic, $pcic));
}

sub bluetooth {
    my ($enable) = @_;
#- FIXME: make sure these packages are installed when needed
#     if ($enable) {
#         require do_pkgs;
#         my $do_pkgs = do_pkgs_standalone->new;
#         $do_pkgs->ensure_is_installed("bluez-utils", "/usr/bin/rfcomm");
#     }
    require services;
    services::set_status("bluetooth", $enable);
    my $kbluetoothd_cfg = '/etc/kde/kbluetoothrc';
    update_gnomekderc($kbluetoothd_cfg,
                      'General',
                      'AutoStart' => bool2text($enable)) if -f $kbluetoothd_cfg;
}

sub laptop {
    my ($on_laptop) = @_;
#- FIXME: make sure these packages are installed when needed
#     require do_pkgs;
#     my $do_pkgs = do_pkgs_standalone->new;
#     if ($on_laptop) {
#         $do_pkgs->ensure_is_installed("cpufreq", "/etc/rc.d/init.d/cpufreq");
#         $do_pkgs->ensure_is_installed("apmd", "/usr/bin/apm");
#         $do_pkgs->ensure_is_installed("hotkeys", "/usr/bin/hotkeys");
#         $do_pkgs->ensure_is_installed("laptop-mode-tools", "/usr/sbin/laptop_mode");
#     } else {
#         $do_pkgs->ensure_is_installed("numlock", "/etc/rc.d/init.d/numlock");
#     }
    require services;
    services::set_status("cpufreq", $on_laptop);
    services::set_status("apmd", $on_laptop);
    services::set_status("laptop-mode", $on_laptop);
    services::set_status("numlock", !$on_laptop);
}

sub cpufreq() {
    require cpufreq;
    modules::set_preload_modules("cpufreq", cpufreq::get_modules());
}

sub fix_aliases {
    my ($modules_conf) = @_;
    require modalias;
    my %new_aliases;
    #- first pass: find module targets whose modalias is not valid anymore
    foreach my $module ($modules_conf->modules) {
	if (my $aliased_to = $modules_conf->get_alias($module)) {
	    my @valid_modaliases = modalias::get_modules($module, 'skip_config') or next;
	    my ($found, $others) = partition { $_ eq $aliased_to } @valid_modaliases;
	    $new_aliases{$aliased_to} = @{$others || []} == 1 && $others->[0] if is_empty_array_ref($found);
	}
    }
    #- second pass: adapt module targets that are not valid anymore
    foreach my $module ($modules_conf->modules) {
	if (my $aliased_to = $modules_conf->get_alias($module)) {
	    if (my $new = exists $new_aliases{$aliased_to} && $new_aliases{$aliased_to}) {
		$modules_conf->set_alias($module, $new);
	    } else {
		$modules_conf->remove_alias($module);
	    }
	}
    }
    $modules_conf->write;
}

1;
