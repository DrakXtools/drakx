package log; # $Id$

use diagnostics;
use strict;
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
    if ($::isStandalone) {
	c::syslog(join "", @_);
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
    if ($::isStandalone) {
	c::openlog("DrakX");
    } elsif ($::isInstall) {
	if ($_[0]) { #- useLocal
	    open LOG, "> $_[0]";# or die "no log possible :(";
	} else {
	    open LOG, "> /dev/tty3" or open LOG, ">> /tmp/install.log";# or die "no log possible :(";
	}
	open LOG2, ">> /tmp/ddebug.log";# or die "no log possible :(";
	select((select(LOG),  $| = 1)[0]);
	select((select(LOG2), $| = 1)[0]);
    }
    exists $ENV{DEBUG} and $logDebugMessages = 1;
    $logOpen = 1;
}

sub closeLog() { 
    if ($::isStandalone) {
	c::closelog();
    } else { close LOG; close LOG2; }
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
