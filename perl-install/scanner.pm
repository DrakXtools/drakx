package scanner;
# scanner.pm $Id$
# Yves Duret <yduret at mandrakesoft.com>
# Copyright (C) 2001-2002 MandrakeSoft
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
# pbs/TODO:
# - scsi mis-configuration (should work better now)
# - devfs use dev_is_devfs()
# - with 2 scanners same manufacturer -> will overwrite previous conf -> only 1 conf !! (should work now)
# - lp: see printerdrake
# - install: prefix --> done (partially)

use standalone;
use common;
use detect_devices;
use log;
use handle_configs;

my $_sanedir = "$::prefix/etc/sane.d";
my $_scannerDBdir = "$::prefix$ENV{SHARE_PATH}/ldetect-lst";
$scannerDB = readScannerDB("$_scannerDBdir/ScannerDB");

sub confScanner {
    my ($model, $port, $vendor, $product) = @_;
    $port ||= detect_devices::dev_is_devfs() ? "$::prefix/dev/usb/scanner0" : "$::prefix/dev/scanner";
    my $a = $scannerDB->{$model}{server};
    #print "file:[$a]\t[$model]\t[$port]\n| ", (join "\n| ", @{$scannerDB->{$model}{lines}}),"\n";
    my @driverconf = cat_("$_sanedir/$a.conf");
    my @configlines = @{$scannerDB->{$model}{lines}};
    foreach my $line (@configlines) {
	$line =~ s/\$DEVICE/$port/g if $port;
	next if $line =~ /\$DEVICE/;
	$line =~ s/\$VENDOR/$vendor/g if $vendor;
	next if $line =~ /\$VENDOR/;
	$line =~ s/\$PRODUCT/$product/g if $product;
	next if $line =~ /\$PRODUCT/;
	$line =~ /^(\S+)LINE\s+(.*?)$/;
	my $linetype = $1;
	$line = $2;
	if ((!$linetype) or
	    (($linetype eq "USB") and (($port =~ /usb/i) or ($vendor))) or
	    (($linetype eq "PARPORT") and (!$vendor) and 
	     ($port =~ /(parport|pt_drv|parallel)/i)) or
	    (($linetype eq "SCSI") and (!$vendor) and
	     ($port =~ m!(/sg|scsi|/scanner)!i))) {
	    handle_configs::set_directive(\@driverconf, $line, 1);
	}
    }
    output("$_sanedir/$a.conf", @driverconf);
    add2dll($a);
}

sub add2dll {
    return if member($_[0], chomp_(cat_("$_sanedir/dll.conf")));
    my @dllconf = cat_("$_sanedir/dll.conf");
    handle_configs::add_directive(\@dllconf, $_[0]);
    output("$_sanedir/dll.conf", @dllconf);
}

sub configured {
    my @res = ();
    # Run "scanimage -L", to find the scanners which are already working
    open LIST, "LC_ALL=C scanimage -L |";
    while (my $line = <LIST>) {
	if ($line =~ /^\s*device\s*\`([^\`\']+)\'\s+is\s+a\s+(\S.*)$/) {
	    # Extract port and description
	    my $port = $1;
	    my $description = $2;
	    # Remove duplicate scanners appearing through saned and the
	    # "net" backend
	    next if $port =~ /^net:(localhost|127.0.0.1):/;
	    # Store collected data
	    push @res, { 
		port => $port, 
		val => { 
		    DESCRIPTION => $description,
		} 
	    };
	}
    }
    close LIST;
    return @res;
}

sub detect {
    my @configured = @_;
    my @res = ();
    # Run "sane-find-scanner", this also detects USB scanners which only
    # work with libusb.
    open DETECT, "LC_ALL=C sane-find-scanner -q |";
    while (my $line = <DETECT>) {
	my $vendorid = undef;
	my $productid = undef;
	my $make = undef;
	my $model = undef;
	my $description = undef;
	my $port = undef;
	if ($line =~ /^\s*found\s+USB\s+scanner/i) {
	    # Found an USB scanner
	    if ($line =~ /vendor=(0x[0-9a-f]+)[^0-9a-f\[]+[^\[]*\[([^\[\]]+)\].*prod(|uct)=(0x[0-9a-f]+)[^0-9a-f\[]+[^\[]*\[([^\[\]]+)\]/) {
		# Scanner connected via libusb
		$vendorid = $1;
		$make = $2;
		$productid = $4;
		$model = $5;
		$description = "$make|$model";
	    } elsif ($line =~ /vendor=(0x[0-9a-f]+)[^0-9a-f]+.*prod(|uct)=(0x[0-9a-f]+)[^0-9a-f]+/) {
		# Scanner connected via scanner.o kernel module
		$vendorid = $1;
		$productid = $3;
	    }
	    if ($vendorid and $productid) {
		# We have vendor and product ID, look up the scanner in
		# the usbtable
		foreach my $entry (cat_("$_scannerDBdir/usbtable")) {
		    if ($entry =~ 
			/^\s*$vendorid\s+$productid\s+.*\"([^\"]+)\"\s*$/) {
			$description = $1;
			$description =~ s/Seiko\s+Epson/Epson/i;
			if ($description =~ /^([^\|]+)\|(.*)$/) {
			    $make = $1;
			    $model = $2;
			}
			last;
		    }
		}
	    }
	} elsif ($line =~ /^\s*found\s+SCSI/i) {
	    # SCSI scanner
	    if ($line =~ /\"([^\"\s]+)\s+([^\"]+?)\s+([^\"\s]+)\"/) {
		$make = $1;
		$model = $2;
		$description = "$make|$model";
	    }
	} else {
	    # Comment line in output of "sane-find-scanner"
	    next;
	}
	# Extract port
        $line =~ /\s+(\S+)\s*$/;
	$port = $1;
	# Check for duplicate (scanner.o/libusb)
	if ($port =~ /^libusb/) {
	    my $duplicate = 0;
	    foreach (@res) {
		if (($_->{val}{vendor} eq $vendorid) &&
		    ($_->{val}{id} eq $productid) &&
		    ($_->{port} =~ /dev.*usb.*scanner/) &&
		    (!defined($_->{port2}))) {
		    # Duplicate entry found, merge the entries
		    $_->{port2} = $port;
		    $_->{val}{MANUFACTURER} ||= $make;
		    $_->{val}{MODEL} ||= $model;
		    $_->{val}{DESCRIPTION} ||= $description;
		    $duplicate = 1;
		    last;
		}
	    }
	    next if $duplicate;
	}
	# Store collected data
	push @res, { 
	    port => $port, 
	    val => { 
		CLASS => 'SCANNER',
		MODEL => $model,
		MANUFACTURER => $make,
		DESCRIPTION => $description,
		id => $productid,
		vendor => $vendorid,
	    } 
	};
    }
    close DETECT;
    if (@configured) {
	# Remove scanners which are already working
	foreach my $d (@res) {
	    my $searchport1 = handle_configs::searchstr($d->{port});
	    my $searchport2 = handle_configs::searchstr($d->{port2});
	    foreach my $c (@configured) {
		if (($c->{port} =~ /$searchport1$/) ||
		    ($c->{port} =~ /$searchport2$/)) {
		    $d->{configured} = 1;
		    last;
		}
	    }
	}
	@res = grep { ! $_->{configured} } @res;
    }
    return @res;
}

sub get_usb_ids_for_port {
    my ($port) = @_;
    my $vendorid;
    my $productid;
    if ($port =~ /^\s*libusb:(\d+):(\d+)\s*$/) {
	# Use "lsusb" to find the USB IDs
	open DETECT, "LC_ALL=C lsusb -s $1:$2 |";
	while (my $line = <DETECT>) {
	    if ($line =~ /ID\s+([0-9a-f]+):(0x[0-9a-f]+)($|\s+)/) {
		# Scanner connected via scanner.o kernel module
		$vendorid = "0x$1";
		$productid = "0x$2";
		last;
	    }
	}
	close DETECT;
    } else {
	# Run "sane-find-scanner" on the port
	open DETECT, "LC_ALL=C sane-find-scanner -q $port |";
	while (my $line = <DETECT>) {
	    if ($line =~ /^\s*found\s+USB\s+scanner/i) {
		if ($line =~ /vendor=(0x[0-9a-f]+)[^0-9a-f]+.*prod(|uct)=(0x[0-9a-f]+)[^0-9a-f]+/) {
		    # Scanner connected via scanner.o kernel module
		    $vendorid = $1;
		    $productid = $3;
		    last;
		}
	    }
	}
	close DETECT;
    }
    return ($vendorid, $productid);
}

sub readScannerDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = common::openFileMaybeCompressed($file);

    my ($lineno, $cmd, $val) = 0;
    my $fs = {
        LINE => sub { push @{$card->{lines}}, "LINE $val" },
        SCSILINE => sub { push @{$card->{lines}}, "SCSILINE $val" },
        USBLINE => sub { push @{$card->{lines}}, "USBLINE $val" },
        PARPORTLINE => sub { push @{$card->{lines}}, "PARPORTLINE $val" },
	NAME => sub {
	    #$cards{$card->{type}} = $card if ($card and !$card->{flags}{unsupported});
	    $cards{$card->{type}} = $card if $card;
	    $val =~ s/Seiko\s+Epson/Epson/i;
	    $card = { type => $val };
	},
	SEE => sub {
	    $val =~ s/Seiko\s+Epson/Epson/i;
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";

	    push @{$card->{lines}}, @{$c->{lines} || []};
	    add2hash($card->{flags}, $c->{flags});
	    add2hash($card, $c);
	},
	ASK => sub { $card->{ask} = $val },
	SERVER => sub { $card->{server} = $val },
	DRIVER => sub { $card->{driver} = $val },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	COMMENT => sub {},
    };

    local $_;
    while (<$F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and do { $cards{$card->{type}} = $card if $card; last };
	($cmd, $val) = /(\S+)\s*(.*)/ or next; #log::l("bad line $lineno ($_)"), next;
	my $f = $fs->{$cmd};
	$f ? $f->() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
}

sub updateScannerDBfromUsbtable {
    substInFile { s/END// } "ScannerDB";
    my $to_add = "# generated from usbtable by scannerdrake\n";
    foreach (cat_("$ENV{SHARE_PATH}/ldetect-lst/usbtable")) {
	my ($vendor_id, $product_id, $mod, $name) = chomp_(split /\s/,$_,4);
	next if $mod ne '"scanner"';
	$name =~ s/\"(.*)\"$/$1/;
	if (member($name, keys %$scanner::scannerDB)) {
	    print "#[$name] already in ScannerDB!\n";
	    next;
	}
	$to_add .= "NAME $name\nDRIVER USB\nCOMMENT usb $vendor_id $product_id\nUNSUPPORTED\n\n";
    }
    $to_add .= "END\n";

    append_to_file("ScannerDB", $to_add);
}

sub updateScannerDBfromSane {
    my ($_sanesrcdir) = @_;
    substInFile { s/END// } "ScannerDB";

    my $to_add = "# generated from Sane by scannerdrake\n";
    # for compat with our usbtable
    my $sane2DB = { 
		   "Acer" => "Acer Peripherals Inc.",
		   "AGFA" => "AGFA-Gevaert NV",
		   "Agfa" => "AGFA-Gevaert NV",
		   "Epson" => "Epson Corp.",
		   "Fujitsu Computer Products of America" => "Fujitsu",
		   "HP" => sub { $_[0] =~ s/HP\s/Hewlett-Packard|/; $_[0] =~ s/HP4200/Hewlett-Packard|ScanJet 4200C/; $_[0] },
		   "Hewlett-Packard" => sub { $_[0] =~ s/HP 3200 C/Hewlett-Packard|ScanJet 3200C/ or $_[0] = "Hewlett-Packard|$_[0]"; $_[0] },
		   "Kodak" => "Kodak Co.",
		   "Mustek" => "Mustek Systems Inc.",
		   "NEC" => "NEC Systems",
		   "Nikon" => "Nikon Corp.",
		   "Plustek" => "Plustek, Inc.",
		   "Primax" => "Primax Electronics",
		   "Siemens" => "Siemens Information and Communication Products",
		   "Trust" => "Trust Technologies",
		   "UMAX" => "Umax",
		   "Vobis/Highscreen" => "Vobis",
		  };

    # Read templates for configuration file lines
    my %configlines;
    my $backend;
    foreach my $line (cat_("$_scannerDBdir/scannerconfigs")) {
	chomp $line;
	if ($line =~ /^\s*SERVER\s+(\S+)\s*$/) {
	    $backend = $1;
	} elsif ($backend) {
	    push (@{$configlines{$backend}}, $line);
	}
    }

    my @descfiles;
    push (@descfiles,
	  glob_("$_sanesrcdir/doc/descriptions/*.desc"));
    push (@descfiles,
	  glob_("$_sanesrcdir/doc/descriptions-external/*.desc"));
    
    foreach my $f (@descfiles) {
	my $F = common::openFileMaybeCompressed($f);
	$to_add .= "\n# from $f";
	my ($lineno, $cmd, $val) = 0;
	my ($name, $intf, $comment, $mfg, $backend);
	my $fs = {
		  backend => sub { $backend = $val },
		  mfg => sub { $mfg = $val; $name = undef },#bug when a new mfg comes. should called $fs->{ $name }(); but ??
		  model => sub {
		      unless ($name) { $name = $val; return }
		      $name = member($mfg, keys %$sane2DB) ?
			(ref $sane2DB->{$mfg}) ? $sane2DB->{$mfg}($name) : "$sane2DB->{ $mfg }|$name" : "$mfg|$name";
		      if (0 && member($name, keys %$scanner::scannerDB)) {
			  print "#[$name] already in ScannerDB!\n";
		      } else {
			  # SANE bug: "snapscan" calls itself "SnapScan"
			  $backend =~ s/SnapScan/snapscan/g;
			  $to_add .= "\nNAME $name\nSERVER $backend\nDRIVER $intf\n";
			  # Go through the configuration lines of
			  # this backend and add what is needed for the
			  # interfaces of this scanner
			  foreach my $line (@{$configlines{$backend}}) {
			      $line =~ /^\s*(\S*?)LINE/;
			      my $i = $1;
			      if (!$i or $intf =~ /$i/i) {
				  $to_add .= "$line\n";
			      }
			  }
			  if ($backend =~
			      /(unsupported|mustek_pp|gphoto2)/i) {
			      $to_add .= "UNSUPPORTED\n";
			  }
			  $to_add .= "COMMENT $comment\n" if $comment;
			  $comment = undef; 
		      }
		      $name = $val;
		  },
		  interface => sub { $intf = $val },
		  comment => sub { $comment = $val },
		 };
	local $_;
	while (<$F>) { $lineno++;
		       s/\s+$//;
		       /^\;/ and next;
		       ($cmd, $val) = /:(\S+)\s*\"([^\;]*)\"/ or next; #log::l("bad line $lineno ($_)"), next;
		       if ($f =~ /microtek/) {
			   #print "##### |$cmd|$val|\n";
		       }
		       my $f = $fs->{$cmd};
		       $f ? $f->() : log::l("unknown line $lineno ($_)");
		       #$f ? $f->() : print "##### unknown line $lineno ($_)\n";
		   }
	$fs->{model}(); # the last one
    }
    $to_add .= "\nEND\n";
    append_to_file("ScannerDB", $to_add);
}

1; #
