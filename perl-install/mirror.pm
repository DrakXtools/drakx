package mirror;

use diagnostics;
use strict;
use feature 'state';

use common;
use log;

=head1 SYNOPSYS

B<mirror> enables to manage cooker distribution mirrors

=head1 Functions

=over

=cut

my %land2tzs = (
	     N_("Australia") => [ 'Australia/Sydney' ],
	     N_("Austria") => [ 'Europe/Vienna', 'Europe/Brussels', 'Europe/Berlin' ],
	     N_("Belgium") => [ 'Europe/Brussels', 'Europe/Paris', 'Europe/Berlin' ],
	     N_("Brazil") => [ 'America/Sao_Paulo' ],
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

=item mirror2text($mirror)

Returns a displayable string from a mirror struct

=cut

sub mirror2text {
    my ($mirror) = @_;
    translate($mirror->{country})  . '|' . $mirror->{host} . ($mirror->{method} ? " ($mirror->{method})" : '');
}

=item register_downloader($func)

Sets a downloader program

=cut

my $downloader;
sub register_downloader {
    my ($func) = @_;
    $downloader = $func;
}

sub _mirrors_raw_install {
    my ($list) = @_;
    require install::http;
    my $f = install::http::getFile($list, "strict-certificate-check" => 1) or die "mirror list not found";
    local $SIG{ALRM} = sub { die "timeout" };
    alarm 60;
    log::l("using mirror list $list");
    my @lines;
    push @lines, $_ while <$f>;
    alarm 0;
    @lines;
}

sub _mirrors_raw_standalone {
    my ($list) = @_;
    my @lines;
    if (ref($downloader)) {
        @lines = $downloader->($list);
        @lines or die "mirror list not found";
    } else {
        die "Missing download callback";
    }
    @lines;
}

=item mirrors_raw($product_id)

Returns a list of mirrors hash refs from http://mirrors.mageia.org

Note that in standalone mode, one has to actually use register_downloader()
first in order to provide a downloader callback.

=cut

sub mirrors_raw {
    my ($product_id) = @_;

    #- contact the following URL to retrieve the list of mirrors.
    #- http://wiki.mandriva.com/en/Product_id
    my $type = lc($product_id->{type}); $type =~ s/\s//g;
    my $list;
    if ($product_id->{branch} eq "Devel") {
        $list = "http://downloads.openmandriva.org/mirrors/cooker.$product_id->{arch}.list?product=$product_id->{product}";
    } else {
        $list = "http://downloads.openmandriva.org/mirrors/openmandriva.$product_id->{version}.$product_id->{arch}.list?product=$product_id->{product}";
    } 
    log::explanations("trying mirror list from $list");
    my @lines = $::isInstall ? _mirrors_raw_install($list) : _mirrors_raw_standalone($list);
    map { common::parse_LDAP_namespace_structure(chomp_($_)) } @lines;
}

=item list($product_id, $type)


Returns a list of mirrors hash refs as returned by mirrors_raw() but filters it.

One can select the type of mirrors ('distrib', 'updates', ...) or 'all'

=cut

sub list {
    my ($product_id, $type) = @_;

    our @mirrors_raw;
    if (!@mirrors_raw) {
        @mirrors_raw = eval { mirrors_raw($product_id) };
        if (my $err = $@) {
            log::explanations("failed to download mirror list");
            die $err;
        }
        @mirrors_raw or log::explanations("empty mirror list"), return;
    }

	my @mirrors = grep {
	    ($_->{method}, $_->{host}, $_->{dir}) = $_->{url} =~ m!^(ftp|http)://(.*?)(/.*)!;
	    $_->{method} && (member($type, 'all', $_->{type}));
	} @mirrors_raw or log::explanations("no mirrors of type $type"), return;

    @mirrors && \@mirrors;
}

=item nearest($timezone, $mirrors)

Randomly returns one of the nearest mirror

=cut

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

=back

=cut

1;
