package printer::gimp;

use strict;
use run_program;
use common;
use printer::common;
use printer::data;
use printer::cups;

# ------------------------------------------------------------------
#   GIMP-print related stuff
# ------------------------------------------------------------------

sub configure {
    my ($printer) = @_;
    # Do we have files to treat?
    my @configfilenames = findconfigfiles();
    return 1 if $#configfilenames < 0;
    # There is no system-wide config file, treat every user's config file
    foreach my $configfilename (@configfilenames) {
	# Load GIMP's printer config file
	my $configfilecontent = readconfigfile($configfilename);
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
		    run_program::rooted(
			 $::prefix, 
			 "ln", "-sf",
			 "/usr/share/postscript/ppd/$queue.ppd",
			 "/etc/foomatic/$queue.ppd");
		} else {
		    # No PPD file at all? We cannot set up this printer
		    next;
		}
	    }
	    # Add the printer entry
	    if (!isprinterconfigured($queue, $configfilecontent)) {
		# Remove the old printer entry
		$configfilecontent = 
		    removeprinter($queue, $configfilecontent);
		# Add the new printer entry
		$configfilecontent = 
		    makeprinterentry($printer, $queue,
					 $configfilecontent);
	    }
	}
	# Default printer
	if ($printer->{DEFAULT}) {
	    if ($configfilecontent !~ /^\s*Current\-Printer\s*:/m) {
		$configfilecontent =~
		    s/\n/\nCurrent-Printer: $printer->{DEFAULT}\n/s;
	    } else {
		$configfilecontent =~ /^\s*Current\-Printer\s*:\s*(\S+)\s*$/m;
		if (!isprinterconfigured($1, $configfilecontent)) {
		    $configfilecontent =~
			s/(Current\-Printer\s*:\s*)\S+/$1$printer->{DEFAULT}/;
		}
	    }
	}
	# Write back GIMP's printer configuration file
	writeconfigfile($configfilename, $configfilecontent);
    }
    return 1;
}

sub addcupsremoteto {
    my ($printer, $queue) = @_;
    # Do we have files to treat?
    my @configfilenames = findconfigfiles();
    return 1 if $#configfilenames < 0;
    my @printerlist = printer::cups::get_remote_queues();
    my $ppdfile = "";
    if ($printer->{SPOOLER} eq "cups" && 
	(-x "$::prefix/usr/bin/curl" || -x "$::prefix/usr/bin/wget")) {
	foreach my $listentry (@printerlist) {
	    next if !($listentry =~ /^([^\|]+)\|([^\|]+)$/);
	    my $q = $1;
	    next if $q ne $queue;
	    my $server = $2;
	    # Remove server name from queue name
	    $q =~ s/^([^@]*)@.*$/$1/;
	    if (-x "$::prefix/usr/bin/wget") {
		eval(run_program::rooted(
		      $::prefix, "/usr/bin/wget", "-O",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$q.ppd"));
	    } else {
		eval(run_program::rooted(
		      $::prefix, "/usr/bin/curl", "-o",
		      "/etc/foomatic/$queue.ppd",
		      "http://$server:631/printers/$q.ppd"));
	    }
	    # Does the file exist and is it not an error message?
	    if (-r "$::prefix/etc/foomatic/$queue.ppd" &&
		cat_("$::prefix/etc/foomatic/$queue.ppd") =~ /^\*PPD-Adobe/) {
		$ppdfile = "/etc/foomatic/$queue.ppd";
	    } else {
		unlink "$::prefix/etc/foomatic/$queue.ppd";
		return 0;
	    }
	}
    } else { return 1 }
    # There is no system-wide config file, treat every user's config file
    foreach my $configfilename (@configfilenames) {
	# Load GIMP's printer config file
	my $configfilecontent = readconfigfile($configfilename);
	# Add the printer entry
	if (!isprinterconfigured($queue, $configfilecontent)) {
	    # Remove the old printer entry
	    $configfilecontent = removeprinter($queue, $configfilecontent);
	    # Add the new printer entry
	    $configfilecontent = makeprinterentry($printer, $queue, $configfilecontent);
	}
	# Write back GIMP's printer configuration file
	writeconfigfile($configfilename, $configfilecontent);
    }
    return 1;
}

sub removeprinterfrom {
    my ($_printer, $queue) = @_;
    # Do we have files to treat?
    my @configfilenames = findconfigfiles();
    return 1 if $#configfilenames < 0;
    # There is no system-wide config file, treat every user's config file
    foreach my $configfilename (@configfilenames) {
	# Load GIMP's printer config file
	my $configfilecontent = readconfigfile($configfilename);
	# Remove the printer entry
	$configfilecontent = removeprinter($queue, $configfilecontent);
	# Write back GIMP's printer configuration file
	writeconfigfile($configfilename, $configfilecontent);
    }
    return 1;
}

sub removelocalprintersfrom {
    my ($printer) = @_;
    # Do we have files to treat?
    my @configfilenames = findconfigfiles();
    return 1 if $#configfilenames < 0;
    # There is no system-wide config file, treat every user's config file
    foreach my $configfilename (@configfilenames) {
	# Load GIMP's printer config file
	my $configfilecontent = readconfigfile($configfilename);
	# Remove the printer entries
	foreach my $queue (keys(%{$printer->{configured}})) {
	    $configfilecontent = removeprinter($queue, $configfilecontent);
	}
	# Write back GIMP's printer configuration file
	writeconfigfile($configfilename, $configfilecontent);
    }
    return 1;
}

sub makeprinterentry {
    my ($printer, $queue, $configfile) = @_;
    # Make printer's section
    $configfile = addprinter($queue, $configfile);
    # Load PPD file
    my $ppd = cat_("$::prefix/etc/foomatic/$queue.ppd");
    # Is the printer configured with GIMP-Print?
    my $gimpprintqueue = 0;
    my $gimpprintdriver = "ps2";
    if ($ppd =~ /CUPS\s*\+\s*GIMP\s*\-\s*Print/im) {
	# Native CUPS driver
	$gimpprintqueue = 1;
	$ppd =~ /\s*\*ModelName:\s*\"(\S+)\"\s*$/im;
	$gimpprintdriver = $1;
    } elsif ($ppd =~ /Foomatic\s*\+\s*gimp\s*\-\s*print/im) {
	# GhostScript + Foomatic driver
	$gimpprintqueue = 1;
	$ppd =~
	    /'idx'\s*=>\s*'ev\/gimp-print-((escp2|pcl|bjc|lexmark)\-\S*)'/im;
	$gimpprintdriver = $1;
    }
    if ($gimpprintqueue) {
	# Get the paper size from the PPD file
	if ($ppd =~ /^\s*\*DefaultPageSize:\s*(\S+)\s*$/m) {
	    my $papersize = $1;
	    $configfile = removeentry($queue,
					  "Media-Size", $configfile);
	    $configfile = addentry($queue, 
				       "Media-Size: $papersize", $configfile);
	}
	$configfile = removeentry($queue, "PPD-File:", $configfile);
	$configfile = addentry($queue, "PPD-File:", $configfile);
	$configfile = removeentry($queue, "Driver:", $configfile);
	$configfile = addentry($queue, "Driver: $gimpprintdriver", $configfile);
	$configfile = removeentry($queue, "Destination:", $configfile);
	$configfile = addentry($queue, 
				   sprintf("Destination: /usr/bin/%s -P %s -o raw", $spoolers{$printer->{SPOOLER}{print_command}}, $queue), $configfile);
    } else {
	$configfile = removeentry($queue, "PPD-File:", $configfile);
	$configfile = addentry($queue, "PPD-File: /etc/foomatic/$queue.ppd", $configfile);
	$configfile = removeentry($queue, "Driver:", $configfile);
	$configfile = addentry($queue, "Driver: ps2", $configfile);
	$configfile = removeentry($queue, "Destination:", $configfile);
	$configfile = addentry($queue, 
				   sprintf("Destination: /usr/bin/%s -P %s", $spoolers{$printer->{SPOOLER}{print_command}}, $queue), $configfile);
    }
    return $configfile;
}

sub findconfigfiles {
    my @configfilenames;
    push @configfilenames, ".gimp-1.2/printrc" if -d "$::prefix/usr/lib/gimp/1.2";
    push @configfilenames, ".gimp-1.3/printrc" if -d "$::prefix/usr/lib/gimp/1.3";
    my @filestotreat;
    local *PASSWD;
    open PASSWD, "< $::prefix/etc/passwd" or die "Cannot read /etc/passwd!\n";
    local $_;
    while (<PASSWD>) {
	chomp;
	if (/^([^:]+):[^:]*:([^:]+):([^:]+):[^:]*:([^:]+):[^:]*$/) {
	    my ($username, $uid, $gid, $homedir) = ($1, $2, $3, $4);
	    if (($uid == 0 || $uid >= 500) && $username ne "nobody") {
		foreach my $file (@configfilenames) {
		    my $dir = "$homedir/$file";
		    $dir =~ s,/[^/]*$,,;
		    next if -f $dir && ! -d $dir;
		    if (! -d "$::prefix$dir") {
			eval { mkdir_p("$::prefix$dir") } or next;
               run_program::rooted($::prefix, "/bin/chown", "$uid.$gid", $dir) or next;
		    }
		    if (! -f "$::prefix$homedir/$file") {
			eval { output("$::prefix$homedir/$file", "#PRINTRCv1 written by GIMP-PRINT 4.2.2 - 13 Sep 2002\n") } or next;
               run_program::rooted($::prefix, "/bin/chown", "$uid.$gid", "$homedir/$file") or next;
		    }
		    push @filestotreat, "$homedir/$file";
		}
	    }
	}
    }
    @filestotreat;
}

sub readconfigfile {
    my ($file) = @_;
    local *F; 
    open F, "< $::prefix$file" or return "";
    my $filecontent = join("", <F>);
    close F;
    return $filecontent;
}

sub writeconfigfile {
    my ($file, $filecontent) = @_;
    local *F; 
    open F, "> $::prefix$file" or return 0;
    print F $filecontent;
    close F;
    return 1;
}

sub addentry {
    my ($section, $entry, $filecontent) = @_;
    my $sectionfound = 0;
    my $entryinserted = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	if (!$sectionfound) {
	    $sectionfound = 1 if /^\s*Printer\s*:\s*($section)\s*$/;
	} else {
	    if (!/^\s*$/ && !/^\s*;/) { #-#
		$_ = "$entry\n$_";
		$entryinserted = 1;
		last;
	    }
	}
    }
    push(@lines, $entry) if $sectionfound && !$entryinserted;
    return join("\n", @lines);
}

sub addprinter {
    my ($section, $filecontent) = @_;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
     # section already there, nothing to be done
     return $filecontent if /^\s*Printer\s*:\s*($section)\s*$/;
    }
    return $filecontent . "\nPrinter: $section";
}

sub removeentry {
    my ($section, $entry, $filecontent) = @_;
    my $sectionfound = 0;
    my $done = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	$_ = "$_\n";
	next if $done;
	if (!$sectionfound) {
	    if (/^\s*Printer\s*:\s*($section)\s*$/) {
		$sectionfound = 1;
	    }
	} else {
	    if (/^\s*Printer\s*:\s*.*\s*$/) { # Next section
		$done = 1;
	    } elsif (/^\s*$entry/) {
		$_ = "";
		$done = 1;
	    }
	}
    }
    return join "", @lines;
}

sub removeprinter {
    my ($section, $filecontent) = @_;
    my $sectionfound = 0;
    my $done = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	$_ = "$_\n";
	next if $done;
	if (!$sectionfound) {
	    if (/^\s*Printer\s*:\s*($section)\s*$/) {
		$_ = "";
		$sectionfound = 1;
	    }
	} else {
	    if (/^\s*Printer\s*:\s*.*\s*$/) { # Next section
		$done = 1;
	    } else {
		$_ = "";
	    }
	}
    }
    return join "", @lines;
}

sub isprinterconfigured {
    my ($queue, $filecontent) = @_;
    my $sectionfound = 0;
    my $done = 0;
    my $drivernotps2 = 0;
    my $ppdfileset = 0;
    my $nonrawprinting = 0;
    my @lines = split("\n", $filecontent);
    foreach (@lines) {
	last if $done;
	if (!$sectionfound) {
	    if (/^\s*Printer\s*:\s*($queue)\s*$/) {
		$sectionfound = 1;
	    }
	} else {
	    if (/^\s*Printer\s*:\s*.*\s*$/) { # Next section
		$done = 1;
	    } elsif (/^\s*Driver:\s*(\S+)\s*$/) {
		$drivernotps2 = $1 ne "ps2";
	    } elsif (/^\s*PPD\-File:\s*(\S+)\s*$/) {
		$ppdfileset = 1;
	    } elsif (my ($dest) = /^\s*Destination:\s*(\S+.*)$/) {
		$nonrawprinting = $dest !~ /\-o\s*raw/;
	    } 
	}
    }
    return 0 if $done && !$sectionfound;
    return 1 if $ppdfileset || $drivernotps2 || $nonrawprinting;
    return 0;
}


# ------------------------------------------------------------------

1;
