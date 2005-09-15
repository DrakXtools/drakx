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
    my ($monitor, $o_intf) = @_;
    my ($results, $list, %networks);
    #- first try to use mandi
    eval {
        $results = $monitor->call_method('ScanResults');
        $list = $monitor->call_method('ListNetworks');
    };
    my $has_roaming = defined $results && defined $list;
    #- try wpa_cli if we're root
    if ($@ && !$>) {
        $results = run_program::get_stdout('/usr/sbin/wpa_cli', '2>', '/dev/null', 'scan_results');
        $list = run_program::get_stdout('/usr/sbin/wpa_cli', '2>', '/dev/null', 'list_networks');
    }
    if (defined $results && defined $list) {
        #- bssid / frequency / signal level / flags / ssid
        while ($results =~ /^((?:[0-9a-f]{2}:){5}[0-9a-f]{2})\t(\d+)\t(\d+)\t(.*?)\t(.*)$/mg) {
            # wpa_supplicant may list the network two times, use ||=
            $networks{$1}{frequency} ||= $2;
            $networks{$1}{signal_level} ||= $3;
            $networks{$1}{flags} ||= $4;
            $networks{$1}{essid} ||= $5 if $5 ne '<hidden>';
        }
        #- network id / ssid / bssid / flags
        while ($list =~ /^(\d+)\t(.*?)\t(.*?)\t(.*)$/mg) {
            if (my $net = $networks{$3} || find { $_->{essid} eq $2 } values(%networks)) {
                $net->{id} = $1;
                $net->{essid} ||= $2;
                $net->{current} = to_bool($4 eq '[CURRENT]');
            }
        }
    } elsif ($o_intf) {
        #- else use iwlist
        my $current_essid = chomp_(run_program::get_stdout('/sbin/iwgetid', '-r', $o_intf));
        my $current_ap = lc(chomp_(run_program::get_stdout('/sbin/iwgetid', '-r', '-a', $o_intf)));
        my @list = run_program::get_stdout('/sbin/iwlist', $o_intf, 'scanning');
        my $net = {};
	foreach (@list) {
            if ((/^\s*$/ || /Cell/) && exists $net->{ap}) {
                $net->{current} = to_bool($net->{essid} eq $current_essid || $net->{ap} eq $current_ap);
                $networks{$net->{ap}} = $net;
                $net = {};
            }
            /Address: (.*)/ and $net->{ap} = lc($1);
            /ESSID:"(.*?)"/ and $net->{essid} = $1;
            /Mode:(\S*)/ and $net->{mode} = $1;
            if (m!Quality[:=](\S*)/!) {
                my $qual = $1;
                $net->{signal_level} = $qual =~ m!/! ? eval($qual)*100 : $qual;
            }
            /Extra:wpa_ie=/ and $net->{flags} = '[WPA]';
            /key:(\S*)\s/ and $net->{flags} ||= $1 eq 'on' && '[WEP]';
	}
    }

    $networks{$_}{approx_level} = 20 + min(80, int($networks{$_}{signal_level}/20)*20) foreach keys %networks;
    (\%networks, $has_roaming);
}

sub select_network {
    my ($o, $id) = @_;
    $o->call_method('SelectNetwork',
                    Net::DBus::Binding::Value->new(&Net::DBus::Binding::Message::TYPE_UINT32, $id));
}

1;
