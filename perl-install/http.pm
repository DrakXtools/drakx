package http;

use IO::Socket;

use install_any;


my $sock;

sub getFile($) {
    local($^W) = 0;

    my ($host, $port, $path) = $ENV{URLPREFIX} =~ m,^http://([^/:]+)(?::(\d+))?(/\S*)?$,;
    $path .= "/" . install_any::relGetFile($_[0]);

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
    $sock;
}

1;
