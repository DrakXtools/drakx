package network::shorewall; # $Id$




use detect_devices;
use network::ethernet;
use network::network;
use run_program;
use common;
use log;


sub check_iptables() {
    -f "$::prefix/etc/sysconfig/iptables" ||
    $::isStandalone && do {
	system('modprobe iptable_nat');
	-x '/sbin/iptables' && listlength(`/sbin/iptables -t nat -nL`) > 8;
    };
}

sub set_config_file {
    my ($file, @l) = @_;

    my $done;
    substInFile {
	if (!$done && (/^#LAST LINE/ || eof)) {
	    $_ = join('', map { join("\t", @$_) . "\n" } @l) . $_;
	    $done = 1;
	} else {
	    $_ = '' if /^[^#]/;
	}
    } "$::prefix/etc/shorewall/$file";
}

sub get_config_file {
    my ($file) = @_;
    map { [ split ' ' ] } grep { !/^#/ } cat_("$::prefix/etc/shorewall/$file");
}

sub get_ifcfg_interface() {
    my $net = {};
    network::network::read_net_conf($net);
    network::tools::get_default_gateway_interface($net);
}

sub get_shorewall_interface() {
    my $default_dev = get_ifcfg_interface();
    $default_dev =~ /^ippp/ && "ippp+" ||
    $default_dev =~ /^ppp/ && "ppp+" ||
    $default_dev;
}

our $ask_shorewall_interface_label = N_("Please enter the name of the interface connected to the internet.

Examples:
		ppp+ for modem or DSL connections, 
		eth0, or eth1 for cable connection, 
		ippp+ for a isdn connection.
");

sub shorewall_interface_choices {
    my ($refval) = @_;
    my $modules_conf = modules::any_conf->read;
    my @all_cards = network::ethernet::get_eth_cards($modules_conf);
    my %net_devices = network::ethernet::get_eth_cards_names(@all_cards);
    put_in_hash(\%net_devices, { 'ppp+' => 'ppp+', 'ippp+' => 'ippp+' });

    [ { label => N("Net Device"), val => $refval, list => [ sort keys %net_devices ], format => sub { $net_devices{$_[0]} || $_[0] }, not_edit => 0 } ];
}

sub read_default_interfaces {
    my ($conf, $o_in) = @_;
    my $interface = get_shorewall_interface();
    $o_in and $o_in->ask_from('', translate($ask_shorewall_interface_label), shorewall_interface_choices(\$interface));
    set_net_interface($conf, $interface);
}

sub set_net_interface {
    my ($conf, $interface) = @_;
    $conf->{net_interface} = $interface;
    $conf->{loc_interface} = [  grep { $_ ne $interface } detect_devices::getNet() ];
}

sub read {
    my ($o_in) = @_;
    my @rules = get_config_file('rules');
    my %conf = (disabled => !glob_("$::prefix/etc/rc3.d/S*shorewall"),
                ports => join(' ', map {
                    my $e = $_;
                    map { "$_/$e->[3]" } split(',', $e->[4]);
                } grep { $_->[0] eq 'ACCEPT' && $_->[1] eq 'net' } @rules),
               );
    $conf{redirects}{$_->[3]}{$_->[2]} = $_->[4] foreach grep { $_->[0] eq 'REDIRECT' } @rules;

    if (my ($e) = get_config_file('masq')) {
	$conf{masq_subnet} = $e->[1];
    }
    read_default_interfaces(\%conf, $o_in);
    $conf{net_interface} && \%conf;
}

sub write {
    my ($conf) = @_;
    my $default_intf = get_ifcfg_interface();
    my $use_pptp = $default_intf =~ /^ppp/ && cat_("$::prefix/etc/ppp/peers/$default_intf") =~ /pptp/;

    my %ports_by_proto;
    foreach (split ' ', $conf->{ports}) {
	m!^(\d+(:\d+)?)/(udp|tcp|icmp)$! or die "bad port $_\n";
	push @{$ports_by_proto{$3}}, $1;
    }

    my $interface_settings = sub {
        my ($zone, $interface) = @_;
        [ $zone, $interface, 'detect', if_(detect_devices::is_bridge_interface($interface), 'routeback') ];
    };

    set_config_file("zones", 
		    [ 'net', 'Net', 'Internet zone' ],
		    if_($conf->{loc_interface}[0], [ 'loc', 'Local', 'Local' ]),
		   );
    set_config_file('interfaces',
                   $interface_settings->('net', $conf->{net_interface}),
                   (map { $interface_settings->('loc', $_) } @{$conf->{loc_interface} || []}),
		   );
    set_config_file('policy',
		    if_($conf->{loc_interface}[0], [ 'loc', 'net', 'ACCEPT' ], [ 'loc', 'fw', 'ACCEPT' ], [ 'fw', 'loc', 'ACCEPT' ]),
		    [ 'fw', 'net', 'ACCEPT' ],
		    [ 'net', 'all', 'DROP', 'info' ],
		    [ 'all', 'all', 'REJECT', 'info' ],
		   );
    set_config_file('rules',
    		    if_($use_pptp, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'tcp', '1723' ]),
		    if_($use_pptp, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'gre' ]),
		    (map_each { [ 'ACCEPT', 'net', 'fw', $::a, join(',', @$::b), '-' ] } %ports_by_proto),
		    (map {
			map_each { [ 'REDIRECT', 'loc', $::a, $_, $::b, '-' ] } %{$conf->{redirects}{$_}};
		    } keys %{$conf->{redirects}}),
		   );
    set_config_file('masq', if_($conf->{masq_subnet}, [ $conf->{net_interface}, $conf->{masq_subnet} ]));

    require services;
    services::set_status('shorewall', !$conf->{disabled}, $::isInstall);
}

1;

