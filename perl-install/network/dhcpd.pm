package network::dhcpd;

use strict;
use common;

my $sysconf_dhcpd = "$::prefix/etc/sysconfig/dhcpd";
my $dhcpd_conf_file = "$::prefix/etc/dhcpd.conf";
my $update_dhcp = "/usr/sbin/update_dhcp.pl";

sub read_dhcpd_conf {
    my ($o_file) = @_;
    my $s = cat_($o_file || $dhcpd_conf_file);
    { option_routers => [ $s =~ /^\s*option routers\s+(\S+);/mg ],
      subnet_mask => [ if_($s =~ /^\s*option subnet-mask\s+(.*);/mg, split(' ', $1)) ],
      domain_name => [ if_($s =~ /^\s*option domain-name\s+"(.*)";/mg, split(' ', $1)) ],
      domain_name_servers => [ if_($s =~ /^\s*option domain-name-servers\s+(.*);/m, split(' ', $1)) ],
      dynamic_bootp => [ if_($s =~ /^\s*range dynamic-bootp\s+\S+\.(\d+)\s+\S+\.(\d+)\s*;/m, split(' ', $1)) ],
      default_lease_time => [ if_($s =~ /^\s*default-lease-time\s+(.*);/m, split(' ', $1)) ],
      max_lease_time => [ if_($s =~ /^\s*max-lease-time\s+(.*);/m, split(' ', $1)) ] };
}

sub write_dhcpd_conf {
    my ($dhcpd_conf, $device) = @_;

    my ($lan) = $dhcpd_conf->{option_routers}[0] =~ /^(.*)\.\d+$/;
    log::explanations("Configuring a DHCP server on $lan.0");

    renamef($dhcpd_conf_file, "$dhcpd_conf_file.old");
    output($dhcpd_conf_file, qq(subnet $lan.0 netmask $dhcpd_conf->{subnet_mask}[0] {
	# default gateway
	option routers $dhcpd_conf->{option_routers}[0];
	option subnet-mask $dhcpd_conf->{subnet_mask}[0];

	option domain-name "$dhcpd_conf->{domain_name}[0]";
	option domain-name-servers $dhcpd_conf->{domain_name_servers}[0];

	range dynamic-bootp $lan.$dhcpd_conf->{dynamic_bootp}[0] $lan.$dhcpd_conf->{dynamic_bootp}[1];
	default-lease-time $dhcpd_conf->{default_lease_time}[0];
	max-lease-time $dhcpd_conf->{max_lease_time}[0];
}
));

    #- put the interface for the dhcp server in the sysconfig-dhcp config, for the /etc/init.d script of dhcpd
    log::explanations("Update network interfaces list for dhcpd server");
    substInFile { s/^INTERFACES\n//; $_ .= qq(INTERFACES="$device"\n) if eof } $sysconf_dhcpd if !$::testing;
    run_program::rooted($::prefix, $update_dhcp);
}


1;
