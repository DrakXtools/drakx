package Xconfig::monitor; #- $Id$

use diagnostics;
use strict;

use detect_devices;
use common;
use any;
use log;


sub good_default_monitor() {
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

sub configure {
    my ($in, $raw_X, $nb_monitors, $o_ddc_info, $b_auto) = @_;

    my $monitors = [ $raw_X->get_or_new_monitors($nb_monitors) ];
    if ($o_ddc_info) {
	put_in_hash($monitors->[0], $o_ddc_info);
    }
    my $head_nb = 1;
    foreach my $monitor (@$monitors) {
	choose($in, $monitor, @$monitors > 1 ? $head_nb++ : 0, $b_auto) or return;
    }
    $raw_X->set_monitors(@$monitors);
    $monitors;
}

sub configure_auto_install {
    my ($raw_X, $old_X) = @_;

    if ($old_X->{monitor}) {
	#- keep compatibility
	$old_X->{monitor}{VertRefresh} = $old_X->{monitor}{vsyncrange};
	$old_X->{monitor}{HorizSync} = $old_X->{monitor}{hsyncrange};

	#- new name
	$old_X->{monitors} = [ delete $old_X->{monitor} ];
    }

    my $monitors = [ $raw_X->get_or_new_monitors($old_X->{monitors} ? int @{$old_X->{monitors}} : 1) ];
    mapn {
	my ($monitor, $auto_install_monitor) = @_;
	put_in_hash($monitor, $auto_install_monitor);
    } $monitors, $old_X->{monitors} if $old_X->{monitors};

    if (!$monitors->[0]{HorizSync}) {
	put_in_hash($monitors->[0], getinfoFromDDC());
    }

    my $monitors_db = monitors_db();
    foreach my $monitor (@$monitors) {
	if (!configure_automatic($monitor, $monitors_db)) {
	    good_default_monitor() =~ /(.*)\|(.*)/ or internal_error("bad good_default_monitor");
	    put_in_hash($monitor, { VendorName => $1, ModelName => $2 });
	    configure_automatic($monitor, $monitors_db) or internal_error("good_default_monitor (" . good_default_monitor()  . ") is unknown in MonitorDB");
	}
    }
    $raw_X->set_monitors(@$monitors);
    $monitors;
}

sub choose {
    my ($in, $monitor, $head_nb, $b_auto) = @_;

    my $monitors_db = monitors_db();

    my $ok = configure_automatic($monitor, $monitors_db);
    if ($b_auto) {
	log::l("Xconfig::monitor: auto failed") if !$ok;
	return $ok;
    }

    my %h_monitors = map { ("$_->{VendorName}|$_->{ModelName}" => $_) } @$monitors_db;

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

    $in->ask_from_({ title => N("Monitor"),
		     messages => $head_nb ? N("Choose a monitor for head #%d", $head_nb) : N("Choose a monitor"), 
		     interactive_help_id => 'configureX_monitor' 
		   },
		  [ { val => \$merged_name, separator => '|', 
		      list => ['Custom', "Plug'n Play", sort keys %h_monitors],
		      format => sub { $_[0] eq 'Custom' ? N("Custom") : 
				      $_[0] eq "Plug'n Play" ? N("Plug'n Play") . ($monitor->{VendorName} eq "Plug'n Play" ? " ($monitor->{ModelName})" : '') :
				      $_[0] =~ /^Generic\|(.*)/ ? N("Generic") . "|$1" :  
				      N("Vendor") . "|$_[0]" },
		      sort => 0 } ]) or return;

    if ($merged_name eq "Plug'n Play") {
	local $::noauto = 0; #- hey, you asked for plug'n play, so i do probe!
	delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};
	put_in_hash($monitor, getinfoFromDDC()) if $head_nb <= 1;
	if ($head_nb > 1 || configure_automatic($monitor, $monitors_db)) {
	    $monitor->{VendorName} = "Plug'n Play";
	} else {
	    $in->ask_warn('', N("Plug'n Play probing failed. Please select the correct monitor"));
	    goto ask_monitor;
	}
    } elsif ($merged_name eq 'Custom') {
	$in->ask_from('',
N("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
		      [ { val => \$monitor->{HorizSync}, list => \@HorizSync_ranges, label => N("Horizontal refresh rate"), not_edit => 0 },
			{ val => \$monitor->{VertRefresh}, list => \@VertRefresh_ranges, label => N("Vertical refresh rate"), not_edit => 0 } ]) or goto &choose;
	delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};
    } else {
	put_in_hash($monitor, $h_monitors{$merged_name});
    }
    $monitor->{manually_chosen} = 1;
    1;
}

sub configure_automatic {
    my ($monitor, $monitors_db) = @_;

    if ($monitor->{EISA_ID}) {
	log::l("EISA_ID: $monitor->{EISA_ID}");
	if (my $mon = find { lc($_->{EISA_ID}) eq $monitor->{EISA_ID} } @$monitors_db) {
	    add2hash($monitor, $mon);
	    log::l("EISA_ID corresponds to: $monitor->{ModelName}");
	} elsif (!$monitor->{HorizSync} || !$monitor->{VertRefresh}) {
	    log::l("unknown EISA_ID and partial DDC probe, so unknown monitor");
	    delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};	    
	}
    } elsif ($monitor->{VendorName}) {
	if (my $mon = find { $_->{VendorName} eq $monitor->{VendorName} && $_->{ModelName} eq $monitor->{ModelName} } @$monitors_db) {
	    put_in_hash($monitor, $mon);
	}
    }

    return $monitor->{HorizSync} && $monitor->{VertRefresh};
}

sub getinfoFromDDC() {
    my ($VideoRam, @l) = any::ddcxinfos() or return;

    my @Modes;
    local $_;
    while (($_ = shift @l) ne "\n") {
	my ($depth, $x, $y) = split;
	$depth = int(log($depth) / log(2));
	
	push @Modes, [ $x, $y, $depth ];
    }

    my ($h, $v, $size, @_modes) = @l;
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

sub monitors_db() {
    readMonitorsDB("$ENV{SHARE_PATH}/ldetect-lst/MonitorsDB");
}
sub readMonitorsDB {
    my ($file) = @_;

    my @monitors_db;
    my $F = openFileMaybeCompressed($file);
    local $_;
    my $lineno = 0; while (<$F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(VendorName ModelName EISA_ID HorizSync VertRefresh dpms);
	my %l; @l{@fields} = split /\s*;\s*/;
	push @monitors_db, \%l;
    }
    \@monitors_db;
}


1;

