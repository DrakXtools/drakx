package install::http; # $Id$

use IO::Socket;

my $sock;


sub close() {
    $sock->close if $sock;
}

sub getFile {
    my ($url) = @_;
    my ($_size, $fh) = get_file_and_size($url) or return;
    $fh;
}

sub parse_url {
    my ($url) = @_;
    $url =~ m,^(?:http|ftp)://([^/:]+)(?::(\d+))?(/\S*)?$,;
}

sub get_file_and_size_ {
    my ($f, $url) = @_;

    if ($f =~ m!^/!) {
	my ($host, $port, $_path) = parse_url($url);
	get_file_and_size("http://$host" . ($port ? ":$port" : '') . $f);
    } else {
	get_file_and_size("$url/$f");
    }
}

sub get_file_and_size {
    local ($^W) = 0;

    my ($url) = @_;
    $sock->close if $sock;

    # can be used for ftp urls (with http proxy)
    my ($host, $port, $path) = parse_url($url);
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
	my ($size) = $tmp =~ /^Content-Length:\s*(\d+)\015?$/m;
	$size, $sock;
    } else {
	log::l("HTTP error: $1");
        undef;
    }
}

1;
