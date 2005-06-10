package http; # $Id$

use IO::Socket;

my $sock;

sub getFile {
    local ($^W) = 0;

    my ($url) = @_;
    $sock->close if $sock;
    $url =~ m|/XXX$| and return; #- force closing connection.

    # can be used for ftp urls (with http proxy)
    my ($host, $port, $path) = $url =~ m,^(?:http|ftp)://([^/:]+)(?::(\d+))?(/\S*)?$,;
    defined $host or return undef;

    my $use_http_proxy = $ENV{PROXY} && $ENV{PROXYPORT};

    $sock = IO::Socket::INET->new(PeerAddr => $use_http_proxy ? $ENV{PROXY} : $host,
				  PeerPort => $use_http_proxy ? $ENV{PROXYPORT} : $port || 80,
				  Proto    => 'tcp',
				  Timeout  => 60) or die "can not connect $@";
    $sock->autoflush;
    print $sock join("\015\012" =>
		     "GET " . ($use_http_proxy ? $url : $path) . " HTTP/1.0",
		     "Host: $host" . ($port && ":$port"),
		     "User-Agent: DrakX/vivelinuxabaszindozs",
		     "", "");

    #- skip until empty line
    my $now = 0;
    my ($last, $buf, $tmp);
    my $read = sub { sysread($sock, $buf, 1) or die ''; $tmp .= $buf };
    do {
	$last = $now;
	&$read; &$read if $buf =~ /\015/;
	$now = $buf =~ /\012/;
    } until $now && $last;

    if ($tmp =~ /^(.*\b(\d+)\b.*)/ && $2 == 200) {
        $sock;
    } else {
	log::l("HTTP error: $1");
        undef;
    }
}

1;
