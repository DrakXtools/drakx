package network::smb;

use common;
use network::network;

sub check {
    my ($in) = @_;
    my $f = '/usr/bin/nmblookup';
    -e $f or $in->do_pkgs->install('samba-client');
    -e $f or $in->ask_warn('', "Mandatory package samba-client is missing"), return;
    1;
}


sub find_servers() {
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
    my ($server) = @_;
    my @l;
    my $name  = $server->{name} || $server->{ip};
    my $group = $server->{group} ? " -W $server->{group}" : '';

    # WARNING: using smbclient -L is ugly. It can't handle more than 15
    # characters shared names

    foreach (`smbclient -U% -L $name -I $server->{ip}$group`) {
	chomp;
	s/^\t//;
	my ($name, $type, $comment) = unpack "A15 A10 A*", $_;
	if ($name eq '---------' && $type eq '----' && $comment eq '-------' .. /^$/) {
	    push @l, { name => $name, type => $type, comment => $comment }
	      if $type eq 'Disk' && $name ne 'ADMIN$';
	}
    }
    @l;
}

1;

