package crypto; # $Id$

use diagnostics;
use strict;

use vars qw(%url2land %land2tzs %static_mirrors %mirrors);

use common;
use log;
use ftp;

%url2land = (
	     at => N("Austria"),
	     au => N("Australia"),
	     be => N("Belgium"),
	     br => N("Brazil"),
	     ca => N("Canada"),
	     ch => N("Switzerland"),
	     cr => N("Costa Rica"),
	     cz => N("Czech Republic"),
	     de => N("Germany"),
	     dk => N("Denmark"),
	     ee => N("Estonia"),
	     es => N("Spain"),
	     fi => N("Finland"),
	     fr => N("France"),
	     gr => N("Greece"),
	     hu => N("Hungary"),
	     ie => N("Ireland"),
	     il => N("Israel"),
	     it => N("Italy"),
	     jp => N("Japan"),
	     nl => N("Netherlands"),
	     no => N("Norway"),
	     nz => N("New Zealand"),
	     pl => N("Poland"),
	     pt => N("Portugal"),
	     ru => N("Russia"),
	     se => N("Sweden"),
	     sk => N("Slovakia"),
	     th => N("Thailand"),
	     tw => N("Taiwan"),
	     za => N("South Africa"),
	    );

%land2tzs = (
	     N("Australia") => [ 'Australia/Sydney' ],
	     N("Austria") => [ 'Europe/Vienna', 'Europe/Brussels', 'Europe/Berlin' ],
	     N("Belgium") => [ 'Europe/Brussels', 'Europe/Paris', 'Europe/Berlin' ],
	     N("Brazil") => [ 'Brazil/East' ],
	     N("Canada") => [ 'Canada/Atlantic', 'Canada/Eastern' ],
	     N("Czech Republic") => [ 'Europe/Prague', 'Europe/Berlin' ],
	     N("Denmark") => [ 'Europe/Copenhagen', 'Europe/Berlin' ],
	     N("Estonia") => [ 'Europe/Tallinn', 'Europe/Helsinki' ],
	     N("Finland") => [ 'Europe/Helsinki', 'Europe/Tallinn' ],
	     N("France") => [ 'Europe/Paris', 'Europe/Brussels', 'Europe/Berlin' ],
	     N("Germany") => [ 'Europe/Berlin', 'Europe/Prague' ],
	     N("Greece") => [ 'Europe/Athens', 'Europe/Prague' ],
	     N("Hungary") => [ 'Europe/Budapest' ],
	     N("Ireland") => [ 'Europe/Dublin', 'Europe/London' ],
	     N("Israel") => [ 'Asia/Tel_Aviv' ],
	     N("Italy") => [ 'Europe/Rome', 'Europe/Brussels', 'Europe/Paris' ],
	     N("Japan") => [ 'Asia/Tokyo', 'Asia/Seoul' ],
	     N("Netherlands") => [ 'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Berlin' ],
	     N("New Zealand") => [ 'Pacific/Auckland' ],
	     N("Norway") => [ 'Europe/Oslo', 'Europe/Stockholm' ],
	     N("Poland") => [ 'Europe/Warsaw' ],
	     N("Portugal") => [ 'Europe/Lisbon', 'Europe/Madrid' ],
	     N("Russia") => [ 'Europe/Moscow', ],
	     N("Slovakia") => [ 'Europe/Bratislava' ],
	     N("South Africa") => [ 'Africa/Johannesburg' ],
	     N("Spain") => [ 'Europe/Madrid', 'Europe/Lisbon' ],
	     N("Sweden") => [ 'Europe/Stockholm', 'Europe/Oslo' ],
	     N("Switzerland") => [ 'Europe/Zurich', 'Europe/Berlin', 'Europe/Brussels' ],
	     N("Taiwan") => [ 'Asia/Taipei', 'Asia/Seoul' ],
	     N("Thailand") => [ 'Asia/Bangkok', 'Asia/Seoul' ],
	     N("United States") => [ 'America/New_York', 'Canada/Atlantic', 'Asia/Tokyo', 'Australia/Sydney', 'Europe/Paris' ],
	    );

%static_mirrors = (
#		   "ackbar" => [ "Ackbar", "/updates", "a", "a" ],
		  );

%mirrors = ();

sub mirror2text { $mirrors{$_[0]} && $mirrors{$_[0]}[0] . '|' . $_[0] }
sub mirrors {
    my ($o_distro_type, $o_use_local_list) = @_;

    unless (keys %mirrors) {
	my $f;
	if ($o_use_local_list) {
	    $f = \*DATA;
	} else {
	    #- contact the following URL to retrieve the list of mirrors.
	    require http;
	    $f = http::getFile("http://www.mandrivalinux.com/mirrorsfull.list");
	}

	local $SIG{ALRM} = sub { die "timeout" };
	$o_use_local_list or alarm 60;
	my $distro_type = $o_distro_type || 'updates';
	my $sub_dir = $distro_type =~ /cooker|community/ ? '' : '/' . version() . '/main_updates';
	foreach (<$f>) {
	    my ($arch, $url, $dir) = m|$distro_type([^:]*):ftp://([^/]*)(/\S*)| or next;
	    MDK::Common::System::compat_arch($arch) or next;
	    my $land = N("United States");
	    foreach (keys %url2land) {
		my $qu = quotemeta $_;
		$url =~ /\.$qu(?:\..*)?$/ and $land = $url2land{$_};
	    }
	    $mirrors{$url} = [ $land, $dir . $sub_dir ];
	}
	unless ($o_use_local_list) {
	    http::getFile('/XXX'); #- close connection.
	    alarm 0; 
	}

	#- now add static mirror (in case of something wrong happened above).
	add2hash(\%mirrors, \%static_mirrors);
    }
    keys %mirrors;
}

sub bestMirror {
    my ($string, $o_distro_type) = @_;
    my %mirror2value;

    foreach my $url (mirrors($o_distro_type)) {
	my $value = 0;
	my $cvalue = mirrors($o_distro_type);

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

#- hack to retrieve Mandriva Linux version... XXX figure out something more robust
sub version() {
    require pkgs;
    my $pkg = pkgs::packageByName($::o->{packages}, 'mandriva-release');
    my $v = $pkg && $pkg->version || '10.2'; #- safe but dangerous ;-)
    $v eq '2006.0' and $v = '10.2';
    $v;
}

sub dir { $mirrors{$_[0]}[1] }

sub getFile {
    my ($file, $o_host) = @_;
    my $host = $o_host || $crypto::host;
    my $dir = dir($host);
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
    my ($packages, $mirror) = @_;

    $crypto::host = $mirror;

    #- get pubkey file first as we cannot handle 2 files opened simultaneously.
    my $pubkey;
    eval {
	my $fpubkey = getFile("media_info/pubkey", $mirror);
	$pubkey = [ $packages->parse_armored_file($fpubkey) ];
    };

    #- check first if there is something to get...
    my $fhdlist = getFile("media_info/hdlist.cz", $mirror);
    unless ($fhdlist) {
	log::l("no updates available, bailing out");
	return;
    }
    
    #- extract hdlist of crypto, then depslist.
    require pkgs;
    my $update_medium = pkgs::psUsingHdlist('ftp', $packages, "hdlist-updates.cz", "1u", "",
					    "Updates for Mandriva Linux " . version(), 1, $fhdlist, $pubkey);
    if ($update_medium) {
	log::l("read updates hdlist");
	#- keep in mind where is the URL prefix used according to mirror (for install_any::install_urpmi).
	$update_medium->{prefix} = "ftp://$mirror" . dir($mirror);
	#- (re-)enable the medium to allow install of package,
	#- make it an update medium (for install_any::install_urpmi).
	$update_medium->select;
	$update_medium->{update} = 1;

	$install_any::global_ftp_prefix = [ $mirror, dir($mirror) ]; #- host, dir (for install_any::getFile)

	#- search for packages to update.
	$packages->{rpmdb} ||= pkgs::rpmDbOpen();
	pkgs::selectPackagesToUpgrade($packages, $update_medium);
    }
    return $update_medium;
}

1;

#- mirror list, hardcoded here to be used in mini-cds (ftp suppl. media)
__DATA__
communityi586:ftp://ftp-linux.cc.gatech.edu/pub/linux/distributions/mandrake/devel/community/i586/media/main
communityi586:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.gwdg.de/pub/linux/mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrake-devel/community/i586/media/main
communityi586:ftp://ftp.lip6.fr/pub/linux/distributions/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrake/devel/community/i586/media/main
communityi586:ftp://ftp.proxad.net/pub/Distributions_Linux/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.tugraz.at/mirror/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.u-strasbg.fr/pub/linux/distributions/mandrakelinux/devel/community/i586/media/main
communityi586:ftp://ftp.uninett.no/pub/unix/Linux/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://jungle.metalab.unc.edu/pub/Linux/distributions/mandrake/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://mandrake.contactel.cz/Mandrakelinux/devel/community/i586/media/main
communityi586:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake-devel/community/i586/media/main
communityi586:rsync://ftp.sunet.se::Mandrakelinux/devel/community/i586/media/main
communityi586:rsync://mirrors.usc.edu::mandrakelinux/devel/community/i586/media/main
cookeri586:ftp://anorien.csc.warwick.ac.uk/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://bo.mirror.garr.it/pub/mirrors/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://carroll.cac.psu.edu/pub/linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://chronos.iut-bm.univ-fcomte.fr/pub/linux/distributions/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://fr2.rpmfind.net/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.ale.org/pub/mirrors/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.aso.ee/pub/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.belnet.be/packages/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.bylinux.net/pub/mirror/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.cica.es/pub/Linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.ciril.fr/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.cise.ufl.edu/pub/mirrors/mandrake/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.esat.net/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.fh-giessen.de/pub/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.fh-wolfenbuettel.de/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.free.fr/mirrors/ftp.mandriva.com/MandrivaLinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.gtlib.cc.gatech.edu/pub/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.heanet.ie/pub/mandrake/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.icm.edu.pl/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.informatik.hu-berlin.de/pub/Linux/Distributions/Mandrake/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.is.co.za/linux/distributions/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.isu.net.sa/pub/mirrors/ftp.mandrake.com/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.kddlabs.co.jp/Linux/packages/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.lip6.fr/pub/linux/distributions/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.mandrake.ikoula.com/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.nara.wide.ad.jp/pub/Linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.ndlug.nd.edu/pub/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.pbone.net/pub/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.phys.ttu.edu/pub/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.physics.auth.gr/pub/mirrors/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.planetmirror.com/pub/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.ps.pl/mirrors/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.rediris.es/pub/linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.riken.go.jp/pub/Linux/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://ftp.rutgers.edu/pub/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.sunsite.org.uk/package/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.tu-chemnitz.de/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.tuniv.szczecin.pl/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.uasw.edu/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.uio.no/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.uni-bayreuth.de/pub/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.uninett.no/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp.vat.tu-dresden.de/pub/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ftp3.mandrake.sk/mirrors/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://helios.dii.utk.edu/pub/linux/Mandrake/devel/cooker/i586/media/main
cookeri586:ftp://linux.ntcu.net/dists/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://mandrake.mirrors.pair.com/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mdk.linux.org.tw/pub/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mirror.averse.net/pub/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mirror.etf.bg.ac.yu/distributions/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mirror.fis.unb.br/pub/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mirror.mandrakelinux.cn/FreeOS/MandrivaLinux/devel/cooker/i586/media/main
cookeri586:ftp://mirror.switch.ch/mirror/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://mirrors.usc.edu/pub/linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://ramses.wh2.tu-dresden.de/pub/mirrors/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://raven.cslab.vt.edu/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://sunsite.cnlab-switch.ch/mirror/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake/devel/cooker/i586/media/main
cookeri586:ftp://sunsite.mff.cuni.cz/OS/Linux/Dist/Mandrake/mandrake/devel/cooker/i586/media/main
cookeri586:http://anorien.csc.warwick.ac.uk/mirrors/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://fr2.rpmfind.net/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://ftp.ale.org/pub/mirrors/mandrake/devel/cooker/i586/media/main
cookeri586:http://ftp.esat.net/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://ftp.nluug.nl/ftp/pub/os/Linux/distr/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://ftp.rediris.es/pub/linux/distributions/mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://ftp.riken.go.jp/Linux/mandrake/devel/cooker/i586/media/main
cookeri586:http://ftp.surfnet.nl/ftp/pub/os/Linux/distr/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://gd.tuwien.ac.at/pub/linux/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://gulus.usherbrooke.ca/pub/distro/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://mandrake.mirrors.pair.com/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:http://www.gtlib.cc.gatech.edu/pub/mandrake/devel/cooker/i586/media/main
cookeri586:rsync://carroll.cac.psu.edu/mandrakelinux/devel/cooker/i586/media/main
cookeri586:rsync://ftp.esat.net/ftp/pub/linux/mandrakelinux/devel/cooker/i586/media/main
cookeri586:rsync://ftp.join.uni-muenster.de/mandrakelinux/devel/cooker/i586/media/main
cookeri586:rsync://ftp.nluug.nl/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:rsync://ftp.riken.go.jp/mandrake/devel/cooker/i586/media/main
cookeri586:rsync://ftp.surfnet.nl/Mandrakelinux/devel/cooker/i586/media/main
cookeri586:rsync://rsync.gtlib.cc.gatech.edu/mandrake/devel/cooker/i586/media/main
cookerppc:ftp://ftp-linux.cc.gatech.edu/pub/linux/distributions/mandrake/devel/cooker/ppc/media/main
cookerppc:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.gwdg.de/pub/linux/mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrake-devel/cooker/ppc/media/main
cookerppc:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrake/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.proxad.net/pub/Distributions_Linux/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.tugraz.at/mirror/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://ftp.uninett.no/pub/unix/Linux/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://mandrake.contactel.cz/Mandrakelinux/devel/cooker/ppc/media/main
cookerppc:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake-devel/cooker/ppc/media/main
cookerx86_64:ftp://ftp-linux.cc.gatech.edu/pub/linux/distributions/mandrake/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.gwdg.de/pub/linux/mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrake-devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrake/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.proxad.net/pub/Distributions_Linux/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.tugraz.at/mirror/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://ftp.uninett.no/pub/unix/Linux/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/devel/cooker/x86_64/media/main
cookerx86_64:ftp://mandrake.contactel.cz/Mandrakelinux/devel/cooker/x86_64/media/main
officiali586:ftp://bo.mirror.garr.it/pub/mirrors/Mandrake/official/current/i586/media/main/
officiali586:ftp://carroll.cac.psu.edu/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://chronos.iut-bm.univ-fcomte.fr/pub/linux/distributions/Mandrake/official/current/i586/media/main/
officiali586:ftp://fr2.rpmfind.net/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ale.org/pub/mirrors/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.aso.ee/pub/Mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.belnet.be/packages/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.cica.es/pub/Linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ciril.fr/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.cise.ufl.edu/pub/mirrors/mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.cru.fr/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.cse.buffalo.edu/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ens-cachan.fr/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.esat.net/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.fh-giessen.de/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.fh-wolfenbuettel.de/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.free.fr/mirrors/ftp.mandriva.com/MandrivaLinux/official/current/i586/media/main/
officiali586:ftp://ftp.fsn.hu/pub/linux/distributions/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.gtlib.cc.gatech.edu/pub/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.iasi.roedu.net/mirrors/ftp.mandrake.com/official/current/i586/media/main/
officiali586:ftp://ftp.informatik.hu-berlin.de/pub/Linux/Distributions/Mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.int-evry.fr/pub/linux/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.is.co.za/linux/distributions/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.isu.edu.tw/pub/Linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.isu.net.sa/pub/mirrors/ftp.mandrake.com/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.kddlabs.co.jp/Linux/packages/Mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.linux.cz/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.lip6.fr/pub/linux/distributions/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.mandrake.ikoula.com/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/current/i586/media/main/
officiali586:ftp://ftp.nara.wide.ad.jp/pub/Linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ndlug.nd.edu/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ntua.gr/pub/linux/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.pbone.net/pub/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.phys.ttu.edu/pub/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.physics.auth.gr/pub/mirrors/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.prew.hu/pub/Linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.ps.pl/mirrors/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.rutgers.edu/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.song.fi/pub/mirrors/Mandrake-linux/official/current/i586/media/main/
officiali586:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.sunsite.org.uk/package/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.tuniv.szczecin.pl/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.u-strasbg.fr/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.uasw.edu/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.uio.no/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.uni-bayreuth.de/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.unina.it/pub/linux/distributions/Mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.uninett.no/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp.uvsq.fr/pub/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.uwsg.indiana.edu/linux/mandrake/official/current/i586/media/main/
officiali586:ftp://ftp.vat.tu-dresden.de/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://ftp3.mandrake.sk/mirrors/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://helios.dii.utk.edu/pub/linux/Mandrake/official/current/i586/media/main/
officiali586:ftp://linux.ntcu.net/dists/mandrake/official/current/i586/media/main/
officiali586:ftp://linux.ups-tlse.fr/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mandrake.contactel.cz/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mandrake.mirrors.pair.com/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mdk.linux.org.tw/pub/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.averse.net/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.cs.wisc.edu/pub/mirrors/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.etf.bg.ac.yu/distributions/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.fis.unb.br/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.inspire.net.nz/mandrake//official/current/i586/media/main/
officiali586:ftp://mirror.mandrakelinux.cn/FreeOS/MandrivaLinux/official/current/i586/media/main/
officiali586:ftp://mirror.switch.ch/mirror/mandrake/official/current/i586/media/main/
officiali586:ftp://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirror.usu.edu/mirrors/Mandrake/official/current/i586/media/main/
officiali586:ftp://mirrors.dotsrc.org/mandrake/official/current/i586/media/main/
officiali586:ftp://mirrors.ptd.net/mandrake/official/current/i586/media/main/
officiali586:ftp://mirrors.secsup.org/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirrors.usc.edu/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://mirrors.xmission.com/mandrake/official/current/i586/media/main/
officiali586:ftp://ramses.wh2.tu-dresden.de/pub/mirrors/mandrake/official/current/i586/media/main/
officiali586:ftp://raven.cslab.vt.edu/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://sunsite.cnlab-switch.ch/mirror/mandrake/official/current/i586/media/main/
officiali586:ftp://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/current/i586/media/main/
officiali586:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake/official/current/i586/media/main/
officiali586:ftp://sunsite.mff.cuni.cz/OS/Linux/Dist/Mandrake/mandrake/official/current/i586/media/main/
officiali586:http://fr2.rpmfind.net/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.ale.org/pub/mirrors/mandrake/official/current/i586/media/main/
officiali586:http://ftp.club-internet.fr/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.esat.net/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.iasi.roedu.net/mirrors/ftp.mandrake.com/official/current/i586/media/main/
officiali586:http://ftp.isu.edu.tw/pub/Linux/Mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.isu.net.sa/pub/mirrors/ftp.mandrake.com/mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.kddlabs.co.jp/Linux/distributions/Mandrake/official/current/i586/media/main/
officiali586:http://ftp.nluug.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/current/i586/media/main/
officiali586:http://ftp.surfnet.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/current/i586/media/main/
officiali586:http://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/current/i586/media/main/
officiali586:http://gulus.usherbrooke.ca/pub/distro/Mandrakelinux/official/current/i586/media/main/
officiali586:http://mandrake.mirrors.pair.com/Mandrakelinux/official/current/i586/media/main/
officiali586:http://mirror.averse.net/pub/Mandrakelinux/official/current/i586/media/main/
officiali586:http://mirror.etf.bg.ac.yu/distributions/Mandrakelinux/official/current/i586/media/main/
officiali586:http://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/current/i586/media/main/
officiali586:http://mirror.usu.edu/mirrors/Mandrake/official/current/i586/media/main/
officiali586:http://mirrors.dotsrc.org/mandrake/official/current/i586/media/main/
officiali586:http://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/current/i586/media/main/
officiali586:http://wftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:http://www.gtlib.cc.gatech.edu/pub/mandrake/official/current/i586/media/main/
officiali586:http://www.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/current/i586/media/main/
officiali586:http://www.sunsite.org.uk/package/mandrakelinux/official/current/i586/media/main/
officiali586:rsync://carroll.cac.psu.edu/mandrakelinux/official/current/i586/media/main/
officiali586:rsync://ftp.esat.net/ftp/pub/linux/mandrakelinux/official/current/i586/media/main/
officiali586:rsync://ftp.iasi.roedu.net/mandrake.com/official/current/i586/media/main/
officiali586:rsync://ftp.join.uni-muenster.de/mandrakelinux/official/current/i586/media/main/
officiali586:rsync://ftp.nluug.nl/Mandrakelinux/official/current/i586/media/main/
officiali586:rsync://ftp.surfnet.nl/Mandrakelinux/official/current/i586/media/main/
officiali586:rsync://mirror.umr.edu/mandrake/official/current/i586/media/main/
officiali586:rsync://mirror.usu.edu/mandrake/official/current/i586/media/main/
updatesi586:ftp://anorien.csc.warwick.ac.uk/Mandrakelinux/official/updates
updatesi586:ftp://bo.mirror.garr.it/pub/mirrors/Mandrake/official/updates
updatesi586:ftp://carroll.cac.psu.edu/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://chronos.iut-bm.univ-fcomte.fr/pub/linux/distributions/Mandrake/official/updates
updatesi586:ftp://fr2.rpmfind.net/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ale.org/pub/mirrors/mandrake/official/updates
updatesi586:ftp://ftp.aso.ee/pub/Mandrake/official/updates
updatesi586:ftp://ftp.belnet.be/packages/mandrakelinux/official/updates
updatesi586:ftp://ftp.cica.es/pub/Linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ciril.fr/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.cise.ufl.edu/pub/mirrors/mandrake/Mandrakelinux/official/updates
updatesi586:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/official/updates
updatesi586:ftp://ftp.cru.fr/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.cse.buffalo.edu/pub/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ens-cachan.fr/pub/Mandrakelinux/official/updates
updatesi586:ftp://ftp.esat.net/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.fh-giessen.de/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.fh-wolfenbuettel.de/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.free.fr/mirrors/ftp.mandriva.com/MandrivaLinux/official/updates
updatesi586:ftp://ftp.fsn.hu/pub/linux/distributions/mandrake/official/updates
updatesi586:ftp://ftp.gtlib.cc.gatech.edu/pub/mandrake/official/updates
updatesi586:ftp://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/updates
updatesi586:ftp://ftp.iasi.roedu.net/mirrors/ftp.mandrake.com/official/updates
updatesi586:ftp://ftp.icm.edu.pl/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.informatik.hu-berlin.de/pub/Linux/Distributions/Mandrake/Mandrakelinux/official/updates
updatesi586:ftp://ftp.is.co.za/linux/distributions/mandrake/official/updates
updatesi586:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://ftp.kddlabs.co.jp/Linux/packages/Mandrake/official/updates
updatesi586:ftp://ftp.linux.cz/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.lip6.fr/pub/linux/distributions/Mandrakelinux/official/updates
updatesi586:ftp://ftp.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/updates
updatesi586:ftp://ftp.mirrorservice.org/pub/Mandrake_Linux/official/updates
updatesi586:ftp://ftp.mki.fh-duesseldorf.de/Mirror/Mandrake/official/updates
updatesi586:ftp://ftp.nara.wide.ad.jp/pub/Linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ndlug.nd.edu/pub/Mandrakelinux/official/updates
updatesi586:ftp://ftp.nectec.or.th/pub/linux-distributions/Mandrake/official/updates
updatesi586:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ntua.gr/pub/linux/mandrake/official/updates
updatesi586:ftp://ftp.pbone.net/pub/mandrakelinux/official/updates
updatesi586:ftp://ftp.phys.ttu.edu/pub/mandrakelinux/official/updates
updatesi586:ftp://ftp.physics.auth.gr/pub/mirrors/Mandrakelinux/official/updates
updatesi586:ftp://ftp.prew.hu/pub/Linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.ps.pl/mirrors/mandrake/official/updates
updatesi586:ftp://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://ftp.riken.go.jp/pub/Linux/mandrake/official/updates
updatesi586:ftp://ftp.rutgers.edu/pub/Mandrakelinux/official/updates
updatesi586:ftp://ftp.song.fi/pub/mirrors/Mandrake-linux/official/updates
updatesi586:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://ftp.sunsite.org.uk/package/mandrakelinux/official/updates
updatesi586:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/official/updates
updatesi586:ftp://ftp.task.gda.pl/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.tuniv.szczecin.pl/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.u-strasbg.fr/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://ftp.uasw.edu/linux/mandrakelinux/official/updates
updatesi586:ftp://ftp.uio.no/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.uni-bayreuth.de/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.unina.it/pub/linux/distributions/Mandrake/official/updates
updatesi586:ftp://ftp.uninett.no/linux/Mandrakelinux/official/updates
updatesi586:ftp://ftp.univ-lille1.fr/pub/os/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://ftp.uvsq.fr/pub/mandrake/official/updates
updatesi586:ftp://ftp.uwsg.indiana.edu/linux/mandrake/official/updates
updatesi586:ftp://ftp.vat.tu-dresden.de/pub/Mandrakelinux/official/updates
updatesi586:ftp://ftp3.mandrake.sk/mirrors/Mandrakelinux/official/updates
updatesi586:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://helios.dii.utk.edu/pub/linux/Mandrake/official/updates
updatesi586:ftp://linux.ntcu.net/dists/mandrake/official/updates
updatesi586:ftp://mandrake.contactel.cz/Mandrakelinux/official/updates
updatesi586:ftp://mandrake.mirrors.pair.com/Mandrakelinux/official/updates
updatesi586:ftp://mdk.linux.org.tw/pub/mandrakelinux/official/updates
updatesi586:ftp://mirror.averse.net/pub/Mandrakelinux/official/updates
updatesi586:ftp://mirror.cs.wisc.edu/pub/mirrors/linux/Mandrakelinux/official/updates
updatesi586:ftp://mirror.fis.unb.br/pub/linux/Mandrakelinux/official/updates
updatesi586:ftp://mirror.inspire.net.nz/mandrake//official/updates
updatesi586:ftp://mirror.mandrakelinux.cn/FreeOS/MandrivaLinux/official/updates
updatesi586:ftp://mirror.switch.ch/mirror/mandrake/official/updates
updatesi586:ftp://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/updates
updatesi586:ftp://mirror.usu.edu/mirrors/Mandrake/official/updates
updatesi586:ftp://mirrors.dotsrc.org/mandrake/official/updates
updatesi586:ftp://mirrors.ptd.net/mandrake/official/updates
updatesi586:ftp://mirrors.secsup.org/pub/linux/mandrakelinux/official/updates
updatesi586:ftp://mirrors.usc.edu/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:ftp://mirrors.xmission.com/mandrake/official/updates
updatesi586:ftp://ramses.wh2.tu-dresden.de/pub/mirrors/mandrake/official/updates
updatesi586:ftp://sunsite.cnlab-switch.ch/mirror/mandrake/official/updates
updatesi586:ftp://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/updates
updatesi586:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake/official/updates
updatesi586:ftp://sunsite.mff.cuni.cz/OS/Linux/Dist/Mandrake/mandrake/official/updates
updatesi586:http://anorien.csc.warwick.ac.uk/mirrors/Mandrakelinux/official/updates
updatesi586:http://fr2.rpmfind.net/linux/Mandrakelinux/official/updates
updatesi586:http://ftp.ale.org/pub/mirrors/mandrake/official/updates
updatesi586:http://ftp.club-internet.fr/pub/linux/Mandrakelinux/official/updates
updatesi586:http://ftp.esat.net/pub/linux/mandrakelinux/official/updates
updatesi586:http://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/updates
updatesi586:http://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/updates
updatesi586:http://ftp.iasi.roedu.net/mirrors/ftp.mandrake.com/official/updates
updatesi586:http://ftp.isu.edu.tw/pub/Linux/Mandrakelinux/official/updates
updatesi586:http://ftp.kddlabs.co.jp/Linux/distributions/Mandrake/official/updates
updatesi586:http://ftp.nluug.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/updates
updatesi586:http://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/updates
updatesi586:http://ftp.riken.go.jp/Linux/mandrake/official/updates
updatesi586:http://ftp.surfnet.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/updates
updatesi586:http://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/updates
updatesi586:http://gulus.usherbrooke.ca/pub/distro/Mandrakelinux/official/updates
updatesi586:http://mandrake.mirrors.pair.com/Mandrakelinux/official/updates
updatesi586:http://mirror.averse.net/pub/Mandrakelinux/official/updates
updatesi586:http://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/updates
updatesi586:http://mirror.usu.edu/mirrors/Mandrake/official/updates
updatesi586:http://mirrors.dotsrc.org/mandrake/official/updates
updatesi586:http://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/updates
updatesi586:http://wftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/updates
updatesi586:http://www.gtlib.cc.gatech.edu/pub/mandrake/official/updates
updatesi586:http://www.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/updates
updatesi586:http://www.sunsite.org.uk/package/mandrakelinux/official/updates
updatesi586:rsync://carroll.cac.psu.edu/mandrakelinux/official/updates
updatesi586:rsync://ftp.esat.net/ftp/pub/linux/mandrakelinux/official/updates
updatesi586:rsync://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/updates
updatesi586:rsync://ftp.iasi.roedu.net/mandrake.com/official/updates
updatesi586:rsync://ftp.join.uni-muenster.de/mandrakelinux/official/updates
updatesi586:rsync://ftp.nluug.nl/Mandrakelinux/official/updates
updatesi586:rsync://ftp.riken.go.jp/mandrake/official/updates
updatesi586:rsync://ftp.surfnet.nl/Mandrakelinux/official/updates
updatesi586:rsync://mirror.umr.edu/mandrake/official/updates
updatesi586:rsync://mirror.usu.edu/mandrake/official/updates
updatesi586:rsync://rsync.gtlib.cc.gatech.edu/mandrake/official/updates
updatesi586:rsync://rsync.mirrorservice.org/sunsite.uio.no/pub/unix/Linux/mandrakelinux/official/updates
updatesi586:rsync://rsync.uni-bayreuth.de/Mandrakelinux/official/updates
updatesppc:ftp://ftp-linux.cc.gatech.edu/pub/linux/distributions/mandrake/official/updates/ppc
updatesppc:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.esat.net/pub/linux/mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.gwdg.de/pub/linux/mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.ikoula.com/pub/ftp.mandrake-linux.com/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrake/updates/ppc
updatesppc:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.pcds.ch/pub/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.proxad.net/pub/Distributions_Linux/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.ps.pl/mirrors/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.tugraz.at/mirror/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.uni-bayreuth.de/pub/linux/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.uninett.no/pub/unix/Linux/Mandrakelinux/official/updates/ppc
updatesppc:ftp://ftp.vat.tu-dresden.de/pub/Mandrakelinux/official/updates/ppc
updatesppc:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/updates/ppc
updatesppc:ftp://jungle.metalab.unc.edu/pub/Linux/distributions/mandrake/Mandrakelinux/official/updates/ppc
updatesppc:ftp://linux.cdpa.nsysu.edu.tw/pub/mandrake/updates/ppc
updatesppc:ftp://mandrake.contactel.cz/Mandrakelinux/official/updates/ppc
updatesppc:ftp://mandrake.mirrors.pair.com/Mandrakelinux/official/updates/ppc
updatesppc:ftp://mirrors.secsup.org/pub/linux/mandrake/Mandrakelinux/official/updates/ppc
updatesppc:ftp://spirit.profinet.sk/mirrors/Mandrake/updates/ppc
updatesppc:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake/updates/ppc
updatesppc:ftp://updates.roma2.infn.it/linux/updates/mandrake/ppc
updatesppc:rsync://ftp.sunet.se::Mandrakelinux/official/updates/ppc
updatesppc:rsync://mirrors.usc.edu::mandrakelinux/official/updates/ppc
updatesx86_64:ftp://anorien.csc.warwick.ac.uk/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://bo.mirror.garr.it/pub/mirrors/Mandrake/official/updates/x86_64
updatesx86_64:ftp://carroll.cac.psu.edu/pub/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://chronos.iut-bm.univ-fcomte.fr/pub/linux/distributions/Mandrake/official/updates/x86_64
updatesx86_64:ftp://fr2.rpmfind.net/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.ale.org/pub/mirrors/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.aso.ee/pub/Mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.belnet.be/packages/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.cica.es/pub/Linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.ciril.fr/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.club-internet.fr/pub/unix/linux/distributions/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.cru.fr/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.cse.buffalo.edu/pub/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.ens-cachan.fr/pub/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.esat.net/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.fh-giessen.de/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.fh-wolfenbuettel.de/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.free.fr/mirrors/ftp.mandriva.com/MandrivaLinux/official/updates/x86_64
updatesx86_64:ftp://ftp.fsn.hu/pub/linux/distributions/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.gtlib.cc.gatech.edu/pub/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.icm.edu.pl/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.informatik.hu-berlin.de/pub/Linux/Distributions/Mandrake/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.is.co.za/linux/distributions/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.join.uni-muenster.de/pub/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.kddlabs.co.jp/Linux/packages/Mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.linux.cz/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.lip6.fr/pub/linux/distributions/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/updates/x86_64
updatesx86_64:ftp://ftp.mirrorservice.org/pub/Mandrake_Linux/official/updates/x86_64
updatesx86_64:ftp://ftp.nara.wide.ad.jp/pub/Linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.ndlug.nd.edu/pub/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.nectec.or.th/pub/linux-distributions/Mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.phys.ttu.edu/pub/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.physics.auth.gr/pub/mirrors/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.ps.pl/mirrors/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.riken.go.jp/pub/Linux/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.rutgers.edu/pub/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.sunet.se/pub/Linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.sunsite.org.uk/package/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.surfnet.nl/pub/os/Linux/distr/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.task.gda.pl/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.tuniv.szczecin.pl/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.uasw.edu/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.uio.no/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.uni-bayreuth.de/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.unina.it/pub/linux/distributions/Mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.uninett.no/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.univ-lille1.fr/pub/os/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://ftp.uwsg.indiana.edu/linux/mandrake/official/updates/x86_64
updatesx86_64:ftp://ftp.vat.tu-dresden.de/pub/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://helios.dii.utk.edu/pub/linux/Mandrake/official/updates/x86_64
updatesx86_64:ftp://linux.ntcu.net/dists/mandrake/official/updates/x86_64
updatesx86_64:ftp://mandrake.contactel.cz/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mandrake.mirrors.pair.com/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mdk.linux.org.tw/pub/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirror.cs.wisc.edu/pub/mirrors/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirror.fis.unb.br/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirror.inspire.net.nz/mandrake//official/updates/x86_64
updatesx86_64:ftp://mirror.switch.ch/mirror/mandrake/official/updates/x86_64
updatesx86_64:ftp://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirror.usu.edu/mirrors/Mandrake/official/updates/x86_64
updatesx86_64:ftp://mirrors.dotsrc.org/mandrake/official/updates/x86_64
updatesx86_64:ftp://mirrors.ptd.net/mandrake/official/updates/x86_64
updatesx86_64:ftp://mirrors.secsup.org/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirrors.usc.edu/pub/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://mirrors.xmission.com/mandrake/official/updates/x86_64
updatesx86_64:ftp://ramses.wh2.tu-dresden.de/pub/mirrors/mandrake/official/updates/x86_64
updatesx86_64:ftp://sunsite.cnlab-switch.ch/mirror/mandrake/official/updates/x86_64
updatesx86_64:ftp://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/updates/x86_64
updatesx86_64:ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/mandrake/official/updates/x86_64
updatesx86_64:ftp://sunsite.mff.cuni.cz/OS/Linux/Dist/Mandrake/mandrake/official/updates/x86_64
updatesx86_64:http://anorien.csc.warwick.ac.uk/mirrors/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://fr2.rpmfind.net/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.ale.org/pub/mirrors/mandrake/official/updates/x86_64
updatesx86_64:http://ftp.club-internet.fr/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.esat.net/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.fi.muni.cz/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.heanet.ie/pub/mandrake/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.isu.edu.tw/pub/Linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.kddlabs.co.jp/Linux/distributions/Mandrake/official/updates/x86_64
updatesx86_64:http://ftp.nluug.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.rediris.es/pub/linux/distributions/mandrakelinux/official/updates/x86_64
updatesx86_64:http://ftp.riken.go.jp/Linux/mandrake/official/updates/x86_64
updatesx86_64:http://ftp.surfnet.nl/ftp/pub/os/Linux/distr/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://gd.tuwien.ac.at/pub/linux/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://gulus.usherbrooke.ca/pub/distro/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://mandrake.mirrors.pair.com/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://mirror.umr.edu/pub/linux/mandrake/Mandrakelinux/official/updates/x86_64
updatesx86_64:http://mirror.usu.edu/mirrors/Mandrake/official/updates/x86_64
updatesx86_64:http://mirrors.dotsrc.org/mandrake/official/updates/x86_64
updatesx86_64:http://sunsite.icm.edu.pl/pub/Linux/mandrakelinux/official/updates/x86_64
updatesx86_64:http://wftp.tu-chemnitz.de/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:http://www.gtlib.cc.gatech.edu/pub/mandrake/official/updates/x86_64
updatesx86_64:http://www.mirror.ac.uk/sites/sunsite.uio.no/ftp/linux/mdl/official/updates/x86_64
updatesx86_64:http://www.sunsite.org.uk/package/mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://carroll.cac.psu.edu/mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://ftp.esat.net/ftp/pub/linux/mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://ftp.join.uni-muenster.de/mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://ftp.nluug.nl/Mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://ftp.riken.go.jp/mandrake/official/updates/x86_64
updatesx86_64:rsync://ftp.surfnet.nl/Mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://mirror.umr.edu/mandrake/official/updates/x86_64
updatesx86_64:rsync://mirror.usu.edu/mandrake/official/updates/x86_64
updatesx86_64:rsync://rsync.gtlib.cc.gatech.edu/mandrake/official/updates/x86_64
updatesx86_64:rsync://rsync.mirrorservice.org/sunsite.uio.no/pub/unix/Linux/mandrakelinux/official/updates/x86_64
updatesx86_64:rsync://rsync.uni-bayreuth.de/Mandrakelinux/official/updates/x86_64
