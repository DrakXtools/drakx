package network::drakfirewall; # $Id$

use diagnostics;
use strict;

use network::shorewall;
use common;

my @all_servers = 
(
  { 
   name => N("Web Server"),
   pkg => 'apache apache-mod_perl boa',
   ports => '80/tcp 443/tcp',
  },
  {
   name => N("Domain Name Server"),
   pkg => 'bind',
   ports => '53/tcp 53/udp',
  },
  {
   name => "SSH",
   pkg => 'openssh-server',
   ports => '22/tcp',
  },
  {
   name => "FTP",
   pkg => 'ftp-server-krb5 wu-ftpd proftpd pure-ftpd',
   ports => '20/tcp 21/tcp',
  },
  {
   name => N("Mail Server"),
   pkg => 'sendmail postfix qmail',
   ports => '25/tcp',
  },
  {
   name => N("POP and IMAP Server"),
   pkg => 'imap courier-imap-pop',
   ports => '109/tcp 110/tcp 143/tcp',
  },
  {
   name => "Telnet",
   pkg => 'telnet-server-krb5',
   ports => '23/tcp',
   hide => 1,
  },
  {
   name => "CUPS",
   pkg => 'cups',
   ports => '631/tcp 631/udp',
   hide => 1,
  },
);

sub port2server {
    my ($port) = @_;
    foreach (@all_servers) {
	return $_ if grep { $port eq $_ } split ' ', $_->{ports};
    }
    undef;
}

sub check_ports_syntax {
    my ($ports) = @_;
    foreach (split ' ', $ports) {
	my ($nb) = m!^(\d+)/(tcp|udp)$! or return $_;
	1 <= $nb && $nb <= 65535 or return $_;
    }
    '';
}

sub to_ports {
    my ($servers, $unlisted) = @_;
    my $ports = join(' ', (map { $_->{ports} } @$servers), if_($unlisted, $unlisted));
    \$ports;
}

sub from_ports {
    my ($ports) = @_;

    my @l;
    my @unlisted;
    foreach (split ' ', $$ports) {
	if (my $s = port2server($_)) {
	    push @l, $s;
	} else {
	    push @unlisted, $_;
	}
    }
    [ uniq(@l) ], join(' ', @unlisted);
}

sub default_from_pkgs {
    my ($in) = @_;
    my @pkgs = $in->do_pkgs->are_installed(map { split ' ', $_->{pkg} } @all_servers);
    [ grep {
	my $s = $_;
	grep { member($_, @pkgs) } split ' ', $s->{pkg};
    } @all_servers ];
}

sub get_ports {
    my ($ports) = @_;
    my $shorewall = network::shorewall::read() or return;
    \$shorewall->{ports};
}

sub set_ports {
    my ($disabled, $ports) = @_;

    my $shorewall = network::shorewall::read() || network::shorewall::default_interfaces() or die N("No network card");
    $shorewall->{disabled} = $disabled;
    $shorewall->{ports} = $$ports;

    network::shorewall::write($shorewall);
}

sub get_conf {
    my ($in, $disabled, $ports) = @_;

    my $possible_servers = default_from_pkgs($in);
    $_->{hide} = 0 foreach @$possible_servers;

    if ($ports) {
	$disabled, from_ports($ports);
    } elsif (my $shorewall = network::shorewall::read()) {
	$shorewall->{disabled}, from_ports(\$shorewall->{ports});
    } else {
	$in->ask_okcancel('', N("drakfirewall configurator

This configures a personal firewall for this Mandrake Linux machine.
For a powerful dedicated firewall solution, please look to the
specialized MandrakeSecurity Firewall distribution."), 1) or return;

	$in->ask_okcancel('', N("drakfirewall configurator

Make sure you have configured your Network/Internet access with
drakconnect before going any further."), 1) or return;

	$disabled, $possible_servers, '';
    }
}

sub choose {
    my ($in, $disabled, $servers, $unlisted) = @_;

    $_->{on} = 0 foreach @all_servers;
    $_->{on} = 1 foreach @$servers;
    my @l = grep { $_->{on} || !$_->{hide} } @all_servers;

    $in->ask_from_({
		    messages => N("Which services would you like to allow the Internet to connect to?"),
		    advanced_messages => N("You can enter miscellaneous ports. 
Valid examples are: 139/tcp 139/udp.
Have a look at /etc/services for information."),
		    callbacks => {
			complete => sub {
			    if (my $invalid_port = check_ports_syntax($unlisted)) {
				$in->ask_warn('', N("Invalid port given: %s.
The proper format is \"port/tcp\" or \"port/udp\", 
where port is between 1 and 65535.", $invalid_port));
				return 1;
			    }
			},
		   } },
		  [ 
		   { text => N("Everything (no firewall)"), val => \$disabled, type => 'bool' },
		   (map { { text => $_->{name}, val => \$_->{on}, type => 'bool', disabled => sub { $disabled } } } @l),
		   { label => N("Other ports"), val => \$unlisted, advanced => 1, disabled => sub { $disabled } }
		  ]) or return;

    $disabled, to_ports([ grep { $_->{on} } @l ], $unlisted);
}

sub main {
    my ($in, $disabled) = @_;

    ($disabled, my $servers, my $unlisted) = get_conf($in, $disabled) or return;

    $in->do_pkgs->ensure_is_installed('shorewall', '/sbin/shorewall', $::isInstall) or return;

    ($disabled, my $ports) = choose($in, $disabled, $servers, $unlisted) or return;

    set_ports($disabled, $ports);
}
