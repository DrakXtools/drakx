package timezone;

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

sub read ($) {
    my ($f) = @_;
    my %t = getVarsFromSh($f) or die "cannot open file $f: $!";

    ("timezone", $t{ZONE}, "UTC", text2bool($t{UTC}));
}

sub write($$$) {
    my ($prefix, $t, $f) = @_;

    eval { commands::cp("-f", "$prefix/usr/share/zoneinfo/$t->{timezone}", "$prefix/etc/localtime") };
    $@ and log::l("installing /etc/localtime failed");
    setVarsInSh($f, {
	ZONE => $t->{timezone},
	UTC  => bool2text($t->{UTC}),
	ARC  => "false",
    });
}

my %l2t = (
'Brezhoneg (Brittany)' => 'Europe/Paris',
'Chinese (China)' => 'Asia/Shanghai',
'Danish (Denmark)' => 'Europe/Copenhagen',
'Dutch (Netherlands)' => 'Europe/Amsterdam',
'English (USA)' => 'America/New_York',
'English (UK)' => 'Europe/London',
'Esperanto' => 'Europe/Warsaw',
'Estonian (Estonia)' => 'Europe/Tallinn',
'Finnish (Finland)' => 'Europe/Helsinki',
'French (France)' => 'Europe/Paris',
'French (Belgium)' => 'Europe/Brussels',
'French (Canada)' => 'Canada/Atlantic', # or Newfoundland ? or Eastern ?
'Gaeilge (Ireland)' => 'Europe/Dublin',
'German (Austria)' => 'Europe/Vienna',
'German (Germany)' => 'Europe/Berlin',
'Greek (Greece)' => 'Europe/Athens',
'Hungarian (Hungary)' => 'Europe/Budapest',
'Icelandic (Iceland)' => 'Atlantic/Reykjavik',
'Indonesian (Indonesia)' => 'Asia/Jakarta',
'Italian (Italy)' => 'Europe/Rome',
#-'Italian (San Marino)' => 'Europe/San_Marino',
#-'Italian (Vatican)' => 'Europe/Vatican',
#-'Italian (Switzerland)' => 'Europe/Zurich',
'Japanese (Japon)' => 'Asia/Tokyo',
'Korean (Korea)' => 'Asia/Seoul',
'Latvian (Latvia)' => 'Europe/Riga',
'Lithuanian (Lithuania)' => 'Europe/Vilnius',
'Norwegian (Bokmaal)' => 'Europe/Oslo',
'Norwegian (Nynorsk)' => 'Europe/Oslo',
'Polish (Poland)' => 'Europe/Warsaw',
'Portuguese (Brazil)' => 'Brazil/East', # most people live on the east coast
'Portuguese (Portugal)' => 'Europe/Lisbon',
'Romanian (Rumania)' => 'Europe/Bucharest',
'Russian (Russia)' => 'Europe/Moscow',
'Serbian (Serbia)' => 'Europe/Belgrade',
'Slovak (Slovakia)' => 'Europe/Bratislava',
'Spanish (Argentina)' => 'America/Buenos_Aires',
'Spanish (Mexico)' => 'America/Mexico_City',
'Spanish (Spain)' => 'Europe/Madrid',
'Swedish (Sweden)' => 'Europe/Stockholm',
'Thai (Thailand)' => 'Asia/Bangkok',
'Turkish (Turkey)' => 'Europe/Istanbul',
'Ukrainian (Ukraine)' => 'Europe/Kiev',
'Walon (Belgium)' => 'Europe/Brussels',
);

sub bestTimezone {
    my ($langtext) = @_;
    $l2t{common::bestMatchSentence($langtext, keys %l2t)};
}

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
