package printer::common;

use strict;


sub addentry {
    my ($section, $entry, $filecontent) = @_;
    my $sectionfound = 0;
    my $entryinserted = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	if (!$sectionfound) {
	    if (/^\s*\[\s*$section\s*\]\s*$/) {
		$sectionfound = 1;
	    }
	} else {
	    if (!/^\s*$/ && !/^\s*;/) { #-#
		$_ = "$entry\n$_";
		$entryinserted = 1;
		last;
	    }
	}
    }
    if ($sectionfound && !$entryinserted) {
	push(@lines, $entry);
    }
    return join ("\n", @lines);
}

sub addsection {
    my ($section, $filecontent) = @_;
    my $entryinserted = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	if (/^\s*\[\s*$section\s*\]\s*$/) {
	    # section already there, nothing to be done
	    return $filecontent;
	}
    }
    return $filecontent . "\n[$section]";
}

sub removeentry {
    my ($section, $entry, $filecontent) = @_;
    my $sectionfound = 0;
    my $done = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	$_ = "$_\n";
	next if $done;
	if (!$sectionfound) {
	    if (/^\s*\[\s*$section\s*\]\s*$/) {
		$sectionfound = 1;
	    }
	} else {
	    if (/^\s*\[.*\]\s*$/) { # Next section
		$done = 1;
	    } elsif (/^\s*$entry/) {
		$_ = "";
		$done = 1;
	    }
	}
    }
    return join ("", @lines);
}

sub removesection {
    my ($section, $filecontent) = @_;
    my $sectionfound = 0;
    my $done = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	$_ = "$_\n";
	next if $done;
	if (!$sectionfound) {
	    if (/^\s*\[\s*$section\s*\]\s*$/) {
		$_ = "";
		$sectionfound = 1;
	    }
	} else {
	    if (/^\s*\[.*\]\s*$/) { # Next section
		$done = 1;
	    } else {
		$_ = "";
	    }
	}
    }
    return join ("", @lines);
}

1;
