package printer::data;

use strict;
use common;

# BUG, FIXME : this was neither declered nor setted anywhere before :
# maybe this should be swtiched : 
# $lprcommand{stuff} => $spoolers{stuff}{print_command}

our %lprcommand;

our %spoolers = ('ppq' => {
                          'help' => "/usr/bin/lphelp %s |",
					 'print_command' => 'lpr-pdq',
					 'long_name' => N("PDQ - Print, Don't Queue"),
					 'short_name' => N("PDQ")
                 },
                'lpd' => {
                        'help' => "/usr/bin/pdq -h -P %s 2>&1 |",
                        'print_command' => 'lpr',
				    'long_name' => N("LPD - Line Printer Daemon"),
					   'short_name' => N("LPD")
                 },
			 'lprng' => {
				'print_command' => 'lpr-lpd',
				'long_name' => N("LPRng - LPR New Generation"),
				'short_name' => N("LPRng")
			 },
			 'cups' => {
				'print_command' => 'lpr-cups',
				'long_name' => N("CUPS - Common Unix Printing System"),
				'short_name' => N("CUPS")
			 }
            );
our %spooler_inv = map { $spoolers{$_}{long_name} => $_ } keys %spoolers;

our %shortspooler_inv = map { $spoolers{$_}{short_name} => $_ } keys %spoolers;
