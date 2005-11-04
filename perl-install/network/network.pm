package network::network; # $Id$wir

#-######################################################################################
#- misc imports
#-######################################################################################

use strict;

use Socket;
use common;
use detect_devices;
use run_program;
use network::tools;
use vars qw(@ISA @EXPORT);
use log;

my $network_file = "/etc/sysconfig/network";
my $resolv_file = "/etc/resolv.conf";
my $tmdns_file = "/etc/tmdns.conf";


@ISA = qw(Exporter);
@EXPORT = qw(addDefaultRoute dns dnsServers gateway guessHostname is_ip is_ip_forbidden masked_ip netmask resolv sethostname);

#- $net hash structure
#-   autodetect
#-   type
#-   net_interface
#-   PROFILE: selected netprofile
#-   network (/etc/sysconfig/network) : NETWORKING FORWARD_IPV4 NETWORKING_IPV6 HOSTNAME GATEWAY GATEWAYDEV NISDOMAIN
#-     NETWORKING : networking flag : string : "yes" by default
#-     FORWARD_IPV4 : forward IP flag : string : "false" by default
#-     HOSTNAME : hostname : string : "localhost.localdomain" by default
#-     GATEWAY : gateway
#-     GATEWAYDEV : gateway interface
#-     NISDOMAIN : nis domain
#-     NETWORKING_IPV6 : use IPv6, "yes" or "no"
#-     IPV6_DEFAULTDEV
#-   resolv (/etc/resolv.conf): dnsServer, dnsServer2, dnsServer3, DOMAINNAME, DOMAINNAME2, DOMAINNAME3
#-     dnsServer : dns server 1
#-     dnsServer2 : dns server 2
#-     dnsServer3 : dns server 3 : note that we uses the dns1 for the LAN, and the 2 others for the internet conx
#-     DOMAINNAME : domainname : string : $net->{network}{HOSTNAME} =~ /\.(.*)/ by default
#-     DOMAINNAME2 : well it's another domainname : have to look further why we used 2
#-   adsl: bus, Encapsulation, vpi, vci provider_id, method, login, passwd, ethernet_device, capi_card
#-   cable: bpalogin, login, passwd
#-   zeroconf: hostname
#-   auth: LDAPDOMAIN WINDOMAIN
#-   ifcfg (/etc/sysconfig/network-scripts/ifcfg-*):
#-     key : device name
#-     value : hash containing ifcfg file values, see write_interface_conf() for an exhaustive list
#-       DHCP_HOSTNAME : If you have a dhcp and want to set the hostname
#-       IPADDR : IP address
#-       NETMASK : netmask
#-       DEVICE : device name
#-       BOOTPROTO : boot prototype : "bootp" or "dhcp" or "pump" or ...
#-       IPV6INIT
#-       IPV6TO4INIT
#-       MS_DNS1
#-       MS_DNS2
#-       DOMAIN

sub read_conf {
    my ($file) = @_;
    +{ getVarsFromSh($file) };
}

sub read_resolv_conf_raw {
    my ($o_file) = @_;
    my $s = cat_($o_file || $::prefix . $resolv_file);
    { nameserver => [ $s =~ /^\s*nameserver\s+(\S+)/mg ],
      search => [ if_($s =~ /^\s*search\s+(.*)/m, split(' ', $1)) ] };
}

sub read_resolv_conf {
    my ($o_file) = @_;
    my $resolv_conf = read_resolv_conf_raw($o_file);
    +{
      (mapn { $_[0] => $_[1] } [ qw(dnsServer dnsServer2 dnsServer3) ], $resolv_conf->{nameserver}),
      (mapn { $_[0] => $_[1] } [ qw(DOMAINNAME DOMAINNAME2 DOMAINNAME3) ], $resolv_conf->{search}),
     };
}

sub read_interface_conf {
    my ($file) = @_;
    my %intf = getVarsFromSh($file);

    $intf{BOOTPROTO} ||= 'static';
    $intf{isPtp} = $intf{NETWORK} eq '255.255.255.255';
    $intf{isUp} = 1;
    \%intf;
}

sub read_zeroconf() {
    cat_($::prefix . $tmdns_file) =~ /^\s*hostname\s*=\s*(\w+)/m && { ZEROCONF_HOSTNAME => $1 };
}

sub write_network_conf {
    my ($net) = @_;

    if ($net->{network}{HOSTNAME} && $net->{network}{HOSTNAME} =~ /\.(.+)$/) {
	$net->{resolv}{DOMAINNAME} = $1;
    }
    $net->{network}{NETWORKING} = 'yes';

    setVarsInSh($::prefix . $network_file, $net->{network}, qw(HOSTNAME NETWORKING GATEWAY GATEWAYDEV NISDOMAIN FORWARD_IPV4 NETWORKING_IPV6 IPV6_DEFAULTDEV));
}

sub write_zeroconf {
    my ($net, $in) = @_;
    my $zhostname = $net->{zeroconf}{hostname};
    my $file = $::prefix . $tmdns_file;

    if ($zhostname) {
	$in->do_pkgs->ensure_binary_is_installed('tmdns', 'tmdns', 'auto') if !$in->do_pkgs->is_installed('bind');
	$in->do_pkgs->ensure_binary_is_installed('zcip', 'zcip', 'auto');
    }

    #- write blank hostname even if disabled so that drakconnect does not assume zeroconf is enabled
    eval { substInFile { s/^\s*(hostname)\s*=.*/$1 = $zhostname/ } $file } if $zhostname || -f $file;

    require services;
    services::set_status('tmdns', $net->{zeroconf}{hostname});
}

sub write_resolv_conf {
    my ($net) = @_;
    my $resolv = $net->{resolv};
    my $file = $::prefix . $resolv_file;

    my %new = (
        search => [ grep { $_ } uniq(@$resolv{'DOMAINNAME', 'DOMAINNAME2', 'DOMAINNAME3'}) ],
        nameserver => [ grep { $_ } uniq(@$resolv{'dnsServer', 'dnsServer2', 'dnsServer3'}) ],
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
    unlink $file if -l $file;  #- workaround situation when /etc/resolv.conf is an absolute link to /etc/ppp/resolv.conf or whatever

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
	output_with_perm($file, 0644, @search, @nameserver, (map { "# $_\n" } @unknown), "\n# ppp temp entry\n");

	#-res_init();		# reinit the resolver so DNS changes take affect
	1;
    } else {
	log::explanations("neither domain name nor dns server are configured");
	0;
    }
}

sub update_broadcast_and_network {
    my ($intf) = @_;
    my @ip = split '\.', $intf->{IPADDR};
    my @mask = split '\.', $intf->{NETMASK};
    $intf->{BROADCAST} = join('.', mapn { int($_[0]) | ((~int($_[1])) & 255) } \@ip, \@mask);
    $intf->{NETWORK} = join('.', mapn { int($_[0]) &        $_[1]          } \@ip, \@mask);
}

sub write_interface_settings {
    my ($intf, $file) = @_;
    setVarsInSh($file, $intf, qw(DEVICE BOOTPROTO IPADDR NETMASK NETWORK BROADCAST ONBOOT HWADDR METRIC MII_NOT_SUPPORTED TYPE USERCTL ATM_ADDR ETHTOOL_OPTS VLAN MTU MS_DNS1 MS_DNS2 DOMAIN),
                qw(WIRELESS_MODE WIRELESS_ESSID WIRELESS_NWID WIRELESS_FREQ WIRELESS_SENS WIRELESS_RATE WIRELESS_ENC_KEY WIRELESS_RTS WIRELESS_FRAG WIRELESS_IWCONFIG WIRELESS_IWSPY WIRELESS_IWPRIV WIRELESS_WPA_DRIVER),
                qw(DVB_ADAPTER_ID DVB_NETWORK_DEMUX DVB_NETWORK_PID),
                qw(IPV6INIT IPV6TO4INIT),
                qw(MRU REMIP PEERDNS PPPOPTIONS HARDFLOWCTL DEFABORT RETRYTIMEOUT PAPNAME LINESPEED MODEMPORT DEBUG ESCAPECHARS INITSTRING),
                qw(DISCONNECTTIMEOUT PERSIST DEFROUTE),
                if_($intf->{BOOTPROTO} eq "dhcp", qw(DHCP_CLIENT DHCP_HOSTNAME NEEDHOSTNAME PEERDNS PEERYP PEERNTPD DHCP_TIMEOUT)),
                if_($intf->{DEVICE} =~ /^ippp\d+$/, qw(DIAL_ON_IFUP))
               );
    substInFile { s/^DEVICE='(`.*`)'/DEVICE=$1/g } $file; #- remove quotes if DEVICE is the result of a command
    chmod $intf->{WIRELESS_ENC_KEY} ? 0700 : 0755, $file; #- hide WEP key for non-root users
    log::explanations("written $intf->{DEVICE} interface configuration in $file");
}

sub write_interface_conf {
    my ($net, $name) = @_;

    my $file = "$::prefix/etc/sysconfig/network-scripts/ifcfg-$name";
    #- prefer ifcfg-XXX files
    unlink("$::prefix/etc/sysconfig/network-scripts/$name");

    my $intf = $net->{ifcfg}{$name};

    require network::ethernet;
    my (undef, $mac_address) = network::ethernet::get_eth_card_mac_address($intf->{DEVICE});
    $intf->{HWADDR} &&= $mac_address; #- set HWADDR to MAC address if required

    update_broadcast_and_network($intf);
    $intf->{ONBOOT} ||= bool2yesno(!member($intf->{DEVICE}, map { $_->{device} } detect_devices::pcmcia_probe()));

    defined($intf->{METRIC}) or $intf->{METRIC} = network::tools::get_default_metric(network::tools::get_interface_type($intf)),
    $intf->{BOOTPROTO} =~ s/dhcp.*/dhcp/;

    write_interface_settings($intf, $file);
}

sub write_wireless_conf {
    my ($ssid, $ifcfg) = @_;
    my $wireless_file = "$::prefix/etc/sysconfig/network-scripts/wireless.d/$ssid";
    write_interface_settings($ifcfg, $wireless_file);
    # FIXME: write only DHCP/IP settings here
    substInFile { $_ = '' if /^DEVICE=/ } $wireless_file;
}

sub add2hosts {
    my ($hostname, @ips) = @_;
    my ($sub_hostname) = $hostname =~ /(.*?)\./;

    my $file = "$::prefix/etc/hosts";

    my %l;
    foreach (cat_($file)) {
        my ($ip, $aliases) = /^\s*(\S+)\s+(\S+.*)$/ or next;
        push @{$l{$ip}}, difference2([ split /\s+/, $aliases ], [ $hostname, $sub_hostname ]);
    } cat_($file);

    unshift @{$l{$_}}, $hostname, if_($sub_hostname, $sub_hostname) foreach grep { $_ } @ips;

    log::explanations("writing host information to $file");
    output($file, map { "$_\t\t" . join(" ", @{$l{$_}}) . "\n" } keys %l);
}

# The interface/gateway needs to be configured before this will work!
sub guessHostname {
    my ($net, $intf_name) = @_;

    $net->{ifcfg}{$intf_name}{isUp} && dnsServers($net) or return 0;
    $net->{network}{HOSTNAME} && $net->{resolv}{DOMAINNAME} and return 1;

    write_resolv_conf($net);

    my $name = gethostbyaddr(Socket::inet_aton($net->{ifcfg}{$intf_name}{IPADDR}), Socket::AF_INET()) or log::explanations("reverse name lookup failed"), return 0;

    log::explanations("reverse name lookup worked");

    $net->{network}{HOSTNAME} ||= $name;
    1;
}

sub addDefaultRoute {
    my ($net) = @_;
    c::addDefaultRoute($net->{network}{GATEWAY}) if $net->{network}{GATEWAY};
}

sub sethostname {
    my ($net) = @_;
    my $text;
    my $hostname = $net->{network}{HOSTNAME};
    syscall_("sethostname", $hostname, length $hostname) ? ($text="set sethostname to $hostname") : ($text="sethostname failed: $!");
    log::explanations($text);

    run_program::run("/usr/bin/run-parts", "--arg", $hostname, "/etc/sysconfig/network-scripts/hostname.d") unless $::isInstall;
}

sub resolv($) {
    my ($name) = @_;
    is_ip($name) and return $name;
    my $a = join(".", unpack "C4", (gethostbyname $name)[4]);
    #-log::explanations("resolved $name in $a");
    $a;
}

sub dnsServers {
    my ($net) = @_;
    #- FIXME: that's weird
    my %used_dns; @used_dns{$net->{network}{dnsServer}, $net->{network}{dnsServer2}, $net->{network}{dnsServer3}} = (1, 2, 3);
    sort { $used_dns{$a} <=> $used_dns{$b} } grep { $_ } keys %used_dns;
}

sub findIntf {
    my ($net, $device) = @_;
    $net->{ifcfg}{$device}{DEVICE} = undef;
    $net->{ifcfg}{$device};
}

my $ip_regexp = qr/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

sub is_ip {
    my ($ip) = @_;
    my @fields = $ip =~ $ip_regexp or return;
    every { 0 <= $_ && $_ <= 255 } @fields or return;
    @fields;
}

sub ip_compare {
    my ($ip1, $ip2) = @_;
    my (@ip1_fields) = $ip1 =~ $ip_regexp;
    my (@ip2_fields) = $ip2 =~ $ip_regexp;
    
    every { $ip1_fields[$_] eq $ip2_fields[$_] } (0 .. 3);
}

sub is_ip_forbidden {
    my ($ip) = @_;
    my @forbidden = ('127.0.0.1', '255.255.255.255');
    
    any { ip_compare($ip, $_) } @forbidden;
}

sub is_domain_name {
    my ($name) = @_;
    my @fields = split /\./, $name;
    $name !~ /\.$/ && @fields > 0 && @fields == grep { /^[[:alnum:]](?:[\-[:alnum:]]{0,61}[[:alnum:]])?$/ } @fields;
}

sub netmask {
    my ($ip) = @_;
    return "255.255.255.0" unless is_ip($ip);
    $ip =~ $ip_regexp or warn "IP_regexp failed\n" and return "255.255.255.0";
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
    my @masked = masked_ip($ip) =~ $ip_regexp;
    $masked[3]  = 2;
    join(".", @masked);

}

sub gateway {
    my ($ip) = @_;
    my @masked = masked_ip($ip) =~ $ip_regexp;
    $masked[3]  = 1;
    join(".", @masked);
}


sub netprofile_set {
    my ($net, $profile) = @_;
    $net->{PROFILE} = $profile;
    system('/sbin/set-netprofile', $net->{PROFILE});
    log::explanations(qq(Switching to "$net->{PROFILE}" profile));
}

sub netprofile_save {
    my ($net) = @_;
    system('/sbin/save-netprofile', $net->{PROFILE});
    log::explanations(qq(Saving "$net->{PROFILE}" profile));
}

sub netprofile_delete {
    my ($profile) = @_;
    return if !$profile || $profile eq "default";
    rm_rf("$::prefix/etc/netprofile/profiles/$profile");
    log::explanations(qq(Deleting "$profile" profile));
}

sub netprofile_add {
    my ($net, $profile) = @_;
    return if !$profile || $profile eq "default" || member($profile, netprofile_list());
    system('/sbin/clone-netprofile', $net->{PROFILE}, $profile);
    log::explanations(qq("Creating "$profile" profile));
}

sub netprofile_list() {
    map { if_(m!([^/]*)/$!, $1) } glob("$::prefix/etc/netprofile/profiles/*/");
}

sub netprofile_read {
    my ($net) = @_;
    my $config = { getVarsFromSh("$::prefix/etc/netprofile/current") };
    $net->{PROFILE} = $config->{PROFILE} || 'default';
}


sub miscellaneous_choose {
    my ($in, $u) = @_;

    $in->ask_from(N("Proxies configuration"),
       N("Here you can set up your proxies configuration (eg: http://my_caching_server:8080)"),
       [ { label => N("HTTP proxy"), val => \$u->{http_proxy} },
         { label => N("FTP proxy"),  val => \$u->{ftp_proxy} },
       ],
       complete => sub {
	   $u->{http_proxy} =~ m,^($|http://), or $in->ask_warn('', N("Proxy should be http://...")), return 1,0;
	   $u->{ftp_proxy} =~ m,^($|ftp://|http://), or $in->ask_warn('', N("URL should begin with 'ftp:' or 'http:'")), return 1,1;
	   0;
       }
    ) or return;
    1;
}

sub proxy_configure {
    my ($u) = @_;
    my $sh_file = "$::prefix/etc/profile.d/proxy.sh";
    setExportedVarsInSh($sh_file,  $u, qw(http_proxy ftp_proxy));
    chmod 0755, $sh_file;
    my $csh_file = "$::prefix/etc/profile.d/proxy.csh";
    setExportedVarsInCsh($csh_file, $u, qw(http_proxy ftp_proxy));
    chmod 0755, $csh_file;

    #- KDE proxy settings
    my $kde_config_dir = "$::prefix/usr/share/config";
    my $kde_config_file = "$kde_config_dir/kioslaverc";
    if (-d $kde_config_dir) {
        update_gnomekderc($kde_config_file,
                          undef,
                          PersistentProxyConnection => "false"
                      );
        update_gnomekderc($kde_config_file,
                          "Proxy Settings",
                          AuthMode => 0,
                          ProxyType => $u->{http_proxy} || $u->{ftp_proxy} ? 4 : 0,
                          ftpProxy => "ftp_proxy",
                          httpProxy => "http_proxy",
                          httpsProxy => "http_proxy"
                  );
    }

    #- Gnome proxy settings
    if (-d "$::prefix/etc/gconf/2/") {
        my $defaults_dir = "/etc/gconf/gconf.xml.local-defaults";
        my $p_defaults_dir = "$::prefix$defaults_dir";
        my $p_defaults_path = "$::prefix/etc/gconf/2/local-defaults.path";
        -r $p_defaults_path or output_with_perm($p_defaults_path, 0755, qq(
# System local settings
xml:readonly:$defaults_dir
));
        -d $p_defaults_dir or mkdir $p_defaults_dir, 0755;

        my $use_alternate_proxy;
        my $gconf_set = sub {
            my ($key, $type, $value) = @_;
            #- gconftool-2 is available since /etc/gconf/2/ exists
            system("gconftool-2", "--config-source=xml::$p_defaults_dir", "--direct", "--set", "--type=$type", $key, $value);
        };

        #- http proxy
        if (my ($user, $password, $host, $port) = $u->{http_proxy} =~ m,^http://(?:([^:\@]+)(?::([^:\@]+))?\@)?([^\:]+)(?::(\d+))?$,) {
            $port ||= 80;
            $gconf_set->("/system/http_proxy/use_http_proxy", "bool", 1);
            $gconf_set->("/system/http_proxy/host", "string", $host);
            $gconf_set->("/system/http_proxy/port", "int", $port);
            $gconf_set->("/system/http_proxy/use_authentication", "bool", to_bool($user));
            $user and $gconf_set->("/system/http_proxy/authentication_user", "string", $user);
            $password and $gconf_set->("/system/http_proxy/authentication_password", "string", $password);

            #- https proxy (ssl)
            $gconf_set->("/system/proxy/secure_host", "string", $host);
            $gconf_set->("/system/proxy/secure_port", "int", $port);
            $use_alternate_proxy = 1;
        } else {
            $gconf_set->("/system/http_proxy/use_http_proxy", "bool", 0);
            #- clear the ssl host so that it isn't used if the manual proxy is activated for ftp
            $gconf_set->("/system/proxy/secure_host", "string", "");
        }

        #- ftp proxy
        if (my ($host, $port) = $u->{ftp_proxy} =~ m,^(?:http|ftp)://(?:[^:\@]+(?::[^:\@]+)?\@)?([^\:]+)(?::(\d+))?$,) {
            $port ||= 21;
            $gconf_set->("/system/proxy/mode", "string", "manual");
            $gconf_set->("/system/proxy/ftp_host", "string", $host);
            $gconf_set->("/system/proxy/ftp_port",  "int", $port);
            $use_alternate_proxy = 1;
        } else {
            #- clear the ftp host so that it isn't used if the manual proxy is activated for ssl
            $gconf_set->("/system/proxy/ftp_host", "string", "");
        }

        #- set proxy mode to manual if either https or ftp is used
        $gconf_set->("/system/proxy/mode", "string", $use_alternate_proxy ? "manual" : "none");

        #- make gconf daemons reload their settings
        system("killall -s HUP gconfd-2");
    }
}

sub read_net_conf {
    my ($net) = @_;
    add2hash($net->{network} ||= {}, read_conf($::prefix . $network_file));
    add2hash($net->{resolv} ||= {}, read_resolv_conf());
    add2hash($net->{zeroconf} ||= {}, read_zeroconf());

    foreach (all("$::prefix/etc/sysconfig/network-scripts")) {
	my ($device) = /^ifcfg-([A-Za-z0-9.:_-]+)$/;
	next if $device =~ /.rpmnew$|.rpmsave$/;
	if ($device && $device ne 'lo') {
	    my $intf = findIntf($net, $device);
	    add2hash($intf, { getVarsFromSh("$::prefix/etc/sysconfig/network-scripts/$_") });
	    $intf->{DEVICE} ||= $device;
	}
    }
    $net->{wireless} ||= {};
    foreach (all("$::prefix/etc/sysconfig/network-scripts/wireless.d")) {
        $net->{wireless}{$_} = { getVarsFromSh("$::prefix/etc/sysconfig/network-scripts/wireless.d/$_") };
    }
    netprofile_read($net);
    if (my $default_intf = network::tools::get_default_gateway_interface($net)) {
	$net->{net_interface} = $default_intf;
	$net->{type} = network::tools::get_interface_type($net->{ifcfg}{$default_intf});
    }
}

#- FIXME: this is buggy, use network::tools::get_default_gateway_interface
sub probe_netcnx_type {
    my ($net) = @_;
    #- try to probe $netcnx->{type} which is used almost everywhere.
    unless ($net->{type}) {
	#- ugly hack to determine network type (avoid saying not configured in summary).
	-e "$::prefix/etc/ppp/peers/adsl" and $net->{type} ||= 'adsl'; # enough ?
	-e "$::prefix/etc/ppp/ioptions1B" || -e "$::prefix/etc/ppp/ioptions2B" and $net->{type} ||= 'isdn'; # enough ?
	$net->{ifcfg}{ppp0} and $net->{type} ||= 'modem';
	$net->{ifcfg}{eth0} and $net->{type} ||= 'lan';
    }
}

sub easy_dhcp {
    my ($net, $modules_conf) = @_;

    return if text2bool($net->{network}{NETWORKING});

    require modules;
    require network::ethernet;
    modules::load_category($modules_conf, list_modules::ethernet_categories());
    my @all_dev = sort map { $_->[0] } network::ethernet::get_eth_cards($modules_conf);

    #- only for a single ethernet network card
    my @ether_dev = grep { /^eth[0-9]+$/ && `LC_ALL= LANG= $::prefix/sbin/ip -o link show $_ 2>/dev/null` =~ m|\slink/ether\s| } @all_dev;
    @ether_dev == 1 or return;

    my $dhcp_intf = $ether_dev[0];
    log::explanations("easy_dhcp: found $dhcp_intf");

    put_in_hash($net->{network}, {
				  NETWORKING => "yes",
				  DHCP => "yes",
				  NET_DEVICE => $dhcp_intf,
				  NET_INTERFACE => $dhcp_intf,
				 });
    $net->{ifcfg}{$dhcp_intf} ||= {};
    put_in_hash($net->{ifcfg}{$dhcp_intf}, {
				      DEVICE => $dhcp_intf,
				      BOOTPROTO => 'dhcp',
				      NETMASK => '255.255.255.0',
				      ONBOOT => 'yes'
				     });
    $net->{type} = 'lan';
    $net->{net_interface} = $dhcp_intf;

    1;
}

sub configure_network {
    my ($net, $in, $modules_conf) = @_;
    if (!$::testing) {
        require network::ethernet;
        network::ethernet::configure_eth_aliases($modules_conf);

        write_network_conf($net);
        write_resolv_conf($net);
        if ($::isInstall && ! -e "/etc/resolv.conf") {
            #- symlink resolv.conf in install root too so that updates and suppl media can be added
            symlink "$::prefix/etc/resolv.conf", "/etc/resolv.conf";
        }
        foreach (keys %{$net->{ifcfg}}) {
            write_interface_conf($net, $_);
            my $ssid = $net->{ifcfg}{$_}{WIRELESS_ESSID} or next;
            write_wireless_conf($ssid, $net->{ifcfg}{$_});
        }
        network::ethernet::install_dhcp_client($in, $_->{DHCP_CLIENT}) foreach grep { $_->{BOOTPROTO} eq "dhcp" } values %{$net->{ifcfg}};
        add2hosts("localhost", "127.0.0.1");
        add2hosts($net->{network}{HOSTNAME}, "127.0.0.1") if $net->{network}{HOSTNAME};
        write_zeroconf($net, $in);

        any { $_->{BOOTPROTO} =~ /^(pump|bootp)$/ } values %{$net->{ifcfg}} and $in->do_pkgs->install('pump');

        #- update interfaces list in shorewall
        require network::shorewall;
        my $shorewall = network::shorewall::read();
        $shorewall && !$shorewall->{disabled} and network::shorewall::write($shorewall);

        $net->{network}{HOSTNAME} && !$::isInstall and sethostname($net);
    }

    #- make net_applet reload the configuration
    my $pid = chomp_(`pidof -x net_applet`);
    $pid and kill 1, $pid;
}

1;
