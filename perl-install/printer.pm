package printer;

# $Id$

#use diagnostics;
#use strict;


use common;
use run_program;

#-if we are in an DrakX config
my $prefix = "";

#-location of the printer database in an installed system
my $PRINTER_DB_FILE = "/usr/share/foomatic/db/compiled/overview.xml";
#-configuration directory of Foomatic
my $FOOMATICCONFDIR = "/etc/foomatic"; 
#-location of the file containing the default spooler's name
my $FOOMATIC_DEFAULT_SPOOLER = "$FOOMATICCONFDIR/defaultspooler";

%spooler = (
    _("CUPS - Common Unix Printing System") => "cups",
    _("LPRng - LPR New Generation")         => "lprng",
    _("LPD - Line Printer Daemon")          => "lpd",
    _("PDQ - Print, Don't Queue")           => "pdq"
#    _("PDQ - Marcia, click here!")           => "pdq"
);
%spooler_inv = reverse %spooler;

%shortspooler = (
    _("CUPS")   => "cups",
    _("LPRng")  => "lprng",
    _("LPD")    => "lpd",
    _("PDQ")    => "pdq"
);
%shortspooler_inv = reverse %shortspooler;

%printer_type = (
    _("Local printer")                              => "LOCAL",
    _("Remote printer")                             => "REMOTE",
    _("Printer on remote CUPS server")              => "CUPS",
    _("Printer on remote lpd server")               => "LPD",
    _("Network printer (socket)")                   => "SOCKET",
    _("Printer on SMB/Windows 95/98/NT server")     => "SMB",
    _("Printer on NetWare server")                  => "NCP",
    _("Enter a printer device URI")                 => "URI",
    _("Pipe job into a command")                    => "POSTPIPE"
);
%printer_type_inv = reverse %printer_type;

#------------------------------------------------------------------------------

sub set_prefix($) { $prefix = $_[0]; }

sub default_printer_type($) { "LOCAL" }

sub spooler {
    # LPD is taken from the menu for the moment because the classic LPD is
    # highly unsecure. Depending on how the GNU lpr development is going on
    # LPD support can be reactivated by uncommenting the line which is
    # commented out now.

    #return @spooler_inv{qw(cups lpd lprng pdq)};
    return @spooler_inv{qw(cups lprng pdq)};
}

sub printer_type($) {
    my ($printer) = @_;
    for ($printer->{SPOOLER}) {
	# In the case of CUPS as spooler only present the "Remote CUPS
	# server" option when one adds a new printer, not when one modifies
	# an already configured one.
	/cups/ && return @printer_type_inv{qw(LOCAL), 
			 $printer->{configured}{$printer->{OLD_QUEUE}} ?
			     () : qw(CUPS), qw(LPD SOCKET SMB), 
			     $::expert ? qw(URI) : ()};
	/lpd/  && return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP),
					   $::expert ? qw(POSTPIPE URI) : ()};
	/lprng/  && return @printer_type_inv{qw(LOCAL LPD SOCKET SMB NCP),
					   $::expert ? qw(POSTPIPE URI) : ()};
	/pdq/  && return @printer_type_inv{qw(LOCAL LPD SOCKET),
					   $::expert ? qw(URI) : ()};
    }
}

sub get_default_spooler () {
    if (-f "$prefix$FOOMATIC_DEFAULT_SPOOLER") {
	open DEFSPOOL, "< $prefix$FOOMATIC_DEFAULT_SPOOLER";
	my $spool = <DEFSPOOL>;
	chomp $spool;
	close DEFSPOOL;
	if ($spool =~ /cups|lpd|lprng|pdq/) {
	    return $spool;
	}
    }
}

sub set_default_spooler ($) {
    my ($printer) = @_;
    # Make Foomatic config directory if it does not exist yet
    if (!(-d $FOOMATICCONFDIR)) {mkdir $FOOMATICCONFDIR;}
    # Mark the default driver in a file
    open DEFSPOOL, "> $prefix$FOOMATIC_DEFAULT_SPOOLER" || 
	die "Cannot create $prefix$FOOMATIC_DEFAULT_SPOOLER!";
    print DEFSPOOL $printer->{SPOOLER};
    close DEFSPOOL;
}

sub set_permissions {
    my ($file, $perms, $owner, $group) = @_;
    if ($owner && $group) {
        run_program::rooted($prefix, "/bin/chown", "$owner.$group", $file)
	    || die "Could not restart chown!";
    } elsif ($owner) {
        run_program::rooted($prefix, "/bin/chown", $owner, $file)
	    || die "Could not restart chown!";
    } elsif ($group) {
        run_program::rooted($prefix, "/bin/chgrp", $group, $file)
	    || die "Could not restart chgrp!";
    }
    run_program::rooted($prefix, "/bin/chmod", $perms, $file)
	|| die "Could not restart chmod!";
}

sub restart_service ($) {
    my ($service) = @_;
    run_program::rooted($prefix, "/etc/rc.d/init.d/$service", "restart")
	|| die "Could not restart $service!";
}

sub start_service ($) {
    my ($service) = @_;
    run_program::rooted($prefix, "/etc/rc.d/init.d/$service", "start")
	|| die "Could not start $service!";
}

sub stop_service ($) {
    my ($service) = @_;
    run_program::rooted($prefix, "/etc/rc.d/init.d/$service", "stop")
	|| die "Could not stop $service!";
}

sub service_starts_on_boot ($) {
    my ($service) = @_;
    local *F; 
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"/bin/sh -c \"export LC_ALL=C; /sbin/chkconfig --list $service 2>&1\" |" ||
	    die "Could not run chkconfig!";
    while (<F>) {
	chomp;
	if ($_ =~ /:on/) {
	    close F;
	    return 1;
	}
    }
    close F;
    return 0;
}

sub start_service_on_boot ($) {
    my ($service) = @_;
    run_program::rooted($prefix, "/sbin/chkconfig", "--add", $service)
	|| die "Could not start chkconfig!";
}

sub network_status {
    # If the network is not running or not running as configured,
    # return 0, otherwise 1.
    local *F; 
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"/bin/sh -c \"export LC_ALL=C; /etc/rc.d/init.d/network status\" |" ||
	    die "Could not run \"/etc/rc.d/init.d/network status\"!";
    while (<F>) {
	if (($_ =~ /Devices.*down/) || # Are there configured devices which
	                               # are down
	    ($_ =~ /Devices.*modified/)) { # Configured devices which are not
	                                   # running as configured
	    my $devices = <F>;
	    chomp $devices;
	    if ($devices !~ /^\s*$/) { # Blank line
		close F;
		return 0;
	    }
	}
    }
    close F;
    return 1;
}

sub files_exist {
    my @files = @_;
    for (@files) {
	if (! -f "$prefix$_") {return 0;}
    }
    return 1;
}

sub set_alternative {
    my ($command, $executable) = @_;
    local *F;
    # Read the list of executables for the given command to find the number
    # of the desired executable
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"/bin/sh -c \"export LC_ALL=C; /bin/echo | update-alternatives --config $command \" |" ||
	    die "Could not run \"update-alternatives\"!";
    my $choice = 0;
    while (<F>) {
	chomp;
	if ($_ =~ m/^[\* ][\+ ]\s*([0-9]+)\s+(\S+)\s*$/) { # list entry?
	    if ($2 eq $executable) {
		$choice = $1;
		last;
	    }
	}
    }
    close F;
    # If the executable was found, assign the command to it
    if ($choice > 0) {
	system(($::testing ? "$prefix" : "chroot $prefix/ ") .
	       "/bin/sh -c \"/bin/echo $choice | update-alternatives --config $command > /dev/null 2>&1\"");
    }
    return 1;
}    

sub pdq_panic_button {
    my $setting = $_[0];
    if (-f "/usr/sbin/pdqpanicbutton") {
        run_program::rooted($prefix, "/usr/sbin/pdqpanicbutton", "--$setting")
	    || die "Could not $setting PDQ panic buttons!";
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
    my @QUEUES;

    set_prefix($prefix);

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
    if (!($printer->{SPOOLER} ||= get_default_spooler())) {
	#- Find the first spooler where there are queues
	my $spooler;
	for $spooler (qw(cups pdq lprng lpd)) {
	    #- poll queue info 
	    local *F; 
	    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
		"foomatic-configure -P -s $spooler |" ||
		    die "Could not run foomatic-configure";
	    eval (join('',(<F>))); 
	    close F;
	    #- Have we found queues?
	    if ($#QUEUES != -1) {
		$printer->{SPOOLER} = $spooler;
		last;
	    }
	}
    } else {
	#- Poll the queues of the current default spooler
	local *F; 
	open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	    "foomatic-configure -P -s $printer->{SPOOLER} |" ||
		die "Could not run foomatic-configure";
	eval (join('',(<F>))); 
	close F;
    }
    $printer->{configured} = {};
    my $i;
    my $N = $#QUEUES + 1;
    for ($i = 0;  $i < $N; $i++) {
	$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}} = 
	    $QUEUES[$i];
	if ((!$QUEUES[$i]->{'make'}) || (!$QUEUES[$i]->{'model'})) {
	    if ($printer->{SPOOLER} eq "cups") {
		$printer->{OLD_QUEUE} = $QUEUES[$i]->{'queuedata'}{'queue'};
		my $descr = get_descr_from_ppd($printer);
		$descr =~ m/^([^\|]*)\|([^\|]*)\|.*$/;
		$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'make'} ||= $1;
		$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'model'} ||= $2;
		# Read out which PPD file was originally used to set up this
		# queue
		local *F;
		if (open F, "< $prefix/etc/cups/ppd/$QUEUES[$i]->{'queuedata'}{'queue'}.ppd") {
		    while (<F>) {
			if ($_ =~ /^\*%MDKMODELCHOICE:(.+)$/) {
			    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'ppd'} = $1;
			}
		    }
		    close F;
		}
		# Mark that we have a CUPS queue but do not know the name
		# the PPD file in /usr/share/cups/model
		if (!$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'ppd'}) {
		    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'ppd'} = '1';
		}
		$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'driver'} = 'CUPS/PPD';
		$printer->{OLD_QUEUE} = "";
		# Read out the printer's options
		$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'args'} = read_cups_options($QUEUES[$i]->{'queuedata'}{'queue'});
	    }
	    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'make'} ||= "";
	    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'model'} ||= _("Unknown model");
	} else {
	    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'make'} = $QUEUES[$i]->{'make'};
	    $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{'model'} = $QUEUES[$i]->{'model'};
	}
	# Fill in "options" field
	if (my $args = $printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'args'}) {
	    my $arg;
	    my @options;
	    for $arg (@{$args}) {
		push(@options, "-o");
		my $optstr = $arg->{'name'} . "=" . $arg->{'default'};
		push(@options, $optstr);
	    }
	    @{$printer->{configured}{$QUEUES[$i]->{'queuedata'}{'queue'}}{'queuedata'}{options}} = @options;
	}
    }
}

sub read_printer_db(;$) {

    my $spooler = $_[0];

    my $dbpath = $prefix . $PRINTER_DB_FILE;

    local $_; #- use of while (<...

    local *DBPATH; #- don't have to do close ... and don't modify globals at least
    # Generate the Foomatic printer/driver overview, read it from the
    # appropriate file when it is already generated
    if (!(-f $dbpath)) {
	open DBPATH, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	    "foomatic-configure -O |" ||
		die "Could not run foomatic-configure";
    } else {
	open DBPATH, $dbpath or die "An error has occurred on $dbpath : $!";
    }

    my $entry = {};
    my $inentry = 0;
    my $indrivers = 0;
    my $inautodetect = 0;
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
		    push (@{$entry->{drivers}}, $1);
		}
	    } elsif ($inautodetect) {
		# We are inside the autodetect block of a printers entry
		# All entries inside this block will be ignored
		if (m!^.*</autodetect>\s*$!) {
		    # End of autodetect block
		    $inautodetect = 0;
		}
	    } else {
		if (m!^\s*</printer>\s*$!) {
		    # entry completed
		    $inentry = 0;
		    # Expert mode:
		    # Make one database entry per driver with the entry name
		    # manufacturer|model|driver
		    if ($::expert) {
			my $driver;
			for $driver (@{$entry->{drivers}}) {
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
			    $entry->{driver} = $driver;
			    # Duplicate contents of $entry because it is multiply entered to the database
			    map { $thedb{$entry->{ENTRY}}->{$_} = $entry->{$_} } keys %$entry;
			}
		    } else {
			# Recommended mode
			# Make one entry per printer, with the recommended
			# driver (manufacturerer|model)
			$entry->{ENTRY} = "$entry->{make}|$entry->{model}";
			if ($entry->{defaultdriver}) {
			    $entry->{driver} = $entry->{defaultdriver};
			    map { $thedb{$entry->{ENTRY}}->{$_} = $entry->{$_} } keys %$entry;
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
	$entry->{ENTRY} = _("Raw printer (No driver)");
	$entry->{driver} = "raw";
	$entry->{make} = "";
	$entry->{model} = "Unknown model";
	map { $thedb{$entry->{ENTRY}}->{$_} = $entry->{$_} } keys %$entry;
    }

    #- Load CUPS driver database if CUPS is used as spooler
    if (($spooler) && ($spooler eq "cups") && ($::expert)) {

	#&$install('cups-drivers') unless $::testing;
	#my $w;
	#if ($in) {
	#    $w = $in->wait_message(_("CUPS starting"),
	#			   _("Reading CUPS drivers database..."));
	#}
        poll_ppd_base();
    }

    @entries_db_short     = sort keys %printer::thedb;
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
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"foomatic-configure -P -p $printer->{currentqueue}{'printer'}" .
	    " -d $printer->{currentqueue}{'driver'}" . 
		($printer->{OLD_QUEUE} ?
		  " -s $printer->{SPOOLER} -n $printer->{OLD_QUEUE}" : "") .
		($printer->{SPECIAL_OPTIONS} ?
		  " $printer->{SPECIAL_OPTIONS}" : "") 
		    . " |" ||
	    die "Could not run foomatic-configure";
    eval (join('',(<F>))); 
    close F;
    # Return the arguments field
    return $COMBODATA->{'args'};
}

sub read_cups_options ($) {
    my ($queue_or_file) = @_;
    # Generate the option data from a CUPS PPD file/a CUPS queue
    # Use the same Perl data structure as Foomatic uses to be able to
    # reuse the dialog
    local *F;
    if ($queue_or_file =~ /.ppd.gz$/) { # compressed PPD file
	open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	    "gunzip -cd $queue_or_file | lphelp - |" || return 0;
    } else { # PPD file not compressed or queue
	open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	    "lphelp $queue_or_file |" || return 0;
    }
    my $i;
    my $j;
    my @args = ();
    my $line;
    my $inoption = 0;
    my $inchoices = 0;
#    my $innumerical = 0;
    while ($line = <F>) {
	chomp $line;
	if ($inoption) {
	    if ($inchoices) {
		if ($line =~ /^\s*(\S+)\s+(\S.*)$/) {
		    push(@{$args[$i]{vals}}, {});
		    $j = $#{$args[$i]{vals}};
		    $args[$i]{vals}[$j]{value} = $1;
		    my $comment = $2;
		    # Did we find the default setting?
		    if ($comment =~ /default\)\s*$/) {
			$args[$i]{default} = $args[$i]{vals}[$j]{value};
			$comment =~ s/,\s*default\)\s*$//;
		    } else {
			$comment =~ s/\)\s*$//;
		    }
		    # Remove opening paranthese
		    $comment =~ s/^\(//;
		    # Remove page size info
		    $comment =~ s/,\s*size:\s*[0-9\.]+x[0-9\.]+in$//;
		    $args[$i]{vals}[$j]{comment} = $comment;
		} elsif (($line =~ /^\s*$/) && ($#{$args[$i]{vals}} > -1)) {
		    $inchoices = 0;
		    $inoption = 0;
		}
#	    } elsif ($innumerical == 1) {
#		if ($line =~ /^\s*The default value is ([0-9\.]+)\s*$/) {
#		    $args[$i]{default} = $1;
#		    $innumerical = 0;
#		    $inoption = 0;
#		}
	    } else {
		if ($line =~ /^\s*<choice>/) {
		    $inchoices = 1;
#		} elsif ($line =~ /^\s*<value> must be a(.*) number in the range ([0-9\.]+)\.\.([0-9\.]+)\s*$/) {
#		    delete($args[$i]{vals});
#		    $args[$i]{min} = $2;
#		    $args[$i]{max} = $3;
#		    my $type = $1;
#		    if ($type =~ /integer/) {
#			$args[$i]{type} = 'int';
#		    } else {
#			$args[$i]{type} = 'float';
#		    }
#		    $innumerical = 1;
		}
	    }
	} else {
	    if ($line =~ /^\s*([^\s:][^:]*):\s+-o\s+([^\s=]+)=<choice>\s*$/) {
#	    if ($line =~ /^\s*([^\s:][^:]*):\s+-o\s+([^\s=]+)=<.*>\s*$/) {
		$inoption = 1;
		push(@args, {});
		$i = $#args;
		$args[$i]{comment} = $1;
		$args[$i]{name} = $2;
		$args[$i]{type} = 'enum';
		@{$args[$i]{vals}} = ();
	    }
	}
    }
    close F;
    # Return the arguments field
    return \@args;
}

#------------------------------------------------------------------------------

sub read_cups_printer_list {
    # This function reads in a list of all printers which the local CUPS
    # daemon currently knows, including remote ones.
    local *F;
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"lpstat -v |" || return ();
    my @printerlist = ();
    my $line;
    while ($line = <F>) {
	if ($line =~ m/^\s*device\s+for\s+([^:\s]+):\s*(\S+)\s*$/) {
	    my $queuename = $1;
	    my $comment = "";
	    if ($2 =~ m!^ipp://([^/:]+)[:/]!) {
		$comment = _("(on %s)", $1);
	    } else {
		$comment = _("(on this machine)");
	    }
	    push (@printerlist, "$queuename $comment");
	}
    }
    close F;
    return @printerlist;
}

sub set_cups_autoconf {
    my $autoconf = $_[0];

    # Read config file
    local *F;
    my $file = "$prefix/etc/sysconfig/printing";
    if (!(-f $file)) {
	@file_content = ();
    } else {
	open F, "< $file" or die "Cannot open $file!";
	@file_content = <F>;
	close F;
    }

    # Remove all valid "CUPS_CONFIG" lines
    ($_ =~ /^\s*CUPS_CONFIG/ and $_="") foreach @file_content;
 
    # Insert the new "Printcap" line
    if ($autoconf) {
	push @file_content, "CUPS_CONFIG=automatic\n";
    } else {
	push @file_content, "CUPS_CONFIG=manual\n";
    }

    # Write back modified file
    open F, "> $file" or die "Cannot open $file!";
    print F @file_content;
    close F;

    # Restart CUPS
    restart_service("cups");

    return 1;
}

sub get_cups_autoconf {
    local *F;
    open F, ("< $prefix/etc/sysconfig/printing") || return 1;
    my $line;
    while ($line = <F>) {
	if ($line =~ m!^[^\#]*CUPS_CONFIG=manual!) {
	    return 0;
	}
    }
    return 1;
}

sub set_default_printer {
    my ($printer) = $_[0];
    run_program::rooted($prefix, "foomatic-configure",
			"-D", "-s", $printer->{SPOOLER},
			"-n", $printer->{DEFAULT}) || return 0;
    return 1;
}

sub get_default_printer {
    my $printer = $_[0];
    local *F;
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	"foomatic-configure -Q -s $printer->{SPOOLER} |" || return undef;
    my $line;
    while ($line = <F>) {
	if ($line =~ m!^\s*<defaultqueue>(.*)</defaultqueue>\s*$!) {
	    return $1;
	}
    }
    return undef;
}

sub read_cupsd_conf {
    my @cupsd_conf;
    local *F;

    open F, "$prefix/etc/cups/cupsd.conf";
    @cupsd_conf = <F>;
    close F;

    @cupsd_conf;
}
sub write_cupsd_conf {
    my (@cupsd_conf) = @_;
    local *F;

    open F, ">$prefix/etc/cups/cupsd.conf";
    print F @cupsd_conf;
    close F;

    #- restart cups after updating configuration.
    restart_service("cups");
}

sub read_printers_conf {
    my ($printer) = @_;
    my $current = undef;

    #- read /etc/cups/printers.conf file.
    #- according to this code, we are now using the following keys for each queues.
    #-    DeviceURI > lpd://printer6/lp
    #-    Info      > Info Text
    #-    Location  > Location Text
    #-    State     > Idle|Stopped
    #-    Accepting > Yes|No
    local *PRINTERS; open PRINTERS, "$prefix/etc/cups/printers.conf" or return;
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
    local *F; open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . "/usr/sbin/lpinfo -v |";
    local $_;
    while (<F>) {
	/^(direct|usb|serial)\s+(\S*)/ and push @direct_uri, $2;
    }
    close F;
    @direct_uri;
}

sub get_descr_from_ppd {
    my ($printer) = @_;
    my %ppd;

    #- if there is no ppd, this means this is a raw queue.
    local *F; open F, "$prefix/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd" or return "|" . _("Unknown model");
    # "OTHERS|Generic PostScript printer|PostScript (en)";
    local $_;
    while (<F>) {
	/^\*([^\s:]*)\s*:\s*\"([^\"]*)\"/ and do { $ppd{$1} = $2; next };
	/^\*([^\s:]*)\s*:\s*([^\s\"]*)/   and do { $ppd{$1} = $2; next };
    }
    close F;

    my $descr = ($ppd{NickName} || $ppd{ShortNickName} || $ppd{ModelName});
    # Apply the beautifying rules of poll_ppd_base
    if ($descr =~ /Foomatic \+ Postscript/) {
	$descr =~ s/Foomatic \+ Postscript/PostScript/;
    } elsif ($descr =~ /Foomatic/) {
	$descr =~ s/Foomatic/GhostScript/;
    } elsif ($descr =~ /CUPS\+GIMP-print/) {
	$descr =~ s/CUPS\+GIMP-print/CUPS \+ GIMP-Print/;
    } elsif ($descr =~ /Series CUPS/) {
	$descr =~ s/Series CUPS/Series, CUPS/;
    } elsif (!(uc($descr) =~ /POSTSCRIPT/)) {
	$descr .= ", PostScript";
    }

    # Split the $descr into model and driver
    my $model;
    my $driver;
    if ($descr =~ /^([^,]+), (.*)$/) {
	$model = $1;
	$driver = $2;
    } else {
	# Some PPDs do not have the ", <driver>" part.
	$model = $descr;
	$driver = "PostScript";
    }
    my $make = $ppd{Manufacturer};
    my $lang = $ppd{LanguageVersion};

    # Remove manufacturer's name from the beginning of the model name
    if (($make) && ($model =~ /^$make[\s\-]+([^\s\-].*)$/)) {
	$model = $1;
    }

    # Put out the resulting description string
    uc($make) . '|' . $model . '|' . $driver .
      ($lang && (" (" . lc(substr($lang, 0, 2)) . ")"));
}

sub poll_ppd_base {
    #- before trying to poll the ppd database available to cups, we have to make sure
    #- the file /etc/cups/ppds.dat is no more modified.
    #- if cups continue to modify it (because it reads the ppd files available), the
    #- poll_ppd_base program simply cores :-)
    run_program::rooted($prefix, "ifconfig lo 127.0.0.1"); #- else cups will not be happy! and ifup lo don't run ?
    start_service("cups");
    my $driversthere = scalar(keys %thedb);
    foreach (1..60) {
	local *PPDS; open PPDS, ($::testing ? "$prefix" : "chroot $prefix/ ") . "/usr/bin/poll_ppd_base -a |";
	local $_;
	while (<PPDS>) {
	    chomp;
	    my ($ppd, $mf, $descr, $lang) = split /\|/;
	    if ($ppd eq "raw") {next;}
	    my ($model, $driver);
	    if ($descr) {
		if ($descr =~ /^([^,]+), (.*)$/) {
		    $model = $1;
		    $driver = $2;
		} else {
		    # Some PPDs do not have the ", <driver>" part.
		    $model = $descr;
		    $driver = "PostScript";
		}
	    }
	    # Rename Canon "BJC XXXX" models into "BJC-XXXX" so that the models
	    # do not appear twice
	    if ($mf eq "CANON") {
		$model =~ s/BJC\s+/BJC-/;
	    }
	    $ppd && $mf && $descr and do {
		my $key = "$mf|$model|$driver" . ($lang && " ($lang)");
	        $thedb{$key}{ppd} = $ppd;
		$thedb{$key}{driver} = $driver;
		$thedb{$key}{make} = $mf;
		$thedb{$key}{model} = $model;
	    }
	}
	close PPDS;
	scalar(keys %thedb) - $driversthere > 5 and last;
	#- we have to try again running the program, wait here a little before.
	sleep 1; 
    }

    #scalar(keys %descr_to_ppd) > 5 or die "unable to connect to cups server";

}



#-******************************************************************************
#- write functions
#-******************************************************************************

sub configure_queue($) {
    my ($printer) = @_;
    local *F;

    if ($printer->{currentqueue}{foomatic}) {
	#- Create the queue with "foomatic-configure", in case of queue
	#- renaming copy the old queue
        run_program::rooted($prefix, "foomatic-configure",
			    "-s", $printer->{currentqueue}{'spooler'},
			    "-n", $printer->{currentqueue}{'queue'},
			    (($printer->{currentqueue}{'queue'} ne 
			      $printer->{OLD_QUEUE}) &&
			     ($printer->{configured}{$printer->{OLD_QUEUE}}) ?
			     ("-C", $printer->{OLD_QUEUE}) : ()),
			    "-c", $printer->{currentqueue}{'connect'},
			    "-p", $printer->{currentqueue}{'printer'},
			    "-d", $printer->{currentqueue}{'driver'},
			    "-N", $printer->{currentqueue}{'desc'},
			    "-L", $printer->{currentqueue}{'loc'},
			    @{$printer->{currentqueue}{options}}
			    ) or die "foomatic-configure failed";
    } elsif ($printer->{currentqueue}{ppd}) {
	#- If the chosen driver is a PPD file from /usr/share/cups/model,
	#- we use lpadmin to set up the queue
        run_program::rooted($prefix, "lpadmin",
			    "-p", $printer->{currentqueue}{'queue'},
#			    $printer->{State} eq 'Idle' && 
#			        $printer->{Accepting} eq 'Yes' ? ("-E") : (),
			    "-E",
			    "-v", $printer->{currentqueue}{'connect'},
			    ($printer->{currentqueue}{'ppd'} ne '1') ?
			        ("-m", $printer->{currentqueue}{'ppd'}) : (),
			    $printer->{currentqueue}{'desc'} ?
			        ("-D", $printer->{currentqueue}{'desc'}) : (),
			    $printer->{currentqueue}{'loc'} ? 
			        ("-L", $printer->{currentqueue}{'loc'}) : (),
			    @{$printer->{currentqueue}{options}}
			    ) or die "lpadmin failed";
	# Add a comment line containing the path of the used PPD file to the
	# end of the PPD file
	if ($printer->{currentqueue}{'ppd'} ne '1') {
	    open F, ">> $prefix/etc/cups/ppd/$printer->{currentqueue}{'queue'}.ppd";
	    print F "*%MDKMODELCHOICE:$printer->{currentqueue}{'ppd'}\n";
	    close F;
	}
	# Copy the old queue's PPD file to the new queue when it is renamed,
	# to conserve the option settings
	if (($printer->{currentqueue}{'queue'} ne 
	     $printer->{OLD_QUEUE}) &&
	    ($printer->{configured}{$printer->{OLD_QUEUE}})) {
	    system("echo yes | cp -f " .
		   "$prefix/etc/cups/ppd/$printer->{OLD_QUEUE}.ppd " .
		   "$prefix/etc/cups/ppd/$printer->{currentqueue}{'queue'}.ppd");
	}
    } else {
	# Raw queue
        run_program::rooted($prefix, "foomatic-configure",
			    "-s", $printer->{currentqueue}{'spooler'},
			    "-n", $printer->{currentqueue}{'queue'},
			    "-c", $printer->{currentqueue}{'connect'},
			    "-d", $printer->{currentqueue}{'driver'},
			    "-N", $printer->{currentqueue}{'desc'},
			    "-L", $printer->{currentqueue}{'loc'}
			    ) or die "foomatic-configure failed";
    }	  

    # Make sure that queue is active
    if ($printer->{SPOOLER} ne "pdq") {
        run_program::rooted($prefix, "foomatic-printjob",
			    "-s", $printer->{currentqueue}{'spooler'},
			    "-C", "up", $printer->{currentqueue}{'queue'});
    }

    # Check whether a USB printer is configured and activate USB printing if so
    my $useUSB = 0;
    foreach (values %{$printer->{configured}}) {
	$useUSB ||= $_->{'queuedata'}{'connect'} =~ /usb/ || 
	    $_->{DeviceURI} =~ /usb/;
    }
    $useUSB ||= ($printer->{currentqueue}{'queue'}{'queuedata'}{'connect'}
		 =~ /usb/);
    if ($useUSB) {
	my $f = "$prefix/etc/sysconfig/usb";
	my %usb = getVarsFromSh($f);
	$usb{PRINTER} = "yes";
	setVarsInSh($f, \%usb);
    }

    # Open permissions for device file when PDQ is chosen as spooler
    # so normal users can print.
    if ($printer->{SPOOLER} eq 'pdq') {
	if ($printer->{currentqueue}{'connect'} =~ m!^\s*file:(\S*)\s*$!) {
	    set_permissions($1,"666");
	}
    }

    # Make a new printer entry in the $printer structure
    $printer->{configured}{$printer->{currentqueue}{'queue'}}{'queuedata'}=
	$printer->{currentqueue};
    $printer->{configured}{$printer->{currentqueue}{'queue'}}{'args'} = {};
    if ($printer->{currentqueue}{foomatic}) {
	my $tmp = $printer->{OLD_QUEUE};
	$printer->{OLD_QUEUE} = $printer->{currentqueue}{'queue'};
	$printer->{configured}{$printer->{currentqueue}{'queue'}}{'args'} = 
	    read_foomatic_options($printer);
	$printer->{OLD_QUEUE} = $tmp;
    } elsif ($printer->{currentqueue}{ppd}) {
	$printer->{configured}{$printer->{currentqueue}{'queue'}}{'args'} =
	    read_cups_options($printer->{currentqueue}{'queue'});
    }
    # Clean up
    delete($printer->{currentqueue});
    delete($printer->{ARGS});
    $printer->{OLD_CHOICE} = "";
    $printer->{ARGS} = {};
    $printer->{DBENTRY} = "";
    $printer->{currentqueue} = {};
}

sub remove_queue($$) {
    my ($printer) = $_[0];
    my ($queue) = $_[1];
    run_program::rooted($prefix, "foomatic-configure", "-R",
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
	/cups/ && do {
	    #- restart cups.
	    restart_service("cups"); sleep 1;
	    last };
	/lpr|lprng/ && do {
	    #- restart lpd.
	    foreach (("/var/spool/lpd/$queue/lock", "/var/spool/lpd/lpd.lock")) {
		my $pidlpd = (cat_("$prefix$_"))[0];
		kill 'TERM', $pidlpd if $pidlpd;
		unlink "$prefix$_";
	    }
	    restart_service("lpd"); sleep 1;
	    last };
    }
    # Kill the jobs
    run_program::rooted($prefix, "foomatic-printjob", "-R",
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
	    system(($::testing ? "$prefix" : "chroot $prefix/ ") .
		   "/usr/bin/convert $page -page 427x654+100+65 PS:- | " .
		   ($::testing ? "$prefix" : "chroot $prefix/ ") .
		   "$lpr -s $printer->{SPOOLER} -P $queue");
	} else {
	    run_program::rooted($prefix, $lpr, "-s", $printer->{SPOOLER},
				"-P", $queue, $page);
	}
    }
    sleep 5; #- allow lpr to send pages.
    # Check whether the job is queued
    local *F; 
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . "$lpq -s $printer->{SPOOLER} -P $queue |";
    my @lpq_output =
	grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <F>;
    close F;
    @lpq_output;
}

sub lphelp_output {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};
    my $lphelp = "/usr/bin/lphelp";

    local *F; 
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . "$lphelp $queue |";
    $helptext = join("", <F>);
    close F;
    return $helptext;
}

sub pdqhelp_output {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};
    my $pdq = "/usr/bin/pdq";

    local *F; 
    open F, ($::testing ? "$prefix" : "chroot $prefix/ ") . "$pdq -h -P $queue  2>&1 |";
    $helptext = join("", <F>);
    close F;
    return $helptext;
}

sub print_optionlist {
    my ($printer) = @_;
    my $queue = $printer->{QUEUE};
    my $lpr = "/usr/bin/foomatic-printjob";

    # Print the option list pages
    if ($printer->{configured}{$queue}{queuedata}{foomatic}) {
        run_program::rooted($prefix, $lpr, "-s", $printer->{SPOOLER},
			    "-P", $queue, "-o", "docs",
			    $FOOMATIC_DEFAULT_SPOOLER);
    } elsif ($printer->{configured}{$queue}{queuedata}{ppd}) {
	system(($::testing ? "$prefix" : "chroot $prefix/ ") .
	       "/usr/bin/lphelp $queue | " .
	       ($::testing ? "$prefix" : "chroot $prefix/ ") .
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
    local $_; #- use of while (<...

    local *QUEUEOUTPUT; #- don't have to do close ... and don't modify globals
                        #- at least
    my @queuelist;      #- here we will list all Foomatic-generated queues
    # Get queue list with foomatic-configure
    open QUEUEOUTPUT, ($::testing ? "$prefix" : "chroot $prefix/ ") . 
	    "foomatic-configure -Q -s $oldspooler |" ||
		die "Could not run foomatic-configure";

    my $entry = {};
    my $inentry = 0;
    while (<QUEUEOUTPUT>) {
	chomp;
	if ($inentry) {
	    # We are inside a queue entry
	    if (m!^\s*</queue>\s*$!) {
		# entry completed
		$inentry = 0;
		if (($entry->{foomatic}) && 
		    ($entry->{spooler} eq $oldspooler)) {
		    # Is the connection type supported by the new
		    # spooler?
		    if ((($newspooler eq "cups") &&
			 (($entry->{connect} =~ /^file:/) ||
			  ($entry->{connect} =~ /^lpd:/) ||
			  ($entry->{connect} =~ /^socket:/) ||
			  ($entry->{connect} =~ /^smb:/) ||
			  ($entry->{connect} =~ /^ipp:/))) ||
			((($newspooler eq "lpd") ||
			  ($newspooler eq "lprng")) &&
			 (($entry->{connect} =~ /^file:/) ||
			  ($entry->{connect} =~ /^lpd:/) ||
			  ($entry->{connect} =~ /^socket:/) ||
			  ($entry->{connect} =~ /^smb:/) ||
			  ($entry->{connect} =~ /^ncp:/) ||
			  ($entry->{connect} =~ /^postpipe:/))) ||
			(($newspooler eq "pdq") &&
			 (($entry->{connect} =~ /^file:/) ||
			  ($entry->{connect} =~ /^lpd:/) ||
			  ($entry->{connect} =~ /^socket:/)))) {
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
    run_program::rooted($prefix, "foomatic-configure",
		      "-s", $printer->{SPOOLER},
		      "-n", $newqueue,
			"-C", $oldspooler, $oldqueue);
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
