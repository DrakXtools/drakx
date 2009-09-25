package install::ftp; # $Id$

use Net::FTP;

use network::network;
use log;

my %hosts;

1;

sub parse_ftp_url {
    my ($url) = @_;
    $url =~ m!^ftp://(?:(.*?)(?::(.*?))?\@)?([^/]+)/(.*)! &&
      ($3, $4, $1, $2);
}

sub _new {
    my ($url) = @_;    
    my ($host, $prefix, $login, $password) = parse_ftp_url($url);

    if ($hosts{"$host$prefix"}) {
	return @{$hosts{"$host$prefix"}};
    }

	my %options = (Passive => 1, Timeout => 60, Port => 21);
	$options{Firewall} = $ENV{PROXY} if $ENV{PROXY};
	$options{Port} = $ENV{PROXYPORT} if $ENV{PROXYPORT};
	unless ($login) {
	    $login = 'anonymous';
	    $password = '-drakx@';
	}

	my $ftp;
	foreach (1..10) {
	    $ftp = Net::FTP->new(network::network::resolv($host), %options) or die "Can't resolve hostname '$host'\n";
	    $ftp && $ftp->login($login, $password) and last;

	    log::l("ftp login failed, sleeping before trying again");
	    sleep 5 * $_;
	}
	$ftp or die "unable to open ftp connection to $host\n";
	$ftp->binary;
	$ftp->cwd($prefix);

	my @l = ($ftp, \ (my $_retr));
	$hosts{"$host$prefix"} = \@l;
	@l;
}

sub getFile {
    my ($f, $url) = @_;
    my ($_size, $fh) = get_file_and_size($f, $url) or return;
    $fh;
}
sub get_file_and_size {
    my ($f, $url) = @_;

    foreach (1..3) {
	my ($ftp, $retr) = _new($url);
	eval { $$retr->close if $$retr };
	if ($@) {
	    log::l("FTP: closing previous retr failed ($@)");
	    _rewindGetFile(); #- in case Timeout got us on "->close"
	    redo;
	}

	my $size = $ftp->size($f);
	$$retr = $ftp->retr($f) and return $size, $$retr;

	my $error = $ftp->code;
	$error == 550 and log::l("FTP: 550 file unavailable"), return;

	_rewindGetFile();
	log::l("ftp get failed, sleeping before trying again (error:$error)");
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

sub _rewindGetFile() {
    #- close any existing connection.
    foreach (values %hosts) {
	my ($ftp, $retr) = @{$_ || []};
	#- do not let Timeout kill us!
	eval { $$retr->close } if $$retr;
	eval { $ftp->close } if $ftp;
    }

    #- make sure to reconnect to server.
    %hosts = ();
}
