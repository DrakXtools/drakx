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
    my ($file) = @_;
    $file ||= "$::prefix/etc/resolv.conf";
    { nameserver => [ cat_($file) =~ /^\s*nameserver\s+(\S+)/mg ],
      search => [ if_(cat_($file) =~ /^\s*search\s+(.*)/m, split(' ', $1)) ] };
}

sub read_resolv_conf {
    my ($file) = @_;
    my $resolv_conf = read_resolv_conf_raw($file);
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
    my ($file) = @_;
    $file ||= "$::prefix/etc/dhcpd.conf";
    { option_routers => [ cat_($file) =~ /^\s*option routers\s+(\S+);/mg ],
      subnet_mask => [ if_(cat_($file) =~ /^\s*option subnet-mask\s+(.*);/mg, split(' ', $1)) ],
      domain_name => [ if_(cat_($file) =~ /^\s*option domain-name\s+"(.*)";/mg, split(' ', $1)) ],
      domain_name_servers => [ if_(cat_($file) =~ /^\s*option domain-name-servers\s+(.*);/m, split(' ', $1)) ],
      dynamic_bootp => [ if_(cat_($file) =~ /^\s*range dynamic-bootp\s+\S+\.(\d+)\s+\S+\.(\d+)\s*;/m, split(' ', $1)) ],
      default_lease_time => [ if_(cat_($file) =~ /^\s*default-lease-time\s+(.*);/m, split(' ', $1)) ],
      max_lease_time => [ if_(cat_($file) =~ /^\s*max-lease-time\s+(.*);/m, split(' ', $1)) ] };
}

sub read_squid_conf {
    my ($file) = @_;
    $file ||= "$::prefix/etc/squid/squid.conf";
    { http_port => [ cat_($file) =~ /^\s*http_port\s+(.*)/mg ],
      cache_size => [ if_(cat_($file) =~ /^\s*cache_dir diskd\s+(.*)/mg, split(' ', $1)) ],
      admin_mail => [ if_(cat_($file) =~ /^\s*err_html_text\s+(.*)/mg, split(' ', $1)) ] };
}

sub read_tmdns_conf {
    my ($file) = @_;
    local *F; open F, $file or die "cannot open file $file: $!";
    local $_;
    my %outf;

    while (<F>) {
	($outf{ZEROCONF_HOSTNAME}) = /^\s*hostname\s*=\s*(\w+)/ and return \%outf;
    }
    
    \%outf;
}

sub write_conf {
    my ($file, $netc) = @_;

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

    if ($intf->{HWADDR} && -e "$::prefix/sbin/ip") {
	$intf->{HWADDR} = undef;
	if (my $s = `LC_ALL= LANG= $::prefix/sbin/ip -o link show $intf->{DEVICE} 2>/dev/null`) {
	    if ($s =~ m|.*link/ether\s([0-9a-z:]+)\s|) {
		$intf->{HWADDR} = $1;
	    }
	}
    }
    my @ip = split '\.', $intf->{IPADDR};
    my @mask = split '\.', $intf->{NETMASK};

    add2hash($intf, {
		     BROADCAST => join('.', mapn { int($_[0]) | ((~int($_[1])) & 255) } \@ip, \@mask),
		     NETWORK   => join('.', mapn { int($_[0]) &        $_[1]          } \@ip, \@mask),
		     ONBOOT => bool2yesno(!member($intf->{DEVICE}, map { $_->{device} } detect_devices::pcmcia_probe())),
		    });

    $intf->{BOOTPROTO} =~ s/dhcp.*/dhcp/;

    local $intf->{WIRELESS_ENC_KEY} = qq("$intf->{WIRELESS_ENC_KEY}") if $intf->{WIRELESS_ENC_KEY} !~ /"/;
    setVarsInSh($file, $intf, qw(DEVICE BOOTPROTO IPADDR NETMASK NETWORK BROADCAST ONBOOT HWADDR MII_NOT_SUPPORTED), 
                qw(WIRELESS_MODE WIRELESS_ESSID WIRELESS_NWID WIRELESS_FREQ WIRELESS_SENS WIRELESS_RATE WIRELESS_ENC_KEY WIRELESS_RTS WIRELESS_FRAG WIRELESS_IWCONFIG WIRELESS_IWSPY WIRELESS_IWPRIV),
                if_($intf->{BOOTPROTO} eq "dhcp", qw(DHCP_HOSTNAME NEEDHOSTNAME))
               );
    log::explanations("written $intf->{DEVICE} interface configuration in $file");
}

sub add2hosts {
    my ($file, $hostname, @ips) = @_;

    my %l = map { if_(/\s*(\S+)(.*)/, $1 => $2) }
            grep { !/\s+\Q$hostname\E\s*$/ } cat_($file);

    my $sub_hostname = $hostname =~ /(.*?)\./ ? " $1" : '';
    $l{$_} = "\t\t$hostname$sub_hostname" foreach grep { $_ } @ips;

    log::explanations("writing host information to $file");
    output($file, map { "$_$l{$_}\n" } keys %l);
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
    $intf->{$device}{DEVICE} = $device;
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
}

sub read_all_conf {
    my ($_prefix, $netc, $intf, $o_netcnx) = @_;
    $netc ||= {}; $intf ||= {};
    my $netcnx = $o_netcnx || {};
    add2hash($netc, read_conf("$::prefix/etc/sysconfig/network")) if -r "$::prefix/etc/sysconfig/network";
    add2hash($netc, read_resolv_conf());
    add2hash($netc, read_tmdns_conf("$::prefix/etc/tmdns.conf")) if -r "$::prefix/etc/tmdns.conf";
    foreach (all("$::prefix/etc/sysconfig/network-scripts")) {
	if (/^ifcfg-([A-Za-z0-9.:]+)$/ && $1 ne 'lo') {
	    my $intf = findIntf($intf, $1);
	    add2hash($intf, { getVarsFromSh("$::prefix/etc/sysconfig/network-scripts/$_") });
	}
    }
    $netcnx->{type} or probe_netcnx_type($::prefix, $netc, $intf, $netcnx);
}

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
    my ($netc, $intf) = @_;

    return if text2bool($netc->{NETWORKING});

    require modules;
    require network::ethernet;
    modules::load_category('network/main|gigabit|usb');
    my @all_cards = network::ethernet::get_eth_cards();

    #- only for a single network card
    (any { $_->[0] eq 'eth0' } @all_cards) && (every { $_->[0] ne 'eth1' } @all_cards) or return;

    log::explanations("easy_dhcp: found eth0");

    network::ethernet::conf_network_card_backend($netc, $intf, 'dhcp', 'eth0');

    put_in_hash($netc, { 
			NETWORKING => "yes",
			DHCP => "yes",
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
    my ($in, $_prefix, $netc, $intf) = @_;
    my $etc = "$::prefix/etc";
    if (!$::testing) {
        $netc->{wireless_eth} and $in->do_pkgs->ensure_is_installed('wireless-tools', '/sbin/iwconfig', 'auto');
        write_conf("$etc/sysconfig/network", $netc);
        write_resolv_conf("$etc/resolv.conf", $netc) if ! $netc->{DHCP};
        write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_->{DEVICE}", $_, $netc, $::prefix) foreach grep { $_->{DEVICE} ne 'ppp0' } values %$intf;
        add2hosts("$etc/hosts", $netc->{HOSTNAME}, map { $_->{IPADDR} } values %$intf) if $netc->{HOSTNAME} && !$netc->{DHCP};
        add2hosts("$etc/hosts", "localhost", "127.0.0.1");
        
        any { $_->{BOOTPROTO} eq "dhcp" } values %$intf and $in->do_pkgs->install($netc->{dhcp_client} || 'dhcp-client');
        if ($netc->{ZEROCONF_HOSTNAME}) {
            $in->do_pkgs->ensure_is_installed('tmdns', '/sbin/tmdns', 'auto') if !$in->do_pkgs->is_installed('bind');
            $in->do_pkgs->ensure_is_installed('zcip', '/sbin/zcip', 'auto');
            write_zeroconf("$etc/tmdns.conf", $netc->{ZEROCONF_HOSTNAME}); 
        } else { run_program::rooted($::prefix, "chkconfig", "--del", $_) foreach qw(tmdns zcip) }  # disable zeroconf
        any { $_->{BOOTPROTO} =~ /^(pump|bootp)$/ } values %$intf and $in->do_pkgs->install('pump');
    }
}

1;
