package printer::data;

use strict;
use common;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(%spoolers %spooler_inv %shortspooler_inv
	     $kernelversion $usbprintermodule
	     $commonpackages $gimpprintingpackages $localqueuepackages);


# Kernel-specific data
our $kernelversion = `uname -r 2>/dev/null`;
$kernelversion =~ s/^(\s*)(\d+\.\d+)(\..*)$/$2/;
chomp $kernelversion;

our $usbprintermodule = ($kernelversion eq '2.6' ? "usblp" : "printer");

# Packages which are always needed to run printerdrake
our $commonpackages = [ [ 'foomatic-db-engine' ], 
			[ '/usr/bin/foomatic-configure' ] ];

# Packages which are needed to print with the GIMP
our $gimpprintingpackages = [ [ 'gutenprint-gimp2' ], 
			      [ '/usr/lib/gimp/2.0/plug-ins/print' ] ];

# Packages which are needed to create and manage local print queues
our $localqueuepackages = [ [ 'foomatic-filters', 'foomatic-db',
			      'foomatic-db-hpijs', 'foomatic-db-engine',
			      'printer-filters', 
			      'printer-utils', 'printer-testpages', 
			      'ghostscript', 'hplip-hpijs', 'gutenprint-ijs',
			      'gutenprint-foomatic', 'gutenprint-escputil', 
			      'postscript-ppds', 
			      'hplip-model-data', 'nmap', 'scli' ],
			    [qw(/usr/bin/foomatic-rip
				/usr/share/foomatic/db/source/driver/ljet4.xml
				/usr/share/foomatic/db/source/driver/hpijs.xml
				/usr/bin/foomatic-configure
				/usr/bin/pnm2ppa
				/usr/bin/getusbprinterid
				/usr/share/printer-testpages/testprint.ps
				/usr/bin/gs-common
				/usr/bin/hpijs
				/usr/share/man/man1/ijsgutenprint.1.bz2
				/usr/share/foomatic/db/source/driver/gutenprint-ijs.5.0.xml
				/usr/bin/escputil
				/usr/share/cups/model/postscript.ppd.gz
				/usr/share/hplip/data/xml/models.xml
				/usr/bin/nmap
				/usr/bin/scli)] ];

# Spooler-specific data
our %spoolers = ('pdq' => {
                          'help' => "/usr/bin/pdq -h -P %s 2>&1 |",
			  'print_command' => 'lpr-pdq',
			  'print_gui' => 'xpdq',
			  'long_name' => N("PDQ - Print, Do not Queue"),
			  'short_name' => N("PDQ"),
			  'local_queues' => 1,
                          'packages2add' => [ [ 'pdq' ], [qw(/usr/bin/pdq /usr/X11R6/bin/xpdq)] ],
                          'alternatives' => [
                              [ 'lpr', '/usr/bin/lpr-pdq' ],
                              [ 'lpq', '/usr/bin/lpq-foomatic' ],
                              [ 'lprm', '/usr/bin/lprm-foomatic' ]
                          ],
			  },
		 'lpd' => {
                        'print_command' => 'lpr-lpd',
			'print_gui' => 'lpr-lpd',
			'long_name' => N("LPD - Line Printer Daemon"),
                        'short_name' => N("LPD"),
                        'boot_spooler' => 'lpd',
                        'service' => 'lpd',
			'local_queues' => 1,
                        'packages2add' => [ [qw(lpr net-tools a2ps ImageMagick)],
                                            [qw(/usr/sbin/lpf
                                                /usr/sbin/lpd
                                                /sbin/ifconfig
                                                /usr/bin/a2ps
                                                /usr/bin/convert)] ],
                        'packages2rm' => [ 'LPRng', '/usr/lib/filters/lpf' ],
                        'alternatives' => [
                            [ 'lpr', '/usr/bin/lpr-lpd' ],
                            [ 'lpq', '/usr/bin/lpq-lpd' ],
                            [ 'lprm', '/usr/bin/lprm-lpd' ],
                            [ 'lpc', '/usr/sbin/lpc-lpd' ]
                        ]
		    },
		 'lprng' => {
		     'print_command' => 'lpr-lpd',
		     'print_gui' => 'lpr-lpd',
		     'long_name' => N("LPRng - LPR New Generation"),
		     'short_name' => N("LPRng"),
		     'boot_spooler' => 'lpd',
		     'service' => 'lpd',
		     'local_queues' => 1,
		     'packages2add' => [ [qw(LPRng net-tools a2ps ImageMagick)],
					 [qw(/usr/lib/filters/lpf
					     /usr/sbin/lpd
					     /sbin/ifconfig
					     /usr/bin/a2ps
					     /usr/bin/convert)] ],
		     'packages2rm' => [ 'lpr', '/usr/sbin/lpf' ],
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
		     'help' => "/usr/bin/lphelp %s |",
		     'print_command' => 'lpr-cups',
		     'print_gui' => 'xpp',
		     'long_name' => N("CUPS - Common Unix Printing System"),
		     'short_name' => N("CUPS"),
		     'boot_spooler' => 'cups',
		     'service' => 'cups',
		     'local_queues' => 1,
		     'packages2add' => [ ['cups', 'net-tools', 'xpp', 'cups-drivers', 'gutenprint-cups', 'desktop-printing',
					  $::isInstall ? 'curl' : 'webfetch'],
					 [ qw(/usr/lib/cups/cgi-bin/printers.cgi
					      /sbin/ifconfig
					      /usr/bin/xpp
					      /usr/lib/cups/filter/rastertolxx74 
					      /usr/lib/cups/filter/commandtoepson
					      /usr/bin/eggcups),
					   $::isInstall ||
					   !(-x '/usr/bin/wget') ?
					   '/usr/bin/curl' :
					   '/usr/bin/wget' ] ],
		     'alternatives' => [
					[ 'lpr', '/usr/bin/lpr-cups' ],
					[ 'lpq', '/usr/bin/lpq-cups' ],
					[ 'lprm', '/usr/bin/lprm-cups' ],
					[ 'lp', '/usr/bin/lp-cups' ],
					[ 'cancel', '/usr/bin/cancel-cups' ],
					[ 'lpstat', '/usr/bin/lpstat-cups' ],
					[ 'lpc', '/usr/sbin/lpc-cups' ]
					]
				    },
		 'rcups' => {
		     'help' => "/usr/bin/lphelp %s |",
		     'print_command' => 'lpr-cups',
		     'print_gui' => 'xpp',
		     'long_name' => N("CUPS - Common Unix Printing System (remote server)"),
		     'short_name' => N("Remote CUPS"),
		     'local_queues' => 0,
		     'packages2add' => [ ['cups-common', 'xpp'],
					 ['/usr/bin/lpr-cups',
					  '/usr/bin/xpp'] ],
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
