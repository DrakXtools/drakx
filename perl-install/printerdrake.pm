package printerdrake;
# $Id$

use diagnostics;
use strict;

use common qw(:common :file :functional :system);
use detect_devices;
use commands;
use modules;
use network;
use log;
use printer;

1;

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


sub setup_local($$$) {
    my ($printer, $in, $install) = @_;

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
	$in->ask_warn('', __("Device/file name missing!"));
	return (1,0);
    }
    return 0;
}
					     );
    }

    #- make the DeviceURI from $device.
    $printer->{currentqueue}{'connect'} = "file:" . $device;

    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {printer::read_printer_db();}

    #- Search the database entry which matches the detected printer best
    foreach (@parport) {
	$device eq $_->{port} or next;
        $printer->{DBENTRY} =
            common::bestMatchSentence2($_->{val}{DESCRIPTION}, 
            keys %printer::thedb);
    }
    1;
}

sub setup_lpd($$$) {
    my ($printer, $in, $install) = @_;

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
__("To use a remote lpd print queue, you need to supply
the hostname of the printer server and the queue name
on that server."), [
{ label => _("Remote hostname"), val => \$remotehost },
{ label => _("Remote queue"), val => \$remotequeue } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', __("Remote host name missing!"));
	return (1,0);
    }
    unless ($remotequeue ne "") {
	$in->ask_warn('', __("Remote queue name missing!"));
	return (1,1);
    }
    return 0;
}
			      );
    #- make the DeviceURI from user input.
    $printer->{currentqueue}{'connect'} = 
        "lpd://$remotehost/$remotequeue";
}

sub setup_smb($$$) {
    my ($printer, $in, $install) = @_;

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
	$in->ask_warn('', __("Either the server name or the server's IP must be given!"));
	return (1,0);
    }
    unless ($smbshare ne "") {
	$in->ask_warn('', __("Samba share name missing!"));
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

    &$install('samba-client');
    $printer->{SPOOLER} eq 'cups' and printer::restart_queue($printer);
    1;
}

sub setup_ncp($$$) {
    my ($printer, $in, $install) = @_;

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
	$in->ask_warn('', __("NCP server name missing!"));
	return (1,0);
    }
    unless ($ncpqueue ne "") {
	$in->ask_warn('', __("NCP queue name missing!"));
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

    &$install('ncpfs');
    1;
}

sub setup_socket($$$) {
    my ($printer, $in, $install) = @_;
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
	$in->ask_warn('', __("Printer host name missing!"));
	return (1,0);
    }
    unless ($remoteport =~ /^[0-9]+$/) {
	$in->ask_warn('', __("The port must be an integer number!"));
	return (1,1);
    }
    return 0;
}
					 );

    #- make the Foomatic URI
    $printer->{currentqueue}{'connect'} = 
    join '', ("socket://$remotehost", $remoteport ? (":$remoteport") : ());
    1;
}

sub setup_uri($$$) {
    my ($printer, $in, $install) = @_;

    return if !$in->ask_from_entries_refH(_("Printer Device URI"),
__("You can specify directly the URI to access the printer. The URI must fulfill either the CUPS or the Foomatic specifications. Not that not all URI types are supported by all the spoolers."), [
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
	$in->ask_warn('', __("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );
    if ($printer->{currentqueue}{'connect'} =~ /^smb:/) {
        &$install('samba-client');
        printer::restart_queue($printer);
    }
    if ($printer->{currentqueue}{'connect'} =~ /^ncp:/) {
        &$install('ncpfs');
        printer::restart_queue($printer);
    }
    1;
}

sub setup_postpipe($$$) {
    my ($printer, $in, $install) = @_;

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

    return if !$in->ask_from_entries_refH(__("Pipe into command"),
__("Here you can specify any arbitrary command line into which the job should be piped instead of being sent directly to a printer."), [
{ label => _("Command line"),
val => \$commandline }, ],
complete => sub {
    unless ($commandline ne "") {
	$in->ask_warn('', __("A command line must be entered!"));
	return (1,0);
    }
    return 0;
}
);

    #- make the Foomatic URI
    $printer->{currentqueue}{'connect'} = "postpipe:$commandline";
    
    1;
}

sub setup_gsdriver($$$;$) {
    my ($printer, $in, $install, $upNetwork) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {printer::read_printer_db();}
    my $testpage = "/usr/share/cups/data/testprint.ps";
    my $queue = $printer->{OLD_QUEUE};
    $in->set_help('configurePrinterType') if $::isInstall;
    while (1) {
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
		$printer->{DBENTRY} = "$make|$model|$driverstr";
	    } elsif ($printer->{SPOOLER} eq "cups") {
		# Do we have a native CUPS driver or a PostScript PPD file?
		$printer->{DBENTRY} = printer::get_descr_from_ppd($printer) ||
		    $printer->{DBENTRY};
	    }
	}
	# Choose the printer/driver from the list
	my $oldchoice = $printer->{DBENTRY};
	$printer->{DBENTRY} = $in->ask_from_treelist
	    (__("Printer model selection"),
	     __("Which printer model do you have?"), '|',
	     [ keys %printer::thedb ], $printer->{DBENTRY}) or return;
	$printer->{currentqueue}{'id'} =
	    $printer::thedb{$printer->{DBENTRY}}{id};
	$printer->{currentqueue}{'driver'} =
	    $printer::thedb{$printer->{DBENTRY}}{driver};
	$printer->{currentqueue}{'make'} =
	    $printer::thedb{$printer->{DBENTRY}}{make};
	$printer->{currentqueue}{'model'} =
	    $printer::thedb{$printer->{DBENTRY}}{model};
	if ($printer->{currentqueue}{'id'}) {
	    # We have a Foomatic queue
	    $printer->{currentqueue}{'foomatic'} = 1;
	    # Now get the options for this printer/driver combo
	    if (($printer->{configured}{$queue}) &&
		($printer->{configured}{$queue}{'queuedata'}{'foomatic'})) {
		# The queue was already configured with Foomatic ...
		if ($printer->{DBENTRY} eq $oldchoice) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = $printer->{configured}{$queue}{'args'};
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS}=printer::read_foomatic_options($printer);
		}
	    } else {
		$printer->{ARGS} = printer::read_foomatic_options($printer);
	    }
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
#	    if ($::expert) {
		$windowtitle = $printer->{DBENTRY};
		$windowtitle =~ s/\|/ /;
		$windowtitle =~ s/\|/, /;
#	    } else {
#		$windowtitle = "$printer->{currentqueue}{'make'} " .
#		    "$printer->{currentqueue}{'model'}"
#	    }
	    return if !$in->ask_from_entries_refH
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
				     ('', __("Option $printer->{ARGS}[$i]{'comment'} must be an integer number!"));
				 return (1, $i);
			     }
			     unless
				 (($printer->{ARGS}[$i]{'type'} eq 'int') ||
				  ($userinputs[$i] =~ /^[0-9\.]+$/)) {
				 $in->ask_warn
				     ('', __("Option $printer->{ARGS}[$i]{'comment'} must be a number!"));
				 return (1, $i);
			     }
			     unless (($userinputs[$i] >= 
				      $printer->{ARGS}[$i]{'min'}) &&
				     ($userinputs[$i] <= 
				      $printer->{ARGS}[$i]{'max'})) {
				 $in->ask_warn
				     ('', __("Option $printer->{ARGS}[$i]{'comment'} out of range!"));
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
	# print "$printer->{OPTIONS}\n";
		
	$printer->{complete} = 1;
	printer::configure_queue($printer);
	$printer->{complete} = 0;
	
	if ($in->ask_yesorno('', __("Do you want to print a test page?"), 1)) {
	    my @lpq_output;
	    {
		my $w = $in->wait_message('', _("Printing test page(s)..."));

		$upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
		@lpq_output = printer::print_pages($printer, $testpage);
	    }

	    if (@lpq_output) {
		$in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
It may take some time before the printer starts.
Printing status:\n%s\n\nDoes it work properly?", "@lpq_output"), 1) and last;
	    } else {
		$in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
It may take some time before the printer starts.
Does it work properly?"), 1) and last;
	    }
	} else {
	    last;
	}
    }
    $printer->{complete} = 1;
}

sub setup_gsdriver_cups($$$;$) {
    my ($printer, $in, $install, $upNetwork) = @_;
    my $testpage = "/usr/share/cups/data/testprint.ps";
    $in->set_help('configurePrinterType') if $::isInstall;
    while (1) {
	$printer->{cupsDescr} ||= printer::get_descr_from_ppd($printer);
	$printer->{cupsDescr} = $in->ask_from_treelist('', _("What type of printer do you have?"), '|',
						       [ keys %printer::descr_to_ppd ], $printer->{cupsDescr}) or return;
	$printer->{cupsPPD} = $printer::descr_to_ppd{$printer->{cupsDescr}};

	#- install additional tools according to PPD files.
        $printer->{cupsPPD} =~ /lexmark/i and &$install('ghostscript-utils');

	$printer->{complete} = 1;
	printer::copy_printer_params($printer, $printer->{configured}{$printer->{QUEUE}} ||= {});
	printer::configure_queue($printer);
	$printer->{complete} = 0;
	
	if ($in->ask_yesorno('', _("Do you want to test printing?"), 1)) {
	    my @lpq_output;
	    {
		my $w = $in->wait_message('', _("Printing test page(s)..."));

		$upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
		@lpq_output = printer::print_pages($printer, $testpage);
	    }

	    if (@lpq_output) {
		$in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
This may take a little time before printer start.
Printing status:\n%s\n\nDoes it work properly?", "@lpq_output"), 1) and last;
	    } else {
		$in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
This may take a little time before printer start.
Does it work properly?"), 1) and last;
	    }
	} else {
	    last;
	}
    }
    $printer->{complete} = 1;
}

sub setup_default_spooler ($$) {
    my ($printer, $in) = @_;
    $printer->{SPOOLER} ||= 'cups';
    my $str_spooler = 
	$in->ask_from_list_(__("Select Printer Spooler"),
			    __("Which printing system (spooler) do you want to use?"),
			    [ printer::spooler() ],
			    $printer::spooler_inv{$printer->{SPOOLER}},
			    ) or return;
    $printer->{SPOOLER} = $printer::spooler{$str_spooler};
    # Get the queues of this spooler
    printer::read_configured_queues($printer);
    return $printer->{SPOOLER};
}

#- Program entry point for configuration with lpr or cups (stored in $mode).
sub main($$$$;$) {
    my ($printer, $in, $ask_multiple_printer, $install, $upNetwork) = @_;

    # printerdrake does not work without foomatic
    &$install('foomatic') unless $::testing;

    !$::expert && ($printer->{SPOOLER} ||= 'cups'); # only experts should be asked
                                                 # for the spooler
    my ($queue, $continue) = ('', 1);
    while ($continue) {
	if (!$ask_multiple_printer && %{$printer->{configured} || {}} == ()) {
	    $queue = $printer->{want} || 
		$in->ask_yesorno(_("Printer"),
				 __("Would you like to configure printing?"),
				 0) ? 'lp' : 'Done';
	    $printer->{SPOOLER} ||= setup_default_spooler ($printer, $in) ||
		return;
	    
	} else {
	    # Ask for a spooler when noone is defined
	    $printer->{SPOOLER} ||= setup_default_spooler ($printer, $in) ||
		return;
	    # Show a queue list window when there is at least one queue
	    # or when we are in expert mode
	    unless ((%{$printer->{configured} || {}} == ()) && (!$::expert)) {
		$in->ask_from_entries_refH_powered(
		    {messages =>
                      _("Here are the following print queues.
                      You can add some more or change the existing ones."),
		      cancel => '',
		    },
		    # List the queues
                    [ { val => \$queue, format => \&translate,
		        list => [ (sort keys %{$printer->{configured} || {}}),
		    # Button to add a new queue
		    __("Add queue"),
		    # In expert mode we can change the spooler
		    ($::expert ?
		     ( __("Spooler: ") .
		       $printer::spooler_inv{$printer->{SPOOLER}} ) : ()),
		    # Bored by configuring your printers, get out of here!
		    __("Done") ] } ]
		);
	    } else { $queue = 'Add queue' }  #- as there are no printers 
	                                     #- already configured, Add one
	                                     #- automatically.
	    if ($queue eq 'Add queue') {
		my %queues; 
		@queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
		my $i = ''; while ($i < 100) { last unless exists $queues{"lp$i"}; ++$i; }
		$queue = "lp$i";
	    }
	    if ($queue =~ /^Spooler: /) {
		$printer->{SPOOLER} =
		    setup_default_spooler ($printer, $in) || $printer->{SPOOLER};
		next;
	    }
	}
	# Save the default spooler
	printer::set_default_spooler($printer);
	#- Close printerdrake
	$queue eq 'Done' and last;

	#- Install the printer driver database
	#for ($printer->{SPOOLER}) {
	#    /CUPS/ && do { &$install('cups-drivers') unless $::testing;
	#		   my $w = $in->wait_message(_("CUPS starting"), _("Reading CUPS drivers database..."));
	#		   printer::poll_ppd_base(); last };
	#}

	#- Copy the queue data and work on the copy
	$printer->{currentqueue} = {};
	printer::copy_printer_params
	    ($printer->{configured}{$queue}{'queuedata'},
	     $printer->{currentqueue})
	    if $printer->{configured}{$queue};
	#- keep in mind old name of queue (in case of changing)
	$printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;

	while ($continue) {
	    $in->set_help('configurePrinterConnected') if $::isInstall;
	    if ($printer->{configured}{$queue}) {
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
	    } else {
		#- Set default values for a new queue
		$printer::printer_type_inv{$printer->{TYPE}} or 
		    $printer->{TYPE} = printer::default_printer_type($printer);
		$printer->{currentqueue}{'queue'} = $queue;
		$printer->{currentqueue}{'foomatic'} = 0;
		$printer->{currentqueue}{'desc'} = "";
		$printer->{currentqueue}{'loc'} = "";
		$printer->{currentqueue}{'spooler'} =
		    $printer->{SPOOLER};
	    }
	    $printer->{str_type}=$printer::printer_type_inv{$printer->{TYPE}};
	    $printer->{str_type} = 
		$in->ask_from_list_(_("Select Printer Connection"),
				    _("How is the printer connected?"),
				    [ printer::printer_type($printer) ],
				    $printer->{str_type},
				    ) or return;
	    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
#	    if ($printer->{TYPE} eq 'REMOTE') {
#		$printer->{str_type} = $printer::printer_type_inv{CUPS};
#		$printer->{str_type} = 
#		    $in->ask_from_list_(_("Select Remote Printer Connection"),
#_("With a remote CUPS server, you do not have to configure
#any printer here; printers will be automatically detected.
#In case of doubt, select \"Remote CUPS server\"."),
#					[ @printer::printer_type_inv{qw(CUPS LPD SOCKET)} ],
#					$printer->{str_type},
#					) or return;
#		$printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
#	    }
	    if ($printer->{TYPE} eq 'CUPS') {
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
		}
		return; #- exit printer configuration, here is another hack for simplification.
	    }
	    # Name, description, location
	    $in->set_help('configurePrinterLocal') if $::isInstall;
	    $in->ask_from_entries_refH_powered
		(
		 { title => __("Enter Printer Name and Comments"),
		   cancel => !$printer->{configured}{$queue} ? '' : _("Remove queue"),
		   callbacks => { complete => sub {
		       unless ($printer->{currentqueue}{'queue'} =~ /^\w+$/) {
			   $in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
			   return (1,0);
		       }
		       return 0;
		   },
			      },
		   messages =>
__("Every printer needs a name (for example lp).
The Description and Location fields do not need 
to be filled in. They are comments for the users.") }, 
		 [
		  { label => _("Name of printer"),
		    val => \$printer->{currentqueue}{'queue'} },
		  { label => _("Description"),
		    val => \$printer->{currentqueue}{'desc'} },
		  { label => _("Location"),
		    val => \$printer->{currentqueue}{'loc'} },
		  ]) or 
	    printer::remove_queue($printer, $printer->{currentqueue}{'queue'}),
		      $continue = 1, last;

	    $printer->{QUEUE} = $printer->{currentqueue}{'queue'};
	    $continue = 0;
	    for ($printer->{TYPE}) {
		/LOCAL/     and setup_local    ($printer, $in, $install) and last;
		/LPD/       and setup_lpd      ($printer, $in, $install) and last;
		/SOCKET/    and setup_socket   ($printer, $in, $install) and last;
		/SMB/       and setup_smb      ($printer, $in, $install) and last;
		/NCP/       and setup_ncp      ($printer, $in, $install) and last;
		/URI/       and setup_uri      ($printer, $in, $install) and last;
		/POSTPIPE/  and setup_postpipe ($printer, $in, $install) and last;
		$continue = 1; last;
	    }
	}
	#- configure specific part according to lpr/cups.
	if (!$continue && setup_gsdriver($printer, $in, $install, $printer->{TYPE} !~ /LOCAL/ && $upNetwork)) {
	    if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
		printer::remove_queue($printer, $printer->{OLD_QUEUE});
	    }
	    delete $printer->{OLD_QUEUE}
	    if $printer->{QUEUE} ne $printer->{OLD_QUEUE} && $printer->{configured}{$printer->{QUEUE}};
	    $continue = $::expert;
	} else {
	    $continue = 1;
	}
	if ($continue) {
	    # Reinitialize $printer data structure
	    printer::resetinfo($printer);
	}
    }
}

