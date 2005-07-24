package network::tools; # $Id$

use strict;
use common;
use run_program;
use c;
use Socket;

sub write_secret_backend {
    my ($a, $b) = @_;
    foreach my $i ("$::prefix/etc/ppp/pap-secrets", "$::prefix/etc/ppp/chap-secrets") {
	substInFile { s/^'$a'.*\n//; $_ .= "\n'$a' * '$b' * \n" if eof  } $i;
	#- restore access right to secrets file, just in case.
	chmod 0600, $i;
    }
}

sub unquotify {
    my ($word) = @_;
    $$word =~ s/^(['"]?)(.*)\1$/$2/;
}

sub read_secret_backend() {
    my $conf = [];
    foreach my $i ("pap-secrets", "chap-secrets") {
	foreach (cat_("$::prefix/etc/ppp/$i")) {
	    my ($login, $server, $passwd) = split(' ');
	    if ($login && $passwd) {
		unquotify \$passwd;
		unquotify \$login;
		unquotify \$server;
		push @$conf, {login => $login,
			      passwd => $passwd,
			      server => $server };
	    }
	}
    }
    $conf;
}

sub passwd_by_login {
    my ($login) = @_;
    
    unquotify \$login;
    my $secret = read_secret_backend();
    foreach (@$secret) {
	return $_->{passwd} if $_->{login} eq $login;
    }
}

sub wrap_command_for_root {
    my ($name, @args) = @_;
    #- FIXME: duplicate code from common::require_root_capability
    check_for_xserver() && fuzzy_pidofs(qr/\bkwin\b/) > 0 ?
      ("kdesu", "--ignorebutton", "-c", "$name @args") :
      ([ 'consolehelper', $name ], @args);
}

sub run_interface_command {
    my ($command, $intf, $detach) = @_;
    my @command =
      !$> || system("/usr/sbin/usernetctl $intf report") == 0 ?
	($command, $intf) :
	wrap_command_for_root($command, $intf);
    run_program::raw({ detach => $detach, root => $::prefix }, @command);
}

sub start_interface {
    my ($intf, $detach) = @_;
    run_interface_command('/sbin/ifup', $intf, $detach);
}

sub stop_interface {
    my ($intf, $detach) = @_;
    run_interface_command('/sbin/ifdown', $intf, $detach);
}

sub start_net_interface {
    my ($net, $detach) = @_;
    start_interface($net->{net_interface}, $detach);
}

sub stop_net_interface {
    my ($net, $detach) = @_;
    stop_interface($net->{net_interface}, $detach);
}

sub start_ifplugd {
    my ($interface) = @_;
    run_program::run('/sbin/ifplugd', '-b', '-i', $interface);
}

sub stop_ifplugd {
    my ($interface) = @_;
    my $ifplugd = chomp_(cat_("/var/run/ifplugd.$interface.pid"));
    $ifplugd and kill(15, $ifplugd);
    sleep 1;
}

sub connected() { gethostbyname("mandrakesoft.com") ? 1 : 0 }

# request a ref on a bg_connect and a ref on a scalar
sub connected_bg__raw {
    my ($kid_pipe, $status) = @_;
    local $| = 1;
    if (ref($kid_pipe) && ref($$kid_pipe)) {
	my $fd = $$kid_pipe->{fd};
	fcntl($fd, c::F_SETFL(), c::O_NONBLOCK()) or die "can not fcntl F_SETFL: $!";
	my $a  = <$fd>;
     $$status = $a if defined $a;
    } else { $$kid_pipe = check_link_beat() }
}

my $kid_pipe;
sub connected_bg {
    my ($status) = @_;
    connected_bg__raw(\$kid_pipe, $status);
}

# test if connected;
# cmd = 0 : ask current status
#     return : 0 : not connected; 1 : connected; -1 : no test ever done; -2 : test in progress
# cmd = 1 : start new connection test
#     return : -2
# cmd = 2 : cancel current test
#    return : nothing
# cmd = 3 : return current status even if a test is in progress
my $kid_pipe_connect;
my $current_connection_status;

sub test_connected {
    local $| = 1;
    my ($cmd) = @_;
    
    $current_connection_status = -1 if !defined $current_connection_status;
    
    if ($cmd == 0) {
        connected_bg__raw(\$kid_pipe_connect, \$current_connection_status);
    } elsif ($cmd == 1) {
        if ($current_connection_status != -2) {
             $current_connection_status = -2;
             $kid_pipe_connect = check_link_beat();
        }
    } elsif ($cmd == 2) {
        if (defined($kid_pipe_connect)) {
	    kill -9, $kid_pipe_connect->{pid};
	    undef $kid_pipe_connect;
        }
    }
    return $current_connection_status;
}

sub check_link_beat() {
    bg_command->new(sub {
                        require Net::Ping;
                        my $p;
                        if ($>) {
                            $p = Net::Ping->new("tcp");
                            # Try connecting to the www port instead of the echo port
                            $p->{port_num} = getservbyname("http", "tcp");
                        } else {
                            $p = Net::Ping->new("icmp");
                        }
                        print $p->ping("www.mandriva.com") ? 1 : 0;
                    });
}

sub is_dynamic_ip {
  my ($net) = @_;
  any { $_->{BOOTPROTO} !~ /^(none|static|)$/ } values %{$net->{ifcfg}};
}

sub is_dynamic_host {
  my ($net) = @_;
  any { defined $_->{DHCP_HOSTNAME} } values %{$net->{ifcfg}};
}

#- returns interface whose IP address matchs given IP address, according to its network mask
sub find_matching_interface {
    my ($net, $address) = @_;
    my @ip = split '\.', $address;
    find {
        my @intf_ip = split '\.', $net->{ifcfg}{$_}{IPADDR} or return;
        my @mask = split '\.', $net->{ifcfg}{$_}{NETMASK} or return;
        every { $_ } mapn { ($_[0] & $_[2]) == ($_[1] & $_[2]) } \@intf_ip, \@ip, \@mask;
    } sort keys %{$net->{ifcfg}};
}

#- returns gateway interface if found
sub get_default_gateway_interface {
    my ($net) = @_;
    my @intfs = sort keys %{$net->{ifcfg}};
    my $routes = get_routes();
    (find { $routes->{$_}{gateway} } sort keys %$routes) ||
    $net->{network}{GATEWAYDEV} ||
    $net->{network}{GATEWAY} && find_matching_interface($net, $net->{network}{GATEWAY}) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'adsl' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'isdn' && text2bool($net->{ifcfg}{$_}{DIAL_ON_IFUP}) } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'modem' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'wifi' && $net->{ifcfg}{$_}{BOOTPROTO} eq 'dhcp' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'ethernet' && $net->{ifcfg}{$_}{BOOTPROTO} eq 'dhcp' } @intfs);
}

sub get_interface_status {
    my ($intf) = @_;
    my $routes = get_routes();
    return $routes->{$intf}{network}, $routes->{$intf}{gateway};
}

#- returns (gateway_interface, interface is up, gateway address, dns server address)
sub get_internet_connection {
    my ($net, $o_gw_intf) = @_;
    my $gw_intf = $o_gw_intf || get_default_gateway_interface($net) or return;
    return $gw_intf, get_interface_status($gw_intf), $net->{resolv}{dnsServer};
}

sub get_interface_type {
    my ($interface) = @_;
    require detect_devices;
    member($interface->{TYPE}, "xDSL", "ADSL") && "adsl" ||
    $interface->{DEVICE} =~ /^ippp/ && "isdn" ||
    $interface->{DEVICE} =~ /^ppp/ && "modem" ||
    (detect_devices::is_wireless_interface($interface->{DEVICE}) || exists $interface->{WIRELESS_MODE}) && "wifi" ||
    detect_devices::is_lan_interface($interface->{DEVICE}) && "ethernet" ||
    "unknown";
}

sub get_default_metric {
    my ($type) = @_;
    my @known_types = ("ethernet_gigabit", "ethernet", "adsl", "wifi", "isdn", "modem", "unknown");
    my $idx;
    eval { $idx = find_index { $type eq $_ } @known_types };
    $idx = @known_types if $@;
    $idx * 10;
}

sub get_interface_ip_address {
    my ($net, $interface) = @_;
    `/sbin/ip addr show dev $interface` =~ /^\s*inet\s+([\d.]+)/m && $1 ||
    $net->{ifcfg}{$interface}{IPADDR};
}

sub host_hex_to_dotted {
    my ($address) = @_;
    inet_ntoa(pack('N', unpack('L', pack('H8', $address))));
}

sub get_routes() {
    my %routes;
    foreach (cat_("/proc/net/route")) {
	if (/^(\w+)\s+([0-9A-F]+)\s+([0-9A-F]+)\s+[0-9A-F]+\s+\d+\s+\d+\s+(\d+)\s+([0-9A-F]+)/) {
	    if (hex($2)) { $routes{$1}{network} = host_hex_to_dotted($2) }
	    elsif (hex($3)) { $routes{$1}{gateway} = host_hex_to_dotted($3) }
	    elsif ($4) { $routes{$1}{metric} = $4 }
	}
    }
    #- TODO: handle IPv6 with /proc/net/ipv6_route
    \%routes;
}

1;
