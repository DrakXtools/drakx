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

sub packages($) { ftp($_[0])->ls }

sub get {
    my ($mirror, $dir, @files) = @_;
    foreach (@files) {
	log::l("crypto: downloading $_");
	ftp($mirror)->get($_, "$dir/$_") 
    }
    int @files;
}
