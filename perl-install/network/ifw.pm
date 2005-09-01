package network::ifw;

use Socket;
use common;

our @ISA = qw(dbus_object);

sub new {
    my ($type, $bus, $filter) = @_;

    my $con = $bus->{connection};
    $con->add_filter($filter);
    $con->add_match("type='signal',interface='com.mandriva.monitoring.ifw'");

    require dbus_object;
    my $o = dbus_object::new($type,
			     $bus,
			     "com.mandriva.monitoring",
			     "/com/mandriva/monitoring/ifw",
			     "com.mandriva.monitoring.ifw");
    dbus_object::set_gtk2_watch($o);
    $o;
}

sub set_blacklist_verdict {
    my ($o, $seq, $blacklist) = @_;
    $o->call_method('SetBlacklistVerdict',
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
    my ($o, $o_include_processed) = @_;
    $o->call_method('GetReports',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, to_bool($o_include_processed)));
}

sub get_blacklist {
    my ($o) = @_;
    $o->call_method('GetBlacklist');
}

sub get_whitelist {
    my ($o) = @_;
    $o->call_method('GetWhitelist');
}

sub clear_processed_reports {
    my ($o) = @_;
    $o->call_method('ClearProcessedReports');
}

sub send_alert_ack {
    my ($o) = @_;
    $o->call_method('SendAlertAck');
}

sub send_manage_request {
    my ($o) = @_;
    $o->call_method('SendManageRequest');
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

sub get_protocol {
    my ($protocol) = @_;
    getprotobynumber($protocol) || $protocol;
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

sub attack_to_hash {
    my ($args) = @_;
    my $attack = { mapn { $_[0] => $_[1] } [ 'timestamp', 'indev', 'prefix', 'sensor', 'protocol', 'addr', 'port', 'icmp_type', 'seq', 'processed' ], $args };
    $attack->{port} = unpack('S', pack('n', $attack->{port}));
    $attack->{date} = format_date($attack->{timestamp});
    $attack->{ip_addr} = get_ip_address($attack->{addr});
    $attack->{hostname} = resolve_address($attack->{ip_addr});
    $attack->{protocol} = get_protocol($attack->{protocol});
    $attack->{service} = get_service($attack->{port});
    $attack->{type} =
        $attack->{prefix} eq 'SCAN' ? N("Port scanning")
      : $attack->{prefix} eq 'SERV' ? N("Service attack")
      : $attack->{prefix} eq 'PASS' ? N("Password cracking")
      : N(qq("%s" attack), $attack->{prefix});
    $attack->{msg} =
        $attack->{prefix} eq "SCAN" ? N("A port scanning attack has been attempted by %s.", $attack->{hostname})
      : $attack->{prefix} eq "SERV" ? N("The %s service has been attacked by %s.", $attack->{service}, $attack->{hostname})
      : $attack->{prefix} eq "PASS" ? N("A password cracking attack has been attempted by %s.", $attack->{hostname})
      : N(qq(A "%s" attack has been attempted by %s), $attack->{prefix}, $attack->{hostname});
    $attack;
}

1;
