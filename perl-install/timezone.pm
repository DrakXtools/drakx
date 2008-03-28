package timezone; # $Id$

use diagnostics;
use strict;

use common;
use log;

sub get_timezone_prefix() {
    my $prefix = $::testing ? '' : $::prefix;
    $prefix . "/usr/share/zoneinfo";
}

sub getTimeZones() {
    my $tz_prefix = get_timezone_prefix();
    open(my $F, "cd $tz_prefix && find [A-Z]* -noleaf -type f |");
    my @l = difference2([ chomp_(<$F>) ], [ 'ROC', 'PRC' ]);
    close $F or die "cannot list the available zoneinfos";
    sort @l;
}

sub read() {
    my %t = getVarsFromSh("$::prefix/etc/sysconfig/clock") or return {};
    { timezone => $t{ZONE}, UTC => text2bool($t{UTC}) };
}

my $ntp_conf_file = "/etc/ntp.conf";

sub ntp_server() {
    find { $_ ne '127.127.1.0' } map { if_(/^\s*server\s+(\S*)/, $1) } cat_($::prefix . $ntp_conf_file);
}

sub set_ntp_server {
    my ($server) = @_;
    my $f = $::prefix . $ntp_conf_file;
    -f $f or return;

    my $pool_match = qr/\.pool\.ntp\.org$/;
    my @servers = $server =~ $pool_match  ? (map { "$_.$server" } 0 .. 2) : $server;

    my $added = 0;
    substInFile {
        if (/^#?\s*server\s+(\S*)/ && $1 ne '127.127.1.0') {
            $_ = $added ? $_ =~ $pool_match ? undef : "#server $1\n" : join('', map { "server $_\n" } @servers);
            $added = 1;
        }
    } $f;
    output_p("$::prefix/etc/ntp/step-tickers", join('', map { "$_\n" } @servers));

    require services;
    services::set_status('ntpd', to_bool($server), $::isInstall);
}

sub write {
    my ($t) = @_;

    set_ntp_server($t->{ntp});

    my $tz_prefix = get_timezone_prefix();
    eval { cp_af($tz_prefix . '/' . $t->{timezone}, "$::prefix/etc/localtime") };
    $@ and log::l("installing /etc/localtime failed");
    setVarsInSh("$::prefix/etc/sysconfig/clock", {
	ZONE => $t->{timezone},
	UTC  => bool2text($t->{UTC}),
	ARC  => "false",
    });
}

sub reload_sys_clock {
    my ($t) = @_;
    require run_program;
    any::disable_x_screensaver();
    run_program::run('hwclock', '--hctosys', ($t->{UTC} ? '--utc' : '--localtime'));
    any::enable_x_screensaver();
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

our %ntp_servers;

sub get_ntp_server_tree {
    my ($zone) = @_;
    map {
        $ntp_servers{$zone}{$_} => (
            exists $ntp_servers{$_} ?
              $zone ?
                translate($_) . "|" . N("All servers") :
                N("All servers") :
              translate($zone) . "|" . translate($_)
        ),
        get_ntp_server_tree($_);
    } keys %{$ntp_servers{$zone}};
}

sub ntp_servers() {
    +{ get_ntp_server_tree() };
}

sub dump_ntp_zone {
    my ($zone) = @_;
    map { if_(/\[\d+\](.+) -- (.+\.ntp\.org)/, $1 => $2) } `lynx -dump http://www.pool.ntp.org/zone/$zone`;
}
sub print_ntp_zone {
    my ($zone, $name) = @_;
    my %servers = dump_ntp_zone($zone);
    print qq(\$ntp_servers{"$name"} = {\n);
    print join('', map { qq(    N_("$_") => "$servers{$_}",\n) } sort(keys %servers));
    print "};\n";
    \%servers;
}
sub print_ntp_servers() {
    print_ntp_zone();
    my $servers = print_ntp_zone('@', "Global");
    foreach my $name (sort(keys %$servers)) {
        my ($zone) = $servers->{$name} =~ /^(.*?)\./;
        print_ntp_zone($zone, $name);
    }
}

# perl -Mtimezone -e 'timezone::print_ntp_servers()'
$ntp_servers{""} = {
    N_("Global") => "pool.ntp.org",
};
$ntp_servers{"Global"} = {
    N_("Africa") => "africa.pool.ntp.org",
    N_("Asia") => "asia.pool.ntp.org",
    N_("Europe") => "europe.pool.ntp.org",
    N_("North America") => "north-america.pool.ntp.org",
    N_("Oceania") => "oceania.pool.ntp.org",
    N_("South America") => "south-america.pool.ntp.org",
};
$ntp_servers{"Africa"} = {
    N_("South Africa") => "za.pool.ntp.org",
    N_("Tanzania") => "tz.pool.ntp.org",
};
$ntp_servers{"Asia"} = {
    N_("Bangladesh") => "bd.pool.ntp.org",
    N_("China") => "cn.pool.ntp.org",
    N_("Hong Kong") => "hk.pool.ntp.org",
    N_("India") => "in.pool.ntp.org",
    N_("Indonesia") => "id.pool.ntp.org",
    N_("Iran") => "ir.pool.ntp.org",
    N_("Israel") => "il.pool.ntp.org",
    N_("Japan") => "jp.pool.ntp.org",
    N_("Korea") => "kr.pool.ntp.org",
    N_("Malaysia") => "my.pool.ntp.org",
    N_("Philippines") => "ph.pool.ntp.org",
    N_("Singapore") => "sg.pool.ntp.org",
    N_("Taiwan") => "tw.pool.ntp.org",
    N_("Thailand") => "th.pool.ntp.org",
    N_("Turkey") => "tr.pool.ntp.org",
    N_("United Arab Emirates") => "ae.pool.ntp.org",
};
$ntp_servers{"Europe"} = {
    N_("Austria") => "at.pool.ntp.org",
    N_("Belarus") => "by.pool.ntp.org",
    N_("Belgium") => "be.pool.ntp.org",
    N_("Bulgaria") => "bg.pool.ntp.org",
    N_("Czech Republic") => "cz.pool.ntp.org",
    N_("Denmark") => "dk.pool.ntp.org",
    N_("Estonia") => "ee.pool.ntp.org",
    N_("Finland") => "fi.pool.ntp.org",
    N_("France") => "fr.pool.ntp.org",
    N_("Germany") => "de.pool.ntp.org",
    N_("Greece") => "gr.pool.ntp.org",
    N_("Hungary") => "hu.pool.ntp.org",
    N_("Ireland") => "ie.pool.ntp.org",
    N_("Italy") => "it.pool.ntp.org",
    N_("Lithuania") => "lt.pool.ntp.org",
    N_("Luxembourg") => "lu.pool.ntp.org",
    N_("Netherlands") => "nl.pool.ntp.org",
    N_("Norway") => "no.pool.ntp.org",
    N_("Poland") => "pl.pool.ntp.org",
    N_("Portugal") => "pt.pool.ntp.org",
    N_("Romania") => "ro.pool.ntp.org",
    N_("Russian Federation") => "ru.pool.ntp.org",
    N_("Slovakia") => "sk.pool.ntp.org",
    N_("Slovenia") => "si.pool.ntp.org",
    N_("Spain") => "es.pool.ntp.org",
    N_("Sweden") => "se.pool.ntp.org",
    N_("Switzerland") => "ch.pool.ntp.org",
    N_("Ukraine") => "ua.pool.ntp.org",
    N_("United Kingdom") => "uk.pool.ntp.org",
    N_("Yugoslavia") => "yu.pool.ntp.org",
};
$ntp_servers{"North America"} = {
    N_("Canada") => "ca.pool.ntp.org",
    N_("Guatemala") => "gt.pool.ntp.org",
    N_("Mexico") => "mx.pool.ntp.org",
    N_("United States") => "us.pool.ntp.org",
};
$ntp_servers{"Oceania"} = {
    N_("Australia") => "au.pool.ntp.org",
    N_("New Zealand") => "nz.pool.ntp.org",
};
$ntp_servers{"South America"} = {
    N_("Argentina") => "ar.pool.ntp.org",
    N_("Brazil") => "br.pool.ntp.org",
    N_("Chile") => "cl.pool.ntp.org",
};

1;
