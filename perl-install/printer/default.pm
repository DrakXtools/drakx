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
    run_program::rooted($::prefix, "foomatic-configure",
			"-D", "-q", "-s", $printer->{SPOOLER},
			"-n", $printer->{DEFAULT}) or return 0;
    return 1;
}

sub get_printer {
    my $printer = $_[0];
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -Q -q -s $printer->{SPOOLER} |" or return undef;
    my $line;
    while ($line = <F>) {
	if ($line =~ m!^\s*<defaultqueue>(.*)</defaultqueue>\s*$!) {
	    return $1;
	}
    }
    return undef;
}

sub printer_type($) { "LOCAL" }

sub get_spooler () {
    if (-f "$::prefix$FOOMATIC_DEFAULT_SPOOLER") {
        my $spool = cat_("$::prefix$FOOMATIC_DEFAULT_SPOOLER");
	chomp $spool;
	return $spool if $spool =~ /cups|lpd|lprng|pdq/; 
    }
}

sub set_spooler ($) {
    my ($printer) = @_;
    # Mark the default driver in a file
    output_p("$::prefix$FOOMATIC_DEFAULT_SPOOLER", $printer->{SPOOLER});
}


1;
