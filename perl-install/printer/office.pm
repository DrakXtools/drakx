package printer::office;

use strict;
use common;
use run_program;
use printer::common;
use printer::cups;

# ------------------------------------------------------------------
#   Star Offica/OpenOffice.org
# ------------------------------------------------------------------


our %suites =
    (
     'Star Office' => {
	 'make' => \&makestarofficeprinterentry,
	 'file_name' => '^(.*)/share/psprint/psprint.conf$',
	 'param' => ["Generic Printer", "Command="],
	 'perl' => "/usr/bin/perl -p -e \"s=16#80 /euro=16#80 /Euro=\" | /usr/bin/",
	 'files' => [qw(/usr/lib/*/share/xp3/Xpdefaults
		       /usr/local/lib/*/share/xp3/Xpdefaults
		       /usr/local/*/share/xp3/Xpdefaults
		       /opt/*/share/xp3/Xpdefaults)]

	 },
     'OpenOffice.Org' => {
	 'make' => \&makeopenofficeprinterentry,
	 'file_name' => '^(.*)/share/xp3/Xpdefaults$',
	 'param' => ["ports", "default_queue="],
	 'perl' => "usr/bin/perl -p -e \"s=/euro /unused=/Euro /unused=\" | /usr/bin/",
	 'files' => [qw(/usr/lib/*/share/psprint/psprint.conf
		       /usr/local/lib/*/share/psprint/psprint.conf
		       /usr/local/*/share/psprint/psprint.conf
		       /opt/*/share/psprint/psprint.conf)]
	 }
     );

sub configureoffice {
    my ($suite, $printer) = @_;
    # Do we have Star Office installed?
    my $configfilename = find_config_file($suite);
    return 1 if !$configfilename;
    $configfilename =~ m!$suites{$suite}{file_name}!;
    my $configprefix = $1;
    # Load Star Office printer config file
    my $configfilecontent = readsofficeconfigfile($configfilename);
    # Update remote CUPS queues
    if (0 && ($printer->{SPOOLER} eq "cups") && 
	((-x "$::prefix/usr/bin/curl") || (-x "$::prefix/usr/bin/wget"))) {
	my @printerlist = printer::cups::get_remote_queues();
	foreach my $listentry (@printerlist) {
	    next if !($listentry =~ /^([^\|]+)\|([^\|]+)$/);
	    my $queue = $1;
	    my $server = $2;
	    if (-x "$::prefix/usr/bin/wget") {
		eval(run_program::rooted
		     ($::prefix, "/usr/bin/wget", "-O",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$queue.ppd"));
	    } else {
		eval(run_program::rooted
		     ($::prefix, "/usr/bin/curl", "-o",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$queue.ppd"));
	    }
	    if (-r "$::prefix/etc/foomatic/$queue.ppd") {
		$configfilecontent = $suites{$suite}{make}($printer, $queue, $configprefix, $configfilecontent);
	    }
	}
    }
    # Update local printer queues
    foreach my $queue (keys(%{$printer->{configured}})) {
	# Check if we have a PPD file
	if (! -r "$::prefix/etc/foomatic/$queue.ppd") {
	    if (-r "$::prefix/etc/cups/ppd/$queue.ppd") {
		# If we have a PPD file in the CUPS config dir, link to it
		run_program::rooted($::prefix, 
				    "ln", "-sf",
				    "/etc/cups/ppd/$queue.ppd",
				    "/etc/foomatic/$queue.ppd");
	    } elsif (-r "$::prefix/usr/share/postscript/ppd/$queue.ppd") {
		# Check PPD directory of GPR, too
		run_program::rooted($::prefix, 
				    "ln", "-sf",
				    "/usr/share/postscript/ppd/$queue.ppd",
				    "/etc/foomatic/$queue.ppd");
	    } else {
		# No PPD file at all? We cannot set up this printer
		next;
	    }
	}
	$configfilecontent = 
	    $suites{$suite}{make}($printer, $queue, $configprefix, $configfilecontent);
    }
    # Patch PostScript output to print Euro symbol correctly also for
    # the "Generic Printer"
    my @parameters = $suites{$suite}{param};
    $configfilecontent = removeentry(@parameters, $configfilecontent);
    $configfilecontent = addentry($parameters[0], $parameters[1] . $suites{$suite}{perl} . $printer::data::lprcommand{$printer->{SPOOLER}{print_command}}, $configfilecontent);
    # Write back Star Office configuration file
    return writesofficeconfigfile($configfilename, $configfilecontent);
}

sub add_cups_remote_to_office {
    my ($suite, $printer, $queue) = @_;
    # Do we have Star Office installed?
    my $configfilename = find_config_file($suite);
    return 1 if !$configfilename;
    $configfilename =~ m!$suites{$suite}{file_name}!;
    my $configprefix = $1;
    # Load Star Office printer config file
    my $configfilecontent = readsofficeconfigfile($configfilename);
    # Update remote CUPS queues
    if (($printer->{SPOOLER} eq "cups") && 
	((-x "$::prefix/usr/bin/curl") || (-x "$::prefix/usr/bin/wget"))) {
	my @printerlist = printer::cups::get_remote_queues();
	foreach my $listentry (@printerlist) {
	    next if !($listentry =~ /^([^\|]+)\|([^\|]+)$/);
	    my $q = $1;
	    next if $q ne $queue;
	    my $server = $2;
	    # Remove server name from queue name
	    $q =~ s/^([^@]*)@.*$/$1/;
	    if (-x "$::prefix/usr/bin/wget") {
		eval(run_program::rooted
		     ($::prefix, "/usr/bin/wget", "-O",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$q.ppd"));
	    } else {
		eval(run_program::rooted
		     ($::prefix, "/usr/bin/curl", "-o",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$q.ppd"));
	    }
	    # Does the file exist and is it not an error message?
	    if ((-r "$::prefix/etc/foomatic/$queue.ppd") &&
		(cat_("$::prefix/etc/foomatic/$queue.ppd") =~ 
		 /^\*PPD-Adobe/)) {
		$configfilecontent = 
		    $suites{$suite}{make}($printer, $queue,
					       $configprefix,
					       $configfilecontent);
	    } else {
		unlink "$::prefix/etc/foomatic/$queue.ppd";
		return 0;
	    }
	    last if $suite eq 'Star Office';
	}
    }
    # Write back Star Office configuration file
    return writesofficeconfigfile($configfilename, $configfilecontent);
}

sub remove_printer_from_office {
    my ($suite, $printer, $queue) = @_;
    # Do we have Star Office installed?
    my $configfilename = find_config_file($suite);
    return 1 if !$configfilename;
    $configfilename =~ m!$suites{$suite}{file_name}!;
    my $configprefix = $1;
    # Load Star Office printer config file
    my $configfilecontent = readsofficeconfigfile($configfilename);
    # Remove the printer entry
    $configfilecontent = 
	removestarofficeprinterentry($printer, $queue, $configprefix,
				     $configfilecontent);
    # Write back Star Office configuration file
    return writesofficeconfigfile($configfilename, $configfilecontent);
}

sub remove_local_printers_from_office {
    my ($suite, $printer) = @_;
    # Do we have Star Office installed?
    my $configfilename = find_config_file($suite);
    return 1 if !$configfilename;
    $configfilename =~ m!$suites{$suite}{file_name}!;
    my $configprefix = $1;
    # Load Star Office printer config file
    my $configfilecontent = readsofficeconfigfile($configfilename);
    # Remove the printer entries
    foreach my $queue (keys(%{$printer->{configured}})) {
	$configfilecontent = 
	    removestarofficeprinterentry($printer, $queue, $configprefix, $configfilecontent);
    }
    # Write back Star Office configuration file
    return writesofficeconfigfile($configfilename, $configfilecontent);
}


sub makestarofficeprinterentry {
    my ($printer, $queue, $configprefix, $configfile) = @_;
    # Set default printer
    if ($queue eq $printer->{DEFAULT}) {
	$configfile = removeentry("windows", "device=", $configfile);
	$configfile = addentry("windows", 
			       "device=$queue,$queue PostScript,$queue",
			       $configfile);
    }
    # Make an entry in the "[devices]" section
    $configfile = removeentry("devices", "$queue=", $configfile);
    $configfile = addentry("devices", 
			   "$queue=$queue PostScript,$queue",
			   $configfile);
    # Make an entry in the "[ports]" section
    # The "perl" command patches the PostScript output to print the Euro
    # symbol correctly.
    $configfile = removeentry("ports", "$queue=", $configfile);
    $configfile = addentry("ports", 
			   "$queue=/usr/bin/perl -p -e \"s=16#80 /euro=16#80 /Euro=\" | /usr/bin/$printer::data::lprcommand{$printer->{SPOOLER}{print_command}} -P $queue",
			   $configfile);
    # Make printer's section
    $configfile = addsection("$queue,PostScript,$queue", $configfile);
    # Load PPD file
    my $ppd = cat_("$::prefix/etc/foomatic/$queue.ppd");
    # Set the PostScript level
    my $pslevel;
    if ($ppd =~ /^\s*\*LanguageLevel:\s*\"?([^\s\"]+)\"?\s*$/m) {
	$pslevel = $1;
	$pslevel = "2" if $pslevel eq "3";
    } else { $pslevel = "2" }
    $configfile = removeentry("$queue.PostScript.$queue",
			      "Level=", $configfile);
    $configfile = addentry("$queue.PostScript.$queue", 
			   "Level=$pslevel", $configfile);
    # Set Color/BW
    my $color = ($ppd =~ /^\s*\*ColorDevice:\s*\"?([Tt]rue)\"?\s*$/m) ? "1" : "0";
    $configfile = removeentry("$queue.PostScript.$queue", "BitmapColor=", $configfile);
    $configfile = addentry("$queue.PostScript.$queue", "BitmapColor=$color", $configfile);
    # Set the default paper size
    if ($ppd =~ /^\s*\*DefaultPageSize:\s*(\S+)\s*$/m) {
	my $papersize = $1;
	$configfile = removeentry("$queue.PostScript.$queue", "PageSize=", $configfile);
	$configfile = removeentry("$queue.PostScript.$queue", "PPD_PageSize=", $configfile);
	$configfile = addentry("$queue.PostScript.$queue", "PageSize=$papersize", $configfile);
	$configfile = addentry("$queue.PostScript.$queue", "PPD_PageSize=$papersize", $configfile);
    }
    # Link the PPD file
    run_program::rooted($::prefix, 
			"ln", "-sf", "/etc/foomatic/$queue.ppd", 
			"$configprefix/share/xp3/ppds/$queue.PS");
    return $configfile;
}

sub makeopenofficeprinterentry {
    my ($printer, $queue, $configprefix, $configfile) = @_;
    # Make printer's section
    $configfile = addsection($queue, $configfile);
    # Load PPD file
    my $ppd = cat_("$::prefix/etc/foomatic/$queue.ppd");
    # "PPD_PageSize" line
    if ($ppd =~ /^\s*\*DefaultPageSize:\s*(\S+)\s*$/m) {
	my $papersize = $1;
	$configfile = removeentry($queue,
				  "PPD_PageSize=", $configfile);
	$configfile = addentry($queue, 
			       "PPD_PageSize=$papersize", $configfile);
    }
    # "Command" line
    # The "perl" command patches the PostScript output to print the Euro
    # symbol correctly.
    $configfile = removeentry($queue, "Command=", $configfile);
    $configfile = addentry($queue, 
			   "Command=/usr/bin/perl -p -e \"s=/euro /unused=/Euro /unused=\" | /usr/bin/$printer::data::lprcommand{$printer->{SPOOLER}{print_command}} -P $queue",
			   $configfile);
    # "Comment" line 
    $configfile = removeentry($queue, "Comment=", $configfile);
    if (($printer->{configured}{$queue}) &&
	($printer->{configured}{$queue}{queuedata}{desc})) {
	$configfile = addentry
	    ($queue, 
	     "Comment=$printer->{configured}{$queue}{queuedata}{desc}",
	     $configfile);
    } else {
	$configfile = addentry($queue, 
			       "Comment=",
			       $configfile);
    }
    # "Location" line 
    $configfile = removeentry($queue, "Location=", $configfile);
    if (($printer->{configured}{$queue}) &&
	($printer->{configured}{$queue}{queuedata}{loc})) {
	$configfile = addentry
	    ($queue, 
	     "Location=$printer->{configured}{$queue}{queuedata}{loc}",
	     $configfile);
    } else {
	$configfile = addentry($queue, "Location=", $configfile);
    }
    # "DefaultPrinter" line
    $configfile = removeentry($queue, "DefaultPrinter=", $configfile);
    my $default = "0";
    if ($queue eq $printer->{DEFAULT}) {
	$default = "1";
	# "DefaultPrinter=0" for the "Generic Printer"
	$configfile = removeentry("Generic Printer", "DefaultPrinter=",
				  $configfile);
	$configfile = addentry("Generic Printer", 
			       "DefaultPrinter=0",
			       $configfile);	
    }
    $configfile = addentry($queue, "DefaultPrinter=$default", $configfile);
    # "Printer" line 
    $configfile = removeentry($queue, "Printer=", $configfile);
    $configfile = addentry($queue, "Printer=$queue/$queue", $configfile);
    # Link the PPD file
    run_program::rooted($::prefix, 
			"ln", "-sf", "/etc/foomatic/$queue.ppd", 
			"$configprefix/share/psprint/driver/$queue.PS");
    return $configfile;
}

sub removestarofficeprinterentry {
    my ($printer, $queue, $configprefix, $configfile) = @_;
    # Remove default printer entry
    $configfile = removeentry("windows", "device=$queue,", $configfile);
    # Remove entry in the "[devices]" section
    $configfile = removeentry("devices", "$queue=", $configfile);
    # Remove entry in the "[ports]" section
    $configfile = removeentry("ports", "$queue=", $configfile);
    # Remove "[$queue,PostScript,$queue]" section
    $configfile = removesection("$queue,PostScript,$queue", $configfile);
    # Remove Link of PPD file
    run_program::rooted($::prefix, 
			"rm", "-f", 
			"$configprefix/share/xp3/ppds/$queue.PS");
    return $configfile;
}

sub removeopenofficeprinterentry {
    my ($printer, $queue, $configprefix, $configfile) = @_;
    # Remove printer's section
    $configfile = removesection($queue, $configfile);
    # Remove Link of PPD file
    run_program::rooted($::prefix, 
			"rm", "-f", 
			"$configprefix/share/psprint/driver/$queue.PS");
    return $configfile;
}

sub find_config_file {
    my ($suite) = @_;
    my $configfilenames = $suites{$suite}{files};
    foreach my $configfilename (@$configfilenames) {
	local *F;
	if (open F, "ls -r $::prefix$configfilename 2> /dev/null |") {
	    my $filename = <F>;
	    close F;
	    if ($filename) {
		if ($::prefix ne "") {
		    $filename =~ s/^$::prefix//;
		}
		# Work around a bug in the "ls" of "busybox". During
		# installation it outputs the mask given on the command line
		# instead of nothing when the mask does not match any file
		next if $filename =~ /\*/;
		return $filename;
	    }
	}
    }
    return "";
}

sub readsofficeconfigfile {
    my ($file) = @_;
    local *F; 
    open F, "< $::prefix$file" or return "";
    my $filecontent = join("", <F>);
    close F;
    return $filecontent;
}

sub writesofficeconfigfile {
    my ($file, $filecontent) = @_;
    local *F; 
    open F, "> $::prefix$file" or return 0;
    print F $filecontent;
    close F;
    return 1;
}

