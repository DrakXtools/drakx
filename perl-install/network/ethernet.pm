package network::ethernet; # $Id$


use network::network;
use modules;
use modules::interactive;
use detect_devices;
use common;
use run_program;
use network::tools;
use vars qw(@ISA @EXPORT);

use MDK::Common::Globals "network", qw($in $prefix);

@ISA = qw(Exporter);
@EXPORT = qw(conf_network_card conf_network_card_backend go_ethernet);

my (@cards, @ether_steps, $last, %last);


sub ether_conf{
    # my ($netcnx, $netc, $intf, $first_time) = @_;
    my ($in, $prefix, $netc, $intf) = @_;
    configureNetwork2($in, $prefix, $netc, $intf);
    $netc->{NETWORKING} = "yes";
    if ($netc->{GATEWAY} || any { $_->{BOOTPROTO} =~ /dhcp/ } values %$intf) {
	$netcnx->{type} = 'lan';
	$netcnx->{NET_DEVICE} = $netc->{NET_DEVICE} = '';
	$netcnx->{NET_INTERFACE} = 'lan'; #$netc->{NET_INTERFACE};
        write_cnx_script($netc, "local network",
qq(
/etc/rc.d/init.d/network restart
),
qq(
/etc/rc.d/init.d/network stop
/sbin/ifup lo
), $netcnx->{type});
    }
    $::isStandalone and modules::write_conf();
    1;
}


#- conf_network_card_backend : configure the network cards and return the list of them, or configure one specified interface : WARNING, you have to setup the ethernet cards, by calling load_category($in, 'network/main|gigabit|usb', !$::expert, 1) or load_category_backend before calling this function. Basically, you call this function in 2 times.
#- input
#-  $prefix
#-  $netc
#-  $intf
#-  $type : type of interface, must be given if $interface is : string : "static" or "dhcp"
#-  $interface : facultative, if given, set this interface and return it in a proper form. If not, return @all_cards
#-  $ipadr : facultative, ip address of the interface : string
#-  $netadr : facultative, netaddress of the interface : string
#- when $interface is given, informations are written in $intf and $netc. If not, @all_cards is returned.
#- $intf output: $device is the result of
#-  $intf->{$device}->{DEVICE} : which device is concerned : $device is the result of $interface =~ /(eth[0-9]+)/; my $device = $1;;
#-  $intf->{$device}->{BOOTPROTO} : $type
#-  $intf->{$device}->{NETMASK} : '255.255.255.0'
#-  $intf->{$device}->{NETWORK} : $netadr
#-  $intf->{$device}->{ONBOOT} : "yes"
#- $netc output:
#-  $netc->{NET_DEVICE} : this is used to indicate that this eth card is used to connect to internet : $device
#- output:
#-  $all_cards : a list of a list ( [eth1, module1], ... , [ethn, modulen]). Pass the ethx as $interface in further call.
#-  $device : only returned in case $interface was given it's $interface, but filtered by /eth[0-9+]/ : string : /eth[0-9+]/
sub conf_network_card_backend {
    my ($netc, $intf, $o_type, $o_interface, $o_ipadr, $o_netadr) = @_;
    #-type =static or dhcp
    if (!$o_interface) {
	my @all_cards = detect_devices::getNet();

	my @devs = detect_devices::pcmcia_probe();
	modules::mergein_conf("$prefix/etc/modules.conf");
	my $saved_driver;
	return map {
	    my $interface = $_;
	    my $a = c::getNetDriver($interface) || modules::get_alias($interface);
	    my $b = find { $_->{device} eq $interface } @devs;
	    $a ||= $b->{driver};
	    $a and $saved_driver = $a; # handle multiple cards managed by the same driver
 	    [ $interface, $saved_driver ]
	} @all_cards;
    }
    $o_interface =~ /eth[0-9]+/ or die("the interface is not an ethx");
    
    $netc->{NET_DEVICE} = $o_interface; #- one consider that there is only ONE Internet connection device..
    
    @{$intf->{$o_interface}}{qw(DEVICE BOOTPROTO NETMASK NETWORK ONBOOT)} = ($o_interface, $o_type, '255.255.255.0', $o_netadr, 'yes');
    
    $intf->{$o_interface}{IPADDR} = $o_ipadr if $o_ipadr;
    $o_interface;
}

# automatic net aliases configuration
sub configure_eth_aliases() {
    foreach (detect_devices::getNet()) {
        my $driver = c::getNetDriver($_) or next;
        modules::add_alias($_, $driver);
    }
}

1;
