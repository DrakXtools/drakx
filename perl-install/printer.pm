package printer;

use diagnostics;
use strict;

use vars qw(%thedb %thedb_gsdriver %printer_type %printer_type_inv @papersize_type %fields @entries_db_short @entry_db_description %descr_to_help %descr_to_db %db_to_descr %descr_to_ppd);

use common qw(:common :system :file);
use commands;

#-if we are in an DrakX config
my $prefix = "";

#-location of the printer database in an installed system
my $PRINTER_DB_FILE    = "/usr/lib/rhs/rhs-printfilters/printerdb";
my $PRINTER_FILTER_DIR = "/usr/lib/rhs/rhs-printfilters";

%printer_type = (
    __("Local printer")           => "LOCAL",
    __("Remote lpd")              => "REMOTE",
    __("SMB/Windows 95/98/NT")    => "SMB",
    __("NetWare")                 => "NCP",
    __("URI for Local printer")   => "URI_LOCAL",
    __("URI for Network printer") => "URI_NET",
);
%printer_type_inv = reverse %printer_type;

%fields = (
    STANDARD => [qw(QUEUE SPOOLDIR IF)],
    SPEC     => [qw(DBENTRY RESOLUTION PAPERSIZE BITSPERPIXEL CRLF)],
    LOCAL    => [qw(DEVICE)],
    REMOTE   => [qw(REMOTEHOST REMOTEQUEUE)],
    SMB      => [qw(SMBHOST SMBHOSTIP SMBSHARE SMBUSER SMBPASSWD SMBWORKGROUP AF)],
    NCP      => [qw(NCPHOST NCPQUEUE NCPUSER NCPPASSWD)],
);
@papersize_type = qw(letter legal ledger a3 a4);

#------------------------------------------------------------------------------
sub set_prefix($) { $prefix = $_[0]; }

sub default_queue($) { (split '\|', $_[0]{QUEUE})[0] }
sub default_spooldir($) { "/var/spool/lpd/" . default_queue($_[0]) }

sub default_printer_type($) { ($_[0]{mode} eq /cups/ && "URI_") . "LOCAL" }
sub printer_type($) {
    for ($_[0]{mode}) {
	/cups/ && return @printer_type_inv{qw(URI_LOCAL URI_NET LOCAL REMOTE SMB)};
	/lpr/  && return @printer_type_inv{qw(LOCAL REMOTE SMB NCP)};
    }
}

sub copy_printer_params($$) {
    my ($from, $to) = @_;
    map { $to->{$_} = $from->{$_} } grep { $_ ne 'configured' } keys %$from; #- avoid cycles.
}

sub getinfo($) {
    my ($prefix) = @_;
    my $printer = {};

    set_prefix($prefix);

    #- try to detect which printing system has been previously installed.
    #- the first detected is the default.
    read_printers_conf($printer); #- try to read existing cups (local only) queues.
    read_configured_queue($printer); #- try to read existing lpr queues.

    add2hash($printer, {
			#- global parameters.
			want         => 0,
			complete     => 0,
			str_type     => undef,
			QUEUE        => "lp",

			#- lpr parameters.
			SPOOLDIR     => "/var/spool/lpd/lp",
			DBENTRY      => "PostScript",
			PAPERSIZE    => "",
			ASCII_TO_PS  => undef,
			CRLF         => undef,
			NUP          => 1,
			RTLFTMAR     => 18,
			TOPBOTMAR    => 18,
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

			#- cups parameters.
			DeviceURI    => "parallel:/dev/lp0",
			Info         => "",
			Location     => "",
			State        => "Idle",
			Accepting    => "Yes",
		       });
    $printer;
}

#------------------------------------------------------------------------------
sub read_configured_queue($) {
    my ($printer) = @_;
    my $current = undef;
    my $flush_current = sub {
	if ($current) {
	    add2hash($printer->{configured}{$current->{QUEUE}} ||= {}, $current);
	    $current = undef;
	}
    };

    #- read /etc/printcap file.
    local *PRINTCAP; open PRINTCAP, "$prefix/etc/printcap" or return;
    foreach (<PRINTCAP>) {
	chomp;
	my $p = '(?:\{(.*?)\}|(\S+))';
	if (/^##PRINTTOOL3##\s+$p\s+$p\s+$p\s+$p\s+$p\s+$p\s+$p(?:\s+$p)?/) {
	    &$flush_current;
	    $current = {
			TYPE => $1 || $2,
			GSDRIVER => $3 || $4,
			RESOLUTION => $5 || $6,
			PAPERSIZE => $7 || $8,
			#- ignored $9 || $10,
			DBENTRY => $11 || $12,
			BITSPERPIXEL => $13 || $14,
			CRLF => $15 || $16,
		       };
	} elsif (/^\s*$/) { &$flush_current }
	elsif (/^([^:]*):\\/) { $current->{QUEUE} = $1 }
	if (/^\s+:(?:[^:]*:)*sd=([^:]*):/) { $current->{SPOOLDIR} = $1 }
	if (/^\s+:(?:[^:]*:)*lp=([^:]*):\\/) { $current->{DEVICE} = $1 }
	if (/^\s+:(?:[^:]*:)*rm=([^:]*):\\/) { $current->{REMOTEHOST} = $1 }
	if (/^\s+:(?:[^:]*:)*rp=([^:]*):\\/) { $current->{REMOTEQUEUE} = $1 }
	if (/^\s+:(?:[^:]*:)*af=([^:]*):\\/) { $current->{AF} = $1 }
	if (/^\s+:(?:[^:]*:)*if=([^:]*):\\/) { $current->{IF} = $1 }
    }
    close PRINTCAP;
    &$flush_current;

    #- parse general.cfg for any configured queue.
    foreach (values %{$printer->{configured}}) {
	my $entry = $_;
	local *F; open F, "$prefix$entry->{SPOOLDIR}/general.cfg" or next;
	foreach (<F>) {
	    chomp;
	    if (/^\s*(?:export\s+)?PRINTER_TYPE=(.*?)\s*$/) { $entry->{TYPE} = $1 unless defined $entry->{TYPE} }
	    elsif (/^\s*(?:export\s+)?ASCII_TO_PS=(.*?)\s*$/) { $entry->{ASCII_TO_PS} = $1 eq 'YES' unless defined $entry->{ASCII_TO_PS} }
	    elsif (/^\s*(?:export\s+)?PAPER_SIZE=(.*?)\s*$/) { $entry->{PAPERSIZE} = $1 unless defined $entry->{PAPERSIZE} }
	}
	close F;
    }

    #- parse postscript.cfg for any configured queue.
    foreach (values %{$printer->{configured}}) {
	my $entry = $_;
	local *F; open F, "$prefix$entry->{SPOOLDIR}/postscript.cfg" or next;
	foreach (<F>) {
	    chomp;
	    if (/^\s*(?:export\s+)?GSDEVICE=(.*?)\s*$/) { $entry->{GSDRIVER} = $1 unless defined $entry->{GSDRIVER} }
	    elsif (/^\s*(?:export\s+)?RESOLUTION=(.*?)\s*$/) { $entry->{RESOLUTION} = $1 unless defined $entry->{RESOLUTION} }
	    elsif (/^\s*(?:export\s+)?COLOR=-dBitsPerPixel=(.*?)\s*$/) { $entry->{COLOR} = $1 unless defined $entry->{COLOR} }
	    elsif (/^\s*(?:export\s+)?COLOR=(.*?)\s*$/) { $entry->{COLOR} = $1 ? $1 : 'Default' unless defined $entry->{COLOR} }
	    elsif (/^\s*(?:export\s+)?PAPERSIZE=(.*?)\s*$/) { $entry->{PAPERSIZE} = $1 unless defined $entry->{PAPERSIZE} }
	    elsif (/^\s*(?:export\s+)?EXTRA_GS_OPTIONS=(.*?)\s*$/) { $entry->{EXTRA_GS_OPTIONS} = $1 unless defined $entry->{EXTRA_GS_OPTIONS}; $entry->{EXTRA_GS_OPTIONS} =~ s/^\"(.*)\"/$1/ }
	    elsif (/^\s*(?:export\s+)?REVERSE_ORDER=(.*?)\s*$/) { $entry->{REVERSE_ORDER} = $1 unless defined $entry->{REVERSE_ORDER} }
	    elsif (/^\s*(?:export\s+)?PS_SEND_EOF=(.*?)\s*$/) { $entry->{AUTOSENDEOF} = $1 eq 'YES' && $entry->{DBENTRY} eq 'PostScript' unless defined $entry->{AUTOSENDEOF} }
	    elsif (/^\s*(?:export\s+)?NUP=(.*?)\s*$/) { $entry->{NUP} = $1 unless defined $entry->{NUP} }
	    elsif (/^\s*(?:export\s+)?RTLFTMAR=(.*?)\s*$/) { $entry->{RTLFTMAR} = $1 unless defined $entry->{RTLFTMAR} }
	    elsif (/^\s*(?:export\s+)?TOPBOTMAR=(.*?)\s*$/) { $entry->{TOPBOTMAR} = $1 unless defined $entry->{TOPBOTMAR} }
	}
	close F;
    }

    #- parse textonly.cfg for any configured queue.
    foreach (values %{$printer->{configured}}) {
	my $entry = $_;
	local *F; open F, "$prefix$entry->{SPOOLDIR}/textonly.cfg" or next;
	foreach (<F>) {
	    chomp;
	    if (/^\s*(?:export\s+)?TEXTONLYOPTIONS=(.*?)\s*$/) { $entry->{TEXTONLYOPTIONS} = $1 unless defined $entry->{TEXTONLYOPTIONS}; $entry->{TEXTONLYOPTIONS} =~ s/^\"(.*)\"/$1/ }
	    elsif (/^\s*(?:export\s+)?CRLFTRANS=(.*?)\s*$/) { $entry->{CRLF} = $1 eq 'YES' unless defined $entry->{CRLF} }
	    elsif (/^\s*(?:export\s+)?TEXT_SEND_EOF=(.*?)\s*$/) { $entry->{AUTOSENDEOF} = $1 eq 'YES' && $entry->{DBENTRY} ne 'PostScript' unless defined $entry->{AUTOSENDEOF} }
	}
	close F;
    }

    #- get extra parameters for SMB or NCP type queue.
    foreach (values %{$printer->{configured}}) {
	my $entry = $_;
	if ($entry->{TYPE} eq 'SMB') {
	    my $config_file = "$prefix$entry->{SPOOLDIR}/.config";
	    local *F; open F, "$config_file" or next; #die "Can't open $config_file $!";
	    foreach (<F>) {
		chomp;
		if (/^\s*share='\\\\(.*?)\\(.*?)'/) {
		    $entry->{SMBHOST} = $1;
		    $entry->{SMBSHARE} = $2;
		} elsif (/^\s*hostip=(.*)/) {
		    $entry->{SMBHOSTIP} = $1;
		} elsif (/^\s*user='(.*)'/) {
		    $entry->{SMBUSER} = $1;
		} elsif (/^\s*password='(.*)'/) {
		    $entry->{SMBPASSWD} = $1;
		} elsif (/^\s*workgroup='(.*)'/) {
		    $entry->{SMBWORKGROUP} = $1;
		}
	    }
	    close F;
	} elsif ($entry->{TYPE} eq 'NCP') {
	    my $config_file = "$prefix$entry->{SPOOLDIR}/.config";
	    local *F; open F, "$config_file" or next; #die "Can't open $config_file $!";
	    foreach (<F>) {
		chomp;
		if (/^\s*server=(.*)/) {
		    $entry->{NCPHOST} = $1;
		} elsif (/^\s*user='(.*)'/) {
		    $entry->{NCPUSER} = $1;
		} elsif (/^\s*password='(.*)'/) {
		    $entry->{NCPPASSWD} = $1;
		} elsif (/^\s*queue='(.*)'/) {
		    $entry->{NCPQUEUE} = $1;
		}
	    }
	    close F;
	}
    }

    #- assume this printing system.
    $printer->{mode} ||= 'lpr';
}

sub read_printer_db(;$) {
    my $dbpath = $prefix . ($_[0] || $PRINTER_DB_FILE);

    scalar(keys %thedb) > 4 and return; #- try reparse if using only ppa, POSTSCRIPT, TEXT.

    my %available_devices; #- keep only available devices in our database.
    local *AVAIL; open AVAIL, ($::testing ? "$prefix" : "chroot $prefix/ ") . "/usr/bin/gs --help |";
    foreach (<AVAIL>) {
	if (/^Available devices:/ ... /^\S/) {
	    @available_devices{split /\s+/, $_} = () if /^\s+/;
	}
    }
    close AVAIL;
    $available_devices{ppa} = undef; #- if -x "$prefix/usr/bin/pbm2ppa" && -x "$prefix/usr/bin/pnm2ppa";
    delete $available_devices{''};
    @available_devices{qw/POSTSCRIPT TEXT/} = (); #- these are always available.

    local $_; #- use of while (<...
    local *DBPATH; #- don't have to do close ... and don't modify globals at least
    open DBPATH, $dbpath or die "An error has occurred on $dbpath : $!";

    while (<DBPATH>) {
	if (/^StartEntry:\s(\w*)/) {
	    my $entry = { ENTRY => $1 };

	  WHILE :
	      while (<DBPATH>) {
		SWITCH: {
		      /GSDriver:\s*(\w*)/      and do { $entry->{GSDRIVER} = $1; last SWITCH };
		      /Description:\s*{(.*)}/  and do { $entry->{DESCR}    = $1; last SWITCH };
		      /About:\s*{\s*(.*?)\s*}/ and do { $entry->{ABOUT}    = $1; last SWITCH };
		      /About:\s*{\s*(.*?)\s*\\\s*$/
			and do {
			    my $string = $1;
			    while (<DBPATH>) {
				$string =~ /\S$/ and $string .= ' ';
				/^\s*(.*?)\s*\\\s*$/ and $string .= $1;
				/^\s*(.*?)\s*}\s*$/  and do { $entry->{ABOUT} = $string . $1; last SWITCH };
			    }
			};
		      /Resolution:\s*{(.*)}\s*{(.*)}\s*{(.*)}/
			and do { push @{$entry->{RESOLUTION} ||= []}, { XDPI => $1, YDPI => $2, DESCR => $3 }; last SWITCH };
		      /BitsPerPixel:\s*{(.*)}\s*{(.*)}/
			and do { push @{$entry->{BITSPERPIXEL} ||= []}, {DEPTH => $1, DESCR => $2}; last SWITCH };

		      /EndEntry/ and last WHILE;
		  }
	      }
	    if (exists $available_devices{$entry->{GSDRIVER}}) {
		$thedb{$entry->{ENTRY}} = $entry;
		$thedb_gsdriver{$entry->{GSDRIVER}} = $entry;
	    }
	}
    }

    @entries_db_short     = sort keys %printer::thedb;
    %descr_to_db          = map { $printer::thedb{$_}{DESCR}, $_ } @entries_db_short;
    %descr_to_help        = map { $printer::thedb{$_}{DESCR}, $printer::thedb{$_}{ABOUT} } @entries_db_short;
    @entry_db_description = keys %descr_to_db;
    %db_to_descr          = reverse %descr_to_db;
}

#------------------------------------------------------------------------------
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
    foreach (<PRINTERS>) {
	chomp;
	/^\s*#/ and next;
	if (/^\s*<(?:DefaultPrinter|Printer)\s+([^>]*)>/) { $current = { QUEUE => $1, } }
	elsif (/\s*<\/Printer>/) { $current->{QUEUE} && $current->{DeviceURI} or next; #- minimal check of synthax.
				   add2hash($printer->{configured}{$current->{QUEUE}} ||= {}, $current); $current = undef }
	elsif (/\s*(\S*)\s+(.*)/) { $current->{$1} = $2 }
    }
    close PRINTERS;

    #- assume this printing system.
    $printer->{mode} ||= 'cups';
}

sub get_direct_uri {
    #- get the local printer to access via a Device URI.
    my @direct_uri;
    local *F; open F, "chroot $prefix/ /usr/sbin/lpinfo -v |";
    foreach (<F>) {
	/^(direct|usb|serial)\s+(\S*)/ and push @direct_uri, $2;
    }
    close F;
    @direct_uri;
}

sub get_descr_from_ppd {
    my ($printer) = @_;
    my %ppd;

    local *F; open F, "$prefix/etc/cups/ppd/$printer->{QUEUE}.ppd" or return;
    foreach (<F>) {
	/^\*([^\s:]*)\s*:\s*\"([^\"]*)\"/ and do { $ppd{$1} = $2; next };
	/^\*([^\s:]*)\s*:\s*([^\s\"]*)/   and do { $ppd{$1} = $2; next };
    }
    close F;

    $ppd{Manufacturer} . '|' . ($ppd{NickName} || $ppd{ShortNickName} || $ppd{ModelName}) .
      ($ppd{LanguageVersion} && (" (" . lc(substr($ppd{LanguageVersion}, 0, 2)) . ")"));
}

sub poll_ppd_base {
    #- before trying to poll the ppd database available to cups, we have to make sure
    #- the file /etc/cups/ppds.dat is no more modified.
    #- if cups continue to modify it (because it reads the ppd files available), the
    #- poll_ppd_base program simply cores :-)
    run_program::rooted($prefix, "/etc/rc.d/init.d/cups start");

    foreach (1..10) {
	local *PPDS; open PPDS, "chroot $prefix/ /usr/bin/poll_ppd_base -a |";
	foreach (<PPDS>) {
	    chomp;
	    my ($ppd, $mf, $descr, $lang) = split /\|/;
	    $ppd && $mf && $descr and $descr_to_ppd{"$mf|$descr" . ($lang && " ($lang)")} = $ppd;
	}
	close PPDS;
	scalar(keys %descr_to_ppd) > 5 and last;
	sleep 1; #- we have to try again running the program, wait here a little before.
    }
}

#-******************************************************************************
#- write functions
#-******************************************************************************

#------------------------------------------------------------------------------
#- given the path queue_path, we create all the required spool directory
#------------------------------------------------------------------------------
sub create_spool_dir($) {
    my ($queue_path) = @_;
    my $complete_path = "$prefix/$queue_path";

    commands::mkdir_("-p", $complete_path);

    unless ($::testing) {
	#-redhat want that "drwxr-xr-x root lp"
	my $gid_lp = (getpwnam("lp"))[3];
	chown 0, $gid_lp, $complete_path
	  or die "An error has occurred - can't chgrp $complete_path to lp $!";
    }
}

#------------------------------------------------------------------------------
#-given the input spec file 'input', and the target output file 'output'
#-we set the fields specified by fieldname to the values in fieldval
#-nval  is the number of fields to set
#-Doesnt currently catch error exec'ing sed yet
#------------------------------------------------------------------------------
sub create_config_file($$%) {
    my ($inputfile, $outputfile, %toreplace) = @_;
    template2file("$prefix/$inputfile", "$prefix/$outputfile", %toreplace);
    eval { commands::chown_("root.lp", "$prefix/$outputfile") };
}


#------------------------------------------------------------------------------
#-copy master filter to the spool dir
#------------------------------------------------------------------------------
sub copy_master_filter($) {
    my ($queue_path) = @_;
    my $complete_path = "$prefix/$queue_path/filter";
    my $master_filter = "$prefix/$PRINTER_FILTER_DIR/master-filter";

    eval { commands::cp('-f', $master_filter, $complete_path) };
    $@ and die "Can't copy $master_filter to $complete_path $!";
    eval { commands::chown_("root.lp", $complete_path); };
}

#------------------------------------------------------------------------------
#- given a PrintCap Entry, create the spool dir and special
#- rhs-printfilters related config files which are required
#------------------------------------------------------------------------------
my $intro_printcap_test = "
#
# Please don't edit this file directly unless you know what you are doing!
# Look at the printcap(5) man page for more info.
# Be warned that the control-panel printtool requires a very strict format!
#
# This file can be edited with printerdrake or printtool.
#

";

sub configure_queue($) {
    my ($entry) = @_;

    for ($entry->{mode}) {
	/cups/ && do {
	    #- at this level, we are using lpadmin to create a local printer (only local
	    #- printer are supported with printerdrake).
	    require run_program;
	    run_program::rooted($prefix, "lpadmin",
				"-p", $entry->{QUEUE},
				$entry->{State} eq 'Idle' && $entry->{Accepting} eq 'Yes' ? ("-E") : (),
				"-v", $entry->{DeviceURI},
				"-m", $entry->{cupsPPD},
				$entry->{Info} ? ("-D", $entry->{Info}) : (),
				$entry->{Location} ? ("-L", $entry->{Location}) : (),
			       );
	    last };
	/lpr/  && do {
	    #- old style configuration scheme for lpr.
	    my $queue_path = "$entry->{SPOOLDIR}";
	    create_spool_dir($queue_path);

	    my $get_name_file = sub {
		my ($name) = @_;
		("$PRINTER_FILTER_DIR/$name.in", "$entry->{SPOOLDIR}/$name")
	    };
	    my ($filein, $file);
	    my %fieldname = ();
	    my $dbentry = $thedb{($entry->{DBENTRY})} or die "no dbentry";

	    #- make general.cfg
	    ($filein, $file) = &$get_name_file("general.cfg");
	    $fieldname{ascps_trans} = $entry->{ASCII_TO_PS} || $dbentry->{GSDRIVER} eq 'ppa' ? "YES" : "NO";
	    $fieldname{desiredto}   = $dbentry->{GSDRIVER} ne "TEXT" ? "ps" : "asc";
	    $fieldname{papersize}   = $entry->{PAPERSIZE} ? $entry->{PAPERSIZE} : "letter";
	    $fieldname{printertype} = $entry->{TYPE};
	    create_config_file($filein, $file, %fieldname);

	    #- now do postscript.cfg
	    ($filein, $file) = &$get_name_file("postscript.cfg");
	    %fieldname = ();
	    $fieldname{gsdevice}       = $dbentry->{GSDRIVER};
	    $fieldname{papersize}      = $entry->{PAPERSIZE} ? $entry->{PAPERSIZE} : "letter";
	    $fieldname{resolution}     = $entry->{RESOLUTION};
	    $fieldname{color}          = $entry->{BITSPERPIXEL} ne "Default" &&
	      (($dbentry->{GSDRIVER} ne "uniprint" && "-dBitsPerPixel=") . $entry->{BITSPERPIXEL});
	    $fieldname{reversepages}   = $entry->{REVERSE_ORDER} ? "YES" : "";
	    $fieldname{extragsoptions} = "\"$entry->{EXTRA_GS_OPTIONS}\"";
	    $fieldname{pssendeof}      = $entry->{AUTOSENDEOF} ? ($dbentry->{GSDRIVER} eq "POSTSCRIPT" ? "YES" : "NO") : "NO";
	    $fieldname{nup}            = $entry->{NUP};
	    $fieldname{rtlftmar}       = $entry->{RTLFTMAR};
	    $fieldname{topbotmar}      = $entry->{TOPBOTMAR};
	    create_config_file($filein, $file, %fieldname);

	    #- finally, make textonly.cfg
	    ($filein, $file) = &$get_name_file("textonly.cfg");
	    %fieldname = ();
	    $fieldname{textonlyoptions} = "\"$entry->{TEXTONLYOPTIONS}\"";
	    $fieldname{crlftrans}       = $entry->{CRLF} ? "YES" : "";
	    $fieldname{textsendeof}     = $entry->{AUTOSENDEOF} ? ($dbentry->{GSDRIVER} eq "POSTSCRIPT" ? "NO" : "YES") : "NO";
	    create_config_file($filein, $file, %fieldname);

	    if ($entry->{TYPE} eq "SMB") {
		#- simple config file required if SMB printer
		my $config_file = "$prefix$queue_path/.config";
		local *F;
		open F, ">$config_file" or die "Can't create $config_file $!";
		print F "share='\\\\$entry->{SMBHOST}\\$entry->{SMBSHARE}'\n";
		print F "hostip=$entry->{SMBHOSTIP}\n";
		print F "user='$entry->{SMBUSER}'\n";
		print F "password='$entry->{SMBPASSWD}'\n";
		print F "workgroup='$entry->{SMBWORKGROUP}'\n";
		close F;
		eval { chmod 0640, $config_file; commands::chown_("root.lp", $config_file) };
	    } elsif ($entry->{TYPE} eq "NCP") {
		#- same for NCP printer
		my $config_file = "$prefix$queue_path/.config";
		local *F;
		open F, ">$config_file" or die "Can't create $config_file $!";
		print F "server=$entry->{NCPHOST}\n";
		print F "queue=$entry->{NCPQUEUE}\n";
		print F "user=$entry->{NCPUSER}\n";
		print F "password=$entry->{NCPPASSWD}\n";
		close F;
		eval { chmod 0640, $config_file; commands::chown_("root.lp", $config_file) };
	    }

	    copy_master_filter($queue_path);

	    #-now the printcap file, note this one contains all the printer (use configured for that).
	    local *PRINTCAP;
	    open PRINTCAP, ">$prefix/etc/printcap" or die "Can't open printcap file $!";
	    print PRINTCAP $intro_printcap_test;
	    foreach (values %{$entry->{configured}}) {
		$_->{DBENTRY} = $thedb_gsdriver{$_->{GSDRIVER}}{ENTRY} unless defined $_->{DBENTRY};
		my $db_ = $thedb{$_->{DBENTRY}} or next; #die "no dbentry";

		$_->{SPOOLDIR} ||= default_spooldir($_);
		$_->{IF}       ||= "$_->{SPOOLDIR}/filter";
		$_->{AF}       ||= "$_->{SPOOLDIR}/acct";

		printf PRINTCAP "##PRINTTOOL3##  %s %s %s %s %s %s %s%s\n",
		  $_->{TYPE} || '{}',
		    $db_->{GSDRIVER} || '{}',
		      $_->{RESOLUTION} || '{}',
			$_->{PAPERSIZE} || '{}',
			  '{}',
			    $db_->{ENTRY} || '{}',
			      $_->{BITSPERPIXEL} || '{}',
				$_->{CRLF} ? " 1" : "";

		print PRINTCAP "$_->{QUEUE}:\\\n";
		print PRINTCAP "\t:sd=$_->{SPOOLDIR}:\\\n";
		print PRINTCAP "\t:mx#0:\\\n\t:sh:\\\n";

		if ($_->{TYPE} eq "LOCAL") {
		    print PRINTCAP "\t:lp=$_->{DEVICE}:\\\n";
		} elsif ($_->{TYPE} eq "REMOTE") {
		    print PRINTCAP "\t:rm=$_->{REMOTEHOST}:\\\n";
		    print PRINTCAP "\t:rp=$_->{REMOTEQUEUE}:\\\n";
		} else {
		    #- (pcentry->Type == (PRINTER_SMB | PRINTER_NCP))
		    print PRINTCAP "\t:lp=/dev/null:\\\n";
		    print PRINTCAP "\t:af=$_->{AF}\\\n";
		}

		#- cheating to get the input filter!
		print PRINTCAP "\t:if=$_->{IF}:\n";
		print PRINTCAP "\n";
	    }
	    eval { commands::chown_("root.lp", "$prefix/etc/printcap") };

	    my $useUSB = 0;
	    foreach (values %{$entry->{configured}}) {
		$useUSB ||= $_->{DEVICE} =~ /usb/;
	    }
	    if ($useUSB) {
		my $f = "$prefix/etc/sysconfig/usb";
		my %usb = getVarsFromSh($f);
		$usb{PRINTER} = "yes";
		setVarsInSh($f, \%usb);
	    }
	    last };
    }
}

#- use the queue currently configured at the top of printer hash.
sub remove_queue($) {
    my ($printer) = @_;
    $printer->{configured}{$printer->{QUEUE}} or return; #- something strange at this point.

    if ($printer->{mode} eq 'cups') {
	require run_program;
	run_program::rooted($prefix, "lpadmin", "-x", $printer->{QUEUE});
    }
    delete $printer->{configured}{$printer->{queue}};
}

sub restart_queue($) {
    my ($printer) = @_;
    my $queue = default_queue($printer);

    for ($printer->{mode}) {
	/cups/ && do {
	    #- restart cups before cleaning the queue.
	    require run_program;
	    run_program::rooted($prefix, "/etc/rc.d/init.d/cups start"); sleep 1;
	    run_program::rooted($prefix, "lprm-cups", "-P$queue", "-");
	    last };
	/lpr/  && do {
	    #- restart lpd after cleaning the queue.
	    foreach (("/var/spool/lpd/$queue/lock", "/var/spool/lpd/lpd.lock")) {
		my $pidlpd = (cat_("$prefix$_"))[0];
		kill 'TERM', $pidlpd if $pidlpd;
		unlink "$prefix$_";
	    }
	    require run_program;
	    run_program::rooted($prefix, "lprm-lpd", "-P$queue", "-"); sleep 1;
	    run_program::rooted($prefix, "lpd"); sleep 1;
	    last };
    }
}

sub print_pages($@) {
    my ($printer, @pages) = @_;
    my $queue = default_queue($printer);
    my ($lpr, $lpq);

    for ($printer->{mode}) {
	/cups/ and ($lpr, $lpq) = ("/usr/bin/lpr-cups", "/usr/bin/lpq-cups");
	/lpr/  and ($lpr, $lpq) = ("/usr/bin/lpq-lpd", "/usr/bin/lpq-lpd");
    }

    require run_program;
    foreach (@pages) {
	run_program::rooted($prefix, $lpr, "-P$queue", $_);
    }
    sleep 5; #- allow lpr to send pages.
    local *F; open F, "chroot $prefix/ $lpq -P$queue |";
    my @lpq_output = grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <F>;
    close F;
    @lpq_output;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
