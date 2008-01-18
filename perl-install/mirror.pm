package mirror; # $Id$

use diagnostics;
use strict;
use feature 'state';

use common;
use log;

my %land2tzs = (
	     N_("Australia") => [ 'Australia/Sydney' ],
	     N_("Austria") => [ 'Europe/Vienna', 'Europe/Brussels', 'Europe/Berlin' ],
	     N_("Belgium") => [ 'Europe/Brussels', 'Europe/Paris', 'Europe/Berlin' ],
	     N_("Brazil") => [ 'Brazil/East' ],
	     N_("Canada") => [ 'Canada/Atlantic', 'Canada/Eastern' ],
	     N_("Costa Rica") => [ 'America/Costa_Rica' ],
	     N_("Czech Republic") => [ 'Europe/Prague', 'Europe/Berlin' ],
	     N_("Denmark") => [ 'Europe/Copenhagen', 'Europe/Berlin' ],
	     N_("Estonia") => [ 'Europe/Tallinn', 'Europe/Helsinki' ],
	     N_("Finland") => [ 'Europe/Helsinki', 'Europe/Tallinn' ],
	     N_("France") => [ 'Europe/Paris', 'Europe/Brussels', 'Europe/Berlin' ],
	     N_("Germany") => [ 'Europe/Berlin', 'Europe/Prague' ],
	     N_("Greece") => [ 'Europe/Athens', 'Europe/Prague' ],
	     N_("Hungary") => [ 'Europe/Budapest' ],
	     N_("Ireland") => [ 'Europe/Dublin', 'Europe/London' ],
	     N_("Israel") => [ 'Asia/Tel_Aviv' ],
	     N_("Italy") => [ 'Europe/Rome', 'Europe/Brussels', 'Europe/Paris' ],
	     N_("Japan") => [ 'Asia/Tokyo', 'Asia/Seoul' ],
	     N_("Netherlands") => [ 'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Berlin' ],
	     N_("New Zealand") => [ 'Pacific/Auckland' ],
	     N_("Norway") => [ 'Europe/Oslo', 'Europe/Stockholm' ],
	     N_("Poland") => [ 'Europe/Warsaw' ],
	     N_("Portugal") => [ 'Europe/Lisbon', 'Europe/Madrid' ],
	     N_("Russia") => [ 'Europe/Moscow', ],
	     N_("Slovakia") => [ 'Europe/Bratislava' ],
	     N_("South Africa") => [ 'Africa/Johannesburg' ],
	     N_("Spain") => [ 'Europe/Madrid', 'Europe/Lisbon' ],
	     N_("Sweden") => [ 'Europe/Stockholm', 'Europe/Oslo' ],
	     N_("Switzerland") => [ 'Europe/Zurich', 'Europe/Berlin', 'Europe/Brussels' ],
	     N_("Taiwan") => [ 'Asia/Taipei', 'Asia/Seoul' ],
	     N_("Thailand") => [ 'Asia/Bangkok', 'Asia/Seoul' ],
	     N_("United States") => [ 'America/New_York', 'Canada/Atlantic', 'Asia/Tokyo', 'Australia/Sydney', 'Europe/Paris' ],
	    );

sub mirror2text {
    my ($mirror) = @_;
    translate($mirror->{country})  . '|' . $mirror->{host} . ($mirror->{method} ? " ($mirror->{method})" : '');
}

my $downloader;
sub register_downloader {
    my ($func) = @_;
    $downloader = $func;
}

sub mirrors_raw {
    my ($product_id, $o_arch) = @_;

    #- contact the following URL to retrieve the list of mirrors.
    #- http://wiki.mandriva.com/en/Product_id
    my $type = lc($product_id->{type}); $type =~ s/\s//g;
    local $product_id->{arch} = $o_arch if $o_arch;
    my $list = "http://api.mandriva.com/mirrors/$type.$product_id->{version}.$product_id->{arch}.list";
    log::explanations("trying mirror list from $list");
    my @lines;
    if ($::isInstall) {
        require install::http;
        my $f = install::http::getFile($list) or die "mirror list not found";
        local $SIG{ALRM} = sub { die "timeout" };
        alarm 60;
        log::l("using mirror list $list");
        push @lines, $_ while <$f>;
        install::http::close();
        alarm 0; 
    } else {
        if (ref($downloader)) {
            @lines = $downloader->($list);
            @lines or die "mirror list not found";
        } else {
            die "Missing download callback";
        }
    }
    map { common::parse_LDAP_namespace_structure(chomp_($_)) } @lines;
}

sub list {
    my ($product_id, $type, $o_arch) = @_;

    our @mirrors_raw;
    state $prev_arch;
    undef @mirrors_raw if $prev_arch ne $o_arch;
    $prev_arch = $o_arch || arch();
    if (!@mirrors_raw) {
        @mirrors_raw = eval { mirrors_raw($product_id, $o_arch) };
        if (my $err = $@) {
            log::explanations("failed to download mirror list");
            die $err;
        }
        @mirrors_raw or log::explanations("empty mirror list"), return;
    }

	my @mirrors = grep {
	    ($_->{method}, $_->{host}, $_->{dir}) = $_->{url} =~ m!^(ftp|http)://(.*?)(/.*)!;
	    $_->{method} && ($type eq 'all' || $_->{type} eq $type);
	} @mirrors_raw or log::explanations("no mirrors of type $type"), return;

    @mirrors && \@mirrors;
}

sub nearest {
    my ($timezone, $mirrors) = @_;

    my (@country, @zone);
    foreach my $mirror (@$mirrors) {
	my @tzs = @{$land2tzs{$mirror->{country}} || []};
	eval { push @{$country[find_index { $_ eq $timezone } @tzs]}, $mirror };
	eval { push @{$zone[find_index { ((split '/')[0] eq (split '/', $timezone)[0]) } @tzs]}, $mirror };
    }
    my @l = @country ? @country : @zone;
    shift @l while !$l[0] && @l;
    
    my @possible = @l ? ((@{$l[0]}) x 2, @{$l[1] || []}) : @$mirrors;
    $possible[rand @possible];
}

1;
