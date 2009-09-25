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
