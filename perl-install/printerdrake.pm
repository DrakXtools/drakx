package printerdrake;
# $Id$

use diagnostics;
use strict;

use common;
use detect_devices;
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
here; these printers will be automatically detected. Please
select \"Printer on remote CUPS server\" in this case.") : ()),
			    [ printer::printer_type($printer) ],
			    $printer->{str_type},
			    ) or return 0;
    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
    1;
}

sub setup_remote_cups_server {
    my ($printer, $in) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in)) {return 0};

    $in->set_help('configureRemoteCUPSServer') if $::isInstall;
    my $queue = $printer->{OLD_QUEUE};
    #- hack to handle cups remote server printing,
    #- first read /etc/cups/cupsd.conf for variable BrowsePoll address:port
    my ($server, $port, $default, $autoconf);
    # Return value: 0 when nothing was changed ("Apply" never pressed), 1
    # when "Apply" was at least pressed once.
    my $retvalue = 0;
    while (1) {
	# Read CUPS config file
	my @cupsd_conf = printer::read_cupsd_conf();
	foreach (@cupsd_conf) {
	    /^\s*BrowsePoll\s+(\S+)/ and $server = $1, last;
	}
	$server =~ /([^:]*):(.*)/ and ($server, $port) = ($1, $2);
	# Read printer list
	my @queuelist = printer::read_cups_printer_list();
	if ($#queuelist >=0) {
	    if ($printer->{DEFAULT} eq '') {
		$default = printer::get_default_printer($printer);
		if ($default) {
		    # If a CUPS system has only remote printers and no default
		    # printer defined, it defines the first printer whose
		    # broadcast signal appeared after the start of the CUPS
		    # daemon, so on every start another printer gets the
		    # default printer. To avoid this, make sure that the
		    # default printer is defined.
		    $printer->{DEFAULT} = $default;
		    printer::set_default_printer($printer);
		}
	    } else {
		$default = $printer->{DEFAULT};
	    }
	    my $queue;
	    for $queue (@queuelist) {
		if ($queue =~ /^\s*$default/) {
		    $default = $queue;
		}
	    }
	    # The default printer setting should not be "None" when there
	    # are printers
	    if ($default eq _("None")) {
		$default = _("Choose a default printer!");
	    }
	} else {
	    push(@queuelist, _("None"));
	    $default = _("None");
	}
	#- Did we have automatic or manual configuration mode for CUPS
	$autoconf = printer::get_cups_autoconf();
	#- Remember the server/port/autoconf settings to check whether the user
        #- has changed them.
	my $oldserver = $server;
	my $oldport = $port;
	my $oldautoconf = $autoconf;

        #- then ask user for this combination and rewrite /etc/cups/cupsd.conf
	#- according to new settings. There are no other point where such
	#- information is written in this file.

	if ($in->ask_from_
	    ({ title => _("Remote CUPS server"),
	       messages => _("With remote CUPS servers, you do not have to configure any 
printer here; CUPS servers inform your machine automatically
about their printers. All printers known to your machine
currently are listed in the \"Default printer\" field. Choose
the default printer for your machine there and click the
\"Apply/Re-read printers\" button. Click the same button to
refresh the list (it can take up to 30 seconds after the start
of CUPS until all remote printers are visible).
When your CUPS server is in a different network, you have to 
give the CUPS server IP address and optionally the port number
to get the printer information from the server, otherwise leave
these fields blank.") .
              ($::expert ? _("
Normally, CUPS is automatically configured according to your
network environment, so that you can access the printers on the
CUPS servers in your local network. If this does not work 
correctly, turn off \"Automatic CUPS configuration\" and edit
your file /etc/cups/cupsd.conf manually. Do not forget to restart
CUPS afterwards (command: \"service cups restart\").") : ()),
              cancel => _("Close"),
              ok => _("Apply/Re-read printers"),
	      callbacks => { complete => sub {
		 unless (!$server || network::is_ip($server)) {
		     $in->ask_warn('', 
			_("The IP address should look like 192.168.1.20"));
		     return (1,0);
		 }
		 if ($port !~ /^\d*$/) {
		     $in->ask_warn('',
			_("The port number should be an integer!"));
		     return (1,1);
		 }
		 return 0;
	     } }
	   },
	     [	
		{ label => _("Default printer"), val => \$default,
		  not_edit => 0, list => \@queuelist},
		#{ label => _("Default printer") },
		#{ val => \$default,
		#  format => \&translate, not_edit => 0, list => \@queuelist},
		{ label => _("CUPS server IP"), val => \$server },
		{ label => _("Port"), val => \$port },
		($::expert ?
		{ text => _("Automatic CUPS configuration"), type => 'bool',
		  val => \$autoconf } : ()),
		]
	     )) {
	    # We have clicked "Apply/Re-read"
	    $retvalue = 1;
	    # Set default printer
	    if ($default =~ /^\s*([^\s\(\)]+)\s*\(/) {
		$default = $1;
	    }
	    if (($default ne _("None")) &&
		($default ne _("Choose a default printer!"))) {
		$printer->{DEFAULT} = $default;
	        printer::set_default_printer($printer);
	    }
	    # Set BrowsePoll line
	    if (($server ne $oldserver) || ($port ne $oldport)) {
		$server && $port and $server = "$server:$port";
		if ($server) {
		    @cupsd_conf = 
			map { $server and 
			      s/^\s*BrowsePoll\s+(\S+)/BrowsePoll $server/ and
				  $server = '';
			      $_ } @cupsd_conf;
		    $server and push @cupsd_conf, "\nBrowsePoll $server\n";
		} else {
		    @cupsd_conf = 
			map { s/^\s*BrowsePoll\s+(\S+)/\#BrowsePoll $1/;
			      $_ } @cupsd_conf;
		}
	        printer::write_cupsd_conf(@cupsd_conf);
		sleep 3;
	    }
	    # Set auto-configuration state
	    if ($autoconf != $oldautoconf) {
	        printer::set_cups_autoconf($autoconf);
	    }
	} else {
	    last;
	}
    }
    # Save user settings for auto-install
    $printer->{BROWSEPOLLADDR} = $server;
    $printer->{BROWSEPOLLPORT} = $port;
    $printer->{MANUALCUPSCONFIG} = 1 - $autoconf;
    return $retvalue;
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
	my $w = $in->wait_message(_("Test ports"), _("Detecting devices ..."));
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
    my (@port, @str, $device);
    my $queue = $printer->{OLD_QUEUE};
    my @parport = auto_detect($in);
    $in->set_help('setupLocal') if $::isInstall;
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
	return if !$in->ask_from(_("Local Printer Device"),
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
	my $w = $in->wait_message('', _("Reading printer database ..."));
        printer::read_printer_db($printer->{SPOOLER});
    }

    #- Search the database entry which matches the detected printer best
    foreach (@parport) {
	$device eq $_->{port} or next;
        $printer->{DBENTRY} =
            bestMatchSentence ($_->{val}{DESCRIPTION}, keys %printer::thedb);
        # If the manufacturer was not guessed correctly, discard the
        # guess.
        #$printer->{DBENTRY} =~ /^([\|])|/;
        #if ($_->{val}{DESCRIPTION} !~ /lc($1)/i) {$printer->{DBENTRY} = ""};
    }
    1;
}

sub setup_lpd {
    my ($printer, $in) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in)) {return 0};

    $in->set_help('setupLPD') if $::isInstall;
    my ($uri, $remotehost, $remotequeue);
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

    return if !$in->ask_from(_("Remote lpd Printer Options"),
_("To use a remote lpd printer, you need to supply
the hostname of the printer server and the printer name
on that server."), [
{ label => _("Remote host name"), val => \$remotehost },
{ label => _("Remote printer name"), val => \$remotequeue } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', _("Remote host name missing!"));
	return (1,0);
    }
    unless ($remotequeue ne "") {
	$in->ask_warn('', _("Remote printer name missing!"));
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
    if (($printer->{SPOOLER} eq 'lpd') && (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/rlpr))))) {
        $in->do_pkgs->install('rlpr');
    }

    1;
}

sub setup_smb {
    my ($printer, $in) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in)) {return 0};

    $in->set_help('setupSMB') if $::isInstall;
    my ($uri, $smbuser, $smbpassword, $workgroup, $smbserver, $smbserverip, $smbshare);
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

    return if !$in->ask_from(_("SMB (Windows 9x/NT) Printer Options"),
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

    if ((!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	$in->do_pkgs->install('samba-client');
    }
    $printer->{SPOOLER} eq 'cups' and printer::restart_queue($printer);
    1;
}

sub setup_ncp {
    my ($printer, $in) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in)) {return 0};

    $in->set_help('setupNCP') if $::isInstall;
    my ($uri, $ncpuser, $ncppassword, $ncpserver, $ncpqueue);
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^ncp:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	my $parameters = $uri =~ m!^\s*ncp://(.*)$!;
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

    return if !$in->ask_from(_("NetWare Printer Options"),
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

    if ((!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nprint))))) {
	$in->do_pkgs->install('ncpfs');
    }

    1;
}

sub setup_socket {
    my ($printer, $in) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in)) {return 0};

    $in->set_help('setupSocket') if $::isInstall;
    my ($hostname, $port, $uri, $remotehost,$remoteport);
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^socket:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	($remotehost, $remoteport) = $uri =~ m!^\s*socket://([^/:]+):([0-9]+)/?\s*$!;
    } else {
	$remotehost = "";
	$remoteport = "9100";
    }

    return if !$in->ask_from(_("Socket Printer Options"),
_("To print to a socket printer, you need to provide the
host name of the printer and optionally the port number.
On HP JetDirect servers the port number is usually 9100,
on other servers it can vary. See the manual of your
hardware."), [
{ label => _("Printer host name"), val => \$remotehost },
{ label => _("Port"), val => \$remoteport } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', _("Printer host name missing!"));
	return (1,0);
    }
    unless ($remoteport =~ /^[0-9]+$/) {
	$in->ask_warn('', _("The port number should be an integer!"));
	return (1,1);
    }
    return 0;
}
					 );

    #- make the Foomatic URI
    $printer->{currentqueue}{'connect'} = 
    join '', ("socket://$remotehost", $remoteport ? (":$remoteport") : ());

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if ((($printer->{SPOOLER} eq 'lpd') || ($printer->{SPOOLER} eq 'lprng'))&& 
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nc))))) {
        $in->do_pkgs->install('nc');
    }

    1;
}

sub setup_uri {
    my ($printer, $in) = @_;

    $in->set_help('setupURI') if $::isInstall;
    return if !$in->ask_from(_("Printer Device URI"),
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
	  "postpipe:\"\"",
	  ], not_edit => 0 }, ],
complete => sub {
    unless ($printer->{currentqueue}{'connect'} =~ /[^:]+:.+/) {
	$in->ask_warn('', _("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );

    # Non-local printer, check network and abort if no network available
    if (($printer->{currentqueue}{'connect'} !~ m!^file:/!) &&
        (!check_network($printer, $in))) {return 0};

    # If the chosen protocol needs additional software, install it.

    # LPD does not support filtered queues to a remote LPD server by itself
    # It needs an additional program as "rlpr"
    if (($printer->{currentqueue}{'connect'} =~ /^lpd:/) &&
	($printer->{SPOOLER} eq 'lpd') && (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/rlpr))))) {
        $in->do_pkgs->install('rlpr');
    }
    if (($printer->{currentqueue}{'connect'} =~ /^smb:/) &&
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	$in->do_pkgs->install('samba-client');
    }
    if (($printer->{currentqueue}{'connect'} =~ /^ncp:/) &&
	(!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nprint))))) {
	$in->do_pkgs->install('ncpfs');
    }
    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if (($printer->{currentqueue}{'connect'} =~ /^socket:/) &&
	(($printer->{SPOOLER} eq 'lpd') || ($printer->{SPOOLER} eq 'lprng')) &&
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nc))))) {
        $in->do_pkgs->install('nc');
    }
    1;
}

sub setup_postpipe {
    my ($printer, $in) = @_;

    $in->set_help('setupPostpipe') if $::isInstall;
    my $uri;
    my $commandline;
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{'connect'} =~ m/^postpipe:/)) {
	$uri = $printer->{currentqueue}{'connect'};
	$uri =~ m!^\s*postpipe:\"(.*)\"$!;
	$commandline = $1;
    } else {
	$commandline = "";
    }

    return if !$in->ask_from(_("Pipe into command"),
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

sub choose_printer_name {
    my ($printer, $in) = @_;
    # Name, description, location
    $in->set_help('setupPrinterName') if $::isInstall;
    my $default = $printer->{currentqueue}{'queue'};
    $in->ask_from_
	(
	 { title => _("Enter Printer Name and Comments"),
	   #cancel => !$printer->{configured}{$queue} ? '' : _("Remove queue"),
	   callbacks => { complete => sub {
	       unless ($printer->{currentqueue}{'queue'} =~ /^\w+$/) {
		   $in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
		   return (1,0);
	       }
	       if (($printer->{configured}{$printer->{currentqueue}{'queue'}})
		   && ($printer->{currentqueue}{'queue'} ne $default) && 
		   (!$in->ask_yesorno('', _("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
					    $printer->{currentqueue}{'queue'}),
				      0))) {
		   return (1,0); # Let the user correct the name
	       }
	       return 0;
	   },
		      },
	   messages =>
_("Every printer needs a name (for example lp).
The Description and Location fields do not need 
to be filled in. They are comments for the users.") }, 
	 [ { label => _("Name of printer"), val => \$printer->{currentqueue}{'queue'} },
	   { label => _("Description"), val => \$printer->{currentqueue}{'desc'} },
	   { label => _("Location"), val => \$printer->{currentqueue}{'loc'} },
	 ]) or return 0;

    $printer->{QUEUE} = $printer->{currentqueue}{'queue'};
    1;
}

sub get_db_entry {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
	my $w = $in->wait_message('', _("Reading printer database ..."));
        printer::read_printer_db($printer->{SPOOLER});
    }
    my $w = $in->wait_message('', _("Preparing printer database ..."));
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue}) {
	# The queue was already configured
	if ($printer->{configured}{$queue}{'queuedata'}{'foomatic'}) {
	    # The queue was configured with Foomatic
	    my $driverstr;
	    if ($printer->{configured}{$queue}{'queuedata'}{'driver'} eq "Postscript") {
		$driverstr = "PostScript";
	    } else {
		$driverstr = "GhostScript + $printer->{configured}{$queue}{'queuedata'}{'driver'}";
	    }
	    my $make = uc($printer->{configured}{$queue}{'queuedata'}{'make'});
	    my $model =	$printer->{configured}{$queue}{'queuedata'}{'model'};
	    if ($::expert) {
		$printer->{DBENTRY} = "$make|$model|$driverstr";
		# database key contains the "(recommended)" for the
		# recommended driver, so add it if necessary
		if (!($printer::thedb{$printer->{DBENTRY}}{printer})) {
		    $printer->{DBENTRY} .= " (recommended)";
		}
	    } else {
		$printer->{DBENTRY} = "$make|$model";
	    }
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} elsif (($printer->{SPOOLER} eq "cups") && ($::expert) &&
		 ($printer->{configured}{$queue}{'queuedata'}{'ppd'})) {
	    # Do we have a native CUPS driver or a PostScript PPD file?
	    $printer->{DBENTRY} = printer::get_descr_from_ppd($printer) || $printer->{DBENTRY};
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} else {
	    # Point the list cursor at least to manufacturer and model of the
	    # printer
	    $printer->{DBENTRY} = "";
	    my $make = uc($printer->{configured}{$queue}{'queuedata'}{'make'});
	    my $model = $printer->{configured}{$queue}{'queuedata'}{'model'};
	    my $key;
	    for $key (keys %printer::thedb) {
		if ((($::expert) && ($key =~ /^$make\|$model\|.*\(recommended\)$/)) ||
		    ((!$::expert) && ($key =~ /^$make\|$model$/))) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	    if ($printer->{DBENTRY} eq "") {
		# Exact match of make and model did not work, try to clean
		# ups the model name
		$model =~ s/PS//;
		$model =~ s/PostScript//;
		$model =~ s/Series//;
		for $key (keys %printer::thedb) {
		    if ((($::expert) && ($key =~ /^$make\|$model\|.*\(recommended\)$/)) ||
			((!$::expert) && ($key =~ /^$make\|$model$/))) {
			$printer->{DBENTRY} = $key;
		    }
		}
	    }
	    if (($printer->{DBENTRY} eq "") && 0) {
		# Exact match with cleaned-up model did not work, try a best match
		$printer->{DBENTRY} = bestMatchSentence("$make|$model", keys %printer::thedb);
		# If the manufacturer was not guessed correctly, discard the
		# guess.
		$printer->{DBENTRY} =~ /^([\|])|/;
		if (lc($1) ne lc($make)) {$printer->{DBENTRY} = ""};
	    }
	    # Set the OLD_CHOICE to a non-existing value
	    $printer->{OLD_CHOICE} = "XXX";
	}
    } else {
	if (($::expert) && ($printer->{DBENTRY} !~ /(recommended)/)) {
	    my ($make, $model) = $printer->{DBENTRY} =~ /^([^\|]+)\|([^\|]+)\|/;
	    for my $key (keys %printer::thedb) {
		if ($key =~ /^$make\|$model\|.*\(recommended\)$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
	$printer->{OLD_CHOICE} = $printer->{DBENTRY};
    }
}

sub choose_model {
    my ($printer, $in) = @_;
    $in->set_help('chooseModel') if $::isInstall;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
	my $w = $in->wait_message('', _("Reading printer database ..."));
        printer::read_printer_db($printer->{SPOOLER});
    }
    if (!$printer::thedb{$printer->{DBENTRY}}) {
	$printer->{DBENTRY} = _("Raw printer (No driver)");
    }
    # Choose the printer/driver from the list
    return ($printer->{DBENTRY} = $in->ask_from_treelist(_("Printer model selection"),
							 _("Which printer model do you have?"), '|',
							 [ keys %printer::thedb ], $printer->{DBENTRY}));

}

sub get_printer_info {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    #if ((keys %printer::thedb) == 0) {
    #    my $w = $in->wait_message('', _("Reading printer database ..."));
    #    printer::read_printer_db($printer->{SPOOLER});
    #}
    my $queue = $printer->{OLD_QUEUE};
    my $oldchoice = $printer->{OLD_CHOICE};
    my $newdriver = 0;
    if ((!$printer->{configured}{$queue}) ||      # New queue  or
	(($oldchoice) && ($printer->{DBENTRY}) && # make/model/driver changed
	 (($oldchoice ne $printer->{DBENTRY}) ||
	  ($printer->{currentqueue}{'driver'} ne 
	   $printer::thedb{$printer->{DBENTRY}}{'driver'})))) {
	delete($printer->{currentqueue}{printer});
	delete($printer->{currentqueue}{ppd});
	$printer->{currentqueue}{foomatic} = 0;
	# Read info from printer database
	foreach (qw(printer ppd driver make model)) { #- copy some parameter, shorter that way...
	    $printer->{currentqueue}{$_} = $printer::thedb{$printer->{DBENTRY}}{$_};
	}
	$newdriver = 1;
    }
    # Use the "printer" and not the "foomatic" field to identify a Foomatic
    # queue because in a new queue "foomatic" is not set yet.
    if (($printer->{currentqueue}{'printer'}) || # We have a Foomatic queue
	($printer->{currentqueue}{'ppd'})) { # We have a CUPS+PPD queue
	if ($printer->{currentqueue}{'printer'}) { # Foomatic queue?
	    # In case of a new queue "foomatic" was not set yet
	    $printer->{currentqueue}{'foomatic'} = 1;
	    # Now get the options for this printer/driver combo
	    if (($printer->{configured}{$queue}) && ($printer->{configured}{$queue}{'queuedata'}{'foomatic'})) {
		# The queue was already configured with Foomatic ...
		if (!$newdriver) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = $printer->{configured}{$queue}{'args'};
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::read_foomatic_options($printer);
		}
	    } else {
		# The queue was not configured with Foomatic before
		# Set some special options
		$printer->{SPECIAL_OPTIONS} = '';
		# Default page size depending on the country/language
		# (US/Canada -> Letter, Others -> A4)
		my $pagesize;
		if ($printer->{PAPERSIZE}) {
		    $printer->{SPECIAL_OPTIONS} .= 
			" -o PageSize=$printer->{PAPERSIZE}";
		} elsif (($in->{lang}) ||
			 ($pagesize = $ENV{'LC_PAPER'}) ||
			 ($pagesize = $ENV{'LANG'}) ||
			 ($pagesize = $ENV{'LANGUAGE'}) ||
			 ($pagesize = $ENV{'LC_ALL'})) {
		    if (($pagesize eq 'en') || ($pagesize eq 'en_US')) {
			$pagesize = "Letter";
		    } else {
			$pagesize = "A4";
		    }
		    $printer->{SPECIAL_OPTIONS} .= 
			" -o PageSize=$pagesize";
		}
		# oki4w driver -> OKI winprinter which needs the
		# oki4daemon to work
		if ($printer->{currentqueue}{'driver'} eq 'oki4w') {
		    if ($printer->{currentqueue}{'connect'} ne 
			'file:/dev/lp0') {
			$in->ask_warn(_("OKI winprinter configuration"),
				      _("You are configuring an OKI laser winprinter. These printers\nuse a very special communication protocol and therefore they
work only when connected to the first parallel port. When
your printer is connected to another port or to a print
server box please connect the printer to the first parallel
port before you print a test page. Otherwise the printer
will not work. Your connection type setting will be ignored
by the driver."));
		    }
		    $printer->{currentqueue}{'connect'} = 'file:/dev/null';
		    # Start the oki4daemon
		    printer::start_service_on_boot('oki4daemon');
		    printer::start_service('oki4daemon');
		    # Set permissions
		    if ($printer->{SPOOLER} eq 'cups') {
			printer::set_permissions('/dev/oki4drv', '660', 'lp',
						 'sys');
		    } elsif ($printer->{SPOOLER} eq 'pdq') {
			printer::set_permissions('/dev/oki4drv', '666');
		    } else {
			printer::set_permissions('/dev/oki4drv', '660', 'lp',
						 'lp');
		    }
		} elsif ($printer->{currentqueue}{'driver'} eq 'lexmarkinkjet') {
		    # Set "Port" option
		    if ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/lp0') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort1";
		    } elsif ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/lp1') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort2";
		    } elsif ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/lp2') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort3";
		    } elsif ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/usb/lp0') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB1";
		    } elsif ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/usb/lp1') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB2";
		    } elsif ($printer->{currentqueue}{'connect'} eq 
			'file:/dev/usb/lp2') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB3";
		    } else {
			$in->ask_warn(_("Lexmark inkjet configuration"),
				      _("The inkjet printer drivers provided by Lexmark only support
local printers, no printers on remote machines or print server
boxes. Please connect your printer to a local port or
configure it on the machine where it is connected to."));
			return 0;
		    }
		    # Set device permissions
		    $printer->{currentqueue}{'connect'} =~ /^\s*file:(\S*)\s*$/;
		    if ($printer->{SPOOLER} eq 'cups') {
			printer::set_permissions($1, '660', 'lp', 'sys');
		    } elsif ($printer->{SPOOLER} eq 'pdq') {
			printer::set_permissions($1, '666');
		    } else {
			printer::set_permissions($1, '660', 'lp', 'lp');
		    }
		    # This is needed to have the device not blocked by the
		    # spooler backend.
		    $printer->{currentqueue}{'connect'} = 'file:/dev/null';
		    #install packages
		    my $drivertype = $printer->{currentqueue}{'model'};
		    if ($drivertype eq 'Z22') {$drivertype = 'Z32';}
		    if ($drivertype eq 'Z23') {$drivertype = 'Z33';}
		    $drivertype = lc($drivertype);
		    if (!printer::files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			eval { $in->do_pkgs->install("lexmark-drivers-$drivertype") };
		    }
		    if (!printer::files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			# Driver installation failed, probably we do not have
			# the commercial CDs
			$in->ask_warn(_("Lexmark inkjet configuration"),
				      _("To be able to print with your Lexmark inkjet and this
configuration, you need the inkjet printer drivers
provided by Lexmark (http://www.lexmark.com/). Go to
the US site and click on the \"Drivers\" button. Then
choose your model and afterwards \"Linux\" as
operating system. The drivers come as RPM packages
or shell scripts with interactive graphical installation.
You do not need to do this configuration by the
graphical frontends. Cancel directly after the license
agreement. Then print printhead alignment pages with
\"lexmarkmaintain\" and adjust the head alignment
settings with this program."));
		    }
		}
		$printer->{ARGS} = printer::read_foomatic_options($printer);
		delete($printer->{SPECIAL_OPTIONS});
	    }
	} elsif ($printer->{currentqueue}{'ppd'}) { # CUPS+PPD queue?
	    # If we had a Foomatic queue before, unmark the flag and initialize
	    # the "printer" and "driver" fields
	    $printer->{currentqueue}{'foomatic'} = 0;
	    $printer->{currentqueue}{'printer'} = undef;
	    $printer->{currentqueue}{'driver'} = "CUPS/PPD";
	    # Now get the options from this PPD file
	    if ($printer->{configured}{$queue}) {
		# The queue was already configured
		if ((!$printer->{DBENTRY}) || (!$oldchoice) ||
		    ($printer->{DBENTRY} eq $oldchoice)) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = printer::read_cups_options($queue);
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
		}
	    } else {
		# The queue was not configured before
		$printer->{ARGS} = printer::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
	    }
	}
    }
    1;
}

sub setup_options {
    my ($printer, $in) = @_;
    $in->set_help('setupOptions') if $::isInstall;
    if (($printer->{currentqueue}{'printer'}) || # We have a Foomatic queue
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
	my $windowtitle = "$printer->{currentqueue}{'make'} $printer->{currentqueue}{'model'}";
	if ($::expert) {
	    my $driver = undef;
	    if ($driver = $printer->{currentqueue}{driver}) {
		if ($printer->{currentqueue}{foomatic}) {
		    if ($driver eq 'Postscript') {
			$driver = "PostScript";
		    } else {
			$driver = "GhostScript + $driver";
		    }
		} elsif ($printer->{currentqueue}{ppd}) {
		    if ($printer->{DBENTRY}) {
			$printer->{DBENTRY} =~ /^[^\|]*\|[^\|]*\|(.*)$/;
			$driver = $1;
		    } else {
			$driver = printer::get_descr_from_ppd($printer);
			if ($driver =~ /^[^\|]*\|[^\|]*$/) { # No driver info
			    $driver = "CUPS/PPD";
			} else {
			    $driver =~ /^[^\|]*\|[^\|]*\|(.*)$/;
			    $driver = $1;
			}
		    }
		}
	    } 
	    if ($driver) {
		$windowtitle .= ", $driver";
	    }
	}
	return 0 if !$in->ask_from
	    ($windowtitle,
	     _("Printer default settings
You should make sure that the page size and the
ink type (if available) are set correctly. Note
that with a very high printout quality printing
can get substantially slower."),
	     \@widgets,
	     complete => sub {
		 my $i;
		 for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
		     if (($printer->{ARGS}[$i]{'type'} eq 'int') || ($printer->{ARGS}[$i]{'type'} eq 'float')) {
			 unless (($printer->{ARGS}[$i]{'type'} ne 'int') || ($userinputs[$i] =~ /^[\-\+]?[0-9]+$/)) {
			     $in->ask_warn('', _("Option %s must be an integer number!", $printer->{ARGS}[$i]{'comment'}));
			     return (1, $i);
			 }
			 unless (($printer->{ARGS}[$i]{'type'} ne 'float') || ($userinputs[$i] =~ /^[\-\+]?[0-9\.]+$/)) {
			     $in->ask_warn('', _("Option %s must be a number!", $printer->{ARGS}[$i]{'comment'}));
			     return (1, $i);
			 }
			 unless (($userinputs[$i] >= $printer->{ARGS}[$i]{'min'}) &&
				 ($userinputs[$i] <= $printer->{ARGS}[$i]{'max'})) {
			     $in->ask_warn('', _("Option %s out of range!", $printer->{ARGS}[$i]{'comment'}));
			     return (1, $i);
			 }
		     }
		 }
		 return (0);
	     } );
	# Read out the user's choices
	@{$printer->{currentqueue}{options}} = ();
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    push(@{$printer->{currentqueue}{options}}, "-o");
	    if ($printer->{ARGS}[$i]{'type'} eq 'enum') {
		# enumerated option
		my $j;
		for ($j = 0; $j <= $#{$choicelists[$i]}; $j++) {
		    if ($choicelists[$i][$j] eq $userinputs[$i]) {
			push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{'name'} . "=". $shortchoicelists[$i][$j]);
		    }
		}
	    } elsif ($printer->{ARGS}[$i]{'type'} eq 'bool') {
		# boolean option
		push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{'name'} . "=".
		     (($choicelists[$i][0] eq $userinputs[$i]) ? "1" : "0"));
	    } else {
		# numerical option
		push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{'name'} . "=" . $userinputs[$i]);
	    }
	}
    }
    1;
}

sub setasdefault {
    my ($printer, $in) = @_;
    $in->set_help('setupAsDefault') if $::isInstall;
    if (($printer->{DEFAULT} eq '') || # We have no default printer,
	                               # so set the current one as default
	($in->ask_yesorno('', _("Do you want to set this printer (\"%s\")\nas the default printer?", $printer->{QUEUE}), 1))) { # Ask the user
	$printer->{DEFAULT} = $printer->{QUEUE};
        printer::set_default_printer($printer);
    }
}
	
sub print_testpages {
    my ($printer, $in, $upNetwork) = @_;
    $in->set_help('printTestPages') if $::isInstall;
    # print test pages
    my $standard = 1;
    my $altletter = 0;
    my $alta4 = 0;
    my $photo = 0;
    my $ascii = 0;
    if ($in->ask_from_
	({ title => _("Test pages"),
	   messages => _("Please select the test pages you want to print.
Note: the photo test page can take a rather long time to get printed
and on laser printers with too low memory it can even not come out.
In most cases it is enough to print the standard test page."),
          cancel => ($printer->{configured}{$printer->{OLD_QUEUE}} ?
		     _("Cancel") : _("No test pages")),
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
	    if (($photo) && (!$::testing) &&
		(!printer::files_exist((qw(/usr/bin/convert))))) {
		$in->do_pkgs->install('ImageMagick');
	    }
	    # set up list of pages to print
	    $standard && push (@testpages, $stdtestpage);
	    $altletter && push (@testpages, $altlttestpage);
	    $alta4 && push (@testpages, $alta4testpage);
	    $photo && push (@testpages, $phototestpage);
	    $ascii && push (@testpages, $asciitestpage);
	    # print the stuff
	    @lpq_output = printer::print_pages($printer, @testpages);
	}
	my $dialogtext;
	if (@lpq_output) {
	    $dialogtext = _("Test page(s) have been sent to the printer.
It may take some time before the printer starts.
Printing status:\n%s\n\n", @lpq_output);
	} else {
	    $dialogtext = _("Test page(s) have been sent to the printer.
It may take some time before the printer starts.\n");
	}
	if ($printer->{NEW} == 0) {
	    $in->ask_warn('',$dialogtext);
	    return 1;
	} else {
	    $in->ask_yesorno('',$dialogtext . _("Did it work properly?"), 1) 
		and return 1;
	}
    } else {
	return 1;
    }
    return 0;
}

sub printer_help {
    my ($printer, $in) = @_;
    my $spooler = $printer->{SPOOLER};
    my $queue = $printer->{QUEUE};
    my $default = $printer->{DEFAULT};
    my $raw = 0;
    if (($printer->{configured}{$queue}{'queuedata'}{'model'} eq
	 _("Unknown model")) ||
	($printer->{configured}{$queue}{'queuedata'}{'model'} eq
	 _("Raw printer"))) {
	$raw = 1;
    }
    #my $foomatic = $printer->{configured}{$queue}{queuedata}{foomatic};
    #my $ppd = $printer->{configured}{$queue}{queuedata}{ppd};
    my $dialogtext;
    if ($spooler eq "cups") {
	$dialogtext =
_("To print a file from the command line (terminal window) you can either use the command \"%s <file>\" or a graphical printing tool: \"xpp <file>\" or \"qtcups <file>\". The graphical tools allow you to choose the printer and to modify the option settings easily.
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("These commands you can also use in the \"Printing command\" field of the printing dialogs of many applications, but here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
_("To get a list of the options available for the current printer read either the list shown below or click on the \"Print option list\" button.

") . printer::lphelp_output($printer) : "");
    } elsif ($spooler eq "lprng") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) . 
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -Z option=setting -Z switch" : "lpr -Z option=setting -Z switch")) .
_("To get a list of the options available for the current printer click on the \"Print option list\" button.

") : "");
    } elsif ($spooler eq "lpd") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
_("To get a list of the options available for the current printer click on the \"Print option list\" button.

") : "");
    } elsif ($spooler eq "pdq") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\" or \"%s <file>\".
", ($queue ne $default ? "pdq -P $queue" : "pdq"), ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
_("You can also use the graphical interface \"xpdq\" for setting options and handling printing jobs.
If you are using KDE as desktop environment you have a \"panic button\", an icon on the desktop, labeled with \"STOP Printer!\", which stops all print jobs immediately when you click it. This is for example useful for paper jams.
") .
(!$raw ?
_("
The \"%s\" and \"%s\" commands also allow to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\".
", "pdq", "lpr", ($queue ne $default ? "pdq -P $queue -aoption=setting -oswitch" : "pdq -aoption=setting -oswitch")) .
_("To get a list of the options available for the current printer read either the list shown below or click on the \"Print option list\" button.

") . printer::pdqhelp_output($printer) : "");
    }
    if (!$raw) {
        my $choice;
        while ($choice ne _("Close")) {
	    $choice = $in->ask_from_list_
	        (_("Printing on the printer \"%s\"", $queue),
		 $dialogtext,
		 [ _("Print option list"), _("Close") ],
		 _("Close"));
	    if ($choice ne _("Close")) {
		my $w = $in->wait_message('', _("Printing test page(s)..."));
	        printer::print_optionlist($printer);
	    }
	}
    } else {
	$in->ask_warn('',$dialogtext);
    }
}

sub copy_queues_from {
    my ($printer, $in, $oldspooler) = @_;

    $in->set_help('copyQueues') if $::isInstall;
    my $newspooler = $printer->{SPOOLER};
    my @oldqueues;
    my @queueentries;
    my @queuesselected;
    my $newspoolerstr;
    my $oldspoolerstr;
    my $noninteractive = 0;
    {
	my $w = $in->wait_message('', _("Reading printer data ..."));
	@oldqueues = printer::get_copiable_queues($oldspooler, $newspooler);
	@oldqueues = sort(@oldqueues);
	$newspoolerstr = $printer::shortspooler_inv{$newspooler};
	$oldspoolerstr = $printer::shortspooler_inv{$oldspooler};
	for (@oldqueues) {
	    push (@queuesselected, 1);
	    push (@queueentries, { text => $_, type => 'bool', 
				   val => \$queuesselected[$#queuesselected] });
	}
	# LPRng and LPD use the same config files, therefore one sees the 
	# queues of LPD when one uses LPRng and vice versa, but these queues
	# do not work. So automatically transfer all queues when switching
	# between LPD and LPRng.
	if (($oldspooler =~ /^lp/) && ($newspooler =~ /^lp/)) {
	    $noninteractive = 1;
	}
    }
    if ($noninteractive ||
	$in->ask_from_
	({ title => _("Transfer printer configuration"),
	   messages => _("You can copy the printer configuration which you have done 
for the spooler %s to %s, your current spooler. All the
configuration data (printer name, description, location, 
connection type, and default option settings) is overtaken,
but jobs will not be transferred.
Not all queues can be transferred due to the following 
reasons:
", $oldspoolerstr, $newspoolerstr) .
($newspooler eq "cups" ? _("CUPS does not support printers on Novell servers or printers
sending the data into a free-formed command.
") :
 ($newspooler eq "pdq" ? _("PDQ only supports local printers, remote LPD printers, and
Socket/TCP printers.
") :
  _("LPD and LPRng do not support IPP printers.
"))) .
_("In addition, queues not created with this program or
\"foomatic-configure\" cannot be transferred.") .
($oldspooler eq "cups" ? _("
Also printers configured with the PPD files provided by
their manufacturers or with native CUPS drivers can not be
transferred.") : ()) . _("
Mark the printers which you want to transfer and click 
\"Transfer\"."),
	   cancel => _("Do not transfer printers"),
           ok => _("Transfer")
	 },
         \@queueentries
      )) {
	my $queuecopied = 0;
	for (@oldqueues) {
	    if (shift(@queuesselected)) {
                my $oldqueue = $_;
                my $newqueue = $_;
                if ((!$printer->{configured}{$newqueue}) ||
		    ($noninteractive) ||
		    ($in->ask_from_
	             ({ title => _("Transfer printer configuration"),
	                messages => _("A printer named \"%s\" already exists under %s. 
Click \"Transfer\" to overwrite it.
You can also type a new name or skip this printer.", 
				      $newqueue, $newspoolerstr),
                        ok => _("Transfer"),
                        cancel => _("Skip"),
		        callbacks => { complete => sub {
	                    unless ($newqueue =~ /^\w+$/) {
				$in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
				return (1,0);
			    }
			    if (($printer->{configured}{$newqueue})
				&& ($newqueue ne $oldqueue) && 
				(!$in->ask_yesorno('', _("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
							 $newqueue),
						   0))) {
				return (1,0); # Let the user correct the name
			    }
			    return 0;
			}}
		    },
		      [{label => _("New printer name"),val => \$newqueue}]))) {
		    {
			my $w = $in->wait_message('', 
			   _("Transferring %s ...", $oldqueue));
		        printer::copy_foomatic_queue($printer, $oldqueue,
						   $oldspooler, $newqueue) and
							 $queuecopied = 1;
		    }
		    if ($oldqueue eq $printer->{DEFAULT}) {
			# Make the former default printer the new default
			# printer if the user does not reject
			if (($noninteractive) ||
			    ($in->ask_yesorno
			     (_("Transfer printer configuration"),
			      _("You have transferred your former default printer (\"%s\"),
Should it be also the default printer under the
new printing system %s?", $oldqueue, $newspoolerstr), 1))) {
			    $printer->{DEFAULT} = $newqueue;
			    printer::set_default_printer($printer);
			}
		    }
		}
            }
	}
        if ($queuecopied) {
	    my $w = $in->wait_message('', _("Refreshing printer data ..."));
	    printer::read_configured_queues($printer);
        }
    }
}

sub start_network {
    my $in = $_[0];
    my $w = $in->wait_message(_("Configuration of a remote printer"), 
			      _("Starting network ..."));
    return printer::start_service("network");
}

sub check_network {

    # This routine is called whenever the user tries to configure a remote
    # printer. It checks the state of the network functionality to assure
    # that the network is up and running so that the remote printer is
    # reachable.

    my ($printer, $in) = @_;

    $in->set_help('checkNetwork') if $::isInstall;

    # First check: Does /etc/sysconfig/network-scripts/draknet_conf exist
    # (otherwise the network is not configured yet and draknet has to be
    # started)

    if (!printer::files_exist("/etc/sysconfig/network-scripts/draknet_conf")) {
	my $go_on = 0;
	while (!$go_on) {
	    my $choice = _("Configure the network now");
	    if ($in->ask_from(_("Network functionality not configured"),
			      _("You are going to configure a remote printer. This needs working
network access, but your network is not configured yet. If you
go on without network configuration, you will not be able to use
the printer which you are configuring now. How do you want 
to proceed?"),
			      [ { val => \$choice, type => 'list',
				  list => [ _("Configure the network now"),
					    _("Go on without configuring the network") ]} ] )) {
		if ($choice eq _("Configure the network now")){
		    if ($::isInstall) {
			require network::netconnect;
		        network::netconnect::main
			    ($in->{prefix}, $in->{netcnx} ||= {}, 
			     $in->{netc}, $in->{mouse}, $in, 
			     $in->{intf}, 0,
			     $in->{lang} eq "fr_FR" && 
			     $in->{keyboard} eq "fr", 0);
		    } else {
			system("/usr/sbin/draknet");
		    }
		    if (printer::files_exist("/etc/sysconfig/network-scripts/draknet_conf")) {
			$go_on = 1;
		    }
		} else {
		    return 1;
		}
	    } else {
		return 0;
	    }
	}
    }

    # Second check: Is the network running?

    if (printer::network_running()) {return 1;}

    # The network is configured now, start it.
    if (!start_network($in)) {
	$in->ask_warn(_("Configuration of a remote printer"), 
($::isInstall ?
_("The network configuration done during the installation 
cannot be started now. Please check whether the network
gets accessable after booting your system and correct the
configuration using the Mandrake Control Center, section
\"Network & Internet\"/\"Connection\", and afterwards set
up the printer, also using the Mandrake Control Center,
section \"Hardware\"/\"Printer\"") :
_("The network access was not running and could not be 
started. Please check your configuration and your 
hardware. Then try to configure your remote printer
again.")));
	return 0;
    }

    # Give a SIGHUP to the daemon and in case of CUPS do also the
    # automatic configuration of broadcasting/access permissions
    # The daemon is not really restarted but only SIGHUPped to not
    # interrupt print jobs.

    my $w = $in->wait_message(_("Configuration of a remote printer"), 
			      _("Restarting printing system ..."));
    return printer::SIGHUP_daemon($printer->{SPOOLER});

}

sub security_check {
    # Check the security mode and when in "high" or "paranoid" mode ask the
    # user whether he really wants to configure printing.
    my ($printer, $in, $spooler) = @_;
    $in->set_help('securityCheck') if $::isInstall;

    # Get security level
    my $security = undef;
    if ($::isInstall) {
	$security = $in->{'security'};
    } else {
	$security = printer::get_security_level();
    }

    # Exit silently if the spooler is PDQ
    if ($spooler eq "pdq") {return 1;}

    # Exit silently in medium or lower security levels
    if ((!$security) || ($security < 4)) {return 1;}
    
    # Exit silently if the current spooler is already activated for the current
    # security level
    if (printer::spooler_in_security_level($spooler, $security)) {return 1;}

    # Tell user in which security mode he is and ask him whether he really
    # wants to activate the spooler in the given security mode. Stop the
    # operation of installing the spooler if he disagrees.
    my $securitystr = ($security == 4 ? _("high") : _("paranoid"));
    if ($in->ask_yesorno(_("Installing a printing system in the %s security level", $securitystr),
			 _("You are about to install the printing system %s on
a system running in the %s security level.

This printing system runs a daemon (background process)
which waits for print jobs and handles them. This daemon
is also accessable by remote machines through the network
and so it is a possible point for attacks. Therefore only
a few selected daemons are started by default in this
security level.

Do you really want to configure printing on this
machine?",
			   $printer::shortspooler_inv{$spooler},
			   $securitystr))) {
        printer::add_spooler_to_security_level($spooler, $security);
	my $service;
	if (($spooler eq "lpr") || ($spooler eq "lprng")) {
	    $service = "lpd";
	} else {
	    $service = $spooler;
	}
        printer::start_service_on_boot($service);
	return 1;
    } else {
	return 0;
    }
}

sub start_spooler_on_boot {
    # Checks whether the spooler will be started at boot time and if not,
    # ask the user whether he wants to start the spooler at boot time.
    my ($printer, $in, $service) = @_;
    $in->set_help('startSpoolerOnBoot') if $::isInstall;
    if (!printer::service_starts_on_boot($service)) {
	if ($in->ask_yesorno(_("Starting the printing system at boot time"),
			     _("The printing system (%s) will not be started automatically
when the machine is booted.

It is possible that the automatic starting was turned off 
by changing to a higher security level, because the printing
system is a potential point for attacks.

Do you want to have the automatic starting of the printing
system turned on again?",
		       $printer::shortspooler_inv{$printer->{SPOOLER}}))) {
	    printer::start_service_on_boot($service);
	}
    }
    1;
}

sub install_spooler {
    # installs the default spooler and start its daemon
    my ($printer, $in) = @_;
    if (!$::testing) {
	# If the user refuses to install the spooler in high or paranoid
	# security level, exit.
	if (!security_check($printer, $in, $printer->{SPOOLER})) {
	    return 0;
	}
	if ($printer->{SPOOLER} eq "cups") {
	    {
		my $w = $in->wait_message('', _("Checking installed software..."));
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/lib/cups/cgi-bin/printers.cgi
					       /sbin/ifconfig
					       /usr/bin/xpp
					       /usr/bin/qtcups),
					    (printer::files_exist("/usr/bin/kwin")?
					     "/usr/bin/kups" : ()),
					    ($::expert ? 
					     "/usr/share/cups/model/postscript.ppd.gz" : ())
					    )))) {
		    $in->do_pkgs->install(('cups', 'net-tools', 'xpp', 'qtcups', 
					   if_($in->do_pkgs->is_installed('kdebase'), 'kups'),
					   ($::expert ? 'cups-drivers' : ())));
		}
		# Start daemon
	        printer::start_service("cups");
		# Set the CUPS tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-cups");
	        printer::set_alternative("lpq","/usr/bin/lpq-cups");
	        printer::set_alternative("lprm","/usr/bin/lprm-cups");
	        printer::set_alternative("lp","/usr/bin/lp-cups");
	        printer::set_alternative("cancel","/usr/bin/cancel-cups");
	        printer::set_alternative("lpstat","/usr/bin/lpstat-cups");
	        printer::set_alternative("lpc","/usr/sbin/lpc-cups");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "cups");
	} elsif ($printer->{SPOOLER} eq "lpd") {
	    {
		my $w = $in->wait_message('', _("Checking installed software..."));
		# "lpr" conflicts with "LPRng", remove "LPRng"
		if ((!$::testing) &&
		    (printer::files_exist((qw(/usr/lib/filters/lpf))))) {
		    my $w = $in->wait_message('', _("Removing LPRng..."));
		    $in->do_pkgs->remove_nodeps('LPRng');
		}
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/sbin/lpf
					       /usr/sbin/lpd
					       /sbin/ifconfig))))) {
		    $in->do_pkgs->install(('lpr', 'net-tools'));
		}
		# Start daemon
	        printer::restart_service("lpd");
		# Set the LPD tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-lpd");
	        printer::set_alternative("lpq","/usr/bin/lpq-lpd");
	        printer::set_alternative("lprm","/usr/bin/lprm-lpd");
	        printer::set_alternative("lpc","/usr/sbin/lpc-lpd");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "lpd");
	} elsif ($printer->{SPOOLER} eq "lprng") {
	    {
		my $w = $in->wait_message('', _("Checking installed software..."));
		# "LPRng" conflicts with "lpr", remove "lpr"
		if ((!$::testing) &&
		    (printer::files_exist((qw(/usr/sbin/lpf))))) {
		    my $w = $in->wait_message('', _("Removing LPD..."));
		    $in->do_pkgs->remove_nodeps('lpr');
		}
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/lib/filters/lpf
					       /usr/sbin/lpd
					       /sbin/ifconfig))))) {
		    $in->do_pkgs->install('LPRng', 'net-tools');
		}
		# Start daemon
	        printer::restart_service("lpd");
		# Set the LPRng tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-lpd");
	        printer::set_alternative("lpq","/usr/bin/lpq-lpd");
	        printer::set_alternative("lprm","/usr/bin/lprm-lpd");
	        printer::set_alternative("lp","/usr/bin/lp-lpd");
	        printer::set_alternative("cancel","/usr/bin/cancel-lpd");
	        printer::set_alternative("lpstat","/usr/bin/lpstat-lpd");
	        printer::set_alternative("lpc","/usr/sbin/lpc-lpd");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "lpd");
	} elsif ($printer->{SPOOLER} eq "pdq") {
	    {
		my $w = $in->wait_message('', _("Checking installed software..."));
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/bin/pdq
					       /usr/X11R6/bin/xpdq))))) {
		    $in->do_pkgs->install('pdq');
		}
		# PDQ has no daemon, so nothing needs to be started
		
		# Set the PDQ tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-pdq");
	        printer::set_alternative("lpq","/usr/bin/lpq-foomatic");
	        printer::set_alternative("lprm","/usr/bin/lprm-foomatic");
		# Add PDQ panic buttons to the user's KDE Desktops
	        printer::pdq_panic_button("add");
	    }
	}
    }
    1;
}

sub setup_default_spooler {
    my ($printer, $in) = @_;
    $in->set_help('setupDefaultSpooler') if $::isInstall;
    $printer->{SPOOLER} ||= 'cups';
    my $oldspooler = $printer->{SPOOLER};
    my $str_spooler = 
	$in->ask_from_list_(_("Select Printer Spooler"),
			    _("Which printing system (spooler) do you want to use?"),
			    [ printer::spooler() ],
			    $printer::spooler_inv{$printer->{SPOOLER}},
			    ) or return;
    $printer->{SPOOLER} = $printer::spooler{$str_spooler};
    # Install the spooler if not done yet
    if (!install_spooler($printer, $in)) {
	$printer->{SPOOLER} = $oldspooler;
	return;
    }
    if ($printer->{SPOOLER} ne $oldspooler) {
	# Get the queues of this spooler
	{
	    my $w = $in->wait_message('', _("Reading printer data ..."));
	    printer::read_configured_queues($printer);
	}
	# Copy queues from former spooler
	copy_queues_from($printer, $in, $oldspooler);
	# Re-read the printer database (CUPS has additional drivers, PDQ
	# has no raw queue)
	%printer::thedb = ();
	#my $w = $in->wait_message('', _("Reading printer database ..."));
	#printer::read_printer_db($printer->{SPOOLER});
    }
    # Save spooler choice
    printer::set_default_spooler($printer);
    return $printer->{SPOOLER};
}

sub configure_queue {
    my ($printer, $in) = @_;
    my $w = $in->wait_message('', _("Configuring printer \"%s\" ...",
				    $printer->{currentqueue}{queue}));
    $printer->{complete} = 1;
    printer::configure_queue($printer);
    $printer->{complete} = 0;
}

#- Program entry point for configuration of the printing system.
sub main {
    my ($printer, $in, $ask_multiple_printer, $upNetwork) = @_;

    # Default printer name, we do not use "lp" so that one can switch the
    # default printer under LPD without needing to rename another printer.
    # Under LPD the alias "lp" will be given to the default printer.
    my $defaultprname = _("Printer");

    # printerdrake does not work without foomatic, and for more convenience
    # we install some more stuff
    {
	my $w = $in->wait_message('', _("Checking installed software..."));
	if ((!$::testing) &&
	    (!printer::files_exist((qw(/usr/bin/foomatic-configure
				       /usr/lib/perl5/site_perl/5.6.1/Foomatic/DB.pm
				       /usr/bin/escputil
				       /usr/share/printer-testpages/testprint.ps
				       ),
				    (printer::files_exist("/usr/bin/gimp") ?
				     "/usr/lib/gimp/1.2/plug-ins/print" : ())
				    )))) {
	    $in->do_pkgs->install('foomatic','printer-utils','printer-testpages',
				  if_($in->do_pkgs->is_installed('gimp'), 'gimpprint'));
	}

	# only experts should be asked for the spooler
	!$::expert and $printer->{SPOOLER} ||= 'cups';

    }

    # If we have chosen a spooler, install it and mark it as default spooler
    if (($printer->{SPOOLER}) && ($printer->{SPOOLER} ne '')) {
	if (!install_spooler($printer, $in)) {return;}
        printer::set_default_spooler($printer);
    }

    # Control variables for the main loop
    my ($queue, $continue, $newqueue, $editqueue, $expertswitch, $menushown) = ('', 1, 0, 0, 0, 0);
    # Cursor position in queue modification window
    my $modify = _("Printer options");
    while ($continue) {
	$newqueue = 0;
	# When the queue list is not shown, cancelling the printer type
	# dialog should leave the program
	$continue = 0;
	# Get the default printer
	if (defined($printer->{SPOOLER}) && ($printer->{SPOOLER} ne '') &&
	    ((!defined($printer->{DEFAULT})) || ($printer->{DEFAULT} eq ''))) {
	    my $w = $in->wait_message('', _("Preparing PrinterDrake ..."));
	    $printer->{DEFAULT} = printer::get_default_printer($printer);
	    if ($printer->{DEFAULT}) {
		# If a CUPS system has only remote printers and no default
		# printer defined, it defines the first printer whose
		# broadcast signal appeared after the start of the CUPS
		# daemon, so on every start another printer gets the default
		# printer. To avoid this, make sure that the default printer
		# is defined.
		printer::set_default_printer($printer);
	    } else {
		$printer->{DEFAULT} = '';
	    }
	}
	if ($editqueue) {
	    # The user was either in the printer modification dialog and did
	    # not close it or he had set up a new queue and said that the test
	    # page didn't come out correctly, so let the user edit the queue.
	    $newqueue = 0;
	    $continue = 1;
	    $editqueue = 0;
	} else {
	    # Reset modification window cursor when one leaves the window
	    $modify = _("Printer options");
	    if (!$ask_multiple_printer && 
		%{$printer->{configured} || {}} == ()) {
		$in->set_help('doYouWantToPrint') if $::isInstall;
		$newqueue = 1;
		$queue = $printer->{want} || 
		    $in->ask_yesorno(_("Printer"),
				    _("Would you like to configure printing?"),
				    0) ? $defaultprname : _("Done");
		if ($queue ne _("Done")) {
		    $printer->{SPOOLER} ||= 
			setup_default_spooler ($printer, $in) ||
			    return;
		}
	    } else {
		# Ask for a spooler when none is defined
		$printer->{SPOOLER} ||=  setup_default_spooler ($printer, $in) || return;
		# This entry and the check for this entry have to use
		# the same translation to work properly
		my $spoolerentry = _("Printing system: ");
		# Show a queue list window when there is at least one queue,
		# when we are in expert mode, or when we are not in the
		# installation.
		unless ((%{$printer->{configured} || {}} == ()) && 
			(!$::expert) && ($::isInstall)) {
		    $in->set_help('mainMenu') if $::isInstall;
		    # Cancelling the printer type dialog should leed to this
		    # dialog
		    $continue = 1;
		    # This is for the "Recommended" installation. When one has
		    # no printer queue printerdrake starts directly adding
		    # a printer and in the end it asks whether one wants to
		    # install another printer. If the user says "Yes", he
		    # arrives in the main menu of printerdrake. From now
		    # on the question is not asked any more but the menu
		    # is shown directly after having done an operation.
		    $menushown = 1;
		    # $expertwitch gets one when the "Expert mode"/
		    # "Standard mode" button is clicked.
		    $expertswitch = !$in->ask_from_(
			{messages =>
			     _("The following printers are configured.
Click on one of them to modify it or
to get information about it or on 
\"Add Printer\" to add a new printer."),
			 cancel => ($::isInstall ? 
				    ('') : ($::expert ? 
				  _("Normal Mode") : _("Expert Mode"))),
			},
			# List the queues
			[ { val => \$queue, format => \&translate,
			    sort => 0, 
		        list => [ (sort(map {"$_" . ($_ eq $printer->{DEFAULT} ?
						     _(" (Default)") : ())}
				   keys(%{$printer->{configured} || {}}))),
			# CUPS makes available remote printers automatically
			($printer->{SPOOLER} eq "cups" ?
			 ($::expert ? _("Printer(s) on remote CUPS server(s)"):
			  _("Printer(s) on remote server(s)")) : ()),
			# Button to add a new queue
			_("Add printer"),
		        # In expert mode we can change the spooler
		        ($::expert ?
		         ( $spoolerentry .
		           $printer::spooler_inv{$printer->{SPOOLER}} ) : ()),
		        # Bored by configuring your printers, get out of here!
		        _("Done") ] } ]
		    );
		    # Toggle expert mode and standard mode
		    if ($expertswitch) {
			$expertswitch = 0;
			$::expert = !$::expert;
			# Read printer database for the new user mode
			%printer::thedb = ();
			#my $w = $in->wait_message('', _("Reading printer database ..."));
		        #printer::read_printer_db($printer->{SPOOLER});
			next;
		    }
		} else {
		    #- as there are no printer already configured, Add one
		    #- automatically.
		    $queue = _("Add printer"); 
		} 
	        # Determine a default name for a new printer queue
		if ($queue eq _("Add printer")) {
		    $newqueue = 1;
		    my %queues; 
		    @queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
		    my $i = ''; while ($i < 100) { last unless exists $queues{"$defaultprname$i"}; ++$i; }
		    $queue = "$defaultprname$i";
		}
		# Function to switch to another spooler chosen
		if ($queue =~ /^$spoolerentry/) {
		    $printer->{SPOOLER} = setup_default_spooler ($printer, $in) || $printer->{SPOOLER};
		    next;
		}
		# Make available printers on remote CUPS servers (CUPS only).
		if (($queue eq _("Printer(s) on remote CUPS server(s)")) ||
		    ($queue eq _("Printer(s) on remote server(s)"))) {
		    setup_remote_cups_server($printer, $in);
		    next;
		}
		# Rip off the " (Default)" tag from the queue name
		if ($queue =~ /^\s*(\S+)\s+/) {
		    $queue = $1;
		}
	    }
	    # Save the default spooler
	    printer::set_default_spooler($printer);
	    #- Close printerdrake
	    $queue eq _("Done") and last;
	}
	if ($newqueue) {
	    $printer->{NEW} = 1;
	    #- Set default values for a new queue
	    $printer::printer_type_inv{$printer->{TYPE}} or 
		$printer->{TYPE} = printer::default_printer_type($printer);
	    $printer->{currentqueue} = { queue    => $queue,
					 foomatic => 0,
					 desc     => "",
					 loc      => "",
					 make     => "",
					 model    => "",
					 printer  => "",
					 driver   => "",
					 connect  => "",
					 spooler  => $printer->{SPOOLER},
				       };
	    #- Set OLD_QUEUE field so that the subroutines for the
	    #- configuration work correctly.
	    $printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
	    #- When we are back on the main menu the cursor should be
	    #- on "Add printer"
	    $queue = _("Add printer");
	    #- Do all the configuration steps for a new queue
	    choose_printer_type($printer, $in) or next;
	    if ($printer->{TYPE} eq 'CUPS') {
		setup_remote_cups_server($printer, $in);
		$continue = ($::expert || !$::isInstall || $menushown ||
			     $in->ask_yesorno('',_("Do you want to configure another printer?")));
		next;
	    }
	    #- Cancelling one of the following dialogs should restart 
	    #- printerdrake
	    $continue = 1;
	    setup_printer_connection($printer, $in) or next;
	    choose_printer_name($printer, $in) or next;
	    get_db_entry($printer, $in);
	    choose_model($printer, $in) or next;
	    get_printer_info($printer, $in) or next;
	    setup_options($printer, $in) or next;
	    configure_queue($printer, $in);
	    setasdefault($printer, $in);
	    if (print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork)) { 
		$continue = ($::expert || !$::isInstall || $menushown ||
			 $in->ask_yesorno('',_("Do you want to configure another printer?")));
	    } else {
		$editqueue = 1;
		$queue = $printer->{QUEUE};
	    }
	} else {
	    $printer->{NEW} = 0;
	    # Modify a queue, ask which part should be modified
	    $in->set_help('modifyPrinterMenu') if $::isInstall;
	    if ($in->ask_from_
		   ({ title => _("Modify printer configuration"),
		      messages => _("Printer %s: %s %s
What do you want to modify on this printer?",
				    $queue,
				    $printer->{configured}{$queue}{'queuedata'}{'make'},
				    $printer->{configured}{$queue}{'queuedata'}{'model'} .
				    ($queue eq $printer->{DEFAULT} ?
				     _(" (Default)") : ())),
		     cancel => _("Close"),
		     ok => _("Do it!")
		     },
		    [ { val => \$modify, format => \&translate,
			list => [ _("Printer connection type"),
				  _("Printer name, description, location"),
				  ($::expert ?
				   _("Printer manufacturer, model, driver") :
				   _("Printer manufacturer, model")),
				  (($printer->{configured}{$queue}{'queuedata'}{'make'} ne
				    "") &&
				   (($printer->{configured}{$queue}{'queuedata'}{'model'} ne
				    _("Unknown model")) &&
				    ($printer->{configured}{$queue}{'queuedata'}{'model'} ne
				    _("Raw printer"))) ?
				   _("Printer options") : ()),
				  (($queue ne $printer->{DEFAULT}) ?
				   _("Set this printer as the default") : ()),
				  _("Print test pages"),
				  _("Know how to print with this printer"),
				  _("Remove printer") ] } ] ) ) {
		# Stay in the queue edit window until the user clicks "Close"
		# or deletes the queue
		$editqueue = 1; 
		#- Copy the queue data and work on the copy
		$printer->{currentqueue} = {};
		if ($printer->{configured}{$queue}) {
		    printer::copy_printer_params($printer->{configured}{$queue}{'queuedata'}, $printer->{currentqueue});
		}
		#- Keep in mind the printer driver which was used, so it can
		#- be determined whether the driver is only available in expert
		#- and so for setting the options for the driver in
		#- recommended mode a special treatment has to be applied.
		my $driver = $printer->{currentqueue}{driver};
		#- keep in mind old name of queue (in case of changing)
		$printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
		#- Reset some variables
		$printer->{OLD_CHOICE} = undef;
		$printer->{DBENTRY} = undef;
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
		# Do the chosen task
		if ($modify eq _("Printer connection type")) {
		    choose_printer_type($printer, $in) &&
			setup_printer_connection($printer, $in) &&
		            configure_queue($printer, $in);
		} elsif ($modify eq _("Printer name, description, location")) {
		    choose_printer_name($printer, $in) &&
			configure_queue($printer, $in);
		    # Delete old queue when it was renamed
		    if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
			my $w = $in->wait_message('', _("Removing old printer \"%s\" ...", $printer->{OLD_QUEUE}));
		        printer::remove_queue($printer, $printer->{OLD_QUEUE});
			# If the default printer was renamed, correct the
			# the default printer setting of the spooler
			if ($queue eq $printer->{DEFAULT}) {
			    $printer->{DEFAULT} = $printer->{QUEUE};
			    printer::set_default_printer($printer);
			}
			$queue = $printer->{QUEUE};
		    }
		} elsif (($modify eq _("Printer manufacturer, model, driver")) ||
			 ($modify eq _("Printer manufacturer, model"))) {
		    get_db_entry($printer, $in);
		    choose_model($printer, $in) &&
			get_printer_info($printer, $in) &&
			    setup_options($printer, $in) &&
				configure_queue($printer, $in);
		} elsif ($modify eq _("Printer options")) {
		    get_printer_info($printer, $in) &&
			setup_options($printer, $in) &&
			    configure_queue($printer, $in);
		} elsif ($modify eq _("Set this printer as the default")) {
		    $printer->{DEFAULT} = $queue;
		    printer::set_default_printer($printer);
		    $in->ask_warn(_("Default printer"),
				  _("The printer \"%s\" is set as the default printer now.", $queue));
		} elsif ($modify eq _("Print test pages")) {
		    print_testpages($printer, $in, $upNetwork);
		} elsif ($modify eq _("Know how to print with this printer")) {
		    printer_help($printer, $in);
		} elsif ($modify eq _("Remove printer")) {
		    if ($in->ask_yesorno('',
           _("Do you really want to remove the printer \"%s\"?", $queue), 1)) {
			{
			    my $w = $in->wait_message('', _("Removing printer \"%s\" ...", $queue));
			    if (printer::remove_queue($printer, $queue)) { 
				$editqueue = 0;
				# Define a new default printer if we have
				# removed the default one
				if ($queue eq $printer->{DEFAULT}) {
				    my @k = sort(keys(%{$printer->{configured}}));
				    if (@k) {
					$printer->{DEFAULT} = $k[0];
				        printer::set_default_printer($printer);
				    } else {
					$printer->{DEFAULT} = "";
				    }
				}
			    }
			}
		    }		
		}
	    } else {
		$editqueue = 0;
	    }
	    $continue = ($editqueue || $::expert || !$::isInstall || 
			 $menushown ||
			 $in->ask_yesorno('',_("Do you want to configure another printer?")));
	}
	# Delete some variables
	$printer->{OLD_QUEUE} = "";
	$printer->{QUEUE} = "";
	$printer->{TYPE} = "";
	$printer->{str_type} = "";
	$printer->{currentqueue} = {};
	$printer->{DBENTRY} = "";
	$printer->{ARGS} = "";
	$printer->{complete} = 0;
	$printer->{OLD_CHOICE} = "";
    }
    # Clean up the $printer data structure for auto-install log
    for my $queue (keys %{$printer->{configured}}) {
	for my $item (keys %{$printer->{configured}{$queue}}) {
	    if ($item ne "queuedata") {
		delete($printer->{configured}{$queue}{$item});
	    }
	}
    }
    delete($printer->{OLD_QUEUE});
    delete($printer->{QUEUE});
    delete($printer->{TYPE});
    delete($printer->{str_type});
    delete($printer->{currentqueue});
    delete($printer->{DBENTRY});
    delete($printer->{ARGS});
    delete($printer->{complete});
    delete($printer->{OLD_CHOICE});
    delete($printer->{NEW});
    #use Data::Dumper;
    #print "###############################################################################\n", Dumper($printer); 

}

