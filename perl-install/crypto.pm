package crypto; # $Id$

use diagnostics;
use strict;

use MDK::Common::System;
use common;
use log;
use ftp;

my %url2lang = (
		fr => _("France"),
		cr => _("Costa Rica"),
		be => _("Belgium"),
		cz => _("Czech Republic"),
		de => _("Germany"),
		gr => _("Grece"),
		no => _("Norway"),
		se => _("Sweden"),
	       );

my %static_mirrors = (
#		      "ackbar" => [ "Ackbar", "/updates", "a", "a" ],
		     );

my %mirrors = ();

my %deps = (
  'libcrypto.so.0' => 'openssl',
  'libssl.so.0' => 'openssl',
  'mod_sxnet.so' => 'mod_ssl-sxnet',
);

sub require2package { $deps{$_[0]} || $_[0] }
sub mirror2text { $mirrors{$_[0]} && ($mirrors{$_[0]}[0] . '|' . $_[0]) }

sub mirrors {
    unless (keys %mirrors) {
	#- contact the following URL to retrieve list of mirror.
	#- http://www.linux-mandrake.com/mirrorsfull.list
	require http;
	my $f = http::getFile("http://www.linux-mandrake.com/mirrorsfull.list");
	foreach (<$f>) {
	    my ($arch, $url, $dir) = m|updates([^:]*):ftp://([^/]*)(/\S*)| or next;
	    MDK::Common::System::compat_arch($arch) or
		log::l("ignoring updates from $url because of incompatible arch: $arch"), next;
	    my $lang = _("United States");
	    foreach (keys %url2lang) {
		my $qu = quotemeta $_;
		$url =~ /\.$qu(?:\..*)?$/ and $lang = $url2lang{$_};
	    }
	    $mirrors{$url} = [ $lang, $dir ];
	}
	http::getFile('/XXX'); #- close connection.

	#- now add static mirror (in case of something wrong happened above).
	add2hash(\%mirrors, \%static_mirrors);
    }
    keys %mirrors;
}

#sub dir { $mirrors{$_[0]}[1] . '/' . $::VERSION }
sub dir { $mirrors{$_[0]}[1] . '/' . '8.1' }
sub ftp($) { ftp::new($_[0], dir($_[0])) }

sub getFile {
    my ($file, $host) = @_;
    $host ||= $crypto::host;
    my $dir = dir($host) . ($file =~ /\.rpm$/ && "/RPMS");
    log::l("getting crypto file $file on directory $dir with login $mirrors{$host}[2]");
    my ($ftp, $retr) = ftp::new($host, $dir,
				$mirrors{$host}[2] ? $mirrors{$host}[2] : (),
				$mirrors{$host}[3] ? $mirrors{$host}[3] : ()
			       );
    $$retr->close if $$retr;
    $$retr   = $ftp->retr($file) or ftp::rewindGetFile();
    $$retr ||= $ftp->retr($file);
}

sub getDepslist { getFile("depslist-crypto", $_[0]) or die "unable to get depslist-crypto" }

sub getPackages {
    my ($prefix, $packages, $mirror) = @_;

    $crypto::host = $mirror;

    #- extract hdlist of crypto, then depslist.
    eval {
	require pkgs;
	my $update_medium = pkgs::psUsingHdlist($prefix, 'ftp', $packages, "hdlist-updates.cz", "1u", "RPMS",
						#"Updates for Mandrake Linux $::VERSION", 1, getFile("base/hdlist.cz", $mirror)) and
						"Updates for Mandrake Linux 8.1", 1, getFile("base/hdlist.cz", $mirror)) and
						  log::l("read updates hdlist");
	#- keep in mind where is the URL prefix used according to mirror (for install_any::install_urpmi).
	$update_medium->{prefix} = dir($mirror);

	return $update_medium;
    };
    return; #- an exception occurred, so ignore it.
}

sub get {
    my ($mirror, $dir, @files) = @_;
    foreach (@files) {
	log::l("crypto: downloading $_");
	ftp($mirror)->get($_, "$dir/$_") 
    }
    int @files;
}
