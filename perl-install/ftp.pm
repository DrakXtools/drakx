package ftp;

use Net::FTP;

use install_any;
use log;

# non-rentrant!!

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

    my $host = $ENV{HOST};
    if ($host !~ /^[.\d]+$/) {
	$host = join ".", unpack "C4", (gethostbyname $host)[4];
    }

    my $ftp = Net::FTP->new($host, %options) or die;
    $ftp->login($ENV{LOGIN}, $ENV{PASSWORD}) or die;
    $ftp->binary;

    $ftp;
}


my $retr;
sub getFile($) {
    $ftp ||= new();
    $retr->close if $retr;
    $retr = $ftp->retr($ENV{PREFIX} . "/" . install_any::relGetFile($_[0]));
}
