package log; # $Id$

use diagnostics;
use strict;
use vars qw(*LOG *LOG2);

use c;


#-#####################################################################################
#- Globals
#-#####################################################################################
my $logOpen = 0;
my $logDebugMessages = 0;

#-######################################################################################
#- Functions
#-######################################################################################
sub F() { *LOG }

sub l {
    $logOpen or openLog();
    if ($::testing) {
	print STDERR @_, "\n";
    } elsif ($::isStandalone) {
	c::syslog(c::LOG_WARNING(), join("", @_));
    } elsif ($::isInstall) {
	print LOG "* ", @_, "\n";
	print LOG2 "* ", @_, "\n";
    } else {
	print STDERR @_, "\n";
    }
}
sub ld { $logDebugMessages and &l }
sub w { &l }

sub openLog(;$) {
    if ($::isInstall) {
	if ($_[0]) { #- useLocal
	    open LOG, "> $_[0]"; #-#
	} else {
	    open LOG, "> /dev/tty3"; #-#
	}
	open LOG2, ">> /tmp/ddebug.log"; #-#
	select((select(LOG),  $| = 1)[0]);
	select((select(LOG2), $| = 1)[0]);
    }
    exists $ENV{DEBUG} and $logDebugMessages = 1;
    $logOpen = 1;
}

sub closeLog() { 
    if ($::isStandalone) {
	c::closelog();
    } else { close LOG; close LOG2 }
}

1;
