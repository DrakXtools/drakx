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
use any;
use vars qw(@ISA @EXPORT);
use log;

@ISA = qw(Exporter);
@EXPORT = qw(add2hosts addDefaultRoute configureNetwork2 dns dnsServers findIntf gateway guessHostname is_ip is_ip_forbidden masked_ip netmask read_all_conf read_conf read_interface_conf read_resolv_conf resolv sethostname write_conf write_resolv_conf);

#-######################################################################################
#- Functions
#-######################################################################################
sub read_conf {
    my ($file) = @_;
    +{ getVarsFromSh($file) };
}

sub read_resolv_conf_raw {
    my ($o_file) = @_;
    my $s = cat_($o_file || "$::prefix/etc/resolv.conf");
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

sub read_dhcpd_conf {
    my ($o_file) = @_;
    my $s = cat_($o_file || "$::prefix/etc/dhcpd.conf");
    { option_routers => [ $s =~ /^\s*option routers\s+(\S+);/mg ],
      subnet_mask => [ if_($s =~ /^\s*option subnet-mask\s+(.*);/mg, split(' ', $1)) ],
      domain_name => [ if_($s =~ /^\s*option domain-name\s+"(.*)";/mg, split(' ', $1)) ],
      domain_name_servers => [ if_($s =~ /^\s*option domain-name-servers\s+(.*);/m, split(' ', $1)) ],
      dynamic_bootp => [ if_($s =~ /^\s*range dynamic-bootp\s+\S+\.(\d+)\s+\S+\.(\d+)\s*;/m, split(' ', $1)) ],
      default_lease_time => [ if_($s =~ /^\s*default-lease-time\s+(.*);/m, split(' ', $1)) ],
      max_lease_time => [ if_($s =~ /^\s*max-lease-time\s+(.*);/m, split(' ', $1)) ] };
}

sub read_squid_conf {
    my ($o_file) = @_;
    my $s = cat_($o_file || "$::prefix/etc/squid/squid.conf");
    { http_port => [ $s =~ /^\s*http_port\s+(.*)/mg ],
      cache_size => [ if_($s =~ /^\s*cache_dir diskd\s+(.*)/mg, split(' ', $1)) ],
      admin_mail => [ if_($s =~ /^\s*err_html_text\s+(.*)/mg, split(' ', $1)) ] };
}

sub read_tmdns_conf() {
    my $file = "$::prefix/etc/tmdns.conf";
    cat_($file) =~ /^\s*hostname\s*=\s*(\w+)/m && { ZEROCONF_HOSTNAME => $1 };
}

sub write_conf {
    my ($netc) = @_;
    my $file = "$::prefix/etc/sysconfig/network";

    if ($netc->{HOSTNAME} && $netc->{HOSTNAME} =~ /\.(.+)$/) {
	$netc->{DOMAINNAME} = $1;
    }
    $netc->{NETWORKING} = 'yes';

    setVarsInSh($file, $netc, qw(HOSTNAME NETWORKING GATEWAY GATEWAYDEV NISDOMAIN));
}

sub write_zeroconf {
    my ($file, $zhostname) = @_;
    eval { substInFile { s/^\s*(hostname)\s*=.*/$1 = $zhostname/ } $file };
}

sub write_resolv_conf {
    my ($file, $netc) = @_;

    my %new = (
        search => [ grep { $_ } uniq(@$netc{'DOMAINNAME', 'DOMAINNAME2', 'DOMAINNAME3'}) ],
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

sub write_interface_conf {
    my ($file, $intf, $_netc, $_prefix) = @_;

    require network::ethernet;
    my (undef, $mac_address) = network::ethernet::get_eth_card_mac_address($intf->{DEVICE}); 
    $intf->{HWADDR} &&= $mac_address; #- set HWADDR to MAC address if required

    my @ip = split '\.', $intf->{IPADDR};
    my @mask = split '\.', $intf->{NETMASK};

    add2hash($intf, {
		     BROADCAST => join('.', mapn { int($_[0]) | ((~int($_[1])) & 255) } \@ip, \@mask),
		     NETWORK   => join('.', mapn { int($_[0]) &        $_[1]          } \@ip, \@mask),
		     ONBOOT => bool2yesno(!member($intf->{DEVICE}, map { $_->{device} } detect_devices::pcmcia_probe())),
		    });

    defined($intf->{METRIC}) or $intf->{METRIC} = network::tools::get_default_metric(network::tools::get_interface_type($intf)),
    $intf->{BOOTPROTO} =~ s/dhcp.*/dhcp/;

    if (local $intf->{WIRELESS_ENC_KEY} = $intf->{WIRELESS_ENC_KEY}) {
        network::tools::convert_wep_key_for_iwconfig($intf->{WIRELESS_ENC_KEY});
    }

    setVarsInSh($file, $intf, qw(DEVICE BOOTPROTO IPADDR NETMASK NETWORK BROADCAST ONBOOT HWADDR METRIC MII_NOT_SUPPORTED TYPE), 
                qw(WIRELESS_MODE WIRELESS_ESSID WIRELESS_NWID WIRELESS_FREQ WIRELESS_SENS WIRELESS_RATE WIRELESS_ENC_KEY WIRELESS_RTS WIRELESS_FRAG WIRELESS_IWCONFIG WIRELESS_IWSPY WIRELESS_IWPRIV),
                if_($intf->{BOOTPROTO} eq "dhcp", qw(DHCP_HOSTNAME NEEDHOSTNAME)),
                if_($intf->{DEVICE} =~ /^ippp\d+$/, qw(DIAL_ON_IFUP))
               );
    substInFile { s/^DEVICE='(`.*`)'/DEVICE=$1/g } $file; #- remove quotes if DEVICE is the result of a command

    chmod $intf->{WIRELESS_ENC_KEY} ? 0700 : 0755, $file; #- hide WEP key for non-root users
    log::explanations("written $intf->{DEVICE} interface configuration in $file");
}

sub add2hosts {
    my ($file, $hostname, @ips) = @_;
    my ($sub_hostname) = $hostname =~ /(.*?)\./;

    my %l;
    foreach (cat_($file)) {
        my ($ip, $aliases) = /^\s*(\S+)\s+(\S+.*)$/ or next;
        push @{$l{$ip}}, difference2([ split /\s+/, $aliases ], [ $hostname, $sub_hostname ]);
    } cat_($file);

    push @{$l{$_}}, $hostname, if_($sub_hostname, $sub_hostname) foreach grep { $_ } @ips;

    log::explanations("writing host information to $file");
    output($file, map { "$_\t\t" . join(" ", @{$l{$_}}) . "\n" } keys %l);
}

# The interface/gateway needs to be configured before this will work!
sub guessHostname {
    my ($_prefix, $netc, $intf) = @_;

    $intf->{isUp} && dnsServers($netc) or return 0;
    $netc->{HOSTNAME} && $netc->{DOMAINNAME} and return 1;

    write_resolv_conf("$::prefix/etc/resolv.conf", $netc);

    my $name = gethostbyaddr(Socket::inet_aton($intf->{IPADDR}), Socket::AF_INET()) or log::explanations("reverse name lookup failed"), return 0;

    log::explanations("reverse name lookup worked");

    add2hash($netc, { HOSTNAME => $name });
    1;
}

sub addDefaultRoute {
    my ($netc) = @_;
    c::addDefaultRoute($netc->{GATEWAY}) if $netc->{GATEWAY};
}

sub sethostname {
    my ($netc) = @_;
    my $text;
    syscall_("sethostname", $netc->{HOSTNAME}, length $netc->{HOSTNAME}) ? ($text="set sethostname to $netc->{HOSTNAME}") : ($text="sethostname failed: $!");
    log::explanations($text);

    if (!$::isInstall) {
      run_program::run("/usr/bin/run-parts", "--arg", $netc->{HOSTNAME}, "/etc/sysconfig/network-scripts/hostname.d");
    }
}

sub resolv($) {
    my ($name) = @_;
    is_ip($name) and return $name;
    my $a = join(".", unpack "C4", (gethostbyname $name)[4]);
    #-log::explanations("resolved $name in $a");
    $a;
}

sub dnsServers {
    my ($netc) = @_;
    my %used_dns; @used_dns{$netc->{dnsServer}, $netc->{dnsServer2}, $netc->{dnsServer3}} = (1, 2, 3);
    sort { $used_dns{$a} <=> $used_dns{$b} } grep { $_ } keys %used_dns;
}

sub findIntf {
    my ($intf, $device) = @_;
    $intf->{$device}{DEVICE} = undef;
    $intf->{$device};
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

sub miscellaneous_choose {
    my ($in, $u) = @_;

    $in->ask_from('',
       N("Proxies configuration"),
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
    setExportedVarsInSh("$::prefix/etc/profile.d/proxy.sh",  $u, qw(http_proxy ftp_proxy));
    chmod 0755, "$::prefix/etc/profile.d/proxy.sh";
    setExportedVarsInCsh("$::prefix/etc/profile.d/proxy.csh", $u, qw(http_proxy ftp_proxy));
    chmod 0755, "$::prefix/etc/profile.d/proxy.csh";

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

sub read_all_conf {
    my ($_prefix, $netc, $intf, $o_netcnx) = @_;
    $netc ||= {}; $intf ||= {};
    my $netcnx = $o_netcnx || {};
    add2hash($netc, read_conf("$::prefix/etc/sysconfig/network")) if -r "$::prefix/etc/sysconfig/network";
    add2hash($netc, read_resolv_conf());
    add2hash($netc, read_tmdns_conf());
    foreach (all("$::prefix/etc/sysconfig/network-scripts")) {
	my ($device) = /^ifcfg-([A-Za-z0-9.:]+)$/;
	next if $device =~ /.rpmnew$|.rpmsave$/;
	if ($device && $device ne 'lo') {
	    my $intf = findIntf($intf, $device);
	    add2hash($intf, { getVarsFromSh("$::prefix/etc/sysconfig/network-scripts/$_") });
	    $intf->{DEVICE} ||= $device;
	    $intf->{WIRELESS_ENC_KEY} = network::tools::get_wep_key_from_iwconfig($intf->{WIRELESS_ENC_KEY});
	}
    }
    if (my $default_intf = network::tools::get_default_gateway_interface($netc, $intf)) {
        $netcnx->{type} ||= network::tools::get_interface_type($intf->{$default_intf});
    }
}

#- FIXME: this is buggy, use network::tools::get_default_gateway_interface
sub probe_netcnx_type {
    my ($_prefix, $_netc, $intf, $netcnx) = @_;
    #- try to probe $netcnx->{type} which is used almost everywhere.
    unless ($netcnx->{type}) {
	#- ugly hack to determine network type (avoid saying not configured in summary).
	-e "$::prefix/etc/ppp/peers/adsl" and $netcnx->{type} ||= 'adsl'; # enough ?
	-e "$::prefix/etc/ppp/ioptions1B" || -e "$::prefix/etc/ppp/ioptions2B" and $netcnx->{type} ||= 'isdn'; # enough ?
	$intf->{ppp0} and $netcnx->{type} ||= 'modem';
	$intf->{eth0} and $netcnx->{type} ||= 'lan';
    }
}

sub easy_dhcp {
    my ($modules_conf, $netc, $intf) = @_;

    return if text2bool($netc->{NETWORKING});

    require modules;
    require network::ethernet;
    modules::load_category($modules_conf, list_modules::ethernet_categories());
    my @all_dev = sort map { $_->[0] } network::ethernet::get_eth_cards($modules_conf);

    #- only for a single ethernet network card
    my @ether_dev = grep { /^eth[0-9]+$/ && `LC_ALL= LANG= $::prefix/sbin/ip -o link show $_ 2>/dev/null` =~ m|\slink/ether\s| } @all_dev;
    @ether_dev == 1 or return;

    my $dhcp_intf = $ether_dev[0];
    log::explanations("easy_dhcp: found $dhcp_intf");

    put_in_hash($netc, {
			NETWORKING => "yes",
			DHCP => "yes",
			NET_DEVICE => $dhcp_intf,
			NET_INTERFACE => $dhcp_intf,
		       });
    $intf->{$dhcp_intf} ||= {};
    put_in_hash($intf->{$dhcp_intf}, {
				      DEVICE => $dhcp_intf,
				      BOOTPROTO => 'dhcp',
				      NETMASK => '255.255.255.0',
				      ONBOOT => 'yes'
				     });
    1;
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
    my ($in, $modules_conf, $_prefix, $netc, $intf) = @_;
    my $etc = "$::prefix/etc";
    if (!$::testing) {
        require network::ethernet;
        network::ethernet::update_iftab();
        network::ethernet::configure_eth_aliases($modules_conf);

        $netc->{wireless_eth} and $in->do_pkgs->ensure_binary_is_installed('wireless-tools', 'iwconfig', 'auto');
        write_conf($netc);
        write_resolv_conf("$etc/resolv.conf", $netc) unless $netc->{DHCP};
        if ($::isInstall && ! -e "/etc/resolv.conf") {
            #- symlink resolv.conf in install root too so that updates and suppl media can be added
            symlink "$etc/resolv.conf", "/etc/resolv.conf";
        }
        foreach (grep { !/^ppp\d+/ } keys %$intf) {
	    unlink("$etc/sysconfig/network-scripts/$_");
	    write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_", $intf->{$_}, $netc, $::prefix);
	}
        add2hosts("$etc/hosts", $netc->{HOSTNAME}, "127.0.0.1") if $netc->{HOSTNAME};
        add2hosts("$etc/hosts", "localhost", "127.0.0.1");

        any { $_->{BOOTPROTO} eq "dhcp" } values %$intf and $in->do_pkgs->install($netc->{dhcp_client} || 'dhcp-client');
        if ($netc->{ZEROCONF_HOSTNAME}) {
            $in->do_pkgs->ensure_binary_is_installed('tmdns', 'tmdns', 'auto') if !$in->do_pkgs->is_installed('bind');
            $in->do_pkgs->ensure_binary_is_installed('zcip', 'zcip', 'auto');
            write_zeroconf("$etc/tmdns.conf", $netc->{ZEROCONF_HOSTNAME});
	    require services;
            services::start_service_on_boot("tmdns");
            services::restart("tmdns");
        } else {
            #- disable zeroconf
            require services;
            #- write blank hostname so that drakconnect does not assume zeroconf is enabled
            -f "$etc/tmdns.conf" and write_zeroconf("$etc/tmdns.conf", '');
            if (-f "$etc/rc.d/init.d/tmdns") {
                services::stop("tmdns");
                services::do_not_start_service_on_boot("tmdns");
            }
        }
        any { $_->{BOOTPROTO} =~ /^(pump|bootp)$/ } values %$intf and $in->do_pkgs->install('pump');
    }
}

1;
