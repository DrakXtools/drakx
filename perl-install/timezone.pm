package timezone; # $Id$

use diagnostics;
use strict;
use vars;

use common;
use log;


sub getTimeZones {
    my ($prefix) = @_;
    local *F;
    open F, "cd $prefix/usr/share/zoneinfo && find [A-Z]* -type f |";
    my @l = chomp_(<F>);
    close F or die "cannot list the available zoneinfos";
    sort @l;
}

sub read {
    my ($prefix) = @_;
    my $f = "$prefix/etc/sysconfig/clock";
    my %t = getVarsFromSh($f) or return;

    (timezone => $t{ZONE}, UTC => text2bool($t{UTC}));
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
	($server) = grep { $_ ne '127.127.1.0' } map { if_(/^\s*server\s+(\S*)/, $1) } cat_($f);
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

my %l2t = (
'Afrikaans (South Africa)' => 'Africa/Johannesburg',
'Arabic' => 'Africa/Cairo',
'Armenian (Armenia)' => 'Asia/Yerevan',
'Azeri (Azerbaijan)' => 'Asia/Baku',
'Belarussian (Belarus)' => 'Europe/Minsk',
'Bosnian (Bosnia)' => 'Europe/Sarajevo',
'Brezhoneg (Brittany)' => 'Europe/Paris',
'Bulgarian (Bulgaria)' => 'Europe/Sofia',
'Catalan' => 'Europe/Madrid',
'Chinese Traditional (Taiwan)' => 'Asia/Taipei',
'Chinese Simplified (China)' => 'Asia/Beijing',
'Croatian (Bosnia)' => 'Europe/Sarajevo',
'Croatian (Croatia)' => 'Europe/Zagreb',
'Cymraeg (Welsh)' => 'Europe/London',
'Czech' => 'Europe/Prague',
'Danish (Denmark)' => 'Europe/Copenhagen',
'Dutch (Netherlands)' => 'Europe/Amsterdam',
'English (United States)' => 'America/New_York',
'English (United Kingdom)' => 'Europe/London',
'Esperanto' => 'Europe/Warsaw',
'Estonian (Estonia)' => 'Europe/Tallinn',
'Euskara (Basque)' => 'Europe/Madrid',
'Finnish (Finland)' => 'Europe/Helsinki',
'French (France)' => 'Europe/Paris',
'French (Belgium)' => 'Europe/Brussels',
'French (Canada)' => 'Canada/Atlantic', # or Newfoundland ? or Eastern ?
'Gaeilge (Ireland)' => 'Europe/Dublin',
'Galego' => 'Europe/Madrid',
'Georgian (Georgia)' => 'Asia/Yerevan',
'German (Austria)' => 'Europe/Vienna',
'German (Germany)' => 'Europe/Berlin',
'Greek (Greece)' => 'Europe/Athens',
'Greenlandic' => 'Arctic/Longyearbyen',
'Hebrew (Israel)' => 'Asia/Tel_Aviv',
'Hungarian (Hungary)' => 'Europe/Budapest',
'Icelandic (Iceland)' => 'Atlantic/Reykjavik',
'Indonesian (Indonesia)' => 'Asia/Jakarta',
'Iranian (Iran)' => 'Asia/Tehran',
'Italian (Italy)' => 'Europe/Rome',
#-'Italian (San Marino)' => 'Europe/San_Marino',
#-'Italian (Vatican)' => 'Europe/Vatican',
#-'Italian (Switzerland)' => 'Europe/Zurich',
'Japanese (Japon)' => 'Asia/Tokyo',
'Korean (Korea)' => 'Asia/Seoul',
'Latvian (Latvia)' => 'Europe/Riga',
'Lithuanian (Lithuania)' => 'Europe/Vilnius',
'Macedonian (Macedonia)' => 'Europe/Skopje',
'Maori (New Zealand)' => 'Australia/Sydney',
'Norwegian (Bokmaal)' => 'Europe/Oslo',
'Norwegian (Nynorsk)' => 'Europe/Oslo',
'Polish (Poland)' => 'Europe/Warsaw',
'Portuguese (Brazil)' => 'Brazil/East', # most people live on the east coast
'Portuguese (Portugal)' => 'Europe/Lisbon',
'Romanian (Rumania)' => 'Europe/Bucharest',
'Russian (Russia)' => 'Europe/Moscow',
'Serbian (Serbia)' => 'Europe/Belgrade',
'Slovak (Slovakia)' => 'Europe/Bratislava',
'Slovenian (Slovenia)' => 'Europe/Ljubljana',
'Spanish (Argentina)' => 'America/Buenos_Aires',
'Spanish (Mexico)' => 'America/Mexico_City',
'Spanish (Spain)' => 'Europe/Madrid',
'Swedish (Sweden)' => 'Europe/Stockholm',
'Tajik (Tajikistan)' => 'Asia/Dushanbe',
'Tamil (Sri Lanka)' => 'Asia/Colombo',
'Tatar' => 'Europe/Minsk',
'Thai (Thailand)' => 'Asia/Bangkok',
'Turkish (Turkey)' => 'Europe/Istanbul',
'Ukrainian (Ukraine)' => 'Europe/Kiev',
'Uzbek (Uzbekistan)' => 'Asia/Tashkent',
'Vietnamese (Vietnam)' => 'Asia/Saigon',
'Walon (Belgium)' => 'Europe/Brussels',
);

sub fuzzyChoice { 
    my ($b, $count) = common::bestMatchSentence($_[0], keys %l2t);
    $count ? $b : '';
}
sub bestTimezone { $l2t{fuzzyChoice($_[0])} || 'GMT' }

my %sex = (
fr_FR => { '[iln]a$' => 1, '[cdilnst]e$' => 1, 'e$' => .8, 'n$' => .1, 'd$' => .05, 't$' => 0 },
en => { 'a$' => 1, 'o$' => 0, '[ln]$' => .3, '[rs]$' => .2 },
);


sub sexProb($) {
    local ($_) = @_;
    my $l = $sex{$ENV{LC_ALL}} or return 0.5;

    my ($prob, $nb) = (0, 0);
    foreach my $k (keys %$l) {
	/$k/ and $prob += $l->{$k}, $nb++;
    }
    $nb ? $prob / $nb : 0.5;
}

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
