package timezone; # $Id$

use diagnostics;
use strict;

use common qw(:common :system);
use commands;
use log;


sub getTimeZones {
    my ($prefix) = @_;
    local *F;
    open F, "cd $prefix/usr/share/zoneinfo && find [A-Z]* -type f |";
    my @l = sort map { chop; $_ } <F>;
    close F or die "cannot list the available zoneinfos";
    @l;
}

sub read {
    my ($prefix) = @_;
    my $f = "$prefix/etc/sysconfig/clock";
    my %t = getVarsFromSh($f) or return;

    (timezone => $t{ZONE}, UTC => text2bool($t{UTC}));
}

sub write {
    my ($prefix, $t) = @_;

    eval { commands::cp("-f", "$prefix/usr/share/zoneinfo/$t->{timezone}", "$prefix/etc/localtime") };
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
'Chinese (China)' => 'Asia/Shanghai',
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

1;
