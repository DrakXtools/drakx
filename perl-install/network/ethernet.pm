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
@EXPORT = qw(get_eth_categories);

sub write_ether_conf {
    my ($in, $modules_conf, $netcnx, $netc, $intf) = @_;
    configureNetwork2($in, $modules_conf, $::prefix, $netc, $intf);
    $netc->{NETWORKING} = "yes";
    if ($netc->{GATEWAY} || any { $_->{BOOTPROTO} =~ /dhcp/ } values %$intf) {
	$netcnx->{type} = 'lan';
	$netcnx->{NET_DEVICE} = $netc->{NET_DEVICE} = '';
	$netcnx->{NET_INTERFACE} = 'lan'; #$netc->{NET_INTERFACE};
    }
    $::isStandalone and $modules_conf->write;
    1;
}


sub mapIntfToDevice {
    my ($interface) = @_;
    my $hw_addr = c::getHwIDs($interface);
    my ($bus, $slot, $func) = map { hex($_) } ($hw_addr =~ /([0-9a-f]+):([0-9a-f]+)\.([0-9a-f]+)/);
    $hw_addr && (every { defined $_ } $bus, $slot, $func) ?
      grep { $_->{pci_bus} == $bus && $_->{pci_device} == $slot && $_->{pci_function} == $func } detect_devices::probeall() : {};
}


sub get_eth_categories() {
    'network/main|gigabit|pcmcia|usb|wireless|firewire';
}

# return list of [ intf_name, module, device_description ] tuples such as:
# [ "eth0", "3c59x", "3Com Corporation|3c905C-TX [Fast Etherlink]" ]
sub get_eth_cards {
    my ($modules_conf) = @_;
    my @all_cards = detect_devices::getNet();

    my @devs = detect_devices::pcmcia_probe();
    my $saved_driver;
    return map {
        my $interface = $_;
        my $description;
        my $a = c::getNetDriver($interface) || $modules_conf->get_alias($interface);
        $a = "eth1394" if $a eq "ip1394";
        if (my $b = find { $_->{device} eq $interface } @devs) { # PCMCIA case
            $a = $b->{driver};
            $description = $b->{description};
        } else {
            ($description) = (mapIntfToDevice($interface))[0]->{description};
        }
        if (!$description) {
            my $drv = readlink("/sys/class/net/$interface/driver");
            if ($drv && $drv =~ s!.*/!!) {
                $a = $drv;
                my %l;
                my %sysfs_fields = (id => "device", subid => "subsystem_device", vendor => "vendor", subvendor => "subsystem_vendor");
                $l{$_} = hex(chomp_(cat_("/sys/class/net/$interface/device/" . $sysfs_fields{$_}))) foreach keys %sysfs_fields;
                my @cards = grep { my $dev = $_; every { $dev->{$_} eq $l{$_} } keys %l } detect_devices::probeall();
                $description = $cards[0]{description} if @cards == 1;
            }
        }
        if (!$description) {
            my @cards = grep { $_->{driver} eq ($a || $saved_driver) } detect_devices::probeall();
            $description = $cards[0]{description} if @cards == 1;
        }
        $a and $saved_driver = $a; # handle multiple cards managed by the same driver
        [ $interface, $saved_driver, if_($description, $description) ]
    } @all_cards;
}

sub get_eth_cards_names {
    my (@all_cards) = @_;
    {
        map {
            $_->[2] ||= "Firewire (IEE1394) Network Adapter" if $_->[1] eq 'ip1394';
            $_->[0] => join(': ', $_->[0], $_->[2]);
        } @all_cards;
    };
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
        my $descriptor = ${{ ether => 'mac', ieee1394 => 'mac_ieee1394' }}{$link_type} or next;
        substInFile {
            s/^$intf\s+.*\n//;
            $_ .= qq($intf\t$descriptor $mac_address\n) if eof
        } "$::prefix/etc/iftab";
    }
}

# automatic net aliases configuration
sub configure_eth_aliases {
    my ($modules_conf) = @_;
    foreach my $card (get_eth_cards($modules_conf)) {
	$modules_conf->remove_alias($card->[1]);
	$modules_conf->set_alias($card->[0], $card->[1]);
    }
}

1;
