package log;

use diagnostics;
use strict;

use c;

my ($LOG);


sub l {
    if ($::testing) {
	print STDERR @_, "\n";
    } elsif ($::isInstall) {
	if (!$LOG) {
	    open $LOG, '>>', '/var/log/stage2.log';
	    select((select($LOG),  $| = 1)[0]);
	}
	print $LOG "* ", @_, "\n";
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
