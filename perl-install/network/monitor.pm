package network::monitor;

use common;
use dbus_object;

our @ISA = qw(dbus_object);

sub new {
    my ($type, $bus) = @_;
    dbus_object::new($type,
		       $bus,
		       "com.mandriva.monitoring",
		       "/com/mandriva/monitoring/wireless",
		       "com.mandriva.monitoring.wireless");
}

sub list_wireless {
    my ($o) = @_;
    my $results;
    eval { $results = $o->call_method('ScanResults') };
    my %networks;
    #- bssid / frequency / signal level / flags / ssid
    while ($results =~ /^((?:[0-9a-f]{2}:){5}[0-9a-f]{2})\t(\d+)\t(\d+)\t(.*?)\t(.*)$/mg) {
        $networks{$1} = { frequency => $2, signal_level => $3, flags => $4, ssid => $5 };
        $networks{$1}{approx_level} = 20 + min(80, int($3/20)*20);
    }
    my $list;
    eval { $list = $o->call_method('ListNetworks') };
    #- network id / ssid / bssid / flags
    while ($list =~ /^(\d+)\t(.*?)\t(.*?)\t(.*)$/mg) {
        if (my $net = $networks{$3} || find { $_->{ssid} eq $2 } values(%networks)) {
            $net->{id} = $1;
            $net->{ssid} ||= $2;
            $net->{current} = to_bool($4 eq '[CURRENT]');
        }
    }
    \%networks;
}

sub select_network {
    my ($o, $id) = @_;
    $networks = $o->call_method('SelectNetwork',
                                Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $id));
}

1;
