package network::ethernet; # $Id$

use c;
use network::network;
use modules;
use modules::interactive;
use detect_devices;
use common;
use run_program;
use network::tools;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(conf_network_card_backend);

sub write_ether_conf {
    my ($in, $netcnx, $netc, $intf) = @_;
    configureNetwork2($in, $::prefix, $netc, $intf);
    $netc->{NETWORKING} = "yes";
    if ($netc->{GATEWAY} || any { $_->{BOOTPROTO} =~ /dhcp/ } values %$intf) {
	$netcnx->{type} = 'lan';
	$netcnx->{NET_DEVICE} = $netc->{NET_DEVICE} = '';
	$netcnx->{NET_INTERFACE} = 'lan'; #$netc->{NET_INTERFACE};
        set_cnx_script($netc, "local network",
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


sub mapIntfToDevice {
    my ($interface) = @_;
    my $hw_addr = c::getHwIDs($interface);
    my ($bus, $slot, $func) = map { hex($_) } ($hw_addr =~ /([0-9a-f]+):([0-9a-f]+)\.([0-9a-f]+)/);
    $hw_addr && (every { defined $_ } $bus, $slot, $func) ?
      grep { $_->{pci_bus} == $bus && $_->{pci_device} == $slot && $_->{pci_function} == $func } detect_devices::probeall() : {};
}


# return list of [ intf_name, module, device_description ] tuples such as:
# [ "eth0", "3c59x", "3Com Corporation|3c905C-TX [Fast Etherlink]" ]
sub get_eth_cards() {
    my @all_cards = detect_devices::getNet();

    my @devs = detect_devices::pcmcia_probe();
    modules::mergein_conf("$::prefix/etc/modules.conf");
    my $saved_driver;
    return map {
        my $interface = $_;
        my $description;
        my $a = c::getNetDriver($interface) || modules::get_alias($interface);
        if (my $b = find { $_->{device} eq $interface } @devs) { # PCMCIA case
            $a = $b->{driver};
            $description = $b->{description};
        } else {
            ($description) = (mapIntfToDevice($interface))[0]->{description};
        }
        if (!$description) {
            my @cards = grep { $_->{driver} eq ($a || $saved_driver) } detect_devices::probeall();
            $description = $cards[0]->{description} if $#cards == 0;
        }
        $a and $saved_driver = $a; # handle multiple cards managed by the same driver
        [ $interface, $saved_driver, if_($description, $description) ]
    } @all_cards;
}

sub get_eth_cards_names {
    my (@all_cards) = @_;
    
    foreach my $card (@all_cards) {
	modules::remove_alias($card->[1]);
	modules::add_alias($card->[0], $card->[1]);
    }

    { map { $_->[0] => join(': ', $_->[0], $_->[2]) } @all_cards };
}


#- conf_network_card_backend : configure the specified network interface
# WARNING: you have to setup the ethernet cards, by calling load_category($in, 'network/main|gigabit|usb', !$::expert, 1)
#          or load_category_backend before calling this function.
#- input
#-  $netc
#-  $intf
#-  $type : type of interface, must be given if $interface is : string : "static" or "dhcp"
#-  $interface : set this interface and return it in a proper form.
#-  $ipadr : facultative, ip address of the interface : string
#-  $netadr : facultative, netaddress of the interface : string
#- when $interface is given, informations are written in $intf and $netc.
#- $intf output: $device is the result of
#-  $intf->{$device}->{DEVICE} : which device is concerned : $device is the result of $interface =~ /(eth[0-9]+)/; my $device = $1;;
#-  $intf->{$device}->{BOOTPROTO} : $type
#-  $intf->{$device}->{NETMASK} : '255.255.255.0'
#-  $intf->{$device}->{NETWORK} : $netadr
#-  $intf->{$device}->{ONBOOT} : "yes"
#- $netc output:
#-  $netc->{NET_DEVICE} : this is used to indicate that this eth card is used to connect to internet : $device
#- output:
#-  $device : returned passed interface name
sub conf_network_card_backend {
    my ($netc, $intf, $type, $interface, $o_ipadr, $o_netadr) = @_;
    #-type =static or dhcp

    $interface =~ /eth[0-9]+/ or die("the interface is not an ethx");
    
    # FIXME: this is wrong regarding some wireless interfaces or/and if user play if ifname(1):
    $netc->{NET_DEVICE} = $interface; #- one consider that there is only ONE Internet connection device..
    
    @{$intf->{$interface}}{qw(DEVICE BOOTPROTO NETMASK NETWORK ONBOOT)} = ($interface, $type, '255.255.255.0', $o_netadr, 'yes');
    
    $intf->{$interface}{IPADDR} = $o_ipadr if $o_ipadr;
    $interface;
}

# automatic net aliases configuration
sub configure_eth_aliases() {
    foreach (detect_devices::getNet()) {
        my $driver = c::getNetDriver($_) or next;
        modules::add_alias($_, $driver);
    }
}

1;
