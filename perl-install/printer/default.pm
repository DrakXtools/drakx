package printer::default;

use strict;
use run_program;
use common;

#-configuration directory of Foomatic
my $FOOMATICCONFDIR = "/etc/foomatic"; 
#-location of the file containing the default spooler's name
my $FOOMATIC_DEFAULT_SPOOLER = "$FOOMATICCONFDIR/defaultspooler";

sub set_printer {
    my ($printer) = $_[0];
    my $spooler = $printer->{SPOOLER};
    $spooler = "cups" if $spooler eq "rcups";
    run_program::rooted($::prefix, "foomatic-configure",
			"-D", "-q", "-s", $spooler,
			"-n", $printer->{DEFAULT}) or return 0;
    return 1;
}

sub get_printer {
    my $printer = $_[0];
    my $spooler = $printer->{SPOOLER};
    $spooler = "cups" if $spooler eq "rcups";
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -Q -q -s $spooler |" or return undef;
    my $line;
    while ($line = <F>) {
	if ($line =~ m!^\s*<defaultqueue>(.*)</defaultqueue>\s*$!) {
	    return $1;
	}
    }
    return undef;
}

sub printer_type() { "LOCAL" }

sub get_spooler () {
    if (-f "$::prefix$FOOMATIC_DEFAULT_SPOOLER") {
        my $spool = cat_("$::prefix$FOOMATIC_DEFAULT_SPOOLER");
	chomp $spool;
	if ($spool =~ /cups/) {
	    my ($daemonless_cups, $_remote_cups_server) =
		printer::main::read_client_conf();
	    $spool = ($daemonless_cups > 0 ? "rcups" : "cups");
	}
	return $spool if $spool =~ /cups|lpd|lprng|pdq/;
    }
}

sub set_spooler ($) {
    my ($printer) = @_;
    # Mark the default driver in a file
    output_p("$::prefix$FOOMATIC_DEFAULT_SPOOLER", $printer->{SPOOLER});
}


1;
