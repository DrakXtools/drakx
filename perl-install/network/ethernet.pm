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
@EXPORT = qw(configureNetwork conf_network_card conf_network_card_backend go_ethernet);

sub configure_cable {
    my ($netcnx, $netc, $intf, $first_time) = @_;
    
    $netcnx->{type} = 'cable';
    
    $in->ask_from(N("Connect to the Internet"),
		  N("Which dhcp client do you want to use ? (default is dhcp-client)"),
		  [ { val => \$netcnx->{dhcp_client}, list => ["dhcp-client", "dhcpcd", "dhcpxd"] } ],
		 ) or return;
    
    $in->do_pkgs->install($netcnx->{dhcp_client});
    
    go_ethernet($netc, $intf, 'dhcp', '', '', $first_time);
    write_cnx_script($netc, "cable",
qq(
/sbin/ifup $netc->{NET_DEVICE}
),
qq(
/sbin/ifdown $netc->{NET_DEVICE}
), $netcnx->{type});
    1;
}

sub configure_lan {
    my ($netcnx, $netc, $intf, $first_time) = @_;
    configureNetwork($netc, $intf, $first_time) or return;
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
    $::isStandalone and modules::write_conf($prefix);
    1;
}

sub conf_network_card {
    my ($netc, $intf, $type, $ipadr, $o_netadr) = @_;
    #-type =static or dhcp
    modules::interactive::load_category($in, 'network/main|gigabit|usb', !$::expert, 1);
    my @all_cards = conf_network_card_backend($netc, $intf, $type, undef, $ipadr, $o_netadr);
    my $interface;
    @all_cards == () and $in->ask_warn('', N("No ethernet network adapter has been detected on your system.
I cannot set up this connection type.")) and return;
    @all_cards == 1 and $interface = $all_cards[0][0];
    while (!$interface) {
	$interface = $in->ask_from_list(N("Choose the network interface"),
					N("Please choose which network adapter you want to use to connect to Internet."),
					[ map { $_->[0] . ($_->[1] ? " (using module $_->[1])" : "") } @all_cards ]
				       ) or return;
    }
    $::isStandalone and modules::write_conf($prefix);

    my $_device = conf_network_card_backend($netc, $intf, $type, $interface, $ipadr, $o_netadr);
#      if ( $::isStandalone and !($type eq "dhcp")) {
#  	$in->ask_yesorno(N("Network interface"),
#  			  N("I'm about to restart the network device:\n") . $device . N("\nDo you agree?"), 1) and configureNetwork2($in, $prefix, $netc, $intf) and system("$prefix/sbin/ifdown $device;$prefix/sbin/ifup $device");
#      }
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
	    my $interface_state = `LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C $::prefix/sbin/ifconfig "$interface"`;
	    my $a = modules::get_alias($interface);
	    my $b;
	    foreach (@devs) {
		$_->{device} eq $interface and $b = $_->{driver};
	    }
	    $a ||= $b;
	    $a and $saved_driver = $a;
	    if_($::isInstall || $interface_state =~ /inet addr|Bcast|Mask|Interrupt|Base address/ && $a,
		[$interface, $saved_driver]);
	} @all_cards;
    }
    $o_interface =~ /eth[0-9]+/ or die("the interface is not an ethx");
    
    $netc->{NET_DEVICE} = $o_interface; #- one consider that there is only ONE Internet connection device..
    
    @{$intf->{$o_interface}}{qw(DEVICE BOOTPROTO NETMASK NETWORK ONBOOT)} = ($o_interface, $o_type, '255.255.255.0', $o_netadr, 'yes');
    
    $intf->{$o_interface}{IPADDR} = $o_ipadr if $o_ipadr;
    $o_interface;
}

sub go_ethernet {
    my ($netc, $intf, $type, $ipadr, $netadr, $first_time) = @_;
    conf_network_card($netc, $intf, $type, $ipadr, $netadr) or return;
    $netc->{NET_INTERFACE} = $netc->{NET_DEVICE};
    configureNetwork($netc, $intf, $first_time) or return;
    1;
}

sub configureNetwork {
    my ($netc, $intf, $_first_time) = @_;
    local $_;
    modules::interactive::load_category($in, 'network/main|gigabit|usb|pcmcia', !$::expert, 1) or return;
    my @all_cards = conf_network_card_backend($netc, $intf);
    my @l = map { $_->[0] } @all_cards;

    foreach (@all_cards) {
	modules::remove_alias($_->[0]);
	modules::add_alias($_->[0], $_->[1]);
    }

  configureNetwork_step_1:
    $netc ||= {};
    my $last; foreach (@all_cards) {
	my $intf2 = findIntf($intf ||= {}, $_->[0]);
	add2hash($intf2, $last);
	add2hash($intf2, { NETMASK => '255.255.255.0' });
	configureNetworkIntf($netc, $in, $intf2, $netc->{NET_DEVICE}, 0, $_->[1]) or return;

	$last = $intf2;
    }
    $last or return;
    
    if ($last->{BOOTPROTO} !~ /static/) {
	$netc->{minus_one} = 1;
#	$::isInstall and $in->set_help('configureNetworkHostDHCP');
	$in->ask_from(N("Configuring network"), N("

Enter a Zeroconf host name without any dot if you don't
want to use the default host name."),
		      [ { label => N("Zeroconf Host name"), val => \$netc->{ZEROCONF_HOSTNAME} },
			if_($::expert, { label => N("Host name"), val => \$netc->{HOSTNAME} }),
		      ],
		      complete => sub {
			  if ($netc->{ZEROCONF_HOSTNAME} && $netc->{ZEROCONF_HOSTNAME} =~ /\./) {
			      $in->ask_warn('', N("Zeroconf host name must not contain a ."));
			      return 1;
			  }
			  0;
		      }
		      ) or goto configureNetwork_step_1;
    } else {
	configureNetworkNet($in, $netc, $last ||= {}, @l) or goto configureNetwork_step_1;
    }
    network::network::miscellaneous_choose($in, $::o->{miscellaneous} ||= {}) or goto configureNetwork_step_1;
    1;
}

1;
