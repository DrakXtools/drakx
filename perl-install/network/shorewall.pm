package network::shorewall; # $Id$




use detect_devices;
use network::netconnect;
use network::ethernet;
use network::network;
use run_program;
use common;
use log;


sub check_iptables {
    my ($in) = @_;

    my $existing_config = -f "$::prefix/etc/sysconfig/iptables";

    $existing_config ||= $::isStandalone && do {
	system('modprobe iptable_nat');
	-x '/sbin/iptables' && listlength(`/sbin/iptables -t nat -nL`) > 8;
    };

    !$existing_config || $in->ask_okcancel(N("Firewalling configuration detected!"),
					   N("Warning! An existing firewalling configuration has been detected. You may need some manual fixes after installation."));
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

sub get_net_device() {
    my $netcnx = {};
    my $netc = {};
    my $intf = {};
    network::netconnect::read_net_conf($netcnx, $netc, $intf);
    my $default_intf = network::tools::get_default_gateway_interface($netc, $intf);
    $default_intf->{DEVICE} =~ /^ippp/ && "ippp+" ||
    $default_intf->{DEVICE} =~ /^ppp/ && "ppp+" ||
    $default_intf->{DEVICE};
}

sub default_interfaces_silent {
	my ($_in) = @_;
	my %conf;
	my @l = detect_devices::getNet() or return;
	if (@l == 1) {
	$conf{net_interface} = $l[0];
    } else {
	$conf{net_interface} = get_net_device() || $l[0];
	$conf{loc_interface} = [  grep { $_ ne $conf{net_interface} } @l ];
    }
    \%conf;
}

sub default_interfaces {
	my ($in) = @_;
	my %conf;
	my $card_netconnect = get_net_device() || "eth0";
	log::l("[drakgw] Information from netconnect: ignore card $card_netconnect");

	my @l = detect_devices::getNet() or return;

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
      [ { label => N("Net Device"), val => \$card_netconnect, list => [ sort keys %net_devices ], format => sub { $net_devices{$_[0]} || $_[0] }, not_edit => 0 } ]);

	$conf{net_interface} = $card_netconnect;
	$conf{loc_interface} = [  grep { $_ ne $conf{net_interface} } @l ];
     \%conf;
}

sub read {
    my ($in, $mode) = @_;
    my %conf = (disabled => !glob_("$::prefix/etc/rc3.d/S*shorewall"),
                ports => join(' ', map {
                    my $e = $_;
                    map { "$_/$e->[3]" } split(',', $e->[4]);
                } grep { $_->[0] eq 'ACCEPT' && $_->[1] eq 'net' } get_config_file('rules'))
               );

    if (my ($e) = get_config_file('masq')) {
	$conf{masquerade}{subnet} = $e->[1] if $e->[1];
    }
    if ($mode eq 'silent') {
	    put_in_hash(\%conf, default_interfaces_silent($in));
    } else {
	    put_in_hash(\%conf, default_interfaces($in));
    }
    $conf{net_interface} && \%conf;
}

sub write {
    my ($conf) = @_;
    my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";
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
		    if_($conf->{loc_interface}[0], [ 'loc', 'net', 'ACCEPT' ], [ 'fw', 'loc', 'ACCEPT' ]),
		    [ 'fw', 'net', 'ACCEPT' ],
		    [ 'net', 'all', 'DROP', 'info' ],
		    [ 'all', 'all', 'REJECT', 'info' ],
		   );
    set_config_file('rules',
    		    if_(cat_("$::prefix$connect_file") =~ /pptp/, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'tcp', '1723' ]),
		    if_(cat_("$::prefix$connect_file") =~ /pptp/, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'gre' ]),
		    (map { 
			map_each { [ 'ACCEPT', $_, 'fw', $::a, join(',', @$::b), '-' ] } %ports_by_proto; 
		    } ('net', if_($conf->{loc_interface}[0], 'loc'))),
		   );
		   if (cat_("/etc/shorewall/rules") !~ /^\s*REDIRECT\s*loc\s*$squid_port\s+(\S+)/mg && $squid_port && -f "/var/run/squid.pid" && grep { /Loc/i } cat_("/etc/shorewall/zones")) {
	substInFile {
		s/#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE/REDIRECT\tloc\t$squid_port\ttcp\twww\t-\nACCEPT\tfw\tnet\ttcp\twww\n#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE/;
	} "/etc/shorewall/rules";
}
    set_config_file('masq', 
		    $conf->{masquerade} ? [ $conf->{net_interface}, $conf->{masquerade}{subnet} ] : (),
		   );
		   
    if ($conf->{disabled}) {
	run_program::rooted($::prefix, 'chkconfig', '--del', 'shorewall');
	run_program::run('service', '>', '/dev/null', 'shorewall', 'stop') if $::isStandalone;
    } else {
	run_program::rooted($::prefix, 'chkconfig', '--add', 'shorewall');
	run_program::run('service', '>', '/dev/null', 'shorewall', 'restart') if $::isStandalone;
    }
}

1;

