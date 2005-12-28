package network::drakfirewall; # $Id$

use strict;
use diagnostics;

use network::shorewall;
use common;

my @all_servers = 
(
  { 
   name => N_("Web Server"),
   pkg => 'apache apache-mod_perl boa',
   ports => '80/tcp 443/tcp',
  },
  {
   name => N_("Domain Name Server"),
   pkg => 'bind',
   ports => '53/tcp 53/udp',
  },
  {
   name => N_("SSH server"),
   pkg => 'openssh-server',
   ports => '22/tcp',
  },
  {
   name => N_("FTP server"),
   pkg => 'ftp-server-krb5 wu-ftpd proftpd pure-ftpd',
   ports => '20/tcp 21/tcp',
  },
  {
   name => N_("Mail Server"),
   pkg => 'sendmail postfix qmail',
   ports => '25/tcp',
  },
  {
   name => N_("POP and IMAP Server"),
   pkg => 'imap courier-imap-pop',
   ports => '109/tcp 110/tcp 143/tcp',
  },
  {
   name => N_("Telnet server"),
   pkg => 'telnet-server-krb5',
   ports => '23/tcp',
   hide => 1,
  },
  {
   name => N_("Windows Files Sharing (SMB)"),
   pkg => 'samba-server',
   ports => '137/tcp 137/udp 138/tcp 138/udp 139/tcp 139/udp 445/tcp 445/udp 1024:1100/tcp 1024:1100/udp',
   hide => 1,
  },
  {
   name => N_("CUPS server"),
   pkg => 'cups',
   ports => '631/tcp 631/udp',
   hide => 1,
  },
  {
   name => N_("Echo request (ping)"),
   ports => '8/icmp',
   force_default_selection => 0,
  },
  {
   name => N_("BitTorrent"),
   ports => '6881:6999/tcp',
   hide => 1,
   pkg => 'bittorrent bittorrent-shadowsclient',
  },
);

my @ifw_rules = (
    {
        name => N_("Port scan detection"),
        ifw_rule => 'psd',
    },
);

sub port2server {
    my ($port) = @_;
    find {
	any { $port eq $_ } split(' ', $_->{ports});
    } @all_servers;
}

sub check_ports_syntax {
    my ($ports) = @_;
    foreach (split ' ', $ports) {
	my ($nb, $range, $nb2) = m!^(\d+)(:(\d+))?/(tcp|udp|icmp)$! or return $_;
	foreach my $port ($nb, if_($range, $nb2)) {
	    1 <= $port && $port <= 65535 or return $_;
	}
	$nb < $nb2 or return $_ if $range;
    }
    '';
}

sub to_ports {
    my ($servers, $unlisted) = @_;
    join(' ', (map { $_->{ports} } @$servers), if_($unlisted, $unlisted));
}

sub from_ports {
    my ($ports) = @_;

    my @l;
    my @unlisted;
    foreach (split ' ', $ports) {
	if (my $s = port2server($_)) {
	    push @l, $s;
	} else {
	    push @unlisted, $_;
	}
    }
    [ uniq(@l) ], join(' ', @unlisted);
}

sub default_from_pkgs {
    my ($do_pkgs) = @_;
    my @pkgs = $do_pkgs->are_installed(map { split ' ', $_->{pkg} } @all_servers);
    [ grep {
	my $s = $_;
	exists $s->{force_default_selection} ? 
	  $s->{force_default_selection} : 
	  any { member($_, @pkgs) } split(' ', $s->{pkg});
    } @all_servers ];
}

sub default_ports {
    my ($do_pkgs) = @_;
    to_ports(default_from_pkgs($do_pkgs), '');
}

sub get_ports() {
    my $shorewall = network::shorewall::read() or return;
    $shorewall->{ports};
}

sub set_ports {
    my ($do_pkgs, $disabled, $ports, $o_in) = @_;

    my $shorewall = network::shorewall::read($o_in) or return;

    if (!$disabled || -x "$::prefix/sbin/shorewall") {
	$do_pkgs->ensure_binary_is_installed('shorewall', 'shorewall', $::isInstall) or return;
    
	$shorewall->{disabled} = $disabled;
	$shorewall->{ports} = $ports;
	log::l($disabled ? "disabling shorewall" : "configuring shorewall to allow ports: $ports");
	network::shorewall::write($shorewall);
    }
}

sub get_conf {
    my ($in, $disabled, $o_ports) = @_;
		
    my $possible_servers = default_from_pkgs($in->do_pkgs);
    $_->{hide} = 0 foreach @$possible_servers;

    if ($o_ports) {
	$disabled, from_ports($o_ports);
    } elsif (my $shorewall = network::shorewall::read()) {
	$shorewall->{disabled}, from_ports($shorewall->{ports});
    } else {
	$in->ask_okcancel('', N("drakfirewall configurator

This configures a personal firewall for this Mandriva Linux machine.
For a powerful and dedicated firewall solution, please look to the
specialized Mandriva Security Firewall distribution."), 1) or return;

	$in->ask_okcancel('', N("drakfirewall configurator

Make sure you have configured your Network/Internet access with
drakconnect before going any further."), 1) or return;

	$disabled, $possible_servers, '';
    }
}

sub choose_allowed_services {
    my ($in, $disabled, $servers, $unlisted) = @_;

    $_->{on} = 0 foreach @all_servers;
    $_->{on} = 1 foreach @$servers;
    my @l = grep { $_->{on} || !$_->{hide} } @all_servers;

    $in->ask_from_({
		    messages => N("Which services would you like to allow the Internet to connect to?"),
		    title => N("Firewall"),
		    icon => 'banner-security',
		    advanced_messages => N("You can enter miscellaneous ports. 
Valid examples are: 139/tcp 139/udp 600:610/tcp 600:610/udp.
Have a look at /etc/services for information."),
		    callbacks => {
			complete => sub {
			    if (my $invalid_port = check_ports_syntax($unlisted)) {
				$in->ask_warn('', N("Invalid port given: %s.
The proper format is \"port/tcp\" or \"port/udp\", 
where port is between 1 and 65535.

You can also give a range of ports (eg: 24300:24350/udp)", $invalid_port));
				return 1;
			    }
			},
		   } },
		  [ 
		   { text => N("Everything (no firewall)"), val => \$disabled, type => 'bool' },
		   (map { { text => translate($_->{name}), val => \$_->{on}, type => 'bool', disabled => sub { $disabled } } } @l),
		   { label => N("Other ports"), val => \$unlisted, advanced => 1, disabled => sub { $disabled } }
		  ]) or return;

    $disabled, [ grep { $_->{on} } @l ], $unlisted;
}

sub set_ifw {
    my ($do_pkgs, $enabled, $rules, $ports) = @_;
    if ($enabled) {
        $do_pkgs->ensure_is_installed('mandi-ifw', '/etc/ifw/start', $::isInstall) or return;

        my $ports_by_proto = network::shorewall::ports_by_proto($ports);
        output_with_perm("$::prefix/etc/ifw/rules", 0644, map { "$_\n" } (
            (map { "source /etc/ifw/rules.d/$_" } @$rules),
            map {
                my $proto = $_;
                map {
                    my $multiport = /:/ && " -m multiport";
                    "iptables -A Ifw -m state --state NEW -p $proto$multiport --dport $_ -j IFWLOG --log-prefix NEW\n";
                } @{$ports_by_proto->{$proto}};
            } keys %$ports_by_proto,
        ));
    }

    my $set_in_file = sub {
        my ($file, @list) = @_;
        substInFile {
            foreach my $l (@list) { s|^$l\n|| }
            $_ .= join("\n", @list) . "\n" if eof && $enabled;
        } "$::prefix/etc/shorewall/$file";
    };
    $set_in_file->('start', "INCLUDE /etc/ifw/start", "INCLUDE /etc/ifw/rules", "iptables -I INPUT 2 -j Ifw");
    $set_in_file->('stop', "iptables -D INPUT -j Ifw", "INCLUDE /etc/ifw/stop");
}

sub choose_watched_services {
    my ($in, $servers, $unlisted) = @_;

    my @l = (@ifw_rules, @$servers, map { { ports => $_ } } split(' ', $unlisted));
    my $enabled = 1;
    $_->{ifw} = 1 foreach @l;

    $in->ask_from_({
        messages =>
          N("Interactive Firewall") . "\n\n" .
          N("You can be warned when someone accesses to a service or tries to intrude into your computer.
Please select which network activity should be watched."),
        title => N("Interactive Firewall"),
    },
                   [
                       { text => N("Use Interactive Firewall"), val => \$enabled, type => 'bool' },
                       map { my $e = $_; {
                           text => (exists $_->{name} ? translate($_->{name}) : $_->{ports}),
                           val => \$_->{ifw},
                           type => 'bool', disabled => sub { !$enabled },
                       } } @l,
                   ]) or return;
    my ($rules, $ports) = partition { exists $_->{ifw_rule} } grep { $_->{ifw} } @l;
    set_ifw($in->do_pkgs, $enabled, [ map { $_->{ifw_rule} } @$rules ], to_ports($ports));
}

sub main {
    my ($in, $disabled) = @_;

    ($disabled, my $servers, my $unlisted) = get_conf($in, $disabled) or return;

    ($disabled, $servers, $unlisted) = choose_allowed_services($in, $disabled, $servers, $unlisted) or return;

    choose_watched_services($in, $servers, $unlisted) unless $disabled;

    my $ports = to_ports($servers, $unlisted);
    set_ports($in->do_pkgs, $disabled, $ports, $in) or return;

    ($disabled, $ports);
}
