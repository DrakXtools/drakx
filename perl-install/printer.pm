package printer;
#-#####################################################################################

=head1 NAME

printer - supply methods for manage the printer related files directory handles

=head1 SYNOPSIS

use printer;

=head1 DESCRIPTION

Use the source.

=cut

#-#####################################################################################

use diagnostics;
use strict;


#-#####################################################################################

=head2 Exported variable

=cut

#-#####################################################################################
use vars qw(%thedb %thedb_gsdriver %printer_type %printer_type_inv $printer_type_default @papersize_type %fields $spooldir @entries_db_short @entry_db_description %descr_to_help %descr_to_db %db_to_descr);
#-#####################################################################################

=head2 Imports

=cut

#-#####################################################################################
use Data::Dumper;

#-#####################################################################################

=head2 pixel imports

=cut

use common qw(:common :system :file);
use commands;

#-#####################################################################################

#-#####################################################################################

=head2 Examples and types

=over 4

=item *

an entry in the 'printerdb' file, which describes each type of
supported printer:

	StartEntry: DeskJet550
	  GSDriver: cdj550
	  Description: {HP DeskJet 550C/560C/6xxC series}
	  About: { \
		     This driver supports the HP inkjet printers which have \
		     color capability using both black and color cartridges \
		     simultaneously. Known to work with the 682C and the 694C. \
		     Other 600 and 800 series printers may work \
		     if they have this feature. \
		     If your printer seems to be saturating the paper with ink, \
		     try added an extra GS option of '-dDepletion=2'. \
		     Ghostscript supports several optional parameters for \
		     this driver: see the document 'devices.doc' \
		     in the ghostscript directory under /usr/doc. \
		   }
	  Resolution: {300} {300} {}
	  BitsPerPixel:  {3} {Normal color printing with color cartridge}
	  BitsPerPixel:  {8} {Floyd-Steinberg B & W printing for better greys}
	  BitsPerPixel: {24} {Floyd-Steinberg Color printing (best, but slow)}
	  BitsPerPixel: {32} {Sometimes provides better output than 24}
	EndEntry

Example of data-struct:

	my %ex_printerdb_entry =
	  (
	   ENTRY    => "DeskJet550",                               #-Human-readable name of the entry
	   GSDRIVER => "cdj550",                                   #-gs driver used by this printer
	   DESCR    => "HP DeskJet 550C/560C/6xxC series",         #-Single line description of printer
	   ABOUT    => "
	   This driver supports the HP inkjet printers which have
	   color capability using both black and color cartridges
		...",                                              #-Lengthy description of printer
	   RESOLUTION   => [                                       #-List of resolutions supported
			    {
			     XDPI    => 300,
			     YDPI    => 300,
			     DESCR   => "commentaire",
			    },
			   ],
	   BITSPERPIXEL => [                                       #-List of color depths supported
			    {
			     DEPTH => 3,
			     DESCR => "Normal color printing with color cartridge",
			    },
			   ],
	  )
	;

=item *

A printcap entry only represents a subset of possible options available
Sufficient for the simple configuration we are interested in
there is also some text in the template (.in) file in the spooldir

	# /etc/printcap
	#
	# Please don't edit this file directly unless you know what you are doing
	# Be warned that the control-panel printtool requires a very strict forma
	# Look at the printcap(5) man page for more info.
	#
	# This file can be edited with the printtool in the control-panel.

	##PRINTTOOL3## LOCAL uniprint NAxNA letter {} U_NECPrinwriter2X necp2x6 1
	lpname:\
		:sd=/var/spool/lpd/lpnamespool:\
		:mx#45:\
		:sh:\
		:lp=/dev/device:\
		:if=/var/spool/lpd/lpnamespool/filter:
	##PRINTTOOL3## REMOTE st800 360x180 a4 {} EpsonStylus800 Default 1
	remote:\
		:sd=/var/spool/lpd/remotespool:\
		:mx#47:\
		:sh:\
		:rm=remotehost:\
		:rp=remotequeue:\
		:if=/var/spool/lpd/remotespool/filter:
	##PRINTTOOL3## SMB la75plus 180x180 letter {} DECLA75P Default {}
	smb:\
		:sd=/var/spool/lpd/smbspool:\
		:mx#46:\
		:sh:\
		:if=/var/spool/lpd/smbspool/filter:\
		:af=/var/spool/lpd/smbspool/acct:\
		:lp=/dev/null:
	##PRINTTOOL3## NCP ap3250 180x180 letter {} EpsonAP3250 Default {}
	ncp:\
		:sd=/var/spool/lpd/ncpspool:\
		:mx#46:\
		:sh:\
		:if=/var/spool/lpd/ncpspool/filter:\
		:af=/var/spool/lpd/ncpspool/acct:\
		:lp=/dev/null:

Example of data-struct:

	my %ex_printcap_entry =
	  (
	   QUEUE    => "lpname",                            #-Queue name, can have multi separated by '|'

	   #-if you want something different from the default
	   SPOOLDIR => "/var/spool/lpd/lpnamespool/",        #-Spool directory
	   IF       => "/var/spool/lpd/lpnamespool/filter",  #-input filter

	   #- commentaire inserer dans le printcap pour que printtool retrouve ses petits
	   DBENTRY      => "DeskJet670",                    #-entry in printer database for this printer

	   RESOLUTION   => "NAxNA",                         #-ghostscript resolution to use
	   PAPERSIZE    => "letter",                        #-Papersize
	   BITSPERPIXEL => "necp2x6",                       #-ghostscript color option
	   CRLF         => 1 ,                              #-Whether or not to do CR/LF xlation

	   TYPE         => "LOCAL",

	   #- LOCAL
	   DEVICE   => "/dev/device",                       #-Print device

	   #- REMOTE (lpd) printers only
	   REMOTEHOST   => "remotehost",                     #-Remote host (not used for all entries)
	   REMOTEQUEUE  => "remotequeue",                    #-Queue on the remote machine


	   #-SMB (LAN Manager) only
	   #- in spooldir/.config
	   #-share='\\hostname\printername'
	   #-hostip=1.2.3.4
	   #-user='user'
	   #-password='passowrd'
	   #-workgroup='AS3'
	   SMBHOST   => "hostname",                              #-Server name (NMB name, can have spaces)
	   SMBHOSTIP => "1.2.3.4",                               #-Can optional specify and IP address for host
	   SMBSHARE  => "printername",                           #-Name of share on the SMB server
	   SMBUSER   => "user",                                  #-User to log in as on SMB server
	   SMBPASSWD => "passowrd",                              #-Corresponding password
	   SMBWORKGROUP => "AS3",                                #-SMB workgroup name
	   AF        => "/var/spool/lpd/smbspool/acct",           #-accounting filter (needed for smbprint)

	   #- NCP (NetWare) only
	   #- in spooldir/.config
	   #-server=printerservername
	   #-queue=queuename
	   #-user=user
	   #-password=pass
	   NCPHOST   => "printerservername",            #-Server name (NCP name)
	   NCPQUEUE  => "queuename",                    #-Queue on server
	   NCPUSER   => "user",                         #-User to log in as on NCP server
	   NCPPASSWD => "pass",                         #-Corresponding password

	  )
	;

=cut

#-#####################################################################################

=head2 Intern constant

=cut

#-#####################################################################################

#-if we are in an DrakX config
my $prefix = "";

#-location of the printer database in an installed system
my $PRINTER_DB_FILE    = "/usr/lib/rhs/rhs-printfilters/printerdb";
my $PRINTER_FILTER_DIR = "/usr/lib/rhs/rhs-printfilters";




#-#####################################################################################

=head2 Exported constant

=cut

#-#####################################################################################

%printer_type = (
    __("Local printer")     => "LOCAL",
    __("Remote lpd")        => "REMOTE",
    __("SMB/Windows 95/98/NT") => "SMB",
    __("NetWare")           => "NCP",
);
%printer_type_inv = reverse %printer_type;
$printer_type_default = "Local printer";

%fields = (
    STANDARD => [qw(QUEUE SPOOLDIR IF)],
    SPEC     => [qw(DBENTRY RESOLUTION PAPERSIZE BITSPERPIXEL CRLF)],
    LOCAL    => [qw(DEVICE)],
    REMOTE   => [qw(REMOTEHOST REMOTEQUEUE)],
    SMB      => [qw(SMBHOST SMBHOSTIP SMBSHARE SMBUSER SMBPASSWD SMBWORKGROUP AF)],
    NCP      => [qw(NCPHOST NCPQUEUE NCPUSER NCPPASSWD)],
);
@papersize_type = qw(letter legal ledger a3 a4);
$spooldir       = "/var/spool/lpd";

#-#####################################################################################

=head2 Functions

=cut

#-#####################################################################################

sub set_prefix($) { $prefix = $_[0]; }

sub default_queue($) { (split '\|', $_[0])[0] }

sub copy_printer_params($$) {
    my ($from, $to) = @_;
    map { $to->{$_} = $from->{$_} } grep { $_ ne 'configured' } keys %$from; #- avoid cycles.
}

sub getinfo($) {
    my ($prefix) = @_;
    my $printer = {};

    set_prefix($prefix);
    read_configured_queue($printer);

    add2hash($printer, {
			want         => 0,
			complete     => 0,
			str_type     => $printer::printer_type_default,
			QUEUE        => "lp",
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
		       });
    $printer;
}

#-*****************************************************************************
#- read function
#-*****************************************************************************
#------------------------------------------------------------------------------
#- Read the printer database from dbpath into memory
#------------------------------------------------------------------------------
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
}


#------------------------------------------------------------------------------
#-copy master filter to the spool dir
#------------------------------------------------------------------------------
sub copy_master_filter($) {
    my ($queue_path) = @_;
    my $complete_path = "$prefix/$queue_path/filter";
    my $master_filter = "$prefix/$PRINTER_FILTER_DIR/master-filter";

    eval { commands::cp('-f', $master_filter, $complete_path) }; #- -f for update.
    $@ and die "Can't copy $master_filter to $complete_path $!";
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
    local *PRINTCAP; open PRINTCAP, "$prefix/etc/printcap" or die "Can't open $prefix/etc/printcap file: $!";
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
}

sub configure_queue($) {
    my ($entry) = @_;
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
    } elsif ($entry->{TYPE} eq "NCP") {
	#- same for NCP printer
	my $config_file = "$prefix$queue_path/.config";
	local *F;
	open F, ">$config_file" or die "Can't create $config_file $!";
	print F "server=$entry->{NCPHOST}\n";
	print F "queue=$entry->{NCPQUEUE}\n";
	print F "user=$entry->{NCPUSER}\n";
	print F "password=$entry->{NCPPASSWD}\n";
    }

    copy_master_filter($queue_path);

    #-now the printcap file, note this one contains all the printer (use configured for that).
    local *PRINTCAP;
    open PRINTCAP, ">$prefix/etc/printcap" or die "Can't open printcap file $!";

    print PRINTCAP $intro_printcap_test;
    foreach (values %{$entry->{configured}}) {
	$_->{DBENTRY} = $thedb_gsdriver{$_->{GSDRIVER}}{ENTRY} unless defined $_->{DBENTRY};
	my $db_ = $thedb{$_->{DBENTRY}} or next; #die "no dbentry";

	$_->{SPOOLDIR} ||= "$spooldir/" . default_queue($_->{QUEUE});
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
}

sub restart_queue($) {
    my ($queue) = @_;

    #- restart lpd after cleaning the queue.
    foreach (("/var/spool/lpd/$queue/lock", "/var/spool/lpd/lpd.lock")) {
	my $pidlpd = (cat_("$prefix$_"))[0];
	kill 'TERM', $pidlpd if $pidlpd;
	unlink "$prefix$_";
    }
    require run_program;
    run_program::rooted($prefix, "lprm", "-P$queue", "-"); sleep 1;
    run_program::rooted($prefix, "lpd"); sleep 1;
}

sub print_pages($@) {
    my ($queue, @pages) = @_;

    require run_program;
    foreach (@pages) {
	run_program::rooted($prefix, "lpr", "-P$queue", $_);
    }

    sleep 5; #- allow lpr to send pages.
    local *F;
    open F, "chroot $prefix/ /usr/bin/lpq -P$queue |";
    my @lpq_output = grep { !/^no entries/ && !(/^Rank\s+Owner/ .. /^\s*$/) } <F>;
    close F;

    @lpq_output;
}

#------------------------------------------------------------------------------
#- interface function
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#- fonction de test
#------------------------------------------------------------------------------
sub test {
    $::testing = 1;
    $printer::prefix="";

    read_printer_db();

    print "the dump\n";
    print Dumper(%thedb);


    #
    #eval { printer::create_spool_dir("/tmp/titi/", ".") };
    #print $@;
    #eval { printer::copy_master_filter("/tmp/titi/", ".") };
    #print $@;
    #
    #
    #eval { printer::create_config_file("files/postscript.cfg.in", "files/postscript.cfg","./",
    #				    (
    #				     gsdevice   => "titi",
    #				     resolution => "tata",
    #				    ));
    #   };
    #print $@;
    #
    #
    #
    #printer::configure_queue(\%printer::ex_printcap_entry, "/");
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #

=head1 AUTHOR

pad.

=cut
