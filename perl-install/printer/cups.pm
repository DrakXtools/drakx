package printer::cups;

use strict;

use printer::data;
use run_program;
use common;


#------------------------------------------------------------------------------
sub lpstat_v {
    map {
	if (my ($queuename, $uri) = m/^\s*device\s+for\s+([^:\s]+):\s*(\S+)\s*$/) {
	    +{ queuename => $queuename, uri => $uri, if_($uri =~ m!^ipp://([^/:]+)[:/]!, ipp => $1) };
	} else {
	    ();
	}
    } run_program::rooted_get_stdout($::prefix, 'lpstat', '-v');
}

sub read_printer_list {
    my ($printer) = @_;
    # This function reads in a list of all printers which the local CUPS
    # daemon currently knows, including remote ones.
    map {
	my $comment = 
	  $_->{ipp} && !$printer->{configured}{$_->{queuename}} ?
	    N("(on %s)", $_->{ipp}) : N("(on this machine)");
	"$_->{queuename} $comment";
    } lpstat_v();
}

sub get_formatted_remote_queues {
    my ($printer) = @_;

    # This function reads in a list of all remote printers which the local 
    # CUPS daemon knows due to broadcasting of remote servers or 
    # "BrowsePoll" entries in the local /etc/cups/cupsd.conf/
    map {
	join('!', if_($::expert, N("CUPS")), N("Remote Printers"), $_);
    } map {
	my $comment = N("On CUPS server \"%s\"", $_->{ipp}) . ($_->{queuename} eq $printer->{DEFAULT} ? N(" (Default)") : "");
	"$_->{queuename}: $comment";
    } grep { 
	$_->{ipp} && !$printer->{configured}{$_->{queuename}};
    } lpstat_v();
}

sub get_remote_queues {
    my ($printer) = @_;
    # The following code reads in a list of all remote printers which the
    # local CUPS daemon knows due to broadcasting of remote servers or 
    # "BrowsePoll" entries in the local /etc/cups/cupsd.conf
    map {
	"$_->{queuename}|$_->{ipp}";
    } grep { 
	$_->{ipp} && !$printer->{configured}{$_->{queuename}};
    } lpstat_v();
}

1;
