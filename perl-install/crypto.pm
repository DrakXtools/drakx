package crypto;

use diagnostics;
use strict;

use common qw(:common);
use log;
use ftp;

my %mirrors = (
 "ftp.ucr.ac.cr" => [ "Costa Rica", "/pub/Unix/linux/mandrake/Mandrake" ],
 "ftp.nectec.or.th" => [ "Thailand", "/pub/mirrors/Mandrake-crypto" ],
 "ftp.tvd.be" => [ "Belgium", "/packages/mandrake-crypto" ],
 "sunsite.mff.cuni.cz" => [ "Czech Republic", "/OS/Linux/Dist/Mandrake-crypto" ],
 "ftp.uni-kl.de" => [ "Germany", "/pub/linux/mandrake/Mandrake-crypto" ],
 "ftp.duth.gr" => [ "Grece", "/pub/mandrake-crypto" ],
 "ftp.leo.org" => [ "Germany", "/pub/comp/os/unix/linux/Mandrake/Mandrake-crypto" ],
 "sunsite.uio.no" => [ "Norway", "/pub/unix/Linux/Mandrake-crypto" ],
 "ftp.sunet.se" => [ "Sweden", "/pub/Linux/distributions/mandrake-crypto" ],
#- "ackbar" => [ "Ackbar", "/crypto", "a", "a" ],
);

my %deps = (
  'libcrypto.so.0' => 'openssl',
  'libssl.so.0' => 'openssl',
  'mod_sxnet.so' => 'mod_ssl-sxnet',
);

sub require2package { $deps{$_[0]} || $_[0] }
sub mirror2text($) { $mirrors{$_[0]} && "$mirrors{$_[0]}[0] ($_[0])" }
sub mirrorstext() { map { mirror2text($_) } keys %mirrors }
sub text2mirror($) { first($_[0] =~ /\((.*)\)$/) }
sub ftp($) { ftp::new($_[0], "$mirrors{$_[0]}[1]/$::VERSION") }

sub getFile($$) {
    my ($file, $host) = @_;
    log::l("getting crypto file $file on directory $host:$mirrors{$host}[1]/$::VERSION with login $mirrors{$host}[2]");
    my ($ftp, $retr) = ftp::new($_[1], "$mirrors{$host}[1]/$::VERSION",
				$mirrors{$host}[2] ? $mirrors{$host}[2] : (),
				$mirrors{$host}[3] ? $mirrors{$host}[3] : ()
			       );
    $$retr->close if $$retr;
    $$retr   = $ftp->retr($file) or ftp::rewindGetFile();
    $$retr ||= $ftp->retr($file);
}

sub getDepslist($) { getFile("depslist-crypto", $_[0]) or die "unable to get depslist-crypto" }
sub getHdlist($) { getFile("hdlist-crypto.cz2", $_[0]) or die "unable to get hdlist-crypto.cz2" }

#sub packages($) { ftp($_[0])->ls }
sub getPackages($) {
    my ($prefix, $packages, $mirror) = @_;

    #- extract hdlist of crypto, then depslist.
    require pkgs;
    pkgs::psUsingHdlist($prefix, '', $packages, getHdlist($mirror), "hdlistCrypto.cz2", "Crypto", '', "Crytographic site", 1) and
	pkgs::getOtherDeps($packages, getDepslist($mirror));

    #- produce an output suitable for visualization.
    map { pkgs::packageName($_) } pkgs::packagesOfMedium($packages, "Crypto");
}

sub get {
    my ($mirror, $dir, @files) = @_;
    foreach (@files) {
	log::l("crypto: downloading $_");
	ftp($mirror)->get($_, "$dir/$_") 
    }
    int @files;
}
