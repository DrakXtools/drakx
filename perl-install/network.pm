package network;

use diagnostics;
use strict;

use Socket;

use common qw(:common :file :system :functional);
use detect_devices;
use modules;
use log;

1;


sub read_conf {
    my ($file) = @_;
    my %netc = getVarsFromSh($file);
    \%netc;
}

sub read_interface_conf {
    my ($file) = @_;
    my %intf = getVarsFromSh($file) or die "cannot open file $file: $!";

    $intf{BOOTPROTO} ||= 'static';
    $intf{isPtp} = $intf{NETWORK} eq '255.255.255.255';
    $intf{isUp} = 1;
    \%intf;
}

sub write_conf {
    my ($file, $netc) = @_;

    add2hash($netc, {
		     NETWORKING => "yes", 
		     FORWARD_IPV4 => "false", 
		     HOSTNAME => "localhost.localdomain",
		     DOMAINNAME => "localdomain",
		     });
		     
    setVarsInSh($file, $netc, qw(NETWORKING FORWARD_IPV4 HOSTNAME DOMAINNAME GATEWAY GATEWAYDEV));
}

sub write_resolv_conf {
    my ($file, $netc) = @_;

    # We always write these, even if they were autoconfigured. Otherwise, the reverse name lookup in the install doesn't work. 
    unless ($netc->{DOMAINNAME} || dnsServers($netc)) {
	unlink($file);
	log::l("neither domain name nor dns server are configured");
	return 0;
    }
    my @l = cat_($file);

    local *F;
    open F, "> $file" or die "cannot write $file: $!";
    print F "search $netc->{DOMAINNAME}\n" if $netc->{DOMAINNAME};
    print F "nameserver $_\n" foreach dnsServers($netc);
    print F "#$_" foreach @l;

    #res_init();		# reinit the resolver so DNS changes take affect 
    1;
}

sub write_interface_conf {
    my ($file, $intf) = @_;

    my @ip = split '\.', $intf->{IPADDR};
    my @mask = split '\.', $intf->{NETMASK};
    add2hash($intf, { 
		     BROADCAST => join('.', mapn { int $_[0] | ~int $_[1] & 255 } \@ip, \@mask),
		     NETWORK   => join('.', mapn { int $_[0] &      $_[1]       } \@ip, \@mask),
		     ONBOOT => "yes",
		    });
    setVarsInSh($file, $intf, qw(DEVICE BOOTPROTO IPADDR NETMASK NETWORK BROADCAST ONBOOT));
}

sub add2hosts {
    my ($file, $hostname, @ips) = @_;
    my %l;
    $l{$_} = $hostname foreach @ips;

    local *F;
    if (-e $file) {
	open F, $file or die "cannot open $file: $!";
	/\s*(\S+)(.*)/ and $l{$1} = $2 foreach <F>;
    }
    log::l("writing host information to $file");
    open F, ">$file" or die "cannot write $file: $!";
    while (my ($ip, $v) = each %l) {
	print F "$ip";
	if ($v =~ /^\s/) {
	    print F $v;
	} else {
	    print F "\t\t$v";
	    print F " $1" if $v =~ /(.*?)\./;
	}
	print F "\n";
    }
}

# The interface/gateway needs to be configured before this will work! 
sub guessHostname {
    my ($prefix, $netc, $intf) = @_;

    $intf->{isUp} && dnsServers($netc) or return 0;
    $netc->{HOSTNAME} && $netc->{DOMAINNAME} and return 1;

    write_resolv_conf("$prefix/etc/resolv.conf", $netc);

#    winStatus(40, 3, _("Hostname"), _("Determining host name and domain..."));
    my $name = gethostbyaddr(Socket::inet_aton($intf->{IPADDR}), AF_INET) or log::l("reverse name lookup failed"), return 0;

    log::l("reverse name lookup worked");

    add2hash($netc, { HOSTNAME => $name, DOMAINNAME => $name =~ /\.(.*)/ });
    1;
}

sub addDefaultRoute {
    my ($netc) = @_;
    c::addDefaultRoute($netc->{GATEWAY}) if $netc->{GATEWAY};
}

sub sethostname {
    my ($netc) = @_;
    syscall_('sethostname', $netc->{HOSTNAME}, length $netc->{HOSTNAME}) or log::l("sethostname failed: $!");
}

sub dnsServers {
    my ($netc) = @_;
    map { $netc->{$_} } qw(dnsServer dnsServer2 dnsServer3);
}

sub getNet() {
    modules::load_thiskind('net');
    detect_devices::getNet();
}

sub findIntf {
    my ($intf, $device) = @_;
    my ($l) = grep { $_->{DEVICE} eq $device } @$intf;
    push @$intf, $l = { DEVICE => $device } unless $l;
    $l;
}
