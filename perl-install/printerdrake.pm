package printerdrake;
# $Id$

use diagnostics;
use strict;

use common;
use detect_devices;
use commands;
use modules;
use network;
use log;
use printer;

1;

sub choose_printer_type {
    my ($printer, $in) = @_;
    $in->set_help('configurePrinterConnected') if $::isInstall;
    my $queue = $printer->{OLD_QUEUE};
    $printer->{str_type} = $printer::printer_type_inv{$printer->{TYPE}};
    $printer->{str_type} = 
	$in->ask_from_list_(_("Select Printer Connection"),
			    _("How is the printer connected?") .
			    ($printer->{SPOOLER} eq "cups" ?
			     _("
Printers on remote CUPS servers you do not have to configure
here; these printers will be automatically detected. In case
of doubt, select \"Printer on remote CUPS server\".") : ()),
			    [ printer::printer_type($printer) ],
			    $printer->{str_type},
			    ) or return 0;
    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
    1;
}

sub setup_remote_cups_server {
    my ($printer, $in) = @_;
    $in->set_help('configureRemoteCUPSServer') if $::isInstall;
    my $queue = $printer->{OLD_QUEUE};
    #- hack to handle cups remote server printing,
    #- first read /etc/cups/cupsd.conf for variable BrowsePoll address:port
    my @cupsd_conf = printer::read_cupsd_conf();
    my ($server, $port);
    
    foreach (@cupsd_conf) {
	/^\s*BrowsePoll\s+(\S+)/ and $server = $1, last;
    }
    $server =~ /([^:]*):(.*)/ and ($server, $port) = ($1, $2);
    
    #- then ask user for this combination
    #- and rewrite /etc/cups/cupsd.conf according to new settings.
    #- there are no other point where such information is written in this file.
    if ($in->ask_from_entries_refH
	(_("Remote CUPS server"),
_("With a remote CUPS server, you do not have to configure
any printer here; printers will be automatically detected
unless you have a server on a different network; in the
latter case, you have to give the CUPS server IP address
and optionally the port number."),
	 [
	  { label => _("CUPS server IP"), val => \$server },
	  { label => _("Port"), val => \$port } ],
	 complete => sub {
	     unless (!$server || network::is_ip($server)) {
		 $in->ask_warn('', _("IP address should be in format 1.2.3.4"));
		 return (1,0);
	     }
	     if ($port !~ /^\d*$/) {
		 $in->ask_warn('', _("Port number should be numeric"));
		 return (1,1);
	     }
	     return 0;
	 },
	 )) {
	$server && $port and $server = "$server:$port";
	if ($server) {
	    @cupsd_conf = map { $server and s/^\s*BrowsePoll\s+(\S+)/BrowsePoll $server/ and $server = '';
				$_ } @cupsd_conf;
	    $server and push @cupsd_conf, "\nBrowsePoll $server\n";
	} else {
	    @cupsd_conf = map { s/^\s*BrowsePoll\s+(\S+)/\#BrowsePoll $1/;
				$_ } @cupsd_conf;
	}
        printer::write_cupsd_conf(@cupsd_conf);
    } else {
	return 0;
    }
    1;
}

sub choose_printer_name {
    my ($printer, $in) = @_;
    # Name, description, location
    my $queue = $printer->{OLD_QUEUE};
    $in->set_help('configurePrinterLocal') if $::isInstall;
    $in->ask_from_entries_refH_powered
	(
	 { title => _("Enter Printer Name and Comments"),
	   #cancel => !$printer->{configured}{$queue} ? '' : _("Remove queue"),
	   callbacks => { complete => sub {
	       unless ($printer->{currentqueue}{'queue'} =~ /^\w+$/) {
		   $in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
		   return (1,0);
	       }
	       return 0;
	   },
		      },
	   messages =>
_("Every printer needs a name (for example lp).
The Description and Location fields do not need 
to be filled in. They are comments for the users.") }, 
	 [
	  { label => _("Name of printer"),
	    val => \$printer->{currentqueue}{'queue'} },
	  { label => _("Description"),
	    val => \$printer->{currentqueue}{'desc'} },
	  { label => _("Location"),
	    val => \$printer->{currentqueue}{'loc'} },
	  ]) or return 0;

    $printer->{QUEUE} = $printer->{currentqueue}{'queue'};
    1;
}

sub setup_printer_connection {
    my ($printer, $in) = @_;
    # Choose the appropriate connection config dialog
    my $done = 1;
    for ($printer->{TYPE}) {
	/LOCAL/     and setup_local    ($printer, $in) and last;
	/LPD/       and setup_lpd      ($printer, $in) and last;
	/SOCKET/    and setup_socket   ($printer, $in) and last;
	/SMB/       and setup_smb      ($printer, $in) and last;
	/NCP/       and setup_ncp      ($printer, $in) and last;
	/URI/       and setup_uri      ($printer, $in) and last;
	/POSTPIPE/  and setup_postpipe ($printer, $in) and last;
	$done = 0; last;
    }
    return $done;
}

sub auto_detect {
    my ($in) = @_;
    {
	my $w = $in->wait_message(_("Test ports"), _("Detecting devices..."));
	modules::get_alias("usb-interface") and eval { modules::load("printer"); sleep(2); };
	foreach (qw(parport_pc lp parport_probe parport)) {
	    eval { modules::unload($_); }; #- on kernel 2.4 parport has to be unloaded to probe again
	}
	foreach (qw(parport_pc lp parport_probe)) {
	    eval { modules::load($_); }; #- take care as not available on 2.4 kernel (silent error).
	}
    }
    my $b = before_leaving { eval { modules::unload("parport_probe") } };
    detect_devices::whatPrinter();
}


sub setup_local {
    my ($printer, $in) = @_;

    my $queue = $printer->{OLD_QUEUE};
    my @port = ();
    my @str = ();
    my $device;
    my @parport = auto_detect($in);
    # $printer->{currentqueue}{queuedata}
    foreach (@parport) {
	$_->{val}{DESCRIPTION} and push @str, _("A printer, model \"%s\", has been detected on ",
						$_->{val}{DESCRIPTION}) . $_->{port};
    }
    if ($::expert || !@str) {
	@port = detect_devices::whatPrinterPort();
    } else {
	@port = map { $_->{port} } grep { $_->{val}{DESCRIPTION} } @parport;
    }
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^file:/)) {
	$device = $printer->{currentqueue}{'connect'};
	$device =~ s/^file://;
    } elsif ($port[0]) {
	$device = $port[0];
    }
    if ($in) {
	$::expert or $in->set_help('configurePrinterDev') if $::isInstall;
	return if !$in->ask_from_entries_refH(_("Local Printer Device"),
_("What device is your printer connected to 
(note that /dev/lp0 is equivalent to LPT1:)?\n") . (join "\n", @str), [
{ label => _("Printer Device"), val => \$device, list => \@port, not_edit => !$::expert } ],
complete => sub {
    unless ($device ne "") {
	$in->ask_warn('', _("Device/file name missing!"));
	return (1,0);
    }
    return 0;
}
					     );
    }

    #- make the DeviceURI from $device.
    $printer->{currentqueue}{'connect'} = "file:" . $device;

    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
        printer::read_printer_db($printer->{SPOOLER});
    }

    #- Search the database entry which matches the detected printer best
    foreach (@parport) {
	$device eq $_->{port} or next;
        $printer->{DBENTRY} =
            bestMatchSentence ($_->{val}{DESCRIPTION}, keys %printer::thedb);
    }
    1;
}

sub setup_lpd {
    my ($printer, $in) = @_;

    my $uri;
    my $remotehost;
    my $remotequeue;
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^lpd:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*lpd://([^/]+)/([^/]+)/?\s*$!;
	$remotehost = $1;
	$remotequeue = $2;
    } else {
	$remotehost = "";
	$remotequeue = "lp";
    }

    return if !$in->ask_from_entries_refH(_("Remote lpd Printer Options"),
_("To use a remote lpd print queue, you need to supply
the hostname of the printer server and the queue name
on that server."), [
{ label => _("Remote hostname"), val => \$remotehost },
{ label => _("Remote queue"), val => \$remotequeue } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', _("Remote host name missing!"));
	return (1,0);
    }
    unless ($remotequeue ne "") {
	$in->ask_warn('', _("Remote queue name missing!"));
	return (1,1);
    }
    return 0;
}
			      );
    #- make the DeviceURI from user input.
    $printer->{currentqueue}{'connect'} = 
        "lpd://$remotehost/$remotequeue";

    #- LPD does not support filtered queues to a remote LPD server by itself
    #- It needs an additional program as "rlpr"
    $printer->{SPOOLER} eq 'lpd' and $in->do_pkgs->install('rlpr');

    1;
}

sub setup_smb {
    my ($printer, $in) = @_;

    my $uri;
    my $smbuser = "";
    my $smbpassword = "";
    my $workgroup = "";
    my $smbserver = "";
    my $smbserverip = "";
    my $smbshare = "";
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^smb:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*smb://(.*)$!;
	my $parameters = $1;
	# Get the user's login and password from the URI
	if ($parameters =~ m!([^@]*)@([^@]+)!) {
	    my $login = $1;
	    $parameters = $2;
	    if ($login =~ m!([^:]*):([^:]*)!) {
		$smbuser = $1;
		$smbpassword = $2;
	    } else {
		$smbuser = $login;
		$smbpassword = "";
	    }
	} else {
	    $smbuser = "";
	    $smbpassword = "";
	}
	# Get the workgroup, server, and share name
	if ($parameters =~ m!([^/]*)/([^/]+)/([^/]+)$!) {
	    $workgroup = $1;
	    $smbserver = $2;
	    $smbshare = $3;
	} elsif ($parameters =~ m!([^/]+)/([^/]+)$!) {
	    $workgroup = "";
	    $smbserver = $1;
	    $smbshare = $2;
	} else {
	    die "The \"smb://\" URI must at least contain the server name and the share name!\n";
	}
	if (network::is_ip($smbserver)) {
	    $smbserverip = $smbserver;
	    $smbserver = "";
	}
    }

    return if !$in->ask_from_entries_refH(_("SMB (Windows 9x/NT) Printer Options"),
_("To print to a SMB printer, you need to provide the
SMB host name (Note! It may be different from its
TCP/IP hostname!) and possibly the IP address of the print server, as
well as the share name for the printer you wish to access and any
applicable user name, password, and workgroup information."), [
{ label => _("SMB server host"), val => \$smbserver },
{ label => _("SMB server IP"), val => \$smbserverip },
{ label => _("Share name"), val => \$smbshare },
{ label => _("User name"), val => \$smbuser },
{ label => _("Password"), val => \$smbpassword, hidden => 1 },
{ label => _("Workgroup"), val => \$workgroup }, ],
complete => sub {
    unless ((network::is_ip($smbserverip)) || ($smbserverip eq "")) {
	$in->ask_warn('', _("IP address should be in format 1.2.3.4"));
	return (1,1);
    }
    unless (($smbserver ne "") || ($smbserverip ne "")) {
	$in->ask_warn('', _("Either the server name or the server's IP must be given!"));
	return (1,0);
    }
    unless ($smbshare ne "") {
	$in->ask_warn('', _("Samba share name missing!"));
	return (1,2);
    }
    return 0;
}
    );
    #- make the DeviceURI from, try to probe for available variable to
    #- build a suitable URI.
    $printer->{currentqueue}{'connect'} =
    join '', ("smb://", ($smbuser && ($smbuser . 
    ($smbpassword && ":$smbpassword") . "@")), ($workgroup && ("$workgroup/")),
    ($smbserver || $smbserverip), "/$smbshare");

    $in->do_pkgs->install('samba-client');
    $printer->{SPOOLER} eq 'cups' and printer::restart_queue($printer);
    1;
}

sub setup_ncp {
    my ($printer, $in) = @_;

    my $uri;
    my $ncpuser = "";
    my $ncppassword = "";
    my $ncpserver = "";
    my $ncpqueue = "";
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^ncp:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*ncp://(.*)$!;
	my $parameters = $1;
	# Get the user's login and password from the URI
	if ($parameters =~ m!([^@]*)@([^@]+)!) {
	    my $login = $1;
	    $parameters = $2;
	    if ($login =~ m!([^:]*):([^:]*)!) {
		$ncpuser = $1;
		$ncppassword = $2;
	    } else {
		$ncpuser = $login;
		$ncppassword = "";
	    }
	} else {
	    $ncpuser = "";
	    $ncppassword = "";
	}
	# Get the workgroup, server, and share name
	if ($parameters =~ m!([^/]+)/([^/]+)$!) {
	    $ncpserver = $1;
	    $ncpqueue = $2;
	} else {
	    die "The \"ncp://\" URI must at least contain the server name and the share name!\n";
	}
    }

    return if !$in->ask_from_entries_refH(_("NetWare Printer Options"),
_("To print on a NetWare printer, you need to provide the
NetWare print server name (Note! it may be different from its
TCP/IP hostname!) as well as the print queue name for the printer you
wish to access and any applicable user name and password."), [
{ label => _("Printer Server"), val => \$ncpserver },
{ label => _("Print Queue Name"), val => \$ncpqueue },
{ label => _("User name"), val => \$ncpuser },
{ label => _("Password"), val => \$ncppassword, hidden => 1 } ],
complete => sub {
    unless ($ncpserver ne "") {
	$in->ask_warn('', _("NCP server name missing!"));
	return (1,0);
    }
    unless ($ncpqueue ne "") {
	$in->ask_warn('', _("NCP queue name missing!"));
	return (1,1);
    }
    return 0;
}
					);
    # Generate the Foomatic URI
    $printer->{currentqueue}{'connect'} =
    join '', ("ncp://", ($ncpuser && ($ncpuser . 
    ($ncppassword && ":$ncppassword") . "@")),
    "$ncpserver/$ncpqueue");

    $in->do_pkgs->install('ncpfs');
    1;
}

sub setup_socket {
    my ($printer, $in) = @_;
    my ($hostname, $port);

    my $uri;
    my $remotehost;
    my $remoteport;
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^socket:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*socket://([^/:]+):([0-9]+)/?\s*$!;
	$remotehost = $1;
	$remoteport = $2;
    } else {
	$remotehost = "";
	$remoteport = "9100";
    }

    return if !$in->ask_from_entries_refH(_("Socket Printer Options"),
_("To print to a socket printer, you need to provide the
hostname of the printer and optionally the port number."), [
{ label => _("Printer Hostname"), val => \$remotehost },
{ label => _("Port"), val => \$remoteport } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', _("Printer host name missing!"));
	return (1,0);
    }
    unless ($remoteport =~ /^[0-9]+$/) {
	$in->ask_warn('', _("The port must be an integer number!"));
	return (1,1);
    }
    return 0;
}
					 );

    #- make the Foomatic URI
    $printer->{currentqueue}{'connect'} = 
    join '', ("socket://$remotehost", $remoteport ? (":$remoteport") : ());

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    $printer->{SPOOLER} eq 'lpd' || $printer->{SPOOLER} eq 'lprng' and $in->do_pkgs->install('nc');

    1;
}

sub setup_uri {
    my ($printer, $in) = @_;

    return if !$in->ask_from_entries_refH(_("Printer Device URI"),
_("You can specify directly the URI to access the printer. The URI must fulfill either the CUPS or the Foomatic specifications. Note that not all URI types are supported by all the spoolers."), [
{ label => _("Printer Device URI"),
val => \$printer->{currentqueue}{'connect'},
list => [ $printer->{currentqueue}{'connect'},
	  "file:/",
	  "http://",
	  "ipp://",
	  "lpd://",
	  "smb://",
	  "ncp://",
	  "socket://",
	  "postpipe:",
	  ], not_edit => 0 }, ],
complete => sub {
    unless ($printer->{currentqueue}{'connect'} =~ /[^:]+:.+/) {
	$in->ask_warn('', _("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );
    if ($printer->{currentqueue}{'connect'} =~ /^smb:/) {
        $in->do_pkgs->install('samba-client');
        printer::restart_queue($printer);
    }
    if ($printer->{currentqueue}{'connect'} =~ /^ncp:/) {
        $in->do_pkgs->install('ncpfs');
        printer::restart_queue($printer);
    }
    1;
}

sub setup_postpipe {
    my ($printer, $in) = @_;

    my $uri;
    my $commandline;
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^postpipe:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*postpipe:(.*)$!;
	$commandline = $1;
    } else {
	$commandline = "";
    }

    return if !$in->ask_from_entries_refH(_("Pipe into command"),
_("Here you can specify any arbitrary command line into which the job should be piped instead of being sent directly to a printer."), [
{ label => _("Command line"),
val => \$commandline }, ],
complete => sub {
    unless ($commandline ne "") {
	$in->ask_warn('', _("A command line must be entered!"));
	return (1,0);
    }
    return 0;
}
);

    #- make the Foomatic URI
    $printer->{currentqueue}{'connect'} = "postpipe:$commandline";
    
    1;
}

sub get_db_entry {
    my ($printer) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
        printer::read_printer_db($printer->{SPOOLER});
    }
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue}) {
	# The queue was already configured
	if ($printer->{configured}{$queue}{'queuedata'}{'foomatic'}) {
	    # The queue was configured with Foomatic
	    my $driverstr;
	    if ($printer->{configured}{$queue}{'driver'} eq "Postscript") {
		$driverstr = "PostScript";
	    } else {
		$driverstr =
		    "GhostScript + $printer->{configured}{$queue}{'driver'}";
	    }
	    my $make = $printer->{configured}{$queue}{'make'};
	    my $model =
		$printer->{configured}{$queue}{'model'};
	    if ($::expert) {
		$printer->{DBENTRY} = "$make|$model|$driverstr";
		# database key contains te "(recommended)" for the
		# recommended driver, so add it if necessary
		if (!($printer::thedb{$printer->{DBENTRY}}{id})) {
		    $printer->{DBENTRY} .= " (recommended)";
		}
	    } else {
		$printer->{DBENTRY} = "$make|$model";
		# Make sure that we use the recommended driver
		$printer->{currentqueue}{'driver'} =
		    $printer::thedb{$printer->{DBENTRY}}{driver};
	    }
	} elsif (($::expert) && ($printer->{SPOOLER} eq "cups")) {
	    # Do we have a native CUPS driver or a PostScript PPD file?
	    $printer->{DBENTRY} = printer::get_descr_from_ppd($printer) ||
		$printer->{DBENTRY};
	}
    } else {
	if (($::expert) && ($printer->{DBENTRY} !~ (recommended))) {
	    $printer->{DBENTRY} =~ /^([^\|]+)\|([^\|]+)\|/;
	    my $make = $1;
	    my $model = $2;
	    my $key;
	    for $key (keys %printer::thedb) {
		if ($key =~ /^$make\|$model\|.*\(recommended\)$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
    }
    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
}

sub choose_model {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
        printer::read_printer_db($printer->{SPOOLER});
    }
    $in->set_help('configurePrinterType') if $::isInstall;
    # Choose the printer/driver from the list

    return ($printer->{DBENTRY} = $in->ask_from_treelist
	(_("Printer model selection"),
	 _("Which printer model do you have?"), '|',
	 [ keys %printer::thedb ], $printer->{DBENTRY}));

}

sub get_printer_info {
    my ($printer) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
        printer::read_printer_db($printer->{SPOOLER});
    }
    my $queue = $printer->{OLD_QUEUE};
    my $oldchoice = $printer->{OLD_CHOICE};
    $printer->{currentqueue}{'id'} =
	$printer::thedb{$printer->{DBENTRY}}{id};
    $printer->{currentqueue}{'ppd'} =
	$printer::thedb{$printer->{DBENTRY}}{ppd};
    $printer->{currentqueue}{'driver'} =
	$printer::thedb{$printer->{DBENTRY}}{driver};
    $printer->{currentqueue}{'make'} =
	$printer::thedb{$printer->{DBENTRY}}{make};
    $printer->{currentqueue}{'model'} =
	$printer::thedb{$printer->{DBENTRY}}{model};
    if (($printer->{currentqueue}{'id'}) || # We have a Foomatic queue
	($printer->{currentqueue}{'ppd'})) { # We have a CUPS+PPD queue
	if ($printer->{currentqueue}{'id'}) { # Foomatic queue?
	    $printer->{currentqueue}{'foomatic'} = 1;
	    # Now get the options for this printer/driver combo
	    if (($printer->{configured}{$queue}) &&
		($printer->{configured}{$queue}{'queuedata'}{'foomatic'})) {
		# The queue was already configured with Foomatic ...
		if ($printer->{DBENTRY} eq $oldchoice) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} =
			$printer->{configured}{$queue}{'args'};
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} =
		      printer::read_foomatic_options($printer);
		}
	    } else {
		# The queue was not configured with Foomatic before
		$printer->{ARGS} = printer::read_foomatic_options($printer);
	    }
	} elsif ($printer->{currentqueue}{'ppd'}) { # CUPS+PPD queue?
	    # Now get the options from this PPD file
	    if ($printer->{configured}{$queue}) {
		# The queue was already configured
		if ($printer->{DBENTRY} eq $oldchoice) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} =
		        printer::read_cups_options($queue);
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} =
		        printer::read_cups_options
			    ("/usr/share/cups/model/" . 
			     $printer->{currentqueue}{ppd});
		}
	    } else {
		# The queue was not configured before
		$printer->{ARGS} =
		    printer::read_cups_options
			("/usr/share/cups/model/" . 
			 $printer->{currentqueue}{ppd});
	    }
	}
    }
}

sub setup_options {
    my ($printer, $in) = @_;
    $in->set_help('configurePrinterOptions') if $::isInstall;
    if (($printer->{currentqueue}{'id'}) || # We have a Foomatic queue
	($printer->{currentqueue}{'ppd'})) { # We have a CUPS+PPD queue
	# Set up the widgets for the option dialog
	my @widgets;
	my @userinputs;
	my @choicelists;
	my @shortchoicelists;
	my $i;
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    my $optshortdefault = $printer->{ARGS}[$i]{'default'};
	    if ($printer->{ARGS}[$i]{'type'} eq 'enum') {
		# enumerated option
		push(@choicelists, []);
		push(@shortchoicelists, []);
		my $choice;
		for $choice (@{$printer->{ARGS}[$i]{'vals'}}) {
		    push(@{$choicelists[$i]}, $choice->{'comment'});
		    push(@{$shortchoicelists[$i]}, $choice->{'value'});
		    if ($choice->{'value'} eq $optshortdefault) {
			push(@userinputs, $choice->{'comment'});
		    }
		}
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{'comment'}, 
		       val => \$userinputs[$i], 
		       not_edit => 1,
		       list => \@{$choicelists[$i]} });
	    } elsif ($printer->{ARGS}[$i]{'type'} eq 'bool') {
		# boolean option
		push(@choicelists, [$printer->{ARGS}[$i]{'name'}, 
				    $printer->{ARGS}[$i]{'name_false'}]);
		push(@shortchoicelists, []);
		push(@userinputs, $choicelists[$i][1-$optshortdefault]);
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{'comment'},
		       val => \$userinputs[$i],
		       not_edit => 1,
		       list => \@{$choicelists[$i]} });
	    } else {
		# numerical option
		push(@choicelists, []);
		push(@shortchoicelists, []);
		push(@userinputs, $optshortdefault);
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{'comment'} . 
			   " ($printer->{ARGS}[$i]{'min'} ... " .
			       "$printer->{ARGS}[$i]{'max'})",
			       #type => 'range',
			       #min => $printer->{ARGS}[$i]{'min'},
			       #max => $printer->{ARGS}[$i]{'max'},
			       val => \$userinputs[$i] } );
	    }
	}
	# Show the options dialog. The call-back function does a
	# range check of the numerical options.
	my $windowtitle;
	if ($::expert) {
	    $windowtitle = $printer->{DBENTRY};
	    $windowtitle =~ s/\|/ /;
	    $windowtitle =~ s/\|/, /;
	} else {
	    $windowtitle = "$printer->{currentqueue}{'make'} " .
		"$printer->{currentqueue}{'model'}"
		}
	return 0 if !$in->ask_from_entries_refH
	    ($windowtitle,
	     _("Printer options"), \@widgets,
	     complete => sub {
		 my $i;
		 for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
		     if (($printer->{ARGS}[$i]{'type'} eq 'int') ||
			 ($printer->{ARGS}[$i]{'type'} eq 'float')) {
			 unless
			     (($printer->{ARGS}[$i]{'type'} eq 'float') ||
			      ($userinputs[$i] =~ /^[0-9]+$/)) {
				 $in->ask_warn
				     ('', _("Option $printer->{ARGS}[$i]{'comment'} must be an integer number!"));
				 return (1, $i);
			     }
			 unless
			     (($printer->{ARGS}[$i]{'type'} eq 'int') ||
			      ($userinputs[$i] =~ /^[0-9\.]+$/)) {
				 $in->ask_warn
				     ('', _("Option $printer->{ARGS}[$i]{'comment'} must be a number!"));
				 return (1, $i);
			     }
			 unless (($userinputs[$i] >= 
				  $printer->{ARGS}[$i]{'min'}) &&
				 ($userinputs[$i] <= 
				  $printer->{ARGS}[$i]{'max'})) {
			     $in->ask_warn
				 ('', _("Option $printer->{ARGS}[$i]{'comment'} out of range!"));
			     return (1, $i);
			 }
		     }
		 }
		 return (0);
	     } );
	# Read out the user's choices
	@{$printer->{OPTIONS}} = ();
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    push(@{$printer->{OPTIONS}}, "-o");
	    if ($printer->{ARGS}[$i]{'type'} eq 'enum') {
		# enumerated option
		my $j;
		for ($j = 0; $j <= $#{$choicelists[$i]}; $j++) {
		    if ($choicelists[$i][$j] eq $userinputs[$i]) {
			push(@{$printer->{OPTIONS}},
			     $printer->{ARGS}[$i]{'name'} .
			     "=". $shortchoicelists[$i][$j]);
		    }
		}
	    } elsif ($printer->{ARGS}[$i]{'type'} eq 'bool') {
		# boolean option
		push(@{$printer->{OPTIONS}},
		     $printer->{ARGS}[$i]{'name'} .
		     "=". 
		     (($choicelists[$i][0] eq $userinputs[$i]) ?
		      "1" : "0"));
	    } else {
		# numerical option
		push(@{$printer->{OPTIONS}},
		     $printer->{ARGS}[$i]{'name'} .
		     "=" . $userinputs[$i]);
	    }
	}
    }
    1;
}

sub print_testpages {
    my ($printer, $in, $upNetwork) = @_;
    # print test pages
    my $standard = 1;
    my $altletter = 0;
    my $alta4 = 0;
    my $photo = 0;
    my $ascii = 0;
    if ($in->ask_from_entries_refH_powered
	({ title => _("Test pages"),
	   messages => _("Please select the test pages you want to print.
Note: the photo test page can take a rather long time to get printed
and on laser printers with too low memory it can even not come out.
In most cases it is enough to print the standard test page."),
          cancel => _("No test pages"),
          ok => _("Print")},
	 [
	  { text => _("Standard test page"), type => 'bool',
	    val => \$standard },
	  ($::expert ?
	   { text => _("Alternative test page (Letter)"), type => 'bool', 
	     val => \$altletter } : ()),
	  ($::expert ?
	   { text => _("Alternative test page (A4)"), type => 'bool', 
	     val => \$alta4 } : ()), 
	  { text => _("Photo test page"), type => 'bool', val => \$photo }
	  #{ text => _("Plain text test page"), type => 'bool',
	  #  val => \$ascii }
	  ])) {
	#	if ($in->ask_yesorno('', _("Do you want to print a test page?"), 1)) {
	my @lpq_output;
	{
	    my $w = $in->wait_message('', _("Printing test page(s)..."));
	    
	    $upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
	    my $stdtestpage = "/usr/share/printer-testpages/testprint.ps";
	    my $altlttestpage = "/usr/share/printer-testpages/testpage.ps";
	    my $alta4testpage = "/usr/share/printer-testpages/testpage-a4.ps";
	    my $phototestpage = "/usr/share/printer-testpages/photo-testpage.jpg";
	    my $asciitestpage = "/usr/share/printer-testpages/testpage.asc";
	    my @testpages;
	    # Install the filter to convert the photo test page to PS
	    $photo && $in->do_pkgs->install('ImageMagick');
	    # set up list of pages to print
	    $standard && push (@testpages, $stdtestpage);
	    $altletter && push (@testpages, $altlttestpage);
	    $alta4 && push (@testpages, $alta4testpage);
	    $photo && push (@testpages, $phototestpage);
	    $ascii && push (@testpages, $asciitestpage);
	    # print the stuff
	    @lpq_output = printer::print_pages($printer, @testpages);
	}
	
	if (@lpq_output) {
	    $in->ask_yesorno('',_("Test page(s) have been sent to the printer.
It may take some time before the printer starts.
Printing status:\n%s\n\nDoes it work properly?", @lpq_output), 1) and return 1;
	} else {
	    $in->ask_yesorno('', _("Test page(s) have been sent to the printer.
It may take some time before the printer starts.
Does it work properly?"), 1) and return 1;
	}
    } else {
	return 1;
    }
    return 0;
}

sub setup_gsdriver {
    my ($printer, $in, $upNetwork) = @_;
    my $queue = $printer->{OLD_QUEUE};
    while (1) {
	get_db_entry($printer);
	choose_model($printer, $in) || return;
	get_printer_info($printer);
	setup_options($printer, $in) || return;
	$printer->{complete} = 1;
	printer::configure_queue($printer);
	$printer->{complete} = 0;
	print_testpages($printer, $in, $upNetwork) && last;
    }
    $printer->{complete} = 1;
}

sub setup_default_spooler {
    my ($printer, $in) = @_;
    $printer->{SPOOLER} ||= 'cups';
    my $str_spooler = 
	$in->ask_from_list_(_("Select Printer Spooler"),
			    _("Which printing system (spooler) do you want to use?"),
			    [ printer::spooler() ],
			    $printer::spooler_inv{$printer->{SPOOLER}},
			    ) or return;
    $printer->{SPOOLER} = $printer::spooler{$str_spooler};
    # Install the spooler if not done yet
    install_spooler($printer, $in);
    # Get the queues of this spooler
    printer::read_configured_queues($printer);
    return $printer->{SPOOLER};
}

sub install_spooler {
    # installs the default spooler and start its daemon
    # TODO: Automatically transfer queues between LPRng and LPD,
    #       Turn off /etc/printcap writing in CUPS when LPD or
    #       LPRng is used (perhaps better to be done in CUPS/LPD/LPRng
    #       start-up scripts?)
    my ($printer, $in) = @_;
    if (!$::testing) {
	if ($printer->{SPOOLER} eq "cups") {
	    $in->do_pkgs->install(('cups', 'xpp', 'qtcups', 'kups',
		       ($::expert ? 'cups-drivers' : ())));
	    # Start daemon
	    printer::start_service("cups");
	    sleep 1;
	} elsif ($printer->{SPOOLER} eq "lpd") {
	    # "lpr" conflicts with "LPRng", remove "LPRng"
	    $in->do_pkgs->remove_nodeps('LPRng');
	    $in->do_pkgs->install('lpr');
	    # Start daemon
	    printer::restart_service("lpd");
	    sleep 1;
	} elsif ($printer->{SPOOLER} eq "lprng") {
	    # "LPRng" conflicts with "lpr", remove "lpr"
	    $in->do_pkgs->remove_nodeps('lpr');
	    $in->do_pkgs->install('LPRng');
	    # Start daemon
	    printer::restart_service("lpd");
	    sleep 1;
	} elsif ($printer->{SPOOLER} eq "pdq") {
	    $in->do_pkgs->install('pdq');
	    # PDQ has no daemon
	}
    }
}

#- Program entry point for configuration with of the printing system.
sub main {
    my ($printer, $in, $ask_multiple_printer, $upNetwork) = @_;

    # printerdrake does not work without foomatic, and for more convenience
    # we install some more stuff
    if (!$::testing) {
	$in->do_pkgs->install('foomatic', 'printer-utils','printer-testpages',
			      if_($in->do_pkgs->is_installed('gimp'), 'gimpprint'));
    }

    # only experts should be asked for the spooler
    !$::expert && ($printer->{SPOOLER} ||= 'cups');

    # If we have chosen a spooler, install it.
    if (($printer->{SPOOLER}) && ($printer->{SPOOLER} ne '')) {
	install_spooler($printer, $in);
    }

    my ($queue, $continue, $newqueue) = ('', 1, 0);
    while ($continue) {
	$newqueue = 0;
	# When the queue list is not shown, cancelling the printer type
	# dislog should leave the program
	$continue = 0;
	if (!$ask_multiple_printer && %{$printer->{configured} || {}} == ()) {
	    $newqueue = 1;
	    $queue = $printer->{want} || 
		$in->ask_yesorno(_("Printer"),
				 _("Would you like to configure printing?"),
				 0) ? 'lp' : _("Done");
	    if ($queue ne _("Done")) {
		$printer->{SPOOLER} ||= 
		    setup_default_spooler ($printer, $in) ||
			return;
	    }
	} else {
	    # Ask for a spooler when none is defined
	    $printer->{SPOOLER} ||= 
		setup_default_spooler ($printer, $in) ||
		    return;
	    # Show a queue list window when there is at least one queue
	    # or when we are in expert mode
	    unless ((%{$printer->{configured} || {}} == ()) && (!$::expert)) {
		# Cancelling the printer type dialog should leed to this
		# dialog
		$continue = 1;
		$in->ask_from_entries_refH_powered(
		    {messages =>
                      _("The following printers are configured.\nYou can add some more or modify the existing ones."),
		      cancel => '',
		    },
		    # List the queues
                    [ { val => \$queue, format => \&translate,
		        list => [ (sort keys %{$printer->{configured} || {}}),
		    # Button to add a new queue
		    _("Add printer"),
		    # In expert mode we can change the spooler
		    ($::expert ?
		     ( _("Spooler: ") .
		       $printer::spooler_inv{$printer->{SPOOLER}} ) : ()),
		    # Bored by configuring your printers, get out of here!
		    _("Done") ] } ]
		);
	    } else {
		#- as there are no printer already configured, Add one
		#- automatically.
		$queue = _("Add printer"); 
	    } 
	                                         
	    if ($queue eq _("Add printer")) {
		$newqueue = 1;
		my %queues; 
		@queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
		my $i = ''; while ($i < 100) { last unless exists $queues{"lp$i"}; ++$i; }
		$queue = "lp$i";
	    }
	    if ($queue =~ /^Spooler: /) {
		$printer->{SPOOLER} =
		    setup_default_spooler ($printer, $in) || 
			$printer->{SPOOLER};
		next;
	    }
	}
	# Save the default spooler
	printer::set_default_spooler($printer);
	#- Close printerdrake
	$queue eq _("Done") and last;

	if ($newqueue) {
	    #- Set default values for a new queue
	    $printer::printer_type_inv{$printer->{TYPE}} or 
		$printer->{TYPE} = printer::default_printer_type($printer);
	    $printer->{currentqueue} = {};
	    $printer->{currentqueue}{'queue'} = $queue;
	    $printer->{currentqueue}{'foomatic'} = 0;
	    $printer->{currentqueue}{'desc'} = "";
	    $printer->{currentqueue}{'loc'} = "";
	    $printer->{currentqueue}{'make'} = "";
	    $printer->{currentqueue}{'model'} = "";
	    $printer->{currentqueue}{'spooler'} =
		$printer->{SPOOLER};
	    #- Set OLD_QUEUE field so that the subroutines for the
	    #- configuration work correctly.
	    $printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
	    #- Do all the configuration steps for a new queue
	    choose_printer_type($printer, $in) or next;
	    #- Cancelling one of the following dialogs should restart 
	    #- printerdrake
	    $continue = 1;
	    if ($printer->{TYPE} eq 'CUPS') {
		if (setup_remote_cups_server($printer, $in)) {
		    $continue = $::expert || !$::isInstall;
		} else {
		    $continue = 1;
		}
		next;
	    }
	    setup_printer_connection($printer, $in) or next;
	    choose_printer_name($printer, $in) or next;
	    
	    #- configure the printer driver
	    if (setup_gsdriver($printer, $in,
			       $printer->{TYPE} !~ /LOCAL/ && $upNetwork)) {
		#if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
		#    printer::remove_queue($printer, $printer->{OLD_QUEUE});
		#}
		#delete $printer->{OLD_QUEUE}
	        #   if (($printer->{QUEUE} ne $printer->{OLD_QUEUE}) && 
		#       ($printer->{configured}{$printer->{QUEUE}}));
		$continue = $::expert || !$::isInstall;
	    } else {
		$continue = 1;
	    }
	} else {
	    # Modify a queue, ask which part should be modified
	    my $modify = _("Printer options");
	    while ($in->ask_from_entries_refH_powered
		   ({ title => _("Modify printer"),
		      messages => _("Printer %s: %s %s
What do you want to modify on this printer?",
				    $queue,
				    $printer->{configured}{$queue}{make},
				    $printer->{configured}{$queue}{model}),
		     cancel => _("Close"),
		     ok => _("Do it!")
		     },
		    [ { val => \$modify, format => \&translate,
			list => [ _("Printer connection type"),
				  _("Printer name, description, location"),
				  ($::expert ?
				   _("Printer manufacturer, model, driver") :
				   _("Printer manufacturer, model")),
				  _("Printer options"),
				  _("Print test pages"),
				  _("Remove printer") ] } ] ) ) {
		#- Copy the queue data and work on the copy
		$printer->{currentqueue} = {};
	        printer::copy_printer_params
		  ($printer->{configured}{$queue}{'queuedata'},
		   $printer->{currentqueue})
		      if $printer->{configured}{$queue};
		#- keep in mind old name of queue (in case of changing)
		$printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
		#- Which printer type did we have before (check beginning of 
		#- URI)
		my $type;
		for $type (qw(file lpd socket smb ncp postpipe)) {
		    if ($printer->{currentqueue}{'connect'}
			=~ /^$type:/) {
			$printer->{TYPE} = 
			    ($type eq 'file' ? 'LOCAL' : uc($type));
			last;
		    }
		}
		# Get all info about the printer model and options
		get_db_entry($printer);
		get_printer_info($printer);
		# Do the chosen task
		if ($modify eq _("Printer connection type")) {
		    choose_printer_type($printer, $in) &&
			setup_printer_connection($printer, $in) && do {
			    $printer->{complete} = 1;
			    printer::configure_queue($printer);
			    $printer->{complete} = 0;
			}
		} elsif ($modify eq _("Printer name, description, location")) {
		    choose_printer_name($printer, $in) && do {
			$printer->{complete} = 1;
		        printer::configure_queue($printer);
			$printer->{complete} = 0;
		    };
		    # Delete old queue when it was renamed
		    if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
		        printer::remove_queue($printer, $printer->{OLD_QUEUE});
			$queue = $printer->{QUEUE};
		    }
		} elsif (($modify eq
			  _("Printer manufacturer, model, driver")) ||
			 ($modify eq _("Printer manufacturer, model"))) {
		    choose_model($printer, $in) && do {
			get_printer_info($printer);
			setup_options($printer, $in) && do {
			    $printer->{complete} = 1;
			    printer::configure_queue($printer);
			    $printer->{complete} = 0;
			}
		    }
		} elsif ($modify eq _("Printer options")) {
		    get_printer_info($printer);
		    setup_options($printer, $in) && do {
			$printer->{complete} = 1;
		        printer::configure_queue($printer);
			$printer->{complete} = 0;
		    }
		} elsif ($modify eq _("Print test pages")) {
		    print_testpages($printer, $in, $upNetwork);
		} elsif ($modify eq _("Remove printer")) {
		    $in->ask_yesorno('',
	   _("Do you really want to remove the printer \"%s\"?", $queue), 1) &&
		      printer::remove_queue($printer, $queue) && last;
		}
		# Reinitialize $printer data structure
	        printer::resetinfo($printer);
	    }
	}
	if ($continue) {
	    # Reinitialize $printer data structure
	    printer::resetinfo($printer);
	}
    }
}

