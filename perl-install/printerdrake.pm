package printerdrake; # $Id$

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
	eval { modules::load_multi("parport_pc", "parport_probe", "lp"); };
    }
    my $b = before_leaving { eval { modules::unload("parport_probe") } };
    detect_devices::whatPrinter();
}


sub setup_local($$$) {
    my ($printer, $in, $install) = @_;

    my @port = ();
    my @str = ();
    my @parport = auto_detect($in);
    foreach (@parport) {
	$_->{val}{DESCRIPTION} and push @str, _("A printer, model \"%s\", has been detected on ",
						$_->{val}{DESCRIPTION}) . $_->{port};
    }
    if (!$::expert && @str) {
	@port = map { $_->{port} } grep { $_->{val}{DESCRIPTION} } @parport;
	@port == 1 and $in = undef;
    } else {
	@port = detect_devices::whatPrinterPort();
    }
    $printer->{DEVICE} = $port[0] if $port[0];

    if ($in) {
	$::expert or $in->set_help('configurePrinterDev') if $::isInstall;
	return if !$in->ask_from_entries_refH(_("Local Printer Device"),
_("What device is your printer connected to 
(note that /dev/lp0 is equivalent to LPT1:)?\n") . (join "\n", @str), [
_("Printer Device") => {val => \$printer->{DEVICE}, list => \@port } ],
					     );
    }

    #- make the DeviceURI from DEVICE.
    $printer->{DeviceURI} = ($printer->{DEVICE} =~ /usb/ ? "usb:" : "parallel:") . $printer->{DEVICE};

    foreach (@parport) {
	$printer->{DEVICE} eq $_->{port} or next;
	$printer->{DBENTRY} = $printer::descr_to_db{common::bestMatchSentence2($_->{val}{DESCRIPTION},
									       @printer::entry_db_description)};
        $printer->{cupsDescr} = common::bestMatchSentence2($_->{val}{DESCRIPTION}, keys %printer::descr_to_ppd);
    }
    1;
}

sub setup_remote($$$) {
    my ($printer, $in, $install) = @_;

    return if !$in->ask_from_entries_refH(_("Remote lpd Printer Options"),
_("To use a remote lpd print queue, you need to supply
the hostname of the printer server and the queue name
on that server which jobs should be placed in."), [
_("Remote hostname") => \$printer->{REMOTEHOST},
_("Remote queue") => \$printer->{REMOTEQUEUE}, ],
			      );
    #- make the DeviceURI from DEVICE.
    $printer->{DeviceURI} = "lpd://$printer->{REMOTEHOST}/$printer->{REMOTEQUEUE}";
}

sub setup_smb($$$) {
    my ($printer, $in, $install) = @_;

    return if !$in->ask_from_entries_refH(_("SMB (Windows 9x/NT) Printer Options"),
_("To print to a SMB printer, you need to provide the
SMB host name (Note! It may be different from its
TCP/IP hostname!) and possibly the IP address of the print server, as
well as the share name for the printer you wish to access and any
applicable user name, password, and workgroup information."), [
_("SMB server host") => \$printer->{SMBHOST},
_("SMB server IP") => \$printer->{SMBHOSTIP},
_("Share name") => \$printer->{SMBSHARE},
_("User name") => \$printer->{SMBUSER},
_("Password") => { val => \$printer->{SMBPASSWD}, hidden => 1 },
_("Workgroup") => \$printer->{SMBWORKGROUP} ],
					 complete => sub {
					     unless (network::is_ip($printer->{SMBHOSTIP})) {
						 $in->ask_warn('', _("IP address should be in format 1.2.3.4"));
						 return (1,1);
					     }
					     return 0;
					 },
					);
    #- make the DeviceURI from DEVICE, try to probe for available variable to build a some suitable URI.
    #- Yes, SMBWORKGROUP is not used here, seems to be not usefull for cups.
    $printer->{DeviceURI} = join '', ("smb://",
				      ($printer->{SMBUSER} && ($printer->{SMBUSER} .
							       ($printer->{SMBPASSWD} && ":$printer->{SMBPASSWD}") . "@")),
				      ($printer->{SMBHOST} || $printer->{SMBHOSTIP}),
				      "/$printer->{SMBSHARE}");

    &$install('samba');
    $printer->{mode} eq 'CUPS' and printer::restart_queue($printer);
    1;
}

sub setup_ncp($$$) {
    my ($printer, $in, $install) = @_;

    return if !$in->ask_from_entries_refH(_("NetWare Printer Options"),
_("To print to a NetWare printer, you need to provide the
NetWare print server name (Note! it may be different from its
TCP/IP hostname!) as well as the print queue name for the printer you
wish to access and any applicable user name and password."), [
_("Printer Server") => \$printer->{NCPHOST},
_("Print Queue Name") => \$printer->{NCPQUEUE},
_("User name") => \$printer->{NCPUSER},
_("Password") => {val => \$printer->{NCPPASSWD}, hidden => 1} ],
					);
    &$install('ncpfs');
    1;
}

sub setup_socket($$$) {
    my ($printer, $in, $install) = @_;
    my ($hostname, $port);

    return if !$in->ask_from_entries_refH(_("Socket Printer Options"),
_("To print to a socket printer, you need to provide the
hostname of the printer and optionally the port number."), [
_("Printer Hostname") => \$hostname,
_("Port") => \$port ],
					 );

    #- make the DeviceURI parameters given above, these parameters are not in printer
    #- structure as only the URI is needed (cups only).
    $printer->{DeviceURI} = join '', ("socket://$hostname", $port ? (":$port") : ());
    1;
}

sub setup_uri($$$) {
    my ($printer, $in, $install) = @_;

    return if !$in->ask_from_entries_refH(_("Printer Device URI"),
_("You can specify directly the URI to access the printer with CUPS."), [
_("Printer Device URI") => { val => \$printer->{DeviceURI}, list => [ printer::get_direct_uri(),
                                                                      "file:/",
                                                                      "http://",
                                                                      "ipp://",
                                                                      "lpq://",
                                                                      "smb://",
                                                                      "socket://",
                                                                    ], not_edit => 0 }, ],
					 );
    if ($printer->{DeviceURI} =~ /^smb:/) {
        &$install('samba');
        printer::restart_queue($printer);
    }
    1;
}

sub setup_gsdriver($$$;$) {
    my ($printer, $in, $install, $upNetwork) = @_;
    for ($printer->{mode}) {
	/CUPS/ && return setup_gsdriver_cups($printer, $in, $install, $upNetwork);
	/lpr/  && return setup_gsdriver_lpr($printer, $in, $install, $upNetwork);
	die "mode not chosen to configure a printer";
    }
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

sub setup_gsdriver_lpr($$$;$) {
    my ($printer, $in, $install, $upNetwork) = @_;
    my $action;
    my @action = qw(ascii ps both done);
    my %action = (
		  ascii  => _("Yes, print ASCII test page"),
		  ps     => _("Yes, print PostScript test page"),
		  both   => _("Yes, print both test pages"),
		  done   => _("No"),
		 );

    do {
	$printer->{DBENTRY} ||= $printer::thedb_gsdriver{$printer->{GSDRIVER}}{ENTRY};
	eval { $printer->{DBENTRY} = $printer::descr_to_db{
	    $in->ask_from_list_(_("Configure Printer"),
				_("What type of printer do you have?"),
				[ @printer::entry_db_description ],
				$printer::db_to_descr{$printer->{DBENTRY}},
                                { %printer::descr_to_help })
	    };
	}; $@ =~ /^ask_from_list cancel/ and return;

	my %db_entry = %{$printer::thedb{$printer->{DBENTRY}}};

	#- specific printer drivers to install.
	#-&$install('pnm2ppa') if $db_entry{GSDRIVER} eq 'ppa';

	my @list_res = @{$db_entry{RESOLUTION} || []};
	my @res = map { "$_->{XDPI}x$_->{YDPI}" } @list_res;
	my @list_col      = @{$db_entry{BITSPERPIXEL} || []};
	my @col           = map { "$_->{DEPTH} $_->{DESCR}" } @list_col;
	my %col_to_depth  = map { ("$_->{DEPTH} $_->{DESCR}", $_->{DEPTH}) } @list_col;
	my %depth_to_col  = reverse %col_to_depth;
	my $is_uniprint = $db_entry{GSDRIVER} eq "uniprint";

	$printer->{PAPERSIZE} ||= "letter";
	$printer->{RESOLUTION} = @res ? $res[0] || "Default" : "Default" unless member($printer->{RESOLUTION}, @res);
	$printer->{ASCII_TO_PS} = $db_entry{GSDRIVER} eq 'POSTSCRIPT' unless defined($printer->{ASCII_TO_PS});
	$printer->{CRLF} = $db_entry{DESCR} =~ /HP/ unless defined($printer->{CRLF});
	$printer->{BITSPERPIXEL} = @list_col ? $depth_to_col{$printer->{BITSPERPIXEL}} || $col[0] : "Default";
	$printer->{NUP} = 1 unless member($printer->{NUP}, qw(1 2 4 8));
	$printer->{RTLFTMAR} = 18 unless $printer->{RTLFTMAR} =~ /^\d+$/;
	$printer->{TOPBOTMAR} = 18 unless $printer->{TOPBOTMAR} =~ /^\d+$/;
	$printer->{EXTRA_GS_OPTIONS} =~ s/^"(.*)"/$1/;
	$printer->{TEXTONLYOPTIONS} =~ s/^"(.*)"/$1/;

	return if !$in->ask_from_entries_refH('', _("Printer options"), [
_("Paper Size") => { val => \$printer->{PAPERSIZE}, type => 'list', not_edit => !$::expert, list => \@printer::papersize_type },
_("Eject page after job?") => { val => \$printer->{AUTOSENDEOF}, type => 'bool' },
@list_res > 1 ? (
_("Resolution") => { val => \$printer->{RESOLUTION}, type => 'list', not_edit => !$::expert, list => \@res } ) : (),
@list_col > 1 ? (
$is_uniprint ? (
_("Uniprint driver options") => { val => \$printer->{BITSPERPIXEL}, type => 'list', list => \@col } ) : (
_("Color depth options") => { val => \$printer->{BITSPERPIXEL}, type => 'list', list => \@col } ), ) : (),
$db_entry{GSDRIVER} ne 'TEXT' && $db_entry{GSDRIVER} ne 'POSTSCRIPT' && $db_entry{GSDRIVER} ne 'ppa' ? (
_("Print text as PostScript?") => { val => \$printer->{ASCII_TO_PS}, type => 'bool' }, ) : (),
#+_("Reverse page order") => { val => \$printer->{REVERSE_ORDER}, type => 'bool' },
$db_entry{GSDRIVER} ne 'POSTSCRIPT' ? (
_("Fix stair-stepping text?") => { val => \$printer->{CRLF}, type => 'bool' },
) : (),
$db_entry{GSDRIVER} ne 'TEXT' ? (
_("Number of pages per output pages") => { val => \$printer->{NUP}, type => 'list', not_edit => !$::expert, list => [1,2,4,8] },
_("Right/Left margins in points (1/72 of inch)") => \$printer->{RTLFTMAR},
_("Top/Bottom margins in points (1/72 of inch)") => \$printer->{TOPBOTMAR},
) : (),
$::expert && $db_entry{GSDRIVER} ne 'TEXT' && $db_entry{GSDRIVER} ne 'POSTSCRIPT' ? (
_("Extra GhostScript options") => \$printer->{EXTRA_GS_OPTIONS},
) : (),
$::expert && $db_entry{GSDRIVER} ne 'POSTSCRIPT' ? (
_("Extra Text options") => \$printer->{TEXTONLYOPTIONS},
) : (),
]);

        $printer->{BITSPERPIXEL} = $col_to_depth{$printer->{BITSPERPIXEL}} || $printer->{BITSPERPIXEL}; #- translate back.

	$printer->{complete} = 1;
	printer::copy_printer_params($printer, $printer->{configured}{$printer->{QUEUE}} ||= {});
	printer::configure_queue($printer);
	$printer->{complete} = 0;
	
	$action = $in->ask_from_listf('', _("Do you want to test printing?"), sub { $action{$_[0]} }, \@action, 'done');

	my @testpages;
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage.asc"
	  if $action eq "ascii" || $action eq "both";
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage". ($printer->{PAPERSIZE} eq 'a4' && '-a4') .".ps"
	  if $action eq "ps" || $action eq "both";

	if (@testpages) {
	    my @lpq_output;
	    {
		my $w = $in->wait_message('', _("Printing test page(s)..."));

		$upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
		printer::restart_queue($printer);
		@lpq_output = printer::print_pages($printer, @testpages);
	    }

	    if (@lpq_output) {
		$action = $in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
This may take a little time before printer start.
Printing status:\n%s\n\nDoes it work properly?", "@lpq_output"), 1) ? 'done' : 'change';
	    } else {
		$action = $in->ask_yesorno('', _("Test page(s) have been sent to the printer daemon.
This may take a little time before printer start.
Does it work properly?"), 1) ? 'done' : 'change';
	    }
	}
    } while ($action ne 'done');
    $printer->{complete} = 1;
}

#- Program entry point for configuration with lpr or cups (stored in $mode).
sub main($$$;$) {
    my ($printer, $in, $install, $upNetwork) = @_;
    my ($queue, $continue) = ('', 1);

    while ($continue) {
	if ($::beginner || !(scalar keys %{$printer->{configured} || {}})) {
	    $queue = $printer->{want} || $in->ask_yesorno(_("Printer"),
							  _("Would you like to configure a printer?"), 0) ? 'lp' : 'Done';
	} else {
	    $queue = $in->ask_from_list_([''],
_("Here are the following print queues.
You can add some more or change the existing ones."),
					 [ (sort keys %{$printer->{configured} || {}}), __("Add"), __("Done") ],
					);
	    if ($queue eq 'Add') {
		my %queues; @queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
		my $i = ''; while ($i < 100) { last unless exists $queues{"lp$i"}; ++$i; }
		$queue = "lp$i";
	    }
	}
	$queue eq 'Done' and last;

	#- switch according to what is being installed: cups, lpr or other.
	for ($printer->{mode}) {
	    /CUPS/ && do { &$install('cups-drivers') unless $::testing;
			   my $w = $in->wait_message(_("CUPS starting"), _("Reading CUPS drivers database..."));
			   printer::poll_ppd_base(); last };
	    /lpr/  && do { &$install('rhs-printfilters') unless $::testing;
			   printer::read_printer_db(); last };
	}

	printer::copy_printer_params($printer->{configured}{$queue}, $printer) if $printer->{configured}{$queue};
	$printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue; #- keep in mind old name of queue (in case of changing)

	while ($continue) {
	    $in->set_help('configurePrinterConnected') if $::isInstall;
	    $printer::printer_type_inv{$printer->{TYPE}} or $printer->{TYPE} = printer::default_printer_type($printer);
	    $printer->{str_type} = $printer::printer_type_inv{$printer->{TYPE}};
	    if ($printer->{mode} eq 'CUPS') {
		$printer->{str_type} = $in->ask_from_list_(_("Select Printer Connection"),
							   _("How is the printer connected?"),
							   [ printer::printer_type($printer) ],
							   $printer->{str_type},
							  );
		$printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
		if ($printer->{TYPE} eq 'REMOTE') {
		    $printer->{str_type} = $printer::printer_type_inv{CUPS};
		    $printer->{str_type} = $in->ask_from_list_(_("Select Remote Printer Connection"),
_("With a remote CUPS server, you do not have to configure
any printer here; printers will be automatically detected.
In case of doubt, select \"Remote CUPS server\"."),
							       [ @printer::printer_type_inv{qw(CUPS LPD SOCKET)} ],
							       $printer->{str_type},
							      );
		    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
		}
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
		    if ($in->ask_from_entries_refH(_("Remote CUPS server"),
_("With a remote CUPS server, you do not have to configure
any printer here; printers will be automatically detected
unless you have a server on a different network; in the
latter case, you have to give the CUPS server IP address
and optionally the port number."), [
_("CUPS server IP") => \$server,
_("Port") => \$port ],
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
		$in->set_help('configurePrinterLocal') if $::isInstall;
		$in->ask_from_entries_refH([_("Select Printer Connection"), _("Ok"),
					    $::beginner || !$printer->{configured}{$printer->{QUEUE}} ? () : _("Remove queue")],
_("Every printer need a name (for example lp).
Other parameters such as the description of the printer or its location
can be defined. What name should be used for this printer and
how is the printer connected?"), [
_("Name of printer") => { val => \$printer->{QUEUE} },
_("Description") => { val => \$printer->{Info} },
_("Location") => { val => \$printer->{Location} },
				  ],
					   ) or printer::remove_queue($printer), $continue = 1, last;
	    } else {
		if ($::beginner) {
		    $printer->{str_type} = $in->ask_from_list_(_("Select Printer Connection"),
							       _("How is the printer connected?"),
							       [ printer::printer_type($printer) ],
							       $printer->{str_type},
							      );
		} else {
		    $in->set_help('configurePrinterLPR') if $::isInstall;
		    $in->ask_from_entries_refH([_("Select Printer Connection"), _("Ok"), $::beginner ? () : _("Remove queue")],
_("Every print queue (which print jobs are directed to) needs a
name (often lp) and a spool directory associated with it. What
name and directory should be used for this queue and how is the printer connected?"), [
_("Name of queue") => { val => \$printer->{QUEUE} },
_("Spool directory") => { val => \$printer->{SPOOLDIR} },
_("Printer Connection") => { val => \$printer->{str_type}, list => [ printer::printer_type($printer) ], not_edit => 1 },
										      ],
					       changed => sub {
						   $printer->{SPOOLDIR} = printer::default_spooldir($printer) unless $_[0];
					       }
					      ) or printer::remove_queue($printer), $continue = 1, last;
		}
		$printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
	    }

	    $continue = 0;
	    for ($printer->{TYPE}) {
		/LOCAL/     and setup_local    ($printer, $in, $install) and last;
		/LPD/       and setup_remote   ($printer, $in, $install) and last;
		/SOCKET/    and setup_socket   ($printer, $in, $install) and last;
		/SMB/       and setup_smb      ($printer, $in, $install) and last;
		/NCP/       and setup_ncp      ($printer, $in, $install) and last;
		/URI/       and setup_uri      ($printer, $in, $install) and last;
		$continue = 1; last;
	    }
	}

	#- configure specific part according to lpr/cups.
	if (!$continue && setup_gsdriver($printer, $in, $install, $printer->{TYPE} !~ /LOCAL/ && $upNetwork)) {
	    delete $printer->{OLD_QUEUE}
		if $printer->{QUEUE} ne $printer->{OLD_QUEUE} && $printer->{configured}{$printer->{QUEUE}};
	    $continue = !$::beginner;
	} else {
	    $continue = 1;
	}
    }
}

