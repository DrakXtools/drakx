package scanner;
# scanner.pm $Id$
# Yves Duret <yduret at mandriva.com>
# Till Kamppeter <till at mandriva.com>
# Copyright (C) 2001-2008 Mandriva
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
# - with 2 scanners same manufacturer -> will overwrite previous conf -> only 1 conf !! (should work now)
# - lp: see printerdrake
# - install: prefix --> done (partially)

use common;
use detect_devices;
use log;
use handle_configs;

my $sanedir = "$::prefix/etc/sane.d";
my $scannerDBdir = "$::prefix$ENV{SHARE_PATH}/ldetect-lst";
our $scannerDB = readScannerDB("$scannerDBdir/ScannerDB");

sub confScanner {
    my ($model, $port, $vendor, $product, $firmware) = @_;
    $port ||= "$::prefix/dev/scanner";
    my $a = $scannerDB->{$model}{server};
    #print "file:[$a]\t[$model]\t[$port]\n| ", (join "\n| ", @{$scannerDB->{$model}{lines}}),"\n";
    my @driverconf = cat_("$sanedir/$a.conf");
    my @configlines = @{$scannerDB->{$model}{lines}};
    foreach my $line (@configlines) {
	$line =~ s/\$DEVICE/$port/g if $port;
	next if $line =~ /\$DEVICE/;
	$line =~ s/\$VENDOR/$vendor/g if $vendor;
	next if $line =~ /\$VENDOR/;
	$line =~ s/\$PRODUCT/$product/g if $product;
	next if $line =~ /\$PRODUCT/;
	$line =~ s/\$FIRMWARE/$firmware/g if $firmware;
	next if $line =~ /\$FIRMWARE/;
	my $linetype;
	if ($line =~ /^(\S*)LINE\s+(.*?)$/) {
	    $linetype = $1;
	    $line = $2;
	}
	next if !$line;
	if (!$linetype ||
	    ($linetype eq "USB" && ($port =~ /usb/i || $vendor)) ||
	    ($linetype eq "PARPORT" && !$vendor &&
	     $port =~ /(parport|pt_drv|parallel)/i) ||
	    ($linetype eq "SCSI" && !$vendor &&
	     $port =~ m!(/sg|scsi|/scanner)!i)) {
	    handle_configs::set_directive(\@driverconf, $line, 1);
	} elsif ($linetype eq "FIRMWARE" && $firmware) {
	    handle_configs::set_directive(\@driverconf, $line, 0);
	}
    }
    output("$sanedir/$a.conf", @driverconf);
    add2dll($a);
}

sub add2dll {
    return if member($_[0], chomp_(cat_("$sanedir/dll.conf")));
    my @dllconf = cat_("$sanedir/dll.conf");
    handle_configs::add_directive(\@dllconf, $_[0]);
    output("$sanedir/dll.conf", @dllconf);
}

sub setfirmware {
    my ($backend, $firmwareline) = @_;
    my @driverconf = cat_("$sanedir/$backend.conf");
    handle_configs::set_directive(\@driverconf, $firmwareline, 0);
    output("$sanedir/$backend.conf", @driverconf);
}

sub installfirmware {
    # Install the firmware file in /usr/share/sane/firmware
    my ($firmware, $backend) = @_;
    return "" if !$firmware;
    # Install firmware
    run_program::rooted($::prefix, "mkdir", "-p",
			"/usr/share/sane/firmware") || do {
			    $in->ask_warn(N("Error"),
					  N("Could not create directory /usr/share/sane/firmware!"));
			    return "";
			};
    # Link /usr/share/sane/firmware to /usr/share/sane/<backend name> as
    # some backends ignore the supplied absolute path to the firmware file
    # and always search their own directory
    if ($backend) {
	run_program::rooted($::prefix, "ln", "-sf",
			    "/usr/share/sane/firmware",
			    "/usr/share/sane/$backend") || do {
				$in->ask_warn(N("Error"),
					      N("Could not create link /usr/share/sane/%s!", $backend));
				return "";
			    };
    }
    run_program::rooted($::prefix, "cp", "-f", "$firmware",
			"/usr/share/sane/firmware") || do {
			    $in->ask_warn(N("Error"),
					  N("Could not copy firmware file %s to /usr/share/sane/firmware!", $firmware));
			    return "";
			};
    $firmware =~ s!^(.*)(/[^/]+)$!/usr/share/sane/firmware$2!;
    run_program::rooted($::prefix, "chmod", "644",
			$firmware) || do {
			    $in->ask_warn(N("Error"),
					  N("Could not set permissions of firmware file %s!", $firmware));
			    return "";
			};
    return $firmware;
}

sub configured {
    my ($in) = @_;
    my @res;
    my $parportscannerfound = 0;
    # Run "scanimage -L", to find the scanners which are already working
    local *LIST;
    open LIST, "LC_ALL=C scanimage -L |";
    while (my $line = <LIST>) {
	if ($line =~ /^\s*device\s*`([^`']+)'\s+is\s+a\s+(\S.*)$/) {
	    # Extract port and description
	    my $port = $1;
	    my $description = $2;
	    # Remove duplicate scanners appearing through saned and the
	    # "net" backend
	    next if $port =~ /^net:(localhost|127.0.0.1):/;
	    # Is the scanner hooked to a parallel or serial port?
	    if ($port =~ /(parport|pt_drv|parallel|ttys)/i) {
		$parportscannerfound = 1;
	    }
	    # Determine which SANE backend the scanner in question uses
	    $port =~ /^([^:]+):/;
	    my $backend = $1;
	    # Does the scanner need a firmware file
	    my $firmwareline = firmwareline($backend);
	    # Store collected data
	    push @res, { 
		port => $port, 
		val => { 
		    DESCRIPTION => $description,
		    ($backend ? (BACKEND => $backend) : ()),
		    ($firmwareline ? 
		     (FIRMWARELINE => $firmwareline) : ()),
		}
	    };
	}
    }
    close LIST;
    # We have a parallel port scanner, make it working for non-root users
    nonroot_access_for_parport($parportscannerfound, $in);
    return @res;
}

sub nonroot_access_for_parport {

    # This function configures a non-root access for parallel port
    # scanners by running saned as root, exporting the scanner to
    # localhost and letting the user's frontend use the "net" backend
    # to access the scanner through the loopback network device.

    # See also
    # http://www.linuxprinting.org/download/digitalimage/Scanning-as-Normal-User-on-Wierd-Scanner-Mini-HOWTO.txt

    # Desired state of this facility: 1: Enable, 0: Disable
    my ($enable, $in) = @_;
    # Is saned running?
    my $sanedrunning = services::starts_on_boot("saned");
    # Is the "net" SANE backend active
    my $netbackendactive = grep { /^\s*net\s*$/ }
      cat_("/etc/sane.d/dll.conf");
    # Set this to 1 to tell the caller that the list of locally available
    # scanners has changed (Here if the SANE client configuration has
    # changed)
    my $changed = 0;
    my $importschanged = 0;
    if ($enable) {
	# Enable non-root access
	
	# Install/start saned
	if (!$sanedrunning) {
	    # Make sure saned and xinetd is installed and 
	    # running
	    if (!files_exist('/usr/sbin/xinetd',
			     '/usr/sbin/saned')) {
		if (!$in->do_pkgs->install('xinetd', 'saned')) {
		    $in->ask_warn(N("Scannerdrake"),
				  N("Could not install the packages needed to share your scanner(s).") . " " .
				  N("Your scanner(s) will not be available for non-root users."));
		}
		return 0;
	    }
	}

	# Modify /etc/xinetd.d/saned to let saned run as root
	my @sanedxinetdconf = cat_("/etc/xinetd.d/saned");
	s/(user\s*=\s*).*$/$1root/ foreach @sanedxinetdconf;
	s/(group\s*=\s*).*$/$1root/ foreach @sanedxinetdconf;
	output("/etc/xinetd.d/saned", @sanedxinetdconf);

	# Read list of hosts to where to export the local scanners
	my @exports = cat_("/etc/sane.d/saned.conf");
	# Read list of hosts from where to import scanners
	my @imports = cat_("/etc/sane.d/net.conf");
	# Add "localhost" to the machines which saned exports
	handle_configs::set_directive(\@exports, "localhost")
	    if !member("localhost\n", @exports);
	# Add "localhost" to the machines which "net" imports
	handle_configs::set_directive(\@imports, "localhost")
	    if !member("localhost\n", @imports);
	# Write /etc/sane.d/saned.conf
	output("/etc/sane.d/saned.conf", @exports);
	# Write /etc/sane.d/net.conf
	output("/etc/sane.d/net.conf", @imports);

	# Make sure that the "net" backend is active
	scanner::add2dll("net");
	
	# (Re)start saned and make sure that it gets started on
	# every boot
	services::start_service_on_boot("saned");
	services::start_service_on_boot("xinetd");
	services::restart("xinetd");

    } else {
	# Disable non-root access

	if (-r "/etc/xinetd.d/saned") {
	    # Modify /etc/xinetd.d/saned to let saned run as saned
	    my @sanedxinetdconf = cat_("/etc/xinetd.d/saned");
	    s/(user\s*=\s*).*$/$1saned/ foreach @sanedxinetdconf;
	    s/(group\s*=\s*).*$/$1saned/ foreach @sanedxinetdconf;
	    output("/etc/xinetd.d/saned", @sanedxinetdconf);
	    # Restart xinetd
	    services::restart("xinetd") if $sanedrunning;
	}
    }

    return 1;
}

sub detect {
    my @configured = @_;
    my @res;
    # Run "sane-find-scanner", this also detects USB scanners which only
    # work with libusb.

    my @devices = detect_devices::probeall();

    local *DETECT;
    open DETECT, "LC_ALL=C sane-find-scanner -q |";
    while (my $line = <DETECT>) {
	my ($vendorid, $productid, $make, $model, $description, $port, $driver);
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
	    if ($vendorid && $productid) {
		my ($vendor) = ($vendorid =~ /0x([0-9a-f]+)/);
		my ($id) = ($productid =~ /0x([0-9a-f]+)/);
		my ($device) = grep { sprintf("%04x", $_->{vendor}) eq $vendor && sprintf("%04x", $_->{id}) eq $id } @devices;

		if ($device) {
		    $driver = $device->{driver};
		} else {
		    #warn "Failed to lookup $vendorid and $productid!\n";
		}
                 
		# We have vendor and product ID, look up the scanner in
		# the usbtable
		foreach my $entry (common::catMaybeCompressed("$scannerDBdir/usbtable")) {
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
	# The Alcatel Speed Touch internet scanner is not supported by
	# SANE
	next if $description =~ /Alcatel.*Speed.*Touch|Camera|ISDN|ADSL/i;
	# Extract port
	$port = $1 if $line =~ /\s+(\S+)\s*$/;
	# Check for duplicate (scanner.o/libusb)
	if ($port =~ /^libusb/) {
	    my $duplicate = 0;
	    foreach (@res) {
		if ($_->{val}{vendor} eq $vendorid &&
		    $_->{val}{id} eq $productid &&
		    $_->{port} =~ /dev.*usb.*scanner/ &&
		    !defined($_->{port2})) {
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
		driver => $driver,
		drakx_device => $device,
	    } 
	};
    }
    close DETECT;
    if (@configured) {
	# Remove scanners which are already working
	foreach my $d (@res) {
	    my $searchport1 =
		handle_configs::searchstr(resolve_symlinks($d->{port}));
	    my $searchport2 =
		handle_configs::searchstr(resolve_symlinks($d->{port2}));
	    foreach my $c (@configured) {
		my $currentport = resolve_symlinks($c->{port});
		if ($currentport =~ /$searchport1$/ ||
		    $searchport2 && $currentport =~ /$searchport2$/) {
		    $d->{configured} = 1;
		    last;
		}
	    }
	}
	@res = grep { ! $_->{configured} } @res;
    }
    # blacklist device that have a driver b/c of buggy sane-find-scanner:
    return grep { member($_->{val}{driver}, qw(scanner unknown)) } @res;
}

sub resolve_symlinks {

    # Check if a given file (either the pure filename or in a SANE device
    # string as "<prefix>:<file>") is a symlink, if so expand the link.
    # If the new file name is a link, expand again, until finding the
    # physical file.
    my ($file) = @_;
    my $prefix = "";
    if ($file =~ m!^([^/]*)(/.*)$!) {
	$prefix = $1;
	$file = $2;
    } else {
	return $file;
    }
    while (1) {
	my $ls = `ls -l $file 2> /dev/null`;
	if ($ls =~ m!\s($file)\s*\->\s*(\S+)\s*$!) {
	    my $target = $2;
	    if ($target !~ m!^/! && $file =~ m!^(.*)/[^/]+$!) {
		$target = "$1/$target";
	    }
	    $file = $target;
	} else {
	    last;
	}
    }
    return $prefix . $file;
}

sub get_usb_ids_for_port {
    my ($port) = @_;
    local *DETECT;
    if ($port =~ /^\s*libusb:(\d+):(\d+)\s*$/) {
	# Use "lsusb" to find the USB IDs
	open DETECT, "LC_ALL=C lsusb -s $1:$2 |";
	while (my $line = <DETECT>) {
	    if ($line =~ /ID\s+([0-9a-f]+):(0x[0-9a-f]+)($|\s+)/) {
		# Scanner connected via scanner.o kernel module
		return "0x$1", "0x$2";
		last;
	    }
	}
    } else {
	# Run "sane-find-scanner" on the port
	open DETECT, "LC_ALL=C sane-find-scanner -q $port |";
	while (my $line = <DETECT>) {
	    if ($line =~ /^\s*found\s+USB\s+scanner/i) {
		if ($line =~ /vendor=(0x[0-9a-f]+)[^0-9a-f]+.*prod(|uct)=(0x[0-9a-f]+)[^0-9a-f]+/) {
		    # Scanner connected via scanner.o kernel module
		    return $1, $3;
		}
	    }
	}
    }
}

sub readconfiglinetemplates {
    # Read templates for configuration file lines
    my %configlines;
    my $backend;
    foreach my $line (cat_("$scannerDBdir/scannerconfigs")) {
	chomp $line;
	if ($line =~ /^\s*SERVER\s+(\S+)\s*$/) {
	    $backend = $1;
	} elsif ($backend) {
	    push @{$configlines{$backend}}, $line;
	}
    }
    return \%configlines;
}

sub firmwareline {
    # Determine whether the given SANE backend supports a firmware file
    # and return the line needed in the config file
    my ($backend) = @_;
    # Read templates for configuration file lines
    my %configlines = %{readconfiglinetemplates()};
    # Does the backend support a line for the firmware?
    my @firmwarelines = (grep { s/^FIRMWARELINE // } @{$configlines{$backend}});
    return join("\n", @firmwarelines);
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
        FIRMWARELINE => sub { push @{$card->{lines}}, "FIRMWARELINE $val" },
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
	KERNEL => sub { push(@{$card->{kernel}}, $val) },
	SCSIKERNEL => sub { push(@{$card->{scsikernel}}, $val) },
	USBKERNEL => sub { push(@{$card->{usbkernel}}, $val) },
	PARPORTKERNEL => sub { push(@{$card->{parportkernel}}, $val) },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	MANUAL => sub { $card->{flags}{manual} = 1 },
	MANUALREQUIRED => sub { $card->{flags}{manual} = 2 },
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

sub updateScannerDBfromUsbtable() {
    substInFile { s/^END// } "ScannerDB";
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
    my ($sanesrcdir) = @_;
    substInFile { s/^END// } "ScannerDB";

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
		   "Hewlett Packard" => "Hewlett-Packard",
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
    my %configlines = %{readconfiglinetemplates()};

    foreach my $ff (glob_("$sanesrcdir/doc/descriptions/*.desc"), glob_("$sanesrcdir/doc/descriptions-external/*.desc"), "UNSUPPORTED") {
	my $f = $ff;
	# unsupported.desc must be treated separately, as the list of
	# unsupported scanners in SANE is out of date.
	next if $f =~ /unsupported.desc$/;
	# Treat unsupported.desc in the end
	$f = "$sanesrcdir/doc/descriptions/unsupported.desc" if
	    ($f eq "UNSUPPORTED");
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
			ref($sane2DB->{$mfg}) ? $sane2DB->{$mfg}($name) : "$sane2DB->{ $mfg }|$name" : "$mfg|$name";
		      # When adding the unsupported scanner models, check
		      # whether the model is not already supported. To
		      # compare the names ignore upper/lower case.
		      my $searchname = quotemeta($name);
		      if (($backend =~ /unsupported/i) &&
			  ($to_add =~ /^NAME $searchname$/im)) {
			  $to_add .= "# $name already supported!\n";
		      } else {
			  # SANE bug: "snapscan" calls itself "SnapScan"
			  $backend =~ s/SnapScan/snapscan/g;
			  $to_add .= "\nNAME $name\nSERVER $backend\nDRIVER $intf\n";
			  # Go through the configuration lines of
			  # this backend and add what is needed for the
			  # interfaces of this scanner
			  foreach my $line (@{$configlines{$backend}}) {
			      my $i = $1 if $line =~ /^\s*(\S*?)LINE/;
			      if (!$i || $i eq "FIRMWARE" || 
				  $intf =~ /$i/i) {
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
		       /^;/ and next;
		       ($cmd, $val) = /:(\S+)\s*\"([^;]*)\"/ or next; #log::l("bad line $lineno ($_)"), next;
		       my $f = $fs->{$cmd};
		       $f ? $f->() : log::l("unknown line $lineno ($_)");
		   }
	$fs->{model}(); # the last one
    }
    $to_add .= "\nEND\n";
    append_to_file("ScannerDB", $to_add);
}

1; #
