package network::tools; # $Id$

use strict;
use common;
use run_program;
use fsedit;
use c;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use MDK::Common::System qw(getVarsFromSh);

@ISA = qw(Exporter);
@EXPORT = qw(connect_backend connected connected_bg disconnect_backend is_dynamic_ip passwd_by_login read_secret_backend test_connected remove_initscript write_secret_backend start_interface stop_interface);

our $connect_prog   = "/etc/sysconfig/network-scripts/net_cnx_pg";
our $connect_file    = "/etc/sysconfig/network-scripts/net_cnx_up";
our $disconnect_file = "/etc/sysconfig/network-scripts/net_cnx_down";

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
    run_program::rooted($::prefix, "ifup $netc->{NET_INTERFACE} &");
}

sub disconnect_backend {
    my ($netc) = @_;
    run_program::rooted($::prefix, "ifdown $netc->{NET_INTERFACE} &");
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

sub start_interface {
    my ($intf) = @_;
    bg_command_as_root('/sbin/ifup', $intf);
}

sub stop_interface {
    my ($intf) = @_;
    bg_command_as_root('/sbin/ifdown', $intf);
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
                        print $p->ping("www.mandrakesoft.com") ? 1 : 0;
                        0;
                    });
}

sub remove_initscript() {
    $::testing and return;
    if (-e "$::prefix/etc/rc.d/init.d/internet") {
        run_program::rooted($::prefix, "/sbin/chkconfig", "--del", "internet");
        rm_rf("$::prefix/etc/rc.d/init.d/internet");
        log::explanations("Removed internet service");
    }
}

sub use_windows {
    my ($file) = @_;
    my $all_hds = fsedit::get_hds(); 
    fs::get_info_from_fstab($all_hds);
    if (my $part = find { $_->{device_windobe} eq 'C' } fs::get::fstab($all_hds)) {
	my $source = find { -d $_ && -r "$_/$file" } map { "$part->{mntpoint}/$_" } qw(windows/system winnt/system windows/system32/drivers winnt/system32/drivers);
	log::explanations("Seek in $source to find firmware");
	$source;
    } else {
	my $failed = N("No partition available");
	log::explanations($failed);
	undef, $failed;
    }
}

sub use_floppy {
    my ($in, $file) = @_;
    my $floppy = detect_devices::floppy();
    $in->ask_okcancel(N("Insert floppy"),
		      N("Insert a FAT formatted floppy in drive %s with %s in root directory and press %s", $floppy, $file, N("Next"))) or return;
    if (eval { fs::mount(devices::make($floppy), '/mnt', 'vfat', 'readonly'); 1 }) {
	log::explanations("Mounting floppy device $floppy in /mnt");
	'/mnt';
    } else {
	my $failed = N("Floppy access error, unable to mount device %s", $floppy);
	log::explanations($failed);
	undef, $failed;
    }
}


sub is_dynamic_ip {
  my ($intf) = @_;
  any { $_->{BOOTPROTO} !~ /^(none|static|)$/ } values %$intf;
}

sub is_dynamic_host {
  my ($intf) = @_;
  any { defined $_->{DHCP_HOSTNAME} } values %$intf;
}

sub convert_wep_key_for_iwconfig {
    #- 5 or 13 characters, consider the key as ASCII and prepend "s:"
    #- else consider the key as hexadecimal, do not strip dashes 
    #- always quote the key as string
    my ($key) = @_;
    member(length($key), (5, 13)) ? "s:$key" : $key;
}

sub get_wep_key_from_iwconfig {
    #- strip "s:" if the key is 5 or 13 characters (ASCII)
    #- else the key as hexadecimal, do not modify
    my ($key) = @_;
    $key =~ s/^s:// if member(length($key), (7,15));
    $key;
}


#- returns interface whose IP address matchs given IP address, according to its network mask
sub find_matching_interface {
    my ($intf, $address) = @_;
    my @ip = split '\.', $address;
    find {
        my @intf_ip = split '\.', $intf->{$_}{IPADDR} or return;
        my @mask = split '\.', $intf->{$_}{NETMASK} or return;
        every { $_ } mapn { ($_[0] & $_[2]) == ($_[1] & $_[2]) } \@intf_ip, \@ip, \@mask;
    } sort keys %$intf;
}

#- returns gateway interface if found
sub get_default_gateway_interface {
    my ($netc, $intf) = @_;
    my @intfs = sort keys %$intf;
    `$::prefix/sbin/ip route show` =~ /^default.*\s+dev\s+(\S+)/m && $1 ||
    $netc->{GATEWAYDEV} ||
    $netc->{GATEWAY} && find_matching_interface($intf, $netc->{GATEWAY}) ||
    (find { get_interface_type($intf->{$_}) eq 'adsl' } @intfs) ||
    (find { get_interface_type($intf->{$_}) eq 'isdn' && text2bool($intf->{$_}{DIAL_ON_IFUP}) } @intfs) ||
    (find { get_interface_type($intf->{$_}) eq 'modem' } @intfs) ||
    (find { get_interface_type($intf->{$_}) eq 'ethernet' && $intf->{$_}{BOOTPROTO} eq 'dhcp' } @intfs);
}

sub get_interface_status {
    my ($gw_intf) = @_;
    my @routes = `$::prefix/sbin/ip route show`;
    my $is_up = to_bool(grep { /\s+dev\s+$gw_intf(?:\s+|$)/ } @routes);
    my ($gw_address) = join('', @routes) =~ /^default\s+via\s+(\S+).*\s+dev\s+$gw_intf(?:\s+|$)/m;
    return $is_up, $gw_address;
}

#- returns (gateway_interface, interface is up, gateway address, dns server address)
sub get_internet_connection {
    my ($netc, $intf, $o_gw_intf) = @_;
    my $gw_intf = $o_gw_intf || get_default_gateway_interface($netc, $intf) or return;
    return $gw_intf, get_interface_status($gw_intf), $netc->{dnsServer};
}

sub get_interface_type {
    my ($interface) = @_;
    member($interface->{TYPE}, "xDSL", "ADSL") && "adsl" ||
    $interface->{DEVICE} =~ /^(eth|ath|wlan)/ && "ethernet" ||
    $interface->{DEVICE} =~ /^ippp/ && "isdn" ||
    $interface->{DEVICE} =~ /^ppp/ && "modem" ||
    "unknown";
}

sub get_default_metric {
    my ($type) = @_;
    my @known_types = ("ethernet_gigabit", "ethernet", "adsl", "isdn", "modem", "unknown");
    my $idx;
    eval { $idx = find_index { $type eq $_ } @known_types };
    $idx = @known_types if $@;
    $idx * 10;
}

sub ndiswrapper_installed_drivers {
    `ndiswrapper -l` =~ /(\w+)\s+driver present/mg;
}

sub ndiswrapper_available_drivers {
    `ndiswrapper -l` =~ /(\w+)\s+driver present, hardware present/mg;
}

1;
