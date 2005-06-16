package harddrake::autoconf;

use common;

sub xconf {
    my ($modules_conf, $o) = @_;

    log::l('automatic XFree configuration');
    
    require Xconfig::default;
    require do_pkgs;
    $o->{raw_X} = Xconfig::default::configure(do_pkgs_standalone->new);
    
    require Xconfig::main;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, do_pkgs_standalone->new, {}, { allowFB => 1 });

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

    #- should be set after installing the package above otherwise the file will be renamed.
    setVarsInSh("$::prefix/etc/sysconfig/pcmcia", {
     PCMCIA    => bool2yesno($pcic),
     PCIC      => $pcic,
     PCIC_OPTS => "",
     CORE_OPTS => "",
    });
}

1;
