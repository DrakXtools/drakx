package printerdrake;

use diagnostics;
use strict;

use common qw(:common :file :functional :system);
use detect_devices;
use run_program;
use commands;
use modules;
use network;
use log;
use printer;

1;

sub getinfo($) {
    my ($prefix) = @_;
    my $entry = {};

    printer::set_prefix($prefix);
    printer::read_configured_queue($entry);

    add2hash($entry, {
		      want         => 0,
		      complete     => 0,
		      str_type     => $printer::printer_type_default,
		      QUEUE        => "lp",
		      SPOOLDIR     => "/var/spool/lpd/lp",
		      DBENTRY      => "PostScript",
		      PAPERSIZE    => "legal",
		      CRLF         => 0,
		      AUTOSENDEOF  => 1,

		      DEVICE       => "/dev/lp0",

		      REMOTEHOST   => "",
		      REMOTEQUEUE  => "",

		      NCPHOST      => "", #-"printerservername",
		      NCPQUEUE     => "", #-"queuename",
		      NCPUSER      => "", #-"user",
		      NCPPASSWD    => "", #-"pass",

		      SMBHOST      => "", #-"hostname",
		      SMBHOSTIP    => "", #-"1.2.3.4",
		      SMBSHARE     => "", #-"printername",
		      SMBUSER      => "", #-"user",
		      SMBPASSWD    => "", #-"passowrd",
		      SMBWORKGROUP => "", #-"AS3",
		     });
    $entry;
}

sub copy_printer_params($$) {
    my ($from, $to) = @_;

    foreach (keys %$from) {
	$to->{$_} = $from->{$_} if $_ ne 'configured'; #- avoid cycles.
    }
}

#- Program entry point.
sub main($$$$) {
    my ($prefix, $printer, $in, $install) = @_;

    unless ($::testing) {
	printer::set_prefix($prefix);
	&$install('rhs-printfilters');
    }
    printer::read_printer_db();

    $printer->{complete} = 0;
    if ($::expert || scalar keys %{$printer->{configured}}) {
	$in->ask_from_entries_ref(_("Local Printer Options"),
				  _("Every print queue (which print jobs are directed to) needs a
name (often lp) and a spool directory associated with it. What
name and directory should be used for this queue?"),
				  [_("Name of queue:"), _("Spool directory:")],
				  [\$printer->{QUEUE}, \$printer->{SPOOLDIR}],
				  changed => sub
				  {
				      $printer->{SPOOLDIR} = "$printer::spooldir/$printer->{QUEUE}" unless $_[0];
				  },
				 );
    }
    copy_printer_params($printer->{configured}{$printer->{QUEUE}}, $printer); #- get default parameters from existing queue.

    $printer->{str_type} =
      $in->ask_from_list_(_("Select Printer Connection"),
			  _("How is the printer connected?"),
			  [ keys %printer::printer_type ],
			  $printer::printer_type_inv{$printer->{TYPE}},
			 );
    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};

    if ($printer->{TYPE} eq "LOCAL") {
	{
	    my $w = $in->wait_message(_("Test ports"), _("Detecting devices..."));
	    eval { modules::load("parport_pc"); modules::load("parport_probe"); modules::load("lp"); };
	}

	my @port = ();
	my @parport = detect_devices::whatPrinter();
	eval { modules::unload("parport_probe") };
	my $str;
	if ($parport[0]) {
	    my $port = $parport[0]{port};
	    $printer->{DEVICE} = $port;
	    my $descr = common::bestMatchSentence2($parport[0]{val}{DESCRIPTION}, @printer::entry_db_description);
	    $printer->{DBENTRY} = $printer::descr_to_db{$descr};
	    $str = _("A printer, model \"%s\", has been detected on ", $parport[0]{val}{DESCRIPTION}) . $port;
	    @port = map { $_->{port}} @parport;
	} else {
	    @port = detect_devices::whatPrinterPort();
	}
	$printer->{DEVICE} = $port[0] if $port[0];

	return if !$in->ask_from_entries_ref(_("Local Printer Device"),
					     _("What device is your printer connected to  \n(note that /dev/lp0 is equivalent to LPT1:)?\n") . $str ,
					     [_("Printer Device:")],
					     [{val => \$printer->{DEVICE}, list => \@port }],
					    );
    } elsif ($printer->{TYPE} eq "REMOTE") {
	return if !$in->ask_from_entries_ref(_("Remote lpd Printer Options"),
					     _("To use a remote lpd print queue, you need to supply
the hostname of the printer server and the queue name
on that server which jobs should be placed in."),
					     [_("Remote hostname:"), _("Remote queue")],
					     [\$printer->{REMOTEHOST}, \$printer->{REMOTEQUEUE}],
					    );
    } elsif ($printer->{TYPE} eq "SMB") {
	return if !$in->ask_from_entries_ref(
	    _("SMB (Windows 9x/NT) Printer Options"),
	    _("To print to a SMB printer, you need to provide the
SMB host name (Note! It may be different from its
TCP/IP hostname!) and possibly the IP address of the print server, as
well as the share name for the printer you wish to access and any
applicable user name, password, and workgroup information."),
	    [_("SMB server host:"), _("SMB server IP:"),
	     _("Share name:"), _("User name:"), _("Password:"),
	     _("Workgroup:")],
	    [\$printer->{SMBHOST}, \$printer->{SMBHOSTIP},
	     \$printer->{SMBSHARE}, \$printer->{SMBUSER},
	     {val => \$printer->{SMBPASSWD}, hidden => 1}, \$printer->{SMBWORKGROUP}
	    ],
	     complete => sub {
		 unless (network::is_ip($printer->{SMBHOSTIP})) {
		     $in->ask_warn('', _("IP address should be in format 1.2.3.4"));
		     return (1,1);
		 }
		 return 0;
	     },
					   );
	&$install('samba');
    } elsif ($printer->{TYPE} eq "NCP") {
	return if !$in->ask_from_entries_ref(_("NetWare Printer Options"),
	    _("To print to a NetWare printer, you need to provide the
NetWare print server name (Note! it may be different from its
TCP/IP hostname!) as well as the print queue name for the printer you
wish to access and any applicable user name and password."),
	    [_("Printer Server:"), _("Print Queue Name:"),
	     _("User name:"), _("Password:")],
	    [\$printer->{NCPHOST}, \$printer->{NCPQUEUE},
	     \$printer->{NCPUSER}, {val => \$printer->{NCPPASSWD}, hidden => 1}],
					   );
	&$install('ncpfs');
    }

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
	$printer->{DBENTRY} =
	  $printer::descr_to_db{
				$in->ask_from_list_(_("Configure Printer"),
						    _("What type of printer do you have?"),
						    [@printer::entry_db_description],
						    $printer::db_to_descr{$printer->{DBENTRY}},
						   )
			       };

	my %db_entry = %{$printer::thedb{$printer->{DBENTRY}}};

	my @list_res = @{$db_entry{RESOLUTION} || []};
	my @res = map { "$_->{XDPI}x$_->{YDPI}" } @list_res;
	my @list_col      = @{$db_entry{BITSPERPIXEL} || []};
	my @col           = map { "$_->{DEPTH} $_->{DESCR}" } @list_col;
	my %col_to_depth  = map { ("$_->{DEPTH} $_->{DESCR}", $_->{DEPTH}) } @list_col;
	my %depth_to_col  = reverse %col_to_depth;
	my $is_uniprint = $db_entry{GSDRIVER} eq "uniprint";

	$printer->{RESOLUTION} = "Default" unless @list_res;
	$printer->{CRLF} = $db_entry{DESCR} =~ /HP/;
	$printer->{BITSPERPIXEL} = "Default" unless @list_col;

	$printer->{BITSPERPIXEL} = $depth_to_col{$printer->{BITSPERPIXEL}} || $printer->{BITSPERPIXEL}; #- translate.

	$in->ask_from_entries_refH('', _("Printer options"), [
_("Paper Size") => { val => \$printer->{PAPERSIZE}, type => 'list', , not_edit => !$::expert, list => \@printer::papersize_type },
_("Eject page after job?") => { val => \$printer->{AUTOSENDEOF}, type => 'bool' },
@list_res > 1 ? (
_("Resolution") => { val => \$printer->{RESOLUTION}, type => 'list', , not_edit => !$::expert, list => \@res } ) : (),
_("Fix stair-stepping text?") => { val => \$printer->{CRLF}, type => "bool" },
@list_col > 1 ? (
$is_uniprint ? (
_("Uniprint driver options") => { val => \$printer->{BITSPERPIXEL}, type => 'list', , not_edit => !$::expert, list => \@col } ) : (
_("Color depth options") => { val => \$printer->{BITSPERPIXEL}, type => 'list', , not_edit => !$::expert, list => \@col } ), ) : ()
]);;

	$printer->{BITSPERPIXEL} = $col_to_depth{$printer->{BITSPERPIXEL}} || $printer->{BITSPERPIXEL}; #- translate.

	$printer->{complete} = 1;
	copy_printer_params($printer, $printer->{configured}{$printer->{QUEUE}} ||= {});
	printer::configure_queue($printer);
	$printer->{complete} = 0;
	
	$action = ${{reverse %action}}{$in->ask_from_list('', _("Do you want to test printing?"),
							  [ map { $action{$_} } @action ], $action{'done'})};

	my $pidlpd;
	my @testpages;
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage.asc"
	  if $action eq "ascii" || $action eq "both";
	push @testpages, "/usr/lib/rhs/rhs-printfilters/testpage". ($printer->{PAPERSIZE} eq 'a4' && '-a4') .".ps"
	  if $action eq "ps" || $action eq "both";

	if (@testpages) {
	    my $w = $in->wait_message('', _(@testpages > 1 ? "Printing tests pages..." : "Printing test page..."));

	    #- restart lpd with blank spool queue.
	    foreach (("/var/spool/lpd/$printer->{QUEUE}/lock", "/var/spool/lpd/lpd.lock")) {
		$pidlpd = (cat_("$prefix$_"))[0]; kill 'TERM', $pidlpd if $pidlpd;
		unlink "$prefix$_";
	    }
	    run_program::rooted($prefix, "lprm", "-P$printer->{QUEUE}", "-"); sleep 1;
	    run_program::rooted($prefix, "lpd"); sleep 1;

	    run_program::rooted($prefix, "lpr", "-P$printer->{QUEUE}", $_) foreach @testpages;

	    sleep 3; #- allow lpr to send pages.
	    local *F; open F, "chroot $prefix/ /usr/bin/lpq -P$printer->{QUEUE} |";
	    my @lpq_output = grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <F>;

	    undef $w; #- erase wait message window.
	    if (@lpq_output) {
		$action = $in->ask_yesorno('', _("Is this correct? Printing status:\n%s", "@lpq_output"), 1) ? 'done' : 'change';
	    } else {
		$action = $in->ask_yesorno('', _("Is this correct?"), 1) ? 'done' : 'change';
	    }
	}
    } while ($action ne 'done');
    $printer->{complete} = 1;
}
