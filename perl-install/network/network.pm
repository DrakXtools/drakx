package network::network; # $Id$wir

#-######################################################################################
#- misc imports
#-######################################################################################
use Socket;

use common;
use detect_devices;
use run_program;
use any;
use log;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(resolv configureNetworkIntf netmask dns is_ip masked_ip findIntf addDefaultRoute all write_interface_conf read_all_conf dnsServers guessHostname configureNetworkNet read_resolv_conf getVarsFromSh read_interface_conf add2hosts gateway configureNetwork2 write_conf sethostname miscellaneousNetwork down_it read_conf write_resolv_conf up_it);

#-######################################################################################
#- Functions
#-######################################################################################
sub read_conf {
    my ($file) = @_;
    my %netc = getVarsFromSh($file);
    \%netc;
}

sub read_resolv_conf {
    my ($file) = @_;
    my @l = qw(dnsServer dnsServer2 dnsServer3);
    my %netc;

    local *F; open F, $file or die "cannot open $file: $!";
    local $_;
    while (<F>) {
	/^\s*nameserver\s+(\S+)/ and $netc{shift @l} = $1;
    }
    \%netc;
}

sub read_interface_conf {
    my ($file) = @_;
    my %intf = getVarsFromSh($file) or die "cannot open file $file: $!";

    $intf{BOOTPROTO} ||= 'static';
    $intf{isPtp} = $intf{NETWORK} eq '255.255.255.255';
    $intf{isUp} = 1;
    \%intf;
}

sub up_it {
    my ($prefix, $intfs) = @_;
    $_->{isUp} and return foreach values %$intfs;
    my $f = "/etc/resolv.conf"; symlink "$prefix/$f", $f;
    run_program::rooted($prefix, "/etc/rc.d/init.d/network", "start");
    $_->{isUp} = 1 foreach values %$intfs;
}

sub down_it {
    my ($prefix, $intfs) = @_;
    run_program::rooted($prefix, "/etc/rc.d/init.d/network", "stop");
    $_->{isUp} = 1 foreach values %$intfs;
}

sub write_conf {
    my ($file, $netc) = @_;

    if ($netc->{HOSTNAME}) {
	$netc->{HOSTNAME} =~ /\.(.*)$/;
	$1 and $netc->{DOMAINNAME} = $1;
    }
    ($netc->{DOMAINNAME}) ||= 'localdomain';
    add2hash($netc, {
		     NETWORKING => "yes",
		     FORWARD_IPV4 => "false",
		     HOSTNAME => "localhost.$netc->{DOMAINNAME}",
		    });

    setVarsInSh($file, $netc, qw(NETWORKING FORWARD_IPV4 DHCP_HOSTNAME HOSTNAME DOMAINNAME GATEWAY GATEWAYDEV NISDOMAIN));
}

sub write_resolv_conf {
    my ($file, $netc) = @_;

    my %new = (
        search => [ grep { $_ } uniq(@$netc{'DOMAINNAME', 'DOMAINNAME2'}) ],
        nameserver => [ grep { $_ } uniq(@$netc{'dnsServer', 'dnsServer2', 'dnsServer3'}) ],
    );

    my (%prev, @unknown);
    foreach (cat_($file)) {
	s/\s+$//;
	s/^[#\s]*//;

	if (my ($key, $val) = /^(search|nameserver)\s+(.*)$/) {
	    push @{$prev{$key}}, $val;
	} elsif (/^ppp temp entry$/) {
	} elsif (/\S/) {
	    push @unknown, $_;
	}
    }
    unlink $file;  #- workaround situation when /etc/resolv.conf is an absolute link to /etc/ppp/resolv.conf or whatever

    if (@{$new{search}} || @{$new{nameserver}}) {
	$prev{$_} = [ difference2($prev{$_} || [], $new{$_}) ] foreach keys %new;

	my @search = do {
	    my @new = if_(@{$new{search}}, "search " . join(' ', @{$new{search}}) . "\n");
	    my @old = if_(@{$prev{search}}, "# search " . join(' ', @{$prev{search}}) . "\n");
	    @new, @old;
	};
	my @nameserver = do {
	    my @new = map { "nameserver $_\n" } @{$new{nameserver}};
	    my @old = map { "# nameserver $_\n" } @{$prev{nameserver}};
	    @new, @old;
	};
	output($file, @search, @nameserver, (map { "# $_\n" } @unknown), "\n# ppp temp entry\n");
	
	#-res_init();		# reinit the resolver so DNS changes take affect
	1;
    } else {
	log::l("neither domain name nor dns server are configured");
	0;
    }
}

sub write_interface_conf {
    my ($file, $intf, $prefix) = @_;

    my @ip = split '\.', $intf->{IPADDR};
    my @mask = split '\.', $intf->{NETMASK};
    my $hwaddr;
    $::o->{miscellaneous}{track_network_id} and $hwaddr = -e "$prefix/sbin/ip" && `LC_ALL= LANG= $prefix/sbin/ip -o link show $intf->{DEVICE} 2>/dev/null`;
    if ($hwaddr) { chomp $hwaddr; $hwaddr =~ s/.*link\/ether\s([0-9a-z:]+)\s.*/$1/ }
    $hwaddr and $intf->{HWADDR} = undef;
    add2hash($intf, {
		     BROADCAST => join('.', mapn { int($_[0]) | ((~int($_[1])) & 255) } \@ip, \@mask),
		     NETWORK   => join('.', mapn { int($_[0]) &        $_[1]          } \@ip, \@mask),
		     ONBOOT => bool2yesno(!member($intf->{DEVICE}, map { $_->{device} } detect_devices::probeall())),
		     if_($::o->{miscellaneous}{track_network_id}, HWADDR => $hwaddr)
		    });
    setVarsInSh($file, $intf, qw(DEVICE BOOTPROTO IPADDR NETMASK NETWORK BROADCAST ONBOOT HWADDR), $intf->{wireless_eth} ? qw(WIRELESS_MODE WIRELESS_ESSID WIRELESS_NWID WIRELESS_FREQ WIRELESS_SENS WIRELESS_RATE WIRELESS_ENC_KEY WIRELESS_RTS WIRELESS_FRAG WIRELESS_IWCONFIG WIRELESS_IWSPY WIRELESS_IWPRIV) : ());
}

sub add2hosts {
    my ($file, $hostname, @ips) = @_;

    my %l = map { if_(/\s*(\S+)(.*)/, $1 => $2) }
            grep { !/\s+\Q$hostname\E\s*$/ } cat_($file);

    my $sub_hostname = $hostname =~ /(.*?)\./ ? " $1" : '';
    $l{$_} = "\t\t$hostname$sub_hostname" foreach grep { $_ } @ips;

    log::l("writing host information to $file");
    output($file, map { "$_$l{$_}\n" } keys %l);
}

# The interface/gateway needs to be configured before this will work!
sub guessHostname {
    my ($prefix, $netc, $intf) = @_;

    $intf->{isUp} && dnsServers($netc) or return 0;
    $netc->{HOSTNAME} && $netc->{DOMAINNAME} and return 1;

    write_resolv_conf("$prefix/etc/resolv.conf", $netc);

    my $name = gethostbyaddr(Socket::inet_aton($intf->{IPADDR}), Socket::AF_INET()) or log::l("reverse name lookup failed"), return 0;

    log::l("reverse name lookup worked");

    add2hash($netc, { HOSTNAME => $name });
    1;
}

sub addDefaultRoute {
    my ($netc) = @_;
    c::addDefaultRoute($netc->{GATEWAY}) if $netc->{GATEWAY};
}

sub sethostname {
    my ($netc) = @_;
    syscall_("sethostname", $netc->{HOSTNAME}, length $netc->{HOSTNAME}) or log::l("sethostname failed: $!");
}

sub resolv($) {
    my ($name) = @_;
    is_ip($name) and return $name;
    my $a = join(".", unpack "C4", (gethostbyname $name)[4]);
    #-log::l("resolved $name in $a");
    $a;
}

sub dnsServers {
    my ($netc) = @_;
    my %used_dns; @used_dns{$netc->{dnsServer}, $netc->{dnsServer2}, $netc->{dnsServer3}} = (1, 2, 3);
    sort { $used_dns{$a} <=> $used_dns{$b} } grep { $_ } keys %used_dns;
}

sub findIntf {
    my ($intf, $device) = @_;
    $intf->{$device}{DEVICE} = $device;
    $intf->{$device};
}
#PAD \s* a la fin
my $ip_regexp = qr/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
sub is_ip {
    my ($ip) = @_;
    my @fields = $ip =~ $ip_regexp or return;
    return if grep { $_ < 0 || $_ > 255 } @fields;
    @fields;
}
sub is_domain_name {
    my ($name) = @_;
    my @fields = split /\./, $name;
    $name !~ /\.$/ && @fields > 0 && @fields == grep { /^[[:alnum:]](?:[\-[:alnum:]]{0,61}[[:alnum:]])?$/ } @fields;
}

sub netmask {
    my ($ip) = @_;
    return "255.255.255.0" unless is_ip($ip);
    $ip =~ $ip_regexp;
    if ($1 >= 1 && $1 < 127) {
	"255.0.0.0";    #-1.0.0.0 to 127.0.0.0
    } elsif ($1  >= 128 && $1 <= 191) {
	"255.255.0.0";  #-128.0.0.0 to 191.255.0.0
    } elsif ($1 >= 192 && $1 <= 223) {
	"255.255.255.0";
    } else {
	"255.255.255.255"; #-experimental classes
    }
}

sub masked_ip {
    my ($ip) = @_;
    my @ip = is_ip($ip) or return '';
    my @mask = netmask($ip) =~ $ip_regexp;
    for (my $i = 0; $i < @ip; $i++) {
	$ip[$i] &= int $mask[$i];
    }
    join(".", @ip);
}

sub dns {
    my ($ip) = @_;
    my $mask = masked_ip($ip);
    my @masked = masked_ip($ip) =~ $ip_regexp;
    $masked[3]  = 2;
    join ".", @masked;

}
sub gateway {
    my ($ip) = @_;
    my @masked = masked_ip($ip) =~ $ip_regexp;
    $masked[3]  = 1;
    join ".", @masked;

}

sub configureNetworkIntf {
    my ($netc, $in, $intf, $net_device, $skip, $module) = @_;
    my $text;
    my @wireless_modules = qw(aironet_cs aironet4500_cs hermes airo orinoco_cs orinoco airo_cs netwave_cs ray_cs wavelan_cs wvlan_cs airport);
    my $flag = 0;
    foreach (@wireless_modules) {
	$module =~ /$_/ and $flag = 1;
    }
    if ($flag) {
	$intf->{wireless_eth} = 1;
	$netc->{wireless_eth} = 1;
	$intf->{WIRELESS_MODE} = "Managed";
	$intf->{WIRELESS_ESSID} = "any";
#-	$intf->{WIRELESS_NWID} = "";
#-	$intf->{WIRELESS_FREQ} = "";
#-	$intf->{WIRELESS_SENS} = "";
#-	$intf->{WIRELESS_RATE} = "";
#-	$intf->{WIRELESS_ENC_KEY} = "";
#-	$intf->{WIRELESS_RTS} = "";
#-	$intf->{WIRELESS_FRAG} = "";
#-	$intf->{WIRELESS_IWCONFIG} = "";
#-	$intf->{WIRELESS_IWSPY} = "";
#-	$intf->{WIRELESS_IWPRIV} = "";
    }
    if ($net_device eq $intf->{DEVICE}) {
	$skip and return 1;
	$text = N("WARNING: this device has been previously configured to connect to the Internet.
Simply accept to keep this device configured.
Modifying the fields below will override this configuration.");
    }
    else {
	$text = N("Please enter the IP configuration for this machine.
Each item should be entered as an IP address in dotted-decimal
notation (for example, 1.2.3.4).");
    }
    my $pump = $intf->{BOOTPROTO} =~ /^(dhcp|bootp)$/;
    delete $intf->{NETWORK};
    delete $intf->{BROADCAST};
    my $onboot = 1;
    my @fields = qw(IPADDR NETMASK);
    $::isStandalone or $in->set_help('configureNetworkIP');
    $in->ask_from(N("Configuring network device %s", $intf->{DEVICE}),
  	          (N("Configuring network device %s", $intf->{DEVICE}) . ($module ? N(" (driver %s)", $module) : '') . "\n\n") .
	          $text,
	         [ { label => N("IP address"), val => \$intf->{IPADDR}, disabled => sub { $pump } },
	           { label => N("Netmask"),     val => \$intf->{NETMASK}, disabled => sub { $pump } },
	           { label => N("Automatic IP"), val => \$pump, type => "bool", text => N("(bootp/dhcp)") },
	           if_($::expert, { label => N("Start at boot"), val => \$onboot, type => "bool" }),
		   if_($intf->{wireless_eth},
	           { label => "WIRELESS_MODE", val => \$intf->{WIRELESS_MODE}, list => [ "Ad-hoc", "Managed", "Master", "Repeater", "Secondary", "Auto" ] },
	           { label => "WIRELESS_ESSID", val => \$intf->{WIRELESS_ESSID} },
	           { label => "WIRELESS_NWID", val => \$intf->{WIRELESS_NWID} },
	           { label => "WIRELESS_FREQ", val => \$intf->{WIRELESS_FREQ} },
	           { label => "WIRELESS_SENS", val => \$intf->{WIRELESS_SENS} },
	           { label => "WIRELESS_RATE", val => \$intf->{WIRELESS_RATE} },
	           { label => "WIRELESS_ENC_KEY", val => \$intf->{WIRELESS_ENC_KEY} },
	           { label => "WIRELESS_RTS", val => \$intf->{WIRELESS_RTS} },
	           { label => "WIRELESS_FRAG", val => \$intf->{WIRELESS_FRAG} },
	           { label => "WIRELESS_IWCONFIG", val => \$intf->{WIRELESS_IWCONFIG} },
	           { label => "WIRELESS_IWSPY", val => \$intf->{WIRELESS_IWSPY} },
	           { label => "WIRELESS_IWPRIV", val => \$intf->{WIRELESS_IWPRIV} }
	           ),
	         ],
	         complete => sub {
	         	 $intf->{BOOTPROTO} = $pump ? "dhcp" : "static";
	         	 return 0 if $pump;
	         	 for (my $i = 0; $i < @fields; $i++) {
	         	     unless (is_ip($intf->{$fields[$i]})) {
	         		 $in->ask_warn('', N("IP address should be in format 1.2.3.4"));
	         		 return (1,$i);
	         	     }
	         	     return 0;
	         	 }
	         	 if ($intf->{WIRELESS_FREQ} !~ /[0-9.]*[kGM]/) {
	         	     $in->ask_warn('', N("Freq should have the suffix k, M or G (for example, \"2.46G\" for 2.46 GHz frequency), or add enough \'0\'."));
	         	     return (1,6);
	         	 }
	         	 if ($intf->{WIRELESS_RATE} !~ /[0-9.]*[kGM]/) {
	         	     $in->ask_warn('', N("Rate should have the suffix k, M or G (for example, \"11M\" for 11M), or add enough \'0\'."));
	         	     return (1,8);
	         	 }
	         },
	         focus_out => sub {
	         	 $intf->{NETMASK} ||= netmask($intf->{IPADDR}) unless $_[0]
	         }
    	    ) or return;
    $intf->{ONBOOT} = bool2yesno($onboot);
}

sub configureNetworkNet {
    my ($in, $netc, $intf, @devices) = @_;

    $netc->{dnsServer} ||= dns($intf->{IPADDR});
    my $gateway_ex = gateway($intf->{IPADDR});
#-    $netc->{GATEWAY}   ||= gateway($intf->{IPADDR});

    $::isInstall and $in->set_help('configureNetworkHost');
    $in->ask_from(N("Configuring network"),
N("Please enter your host name.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''.
You may also enter the IP address of the gateway if you have one"),
			       [ { label => N("Host name"), val => \$netc->{HOSTNAME} },
				 { label => N("DNS server"), val => \$netc->{dnsServer} },
				 { label => N("Gateway (e.g. %s)", $gateway_ex), val => \$netc->{GATEWAY} },
				    if_(@devices > 1,
				 { label => N("Gateway device"), val => \$netc->{GATEWAYDEV}, list => \@devices },
				    ),
			       ],
		               complete => sub {
				   if ($netc->{dnsServer} and !is_ip($netc->{dnsServer})) {
				       $in->ask_warn('', N("DNS server address should be in format 1.2.3.4"));
				       return 1;
				   }
				   if ($netc->{GATEWAY} and !is_ip($netc->{GATEWAY})) {
				       $in->ask_warn('', N("Gateway address should be in format 1.2.3.4"));
				       return 1;
				   }
				   0;
			       }
			      );
}

sub miscellaneousNetwork {
    my ($in, $clicked, $no_track_net) = @_;
    my $u = $::o->{miscellaneous} ||= {};
    $::isInstall and $in->set_help('configureNetworkProxy');
    $u->{track_network_id} = detect_devices::isLaptop();
    $::expert || $clicked and ($in->ask_from('',
       N("Proxies configuration"),
       [ { label => N("HTTP proxy"), val => \$u->{http_proxy} },
         { label => N("FTP proxy"),  val => \$u->{ftp_proxy} },
	 if_(!$no_track_net, { label => N("Track network card id (useful for laptops)"), val => \$u->{track_network_id}, type => "bool" }),
       ],
       complete => sub {
	   $u->{http_proxy} =~ m,^($|http://), or $in->ask_warn('', N("Proxy should be http://...")), return 1,0;
	   $u->{ftp_proxy} =~ m,^($|ftp://|http://), or $in->ask_warn('', N("Url should begin with 'ftp:' or 'http:'")), return 1,1;
	   0;
       }
    ) or return);
    1;
}

sub read_all_conf {
    my ($prefix, $netc, $intf) = @_;
    $netc ||= {}; $intf ||= {};
    add2hash($netc, read_conf("$prefix/etc/sysconfig/network")) if -r "$prefix/etc/sysconfig/network";
    add2hash($netc, read_resolv_conf("$prefix/etc/resolv.conf")) if -r "$prefix/etc/resolv.conf";
    foreach (all("$prefix/etc/sysconfig/network-scripts")) {
	if (/ifcfg-(\w+)/ && $1 ne 'lo') {
	    my $intf = findIntf($intf, $1);
	    add2hash($intf, { getVarsFromSh("$prefix/etc/sysconfig/network-scripts/$_") });
	}
    }
}

#- configureNetwork2 : configure the network interfaces.
#- input
#-  $prefix
#-  $netc
#-  $intf
#- $netc input
#-  NETWORKING : networking flag : string : "yes" by default
#-  FORWARD_IPV4 : forward IP flag : string : "false" by default
#-  HOSTNAME : hostname : string : "localhost.localdomain" by default
#-  DOMAINNAME : domainname : string : $netc->{HOSTNAME} =~ /\.(.*)/ by default
#-  DOMAINNAME2 : well it's another domainname : have to look further why we used 2
#-  The following are facultatives
#-  DHCP_HOSTNAME : If you have a dhcp and want to set the hostname
#-  GATEWAY : gateway
#-  GATEWAYDEV : gateway interface
#-  NISDOMAIN : nis domain
#-  $netc->{dnsServer} : dns server 1
#-  $netc->{dnsServer2} : dns server 2
#-  $netc->{dnsServer3} : dns server 3 : note that we uses the dns1 for the LAN, and the 2 others for the internet conx
#- $intf input: for each $device (for example ethx)
#-  $intf->{$device}{IPADDR} : IP address
#-  $intf->{$device}{NETMASK} : netmask
#-  $intf->{$device}{DEVICE} : DEVICE = $device
#-  $intf->{$device}{BOOTPROTO} : boot prototype : "bootp" or "dhcp" or "pump" or ...
sub configureNetwork2 {
    my ($in, $prefix, $netc, $intf) = @_;
    my $etc = "$prefix/etc";

    $netc->{wireless_eth} and $in->do_pkgs->install(qw(wireless-tools));
    write_conf("$etc/sysconfig/network", $netc);
    write_resolv_conf("$etc/resolv.conf", $netc);
    write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_->{DEVICE}", $_, $prefix) foreach grep { $_->{DEVICE} } values %$intf;
    add2hosts("$etc/hosts", $netc->{HOSTNAME}, map { $_->{IPADDR} } values %$intf);

    if (grep { $_->{BOOTPROTO} =~ /^(dhcp)$/ } values %$intf) {
	$in->do_pkgs->install($netc->{dhcp_client} ? $netc->{dhcp_client} : 'dhcpcd');
    }
    if (grep { $_->{BOOTPROTO} =~ /^(pump|bootp)$/ } values %$intf) {
	$in->do_pkgs->install('pump');
    }
    #-res_init();		#- reinit the resolver so DNS changes take affect

    any::miscellaneousNetwork();
}


1;
