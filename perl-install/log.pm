package log; # $Id$

use diagnostics;
use strict;

use c;

my ($LOG, $LOG2);

#-#####################################################################################
#- Globals
#-#####################################################################################

#-######################################################################################
#- Functions
#-######################################################################################
sub F() { $LOG }

sub l {
    $LOG or openLog();
    if ($::testing) {
	print STDERR @_, "\n";
    } elsif ($LOG) {
	print $LOG "* ", @_, "\n";
	print $LOG2 "* ", @_, "\n" if $LOG2;
    } elsif ($::isStandalone) {
	c::syslog(c::LOG_WARNING(), join("", @_));
    } else {
	print STDERR @_, "\n";
    }
}

sub openLog {
    my ($o_file) = @_;

    if ($o_file) { #- useLocal
	open $LOG, "> $o_file";
    } elsif ($::isInstall) {
	open $LOG, "> /dev/tty3";
	open $LOG2, ">> /tmp/ddebug.log";
    }
    select((select($LOG),  $| = 1)[0]) if $LOG;
    select((select($LOG2), $| = 1)[0]) if $LOG2;
}

sub closeLog() { 
    if ($LOG) { 
	close $LOG; 
	close $LOG2;
    } elsif ($::isStandalone) {
	c::closelog();
    }
}

sub explanations {
    if ($::isStandalone) {
        c::syslog(c::LOG_INFO()|c::LOG_LOCAL1(), "@_");
    } else {
        l(@_);
    }
}

1;
