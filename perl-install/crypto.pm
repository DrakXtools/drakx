package crypto; # $Id$

use diagnostics;
use strict;

use vars qw(%url2land %land2tzs %static_mirrors %mirrors);

use MDK::Common::System;
use common;
use log;
use ftp;

%url2land = (
	     fr => N("France"),
	     cr => N("Costa Rica"),
	     be => N("Belgium"),
	     cz => N("Czech Republic"),
	     de => N("Germany"),
	     gr => N("Greece"),
	     no => N("Norway"),
	     se => N("Sweden"),
	     nl => N("Netherlands"),
	     it => N("Italy"),
	     at => N("Austria"),
	    );

%land2tzs = (
	     N("France") => [ 'Europe/Paris', 'Europe/Brussels', 'Europe/Berlin' ],
	     N("Belgium") => [ 'Europe/Brussels', 'Europe/Paris', 'Europe/Berlin' ],
	     N("Czech Republic") => [ 'Europe/Prague', 'Europe/Berlin' ],
	     N("Germany") => [ 'Europe/Berlin', 'Europe/Prague' ],
	     N("Greece") => [ 'Europe/Athens', 'Europe/Prague' ],
	     N("Norway") => [ 'Europe/Oslo', 'Europe/Stockholm' ],
	     N("Sweden") => [ 'Europe/Stockholm', 'Europe/Oslo' ],
	     N("United States") => [ 'America/New_York', 'Canada/Atlantic', 'Asia/Tokyo', 'Australia/Sydney', 'Europe/Paris' ],
	     N("Netherlands") => [ 'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Berlin' ],
	     N("Italy") => [ 'Europe/Rome', 'Europe/Brussels', 'Europe/Paris' ],
	     N("Austria") => [ 'Europe/Vienna', 'Europe/Brussels', 'Europe/Berlin' ],
	    );

%static_mirrors = (
#		   "ackbar" => [ "Ackbar", "/updates", "a", "a" ],
		  );

%mirrors = ();

sub mirror2text { $mirrors{$_[0]} && $mirrors{$_[0]}[0] . '|' . $_[0] }
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
	    my $land = N("United States");
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
    my $min_value = min(values %mirror2value);

    my @possible = (grep { $mirror2value{$_} == $min_value } keys %mirror2value) x 2; #- increase probability
    push @possible, grep { $mirror2value{$_} == 1 + $min_value } keys %mirror2value;

    $possible[rand @possible];
}

#- hack to retrieve Mandrake Linux version...
sub version {
    require pkgs;
    my $pkg = pkgs::packageByName($::o->{packages}, 'mandrake-release');
    $pkg && $pkg->version || '9.0'; #- safe but dangerous ;-)
}

sub dir { $mirrors{$_[0]}[1] . '/' . version() }
sub ftp($) { ftp::new($_[0], dir($_[0])) }

sub getFile {
    my ($file, $host) = @_;
    $host ||= $crypto::host;
    my $dir = dir($host) . ($file =~ /\.rpm$/ && "/RPMS");
    log::l("getting crypto file $file on directory $dir with login $mirrors{$host}[2]");
    my ($ftp, $retr) = ftp::new($host, $dir,
				if_($mirrors{$host}[2], $mirrors{$host}[2]),
				if_($mirrors{$host}[3], $mirrors{$host}[3])
			       );
    $$retr->close if $$retr;
    $$retr   = $ftp->retr($file) or ftp::rewindGetFile();
    $$retr ||= $ftp->retr($file);
}

sub getPackages {
    my ($prefix, $packages, $mirror) = @_;

    $crypto::host = $mirror;

    #- check first if there is something to get...
    my $fhdlist = getFile("base/hdlist.cz", $mirror);
    unless ($fhdlist) {
	log::l("no updates available, bailing out");
	return;
    }
    
    #- extract hdlist of crypto, then depslist.
    require pkgs;
    my $update_medium = pkgs::psUsingHdlist($prefix, 'ftp', $packages, "hdlist-updates.cz", "1u", "RPMS",
					    "Updates for Mandrake Linux " . version(), 1, $fhdlist) and
					      log::l("read updates hdlist");
    #- keep in mind where is the URL prefix used according to mirror (for install_any::install_urpmi).
    $update_medium->{prefix} = "ftp://$mirror" . dir($mirror);
    #- (re-)enable the medium to allow install of package,
    #- make it an update medium (for install_any::install_urpmi).
    $update_medium->{selected} = 1;
    $update_medium->{update} = 1;

    #- search for packages to update.
    $packages->{rpmdb} ||= pkgs::rpmDbOpen($prefix);
    pkgs::selectPackagesToUpgrade($packages, $prefix, $update_medium);

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

1;
