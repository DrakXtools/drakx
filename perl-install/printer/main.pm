package printer::main;

# $Id$

use strict;

use common;
use run_program;
use printer::data;
use printer::services;
use printer::default;
use printer::cups;
use printer::detect;
use handle_configs;
use services;
use lang;

use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(%printer_type %printer_type_inv);

#-Did we already read the subroutines of /usr/sbin/ptal-init?
my $ptalinitread = 0;

our %printer_type = (
    N("Local printer")                              => "LOCAL",
    N("Remote printer")                             => "REMOTE",
    N("Printer on remote CUPS server")              => "CUPS",
    N("Printer on remote lpd server")               => "LPD",
    N("Network printer (TCP/Socket)")               => "SOCKET",
    N("Printer on SMB/Windows server")              => "SMB",
    N("Printer on NetWare server")                  => "NCP",
    N("Enter a printer device URI")                 => "URI",
    N("Pipe job into a command")                    => "POSTPIPE"
);

our %printer_type_inv = reverse %printer_type;

our %thedb;
our %linkedppds;

our $hplipdevicesdb;

# Translation of the "(recommended)" in printer driver entries
our $recstr = N("recommended");
our $precstr = "($recstr)";
our $sprecstr = quotemeta($precstr);

#------------------------------------------------------------------------------

sub spooler() {
    # LPD is taken from the menu for the moment because the classic LPD is
    # highly unsecure. Depending on how the GNU lpr development is going on
    # LPD support can be reactivated by uncommenting the following line.

    #return @spooler_inv{qw(cups lpd lprng pdq)};

    # LPRng is not officially supported any more since version 9.0 of
    # this distribution, so show it only in the spooler menu when it
    # was manually installed.

    # PDQ is not officially supported any more since version 9.1, so
    # show it only in the spooler menu when it was manually installed.

    return map { $spoolers{$_}{long_name} } ('cups', 'rcups' , 
    if_(files_exist(qw(/usr/bin/pdq)), 'pdq'),
    if_(files_exist(qw(/usr/lib/filters/lpf /usr/sbin/lpd)), 'lprng'));
}

sub printer_type($) {
    my ($printer) = @_;
    for ($printer->{SPOOLER}) {
	/cups/  and return @printer_type_inv{qw(LOCAL LPD SOCKET SMB), if_($printer->{expert}, qw(URI))};
	/lpd/   and return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP), if_($printer->{expert}, qw(POSTPIPE URI))};
	/lprng/ and return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP), if_($printer->{expert}, qw(POSTPIPE URI))};
	/pdq/   and return @printer_type_inv{qw(LOCAL LPD SOCKET), if_($printer->{expert}, qw(URI))};
	/rcups/ and return ();
    }
}

sub SIGHUP_daemon {
    my ($service) = @_;
    if ($service eq "cupsd") { $service = "cups" }
    # PDQ and remote CUPS have no daemons, exit.
    if (($service eq "pdq") || ($service eq "rcups")) { return 1 }
    # CUPS needs auto-correction for its configuration
    run_program::rooted($::prefix, "/usr/sbin/correctcupsconfig") if $service eq "cups";
    # Name of the daemon
    my %daemons = (
			    "lpr" => "lpd",
			    "lpd" => "lpd",
			    "lprng" => "lpd",
			    "cups" => "cupsd",
			    "devfs" => "devfsd",
			    );
    my $daemon = $daemons{$service};
    $daemon = $service unless defined $daemon;
#    if ($service eq "cups") {
#	# The current CUPS (1.1.13) dies on SIGHUP, do the normal restart.
#	printer::services::restart($service);
#	# CUPS needs some time to come up.
#	printer::services::wait_for_cups();
#    } else {

    # Send the SIGHUP
    run_program::rooted($::prefix, "/usr/bin/killall", "-HUP", $daemon);
    if ($service eq "cups") {
	# CUPS needs some time to come up.
	printer::services::wait_for_cups();
    }

    return 1;
}


sub assure_device_is_available_for_cups {
    # Checks whether CUPS already "knows" a certain port, it does not
    # know it usually when the appropriate kernel module is loaded
    # after CUPS was started or when the printer is turned on after
    # CUPS was started. CUPS 1.1.12 and newer refuses to set up queues
    # on devices which it does not know, it points these queues to
    # file:/dev/null instead. Restart CUPS if necessary to assure that
    # CUPS knows the device.
    my ($device) = @_;
    my $sdevice = handle_configs::searchstr($device);
    my ($result, $i);
    # USB printers get special model-dependent URLs in "lpinfo -v" here
    # checking is complicated, so we simply restart CUPS then and ready.
    if ($device =~ /usb/) {
	$result = printer::services::restart("cups");
	return 1;
    }
    my $maxattempts = 3;
    for ($i = 0; $i < $maxattempts; $i++) {
	open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
	    '/bin/sh -c "export LC_ALL=C; /usr/sbin/lpinfo -v" |') or
	    die 'Could not run "lpinfo"!';
	while (my $line = <$F>) {
	    if ($line =~ /$sdevice/) { # Found a line containing the device
		                       # name, so CUPS knows it.
		close $F;
		return 1;
	    }
	}
	close $F;
	$result = printer::services::restart("cups");
    }
    return $result;
}


sub spooler_in_security_level {
    # Was the current spooler already added to the current security level?
    my ($spooler, $level) = @_;
    my $sp;
    $sp = $spooler eq "lpr" || $spooler eq "lprng" ? "lpd" : $spooler;
    my $file = "$::prefix/etc/security/msec/server.$level";
    if (-f $file) {
	open(my $F, "< $file") or return 0;
	while (my $line = <$F>) {
	    if ($line =~ /^\s*$sp\s*$/) {
		close $F;
		return 1;
	    }
	}
	close $F;
    }
    return 0;
}

sub add_spooler_to_security_level {
    my ($spooler, $level) = @_;
    my $sp;
    $sp = $spooler eq "lpr" || $spooler eq "lprng" ? "lpd" : $spooler;
    my $file = "$::prefix/etc/security/msec/server.$level";
    if (-f $file) {
	   eval { append_to_file($file, "$sp\n") } or return 0;
    }
    return 1;
}

sub pdq_panic_button {
    my $setting = $_[0];
    if (-f "$::prefix/usr/sbin/pdqpanicbutton") {
        run_program::rooted($::prefix, "/usr/sbin/pdqpanicbutton", "--$setting")
	    or die "Could not $setting PDQ panic buttons!";
    }
}

sub copy_printer_params($$) {
    my ($from, $to) = @_;
    map { $to->{$_} = $from->{$_} } grep { $_ ne 'configured' } keys %$from; 
    #- avoid cycles-----------------^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
}

sub getinfo($) {
    my ($prefix) = @_;
    my $printer = {};

    $::prefix = $prefix;

    # Initialize $printer data structure
    resetinfo($printer);

    return $printer;
}

#------------------------------------------------------------------------------
sub resetinfo($) {
    my ($printer) = @_;
    $printer->{QUEUE} = "";
    $printer->{OLD_QUEUE} = "";
    $printer->{OLD_CHOICE} = "";
    $printer->{ARGS} = {};
    $printer->{DBENTRY} = "";
    $printer->{DEFAULT} = "";
    $printer->{currentqueue} = {};
    # -check which printing system was used previously and load the information
    # -about its queues
    read_configured_queues($printer);
}

sub read_configured_queues($) {
    my ($printer) = @_;
    my @QUEUES;
    # Get the default spooler choice from the config file
    $printer->{SPOOLER} ||= printer::default::get_spooler();
    if (!$printer->{SPOOLER}) {
	#- Find the first spooler where there are queues
	foreach my $spooler (qw(rcups cups pdq lprng lpd)) {
	    #- Is the spooler's daemon running?
	    my $service = $spooler;
	    if ($service eq "lprng") {
		$service = "lpd";
	    }
	    if (($service ne "pdq") && ($service ne "rcups")) {
		next unless services::is_service_running($service);
		# daemon is running, spooler found
		$printer->{SPOOLER} = $spooler;
	    }
	    #- poll queue info
	    if ($service ne "rcups") {
		open(my $F, ($::testing ? 
			     $::prefix : "chroot $::prefix/ ") .
		     "foomatic-configure -P -q -s $spooler |") or
		     die "Could not run foomatic-configure";
		eval join('', <$F>);
		close $F;
	    }
	    if ($service eq "pdq") {
		#- Have we found queues? PDQ has no damon, so we consider
		#- it in use when there are defined printer queues
		if ($#QUEUES != -1) {
		    $printer->{SPOOLER} = $spooler;
		    last;
		}
	    } elsif ($service eq "rcups") {
		#- In daemon-less CUPS mode there are no local queues,
		#- we can only recognize it by a server entry in
		#- /etc/cups/client.conf
		my ($daemonless_cups, $remote_cups_server) =
		    printer::main::read_client_conf();
		if ($daemonless_cups) {
		    $printer->{SPOOLER} = $spooler;
		    $printer->{remote_cups_server} = $remote_cups_server;
		    last;
		}
	    } else {
		#- For other spoolers we have already found a running
		#- daemon when we have arrived here
		last;
	    }
	}
    } else {
	if ($printer->{SPOOLER} ne "rcups") {
	    #- Poll the queues of the current default spooler
	    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
		 "foomatic-configure -P -q -s $printer->{SPOOLER} -r |") or
		 die "Could not run foomatic-configure";
	    eval join('', <$F>);
	    close $F;
	} else {
	    my ($_daemonless_cups, $remote_cups_server) =
		printer::main::read_client_conf();
	    $printer->{remote_cups_server} = $remote_cups_server;
	}
    }
    $printer->{configured} = {};
    my $i;
    my $N = $#QUEUES + 1;
    for ($i = 0;  $i < $N; $i++) {
	# Set the default printer
	$printer->{DEFAULT} = $QUEUES[$i]{queuedata}{queue} if
	    $QUEUES[$i]{queuedata}{default};
	# Advance to the next entry if the current is a remotely defined
	# printer
	next if $QUEUES[$i]{queuedata}{remote};
	# Add an entry for a locally defined queue
	$printer->{configured}{$QUEUES[$i]{queuedata}{queue}} = 
	    $QUEUES[$i];
	if (!$QUEUES[$i]{make} || !$QUEUES[$i]{model}) {
	    if ($printer->{SPOOLER} eq "cups") {
		$printer->{OLD_QUEUE} = $QUEUES[$i]{queuedata}{queue};
		my $descr = get_descr_from_ppd($printer);
		if ($descr =~ m/^([^\|]*)\|([^\|]*)(\|.*|)$/) {
		    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{make} ||= $1;
		    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{model} ||= $2;
	        }
		# Read out which PPD file was originally used to set up this
		# queue
		if (open(my $F, "< $::prefix/etc/cups/ppd/$QUEUES[$i]{queuedata}{queue}.ppd")) {
		    while (my $line = <$F>) {
			if ($line =~ /^\*%MDKMODELCHOICE:(.+)$/) {
			    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd} = $1;
			}
		    }
		    close $F;
		}
		# Mark that we have a CUPS queue but do not know the name
		# the PPD file in /usr/share/cups/model
		if ((!$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd}) &&
		    (! -r $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd})) {
		    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd} = '1';
		}
		$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{driver} = 'PPD';
		$printer->{OLD_QUEUE} = "";
	    }
	    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{make} ||= "";
	    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{model} ||= N("Unknown model");
	} else {
	    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{make} = $QUEUES[$i]{make};
	    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{model} = $QUEUES[$i]{model};
	}
	# Fill in "options" field
	if (my $args = $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{args}) {
	    my @options;
	    foreach my $arg (@$args) {
		push(@options, "-o");
		my $optstr = $arg->{name} . "=" . $arg->{default};
		push(@options, $optstr);
	    }
	    @{$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{options}} = @options;
	}
	# Construct an entry line for tree view in main window of
	# printerdrake
	make_menuentry($printer, $QUEUES[$i]{queuedata}{queue});
    }
}

sub make_menuentry {
    my ($printer, $queue) = @_;
    my $spooler = $spoolers{$printer->{SPOOLER}}{short_name};
    my $connect = $printer->{configured}{$queue}{queuedata}{connect};
    my $localremote = N("Configured on this machine");
    my $make = $printer->{configured}{$queue}{queuedata}{make};
    my $model = $printer->{configured}{$queue}{queuedata}{model};
    my $connection;
    if ($connect =~ m!^(file|parallel):/dev/lp(\d+)$!) {
	my $number = $2;
	$connection = N(" on parallel port #%s", $number);
    } elsif ($connect =~ m!^(file|usb):/dev/usb/lp(\d+)$!) {
	my $number = $2;
	$connection = N(", USB printer #%s", $number);
    } elsif ($connect =~ m!^usb://!) {
	$connection = N(", USB printer");
    } elsif ($connect =~ m!^hp:/(.+?)$!) {
	my $hplipdevice = $1;
	if ($hplipdevice =~ m!^par/!) {
	    $connection = N(", HP printer on a parallel port");
	} elsif ($hplipdevice =~ m!^usb/!) {
	    $connection = N(", HP printer on USB");
	} elsif ($hplipdevice =~ m!^net/!) {
	    $connection = N(", HP printer on HP JetDirect");
	} else {
	    $connection = N(", HP printer");
	}
    } elsif ($connect =~ m!^ptal://?(.+?)$!) {
	my $ptaldevice = $1;
	if ($ptaldevice =~ /^mlc:par:(\d+)$/) {
	    my $number = $1;
	    $connection = N(", multi-function device on parallel port #%s",
			    $number);
	} elsif ($ptaldevice =~ /^mlc:par:/) {
	    $connection = N(", multi-function device on a parallel port");
	} elsif ($ptaldevice =~ /^mlc:usb:/) {
	    $connection = N(", multi-function device on USB");
	} elsif ($ptaldevice =~ /^hpjd:/) {
	    $connection = N(", multi-function device on HP JetDirect");
	} else {
	    $connection = N(", multi-function device");
	}
    } elsif ($connect =~ m!^file:(.+)$!) {
        my $file = $1;
	$connection = N(", printing to %s", $file);
    } elsif ($connect =~ m!^lpd://([^/]+)/([^/]+)/?$!) {
        my ($server, $printer) = ($1, $2);
	$connection = N(" on LPD server \"%s\", printer \"%s\"", $server, $printer);
    } elsif ($connect =~ m!^socket://([^/:]+):([^/:]+)/?$!) {
        my ($host, $port) = ($1, $2);
	$connection = N(", TCP/IP host \"%s\", port %s", $host, $port);
    } elsif ($connect =~ m!^smb://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*\@([^/\@]+)/([^/\@]+)/?$!) {
        my ($server, $share) = ($1, $2);
	$connection = N(" on SMB/Windows server \"%s\", share \"%s\"", $server, $share);
    } elsif ($connect =~ m!^ncp://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*\@([^/\@]+)/([^/\@]+)/?$!) {
        my ($server, $printer) = ($1, $2);
	$connection = N(" on Novell server \"%s\", printer \"%s\"", $server, $printer);
    } elsif ($connect =~ m!^postpipe:(.+)$!) {
        my $command = $1;
	$connection = N(", using command %s", $command);
    } else {
	$connection = ($printer->{expert} ? ", URI: $connect" : "");
    }
    my $sep = "!";
    $printer->{configured}{$queue}{queuedata}{menuentry} = 
	($printer->{expert} ? "$spooler$sep" : "") .
	"$localremote$sep$queue: $make $model$connection";
}

sub connectionstr {
    my ($connect) = @_;
    my $connection;
    if ($connect =~ m!^(file|parallel):/dev/lp(\d+)$!) {
	my $number = $2;
	$connection = N("Parallel port #%s", $number);
    } elsif ($connect =~ m!^(file|usb):/dev/usb/lp(\d+)$!) {
	my $number = $2;
	$connection = N("USB printer #%s", $number);
    } elsif ($connect =~ m!^usb://!) {
	$connection = N("USB printer");
    } elsif ($connect =~ m!^hp:/(.+?)$!) {
	my $hplipdevice = $1;
	if ($hplipdevice =~ m!^par/!) {
	    $connection = N("HP printer on a parallel port");
	} elsif ($hplipdevice =~ m!^usb/!) {
	    $connection = N("HP printer on USB");
	} elsif ($hplipdevice =~ m!^net/!) {
	    $connection = N("HP printer on HP JetDirect");
	} else {
	    $connection = N("HP printer");
	}
    } elsif ($connect =~ m!^ptal://?(.+?)$!) {
	my $ptaldevice = $1;
	if ($ptaldevice =~ /^mlc:par:(\d+)$/) {
	    my $number = $1;
	    $connection = N("Multi-function device on parallel port #%s",
			    $number);
	} elsif ($ptaldevice =~ /^mlc:par:/) {
	    $connection = N("Multi-function device on a parallel port");
	} elsif ($ptaldevice =~ /^mlc:usb:/) {
	    $connection = N("Multi-function device on USB");
	} elsif ($ptaldevice =~ /^hpjd:/) {
	    $connection = N("Multi-function device on HP JetDirect");
	} else {
	    $connection = N("Multi-function device");
	}
    } elsif ($connect =~ m!^file:(.+)$!) {
        my $file = $1;
	$connection = N("Prints into %s", $file);
    } elsif ($connect =~ m!^lpd://([^/]+)/([^/]+)/?$!) {
        my ($server, $port) = ($1, $2);
	$connection = N("LPD server \"%s\", printer \"%s\"", $server, $port);
    } elsif ($connect =~ m!^socket://([^/:]+):([^/:]+)/?$!) {
        my ($host, $port) = ($1, $2);
        $connection = N("TCP/IP host \"%s\", port %s", $host, $port);
    } elsif ($connect =~ m!^smb://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*\@([^/\@]+)/([^/\@]+)/?$!) {
        my ($server, $share) = ($1, $2);
	$connection = N("SMB/Windows server \"%s\", share \"%s\"", $server, $share);
    } elsif ($connect =~ m!^ncp://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*\@([^/\@]+)/([^/\@]+)/?$!) {
        my ($server, $share) = ($1, $2);
	$connection = N("Novell server \"%s\", printer \"%s\"", $server, $share);
    } elsif ($connect =~ m!^postpipe:(.+)$!) {
        my $command = $1;
	$connection = N("Uses command %s", $command);
    } else {
	$connection = N("URI: %s", $connect);
    }
    return $connection;
}

sub read_printer_db {

    my ($printer, $spooler) = @_;

    # No local queues available in daemon-less CUPS mode
    return 1 if $spooler eq "rcups";

    my $DBPATH; #- do not have to do close ... and do not modify globals at least
    # Generate the Foomatic printer/driver overview, read it from the
    # appropriate file when it is already generated
    open($DBPATH, ($::testing ? $::prefix : "chroot $::prefix/ ") . #-#
	"foomatic-configure -O -q |") or
	die "Could not run foomatic-configure";

    %linkedppds = ();
    my $entry = {};
    @{$entry->{drivers}} = (); 
    my $inentry = 0;
    my $indrivers = 0;
    my $inppds = 0;
    my $inppd = 0;
    my $inautodetect = 0;
    my $autodetecttype = "";
    my $ppds = {};
    my $ppddriver = "";
    my $ppdfile = "";
    local $_;
    while (<$DBPATH>) {
	chomp;
	if ($inentry) {
	    # We are inside a printer entry
	    if ($indrivers) {
		# We are inside the drivers block of a printers entry
		if (m!^\s*</drivers>\s*$!) {
		    # End of drivers block
		    $indrivers = 0;
		} elsif (m!^\s*<driver>(.+)</driver>\s*$!) {
		    push @{$entry->{drivers}}, $1;
		}
	    } elsif ($inppds) {
		# We are inside the ppds block of a printers entry
		if ($inppd) {
		    # We are inside a PPD entry in the ppds block
		    if (m!^\s*</ppd>\s*$!) {
			# End of ppds block
			$inppd = 0;
			if ($ppddriver && $ppdfile) {
			    $ppds->{$ppddriver} = $ppdfile;
			}
			$ppddriver = "";
			$ppdfile = "";
		    } elsif (m!^\s*<driver>(.+)</driver>\s*$!) {
			$ppddriver = $1;
		    } elsif (m!^\s*<ppdfile>(.+)</ppdfile>\s*$!) {
			$ppdfile = $1;
		    }
		} else {
		    if (m!^\s*</ppds>\s*$!) {
			# End of ppds block
			$inppds = 0;
		    } elsif (m!^\s*<ppd>\s*$!) {
			$inppd = 1;
		    }
		}
	    } elsif ($inautodetect) {
		# We are inside the autodetect block of a printers entry
		# All entries inside this block will be ignored
		if ($autodetecttype) {
		    if (m!^.*</$autodetecttype>\s*$!) {
			# End of general, parallel, USB, or SNMP section
			$autodetecttype = "";
		    } elsif (m!^\s*<manufacturer>\s*([^<>]+)\s*</manufacturer>\s*$!) {
			# Manufacturer
			$entry->{devidmake} = $1;
		    } elsif (m!^\s*<model>\s*([^<>]+)\s*</model>\s*$!) {
			# Model
			$entry->{devidmodel} = $1;
		    } elsif (m!^\s*<description>\s*([^<>]+)\s*</description>\s*$!) {
			# Description
			$entry->{deviddesc} = $1;
		    } elsif (m!^\s*<commandset>\s*([^<>]+)\s*</commandset>\s*$!) {
			# Command set
			$entry->{devidcmdset} = $1;
		    } elsif (m!^\s*<ieee1284>\s*([^<>]+)\s*</ieee1284>\s*$!) {
			# Full ID string
			my $idstr = $1;
			$idstr =~ m!(MFG|MANUFACTURER):([^;]+);!i
			    and $entry->{devidmake} = $2;
			$idstr =~ m!(MDL|MODEL):([^;]+);!i
			    and $entry->{devidmodel} = $2;
			$idstr =~ m!(DES|DESCRIPTION):([^;]+);!i
			    and $entry->{deviddesc} = $2;
			$idstr =~ m!(CMD|COMMAND\s*SET):([^;]+);!i
			    and $entry->{devidcmdset} = $2;
		    }
		} else {
		    if (m!^.*</autodetect>\s*$!) {
			# End of autodetect block
			$inautodetect = 0;
		    } elsif (m!^\s*<(general|parallel|usb|snmp)>\s*$!) {
			# Beginning of parallel, USB, or SNMP section
			$autodetecttype = $1;
		    }
		}
	    } else {
		if (m!^\s*</printer>\s*$!) {
		    # entry completed
		    $inentry = 0;
		    # Expert mode:
		    # Make one database entry per driver with the entry name
		    # manufacturer|model|driver
		    if ($printer->{expert}) {
			foreach my $driver (@{$entry->{drivers}}) {
			    my $driverstr;
			    if ($driver eq "Postscript") {
				$driverstr = "PostScript";
			    } else {
				$driverstr = "GhostScript + $driver";
			    }
			    if ($driver eq $entry->{defaultdriver}) {
				$driverstr .= " $precstr";
			    }
			    $entry->{ENTRY} = "$entry->{make}|$entry->{model}|$driverstr";
			    $entry->{ENTRY} =~ s/^CITOH/C.ITOH/i;
			    $entry->{ENTRY} =~ 
				s/^KYOCERA[\s\-]*MITA/KYOCERA/i;
			    $entry->{driver} = $driver;
			    if (defined($ppds->{$driver})) {
				$entry->{ppd} = $ppds->{$driver};
				$ppds->{$driver} =~ m!([^/]+)$!;
				push(@{$linkedppds{$1}}, $entry->{ENTRY});
			    } else {
				undef $entry->{ppd};
			    }
			    # Duplicate contents of $entry because it is multiply entered to the database
			    map { $thedb{$entry->{ENTRY}}{$_} = $entry->{$_} } keys %$entry;
			}
		    } else {
			# Recommended mode
			# Make one entry per printer, with the recommended
			# driver (manufacturerer|model)
			$entry->{ENTRY} = "$entry->{make}|$entry->{model}";
			$entry->{ENTRY} =~ s/^CITOH/C.ITOH/i;
			$entry->{ENTRY} =~ 
			    s/^KYOCERA[\s\-]*MITA/KYOCERA/i;
			if ($entry->{defaultdriver}) {
			    my $driver = $entry->{defaultdriver};
			    $entry->{driver} = $driver;
			    if (defined($ppds->{$driver})) {
				$entry->{ppd} = $ppds->{$driver};
				$ppds->{$driver} =~ m!([^/]+)$!;
				push(@{$linkedppds{$1}}, $entry->{ENTRY});
			    } else {
				undef $entry->{ppd};
			    }
			    map { $thedb{$entry->{ENTRY}}{$_} = $entry->{$_} } keys %$entry;
			}
		    }
		    $entry = {};
		    @{$entry->{drivers}} = (); 
		    $ppds = {};
		} elsif (m!^\s*<id>\s*([^\s<>]+)\s*</id>\s*$!) {
		    # Foomatic printer ID
		    $entry->{printer} = $1;
		} elsif (m!^\s*<make>(.+)</make>\s*$!) {
		    # Printer manufacturer
		    $entry->{make} = uc($1);
		} elsif (m!^\s*<model>(.+)</model>\s*$!) {
		    # Printer model
		    $entry->{model} = $1;
		} elsif (m!<driver>(.+)</driver>!) {
		    # Printer default driver
		    $entry->{defaultdriver} = $1;
		} elsif (m!^\s*<drivers>\s*$!) {
		    # Drivers block
		    $indrivers = 1;
		} elsif (m!^\s*<ppds>\s*$!) {
		    # PPDs block
		    $inppds = 1;
		} elsif (m!^\s*<autodetect>\s*$!) {
		    # Autodetect block
		    $inautodetect = 1;
		}
	    }
	} else {
	    if (m!^\s*<printer>\s*$!) {
		# new entry
		$inentry = 1;
	    }
	}
    }
    close $DBPATH;

    # Add raw queue
    $entry->{ENTRY} = N("Raw printer (No driver)");
    $entry->{driver} = "raw";
    $entry->{make} = "";
    $entry->{model} = N("Unknown model");
    $thedb{$entry->{ENTRY}}{$_} = $entry->{$_} foreach keys %$entry;

    #- Load CUPS driver database if CUPS is used as spooler
    if ($spooler && $spooler eq "cups") {
        poll_ppd_base($printer);
    }

    #my @entries_db_short     = sort keys %printer::thedb;
    #%descr_to_db          = map { $printer::thedb{$_}{DESCR}, $_ } @entries_db_short;
    #%descr_to_help        = map { $printer::thedb{$_}{DESCR}, $printer::thedb{$_}{ABOUT} } @entries_db_short;
    #@entry_db_description = keys %descr_to_db;
    #db_to_descr          = reverse %descr_to_db;

}

sub read_foomatic_options ($) {
    my ($printer) = @_;
    # Generate the option data for the chosen printer/driver combo
    my $COMBODATA;
    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -P -q -p $printer->{currentqueue}{printer}" .
	" -d $printer->{currentqueue}{driver}" . 
	($printer->{OLD_QUEUE} ?
	 " -s $printer->{SPOOLER} -n $printer->{OLD_QUEUE}" : "") .
	 ($printer->{SPECIAL_OPTIONS} ?
	  " $printer->{SPECIAL_OPTIONS}" : "") 
	 . " |") or
	 die "Could not run foomatic-configure";
    eval join('', (<$F>)); 
    close $F;
    # Return the arguments field
    return $COMBODATA->{args};
}

sub read_ppd_options ($) {
    my ($printer) = @_;
    # Generate the option data for a given PPD file
    my $COMBODATA;
    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -P -q" .
	 if_($printer->{currentqueue}{ppd} &&
	     ($printer->{currentqueue}{ppd} ne '1'),
	     " --ppd \'" . ($printer->{currentqueue}{ppd} !~ m!^/! ?
			    "/usr/share/cups/model/" : "") .
			   $printer->{currentqueue}{ppd} . "\'") .
	($printer->{OLD_QUEUE} ?
	 " -s $printer->{SPOOLER} -n $printer->{OLD_QUEUE}" : "") .
	 ($printer->{SPECIAL_OPTIONS} ?
	  " $printer->{SPECIAL_OPTIONS}" : "") 
		    . " |") or
	    die "Could not run foomatic-configure";
    eval join('', (<$F>));
    close $F;
    # Return the arguments field
    return $COMBODATA->{args};
}

sub set_cups_special_options {
    my ($printer, $queue) = @_;
    # Set some special CUPS options
    my @lpoptions = cat_("$::prefix/etc/cups/lpoptions");
    # If nothing is already configured, set text file borders of half
    # an inch so nothing of the text gets cut off by unprintable
    # borders. Do this only when the driver is not Gutenprint, as with
    # Gutenprint this will break PostScript printing
    if ((($queue eq $printer->{currentqueue}{$queue}) &&
	 (($printer->{currentqueue}{driver} =~ /guten.*print/i) ||
	  ($printer->{currentqueue}{ppd} =~ /guten.*print/i))) ||
	((defined($printer->{configured}{$queue})) &&
	 (($printer->{configured}{$queue}{queuedata}{driver} =~
	   /guten.*print/i) ||
	  ($printer->{configured}{$queue}{queuedata}{ppd} =~
	   /guten.*print/i))) ||
	(($printer->{SPOOLER} eq "cups") &&
	 (-r "$::prefix/etc/cups/ppd/$queue.ppd") &&
	 (`grep -ic gutenprint $::prefix/etc/cups/ppd/$queue.ppd` > 2))) {
	# Remove page margin settings
	foreach (@lpoptions) {
	    s/\s*page-(top|bottom|left|right)=\S+//g if /$queue/;
	}
	output("$::prefix/etc/cups/lpoptions", @lpoptions);
    } else {
	if (!any { /$queue.*\spage-(top|bottom|left|right)=/ } @lpoptions) {
	    run_program::rooted($::prefix, "lpoptions",
				"-p", $queue,
				"-o", "page-top=36", "-o", "page-bottom=36",
				"-o", "page-left=36", "-o page-right=36");
	}
    }
    # Let images fill the whole page by default and let text be word-wrapped
    # and printed in a slightly smaller font
    if (!any { /$queue.*\s(scaling|natural-scaling|ppi)=/ } @lpoptions) {
	run_program::rooted($::prefix, "lpoptions",
			    "-p", $queue,
			    "-o", "scaling=100");
    }
    if (!any { /$queue.*\s(cpi|lpi)=/ } @lpoptions) {
	run_program::rooted($::prefix, "lpoptions",
			    "-p", $queue,
			    "-o", "cpi=12", "-o", "lpi=7", "-o", "wrap");
    }
    return 1;
}

my %sysconfig = getVarsFromSh("$::prefix/etc/sysconfig/printing");

sub set_cups_autoconf {
    my ($autoconf) = @_;
    $sysconfig{CUPS_CONFIG} = $autoconf ? "automatic" : "manual";
    setVarsInSh("$::prefix/etc/sysconfig/printing", \%sysconfig);
    # Restart CUPS
    printer::services::restart("cups") if $autoconf;
    return 1;
}

sub get_cups_autoconf() { $sysconfig{CUPS_CONFIG} ne 'manual' ? 1 : 0 }

sub set_usermode {
    my ($usermode) = @_;
    $sysconfig{USER_MODE} = $usermode ? "expert" : "recommended";
    setVarsInSh("$::prefix/etc/sysconfig/printing", \%sysconfig) if !$::testing;
    return $usermode;
}

sub get_usermode() { $sysconfig{USER_MODE} eq 'expert' ? 1 : 0 }

sub set_auto_admin {
    my ($printer) = @_;
    $sysconfig{ENABLE_QUEUES_ON_PRINTER_CONNECTED} = 
	$printer->{enablequeuesonnewprinter} ? "yes" : "no";
    $sysconfig{AUTO_SETUP_QUEUES_ON_PRINTER_CONNECTED} = 
	$printer->{autoqueuesetuponnewprinter} ? "yes" : "no";
    $sysconfig{ENABLE_QUEUES_ON_SPOOLER_START} = 
	$printer->{enablequeuesonspoolerstart} ? "yes" : "no";
    $sysconfig{AUTO_SETUP_QUEUES_ON_PRINTERDRAKE_START} = 
	$printer->{autoqueuesetuponstart} ? "yes" : "no";
    $sysconfig{AUTO_SETUP_QUEUES_MODE} = 
	$printer->{autoqueuesetupgui} ? "waitforgui" : "nogui";
    setVarsInSh("$::prefix/etc/sysconfig/printing", \%sysconfig);
    return 1;
}

sub get_auto_admin {
    my ($printer) = @_;
    $printer->{enablequeuesonnewprinter} = 
	(!defined($sysconfig{ENABLE_QUEUES_ON_PRINTER_CONNECTED}) ||
	 ($sysconfig{ENABLE_QUEUES_ON_PRINTER_CONNECTED} =~ /no/i) ?
	 0 : 1);
    $printer->{autoqueuesetuponnewprinter} = 
	(!defined($sysconfig{AUTO_SETUP_QUEUES_ON_PRINTER_CONNECTED}) ||
	 ($sysconfig{AUTO_SETUP_QUEUES_ON_PRINTER_CONNECTED} =~ /yes/i) ?
	 1 : 0);
    $printer->{enablequeuesonspoolerstart} = 
	(!defined($sysconfig{ENABLE_QUEUES_ON_SPOOLER_START}) ||
	 ($sysconfig{ENABLE_QUEUES_ON_SPOOLER_START} =~ /no/i) ?
	 0 : 1);
    $printer->{autoqueuesetuponstart} = 
	(!defined($sysconfig{AUTO_SETUP_QUEUES_ON_PRINTERDRAKE_START}) ||
	 ($sysconfig{AUTO_SETUP_QUEUES_ON_PRINTERDRAKE_START} =~ /yes/i) ?
	 1 : 0);
    $printer->{autoqueuesetupgui} = 
	(!defined($sysconfig{AUTO_SETUP_QUEUES_MODE}) ||
	 ($sysconfig{AUTO_SETUP_QUEUES_MODE} =~ /waitforgui/i) ?
	 1 : 0);
}

sub set_jap_textmode {
    my $textmode = ($_[0] ? 'cjk' : '');
    # Do not write mime.convs if the file does not exist, as then
    # CUPS is not installed and the created mime.convs will be broken.
    # When installing CUPS later it will not work.
    return 1 if (! -r "$::prefix/etc/cups/mime.convs");
    substInFile {
        s!^(\s*text/plain\s+\S+\s+\d+\s+)\S+(\s*$)!$1${textmode}texttops$2!;
    } "$::prefix/etc/cups/mime.convs";
    return 1;
}

sub get_jap_textmode() {
    my @mimeconvs = cat_("$::prefix/etc/cups/mime.convs");
    (m!^\s*text/plain\s+\S+\s+\d+\s+(\S+)\s*$!m and
     $1 eq 'cjktexttops' and return 1) foreach @mimeconvs;
    return 0;
}

#----------------------------------------------------------------------
# Handling of /etc/cups/cupsd.conf

sub read_cupsd_conf() {
    # If /etc/cups/cupsd.conf does not exist a default cupsd.conf will be 
    # put out to avoid writing of a broken cupsd.conf file when we write 
    # it back later.
    my @cupsd_conf = cat_("$::prefix/etc/cups/cupsd.conf");
    if (!@cupsd_conf) {
	@cupsd_conf = map { /\n$/s or "$_\n" } split('\n',
'LogLevel info
TempDir /var/spool/cups/tmp
Port 631
Browsing On
BrowseAddress @LOCAL
BrowseDeny All
BrowseAllow 127.0.0.1
BrowseAllow @LOCAL
BrowseOrder deny,allow
<Location />
Order Deny,Allow
Deny From All
Allow From 127.0.0.1
Allow From @LOCAL
</Location>
<Location /admin>
AuthType Basic
AuthClass System
Order Deny,Allow
Deny From All
Allow From 127.0.0.1
</Location>
');
    }
    return @cupsd_conf;
}

sub write_cupsd_conf {
    my (@cupsd_conf) = @_;
    # Do not write cupsd.conf if the file does not exist, as then
    # CUPS is not installed and the created cupsd.conf will be broken.
    # When installing CUPS later it will not start.
    return 1 if (! -r "$::prefix/etc/cups/cupsd.conf");
    output("$::prefix/etc/cups/cupsd.conf", @cupsd_conf);
}

sub read_location {

    # Return the lines inside the [path] location block
    #
    #   <Location [path]>
    #   ...
    #   </Location>

    my ($cupsd_conf_ptr, $path) = @_;

    my @result;
    if (any { m!^\s*<Location\s+$path\s*>! } @$cupsd_conf_ptr) {
	my $location_start = -1;
	my $location_end = -1;
	# Go through all the lines, bail out when start and end line found
	for (my $i = 0; 
	     $i <= $#{$cupsd_conf_ptr} && $location_end == -1;
	     $i++) {
	    if ($cupsd_conf_ptr->[$i] =~ m!^\s*<\s*Location\s+$path\s*>!) {
		# Start line of block
		$location_start = $i;
	    } elsif ($cupsd_conf_ptr->[$i] =~ 
		      m!^\s*<\s*/Location\s*>! &&
		     $location_start != -1) {
		# End line of block
		$location_end = $i;
		last;
	    } elsif ($location_start >= 0 && $location_end < 0) {
		# Inside the location block
		push(@result, $cupsd_conf_ptr->[$i]);
	    }
	}
    } else {
	# If there is no root location block, set the result array to
	# "undef"
	@result = undef;
    }
    return @result;
}

sub rip_location {

    # Cut out the [path]  location block
    #
    #   <Location [path]>
    #   ...
    #   </Location>
    #
    # so that it can be treated seperately without affecting the
    # rest of the file

    my ($cupsd_conf_ptr, $path) = @_;

    my @location;
    my $location_start = -1;
    my $location_end = -1;
    if (any { m!^\s*<Location\s+$path\s*>! } @$cupsd_conf_ptr) {
	# Go through all the lines, bail out when start and end line found
	for (my $i = 0; 
	     $i <= $#{$cupsd_conf_ptr} && $location_end == -1;
	     $i++) {
	    if ($cupsd_conf_ptr->[$i] =~ m!^\s*<\s*Location\s+$path\s*>!) {
		# Start line of block
		$location_start = $i;
	    } elsif ($cupsd_conf_ptr->[$i] =~ 
		      m!^\s*<\s*/Location\s*>! &&
		     $location_start != -1) {
		# End line of block
		$location_end = $i;
		last;
	    }
	}
	# Rip out the block and store it seperately
	@location = 
	    splice(@$cupsd_conf_ptr, $location_start,
		   $location_end - $location_start + 1);
    } else {
	# If there is no location block, create one
	$location_start = $#{$cupsd_conf_ptr} + 1;
	@location = ("<Location $path>\n", "</Location>\n");
    }

    return $location_start, @location;
}

sub insert_location {

    # Re-insert a location block ripped with "rip_location"

    my ($cupsd_conf_ptr, $location_start, @location) = @_;

    splice(@$cupsd_conf_ptr, $location_start,0,@location);
}

sub add_to_location {

    # Add a directive to a given location (only if it is not already there)

    my ($cupsd_conf_ptr, $path, $directive) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = handle_configs::insert_directive(\@location, $directive);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub remove_from_location {

    # Remove a directive from a given location

    my ($cupsd_conf_ptr, $path, $directive) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = handle_configs::remove_directive(\@location, $directive);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub replace_in_location {

    # Replace a directive in a given location

    my ($cupsd_conf_ptr, $path, $olddirective, $newdirective) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = handle_configs::replace_directive(\@location, 
						    $olddirective, 
						    $newdirective);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub add_allowed_host {

    # Add a host or network which should get access to the local printer(s)
    my ($cupsd_conf_ptr, $host) = @_;
    
    return (handle_configs::insert_directive($cupsd_conf_ptr, 
					     "BrowseAddress $host") and
	    add_to_location($cupsd_conf_ptr, "/", "Allow From $host"));
}

sub remove_allowed_host {

    # Remove a host or network which should get access to the local 
    # printer(s)
    my ($cupsd_conf_ptr, $host) = @_;
    
    return (handle_configs::remove_directive($cupsd_conf_ptr, "BrowseAddress $host") and
	    remove_from_location($cupsd_conf_ptr, "/",
				 "Allow From $host"));
}

sub replace_allowed_host {

    # Remove a host or network which should get access to the local 
    # printer(s)
    my ($cupsd_conf_ptr, $oldhost, $newhost) = @_;
    
    return (handle_configs::replace_directive($cupsd_conf_ptr,
					      "BrowseAddress $oldhost",
					      "BrowseAddress $newhost") and
	    replace_in_location($cupsd_conf_ptr, "/", "Allow From $newhost",
				"Allow From $newhost"));
}

sub broadcastaddress {
    
    # Determines the broadcast address (for "BrowseAddress" line) for
    # a given network IP

    my ($address) = @_;

    if ($address =~ /^\d+\.\*$/) {
	$address =~ s/\*$/255.255.255/;
    } elsif ($address =~ /^\d+\.\d+\.\*$/) {
	$address =~ s/\*$/255.255/;
    } elsif ($address =~ /^\d+\.\d+\.\d+\.\*$/) {
	$address =~ s/\*$/255/;
    } elsif ($address =~ m!^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$!) {
	my $numadr = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
	my $mask = ((1 << $5) - 1) << (32 - $5);
	my $broadcast = $numadr | (~$mask);
	$address =
	    (($broadcast & (255 << 24)) >> 24) . '.' .
	    (($broadcast & (255 << 16)) >> 16) . '.' .
	    (($broadcast & (255 << 8)) >> 8) . '.' .
	    ($broadcast & 255);
    } elsif ($address =~
	     m!^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)\.(\d+)\.(\d+)\.(\d+)$!) {
	my $numadr = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
	my $mask = ($5 << 24) + ($6 << 16) + ($7 << 8) + $8;
	my $broadcast = $numadr | (~$mask);
	$address =
	    (($broadcast & (255 << 24)) >> 24) . '.' .
	    (($broadcast & (255 << 16)) >> 16) . '.' .
	    (($broadcast & (255 << 8)) >> 8) . '.' .
	    ($broadcast & 255);
    }
    
    return $address;
}

sub networkaddress {
    
    # Guesses a network address for a given broadcast address
    
    my ($address) = @_;

    if ($address =~ /\.255$/) {
	while ($address =~ s/\.255$//) {}
	$address .= ".*";
    }
 
    return $address;
}

sub localprintersshared {

    # Do we broadcast our local printers

    my ($printer) = @_;

    return ($printer->{cupsconfig}{keys}{Browsing} !~ /off/i &&
	    $printer->{cupsconfig}{keys}{BrowseInterval} != 0 &&
	    $#{$printer->{cupsconfig}{keys}{BrowseAddress}} >= 0);
}

sub remotebroadcastsaccepted {
    
    # Do we accept broadcasts from remote CUPS servers?

    my ($printer) = @_;

    # Is browsing not turned on at all?
    if ($printer->{cupsconfig}{keys}{Browsing} =~ /off/i) {
	return 0;
    }

    # No "BrowseDeny" lines at all
    if ($#{$printer->{cupsconfig}{keys}{BrowseDeny}} < 0) {
	return 1;
    }

    my $havedenyall = 
	join('', @{$printer->{cupsconfig}{keys}{BrowseDeny}}) =~
	 /All/im;
    my $havedenylocal = 
	join('', @{$printer->{cupsconfig}{keys}{BrowseDeny}}) =~
	 /\@LOCAL/im;
    my $orderallowdeny =
	$printer->{cupsconfig}{keys}{BrowseOrder} =~
	 /allow\s*,\s*deny/i;
    my $haveallowremote = 0;
    foreach my $allowline (@{$printer->{cupsconfig}{keys}{BrowseAllow}}) {
	next if 
	    $allowline =~ /^\s*(localhost|0*127\.0+\.0+\.0*1|none)\s*$/i;
	$haveallowremote = 1;
    }

    # A line denying all (or at least the all LANs) together with the order
    # "allow,deny" or without "BrowseAllow" lines (which allow the
    # broadcasts of at least one remote resource).
    if (($havedenyall || $havedenylocal) &&
	($orderallowdeny || !$haveallowremote)) {
	return 0;
    }

    return 1;
}

sub clientnetworks {

    # Determine the client networks to which the printers will be
    # shared If the configuration is supported by our simplified
    # interface ("Deny From All", "Order Deny,Allow", "Allow From ..."
    # lines in "<location /> ... </location>", a "BrowseAddress ..."
    # line for each "Allow From ..." line), return the list of allowed
    # client networks ("Allow"/"BrowseAddress" lines), if not, return
    # the list of all items which are at least one of the
    # "BrowseAddresse"s or one of the "Allow From" addresses together
    # with a flag that the setup is not supported.

    my ($printer) = @_;

    # Check for a "Deny From All" line
    my $havedenyfromall =
	(join('', @{$printer->{cupsconfig}{root}{DenyFrom}}) =~
	 /All/im ? 1 : 0);

    # Check for "Deny From XXX" with XXX != All
    my $havedenyfromnotall =
	($#{$printer->{cupsconfig}{root}{DenyFrom}} - $havedenyfromall < 0 ?
	 0 : 1);
    
    # Check for a "BrowseDeny All" line
    my $havebrowsedenyall =
	(join('', @{$printer->{cupsconfig}{keys}{BrowseDeny}}) =~
	 /All/im ? 1 : 0);

    # Check for "BrowseDeny XXX" with XXX != All
    my $havebrowsedenynotall =
	($#{$printer->{cupsconfig}{keys}{BrowseDeny}} - 
	 $havebrowsedenyall < 0 ? 0 : 1);
    
    my @sharehosts;
    my $haveallowfromlocalhost = 0;
    my $haveallowedhostwithoutbrowseaddress = 0;
    my $haveallowedhostwithoutbrowseallow = 0;
    # Go through all "Allow From" lines
    foreach my $line (@{$printer->{cupsconfig}{root}{AllowFrom}}) {
	if ($line =~ /^\s*(localhost|0*127\.0+\.0+\.0*1)\s*$/i) {
	    # Line pointing to localhost
	    $haveallowfromlocalhost = 1;
	} elsif ($line =~ /^\s*(none)\s*$/i) {
	    # Skip "Allow From None" lines
	} elsif (!member($line, @sharehosts)) {
	    # Line pointing to remote server
	    push(@sharehosts, $line);
	    if (!member(broadcastaddress($line),
			@{$printer->{cupsconfig}{keys}{BrowseAddress}})) {
		$haveallowedhostwithoutbrowseaddress = 1;
	    }
	    if (!member($line,
			@{$printer->{cupsconfig}{keys}{BrowseAllow}})) {
		$haveallowedhostwithoutbrowseallow = 1;
	    }
	}
    }
    my $havebrowseaddresswithoutallowedhost = 0;
    # Go through all "BrowseAdress" lines
    foreach my $line (@{$printer->{cupsconfig}{keys}{BrowseAddress}}) {
	if ($line =~ /^\s*(localhost|0*127\.0+\.0+\.0*1)\s*$/i) {
	    # Skip lines pointing to localhost
	} elsif ($line =~ /^\s*(none)\s*$/i) {
	    # Skip "Allow From None" lines
	} elsif (!member($line, map { broadcastaddress($_) } @sharehosts)) {
	    # Line pointing to remote server
	    push(@sharehosts, networkaddress($line));
	    if ($printer->{cupsconfig}{localprintersshared}) {
		$havebrowseaddresswithoutallowedhost = 1;
	    }
	}
    }
    my $havebrowseallowwithoutallowedhost = 0;
    # Go through all "BrowseAllow" lines
    foreach my $line (@{$printer->{cupsconfig}{keys}{BrowseAllow}}) {
	if ($line =~ /^\s*(localhost|0*127\.0+\.0+\.0*1)\s*$/i) {
	    # Skip lines pointing to localhost
	} elsif ($line =~ /^\s*(none)\s*$/i) {
	    # Skip "BrowseAllow None" lines
	} elsif (!member($line, @sharehosts)) {
	    # Line pointing to remote server
	    push(@sharehosts, $line);
	    #$havebrowseallowwithoutallowedhost = 1;
	}
    }

    my $configunsupported = (!$havedenyfromall || $havedenyfromnotall ||
			     !$havebrowsedenyall || $havebrowsedenynotall ||
			     !$haveallowfromlocalhost ||
			     $haveallowedhostwithoutbrowseaddress ||
			     $havebrowseaddresswithoutallowedhost ||
			     $haveallowedhostwithoutbrowseallow ||
			     $havebrowseallowwithoutallowedhost);

    return $configunsupported, @sharehosts;
}

sub makesharehostlist {

    # Human-readable strings for hosts onto which the local printers
    # are shared

    my ($printer) = @_;

    my @sharehostlist; 
    my %sharehosthash;
    foreach my $host (@{$printer->{cupsconfig}{clientnetworks}}) {
	if ($host =~ /\@LOCAL/i) {
	    $sharehosthash{$host} = N("Local network(s)");
	} elsif ($host =~ /\@IF\((.*)\)/i) {
	    $sharehosthash{$host} = N("Interface \"%s\"", $1);
	} elsif ($host =~ m!(/|^\*|\*$|^\.)!) {
	    $sharehosthash{$host} = N("Network %s", $host);
	} else {
	    $sharehosthash{$host} = N("Host %s", $host);
	}
	push(@sharehostlist, $sharehosthash{$host});
    }
    my %sharehosthash_inv = reverse %sharehosthash;

    return { list => \@sharehostlist, 
	     hash => \%sharehosthash, 
	     invhash => \%sharehosthash_inv };
}

sub makebrowsepolllist {

    # Human-readable strings for hosts from which the print queues are
    # polled

    my ($printer) = @_;

    my @browsepolllist; 
    my %browsepollhash;
    foreach my $host (@{$printer->{cupsconfig}{BrowsePoll}}) {
	my ($ip, $port);
	if ($host =~ /^([^:]+):([^:]+)$/) {
	    $ip = $1;
	    $port = $2;
	} else {
	    $ip = $host;
	    $port = '631';
	}
	$browsepollhash{$host} = N("%s (Port %s)", $ip, $port);
	push(@browsepolllist, $browsepollhash{$host});
    }
    my %browsepollhash_inv = reverse %browsepollhash;

    return { list => \@browsepolllist, 
	     hash => \%browsepollhash, 
	     invhash => \%browsepollhash_inv };
}

sub is_network_ip {

    # Determine whwther the given string is a valid network IP

    my ($address) = @_;

    $address =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ||
	$address =~ /^(\d+\.){1,3}\*$/ ||
	$address =~ m!^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$! ||
	$address =~
	 m!^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)\.(\d+)\.(\d+)\.(\d+)$!;

}

sub read_cups_config {
    
    # Read the information relevant to the printer sharing dialog from
    # the CUPS configuration

    my ($printer) = @_;

    # From /etc/cups/cupsd.conf

    # Keyword "Browsing" 
    $printer->{cupsconfig}{keys}{Browsing} =
	handle_configs::read_unique_directive($printer->{cupsconfig}{cupsd_conf},
					      'Browsing', 'On');

    # Keyword "BrowseInterval"
    $printer->{cupsconfig}{keys}{BrowseInterval} =
	handle_configs::read_unique_directive($printer->{cupsconfig}{cupsd_conf},
					      'BrowseInterval', '30');

    # Keyword "BrowseAddress" 
    @{$printer->{cupsconfig}{keys}{BrowseAddress}} =
	handle_configs::read_directives($printer->{cupsconfig}{cupsd_conf},
					'BrowseAddress');

    # Keyword "BrowseAllow" 
    @{$printer->{cupsconfig}{keys}{BrowseAllow}} =
	handle_configs::read_directives($printer->{cupsconfig}{cupsd_conf},
					'BrowseAllow');

    # Keyword "BrowseDeny" 
    @{$printer->{cupsconfig}{keys}{BrowseDeny}} =
	handle_configs::read_directives($printer->{cupsconfig}{cupsd_conf},
					'BrowseDeny');

    # Keyword "BrowseOrder" 
    $printer->{cupsconfig}{keys}{BrowseOrder} =
	handle_configs::read_unique_directive($printer->{cupsconfig}{cupsd_conf},
					      'BrowseOrder', 'deny,allow');

    # Keyword "BrowsePoll" (needs "Browsing On")
    if ($printer->{cupsconfig}{keys}{Browsing} !~ /off/i) {
	@{$printer->{cupsconfig}{BrowsePoll}} =
	    handle_configs::read_directives($printer->{cupsconfig}{cupsd_conf},
					    'BrowsePoll');
    }

    # Root location
    @{$printer->{cupsconfig}{rootlocation}} =
	read_location($printer->{cupsconfig}{cupsd_conf}, '/');

    # Keyword "Allow from" 
    @{$printer->{cupsconfig}{root}{AllowFrom}} =
	handle_configs::read_directives($printer->{cupsconfig}{rootlocation},
					'Allow From');
    # Remove the IPs pointing to the local machine
    my @localips = printer::detect::getIPsOfLocalMachine();
    @{$printer->{cupsconfig}{root}{AllowFrom}} =
	grep {
	    !member($_, @localips);
	} @{$printer->{cupsconfig}{root}{AllowFrom}};

    # Keyword "Deny from" 
    @{$printer->{cupsconfig}{root}{DenyFrom}} =
	handle_configs::read_directives($printer->{cupsconfig}{rootlocation},
					'Deny From');

    # Keyword "Order" 
    $printer->{cupsconfig}{root}{Order} =
	handle_configs::read_unique_directive($printer->{cupsconfig}{rootlocation},
					      'Order', 'Deny,Allow');

    # Widget settings

    # Local printers available to other machines?
    $printer->{cupsconfig}{localprintersshared} = 
	localprintersshared($printer);

    # This machine is accepting printers shared by remote machines?
    $printer->{cupsconfig}{remotebroadcastsaccepted} =
	remotebroadcastsaccepted($printer);

    # To which machines are the local printers available?
    ($printer->{cupsconfig}{customsharingsetup},
     @{$printer->{cupsconfig}{clientnetworks}}) =
	 clientnetworks($printer);

}

sub write_cups_config {
    
    # Write the information edited via the printer sharing dialog into
    # the CUPS configuration

    my ($printer) = @_;

    # Local printers available to other machines?
    if ($printer->{cupsconfig}{localprintersshared}) {
	handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
				      'Browsing On');
	if ($printer->{cupsconfig}{keys}{BrowseInterval} == 0) {
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseInterval 30');
	}  
    } else {
	handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
				      'BrowseInterval 0');
    }

    # This machine is accepting printers shared by remote machines?
    if ($printer->{cupsconfig}{remotebroadcastsaccepted}) {
	handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
				      'Browsing On');
	if (!$printer->{cupsconfig}{customsharingsetup}) {
	    # If we broadcast our printers, let's accept the broadcasts
	    # from the machines to which we broadcast
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseDeny All');
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseOrder Deny,Allow');
	}
    } else {
	if ($printer->{cupsconfig}{localprintersshared} ||
	    $#{$printer->{cupsconfig}{BrowsePoll}} >= 0) {
	    # Deny all broadcasts, but leave all "BrowseAllow" lines
	    # untouched
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseDeny All');
	      handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					    'BrowseOrder Allow,Deny');
	} else {
	    # We also do not share printers, if we also do not
	    # "BrowsePoll", we turn browsing off to do not need to deal 
	    # with any addresses
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'Browsing Off');
	}
    }

    # To which machines are the local printers available?
    if (!$printer->{cupsconfig}{customsharingsetup}) {
	my @localips = printer::detect::getIPsOfLocalMachine();
	# root location block
	@{$printer->{cupsconfig}{rootlocation}} =
	    "<Location />\n" .
	    "Order Deny,Allow\n" .
	    "Deny From All\n" .
	    "Allow From 127.0.0.1\n" .
	    (@localips ?
	     "Allow From " .
	     join("\nAllow From ", @localips) .
	     "\n" : "") .
	    ($printer->{cupsconfig}{localprintersshared} &&
	     $#{$printer->{cupsconfig}{clientnetworks}} >= 0 ?
	     "Allow From " .
	     join("\nAllow From ", 
		  grep {
		      !member($_, @localips);
		  } @{$printer->{cupsconfig}{clientnetworks}}) .
	     "\n" : "") .
	    "</Location>\n";
	my ($location_start, @_location) = 
	    rip_location($printer->{cupsconfig}{cupsd_conf}, "/");
	insert_location($printer->{cupsconfig}{cupsd_conf}, $location_start,
			@{$printer->{cupsconfig}{rootlocation}});
	# "BrowseAddress" lines
	if ($#{$printer->{cupsconfig}{clientnetworks}} >= 0) {
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseAddress ' .
					  join("\nBrowseAddress ",
						map { broadcastaddress($_) }
						@{$printer->{cupsconfig}{clientnetworks}}));
	} else {
	    handle_configs::comment_directive($printer->{cupsconfig}{cupsd_conf},
					      'BrowseAddress');
	}
	# Set "BrowseAllow" lines
	if ($#{$printer->{cupsconfig}{clientnetworks}} >= 0) {
	    handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowseAllow ' .
					  join("\nBrowseAllow ", 
						@{$printer->{cupsconfig}{clientnetworks}}));
	} else {
	    handle_configs::comment_directive($printer->{cupsconfig}{cupsd_conf},
					      'BrowseAllow');
	}
    }

    # Set "BrowsePoll" lines
    if ($#{$printer->{cupsconfig}{BrowsePoll}} >= 0) {
	handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
				      'BrowsePoll ' .
				      join("\nBrowsePoll ", 
					    @{$printer->{cupsconfig}{BrowsePoll}}));
	# "Browsing" must be on for "BrowsePoll" to work
	handle_configs::set_directive($printer->{cupsconfig}{cupsd_conf},
				      'Browsing On');
    } else {
	handle_configs::comment_directive($printer->{cupsconfig}{cupsd_conf},
					  'BrowsePoll');
    }

}

sub clean_cups_config {
    
    # Clean $printer data structure from all settings not related to
    # the CUPS printer sharing dialog

    my ($printer) = @_;

    delete $printer->{cupsconfig}{keys};
    delete $printer->{cupsconfig}{root};
    delete $printer->{cupsconfig}{cupsd_conf};
    delete $printer->{cupsconfig}{rootlocation};
}

#----------------------------------------------------------------------
# Handling of /etc/cups/client.conf

sub read_client_conf() {
    return (0, undef) if (! -r "$::prefix/etc/cups/client.conf");
    my @client_conf = cat_("$::prefix/etc/cups/client.conf");
    my @servers = handle_configs::read_directives(\@client_conf, 
						  "ServerName");
    return (@servers > 0, 
	    $servers[0]); # If there is more than one entry in client.conf,
                          # the first one counts.
}

sub write_client_conf {
    my ($daemonless_cups, $remote_cups_server) = @_;
    # Create the directory for client.conf if needed
    (-d "$::prefix/etc/cups/") || mkdir("$::prefix/etc/cups/") || return 1;
    my (@client_conf) = cat_("$::prefix/etc/cups/client.conf");
    if ($daemonless_cups) {
	handle_configs::set_directive(\@client_conf, 
				      "ServerName $remote_cups_server");
    } else {
	handle_configs::comment_directive(\@client_conf, "ServerName");
    }
    output("$::prefix/etc/cups/client.conf", @client_conf);
}



#----------------------------------------------------------------------
sub read_printers_conf {
    my ($printer) = @_;
    my $current;

    #- read /etc/cups/printers.conf file.
    #- according to this code, we are now using the following keys for each queues.
    #-    DeviceURI > lpd://printer6/lp
    #-    Info      > Info Text
    #-    Location  > Location Text
    #-    State     > Idle|Stopped
    #-    Accepting > Yes|No
    open(my $PRINTERS, "$::prefix/etc/cups/printers.conf") or return;
    local $_;
    while (<$PRINTERS>) {
	chomp;
	/^\s*#/ and next;
	if (/^\s*<(?:DefaultPrinter|Printer)\s+([^>]*)>/) { $current = { mode => 'cups', QUEUE => $1, } }
	elsif (m!\s*</Printer>!) { $current->{QUEUE} && $current->{DeviceURI} or next; #- minimal check of synthax.
				   add2hash($printer->{configured}{$current->{QUEUE}} ||= {}, $current); $current = undef }
	elsif (/\s*(\S*)\s+(.*)/) { $current->{$1} = $2 }
    }
    close $PRINTERS;

    #- assume this printing system.
    $printer->{SPOOLER} ||= 'cups';
}

sub get_direct_uri() {
    #- get the local printer to access via a Device URI.
    my @direct_uri;
    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/sbin/lpinfo -v |");
    local $_;
    while (<$F>) {
	/^(direct|usb|serial)\s+(\S*)/ and push @direct_uri, $2;
    }
    close $F;
    @direct_uri;
}

sub checkppd {
    # Check whether the PPD file is valid
    my ($printer, $ppdfile) = @_;
    return 1 if $printer->{SPOOLER} ne "cups";
    return run_program::rooted($::prefix, "cupstestppd", "-q",
			       $ppdfile);
}

sub installppd {
    # Install the PPD file in /usr/share/cups/model/printerdrake/
    my ($printer, $ppdfile) = @_;
    return "" if !$ppdfile;
    # Install PPD file
    mkdir_p("$::prefix/usr/share/cups/model/printerdrake");
    # "cp_f()" is broken, it hangs infinitely
    # cp_f($ppdfile, "$::prefix/usr/share/cups/model/printerdrake");
    run_program::rooted($::prefix, "cp", "-f", $ppdfile,
			"$::prefix/usr/share/cups/model/printerdrake");
    $ppdfile =~ s!^(.*)(/[^/]+)$!/usr/share/cups/model/printerdrake$2!;
    chmod 0644, "$::prefix$ppdfile";
    # Restart CUPS to register new PPD file
    printer::services::restart("cups") if $printer->{SPOOLER} eq "cups";
    # Re-read printer database
    %thedb = ();
    read_printer_db($printer, $printer->{SPOOLER});
    # Return description string of the PPD file
    my $ppdentry = get_descr_from_ppdfile($printer, $ppdfile);
    return $ppdentry;
}

sub clean_manufacturer_name {
    my ($make) = @_;
    # Clean some manufacturer's names so that every manufacturer has only
    # one entry in the tree list
    $make =~ s/^CANON\W.*$/CANON/i;
    $make =~ s/^LEXMARK.*$/LEXMARK/i;
    $make =~ s/^HEWLETT?[\s\-]*PACKARD/HP/i;
    $make =~ s/^SEIKO[\s\-]*EPSON/EPSON/i;
    $make =~ s/^KYOCERA[\s\-]*MITA/KYOCERA/i;
    $make =~ s/^CITOH/C.ITOH/i;
    $make =~ s/^OKI(|[\s\-]*DATA)\s*$/OKIDATA/i;
    $make =~ s/^(SILENTWRITER2?|COLORMATE)/NEC/i;
    $make =~ s/^(XPRINT|MAJESTIX)/XEROX/i;
    $make =~ s/^QMS-PS/QMS/i;
    $make =~ s/^(PERSONAL|LASERWRITER)/APPLE/i;
    $make =~ s/^DIGITAL/DEC/i;
    $make =~ s/\s+Inc\.//i;
    $make =~ s/\s+Corp\.//i;
    $make =~ s/\s+SA\.//i;
    $make =~ s/\s+S\.\s*A\.//i;
    $make =~ s/\s+Ltd\.//i;
    $make =~ s/\s+International//i;
    $make =~ s/\s+Int\.//i;
    return uc($make);
}    

sub ppd_entry_str {
    my ($mf, $descr, $lang) = @_;
    my ($model, $driver);
    if ($descr) {
	# Apply the beautifying rules of poll_ppd_base
	if ($descr =~ /Foomatic \+ Postscript/) {
	    $descr =~ s/Foomatic \+ Postscript/PostScript/;
	} elsif ($descr =~ /Foomatic/i) {
	    $descr =~ s/Foomatic/GhostScript/i;
	} elsif ($descr =~ /CUPS\+Gimp-Print/i) {
	    $descr =~ s/CUPS\+Gimp-Print/CUPS + Gimp-Print/i;
	} elsif ($descr =~ /Series CUPS/i) {
	    $descr =~ s/Series CUPS/Series, CUPS/i;
	} elsif ($descr !~ /(PostScript|GhostScript|CUPS|Foomatic|PCL|PXL)/i) {
	    $descr .= ", PostScript";
	}
	# Split model and driver
	$descr =~ s/\s*Series//i;
	$descr =~ s/\((.*?(PostScript|PS.*).*?)\)/$1/i;
	if ($descr =~
	     /^\s*(Generic\s*PostScript\s*Printer)\s*,?\s*(.*)$/i ||
	    $descr =~
	     /^\s*(PostScript\s*Printer)\s*,?\s*(.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,?\s*(Foomatic.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,?\s*(GhostScript.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,?\s*(CUPS.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,\s+(PS.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,\s+(PXL.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,\s+(PCL.*)$/i ||
	    $descr =~
	     /^([^,]+?)\s*,?\s*(\(v?\.?\s*\d\d\d\d\.\d\d\d\).*)$/i ||
	    $descr =~ /^([^,]+?)\s*,?\s*(v?\.?\s*\d+\.\d+.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,?\s*(PostScript.*)$/i ||
	    $descr =~ /^([^,]+?)\s*,\s*(.+?)$/) {
	    $model = $1;
	    $driver = $2;
	    $model =~ s/[\-\s,]+$//;
	    $driver =~ s/\b(PS|PostScript\b)/PostScript/gi;
	    $driver =~ s/(PostScript)(.*)(PostScript)/$1$2/i;
	    $driver =~ s/\b(PXL|PCL[\s\-]*(6|XL)\b)/PCL-XL/gi;
	    $driver =~ s/(PCL-XL)(.*)(PCL-XL)/$1$2/i;
	    $driver =~ s/\b(PCL[\s\-]*(|4|5|5c|5e)\b)/PCL/gi;
	    $driver =~ s/(PCL)(.*)(PCL)/$1$2/i;
	    $driver =~ 
	      s/^\s*(\(?v?\.?\s*\d\d\d\d\.\d\d\d\)?|v\d+\.\d+)([,\s]*)(.*?)\s*$/$3$2$1/i;
	    $driver =~ s/,\s*\(/ (/g;
	    $driver =~ s/[\-\s,]+$//;
	    $driver =~ s/^[\-\s,]+//;
	    $driver =~ s/\s+/ /g;
	    if ($driver !~ /[a-z]/i) {
		$driver = "PostScript " . $driver;
		$driver =~ s/ $//;
	    }
	} else {
	    # Some PPDs do not have the ", <driver>" part.
	    $model = $descr;
	    if ($model =~ /\b(PXL|PCL[\s\-]*(6|XL))\b/i) {
		$driver = "PCL-XL";
	    } elsif ($model =~ /\b(PCL[\s\-]*(|4|5|5c|5e)\b)/i) {
		$driver = "PCL";
	    } else {
		$driver = "PostScript";
	    }
	}
    }
    # Remove manufacturer's name from the beginning of the model
    # name (do not do this with manufacturer names which contain
    # odd characters)
    $model =~ s/^$mf[\s\-]+//i 
	if $mf && $mf !~ m![\\/\(\)\[\]\|\.\$\@\%\*\?]!;
    # Clean some manufacturer's names
    $mf = clean_manufacturer_name($mf);
    # Rename Canon "BJC XXXX" models into "BJC-XXXX" so that the 
    # models do not appear twice
    if ($mf eq "CANON") {
	$model =~ s/BJC\s+/BJC-/;
    }
    # New MF devices from Epson have mis-spelled name in PPD files for
    # native CUPS drivers of Gimp-Print
    if ($mf eq "EPSON") {
	$model =~ s/Stylus CX\-/Stylus CX/;
    }
    # Remove the "Oki" from the beginning of the model names of Okidata
    # printers
    if ($mf eq "OKIDATA") {
	$model =~ s/Oki\s+//i;
    }
    # Try again to remove manufacturer's name from the beginning of the 
    # model name, this time with the cleaned manufacturer name
    $model =~ s/^$mf[\s\-]+//i 
	if $mf && $mf !~ m![\\/\(\)\[\]\|\.\$\@\%\*\?]!;
    # Translate "(recommended)" in the driver string
    $driver =~ s/\(recommended\)/$precstr/gi;
    # Put out the resulting description string
    uc($mf) . '|' . $model . '|' . $driver .
      ($lang && " (" . lang::locale_to_main_locale($lang) . ")");
}

sub get_descr_from_ppd {
    my ($printer) = @_;
    #- if there is no ppd, this means this is a raw queue.
    if (! -r "$::prefix/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd") {
	return "|" . N("Unknown model");
    }
    return get_descr_from_ppdfile($printer, "/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd");
}

sub get_descr_from_ppdfile {
    my ($printer, $ppdfile) = @_;
    my %ppd;

    # Remove ".gz" from end of file name, so that "catMaybeCompressed" works
    $ppdfile =~ s/\.gz$//;

    eval {
	local $_;
	foreach (catMaybeCompressed("$::prefix$ppdfile")) {
	    # "OTHERS|Generic PostScript printer|PostScript (en)";
	    /^\*([^\s:]*)\s*:\s*"([^"]*)"/ and
		do { $ppd{$1} = $2; next };
	    /^\*([^\s:]*)\s*:\s*([^\s"]*)/   and
		do { $ppd{$1} = $2; next };
	}
    };
    my $descr = ($ppd{NickName} || $ppd{ShortNickName} || $ppd{ModelName});
    my $make = $ppd{Manufacturer};
    my $lang = $ppd{LanguageVersion};
    my $entry = ppd_entry_str($make, $descr, $lang);
    if (!$printer->{expert}) {
	# Remove driver from printer list entry when in recommended mode
	$entry =~ s/^([^\|]+\|[^\|]+)\|.*$/$1/;
    }
    return $entry;
}

sub ppd_devid_data {
    my ($ppd) = @_;
    $ppd = "$::prefix/usr/share/cups/model/$ppd";
    my @content;
    if ($ppd =~ /\.gz$/i) {
	@content = cat_("$::prefix/bin/zcat $ppd |") or return "", "";
    } else {
	@content = cat_($ppd) or return "", "";
    }
    my ($devidmake, $devidmodel);
    /^\*Manufacturer:\s*"(.*)"\s*$/ and $devidmake = $1
	foreach @content;
    /^\*Product:\s*"\(?(.*?)\)?"\s*$/ and $devidmodel = $1 
	foreach @content;
    return $devidmake, $devidmodel;
}

sub poll_ppd_base {
    my ($printer) = @_;
    #- Before trying to poll the ppd database available to cups, we have 
    #- to make sure the file /etc/cups/ppds.dat is no more modified.
    #- If cups continue to modify it (because it reads the ppd files 
    #- available), the poll_ppd_base program simply cores :-)
    # else cups will not be happy! and ifup lo do not run ?
    run_program::rooted($::prefix, 'ifconfig', 'lo', '127.0.0.1');
    printer::services::start_not_running_service("cups");
    my $driversthere = scalar(keys %thedb);
    foreach (1..60) {
	open(my $PPDS, ($::testing ? $::prefix :
				 "chroot $::prefix/ ") .
				 "/usr/bin/poll_ppd_base -a |");
	local $_;
	while (<$PPDS>) {
	    chomp;
	    my ($ppd, $mf, $descr, $lang) = split /\|/;
	    if ($ppd eq "raw") { next }
	    $ppd && $mf && $descr and do {
		my $key = ppd_entry_str($mf, $descr, $lang);
		my ($model, $driver) = ($1, $2) if $key =~ /^[^\|]+\|([^\|]+)\|(.*)$/;
		# Clean some manufacturer's names
		$mf = clean_manufacturer_name($mf);
		# Remove language tag
		$driver =~ s/\s*\([a-z]{2}(|_[A-Z]{2})\)\s*$//;
		# Recommended Foomatic PPD? Extract "(recommended)"
		my $isrecommended = 
		    $driver =~ s/\s+$sprecstr\s*$//i;
		# Remove trailing white space
		$driver =~ s/\s+$//;
		# For Foomatic: Driver with "GhostScript + "
		my $fullfoomaticdriver = $driver;
		# Foomatic PPD? Extract driver name
		my $isfoomatic = 
		    $driver =~ s!^\s*(GhostScript|Foomatic)(\s*\+\s*|/)!!i;
		# Foomatic PostScript driver?
		$isfoomatic ||= $descr =~ /Foomatic/i;
		# Native CUPS?
		my $isnativecups = $driver =~ /CUPS/i;
		# Native PostScript
		my $isnativeps = !$isfoomatic && !$isnativecups;
		# Key without language tag (key as it was produced for the
		# entries from the Foomatic XML database)
		my $keynolang = $key;
		$keynolang =~ s/\s*\([a-z]{2}(|_[A-Z]{2})\)\s*$//;
		if (!$isfoomatic) {
		    # Driver is PPD when the PPD is a non-Foomatic one
		    $driver = "PPD";
		} else {
		    # Remove language tag in menu entry when PPD is from
		    # Foomatic
		    $key = $keynolang;
		}
	        my ($devidmake, $devidmodel, $deviddesc, $devidcmdset);
		# Replace an existing printer entry if it has linked
		# to the current PPD file.
		my ($filename, $ppdkey);
		$ppd =~ m!([^/]+\.ppd)(\.gz|\.bz2|)$!;
		if (($filename = $1) && 
		    ($#{$linkedppds{$filename}} >= 0)) {
		    foreach $ppdkey (@{$linkedppds{$filename}}) {
			next if !defined($thedb{$ppdkey});
			# Save the autodetection data
			$devidmake = $thedb{$ppdkey}{devidmake};
			$devidmodel = $thedb{$ppdkey}{devidmodel};
			$deviddesc = $thedb{$ppdkey}{deviddesc};
			$devidcmdset = $thedb{$ppdkey}{devidcmdset};
			# We must preserve make and model if we have one
			# PPD for multiple printers
			my $oldmake = $thedb{$ppdkey}{make};
			my $oldmodel = $thedb{$ppdkey}{model};
			# Remove the old entry
			delete $thedb{$ppdkey};
			my $newkey = $key;
			if (!$printer->{expert}) {
			    # Remove driver part in recommended mode
			    $newkey =~ s/^([^\|]+\|[^\|]+)\|.*$/$1/;
			} else {
			    # If the Foomatic entry is "recommended" let
			    # the new PPD entry be "recommended"
			    $newkey =~ s/\s*$sprecstr//g;
			    $newkey .= " $precstr" 
				if $ppdkey =~ m!$precstr!;
			    # Remove duplicate "recommended" tags and have 
			    # the "recommended" tag at the end
			    $newkey =~
				s/(\s*$sprecstr)(.*?)(\s*$sprecstr)/$2$3/;
			    $newkey =~ s/(\s*$sprecstr)(.+)$/$2$1/;
			}
			# If the PPD serves for multiple printers, conserve
			# the make and model of the original entry
			if (($#{$linkedppds{$filename}} > 0)) {
			    $newkey =~
				s/^([^\|]+)(\|[^\|]+)(\|.*|)$/$oldmake$2$3/;
			    $newkey =~
				s/^([^\|]+\|)([^\|]+)(\|.*|)$/$1$oldmodel$3/;
			}
			# Create the new entry
			$thedb{$newkey}{ppd} = $ppd;
			$thedb{$newkey}{make} = $mf;
			$thedb{$newkey}{model} = $model;
			$thedb{$newkey}{driver} = $driver;
			# Recover saved autodetection data
			$thedb{$newkey}{devidmake} = $devidmake
			    if $devidmake;
			$thedb{$newkey}{devidmodel} = $devidmodel
			    if $devidmodel;
			$thedb{$newkey}{deviddesc} = $deviddesc
			    if $deviddesc;
			$thedb{$newkey}{devidcmdset} = $devidcmdset
			    if $devidcmdset;
		    }
		    next;
		} elsif (!$printer->{expert}) {
		    # Remove driver from printer list entry when in
		    # recommended mode
		    $key =~ s/^([^\|]+\|[^\|]+)\|.*$/$1/;

		    # Only replace an existing printer entry if
		    #  - its driver is not the same as the driver of the
		    #    new one
		    # AND if one of the following items is true
		    #  - The existing entry uses a "Foomatic + Postscript" 
		    #    driver and the new one is native PostScript
		    #  - The existing entry is a Foomatic entry and the new 
		    #    one is "recommended"
		    #  - The existing entry is a native PostScript entry
		    #    and the new entry is a "recommended" driver other
		    #    then "Foomatic + Postscript"
		    if (defined($thedb{$key})) {
			next if lc($thedb{$key}{driver}) eq
				     lc($driver);
			if ($isnativeps &&
                            $thedb{$key}{driver} =~ /^PostScript$/i ||
                            $thedb{$key}{driver} ne "PPD" && $isrecommended ||
                            $thedb{$key}{driver} eq "PPD" && $isrecommended && $driver ne "PostScript") {
			    # Save the autodetection data
			    $devidmake = $thedb{$key}{devidmake};
			    $devidmodel = $thedb{$key}{devidmodel};
			    $deviddesc = $thedb{$key}{deviddesc};
			    $devidcmdset = $thedb{$key}{devidcmdset};
                            # Remove the old entry
                            delete $thedb{$key};
                        } else {
                            next;
                        }
		    }
		} elsif ((defined 
			   $thedb{"$mf|$model|$fullfoomaticdriver"} ||
			  defined 
			   $thedb{"$mf|$model|$fullfoomaticdriver $precstr"}) && 
			 $isfoomatic) {
		    # Expert mode: There is already an entry for the
		    # same printer/driver combo produced by the
		    # Foomatic XML database, so do not make a second
		    # entry
		    next;
		} elsif (defined
			 $thedb{"$mf|$model|PostScript $precstr"} &&
			 $isnativeps) {
		    # Expert mode: "Foomatic + Postscript" driver is
		    # recommended and this is a PostScript PPD? Make
		    # this PPD the recommended one
		    foreach (keys 
		         %{$thedb{"$mf|$model|PostScript $precstr"}}) {
			$thedb{"$mf|$model|PostScript"}{$_} =
			  $thedb{"$mf|$model|PostScript $precstr"}{$_};
		    }
		    delete
			$thedb{"$mf|$model|PostScript $precstr"};
		    if (!$isrecommended) {
			$key .= " $precstr";
		    }
		} elsif ($driver =~ /PostScript/i &&
			 $isrecommended && $isfoomatic &&
			 (my @foundkeys = grep {
			     /^$mf\|$model\|/ && !/CUPS/i &&
			     $thedb{$_}{driver} eq "PPD";
			 } keys %thedb)) {
		    # Expert mode: "Foomatic + Postscript" driver is
		    # recommended and there was a PostScript PPD? Make
		    # the PostScript PPD the recommended one
		    my $firstfound = $foundkeys[0];
		    if (!(any { /$sprecstr/ } @foundkeys)) {
			# Do it only if none of the native PostScript
			# PPDs for this printer is already "recommended"
			foreach (keys %{$thedb{$firstfound}}) {
			    $thedb{"$firstfound $precstr"}{$_} =
				$thedb{$firstfound}{$_};
			}
			delete $thedb{$firstfound};
		    }
		    $key =~ s/\s*$sprecstr//;
		} elsif ($driver !~ /PostScript/i &&
			 $isrecommended && $isfoomatic &&
			 (@foundkeys = grep {
			     /^$mf\|$model\|.*$sprecstr/ && 
			     !/CUPS/i && $thedb{$_}{driver} eq "PPD";
			 } keys %thedb)) {
		    # Expert mode: Foomatic driver other than "Foomatic +
		    # Postscript" is recommended and there was a PostScript 
		    # PPD which was recommended? Make the Foomatic driver
		    # the recommended one
		    foreach my $sourcekey (@foundkeys) {
			# Remove the "recommended" tag
			my $destkey = $sourcekey;
			$destkey =~ s/\s+$sprecstr\s*$//i;
			foreach (keys %{$thedb{$sourcekey}}) {
			    $thedb{$destkey}{$_} = $thedb{$sourcekey}{$_};
			}
			delete $thedb{$sourcekey};
		    }
		}
		
		# Remove duplicate "recommended" tags and have the
		# "recommended" tag at the end
		$key =~ s/(\s*$sprecstr)(.*?)(\s*$sprecstr)/$2$3/;
		$key =~ s/(\s*$sprecstr)(.+)$/$2$1/;
		# Create the new entry
	        $thedb{$key}{ppd} = $ppd;
		$thedb{$key}{make} = $mf;
		$thedb{$key}{model} = $model;
		$thedb{$key}{driver} = $driver;
		# Recover saved autodetection data
		$thedb{$key}{devidmake} = $devidmake if $devidmake;
		$thedb{$key}{devidmodel} = $devidmodel if $devidmodel;
		$thedb{$key}{deviddesc} = $deviddesc if $deviddesc;
		$thedb{$key}{devidcmdset} = $devidcmdset if $devidcmdset;
		# Get autodetection data
		#my ($devidmake, $devidmodel) = ppd_devid_data($ppd);
		#$thedb{$key}{devidmake} = $devidmake;
		#$thedb{$key}{devidmodel} = $devidmodel;
	    };
	}
	close $PPDS;
	scalar(keys %thedb) - $driversthere > 5 and last;
	#- we have to try again running the program, wait here a little 
	#- before.
	sleep 1;
    }
    #scalar(keys %descr_to_ppd) > 5 or 
    #  die "unable to connect to cups server";

}



#-******************************************************************************
#- write functions
#-******************************************************************************

sub configure_queue($) {
    my ($printer) = @_;

    #- Create the queue with "foomatic-configure", in case of queue
    #- renaming copy the old queue
    my $quotedconnect = $printer->{currentqueue}{connect};
    $quotedconnect =~ s/\$/\\\$/g; # Quote '$' in URI
    run_program::rooted($::prefix, "foomatic-configure", "-q",
			"-s", $printer->{currentqueue}{spooler},
			"-n", $printer->{currentqueue}{queue},
			($printer->{currentqueue}{queue} ne 
			 $printer->{OLD_QUEUE} &&
			 $printer->{configured}{$printer->{OLD_QUEUE}} ?
			 ("-C", $printer->{OLD_QUEUE}) : ()),
			"-c", $quotedconnect,
			($printer->{currentqueue}{foomatic} ?
			 ("-p", $printer->{currentqueue}{printer},
			  "-d", $printer->{currentqueue}{driver}) :
			 ($printer->{currentqueue}{ppd} ?
			  ($printer->{currentqueue}{ppd} ne '1' ?
			   ("--ppd",
			    ($printer->{currentqueue}{ppd} !~ m!^/! ?
			     "/usr/share/cups/model/" : "") .
			    $printer->{currentqueue}{ppd}) : ()) :
			  ("-d", "raw"))),
			"-N", $printer->{currentqueue}{desc},
			"-L", $printer->{currentqueue}{loc},
			if_($printer->{SPOOLER} eq "cups",
			    "--backend-dont-disable=" . 
			    $printer->{currentqueue}{dd},
			    "--backend-attempts=" . 
			    $printer->{currentqueue}{att},
			    "--backend-delay=" . 
			    $printer->{currentqueue}{delay}),
			@{$printer->{currentqueue}{options}}
			) or return 0;
    if ($printer->{currentqueue}{ppd} &&
	($printer->{currentqueue}{ppd} ne '1')) {
	# Add a comment line containing the path of the used PPD file to the
	# end of the PPD file
	if ($printer->{currentqueue}{ppd} ne '1') {
	    append_to_file("$::prefix/etc/cups/ppd/$printer->{currentqueue}{queue}.ppd", "*%MDKMODELCHOICE:$printer->{currentqueue}{ppd}\n");
	}
    }	  

    # Make sure that queue is active
    if ($printer->{NEW} && ($printer->{SPOOLER} ne "pdq")) {
        run_program::rooted($::prefix, "foomatic-printjob",
			    "-s", $printer->{currentqueue}{spooler},
			    "-C", "up", $printer->{currentqueue}{queue});
    }

    # Check whether a USB printer is configured and activate USB printing if so
    my $useUSB = 0;
    foreach (values %{$printer->{configured}}) {
	$useUSB ||= $_->{queuedata}{connect} =~ /usb/i || 
	    $_->{DeviceURI} =~ /usb/i;
    }
    $useUSB ||= $printer->{currentqueue}{connect} =~ /usb/i;
    if ($useUSB) {
	my $f = "$::prefix/etc/sysconfig/usb";
	my %usb = getVarsFromSh($f);
	$usb{PRINTER} = "yes";
	setVarsInSh($f, \%usb);
    }

    # Open permissions for device file when PDQ is chosen as spooler
    # so normal users can print.
    if ($printer->{SPOOLER} eq 'pdq') {
	if ($printer->{currentqueue}{connect} =~ 
	    m!^\s*(file|parallel|usb|serial):(\S*)\s*$!) {
	    set_permissions($1, "666");
	}
    }

    # Make a new printer entry in the $printer structure
    $printer->{configured}{$printer->{currentqueue}{queue}}{queuedata} =
        {};
    copy_printer_params($printer->{currentqueue},
      $printer->{configured}{$printer->{currentqueue}{queue}}{queuedata});
    # Construct an entry line for tree view in main window of
    # printerdrake
    make_menuentry($printer, $printer->{currentqueue}{queue});

    # Store the default option settings
    $printer->{configured}{$printer->{currentqueue}{queue}}{args} = {};
    $printer->{configured}{$printer->{currentqueue}{queue}}{args} =
	$printer->{ARGS};

    # In case of CUPS set some more useful defaults for text and image 
    # printing
    if ($printer->{SPOOLER} eq "cups") {
	set_cups_special_options($printer,
				 $printer->{currentqueue}{queue});
    }

    # Clean up
    delete($printer->{ARGS});
    $printer->{OLD_CHOICE} = "";
    $printer->{ARGS} = {};
    $printer->{DBENTRY} = "";
    $printer->{currentqueue} = {};

    return 1;
}

sub enable_disable_queue {
    my ($printer, $queue, $state) = @_;
    
    if (($printer->{SPOOLER} ne "pdq") &&
	($printer->{SPOOLER} ne "rcups")) {
        run_program::rooted($::prefix, "foomatic-printjob",
			    "-s", $printer->{SPOOLER},
			    "-C", ($state ? "start" : "stop"), $queue);
    }
}

sub remove_queue($$) {
    my ($printer, $queue) = @_;
    run_program::rooted($::prefix, "foomatic-configure", "-R", "-q",
			"-s", $printer->{SPOOLER},
			"-n", $queue);
    # Delete old stuff from data structure
    delete $printer->{configured}{$queue};
    delete($printer->{currentqueue});
    delete($printer->{ARGS});
    $printer->{OLD_CHOICE} = "";
    $printer->{ARGS} = {};
    $printer->{DBENTRY} = "";
    $printer->{currentqueue} = {};
}

sub restart_queue($) {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};

    # Restart the daemon(s)
    for ($printer->{SPOOLER}) {
	/cups/ and do {
	    #- restart cups.
	    printer::services::restart("cups");
	    last };
	/lpr|lprng/ and do {
	    #- restart lpd.
	    foreach ("/var/spool/lpd/$queue/lock", "/var/spool/lpd/lpd.lock") {
		my $pidlpd = (cat_("$::prefix$_"))[0];
		kill 'TERM', $pidlpd if $pidlpd;
		unlink "$::prefix$_";
	    }
	    printer::services::restart("lpd"); sleep 1;
	    last };
    }
    # Kill the jobs
    run_program::rooted($::prefix, "foomatic-printjob", "-R",
			"-s", $printer->{SPOOLER},
			"-P", $queue, "-");

}

sub print_pages($@) {
    my ($printer, @pages) = @_;
    my $queue = $printer->{QUEUE};
    my $lpr = "/usr/bin/foomatic-printjob";
    my $lpq = "$lpr -Q";
    my $spooler = $printer->{SPOOLER};
    $spooler = "cups" if $spooler eq "rcups";

    # Print the pages
    foreach (@pages) {
	my $page = $_;
	# Only text and PostScript can be printed directly with all
	# spoolers, images must be treated seperately
	if ($page =~ /\.jpg$/) {
	    if ($spooler ne "cups") {
		# Use "convert" from ImageMagick for non-CUPS spoolers
		system(($::testing ? $::prefix : "chroot $::prefix/ ") .
		       "/usr/bin/convert $page -page 427x654+100+65 PS:- | " .
		       ($::testing ? $::prefix : "chroot $::prefix/ ") .
		       "$lpr -s $spooler -P $queue");
	    } else {
		# Use CUPS's internal image converter with CUPS, tell it
		# to let the image occupy 90% of the page size (so nothing
		# gets cut off by unprintable borders)
		run_program::rooted($::prefix, $lpr, "-s", $spooler,
				    "-P", $queue, "-o", "scaling=90", $page);
	    }		
	} else {
	    run_program::rooted($::prefix, $lpr, "-s", $spooler,
				"-P", $queue, $page);
	}
    }
    sleep 5; #- allow lpr to send pages.
    # Check whether the job is queued
    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "$lpq -s $spooler -P $queue |");
    my @lpq_output =
	grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <$F>;
    close $F;
    @lpq_output;
}

sub help_output {
    my ($printer, $spooler) = @_;
    my $queue = $printer->{QUEUE};

    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . sprintf($spoolers{$spooler}{help}, $queue));
    my $helptext = join("", <$F>);
    close $F;
    $helptext ||= "Option list not available!\n";
    return $helptext;
}

sub print_optionlist {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};
    my $lpr = "/usr/bin/foomatic-printjob";

    # Print the option list pages
    if ($printer->{configured}{$queue}{queuedata}{foomatic}) {
        run_program::rooted($::prefix, $lpr, "-s", $printer->{SPOOLER},
			    "-P", $queue, "-o", "docs",
			    "/etc/bashrc");
    } elsif ($printer->{configured}{$queue}{queuedata}{ppd}) {
	system(($::testing ? $::prefix : "chroot $::prefix/ ") .
	       "/usr/bin/lphelp $queue | " .
	       ($::testing ? $::prefix : "chroot $::prefix/ ") .
	       "$lpr -s $printer->{SPOOLER} -P $queue");
    }
}

# ---------------------------------------------------------------
#
# Spooler config stuff
#
# ---------------------------------------------------------------

sub get_copiable_queues {
    my ($oldspooler, $newspooler) = @_;

    # No local queues available in daemon-less CUPS mode
    return () if ($oldspooler eq "rcups") or ($newspooler eq "rcups");

    my @queuelist;      #- here we will list all Foomatic-generated queues
    # Get queue list with foomatic-configure
    open(my $QUEUEOUTPUT, ($::testing ? $::prefix : "chroot $::prefix/ ") .
	    "foomatic-configure -Q -q -s $oldspooler |") or
		die "Could not run foomatic-configure";

    my $entry = {};
    my $inentry = 0;
    local $_;
    while (<$QUEUEOUTPUT>) {
	chomp;
	if ($inentry) {
	    # We are inside a queue entry
	    if (m!^\s*</queue>\s*$!) {
		# entry completed
		$inentry = 0;
		if ($entry->{foomatic} && $entry->{spooler} eq $oldspooler) {
		    # Is the connection type supported by the new
		    # spooler?
		    if ($newspooler eq "cups" && $entry->{connect} =~ /^(file|hp|ptal|lpd|socket|smb|ipp):/ ||
                  $newspooler =~ /^(lpd|lprng)$/ && $entry->{connect} =~ /^(file|ptal|lpd|socket|smb|ncp|postpipe):/ ||
                  $newspooler eq "pdq" && $entry->{connect} =~ /^(file|ptal|lpd|socket):/) {
                  push(@queuelist, $entry->{name});
		    }
		}
		$entry = {};
	    } elsif (m!^\s*<name>(.+)</name>\s*$!) {
		    # queue name
		    $entry->{name} = $1;
	    } elsif (m!^\s*<connect>(.+)</connect>\s*$!) {
		    # connection type (URI)
		    $entry->{connect} = $1;
	    }
	} else {
	    if (m!^\s*<queue\s+foomatic\s*=\s*"?(\d+)"?\s*spooler\s*=\s*"?(\w+)"?\s*>\s*$!) {
		# new entry
		$inentry = 1;
		$entry->{foomatic} = $1;
		$entry->{spooler} = $2;
	    }
	}
    }
    close $QUEUEOUTPUT;

    return @queuelist;
}

sub copy_foomatic_queue {
    my ($printer, $oldqueue, $oldspooler, $newqueue) = @_;
    run_program::rooted($::prefix, "foomatic-configure", "-q",
			"-s", $printer->{SPOOLER},
			"-n", $newqueue,
			"-C", $oldspooler, $oldqueue);
    # In case of CUPS set some more useful defaults for text and image printing
    if ($printer->{SPOOLER} eq "cups") {
	set_cups_special_options($printer, $newqueue);
    }
}

# ------------------------------------------------------------------
#
# Stuff for non-interactive printer configuration
#
# ------------------------------------------------------------------

# Check whether a given URI (for example of an existing queue matches
# one of the auto-detected printers

sub autodetectionentry_for_uri {
    my ($uri, @autodetected) = @_;

    if ($uri =~ m!^usb://([^/]+)/([^/\?]+)(|\?serial=(\S+))$!) {
	# USB device with URI referring to printer model
	my $make = $1;
	my $model = $2;
	my $serial = $4;
	if ($make && $model) {
	    $make =~ s/\%20/ /g;
	    $model =~ s/\%20/ /g;
	    $serial =~ s/\%20/ /g;
	    $make =~ s/Hewlett[-\s_]Packard/HP/;
	    $make =~ s/HEWLETT[-\s_]PACKARD/HP/;
	    my $smake = handle_configs::searchstr($make);
	    my $smodel = handle_configs::searchstr($model);
	    foreach my $p (@autodetected) {
		next if $p->{port} !~ /usb/i;
		next if ((!$p->{val}{MANUFACTURER} ||
                    $p->{val}{MANUFACTURER} ne $make) &&
                   (!$p->{val}{DESCRIPTION} ||
                    $p->{val}{DESCRIPTION} !~ /^\s*$smake\s+/));
		next if ((!$p->{val}{MODEL} ||
			  $p->{val}{MODEL} ne $model) &&
			 (!$p->{val}{DESCRIPTION} ||
			  $p->{val}{DESCRIPTION} !~ /\s+$smodel\s*$/));
		next if ($serial &&
			 (!$p->{val}{SERIALNUMBER} ||
			  $p->{val}{SERIALNUMBER} ne $serial));
		return $p;
	    }
	}
    } elsif ($uri =~ m!^hp:/(usb|par|net)/!) {
	# HP printer (controlled by HPLIP)
	my $hplipdevice = $uri;
	$hplipdevice =~ m!^hp:/(usb|par|net)/(\S+?)(\?serial=(\S+)|)$!;
	my $model = $2;
	my $serial = $4;
	$model =~ s/_/ /g;
	foreach my $p (@autodetected) {
	    next if !$p->{val}{MODEL};
	    if (uc($p->{val}{MODEL}) ne uc($model)) {
		my $entry = hplip_device_entry($p->{port}, @autodetected);
		next if !$entry;
		my $m = $entry->{model};
		$m =~ s/_/ /g;
		next if uc($m) ne uc($model);
	    }
	    next if ($serial && !$p->{val}{SERIALNUMBER}) ||
		(!$serial && $p->{val}{SERIALNUMBER}) ||
		(uc($serial) ne uc($p->{val}{SERIALNUMBER}));
	    return $p;
	}
    } elsif ($uri =~ m!^ptal://?mlc:!) {
	# HP multi-function device (controlled by HPOJ)
	my $ptaldevice = $uri;
	$ptaldevice =~ s!^ptal://?mlc:!!;
	if ($ptaldevice =~ /^par:(\d+)$/) {
	    my $device = "/dev/lp$1";
	    foreach my $p (@autodetected) {
		next if !$p->{port} ||
			 $p->{port} ne $device;
		return $p;
	    }
	} else {
	    my $model = $2 if $ptaldevice =~ /^(usb|par):(.*)$/;
	    $model =~ s/_/ /g;
	    foreach my $p (@autodetected) {
		next if !$p->{val}{MODEL} ||
			 $p->{val}{MODEL} ne $model;
		return $p;
	    }
	}
    } elsif ($uri =~ m!^(socket|smb|file|parallel|usb|serial):/!) {
	# Local print-only device, Ethernet-(TCP/Socket)-connected printer, 
	# or printer on Windows server
	my $device = $uri;
	$device =~ s/^(file|parallel|usb|serial)://;
	foreach my $p (@autodetected) {
	    next if !$p->{port} ||
		     $p->{port} ne $device;
	    return $p;
	}
    }
    return undef;
}

# ------------------------------------------------------------------
#
# Configuration of HP multi-function devices
#
# ------------------------------------------------------------------

sub read_hplip_db {

    # Read the device database XML file which comes with the HPLIP
    # package
    open(my $F, "< $::prefix/usr/share/hplip/data/xml/models.xml") or
	die "Could not read /usr/share/hplip/data/xml/models.xml\n";

    my $entry = {};
    my $inentry = 0;
    my $inrX = 0;
    my $incomment = 0;
    my %hplipdevices;
    local $_;
    while (<$F>) {
	chomp;
	if ($incomment) {
	    # In a comment block, skip all except the end of the comment
	    if (m!^(.*?)-->(.*)$!) {
		# End of comment, keep rest of line
		$_ = $2;
		$incomment = 0;
	    } else {
		# Skip line
		$_ = '';
	    }
	} else {
	    while (m/^(.*?)<!--(.*?)-->(.*)$/) {
		# Remove one-line comments
		$_ = $1 . $3;
	    }
	    if (m/^(.*?)<!--(.*)$/) {
		# Start of comment, keep the beginning of the line
		$_ = $1;
		$incomment = 1;
	    }
	}
	# Is there some non-comment part left in the line
	if (m!\S!) {
	    if ($inentry) {
		# We are inside a device entry
		if ($inrX) {
		    # We are in one of the the device's <rX> sections,
		    # skip the section
		    if (m!^\s*</r\d+>\s*$!) {
			# End of <rX> section
			$inrX = 0;
		    }
		} else {
		    if (m!^\s*<r\d+>\s*$!) {
			# Start of <rX> section
			$inrX = 1;
		    } elsif (m!^\s*</model>\s*$!) {
			# End of device entry
			$inentry = 0;
			my $devidmodel;
			if ($entry->{$devidmodel}) {
			    $devidmodel = $entry->{devidmodel};
			    $devidmodel =~ s/ /_/g;
			} else {
			    $devidmodel = $entry->{model};
			}
			$hplipdevices{$devidmodel} = $entry;
			$entry = {};
		    } elsif (m!^\s*<id>\s*([^<>]+)\s*</id>\s*$!) {
			# Full ID string
			my $idstr = $1;
			$idstr =~ m!(MFG|MANUFACTURER):([^;]+);!i
			    and $entry->{devidmake} = $2;
			$idstr =~ m!(MDL|MODEL):([^;]+);!i
			    and $entry->{devidmodel} = $2;
			$idstr =~ m!(DES|DESCRIPTION):([^;]+);!i
			    and $entry->{deviddesc} = $2;
			$idstr =~ m!(CMD|COMMAND\s*SET):([^;]+);!i
			    and $entry->{devidcmdset} = $2;
		    } elsif (m!^\s*<tech type="(\d+)"/>\s*$!) {
			# Printing technology
			$entry->{tech} = $1;
		    } elsif (m!^\s*<align type="(\d+)"/>\s*$!) {
			# Head alignment type
			$entry->{align} = $1;
		    } elsif (m!^\s*<clean type="(\d+)"/>\s*$!) {
			# Head cleaning type
			$entry->{clean} = $1;
		    } elsif (m!^\s*<color-cal type="(\d+)"/>\s*$!) {
			# Color calibration type
			$entry->{colorcal} = $1;
		    } elsif (m!^\s*<status type="(\d+)"/>\s*$!) {
			# Status request type
			$entry->{status} = $1;
		    } elsif (m!^\s*<scan type="(\d+)"/>\s*$!) {
			# Scanner access type
			$entry->{scan} = $1;
		    } elsif (m!^\s*<fax type="(\d+)"/>\s*$!) {
			# Fax access type
			$entry->{fax} = $1;
		    } elsif (m!^\s*<pcard type="(\d+)"/>\s*$!) {
			# Memory card access type
			$entry->{card} = $1;
		    } elsif (m!^\s*<copy type="(\d+)"/>\s*$!) {
			# Copier access type
			$entry->{copy} = $1;
		    }
		}
	    } else {
		# We are not in a printer entry
		if (m!^\s*<\s*model\s+name=\"(\S+)\"\a*>\s*$!) {
		    $inentry = 1;
		    # HPLIP model ID
		    $entry->{model} = $1;
		}
	    }
	}
    }
    close $F;
    return \%hplipdevices;
}

sub hplip_simple_model {
    my ($model) = @_;
    my $simplemodel = $model;
    $simplemodel =~ s/[^A-Za-z0-9]//g;
    $simplemodel =~ s/HewlettPackard/HP/gi;
    $simplemodel =~ s/HP//gi;
    $simplemodel =~ s/(DeskJet\d+C?)([a-z]*?)/$1/gi;
    $simplemodel =~ s/((LaserJet|OfficeJet|PhotoSmart|PSC)\d+)([a-z]*?)/$1/gi;
    $simplemodel =~ s/DeskJet/DJ/gi;
    $simplemodel =~ s/PhotoSmartP/PhotoSmart/gi;
    $simplemodel =~ s/LaserJet/LJ/gi;
    $simplemodel =~ s/OfficeJet/OJ/gi;
    $simplemodel =~ s/Series//gi;
    $simplemodel = uc($simplemodel);
    return $simplemodel;
}

sub hplip_device_entry {
    my ($device, @autodetected) = @_;

    # Currently, only devices on USB or TCP/Socket work
    return undef if ($device !~ /usb/i) && ($device !~ m!^socket://!i);

    if (!$hplipdevicesdb) {
	# Read the HPLIP device database if not done already
	$hplipdevicesdb = read_hplip_db();
    }

    my $entry;
    foreach my $a (@autodetected) {
	$device eq $a->{port} or next;
	# Only HP devices supported
	return undef if $a->{val}{MANUFACTURER} !~ /^\s*HP\s*$/i;
	my $modelstr = $a->{val}{MODEL};
	$modelstr =~ s/ /_/g;
	if ($entry = $hplipdevicesdb->{$modelstr}) {
	    # Exact match
	    return $entry;
	}
	my $hpmodelstr = "HP_" . $modelstr;
	if ($entry = $hplipdevicesdb->{$hpmodelstr}) {
	    # Exact match
	    return $entry;
	}
	# More 'fuzzy' matching
	my $simplemodel = hplip_simple_model($modelstr);
	foreach my $key (keys %{$hplipdevicesdb}) {
	    my $simplekey = hplip_simple_model($key);
	    return $hplipdevicesdb->{$key} if $simplemodel eq $simplekey;
	}
	foreach my $key (keys %{$hplipdevicesdb}) {
	    my $simplekey = hplip_simple_model($key);
	    $simplekey =~ s/(\d\d)00(C?)$/$1\\d\\d$2/;
	    $simplekey =~ s/(\d\d\d)0(C?)$/$1\\d$2/;
	    $simplekey =~ s/(\d\d)0(\dC?)$/$1\\d$2/;
	    return $hplipdevicesdb->{$key} if 
		$simplemodel =~ m/^$simplekey$/i;
	}
	# Device not supported
	return undef;
    }
    # $device not in @autodetected
    return undef;
}

sub hplip_device_entry_from_uri {
    my ($deviceuri) = @_;

    return undef if $deviceuri !~ m!^hp:/!;
    
    if (!$hplipdevicesdb) {
	# Read the HPLIP device database if not done already
	$hplipdevicesdb = read_hplip_db();
    }

    $deviceuri =~ m!^hp:/(usb|par|net)/(\S+?)(\?\S+|)$!;
    my $model = $2;
    return undef if !$model;

    my $entry;
    if ($entry = $hplipdevicesdb->{$model}) {
	return $entry;
    }
    return undef;
}

sub start_hplip {
    my ($device, $hplipentry, @autodetected) = @_;

    # Determine connection type
    my $bus;
    if ($device =~ /usb/) {
	$bus = "usb";
    } elsif ($device =~ /par/ ||
	     $device =~ m!/dev/lp! ||
	     $device =~ /printers/) {
	$bus = "par";
    } elsif ($device =~ m!^socket://!) {
	$bus = "net";
    } else {
	return undef;
    }

    # Start HPLIP daemons
    printer::services::start_not_running_service("hplip");

    # Determine HPLIP device URI for the CUPS queue
    if ($bus eq "net") {
	$device =~ m!^socket://([^:]+)(|:\d+)$!;
	my $host = $1;
	my $ip;
	if ($host !~ m!^\d+\.\d+\.\d+\.\d+$!) {
	    my $addr = gethostbyname("$host");
	    my ($a,$b,$c,$d) = unpack('C4',$addr);
	    $ip = sprintf("%d.%d.%d.%d", $a, $b, $c, $d);
	} else {
	    $ip = $host;
	}
	open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
	     "/bin/sh -c \"export LC_ALL=C; /usr/bin/hp-makeuri $ip\" |") or
	     die "Could not run \"/usr/bin/hp-makeuri $ip\"!";
	while (my $line = <$F>) {
	    if ($line =~ m!(hp:/net/\S+)!) {
		my $uri = $1;
		close $F;
		return $uri;
	    }
	}
	close $F;
    } else {
	foreach my $a (@autodetected) {
	    $device eq $a->{port} or next;
	    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
		 '/bin/sh -c "export LC_ALL=C; /usr/lib/cups/backend/hp" |') or
		 die 'Could not run "/usr/lib/cups/backend/hp"!';
	    while (my $line = <$F>) {
		if (($line =~ m!^direct\s+(hp:/$bus/(\S+)\?serial=(\S+))\s+!) ||
		    ($line =~ m!^direct\s+(hp:/$bus/(\S+))\s+!)) {
		    my $uri = $1;
		    my $modelstr = $2;
		    my $serial = $3;
		    if ((uc($modelstr) eq uc($hplipentry->{model})) &&
			(!$serial ||
			 (uc($serial) eq uc($a->{val}{SERIALNUMBER})))) {
			close $F;
			return $uri;
		    }
		}
	    }
	    close $F;
	}
	last;
    }
    # HPLIP URI not found
    return undef;
}

sub start_hplip_manual {

    # Start HPLIP daemons
    printer::services::start_not_running_service("hplip");

    # Return all possible device URIs
    open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
	 '/bin/sh -c "export LC_ALL=C; /usr/lib/cups/backend/hp" |') or
	 die 'Could not run "/usr/lib/cups/backend/hp"!';
    my @uris;
    while (<$F>) {
        m!^direct\s+(hp:\S+)\s+!;
	push(@uris, $1);
    }
    return @uris;
}

sub remove_hpoj_config {
    my ($device, @autodetected) = @_;

    for my $d (@autodetected) {
	$device eq $d->{port} or next;
	my $bus;
	if ($device =~ /usb/) {
	    $bus = "usb";
	} elsif ($device =~ /par/ ||
		 $device =~ m!/dev/lp! ||
		 $device =~ /printers/) {
	    $bus = "par";
	} elsif ($device =~ /socket/) {
	    $bus = "hpjd";
	}
	my $path = "$::prefix/etc/ptal";
	opendir PTALDIR, "$path";
	while (my $file = readdir(PTALDIR)) {
	    next if $file !~ /^(mlc:|)$bus:/;
	    $file = "$path/$file";
	    if ($bus eq "hpjd") {
		$device =~ m!^socket://(\S+?)(:\d+|)$!;
		my $host = $1;
		if ($file =~ /$host/) {
		    closedir PTALDIR;
		    unlink($file) or return $file;
		    printer::services::restart("hpoj");
		    return undef;
		} 
	    } else {
		if ((grep { /$d->{val}{MODEL}/ } chomp_(cat_($file))) &&
		    ((!$d->{val}{SERIALNUMBER}) ||
		     (grep { /$d->{val}{SERIALNUMBER}/ } 
		      chomp_(cat_($file))))) {
		    closedir PTALDIR;
		    unlink($file) or return $file;
		    printer::services::restart("hpoj");
		    return undef;
		}
	    }
	}
	last;
    }
    closedir PTALDIR;
    return undef;
}    

sub configure_hpoj {
    my ($device, @autodetected) = @_;

    # Make the subroutines of /usr/sbin/ptal-init available
    # It's only necessary to read it at the first call of this subroutine,
    # the subroutine definitions stay valid after leaving this subroutine.
    if (!$ptalinitread) {
	open(my $PTALINIT, "$::prefix/usr/sbin/ptal-init") or do {
	    die "unable to open $::prefix/usr/sbin/ptal-init";
	};
	my @ptalinitfunctions; # subroutine definitions in /usr/sbin/ptal-init
	local $_;
	while (<$PTALINIT>) {
	    if (m!sub main!) {
		last;
	    } elsif (m!^[^#]! && !(m!^\s*exec\b!)) {
		# Comment lines and the "exec" line (probably obsolete
		# Red Hat workaround) are skipped.

		# Make the subroutines also working during installation
		if ($::isInstall) {
		    s!\$::prefix!\$hpoj_prefix!g;
		    s!prefix="/usr"!prefix="$::prefix/usr"!g;
		    s!etcPtal="/etc/ptal"!etcPtal="$::prefix/etc/ptal"!g;
		    s!varLock="/var/lock"!varLock="$::prefix/var/lock"!g;
		    s!varRunPrefix="/var/run"!varRunPrefix="$::prefix/var/run"!g;
		    s!/sbin/lsmod!/usr/bin/lsmod!g;
		    s!/sbin/modprobe!/usr/bin/modprobe!g;
		    s!/sbin/rmmod!/usr/bin/rmmod!g;
		    s!(my\s*\$osPlatform\s*=\s*).*?$!$1"Linux";!g;
		    s!chomp\s*\$osPlatform\s*;\s*$!!g;
		    s!(my\s*\$linuxVersion\s*=\s*).*?$!$1"$kernelversion";!g;
		    s!^\s*\$linuxVersion\s*=~\s*s.*$!!g;
		    s!chomp\s*\$linuxVersion\s*;\s*$!!g;
		    s!(my\s*\$usbprintermodule\s*=\s*).*?$!$1"$usbprintermodule";!g;
		}
		push @ptalinitfunctions, $_;
	    }
	}
	close $PTALINIT;

	eval "package printer::hpoj;
        @ptalinitfunctions
        sub getDevnames {
	    return (%devnames)
	}
        sub getConfigInfo {
            return (%configInfo)
        }";

	if ($::isInstall) {
	    # Needed for photo card reader detection during installation
	    system("ln -s $::prefix/var/run/ptal-mlcd /var/run/ptal-mlcd");
	    system("ln -s $::prefix/etc/ptal /etc/ptal");
	}
	$ptalinitread = 1;
    }

    # Read the HPOJ config file and check whether this device is already
    # configured
    printer::hpoj::setupVariables();
    printer::hpoj::readDeviceInfo();

    $device =~ m!^/dev/\S*lp(\d+)$! or
	$device =~ m!^/dev/printers/(\d+)$! or
	$device =~ m!^socket://([^:]+)$! or
	$device =~ m!^socket://([^:]+):(\d+)$!;
    my $model = $1;
    my ($model_long, $serialnumber, $serialnumber_long) = ("", "", "");
    my $cardreader = 0;
    my $device_ok = 1;
    my $bus;
    my $address_arg = "";
    my $base_address = "";
    my $hostname = "";
    my $port = $2;
    if ($device =~ /usb/) {
	$bus = "usb";
    } elsif ($device =~ /par/ ||
	     $device =~ m!/dev/lp! ||
	     $device =~ /printers/) {
	$bus = "par";
	$address_arg = printer::detect::parport_addr($device);
	eval "$base_address = $1" if $address_arg =~ /^\s*-base\s+(\S+)/;
    } elsif ($device =~ /socket/) {
	$bus = "hpjd";
	$hostname = $model;
	return "" if $port && ($port < 9100 || $port > 9103);
	if ($port && $port != 9100) {
	    $port -= 9100;
	    $hostname .= ":$port";
	}
    } else {
	return "";
    }
    if ($#autodetected < 0) {
	# Make a pseudo structure for the auto-detected data if there is
	# no auto-detected data (for example when configuring manually)
	$autodetected[0] = {
	    'port' => $device,
	    'val' => {
		'MODEL' => N("Unknown model")
	    }
	};
    }
    foreach (@autodetected) {
	$device eq $_->{port} or next;
	# $model is for the PTAL device name, so make sure that it is unique
	# so in the case of the model name auto-detection having failed leave
	# the port number or the host name as model name.
	my $searchunknown = N("Unknown model");
	if ($_->{val}{MODEL} &&
	    $_->{val}{MODEL} !~ /$searchunknown/i &&
	    $_->{val}{MODEL} !~ /^\s*$/) {
	    $model = $_->{val}{MODEL};
	}
	$serialnumber = $_->{val}{SERIALNUMBER};
	services::stop("hpoj") if $bus ne "hpjd";
	# Check if the device is really an HP multi-function device
	#my $libusb = 0;
	foreach my $libusb (0, 1) {
	    # Do access via libusb/user mode only if we have a USB device
	    next if $libusb && $bus ne "usb";
	    # Preliminary workaround to make the user-mode USB devices
	    # (LIDIL devices) installable as verification of the HPOJ
	    # settings of these devices does not work yet. The workaround
	    # will probably removed after version 9.2 of this distribution.
	    # Note: This workaround leaves out the checking for a photo
	    # memory card reader, but to my knowledge there are no LIDIL
	    # devices with card reader yet.
	    if ($libusb) {
		$device_ok = 1;
		next;
	    }
	    my $printermoduleunloaded = 0;
	    if ($bus ne "hpjd") {
		if (!$libusb) {
		    # Start ptal-mlcd daemon for locally connected devices
		    # (kernel mode with "printer"/"usblp" module for USB).
		    run_program::rooted($::prefix, 
					"ptal-mlcd", "$bus:probe",
					(($bus ne "par") ||
					 (!$address_arg) ?
					 ("-device", $device) : ()), 
					split(' ',$address_arg));
		} else {
		    # Start ptal-mlcd daemon for user-mode USB devices
		    # (all LIDIL MF devices as HP PSC 1xxx and OfficeJet 
		    #  4xxx)
		    my $usbdev = usbdevice($_->{val});
		    if (defined($usbdev)) {
			# Unload kernel module "printer"/"usblp"
			if (modules::any_conf->read->get_probeall("usb-interface")) {
			    eval(modules::unload($usbprintermodule));
			    $printermoduleunloaded = 1;
			}
			# Start ptal-mlcd
			run_program::rooted($::prefix, 
					    "ptal-mlcd", "$bus:probe",
					    "-device", $usbdev);
		    } else {
			# We could not determine the USB device number,
			# so we cannot check this device in user mode
			next;
		    }
		}
	    }
	    $device_ok = 0;
	    my $ptalprobedevice = $bus eq "hpjd" ? "hpjd:$hostname" : "mlc:$bus:probe";
	    if (open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice |")) {
		my $devid = join("", <$F>);
		close $F;
		if ($devid) {
		    $device_ok = 1;
		    if (open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice -long -mdl 2>/dev/null |")) {
			$model_long = join("", <$F>);
			close $F;
			chomp $model_long;
			# If SNMP or local port auto-detection failed but 
			# HPOJ auto-detection succeeded, fill in model name 
			# here.
			if (!$_->{val}{MODEL} ||
			    $_->{val}{MODEL} =~ /$searchunknown/i ||
			    $_->{val}{MODEL} =~ /^\s*$/) {
			    if ($model_long =~ /:([^:;]+);/) {
				$_->{val}{MODEL} = $1;
				$model = $_->{val}{MODEL};
				$model =~ s/ /_/g;
			    }
			}
		    }
		    if (open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice -long -sern 2>/dev/null |")) { #-#
			$serialnumber_long = join("", <$F>);
			close $F;
			chomp $serialnumber_long;
		    }
		    $cardreader = 1 if printer::hpoj::cardReaderDetected($ptalprobedevice);
		}
	    }
	    if ($bus ne "hpjd") {
		# Stop ptal-mlcd daemon for locally connected devices
		if (open(my $F, ($::testing ? $::prefix : "chroot $::prefix/ ") . qq(ps auxwww | grep "ptal-mlcd $bus:probe" | grep -v grep | ))) {
		    my $line = <$F>;
		    if ($line =~ /^\s*\S+\s+(\d+)\s+/) {
			my $pid = $1;
			kill 15, $pid;
		    }
		    close $F;
		}
		$printermoduleunloaded &&
		    eval(modules::load($usbprintermodule));
	    }
	    last if $device_ok;
	}
	printer::services::start("hpoj") if $bus ne "hpjd";
	last;
    }
    # No, it is not an HP multi-function device.
    return "" if !$device_ok;
	
    # If $model_long and $serialnumber_long stay empty, fill them with
    # $model and $serialnumber
    $model_long ||= $model;
    $serialnumber_long ||= $serialnumber;

    # Determine the ptal device name from already existing config files
    my $ptalprefix =
	($bus eq "hpjd" ? "hpjd:" : "mlc:$bus:");
    my $ptaldevice = printer::hpoj::lookupDevname($ptalprefix, $model_long, 
				    $serialnumber_long, $base_address);

    # It's all done for us, the device is already configured
    return $ptaldevice if defined($ptaldevice);

    # Determine the ptal name for a new device
    if ($bus eq "hpjd") {
	$ptaldevice = "hpjd:$hostname";
    } else {
	$ptaldevice = $model;
	$ptaldevice =~ s![\s/]+!_!g;
	$ptaldevice = "mlc:$bus:$ptaldevice";
    }

    # Delete any old/conflicting devices
    printer::hpoj::deleteDevice($ptaldevice);
    if ($bus eq "par") {
	while (1) {
	    my $oldDevname = printer::hpoj::lookupDevname("mlc:par:",undef,undef,$base_address);
	    last unless defined($oldDevname);
	    printer::hpoj::deleteDevice($oldDevname);
	}
    }

    # Configure the device

    # Open configuration file
    open(my $CONFIG, "> $::prefix/etc/ptal/$ptaldevice") or
	die "Could not open /etc/ptal/$ptaldevice for writing!\n";

    # Write file header.
    my $date = chomp_(`date`);
    print $CONFIG
qq(
# Added $date by "printerdrake"

# The basic format for this file is "key[+]=value".
# If you say "+=" instead of "=", then the value is appended to any
# value already defined for this key, rather than replacing it.

# Comments must start at the beginning of the line.  Otherwise, they may
# be interpreted as being part of the value.

# If you have multiple devices and want to define options that apply to
# all of them, then put them in the file /etc/ptal/defaults, which is read
# in before this file.

# The format version of this file:
#   ptal-init ignores devices with incorrect/missing versions.
init.version=2
);

    # Write model string.
    if ($model_long !~ /\S/) {
	print $CONFIG
	    "\n" .
	    qq(# "printerdrake" couldn't read the model but added this device anyway:\n) .
	    "# ";
    } else {
	print $CONFIG
	    "\n" .
	    "# The device model that was originally detected on this port:\n" .
	    qq(#   If this ever changes, then you should re-run "printerdrake"\n) .
	    "#   to delete and re-configure this device.\n";
	if ($bus eq "par") {
	    print $CONFIG
		"#   Comment out if you do not care what model is really connected to this\n" .
		"#   parallel port.\n";
	}
    }
    print $CONFIG
	qq(init.mlcd.append+=-devidmatch "$model_long"\n);

    # Write serial-number string.
    if ($serialnumber_long !~ /\S/) {
	print $CONFIG
	    "\n" .
	    "# The device's serial number is unknown.\n" .
	    "# ";
    } else {
	print $CONFIG
	    "\n" .
	    "# The serial number of the device that was originally detected on this port:\n";
	if ($bus =~ /^[pu]/) {
	    print $CONFIG
		"#   Comment out if you want to disable serial-number matching.\n";
	}
    }
    print $CONFIG
	qq(init.mlcd.append+=-devidmatch "$serialnumber_long"\n);

    if ($bus =~ /^[pu]/) {
	print $CONFIG
	    "\n" .
	    "# Standard options passed to ptal-mlcd:\n" .
	    "init.mlcd.append+=";
	if ($bus eq "usb") {
	    # Important: do not put more quotes around /dev/usb/lp[0-9]*,
	    # because ptal-mlcd currently does no globbing:
	    print $CONFIG "-device /dev/usb/lp0 /dev/usb/lp1 /dev/usb/lp2 /dev/usb/lp3 /dev/usb/lp4 /dev/usb/lp5 /dev/usb/lp6 /dev/usb/lp7 /dev/usb/lp8 /dev/usb/lp9 /dev/usb/lp10 /dev/usb/lp11 /dev/usb/lp12 /dev/usb/lp13 /dev/usb/lp14 /dev/usb/lp15";
	} elsif ($bus eq "par") {
	    print $CONFIG "$address_arg" .
		(!$address_arg ? " -device $device" : "");
	}
	print $CONFIG "\n" .
	    "\n" .
	    "# ptal-mlcd's remote console can be useful for debugging, but may be a\n" .
	    "# security/DoS risk otherwise.  In any case, it's accessible with the\n" .
	    qq(# command "ptal-connect mlc:<XXX>:<YYY> -service PTAL-MLCD-CONSOLE".\n) .
	    "# Uncomment the following line if you want to enable this feature for\n" .
	    "# this device:\n" .
	    "# init.mlcd.append+=-remconsole\n" .
	    "\n" .
	    "# If you need to pass any other command-line options to ptal-mlcd, then\n" .
	    "# add them to the following line and uncomment the line:\n" .
	    "# init.mlcd.append+=\n" .
	    "\n" .
	    "# By default ptal-printd is started for mlc: devices.  If you use CUPS,\n" .
	    "# then you may not be able to use ptal-printd, and you can uncomment the\n" .
	    "# following line to disable ptal-printd for this device:\n" .
	    "# init.printd.start=0\n";
    } else {
	print $CONFIG
	    "\n" .
	    "# By default ptal-printd is not started for hpjd: devices.\n" .
	    "# If for some reason you want to start it for this device, then\n" .
	    "# uncomment the following line:\n" .
	    "init.printd.start=1\n";
    }

    print $CONFIG
	"\n" .
	"# If you need to pass any additional command-line options to ptal-printd,\n" .
	"# then add them to the following line and uncomment the line:\n" .
	"# init.printd.append+=\n";
    if ($cardreader) {
	print $CONFIG
	    "\n" .
	    "# Uncomment the following line to enable ptal-photod for this device:\n" .
	    "init.photod.start=1\n" .
	    "\n" .
	    "# If you have more than one photo-card-capable peripheral and you want to\n" .
	    "# assign particular TCP port numbers and mtools drive letters to each one,\n" .
	    qq(# then change the line below to use the "-portoffset <n>" option.\n) .
	    "init.photod.append+=-maxaltports 26\n";
    }
    close($CONFIG);
    printer::hpoj::readOneDevice($ptaldevice);

    # Restart HPOJ
    printer::services::restart("hpoj");

    # Return HPOJ device name to form the URI
    return $ptaldevice;
}

sub devicefound {
    my ($usbid, $model, $serial) = @_;
    # Compare the output of "lsusb -vv" with the elements of the device 
    # ID string
    if ($serial && $usbid->{SERIALNUMBER} eq $serial) {
	# Match of serial number has absolute priority
	return 1;
    } elsif ($model && $usbid->{MODEL} eq $model) {
	# Try to match the model name otherwise
	return 1;
    }
    return 0;
}

sub usbdevice {
    my ($usbid) = @_;
    # Run "lsusb -vv" and search the given device to get its USB bus and
    # device numbers
    open(my $F, ($::testing ? "" : "chroot $::prefix/ ") .
	'/bin/sh -c "export LC_ALL=C; lsusb -vv 2> /dev/null" |')
	or return undef;
    my ($bus, $device, $model, $serial) = ("", "", "", "");
    my $found = 0;
    while (my $line = <$F>) {
	chomp $line;
	if ($line =~ m/^\s*Bus\s+(\d+)\s+Device\s+(\d+)\s*:/i) {
	    # head line of a new device
	    my ($newbus, $newdevice) = ($1, $2);
	    last if (($model || $serial) && 
		     ($found = devicefound($usbid, $model, $serial)));
	    ($bus, $device) = ($newbus, $newdevice);
	} elsif ($line =~ m/^\s*iProduct\s+\d+\s+(.+)$/i) {
	    # model line
	    next if $device eq "";
	    $model = $1;
	} elsif ($line =~ m/^\s*iSerial\s+\d+\s+(.+)$/i) {
	    # model line
	    next if $device eq "";
	    $serial = $1;
	}
    }
    close $F;
    # Check last entry
    $found = devicefound($usbid, $model, $serial);

    return 0 if !$found;
    return sprintf("%%%03d%%%03d", $bus, $device);
}

sub config_sane {
    my ($backend) = @_;

    # Add HPOJ/HPLIP backend to /etc/sane.d/dll.conf if needed (no
    # individual config file /etc/sane.d/hplip.conf or
    # /etc/sane.d/hpoj.conf necessary, the HPLIP and HPOJ drivers find
    # the scanner automatically)

    return if (! -f "$::prefix/etc/sane.d/dll.conf");
    return if member($backend,
		     chomp_(cat_("$::prefix/etc/sane.d/dll.conf")));
    eval { append_to_file("$::prefix/etc/sane.d/dll.conf",
			  "$backend\n") } or
	   die "can not write SANE config in /etc/sane.d/dll.conf: $!";
}

sub config_photocard() {

    # Add definitions for the drives p:. q:, r:, and s: to /etc/mtools.conf
    cat_("$::prefix/etc/mtools.conf") !~ m/^\s*drive\s+p:/m or return;

    append_to_file("$::prefix/etc/mtools.conf", <<'EOF');
# Drive definitions added for the photo card readers in HP multi-function
# devices driven by HPOJ
drive p: file=":0" remote
drive q: file=":1" remote
drive r: file=":2" remote
drive s: file=":3" remote
# This turns off some file system integrity checks of mtools, it is needed
# for some photo cards.
mtools_skip_check=1
EOF

    # Generate a config file for the graphical mtools frontend MToolsFM or
    # modify the existing one
    my $mtoolsfmconf;
    if (-f "$::prefix/etc/mtoolsfm.conf") {
	$mtoolsfmconf = cat_("$::prefix/etc/mtoolsfm.conf") or die "can not read MToolsFM config in $::prefix/etc/mtoolsfm.conf: $!";
	my $alloweddrives = lc($1) if $mtoolsfmconf =~ m/^\s*DRIVES\s*=\s*"([A-Za-z ]*)"/m;
	foreach my $letter ("p", "q", "r", "s") {
         $alloweddrives .= $letter if $alloweddrives !~ /$letter/;
	}
	$mtoolsfmconf =~ s/^\s*DRIVES\s*=\s*"[A-Za-z ]*"/DRIVES="$alloweddrives"/m;
	$mtoolsfmconf =~ s/^\s*LEFTDRIVE\s*=\s*"[^"]*"/LEFTDRIVE="p"/m;
        #"# Fix emacs syntax highlighting
    } else {
	$mtoolsfmconf = <<'EOF';
# MToolsFM config file. comments start with a hash sign.
#
# This variable sets the allowed driveletters (all lowercase). Example:
# DRIVES="ab"
DRIVES="apqrs"
#
# This variable sets the driveletter upon startup in the left window.
# An empty string or space is for the hardisk. Example:
# LEFTDRIVE="a"
LEFTDRIVE="p"
#
# This variable sets the driveletter upon startup in the right window.
# An empty string or space is for the hardisk. Example:
# RIGHTDRIVE="a"
RIGHTDRIVE=" "
EOF
    }
    output("$::prefix/etc/mtoolsfm.conf", $mtoolsfmconf);
}

sub setcupslink {
    my ($printer) = @_;
    return 1 if !$::isInstall || $printer->{SPOOLER} ne "cups" || -d "/etc/cups/ppd";
    system("ln -sf $::prefix/etc/cups /etc/cups");
    return 1;
}


1;
