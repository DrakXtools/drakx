package log; # $Id$

use diagnostics;
use strict;

use c;

my ($LOG, $LOG2);


sub l {
    if ($::testing) {
	print STDERR @_, "\n";
    } elsif ($::isInstall) {
	if (!$LOG) {
	    open $LOG, '>>', '/tmp/ddebug.log';
	    open $LOG2, '>', '/dev/tty3' if !$::local_install;
	    select((select($LOG),  $| = 1)[0]);
	    select((select($LOG2), $| = 1)[0]) if !$::local_install;
	}
	print $LOG "* ", @_, "\n";
	print $LOG2 "* ", @_, "\n" if $LOG2;
    } elsif ($::isStandalone) {
	#- openlog was done in standalone.pm

	c::syslog(c::LOG_WARNING(), join("", @_));
    } else {
	print STDERR @_, "\n";
    }
}

sub openLog {
    my ($file) = @_;
    open $LOG, "> $file";
    select((select($LOG),  $| = 1)[0]);
}

sub closeLog() { 
    if ($LOG) { 
	close $LOG; 
	close $LOG2 if $LOG2;
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
