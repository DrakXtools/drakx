package network::monitor;

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
    my $networks;
    eval { $networks = $o->call_method('ListWireless') };
    my %networks;
    while ($networks =~ /^((?:[0-9a-f]{2}:){5}[0-9a-f]{2})\t(\d+)\t(\d+)\t(.*?)\t(.*)$/mg) {
        $networks{$1} = { frequency => $2, signal_level => $3, flags => $4, ssid => $5 };
    }
    \%networks;
}

1;
