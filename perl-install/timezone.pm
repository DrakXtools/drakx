package timezone;

use diagnostics;
use strict;



sub getTimeZones {
    my ($prefix) = @_;
    local *F;
    open F, "cd $prefix/usr/share/zoneinfo && find [A-Z]* -type f |";
    my @l = sort map { chop; $_ } <F>;
    close F or die "cannot list the available zoneinfos";
    @l;
}

my %l2t = (
'Danish (Denmark)' => 'Europe/Copenhagen',
'English (USA)' => 'America/New_York',
'English (UK)' => 'Europe/London',
'Estonian (Estonia)' => 'Europe/Tallinn',
'Finnish (Finland)' => 'Europe/Helsinki',
'French (France)' => 'Europe/Paris',
'French (Belgium)' => 'Europe/Brussels',
'French (Canada)' => 'Canada/Atlantic', # or Newfoundland ? or Eastern ?
'German (Germany)' => 'Europe/Berlin',
'Hungarian (Hungary)' => 'Europe/Budapest',
'Icelandic (Iceland)' => 'Atlantic/Reykjavik',
'Indonesian (Indonesia)' => 'Asia/Jakarta',
'Italian (Italy)' => 'Europe/Rome',
'Italian (San Marino)' => 'Europe/San_Marino',
'Italian (Vatican)' => 'Europe/Vatican',
'Italian (Switzerland)' => 'Europe/Zurich',
'Japanese' => 'Asia/Tokyo',
'Latvian (Latvia)' => 'Europe/Riga',
'Lithuanian (Lithuania)' => 'Europe/Vilnius',
'Norwegian (Bokmaal)' => 'Europe/Oslo',
'Norwegian (Nynorsk)' => 'Europe/Oslo',
'Polish (Poland)' => 'Europe/Warsaw',
'Portuguese (Brazil)' => 'Brazil/East', # most people live on the east coast
'Portuguese (Portugal)' => 'Europe/Lisbon',
'Romanian (Rumania)' => 'Europe/Bucharest',
'Russian (Russia)' => 'Europe/Moscow',
'Slovak (Slovakia)' => 'Europe/Bratislava',
'Spanish (Spain)' => 'Europe/Madrid',
'Swedish (Finland)' => 'Europe/Helsinki'
'Swedish (Sweden)' => 'Europe/Stockholm',
'Turkish (Turkey)' => 'Europe/Istanbul',
'Ukrainian (Ukraine)' => 'Europe/Kiev',
'Walon (Belgium)' => 'Europe/Brussels',
);
