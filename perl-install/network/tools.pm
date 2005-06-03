package network::tools; # $Id$

use strict;
use common;
use run_program;
use c;

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

sub connect_backend {
    my ($netc) = @_;
    run_program::raw({ detach => 1, root => $::prefix }, "/sbin/ifup", $netc->{NET_INTERFACE});
}

sub disconnect_backend {
    my ($netc) = @_;
    run_program::raw({ detach => 1, root => $::prefix }, "/sbin/ifdown", $netc->{NET_INTERFACE});
}

sub bg_command_as_root {
    my ($name, @args) = @_;
    #- FIXME: duplicate code from common::require_root_capability
    if (check_for_xserver() && fuzzy_pidofs(qr/\bkwin\b/) > 0) {
        run_program::raw({ detach => 1 }, "kdesu", "--ignorebutton", "-c", "$name @args");
    } else {
	run_program::raw({ detach => 1 }, [ 'consolehelper', $name ], @args);
    }
}

sub user_run_interface_command {
    my ($command, $intf) = @_;
    if (system("/usr/sbin/usernetctl $intf report") == 0) {
        run_program::raw({ detach => 1 }, $command, $intf);
    } else {
        bg_command_as_root($command, $intf);
    }
}

sub start_interface {
    my ($intf) = @_;
    user_run_interface_command('/sbin/ifup', $intf);
}

sub stop_interface {
    my ($intf) = @_;
    user_run_interface_command('/sbin/ifdown', $intf);
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
    `$::prefix/sbin/ip route show` =~ /^default.*\s+dev\s+(\S+)/m && $1 ||
    $net->{network}{GATEWAYDEV} ||
    $net->{network}{GATEWAY} && find_matching_interface($net, $net->{network}{GATEWAY}) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'adsl' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'isdn' && text2bool($net->{ifcfg}{$_}{DIAL_ON_IFUP}) } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'modem' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'wifi' && $net->{ifcfg}{$_}{BOOTPROTO} eq 'dhcp' } @intfs) ||
    (find { get_interface_type($net->{ifcfg}{$_}) eq 'ethernet' && $net->{ifcfg}{$_}{BOOTPROTO} eq 'dhcp' } @intfs);
}

sub get_interface_status {
    my ($gw_intf) = @_;
    my @routes = `$::prefix/sbin/ip route show`;
    my $is_up = any { /\s+dev\s+$gw_intf(?:\s+|$)/ } @routes;
    my ($gw_address) = join('', @routes) =~ /^default\s+via\s+(\S+).*\s+dev\s+$gw_intf(?:\s+|$)/m;
    return $is_up, $gw_address;
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

1;
