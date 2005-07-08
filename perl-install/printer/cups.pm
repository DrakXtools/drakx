package printer::cups;

use strict;

use printer::data;
use run_program;
use common;


#------------------------------------------------------------------------------

sub lpstat_lpv() {

    # Get a list of remotely defined print queues, with "Description" and
    # "Location"

    # Info to return
    my @items;

    # Hash to simplify the adding of the URIs
    my $itemshash;

    # Run the "lpstat" command in a mode to give as much info about the
    # print queues as possible
    my @lpstat = run_program::rooted_get_stdout
	($::prefix, 'lpstat', '-l', '-p', '-v');
    
    my $currentitem = -1;
    for my $line (@lpstat) {
	chomp($line);
	if ($line !~ m!^\s*$!) {
	    if ($line =~ m!^printer\s+(\S+)\s+(\S.*)$!) {
		# Beginning of new printer's entry
		my $name = $1;
		push(@items, {});
		$currentitem = $#items;
		$itemshash->{$name} = $currentitem;
		$items[$currentitem]{queuename} ||= $name;
	    } elsif ($line =~ m!^\s+Description:\s+(\S.*)$!) {
		# Description field
		if ($currentitem != -1) {
		    $items[$currentitem]{description} ||= $1;
		}
	    } elsif ($line =~ m!^\s+Location:\s+(\S.*)$!) {
		# Location field
		if ($currentitem != -1) {
		    $items[$currentitem]{location} ||= $1;
		}
	    } elsif ($line =~ m!^device\s+for\s+(\S+):\s+(\S.*)$!) {
		# "device for ..." line, extract URI
		my $name = $1;
		my $uri = $2;
		if (defined($itemshash->{$name})) {
		    if ($uri !~ /:/) { $uri = "file:" . $uri }
		    $currentitem = $itemshash->{$name};
		    if (($currentitem <= $#items) &&
			($items[$currentitem]{queuename} eq $name)) {
			$items[$currentitem]{uri} ||= $uri;
			if ($uri =~ m!^ipp://([^/:]+)[:/]!) {
			    $items[$currentitem]{ipp} = $1;
			}
		    }
		}
	    }
	}
    }
    return @items;
}

sub lpstat_v() {
    map {
	if (my ($queuename, $uri) = m/^\s*device\s+for\s+([^:\s]+):\s*(\S+)\s*$/) {
	    +{ queuename => $queuename, uri => $uri, if_($uri =~ m!^ipp://([^/:]+)[:/]!, ipp => $1) };
	} else {
	    ();
	}
    } run_program::rooted_get_stdout($::prefix, 'lpstat', '-v');
}

sub lpinfo_v() {
    map {
	if (my ($type, $uri) = m/^\s*(\S+)\s+(\S+)\b/) {
	    if ($uri =~ m!:/!) {
		$uri;
	    } elsif ($type =~ m/network/i) {
		"$uri://";
	    } else {
		"$uri:/";
	    }
	} else {
	    ();
	}
    } run_program::rooted_get_stdout($::prefix, 'lpinfo', '-v');
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
	join('!', if_($printer->{expert}, N("CUPS")), N("Configured on other machines"), $_);
    } map {
	my $comment = N("On CUPS server \"%s\"", ($_->{ipp} ? $_->{ipp} : $printer->{remote_cups_server})) . ($_->{queuename} eq $printer->{DEFAULT} ? N(" (Default)") : "");
	"$_->{queuename}: $comment";
    } grep { 
	!$printer->{configured}{$_->{queuename}};
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

sub queue_enabled {
    my ($queue) = @_;
    0 != grep {
	/\b$queue\b.*\benabled\b/i;
    } run_program::rooted_get_stdout($::prefix, 'lpstat', '-p', $queue);
}



1;
