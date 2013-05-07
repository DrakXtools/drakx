package harddrake::autoconf;

use common;

sub xconf {
    my ($modules_conf, $o, $o_skip_fb_setup, $o_resolution_wanted) = @_;

    log::l('automatic XFree configuration');
    
    require Xconfig::default;
    require do_pkgs;
    my $do_pkgs = do_pkgs_standalone->new;
    $o->{raw_X} = Xconfig::default::configure($do_pkgs);
    
    my $old_x = { if_($o_resolution_wanted, resolution_wanted => $o_resolution_wanted) };

    require Xconfig::main;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, $do_pkgs, $old_x, { allowFB => listlength(cat_("/proc/fb")), skip_fb_setup => $o_skip_fb_setup });

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
    # do not disable bluetooth service if adapter disappears
    # (for example if disabled by Fn keys)
    # systemd will automatically disable the service if needed
    return if !$enable;

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
#         $do_pkgs->ensure_is_installed("cpupower", "/lib/systemd/system/cpupower.service");
#         $do_pkgs->ensure_is_installed("apmd", "/usr/bin/apm");
#         $do_pkgs->ensure_is_installed("hotkeys", "/usr/bin/hotkeys");
#         $do_pkgs->ensure_is_installed("laptop-mode-tools", "/usr/sbin/laptop_mode");
#     } else {
#         $do_pkgs->ensure_is_installed("numlock", "/etc/rc.d/init.d/numlock");
#     }
    require services;
    services::set_status("apmd", -e "/proc/apm");
    #services::set_status("laptop-mode", $on_laptop);
    services::set_status("numlock", !$on_laptop);
    #services::set_status("cpupower", $on_laptop);
    
}

sub cpupower() {
    require cpupower;
    modules::set_preload_modules("cpupower", cpupower::get_modules());
}

sub floppy() {
    require detect_devices;
    modules::set_preload_modules("floppy", if_(detect_devices::floppy(), "floppy"));
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
