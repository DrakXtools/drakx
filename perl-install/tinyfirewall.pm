package tinyfirewall; # $Id$

use diagnostics;
use strict;

use common;

my @all_servers = 
(
  { 
   name => _("Web Server"),
   pkg => 'apache apache-mod_perl boa',
   ports => '80/tcp 443/tcp',
  },
  {
   name => _("Domain Name Server"),
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
   name => _("Mail Server"),
   pkg => 'sendmail postfix qmail',
   ports => '25/tcp',
  },
  {
   name => _("POP and IMAP Server"),
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
}

sub set_ports {
    my ($ports) = @_;
    print "set_ports $$ports\n";
}

sub get_conf {
    my ($in, $ports) = @_;

    my $possible_servers = default_from_pkgs($in);
    $_->{hide} = 0 foreach @$possible_servers;

    if ($ports ||= get_ports()) {
	from_ports($ports);
    } else {
	$in->ask_okcancel('', _("tinyfirewall configurator

This configures a personal firewall for this Mandrake Linux machine.
For a powerful dedicated firewall solution, please look to the
specialized MandrakeSecurity Firewall distribution."), 1) or return;

	$possible_servers, '';
    }
}

sub choose {
    my ($in, $servers, $unlisted) = @_;

    $_->{on} = 0 foreach @all_servers;
    $_->{on} = 1 foreach @$servers;
    my @l = grep { $_->{on} || !$_->{hide} } @all_servers;

    $in->ask_from_({
		    messages => _("Which services would you like to allow the Internet to connect to?"),
		    advanced_messages => _("You can enter miscellaneous ports. 
Valid examples are: 139/tcp 139/udp.
Have a look at /etc/services for information."),
		    callbacks => {
			complete => sub {
			    if (my $invalid_port = check_ports_syntax($unlisted)) {
				$in->ask_warn('', _("Invalid port given: %s.
The proper format is \"port/tcp\" or \"port/udp\", 
where port is between 1 and 65535.", $invalid_port));
				return 1;
			    }
			},
		   }},
		  [ 
		   (map { { text => $_->{name}, val => \$_->{on}, type => 'bool' } } @l),
		   { label => _("Other ports"), val => \$unlisted, advanced => 1 }
		  ]) or return;

    to_ports([ grep { $_->{on} } @l ], $unlisted);
}

sub main {
    my ($in) = @_;

    my ($servers, $unlisted) = get_conf($in) or return;

    $in->do_pkgs->ensure_is_installed('shorewall', '/sbin/shorewall', $::isInstall) or return;

    my $ports = choose($in, $servers, $unlisted) or return;

    set_ports($ports);
}
