package printer::printerdrake;
# $Id$

use strict;

use common;
use detect_devices;
use modules;
use network;
use log;
use interactive;
use printer::main;
use printer::services;
use printer::detect;
use printer::default;
use printer::data;

1;

sub choose_printer_type {
    my ($printer, $in) = @_;
    $in->set_help('configurePrinterConnected') if $::isInstall;
    $printer->{str_type} = $printer_type_inv{$printer->{TYPE}};
    my $autodetect = 0;
    $autodetect = 1 if $printer->{AUTODETECT};
    my @printertypes = printer::main::printer_type($printer);
    $in->ask_from_(
		   { title => N("Select Printer Connection"),
		     messages => N("How is the printer connected?") .
			 if_($printer->{SPOOLER} eq "cups",
			  N("
Printers on remote CUPS servers you do not have to configure here; these printers will be automatically detected.")),
		     },
		   [
		    { val => \$printer->{str_type},
		      list => \@printertypes, 
		      not_edit => 1, sort => 0,
		      type => 'list' },
		    { text => N("Printer auto-detection (Local, TCP/Socket, and SMB printers)"),
		      type => 'bool', val => \$autodetect }
		    ]
		   ) or return 0;
    $printer->{AUTODETECT} = $autodetect ? 1 : undef;
    $printer->{TYPE} = $printer_type{$printer->{str_type}};
    1;
}

sub config_cups {
    my ($printer, $in, $upNetwork) = @_;

    local $::isWizard = 0;
    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('configureRemoteCUPSServer') if $::isInstall;
    #- hack to handle cups remote server printing,
    #- first read /etc/cups/cupsd.conf for variable BrowsePoll address:port
    my ($server, $port, $autoconf);
    # Return value: 0 when nothing was changed ("Apply" never pressed), 1
    # when "Apply" was at least pressed once.
    my $retvalue = 0;
    # Read CUPS config file
    @{$printer->{cupsconfig}{cupsd_conf}} =
	printer::main::read_cupsd_conf();
    printer::main::read_cups_config($printer);
    # Read state for auto-correction of cupsd.conf
    $printer->{cupsconfig}{autocorrection} =
	printer::main::get_cups_autoconf();
    my $oldautocorr = $printer->{cupsconfig}{autocorrection};
    # Human-readable strings for hosts onto which the local printers
    # are shared
    my $maindone;
    while (!$maindone) {
	my $sharehosts = printer::main::makesharehostlist($printer);
	my $buttonclicked;
	#- Show dialog
	if ($in->ask_from_
	    (
	     { 
		 title => N("CUPS printer sharing configuration"),
		 messages => N("Here you can choose whether the printers connected to this machine should be accessable by remote machines and by which remote machines.") .
		     N("You can also decide here whether printers on remote machines should be automatically made available on this machine."),
	     },
	     [
	      { text => N("The printers on this machine are available to other computers"), type => 'bool',
		val => \$printer->{cupsconfig}{localprintersshared} },
	      { val => N("Local printers available on: ") .
		    ($printer->{cupsconfig}{customsharingsetup} ?
		     N("Custom configuration") :
		     ($#{$sharehosts->{list}} >= 0 ?
		      ($#{$sharehosts->{list}} > 1 ?
		       join (", ", @{$sharehosts->{list}}[0,1]) . " ..." :
		       join (", ", @{$sharehosts->{list}})) :
		      N("No remote machines"))), 
		type => 'button',
		clicked_may_quit => sub {
		    $buttonclicked = "sharehosts";
		    1;
		},
		disabled => sub {
		    (!$printer->{cupsconfig}{localprintersshared});
		}},
	      { text => N("Automatically find available printers on remote machines"), type => 'bool',
		val => \$printer->{cupsconfig}{remotebroadcastsaccepted} },
	      if_($::expert,
		  { text => N("Automatic correction of CUPS configuration"),
		    type => 'bool',
		    help => N("When this option is turned on, on every startup of CUPS is automatically made sure that

- if LPD/LPRng is installed, /etc/printcap will not be overwritten by CUPS

- if /etc/cups/cupsd.conf is missing, it will be created

- when printer information is broadcasted, it does not contain \"localhost\" as the server name.

If some of these measures lead to problems for you, turn this option off, but then you have to take care of these points."),
		    val => \$printer->{cupsconfig}{autocorrection} }),
	      ]
	     )
	    ) {
	    if ($buttonclicked eq "sharehosts") {
		# Show dialog to add hosts to share printers to
		my $subdone = 0;
		my $choice;
		while (!$subdone) {
		    # Entry should be edited when double-clicked
		    $buttonclicked = "edit";
		    $in->ask_from_
			(
			 { title => N("Sharing of local printers"),
			   messages => N("These are the machines and networks on which the locally connected printer(s) should be available:"),
			   ok => "",
			   cancel => "",
		         },
			 # List the hosts
			 [ { val => \$choice, format => \&translate,
			     sort => 0, separator => "####",
			     tree_expanded => 1,
			     quit_if_double_click => 1,
			     allow_empty_list => 1,
			     list => $sharehosts->{list} },
			   { val => N("Add host/network"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "add";
				 1; 
			     }},
			   { val => N("Edit selected host/network"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "edit";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$sharehosts->{list}} < 0);
			     }},
			   { val => N("Remove selected host/network"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "remove";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$sharehosts->{list}} < 0);
			     }},
			   { val => N("Done"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "";
				 $subdone = 1;
				 1; 
			     }},
			   ]
			 );
		    if (($buttonclicked eq "add") ||
			($buttonclicked eq "edit")) {
			my ($hostchoice, $ip);
			if ($buttonclicked eq "add") {
			    # Use first entry as default for a new entry
			    $hostchoice = N("Local network(s)");
			} else {
			    if ($sharehosts->{invhash}{$choice} =~ /^\@/) {
				# Entry to edit is not an IP address
				$hostchoice = $choice;
			    } else {
				# Entry is an IP address
				$hostchoice = 
				    N("IP address of host/network:");
				$ip = $sharehosts->{invhash}{$choice};
			    }
			}
			my @menu = (N("Local network(s)"));
			my @interfaces = 
			    printer::detect::getNetworkInterfaces();
		        for my $interface (@interfaces) {
			    push (@menu,
				  (N("Interface \"%s\"", $interface)));
			}
			push (@menu, N("IP address of host/network:"));
			# Show the dialog
			my $address;
			my $oldaddress = 
			    ($buttonclicked eq "edit" ?
			     $sharehosts->{invhash}{$choice} : "");
			if ($in->ask_from_
			    (
			     { title => N("Sharing of local printers"),
			       messages => N("Choose the network or host on which the local printers should be made available:"),
			       callbacks => {
				   complete => sub {
				       if (($hostchoice eq 
					    N("IP address of host/network:")) &&
					   (!printer::main::is_network_ip($ip))) {
					   
					   $in->ask_warn('', 
N("The entered host/network IP is not correct.\n") .
N("Examples for correct IPs:\n") .
N("192.168.100.194\n") .
N("10.0.0.*\n") .
N("10.1.*\n") .
N("192.168.100.0/24\n") .
N("192.168.100.0/255.255.255.0\n")
);
					   return (1,0);
				       }
				       if ($hostchoice eq $menu[0]) {
					   $address = "\@LOCAL";
				       } elsif ($hostchoice eq 
						$menu[$#menu]) {
					   $address = $ip;
				       } else {
					   ($address) =
					       grep {$hostchoice =~ /$_/} 
					       @interfaces;
					   $address = "\@IF($address)";
				       }
				       # Check whether item is duplicate
				       if (($address ne $oldaddress) &&
					   (member($address,
						   @{$printer->{cupsconfig}{clientnetworks}}))) {
					   $in->ask_warn('', 
							 N("This host/network is already in the list, it cannot be added again.\n"));
					   return (1,1);
				       }
				       return 0;
				   },
			       },
			   },
			     # List the host types
			     [ { val => \$hostchoice, format => \&translate,
				 type => 'list',
				 sort => 0,
				 list => \@menu },
			       { val => \$ip, 
				 disabled => sub {
				     $hostchoice ne 
					 N("IP address of host/network:");
			         }},
			       ],
			     )) {
			    # OK was clicked, insert new item into the list
			    if ($buttonclicked eq "add") {
				push(@{$printer->{cupsconfig}{clientnetworks}},
				     $address);
			    } else {
				@{$printer->{cupsconfig}{clientnetworks}} =
				    map {($_ eq
					  $sharehosts->{invhash}{$choice} ?
					  $address : $_)}
				        @{$printer->{cupsconfig}{clientnetworks}};
			    }
			    # Refresh list of hosts
			    $sharehosts = 
			    printer::main::makesharehostlist($printer);
			    # We have modified the configuration now
			    $printer->{cupsconfig}{customsharingsetup} = 0;
			    # Position the list cursor on the new/modified
			    # item
			    $choice = $sharehosts->{hash}{$address};
			}
		    } elsif ($buttonclicked eq "remove") {
			@{$printer->{cupsconfig}{clientnetworks}} =
			    grep {$_ ne $sharehosts->{invhash}{$choice}}
			    @{$printer->{cupsconfig}{clientnetworks}};
			# Refresh list of hosts
			$sharehosts = 
			    printer::main::makesharehostlist($printer);
			# We have modified the configuration now
			$printer->{cupsconfig}{customsharingsetup} = 0;
		    }
		    # If we have no entry in the list, we do not
		    # share the local printers, mark this
		    $printer->{cupsconfig}{localprintersshared} =
			($#{$printer->{cupsconfig}{clientnetworks}} >= 0);
		}
	    } else {
		# We have clicked "OK"
		$retvalue = 1;
		$maindone = 1;
		# Write state for auto-correction of cupsd.conf
		if ($oldautocorr != 
		    $printer->{cupsconfig}{autocorrection}) {
		    printer::main::set_cups_autoconf
			($printer->{cupsconfig}{autocorrection});
		}
		# Write cupsd.conf
		printer::main::write_cups_config($printer);
		printer::main::write_cupsd_conf
		    (@{$printer->{cupsconfig}{cupsd_conf}});
	    }
	} else {
	    # Cancel clicked
	    $maindone = 1;
	}
    }
    printer::main::clean_cups_config($printer);
    return $retvalue;
}

sub setup_printer_connection {
    my ($printer, $in, $upNetwork) = @_;
    # Choose the appropriate connection config dialog
    my $done = 1;
    for ($printer->{TYPE}) {
	/LOCAL/    and setup_local_autoscan($printer, $in, $upNetwork) and last;
	/LPD/      and setup_lpd(      $printer, $in, $upNetwork) and last;
	/SOCKET/   and setup_socket(   $printer, $in, $upNetwork) and last;
	/SMB/      and setup_smb(      $printer, $in, $upNetwork) and last;
	/NCP/      and setup_ncp(      $printer, $in, $upNetwork) and last;
	/URI/      and setup_uri(      $printer, $in, $upNetwork) and last;
	/POSTPIPE/ and setup_postpipe( $printer, $in) and last;
	$done = 0; last;
    }
    return $done;
}

sub first_time_dialog {
    my ($printer, $in, $upNetwork) = @_;
    return 1 if printer::default::get_spooler() || $::isInstall;

    # Wait message
    my $w = $in->wait_message(N("Printerdrake"), N("Checking your system..."));

    # Auto-detect local printers   
    my @autodetected = printer::detect::local_detect();
    my $msg = do {
	if (@autodetected) {
	    my @printerlist = 
	      map {
		  my $entry = $_->{val}{DESCRIPTION};
		  if_($entry, "  -  $entry\n");
	      } @autodetected;
	    my $unknown_printers = @autodetected - @printerlist;
	    if (@printerlist) {
		my $unknown_msg = 
		  $unknown_printers == 1 ? 
		    "\n" . N("and one unknown printer") :
		  $unknown_printers > 1 ?
		    "\n" . N("and %d unknown printers", $unknown_printers) :
		    '';
		my $main_msg = 
		  @printerlist > 1 ?
		    N_("The following printers\n\n%s%s\nare directly connected to your system") :
		  $unknown_printers ?
		    N_("The following printer\n\n%s%s\nare directly connected to your system") :
		    N_("The following printer\n\n%s%s\nis directly connected to your system");
		sprintf($main_msg, join('', @printerlist), $unknown_msg);
	    } else {
		$unknown_printers == 1 ?
		  N("\nThere is one unknown printer directly connected to your system") :
		  N("\nThere are %d unknown printers directly connected to your system", $unknown_printers);
	    }
	} else {
	    N("There are no printers found which are directly connected to your machine");
	}
    };
    $msg .= N(" (Make sure that all your printers are connected and turned on).\n");

    # Do we have a local network?

    # If networking is configured, start it, but don't ask the user to
    # configure networking.
    my $havelocalnetworks = 
	 check_network($printer, $in, $upNetwork, 1) && 
	  printer::detect::getIPsInLocalNetworks() != ();

    # Finish building the dialog text
    my $question = ($havelocalnetworks ?
		    (@autodetected ?
		     N("Do you want to enable printing on the printers mentioned above or on printers in the local network?\n") :
		     N("Do you want to enable printing on printers in the local network?\n")) :
		    (@autodetected ?
		     N("Do you want to enable printing on the printers mentioned above?\n") :
		     N("Are you sure that you want to set up printing on this machine?\n")));
    my $warning = N("NOTE: Depending on the printer model and the printing system up to %d MB of additional software will be installed.", 80);
    my $dialogtext = "$msg\n$question\n$warning";

    # Close wait message
    undef $w;

    # Show dialog
    $in->ask_yesorno(N("Printerdrake"), $dialogtext, 0);
}

sub wizard_welcome {
    my ($printer, $in, $upNetwork) = @_;
    my $ret;
    my $autodetectlocal = 0;
    my $autodetectnetwork = 0;
    my $autodetectsmb = 0;
    # If networking is configured, start it, but don't ask the user to
    # configure networking.
    my $havelocalnetworks;
    if ($::expert) {
	$havelocalnetworks = 0;
	undef $printer->{AUTODETECTNETWORK};
	undef $printer->{AUTODETECTSMB};
    } else {
	$havelocalnetworks = check_network($printer, $in, $upNetwork, 1) &&
			      printer::detect::getIPsInLocalNetworks() != ();
	if (!$havelocalnetworks) {
	    undef $printer->{AUTODETECTNETWORK};
	    undef $printer->{AUTODETECTSMB};
	}
	$autodetectlocal = 1 if $printer->{AUTODETECTLOCAL};
	$autodetectnetwork = 1 if $printer->{AUTODETECTNETWORK};
	$autodetectsmb = 1 if $printer->{AUTODETECTSMB};
    }
    if ($in) {
	eval {
	    if ($::expert) {
		if ($::isWizard) {
		    $ret = $in->ask_okcancel(
			 N("Add a new printer"),
			 N("
Welcome to the Printer Setup Wizard

This wizard allows you to install local or remote printers to be used from this machine and also from other machines in the network.

It asks you for all necessary information to set up the printer and gives you access to all available printer drivers, driver options, and printer connection types."));
		} else {
		    $ret = 1;
		}
	    } else {
		$ret = $in->ask_from_(
		     { title => N("Add a new printer"),
		       messages => ($printer->{SPOOLER} ne "pdq" ? 
				   ($havelocalnetworks ? N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer, connected directly to the network or to a remote Windows machine.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected. Also your network printer(s) and you Windows machines must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network and/or Windows-hosted printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.") : N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.")) : 
				   ($havelocalnetworks ? N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer or connected directly to the network.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected. Also your network printer(s) must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.") : N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now."))) },
		     [
		      { text => N("Auto-detect printers connected to this machine"), type => 'bool',
			val => \$autodetectlocal },
		           if_($havelocalnetworks,
		      { text => N("Auto-detect printers connected directly to the local network"), type => 'bool',
			val => \$autodetectnetwork },
			   if_($printer->{SPOOLER} ne "pdq",
		      { text => N("Auto-detect printers connected to machines running Microsoft Windows"), type => 'bool',
			val => \$autodetectsmb })),
		      ]);
		$printer->{AUTODETECTLOCAL} = $autodetectlocal ? 1 : undef;
		$printer->{AUTODETECTNETWORK} = $autodetectnetwork ? 1 : undef;
		$printer->{AUTODETECTSMB} = $autodetectsmb && $printer->{SPOOLER} ne "pdq" ? 1 : undef;
	    }
	};
	return $@ =~ /wizcancel/ ? 0 : $ret;
    }
}

sub wizard_congratulations {
    my ($in) = @_;
    if ($in) {
	$in->ask_okcancel(N("Add a new printer"),
			  N("
Congratulations, your printer is now installed and configured!

You can print using the \"Print\" command of your application (usually in the \"File\" menu).

If you want to add, remove, or rename a printer, or if you want to change the default option settings (paper input tray, printout quality, ...), select \"Printer\" in the \"Hardware\" section of the Mandrake Control Center."))
    }
}

sub setup_local_autoscan {
    my ($printer, $in, $upNetwork) = @_;
    my $queue = $printer->{OLD_QUEUE};
    my $expert_or_modify = $::expert || !$printer->{NEW};
    my $do_auto_detect = 
	($expert_or_modify &&
	  $printer->{AUTODETECT} ||
	 (!$expert_or_modify &&
	  ($printer->{AUTODETECTLOCAL} ||
	   $printer->{AUTODETECTNETWORK} ||
	   $printer->{AUTODETECTSMB})));

    # If the user requested auto-detection of remote printers, check
    # whether the network functionality is configured and running
    if ($printer->{AUTODETECTNETWORK} || $printer->{AUTODETECTSMB}) {
	return 0 unless check_network($printer, $in, $upNetwork, 0);
    }

    my @autodetected;
    my $menuentries = {};
    $in->set_help('setupLocal') if $::isInstall;
    if ($do_auto_detect) {
	if (!$::testing &&
	    !$expert_or_modify && $printer->{AUTODETECTSMB} && !files_exist('/usr/bin/smbclient')) {
	    $in->do_pkgs->install('samba-client');
	}
	my $_w = $in->wait_message(N("Printer auto-detection"), N("Detecting devices..."));
	# When HPOJ is running, it blocks the printer ports on which it is
	# configured, so we stop it here. If it is not installed or not 
	# configured, this command has no effect.
	require services;
	services::stop("hpoj");
	@autodetected = (
	    $expert_or_modify || $printer->{AUTODETECTLOCAL} ? printer::detect::local_detect() : (),
	    !$expert_or_modify ? printer::detect::whatNetPrinter($printer->{AUTODETECTNETWORK}, $printer->{AUTODETECTSMB}) : (),
        );
	# We have more than one printer, so we must ask the user for a queue
	# name in the fully automatic printer configuration.
	$printer->{MORETHANONE} = $#autodetected > 0;
	my @str;
	foreach my $p (@autodetected) {
	    if ($p->{val}{DESCRIPTION}) {
		my $menustr = $p->{val}{DESCRIPTION};
		if ($p->{port} =~ m!^/dev/lp(\d+)$!) {
		    $menustr .= N(" on parallel port \#%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr .= N(", USB printer \#%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= N(", network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= N(", printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
          $menustr .= " ($p->{port})" if $::expert;
		$menuentries->{$menustr} = $p->{port};
		push @str, N("Detected %s", $menustr);
	    } else {
		my $menustr;
		if ($p->{port} =~ m!^/dev/lp(\d+)$!) {
		    $menustr = N("Printer on parallel port \#%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = N("USB printer \#%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= N("Network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= N("Printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
		$menustr .= " ($p->{port})" if $::expert;
		$menuentries->{$menustr} = $p->{port};
	    }
	}
	my @port;
	if ($::expert) {
	    @port = detect_devices::whatPrinterPort();
	    LOOP: foreach my $q (@port) {
		if (@str) {
		    foreach my $p (@autodetected) {
			last LOOP if $p->{port} eq $q;
		    }
		}
		my $menustr;
		if ($q =~ m!^/dev/lp(\d+)$!) {
		    $menustr = N("Printer on parallel port \#%s", $1);
		} elsif ($q =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = N("USB printer \#%s", $1);
		}
		$menustr .= " ($q)" if $::expert;
		$menuentries->{$menustr} = $q;
	    }
	}
	# We are ready with auto-detection, so we restart HPOJ here. If it 
	# is not installed or not configured, this command has no effect.
	printer::services::start("hpoj");
    } else {
	# Always ask for queue name in recommended mode when no auto-
	# detection was done
	$printer->{MORETHANONE} = $#autodetected > 0;
	my $m;
	for ($m = 0; $m <= 2; $m++) {
	    my $menustr = N("Printer on parallel port \#%s", $m);
	    $menustr .= " (/dev/lp$m)" if $::expert;
	    $menuentries->{$menustr} = "/dev/lp$m";
	    $menustr = N("USB printer \#%s", $m);
	    $menustr .= " (/dev/usb/lp$m)" if $::expert;
	    $menuentries->{$menustr} = "/dev/usb/lp$m";
	}
    }
    my @menuentrieslist = sort { 
	my @prefixes = ("/dev/lp", "/dev/usb/lp", "/dev/", "socket:", "smb:");
	my $first = $menuentries->{$a};
	my $second = $menuentries->{$b};
	for (my $i = 0; $i <= $#prefixes; $i++) {
	    my $firstinlist = $first =~ m!^$prefixes[$i]!;
	    my $secondinlist = $second =~ m!^$::prefixes[$i]!;
	    if ($firstinlist && !$secondinlist) { return -1 };
	    if ($secondinlist && !$firstinlist) { return 1 };
	}
	return $first cmp $second;
    } keys(%{$menuentries});
    my $menuchoice = "";
    my $oldmenuchoice = "";
    my $device;
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^file:/) {
	# Non-HP or HP print-only device (HPOJ not used)
	$device = $printer->{currentqueue}{connect};
	$device =~ s/^file://;
	foreach my $p (keys %{$menuentries}) {
	    if ($device eq $menuentries->{$p}) {
		$menuchoice = $p;
		last;
	    }
	}
    } elsif ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m!^ptal:/mlc:!) {
	# HP multi-function device (controlled by HPOJ)
	my $ptaldevice = $printer->{currentqueue}{connect};
	$ptaldevice =~ s!^ptal:/mlc:!!;
	if ($ptaldevice =~ /^par:(\d+)$/) {
	    $device = "/dev/lp$1";
	    foreach my $p (keys %{$menuentries}) {
		if ($device eq $menuentries->{$p}) {
		    $menuchoice = $p;
		    last;
		}
	    }
	} else {
	    my $make = lc($printer->{currentqueue}{make});
	    my $model = lc($printer->{currentqueue}{model});
	    $device = "";
	    foreach my $p (keys %{$menuentries}) {
		my $menumakemodel = lc($p);
		if ($menumakemodel =~ /$make/ && 
		    $menumakemodel =~ /$model/) {
		    $menuchoice = $p;
		    $device = $menuentries->{$p};
		    last;
		}
	    }
	}
    } elsif ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m!^(socket|smb):/!) {
	# Ethernet-(TCP/Socket)-connected printer or printer on Windows server
	$device = $printer->{currentqueue}{connect};
	foreach my $p (keys %{$menuentries}) {
	    if ($device eq $menuentries->{$p}) {
		$menuchoice = $p;
		last;
	    }
	}
    } else { $device = "" }
    if ($menuchoice eq "" && @menuentrieslist > -1) {
	$menuchoice = $menuentrieslist[0];
	$oldmenuchoice = $menuchoice;
	$device = $menuentries->{$menuchoice} if $device eq "";
    }
    if ($in) {
	$::expert or $in->set_help('configurePrinterDev') if $::isInstall;
	if ($#menuentrieslist < 0) { # No menu entry
	    # auto-detection has failed, we must do all manually
	    $do_auto_detect = 0;
	    $printer->{MANUAL} = 1;
	    if ($::expert) {
		$device = $in->ask_from_entry(
		     N("Local Printer"),
		     N("No local printer found! To manually install a printer enter a device name/file name in the input line (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...)."),
		     { 
			 complete => sub {
			     if ($menuchoice eq "") {
				 $in->ask_warn('', N("You must enter a device or file name!"));
				 return (1,0);
			     }
			     return 0;
			 }
		     });
		return 0 if $device eq "";
	    } else {
		$in->ask_warn(N("Printer auto-detection"),
			      N("No printer found!"));
		return 0;
	    }
	} else {
	    my $manualconf = 0;
	    $manualconf = 1 if $printer->{MANUAL} || !$do_auto_detect;
	    if (!$in->ask_from_(
		 { title => ($expert_or_modify ?
			     N("Local Printer") :
			     N("Available printers")),
		   messages => (($do_auto_detect ?
				 ($::expert ?
				  ($#menuentrieslist == 0 ?
				   N("The following printer was auto-detected, if it is not the one you want to configure, enter a device name/file name in the input line") :
				   N("Here is a list of all auto-detected printers. Please choose the printer you want to set up or enter a device name/file name in the input line")) :
				  ($#menuentrieslist == 0 ?
				   N("The following printer was auto-detected. The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\".") :
				   N("Here is a list of all auto-detected printers. Please choose the printer you want to set up. The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\"."))) :
				 ($::expert ?
				  N("Please choose the port where your printer is connected to or enter a device name/file name in the input line") :
				  N("Please choose the port where your printer is connected to."))) .
				if_($::expert,
				 N(" (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...)."))), 
				 callbacks => {
				     complete => sub {
					 unless ($menuchoice ne "") {
					     $in->ask_warn('', N("You must choose/enter a printer/device!"));
					     return (1,0);
					 }
					 return 0;
				     },
				     changed => sub {
					 if ($oldmenuchoice ne $menuchoice) {
					     $device = $menuentries->{$menuchoice};
					     $oldmenuchoice = $menuchoice;
					 }
					 return 0;
				     }
				 } },
		 [
		  if_($::expert, { val => \$device }),
		  { val => \$menuchoice, list => \@menuentrieslist, 
		    not_edit => !$::expert, format => \&translate, sort => 0,
		    allow_empty_list => 1, type => 'list' },
		  if_(!$::expert && $do_auto_detect && $printer->{NEW}, 
		   { text => N("Manual configuration"), type => 'bool',
		     val => \$manualconf }),
		  ]
		 )) {
		return 0;
	    }
	    if ($device ne $menuentries->{$menuchoice}) {
		$menuchoice = "";
		$do_auto_detect = 0;
	    }
	    $printer->{MANUAL} = $manualconf ? 1 : undef;
	}
    }

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if (($printer->{SPOOLER} eq 'lpd' || $printer->{SPOOLER} eq 'lprng') &&
        !$::testing && $device =~ /^socket:/ && !files_exist('/usr/bin/nc')) {
        $in->do_pkgs->install('nc');
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common($printer, $in, $menuchoice, $device, $do_auto_detect,
		  @autodetected);

    1;
}

sub setup_lpd {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('setupLPD') if $::isInstall;
    my ($uri, $remotehost, $remotequeue);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^lpd:/) {
	$uri = $printer->{currentqueue}{connect};
	$uri =~ m!^\s*lpd://([^/]+)/([^/]+)/?\s*$!;
	$remotehost = $1;
	$remotequeue = $2;
    } else {
	$remotehost = "";
	$remotequeue = "lp";
    }

    return if !$in->ask_from(N("Remote lpd Printer Options"),
N("To use a remote lpd printer, you need to supply the hostname of the printer server and the printer name on that server."), [
{ label => N("Remote host name"), val => \$remotehost },
{ label => N("Remote printer name"), val => \$remotequeue } ],
complete => sub {
    if ($remotehost eq "") {
	$in->ask_warn('', N("Remote host name missing!"));
	return (1,0);
    }
    if ($remotequeue eq "") {
	$in->ask_warn('', N("Remote printer name missing!"));
	return (1,1);
    }
    return 0;
}
			      );
    #- make the DeviceURI from user input.
    $printer->{currentqueue}{connect} = "lpd://$remotehost/$remotequeue";

    #- LPD does not support filtered queues to a remote LPD server by itself
    #- It needs an additional program as "rlpr"
    if ($printer->{SPOOLER} eq 'lpd' && !$::testing && !files_exist('/usr/bin/rlpr')) {
        $in->do_pkgs->install('rlpr');
    }

    # Auto-detect printer model (works if host is an ethernet-connected
    # printer)
    my $modelinfo = printer::detect::getSNMPModel($remotehost);
    my $auto_hpoj;
    if (defined($modelinfo) &&
	$modelinfo->{MANUFACTURER} ne "" &&
	$modelinfo->{MODEL} ne "") {
        $in->ask_warn('', N("Detected model: %s %s",
                            $modelinfo->{MANUFACTURER}, $modelinfo->{MODEL}));
        $auto_hpoj = 1;
    } else {
	$auto_hpoj = 0;
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common($printer, $in,
		  "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		  $printer->{currentqueue}{connect}, $auto_hpoj,
                  ({port => $printer->{currentqueue}{connect},
                    val => $modelinfo }));

    1;
}

sub setup_smb {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('setupSMB') if $::isInstall;
    my ($uri, $smbuser, $smbpassword, $workgroup, $smbserver, $smbserverip, $smbshare);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^smb:/) {
	$uri = $printer->{currentqueue}{connect};
	$uri =~ m!^\s*smb://(.*)$!;
	my $parameters = $1;
	# Get the user's login and password from the URI
	if ($parameters =~ m!([^@]*)@([^@]+)!) {
	    my $login = $1;
	    $parameters = $2;
	    if ($login =~ m!([^:]*):([^:]*)!) {
		$smbuser = $1;
		$smbpassword = $2;
	    } else {
		$smbuser = $login;
		$smbpassword = "";
	    }
	} else {
	    $smbuser = "";
	    $smbpassword = "";
	}
	# Get the workgroup, server, and share name
	if ($parameters =~ m!([^/]*)/([^/]+)/([^/]+)$!) {
	    $workgroup = $1;
	    $smbserver = $2;
	    $smbshare = $3;
	} elsif ($parameters =~ m!([^/]+)/([^/]+)$!) {
	    $workgroup = "";
	    $smbserver = $1;
	    $smbshare = $2;
	} else {
	    die "The \"smb://\" URI must at least contain the server name and the share name!\n";
	}
	if (network::is_ip($smbserver)) {
	    $smbserverip = $smbserver;
	    $smbserver = "";
	}
    }

    my $autodetect = 0;
    my @autodetected;
    my $menuentries;
    my @menuentrieslist;
    my $menuchoice = "";
    my $oldmenuchoice = "";
    if ($printer->{AUTODETECT}) {
	$autodetect = 1;
	if (!$::testing && !files_exist('/usr/bin/smbclient')) {
	    $in->do_pkgs->install('samba-client');
	}
	my $_w = $in->wait_message(N("Printer auto-detection"), N("Scanning network..."));
	@autodetected = printer::detect::net_smb_detect();
	foreach my $p (@autodetected) {
	    my $menustr;
	    $p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!;
	    my $server = $1;
	    my $share = $2;
	    if ($p->{val}{DESCRIPTION}) {
		$menustr = $p->{val}{DESCRIPTION};
		$menustr .= N(", printer \"%s\" on server \"%s\"",
			      $share, $server);
	    } else {
		$menustr = N("Printer \"%s\" on server \"%s\"",
			     $share, $server);
	    }
	    $menuentries->{$menustr} = $p->{port};
	    if ($server eq $smbserver &&
		$share eq $smbshare) {
		$menuchoice = $menustr;
	    }
	}
	@menuentrieslist = sort {
	    $menuentries->{$a} cmp $menuentries->{$b};
	} keys(%{$menuentries});
	if ($printer->{configured}{$queue} &&
	    $printer->{currentqueue}{connect} =~ m/^smb:/ &&
	    $menuchoice eq "") {
	    my $menustr;
	    if ($printer->{currentqueue}{make}) {
		$menustr = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
		$menustr .= N(", printer \"%s\" on server \"%s\"",
			      $smbshare, $smbserver);
	    } else {
		$menustr = N("Printer \"%s\" on server \"%s\"",
			     $smbshare, $smbserver);
	    }
	    $menuentries->{$menustr} = "smb://$smbserver/$smbshare";
	    unshift(@menuentrieslist, $menustr);
	    $menuchoice = $menustr;
	}
	if ($#menuentrieslist < 0) {
	    $autodetect = 0;
	} elsif ($menuchoice eq "") {
	    $menuchoice = $menuentrieslist[0];
	    $menuentries->{$menuentrieslist[0]} =~
		m!^smb://([^/:]+)/([^/:]+)$!;
	    $smbserver = $1;
	    $smbshare = $2;
	}
	$oldmenuchoice = $menuchoice;
    }

    return 0 if !$in->ask_from(
	 N("SMB (Windows 9x/NT) Printer Options"),
	 N("To print to a SMB printer, you need to provide the SMB host name (Note! It may be different from its TCP/IP hostname!) and possibly the IP address of the print server, as well as the share name for the printer you wish to access and any applicable user name, password, and workgroup information.") .
	 ($autodetect ? N(" If the desired printer was auto-detected, simply choose it from the list and then add user name, password, and/or workgroup if needed.") : ""),
	 [ 
	  { label => N("SMB server host"), val => \$smbserver },
	  { label => N("SMB server IP"), val => \$smbserverip },
	  { label => N("Share name"), val => \$smbshare },
	  { label => N("User name"), val => \$smbuser },
	  { label => N("Password"), val => \$smbpassword, hidden => 1 },
	  { label => N("Workgroup"), val => \$workgroup },
	  if_($autodetect,
	   { label => N("Auto-detected"),
	     val => \$menuchoice, list => \@menuentrieslist, 
	     not_edit => 1, format => \&translate, sort => 0,
	     allow_empty_list => 1, type => 'combo' }) ],
	 complete => sub {
	     if (!network::is_ip($smbserverip) && $smbserverip ne "") {
		 $in->ask_warn('', N("IP address should be in format 1.2.3.4"));
		 return (1,1);
	     }
	     if ($smbserver eq "" && $smbserverip eq "") {
		 $in->ask_warn('', N("Either the server name or the server's IP must be given!"));
		 return (1,0);
	     }
	     if ($smbshare eq "") {
		 $in->ask_warn('', N("Samba share name missing!"));
		 return (1,2);
	     }
	     if ($smbpassword ne "") {
		 local $::isWizard = 0;
		 my $yes = $in->ask_yesorno(
		      N("SECURITY WARNING!"),
		      N("You are about to set up printing to a Windows account with password. Due to a fault in the architecture of the Samba client software the password is put in clear text into the command line of the Samba client used to transmit the print job to the Windows server. So it is possible for every user on this machine to display the password on the screen by issuing commands as \"ps auxwww\".

We recommend to make use of one of the following alternatives (in all cases you have to make sure that only machines from your local network have access to your Windows server, for example by means of a firewall):

Use a password-less account on your Windows server, as the \"GUEST\" account or a special account dedicated for printing. Do not remove the password protection from a personal account or the administrator account.

Set up your Windows server to make the printer available under the LPD protocol. Then set up printing from this machine with the \"%s\" connection type in Printerdrake.

", N("Printer on remote lpd server")) .
		      ($::expert ? 
		       N("Set up your Windows server to make the printer available under the IPP protocol and set up printing from this machine with the \"%s\" connection type in Printerdrake.

", N("Enter a printer device URI")) : "") .
N("Connect your printer to a Linux server and let your Windows machine(s) connect to it as a client.

Do you really want to continue setting up this printer as you are doing now?"), 0);
		 return 0 if $yes;
		 return (1,2);
	     }
	     return 0;
	 },
	 changed => sub {
	     return 0 if !$autodetect;
	     if ($oldmenuchoice ne $menuchoice) {
		 $menuentries->{$menuchoice} =~ m!^smb://([^/:]+)/([^/:]+)$!;
		 $smbserver = $1;
		 $smbshare = $2;
		 $oldmenuchoice = $menuchoice;
	     }
	     return 0;
	 }
	 );
    #- make the DeviceURI from, try to probe for available variable to
    #- build a suitable URI.
    $printer->{currentqueue}{connect} =
    join '', ("smb://", ($smbuser && ($smbuser . 
    ($smbpassword && ":$smbpassword") . '@')), ($workgroup && "$workgroup/"),
    ($smbserver || $smbserverip), "/$smbshare");

    if (!$::testing && !files_exist('/usr/bin/smbclient')) {
	$in->do_pkgs->install('samba-client');
    }
    $printer->{SPOOLER} eq 'cups' and printer::main::restart_queue($printer);
    1;
}

sub setup_ncp {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('setupNCP') if $::isInstall;
    my ($uri, $ncpuser, $ncppassword, $ncpserver, $ncpqueue);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^ncp:/) {
	$uri = $printer->{currentqueue}{connect};
	my $parameters = $uri =~ m!^\s*ncp://(.*)$!;
	# Get the user's login and password from the URI
	if ($parameters =~ m!([^@]*)@([^@]+)!) {
	    my $login = $1;
	    $parameters = $2;
	    if ($login =~ m!([^:]*):([^:]*)!) {
		$ncpuser = $1;
		$ncppassword = $2;
	    } else {
		$ncpuser = $login;
		$ncppassword = "";
	    }
	} else {
	    $ncpuser = "";
	    $ncppassword = "";
	}
	# Get the workgroup, server, and share name
	if ($parameters =~ m!([^/]+)/([^/]+)$!) {
	    $ncpserver = $1;
	    $ncpqueue = $2;
	} else {
	    die "The \"ncp://\" URI must at least contain the server name and the share name!\n";
	}
    }

    return 0 if !$in->ask_from(N("NetWare Printer Options"),
N("To print on a NetWare printer, you need to provide the NetWare print server name (Note! it may be different from its TCP/IP hostname!) as well as the print queue name for the printer you wish to access and any applicable user name and password."), [
{ label => N("Printer Server"), val => \$ncpserver },
{ label => N("Print Queue Name"), val => \$ncpqueue },
{ label => N("User name"), val => \$ncpuser },
{ label => N("Password"), val => \$ncppassword, hidden => 1 } ],
complete => sub {
    unless ($ncpserver ne "") {
	$in->ask_warn('', N("NCP server name missing!"));
	return (1,0);
    }
    unless ($ncpqueue ne "") {
	$in->ask_warn('', N("NCP queue name missing!"));
	return (1,1);
    }
    return 0;
}
					);
    # Generate the Foomatic URI
    $printer->{currentqueue}{connect} =
    join '', ("ncp://", ($ncpuser && ($ncpuser . 
    ($ncppassword && ":$ncppassword") . '@')),
    "$ncpserver/$ncpqueue");

	$in->do_pkgs->install('ncpfs') if !$::testing && !files_exist('/usr/bin/nprint');

    1;
}

sub setup_socket {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('setupSocket') if $::isInstall;

    my ($uri, $remotehost, $remoteport);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~  m!^(socket:|ptal:/hpjd:)!) {
	$uri = $printer->{currentqueue}{connect};
	if ($uri =~ m!^ptal:!) {
	    if ($uri =~ m!^ptal:/hpjd:([^/:]+):([0-9]+)/?\s*$!) {
		my $ptalport = $2 - 9100;
		($remotehost, $remoteport) = ($1, $ptalport);
	    } elsif ($uri =~ m!^ptal:/hpjd:([^/:]+)\s*$!) {
		($remotehost, $remoteport) = ($1, 9100);
	    }
	} else {
	    ($remotehost, $remoteport) =
		$uri =~ m!^\s*socket://([^/:]+):([0-9]+)/?\s*$!;
	}
    } else {
	$remotehost = "";
	$remoteport = "9100";
    }

    my $autodetect = 0;
    my @autodetected;
    my $menuentries;
    my @menuentrieslist;
    my $menuchoice = "";
    my $oldmenuchoice = "";
    if ($printer->{AUTODETECT}) {
	$autodetect = 1;
	my $_w = $in->wait_message(N("Printer auto-detection"), N("Scanning network..."));
	@autodetected = printer::detect::net_detect();
	foreach my $p (@autodetected) {
	    my $menustr;
	    $p->{port} =~ m!^socket://([^:]+):(\d+)$!;
	    my $host = $1;
	    my $port = $2;
	    if ($p->{val}{DESCRIPTION}) {
		$menustr = $p->{val}{DESCRIPTION};
		$menustr .= N(", host \"%s\", port %s",
			      $host, $port);
	    } else {
		$menustr = N("Host \"%s\", port %s", $host, $port);
	    }
	    $menuentries->{$menustr} = $p->{port};
	    if ($host eq $remotehost &&
		$host eq $remotehost) {
		$menuchoice = $menustr;
	    }
	}
	@menuentrieslist = sort { 
	    $menuentries->{$a} cmp $menuentries->{$b};
	} keys(%{$menuentries});
	if ($printer->{configured}{$queue} &&
	    $printer->{currentqueue}{connect} =~ m!^(socket:|ptal:/hpjd:)! &&
	    $menuchoice eq "") {
	    my $menustr;
	    if ($printer->{currentqueue}{make}) {
		$menustr = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
		$menustr .= N(", host \"%s\", port %s",
			      $remotehost, $remoteport);
	    } else {
		$menustr = N("Host \"%s\", port %s",
			      $remotehost, $remoteport);
	    }
	    $menuentries->{$menustr} = "socket://$remotehost:$remoteport";
	    unshift(@menuentrieslist, $menustr);
	    $menuchoice = $menustr;
	}
	if ($#menuentrieslist < 0) {
	    $autodetect = 0;
	} elsif ($menuchoice eq "") {
	    $menuchoice = $menuentrieslist[0];
	    $menuentries->{$menuentrieslist[0]} =~ m!^socket://([^:]+):(\d+)$!;
	    $remotehost = $1;
	    $remoteport = $2;
	}
	$oldmenuchoice = $menuchoice;
    }

    return 0 if !$in->ask_from_(
	 {
	     title => N("TCP/Socket Printer Options"),
	     messages => ($autodetect ?
			  N("Choose one of the auto-detected printers from the list or enter the hostname or IP and the optional port number (default is 9100) into the input fields.") :
			  N("To print to a TCP or socket printer, you need to provide the host name or IP of the printer and optionally the port number (default is 9100). On HP JetDirect servers the port number is usually 9100, on other servers it can vary. See the manual of your hardware.")),
		 callbacks => {
		 complete => sub {
		     unless ($remotehost ne "") {
			 $in->ask_warn('', N("Printer host name or IP missing!"));
			 return (1,0);
		     }
		     unless ($remoteport =~ /^[0-9]+$/) {
			 $in->ask_warn('', N("The port number should be an integer!"));
			 return (1,1);
		     }
		     return 0;
		 },
		 changed => sub {
		     return 0 if !$autodetect;
		     if ($oldmenuchoice ne $menuchoice) {
			 $menuentries->{$menuchoice} =~ m!^socket://([^:]+):(\d+)$!;
			 $remotehost = $1;
			 $remoteport = $2;
			 $oldmenuchoice = $menuchoice;
		     }
		     return 0;
		 }
	     }
	 },
	 [
	  { label => ($autodetect ? "" : N("Printer host name or IP")),
	    val => \$remotehost },
	  { label => ($autodetect ? "" : N("Port")), val => \$remoteport },
	  if_($autodetect,
	   { val => \$menuchoice, list => \@menuentrieslist, 
	     not_edit => 0, format => \&translate, sort => 0,
	     allow_empty_list => 1, type => 'list' })
	  ]
	 );
    
    #- make the Foomatic URI
    $printer->{currentqueue}{connect} = 
	join '', ("socket://$remotehost", $remoteport ? ":$remoteport" : ());

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if (($printer->{SPOOLER} eq 'lpd' || $printer->{SPOOLER} eq 'lprng') && 
        !$::testing && !files_exist('/usr/bin/nc')) {
        $in->do_pkgs->install('nc');
    }

    # Auto-detect printer model
    my $modelinfo;
    if ($printer->{AUTODETECT}) {
	$modelinfo = printer::detect::getSNMPModel($remotehost);
    }
    my $auto_hpoj;
    if (defined($modelinfo) &&
	$modelinfo->{MANUFACTURER} ne "" &&
	$modelinfo->{MODEL} ne "") {
        $auto_hpoj = 1;
    } else {
	$auto_hpoj = 0;
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common($printer, $in,
		  "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		  $printer->{currentqueue}{connect}, $auto_hpoj,
                  ({port => $printer->{currentqueue}{connect},
                    val => $modelinfo }));
    1;
}

sub setup_uri {
    my ($printer, $in, $upNetwork) = @_;

    $in->set_help('setupURI') if $::isInstall;
    return if !$in->ask_from(N("Printer Device URI"),
N("You can specify directly the URI to access the printer. The URI must fulfill either the CUPS or the Foomatic specifications. Note that not all URI types are supported by all the spoolers."), [
{ label => N("Printer Device URI"),
val => \$printer->{currentqueue}{connect},
list => [ $printer->{currentqueue}{connect},
	  "file:/",
	  "http://",
	  "ipp://",
	  "lpd://",
	  "smb://",
	  "ncp://",
	  "socket://",
	  "postpipe:\"\"",
	  ], not_edit => 0 }, ],
complete => sub {
    unless ($printer->{currentqueue}{connect} =~ /[^:]+:.+/) {
	$in->ask_warn('', N("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );

    # Non-local printer, check network and abort if no network available
    if ($printer->{currentqueue}{connect} !~ m!^(file|ptal):/! &&
        !check_network($printer, $in, $upNetwork, 0)) { 
        return 0;
    }
    # If the chosen protocol needs additional software, install it.

    # LPD does not support filtered queues to a remote LPD server by itself
    # It needs an additional program as "rlpr"
    elsif ($printer->{currentqueue}{connect} =~ /^lpd:/ &&
	$printer->{SPOOLER} eq 'lpd' && !$::testing && !files_exist('/usr/bin/rlpr')) {
        $in->do_pkgs->install('rlpr');
    } elsif ($printer->{currentqueue}{connect} =~ /^smb:/ &&
        !$::testing && !files_exist('/usr/bin/smbclient')) {
	$in->do_pkgs->install('samba-client');
    } elsif ($printer->{currentqueue}{connect} =~ /^ncp:/ &&
	!$::testing && !files_exist('/usr/bin/nprint')) {
	$in->do_pkgs->install('ncpfs');
    }
    #- LPD and LPRng need netcat ('nc') to access to socket printers
    elsif ($printer->{currentqueue}{connect} =~ /^socket:/ &&
	($printer->{SPOOLER} eq 'lpd' || $printer->{SPOOLER} eq 'lprng') &&
        !$::testing && !files_exist('/usr/bin/nc')) {
        $in->do_pkgs->install('nc');
    }

    if ($printer->{currentqueue}{connect} =~ m!^socket://([^:/]+)! ||
        $printer->{currentqueue}{connect} =~ m!^lpd://([^:/]+)! ||
        $printer->{currentqueue}{connect} =~ m!^http://([^:/]+)! ||
        $printer->{currentqueue}{connect} =~ m!^ipp://([^:/]+)!) {
	
	# Auto-detect printer model (works if host is an ethernet-connected
	# printer)
	my $remotehost = $1;
	my $modelinfo = printer::detect::getSNMPModel($remotehost);
        my $auto_hpoj;
        if (defined($modelinfo) &&
            $modelinfo->{MANUFACTURER} ne "" &&
	    $modelinfo->{MODEL} ne "") {
            $in->ask_warn('', N("Detected model: %s %s",
                                $modelinfo->{MANUFACTURER},
				$modelinfo->{MODEL}));
            $auto_hpoj = 1;
        } else {
	    $auto_hpoj = 0;
        }

        # Do configuration of multi-function devices and look up model name
        # in the printer database
        setup_common($printer, $in,
		      "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		      $printer->{currentqueue}{connect}, $auto_hpoj,
                      ({port => $printer->{currentqueue}{connect},
                        val => $modelinfo }));
    }

    1;
}

sub setup_postpipe {
    my ($printer, $in) = @_;

    $in->set_help('setupPostpipe') if $::isInstall;
    my $uri;
    my $commandline;
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^postpipe:/) {
	$uri = $printer->{currentqueue}{connect};
	$uri =~ m!^\s*postpipe:\"(.*)\"$!;
	$commandline = $1;
    } else {
	$commandline = "";
    }

    return if !$in->ask_from(N("Pipe into command"),
N("Here you can specify any arbitrary command line into which the job should be piped instead of being sent directly to a printer."), [
{ label => N("Command line"),
val => \$commandline }, ],
complete => sub {
    unless ($commandline ne "") {
	$in->ask_warn('', N("A command line must be entered!"));
	return (1,0);
    }
    return 0;
}
);

    #- make the Foomatic URI
    $printer->{currentqueue}{connect} = "postpipe:$commandline";
    
    1;
}

sub setup_common {

    my ($printer, $in, $makemodel, $device, $do_auto_detect, @autodetected) = @_;

    #- Check whether the printer is an HP multi-function device and 
    #- configure HPOJ if it is one

    my $ptaldevice = "";
    my $isHPOJ = 0;
    if ($device =~ /^\/dev\// || $device =~ /^socket:\/\//) {
	# Ask user whether he has a multi-function device when he didn't
	# do auto-detection or when auto-detection failed
	my $searchunknown = N("Unknown model");
	if (!$do_auto_detect ||
	    $makemodel =~ /$searchunknown/i ||
	    $makemodel =~ /^\s*$/) {
	    local $::isWizard = 0;
	    $isHPOJ = $in->ask_yesorno(N("Add a new printer"),
				       N("Is your printer a multi-function device from HP or Sony (OfficeJet, PSC, LaserJet 1100/1200/1220/3200/3300 with scanner, Sony IJP-V100), an HP PhotoSmart or an HP LaserJet 2200?"), 0);
	}
	if ($makemodel =~ /HP\s+(OfficeJet|PSC|PhotoSmart|LaserJet\s+(1200|1220|2200|3200|33.0))/i ||
	    $makemodel =~ /Sony\s+IJP[\s\-]+V[\s\-]+100/i ||
	    $isHPOJ) {
	    # Install HPOJ package
	    if (!$::testing &&
		!files_exist(qw(/usr/sbin/ptal-mlcd
					   /usr/sbin/ptal-init
					   /usr/bin/xojpanel))) {
		my $_w = $in->wait_message(N("Printerdrake"),
					  N("Installing HPOJ package..."));
		$in->do_pkgs->install('hpoj', 'xojpanel');
	    }
	    # Configure and start HPOJ
	    my $_w = $in->wait_message(
		 N("Printerdrake"),
		 N("Checking device and configuring HPOJ..."));
	    $ptaldevice = printer::main::configure_hpoj($device, @autodetected);
	    
	    if ($ptaldevice) {
		# Configure scanning with SANE on the MF device
		if ($makemodel !~ /HP\s+PhotoSmart/i &&
		    $makemodel !~ /HP\s+LaserJet\s+2200/i) {
		    # Install SANE
		    if (!$::testing &&
			!files_exist(qw(/usr/bin/scanimage
						   /usr/bin/xscanimage
						   /usr/bin/xsane
						   /etc/sane.d/dll.conf
						   /usr/lib/libsane-hpoj.so.1),
						if_(files_exist('/usr/bin/gimp'), 
						    '/usr/bin/xsane-gimp'))) {
			my $_w = $in->wait_message(
			     N("Printerdrake"),
			     N("Installing SANE packages..."));
			$in->do_pkgs->install('sane-backends',
					      'sane-frontends',
					      'xsane', 'libsane-hpoj0',
					      if_($in->do_pkgs->is_installed('gimp'), 'xsane-gimp'));
		    }
		    # Configure the HPOJ SANE backend
		    printer::main::config_sane();
		}
		# Configure photo card access with mtools and MToolsFM
		if (($makemodel =~ /HP\s+PhotoSmart/i ||
		     $makemodel =~ /HP\s+PSC\s*9[05]0/i ||
		     $makemodel =~ /HP\s+PSC\s*22\d\d/i ||
		     $makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i) &&
		    $makemodel !~ /HP\s+PhotoSmart\s+7150/i) {
		    # Install mtools and MToolsFM
		    if (!$::testing &&
			!files_exist(qw(/usr/bin/mdir
						  /usr/bin/mcopy
						  /usr/bin/MToolsFM
						  ))) {
			my $_w = $in->wait_message(
			     N("Printerdrake"),
			     N("Installing mtools packages..."));
			$in->do_pkgs->install('mtools', 'mtoolsfm');
		    }
		    # Configure mtools/MToolsFM for photo card access
		    printer::main::config_photocard();
		}
		
		my $text = "";
		# Inform user about how to scan with his MF device
		$text = scanner_help($makemodel, "ptal:/$ptaldevice");
		if ($text) {
		    $in->ask_warn(
			 N("Scanning on your HP multi-function device"),
			 $text);
		}
		# Inform user about how to access photo cards with his MF
		# device
		$text = photocard_help($makemodel, "ptal:/$ptaldevice");
		if ($text) {
		    $in->ask_warn(N("Photo memory card access on your HP multi-function device"),
				  $text);
		}
		# make the DeviceURI from $ptaldevice.
		$printer->{currentqueue}{connect} = "ptal:/" . $ptaldevice;
	    } else {
		# make the DeviceURI from $device.
		$printer->{currentqueue}{connect} = $device;
	    }
	} else {
	    # make the DeviceURI from $device.
	    $printer->{currentqueue}{connect} = $device;
	}
    } else {
	# make the DeviceURI from $device.
	$printer->{currentqueue}{connect} = $device;
    }

    if ($printer->{currentqueue}{connect} !~ /:/) {
	$printer->{currentqueue}{connect} =
	    "file:" . $printer->{currentqueue}{connect};
    }

    #- if CUPS is the spooler, make sure that CUPS knows the device
    if ($printer->{SPOOLER} eq "cups" &&
	$device !~ /^lpd:/ &&
	$device !~ /^smb:/ &&
	$device !~ /^socket:/ &&
	$device !~ /^http:/ &&
	$device !~ /^ipp:/) {
	my $_w = $in->wait_message(N("Printerdrake"), N("Making printer port available for CUPS..."));
	printer::main::assure_device_is_available_for_cups($ptaldevice || $device);
    }

    #- Read the printer driver database if necessary
    if ((keys %printer::main::thedb) == 0) {
	my $_w = $in->wait_message(N("Printerdrake"), N("Reading printer database..."));
        printer::main::read_printer_db($printer->{SPOOLER});
    }

    #- Search the database entry which matches the detected printer best
    my $descr = "";
    foreach (@autodetected) {
	$device eq $_->{port} or next;
	if ($_->{val}{MANUFACTURER} && $_->{val}{MODEL}) {
	    $descr = "$_->{val}{MANUFACTURER}|$_->{val}{MODEL}";
	} else {
	    $descr = $_->{val}{DESCRIPTION};
	    $descr =~ s/ /\|/;
	}
	# Clean up the description from noise which makes the best match
	# difficult
	$descr =~ s/Seiko\s+Epson/Epson/;
	$descr =~ s/\s+Inc\.//;
	$descr =~ s/\s+Corp\.//;
	$descr =~ s/\s+SA\.//;
	$descr =~ s/\s+S\.\s*A\.//;
	$descr =~ s/\s+Ltd\.//;
	$descr =~ s/\s+International//;
	$descr =~ s/\s+Int\.//;
	$descr =~ s/\s+[Ss]eries//;
	$descr =~ s/\s+\(?[Pp]rinter\)?$//;
	$printer->{DBENTRY} = "";
	# Try to find an exact match, check both whether the detected
	# make|model is in the make|model of the database entry and vice versa
	# If there is more than one matching database entry, the longest match
	# counts.
	my $matchlength = 0;
	foreach my $entry (keys %printer::main::thedb) {
	    my $dbmakemodel;
	    if ($::expert) {
		$entry =~ m/^(.*)\|[^\|]*$/;
		$dbmakemodel = $1;
	    } else {
		$dbmakemodel = $entry;
	    }
	    next unless $dbmakemodel;
	    $dbmakemodel =~ s/\|/\\\|/;
	    my $searchterm = $descr;
	    $searchterm =~ s/\|/\\\|/;
	    my $lsearchterm = length($searchterm);
	    if ($lsearchterm > $matchlength &&
		$entry =~ m!$searchterm!i) {
		$matchlength = $lsearchterm;
		$printer->{DBENTRY} = $entry;
	    }
	    my $ldbmakemodel = length($dbmakemodel);
	    if ($ldbmakemodel > $matchlength &&
		$descr =~ m!$dbmakemodel!i) {
		$matchlength = $ldbmakemodel;
		$printer->{DBENTRY} = $entry;
	    }
	}
     $printer->{DBENTRY} ||= bestMatchSentence($descr, keys %printer::main::thedb);
        # If the manufacturer was not guessed correctly, discard the
        # guess.
        $printer->{DBENTRY} =~ /^([^\|]+)\|/;
        my $guessedmake = lc($1);
        if ($descr !~ /$guessedmake/i &&
            ($guessedmake ne "hp" ||
             $descr !~ /Hewlett[\s-]+Packard/i))
            { $printer->{DBENTRY} = "" };
    }

    #- Pre-fill the "Description" field with the printer's model name
    if (!$printer->{currentqueue}{desc} && $descr) {
	$printer->{currentqueue}{desc} = $descr;
	$printer->{currentqueue}{desc} =~ s/\|/ /g;
    }

    #- When we have chosen a printer here, the question whether the
    #- automatically chosen model from the database is correct, should
    #- have "This model is correct" as default answer
    delete($printer->{MANUALMODEL});

    1;
}

sub choose_printer_name {
    my ($printer, $in) = @_;
    # Name, description, location
    $in->set_help('setupPrinterName') if $::isInstall;
    my $default = $printer->{currentqueue}{queue};
    $in->ask_from_(
	 { title => N("Enter Printer Name and Comments"),
	   #cancel => !$printer->{configured}{$queue} ? '' : N("Remove queue"),
	   callbacks => { complete => sub {
	       unless ($printer->{currentqueue}{queue} =~ /^\w+$/) {
		   $in->ask_warn('', N("Name of printer should contain only letters, numbers and the underscore"));
		   return (1,0);
	       }
	       local $::isWizard = 0;
	       if ($printer->{configured}{$printer->{currentqueue}{queue}}
		   && $printer->{currentqueue}{queue} ne $default && 
		   !$in->ask_yesorno('', N("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
					    $printer->{currentqueue}{queue}),
				      0)) {
		   return (1,0); # Let the user correct the name
	       }
	       return 0;
	   },
		      },
	   messages =>
N("Every printer needs a name (for example \"printer\"). The Description and Location fields do not need to be filled in. They are comments for the users.") }, 
	 [ { label => N("Name of printer"), val => \$printer->{currentqueue}{queue} },
	   { label => N("Description"), val => \$printer->{currentqueue}{desc} },
	   { label => N("Location"), val => \$printer->{currentqueue}{loc} },
	 ]) or return 0;

    $printer->{QUEUE} = $printer->{currentqueue}{queue};
    1;
}

sub get_db_entry {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::main::thedb) == 0) {
	my $_w = $in->wait_message(N("Printerdrake"),
				  N("Reading printer database..."));
        printer::main::read_printer_db($printer->{SPOOLER});
    }
    my $_w = $in->wait_message(N("Printerdrake"),
			      N("Preparing printer database..."));
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue}) {
	# The queue was already configured
	if ($printer->{configured}{$queue}{queuedata}{foomatic}) {
	    # The queue was configured with Foomatic
	    my $driverstr;
	    if ($printer->{configured}{$queue}{queuedata}{driver} eq "Postscript") {
		$driverstr = "PostScript";
	    } else {
		$driverstr = "GhostScript + $printer->{configured}{$queue}{queuedata}{driver}";
	    }
	    my $make = uc($printer->{configured}{$queue}{queuedata}{make});
	    my $model =	$printer->{configured}{$queue}{queuedata}{model};
	    if ($::expert) {
		$printer->{DBENTRY} = "$make|$model|$driverstr";
		# database key contains the "(recommended)" for the
		# recommended driver, so add it if necessary
		if (!member($printer->{DBENTRY}, keys(%printer::main::thedb))) {
		    $printer->{DBENTRY} .= " (recommended)";
		}
	    } else {
		$printer->{DBENTRY} = "$make|$model";
	    }
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} elsif ($printer->{SPOOLER} eq "cups" && $::expert &&
		 $printer->{configured}{$queue}{queuedata}{ppd}) {
	    # Do we have a native CUPS driver or a PostScript PPD file?
	    $printer->{DBENTRY} = printer::main::get_descr_from_ppd($printer) || $printer->{DBENTRY};
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} else {
	    # Point the list cursor at least to manufacturer and model of the
	    # printer
	    $printer->{DBENTRY} = "";
	    my $make = uc($printer->{configured}{$queue}{queuedata}{make});
	    my $model = $printer->{configured}{$queue}{queuedata}{model};
	    foreach my $key (keys %printer::main::thedb) {
		if ($::expert && $key =~ /^$make\|$model\|.*\(recommended\)$/ ||
		    !$::expert && $key =~ /^$make\|$model$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	    if ($printer->{DBENTRY} eq "") {
		# Exact match of make and model did not work, try to clean
		# up the model name
		$model =~ s/PS//;
		$model =~ s/PostScript//;
		$model =~ s/Series//;
		foreach my $key (keys %printer::main::thedb) {
		    if ($::expert && $key =~ /^$make\|$model\|.*\(recommended\)$/ ||
			!$::expert && $key =~ /^$make\|$model$/) {
			$printer->{DBENTRY} = $key;
		    }
		}
	    }
	    if ($printer->{DBENTRY} eq "" && $make ne "") {
		# Exact match with cleaned-up model did not work, try a best match
		my $matchstr = "$make|$model";
		$printer->{DBENTRY} = bestMatchSentence($matchstr, keys %printer::main::thedb);
		# If the manufacturer was not guessed correctly, discard the
		# guess.
		$printer->{DBENTRY} =~ /^([^\|]+)\|/;
		my $guessedmake = lc($1);
		if ($matchstr !~ /$guessedmake/i &&
		    ($guessedmake ne "hp" ||
		     $matchstr !~ /Hewlett[\s-]+Packard/i))
		{ $printer->{DBENTRY} = "" };
	    }
	    # Set the OLD_CHOICE to a non-existing value
	    $printer->{OLD_CHOICE} = "XXX";
	}
    } else {
	if ($::expert && $printer->{DBENTRY} !~ /(recommended)/) {
	    my ($make, $model) = $printer->{DBENTRY} =~ /^([^\|]+)\|([^\|]+)\|/;
	    foreach my $key (keys %printer::main::thedb) {
		if ($key =~ /^$make\|$model\|.*\(recommended\)$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
	$printer->{OLD_CHOICE} = $printer->{DBENTRY};
    }
}

sub is_model_correct {
    my ($printer, $in) = @_;
    $in->set_help('chooseModel') if $::isInstall;
    my $dbentry = $printer->{DBENTRY};
    if (!$dbentry) {
	# If printerdrake could not determine the model, omit this dialog and
	# let the user choose manually.
	$printer->{MANUALMODEL} = 1;
	return 1;
    }
    $dbentry =~ s/\|/ /g;
    my $res = $in->ask_from_list_(
	     N("Your printer model"),
	     N("Printerdrake has compared the model name resulting from the printer auto-detection with the models listed in its printer database to find the best match. This choice can be wrong, especially when your printer is not listed at all in the database. So check whether the choice is correct and click \"The model is correct\" if so and if not, click \"Select model manually\" so that you can choose your printer model manually on the next screen.

For your printer Printerdrake has found:

%s", $dbentry),
	     [N("The model is correct"),
	      N("Select model manually")],
	     ($printer->{MANUALMODEL} ? N("Select model manually") : 
	      N("The model is correct")));
    return 0 if !$res;
    $printer->{MANUALMODEL} = $res eq N("Select model manually");
    1;
}

sub choose_model {
    my ($printer, $in) = @_;
    $in->set_help('chooseModel') if $::isInstall;
    #- Read the printer driver database if necessary
    if ((keys %printer::main::thedb) == 0) {
	my $_w = $in->wait_message(N("Printerdrake"),
				  N("Reading printer database..."));
        printer::main::read_printer_db($printer->{SPOOLER});
    }
    if (!member($printer->{DBENTRY}, keys(%printer::main::thedb))) {
	$printer->{DBENTRY} = N("Raw printer (No driver)");
    }
    # Choose the printer/driver from the list
    return($printer->{DBENTRY} = $in->ask_from_treelist(N("Printer model selection"),
							 N("Which printer model do you have?") .
							 N("

Please check whether Printerdrake did the auto-detection of your printer model correctly. Search the correct model in the list when the cursor is standing on a wrong model or on \"Raw printer\".") . " " .
N("If your printer is not listed, choose a compatible (see printer manual) or a similar one."), '|',
							 [ keys %printer::main::thedb ], $printer->{DBENTRY}));

}

my %lexmarkinkjet_options = (
                             'file:/dev/lp0' => " -o Port=ParPort1",
                             'file:/dev/lp1' => " -o Port=ParPort2",
                             'file:/dev/lp2' => " -o Port=ParPort3",
                             'file:/dev/usb/lp0' => " -o Port=USB1",
                             'file:/dev/usb/lp1' => " -o Port=USB2",
                             'file:/dev/usb/lp2' => " -o Port=USB3",
                             );

sub get_printer_info {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    #if ((keys %printer::main::thedb) == 0) {
    #    my $_w = $in->wait_message(N("Printerdrake"), 
    #                              N("Reading printer database..."));
    #    printer::main::read_printer_db($printer->{SPOOLER});
    #}
    my $queue = $printer->{OLD_QUEUE};
    my $oldchoice = $printer->{OLD_CHOICE};
    my $newdriver = 0;
    if (!$printer->{configured}{$queue} ||      # New queue  or
	($oldchoice && $printer->{DBENTRY} && # make/model/driver changed
	 ($oldchoice ne $printer->{DBENTRY} ||
	  $printer->{currentqueue}{driver} ne 
	   $printer::main::thedb{$printer->{DBENTRY}}{driver}))) {
	delete($printer->{currentqueue}{printer});
	delete($printer->{currentqueue}{ppd});
	$printer->{currentqueue}{foomatic} = 0;
	# Read info from printer database
	foreach (qw(printer ppd driver make model)) { #- copy some parameter, shorter that way...
	    $printer->{currentqueue}{$_} = $printer::main::thedb{$printer->{DBENTRY}}{$_};
	}
	$newdriver = 1;
    }
    # Use the "printer" and not the "foomatic" field to identify a Foomatic
    # queue because in a new queue "foomatic" is not set yet.
    if ($printer->{currentqueue}{printer} || # We have a Foomatic queue
	$printer->{currentqueue}{ppd}) { # We have a CUPS+PPD queue
	if ($printer->{currentqueue}{printer}) { # Foomatic queue?
	    # In case of a new queue "foomatic" was not set yet
	    $printer->{currentqueue}{foomatic} = 1;
	    # Now get the options for this printer/driver combo
	    if ($printer->{configured}{$queue} && $printer->{configured}{$queue}{queuedata}{foomatic}) {
		# The queue was already configured with Foomatic ...
		if (!$newdriver) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = $printer->{configured}{$queue}{args};
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::main::read_foomatic_options($printer);
		}
	    } else {
		# The queue was not configured with Foomatic before
		# Set some special options
		$printer->{SPECIAL_OPTIONS} = '';
		# Default page size depending on the country/language
		# (US/Canada -> Letter, Others -> A4)
		my $pagesize;
		if ($printer->{PAPERSIZE}) {
		    $printer->{SPECIAL_OPTIONS} .= 
			" -o PageSize=$printer->{PAPERSIZE}";
		} elsif (($pagesize = $in->{lang}) ||
			 ($pagesize = $ENV{LC_PAPER}) ||
			 ($pagesize = $ENV{LANG}) ||
			 ($pagesize = $ENV{LANGUAGE}) ||
			 ($pagesize = $ENV{LC_ALL})) {
		    if ($pagesize =~ /^en_CA/ ||
			$pagesize =~ /^fr_CA/ || 
			$pagesize =~ /^en_US/) {
			$pagesize = "Letter";
		    } else {
			$pagesize = "A4";
		    }
		    $printer->{SPECIAL_OPTIONS} .= 
			" -o PageSize=$pagesize";
		}
		# oki4w driver -> OKI winprinter which needs the
		# oki4daemon to work
		if ($printer->{currentqueue}{driver} eq 'oki4w') {
		    if ($printer->{currentqueue}{connect} ne 
			'file:/dev/lp0') {
			$in->ask_warn(N("OKI winprinter configuration"),
				      N("You are configuring an OKI laser winprinter. These printers\nuse a very special communication protocol and therefore they work only when connected to the first parallel port. When your printer is connected to another port or to a print server box please connect the printer to the first parallel port before you print a test page. Otherwise the printer will not work. Your connection type setting will be ignored by the driver."));
		    }
		    $printer->{currentqueue}{connect} = 'file:/dev/null';
		    # Start the oki4daemon
		    services::start_service_on_boot('oki4daemon');
		    printer::services::start('oki4daemon');
		    # Set permissions

              my $h = {
                  cups => sub { set_permissions('/dev/oki4drv', '660', 'lp', 'sys') },
                  pdq  => sub { set_permissions('/dev/oki4drv', '666') }
              };
              my $s = $h->{$printer->{SPOOLER}} ||= sub { set_permissions('/dev/oki4drv', '660', 'lp', 'lp') };
              &$s;
		} elsif ($printer->{currentqueue}{driver} eq 'lexmarkinkjet') {
		    # Set "Port" option
              my $opt = $lexmarkinkjet_options{$printer->{currentqueue}{connect}};
              if ($opt) {
                  $printer->{SPECIAL_OPTIONS} .= $opt;
		    } else {
			$in->ask_warn(N("Lexmark inkjet configuration"),
				      N("The inkjet printer drivers provided by Lexmark only support local printers, no printers on remote machines or print server boxes. Please connect your printer to a local port or configure it on the machine where it is connected to."));
			return 0;
		    }
		    # Set device permissions
		    $printer->{currentqueue}{connect} =~ /^\s*file:(\S*)\s*$/;
		    if ($printer->{SPOOLER} eq 'cups') {
			set_permissions($1, '660', 'lp', 'sys');
		    } elsif ($printer->{SPOOLER} eq 'pdq') {
			set_permissions($1, '666');
		    } else {
			set_permissions($1, '660', 'lp', 'lp');
		    }
		    # This is needed to have the device not blocked by the
		    # spooler backend.
		    $printer->{currentqueue}{connect} = 'file:/dev/null';
		    #install packages
		    my $drivertype = $printer->{currentqueue}{model};
		    if ($drivertype eq 'Z22') { $drivertype = 'Z32' }
		    if ($drivertype eq 'Z23') { $drivertype = 'Z33' }
		    $drivertype = lc($drivertype);
		    if (!files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			eval { $in->do_pkgs->install("lexmark-drivers-$drivertype") };
		    }
		    if (!files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			# Driver installation failed, probably we do not have
			# the commercial CDs
			$in->ask_warn(N("Lexmark inkjet configuration"),
				      N("To be able to print with your Lexmark inkjet and this configuration, you need the inkjet printer drivers provided by Lexmark (http://www.lexmark.com/). Click on the \"Drivers\" link. Then choose your model and afterwards \"Linux\" as operating system. The drivers come as RPM packages or shell scripts with interactive graphical installation. You do not need to do this configuration by the graphical frontends. Cancel directly after the license agreement. Then print printhead alignment pages with \"lexmarkmaintain\" and adjust the head alignment settings with this program."));
		    }
		} elsif ($printer->{currentqueue}{driver} eq 'pbmtozjs') {
		    $in->ask_warn(N("GDI Laser Printer using the Zenographics ZJ-Stream Format"),
				  N("Your printer belongs to the group of GDI laser printers (winprinters) sold by different manufacturers which uses the Zenographics ZJ-stream raster format for the data sent to the printer. The driver for these printers is still in a very early development stage and so it will perhaps not always work properly. Especially it is possible that the printer only works when you choose the A4 paper size.

Some of these printers, as the HP LaserJet 1000, for which this driver was originally created, need their firmware to be uploaded to them after they are turned on. In the case of the HP LaserJet 1000 you have to search the printer's Windows driver CD or your Windows partition for the file \"sihp1000.img\" and upload the file to the printer with one of the following commands:

     lpr -o raw sihp1000.img
     cat sihp1000.img > /dev/usb/lp0

The first command can be given by any normal user, the second must be given as root. After having done so you can print normally.
"));
		}
		$printer->{ARGS} = printer::main::read_foomatic_options($printer);
		delete($printer->{SPECIAL_OPTIONS});
	    }
	} elsif ($printer->{currentqueue}{ppd}) { # CUPS+PPD queue?
	    # If we had a Foomatic queue before, unmark the flag and initialize
	    # the "printer" and "driver" fields
	    $printer->{currentqueue}{foomatic} = 0;
	    $printer->{currentqueue}{printer} = undef;
	    $printer->{currentqueue}{driver} = "CUPS/PPD";
	    # Now get the options from this PPD file
	    if ($printer->{configured}{$queue}) {
		# The queue was already configured
		if (!$printer->{DBENTRY} || !$oldchoice ||
		    $printer->{DBENTRY} eq $oldchoice) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = printer::main::read_cups_options($queue);
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::main::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
		}
	    } else {
		# The queue was not configured before
		$printer->{ARGS} = printer::main::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
	    }
	}
    }
    1;
}

sub setup_options {
    my ($printer, $in) = @_;
    my @simple_options = 
	("PageSize",        # Media properties
	 "MediaType",
	 "Form",
	 "InputSlot",       # Trays
	 "Tray",
	 "OutBin",
	 "OutputBin",
	 "FaceUp",
	 "FaceDown",
	 "Collate",
	 "Manual",
	 "ManualFeed",
	 "Manualfeed",
	 "ManualFeeder",
	 "Feeder",
	 "Duplex",          # Double-sided printing
	 "Binding",
	 "Tumble",
	 "DoubleSided",
	 "Resolution",      # Resolution/Quality
	 "GSResolution",
	 "JCLResolution",
	 "Quality",
	 "PrintQuality",
	 "PrintoutQuality",
	 "QualityType",
	 "ImageType",
	 "stpImageType",
	 "InkType",         # Colour/Gray/BW, 4-ink/6-ink
	 "stpInkType",
	 "Mode",
	 "OutputMode",
	 "OutputType",
	 "ColorMode",
	 "ColorModel",
	 "PrintingMode",
	 "Monochrome",
	 "BlackOnly",
	 "Grayscale",
	 "GrayScale",
	 "Colour",
	 "Color",
	 "Gamma",           # Lighter/Darker
	 "GammaCorrection",
	 "GammaGeneral",
	 "MasterGamma",
	 "StpGamma",
	 "stpGamma",
	 "EconoMode",       # Ink/Toner saving
	 "Economode",
	 "TonerSaving",
	 "JCLEconomode",
	 "HPNup",           # Other useful options
	 "InstalledMemory", # Laser printer hardware config
	 "Option1",
	 "Option2",
	 "Option3",
	 "Option4",
	 "Option5",
	 "Option6",
	 "Option7",
	 "Option8",
	 "Option9",
	 "Option10",
	 "Option11",
	 "Option12",
	 "Option13",
	 "Option14",
	 "Option15",
	 "Option16",
	 "Option17",
	 "Option18",
	 "Option19",
	 "Option20",
	 "Option21",
	 "Option22",
	 "Option23",
	 "Option24",
	 "Option25",
	 "Option26",
	 "Option27",
	 "Option28",
	 "Option29",
	 "Option30"
	 );
    $in->set_help('setupOptions') if $::isInstall;
    if ($printer->{currentqueue}{printer} || # We have a Foomatic queue
	$printer->{currentqueue}{ppd}) { # We have a CUPS+PPD queue
	# Set up the widgets for the option dialog
	my @widgets;
	my @userinputs;
	my @choicelists;
	my @shortchoicelists;
	my $i;
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    my $optshortdefault = $printer->{ARGS}[$i]{default};
	    if ($printer->{ARGS}[$i]{type} eq 'enum') {
		# enumerated option
		push(@choicelists, []);
		push(@shortchoicelists, []);
		foreach my $choice (@{$printer->{ARGS}[$i]{vals}}) {
		    push(@{$choicelists[$i]}, $choice->{comment});
		    push(@{$shortchoicelists[$i]}, $choice->{value});
		    if ($choice->{value} eq $optshortdefault) {
			push(@userinputs, $choice->{comment});
		    }
		}
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment}, 
		       val => \$userinputs[$i], 
		       not_edit => 1,
		       list => \@{$choicelists[$i]},
		       advanced => !member($printer->{ARGS}[$i]{name},
					   @simple_options) });
	    } elsif ($printer->{ARGS}[$i]{type} eq 'bool') {
		# boolean option
		push(@choicelists, [$printer->{ARGS}[$i]{name}, 
				    $printer->{ARGS}[$i]{name_false}]);
		push(@shortchoicelists, []);
		push(@userinputs, $choicelists[$i][1-$optshortdefault]);
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment},
		       val => \$userinputs[$i],
		       not_edit => 1,
		       list => \@{$choicelists[$i]},
		       advanced => !member($printer->{ARGS}[$i]{name},
					   @simple_options) });
	    } else {
		# numerical option
		push(@choicelists, []);
		push(@shortchoicelists, []);
		push(@userinputs, $optshortdefault);
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment} . 
			   " ($printer->{ARGS}[$i]{min}... " .
			       "$printer->{ARGS}[$i]{max})",
			   #type => 'range',
			   #min => $printer->{ARGS}[$i]{min},
			   #max => $printer->{ARGS}[$i]{max},
			   val => \$userinputs[$i],
			   advanced => !member($printer->{ARGS}[$i]{name},
					       @simple_options) });
	    }
	}
	# Show the options dialog. The call-back function does a
	# range check of the numerical options.
	my $windowtitle = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
	if ($::expert) {
	    my $driver;
	    if ($driver = $printer->{currentqueue}{driver}) {
		if ($printer->{currentqueue}{foomatic}) {
		    if ($driver eq 'Postscript') {
			$driver = "PostScript";
		    } else {
			$driver = "GhostScript + $driver";
		    }
		} elsif ($printer->{currentqueue}{ppd}) {
		    if ($printer->{DBENTRY}) {
			$printer->{DBENTRY} =~ /^[^\|]*\|[^\|]*\|(.*)$/;
			$driver = $1;
		    } else {
			$driver = printer::main::get_descr_from_ppd($printer);
			if ($driver =~ /^[^\|]*\|[^\|]*$/) { # No driver info
			    $driver = "CUPS/PPD";
			} else {
			    $driver =~ /^[^\|]*\|[^\|]*\|(.*)$/;
			    $driver = $1;
			}
		    }
		}
	    } 
	    if ($driver) {
		$windowtitle .= ", $driver";
	    }
	}
	# Do not show the options setup dialog when installing a new printer
	# in recommended mode without "Manual configuration" turned on.
	if (!$printer->{NEW} or $::expert or $printer->{MANUAL}) {
	    return 0 if !$in->ask_from(
		 $windowtitle,
		 N("Printer default settings

You should make sure that the page size and the ink type/printing mode (if available) and also the hardware configuration of laser printers (memory, duplex unit, extra trays) are set correctly. Note that with a very high printout quality/resolution printing can get substantially slower."),
		 \@widgets,
		 complete => sub {
		     my $i;
		     for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
			 if ($printer->{ARGS}[$i]{type} eq 'int' || $printer->{ARGS}[$i]{type} eq 'float') {
			     if ($printer->{ARGS}[$i]{type} eq 'int' && $userinputs[$i] !~ /^[\-\+]?[0-9]+$/) {
				 $in->ask_warn('', N("Option %s must be an integer number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     if ($printer->{ARGS}[$i]{type} eq 'float' && $userinputs[$i] !~ /^[\-\+]?[0-9\.]+$/) {
				 $in->ask_warn('', N("Option %s must be a number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     if ($userinputs[$i] < $printer->{ARGS}[$i]{min} || $userinputs[$i] > $printer->{ARGS}[$i]{max}) {
				 $in->ask_warn('', N("Option %s out of range!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			 }
		     }
		     return 0;
		 });
	}
	# Read out the user's choices and generate the appropriate command
	# line arguments
	@{$printer->{currentqueue}{options}} = ();
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    push(@{$printer->{currentqueue}{options}}, "-o");
	    if ($printer->{ARGS}[$i]{type} eq 'enum') {
		# enumerated option
		my $j;
		for ($j = 0; $j <= $#{$choicelists[$i]}; $j++) {
		    if ($choicelists[$i][$j] eq $userinputs[$i]) {
			push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{name} . "=" . $shortchoicelists[$i][$j]);
		    }
		}
	    } elsif ($printer->{ARGS}[$i]{type} eq 'bool') {
		# boolean option
		push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{name} . "=" .
		     ($choicelists[$i][0] eq $userinputs[$i] ? "1" : "0"));
	    } else {
		# numerical option
		push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{name} . "=" . $userinputs[$i]);
	    }
	}
    }
    1;
}

sub setasdefault {
    my ($printer, $in) = @_;
    $in->set_help('setupAsDefault') if $::isInstall;
    if ($printer->{DEFAULT} eq '' || # We have no default printer,
	                               # so set the current one as default
	$in->ask_yesorno('', N("Do you want to set this printer (\"%s\")\nas the default printer?", $printer->{QUEUE}), 0)) { # Ask the user
	$printer->{DEFAULT} = $printer->{QUEUE};
        printer::default::set_printer($printer);
    }
}
	
sub print_testpages {
    my ($printer, $in, $upNetwork) = @_;
    $in->set_help('printTestPages') if $::isInstall;
    # print test pages
    my $standard = 1;
    my $altletter = 0;
    my $alta4 = 0;
    my $photo = 0;
    my $ascii = 0;
    my $res2 = 0;
    my $oldstandard = 1;
    my $oldaltletter = 0;
    my $oldalta4 = 0;
    my $oldphoto = 0;
    my $oldascii = 0;
    my $oldres2 = 0;
    my $res1 = $in->ask_from_(
	 { title => N("Test pages"),
	   messages => N("Please select the test pages you want to print.
Note: the photo test page can take a rather long time to get printed and on laser printers with too low memory it can even not come out. In most cases it is enough to print the standard test page."),
	   cancel => (!$printer->{NEW} ?
		       N("Cancel") : ($::isWizard ? N("<- Previous") : 
				      N("No test pages"))),
	   ok => ($::isWizard ? N("Next ->") : N("Print")),
	   callbacks => {
	       changed => sub {
		   if ($oldres2 ne $res2) {
		       if ($res2) {
			   $standard = 0;
			   $altletter = 0;
			   $alta4 = 0;
			   $photo = 0;
			   $ascii = 0;
			   $oldstandard = 0;
			   $oldaltletter = 0;
			   $oldalta4 = 0;
			   $oldphoto = 0;
			   $oldascii = 0;
		       }
		       $oldres2 = $res2;
		   }
		   if ($oldstandard ne $standard) {
		       if ($standard) {
			   $res2 = 0;
			   $oldres2 = 0;
		       }
		       $oldstandard = $standard;
		   }
		   if ($oldaltletter ne $altletter) {
		       if ($altletter) {
			   $res2 = 0;
			   $oldres2 = 0;
		       }
		       $oldaltletter = $altletter;
		   }
		   if ($oldalta4 ne $alta4) {
		       if ($alta4) {
			   $res2 = 0;
			   $oldres2 = 0;
		       }
		       $oldalta4 = $alta4;
		   }
		   if ($oldphoto ne $photo) {
		       if ($photo) {
			   $res2 = 0;
			   $oldres2 = 0;
		       }
		       $oldphoto = $photo;
		   }
		   if ($oldascii ne $ascii) {
		       if ($ascii) {
			   $res2 = 0;
			   $oldres2 = 0;
		       }
		       $oldascii = $ascii;
		   }
		   return 0;
	       }
	   } },
	 [
	  { text => N("Standard test page"), type => 'bool',
	    val => \$standard },
	  if_($::expert,
	   { text => N("Alternative test page (Letter)"), type => 'bool', 
	     val => \$altletter }),
	  if_($::expert,
	   { text => N("Alternative test page (A4)"), type => 'bool', 
	     val => \$alta4 }), 
	  { text => N("Photo test page"), type => 'bool', val => \$photo },
	  #{ text => N("Plain text test page"), type => 'bool',
	  #  val => \$ascii }
	  if_($::isWizard,
	   { text => N("Do not print any test page"), type => 'bool', 
	     val => \$res2 })
	  ]);
    $res2 = 1 if !($standard || $altletter || $alta4 || $photo || $ascii);
    if ($res1 && !$res2) {
	my @lpq_output;
	{
	    my $_w = $in->wait_message(N("Printerdrake"),
				      N("Printing test page(s)..."));
	    
	    $upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
	    my $stdtestpage = "/usr/share/printer-testpages/testprint.ps";
	    my $altlttestpage = "/usr/share/printer-testpages/testpage.ps";
	    my $alta4testpage = "/usr/share/printer-testpages/testpage-a4.ps";
	    my $phototestpage = "/usr/share/printer-testpages/photo-testpage.jpg";
	    my $asciitestpage = "/usr/share/printer-testpages/testpage.asc";
	    my @testpages;
	    # Install the filter to convert the photo test page to PS
	    if ($printer->{SPOOLER} ne "cups" && $photo && !$::testing &&
		!files_exist('/usr/bin/convert')) {
		$in->do_pkgs->install('ImageMagick');
	    }
	    # set up list of pages to print
	    $standard && push @testpages, $stdtestpage;
	    $altletter && push @testpages, $altlttestpage;
	    $alta4 && push @testpages, $alta4testpage;
	    $photo && push @testpages, $phototestpage;
	    $ascii && push @testpages, $asciitestpage;
	    # print the stuff
	    @lpq_output = printer::main::print_pages($printer, @testpages);
	}
	my $dialogtext;
	if (@lpq_output) {
	    $dialogtext = N("Test page(s) have been sent to the printer.
It may take some time before the printer starts.
Printing status:\n%s\n\n", @lpq_output);
	} else {
	    $dialogtext = N("Test page(s) have been sent to the printer.
It may take some time before the printer starts.\n");
	}
	if ($printer->{NEW} == 0) {
	    $in->ask_warn('',$dialogtext);
	    return 1;
	} else {
	    $in->ask_yesorno('', $dialogtext . N("Did it work properly?"), 1) 
		and return 1;
	}
    } else {
	return($::isWizard ? $res1 : 1);
    }
    return 2;
}

sub printer_help {
    my ($printer, $in) = @_;
    my $spooler = $printer->{SPOOLER};
    my $queue = $printer->{QUEUE};
    my $default = $printer->{DEFAULT};
    my $raw = 0;
    my $cupsremote = 0;
    my $scanning = "";
    my $photocard = "";
    if ($printer->{configured}{$queue}) {
	if ($printer->{configured}{$queue}{queuedata}{model} eq "Unknown model" ||
	    $printer->{configured}{$queue}{queuedata}{model} eq N("Raw printer")) {
	    $raw = 1;
	}
	# Information about scanning with HP's multi-function devices
	$scanning = scanner_help(
	     $printer->{configured}{$queue}{queuedata}{make} . " " .
	     $printer->{configured}{$queue}{queuedata}{model}, 
	     $printer->{configured}{$queue}{queuedata}{connect});
	if ($scanning) {
	    $scanning = "\n\n$scanning\n\n";
	}
	# Information about photo card access with HP's multi-function devices
	$photocard = photocard_help(
	     $printer->{configured}{$queue}{queuedata}{make} . " " .
	     $printer->{configured}{$queue}{queuedata}{model}, 
	     $printer->{configured}{$queue}{queuedata}{connect});
	if ($photocard) {
	    $photocard = "\n\n$photocard\n\n";
	}
    } else {
	$cupsremote = 1;
    }

    my $dialogtext;
    if ($spooler eq "cups") {
	$dialogtext =
N("To print a file from the command line (terminal window) you can either use the command \"%s <file>\" or a graphical printing tool: \"xpp <file>\" or \"kprinter <file>\". The graphical tools allow you to choose the printer and to modify the option settings easily.
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
N("These commands you can also use in the \"Printing command\" field of the printing dialogs of many applications, but here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
N("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
(!$cupsremote ?
 N("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s

", $scanning, $photocard) . printer::main::help_output($printer, 'lpd') : 
 $scanning . $photocard .
 N("Here is a list of the available printing options for the current printer:

") . printer::main::help_output($printer, 'lpd')) : $scanning . $photocard);
    } elsif ($spooler eq "lprng") {
	$dialogtext =
N("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) . 
N("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
N("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -Z option=setting -Z switch" : "lpr -Z option=setting -Z switch")) .
N("To get a list of the options available for the current printer click on the \"Print option list\" button.") . $scanning . $photocard : $scanning . $photocard);
    } elsif ($spooler eq "lpd") {
	$dialogtext =
N("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
N("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
N("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
N("To get a list of the options available for the current printer click on the \"Print option list\" button.") . $scanning . $photocard : $scanning . $photocard);
    } elsif ($spooler eq "pdq") {
	$dialogtext =
N("To print a file from the command line (terminal window) use the command \"%s <file>\" or \"%s <file>\".
", ($queue ne $default ? "pdq -P $queue" : "pdq"), ($queue ne $default ? "lpr -P $queue" : "lpr")) .
N("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
N("You can also use the graphical interface \"xpdq\" for setting options and handling printing jobs.
If you are using KDE as desktop environment you have a \"panic button\", an icon on the desktop, labeled with \"STOP Printer!\", which stops all print jobs immediately when you click it. This is for example useful for paper jams.
") .
(!$raw ?
N("
The \"%s\" and \"%s\" commands also allow to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\".
", "pdq", "lpr", ($queue ne $default ? "pdq -P $queue -aoption=setting -oswitch" : "pdq -aoption=setting -oswitch")) .
N("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s

", $scanning, $photocard) . printer::main::help_output($printer, 'pdq') :
 $scanning . $photocard);
    }
    my $windowtitle = ($scanning ?
                       ($photocard ?
			N("Printing/Scanning/Photo Cards on \"%s\"", $queue) :
			N("Printing/Scanning on \"%s\"", $queue)) :
                       ($photocard ?
			N("Printing/Photo Card Access on \"%s\"", $queue) :
			N("Printing on the printer \"%s\"", $queue)));
    if (!$raw && !$cupsremote) {
        my $choice;
        while ($choice ne N("Close")) {
	    $choice = $in->ask_from_list_(
	         $windowtitle, $dialogtext,
		 [ N("Print option list"), N("Close") ],
		 N("Close"));
	    if ($choice ne N("Close")) {
		my $_w = $in->wait_message(N("Printerdrake"),
					  N("Printing test page(s)..."));
	        printer::main::print_optionlist($printer);
	    }
	}
    } else {
	$in->ask_warn($windowtitle, $dialogtext);
    }
}

sub scanner_help {
    my ($makemodel, $deviceuri) = @_;
    if ($deviceuri =~ m!^ptal:/(.*)$!) {
	my $ptaldevice = $1;
	if ($makemodel !~ /HP\s+PhotoSmart/i &&
	    $makemodel !~ /HP\s+LaserJet\s+2200/i) {
	    # Models with built-in scanner
	    return N("Your multi-function device was configured automatically to be able to scan. Now you can scan with \"scanimage\" (\"scanimage -d hp:%s\" to specify the scanner when you have more than one) from the command line or with the graphical interfaces \"xscanimage\" or \"xsane\". If you are using the GIMP, you can also scan by choosing the appropriate point in the \"File\"/\"Acquire\" menu. Call also \"man scanimage\" on the command line to get more information.

Do not use \"scannerdrake\" for this device!",
		     $ptaldevice);
	} else {
	    # Scanner-less models
	    return "";
	}
    }
}

sub photocard_help {
    my ($makemodel, $deviceuri) = @_;
    if ($deviceuri =~ m!^ptal:/(.*)$!) {
	my $ptaldevice = $1;
	if (($makemodel =~ /HP\s+PhotoSmart/i ||
	     $makemodel =~ /HP\s+PSC\s*9[05]0/i ||
	     $makemodel =~ /HP\s+PSC\s*22\d\d/i ||
	     $makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i) &&
	    $makemodel !~ /HP\s+PhotoSmart\s+7150/i) {
	    # Models with built-in photo card drives
	    return N("Your printer was configured automatically to give you access to the photo card drives from your PC. Now you can access your photo cards using the graphical program \"MtoolsFM\" (Menu: \"Applications\" -> \"File tools\" -> \"MTools File Manager\") or the command line utilities \"mtools\" (enter \"man mtools\" on the command line for more info). You find the card's file system under the drive letter \"p:\", or subsequent drive letters when you have more than one HP printer with photo card drives. In \"MtoolsFM\" you can switch between drive letters with the field at the upper-right corners of the file lists.",
		     $ptaldevice);
	} else {
	    # Photo-card-drive-less models
	    return "";
	}
    }
}

sub copy_queues_from {
    my ($printer, $in, $oldspooler) = @_;

    $in->set_help('copyQueues') if $::isInstall;
    my $newspooler = $printer->{SPOOLER};
    my @oldqueues;
    my @queueentries;
    my @queuesselected;
    my $newspoolerstr;
    my $oldspoolerstr;
    my $noninteractive = 0;
    {
	my $_w = $in->wait_message(N("Printerdrake"),
				  N("Reading printer data..."));
	@oldqueues = printer::main::get_copiable_queues($oldspooler, $newspooler);
	@oldqueues = sort(@oldqueues);
	$newspoolerstr = $printer::data::shortspooler_inv{$newspooler};
	$oldspoolerstr = $printer::data::shortspooler_inv{$oldspooler};
	foreach (@oldqueues) {
	    push @queuesselected, 1;
	    push @queueentries, { text => $_, type => 'bool', 
				   val => \$queuesselected[$#queuesselected] };
	}
	# LPRng and LPD use the same config files, therefore one sees the 
	# queues of LPD when one uses LPRng and vice versa, but these queues
	# do not work. So automatically transfer all queues when switching
	# between LPD and LPRng.
	if ($oldspooler =~ /^lp/ && $newspooler =~ /^lp/) {
	    $noninteractive = 1;
	}
    }
    if ($noninteractive ||
	$in->ask_from_(
	 { title => N("Transfer printer configuration"),
	   messages => N("You can copy the printer configuration which you have done for the spooler %s to %s, your current spooler. All the configuration data (printer name, description, location, connection type, and default option settings) is overtaken, but jobs will not be transferred.
Not all queues can be transferred due to the following reasons:
", $oldspoolerstr, $newspoolerstr) .
($newspooler eq "cups" ? N("CUPS does not support printers on Novell servers or printers sending the data into a free-formed command.
") :
 ($newspooler eq "pdq" ? N("PDQ only supports local printers, remote LPD printers, and Socket/TCP printers.
") :
  N("LPD and LPRng do not support IPP printers.
"))) .
N("In addition, queues not created with this program or \"foomatic-configure\" cannot be transferred.") .
if_($oldspooler eq "cups", N("
Also printers configured with the PPD files provided by their manufacturers or with native CUPS drivers cannot be transferred.")) . N("
Mark the printers which you want to transfer and click 
\"Transfer\"."),
	   cancel => N("Do not transfer printers"),
           ok => N("Transfer")
	 },
         \@queueentries
      )) {
	my $queuecopied = 0;
	foreach (@oldqueues) {
	    if (shift(@queuesselected)) {
                my $oldqueue = $_;
                my $newqueue = $_;
                if (!$printer->{configured}{$newqueue} || $noninteractive ||
		    $in->ask_from_(
	              { title => N("Transfer printer configuration"),
	                messages => N("A printer named \"%s\" already exists under %s. 
Click \"Transfer\" to overwrite it.
You can also type a new name or skip this printer.", 
				      $newqueue, $newspoolerstr),
                        ok => N("Transfer"),
                        cancel => N("Skip"),
		        callbacks => { complete => sub {
	                    unless ($newqueue =~ /^\w+$/) {
				$in->ask_warn('', N("Name of printer should contain only letters, numbers and the underscore"));
				return (1,0);
			    }
			    if ($printer->{configured}{$newqueue}
				&& $newqueue ne $oldqueue && 
				!$in->ask_yesorno('', N("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
							 $newqueue),
						   0)) {
				return (1,0); # Let the user correct the name
			    }
			    return 0;
			} }
		    },
		      [{label => N("New printer name"),val => \$newqueue }])) {
		    {
			my $_w = $in->wait_message(N("Printerdrake"), 
			   N("Transferring %s...", $oldqueue));
		        printer::main::copy_foomatic_queue($printer, $oldqueue,
						   $oldspooler, $newqueue) and
							 $queuecopied = 1;
		    }
		    if ($oldqueue eq $printer->{DEFAULT}) {
			# Make the former default printer the new default
			# printer if the user does not reject
			if ($noninteractive ||
			    $in->ask_yesorno(
			      N("Transfer printer configuration"),
			      N("You have transferred your former default printer (\"%s\"), Should it be also the default printer under the new printing system %s?", $oldqueue, $newspoolerstr), 1)) {
			    $printer->{DEFAULT} = $newqueue;
			    printer::default::set_printer($printer);
			}
		    }
		}
            }
	}
        if ($queuecopied) {
	    my $_w = $in->wait_message(N("Printerdrake"),
                                      N("Refreshing printer data..."));
	    printer::main::read_configured_queues($printer);
        }
    }
}

sub start_network {
    my ($in, $upNetwork) = @_;
    my $_w = $in->wait_message(N("Configuration of a remote printer"), 
			      N("Starting network..."));
    if ($::isInstall) {
	return ($upNetwork and 
		do { my $ret = &$upNetwork(); 
		     undef $upNetwork; 
		     sleep(1);
		     $ret });
    } else { return printer::services::start("network") }
}

sub check_network {

    # This routine is called whenever the user tries to configure a remote
    # printer. It checks the state of the network functionality to assure
    # that the network is up and running so that the remote printer is
    # reachable.

    my ($printer, $in, $upNetwork, $dontconfigure) = @_;

    # Any additional dialogs caused by this subroutine should appear as
    # extra windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    $in->set_help('checkNetwork') if $::isInstall;

    # First check: Does /etc/sysconfig/network-scripts/drakconnect_conf exist
    # (otherwise the network is not configured yet and drakconnect has to be
    # started)

    if (!files_exist("/etc/sysconfig/network-scripts/drakconnect_conf") &&
	!$dontconfigure) {
	my $go_on = 0;
	while (!$go_on) {
	    my $choice = N("Configure the network now");
	    if ($in->ask_from(N("Network functionality not configured"),
			      N("You are going to configure a remote printer. This needs working network access, but your network is not configured yet. If you go on without network configuration, you will not be able to use the printer which you are configuring now. How do you want to proceed?"),
			      [ { val => \$choice, type => 'list',
				  list => [ N("Configure the network now"),
					    N("Go on without configuring the network") ] } ])) {
		if ($choice eq N("Configure the network now")) {
		    if ($::isInstall) {
			require network::netconnect;
		        network::netconnect::main(
			     $in->{prefix}, $in->{netcnx} ||= {}, 
			     $in->{netc}, $in->{mouse}, $in, 
			     $in->{intf}, 0,
			     $in->{lang} eq "fr_FR" && 
			     $in->{keyboard}{KEYBOARD} eq "fr", 0);
		    } else {
			system("/usr/sbin/drakconnect");
		    }
		    $go_on = files_exist("/etc/sysconfig/network-scripts/drakconnect_conf");
		} else {
		    return 1;
		}
	    } else {
		return 0;
	    }
	}
    }

    # Do not try to start the network if it is not configured
    if (!files_exist("/etc/sysconfig/network-scripts/drakconnect_conf")) { return 0 }

    # Second check: Is the network running?

    if (printer::detect::network_running()) { return 1 }

    # The network is configured now, start it.
    if (!start_network($in, $upNetwork) && !$dontconfigure) {
	$in->ask_warn(N("Configuration of a remote printer"), 
($::isInstall ?
N("The network configuration done during the installation cannot be started now. Please check whether the network gets accessable after booting your system and correct the configuration using the Mandrake Control Center, section \"Network & Internet\"/\"Connection\", and afterwards set up the printer, also using the Mandrake Control Center, section \"Hardware\"/\"Printer\"") :
N("The network access was not running and could not be started. Please check your configuration and your hardware. Then try to configure your remote printer again.")));
	return 0;
    }

    # Give a SIGHUP to the daemon and in case of CUPS do also the
    # automatic configuration of broadcasting/access permissions
    # The daemon is not really restarted but only SIGHUPped to not
    # interrupt print jobs.

    my $_w = $in->wait_message(N("Configuration of a remote printer"), 
			      N("Restarting printing system..."));

    return printer::main::SIGHUP_daemon($printer->{SPOOLER});

}

sub security_check {
    # Check the security mode and when in "high" or "paranoid" mode ask the
    # user whether he really wants to configure printing.
    my ($_printer, $in, $spooler) = @_;

    # Any additional dialogs caused by this subroutine should appear as
    # extra windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    $in->set_help('securityCheck') if $::isInstall;

    # Get security level
    my $security;
    if ($::isInstall) {
	$security = $in->{security};
    } else {
     require security::level;
	$security = security::level::get();
    }

    # Exit silently if the spooler is PDQ
    if ($spooler eq "pdq") { return 1 }

    # Exit silently in medium or lower security levels
    if (!$security || $security < 4) { return 1 }
    
    # Exit silently if the current spooler is already activated for the current
    # security level
    if (printer::main::spooler_in_security_level($spooler, $security)) { return 1 }

    # Tell user in which security mode he is and ask him whether he really
    # wants to activate the spooler in the given security mode. Stop the
    # operation of installing the spooler if he disagrees.
    my $securitystr = ($security == 4 ? N("high") : N("paranoid"));
    if ($in->ask_yesorno(N("Installing a printing system in the %s security level", $securitystr),
			 N("You are about to install the printing system %s on a system running in the %s security level.

This printing system runs a daemon (background process) which waits for print jobs and handles them. This daemon is also accessable by remote machines through the network and so it is a possible point for attacks. Therefore only a few selected daemons are started by default in this security level.

Do you really want to configure printing on this machine?",
			   $printer::data::shortspooler_inv{$spooler},
			   $securitystr))) {
        printer::main::add_spooler_to_security_level($spooler, $security);
	my $service;
	if ($spooler eq "lpr" || $spooler eq "lprng") {
	    $service = "lpd";
	} else {
	    $service = $spooler;
	}
        services::start_service_on_boot($service); #TV
	return 1;
    } else {
	return 0;
    }
}

sub start_spooler_on_boot {
    # Checks whether the spooler will be started at boot time and if not,
    # ask the user whether he wants to start the spooler at boot time.
    my ($printer, $in, $service) = @_;
    # PDQ has no daemon, so nothing needs to be started :
    return unless $service;

    # Any additional dialogs caused by this subroutine should appear as
    # extra windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    $in->set_help('startSpoolerOnBoot') if $::isInstall;
    if (!services::starts_on_boot($service)) {
	if ($in->ask_yesorno(N("Starting the printing system at boot time"),
			     N("The printing system (%s) will not be started automatically when the machine is booted.

It is possible that the automatic starting was turned off by changing to a higher security level, because the printing system is a potential point for attacks.

Do you want to have the automatic starting of the printing system turned on again?",
		       $printer::data::shortspooler_inv{$printer->{SPOOLER}}))) {
	    services::start_service_on_boot($service);
	}
    }
    1;
}

sub install_spooler {
    # installs the default spooler and start its daemon
    my ($printer, $in, $upNetwork) = @_;
    return 1 if $::testing;
    my $spooler = $printer->{SPOOLER};
    # If the user refuses to install the spooler in high or paranoid security level, exit.
    return 0 unless security_check($printer, $in, $spooler);
    return 1 if $spooler !~ /^(cups|lpd|lprng|pqd)$/; # should not happen
    my $w = $in->wait_message(N("Printerdrake"), N("Checking installed software..."));

    # "lpr" conflicts with "LPRng", remove either "LPRng" or remove "lpr"
    my $packages = $spoolers{$spooler}{packages2rm};
    if ($packages && files_exist($packages->[1])) {
        $w->set(N("Printerdrake"), N("Removing %s ..."), $spoolers{$packages->[0]}{short_name});
        $in->do_pkgs->remove_nodeps($packages->[0]);
    }

    $packages = $spoolers{$spooler}{packages2add};
    if ($packages && !files_exist(@{$packages->[1]})) {
        $w->set(N("Printerdrake"), N("Installing %s ..."), $spoolers{$spooler}{short_name});
        $in->do_pkgs->install(@{$packages->[0]});
    }

    undef $w;
    
    # Start the network (especially during installation), so the
    # user can set up queues to remote printers.
    # (especially during installation)

    $upNetwork and do {
        &$upNetwork(); 
        undef $upNetwork; 
        sleep(1);
    };

    # Start daemon
    if ($spooler eq "cups") {
        # Start daemon
        # Avoid unnecessary restarting of CUPS, this blocks the
        # startup of printerdrake for several seconds.
        printer::services::start_not_running_service("cups");
     } elsif ($spoolers{$spooler}{service}) {
          printer::services::restart($spoolers{$spooler}{service});
        }
    
    # Set the choosen spooler tools as defaults for "lpr", "lpq", "lprm", ...
    foreach (@{$spoolers{$spooler}{alternatives}}) {
        set_alternative($_->[0], $_->[1]);
    }

    # Remove/add PDQ panic buttons from the user's KDE Desktops
    printer::main::pdq_panic_button($spooler eq 'pdq' ? "add" : "remove");

    # Should it be started at boot time?
    start_spooler_on_boot($printer, $in, $spoolers{$spooler}{boot_spooler});

    # Give a SIGHUP to the devfsd daemon to correct the permissions
    # for the /dev/... files according to the spooler
    printer::main::SIGHUP_daemon("devfs");
    1;
}

sub setup_default_spooler {
    my ($printer, $in, $upNetwork) = @_;
    $in->set_help('setupDefaultSpooler') if $::isInstall;
    $printer->{SPOOLER} ||= 'cups';
    my $oldspooler = $printer->{SPOOLER};

    my $str_spooler = 
	$in->ask_from_list_(N("Select Printer Spooler"),
			    N("Which printing system (spooler) do you want to use?"),
			    [ printer::main::spooler() ],
			    $spoolers{$printer->{SPOOLER}},
			    ) or return;
    $printer->{SPOOLER} = $spoolers{$str_spooler};
    # Install the spooler if not done yet
    if (!install_spooler($printer, $in, $upNetwork)) {
	$printer->{SPOOLER} = $oldspooler;
	return;
    }
    if ($printer->{SPOOLER} ne $oldspooler) {
	# Remove the local printers from Star Office/OpenOffice.org/GIMP
	printer::main::removelocalprintersfromapplications($printer);
	# Get the queues of this spooler
	{
	    my $_w = $in->wait_message(N("Printerdrake"),
				      N("Reading printer data..."));
	    printer::main::read_configured_queues($printer);
	}
	# Copy queues from former spooler
	copy_queues_from($printer, $in, $oldspooler);
	# Re-read the printer database (CUPS has additional drivers, PDQ
	# has no raw queue)
	%printer::main::thedb = ();
	#my $_w = $in->wait_message(N("Printerdrake"), N("Reading printer database..."));
	#printer::main::read_printer_db($printer->{SPOOLER});
    }
    # Save spooler choice
    printer::default::set_spooler($printer);
    return $printer->{SPOOLER};
}

sub configure_queue {
    my ($printer, $in) = @_;
    my $_w = $in->wait_message(N("Printerdrake"), N("Configuring printer \"%s\"...",
				$printer->{currentqueue}{queue}));
    $printer->{complete} = 1;
    printer::main::configure_queue($printer);
    $printer->{complete} = 0;
}

sub install_foomatic {
    my ($in) = @_;
    if (!$::testing &&
	!files_exist(qw(/usr/bin/foomatic-configure /usr/lib/perl5/vendor_perl/5.8.0/Foomatic/DB.pm))) {
	my $_w = $in->wait_message(N("Printerdrake"), N("Installing Foomatic..."));
	$in->do_pkgs->install('foomatic');
    }
}

sub wizard_close {
    my ($in, $mode) = @_;
    # Leave wizard mode with congratulations screen if $mode = 1
    $::Wizard_no_previous = 1;
    $::Wizard_no_cancel = 1;
    $::Wizard_finished = 1;
    wizard_congratulations($in) if $mode == 1;
    undef $::isWizard;
    $::WizardWindow->destroy if defined $::WizardWindow;
    undef $::WizardWindow;
};

#- Program entry point for configuration of the printing system.
sub main {
    my ($printer, $in, $ask_multiple_printer, $upNetwork) = @_;

    # Save the user mode, so that the same one is used on the next start
    # of Printerdrake
    printer::main::set_usermode($::expert);

    # Default printer name, we do not use "lp" so that one can switch the
    # default printer under LPD without needing to rename another printer.
    # Under LPD the alias "lp" will be given to the default printer.
    my $defaultprname = N("Printer");

    # printerdrake does not work without foomatic, and for more convenience
    # we install some more stuff
    {
	my $_w = $in->wait_message(N("Printerdrake"),
				  N("Checking installed software..."));
	if (!$::testing &&
	    !files_exist(qw(/usr/bin/foomatic-configure
				       /usr/lib/perl5/vendor_perl/5.8.0/Foomatic/DB.pm
				       /usr/bin/escputil
				       /usr/share/printer-testpages/testprint.ps
				       /usr/bin/nmap
				       /usr/bin/scli
				       ),
				    if_(files_exist("/usr/bin/gimp"), "/usr/lib/gimp/1.2/plug-ins/print")
				    )) {
	    $in->do_pkgs->install('foomatic', 'printer-utils', 'printer-testpages', 'nmap', 'scli',
				  if_($in->do_pkgs->is_installed('gimp'), 'gimpprint'));
	}

	# only experts should be asked for the spooler
	$printer->{SPOOLER} ||= 'cups' if $::expert;

    }

    # If we have chosen a spooler, install it and mark it as default spooler
    if ($printer->{SPOOLER}) {
        return unless install_spooler($printer, $in, $upNetwork);
        printer::default::set_spooler($printer);
    }

    # Turn on printer autodetection by default
    $printer->{AUTODETECT} = 1;
    $printer->{AUTODETECTLOCAL} = 1;
    $printer->{AUTODETECTNETWORK} = 1;
    $printer->{AUTODETECTSMB} = 1;

    # Control variables for the main loop
    my ($menuchoice, $cursorpos, $queue, $continue, $newqueue, $editqueue, $menushown) = ('', '::', $defaultprname, 1, 0, 0, 0);
    # Cursor position in queue modification window
    my $modify = N("Printer options");
    while ($continue) {
	$newqueue = 0;
	# When the queue list is not shown, cancelling the printer type
	# dialog should leave the program
	$continue = 0;
	# Get the default printer
	if (defined($printer->{SPOOLER}) && $printer->{SPOOLER} &&
	    (!defined($printer->{DEFAULT}) || $printer->{DEFAULT})) {
	    my $_w = $in->wait_message(N("Printerdrake"),
				      N("Preparing Printerdrake..."));
	    $printer->{DEFAULT} = printer::default::get_printer($printer);
	    if ($printer->{DEFAULT}) {
		# If a CUPS system has only remote printers and no default
		# printer defined, it defines the first printer whose
		# broadcast signal appeared after the start of the CUPS
		# daemon, so on every start another printer gets the default
		# printer. To avoid this, make sure that the default printer
		# is defined.
		printer::default::set_printer($printer);
	    } else { $printer->{DEFAULT} = '' }
	}

	# Configure the current printer queues in applications
	{
	    my $_w = $in->wait_message(N("Printerdrake"), N("Configuring applications..."));
	    printer::main::configureapplications($printer);
	}

	if ($editqueue) {
	    # The user was either in the printer modification dialog and did
	    # not close it or he had set up a new queue and said that the test
	    # page didn't come out correctly, so let the user edit the queue.
	    $newqueue = 0;
	    $continue = 1;
	    $editqueue = 0;
	} else {
	    # Reset modification window cursor when one leaves the window
	    $modify = N("Printer options");
	    if (!$ask_multiple_printer && 
		%{$printer->{configured} || {}} == ()) {
		$in->set_help('doYouWantToPrint') if $::isInstall;
		$newqueue = 1;
		$menuchoice = $printer->{want} || 
		    $in->ask_yesorno(N("Printer"),
				    N("Would you like to configure printing?"),
				    0) ? "\@addprinter" : "\@quit";
		if ($menuchoice ne "\@quit") {
		    $printer->{SPOOLER} ||= 
			setup_default_spooler($printer, $in, $upNetwork) ||
			    return;
		}
	    } else {
		# Ask for a spooler when none is defined
		$printer->{SPOOLER} ||= setup_default_spooler($printer, $in, $upNetwork) || return;
		# This entry and the check for this entry have to use
		# the same translation to work properly
		my $_spoolerentry = N("Printing system: ");
		# If networking is configured, start it, but don't ask the
		# user to configure networking. We want to know whether we
		# have a local network, to suppress some buttons in the
		# recommended mode
		my $havelocalnetworks_or_expert =
		    $::expert ||
		     check_network($printer, $in, $upNetwork, 1) && 
		      printer::detect::getIPsInLocalNetworks() != ();
		# Show a queue list window when there is at least one queue,
		# when we are in expert mode, or when we are not in the
		# installation.
		if (%{$printer->{configured} || {}} || $::expert || !$::isInstall) {
		    $in->set_help('mainMenu') if $::isInstall;
		    # Cancelling the printer type dialog should leed to this
		    # dialog
		    $continue = 1;
		    # This is for the "Recommended" installation. When one has
		    # no printer queue printerdrake starts directly adding
		    # a printer and in the end it asks whether one wants to
		    # install another printer. If the user says "Yes", he
		    # arrives in the main menu of printerdrake. From now
		    # on the question is not asked any more but the menu
		    # is shown directly after having done an operation.
		    $menushown = 1;
		    # Initialize the cursor position
		    if ($cursorpos eq "::" && 
			$printer->{DEFAULT} &&
			$printer->{DEFAULT} ne "") {
			if ($printer->{configured}{$printer->{DEFAULT}}) {
			    $cursorpos = 
				$printer->{configured}{$printer->{DEFAULT}}{queuedata}{menuentry} . N(" (Default)");
			} elsif ($printer->{SPOOLER} eq "cups") {
			    $cursorpos = find { /!$printer->{DEFAULT}:[^!]*$/ } printer::cups::get_formatted_remote_queues($printer);
			}
		    }
		    # Generate the list of available printers
		    my @printerlist = 
			sort((map { $printer->{configured}{$_}{queuedata}{menuentry} 
				      . ($_ eq $printer->{DEFAULT} ?
					 N(" (Default)") : "") }
				 keys(%{$printer->{configured}
					|| {}})),
				($printer->{SPOOLER} eq "cups" ?
				 printer::cups::get_formatted_remote_queues($printer) :
				 ()));
		    my $noprinters = $#printerlist < 0;
		    # Position the cursor where it were before (in case
		    # a button was pressed).
		    $menuchoice = $cursorpos;
		    # Show the main dialog
		    $in->ask_from_(
			{ title => N("Printerdrake"),
			 messages =>
			     ($noprinters ? "" :
			      ($printer->{SPOOLER} eq "cups" ?
			       N("The following printers are configured. Double-click on a printer to change its settings; to make it the default printer; to view information about it; or to make a printer on a remote CUPS server available for Star Office/OpenOffice.org/GIMP.") :
			       N("The following printers are configured. Double-click on a printer to change its settings; to make it the default printer; or to view information about it."))),
			 cancel => (""),
			 ok => (""),
			},
			# List the queues
			[ if_(!$noprinters,
			   { val => \$menuchoice, format => \&translate,
			     sort => 0, separator => "!",tree_expanded => 1,
			     quit_if_double_click => 1,allow_empty_list =>1,
			     list => \@printerlist }),
			  { clicked_may_quit =>
			    sub { 
				# Save the cursor position
				$cursorpos = $menuchoice;
				$menuchoice = "\@addprinter";
				1; 
			    },
			    val => N("Add a new printer") },
			  ($printer->{SPOOLER} eq "cups" && $havelocalnetworks_or_expert ?
			    ({ clicked_may_quit =>
				   sub { 
				       # Save the cursor position
				       $cursorpos = $menuchoice;
				       $menuchoice = "\@refresh";
				       1;
				   },
			       val => N("Refresh printer list (to display all available remote CUPS printers)") },
			     { clicked_may_quit =>
				   sub { 
				       # Save the cursor position
				       $cursorpos = $menuchoice;
				       $menuchoice = "\@cupsconfig";
				       1;
				   },
			       val => ($::expert ? N("CUPS configuration") :
				       N("Printer sharing")) }) : ()),
			  ($::expert ?
			    { clicked_may_quit =>
				  sub {
				      # Save the cursor position
				      $cursorpos = $menuchoice;
				      $menuchoice = "\@spooler";
				      1;
				  },
				  val => N("Change the printing system") } :
			    ()),
			  (!$::isInstall ?
			    { clicked_may_quit =>
				  sub { $menuchoice = "\@usermode"; 1 },
				  val => ($::expert ? N("Normal Mode") :
					  N("Expert Mode")) } : ()),
			  { clicked_may_quit =>
			    sub { $menuchoice = "\@quit"; 1 },
			    val => ($::isEmbedded || $::isInstall ?
				    N("Done") : N("Quit")) },
			  ]
		    );
		    # Toggle expert mode and standard mode
		    if ($menuchoice eq "\@usermode") {
			printer::main::set_usermode(!$::expert);
			# make sure that the "cups-drivers" package gets
			# installed when switching into expert mode
			if ($::expert && $printer->{SPOOLER} eq "cups") {
			    install_spooler($printer, $in, $upNetwork);
			}
			# Read printer database for the new user mode
			%printer::main::thedb = ();
			#my $_w = $in->wait_message(N("Printerdrake"), 
			#                   N("Reading printer database..."));
		        #printer::main::read_printer_db($printer->{SPOOLER});
			# Re-read printer queues to switch the tree
			# structure between expert/normal mode.
			my $_w = $in->wait_message(
			     N("Printerdrake"), 
			     N("Reading printer data..."));
			printer::main::read_configured_queues($printer);
			$cursorpos = "::";
			next;
		    }
		} else {
		    #- as there are no printer already configured, Add one
		    #- automatically.
		    $menuchoice = "\@addprinter"; 
		}
		# Refresh printer list
		next if $menuchoice eq "\@refresh";
		# Configure CUPS
		if ($menuchoice eq "\@cupsconfig") {
		    config_cups($printer, $in, $upNetwork);
		    next;
		}
	        # Determine a default name for a new printer queue
		if ($menuchoice eq "\@addprinter") {
		    $newqueue = 1;
		    my %queues; 
		    @queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
		    my $i = ''; while ($i < 150) { last unless exists $queues{"$defaultprname$i"}; ++$i }
		    $queue = "$defaultprname$i";
		}
		# Function to switch to another spooler
		if ($menuchoice eq "\@spooler") {
		    $printer->{SPOOLER} = setup_default_spooler($printer, $in, $upNetwork) || $printer->{SPOOLER};
		    next;
		}
		# Rip the queue name out of the chosen menu entry
		if ($menuchoice =~ /!([^\s!:]+):[^!]*$/) {
		    $queue = $1;
		    # Save the cursor position
		    $cursorpos = $menuchoice;
		}
	    }
	    # Save the default spooler
	    printer::default::set_spooler($printer);
	    #- Close printerdrake
	    $menuchoice eq "\@quit" and last;
	}
	if ($newqueue) {
	    $printer->{NEW} = 1;
	    #- Set default values for a new queue
	    $printer_type_inv{$printer->{TYPE}} or 
		$printer->{TYPE} = printer::default::printer_type($printer);
	    $printer->{currentqueue} = { queue    => $queue,
					 foomatic => 0,
					 desc     => "",
					 loc      => "",
					 make     => "",
					 model    => "",
					 printer  => "",
					 driver   => "",
					 connect  => "",
					 spooler  => $printer->{SPOOLER},
				       };
	    #- Set OLD_QUEUE field so that the subroutines for the
	    #- configuration work correctly.
	    $printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
	    #- Do all the configuration steps for a new queue
	  step_0:
	    #if ((!$::expert) && (!$::isEmbedded) && (!$::isInstall) &&
	    if (!$::isEmbedded && !$::isInstall &&
	    #if ((!$::isInstall) &&
		$in->isa('interactive::gtk')) {
		$continue = 1;
		# Enter wizard mode
		$::Wizard_pix_up = "wiz_printerdrake.png";
		$::Wizard_title = N("Add a new printer");
		$::isWizard = 1;
		# Wizard welcome screen
		$::Wizard_no_previous = 1;
		undef $::Wizard_no_cancel; undef $::Wizard_finished;
		wizard_welcome($printer, $in, $upNetwork) or do {
		    wizard_close($in, 0);
		    next;
		};
		undef $::Wizard_no_previous;
		eval { 
		    # eval to catch wizard cancel. The wizard stuff should 
		    # be in a separate function with steps. see dragw.
		    # (dams)
		    $::expert or $printer->{TYPE} = "LOCAL";
		  step_1:
		    !$::expert or choose_printer_type($printer, $in) or
			goto step_0;
		  step_2:
		    setup_printer_connection($printer, $in, $upNetwork) or 
			do {
			    goto step_1 if $::expert;
			    goto step_0;
			};
		  step_3:
		    if ($::expert or $printer->{MANUAL} or
			$printer->{MORETHANONE}) {
			choose_printer_name($printer, $in) or
			    goto step_2;
		    }
		    get_db_entry($printer, $in);
		  step_3_9:
		    if (!$::expert and !$printer->{MANUAL}) {
			is_model_correct($printer, $in) or do {
			    goto step_3 if $printer->{MORETHANONE};
			    goto step_2;
			}
		    }
		  step_4:
		    # Remember DB entry for "Previous" button in wizard
		    my $dbentry = $printer->{DBENTRY};
		    if ($::expert or $printer->{MANUAL} or
			$printer->{MANUALMODEL}) { 
			choose_model($printer, $in) or do {
			    # Restore DB entry
			    $printer->{DBENTRY} = $dbentry;
			    goto step_3_9 if $printer->{MANUALMODEL};
			    goto step_3;
			};
		    }
		    get_printer_info($printer, $in) or next;
		  step_5:
		    setup_options($printer, $in) or
			goto step_4;
		    configure_queue($printer, $in);
		    undef $printer->{MANUAL} if $printer->{MANUAL};
		    $::Wizard_no_previous = 1;
		    setasdefault($printer, $in);
		    $cursorpos = 
			$printer->{configured}{$printer->{QUEUE}}{queuedata}{menuentry} .
			($printer->{QUEUE} eq $printer->{DEFAULT} ? N(" (Default)") : '');
		    my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
		    if ($testpages == 1) {
			# User was content with test pages
			# Leave wizard mode with congratulations screen
			wizard_close($in, 1);
			$continue = ($::expert || !$::isInstall || $menushown ||
				     $in->ask_yesorno('', N("Do you want to configure another printer?")));
		    } elsif ($testpages == 2) {
			# User was not content with test pages
			# Leave wizard mode without congratulations
			# screen
			wizard_close($in, 0);
			$editqueue = 1;
			$queue = $printer->{QUEUE};
		    }
		};
		wizard_close($in, 0) if $@ =~ /wizcancel/;
	    } else {
		$::expert or $printer->{TYPE} = "LOCAL";
		wizard_welcome($printer, $in, $upNetwork) or next;
		!$::expert or choose_printer_type($printer, $in) or next;
		#- Cancelling the printer connection type window
		#- should not restart printerdrake in recommended mode,
		#- it is the first dialog of the sequence there and
		#- the "Add printer" sequence should be stopped when there
		#- are no local printers. In expert mode this is the second
		#- dialog of the sequence.
		$continue = 1;
		setup_printer_connection($printer, $in, $upNetwork) or next;
		#- Cancelling one of the following dialogs should
		#- restart printerdrake
		if ($::expert or $printer->{MANUAL} or
		    $printer->{MORETHANONE}) {
		    choose_printer_name($printer, $in) or next;
		}
		get_db_entry($printer, $in);
		if (!$::expert and !$printer->{MANUAL}) {
		    is_model_correct($printer, $in) or next;
		}
		if ($::expert or $printer->{MANUAL} or
		    $printer->{MANUALMODEL}) { 
		    choose_model($printer, $in) or next;
		}
		get_printer_info($printer, $in) or next;
		setup_options($printer, $in) or next;
		configure_queue($printer, $in);
		undef $printer->{MANUAL} if $printer->{MANUAL};
		setasdefault($printer, $in);
		$cursorpos = 
		    $printer->{configured}{$printer->{QUEUE}}{queuedata}{menuentry} .
		    ($printer->{QUEUE} eq $printer->{DEFAULT} ? N(" (Default)") : '');
		my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
		if ($testpages == 1) {
		    # User was content with test pages
		    $continue = ($::expert || !$::isInstall || $menushown ||
				 $in->ask_yesorno('', N("Do you want to configure another printer?")));
		} elsif ($testpages == 2) {
		    # User was not content with test pages
		    $editqueue = 1;
		    $queue = $printer->{QUEUE};
		}
	    };
	    undef $printer->{MANUAL} if $printer->{MANUAL};
	} else {
	    $printer->{NEW} = 0;
	    # Modify a queue, ask which part should be modified
	    $in->set_help('modifyPrinterMenu') if $::isInstall;
	    # Get some info to display
	    my $infoline;
	    if ($printer->{configured}{$queue}) {
		# Here we must regenerate the menu entry, because the
		# parameters can be changed.
		printer::main::make_menuentry($printer,$queue);
		$printer->{configured}{$queue}{queuedata}{menuentry} =~
		    /!([^!]+)$/;
		$infoline = $1 .
		    ($queue eq $printer->{DEFAULT} ? N(" (Default)") : '') .
		    ($printer->{configured}{$queue}{queuedata}{desc} ?
		     ", Descr.: $printer->{configured}{$queue}{queuedata}{desc}" : '') .
		    ($printer->{configured}{$queue}{queuedata}{loc} ?
		     ", Loc.: $printer->{configured}{$queue}{queuedata}{loc}" : '') .
		    ($::expert ?
		     ", Driver: $printer->{configured}{$queue}{queuedata}{driver}" : '');
	    } else {
		# The parameters of a remote CUPS queue cannot be changed,
		# so we can simply take the menu entry.
		$cursorpos =~ /!([^!]+)$/;
		$infoline = $1;
	    }
	    if ($in->ask_from_(
		    { title => N("Modify printer configuration"),
		      messages => 
			   N("Printer %s
What do you want to modify on this printer?",
			     $infoline),
		     cancel => N("Close"),
		     ok => N("Do it!")
		     },
		    [ { val => \$modify, format => \&translate, 
			type => 'list',
			list => [ ($printer->{configured}{$queue} ?
				   (N("Printer connection type"),
				    N("Printer name, description, location"),
				    ($::expert ?
				     N("Printer manufacturer, model, driver") :
				     N("Printer manufacturer, model")),
				    if_($printer->{configured}{$queue}{queuedata}{make} ne "" &&
					$printer->{configured}{$queue}{queuedata}{model} ne N("Unknown model") &&
					$printer->{configured}{$queue}{queuedata}{model} ne N("Raw printer"),
				     N("Printer options"))) : ()),
				   if_($queue ne $printer->{DEFAULT},
				       N("Set this printer as the default")),
				   if_(!$printer->{configured}{$queue},
				       N("Add this printer to Star Office/OpenOffice.org/GIMP"),
				       N("Remove this printer from Star Office/OpenOffice.org/GIMP")),
				   N("Print test pages"),
				   N("Know how to use this printer"),
				   if_($printer->{configured}{$queue}, N("Remove printer")) ] } ])) {
		# Stay in the queue edit window until the user clicks "Close"
		# or deletes the queue
		$editqueue = 1; 
		#- Copy the queue data and work on the copy
		$printer->{currentqueue} = {};
		my $driver;
		if ($printer->{configured}{$queue}) {
		    printer::main::copy_printer_params($printer->{configured}{$queue}{queuedata}, $printer->{currentqueue});
		    #- Keep in mind the printer driver which was used, so it
                    #- can be determined whether the driver is only
		    #- available in expert and so for setting the options
		    #- for the driver in recommended mode a special
		    #- treatment has to be applied.
		    $driver = $printer->{currentqueue}{driver};
		}
		#- keep in mind old name of queue (in case of changing)
		$printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
		#- Reset some variables
		$printer->{OLD_CHOICE} = undef;
		$printer->{DBENTRY} = undef;
		#- Which printer type did we have before (check beginning of
		#- URI)
		if ($printer->{configured}{$queue}) {
		    foreach my $type (qw(file lpd socket smb ncp postpipe)) {
			if ($printer->{currentqueue}{connect} =~ /^$type:/) {
			    $printer->{TYPE} = 
				($type eq 'file' ? 'LOCAL' : uc($type));
			    last;
			}
		    }
		}
		# Do the chosen task
		if ($modify eq N("Printer connection type")) {
		    choose_printer_type($printer, $in) &&
			setup_printer_connection($printer, $in, $upNetwork) &&
		            configure_queue($printer, $in);
		} elsif ($modify eq N("Printer name, description, location")) {
		    choose_printer_name($printer, $in) &&
			configure_queue($printer, $in);
		    # Delete old queue when it was renamed
		    if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
			my $_w = $in->wait_message(
			     N("Printerdrake"),
			     N("Removing old printer \"%s\"...",
			       $printer->{OLD_QUEUE}));
		        printer::main::remove_queue($printer, $printer->{OLD_QUEUE});
			# If the default printer was renamed, correct the
			# the default printer setting of the spooler
			if ($queue eq $printer->{DEFAULT}) {
			    $printer->{DEFAULT} = $printer->{QUEUE};
			    printer::default::set_printer($printer);
			}
			$queue = $printer->{QUEUE};
		    }
		} elsif ($modify eq N("Printer manufacturer, model, driver") ||
			 $modify eq N("Printer manufacturer, model")) {
		    get_db_entry($printer, $in);
		    choose_model($printer, $in) &&
			get_printer_info($printer, $in) &&
			setup_options($printer, $in) &&
			configure_queue($printer, $in);
		} elsif ($modify eq N("Printer options")) {
		    get_printer_info($printer, $in) &&
			setup_options($printer, $in) &&
			configure_queue($printer, $in);
		} elsif ($modify eq N("Set this printer as the default")) {
		    $printer->{DEFAULT} = $queue;
		    printer::default::set_printer($printer);
		    $in->ask_warn(N("Default printer"),
				  N("The printer \"%s\" is set as the default printer now.", $queue));
		} elsif ($modify eq N("Add this printer to Star Office/OpenOffice.org/GIMP")) {
              $in->ask_warn(N("Adding printer to Star Office/OpenOffice.org/GIMP"),
                            printer::main::addcupsremotetoapplications($printer, $queue) ?
                            N("The printer \"%s\" was successfully added to Star Office/OpenOffice.org/GIMP.", $queue) :
                            N("Failed to add the printer \"%s\" to Star Office/OpenOffice.org/GIMP.", $queue));
		} elsif ($modify eq N("Remove this printer from Star Office/OpenOffice.org/GIMP")) {
              $in->ask_warn(N("Removing printer from Star Office/OpenOffice.org/GIMP"),
                            printer::main::removeprinterfromapplications($printer, $queue) ?
                            N("The printer \"%s\" was successfully removed from Star Office/OpenOffice.org/GIMP.", $queue) :
                            N("Failed to remove the printer \"%s\" from Star Office/OpenOffice.org/GIMP.", $queue));
		} elsif ($modify eq N("Print test pages")) {
		    print_testpages($printer, $in, $upNetwork);
		} elsif ($modify eq N("Know how to use this printer")) {
		    printer_help($printer, $in);
		} elsif ($modify eq N("Remove printer")) {
		    if ($in->ask_yesorno('',
           N("Do you really want to remove the printer \"%s\"?", $queue), 1)) {
			{
			    my $_w = $in->wait_message(
				 N("Printerdrake"),
				 N("Removing printer \"%s\"...", $queue));
			    if (printer::main::remove_queue($printer, $queue)) { 
				$editqueue = 0;
				# Define a new default printer if we have
				# removed the default one
				if ($queue eq $printer->{DEFAULT}) {
				    my @k = sort(keys %{$printer->{configured}});
                        $printer->{DEFAULT} = $k[0];
                        printer::default::set_printer($printer) if @k;
				}
				# Let the main menu cursor go to the default position
				$cursorpos = "::";
			    }
			}
		    }
		}
		# Make sure that the cursor is still at the same position
		# in the main menu when one has modified something on the
		# current printer
		if ($printer->{QUEUE} && $printer->{QUEUE} ne "") {
		    if ($printer->{configured}{$printer->{QUEUE}}) {
			$cursorpos = 
			    $printer->{configured}{$printer->{QUEUE}}{queuedata}{menuentry} . 
			    if_($printer->{QUEUE} eq $printer->{DEFAULT}, N(" (Default)"));
		    } else {
			my $s1 = N(" (Default)");
			my $s2 = $s1;
			$s2 =~ s/\(/\\\(/;
			$s2 =~ s/\)/\\\)/;
			$cursorpos .= $s1 if $printer->{QUEUE} eq $printer->{DEFAULT} && $cursorpos !~ /$s2/;
		    }
		}
	    } else { $editqueue = 0 }
	    $continue = $editqueue || $::expert || !$::isInstall || $menushown ||
			 $in->ask_yesorno('', N("Do you want to configure another printer?"));
	}

	# Configure the current printer queue in applications when main menu
	# will not be shown (During installation in "Recommended" mode)
	if ($::isInstall && !$::expert && !$menushown && !$continue) {
	    my $_w = $in->wait_message(N("Printerdrake"), N("Configuring applications..."));
	    printer::main::configureapplications($printer);
	}

	# Delete some variables
	$printer->{OLD_QUEUE} = "";
	foreach (qw(QUEUE TYPE str_type DBENTRY ARGS OLD_CHOICE)) {
		$printer->{$_} = "";
	}
	$printer->{currentqueue} = {};
	$printer->{complete} = 0;
    }
    # Clean up the $printer data structure for auto-install log
    foreach my $queue (keys %{$printer->{configured}}) {
	foreach my $item (keys %{$printer->{configured}{$queue}}) {
         delete($printer->{configured}{$queue}{$item}) if $item ne "queuedata";
	}
     delete($printer->{configured}{$queue}{queuedata}{menuentry});
    }
    foreach (qw(Old_queue QUEUE TYPE str_type currentqueue DBENTRY ARGS complete OLD_CHOICE NEW MORETHANONE MANUALMODEL AUTODETECT AUTODETECTLOCAL AUTODETECTNETWORK AUTODETECTSMB))
    { delete $printer->{$_} };
}

