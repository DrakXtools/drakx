package ftp;

use Net::FTP;

use install_any;
use network;
use log;

# non-rentrant!!

my $retr;

1;


sub new {
    my %options = (Passive => 1);
    $options{Firewall} = $ENV{PROXY} if $ENV{PROXY};
    $options{Port} = $ENV{PROXYPORT} if $ENV{PROXYPORT};
    my @l;
    unless ($ENV{HOST}) {
	# must be in kickstart, using URLPREFIX to find out information
	($ENV{LOGIN}, $ENV{PASSWORD}, $ENV{HOST}, $ENV{PREFIX}) = @l =
	  $ENV{URLPREFIX} =~ m|
       ://
       (?: ([^:]*)              # login
           (?: :([^@]*))?       # password
       @)?
       ([^/]*)                	# host
       /?(.*)			# prefix
      |x;
    }
    unless ($ENV{LOGIN}) {
	$ENV{LOGIN} = 'anonymous';
	$ENV{PASSWORD} = 'mdkinst@test';
    }

    my $ftp = Net::FTP->new(network::resolv($ENV{HOST}), %options) or die '';
    $ftp->login($ENV{LOGIN}, $ENV{PASSWORD}) or die '';
    $ftp->binary;

    $ftp;
}


sub getFile($) {
    $ftp ||= new();
    $retr->close if $retr;
    $retr = $ftp->retr($ENV{PREFIX} . "/" . install_any::relGetFile($_[0]));
}
