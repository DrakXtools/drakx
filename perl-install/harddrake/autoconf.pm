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
    my ($obj) = @_;
    require network::network;
    network::network::easy_dhcp($obj->{modules_conf}, $obj->{netc}, $obj->{intf}) and $obj->{netcnx}{type} = 'lan';
}

1;
