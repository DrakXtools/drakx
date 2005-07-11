package network::activefw;

use Gtk2::Helper;
use Socket;

sub new {
    my ($type, $filter) = @_;

    require Net::DBus;
    my $bus = Net::DBus->system;
    my $con = $bus->{connection};

    $con->add_filter($filter);
    $con->add_match("type='signal',interface='com.mandrakesoft.activefirewall'");

    set_DBus_watch($con);
    $con->dispatch;

    my $o = bless { bus => $bus }, $type;
    $o->find_daemon;

    $o;
}

sub find_daemon {
    my ($o) = @_;
    my $service = $o->{bus}->get_service("com.mandrakesoft.activefirewall.daemon");
    $o->{daemon} = $service->get_object("/com/mandrakesoft/activefirewall", "com.mandrakesoft.activefirewall.daemon");
}

sub set_DBus_watch {
    my ($con) = @_;
    $con->set_watch_callbacks(sub {
        my ($con, $watch) = @_;
        my $flags = $watch->get_flags;
        require Net::DBus::Binding::Watch;
        if ($flags & &Net::DBus::Binding::Watch::READABLE) {
            Gtk2::Helper->add_watch($watch->get_fileno, 'in', sub {
                $watch->handle(&Net::DBus::Binding::Watch::READABLE);
                $con->dispatch;
                1;
            });
        }
        #- do nothing for WRITABLE watch, we dispatch when needed
    }, undef, undef); #- do nothing when watch is disabled or toggled yet
}

sub dispatch {
    my ($o) = @_;
    $o->{bus}{connection}->dispatch;
}

sub call_method {
    my ($o, $method, @args) = @_;
    my @ret;
    eval {
        @ret = $o->{daemon}->$method(@args);
    };
    if ($@) {
        print "($method) exception: $@\n";
        $o->dispatch;
        return;
    }
    @ret;
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
    inet_ntoa(pack('N', $addr));
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
