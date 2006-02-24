package timezone; # $Id$

use diagnostics;
use strict;

use common;
use log;


sub getTimeZones() {
    my $prefix = $::testing ? '' : $::prefix;
    open(my $F, "find $prefix/usr/share/zoneinfo/[A-Z]* -noleaf -type f |");
    my @l = difference2([ chomp_(<$F>) ], [ 'ROC', 'PRC' ]);
    close $F or die "cannot list the available zoneinfos";
    sort @l;
}

sub read() {
    my %t = getVarsFromSh("$::prefix/etc/sysconfig/clock") or return {};
    { timezone => $t{ZONE}, UTC => text2bool($t{UTC}) };
}

sub ntp_server {
    my $setting = @_ >= 1;
    my ($server) = @_;

    my $f = "$::prefix/etc/ntp.conf";
    -e $f or return;

    if ($setting) {
	my $added = 0;
	substInFile {
	    if (/^#?\s*server\s+(\S*)/ && $1 ne '127.127.1.0') {
		$_ = $added ? "#server $1\n" : "server $server\n";
		$added = 1;
	    }
	} $f;
	output_p("$::prefix/etc/ntp/step-tickers", "$server\n");
    } else {
	$server = find { $_ ne '127.127.1.0' } map { if_(/^\s*server\s+(\S*)/, $1) } cat_($f);
    }
    $server;
}

sub write {
    my ($t) = @_;

    ntp_server($t->{ntp});

    eval { cp_af("$::prefix/usr/share/zoneinfo/$t->{timezone}", "$::prefix/etc/localtime") };
    $@ and log::l("installing /etc/localtime failed");
    setVarsInSh("$::prefix/etc/sysconfig/clock", {
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

sub ntp_servers() { 
    +{
	'time.sinectis.com.ar' => 'Argentina',
	'tick.nap.com.ar' => 'Argentina',
	'tock.nap.com.ar' => 'Argentina',
	'ntp.adelaide.edu.au' => 'Australia',
	'ntp.saard.net' => 'Australia',
	'ntp.pop-df.rnp.br' => 'Brazil',
	'ntp.pop-pr.rnp.br' => 'Brazil',
	'ntp.on.br' => 'Brazil',
	'ntp1.belbone.be' => 'Belgium',
	'ntp2.belbone.be' => 'Belgium',
	'ntp.cpsc.ucalgary.ca' => 'Canada',
	'ntp1.cmc.ec.gc.ca' => 'Canada',
	'ntp2.cmc.ec.gc.ca' => 'Canada',
	'time.chu.nrc.ca' => 'Canada',
	'time.nrc.ca' => 'Canada',
	'timelord.uregina.ca' => 'Canada',
	'ntp.globe.cz' => 'Czech republic',
	'ntp.karpo.cz' => 'Czech republic',
	'ntp1.contactel.cz' => 'Czech republic',
	'ntp2.contactel.cz' => 'Czech republic',
	'clock.netcetera.dk' => 'Denmark',
	'clock2.netcetera.dk' => 'Denmark',
	'slug.ctv.es' => 'Spain',
	'tick.keso.fi' => 'Finland',
	'tock.keso.fi' => 'Finland',
	'ntp.ndsoftwarenet.com' => 'France',
	'ntp.obspm.fr' => 'France',
	'ntp.tuxfamily.net' => 'France',
	'ntp1.tuxfamily.net' => 'France',
	'ntp2.tuxfamily.net' => 'France',
	'ntp.univ-lyon1.fr' => 'France',
	'zg1.ntp.carnet.hr' => 'Croatia',
	'zg2.ntp.carnet.hr' => 'Croatia',
	'st.ntp.carnet.hr' => 'Croatia',
	'ri.ntp.carnet.hr' => 'Croatia',
	'os.ntp.carnet.hr' => 'Croatia',
	'ntp.incaf.net' => 'Indonesia',
	'ntp.maths.tcd.ie' => 'Ireland',
	'time.ien.it' => 'Italy',
	'ntps.net4u.it' => 'Italy',
	'ntp.cyber-fleet.net' => 'Japan',
	'time.nuri.net' => 'Korea, republic of',
	'ntp2a.audiotel.com.mx' => 'Mexico',
	'ntp2b.audiotel.com.mx' => 'Mexico',
	'ntp2c.audiotel.com.mx' => 'Mexico',
	'ntp.doubleukay.com' => 'Malaysia',
	'ntp1.theinternetone.net' => 'Netherlands',
	'ntp2.theinternetone.net' => 'Netherlands',
	'ntp3.theinternetone.net' => 'Netherlands',
	'fartein.ifi.uio.no' => 'Norway',
	'info.cyf-kr.edu.pl' => 'Poland',
	'ntp.ip.ro' => 'Romania',
	'ntp.psn.ru' => 'Russia',
	'time.flygplats.net' => 'Sweden',
	'ntp.shim.org' => 'Singapore',
	'biofiz.mf.uni-lj.si' => 'Slovenia',
	'time.ijs.si' => 'Slovenia',
	'time.ijs.si' => 'Slovenia',
	'clock.cimat.ues.edu.sv' => 'El salvador',
	'a.ntp.alphazed.net' => 'United kingdom',
	'bear.zoo.bt.co.uk' => 'United kingdom',
	'ntp.cis.strath.ac.uk' => 'United kingdom',
	'ntp2a.mcc.ac.uk' => 'United kingdom',
	'ntp2b.mcc.ac.uk' => 'United kingdom',
	'ntp2c.mcc.ac.uk' => 'United kingdom',
	'ntp2d.mcc.ac.uk' => 'United kingdom',
	'tick.tanac.net' => 'United kingdom',
	'time-server.ndo.com' => 'United kingdom',
	'sushi.compsci.lyon.edu' => 'United states AR',
	'ntp.drydog.com' => 'United states AZ',
	'clock.fmt.he.net' => 'United states CA',
	'clock.sjc.he.net' => 'United states CA',
	'ntp.ucsd.edu' => 'United states CA',
	'ntp1.sf-bay.org' => 'United states CA',
	'ntp2.sf-bay.org' => 'United states CA',
	'time.berkeley.netdot.net' => 'United states CA',
	'ntp1.linuxmedialabs.com' => 'United states CO',
	'ntp1.tummy.com' => 'United states CO',
	'louie.udel.edu' => 'United states DE',
	'rolex.usg.edu' => 'United states GA',
	'timex.usg.edu' => 'United states GA',
	'ntp-0.cso.uiuc.edu' => 'United states IL',
	'ntp-1.cso.uiuc.edu' => 'United states IL',
	'ntp-1.mcs.anl.gov' => 'United states IL',
	'ntp-2.cso.uiuc.edu' => 'United states IL',
	'ntp-2.mcs.anl.gov' => 'United states IL',
	'gilbreth.ecn.purdue.edu' => 'United states IN',
	'harbor.ecn.purdue.edu' => 'United states IN',
	'molecule.ecn.purdue.edu' => 'United states IN',
	'ntp.ourconcord.net' => 'United states MA',
	'ns.nts.umn.edu' => 'United states MN',
	'nss.nts.umn.edu' => 'United states MN',
	'time-ext.missouri.edu' => 'United states MO',
	'chronos1.umt.edu' => 'United states MT',
	'chronos2.umt.edu' => 'United states MT',
	'chronos3.umt.edu' => 'United states MT',
	'tick.jrc.us' => 'United states NJ',
	'tock.jrc.us' => 'United states NJ',
	'cuckoo.nevada.edu' => 'United states NV',
	'tick.cs.unlv.edu' => 'United states NV',
	'tock.cs.unlv.edu' => 'United states NV',
	'clock.linuxshell.net' => 'United states NY',
	'clock.nyc.he.net' => 'United states NY',
	'ntp0.cornell.edu' => 'United states NY',
	'reva.sixgirls.org' => 'United states NY',
	'clock.psu.edu' => 'United states PA',
	'fuzz.psc.edu' => 'United states PA',
	'ntp-1.cede.psu.edu' => 'United states PA',
	'ntp-2.cede.psu.edu' => 'United states PA',
	'ntp-1.ece.cmu.edu' => 'United states PA',
	'ntp-2.ece.cmu.edu' => 'United states PA',
	'ntp.cox.smu.edu' => 'United states TX',
	'ntp.fnbhs.com' => 'United states TX',
	'ntppub.tamu.edu' => 'United states TX',
	'ntp-1.vt.edu' => 'United states VA',
	'ntp-2.vt.edu' => 'United states VA',
	'ntp.cmr.gov' => 'United states VA',
	'ntp1.cs.wisc.edu' => 'United states WI',
	'ntp3.cs.wisc.edu' => 'United states WI',
	'ntp3.sf-bay.org' => 'United states WI',
	'ntp.cs.unp.ac.za' => 'South africa',
	'tock.nml.csir.co.za' => 'South africa',
        'pool.ntp.org' => 'World Wide',
    };
}

1;
