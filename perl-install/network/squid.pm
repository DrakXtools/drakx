package network::squid;

use strict;
use common;

our $squid_conf_file = "$::prefix/etc/squid/squid.conf";

sub read_squid_conf {
    my ($o_file) = @_;
    my $s = cat_($o_file || $squid_conf_file);
    { http_port => [ $s =~ /^\s*http_port\s+(.*)/mg ],
      cache_size => [ if_($s =~ /^\s*cache_dir diskd\s+(.*)/mg, split(' ', $1)) ],
      admin_mail => [ if_($s =~ /^\s*err_html_text\s+(.*)/mg, split(' ', $1)) ] };
}

sub write_squid_conf {
    my ($squid_conf, $intf, $internal_domain_name) = @_;

    renamef($squid_conf_file, "$squid_conf_file.old");
    output($squid_conf_file, qq(
http_port $squid_conf->{http_port}[0]
hierarchy_stoplist cgi-bin ?
acl QUERY urlpath_regex cgi-bin \\?
no_cache deny QUERY
cache_dir diskd /var/spool/squid $squid_conf->{cache_size}[1] 16 256
cache_store_log none
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern .               0       20%     4320
half_closed_clients off
acl all src 0.0.0.0/0.0.0.0
acl manager proto cache_object
acl localhost src 127.0.0.1/255.255.255.255
acl to_localhost dst 127.0.0.0/8
acl SSL_ports port 443 563
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443 563     # https, snews
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl CONNECT method CONNECT
http_access allow manager localhost
http_access deny manager
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny to_localhost
acl mynetwork src $intf->{NETWORK}/$intf->{NETMASK}
http_access allow mynetwork
http_access allow localhost
http_reply_access allow all
icp_access allow all
visible_hostname $squid_conf->{visible_hostname}[0]
httpd_accel_host virtual
httpd_accel_with_proxy on
httpd_accel_uses_host_header on
append_domain .$internal_domain_name
err_html_text $squid_conf->{admin_mail}[0]
deny_info ERR_CUSTOM_ACCESS_DENIED all
memory_pools off
coredump_dir /var/spool/squid
ie_refresh on
)) if !$::testing;
}

1;
