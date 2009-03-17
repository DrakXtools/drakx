package fs::remote::nfs; # $Id$

use strict;
use diagnostics;

use common;
use fs::remote;
use log;

our @ISA = 'fs::remote';

sub to_fstab_entry {
    my ($class, $e) = @_;
    $class->to_fstab_entry_raw($e, 'nfs');
}
sub comment_to_string {
    my ($_class, $comment) = @_;
    member($comment, qw(* 0.0.0.0/0.0.0.0 (everyone))) ? '' : $comment;
}
sub from_dev { 
    my ($_class, $dev) = @_;
    $dev =~ m|(.*?):(.*)|;
}
sub to_dev_raw {
    my ($_class, $server, $name) = @_;
    $server . ':' . $name;
}

sub check {
    my ($_class, $in) = @_;
    $in->do_pkgs->ensure_binary_is_installed('nfs-utils-clients', 'showmount') or return;
    require services;
    services::start_not_running_service('portmap');
    services::start('nfs-common'); #- TODO: once nfs-common is fixed, it could use start_not_running_service()
    1;
}

sub find_servers {
    open(my $F2, "rpcinfo-flushed -b mountd 2 |");
    open(my $F3, "rpcinfo-flushed -b mountd 3 |");

    common::nonblock($F2);
    common::nonblock($F3);
    my $domain = chomp_(`domainname`);
    my ($s, %servers);
    my $quit;
    while (!$quit) {
	$quit = 1;
	sleep 1;
	while ($s = <$F2> || <$F3>) {
	    $quit = 0;
	    my ($ip, $name) = $s =~ /(\S+)\s+(\S+)/ or log::explanations("bad line in rpcinfo output"), next;
	    $name =~ s/\.$//;
	    $domain && $name =~ s/\Q.$domain\E$//
	      || $name =~ s/^([^.]*)\.local$/$1/;
	    $servers{$ip} ||= { ip => $ip, if_($name ne '(unknown)', name => $name) };
	}
    }
    values %servers;
}

sub find_exports {
    my ($_class, $server) = @_;

    my @l;
    run_program::raw({ timeout => 1 }, "showmount", '>', \@l, "--no-headers", "-e", $server->{ip} || $server->{name});

    map { if_(/(\S+(\s*\S+)*)\s+(\S+)/, { name => $1, comment => $3, server => $server }) } @l;
}

sub find_server_options {
    my $statd_port = 4001;
    my $statd_outgoing_port = 4001;
    my $lockd_tcp_port = 4002;
    my $lockd_udp_port = 4002;
    my $rpc_mountd_port = 4003;
    my $rpc_rquotad_port = 4004;
    if (-f "/etc/sysconfig/nfs-common") {
            foreach (cat_("/etc/sysconfig/nfs-common")) {
            $_ =~ /^STATD_OPTIONS=.*(--port|-p) (\d+).*$/ and $statd_port = $2;
            $_ =~ /^STATD_OPTIONS=.*(--outgoing-port|-o) (\d+).*$/ and $statd_outgoing_port = $2;
            $_ =~ /^LOCKD_TCPPORT=(\d+)/ and $lockd_tcp_port = $1;
            $_ =~ /^LOCKD_UDPPORT=(\d+)/ and $lockd_udp_port = $1;
        }
    }
    if (-f "/etc/sysconfig/nfs-server") {
        foreach (cat_("/etc/sysconfig/nfs-server")) {
            $_ =~ /^RPCMOUNTD_OPTIONS=.*(--port|-p) (\d+).*$/ and $rpc_mountd_port = $2;
            $_ =~ /^RPCRQUOTAD_OPTIONS=.*(--port|-p) (\d+).*$/ and $rpc_rquotad_port = $2;
        }
    }

    { statd_port => $statd_port,
        statd_outgoing_port => $statd_outgoing_port,
        lockd_tcp_port => $lockd_tcp_port,
        lockd_udp_port => $lockd_udp_port,
        rpc_mountd_port => $rpc_mountd_port,
        rpc_rquotad_port => $rpc_rquotad_port,
    }
}

1;
