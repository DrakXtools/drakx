package network::ethernet;

use network;
use modules;
use any;
use detect_devices;
use common qw(:file);
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(conf_network_card conf_network_card_backend go_ethernet);

sub conf_network_card {
    my ($netc, $intf, $type, $ipadr, $netadr) = @_;
    #-type =static or dhcp
    any::setup_thiskind($in, 'net', !$::expert, 1);
    my @all_cards=conf_network_card_backend($prefix, $netc, $intf, $type, undef, $ipadr, $netadr);
    my $interface;
    @all_cards == () and $in->ask_warn('', _("No ethernet network adapter has been detected on your system.
I cannot set up this connection type.")) and return;
    @all_cards == 1 and $interface = $all_cards[0]->[0] and goto l1;
    again :
	$interface = $in->ask_from_list(_("Choose the network interface"),
					_("Please choose which network adapter you want to use to connect to Internet"),
					[ map { $_->[0] . ($_->[1] ? " ( using module $_->[1] )" : "") } @all_cards ]
				       ) or return;
    defined $interface or goto again;
  l1:
    $::isStandalone and modules::write_conf($prefix);

    my $device=conf_network_card_backend($prefix, $netc, $intf, $type, $interface, $ipadr, $netadr, $interface);
    if ( $::isStandalone and !($type eq "dhcp")) {
	$in->ask_yesorno(_("Network interface"),
			  _("I'm about to restart the network device:\n") . $device . _("\nDo you agree?"), 1) and network::configureNetwork2($in, $prefix, $netc, $intf) and system("$prefix/sbin/ifdown $device;$prefix/sbin/ifup $device");
    }
    1;
}

#- conf_network_card_backend : configure the network cards and return the list of them, or configure one specified interface : WARNING, you have to setup the ethernet cards, by calling setup_thiskind($in, 'net', !$::expert, 1) or setup_thiskind_backend before calling this function. Basically, you call this function in 2 times.
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
#-  $netc->{nb_cards} : nb of ethernet cards
#-  $netc->{NET_DEVICE} : this is used to indicate that this eth card is used to connect to internet : $device
#- output:
#-  $all_cards : a list of a list ( [eth1, module1], ... , [ethn, modulen]). Pass the ethx as $interface in further call.
#-  $device : only returned in case $interface was given it's $interface, but filtered by /eth[0-9+]/ : string : /eth[0-9+]/
sub conf_network_card_backend {
    my ($prefix, $netc, $intf, $type, $interface, $ipadr, $netadr) = @_;
    #-type =static or dhcp
    if (!$interface) {
	my @all_cards = detect_devices::getNet();
	$netc->{nb_cards} = @all_cards;

	my @devs = modules::get_pcmcia_devices();
	modules::mergein_conf("$prefix/etc/modules.conf");
	my $saved_driver;
	return map {
	    my $interface = $_;
	    my $a = modules::get_alias($interface);
	    my $b;
	    foreach (@devs) {
		$_->{device} eq $interface and $b = $_->{driver};
	    }
	    $a ||= $b;
	    if ($a) { $saved_driver = $a }
	    [$interface, $saved_driver];
	} @all_cards;
    }
    my ($device) = $interface =~ /(eth[0-9]+)/ or die("the interface is not an ethx");
    $netc->{NET_DEVICE} = $device; #- one consider that there is only ONE Internet connection device..

    @{$intf->{$device}}{qw(DEVICE BOOTPROTO   NETMASK     NETWORK ONBOOT)} = 
                         ($device, $type, '255.255.255.0', $netadr, 'yes');

    $intf->{$device}->{IPADDR} = $ipadr if $ipadr;
    $device;
}

sub go_ethernet {
    my ($netc, $intf, $type, $ipadr, $netadr, $first_time) = @_;
    conf_network_card($netc, $intf, $type, $ipadr, $netadr) or return;
    $netc->{NET_INTERFACE}=$netc->{NET_DEVICE};
    network::configureNetwork($prefix, $netc, $in, $intf, $first_time) or return;
    output "$prefix$connect_file",
      qq(
#!/bin/bash
ifup $netc->{NET_DEVICE}
);
    output "$prefix$disconnect_file",
      qq(
#!/bin/bash
ifdown $netc->{NET_DEVICE}
);
    chmod 0755, "$prefix$disconnect_file";
    chmod 0755, "$prefix$connect_file";
    if ( $::isStandalone and $netc->{NET_DEVICE}) {
	$in->ask_yesorno(_("Network interface"),
			 _("I'm about to restart the network device $netc->{NET_DEVICE}. Do you agree?"), 1) and system("$prefix/sbin/ifdown $netc->{NET_DEVICE}; $prefix/sbin/ifup $netc->{NET_DEVICE}");
    }
    1;
}

1;
