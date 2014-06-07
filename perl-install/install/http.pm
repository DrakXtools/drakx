package install::http;

use urpm::download;
use common;
use Cwd;

sub getFile {
    my ($url, %o_options) = @_;
    my ($_size, $fh) = get_file_and_size($url, %o_options) or return;
    $fh;
}

sub parse_http_url {
    my ($url) = @_;
    $url =~ m,^(?:https?|ftp)://(?:[^:/]+:[^:/]+\@)?([^/:@]+)(?::(\d+))?(/\S*)?$,;
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
    my ($url, %o_options) = @_;

    # can be used for ftp urls (with http proxy)
    my ($host) = parse_http_url($url);
    defined $host or return undef;

    my $urpm = $::o->{packages};
    if (!$urpm) {
        require install::pkgs;
        $urpm = install::pkgs::empty_packages($::o->{keep_unrequested_dependencies});
	$urpm->{options}{'curl-options'} = '-s';
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
    
    my $res = eval { urpm::download::sync_url($urpm, $url, %o_options, dir => $cachedir) };

    if ($res) {
        open(my $f, $file);
        (-s $file, $f);
    } else {
        log::l("retrieval of [$file] failed");
        undef;
    }
}

1;
