package printer::common;

use strict;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(addentry addsection removeentry  removesection);


sub addentry {
    my ($section, $entry, $filecontent) = @_;
    my $sectionfound = 0;
    my $entryinserted = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	if (!$sectionfound) {
	    $sectionfound = 1 if /^\s*\[\s*$section\s*\]\s*$/;
	} else {
	    if (!/^\s*$/ && !/^\s*;/) { #-#
		$_ = "$entry\n$_";
		$entryinserted = 1;
		last;
	    }
	}
    }
    push(@lines, $entry) if $sectionfound && !$entryinserted;
    return join ("\n", @lines);
}

sub addsection {
    my ($section, $filecontent) = @_;
    my $entryinserted = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
     # section already there, nothing to be done
     return $filecontent if /^\s*\[\s*$section\s*\]\s*$/;
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
	    $sectionfound = 1 if /^\s*\[\s*$section\s*\]\s*$/;
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
