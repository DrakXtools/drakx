package ftp; # $Id$

use Net::FTP;

use install_any;
use network;
use log;

my %hosts;

1;

sub fromEnv() {
    # using URLPREFIX to find out information if kickstart
    ($ENV{LOGIN}, $ENV{PASSWORD}, $ENV{HOST}, $ENV{PREFIX}) =
      $ENV{URLPREFIX} =~ m|
       ://
       (?: ([^:]*)              # login
           (?: :([^@]*))?       # password
       @)?
       ([^/]*)                	# host
       /?(.*)			# prefix
      |x unless $ENV{HOST};
    
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
	while (1) {
	    $ftp = Net::FTP->new(network::resolv($host), %options) or die;
	    $ftp && $ftp->login($login, $password) and last;

	    log::l("login failed, sleeping before trying again");
	    sleep 10;
	}
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
    my ($ftp, $retr) = new(@para ? @para : fromEnv);
    $$retr->close if $$retr;
    $$retr   = $ftp->retr($f) or do { rewindGetFile(); goto &getFile };
    $$retr ||= $ftp->retr($f);
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
	my ($ftp) = @{$_ || []};
	$ftp->close() if $ftp;
    }

    #- make sure to reconnect to server.
    %hosts = ();
}
