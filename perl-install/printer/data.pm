package printer::data;

use strict;
use common;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(%lprcommand  %spoolers %spooler_inv %shortspooler_inv);


# BUG, FIXME : this was neither declered nor setted anywhere before :
# maybe this should be swtiched : 
# $lprcommand{stuff} => $spoolers{stuff}{print_command}

our %spoolers = ('ppq' => {
                          'help' => "/usr/bin/lphelp %s |",
					 'print_command' => 'lpr-pdq',
					 'long_name' => N("PDQ - Print, Don't Queue"),
					 'short_name' => N("PDQ"),
                          'alternatives' => [
                              [ 'lpr', '/usr/bin/lpr-pdq' ],
                              [ 'lpq', '/usr/bin/lpq-foomatic' ],
                              [ 'lprm', '/usr/bin/lprm-foomatic' ]
                          ]
                 },
                'lpd' => {
                        'help' => "/usr/bin/pdq -h -P %s 2>&1 |",
                        'print_command' => 'lpr',
				    'long_name' => N("LPD - Line Printer Daemon"),
                        'short_name' => N("LPD"),
                        'alternatives' => [
                            [ 'lpr', '/usr/bin/lpr-lpd' ],
                            [ 'lpq', '/usr/bin/lpq-lpd' ],
                            [ 'lprm', '/usr/bin/lprm-lpd' ],
                            [ 'lpc', '/usr/sbin/lpc-lpd' ]
                        ]
                 },
			 'lprng' => {
				'print_command' => 'lpr-lpd',
				'long_name' => N("LPRng - LPR New Generation"),
				'short_name' => N("LPRng"),
                    'alternatives' => [
                        [ 'lpr', '/usr/bin/lpr-lpd' ],
                        [ 'lpq', '/usr/bin/lpq-lpd' ],
                        [ 'lprm', '/usr/bin/lprm-lpd' ],
                        [ 'lp', '/usr/bin/lp-lpd' ],
                        [ 'cancel', '/usr/bin/cancel-lpd' ],
                        [ 'lpstat', '/usr/bin/lpstat-lpd' ],
                        [ 'lpc', '/usr/sbin/lpc-lpd' ]
                    ]
			 },
			 'cups' => {
				'print_command' => 'lpr-cups',
				'long_name' => N("CUPS - Common Unix Printing System"),
				'short_name' => N("CUPS"),
                    'alternatives' => [
                        [ 'lpr', '/usr/bin/lpr-cups' ],
                        [ 'lpq', '/usr/bin/lpq-cups' ],
                        [ 'lprm', '/usr/bin/lprm-cups' ],
                        [ 'lp', '/usr/bin/lp-cups' ],
                        [ 'cancel', '/usr/bin/cancel-cups' ],
                        [ 'lpstat', '/usr/bin/lpstat-cups' ],
                        [ 'lpc', '/usr/sbin/lpc-cups' ]
                    ]
			 }
            );
our %spooler_inv = map { $spoolers{$_}{long_name} => $_ } keys %spoolers;

our %shortspooler_inv = map { $spoolers{$_}{short_name} => $_ } keys %spoolers;
