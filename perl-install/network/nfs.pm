package network::nfs; # $Id$

use strict;
use diagnostics;

use common;
use network::network;
use network::smbnfs;
use log;

our @ISA = 'network::smbnfs';

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
    $in->do_pkgs->ensure_is_installed('nfs-utils-clients', '/usr/sbin/showmount') or return;
    system('/etc/init.d/portmap start') if system('/etc/init.d/portmap status') != 0;
    1;
}

sub find_servers {
    my $pid = open(my $F, "rpcinfo-flushed -b mountd 2 |");
    $SIG{ALRM} = sub { kill(15, $pid) };
    alarm 1;

    my $domain = chomp_(`domainname`);
    my @servers;
    local $_;
    while (<$F>) {
	my ($ip, $name) = /(\S+)\s+(\S+)/ or log::explanations("bad line in rpcinfo output"), next;
	$name =~ s/\Q.$domain//; 
	$name =~ s/\.$//;
	push @servers, { ip => $ip, if_($name ne '(unknown)', name => $name) };
    }
    @servers;
}

sub find_exports {
    my ($_class, $server) = @_;

    my @l;
    run_program::raw({ timeout => 1 }, "showmount", '>', \@l, "--no-headers", "-e", $server->{ip} || $server->{name});

    map { if_(/(\S+(\s*\S+)*)\s+(\S+)/, { name => $1, comment => $3, server => $server }) } @l;
}

1;
