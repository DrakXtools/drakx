package network::shorewall; # $Id$




use detect_devices;
use network::netconnect;
use run_program;
use common;
use log;

my @drakgw_ports = qw(domain bootps http https 631 imap pop3 smtp nntp ntp);
# Ports for CUPS (631), LPD/LPRng (515), SMB (137, 138, 139)
my @internal_ports = qw(631 515 137 138 139);

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

sub default_interfaces_silent {
	my ($_in) = @_;
	my %conf;
	my @l = detect_devices::getNet() or return;
	if (@l == 1) {
	$conf{net_interface} = $l[0];
    } else {
	$conf{net_interface} = network::netconnect::get_net_device() || $l[0];
	$conf{loc_interface} = [  grep { $_ ne $conf{net_interface} } @l ];
    }
    \%conf;
}

sub default_interfaces {
	my ($in) = @_;
	my %conf;
	my $card_netconnect = network::netconnect::get_net_device() || "eth0";
	defined $card_netconnect and log::l("[drakgw] Information from netconnect: ignore card $card_netconnect");

	my @l = detect_devices::getNet() or return;
	$in->ask_from('',
                      N("Please enter the name of the interface connected to the internet.              
                
Examples:
                ppp+ for modem or DSL connections, 
                eth0, or eth1 for cable connection, 
                ippp+ for a isdn connection.
"),
                   [ { label => N("Net Device"), val => \$card_netconnect, list => \@l } ]);
	$conf{net_interface} = $card_netconnect;
	#$conf{net_interface} = network::netconnect::get_net_device() || $l[0];
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
    };
    foreach (get_config_file('interfaces')) {
	my ($name, $interface) = @$_;
	if ($name eq 'masq') {
	    $conf{masquerade}{interface} = $interface;
	    $conf{loc_interface} = [ difference2($conf{loc_interface}, [$interface]) ];
	}
    }
    $conf{net_interface} && \%conf;
}

sub write {
    my ($conf) = @_;
    my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";

    my %ports_by_proto;
    foreach (split ' ', $conf->{ports}) {
	m!^(\d+)/(udp|tcp|icmp)$! or die "bad port $_\n";
	push @{$ports_by_proto{$2}}, $1;
    }

    set_config_file("zones", 
		    [ 'net', 'Net', 'Internet zone' ],
		    if_($conf->{masquerade}, [ 'masq', 'Masquerade', 'Masquerade Local' ]),
		    if_($conf->{loc_interface}, [ 'loc', 'Local', 'Local' ]),
		   );
    set_config_file('interfaces',
		    [ 'net', $conf->{net_interface}, 'detect' ],
		    $conf->{masquerade} ? [ 'masq', $conf->{masquerade}{interface}, 'detect' ] : (),
		    (map { [ 'loc', $_, 'detect' ] } @{$conf->{loc_interface} || []}),
		   );
    set_config_file('policy',
		    if_($conf->{masquerade}, [ 'masq', 'net', 'ACCEPT' ]),
		    if_($conf->{loc_interface}, [ 'loc', 'net', 'ACCEPT' ]),
		    [ 'fw', 'net', 'ACCEPT' ],
		    [ 'net', 'all', 'DROP', 'info' ],
		    [ 'all', 'all', 'REJECT', 'info' ],
		   );
    set_config_file('rules',
    		    if_(cat_("$::prefix$connect_file") =~ /pptp/, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'tcp', '1723' ]),
		    if_(cat_("$::prefix$connect_file") =~ /pptp/, [ 'ACCEPT', 'fw', 'loc:10.0.0.138', 'gre' ]),
		    (map { 
			map_each { [ 'ACCEPT', $_, 'fw', $::a, join(',', @$::b), '-' ] } %ports_by_proto 
		    } ('net', if_($conf->{masquerade}, 'masq'), if_($conf->{loc_interface}, 'loc'))),
		    if_($conf->{masquerade}, map { [ 'ACCEPT', 'masq', 'fw', $_, join(',', @drakgw_ports), '-' ] } 'tcp', 'udp'),
	            if_($conf->{masquerade}, map { [ 'ACCEPT', 'fw', 'masq', $_, join(',', @internal_ports), '-' ] } 'tcp', 'udp'),
		   );
    set_config_file('masq', 
		    $conf->{masquerade} ? [ $conf->{net_interface}, $conf->{masquerade}{subnet} ] : (),
		   );
		   system('uniq /etc/shorewall/masq > /etc/shorewall/masq.uniq');
		   rename("/etc/shorewall/masq.uniq", "/etc/shorewall/masq");
		   
    if ($conf->{disabled}) {
	run_program::rooted($::prefix, 'chkconfig', '--del', 'shorewall');
	run_program::run('service', '>', '/dev/null', 'shorewall', 'stop') if $::isStandalone;
	run_program::run('service', '>', '/dev/null', 'shorewall', 'clear') if $::isStandalone;
    } else {
	run_program::rooted($::prefix, 'chkconfig', '--add', 'shorewall');
	run_program::run('service', '>', '/dev/null', 'shorewall', 'restart') if $::isStandalone;
    }
}

1;

