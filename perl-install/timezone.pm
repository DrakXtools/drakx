package timezone; # $Id$

use diagnostics;
use strict;

use common;
use log;


sub getTimeZones {
    my ($prefix) = @_;
    $::testing and $prefix = '';
    open(my $F, "cd $prefix/usr/share/zoneinfo && find [A-Z]* -type f |");
    my @l = chomp_(<$F>);
    close $F or die "cannot list the available zoneinfos";
    sort @l;
}

sub read {
    my %t = getVarsFromSh("$::prefix/etc/sysconfig/clock") or return {};
    { timezone => $t{ZONE}, UTC => text2bool($t{UTC}) };
}

sub ntp_server {
    my ($prefix, $server) = @_;

    my $f = "$prefix/etc/ntp.conf";
    -e $f or return;

    if (@_ > 1) {
	my $added = 0;
	substInFile {
	    if (/^#?\s*server\s+(\S*)/ && $1 ne '127.127.1.0') {
		$_ = $added ? "#server $1\n" : "server $server\n";
		$added = 1;
	    }
	} $f;
	output("$prefix/etc/ntp/step-tickers", "$server\n");
    } else {
	$server = find { $_ ne '127.127.1.0' } map { if_(/^\s*server\s+(\S*)/, $1) } cat_($f);
    }
    $server;
}

sub write {
    my ($prefix, $t) = @_;

    ntp_server($prefix, $t->{ntp});

    eval { cp_af("$prefix/usr/share/zoneinfo/$t->{timezone}", "$prefix/etc/localtime") };
    $@ and log::l("installing /etc/localtime failed");
    setVarsInSh("$prefix/etc/sysconfig/clock", {
	ZONE => $t->{timezone},
	UTC  => bool2text($t->{UTC}),
	ARC  => "false",
    });
}

#- best guesses for a given country
my %c2t = (
'AM' => 'Asia/Yerevan',
'AR' => 'America/Buenos_Aires',
'AT' => 'Europe/Vienna',
'AU' => 'Australia/Sydney',
'BA' => 'Europe/Sarajevo',
'BE' => 'Europe/Brussels',
'BG' => 'Europe/Sofia',
'BR' => 'Brazil/East', #- most people live on the east coast
'BY' => 'Europe/Minsk',
'CA' => 'Canada/Eastern',
'CH' => 'Europe/Zurich',
'CN' => 'Asia/Beijing',
'CZ' => 'Europe/Prague',
'DE' => 'Europe/Berlin',
'DK' => 'Europe/Copenhagen',
'EE' => 'Europe/Tallinn',
'ES' => 'Europe/Madrid',
'FI' => 'Europe/Helsinki',
'FR' => 'Europe/Paris',
'GB' => 'Europe/London',
'GE' => 'Asia/Yerevan',
'GL' => 'Arctic/Longyearbyen',
'GR' => 'Europe/Athens',
'HR' => 'Europe/Zagreb',
'HU' => 'Europe/Budapest',
'ID' => 'Asia/Jakarta',
'IE' => 'Europe/Dublin',
'IL' => 'Asia/Tel_Aviv',
'IN' => 'Asia/Calcutta',
'IR' => 'Asia/Tehran',
'IS' => 'Atlantic/Reykjavik',
'IT' => 'Europe/Rome',
'JP' => 'Asia/Tokyo',
'KR' => 'Asia/Seoul',
'LT' => 'Europe/Vilnius',
'LV' => 'Europe/Riga',
'MK' => 'Europe/Skopje',
'MT' => 'Europe/Malta',
'MX' => 'America/Mexico_City',
'MY' => 'Asia/Kuala_Lumpur',
'NL' => 'Europe/Amsterdam',
'NO' => 'Europe/Oslo',
'NZ' => 'Pacific/Auckland',
'PL' => 'Europe/Warsaw',
'PT' => 'Europe/Lisbon',
'RO' => 'Europe/Bucharest',
'RU' => 'Europe/Moscow',
'SE' => 'Europe/Stockholm',
'SI' => 'Europe/Ljubljana',
'SK' => 'Europe/Bratislava',
'TH' => 'Asia/Bangkok',
'TJ' => 'Asia/Dushanbe',
'TR' => 'Europe/Istanbul',
'TW' => 'Asia/Taipei',
'UA' => 'Europe/Kiev',
'US' => 'America/New_York',
'UZ' => 'Asia/Tashkent',
'VN' => 'Asia/Saigon',
'YU' => 'Europe/Belgrade',
'ZA' => 'Africa/Johannesburg',
);

sub fuzzyChoice { 
    my ($b, $count) = bestMatchSentence($_[0], keys %c2t);
    $count ? $b : '';
}
sub bestTimezone { $c2t{fuzzyChoice($_[0])} || 'GMT' }

sub ntp_servers { 
q(Australia (ntp.adelaide.edu.au)
Australia (ntp.saard.net)
Australia (time.esec.com.au)
Canada (ntp.cpsc.ucalgary.ca)
Canada (ntp1.cmc.ec.gc.ca)
Canada (ntp2.cmc.ec.gc.ca)
Canada (time.chu.nrc.ca)
Canada (time.nrc.ca)
Canada (timelord.uregina.ca)
Spain (slug.ctv.es)
France (ntp.univ-lyon1.fr)
Croatia (zg1.ntp.carnet.hr)
Croatia (zg2.ntp.carnet.hr)
Croatia (st.ntp.carnet.hr)
Croatia (ri.ntp.carnet.hr)
Croatia (os.ntp.carnet.hr)
Indonesia (ntp.incaf.net)
Italy (time.ien.it)
Korea, republic of (time.nuri.net)
Norway (fartein.ifi.uio.no)
Russia (ntp.landau.ac.ru)
Singapore (ntp.shim.org)
Slovenia (time.ijs.si)
United kingdom (ntp.cs.strath.ac.uk)
United kingdom (ntp2a.mcc.ac.uk)
United kingdom (ntp2b.mcc.ac.uk)
United kingdom (ntp2c.mcc.ac.uk)
United kingdom (ntp2d.mcc.ac.uk)
United states DE (louie.udel.edu)
United states IL (ntp-0.cso.uiuc.edu)
United states IL (ntp-1.cso.uiuc.edu)
United states IL (ntp-2.cso.uiuc.edu)
United states IN (gilbreth.ecn.purdue.edu)
United states IN (harbor.ecn.purdue.edu)
United states IN (molecule.ecn.purdue.edu)
);
}

1;
