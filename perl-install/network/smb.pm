package network::smb; # $Id$

use strict;
use diagnostics;

use common;
use network::network;
use network::smbnfs;


our @ISA = 'network::smbnfs';

sub to_fstab_entry {
    my ($class, $e) = @_;
    $class->to_fstab_entry_raw($e, 'nfs');
}
sub from_dev { 
    my ($class, $dev) = @_;
    $dev =~ m|//(.*?)/(.*)|;
}
sub to_dev_raw {
    my ($class, $server, $name) = @_;
    '//' . $server . '/' . $name;
}

sub check {
    my ($class, $in) = @_;
    $class->raw_check($in, 'samba-client', '/usr/bin/nmblookup');
}

sub find_servers {
    my (undef, @l) = `nmblookup "*"`;
    s/\s.*\n// foreach @l;
    my @servers = grep { network::network::is_ip($_) } @l;
    my %servers;
    $servers{$_}{ip} = $_ foreach @servers;
    my ($ip);
    foreach (`nmblookup -A @servers`) {
	if (my $nb = /^Looking up status of (\S+)/ .. /^$/) {
	    if ($nb == 1) {
		$ip = $1;
	    } else {
		/<00>/ or next;
		$servers{$ip}{/<GROUP>/ ? 'group' : 'name'} ||= lc first(/(\S+)/);
	    }
	}
    }
    values %servers;
}

sub find_exports {
    my ($class, $server) = @_;
    my @l;
    my $name  = $server->{name} || $server->{ip};
    my $ip    = $server->{ip} ? "-I $server->{ip}" : '';
    my $group = $server->{group} ? " -W $server->{group}" : '';

    # WARNING: using smbclient -L is ugly. It can't handle more than 15
    # characters shared names

    foreach (`smbclient -U% -L $name $ip$group`) {
	chomp;
	s/^\t//;
	my ($name, $type, $comment) = unpack "A15 A10 A*", $_;
	if ($name eq '---------' && $type eq '----' && $comment eq '-------' .. /^$/) {
	    push @l, { name => $name, type => $type, comment => $comment, server => $server }
	      if $type eq 'Disk' && $name !~ /\$$/;
	}
    }
    @l;
}

1;

