package harddrake::autoconf;

use common;
use any;

sub xconf {
    my ($o) = @_;

    log::l('automatic XFree configuration');
    
    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure(keyboard::read());
    
    require Xconfig::main;
    require class_discard;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {}, { allowFB => 1 });

    modules::load_category('various/agpgart'); 
}

sub network_conf {
    my ($o) = @_;
    require network::network;
    network::network::easy_dhcp($o->{netc}, $o->{intf}) and $o->{netcnx}{type} = 'lan';
}

1;
