package activefw;

use Net::DBus;
use Net::DBus::Binding::Watch;
use Gtk2::Helper;
use POSIX qw(strftime);
use Socket;

sub new {
    my ($type, $filter) = @_;

    my $bus = Net::DBus->system;
    my $con = $bus->{connection};

    $con->add_filter($filter);
    $con->add_match("type='signal',interface='com.mandrakesoft.activefirewall'");

    set_DBus_watch($con);
    $con->dispatch;

    my $o = bless {
        bus => $bus,
        daemon => $daemon
    }, $type;

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

sub get_mode {
    my ($o) = @_;
    my $mode;
    eval {
        $mode = $o->{daemon}->GetMode;
    };
    if ($@) {
        print "(GetMode) exception: $@\n";
        $o->dispatch;
        return;
    }
    $mode;
}

sub blacklist {
    my ($o, $seq, $blacklist) = @_;
    eval {
        $o->{daemon}->Blacklist(Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $seq),
                                Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $blacklist));
    };
    if ($@) {
        print "(Blacklist) exception: $@\n";
        $o->dispatch;
    }
}

sub unblacklist {
    my ($o, $addr) = @_;
    eval {
        $o->{daemon}->UnBlacklist(Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
    };
    if ($@) {
        print "(Blacklist) exception: $@\n";
        $o->dispatch;
    }
}

sub whitelist {
    my ($o, $addr) = @_;
    eval {
        $o->{daemon}->Whitelist(Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
    };
    if ($@) {
        print "(Whitelist) exception: $@\n";
        $o->dispatch;
    }
}

sub unwhitelist {
    my ($o, $addr) = @_;
    eval {
        $o->{daemon}->UnWhitelist(Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $addr));
    };
    if ($@) {
        print "(UnWhitelist) exception: $@\n";
        $o->dispatch;
    }
}

sub set_interactive {
    my ($o, $mode) = @_;
    print "setting new IDS mode: $mode\n";
    eval {
        $o->{daemon}->SetMode(Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $mode));
    };
    if ($@) {
        print "(SetMode) exception: $@\n";
        $o->dispatch;
    }
}

sub get_blacklist {
    my ($o) = @_;
    my @blacklist;
    eval {
        @blacklist = $o->{daemon}->GetBlacklist;
    };
    if ($@) {
        print "(GetBlacklist) exception: $@\n";
        $o->dispatch;
        return;
    }
    @blacklist;
}

sub get_whitelist {
    my ($o) = @_;
    my @whitelist;
    eval {
        @whitelist = $o->{daemon}->GetWhitelist;
    };
    if ($@) {
        print "(GetWhitelist) exception: $@\n";
        $o->dispatch;
        return;
    }
    @whitelist;
}

sub format_date {
    my ($timestamp) = @_;
    strftime("%c", localtime($timestamp));
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
