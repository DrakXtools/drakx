package printer::detect;

use strict;
use common;
use detect_devices;
use modules;

sub local_detect {
    modules::get_probeall("usb-interface") and eval { modules::load("printer") };
    eval { modules::unload(qw(lp parport_pc parport_probe parport)) }; #- on kernel 2.4 parport has to be unloaded to probe again
    eval { modules::load(qw(parport_pc lp parport_probe)) }; #- take care as not available on 2.4 kernel (silent error).
    my $b = before_leaving { eval { modules::unload("parport_probe") } };
    detect_devices::whatPrinter();
}

sub net_detect { whatNetPrinter(1, 0) }

sub net_smb_detect { whatNetPrinter(0, 1) }

sub detect {
    local_detect(), net_detect(), net_smb_detect();
}

sub whatNetPrinter {
    my ($network, $smb) = @_;

    my ($i,@res);

    # Which ports should be scanned?
    my @portstoscan;
    push @portstoscan, "139" if $smb;
    push @portstoscan, "4010", "4020", "4030", "5503", "9100-9104" if $network;
    
    return () if $#portstoscan < 0;
    my $portlist = join (",", @portstoscan);
    
    # Which hosts should be scanned?
    # (Applying nmap to a whole network is very time-consuming, because nmap
    #  waits for a certain timeout period on non-existing hosts, so we get a 
    #  lists of existing hosts by pinging the broadcast addresses for existing
    #  hosts and then scanning only them, which is much faster)
    my @hostips = getIPsInLocalNetworks();
    return () if $#hostips < 0;
    my $hostlist = join (" ", @hostips);

    # Scan network for printers, the timeout settings are there to avoid
    # delays caused by machines blocking their ports with a firewall
    local *F;
    open F, ($::testing ? "" : "chroot $::prefix/ ") .
	"/bin/sh -c \"export LC_ALL=C; nmap -r -P0 --host_timeout 400 --initial_rtt_timeout 200 -p $portlist $hostlist\" |"
	or return @res;
    my ($host, $ip, $port, $modelinfo) = ("", "", "", "");
    while (my $line = <F>) {
	chomp $line;

	# head line of the report of a host with the ports in question open
	#if ($line =~ m/^\s*Interesting\s+ports\s+on\s+(\S*)\s*\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\)\s*:\s*$/i) {
	if ($line =~ m/^\s*Interesting\s+ports\s+on\s+(\S*)\s*\((\S+)\)\s*:\s*$/i) {
	    ($host, $ip) = ($1, $2);
	    $host = $ip if $host eq "";
	    $port = "";

	    undef $modelinfo;

	} elsif ($line =~ m/^\s*(\d+)\/\S+\s+open\s+/i) {
	    next if $ip eq "";
	    $port = $1;
	    
	    # Now we have all info for one printer
	    # Store this auto-detection result in the data structure

	    # Determine the protocol by the port number

	    # SMB/Windows
	    if ($port eq "139") {
		my @shares = getSMBPrinterShares($ip);
		foreach my $share (@shares) {
		    push @res, { port => "smb://$host/$share->{name}",
				 val => { CLASS => 'PRINTER',
					  MODEL => N("Unknown Model"),
					  MANUFACTURER => "",
					  DESCRIPTION => "$share->{description}",
					  SERIALNUMBER => ""
				      }
			     };
		}
	    } else {
		if (!defined($modelinfo)) {
		    # SNMP request to auto-detect model
		    $modelinfo = getSNMPModel($ip);
		}
		if (defined($modelinfo)) {
		    push @res, { port => "socket://$host:$port",
				 val => $modelinfo
				 };
		}
	    }
	}
    }
    close F;
    @res;
}

sub getIPsInLocalNetworks {

    # subroutine determines the list of all hosts reachable in the local
    # networks by means of pinging the broadcast addresses.
    
    # Return an empty list if no network is running
    return () unless network_running();
    
    # Read the output of "ifconfig" to determine the broadcast addresses of
    # the local networks
    my $dev_is_localnet = 0;
    my @local_bcasts;
    my $current_bcast = "";
	
    local *IFCONFIG_OUT;
    open IFCONFIG_OUT, ($::testing ? "" : "chroot $::prefix/ ") .
	"/bin/sh -c \"export LC_ALL=C; ifconfig\" |" or return ();
    while (my $readline = <IFCONFIG_OUT>) {
	# New entry ...
	if ($readline =~ /^(\S+)\s/) {
	    my $dev = $1;
	    # ... for a local network (eth = ethernet, 
	    #     vmnet = VMWare,
	    #     ethernet card connected to ISP excluded)?
	    $dev_is_localnet = $dev =~ /^eth/ || $dev =~ /^vmnet/;
	    # delete previous address
	    $current_bcast = "";
	}
	# Are we in the important line now?
	if ($readline =~ /\sBcast:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s/) {
	    # Rip out the broadcast IP address
	    $current_bcast = $1;
	    
	    # Are we in an entry for a local network?
	    if ($dev_is_localnet == 1) {
		# Store current IP address
		push @local_bcasts, $current_bcast;
	    }
	}
    }
    close(IFCONFIG_OUT);

    my @addresses;
    # Now ping all broadcast addresses and additionally "nmblookup" the
    # networks (to find Windows servers which do not answer to ping)
    foreach my $bcast (@local_bcasts) {
	local *F;
	open F, ($::testing ? "" : "chroot $::prefix/ ") . 
	    "/bin/sh -c \"export LC_ALL=C; ping -w 1 -b -n $bcast | cut -f 4 -d ' ' | sed s/:// | egrep '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | uniq | sort\" |" 
	    or next;
	local $_;
	while (<F>) { chomp; push @addresses, $_ }
	close F;
	if (-x "/usr/bin/nmblookup") {
	    local *F;
	    open F, ($::testing ? "" : "chroot $::prefix/ ") . 
		"/bin/sh -c \"export LC_ALL=C; nmblookup -B $bcast \\* | cut -f 1 -d ' ' | egrep '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | uniq | sort\" |" 
		or next;
	    local $_;
	    while (<F>) { 
		chomp;
		push @addresses, $_ if !(member($_,@addresses));
	    }
	}
    }

    @addresses;
}

sub getSMBPrinterShares {
    my ($host) = @_;
    
    # SMB request to auto-detect shares
    local *F;
    open F, ($::testing ? "" : "chroot $::prefix/ ") .
	"/bin/sh -c \"export LC_ALL=C; smbclient -N -L $host\" |" or return ();
    my $insharelist = 0;
    my @shares;
    while (my $l = <F>) {
	chomp $l;
	if ($l =~ /^\s*Sharename\s+Type\s+Comment\s*$/i) {
	    $insharelist = 1;
	} elsif ($l =~ /^\s*Server\s+Comment\s*$/i) {
	    $insharelist = 0;
	} elsif ($l =~ /^\s*(\S+)\s+Printer\s*(.*)$/i &&
		 $insharelist) {
	    my $name = $1;
	    my $description = $2;
	    $description =~ s/^(\s*)//;
	    push (@shares, { name => $name, description => $description });
	}
    }
    close F;

    return @shares;
}

sub getSNMPModel {
    my ($host) = @_;
    my $manufacturer = "";
    my $model = "";
    my $description = "";
    my $serialnumber = "";
    
    # SNMP request to auto-detect model
    local *F;
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") .
	"/bin/sh -c \"scli -1 -c 'show printer info' $host\" |" or
	return { CLASS => 'PRINTER',
		 MODEL => N("Unknown Model"),
		 MANUFACTURER => "",
		 DESCRIPTION => "",
		 SERIALNUMBER => ""
		 };
    while (my $l = <F>) {
	chomp $l;
	if ($l =~ /^\s*Manufacturer:\s*(\S.*)$/i &&
	    $l =~ /^\s*Vendor:\s*(\S.*)$/i) {
	    $manufacturer = $1;
	    $manufacturer =~ s/Hewlett[-\s_]Packard/HP/;
	    $manufacturer =~ s/HEWLETT[-\s_]PACKARD/HP/;
	} elsif ($l =~ /^\s*Model:\s*(\S.*)$/i) {
	    $model = $1;
	} elsif ($l =~ /^\s*Description:\s*(\S.*)$/i) {
	    $description = $1;
	    $description =~ s/Hewlett[-\s_]Packard/HP/;
	    $description =~ s/HEWLETT[-\s_]PACKARD/HP/;
	} elsif ($l =~ /^\s*Serial\s*Number:\s*(\S.*)$/i) {
	    $serialnumber = $1;
	}
    }
    close F;

    # Was there a manufacturer and a model in the output?
    # If not, get them from the description
    if ($manufacturer eq "" || $model eq "") {
	if ($description =~ /^\s*(\S*)\s+(\S.*)$/) {
	    $manufacturer = $1 if $manufacturer eq "";
	    $model = $2 if $model eq "";
	}
	# No description field? Make one out of manufacturer and model.
    } elsif ($description eq "") {
	$description = "$manufacturer $model";
    }
    
    # We couldn't determine a model
    $model = N("Unknown Model") if $model eq "";
    
    # Remove trailing spaces
    $manufacturer =~ s/(\S+)\s+$/$1/;
    $model        =~ s/(\S+)\s+$/$1/;
    $description  =~ s/(\S+)\s+$/$1/;
    $serialnumber =~ s/(\S+)\s+$/$1/;

    # Now we have all info for one printer
    # Store this auto-detection result in the data structure
    return  { CLASS => 'PRINTER',
	      MODEL => $model,
	      MANUFACTURER => $manufacturer,
	      DESCRIPTION => $description,
	      SERIALNUMBER => $serialnumber
	      };
}

sub network_running {
    # If the network is not running return 0, otherwise 1.
    local *F; 
    open F, ($::testing ? $::prefix : "chroot $::prefix/ ") . 
	"/bin/sh -c \"export LC_ALL=C; /sbin/ifconfig\" |" or
	    die "Could not run \"ifconfig\"!";
    while (my $line = <F>) {
	if ($line !~ /^lo\s+/ && # The loopback device can have been 
                                   # started by the spooler's startup script
	    $line =~ /^(\S+)\s+/) { # In this line starts an entry for a
	                              # running network
	    close F;
	    return 1;
	}
    }
    close F;
    return 0;
}

sub parport_addr {
    # auto-detect the parallel port addresses
    my ($device) = @_;
    $device =~ m!^/dev/lp(\d+)$! or
	$device =~ m!^/dev/printers/(\d+)$!;
    my $portnumber = $1;
    my $parport_addresses = 
	`cat /proc/sys/dev/parport/parport$portnumber/base-addr`;
    my $address_arg;
    if ($parport_addresses =~ /^\s*(\d+)\s+(\d+)\s*$/) {
	$address_arg = sprintf(" -base 0x%x -basehigh 0x%x", $1, $2);
    } elsif ($parport_addresses =~ /^\s*(\d+)\s*$/) {
	$address_arg = sprintf(" -base 0x%x", $1);
    } else {
	$address_arg = "";
    }
    return $address_arg;
}

1;
