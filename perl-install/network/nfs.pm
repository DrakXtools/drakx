package network::nfs;

use common;
use network::network;
use log;

sub check {
    my ($in) = @_;

    my $pkg = 'nfs-utils-clients';
    my $f = '/usr/sbin/showmount';
    if (! -e $f) {
	$in->ask_okcancel('', _("The package %s needs to be installed. Do you want to install it?", $pkg), 1) or return;
	$in->do_pkgs->install($pkg);
    }
    if (! -e $f) {
	$in->ask_warn('', _("Mandatory package %s is missing", $pkg));
	return;
    }
    1;
}


sub find_servers() {
    local (*F, $_);
    my $pid = open F, "rpcinfo-flushed -b mountd 2 |";
    $SIG{ALRM} = sub { kill(15, $pid) };
    alarm 1;

    my $domain = chomp_(`domainname`);
    my @servers;
    while (<F>) {
	chomp;
	my ($ip, $name) = /(\S+)\s+(\S+)/ or log::l("bad line in rpcinfo output"), next;
	$name =~ s/\Q.$domain//; 
	$name =~ s/\.$//;
	push @servers, { ip => $ip, if_($name ne '(unknown)', name => $name) };
    }
    @servers;
}

sub find_exports {
    my ($server) = @_;

    my (undef, @l) = `showmount -e $server->{ip}`;
    map { /(\S+)\s*(\S+)/; { name => $1, comment => $2 } } @l;
}

1;

