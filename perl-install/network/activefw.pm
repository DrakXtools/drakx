package network::activefw;

use dbus_object;
use Socket;

our @ISA = qw(dbus_object);

sub new {
    my ($type, $bus, $filter) = @_;

    my $con = $bus->{connection};
    $con->add_filter($filter);
    $con->add_match("type='signal',interface='com.mandriva.monitoring.activefw'");

    my $o = dbus_object::new($type,
			     $bus,
			     "com.mandriva.monitoring",
			     "/com/mandriva/monitoring/activefw",
			     "com.mandriva.monitoring.activefw");
    dbus_object::set_gtk2_watch($o);
    $o;
}

sub blacklist {
    my ($o, $seq, $blacklist) = @_;
    $o->call_method('Blacklist',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $seq),
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $blacklist));
}

sub unblacklist {
    my ($o, $addr) = @_;
    $o->call_method('UnBlacklist',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
}

sub whitelist {
    my ($o, $addr) = @_;
    $o->call_method('Whitelist',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
}

sub unwhitelist {
    my ($o, $addr) = @_;
    $o->call_method('UnWhitelist',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
}

sub get_interactive {
    my ($o) = @_;
    $o->call_method('GetMode');
}

sub set_interactive {
    my ($o, $mode) = @_;
    $o->call_method('SetMode',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $mode));
}

sub get_reports {
    my ($o) = @_;
    $o->call_method('GetReports');
}

sub get_blacklist {
    my ($o) = @_;
    $o->call_method('GetBlacklist');
}

sub get_whitelist {
    my ($o) = @_;
    $o->call_method('GetWhitelist');
}

sub format_date {
    my ($timestamp) = @_;
    require c;
    c::strftime("%c", localtime($timestamp));
}

sub get_service {
    my ($port) = @_;
    getservbyport($port, undef) || $port;
}

sub get_ip_address {
    my ($addr) = @_;
    inet_ntoa(pack('L', $addr));
}

sub resolve_address {
    my ($ip_addr) = @_;
    #- try to resolve address, timeout after 2 seconds
    my $hostname;
    eval {
        local $SIG{ALRM} = sub { die "ALARM" };
        alarm 2;
        $hostname = gethostbyaddr(inet_aton($ip_addr), AF_INET);
        alarm 0;
    };
    $hostname || $ip_addr;
}

1;
