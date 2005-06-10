package network::ethernet; # $Id$

use c;
use detect_devices;
use common;
use run_program;

our @dhcp_clients = qw(dhclient dhcpcd pump dhcpxd);

sub install_dhcp_client {
    my ($in, $client) = @_;
    my %packages = (
        "dhclient" => "dhcp-client",
    );
    #- use default dhcp client if none is provided
    $client ||= $dhcp_clients[0];
    $client = $packages{$client} if exists $packages{$client};
    $in->do_pkgs->install($client);
}

sub mapIntfToDevice {
    my ($interface) = @_;
    my $hw_addr = c::getHwIDs($interface);
    return {} if $hw_addr =~ /^usb/;
    my ($bus, $slot, $func) = map { hex($_) } ($hw_addr =~ /([0-9a-f]+):([0-9a-f]+)\.([0-9a-f]+)/);
    $hw_addr && (every { defined $_ } $bus, $slot, $func) ?
      grep { $_->{pci_bus} == $bus && $_->{pci_device} == $slot && $_->{pci_function} == $func } detect_devices::probeall() : {};
}


# return list of [ intf_name, module, device_description ] tuples such as:
# [ "eth0", "3c59x", "3Com Corporation|3c905C-TX [Fast Etherlink]" ]
#
# this function try several method in order to get interface's driver and description in order to support both:
# - hotplug managed devices (USB, firewire)
# - special interfaces (IP aliasing, VLAN)
sub get_eth_cards {
    my ($modules_conf) = @_;
    my @all_cards = detect_devices::getNet();

    my @devs = detect_devices::pcmcia_probe();
    my $saved_driver;
    # compute device description and return (interface, driver, description) tuples:
    return map {
        my $interface = $_;
        my $description;
        # 1) get interface's driver through ETHTOOL ioctl:
        my ($a, $detected_through_ethtool);
        $a = c::getNetDriver($interface);
        if ($a) {
            $detected_through_ethtool = 1;
        } else {
            # 2) get interface's driver through module aliases:
            $a = $modules_conf->get_alias($interface);
        }

        # workaround buggy drivers that returns a bogus driver name for the GDRVINFO command of the ETHTOOL ioctl:
        my %fixes = (
                     "p80211_prism2_cs"  => 'prism2_cs',
                     "p80211_prism2_pci" => 'prism2_pci',
                     "p80211_prism2_usb" => 'prism2_usb',
                     "ip1394" => "eth1394",
                     "DL2K" => "dl2k",
                     "hostap" => undef, #- should be either "hostap_plx", "hostap_pci" or "hostap_cs"
                    );
        $a = $fixes{$a} if exists $fixes{$a};

        # 3) try to match a PCMCIA device for device description:
        if (my $b = find { $_->{device} eq $interface } @devs) { # PCMCIA case
            $a = $b->{driver};
            $description = $b->{description};
        } else {
            # 4) try to lookup a device by hardware address for device description:
            #    maybe should have we try sysfs first for robustness?
            ($description) = (mapIntfToDevice($interface))[0]->{description};
        }
        # 5) try to match a device through sysfs for driver & device description:
        #     (eg: ipw2100 driver for intel centrino do not support ETHTOOL)
        if (!$description) {
            my $drv = readlink("/sys/class/net/$interface/driver");
            if ($drv && $drv =~ s!.*/!!) {
                $a = $drv unless $detected_through_ethtool;
                my %l;
                my $dev_path = "/sys/class/net/$interface/device";
                my $sysfs_fields = detect_devices::get_sysfs_device_id_map($dev_path);
                $l{$_} = hex(chomp_(cat_("$dev_path/" . $sysfs_fields->{$_}))) foreach keys %$sysfs_fields;
                my @cards = grep { my $dev = $_; every { $dev->{$_} eq $l{$_} } keys %l } detect_devices::probeall();
                $description = $cards[0]{description} if @cards == 1;
            }
        }
        # 6) try to match a device by driver for device description:
        #    (eg: madwifi, ndiswrapper, ...)
        if (!$description) {
            my @cards = grep { $_->{driver} eq ($a || $saved_driver) } detect_devices::probeall();
            $description = $cards[0]{description} if @cards == 1;
        }
        $a and $saved_driver = $a; # handle multiple cards managed by the same driver
        [ $interface, $saved_driver, if_($description, $description) ];
    } @all_cards;
}

sub get_eth_cards_names {
    my (@all_cards) = @_;
    map { $_->[0] => join(': ', $_->[0], $_->[2]) } @all_cards;
}

#- returns (link_type, mac_address)
sub get_eth_card_mac_address {
    my ($intf) = @_;
    `LC_ALL= LANG= $::prefix/sbin/ip -o link show $intf 2>/dev/null` =~ m|.*link/(\S+)\s([0-9a-z:]+)\s|;
}

#- write interfaces MAC address in iftab
sub update_iftab() {
    foreach my $intf (detect_devices::getNet()) {
        my ($link_type, $mac_address) = get_eth_card_mac_address($intf) or next;
        #- do not write zeroed MAC addresses in iftab, it confuses ifrename
        $mac_address =~ /^[0:]+$/ and next;
        my $descriptor = ${{ ether => 'mac', ieee1394 => 'mac_ieee1394' }}{$link_type} or next;
        substInFile {
            s/^$intf\s+.*\n//;
            s/^.*\s+$mac_address\n//;
            $_ .= qq($intf\t$descriptor $mac_address\n) if eof;
        } "$::prefix/etc/iftab";
    }
}

# automatic net aliases configuration
sub configure_eth_aliases {
    my ($modules_conf) = @_;
    my @pcmcia_interfaces = map { $_->{device} } detect_devices::pcmcia_probe();
    foreach my $card (get_eth_cards($modules_conf)) {
        if (member($card->[0], @pcmcia_interfaces)) {
            #- do not write aliases for pcmcia cards, or cardmgr will not be loaded
            $modules_conf->remove_alias($card->[0]);
        } else {
            $modules_conf->set_alias($card->[0], $card->[1]);
        }
    }
}

1;
