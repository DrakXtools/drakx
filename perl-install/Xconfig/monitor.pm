package Xconfig::monitor; #- $Id$

use diagnostics;
use strict;

use detect_devices;
use common;
use any;
use log;


sub good_default_monitor {
    arch() =~ /ppc/ ? 
      (detect_devices::get_mac_model() =~ /^iBook/ ? 'Apple|iBook 800x600' : 'Apple|iMac/PowerBook 1024x768') :
      (detect_devices::isLaptop() ? 'Generic|Flat Panel 1024x768' : 'Generic|1024x768 @ 70 Hz');
}

my @VertRefresh_ranges = ("50-70", "50-90", "50-100", "40-150");

my @HorizSync_ranges = (
	"31.5",
	"31.5-35.1",
	"31.5-37.9",
	"31.5-48.5",
	"31.5-57.0",
	"31.5-64.3",
	"31.5-79.0",
	"31.5-82.0",
	"31.5-88.0",
	"31.5-94.0",
);


sub from_raw_X {
    my ($raw_X) = @_;

    my $monitor = $raw_X->get_monitor;
    if (!$monitor->{HorizSync}) {
	put_in_hash($monitor, getinfoFromDDC());
    }
    $monitor;
}

sub configure {
    my ($in, $raw_X, $auto) = @_;

    my $monitor = from_raw_X($raw_X);
    choose($in, $monitor, $auto) or return;
    $raw_X->set_monitors($monitor);
    $monitor;
}

sub configure_auto_install {
    my ($raw_X, $old_X) = @_;

    my $old_monitor = $old_X->{monitor} || {};
    $old_monitor->{VertRefresh} ||= $old_monitor->{vsyncrange};
    $old_monitor->{HorizSync} ||= $old_monitor->{hsyncrange};

    my $monitor = from_raw_X($raw_X);
    put_in_hash($monitor, $old_monitor);

    my $monitors = monitors();
    configure_automatic($monitor, $monitors) or put_in_hash($monitor, { HorizSync => '31.5-35.1', VertRefresh => '50-61' });
    $raw_X->set_monitors($monitor);
    $monitor;
}

sub choose {
    my ($in, $monitor, $auto) = @_;

    my $monitors = monitors();

    configure_automatic($monitor, $monitors) and $auto and return 1;

    my %h_monitors = map { ; "$_->{VendorName}|$_->{ModelName}" => $_ } @$monitors;

  ask_monitor:
    my $merged_name = do {
	if ($monitor->{VendorName} eq "Plug'n Play") {
	    $monitor->{VendorName};
	} else {
	    my $merged_name = $monitor->{VendorName} . '|' . $monitor->{ModelName};

	    if (!exists $h_monitors{$merged_name}) {
		$merged_name = $monitor->{HorizSync} ? 'Custom' : good_default_monitor();
	    } else {
		$merged_name;
	    }
	}
    };

    $in->ask_from(_("Monitor"), _("Choose a monitor"), 
		  [ { val => \$merged_name, separator => '|', 
		      list => ['Custom', "Plug'n Play", sort keys %h_monitors],
		      format => sub { $_[0] eq 'Custom' ? _("Custom") : 
				      $_[0] eq "Plug'n Play" ? _("Plug'n Play") . " ($monitor->{ModelName})" :
				      $_[0] =~ /^Generic\|(.*)/ ? _("Generic") . "|$1" :  
				      _("Vendor") . "|$_[0]" },
		      sort => 0 } ]) or return;

    if ($merged_name eq "Plug'n Play") {
	local $::noauto = 0; #- hey, you asked for plug'n play, so i do probe!
	put_in_hash($monitor, getinfoFromDDC());
	if (configure_automatic($monitor, $monitors)) {
	    $monitor->{VendorName} = "Plug'n Play";
	} else {
	    delete $monitor->{VendorName};
	    $in->ask_warn('', _("Plug'n Play probing failed. Please choose a precise monitor"));
	    goto ask_monitor;
	}
    } elsif ($merged_name eq 'Custom') {
	$in->ask_from('',
_("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
		      [ { val => \$monitor->{HorizSync}, list => \@HorizSync_ranges, label => _("Horizontal refresh rate"), not_edit => 0 },
			{ val => \$monitor->{VertRefresh}, list => \@VertRefresh_ranges, label => _("Vertical refresh rate"), not_edit => 0 } ]) or goto &choose;
	delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};
    } else {
	put_in_hash($monitor, $h_monitors{$merged_name});
    }
    $monitor->{manually_chosen} = 1;
    1;
}

sub configure_automatic {
    my ($monitor, $monitors) = @_;

    if ($monitor->{EISA_ID}) {
	log::l("EISA_ID: $monitor->{EISA_ID}");
	if (my ($mon) = grep { lc($_->{EISA_ID}) eq $monitor->{EISA_ID} } @$monitors) {
	    add2hash($monitor, $mon);
	    log::l("EISA_ID corresponds to: $monitor->{ModelName}");
	} elsif (!$monitor->{HorizSync} || !$monitor->{VertRefresh}) {
	    log::l("unknown EISA_ID and partial DDC probe, so unknown monitor");
	    delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};	    
	}
    } else {
	if (my ($mon) = grep { $_->{VendorName} eq $monitor->{VendorName} && $_->{ModelName} eq $monitor->{ModelName} } @$monitors) {
	    put_in_hash($monitor, $mon);
	}
    }

    return $monitor->{HorizSync} && $monitor->{VertRefresh};
}

sub getinfoFromDDC {
    my ($VideoRam, @l) = any::ddcxinfos() or return;

    my @Modes;
    local $_;
    while (($_ = shift @l) ne "\n") {
	my ($depth, $x, $y) = split;
	$depth = int(log($depth) / log(2));
	
	push @Modes, [ $x, $y, $depth ];
    }

    my ($h, $v, $size, @m) = @l;
    { 
        VideoRam_probed => to_int($VideoRam),
        HorizSync => first($h =~ /^(\S*)/), 
        VertRefresh => first($v =~ /^(\S*)/),
        size => to_float($size),
        if_($size =~ /EISA ID=(\S*)/, EISA_ID => lc($1), VendorName => "Plug'n Play"),
	#- not-used-anymore Modes => \@Modes,
        #- not-used-anymore ModeLines => join('', @m),
    };
}

sub monitors {
    readMonitorsDB("$ENV{SHARE_PATH}/ldetect-lst/MonitorsDB");
}
sub readMonitorsDB {
    my ($file) = @_;

    my @monitors;
    my $F = common::openFileMaybeCompressed($file);
    local $_;
    my $lineno = 0; while (<$F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(VendorName ModelName EISA_ID HorizSync VertRefresh dpms);
	my %l; @l{@fields} = split /\s*;\s*/;
	push @monitors, \%l;
    }
    \@monitors;
}


1;

