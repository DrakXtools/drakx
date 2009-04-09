package install::http; # $Id$

use urpm::download;
use common;

# to be killed once callers got fixed
sub close() {
}

sub getFile {
    my ($url) = @_;
    my ($_size, $fh) = get_file_and_size($url) or return;
    $fh;
}

sub parse_http_url {
    my ($url) = @_;
    $url =~ m,^(?:http|ftp)://([^/:]+)(?::(\d+))?(/\S*)?$,;
}

sub get_file_and_size_ {
    my ($f, $url) = @_;

    if ($f =~ m!^/!) {
	my ($host, $port, $_path) = parse_http_url($url);
	get_file_and_size("http://$host" . ($port ? ":$port" : '') . $f);
    } else {
	get_file_and_size("$url/$f");
    }
}

sub get_file_and_size {
    my ($url) = @_;

    # can be used for ftp urls (with http proxy)
    my ($host) = parse_http_url($url);
    defined $host or return undef;

    my $urpm = $::o->{packages};
    if (!$urpm) {
        require install::pkgs;
        $urpm = install::pkgs::empty_packages($o->{keep_unrequested_dependencies});
    }

    my $cachedir = $urpm->{cachedir} || '/root';
    my $file = $url;
    $file =~ s!.*/!$cachedir/!;
    unlink $file;       # prevent "partial file" errors
    
    if ($ENV{PROXY}) {
        my ($proxy, $port) = urpm::download::parse_http_proxy(join(':', $ENV{PROXY}, $ENV{PROXYPORT}))
          or die "bad proxy declaration\n";
        $proxy .= ":1080" unless $port;
        urpm::download::set_cmdline_proxy(http_proxy => "http://$proxy/");
    }
    
    my $res = urpm::download::sync_url($urpm, $url, dir => $cachedir);
    $res or die N("retrieval of [%s] failed", $file) . "\n";
    open(my $f, $file);
    ( -s $file, $f);
}

1;
