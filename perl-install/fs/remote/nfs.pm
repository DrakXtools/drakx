package fs::remote::nfs; # $Id$

use strict;
use diagnostics;

use common;
use fs::remote;
use network::tools;
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
    $in->do_pkgs->ensure_files_are_installed([ [ qw(nfs-utils showmount) ] , [ qw(nmap nmap) ] ]);
    require services;
    services::start_not_running_service('rpcbind');
    services::start('nfs-common'); #- TODO: once nfs-common is fixed, it could use start_not_running_service()
    1;
}

sub find_servers {
    my @hosts;
    my %servers;
    my @routes = cat_("/proc/net/route");
    @routes = reverse(@routes) if common::cmp_kernel_versions(c::kernel_version(), "2.6.39") >= 0;
    foreach (@routes) {
	if (/^(\S+)\s+([0-9A-F]+)\s+([0-9A-F]+)\s+[0-9A-F]+\s+\d+\s+\d+\s+(\d+)\s+([0-9A-F]+)/) {
	    my $net = network::tools::host_hex_to_dotted($2);
	    my $gateway = $3;
	    # get the netmask in binary and remove leading zeros
	    my $mask = unpack('B*', pack('h*', $5));
	    $mask =~ s/^0*//;
	    push @hosts, $net . "/" . length($mask) if $gateway eq '00000000' && $net ne '169.254.0.0';
	}
     }
    # runs the nmap command on the local subnet
    my $cmd = "/usr/bin/nmap -p 111 --open --system-dns -oG - " . (join ' ',@hosts);
    open my $FH, "$cmd |" or die "Could not perform nmap scan - $!";
    foreach (<$FH>) { 
      my ($ip, $name) = /^H\S+\s(\S+)\s+\((\S*)\).+Port/ or next;
      $servers{$ip} ||= { ip => $ip, name => $name || $ip };
    }
    close $FH;
    values %servers;
}

sub find_exports {
    my ($_class, $server) = @_;

    my @l;
    run_program::raw({ timeout => 1 }, "showmount", '>', \@l, "--no-headers", "-e", $server->{ip} || $server->{name});

    map { if_(/(\S+(\s*\S+)*)\s+(\S+)/, { name => $1, comment => $3, server => $server }) } @l;
}

1;
