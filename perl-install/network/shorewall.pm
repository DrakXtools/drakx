package network::shorewall; # $Id$




use detect_devices;
use network::netconnect;
use network::ethernet;
use network::network;
use run_program;
use common;
use log;


sub check_iptables {
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
    my $netcnx = {};
    my $netc = {};
    my $intf = {};
    network::netconnect::read_net_conf($netcnx, $netc, $intf);
    network::tools::get_default_gateway_interface($netc, $intf);
}

sub get_shorewall_interface() {
    my $default_dev = get_ifcfg_interface();
    $default_dev =~ /^ippp/ && "ippp+" ||
    $default_dev =~ /^ppp/ && "ppp+" ||
    $default_dev;
}

sub ask_shorewall_interface {
    my ($in, $interface) = @_;
    my $modules_conf = modules::any_conf->read;
    my @all_cards = network::ethernet::get_eth_cards($modules_conf);
    my %net_devices = network::ethernet::get_eth_cards_names(@all_cards);
    put_in_hash(\%net_devices, { 'ppp+' => 'ppp+', 'ippp+' => 'ippp+' });

    $in->ask_from('',
		  N("Please enter the name of the interface connected to the internet.

Examples:
		ppp+ for modem or DSL connections, 
		eth0, or eth1 for cable connection, 
		ippp+ for a isdn connection.
"),
		  [ { label => N("Net Device"), val => \$interface, list => [ sort keys %net_devices ], format => sub { $net_devices{$_[0]} || $_[0] }, not_edit => 0 } ]);
    $interface;
}

sub read_default_interfaces {
    my ($conf, $o_in) = @_;
    my $interface = get_shorewall_interface();
    $o_in and $interface = ask_shorewall_interface($o_in, $interface);
    $conf->{net_interface} = $interface;
    $conf->{loc_interface} = [  grep { $_ ne $interface } detect_devices::getNet() ];
}

sub read {
    my ($o_in) = @_;
    my %conf = (disabled => !glob_("$::prefix/etc/rc3.d/S*shorewall"),
                ports => join(' ', map {
                    my $e = $_;
                    map { "$_/$e->[3]" } split(',', $e->[4]);
                } grep { $_->[0] eq 'ACCEPT' && $_->[1] eq 'net' } get_config_file('rules'))
               );

    if (my ($e) = get_config_file('masq')) {
	$conf{masquerade}{subnet} = $e->[1] if $e->[1];
    }
    read_default_interfaces(\%conf, $o_in);
    $conf{net_interface} && \%conf;
}

sub write {
    my ($conf) = @_;
    my $default_intf = get_ifcfg_interface();
    my $use_pptp = $default_intf =~ /^ppp/ && cat_("$::prefix/etc/ppp/peers/$default_intf") =~ /pptp/;
    my $squid_port = network::network::read_squid_conf()->{http_port}[0];

    my %ports_by_proto;
    foreach (split ' ', $conf->{ports}) {
	m!^(\d+(:\d+)?)/(udp|tcp|icmp)$! or die "bad port $_\n";
	push @{$ports_by_proto{$3}}, $1;
    }

    set_config_file("zones", 
		    [ 'net', 'Net', 'Internet zone' ],
		    if_($conf->{loc_interface}[0], [ 'loc', 'Local', 'Local' ]),
		   );
    set_config_file('interfaces',
		    [ 'net', $conf->{net_interface}, 'detect' ],
		    (map { [ 'loc', $_, 'detect' ] } @{$conf->{loc_interface} || []}),
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
		    (map { 
			map_each { [ 'ACCEPT', $_, 'fw', $::a, join(',', @$::b), '-' ] } %ports_by_proto; 
		    } ('net', if_($conf->{loc_interface}[0], 'loc'))),
		   );
		   if (cat_("/etc/shorewall/rules") !~ /^\s*REDIRECT\s*loc\s*$squid_port\s+(\S+)/mg && $squid_port && -f "/var/run/squid.pid" && grep { /Loc/i } cat_("/etc/shorewall/zones")) {
	substInFile {
		s/#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE/REDIRECT\tloc\t$squid_port\ttcp\twww\t-\nACCEPT\tfw\tnet\ttcp\twww\n#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE/;
	} "/etc/shorewall/rules";
}
    set_config_file('masq', if_($conf->{masquerade}, [ $conf->{net_interface}, $conf->{masquerade}{subnet} ]));

    services::set_status('shorewall', !$conf->{disabled}, $::isInstall);
}

1;

