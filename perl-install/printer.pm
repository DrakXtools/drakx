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
use vars qw(%thedb %printer_type %printer_type_inv @papersize_type %fields $spooldir @entries_db_short @entry_db_description %descr_to_db %db_to_descr);
#-#####################################################################################

=head2 Imports

=cut

#-#####################################################################################
use Data::Dumper;

#-#####################################################################################

=head2 pixel imports

=cut

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

#-if we are in an panoramix config
my $prefix = "";

#-location of the printer database in an installed system
my $PRINTER_DB_FILE    = "/usr/lib/rhs/rhs-printfilters/printerdb";
my $PRINTER_FILTER_DIR = "/usr/lib/rhs/rhs-printfilters";




#-#####################################################################################

=head2 Exported constant

=cut

#-#####################################################################################

%printer_type = (
    "local"             => "LOCAL",
    "Remote lpd"        => "REMOTE",
    "SMB/Windows 95/NT" => "SMB",
    "NetWare"           => "NCP",   
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
$spooldir       = "/var/spool/lpd";

#-#####################################################################################

=head2 Functions

=cut

#-#####################################################################################

sub set_prefix($) {
    ($prefix) = @_;
}
#-*****************************************************************************
#- read function
#-*****************************************************************************
#------------------------------------------------------------------------------
#- Read the printer database from dbpath into memory
#------------------------------------------------------------------------------
sub read_printer_db(;$) {
    my ($dbpath) = @_;
    
    $dbpath = $prefix . ($dbpath || $PRINTER_DB_FILE);

    %thedb and return;

    local *DBPATH;		#-don't have to do close
    open DBPATH, "<$dbpath" or die "An error has occurred on $dbpath : $!";
      
    while (<DBPATH>) {
	if (/^StartEntry:\s(\w*)/) {
	    my $entryname = $1;
	    my $entry = {};
	      
	    $entry->{ENTRY} = $entryname;
	      
	  WHILE : 
	      while (<DBPATH>) {
		SWITCH: {
		      /GSDriver:\s*(\w*)/      and do { $entry->{GSDRIVER} = $1; last SWITCH };
		      /Description:\s*{(.*)}/  and do { $entry->{DESCR}    = $1; last SWITCH };
		      /About:\s*{(.*)}/        and do { $entry->{ABOUT}    = $1; last SWITCH };
		      /About:\s*{(.*)/ 
			and do 
			  {
			      my $string = "$1\n";
			      while (<DBPATH>) {
				  /(.*)}/ and do { $entry->{ABOUT} = $string; last SWITCH };
				  $string .= $_;
			      }
			  };
		      /Resolution:\s*{(.*)}\s*{(.*)}\s*{(.*)}/ 
			and do { push @{$entry->{RESOLUTION}}, { XDPI => $1, YDPI => $2, DESCR => $3 }; last SWITCH };
		      /BitsPerPixel:\s*{(.*)}\s*{(.*)}/ 
			and do { push @{$entry->{BITSPERPIXEL}}, {DEPTH => $1, DESCR => $2}; last SWITCH };

		      /EndEntry/ and last WHILE;
		  }
	      }
	    $thedb{$entryname} = $entry;
	}
    }
    
    @entries_db_short     = sort keys %printer::thedb;
    @entry_db_description = map { $printer::thedb{$_}{DESCR} } @entries_db_short;
    %descr_to_db          = map { $printer::thedb{$_}{DESCR}, $_ } @entries_db_short;
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
    
    unless (-d $complete_path) {
	mkdir "$complete_path", 0755
	  or die "An error has occurred - can't create $complete_path : $!";
    }
	
    #-redhat want that "drwxr-xr-x root lp"
    my $gid_lp = (getpwnam("lp"))[3];
    chown 0, $gid_lp, $complete_path 
      or die "An error has occurred - can't chgrp $complete_path to lp $!";
}

#------------------------------------------------------------------------------
#-given the input spec file 'input', and the target output file 'output'
#-we set the fields specified by fieldname to the values in fieldval    
#-nval  is the number of fields to set                                  
#-Doesnt currently catch error exec'ing sed yet                         
#------------------------------------------------------------------------------
sub create_config_file($$%) {
    my ($inputfile, $outpufile, %toreplace) = @_;
    my ($in, $out) = ("$prefix/$inputfile", "$prefix/$outpufile");
    local *OUT;
    local *IN;
    
    #-TODO my $oldmask = umask 0755;

    open IN , "<$in"  or die "Can't open $in $!";
    if ($::testing) {
	*OUT = *STDOUT
    } else {
	open OUT, ">$out" or die "Can't open $out $!";
    }
    
    while (<IN>) {
	if (/@@@(.*)@@@/) {
	    my $r = $toreplace{$1};
	    s/@@@(.*)@@@/$r/g;
	}
	print OUT;
    }
}


#------------------------------------------------------------------------------
#-copy master filter to the spool dir
#------------------------------------------------------------------------------
sub copy_master_filter($) {
    my ($queue_path) = @_;
    my $complete_path = "$prefix/$queue_path/filter";
    my $master_filter = "$prefix/$PRINTER_FILTER_DIR/master-filter";

    eval { commands::cp($master_filter, $complete_path) };
    $@ and die "Can't copy $master_filter to $complete_path $!";
}

#------------------------------------------------------------------------------
#- given a PrintCap Entry, create the spool dir and special 
#- rhs-printfilters related config files which are required
#------------------------------------------------------------------------------
my $intro_printcap_test="
#
# Please don't edit this file directly unless you know what you are doing!
# Look at the printcap(5) man page for more info.
# Be warned that the control-panel printtool requires a very strict format!
# Look at the printcap(5) man page for more info.
#
# This file can be edited with the printtool in the control-panel.
#

";


sub configure_queue($) {
    my ($entry) = @_;

    $entry->{SPOOLDIR} ||= "$spooldir";
    $entry->{IF}       ||= "$spooldir/$entry->{QUEUE}/filter";
    $entry->{AF}       ||= "$spooldir/$entry->{QUEUE}/acct";
    
    my $queue_path      = "$entry->{SPOOLDIR}";
    create_spool_dir($queue_path);

    my $get_name_file = sub { 
	my ($name) = @_; 
	("$PRINTER_FILTER_DIR/$name.in", "$entry->{SPOOLDIR}/$name")
    };
    my ($filein, $file);
    my %fieldname = ();
    my $dbentry = $thedb{($entry->{DBENTRY})} or die "no dbentry";


    ($filein, $file) = &$get_name_file("general.cfg");
    $fieldname{ascps_trans} = ($dbentry->{GSDRIVER} eq "POSTSCRIPT") ? "NO" : "YES";
    $fieldname{desiredto}   = ($entry->{GSDRIVER} eq "TEXT") ? "ps" : "asc";
    $fieldname{papersize}   = $entry->{PAPERSIZES} ? $entry->{PAPERSIZES} : "letter";
    $fieldname{printertype} = $entry->{TYPE};
    create_config_file($filein, $file, %fieldname);

    #- successfully created general.cfg, now do postscript.cfg 
    ($filein, $file) = &$get_name_file("postscript.cfg");
    %fieldname = ();
    $fieldname{gsdevice}       = $dbentry->{GSDRIVER};
    $fieldname{papersize}      = $entry->{PAPERSIZES} ? $entry->{PAPERSIZES} : "letter";
    $fieldname{resolution}     = ($entry->{RESOLUTION} eq "Default") ? "Default" : "";
    $fieldname{color}          = 
      do {
	  if ($dbentry->{GSDRIVER} eq "uniprint") {
	      ($entry->{BITSPERPIXEL} eq "Default") ? "-dBitsPerPixel=Default" : "";
	  } else {
	      $entry->{BITSPERPIXEL};
	  }
      };
    $fieldname{reversepages}   = "NO";
    $fieldname{extragsoptions} = "";
    $fieldname{pssendeof}      = ($dbentry->{GSDRIVER} eq "POSTSCRIPT") ? "NO" : "YES";
    $fieldname{nup}            = "1";
    $fieldname{rtlftmar}       = "18";
    $fieldname{topbotmar}      = "18";
    create_config_file($filein, $file, %fieldname);
	
    #- finally, make textonly.cfg
    ($filein, $file) = &$get_name_file("textonly.cfg");
    %fieldname = ();
    $fieldname{textonlyoptions} = "";
    $fieldname{crlftrans}       = $entry->{CRLF} ? "YES" : "";
    $fieldname{textsendeof}     = "1";
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

    #-now the printcap file
    local *PRINTCAP;
    if ($::testing) {
	*PRINTCAP = *STDOUT;
    } else {
	open PRINTCAP, ">$prefix/etc/printcap" or die "Can't open printcap file $!";
    }
    
    print PRINTCAP $intro_printcap_test;
    printf PRINTCAP "##PRINTTOOL3##  %s %s %s %s %s %s %s \n",
      $entry->{TYPE},
	$dbentry->{GSDRIVER},
	  $entry->{RESOLUTION},
	    $entry->{PAPERSIZE},
	      "{}",
		$dbentry->{ENTRY},
		  $entry->{BITSPERPIXEL},
		    $entry->{CRLF} ? "1" : "";

	
    print PRINTCAP "$entry->{QUEUE}:\\\n";
    print PRINTCAP "\t:sd=$entry->{SPOOLDIR}:\\\n";
    print PRINTCAP "\t:mx#0:\\\n\t:sh:\\\n";
	   
    if ($entry->{TYPE} eq "LOCAL") {
	print PRINTCAP "\t:lp=$entry->{DEVICE}:\\\n";
    } elsif ($entry->{TYPE} eq "REMOTE") { 
	print PRINTCAP "\t:rm=$entry->{REMOTEHOST}:\\\n";
	print PRINTCAP "\t:rp=$entry->{REMOTEQUEUE}:\\\n";
    } else {
	#- (pcentry->Type == (PRINTER_SMB | PRINTER_NCP))
	print PRINTCAP "\t:lp=/dev/null:\\\n";
	print PRINTCAP "\t:af=$entry->{SPOOLDIR}/acct\\\n";
    }

    #- cheating to get the input filter!
    print PRINTCAP "\t:if=$entry->{SPOOLDIR}/filter:\n";
	
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
