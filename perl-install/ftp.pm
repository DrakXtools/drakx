package ftp; # $Id$

use Net::FTP;

use install_any;
use network;
use log;

my %hosts;

1;

sub fromEnv() {
    #- now URLPREFIX is generated from what is given by mdk-stage1 which is only this 4 variables.
    $ENV{URLPREFIX} = "ftp://$ENV{LOGIN}" . ($ENV{PASSWORD} && ":$ENV{PASSWORD}") . '@' . "$ENV{HOST}/$ENV{PREFIX}";
    @ENV{qw(HOST PREFIX LOGIN PASSWORD)};
}

sub new {
    my ($host, $prefix, $login, $password) = @_;
    my @l = do { if ($hosts{"$host$prefix"}) {
	@{$hosts{"$host$prefix"}};
    } else {
	my %options = (Passive => 1, Timeout => 60, Port => 21);
	$options{Firewall} = $ENV{PROXY} if $ENV{PROXY};
	$options{Port} = $ENV{PROXYPORT} if $ENV{PROXYPORT};
	unless ($login) {
	    $login = 'anonymous';
	    $password = '-drakx@';
	}

	my $ftp;
	foreach (1..10) {
	    $ftp = Net::FTP->new(network::resolv($host), %options) or die;
	    $ftp && $ftp->login($login, $password) and last;

	    log::l("ftp login failed, sleeping before trying again");
	    sleep 5 * $_;
	}
	$ftp or die "unable to open ftp connection to $host";
	$ftp->binary;
	$ftp->cwd($prefix);

	my @l = ($ftp, \ (my $retr = undef));
	$hosts{"$host$prefix"} = \@l;
	@l;
    }};
    wantarray ? @l : $l[0];
}

sub getFile {
    my ($f, @para) = @_;
    $f eq 'XXX' and rewindGetFile(), return; #- special case to force closing connection.
    foreach (1..3) {
	my ($ftp, $retr) = new(@para ? @para : fromEnv);
	$$retr->close if $$retr;
	$$retr = $ftp->retr($f) and return $$retr;
	rewindGetFile();
	log::l("ftp get failed, sleeping before trying again");
	sleep 1;
    }
}

#-sub closeFiles() {
#-    #- close any existing connections
#-    foreach (values %hosts) {
#-	  my $retr = $_->[1] if ref $_;
#-	  $$retr->close if $$retr;
#-	  undef $$retr;
#-    }
#-}

sub rewindGetFile() {
    #- close any existing connection.
    foreach (values %hosts) {
	my ($ftp, $retr) = @{$_ || []};
	$$retr->close if $$retr;
	$ftp->close() if $ftp;
    }

    #- make sure to reconnect to server.
    %hosts = ();
}
