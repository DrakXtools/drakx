package harddrake::autoconf;

use common;
use any;

sub xconf {
    my ($modules_conf, $o) = @_;

    log::l('automatic XFree configuration');
    
    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure();
    
    require Xconfig::main;
    require do_pkgs_standalone;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, do_pkgs_standalone->new, {}, { allowFB => 1 });

    modules::load_category($modules_conf, 'various/agpgart'); 
}

sub network_conf {
    my ($o) = @_;
    require network::network;
    network::network::easy_dhcp($o->{modules_conf}, $o->{netc}, $o->{intf}) and $o->{netcnx}{type} = 'lan';
}

1;
