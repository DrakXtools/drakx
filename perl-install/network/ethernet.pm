package network::ethernet;

use network::network;
use modules;
use any;
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
    $::isInstall and $in->set_help('configureNetworkCable');
    $netcnx->{type}='cable';
    #  		     $netcnx->{cable}={};
    #  		     $in->ask_from_entries_ref(_("Cable connection"),
    #  _("Please enter your host name if you know it.
    #  Some DHCP servers require the hostname to work.
    #  Your host name should be a fully-qualified host name,
    #  such as ``mybox.mylab.myco.com''."),
    #  					       [_("Host name:")], [ \$netcnx->{cable}{hostname} ]);
    if ($::expert) {
	my @m=(
	       { description => "dhcpcd",
		 c => 1},
	       { description => "dhcpxd",
		 c => 3},
	       { description => "dhcp-client",
		 c => 4},
	      );
	if (my $f = $in->ask_from_listf(_("Connect to the Internet"),
					_("Which dhcp client do you want to use?
Default is dhcpcd"),
					sub { $_[0]{description} },
					\@m )) {
	    $f->{c}==1 and $netcnx->{dhcp_client}="dhcpcd" and $in->do_pkgs->install(qw(dhcpcd));
	    $f->{c}==3 and $netcnx->{dhcp_client}="dhcpxd" and $in->do_pkgs->install(qw(dhcpxd));
	    $f->{c}==4 and $netcnx->{dhcp_client}="dhcp-client" and $in->do_pkgs->install(qw(dhcp-client));
	}
    } else {
	$in->do_pkgs->install(qw(dhcpcd));
    }
    go_ethernet($netc, $intf, 'dhcp', '', '', $first_time);
    write_cnx_script($netc, "cable",
qq(
/sbin/ifup $netc->{NET_DEVICE}
),
qq(
/sbin/ifdown $netc->{NET_DEVICE}
));
}

sub configure_lan {
    my ($netcnx, $netc, $intf, $first_time) = @_;
    $::isInstall and $in->set_help('configureNetworkIP');
    configureNetwork($netc, $intf, $first_time) or return;
    configureNetwork2($in, $prefix, $netc, $intf);
    if ($::isStandalone and ($::expert or $in->ask_yesorno(_("Network configuration"),
							  _("Do you want to restart the network"), 1))) {
	run_program::rooted($prefix, "/etc/rc.d/init.d/network stop");
	if (!run_program::rooted($prefix, "/etc/rc.d/init.d/network start")) {
	    $in->ask_okcancel(_("Network Configuration"), _("A problem occured while restarting the network: \n\n%s", `/etc/rc.d/init.d/network start`), 0) or return;
	}
    }
    $netc->{NETWORKING} = "yes";
    if ($netc->{GATEWAY}) {
	$netcnx->{type}='lan';
	$netcnx->{NET_DEVICE} = $netc->{NET_DEVICE} = '';
	$netcnx->{NET_INTERFACE} = 'lan'; #$netc->{NET_INTERFACE};
        write_cnx_script($netc, "local network",
qq(
/etc/rc.d/init.d/network restart
),
qq(
/etc/rc.d/init.d/network stop
/sbin/ifup lo
));
    }
    $::isStandalone and modules::write_conf($prefix);
    1;
}

sub conf_network_card {
    my ($netc, $intf, $type, $ipadr, $netadr) = @_;
    #-type =static or dhcp
    any::setup_thiskind($in, 'net', !$::expert, 1);
    my @all_cards=conf_network_card_backend($netc, $intf, $type, undef, $ipadr, $netadr);
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

    my $device=conf_network_card_backend($netc, $intf, $type, $interface, $ipadr, $netadr, $interface);
    if ( $::isStandalone and !($type eq "dhcp")) {
	$in->ask_yesorno(_("Network interface"),
			  _("I'm about to restart the network device:\n") . $device . _("\nDo you agree?"), 1) and configureNetwork2($in, $prefix, $netc, $intf) and system("$prefix/sbin/ifdown $device;$prefix/sbin/ifup $device");
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
    my ($netc, $intf, $type, $interface, $ipadr, $netadr) = @_;
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
    configureNetwork($netc, $intf, $first_time) or return;
    if ( $::isStandalone and $netc->{NET_DEVICE}) {
	$in->ask_yesorno(_("Network interface"),
			 _("I'm about to restart the network device %s. Do you agree?", $netc->{NET_DEVICE}), 1) and system("$prefix/sbin/ifdown $netc->{NET_DEVICE}; $prefix/sbin/ifup $netc->{NET_DEVICE}");
    }
    1;
}

sub configureNetwork {
    my ($netc, $intf, $first_time) = @_;
    local $_;
    any::setup_thiskind($in, 'net', !$::expert, 1);
    my @l = detect_devices::getNet() or die _("no network card found");
    my @all_cards = conf_network_card_backend ($netc, $intf, undef, undef, undef, undef);

  configureNetwork_step_1:
    my $n_card=0;
    $netc ||= {};
    my $last; foreach (@l) {
	my $intf2 = findIntf($intf ||= {}, $_);
	add2hash($intf2, $last);
	add2hash($intf2, { NETMASK => '255.255.255.0' });
	configureNetworkIntf($netc, $in, $intf2, $netc->{NET_DEVICE}, 0, $all_cards[$n_card]->[1]) or return;

	$last = $intf2;
	$n_card++;
    }
    #-	  {
    #-	      my $wait = $o->wait_message(_("Hostname"), _("Determining host name and domain..."));
    #-	      network::guessHostname($o->{prefix}, $o->{netc}, $o->{intf});
    #-	  }
    $last or return;
    if ($last->{BOOTPROTO} =~ /^(dhcp|bootp)$/) {
	$netc->{minus_one} = 1;
	my $dhcp_hostname = $netc->{HOSTNAME};
	$::isInstall and $in->set_help('configureNetworkHostDHCP');
	$in->ask_from(_("Configuring network"),
_("Please enter your host name if you know it.
Some DHCP servers require the hostname to work.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''."),
		      [ { label => _("Host name"), val => \$netc->{HOSTNAME} }]) or goto configureNetwork_step_1;
	$netc->{HOSTNAME} ne $dhcp_hostname and $netc->{DHCP_HOSTNAME} = $netc->{HOSTNAME};
    } else {
	configureNetworkNet($in, $netc, $last ||= {}, @l) or goto configureNetwork_step_1;
    }
    miscellaneousNetwork($in);
    1;
}

1;
