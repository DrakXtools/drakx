package printer::cups;

use strict;
use printer::data;

sub get_remote_queues {
    my ($printer) = $_[0];
    # The following code reads in a list of all remote printers which the
    # local CUPS daemon knows due to broadcasting of remote servers or 
    # "BrowsePoll" entries in the local /etc/cups/cupsd.conf
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"lpstat -v |" or return ();
    my @printerlist;
    my $line;
    while ($line = <F>) {
	if ($line =~ m/^\s*device\s+for\s+([^:\s]+):\s*(\S+)\s*$/) {
	    my $queuename = $1;
	    if ($2 =~ m!^ipp://([^/:]+)[:/]! &&
		!$printer->{configured}{$queuename}) {
		my $server = $1;
		push (@printerlist, "$queuename|$server");
	    }
	}
    }
    close F;
    return @printerlist;
}

1;
