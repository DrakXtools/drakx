package printer::main;

# $Id$

use strict;

use common;
use run_program;
use printer::data;
use printer::services;
use printer::default;
use printer::gimp;
use printer::cups;
use printer::office;
use printer::detect;
use services;

use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(%printer_type %printer_type_inv);

#-location of the printer database in an installed system
my $PRINTER_DB_FILE = "/usr/share/foomatic/db/compiled/overview.xml";

#-Did we already read the subroutines of /usr/sbin/ptal-init?
my $ptalinitread = 0;

our %printer_type = (
    N("Local printer")                              => "LOCAL",
    N("Remote printer")                             => "REMOTE",
    N("Printer on remote CUPS server")              => "CUPS",
    N("Printer on remote lpd server")               => "LPD",
    N("Network printer (TCP/Socket)")               => "SOCKET",
    N("Printer on SMB/Windows 95/98/NT server")     => "SMB",
    N("Printer on NetWare server")                  => "NCP",
    N("Enter a printer device URI")                 => "URI",
    N("Pipe job into a command")                    => "POSTPIPE"
);

our %printer_type_inv = reverse %printer_type;

our %thedb;

#------------------------------------------------------------------------------

sub spooler {
    # LPD is taken from the menu for the moment because the classic LPD is
    # highly unsecure. Depending on how the GNU lpr development is going on
    # LPD support can be reactivated by uncommenting the following line.

    #return @spooler_inv{qw(cups lpd lprng pdq)};

    # LPRng is not officially supported any more since Mandrake 9.0, so
    # show it only in the spooler menu when it was manually installed.
    return map { $spoolers{$_}{long_name} } qw(cups pdq), if_(files_exist(qw(/usr/lib/filters/lpf /usr/sbin/lpd)), 'lprng');
}

sub printer_type($) {
    my ($printer) = @_;
    for ($printer->{SPOOLER}) {
	/cups/  && return @printer_type_inv{qw(LOCAL LPD SOCKET SMB), if_($::expert, qw(URI))};
	/lpd/   && return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP), if_($::expert, qw(POSTPIPE URI))};
	/lprng/ && return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP), if_($::expert, qw(POSTPIPE URI))};
	/pdq/   && return @printer_type_inv{qw(LOCAL LPD SOCKET), if_($::expert, qw(URI))};
    }
}

sub SIGHUP_daemon {
    my ($service) = @_;
    if ($service eq "cupsd") { $service = "cups" };
    # PDQ has no daemon, exit.
    if ($service eq "pdq") { return 1 };
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
    my ($result, $i);
    for ($i = 0; $i < 3; $i++) {
	local *F; 
	open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	    "/bin/sh -c \"export LC_ALL=C; /usr/sbin/lpinfo -v\" |" or
	    die "Could not run \"lpinfo\"!";
	while (my $line = <F>) {
	    if ($line =~ /$device/) { # Found a line containing the device
		                      # name, so CUPS knows it.
		close F;
		return 1;
	    }
	}
	close F;
	$result = SIGHUP_daemon("cups");
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
	local *F; 
	open F, "< $file" or return 0;
	while (my $line = <F>) {
	    if ($line =~ /^\s*$sp\s*$/) {
		close F;
		return 1;
	    }
	}
	close F;
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
    $printer->{ARGS} = "";
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
	foreach my $spooler (qw(cups pdq lprng lpd)) {
	    #- Is the spooler's daemon running?
	    my $service = $spooler;
	    if ($service eq "lprng") {
		$service = "lpd";
	    }
	    if ($service ne "pdq") {
		next unless services::is_service_running($service);
		# daemon is running, spooler found
		$printer->{SPOOLER} = $spooler;
	    }
	    #- poll queue info 
	    local *F; 
	    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
		"foomatic-configure -P -q -s $spooler |" or
		    die "Could not run foomatic-configure";
	    eval join('', <F>); 
	    close F;
	    if ($service eq "pdq") {
		#- Have we found queues? PDQ has no damon, so we consider
		#- it in use when there are defined printer queues
		if ($#QUEUES != -1) {
		    $printer->{SPOOLER} = $spooler;
		    last;
		}
	    } else {
		#- For other spoolers we have already found a running
		#- daemon when we have arrived here
		last;
	    }
	}
    } else {
	#- Poll the queues of the current default spooler
	local *F; 
	open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	    "foomatic-configure -P -q -s $printer->{SPOOLER} |" or
		die "Could not run foomatic-configure";
	eval join('', <F>); 
	close F;
    }
    $printer->{configured} = {};
    my $i;
    my $N = $#QUEUES + 1;
    for ($i = 0;  $i < $N; $i++) {
	$printer->{configured}{$QUEUES[$i]{queuedata}{queue}} = 
	    $QUEUES[$i];
	if (!$QUEUES[$i]{make} || !$QUEUES[$i]{model}) {
	    if ($printer->{SPOOLER} eq "cups") {
		$printer->{OLD_QUEUE} = $QUEUES[$i]{queuedata}{queue};
		my $descr = get_descr_from_ppd($printer);
		$descr =~ m/^([^\|]*)\|([^\|]*)(\|.*|)$/;
		$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{make} ||= $1;
		$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{model} ||= $2;
		# Read out which PPD file was originally used to set up this
		# queue
		local *F;
		if (open F, "< $::prefix/etc/cups/ppd/$QUEUES[$i]{queuedata}{queue}.ppd") {
		    while (my $line = <F>) {
			if ($line =~ /^\*%MDKMODELCHOICE:(.+)$/) {
			    $printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd} = $1;
			}
		    }
		    close F;
		}
		# Mark that we have a CUPS queue but do not know the name
		# the PPD file in /usr/share/cups/model
		if (!$printer->{configured}{$QUEUES[$i]{queuedata}{queue}}{queuedata}{ppd}) {
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
	    foreach my $arg (@{$args}) {
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
    my $localremote;
    if ($connect =~ m!^(file|parallel|usb|serial):! || 
	$connect =~ m!^ptal:/mlc:! ||
	$connect =~ m!^mtink:!) {
	$localremote = N("Local Printers");
    } else {
	$localremote = N("Remote Printers");
    }
    my $make = $printer->{configured}{$queue}{queuedata}{make};
    my $model = $printer->{configured}{$queue}{queuedata}{model};
    my $connection;
    if ($connect =~ m!^(file|parallel):/dev/lp(\d+)$!) {
	my $number = $2;
	$connection = N(" on parallel port \#%s", $number);
    } elsif ($connect =~ m!^(file|usb):/dev/usb/lp(\d+)$!) {
	my $number = $2;
	$connection = N(", USB printer \#%s", $number);
    } elsif ($connect =~ m!^usb://!) {
	$connection = N(", USB printer");
    } elsif ($connect =~ m!^ptal:/(.+)$!) {
	my $ptaldevice = $1;
	if ($ptaldevice =~ /^mlc:par:(\d+)$/) {
	    my $number = $1;
	    $connection = N(", multi-function device on parallel port \#%s",
			    $number);
	} elsif ($ptaldevice =~ /^mlc:usb:/) {
	    $connection = N(", multi-function device on USB");
	} elsif ($ptaldevice =~ /^hpjd:/) {
	    $connection = N(", multi-function device on HP JetDirect");
	} else {
	    $connection = N(", multi-function device");
	}
    } elsif ($connect =~ m!^file:(.+)$!) {
	$connection = N(", printing to %s", $1);
    } elsif ($connect =~ m!^lpd://([^/]+)/([^/]+)/?$!) {
	$connection = N(" on LPD server \"%s\", printer \"%s\"", $2, $1);
    } elsif ($connect =~ m!^socket://([^/:]+):([^/:]+)/?$!) {
	$connection = N(", TCP/IP host \"%s\", port %s", $1, $2);
    } elsif ($connect =~ m!^smb://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^smb://.*\@([^/\@]+)/([^/\@]+)/?$!) {
	$connection = N(" on SMB/Windows server \"%s\", share \"%s\"", $1, $2);
    } elsif ($connect =~ m!^ncp://([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*/([^/\@]+)/([^/\@]+)/?$! ||
	     $connect =~ m!^ncp://.*\@([^/\@]+)/([^/\@]+)/?$!) {
	$connection = N(" on Novell server \"%s\", printer \"%s\"", $1, $2);
    } elsif ($connect =~ m!^postpipe:(.+)$!) {
	$connection = N(", using command %s", $1);
    } else {
	$connection = ($::expert ? ", URI: $connect" : "");
    }
    my $sep = "!";
    $printer->{configured}{$queue}{queuedata}{menuentry} = 
	($::expert ? "$spooler$sep" : "") .
	"$localremote$sep$queue: $make $model$connection";
}

sub read_printer_db(;$) {

    my $spooler = $_[0];

    my $dbpath = $::prefix . $PRINTER_DB_FILE;

    local *DBPATH; #- don't have to do close ... and don't modify globals at least
    # Generate the Foomatic printer/driver overview, read it from the
    # appropriate file when it is already generated
    if (!(-f $dbpath)) {
	open DBPATH, ($::testing ? $::prefix : "chroot $::prefix/ ") . #-#
	    "foomatic-configure -O -q |" or
		die "Could not run foomatic-configure";
    } else {
	open DBPATH, $dbpath or die "An error occurred on $dbpath : $!"; #-#
    }

    my $entry = {};
    my $inentry = 0;
    my $indrivers = 0;
    my $inautodetect = 0;
    my $autodetecttype = "";
    local $_;
    while (<DBPATH>) {
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
	    } elsif ($inautodetect) {
		# We are inside the autodetect block of a printers entry
		# All entries inside this block will be ignored
		if ($autodetecttype) {
		    if (m!^.*</$autodetecttype>\s*$!) {
			# End of parallel, USB, or SNMP section
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
		    }
		} else {
		    if (m!^.*</autodetect>\s*$!) {
			# End of autodetect block
			$inautodetect = 0;
		    } elsif (m!^\s*<(parallel|usb|snmp)>\s*$!) {
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
		    if ($::expert) {
			foreach my $driver (@{$entry->{drivers}}) {
			    my $driverstr;
			    if ($driver eq "Postscript") {
				$driverstr = "PostScript";
			    } else {
				$driverstr = "GhostScript + $driver";
			    }
			    if ($driver eq $entry->{defaultdriver}) {
				$driverstr .= " (recommended)";
			    }
			    $entry->{ENTRY} = "$entry->{make}|$entry->{model}|$driverstr";
			    $entry->{ENTRY} =~ s/^CITOH/C.ITOH/i;
			    $entry->{ENTRY} =~ 
				s/^KYOCERA[\s\-]*MITA/KYOCERA/i;
			    $entry->{driver} = $driver;
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
			    $entry->{driver} = $entry->{defaultdriver};
			    map { $thedb{$entry->{ENTRY}}{$_} = $entry->{$_} } keys %$entry;
			}
		    }
		    $entry = {};
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
		    @{$entry->{drivers}} = (); 
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
    close DBPATH;

    # Add raw queue
    if ($spooler ne "pdq") {
	$entry->{ENTRY} = N("Raw printer (No driver)");
	$entry->{driver} = "raw";
	$entry->{make} = "";
	$entry->{model} = N("Unknown model");
	map { $thedb{$entry->{ENTRY}}{$_} = $entry->{$_} } keys %$entry;
    }

    #- Load CUPS driver database if CUPS is used as spooler
    if ($spooler && $spooler eq "cups") {
        poll_ppd_base();
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
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -P -q -p $printer->{currentqueue}{printer}" .
	" -d $printer->{currentqueue}{driver}" . 
	($printer->{OLD_QUEUE} ?
	 " -s $printer->{SPOOLER} -n $printer->{OLD_QUEUE}" : "") .
	 ($printer->{SPECIAL_OPTIONS} ?
	  " $printer->{SPECIAL_OPTIONS}" : "") 
	 . " |" or
	 die "Could not run foomatic-configure";
    eval join('', (<F>)); 
    close F;
    # Return the arguments field
    return $COMBODATA->{args};
}

sub read_ppd_options ($) {
    my ($printer) = @_;
    # Generate the option data for a given PPD file
    my $COMBODATA;
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"foomatic-configure -P -q" .
	" --ppd /usr/share/cups/model/$printer->{currentqueue}{ppd}" .
	($printer->{OLD_QUEUE} ?
	 " -s $printer->{SPOOLER} -n $printer->{OLD_QUEUE}" : "") .
	 ($printer->{SPECIAL_OPTIONS} ?
	  " $printer->{SPECIAL_OPTIONS}" : "") 
		    . " |" or
	    die "Could not run foomatic-configure";
    eval join('', (<F>)); 
    close F;
    # Return the arguments field
    return $COMBODATA->{args};
}

sub set_cups_special_options {
    my ($queue) = $_[0];
    # Set some special CUPS options
    my @lpoptions = chomp_(cat_("$::prefix/etc/cups/lpoptions"));
    # If nothing is already configured, set text file borders of half an inch
    # and decrease the font size a little bit, so nothing of the text gets
    # cut off by unprintable borders.
    if (!any { /$queue.*\s(page-(top|bottom|left|right)|lpi|cpi)=/ } @lpoptions) {
	run_program::rooted($::prefix, "lpoptions",
			    "-p", $queue,
			    "-o", "page-top=36", "-o", "page-bottom=36",
			    "-o", "page-left=36", "-o page-right=36",
			    "-o", "cpi=12", "-o", "lpi=7", "-o", "wrap");
    }
    # Let images fill the whole page by default
    if (!any { /$queue.*\s(scaling|natural-scaling|ppi)=/ } @lpoptions) {
	run_program::rooted($::prefix, "lpoptions",
			    "-p", $queue,
			    "-o", "scaling=100");
    }
    return 1;
}

sub set_cups_autoconf {
    my $autoconf = $_[0];

    # Read config file
    my $file = "$::prefix/etc/sysconfig/printing";
    my @file_content = cat_($file);

    # Remove all valid "CUPS_CONFIG" lines
    /^\s*CUPS_CONFIG/ and $_ = "" foreach @file_content;
 
    # Insert the new "CUPS_CONFIG" line
    if ($autoconf) {
	push @file_content, "CUPS_CONFIG=automatic\n";
    } else {
	push @file_content, "CUPS_CONFIG=manual\n";
    }

    output($file, @file_content);

    # Restart CUPS
    if ($autoconf) {
	printer::services::restart("cups");
    }

    return 1;
}

sub get_cups_autoconf {
    local *F;
    open F, "< $::prefix/etc/sysconfig/printing" or return 1;
    while (my $line = <F>) {
	return 0 if $line =~ m!^[^\#]*CUPS_CONFIG=manual!;
    }
    return 1;
}

sub set_usermode {
    my $usermode = $_[0];
    $::expert = $usermode;

    # Read config file
    local *F;
    my $file = "$::prefix/etc/sysconfig/printing";
    my @file_content;
    if (!(-f $file)) {
	@file_content = ();
    } else {
	open F, "< $file" or die "Cannot open $file for reading!";
	@file_content = <F>;
	close F;
    }

    # Remove all valid "USER_MODE" lines
    (/^\s*USER_MODE/ and $_ = "") foreach @file_content;
 
    # Insert the new "USER_MODE" line
    if ($usermode) {
	push @file_content, "USER_MODE=expert\n";
    } else {
	push @file_content, "USER_MODE=recommended\n";
    }

    # Write back modified file
    open F, "> $file" or die "Cannot open $file for writing!";
    print F @file_content;
    close F;

    return 1;
}

sub get_usermode {
    my %cfg = getVarsFromSh("$::prefix/etc/sysconfig/printing");
    $::expert = $cfg{USER_MODE} eq 'expert' ? 1 : 0;
    return $::expert;
}

#----------------------------------------------------------------------
# Handling of /etc/cups/cupsd.conf

sub read_cupsd_conf {
    cat_("$::prefix/etc/cups/cupsd.conf");
}
sub write_cupsd_conf {
    my (@cupsd_conf) = @_;

    output("$::prefix/etc/cups/cupsd.conf", @cupsd_conf);

    #- restart cups after updating configuration.
    printer::services::restart("cups");
}

sub read_directives {

    # Read one or more occurences of a directive from the cupsd.conf file 
    # or from a ripped-out location block

    my ($lines_ptr, $directive) = @_;

    my @result = ();
    ($_ =~ /^\s*$directive\s+(\S.*)$/ and push(@result, $1)) 
	foreach @{$lines_ptr};
    (chomp) foreach @result;
    return @result;
}

sub read_unique_directive {

    # Read a directive from the from the cupsd.conf file or from a
    # ripped-out location block, if the directive appears more than once,
    # use the last occurence and remove all the others, if it does not
    # occur, return the default value

    my ($lines_ptr, $directive, $default) = @_;

    if ((my @d = read_directives($lines_ptr, $directive)) > 0) {
	my $value = @d[$#d];
	set_directive($lines_ptr, "$directive $value");
	return $value;
    } else {
        return $default;
    }
}

sub insert_directive {

    # Insert a directive into the cupsd.conf file or into a ripped-out
    # location block (but only if it is not already there)

    my ($lines_ptr, $directive) = @_;

    ($_ =~ /^\s*$directive$/ and return 0) foreach @{$lines_ptr};
    splice(@{$lines_ptr}, -1, 0, "$directive\n");
    return 1;
}

sub remove_directive {

    # Remove a directive from the cupsd.conf file or from a ripped-out
    # location block

    my ($lines_ptr, $directive) = @_;

    my $success = 0;
    ($_ =~ /^\s*$directive/ and $_ = "" and $success = 1)
	foreach @{$lines_ptr};
    return $success;
}

sub replace_directive {

    # Replace a directive in the cupsd.conf file or from a ripped-out
    # location block, if the directive appears more than once, remove
    # the additional occurences

    my ($lines_ptr, $olddirective, $newdirective) = @_;

    $newdirective = "$newdirective\n";
    my $success = 0;
    ($_ =~ /^\s*$olddirective/ and $_ = $newdirective and 
     $success = 1 and $newdirective = "") foreach @{$lines_ptr};
    return $success;
}

sub set_directive {

    # Set a directive in the cupsd.conf, replace the old definition or
    # a commented definition

    my ($cupsd_conf_ptr, $directive) = @_;

    my $olddirective = $directive;
    $olddirective =~ s/^\s*(\S+)\s+.*$/$1/s;

    return (replace_directive($cupsd_conf_ptr, $olddirective,
			      $directive) or
	    replace_directive($cupsd_conf_ptr, "\#$olddirective", 
			      $directive) or 
	    insert_directive($cupsd_conf_ptr, $directive));
}

sub read_location {

    # Return the lines inside the [path] location block
    #
    #   <Location [path]>
    #   ...
    #   </Location>

    my ($cupsd_conf_ptr, $path) = @_;

    my @result = ();
    if (grep(m!^\s*<Location\s+$path\s*>!, @{$cupsd_conf_ptr})) {
	my $location_start = -1;
	my $location_end = -1;
	# Go through all the lines, bail out when start and end line found
	for (my $i = 0; 
	     ($i <= $#{$cupsd_conf_ptr}) and ($location_end == -1);
	     $i++) {
	    if ($cupsd_conf_ptr->[$i] =~ m!^\s*<\s*Location\s+$path\s*>!) {
		# Start line of block
		$location_start = $i;
	    } elsif (($cupsd_conf_ptr->[$i] =~ 
		      m!^\s*<\s*/Location\s*>!) and
		     ($location_start != -1)) {
		# End line of block
		$location_end = $i;
		last;
	    } elsif (($location_start >= 0) and ($location_end < 0)) {
		# Inside the location block
		push(@result, $cupsd_conf_ptr->[$i]);
	    }
	}
    } else {
	# If there is no root location block, set the result array to
	# "undef"
	@result = undef;
    }
    return (@result);
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

    my @location = ();
    my $location_start = -1;
    my $location_end = -1;
    if (grep(m!^\s*<Location\s+$path\s*>!, @{$cupsd_conf_ptr})) {
	# Go through all the lines, bail out when start and end line found
	for (my $i = 0; 
	     ($i <= $#{$cupsd_conf_ptr}) and ($location_end == -1);
	     $i++) {
	    if ($cupsd_conf_ptr->[$i] =~ m!^\s*<\s*Location\s+$path\s*>!) {
		# Start line of block
		$location_start = $i;
	    } elsif (($cupsd_conf_ptr->[$i] =~ 
		      m!^\s*<\s*/Location\s*>!) and
		     ($location_start != -1)) {
		# End line of block
		$location_end = $i;
		last;
	    }
	}
	# Rip out the block and store it seperately
	@location = 
	    splice(@{$cupsd_conf_ptr},$location_start,
		   $location_end - $location_start + 1);
    } else {
	# If there is no location block, create one
	$location_start = $#{$cupsd_conf_ptr} + 1;
	@location = ();
	push @location, "<Location $path>\n";
	push @location, "</Location>\n";
    }

    return ($location_start, @location);
}

sub insert_location {

    # Re-insert a location block ripped with "rip_location"

    my ($cupsd_conf_ptr, $location_start, @location) = @_;

    splice(@{$cupsd_conf_ptr}, $location_start,0,@location);
}

sub add_to_location {

    # Add a directive to a given location (only if it is not already there)

    my ($cupsd_conf_ptr, $path, $directive) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = insert_directive(\@location, $directive);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub remove_from_location {

    # Remove a directive from a given location

    my ($cupsd_conf_ptr, $path, $directive) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = remove_directive(\@location, $directive);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub replace_in_location {

    # Replace a directive in a given location

    my ($cupsd_conf_ptr, $path, $olddirective, $newdirective) = @_;

    my ($location_start, @location) = rip_location($cupsd_conf_ptr, $path);
    my $success = replace_directive(\@location, $olddirective, 
				    $newdirective);
    insert_location($cupsd_conf_ptr, $location_start, @location);
    return $success;
}

sub add_allowed_host {

    # Add a host or network which should get access to the local printer(s)
    my ($cupsd_conf_ptr, $host) = @_;
    
    return (insert_directive($cupsd_conf_ptr, "BrowseAddress $host") and
	    add_to_location($cupsd_conf_ptr, "/", "Allow From $host"));
}

sub remove_allowed_host {

    # Remove a host or network which should get access to the local 
    # printer(s)
    my ($cupsd_conf_ptr, $host) = @_;
    
    return (remove_directive($cupsd_conf_ptr, "BrowseAddress $host") and
	    remove_from_location($cupsd_conf_ptr, "/", "Allow From $host"));
}

sub replace_allowed_host {

    # Remove a host or network which should get access to the local 
    # printer(s)
    my ($cupsd_conf_ptr, $oldhost, $newhost) = @_;
    
    return (replace_directive($cupsd_conf_ptr, "BrowseAddress $oldhost",
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
    } elsif ($address =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/) {
	my $numadr = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
	my $mask = ((1 << $5) - 1) << (32 - $5);
	my $broadcast = $numadr | (~$mask);
	$address =
	    (($broadcast & (255 << 24)) >> 24) . '.' .
	    (($broadcast & (255 << 16)) >> 16) . '.' .
	    (($broadcast & (255 << 8)) >> 8) . '.' .
	    ($broadcast & 255);
    } elsif ($address =~
	     /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
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
	while ($address =~ s/\.255$//) {};
	$address .= ".*";
    }
 
    return $address;
}

sub localprintersshared {

    # Do we broadcast our local printers

    my ($printer) = @_;

    return (($printer->{cupsconfig}{keys}{Browsing} !~ /off/i) &&
	    ($printer->{cupsconfig}{keys}{BrowseInterval} != 0) &&
	    ($#{$printer->{cupsconfig}{keys}{BrowseAddress}} >= 0));
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
	(join('', @{$printer->{cupsconfig}{keys}{BrowseDeny}}) =~
	 /All/im);
    my $havedenylocal = 
	(join('', @{$printer->{cupsconfig}{keys}{BrowseDeny}}) =~
	 /\@LOCAL/im);
    my $orderallowdeny =
	($printer->{cupsconfig}{keys}{BrowseOrder} =~
	 /allow\s*,\s*deny/i);
    my $haveallowremote = 0;
    for my $allowline (@{$printer->{cupsconfig}{keys}{BrowseAllow}}) {
	next if 
	    ($allowline =~ /^\s*(localhost|0*127\.0+\.0+\.0*1|none)\s*$/i);
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
	 /All/im);

    # Check for "Order Deny,Allow"
    my $orderdenyallow =
	($printer->{cupsconfig}{root}{Order} =~
	 /deny\s*,\s*allow/i);
    
    my @sharehosts;
    my $haveallowfromlocalhost = 0;
    my $haveallowedhostwithoutbrowseaddress = 0;

    # Go through all "Allow From" lines
    for my $line (@{$printer->{cupsconfig}{root}{AllowFrom}}) {
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
	}
    }
    my $havebrowseaddresswithoutallowedhost = 0;
    # Go through all "BrowseAdress" lines
    for my $line (@{$printer->{cupsconfig}{keys}{BrowseAddress}}) {
	if ($line =~ /^\s*(localhost|0*127\.0+\.0+\.0*1)\s*$/i) {
	    # Skip lines pointing to localhost
	} elsif ($line =~ /^\s*(none)\s*$/i) {
	    # Skip "Allow From None" lines
	} elsif (!member($line, map {broadcastaddress($_)} @sharehosts)) {
	    # Line pointing to remote server
	    push(@sharehosts, networkaddress($line));
	    $havebrowseaddresswithoutallowedhost = 1;
	}
    }

    my $configunsupported = (!$havedenyfromall || !$orderdenyallow ||
			     !$haveallowfromlocalhost ||
			     $haveallowedhostwithoutbrowseaddress ||
			     $havebrowseaddresswithoutallowedhost);

    return ($configunsupported, @sharehosts);
}

sub makesharehostlist {

    # Human-readable strings for hosts onto which the local printers
    # are shared

    my ($printer) = @_;

    my @sharehostlist; 
    my %sharehosthash;
    for my $host (@{$printer->{cupsconfig}{clientnetworks}}) {
	if ($host =~ /\@LOCAL/i) {
	    $sharehosthash{$host} = N("Local network(s)");
	} elsif ($host =~ /\@IF\((.*)\)/i) {
	    $sharehosthash{$host} = N("Interface \"%s\"", $1);
	} elsif ($host =~ /(\/|^\*|\*$|^\.)/i) {
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

sub is_network_ip {

    # Determine whwther the given string is a valid network IP

    my ($address) = @_;

    ($address =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) ||
	($address =~ /^(\d+\.){1,3}\*$/) ||
	($address =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/) ||
	($address =~
	 /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

}

sub read_cups_config {
    
    # Read the information relevant to the printer sharing dialog from
    # the CUPS configuration

    my ($printer) = @_;

    # From /etc/cups/cupsd.conf

    # Keyword "Browsing" 
    $printer->{cupsconfig}{keys}{Browsing} =
	read_unique_directive($printer->{cupsconfig}{cupsd_conf},
			      'Browsing', 'On');

    # Keyword "BrowseInterval" 
    $printer->{cupsconfig}{keys}{BrowseInterval} =
	read_unique_directive($printer->{cupsconfig}{cupsd_conf},
			      'BrowseInterval', '30');

    # Keyword "BrowseAddress" 
    @{$printer->{cupsconfig}{keys}{BrowseAddress}} =
	read_directives($printer->{cupsconfig}{cupsd_conf},
			'BrowseAddress');

    # Keyword "BrowseAllow" 
    @{$printer->{cupsconfig}{keys}{BrowseAllow}} =
	read_directives($printer->{cupsconfig}{cupsd_conf},
			'BrowseAllow');

    # Keyword "BrowseDeny" 
    @{$printer->{cupsconfig}{keys}{BrowseDeny}} =
	read_directives($printer->{cupsconfig}{cupsd_conf},
			'BrowseDeny');

    # Keyword "BrowseOrder" 
    $printer->{cupsconfig}{keys}{BrowseOrder} =
	read_unique_directive($printer->{cupsconfig}{cupsd_conf},
			      'BrowseOrder', 'deny,allow');

    # Root location
    @{$printer->{cupsconfig}{rootlocation}} =
	read_location($printer->{cupsconfig}{cupsd_conf}, '/');

    # Keyword "Allow from" 
    @{$printer->{cupsconfig}{root}{AllowFrom}} =
	read_directives($printer->{cupsconfig}{rootlocation},
			'Allow From');

    # Keyword "Deny from" 
    @{$printer->{cupsconfig}{root}{DenyFrom}} =
	read_directives($printer->{cupsconfig}{rootlocation},
			'Deny From');

    # Keyword "Order" 
    $printer->{cupsconfig}{root}{Order} =
	read_unique_directive($printer->{cupsconfig}{rootlocation},
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
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'Browsing On');
	if ($printer->{cupsconfig}{keys}{BrowseInterval} == 0) {
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseInterval 30');
	}  
    } else {
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'BrowseInterval 0');
    }

    # This machine is accepting printers shared by remote machines?
    if ($printer->{cupsconfig}{remotebroadcastsaccepted}) {
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'Browsing On');
	if (($printer->{cupsconfig}{localprintersshared}) &&
	    ($#{$printer->{cupsconfig}{clientnetworks}} > 0) &&
	    (!$printer->{cupsconfig}{customsharingsetup})) {
	    # If we broadcast our printers, let's accept the broadcasts
	    # from the machines to which we broadcast
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseDeny All');
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseOrder Deny,Allow');
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseAllow ' .
			  join ("\nBrowseAllow ", 
				@{$printer->{cupsconfig}{clientnetworks}}));
	} elsif (!remotebroadcastsaccepted($printer)) {
	    # Use default settings if the "BrowseDeny"/"BrowseAllow"
	    # configuration does not accept broadcasts
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseDeny All');
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseOrder Deny,Allow');
	    set_directive($printer->{cupsconfig}{cupsd_conf},
			  'BrowseOrder @LOCAL');
	}
    } else {
	# Deny all broadcasts, but leave all "BrowseAllow" lines
	# untouched
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'BrowseDeny All');
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'BrowseOrder Allow,Deny');
    }

    # To which machines are the local printers available?
    if (!$printer->{cupsconfig}{customsharingsetup}) {
	# root location block
	@{$printer->{cupsconfig}{rootlocation}} =
	    "<Location />\n" .
	    "Order Deny,Allow\n" .
	    "Deny From All\n" .
	    "Allow From 127.0.0.1\n" .
	    "Allow From " .
	    join ("\nAllow From ", 
		  @{$printer->{cupsconfig}{clientnetworks}}) .
	    "\n" .
	    "</Location>\n";
	my ($location_start, @location) = 
	    rip_location($printer->{cupsconfig}{cupsd_conf}, "/");
	insert_location($printer->{cupsconfig}{cupsd_conf}, $location_start,
			@{$printer->{cupsconfig}{rootlocation}});
	# "BrowseAddress" lines
	set_directive($printer->{cupsconfig}{cupsd_conf},
		      'BrowseAddress ' .
		      join ("\nBrowseAddress ",
			    map {broadcastaddress($_)}
			    @{$printer->{cupsconfig}{clientnetworks}}));
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
    local *PRINTERS; open PRINTERS, "$::prefix/etc/cups/printers.conf" or return;
    local $_;
    while (<PRINTERS>) {
	chomp;
	/^\s*#/ and next;
	if (/^\s*<(?:DefaultPrinter|Printer)\s+([^>]*)>/) { $current = { mode => 'cups', QUEUE => $1, } }
	elsif (/\s*<\/Printer>/) { $current->{QUEUE} && $current->{DeviceURI} or next; #- minimal check of synthax.
				   add2hash($printer->{configured}{$current->{QUEUE}} ||= {}, $current); $current = undef }
	elsif (/\s*(\S*)\s+(.*)/) { $current->{$1} = $2 }
    }
    close PRINTERS;

    #- assume this printing system.
    $printer->{SPOOLER} ||= 'cups';
}

sub get_direct_uri {
    #- get the local printer to access via a Device URI.
    my @direct_uri;
    local *F; open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/sbin/lpinfo -v |";
    local $_;
    while (<F>) {
	/^(direct|usb|serial)\s+(\S*)/ and push @direct_uri, $2;
    }
    close F;
    @direct_uri;
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
    $make =~ s/^OKI(|[\s\-]*DATA)/OKIDATA/i;
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
    return $make;
}    

sub ppd_entry_str {
    my ($mf, $descr, $lang) = @_;
    my ($model, $driver);
    if ($descr) {
	# Apply the beautifying rules of poll_ppd_base
	if ($descr =~ /Foomatic \+ Postscript/) {
	    $descr =~ s/Foomatic \+ Postscript/PostScript/;
	} elsif ($descr =~ /Foomatic/) {
	    $descr =~ s/Foomatic/GhostScript/;
	} elsif ($descr =~ /CUPS\+GIMP-print/) {
	    $descr =~ s/CUPS\+GIMP-print/CUPS \+ GIMP-Print/;
	} elsif ($descr =~ /Series CUPS/) {
	    $descr =~ s/Series CUPS/Series, CUPS/;
	} elsif ($descr !~ /(PostScript|GhostScript|CUPS|Foomatic)/i) {
	    $descr .= ", PostScript";
	}
	# Split model and driver
	$descr =~ s/\s*Series//i;
	$descr =~ s/\((.*?(PostScript|PS.*).*?)\)/$1/i;
	if (($descr =~
	     /^\s*(Generic\s*PostScript\s*Printer)\s*,?\s*(.*)$/i) ||
	    ($descr =~
	     /^\s*(PostScript\s*Printer)\s*,?\s*(.*)$/i) ||
	    ($descr =~ /^([^,]+[^,\s])\s*(\(v?\d\d\d\d\.\d\d\d\).*)$/i) ||
	    ($descr =~ /^([^,]+[^,\s])\s+(PS.*)$/i) ||
	    ($descr =~ /^([^,]+[^,\s])\s*(PostScript.*)$/i) ||
	    ($descr =~ /^([^,]+[^,\s])\s*(v\d+\.\d+.*)$/i) ||
	    ($descr =~ /^([^,]+),\s*(.+)$/)) {
	    $model = $1;
	    $driver = $2;
	    $model =~ s/[\-\s,]+$//;
	    $driver =~ s/\b(PS|PostScript\b)/PostScript/gi;
	    $driver =~ s/(PostScript)(.*)(PostScript)/$1$2/i;
	    $driver =~ 
	      s/^\s*(\(v?\d\d\d\d\.\d\d\d\)|v\d+\.\d+)([,\s]*)(.*)/$3$2$1/i;
	    $driver =~ s/,\s*\(/ \(/g;
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
	    $driver = "PostScript";
	}
    }
    # Remove manufacturer's name from the beginning of the model
    # name (do not do this with manufacturer names which contain
    # odd characters)
    $model =~ s/^$mf[\s\-]+//i 
	if ($mf and ($mf !~ /[\\\/\(\)\[\]\|\.\$\@\%\*\?]/));
    # Clean some manufacturer's names
    $mf = clean_manufacturer_name($mf);
    # Rename Canon "BJC XXXX" models into "BJC-XXXX" so that the 
    # models do not appear twice
    if ($mf eq "CANON") {
	$model =~ s/BJC\s+/BJC-/;
    }
    # New MF devices from Epson have mis-spelled name in PPD files for
    # native CUPS drivers of GIMP-Print
    if ($mf eq "EPSON") {
	$model =~ s/Stylus CX\-/Stylus CX/;
    }
    # Try again to remove manufacturer's name from the beginning of the 
    # model name, this with the cleaned manufacturer name
    $model =~ s/^$mf[\s\-]+//i 
	if ($mf and ($mf !~ /[\\\/\(\)\[\]\|\.\$\@\%\*\?]/));
    # Put out the resulting description string
    uc($mf) . '|' . $model . '|' . $driver .
      ($lang && " (" . lc(substr($lang, 0, 2)) . ")");
}

sub get_descr_from_ppd {
    my ($printer) = @_;
    my %ppd;

    #- if there is no ppd, this means this is a raw queue.
    if (! -r "$::prefix/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd") {
	return "|" . N("Unknown model");
    }
    eval {
	local $_;
	foreach (cat_("$::prefix/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd")) {
	    # "OTHERS|Generic PostScript printer|PostScript (en)";
	    /^\*([^\s:]*)\s*:\s*\"([^\"]*)\"/ and
		do { $ppd{$1} = $2; next };
	    /^\*([^\s:]*)\s*:\s*([^\s\"]*)/   and
		do { $ppd{$1} = $2; next };
	}
    };
    my $descr = ($ppd{NickName} || $ppd{ShortNickName} || $ppd{ModelName});
    my $make = $ppd{Manufacturer};
    my $lang = $ppd{LanguageVersion};
    my $entry = ppd_entry_str($make, $descr, $lang);
    if (!$::expert) {
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
	@content = cat_("$::prefix/bin/zcat $ppd |") or return ("", "");
    } else {
	@content = cat_($ppd) or return ("", "");
    }
    my ($devidmake, $devidmodel);
    ($_ =~ /^\*Manufacturer:\s*\"(.*)\"\s*$/ and $devidmake = $1) 
	foreach @content;
    ($_ =~ /^\*Product:\s*\"\(?(.*?)\)?\"\s*$/ and $devidmodel = $1) 
	foreach @content;
    return ($devidmake, $devidmodel);
}

sub poll_ppd_base {
    #- Before trying to poll the ppd database available to cups, we have 
    #- to make sure the file /etc/cups/ppds.dat is no more modified.
    #- If cups continue to modify it (because it reads the ppd files 
    #- available), the poll_ppd_base program simply cores :-)
    # else cups will not be happy! and ifup lo don't run ?
    run_program::rooted($::prefix, "ifconfig lo 127.0.0.1");
    printer::services::start_not_running_service("cups");
    my $driversthere = scalar(keys %thedb);
    foreach (1..60) {
	local *PPDS; open PPDS, ($::testing ? $::prefix :
				 "chroot $::prefix/ ") . 
				 "/usr/bin/poll_ppd_base -a |";
	local $_;
	while (<PPDS>) {
	    chomp;
	    my ($ppd, $mf, $descr, $lang) = split /\|/;
	    if ($ppd eq "raw") { next }
	    $ppd && $mf && $descr and do {
		my $key = ppd_entry_str($mf, $descr, $lang);
		$key =~ /^[^\|]+\|([^\|]+)\|(.*)$/;
		my ($model, $driver) = ($1, $2);
		# Clean some manufacturer's names
		$mf = clean_manufacturer_name($mf);
		# Remove language tag
		$driver =~ s/\s*\([a-z]{2}(|_[A-Z]{2})\)\s*$//;
		# Recommended Foomatic PPD? Extract "(recommended)"
		my $isrecommended = 
		    ($driver =~ s/\s+\(recommended\)\s*$//i);
		# Remove trailing white space
		$driver =~ s/\s+$//;
		# For Foomatic: Driver with "GhostScript + "
		my $fullfoomaticdriver = $driver;
		# Foomatic PPD? Extract driver name
		my $isfoomatic = 
		    ($driver =~ s/^\s*(GhostScript|Foomatic)\s*\+\s*//i);
		# Foomatic PostScript driver?
		$isfoomatic ||= ($descr =~ /Foomatic/i);
		# Native CUPS?
		my $isnativecups = ($driver =~ /CUPS/i);
		# Native PostScript
		my $isnativeps = (!$isfoomatic and !$isnativecups);
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
		if (!$::expert) {
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
			next unless (lc($thedb{$key}{driver}) ne
				     lc($driver));
			next unless (($isnativeps &&
				      ($thedb{$key}{driver} =~ 
				       /^PostScript$/i)) ||
				     (($thedb{$key}{driver} ne "PPD") &&
				      $isrecommended) ||
				     (($thedb{$key}{driver} eq "PPD") &&
				      ($driver ne "PostScript") &&
				      $isrecommended));
			# Remove the old entry
			delete $thedb{$key};
		    }
		} elsif (((defined 
			   $thedb{"$mf|$model|$fullfoomaticdriver"}) ||
			  (defined 
			   $thedb{"$mf|$model|$fullfoomaticdriver (recommended)"})) && 
			 ($isfoomatic)) {
		    # Expert mode: There is already an entry for the
		    # same printer/driver combo produced by the
		    # Foomatic XML database, so do not make a second
		    # entry
		    next;
		} elsif (defined
			 $thedb{"$mf|$model|PostScript (recommended)"} &&
			 ($isnativeps)) {
		    # Expert mode: "Foomatic + Postscript" driver is
		    # recommended and this is a PostScript PPD? Make
		    # this PPD the recommended one
		    for (keys 
		         %{$thedb{"$mf|$model|PostScript (recommended)"}}) {
			$thedb{"$mf|$model|PostScript"}{$_} =
			  $thedb{"$mf|$model|PostScript (recommended)"}{$_};
		    }
		    delete
			$thedb{"$mf|$model|PostScript (recommended)"};
		    if (!$isrecommended) {
			$key .= " (recommended)";
		    }
		} elsif (($driver =~ /PostScript/i) &&
			 $isrecommended && $isfoomatic &&
			 (my @foundkeys = grep {
			     /^$mf\|$model\|/ && !/CUPS/i &&
			     $thedb{$_}{driver} eq "PPD" 
			 } keys %thedb)) {
		    # Expert mode: "Foomatic + Postscript" driver is
		    # recommended and there was a PostScript PPD? Make
		    # the PostScript PPD the recommended one
		    my $firstfound = $foundkeys[0];
		    if (!(grep {/\(recommended\)/} @foundkeys)) {
			# Do it only if none of the native PostScript
			# PPDs for this printer is already "recommended"
			for (keys %{$thedb{$firstfound}}) {
			    $thedb{"$firstfound (recommended)"}{$_} =
				$thedb{$firstfound}{$_};
			}
			delete $thedb{$firstfound};
		    }
		    $key =~ s/\s*\(recommended\)//;
		} elsif (($driver !~ /PostScript/i) &&
			 $isrecommended && $isfoomatic &&
			 (my @foundkeys = grep {
			     /^$mf\|$model\|.*\(recommended\)/ && 
			     !/CUPS/i && $thedb{$_}{driver} eq "PPD" 
			 } keys %thedb)) {
		    # Expert mode: Foomatic driver other than "Foomatic +
		    # Postscript" is recommended and there was a PostScript 
		    # PPD which was recommended? Make The Foomatic driver
		    # the recommended one
		    foreach my $sourcekey (@foundkeys) {
			# Remove the "recommended" tag
			my $destkey = $sourcekey;
			$destkey =~ s/\s+\(recommended\)\s*$//i;
			for (keys %{$thedb{$sourcekey}}) {
			    $thedb{$destkey}{$_} = $thedb{$sourcekey}{$_};
			}
			delete $thedb{$sourcekey};
		    }
		}
	        $thedb{$key}{ppd} = $ppd;
		$thedb{$key}{make} = $mf;
		$thedb{$key}{model} = $model;
		$thedb{$key}{driver} = $driver;
		# Get auto-detection data
		#my ($devidmake, $devidmodel) = ppd_devid_data($ppd);
		#$thedb{$key}{devidmake} = $devidmake;
		#$thedb{$key}{devidmodel} = $devidmodel;
	    }
	}
	close PPDS;
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
    run_program::rooted($::prefix, "foomatic-configure", "-q",
			"-s", $printer->{currentqueue}{spooler},
			"-n", $printer->{currentqueue}{queue},
			($printer->{currentqueue}{queue} ne 
			 $printer->{OLD_QUEUE} &&
			 $printer->{configured}{$printer->{OLD_QUEUE}} ?
			 ("-C", $printer->{OLD_QUEUE}) : ()),
			"-c", $printer->{currentqueue}{connect},
			($printer->{currentqueue}{foomatic} ?
			 ("-p", $printer->{currentqueue}{printer},
			  "-d", $printer->{currentqueue}{driver}) :
			 ($printer->{currentqueue}{ppd} ?
			  ("--ppd",
			   ($printer->{currentqueue}{ppd} !~ m!^/! ?
			    "/usr/share/cups/model/" : "") .
			   $printer->{currentqueue}{ppd}) :
			  ("-d", "raw"))),
			"-N", $printer->{currentqueue}{desc},
			"-L", $printer->{currentqueue}{loc},
			@{$printer->{currentqueue}{options}}
			) or return 0;;
    if ($printer->{currentqueue}{ppd}) {
	# Add a comment line containing the path of the used PPD file to the
	# end of the PPD file
	if ($printer->{currentqueue}{ppd} ne '1') {
	    append_to_file("$::prefix/etc/cups/ppd/$printer->{currentqueue}{queue}.ppd", "*%MDKMODELCHOICE:$printer->{currentqueue}{ppd}\n");
	}
    }	  

    # Make sure that queue is active
    if ($printer->{SPOOLER} ne "pdq") {
        run_program::rooted($::prefix, "foomatic-printjob",
			    "-s", $printer->{currentqueue}{spooler},
			    "-C", "up", $printer->{currentqueue}{queue});
    }

    # In case of CUPS set some more useful defaults for text and image 
    # printing
    if ($printer->{SPOOLER} eq "cups") {
	set_cups_special_options($printer->{currentqueue}{queue});
    }

    # Check whether a USB printer is configured and activate USB printing if so
    my $useUSB = 0;
    foreach (values %{$printer->{configured}}) {
	$useUSB ||= (($_->{queuedata}{connect} =~ /usb/i) || 
	    ($_->{DeviceURI} =~ /usb/i));
    }
    $useUSB ||= ($printer->{currentqueue}{connect} =~ /usb/i);
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
    # Clean up
    delete($printer->{ARGS});
    $printer->{OLD_CHOICE} = "";
    $printer->{ARGS} = {};
    $printer->{DBENTRY} = "";
    $printer->{currentqueue} = {};

    return 1;
}

sub remove_queue($$) {
    my ($printer) = $_[0];
    my ($queue) = $_[1];
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
    removeprinterfromapplications($printer, $queue);
}

sub restart_queue($) {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};

    # Restart the daemon(s)
    for ($printer->{SPOOLER}) {
	/cups/ && do {
	    #- restart cups.
	    printer::services::restart("cups");
	    last };
	/lpr|lprng/ && do {
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

    # Print the pages
    foreach (@pages) {
	my $page = $_;
	# Only text and PostScript can be printed directly with all spoolers,
	# images must be treated seperately
	if ($page =~ /\.jpg$/) {
	    if ($printer->{SPOOLER} ne "cups") {
		# Use "convert" from ImageMagick for non-CUPS spoolers
		system(($::testing ? $::prefix : "chroot $::prefix/ ") .
		       "/usr/bin/convert $page -page 427x654+100+65 PS:- | " .
		       ($::testing ? $::prefix : "chroot $::prefix/ ") .
		       "$lpr -s $printer->{SPOOLER} -P $queue");
	    } else {
		# Use CUPS's internal image converter with CUPS, tell it
		# to let the image occupy 90% of the page size (so nothing
		# gets cut off by unprintable borders)
		run_program::rooted($::prefix, $lpr, "-s", $printer->{SPOOLER},
				    "-P", $queue, "-o", "scaling=90", $page);
	    }		
	} else {
	    run_program::rooted($::prefix, $lpr, "-s", $printer->{SPOOLER},
				"-P", $queue, $page);
	}
    }
    sleep 5; #- allow lpr to send pages.
    # Check whether the job is queued
    local *F; 
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "$lpq -s $printer->{SPOOLER} -P $queue |";
    my @lpq_output =
	grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <F>;
    close F;
    @lpq_output;
}

sub help_output {
    my ($printer, $spooler) = @_;
    my $queue = $printer->{QUEUE};

    local *F; 
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . sprintf($spoolers{$spooler}{help}, $queue);
    my $helptext = join("", <F>);
    close F;
    $helptext = "Option list not available!\n" if $spooler eq 'lpq' && (!$helptext || $helptext eq "");
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

    my @queuelist;      #- here we will list all Foomatic-generated queues
    # Get queue list with foomatic-configure
    local *QUEUEOUTPUT;
    open QUEUEOUTPUT, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	    "foomatic-configure -Q -q -s $oldspooler |" or
		die "Could not run foomatic-configure";

    my $entry = {};
    my $inentry = 0;
    local $_;
    while (<QUEUEOUTPUT>) {
	chomp;
	if ($inentry) {
	    # We are inside a queue entry
	    if (m!^\s*</queue>\s*$!) {
		# entry completed
		$inentry = 0;
		if ($entry->{foomatic} && $entry->{spooler} eq $oldspooler) {
		    # Is the connection type supported by the new
		    # spooler?
		    if ($newspooler eq "cups" && $entry->{connect} =~ /^(file|ptal|lpd|socket|smb|ipp):/ ||
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
	    if (m!^\s*<queue\s+foomatic\s*=\s*\"?(\d+)\"?\s*spooler\s*=\s*\"?(\w+)\"?\s*>\s*$!) {
		# new entry
		$inentry = 1;
		$entry->{foomatic} = $1;
		$entry->{spooler} = $2;
	    }
	}
    }
    close QUEUEOUTPUT;
    
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
	set_cups_special_options($newqueue);
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
	if ($make and $model) {
	    $make =~ s/\%20/ /g;
	    $model =~ s/\%20/ /g;
	    $serial =~ s/\%20/ /g;
	    $make =~ s/Hewlett[-\s_]Packard/HP/;
	    $make =~ s/HEWLETT[-\s_]PACKARD/HP/;
	    foreach my $p (@autodetected) {
		next if (!$p->{val}{MANUFACTURER} or
			 ($p->{val}{MANUFACTURER} ne $make));
		next if (!$p->{val}{MODEL} or
			 ($p->{val}{MODEL} ne $model));
		next if ((!$p->{val}{SERIALNUMBER} and $serial) or
			 ($p->{val}{SERIALNUMBER} and !$serial) or
			 ($p->{val}{SERIALNUMBER} ne $serial));
		return $p;
	    }
	}
    } elsif ($uri =~ m!^ptal:/mlc:!) {
	# HP multi-function device (controlled by HPOJ)
	my $ptaldevice = $uri;
	$ptaldevice =~ s!^ptal:/mlc:!!;
	if ($ptaldevice =~ /^par:(\d+)$/) {
	    my $device = "/dev/lp$1";
	    foreach my $p (@autodetected) {
		next if (!$p->{port} or
			 ($p->{port} ne $device));
		return $p;
	    }
	} else {
	    $ptaldevice =~ /^usb:(.*)$/;
	    my $model = $1;
	    $model =~ s/_/ /g;
	    my $device = "";
	    foreach my $p (@autodetected) {
		next if (!$p->{val}{MODEL} or
			 ($p->{val}{MODEL} ne $model));
		return $p;
	    }
	}
    } elsif ($uri =~ m!^(socket|smb|file|parallel|usb|serial):/!) {
	# Local print-only device, Ethernet-(TCP/Socket)-connected printer, 
	# or printer on Windows server
	my $device = $uri;
	$device =~ s/^(file|parallel|usb|serial)://;
	foreach my $p (@autodetected) {
	    next if (!$p->{port} or
		     ($p->{port} ne $device));
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

sub configure_hpoj {
    my ($device, @autodetected) = @_;

    # Make the subroutines of /usr/sbin/ptal-init available
    # It's only necessary to read it at the first call of this subroutine,
    # the subroutine definitions stay valid after leaving this subroutine.
    if (!$ptalinitread) {
	local *PTALINIT;
	open PTALINIT, "$::prefix/usr/sbin/ptal-init" or do {
	    die "unable to open $::prefix/usr/sbin/ptal-init";
	};
	my @ptalinitfunctions; # subroutine definitions in /usr/sbin/ptal-init
	local $_;
	while (<PTALINIT>) {
	    if (m!sub main!) {
		last;
	    } elsif (m!^[^\#]!) {
		# Make the subroutines also working during installation
		if ($::isInstall) {
		    s!\$::prefix!\$hpoj_prefix!g;
		    s!prefix=\"/usr\"!prefix=\"$::prefix/usr\"!g;
		    s!etcPtal=\"/etc/ptal\"!etcPtal=\"$::prefix/etc/ptal\"!g;
		    s!varLock=\"/var/lock\"!varLock=\"$::prefix/var/lock\"!g;
		    s!varRunPrefix=\"/var/run\"!varRunPrefix=\"$::prefix/var/run\"!g;
		}
		push @ptalinitfunctions, $_;
	    }
	}
	close PTALINIT;

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
	     $device =~ /\/dev\/lp/ ||
	     $device =~ /printers/) {
	$bus = "par";
	$address_arg = printer::detect::parport_addr($device);
	$address_arg =~ /^\s*-base\s+(\S+)/;
	eval "$base_address = $1";
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
    my $devdata;
    foreach (@autodetected) {
	$device eq $_->{port} or next;
	$devdata = $_;
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
	# Check if the device is really an HP multi-function device
	if ($bus ne "hpjd") {
	    # Start ptal-mlcd daemon for locally connected devices
	    services::stop("hpoj");
	    run_program::rooted($::prefix, 
				"ptal-mlcd", "$bus:probe", "-device", 
				$device, split(' ',$address_arg));
	}
	$device_ok = 0;
	my $ptalprobedevice = $bus eq "hpjd" ? "hpjd:$hostname" : "mlc:$bus:probe";
	local *F;
	if (open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice |") {
	    my $devid = join("", <F>);
	    close F;
	    if ($devid) {
		$device_ok = 1;
          local *F;
		if (open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice -long -mdl 2>/dev/null |") {
		    $model_long = join("", <F>);
		    close F;
		    chomp $model_long;
		    # If SNMP or local port auto-detection failed but HPOJ
		    # auto-detection succeeded, fill in model name here.
		    if (!$_->{val}{MODEL} ||
			$_->{val}{MODEL} =~ /$searchunknown/i ||
			$_->{val}{MODEL} =~ /^\s*$/) {
			if ($model_long =~ /:([^:;]+);/) {
			    $_->{val}{MODEL} = $1;
			}
		    }
		}
		if (open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "/usr/bin/ptal-devid $ptalprobedevice -long -sern 2>/dev/null |") { #-#
		    $serialnumber_long = join("", <F>);
		    close F;
		    chomp $serialnumber_long;
		}
		$cardreader = 1 if printer::hpoj::cardReaderDetected($ptalprobedevice);
	    }
	}
	if ($bus ne "hpjd") {
	    # Stop ptal-mlcd daemon for locally connected devices
            local *F;
	    if (open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . "ps auxwww | grep \"ptal-mlcd $bus:probe\" | grep -v grep | ") {
		my $line = <F>;
		if ($line =~ /^\s*\S+\s+(\d+)\s+/) {
		    my $pid = $1;
		    kill 15, $pid;
		}
		close F;
	    }
	    printer::services::start("hpoj");
	}
	last;
    }
    # No, it is not an HP multi-function device.
    return "" if !$device_ok;

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
    local *CONFIG;
    open(CONFIG, "> $::prefix/etc/ptal/$ptaldevice") or
	die "Could not open /etc/ptal/$ptaldevice for writing!\n";

    # Write file header.
    my $date = chomp_(`date`);
    print CONFIG
	"# Added $date by \"printerdrake\".\n" .
	"\n" .
	"# The basic format for this file is \"key[+]=value\".\n" .
	"# If you say \"+=\" instead of \"=\", then the value is appended to any\n" .
	"# value already defined for this key, rather than replacing it.\n" .
	"\n" .
	"# Comments must start at the beginning of the line.  Otherwise, they may\n" .
	"# be interpreted as being part of the value.\n" .
	"\n" .
	"# If you have multiple devices and want to define options that apply to\n" .
	"# all of them, then put them in the file /etc/ptal/defaults, which is read\n" .
	"# in before this file.\n" .
	"\n" .
	"# The format version of this file:\n" .
	"#   ptal-init ignores devices with incorrect/missing versions.\n" .
	"init.version=1\n";

    # Write model string.
    if ($model_long !~ /\S/) {
	print CONFIG
	    "\n" .
	    "# \"printerdrake\" couldn't read the model but added this device anyway:\n" .
	    "# ";
    } else {
	print CONFIG
	    "\n" .
	    "# The device model that was originally detected on this port:\n" .
	    "#   If this ever changes, then you should re-run \"printerdrake\"\n" .
	    "#   to delete and re-configure this device.\n";
	if ($bus eq "par") {
	    print CONFIG
		"#   Comment out if you don't care what model is really connected to this\n" .
		"#   parallel port.\n";
	}
    }
    print CONFIG
	"init.mlcd.append+=-devidmatch \"$model_long\"\n";

    # Write serial-number string.
    if ($serialnumber_long !~ /\S/) {
	print CONFIG
	    "\n" .
	    "# The device's serial number is unknown.\n" .
	    "# ";
    } else {
	print CONFIG
	    "\n" .
	    "# The serial number of the device that was originally detected on this port:\n";
	if ($bus =~ /^[pu]/) {
	    print CONFIG
		"#   Comment out if you want to disable serial-number matching.\n";
	}
    }
    print CONFIG
	"init.mlcd.append+=-devidmatch \"$serialnumber_long\"\n";

    if ($bus =~ /^[pu]/) {
	print CONFIG
	    "\n" .
	    "# Standard options passed to ptal-mlcd:\n" .
	    "init.mlcd.append+=";
	if ($bus eq "usb") {
	    # Important: don't put more quotes around /dev/usb/lp[0-9]*,
	    # because ptal-mlcd currently does no globbing:
	    print CONFIG "-device /dev/usb/lp[0-9]*";
	} elsif ($bus eq "par") {
	    print CONFIG "$address_arg -device $device";
	}
	print CONFIG "\n" .
	    "\n" .
	    "# ptal-mlcd's remote console can be useful for debugging, but may be a\n" .
	    "# security/DoS risk otherwise.  In any case, it's accessible with the\n" .
	    "# command \"ptal-connect mlc:<XXX>:<YYY> -service PTAL-MLCD-CONSOLE\".\n" .
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
	print CONFIG
	    "\n" .
	    "# By default ptal-printd isn't started for hpjd: devices.\n" .
	    "# If for some reason you want to start it for this device, then\n" .
	    "# uncomment the following line:\n" .
	    "init.printd.start=1\n";
    }

    print CONFIG
	"\n" .
	"# If you need to pass any additional command-line options to ptal-printd,\n" .
	"# then add them to the following line and uncomment the line:\n" .
	"# init.printd.append+=\n";
    if ($cardreader) {
	print CONFIG
	    "\n" .
	    "# Uncomment the following line to enable ptal-photod for this device:\n" .
	    "init.photod.start=1\n" .
	    "\n" .
	    "# If you have more than one photo-card-capable peripheral and you want to\n" .
	    "# assign particular TCP port numbers and mtools drive letters to each one,\n" .
	    "# then change the line below to use the \"-portoffset <n>\" option.\n" .
	    "init.photod.append+=-maxaltports 26\n";
    }
    close(CONFIG);
    printer::hpoj::readOneDevice($ptaldevice);

    # Restart HPOJ
    printer::services::restart("hpoj");

    # Return HPOJ device name to form the URI
    return $ptaldevice;
}

sub config_sane {
    # Add HPOJ backend to /etc/sane.d/dll.conf if needed (no individual
    # config file /etc/sane.d/hpoj.conf necessary, the HPOJ driver finds the
    # scanner automatically)
    return if member("hpoj", chomp_(cat_("$::prefix/etc/sane.d/dll.conf")));
    eval { append_to_file("$::prefix/etc/sane.d/dll.conf", "hpoj\n") } or
	   die "can't write SANE config in /etc/sane.d/dll.conf: $!";
}

sub config_photocard {

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
	$mtoolsfmconf = cat_("$::prefix/etc/mtoolsfm.conf") or die "can't read MToolsFM config in $::prefix/etc/mtoolsfm.conf: $!";
	$mtoolsfmconf =~ m/^\s*DRIVES\s*=\s*\"([A-Za-z ]*)\"/m;
	my $alloweddrives = lc($1);
	foreach my $letter ("p", "q", "r", "s") {
         $alloweddrives .= $letter if $alloweddrives !~ /$letter/;
	}
	$mtoolsfmconf =~ s/^\s*DRIVES\s*=\s*\"[A-Za-z ]*\"/DRIVES=\"$alloweddrives\"/m;
	$mtoolsfmconf =~ s/^\s*LEFTDRIVE\s*=\s*\"[^\"]*\"/LEFTDRIVE=\"p\"/m;
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

# ------------------------------------------------------------------
#
# Configuration of printers in applications
#
# ------------------------------------------------------------------

sub configureapplications {
    my ($printer) = @_;
    setcupslink($printer);
    printer::office::configureoffice('Star Office', $printer);
    printer::office::configureoffice('OpenOffice.Org', $printer);
    printer::gimp::configure($printer);
}

sub addcupsremotetoapplications {
    my ($printer, $queue) = @_;
    setcupslink($printer);
    return printer::office::add_cups_remote_to_office('Star Office', $printer, $queue) &&
	   printer::office::add_cups_remote_to_office('OpenOffice.Org', $printer, $queue) &&
	   printer::gimp::addcupsremoteto($printer, $queue);
}

sub removeprinterfromapplications {
    my ($printer, $queue) = @_;
    setcupslink($printer);
    return printer::office::remove_printer_from_office('Star Office', $printer, $queue) &&
	   printer::office::remove_printer_from_office('OpenOffice.Org', $printer, $queue) &&
	   printer::gimp::removeprinterfrom($printer, $queue);
}

sub removelocalprintersfromapplications {
    my ($printer) = @_;
    setcupslink($printer);
    printer::office::remove_local_printers_from_office('Star Office', $printer);
    printer::office::remove_local_printers_from_office('OpenOffice.Org', $printer);
    printer::gimp::removelocalprintersfrom($printer);
}

sub setcupslink {
    my ($printer) = @_;
    return 1 if !$::isInstall || $printer->{SPOOLER} ne "cups" || -d "/etc/cups/ppd";
    system("ln -sf $::prefix/etc/cups /etc/cups");
    return 1;
}


1;
