package crypto; # $Id$

use diagnostics;
use strict;

use MDK::Common::System;
use common;
use log;
use ftp;

my %url2land = (
		fr => _("France"),
		cr => _("Costa Rica"),
		be => _("Belgium"),
		cz => _("Czech Republic"),
		de => _("Germany"),
		gr => _("Greece"),
		no => _("Norway"),
		se => _("Sweden"),
		nl => _("Netherlands"),
		it => _("Italy"),
		at => _("Austria"),
	       );

my %land2tzs = (
		_("France") => [ 'Europe/Paris', 'Europe/Brussels', 'Europe/Berlin' ],
		_("Belgium") => [ 'Europe/Brussels', 'Europe/Paris', 'Europe/Berlin' ],
		_("Czech Republic") => [ 'Europe/Prague', 'Europe/Berlin' ],
		_("Germany") => [ 'Europe/Berlin', 'Europe/Prague' ],
		_("Greece") => [ 'Europe/Athens', 'Europe/Prague' ],
		_("Norway") => [ 'Europe/Oslo', 'Europe/Stockholm' ],
		_("Sweden") => [ 'Europe/Stockholm', 'Europe/Oslo' ],
		_("United States") => [ 'America/New_York', 'Canada/Atlantic', 'Asia/Tokyo', 'Australia/Sydney', 'Europe/Paris' ],
		_("Netherlands") => [ 'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Berlin' ],
		_("Italy") => [ 'Europe/Rome', 'Europe/Brussels', 'Europe/Paris' ],
		_("Austria") => [ 'Europe/Vienna', 'Europe/Brussels', 'Europe/Berlin' ],
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

	local $SIG{ALRM} = sub { die "timeout" };
	alarm 60; 
	foreach (<$f>) {
	    my ($arch, $url, $dir) = m|updates([^:]*):ftp://([^/]*)(/\S*)| or next;
	    MDK::Common::System::compat_arch($arch) or
		log::l("ignoring updates from $url because of incompatible arch: $arch"), next;
	    my $land = _("United States");
	    foreach (keys %url2land) {
		my $qu = quotemeta $_;
		$url =~ /\.$qu(?:\..*)?$/ and $land = $url2land{$_};
	    }
	    $mirrors{$url} = [ $land, $dir ];
	}
	http::getFile('/XXX'); #- close connection.
	alarm 0; 

	#- now add static mirror (in case of something wrong happened above).
	add2hash(\%mirrors, \%static_mirrors);
    }
    keys %mirrors;
}

sub bestMirror {
    my ($string) = @_;
    my %mirror2value;

    foreach my $url (mirrors()) {
	my $value = 0;
	my $cvalue = mirrors();

	$mirror2value{$url} ||= 1 + $cvalue;
	foreach (@{$land2tzs{$mirrors{$url}[0]} || []}) {
	    $_ eq $string and $mirror2value{$url} > $value and $mirror2value{$url} = $value;
	    (split '/')[0] eq (split '/', $string)[0] and $mirror2value{$url} > $cvalue and $mirror2value{$url} = $cvalue;
	    ++$value;
	}
    }
    my ($min_value) = sort { $a <=> $b } values %mirror2value;

    my @possible = grep { $mirror2value{$_} == $min_value } keys %mirror2value;
    push @possible, grep { $mirror2value{$_} == $min_value } keys %mirror2value;
    push @possible, grep { $mirror2value{$_} == 1 + $min_value } keys %mirror2value;

    $possible[rand @possible];
}

sub dir { $mirrors{$_[0]}[1] . '/' . $::VERSION }
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
    require pkgs;
    my $update_medium = pkgs::psUsingHdlist($prefix, 'ftp', $packages, "hdlist-updates.cz", "1u", "RPMS",
					    #"Updates for Mandrake Linux $::VERSION", 1, getFile("base/hdlist.cz", $mirror)) and
					    "Updates for Mandrake Linux 8.1", 1, getFile("base/hdlist.cz", $mirror)) and
					      log::l("read updates hdlist");
    #- keep in mind where is the URL prefix used according to mirror (for install_any::install_urpmi).
    $update_medium->{prefix} = "ftp://$mirror" . dir($mirror);
    #- (re-)enable the medium to allow install of package,
    #- make it an update medium (for install_any::install_urpmi).
    $update_medium->{selected} = 1;
    $update_medium->{update} = 1;

    return $update_medium;
}

sub get {
    my ($mirror, $dir, @files) = @_;
    foreach (@files) {
	log::l("crypto: downloading $_");
	ftp($mirror)->get($_, "$dir/$_") 
    }
    int @files;
}
