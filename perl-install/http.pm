package http;

use IO::Socket;

use install_any;
use network;


my $sock;

sub getFile {
    local($^W) = 0;

    my ($host, $port, $path) = $ENV{URLPREFIX} =~ m,^http://([^/:]+)(?::(\d+))?(/\S*)?$,;
    $host = network::resolv($host);
    $path .= "/$_[0]";

    $sock->close if $sock;
    $sock = IO::Socket::INET->new(PeerAddr => $host,
				  PeerPort => $port || 80,
				  Proto    => 'tcp',
				  Timeout  => 60) or die "can't connect ";
    $sock->autoflush;
    print $sock join("\015\012" =>
		     "GET $path HTTP/1.0",
		     "Host: $host" . ($port && ":$port"),
		     "User-Agent: DrakX/vivelinuxabaszindozs",
		     "", "");

    #- skip until empty line
    local $_;
    my ($now, $last) = 0;
    do {
	$last = $now;
	sysread($sock, $_, 1) || die;
	sysread($sock, $_, 1) || die if /\015/;
	$now = /\012/;
    } until ($now && $last);

    $sock;
}

1;
