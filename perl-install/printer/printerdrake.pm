package printer::printerdrake;
# $Id$

use strict;

use common;
use modules;
use network::network;
use log;
use interactive;
use printer::main;
use printer::services;
use printer::detect;
use printer::default;
use printer::data;

my $companyname = "MandrakeSoft";
my $distroname = "Mandrake Linux";
my $shortdistroname = "Mandrake";
my $domainname = "mandrakesoft.com";

my $hp1000fwtext = N("The HP LaserJet 1000 needs its firmware to be uploaded after being turned on. Download the Windows driver package from the HP web site (the firmware on the printer's CD does not work) and extract the firmware file from it by uncompresing the self-extracting '.exe' file with the 'unzip' utility and searching for the 'sihp1000.img' file. Copy this file into the '/etc/printer' directory. There it will be found by the automatic uploader script and uploaded whenever the printer is connected and turned on.
");

1;

sub config_cups {
    my ($printer, $in, $upNetwork) = @_;

    local $::isWizard = 0;
    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    #$in->set_help('configureRemoteCUPSServer') if $::isInstall;
    #- hack to handle cups remote server printing,
    #- first read /etc/cups/cupsd.conf for variable BrowsePoll address:port
    # Return value: 0 when nothing was changed ("Apply" never pressed), 1
    # when "Apply" was at least pressed once.
    my $retvalue = 0;
    # Read CUPS config file
    @{$printer->{cupsconfig}{cupsd_conf}} =
	printer::main::read_cupsd_conf();
    printer::main::read_cups_config($printer);
    # Read state of japanese text printing mode
    my $jap_textmode = printer::main::get_jap_textmode();
    # Read state for auto-correction of cupsd.conf
    $printer->{cupsconfig}{autocorrection} =
	printer::main::get_cups_autoconf();
    my $oldautocorr = $printer->{cupsconfig}{autocorrection};
    # Human-readable strings for hosts onto which the local printers
    # are shared
    my $maindone;
    while (!$maindone) {
	my $sharehosts = printer::main::makesharehostlist($printer);
	my $browsepoll = printer::main::makebrowsepolllist($printer);
	my $buttonclicked;
	#- Show dialog
	if ($in->ask_from_
	    (
	     { 
		 title => N("CUPS printer configuration"),
		 messages => N("Here you can choose whether the printers connected to this machine should be accessible by remote machines and by which remote machines.") .
		     N("You can also decide here whether printers on remote machines should be automatically made available on this machine."),
	     },
	     [
	      { text => N("The printers on this machine are available to other computers"), type => 'bool',
		val => \$printer->{cupsconfig}{localprintersshared} },
	      { text => N("Automatically find available printers on remote machines"), type => 'bool',
		val => \$printer->{cupsconfig}{remotebroadcastsaccepted} },
	      { val => N("Printer sharing on hosts/networks: ") .
		    ($printer->{cupsconfig}{customsharingsetup} ?
		     N("Custom configuration") :
		     ($#{$sharehosts->{list}} >= 0 ?
		      ($#{$sharehosts->{list}} > 1 ?
		       join(", ", @{$sharehosts->{list}}[0,1]) . " ..." :
		       join(", ", @{$sharehosts->{list}})) :
		      N("No remote machines"))), 
		type => 'button',
		clicked_may_quit => sub {
		    $buttonclicked = "sharehosts";
		    1;
		},
		disabled => sub {
		    (!$printer->{cupsconfig}{localprintersshared} &&
		     !$printer->{cupsconfig}{remotebroadcastsaccepted});
		} },
	      { val => N("Additional CUPS servers: ") .
		     ($#{$browsepoll->{list}} >= 0 ?
		      ($#{$browsepoll->{list}} > 1 ?
		       join(", ", @{$browsepoll->{list}}[0,1]) . " ..." :
		       join(", ", @{$browsepoll->{list}})) :
		      N("None")), 
		type => 'button',
		help => N("To get access to printers on remote CUPS servers in your local network you only need to turn on the \"Automatically find available printers on remote machines\" option; the CUPS servers inform your machine automatically about their printers. All printers currently known to your machine are listed in the \"Remote printers\" section in the main window of Printerdrake. If your CUPS server(s) is/are not in your local network, you have to enter the IP address(es) and optionally the port number(s) here to get the printer information from the server(s)."),
		clicked_may_quit => sub {
		    $buttonclicked = "browsepoll";
		    1;
		} },
	      { text => N("Japanese text printing mode"),
		help => N("Turning on this allows to print plain text files in japanese language. Only use this function if you really want to print text in japanese, if it is activated you cannot print accentuated characters in latin fonts any more and you will not be able to adjust the margins, the character size, etc. This setting only affects printers defined on this machine. If you want to print japanese text on a printer set up on a remote machine, you have to activate this function on that remote machine."),
		type => 'bool',
		val => \$jap_textmode },
	      if_($printer->{expert},
		  { text => N("Automatic correction of CUPS configuration"),
		    type => 'bool',
		    help => N("When this option is turned on, on every startup of CUPS it is automatically made sure that

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
			     } },
			   { val => N("Edit selected host/network"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "edit";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$sharehosts->{list}} < 0);
			     } },
			   { val => N("Remove selected host/network"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "remove";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$sharehosts->{list}} < 0);
			     } },
			   { val => N("Done"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "";
				 $subdone = 1;
				 1; 
			     } },
			   ]
			 );
		    if ($buttonclicked eq "add" ||
			$buttonclicked eq "edit") {
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
			my @menu = N("Local network(s)");
			my @interfaces = 
			    printer::detect::getNetworkInterfaces();
		        foreach my $interface (@interfaces) {
			    push @menu, N("Interface \"%s\"", $interface);
			}
			push @menu, N("IP address of host/network:");
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
				       if ($hostchoice eq 
					    N("IP address of host/network:") &&
					   $ip =~ /^\s*$/) {
					   
					   $in->ask_warn(N("Error"), N("Host/network IP address missing."));
					   return (1,1);
				       }
				       if ($hostchoice eq 
					    N("IP address of host/network:") &&
					   !printer::main::is_network_ip($ip)) {
					   
					   $in->ask_warn(N("Error"), 
N("The entered host/network IP is not correct.\n") .
N("Examples for correct IPs:\n") .
  "192.168.100.194\n" .
  "10.0.0.*\n" .
  "10.1.*\n" .
  "192.168.100.0/24\n" .
  "192.168.100.0/255.255.255.0\n"
);
					   return (1,1);
				       }
				       if ($hostchoice eq $menu[0]) {
					   $address = '@LOCAL';
				       } elsif ($hostchoice eq $menu[-1]) {
					   $address = $ip;
				       } else {
					   ($address) =
					       grep { $hostchoice =~ /$_/ } 
					       @interfaces;
					   $address = "\@IF($address)";
				       }
				       # Check whether item is duplicate
				       if ($address ne $oldaddress &&
					   member($address,
						  @{$printer->{cupsconfig}{clientnetworks}})) {
					   $in->ask_warn(N("Error"), 
							 N("This host/network is already in the list, it cannot be added again.\n"));
					   if ($hostchoice eq 
					       N("IP address of host/network:")) {
					       return (1,1);
					   } else {
					       return (1,0);
					   }
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
			         } },
			       ],
			     )) {
			    # OK was clicked, insert new item into the list
			    if ($buttonclicked eq "add") {
				push(@{$printer->{cupsconfig}{clientnetworks}},
				     $address);
			    } else {
				@{$printer->{cupsconfig}{clientnetworks}} =
				    map { ($_ eq
					  $sharehosts->{invhash}{$choice} ?
					  $address : $_) }
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
			    grep { $_ ne $sharehosts->{invhash}{$choice} }
			    @{$printer->{cupsconfig}{clientnetworks}};
			# Refresh list of hosts
			$sharehosts = 
			    printer::main::makesharehostlist($printer);
			# We have modified the configuration now
			$printer->{cupsconfig}{customsharingsetup} = 0;
		    }
		}
		# If we have no entry in the list, we do not
		# share the local printers, mark this
		if ($#{$printer->{cupsconfig}{clientnetworks}} < 0) {
		    $printer->{cupsconfig}{localprintersshared} = 0;
		    $printer->{cupsconfig}{remotebroadcastsaccepted} = 0;
		}
	    } elsif ($buttonclicked eq "browsepoll") {
		# Show dialog to add hosts to "BrowsePoll" from
		my $subdone = 0;
		my $choice;
		while (!$subdone) {
		    # Entry should be edited when double-clicked
		    $buttonclicked = "edit";
		    $in->ask_from_
			(
			 { title => N("Accessing printers on remote CUPS servers"),
			   messages => N("Add here the CUPS servers whose printers you want to use. You only need to do this if the servers do not broadcast their printer information into the local network."),
			   ok => "",
			   cancel => "",
		         },
			 # List the hosts
			 [ { val => \$choice, format => \&translate,
			     sort => 0, separator => "####",
			     tree_expanded => 1,
			     quit_if_double_click => 1,
			     allow_empty_list => 1,
			     list => $browsepoll->{list} },
			   { val => N("Add server"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "add";
				 1; 
			     } },
			   { val => N("Edit selected server"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "edit";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$browsepoll->{list}} < 0);
			     } },
			   { val => N("Remove selected server"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "remove";
				 1; 
			     },
			     disabled => sub {
				 return ($#{$browsepoll->{list}} < 0);
			     } },
			   { val => N("Done"), 
			     type => 'button',
			     clicked_may_quit => sub {
				 $buttonclicked = "";
				 $subdone = 1;
				 1; 
			     } },
			   ]
			 );
		    if ($buttonclicked eq "add" ||
			$buttonclicked eq "edit") {
			my ($ip, $port);
			if ($buttonclicked eq "add") {
			    # Use default port
			    $port = '631';
			} else {
			    if ($browsepoll->{invhash}{$choice} =~
				/^([^:]+):([^:]+)$/) {
				# Entry to edit has IP and port
				$ip = $1;
				$port = $2;
			    } else {
				# Entry is only an IP, no port, so take
				# the default port 631
				$ip = $browsepoll->{invhash}{$choice};
				$port = '631';
			    }
			}
			# Show the dialog
			my $address;
			my $oldaddress = 
			    ($buttonclicked eq "edit" ?
			     $browsepoll->{invhash}{$choice} : "");
			if ($in->ask_from_
			    (
			     { title => N("Accessing printers on remote CUPS servers"),
			       messages => N("Enter IP address and port of the host whose printers you want to use.") . ' ' .
				   N("If no port is given, 631 will be taken as default."),
			       callbacks => {
				   complete => sub {
				       if ($ip =~ /^\s*$/) {
					   $in->ask_warn(N("Error"), N("Server IP missing!"));
					   return (1,0);
				       }
				       if ($ip !~ 
					   /^\s*(\d+\.\d+\.\d+\.\d+)\s*$/) {
					   $in->ask_warn(N("Error"), 
N("The entered IP is not correct.\n") .
N("Examples for correct IPs:\n") .
  "192.168.100.194\n" .
  "10.0.0.2\n"
);
					   return (1,0);
				       } else {
					   $ip = $1;
				       }
				       if ($port !~ /\S/) {
					   $port = '631';
				       } elsif ($port !~ /^\s*(\d+)\s*$/) {
					   $in->ask_warn(N("Error"), N("The port number should be an integer!"));
					   return (1,1);
				       } else {
					   $port = $1;
				       }
				       $address = "$ip:$port";
				       # Check whether item is duplicate
				       if ($address ne $oldaddress &&
					   member($address,
						  @{$printer->{cupsconfig}{BrowsePoll}})) {
					   $in->ask_warn(N("Error"), 
							 N("This server is already in the list, it cannot be added again.\n"));
					   return (1,0);
				       }
				       return 0;
				   },
			       },
			   },
			     # Ask for IP and port
			     [ { val => \$ip, 
				 label => N("IP address") },
			       { val => \$port, 
				 label => N("Port") },
			       ],
			     )) {
			    # OK was clicked, insert new item into the list
			    if ($buttonclicked eq "add") {
				push(@{$printer->{cupsconfig}{BrowsePoll}},
				     $address);
			    } else {
				@{$printer->{cupsconfig}{BrowsePoll}} =
				    map { ($_ eq
					  $browsepoll->{invhash}{$choice} ?
					  $address : $_) }
				        @{$printer->{cupsconfig}{BrowsePoll}};
			    }
			    # Refresh list of hosts
			    $browsepoll = 
			    printer::main::makebrowsepolllist($printer);
			    # Position the list cursor on the new/modified
			    # item
			    $choice = $browsepoll->{hash}{$address};
			}
		    } elsif ($buttonclicked eq "remove") {
			@{$printer->{cupsconfig}{BrowsePoll}} =
			    grep { $_ ne $browsepoll->{invhash}{$choice} }
			    @{$printer->{cupsconfig}{BrowsePoll}};
			# Refresh list of hosts
			$browsepoll = 
			    printer::main::makebrowsepolllist($printer);
		    }
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
		# Write state of japanese text printing mode
		printer::main::set_jap_textmode($jap_textmode);
		# Write cupsd.conf
		printer::main::write_cups_config($printer);
		my $w = 
		    $in->wait_message(N("Printerdrake"),
				      N("Restarting CUPS..."));
		printer::main::write_cupsd_conf
		    (@{$printer->{cupsconfig}{cupsd_conf}});
		undef $w;
	    }
	} else {
	    # Cancel clicked
	    $maindone = 1;
	}
    }
    printer::main::clean_cups_config($printer);
    return $retvalue;
}

sub choose_printer_type {
    my ($printer, $in, $upNetwork) = @_;
    my $havelocalnetworks = check_network($printer, $in, $upNetwork, 1) &&
	                    printer::detect::getIPsInLocalNetworks() != ();
    $printer->{str_type} = $printer_type_inv{$printer->{TYPE}};
    my $autodetect = 0;
    $autodetect = 1 if $printer->{AUTODETECT};
    my @printertypes = printer::main::printer_type($printer);
    $in->ask_from_(
		   { title => N("Select Printer Connection"),
		     messages => N("How is the printer connected?") .
			 if_($printer->{SPOOLER} eq "cups",
			  N("
Printers on remote CUPS servers do not need to be configured here; these printers will be automatically detected.")) .
			 if_(!$havelocalnetworks,
			  N("\nWARNING: No local network connection active, remote printers can neither be detected nor tested!")),
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

    my $w = $in->wait_message(N("Printerdrake"), N("Checking your system..."));

    # Auto-detect local printers   
    my @autodetected = printer::detect::local_detect();
    my $msg = do {
	if (@autodetected) {
	    my @printerlist = 
	      map {
		  my $entry = $_->{val}{DESCRIPTION};
		  $entry ||= "$_->{val}{MANUFACTURER} $_->{val}{MODEL}";
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
    return $in->ask_yesorno(N("Printerdrake"), $dialogtext, 0);
}

sub configure_new_printers {
    my ($printer, $in, $_upNetwork) = @_;

    # This procedure auto-detects local printers and checks whether
    # there is already a queue for them. If there is no queue for an
    # auto-detected printer, a queue gets set up non-interactively.

    # Experts can have weird things as self-made CUPS backends, so do not
    # automatically pollute the system with unwished queues in expert
    # mode
    return 1 if $printer->{expert};
    
    # Wait message
    my $w = $in->wait_message(N("Printerdrake"),
			       N("Searching for new printers..."));

    # When HPOJ is running, it blocks the printer ports on which it is
    # configured, so we stop it here. If it is not installed or not 
    # configured, this command has no effect.
    require services;
    services::stop("hpoj");

    # Auto-detect local printers
    my @autodetected = printer::detect::local_detect();

    # We are ready with auto-detection, so we restart HPOJ here. If it 
    # is not installed or not configured, this command has no effect.
    services::start("hpoj");

    # No printer found? So no need of new queues.
    return 1 if !@autodetected;

    # Black-list all auto-detected printers for which there is already
    # a queue
    my @blacklist;
    foreach my $queue (keys %{$printer->{configured}}) {
	# Does the URI of this installed queue match one of the autodetected
	# printers?
	my $uri = $printer->{configured}{$queue}{queuedata}{connect};
	my $p = printer::main::autodetectionentry_for_uri
	    ($uri, @autodetected);
	if (defined($p)) {
	    # Blacklist the port
	    push(@blacklist, $p->{port});
	}
    }

    # Now install queues for all auto-detected printers which have no queue
    # yet
    $printer->{noninteractive} = 1; # Suppress all interactive steps
    my $configapps = 0;
    foreach my $p (@autodetected) {
	if (!member($p->{port}, @blacklist)) {
	    # Initialize some variables for queue setup
	    $printer->{NEW} = 1;
	    $printer->{TYPE} = "LOCAL";
	    $printer->{currentqueue} = { queue    => "",
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
	    # Generate a queue name from manufacturer and model
	    my $queue;
	    my $unknown;
	    if (!$p->{val}{MANUFACTURER} || !$p->{val}{MODEL} ||
		$p->{val}{MODEL} eq N("Unknown Model")) {
		$queue = N("Printer");
		$unknown = 1;
	    } else {
		my $make = $p->{val}{MANUFACTURER};
		if ($p->{val}{SKU}) {
		    $queue = $make . $p->{val}{SKU};
		} else {
		    $queue = $make . $p->{val}{MODEL};
		}
		$queue =~ s/series//gi;
		$queue =~ s/[\s\(\)\-,]//g;
		$queue =~ s/^$make$make/$make/;
	    }
	    # Append a number if the queue name already exists
	    if ($printer->{configured}{$queue}) {
		$queue =~ s/(\d)$/$1_/;
		my $i = 1;
		while ($printer->{configured}{"$queue$i"}) {
		    $i++;
		}
		$queue .= $i;
	    }
	    $printer->{currentqueue}{queue} = $queue;
	    undef $w;
	    $w = $in->wait_message(N("Printerdrake"),
				    ($unknown ?
				     N("Configuring printer ...") :
				     N("Configuring printer \"%s\"...",
				       $printer->{currentqueue}{queue})));
	    # Do configuration of multi-function devices and look up
	    # model name in the printer database
	    setup_common($printer, $in, $p->{val}{DESCRIPTION}, $p->{port},
			 1, @autodetected) or next;
	    # Set also OLD_QUEUE field so that the subroutines for the
	    # configuration work correctly.
	    $printer->{OLD_QUEUE} = $printer->{QUEUE} =
		$printer->{currentqueue}{queue};
	    # Do the steps of queue setup
	    get_db_entry($printer, $in);
	    # Let the user choose the model manually if it could not be
	    # auto-detected.
	    if (!$printer->{DBENTRY}) {
		# Set the OLD_CHOICE to a non-existing value
		$printer->{OLD_CHOICE} = "XXX";
		# Set model selection cursor onto the "Raw Printer" entry.
		$printer->{DBENTRY} = N("Raw printer (No driver)");
		# Info about what was detected
		my $info = N("(") . if_($p->{val}{DESCRIPTION},
					$p->{val}{DESCRIPTION} . N(" on ")) .
					$p->{port} . N(")");
		# Remove wait message
		undef $w;
		# Choose the printer/driver from the list
		$printer->{DBENTRY} = 
		    $in->ask_from_treelist(N("Printer model selection"),
					   N("Which printer model do you have?") .
					   N("

Printerdrake could not determine which model your printer %s is. Please choose the correct model from the list.", $info) . " " .
					   N("If your printer is not listed, choose a compatible (see printer manual) or a similar one."), '|',
					   [ keys %printer::main::thedb ], $printer->{DBENTRY}) or next;
		if ($unknown) {
		    # Rename the queue according to the chosen model
		    $queue = $printer->{DBENTRY};
		    $queue =~ s/\|/ /g;
		    $printer->{currentqueue}{desc} = $queue;
		    $queue =~ s/series//gi;
		    $queue =~ s/[\s\(\)\-,]//g;
		    # Append a number if the queue name already exists
		    if ($printer->{configured}{$queue}) {
			$queue =~ s/(\d)$/$1_/;
			my $i = 1;
			while ($printer->{configured}{"$queue$i"}) {
			    $i++;
			}
			$queue .= $i;
		    }
		    $printer->{currentqueue}{queue} = $queue;
		    $printer->{QUEUE} = $printer->{currentqueue}{queue};
		}
		# Restore wait message
		$w = $in->wait_message(N("Printerdrake"),
					N("Configuring printer \"%s\"...",
					  $printer->{currentqueue}{queue}));
	    }
	    get_printer_info($printer, $in) or next;
	    setup_options($printer, $in) or next;
	    configure_queue($printer, $in) or next;
	    $configapps = 1;
	    # If there is no default printer set, let this one get the
	    # default
	    if (!$printer->{DEFAULT}) {
		$printer->{DEFAULT} = $printer->{QUEUE};
		printer::default::set_printer($printer);
	    }
	}
	# Delete some variables
	foreach (qw(OLD_QUEUE QUEUE TYPE str_type DBENTRY ARGS OLD_CHOICE)) {
	    $printer->{$_} = "";
	}
	$printer->{currentqueue} = {};
	$printer->{complete} = 0;
    }
    # Configure the current printer queues in applications
    undef $w;
    if ($configapps) {
	$w =
	    $in->wait_message(N("Printerdrake"),
			      N("Configuring applications..."));
	printer::main::configureapplications($printer);
	undef $w;
    }
    undef $printer->{noninteractive};
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
    if ($printer->{expert}) {
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
	    if ($printer->{expert}) {
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

Please plug in and turn on all printers connected to this machine so that it/they can be auto-detected. Also your network printer(s) and your Windows machines must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network and/or Windows-hosted printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" if you do not want to set up your printer(s) now.") : N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

Please plug in and turn on all printers connected to this machine so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" if you do not want to set up your printer(s) now.")) : 
				   ($havelocalnetworks ? N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer or connected directly to the network.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected. Also your network printer(s) must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" if you do not want to set up your printer(s) now.") : N("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" if you do not want to set up your printer(s) now."))) },
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

If you want to add, remove, or rename a printer, or if you want to change the default option settings (paper input tray, printout quality, ...), select \"Printer\" in the \"Hardware\" section of the %s Control Center.", $shortdistroname))
    }
}

sub setup_local_autoscan {
    my ($printer, $in, $upNetwork) = @_;
    my $queue = $printer->{OLD_QUEUE};
    my $expert_or_modify = $printer->{expert} || !$printer->{NEW};
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
#    $in->set_help('setupLocal') if $::isInstall;
    if ($do_auto_detect) {
	if (!$::testing &&
	    !$expert_or_modify && $printer->{AUTODETECTSMB} && !files_exist('/usr/bin/smbclient')) {
	    $in->do_pkgs->install('samba-client') or do {
		$in->ask_warn(N("Warning"),
			      N("Could not install the %s packages!",
				"Samba client") . " " .
			      N("Skipping Windows/SMB server auto-detection"));
		$printer->{AUTODETECTSMB} = 0;
		return 0 if (!$printer->{AUTODETECTLOCAL} && 
			     !$printer->{AUTODETECTNETWORK});
	    };
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
		    $menustr .= N(" on parallel port #%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr .= N(", USB printer #%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= N(", network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= N(", printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
		$menustr .= " ($p->{port})" if $printer->{expert};
		$menuentries->{$menustr} = $p->{port};
		push @str, N("Detected %s", $menustr);
	    } else {
		my $menustr;
		if ($p->{port} =~ m!^/dev/lp(\d+)$!) {
		    $menustr = N("Printer on parallel port #%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = N("USB printer #%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= N("Network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= N("Printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
		$menustr .= " ($p->{port})" if $printer->{expert};
		$menuentries->{$menustr} = $p->{port};
	    }
	}
	my @port;
	if ($printer->{expert}) {
	    @port = printer::detect::whatPrinterPort();
	  LOOP: foreach my $q (@port) {
		if (@str) {
		    foreach my $p (@autodetected) {
			last LOOP if $p->{port} eq $q;
		    }
		}
		my $menustr;
		if ($q =~ m!^/dev/lp(\d+)$!) {
		    $menustr = N("Printer on parallel port #%s", $1);
		} elsif ($q =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = N("USB printer #%s", $1);
		}
		$menustr .= " ($q)" if $printer->{expert};
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
	    my $menustr = N("Printer on parallel port #%s", $m);
	    $menustr .= " (/dev/lp$m)" if $printer->{expert};
	    $menuentries->{$menustr} = "/dev/lp$m";
	    $menustr = N("USB printer #%s", $m);
	    $menustr .= " (/dev/usb/lp$m)" if $printer->{expert};
	    $menuentries->{$menustr} = "/dev/usb/lp$m";
	}
    }
    my @menuentrieslist = sort { 
	my @prefixes = ("/dev/lp", "/dev/usb/lp", "/dev/", "socket:", 
			"smb:");
	my $first = $menuentries->{$a};
	my $second = $menuentries->{$b};
	for (my $i = 0; $i <= $#prefixes; $i++) {
	    my $firstinlist = $first =~ m!^$prefixes[$i]!;
	    my $secondinlist = $second =~ m!^$prefixes[$i]!;
	    if ($firstinlist && !$secondinlist) { return -1 };
	    if ($secondinlist && !$firstinlist) { return 1 };
	}
	return $first cmp $second;
    } keys(%$menuentries);
    my $menuchoice = "";
    my $oldmenuchoice = "";
    my $device;
    if ($printer->{configured}{$queue}) {
	my $p = printer::main::autodetectionentry_for_uri
	    ($printer->{currentqueue}{connect}, @autodetected);
	if (defined($p)) {
	    $device = $p->{port};
	    $menuchoice = { reverse %$menuentries }->{$device};
	}
    }
    if ($menuchoice eq "" && @menuentrieslist > -1) {
	$menuchoice = $menuentrieslist[0];
	$oldmenuchoice = $menuchoice;
	$device = $menuentries->{$menuchoice} if $device eq "";
    }
    if ($in) {
#	$printer->{expert} or $in->set_help('configurePrinterDev') if $::isInstall;
	if ($#menuentrieslist < 0) { # No menu entry
	    # auto-detection has failed, we must do all manually
	    $do_auto_detect = 0;
	    $printer->{MANUAL} = 1;
	    if ($printer->{expert}) {
		$device = $in->ask_from_entry(
		     N("Local Printer"),
		     N("No local printer found! To manually install a printer enter a device name/file name in the input line (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...)."),
		     { 
			 complete => sub {
			     if ($menuchoice eq "") {
				 $in->ask_warn(N("Error"), N("You must enter a device or file name!"));
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
			     N("Local Printers") :
			     N("Available printers")),
		   messages => (($do_auto_detect ?
				 ($printer->{expert} ?
				  ($#menuentrieslist == 0 ?
				   (N("The following printer was auto-detected. ") .
				    ($printer->{NEW} ?
				     N("If it is not the one you want to configure, enter a device name/file name in the input line") :
				     N("Alternatively, you can specify a device name/file name in the input line"))) :
				   (N("Here is a list of all auto-detected printers. ") .
				    ($printer->{NEW} ?
				     N("Please choose the printer you want to set up or enter a device name/file name in the input line") :
				     N("Please choose the printer to which the print jobs should go or enter a device name/file name in the input line")))) :
				  ($#menuentrieslist == 0 ?
				   (N("The following printer was auto-detected. ") .
				    ($printer->{NEW} ?
				     N("The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\".") : 
				     N("Currently, no alternative possibility is available"))) :
				   (N("Here is a list of all auto-detected printers. ") .
				    ($printer->{NEW} ?
				     N("Please choose the printer you want to set up. The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\".") :
				     N("Please choose the printer to which the print jobs should go."))))) :
				 ($printer->{expert} ?
				  N("Please choose the port that your printer is connected to or enter a device name/file name in the input line") :
				  N("Please choose the port that your printer is connected to."))) .
				if_($printer->{expert},
				    N(" (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...)."))), 
				  callbacks => {
				      complete => sub {
					  unless ($menuchoice ne "") {
					      $in->ask_warn(N("Error"), N("You must choose/enter a printer/device!"));
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
		  if_($printer->{expert}, { val => \$device }),
		  { val => \$menuchoice, list => \@menuentrieslist, 
		    not_edit => !$printer->{expert}, format => \&translate,
		    allow_empty_list => 1, type => 'list' },
		  if_(!$printer->{expert} && $do_auto_detect && $printer->{NEW}, 
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
        $in->do_pkgs->install('nc') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "nc") . " " .
		N("Aborting"));
	    return 0;
        };
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

#    $in->set_help('setupLPD') if $::isInstall;
    my ($uri, $remotehost, $remotequeue);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^lpd:/) {
	$uri = $printer->{currentqueue}{connect};
	if ($uri =~ m!^\s*lpd://([^/]+)/([^/]+)/?\s*$!) {
         $remotehost = $1;
         $remotequeue = $2;
     }
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
	$in->ask_warn(N("Error"), N("Remote host name missing!"));
	return (1,0);
    }
    if ($remotequeue eq "") {
	$in->ask_warn(N("Error"), N("Remote printer name missing!"));
	return (1,1);
    }
    return 0;
}
			      );
    #- make the DeviceURI from user input.
    $printer->{currentqueue}{connect} = "lpd://$remotehost/$remotequeue";

    #- LPD does not support filtered queues to a remote LPD server by itself
    #- It needs an additional program as "rlpr"
    if ($printer->{SPOOLER} eq 'lpd' && !$::testing &&
        !files_exist('/usr/bin/rlpr')) {
        $in->do_pkgs->install('rlpr') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "rlpr") . " " .
		N("Aborting"));
	    return 0;
        };
    }

    # Auto-detect printer model (works if host is an ethernet-connected
    # printer)
    my $modelinfo = printer::detect::getSNMPModel($remotehost);
    my $auto_hpoj;
    if (defined($modelinfo) &&
	$modelinfo->{MANUFACTURER} ne "" &&
	$modelinfo->{MODEL} ne "") {
        $in->ask_warn(N("Information"), N("Detected model: %s %s",
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

#    $in->set_help('setupSMB') if $::isInstall;
    my ($uri, $smbuser, $smbpassword, $workgroup, $smbserver, $smbserverip, $smbshare);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^smb:/) {
	$uri = $printer->{currentqueue}{connect};
	my $parameters = $1 if $uri =~ m!^\s*smb://(.*)$!;
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
	    die qq(The "smb://" URI must at least contain the server name and the share name!\n);
	}
	if (is_ip($smbserver)) {
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
	    $in->do_pkgs->install('samba-client') or do {
		$in->ask_warn(N("Error"),
			      N("Could not install the %s packages!",
				"Samba client") . " " .
			      N("Aborting"));
		return 0;
	    };
	}
	my $_w = $in->wait_message(N("Printer auto-detection"), N("Scanning network..."));
	@autodetected = printer::detect::net_smb_detect();
     my ($server, $share);
	foreach my $p (@autodetected) {
	    my $menustr;
	    if ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
             $server = $1;
             $share = $2;
         }
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
	} keys(%$menuentries);
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
	    if ($menuentries->{$menuentrieslist[0]} =~
		m!^smb://([^/:]+)/([^/:]+)$!) {
             $smbserver = $1;
             $smbshare = $2;
         }
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
	     if (!is_ip($smbserverip) && $smbserverip ne "") {
		 $in->ask_warn(N("Error"), N("IP address should be in format 1.2.3.4"));
		 return (1,1);
	     }
	     if ($smbserver eq "" && $smbserverip eq "") {
		 $in->ask_warn(N("Error"), N("Either the server name or the server's IP must be given!"));
		 return (1,0);
	     }
	     if ($smbshare eq "") {
		 $in->ask_warn(N("Error"), N("Samba share name missing!"));
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
		      ($printer->{expert} ? 
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
		 if ($menuentries->{$menuchoice} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
               $smbserver = $1;
               $smbshare = $2;
           }
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
	$in->do_pkgs->install('samba-client') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "Samba client") . " " .
		N("Aborting"));
	    return 0;
        };
    }
    $printer->{SPOOLER} eq 'cups' and printer::main::restart_queue($printer);
    1;
}

sub setup_ncp {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

#    $in->set_help('setupNCP') if $::isInstall;
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
	    die qq(The "ncp://" URI must at least contain the server name and the share name!\n);
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
	$in->ask_warn(N("Error"), N("NCP server name missing!"));
	return (1,0);
    }
    unless ($ncpqueue ne "") {
	$in->ask_warn(N("Error"), N("NCP queue name missing!"));
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

    if (!$::testing && !files_exist('/usr/bin/nprint')) {
	$in->do_pkgs->install('ncpfs') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "ncpfs") . " " .
		N("Aborting"));
	    return 0;
        };
    } 
    1;
}

sub setup_socket {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

#    $in->set_help('setupSocket') if $::isInstall;

    my ($uri, $remotehost, $remoteport);
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~  m!^(socket:|ptal://?hpjd:)!) {
	$uri = $printer->{currentqueue}{connect};
	if ($uri =~ m!^ptal:!) {
	    if ($uri =~ m!^ptal://?hpjd:([^/:]+):([0-9]+)/?\s*$!) {
		my $ptalport = $2 - 9100;
		($remotehost, $remoteport) = ($1, $ptalport);
	    } elsif ($uri =~ m!^ptal://?hpjd:([^/:]+)\s*$!) {
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
     my ($host, $port);
	foreach my $p (@autodetected) {
	    my $menustr;
	    if ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
             $host = $1;
             $port = $2;
         }
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
	} keys(%$menuentries);
	if ($printer->{configured}{$queue} &&
	    $printer->{currentqueue}{connect} =~ m!^(socket:|ptal://?hpjd:)! &&
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
	    if ($menuentries->{$menuentrieslist[0]} =~ m!^socket://([^:]+):(\d+)$!) {
             $remotehost = $1;
             $remoteport = $2;
         }
	}
	$oldmenuchoice = $menuchoice;
    }

    return 0 if !$in->ask_from_(
	 {
	     title => N("TCP/Socket Printer Options"),
	     messages => ($autodetect ?
			  N("Choose one of the auto-detected printers from the list or enter the hostname or IP and the optional port number (default is 9100) in the input fields.") :
			  N("To print to a TCP or socket printer, you need to provide the host name or IP of the printer and optionally the port number (default is 9100). On HP JetDirect servers the port number is usually 9100, on other servers it can vary. See the manual of your hardware.")),
		 callbacks => {
		 complete => sub {
		     unless ($remotehost ne "") {
			 $in->ask_warn(N("Error"), N("Printer host name or IP missing!"));
			 return (1,0);
		     }
		     unless ($remoteport =~ /^[0-9]+$/) {
			 $in->ask_warn(N("Error"), N("The port number should be an integer!"));
			 return (1,1);
		     }
		     return 0;
		 },
		 changed => sub {
		     return 0 if !$autodetect;
		     if ($oldmenuchoice ne $menuchoice) {
                   if ($menuentries->{$menuchoice} =~ m!^socket://([^:]+):(\d+)$!) {
                       $remotehost = $1;
                       $remoteport = $2;
                   }
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
        $in->do_pkgs->install('nc') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "nc") . " " .
		N("Aborting"));
	    return 0;
	}
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

#    $in->set_help('setupURI') if $::isInstall;
    return if !$in->ask_from(N("Printer Device URI"),
N("You can specify directly the URI to access the printer. The URI must fulfill either the CUPS or the Foomatic specifications. Note that not all URI types are supported by all the spoolers."), [
{ label => N("Printer Device URI"),
val => \$printer->{currentqueue}{connect},
list => [ $printer->{currentqueue}{connect},
	  "parallel:/",
	  "usb:/",
	  "serial:/",
	  "http://",
	  "ipp://",
	  "lpd://",
	  "smb://",
	  "ncp://",
	  "socket://",
	  "ptal:/mlc:",
	  "ptal:/hpjd:",
	  "file:/",
	  'postpipe:""',
	  ], not_edit => 0, sort => 0 }, ],
complete => sub {
    unless ($printer->{currentqueue}{connect} =~ /[^:]+:.+/) {
	$in->ask_warn(N("Error"), N("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );

    # Non-local printer, check network and abort if no network available
    if ($printer->{currentqueue}{connect} !~ m!^(file|parallel|usb|serial|mtink|ptal://?mlc):/! &&
        !check_network($printer, $in, $upNetwork, 0)) { 
        return 0;
    # If the chosen protocol needs additional software, install it.
    } elsif ($printer->{currentqueue}{connect} =~ /^lpd:/ &&
        $printer->{SPOOLER} eq 'lpd' &&
        !$::testing && !files_exist('/usr/bin/rlpr')) {
	# LPD does not support filtered queues to a remote LPD server by itself
	# It needs an additional program as "rlpr"
        $in->do_pkgs->install('rlpr') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "rlpr") . " " .
		N("Aborting"));
		return 0;
            };
    } elsif ($printer->{currentqueue}{connect} =~ /^smb:/ &&
        !$::testing && !files_exist('/usr/bin/smbclient')) {
	$in->do_pkgs->install('samba-client') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "Samba client") . " " .
		N("Aborting"));
		return 0;
            };
    } elsif ($printer->{currentqueue}{connect} =~ /^ncp:/ &&
	!$::testing && !files_exist('/usr/bin/nprint')) {
	$in->do_pkgs->install('ncpfs') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "ncpfs") . " " .
		N("Aborting"));
		return 0;
            };
    } elsif ($printer->{currentqueue}{connect} =~ /^socket:/ &&
	#- LPD and LPRng need netcat ('nc') to access to socket printers
	($printer->{SPOOLER} eq 'lpd' || $printer->{SPOOLER} eq 'lprng') &&
        !$::testing && !files_exist('/usr/bin/nc')) {
        $in->do_pkgs->install('nc') or do {
            $in->ask_warn(N("Error"),
		N("Could not install the %s packages!",
		  "nc") . " " .
		N("Aborting"));
		return 0;
            };
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
            $in->ask_warn(N("Information"), N("Detected model: %s %s",
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

#    $in->set_help('setupPostpipe') if $::isInstall;
    my $uri;
    my $commandline;
    my $queue = $printer->{OLD_QUEUE};
    if ($printer->{configured}{$queue} &&
	$printer->{currentqueue}{connect} =~ m/^postpipe:/) {
	$uri = $printer->{currentqueue}{connect};
	$commandline = $1 if $uri =~ m!^\s*postpipe:"(.*)"$!;
    } else {
	$commandline = "";
    }

    return if !$in->ask_from(N("Pipe into command"),
N("Here you can specify any arbitrary command line into which the job should be piped instead of being sent directly to a printer."), [
{ label => N("Command line"),
val => \$commandline }, ],
complete => sub {
    unless ($commandline ne "") {
	$in->ask_warn(N("Error"), N("A command line must be entered!"));
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
    my $w;
    if ($device =~ m!^/dev/! || $device =~ m!^socket://!) {
	# Ask user whether he has a multi-function device when he didn't
	# do auto-detection or when auto-detection failed
	my $searchunknown = N("Unknown model");
	if (!$do_auto_detect ||
	    $makemodel eq $searchunknown ||
	    $makemodel =~ /^\s*$/) {
	    local $::isWizard = 0;
	    if (!$printer->{noninteractive}) {
		$isHPOJ = $in->ask_yesorno(N("Add a new printer"),
					   N("Is your printer a multi-function device from HP or Sony (OfficeJet, PSC, LaserJet 1100/1200/1220/3200/3300 with scanner, DeskJet 450, Sony IJP-V100), an HP PhotoSmart or an HP LaserJet 2200?"), 0);
	    }
	}
	if ($makemodel =~ /HP\s+(OfficeJet|PSC|PhotoSmart|LaserJet\s+(1200|1220|2200|3200|33.0)|(DeskJet|dj)\s*450)/i ||
	    $makemodel =~ /Sony\s+IJP[\s\-]+V[\s\-]+100/i ||
	    $isHPOJ) {
	    # Install HPOJ package
	    my $hpojinstallfailed = 0;
	    if (!$::testing &&
		!files_exist(qw(/usr/sbin/ptal-mlcd
				/usr/sbin/ptal-init
				/usr/bin/xojpanel
				/usr/sbin/lsusb))) {
		$w = $in->wait_message(N("Printerdrake"),
					   N("Installing HPOJ package..."))
		    if !$printer->{noninteractive};
		$in->do_pkgs->install('hpoj', 'xojpanel', 'usbutils')
		    or do {
			$in->ask_warn(N("Warning"),
				      N("Could not install the %s packages!",
					"HPOJ") . " " .
				      N("Only printing will be possible on the %s.",
					$makemodel));
			$hpojinstallfailed = 1;
		    };
	    }
	    # Configure and start HPOJ
	    undef $w;
	    $w = $in->wait_message
		(N("Printerdrake"),
		 N("Checking device and configuring HPOJ..."))
		if !$printer->{noninteractive};
	    
	    eval {$ptaldevice = printer::main::configure_hpoj
		      ($device, @autodetected) if !$hpojinstallfailed;};

	    if (my $err = $@) {
		warn qq(HPOJ conf faillure: "$err");
		log::l(qq(HPOJ conf faillure: "$err"));
	    }

	    if ($ptaldevice) {
		# HPOJ has determined the device name, make use of it if we
		# didn't know it before
		if (!$do_auto_detect ||
		    !$makemodel ||
		    $makemodel eq $searchunknown ||
		    $makemodel =~ /^\s*$/) {
		    $makemodel = $ptaldevice;
		    $makemodel =~ s/^.*:([^:]+)$/$1/;
		    $makemodel =~ s/_/ /g;
		    if ($makemodel =~ /^\s*IJP/i) {
			$makemodel = "Sony $makemodel";
		    } else {
			$makemodel = "HP $makemodel";
		    }
		}
		# Configure scanning with SANE on the MF device
		if ($makemodel !~ /HP\s+PhotoSmart/i &&
		    $makemodel !~ /HP\s+LaserJet\s+2200/i &&
		    $makemodel !~ /HP\s+(DeskJet|dj)\s*450/i) {
		    # Install SANE
		    if (!$::testing &&
			!files_exist(qw(/usr/bin/scanimage
						   /usr/bin/xscanimage
						   /usr/bin/xsane
						   /etc/sane.d/dll.conf
						   /usr/lib/libsane-hpoj.so.1),
						if_(files_exist('/usr/bin/gimp'), 
						    '/usr/bin/xsane-gimp'))) {
			undef $w;
			$w = $in->wait_message
			    (N("Printerdrake"),
			     N("Installing SANE packages..."))
			    if !$printer->{noninteractive};
			$in->do_pkgs->install('sane-backends',
					      'sane-frontends',
					      'xsane', 'libsane-hpoj1',
					      if_($in->do_pkgs->is_installed('gimp'), 'xsane-gimp'))
			    or do {
				$in->ask_warn(N("Warning"),
					      N("Could not install the %s packages!",
						"SANE") . " " .
					      N("Scanning on the %s will not be possible.",
						$makemodel));
			    };
		    }
		    # Configure the HPOJ SANE backend
		    printer::main::config_sane();
		}
		# Configure photo card access with mtools and MToolsFM
		if (($makemodel =~ /HP\s+PhotoSmart/i ||
		     $makemodel =~ /HP\s+PSC\s*9[05]0/i ||
		     $makemodel =~ /HP\s+PSC\s*135\d/i ||
		     $makemodel =~ /HP\s+PSC\s*21[57]\d/i ||
		     $makemodel =~ /HP\s+PSC\s*22\d\d/i ||
		     $makemodel =~ /HP\s+PSC\s*2[45]\d\d/i ||
		     $makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i ||
		     $makemodel =~ /HP\s+OfficeJet\s+71[34]0/i ||
		     $makemodel =~ /HP\s+(DeskJet|dj)\s*450/i) &&
		    $makemodel !~ /HP\s+PhotoSmart\s+7150/i) {
		    # Install mtools and MToolsFM
		    if (!$::testing &&
			!files_exist(qw(/usr/bin/mdir
						  /usr/bin/mcopy
						  /usr/bin/MToolsFM
						  ))) {
			undef $w;
			$w = $in->wait_message
			    (N("Printerdrake"),
			     N("Installing mtools packages..."))
			    if !$printer->{noninteractive};
			$in->do_pkgs->install('mtools', 'mtoolsfm')
			    or do {
				$in->ask_warn(N("Warning"),
					      N("Could not install the %s packages!",
						"Mtools") . " " .
					      N("Photo memory card access on the %s will not be possible.",
						$makemodel));
			    };
		    }
		    # Configure mtools/MToolsFM for photo card access
		    printer::main::config_photocard();
		}
		
		if (!$printer->{noninteractive}) {
		    my $text = "";
		    # Inform user about how to scan with his MF device
		    $text = scanner_help($makemodel, "ptal://$ptaldevice");
		    if ($text) {
			undef $w;
			$in->ask_warn
			    (N("Scanning on your HP multi-function device"),
			     $text);
		    }
		    # Inform user about how to access photo cards with his 
		    # MF device
		    $text = photocard_help($makemodel, "ptal://$ptaldevice");
		    if ($text) {
			undef $w;
			$in->ask_warn(N("Photo memory card access on your HP multi-function device"),
				      $text);
		    }
		}
		# make the DeviceURI from $ptaldevice.
		$printer->{currentqueue}{connect} = "ptal://" . $ptaldevice;
	    } else {
		# make the DeviceURI from $device.
		$printer->{currentqueue}{connect} = $device;
	    }
	    $w = $in->wait_message
		(N("Printerdrake"),
		 N("Checking device and configuring HPOJ..."))
		if !$printer->{noninteractive} && !defined($w);
	} else {
	    # make the DeviceURI from $device.
	    $printer->{currentqueue}{connect} = $device;
	}
    } else {
	# make the DeviceURI from $device.
	$printer->{currentqueue}{connect} = $device;
    }

    if ($printer->{currentqueue}{connect} !~ /:/) {
	if ($printer->{currentqueue}{connect} =~ /usb/) {
	    $printer->{currentqueue}{connect} =
		"usb:" . $printer->{currentqueue}{connect};
	} elsif ($printer->{currentqueue}{connect} =~ /(serial|tty)/) {
	    $printer->{currentqueue}{connect} =
		"serial:" . $printer->{currentqueue}{connect};
	} elsif ($printer->{currentqueue}{connect} =~ 
		 /(printers|parallel|parport|lp\d)/) {
	    $printer->{currentqueue}{connect} =
		"parallel:" . $printer->{currentqueue}{connect};
	} else {
	    $printer->{currentqueue}{connect} =
		"file:" . $printer->{currentqueue}{connect};
	}
    }

    #- if CUPS is the spooler, make sure that CUPS knows the device
    if ($printer->{SPOOLER} eq "cups" &&
	$device !~ /^lpd:/ &&
	$device !~ /^smb:/ &&
	$device !~ /^socket:/ &&
	$device !~ /^http:/ &&
	$device !~ /^ipp:/) {
	my $_w = $in->wait_message
	    (N("Printerdrake"),
	     N("Making printer port available for CUPS..."))
	    if !$printer->{noninteractive};
	printer::main::assure_device_is_available_for_cups($ptaldevice ||
							   $device);
    }

    #- Read the printer driver database if necessary
    if (keys %printer::main::thedb == 0) {
	my $_w = $in->wait_message
	    (N("Printerdrake"), N("Reading printer database..."))
	    if !$printer->{noninteractive};
        printer::main::read_printer_db($printer, $printer->{SPOOLER});
    }

    #- Search the database entry which matches the detected printer best
    my $descr = "";
    foreach (@autodetected) {
	$device eq $_->{port} or next;
	my ($automake, $automodel, $autodescr, $autocmdset, $autosku) =
	    ($_->{val}{MANUFACTURER}, $_->{val}{MODEL},
	     $_->{val}{DESCRIPTION}, $_->{val}{'COMMAND SET'},
	     $_->{val}{SKU});
	# Clean some manufacturer's names
	my $descrmake = printer::main::clean_manufacturer_name($automake);
	if ($automake && $autosku) {
	    $descr = "$descrmake|$autosku";
	} elsif ($automake && $automodel) {
	    $descr = "$descrmake|$automodel";
	} elsif ($autodescr) {
	    $descr = $autodescr;
	    $descr =~ s/ /|/;
	} elsif ($automodel) {
	    $descr = $automodel;
	    $descr =~ s/ /|/;
	} elsif ($automake) {
	    $descr = "$descrmake|";
	}
	# Remove manufacturer's name from the beginning of the
	# description (do not do this with manufacturer names which
	# contain odd characters)
	$descr =~ s/^$descrmake\|\s*$descrmake\s*/$descrmake|/i
	    if $descrmake && 
           $descrmake !~ m![\\/\(\)\[\]\|\.\$\@\%\*\?]!;
	# Clean up the description from noise which makes the best match
	# difficult
	$descr =~ s/\s+[Ss]eries//i;
	$descr =~ s/\s+\(?[Pp]rinter\)?$//i;
	$printer->{DBENTRY} = "";
	# Try to find an exact match, check both whether the detected
	# make|model is in the make|model of the database entry and vice versa
	# If there is more than one matching database entry, the longest match
	# counts.
	my $matchlength = -100;
	foreach my $entry (keys %printer::main::thedb) {
	    # Try to match the device ID string of the auto-detection
	    if ($printer::main::thedb{$entry}{make} =~ /Generic/i) {
		# Database entry for generic printer, check printer
		# languages (command set)
		my $_cmd = $printer::main::thedb{$entry}{devidcmd};
		if ($printer::main::thedb{$entry}{model} =~ 
		    m!PCL\s*5/5e!i) {
		    # Generic PCL 5/5e Printer
		    if ($autocmdset =~
			/(^|[:,])PCL\s*\-*\s*(5|)([,;]|$)/i) {
			if ($matchlength < -50) {
			    $matchlength = -50;
			    $printer->{DBENTRY} = $entry;
			    next;
			}
		    }
		} elsif ($printer::main::thedb{$entry}{model} =~ 
		    m!PCL\s*(6|XL)!i) {
		    # Generic PCL 6/XL Printer
		    if ($autocmdset =~
			/(^|[:,])PCL\s*\-*\s*(6|XL)([,;]|$)/i) {
			if ($matchlength < -40) {
			    $matchlength = -40;
			    $printer->{DBENTRY} = $entry;
			    next;
			}
		    }
		} elsif ($printer::main::thedb{$entry}{model} =~ 
		    m!(PostScript)!i) {
		    # Generic PostScript Printer
		    if ($autocmdset =~
			/(^|[:,])(PS|POSTSCRIPT)[^:;,]*([,;]|$)/i) {
			if ($matchlength < -10) {
			    $matchlength = -10;
			    $printer->{DBENTRY} = $entry;
			    next;
			}
		    }
		}
	    } else {
		# "Real" manufacturer, check manufacturer, model, and/or
		# description
		my $matched = 1;
		my ($mfg, $mdl, $des);
		if ($mfg = $printer::main::thedb{$entry}{devidmake}) {
		    $mfg =~ s/Hewlett[-\s_]Packard/HP/i;
		    if (uc($mfg) ne uc($automake)) {
			$matched = 0;
		    }
		}
		if ($mdl = $printer::main::thedb{$entry}{devidmodel}) {
		    if ($mdl ne $automodel) {
			$matched = 0;
		    }
		}
		if ($des = $printer::main::thedb{$entry}{deviddesc}) {
		    $des =~ s/Hewlett[-\s_]Packard/HP/;
		    $des =~ s/HEWLETT[-\s_]PACKARD/HP/;    
		    if ($des ne $autodescr) {
			$matched = 0;
		    }
		}
		if ($matched && ($des || $mfg && $mdl)) {
		    # Full match to known auto-detection data
		    $printer->{DBENTRY} = $entry;
		    $matchlength = 1000;
		    last;
		}
	    }
	    # Do not search human-readable make and model names if we had an
	    # exact match or a match to the auto-detection ID string 
	    next if $matchlength >= 100;
	    # Try to match the (human-readable) make and model of the
	    # Foomatic database or of thr PPD file
	    my $dbmakemodel;
	    if ($printer->{expert}) {
		$dbmakemodel = $1 if $entry =~ m/^(.*)\|[^\|]*$/;
	    } else {
		$dbmakemodel = $entry;
	    }
	    # Don't try to match if the database entry does not provide
	    # make and model
	    next unless $dbmakemodel;
	    # If make and model match exactly, we have found the correct
	    # entry and we can stop searching human-readable makes and
	    # models
	    if (lc($dbmakemodel) eq lc($descr)) {
		$printer->{DBENTRY} = $entry;
		$matchlength = 100;
		next;
	    }
	    # Matching a part of the human-readable makes and models
	    # should only be done if the search term is not the name of
	    # an old model, otherwise the newest, not yet listed models
	    # match with the oldest model of the manufacturer (as the
	    # Epson Stylus Photo 900 with the original Epson Stylus Photo)
	    my @badsearchterms = 
		("HP|DeskJet",
		 "HP|LaserJet",
		 "HP|DesignJet",
		 "HP|OfficeJet",
		 "HP|PhotoSmart",
		 "EPSON|Stylus",
		 "EPSON|Stylus Color",
		 "EPSON|Stylus Photo",
		 "EPSON|Stylus Pro",
		 "XEROX|WorkCentre",
		 "XEROX|DocuPrint");
	    if (!member($descr, @badsearchterms)) {
		my $searchterm = $descr;
		my $lsearchterm = length($searchterm);
		$searchterm =~ s!([\\/\(\)\[\]\|\.\$\@\%\*\?])!\\$1!g;
		if ($lsearchterm > $matchlength &&
		    $dbmakemodel =~ m!$searchterm!i) {
		    $matchlength = $lsearchterm;
		    $printer->{DBENTRY} = $entry;
		}
	    }
	    if (!member($dbmakemodel, @badsearchterms)) {
		my $searchterm = $dbmakemodel;
		my $lsearchterm = length($searchterm);
		$searchterm =~ s!([\\/\(\)\[\]\|\.\$\@\%\*\?])!\\$1!g;
		if ($lsearchterm > $matchlength &&
		    $descr =~ m!$searchterm!i) {
		    $matchlength = $lsearchterm;
		    $printer->{DBENTRY} = $entry;
		}
	    }
	}
	# No matching printer found, try a best match as last mean (not
	# when generating queues non-interactively)
	if (!$printer->{noninteractive}) {
	    $printer->{DBENTRY} ||=
		bestMatchSentence($descr, keys %printer::main::thedb);
	    # If the manufacturer was not guessed correctly, discard the
	    # guess.
	    my $guessedmake = lc($1) if $printer->{DBENTRY} =~ /^([^\|]+)\|/;
	    if ($guessedmake !~ /Generic/i &&
		$descr !~ /$guessedmake/i &&
		($guessedmake ne "hp" ||
		 $descr !~ /Hewlett[\s-]+Packard/i))
            { $printer->{DBENTRY} = "" };
	}
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
#    $in->set_help('setupPrinterName') if $::isInstall;
    my $default = $printer->{currentqueue}{queue};
    $in->ask_from_(
	 { title => N("Enter Printer Name and Comments"),
	   #cancel => !$printer->{configured}{$queue} ? '' : N("Remove queue"),
	   callbacks => { complete => sub {
	       unless ($printer->{currentqueue}{queue} =~ /^\w+$/) {
		   $in->ask_warn(N("Error"), N("Name of printer should contain only letters, numbers and the underscore"));
		   return (1,0);
	       }
	       local $::isWizard = 0;
	       if ($printer->{configured}{$printer->{currentqueue}{queue}}
		   && $printer->{currentqueue}{queue} ne $default && 
		   !$in->ask_yesorno(N("Warning"), N("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
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
    if (keys %printer::main::thedb == 0) {
	my $_w = $in->wait_message(N("Printerdrake"),
				   N("Reading printer database..."))
	    if $printer->{noninteractive};
	printer::main::read_printer_db($printer, $printer->{SPOOLER});
    }
    my $_w = $in->wait_message(N("Printerdrake"),
			       N("Preparing printer database..."))
	if !$printer->{noninteractive};
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
	    if ($printer->{expert}) {
		$printer->{DBENTRY} = "$make|$model|$driverstr";
		# database key contains the "(recommended)" for the
		# recommended driver, so add it if necessary
		if (!member($printer->{DBENTRY}, 
			    keys(%printer::main::thedb))) {
		    $printer->{DBENTRY} .= " (recommended)";
		}
	    } else {
		$printer->{DBENTRY} = "$make|$model";
	    }
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} elsif ($printer->{configured}{$queue}{queuedata}{ppd}) {
	    # Do we have a native CUPS driver or a PostScript PPD file?
	    $printer->{DBENTRY} =
		printer::main::get_descr_from_ppd($printer) ||
		$printer->{DBENTRY};
	    if (!member($printer->{DBENTRY}, 
			keys(%printer::main::thedb))) {
		$printer->{DBENTRY} .= " (recommended)";
	    }
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	}
	my ($make, $model);
	if ($printer->{DBENTRY} eq "") {
	    # Point the list cursor at least to manufacturer and model of 
	    # the printer
	    $printer->{DBENTRY} = "";
	    if ($printer->{configured}{$queue}{queuedata}{foomatic}) {
		$make = uc($printer->{configured}{$queue}{queuedata}{make});
		$model = $printer->{configured}{$queue}{queuedata}{model};
	    } elsif ($printer->{configured}{$queue}{queuedata}{ppd}) {
		my $makemodel =
		    printer::main::get_descr_from_ppd($printer);
		if ($makemodel =~ m!^([^\|]+)\|([^\|]+)(|\|.*)$!) {
              $make = $1;
              $model = $2;
          }
	    }
	    foreach my $key (keys %printer::main::thedb) {
		if ($printer->{expert} &&
		    $key =~ /^$make\|$model\|.*\(recommended\)$/ ||
		    !$printer->{expert} && $key =~ /^$make\|$model$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
	if ($printer->{DBENTRY} eq "") {
	    # Exact match of make and model did not work, try to clean
	    # up the model name
	    $model =~ s/PS//;
	    $model =~ s/PostScript//i;
	    $model =~ s/Series//i;
	    foreach my $key (keys %printer::main::thedb) {
		if ($printer->{expert} && $key =~ /^$make\|$model\|.*\(recommended\)$/ ||
		    !$printer->{expert} && $key =~ /^$make\|$model$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
	if ($printer->{DBENTRY} eq "" && $make ne "") {
	    # Exact match with cleaned-up model did not work, try a best match
	    my $matchstr = "$make|$model";
	    $printer->{DBENTRY} = 
		bestMatchSentence($matchstr, keys %printer::main::thedb);
	    # If the manufacturer was not guessed correctly, discard the
	    # guess.
	    my $guessedmake = lc($1) if $printer->{DBENTRY} =~ /^([^\|]+)\|/;
	    if ($matchstr !~ /$guessedmake/i &&
		($guessedmake ne "hp" ||
		 $matchstr !~ /Hewlett[\s-]+Packard/i))
	    { $printer->{DBENTRY} = "" };
	}
	if ($printer->{DBENTRY} eq "") {
	    # Set the OLD_CHOICE to a non-existing value
	    $printer->{OLD_CHOICE} = "XXX";
	}
    } else {
	if ($printer->{expert} && $printer->{DBENTRY} !~ /(recommended)/) {
	    my ($make, $model) = $printer->{DBENTRY} =~ /^([^\|]+)\|([^\|]+)\|/;
	    foreach my $key (keys %printer::main::thedb) {
		if ($key =~ /^$make\|$model\|.*\(recommended\)$/) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	}
	$printer->{OLD_CHOICE} = $printer->{DBENTRY};
    }
    1;
}

sub is_model_correct {
    my ($printer, $in) = @_;
#    $in->set_help('chooseModel') if $::isInstall;
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
#    $in->set_help('chooseModel') if $::isInstall;
    #- Read the printer driver database if necessary
    if (keys %printer::main::thedb == 0) {
	my $_w = $in->wait_message(N("Printerdrake"),
				  N("Reading printer database..."));
        printer::main::read_printer_db($printer, $printer->{SPOOLER});
    }
    if (!member($printer->{DBENTRY}, keys(%printer::main::thedb))) {
	$printer->{DBENTRY} = N("Raw printer (No driver)");
    }
    # Choose the printer/driver from the list
    my $choice = $printer->{DBENTRY};
    my $loadppdchosen = 0;
    while (1) {
	if ($in->ask_from_({ 
	    title => N("Printer model selection"),
	    messages => N("Which printer model do you have?") .
		N("

Please check whether Printerdrake did the auto-detection of your printer model correctly. Find the correct model in the list when a wrong model or \"Raw printer\" is highlighted.") 
		. " " .
		N("If your printer is not listed, choose a compatible (see printer manual) or a similar one."),
		#cancel => (""),
		#ok => (""),
	    }, [ 
		 # List the printers/drivers
		 { val => \$choice, format => \&translate,
		   sort => 1, separator => "|", tree_expanded => 0,
		   quit_if_double_click => 1, allow_empty_list => 1,
		   list => [ keys %printer::main::thedb ] },
		 # Button to install a manufacturer-supplied PPD file
		 { clicked_may_quit =>
		       sub { 
			   $loadppdchosen = 1;
			   1; 
		       },
		   val => N("Install a manufacturer-supplied PPD file") },
		 ])) {
	    $printer->{DBENTRY} = $choice if !$loadppdchosen;
	} else {
	    return 0;
	}
	last if !$loadppdchosen;
	# Install a manufacturer-supplied PPD file
	my $ppdentry;
	if ($ppdentry = installppd($printer, $in)) {
	    $choice = $ppdentry;
	}
	$loadppdchosen = 0;
    }
    return 1;
}

sub installppd {
    my ($printer, $in) = @_;

    # Install a manufacturer-supplied PPD file

    # The dialogs to choose the PPD file should appear as extra
    # windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    my $ppdfile;
    my ($mediachoice);
    while (1) {
	# Tell user about PPD file installation
	$in->ask_from('Printerdrake',
		      N("Every PostScript printer is delivered with a PPD file which describes the printer's options and features.") . " " .
		      N("This file is usually somewhere on the CD with the Windows and Mac drivers delivered with the printer.") . " " .
		      N("You can find the PPD files also on the manufacturer's web sites.") . " " .
		      N("If you have Windows installed on your machine, you can find the PPD file on your Windows partition, too.") . "\n" .
		      N("Installing the printer's PPD file and using it when setting up the printer makes all options of the printer available which are provided by the printer's hardware") . "\n" .
		      N("Here you can choose the PPD file to be installed on your machine, it will then be used for the setup of your printer."),
		      [
		       { label => N("Install PPD file from"), 
			 val => \$mediachoice,
			 list => [N("CD-ROM"),
				  N("Floppy Disk"), 
				  N("Other place")], 
			 not_edit => 1, sort => 0 },
		       ],
		      ) or return 0;
	my $dir;
	if ($mediachoice eq N("CD-ROM")) {
	    $dir = "/mnt/cdrom";
	} elsif ($mediachoice eq N("Floppy Disk")) {
	    $dir = "/mnt/floppy";
	} elsif ($mediachoice eq N("Other place")) {
	    $dir = "/mnt";
	} else {
	    return 0;
	}
	# Let user select a PPD file from a floppy, hard disk, ...
        $ppdfile = $in->ask_file(N("Select PPD file"), "$dir");
	last if !$ppdfile;
	if (! -r $ppdfile) {
	    $in->ask_warn(N("Error"),
			  N("The PPD file %s does not exist or is unreadable!",
			    $ppdfile));
	    next;
	}
	if (! printer::main::checkppd($printer, $ppdfile)) {
	    $in->ask_warn(N("Error"),
			  N("The PPD file %s does not conform with the PPD specifications!",
			    $ppdfile));
	    next;
	}
	last;
    }

    return 0 if !$ppdfile;

    # Install the PPD file in /usr/share/cups/ppd/printerdrake/
    my $_w = $in->wait_message(N("Printerdrake"),
			       N("Installing PPD file..."));
    my $ppdentry = printer::main::installppd($printer, $ppdfile);
    undef $_w;
    return $ppdentry;
}

my %lexmarkinkjet_options = (
                             'parallel:/dev/lp0' => " -o Port=ParPort1",
                             'parallel:/dev/lp1' => " -o Port=ParPort2",
                             'parallel:/dev/lp2' => " -o Port=ParPort3",
                             'usb:/dev/usb/lp0' => " -o Port=USB1",
                             'usb:/dev/usb/lp1' => " -o Port=USB2",
                             'usb:/dev/usb/lp2' => " -o Port=USB3",
                             'file:/dev/lp0' => " -o Port=ParPort1",
                             'file:/dev/lp1' => " -o Port=ParPort2",
                             'file:/dev/lp2' => " -o Port=ParPort3",
                             'file:/dev/usb/lp0' => " -o Port=USB1",
                             'file:/dev/usb/lp1' => " -o Port=USB2",
                             'file:/dev/usb/lp2' => " -o Port=USB3",
                             );

my %drv_x125_options = (
                             'usb:/dev/usb/lp0' => " -o Device=usb_lp1",
                             'usb:/dev/usb/lp1' => " -o Device=usb_lp2",
                             'usb:/dev/usb/lp2' => " -o Device=usb_lp3",
                             'usb:/dev/usb/lp3' => " -o Device=usb_lp3",
                             'file:/dev/usb/lp0' => " -o Device=usb_lp1",
                             'file:/dev/usb/lp1' => " -o Device=usb_lp2",
                             'file:/dev/usb/lp2' => " -o Device=usb_lp3",
                             'file:/dev/usb/lp3' => " -o Device=usb_lp3",
                             );

sub get_printer_info {
    my ($printer, $in) = @_;
    my $queue = $printer->{OLD_QUEUE};
    my $oldchoice = $printer->{OLD_CHOICE};
    my $newdriver = 0;
    if (!$printer->{configured}{$queue} ||    # New queue  or
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
	$printer->{currentqueue}{ppd}) { # We have a PPD queue
	if ($printer->{currentqueue}{printer}) { # Foomatic queue?
	    # In case of a new queue "foomatic" was not set yet
	    $printer->{currentqueue}{foomatic} = 1;
	    $printer->{currentqueue}{ppd} = undef;
	} elsif ($printer->{currentqueue}{ppd}) { # PPD queue?
	    # If we had a Foomatic queue before, unmark the flag and
	    # initialize the "printer" and "driver" fields
	    $printer->{currentqueue}{foomatic} = 0;
	    $printer->{currentqueue}{printer} = undef;
	    $printer->{currentqueue}{driver} = "PPD";
	}
	# Now get the options for this printer/driver combo
	if ($printer->{configured}{$queue} && 
	    ($printer->{configured}{$queue}{queuedata}{foomatic} ||
	     $printer->{configured}{$queue}{queuedata}{ppd})) {
	    if (!$newdriver) {
		# The user didn't change the printer/driver
		$printer->{ARGS} = $printer->{configured}{$queue}{args};
	    } elsif ($printer->{currentqueue}{foomatic}) {
		# The queue was already configured with Foomatic ...
		# ... and the user has chosen another printer/driver
		$printer->{ARGS} = 
		    printer::main::read_foomatic_options($printer);
	    } elsif ($printer->{currentqueue}{ppd}) {
		# ... and the user has chosen another printer/driver
		$printer->{ARGS} = 
		    printer::main::read_ppd_options($printer);
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
		if ($printer->{currentqueue}{connect} !~ 
		    m!^(parallel|file):/dev/lp0$!) {
		    $in->ask_warn(N("OKI winprinter configuration"),
				  N("You are configuring an OKI laser winprinter. These printers\nuse a very special communication protocol and therefore they work only when connected to the first parallel port. When your printer is connected to another port or to a print server box please connect the printer to the first parallel port before you print a test page. Otherwise the printer will not work. Your connection type setting will be ignored by the driver."));
		}
		$printer->{currentqueue}{connect} = 'file:/dev/null';
		# Start the oki4daemon
		services::start_service_on_boot('oki4daemon');
		printer::services::start('oki4daemon');
		# Set permissions
		
		my $h = {
		    cups => sub { set_permissions('/dev/oki4drv', '660', 
						  'lp', 'sys') },
		    pdq  => sub { set_permissions('/dev/oki4drv', '666') }
		};
		my $s = $h->{$printer->{SPOOLER}} ||= 
		    sub { set_permissions('/dev/oki4drv', '660',
					  'lp', 'lp') };
		&$s;
	    } elsif ($printer->{currentqueue}{driver} eq 'lexmarkinkjet') {
		# Set "Port" option
		my $opt =
		    $lexmarkinkjet_options{$printer->{currentqueue}{connect}};
		if ($opt) {
		    $printer->{SPECIAL_OPTIONS} .= $opt;
		} else {
		    $in->ask_warn(N("Lexmark inkjet configuration"),
				  N("The inkjet printer drivers provided by Lexmark only support local printers, no printers on remote machines or print server boxes. Please connect your printer to a local port or configure it on the machine where it is connected to."));
		    return 0;
		}
		# Set device permissions
		if ($printer->{currentqueue}{connect} =~ 
		    /^\s*(file|parallel|usb):(\S*)\s*$/) {
              if ($printer->{SPOOLER} eq 'cups') {
                  set_permissions($2, '660', 'lp', 'sys');
              } elsif ($printer->{SPOOLER} eq 'pdq') {
                  set_permissions($2, '666');
              } else {
                  set_permissions($2, '660', 'lp', 'lp');
              }
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
	    } elsif ($printer->{currentqueue}{driver} eq 'drv_x125') {
		# Set "Device" option
		my $opt =
		    $drv_x125_options{$printer->{currentqueue}{connect}};
		if ($opt) {
		    $printer->{SPECIAL_OPTIONS} .= $opt;
		} else {
		    $in->ask_warn(N("Lexmark X125 configuration"),
				  N("The driver for this printer only supports printers locally connected via USB, no printers on remote machines or print server boxes. Please connect your printer to a local USB port or configure it on the machine where it is connected to."));
		    return 0;
		}
		# Set device permissions
		if ($printer->{currentqueue}{connect} =~ 
		    /^\s*(file|parallel|usb):(\S*)\s*$/) {
              if ($printer->{SPOOLER} eq 'cups') {
                  set_permissions($2, '660', 'lp', 'sys');
              } elsif ($printer->{SPOOLER} eq 'pdq') {
                  set_permissions($2, '666');
              } else {
                  set_permissions($2, '660', 'lp', 'lp');
              }
		}
		# This is needed to have the device not blocked by the
		# spooler backend.
		$printer->{currentqueue}{connect} = 'file:/dev/null';
	    } elsif ($printer->{currentqueue}{printer} eq 'HP-LaserJet_1000') {
		$in->ask_warn(N("Firmware-Upload for HP LaserJet 1000"),
			      $hp1000fwtext);
	    }
	    if ($printer->{currentqueue}{foomatic}) { # Foomatic queue?
		$printer->{ARGS} = 
		    printer::main::read_foomatic_options($printer);
	    }  elsif ($printer->{currentqueue}{ppd}) { # PPD queue?
		$printer->{ARGS} =
		    printer::main::read_ppd_options($printer);
	    }
	    delete($printer->{SPECIAL_OPTIONS});
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
	 "HWResolution",
	 "JCLResolution",
	 "Quality",
	 "PrintQuality",
	 "PrintoutQuality",
	 "QualityType",
	 "ImageType",
	 "stpImageType",
	 "EconoMode",
	 "JCLEconoMode",
	 "FastRes",
	 "JCLFastRes",
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
#    $in->set_help('setupOptions') if $::isInstall;
    if ($printer->{currentqueue}{printer} || # We have a Foomatic queue
	$printer->{currentqueue}{ppd}) { # We have a CUPS+PPD queue
	# Set up the widgets for the option dialog
	my $helptext = N("Printer default settings

You should make sure that the page size and the ink type/printing mode (if available) and also the hardware configuration of laser printers (memory, duplex unit, extra trays) are set correctly. Note that with a very high printout quality/resolution printing can get substantially slower.");
	my @widgets;
	my @userinputs;
	my @choicelists;
	my @shortchoicelists;
	my $i;
	my @oldgroup = ("", "");
	for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
	    # Do not show hidden options (member options of a forced
	    # composite option)
	    next if $printer->{ARGS}[$i]{hidden};
	    my $optshortdefault = $printer->{ARGS}[$i]{default};
	    # Should the option only show when the "Advanced" button was
	    # clicked?
	    my $advanced = ((defined($printer->{ARGS}[$i]{group}) &&
			     ($printer->{ARGS}[$i]{group} !~
			      /^(|General|.*install.*)$/i)) ||
			    (!($printer->{ARGS}[$i]{group}) &&
			     !member($printer->{ARGS}[$i]{name},
				     @simple_options)) ? 1 : 0);
	    # Group header
	    if ($printer->{ARGS}[$i]{group} ne $oldgroup[$advanced]) {
		my $_level = $#{$printer->{ARGS}[$i]{grouptrans}};
		$oldgroup[$advanced] = $printer->{ARGS}[$i]{group};
		if ($printer->{ARGS}[$i]{group}) {
		    push(@widgets,
			 { val => 
			   join(" / ", @{$printer->{ARGS}[$i]{grouptrans}}),
			   advanced => $advanced });
		}
	    }
	    if ($printer->{ARGS}[$i]{type} eq 'enum') {
		# enumerated option
		$choicelists[$i] = [];
		$shortchoicelists[$i] = [];
		foreach my $choice (@{$printer->{ARGS}[$i]{vals}}) {
		    push(@{$choicelists[$i]}, $choice->{comment});
		    push(@{$shortchoicelists[$i]}, $choice->{value});
		    if ($choice->{value} eq $optshortdefault) {
			$userinputs[$i] = $choice->{comment};
		    }
		}
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment}, 
		       val => \$userinputs[$i], 
		       not_edit => 1,
		       list => \@{$choicelists[$i]},
		       sort => 0,
		       advanced => $advanced,
		       help => $helptext })
		    if ($printer->{ARGS}[$i]{name} ne 'PageRegion');
	    } elsif ($printer->{ARGS}[$i]{type} eq 'bool') {
		# boolean option
		$choicelists[$i] = [($printer->{ARGS}[$i]{comment_true} ||
				     $printer->{ARGS}[$i]{name} || "Yes"),
				    ($printer->{ARGS}[$i]{comment_false} ||
				     $printer->{ARGS}[$i]{name_false} ||
				     "No")];
		$shortchoicelists[$i] = [];
		my $numdefault = 
		    ($optshortdefault =~ m!^\s*(true|on|yes|1)\s*$! ? 
		     "1" : "0");
		$userinputs[$i] = $choicelists[$i][1-$numdefault];
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment},
		       val => \$userinputs[$i],
		       not_edit => 1,
		       list => \@{$choicelists[$i]},
		       sort => 0,
		       advanced => $advanced,
		       help => $helptext });
	    } else {
		# numerical option
		$choicelists[$i] = [];
		$shortchoicelists[$i] = [];
		$userinputs[$i] = $optshortdefault;
		push(@widgets,
		     { label => $printer->{ARGS}[$i]{comment} . 
			   " ($printer->{ARGS}[$i]{min}... " .
			       "$printer->{ARGS}[$i]{max})",
			   #type => 'range',
			   #min => $printer->{ARGS}[$i]{min},
			   #max => $printer->{ARGS}[$i]{max},
			   val => \$userinputs[$i],
			   advanced => $advanced,
			   help => $helptext });
	    }
	}
	# Show the options dialog. The call-back function does a
	# range check of the numerical options.
	my $windowtitle = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
	if ($printer->{expert}) {
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
			$driver = $1 if $printer->{DBENTRY} =~ /^[^\|]*\|[^\|]*\|(.*)$/;
		    } else {
			$driver = printer::main::get_descr_from_ppd($printer);
			if ($driver =~ /^[^\|]*\|[^\|]*$/) { # No driver info
			    $driver = "PPD";
			} else {
			    $driver = $1 if $driver =~ /^[^\|]*\|[^\|]*\|(.*)$/;
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
	if ((!$printer->{NEW} || $printer->{expert} || $printer->{MANUAL}) &&
	    !$printer->{noninteractive}) {
	    return 0 if !$in->ask_from(
		 $windowtitle,
		 N("Printer default settings"),
		 \@widgets,
		 complete => sub {
		     my $i;
		     for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
			 if ($printer->{ARGS}[$i]{type} eq 'int' || $printer->{ARGS}[$i]{type} eq 'float') {
			     if ($printer->{ARGS}[$i]{type} eq 'int' && $userinputs[$i] !~ /^[\-\+]?[0-9]+$/) {
				 $in->ask_warn(N("Error"), N("Option %s must be an integer number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     if ($printer->{ARGS}[$i]{type} eq 'float' && $userinputs[$i] !~ /^[\-\+]?[0-9\.]+$/) {
				 $in->ask_warn(N("Error"), N("Option %s must be a number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     if ($userinputs[$i] < $printer->{ARGS}[$i]{min} || $userinputs[$i] > $printer->{ARGS}[$i]{max}) {
				 $in->ask_warn(N("Error"), N("Option %s out of range!", $printer->{ARGS}[$i]{comment}));
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
	    # We did not show hidden options, so we do not have user input 
	    # to add to the option list
	    next if $printer->{ARGS}[$i]{hidden};
	    push(@{$printer->{currentqueue}{options}}, "-o");
	    if ($printer->{ARGS}[$i]{type} eq 'enum') {
		# enumerated option
		my $j;
		for ($j = 0; $j <= $#{$choicelists[$i]}; $j++) {
		    if ($choicelists[$i][$j] eq $userinputs[$i]) {
			$printer->{ARGS}[$i]{default} =
			    $shortchoicelists[$i][$j];
			push(@{$printer->{currentqueue}{options}},
			     $printer->{ARGS}[$i]{name} . "=" .
			     $shortchoicelists[$i][$j]);
		    }
		}
	    } elsif ($printer->{ARGS}[$i]{type} eq 'bool') {
		# boolean option
		my $v = 
		    ($choicelists[$i][0] eq $userinputs[$i] ? "1" : "0");
		$printer->{ARGS}[$i]{default} = $v;
		push(@{$printer->{currentqueue}{options}},
		     $printer->{ARGS}[$i]{name} . "=" . $v);
	    } else {
		# numerical option
		$printer->{ARGS}[$i]{default} = $userinputs[$i];
		push(@{$printer->{currentqueue}{options}},
		     $printer->{ARGS}[$i]{name} . "=" . $userinputs[$i]);
	    }
	}
    }
    1;
}

sub setasdefault {
    my ($printer, $in) = @_;
#    $in->set_help('setupAsDefault') if $::isInstall;
    if ($printer->{DEFAULT} eq '' || # We have no default printer,
	                             # so set the current one as default
	$in->ask_yesorno(N("Printerdrake"), N("Do you want to set this printer (\"%s\")\nas the default printer?", $printer->{QUEUE}), 0)) { # Ask the user
	$printer->{DEFAULT} = $printer->{QUEUE};
        printer::default::set_printer($printer);
    }
}
	
sub print_testpages {
    my ($printer, $in, $upNetwork) = @_;
#    $in->set_help('printTestPages') if $::isInstall;
    # print test pages
    my $res2 = 0;
    my %options = (alta4 => 0, altletter => 0, ascii => 0, photo => 0, standard => 1);
    my %old_options = (alta4 => 0, altletter => 0, ascii => 0, photo => 0, standard => 1);
    my $oldres2 = 0;
    my $res1 = $in->ask_from_(
	 { title => N("Test pages"),
	   messages => N("Please select the test pages you want to print.
Note: the photo test page can take a rather long time to get printed and on laser printers with too low memory it can even not come out. In most cases it is enough to print the standard test page."),
	   cancel => (!$printer->{NEW} ?
		       N("Cancel") : ($::isWizard ? N("Previous") : 
				      N("No test pages"))),
	   ok => ($::isWizard ? N("Next") : N("Print")),
	   callbacks => {
	       changed => sub {
		   if ($oldres2 ne $res2) {
		       if ($res2) {
				 foreach my $opt (keys %options) {
					$options{$opt} = 0;
					$old_options{$opt} = 0;
				 }
		       }
		       $oldres2 = $res2;
		   }
		   foreach my $opt (keys %options) {
			  if ($old_options{$opt} ne $options{$opt}) {
				 if ($options{$opt}) {
					$res2 = 0;
					$oldres2 = 0;
				 }
				 $old_options{standard} = $options{standard};
			  }
		   }
		   return 0;
	       }
	   } },
	 [
	  { text => N("Standard test page"), type => 'bool',
	    val => \$options{standard} },
	  if_($printer->{expert},
	   { text => N("Alternative test page (Letter)"), type => 'bool', 
	     val => \$options{altletter} }),
	  if_($printer->{expert},
	   { text => N("Alternative test page (A4)"), type => 'bool', 
	     val => \$options{alta4} }), 
	  { text => N("Photo test page"), type => 'bool', val => \$options{photo} },
	  #{ text => N("Plain text test page"), type => 'bool',
	  #  val => \$options{ascii} }
	  if_($::isWizard,
	   { text => N("Do not print any test page"), type => 'bool', 
	     val => \$res2 })
	  ]);
    $res2 = 1 if !($options{standard} || $options{altletter} || $options{alta4} || $options{photo} || $options{ascii});
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
	    if ($printer->{SPOOLER} ne "cups" && $options{photo} && !$::testing &&
		!files_exist('/usr/bin/convert')) {
		$in->do_pkgs->install('ImageMagick')
		    or do {
			$in->ask_warn(N("Warning"),
				      N("Could not install the %s package!",
					"ImageMagick") . " " .
				      N("Skipping photo test page."));
			$options{photo} = 0;
		    };
	    }
	    # set up list of pages to print
	    $options{standard} and push @testpages, $stdtestpage;
	    $options{altletter} and push @testpages, $altlttestpage;
	    $options{alta4} and push @testpages, $alta4testpage;
	    $options{photo} and push @testpages, $phototestpage;
	    $options{ascii} and push @testpages, $asciitestpage;
	    # Nothing to print
	    return 1 if $#testpages < 0;
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
	    $in->ask_warn(N("Printerdrake"),$dialogtext);
	    return 1;
	} else {
	    $in->ask_yesorno(N("Printerdrake"), $dialogtext . N("Did it work properly?"), 1) 
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
    my $hp11000fw = "";
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
	if ($printer->{configured}{$queue}{queuedata}{printer} eq
	    'HP-LaserJet_1000') {
	    $hp11000fw = "\n\n$hp1000fwtext\n";
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
 N("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s%s

", $scanning, $photocard, $hp11000fw) . printer::main::help_output($printer, 'cups') : 
 $scanning . $photocard . $hp11000fw .
 N("Here is a list of the available printing options for the current printer:

") . printer::main::help_output($printer, 'cups')) : $scanning . $photocard . $hp11000fw);
    } elsif ($spooler eq "lprng") {
	$dialogtext =
N("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) . 
N("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
N("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -Z option=setting -Z switch" : "lpr -Z option=setting -Z switch")) .
N("To get a list of the options available for the current printer click on the \"Print option list\" button.") . $scanning . $photocard . $hp11000fw : $scanning . $photocard . $hp11000fw);
    } elsif ($spooler eq "lpd") {
	$dialogtext =
N("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
N("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
N("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
N("To get a list of the options available for the current printer click on the \"Print option list\" button.") . $scanning . $photocard . $hp11000fw : $scanning . $photocard . $hp11000fw);
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
N("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s%s

", $scanning, $photocard, $hp11000fw) . printer::main::help_output($printer, 'pdq') :
 $scanning . $photocard . $hp11000fw);
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
    if ($deviceuri =~ m!^ptal://?(.*?)$!) {
	my $ptaldevice = $1;
	if ($makemodel !~ /HP\s+PhotoSmart/i &&
	    $makemodel !~ /HP\s+LaserJet\s+2200/i &&
	    $makemodel !~ /HP\s+(DeskJet|dj)\s*450/i) {
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
    if ($deviceuri =~ m!^ptal://?(.*?)$!) {
	my $ptaldevice = $1;
	if (($makemodel =~ /HP\s+PhotoSmart/i ||
	     $makemodel =~ /HP\s+PSC\s*9[05]0/i ||
	     $makemodel =~ /HP\s+PSC\s*135\d/i ||
	     $makemodel =~ /HP\s+PSC\s*21[57]\d/i ||
	     $makemodel =~ /HP\s+PSC\s*22\d\d/i ||
	     $makemodel =~ /HP\s+PSC\s*2[45]\d\d/i ||
	     $makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i ||
	     $makemodel =~ /HP\s+OfficeJet\s+71[34]0/i ||
	     $makemodel =~ /HP\s+(DeskJet|dj)\s*450/i) &&
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

#    $in->set_help('copyQueues') if $::isInstall;
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
	$newspoolerstr = $printer::data::spoolers{$newspooler}{short_name};
	$oldspoolerstr = $printer::data::spoolers{$oldspooler}{short_name};
	foreach (@oldqueues) {
	    push @queuesselected, 1;
	    push @queueentries, { text => $_, type => 'bool', 
				   val => \$queuesselected[-1] };
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
				$in->ask_warn(N("Error"), N("Name of printer should contain only letters, numbers and the underscore"));
				return (1,0);
			    }
			    if ($printer->{configured}{$newqueue}
				&& $newqueue ne $oldqueue && 
				!$in->ask_yesorno(N("Warning"), N("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
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
    my $_w = $in->wait_message(N("Printerdrake"), 
			      N("Starting network..."));
    if ($::isInstall) {
	return ($upNetwork and 
		do { my $ret = &$upNetwork(); 
		     undef $upNetwork; 
		     sleep(1);
		     $ret });
    } else { return printer::services::start("network") }
}

sub network_configured() {
    # Do configured networks (/etc/sysconfig/network-scripts/ifcfg*) exist?
    my @netscripts =
	cat_("ls -1 $::prefix/etc/sysconfig/network-scripts/ |");
    my $netconfigured = 0;
    (/ifcfg-/ and !/(ifcfg-lo|:|rpmsave|rpmorig|rpmnew)/ and
      !/(~|\.bak)$/ and $netconfigured = 1) foreach @netscripts;
    return $netconfigured;
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

#    $in->set_help('checkNetwork') if $::isInstall;

    # First check: Do configured networks
    # (/etc/sysconfig/network-scripts/ifcfg*) exist?

    if (!$dontconfigure && !network_configured()) {
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
			     $in, $in->{netc}, $in->{mouse}, 
			     $in->{intf});
#    my ($prefix, $netcnx, $in, $o_netc, $o_mouse, $o_intf, $o_first_time, $o_noauto) = @_;
		    } else {
			system("/usr/sbin/drakconnect");
		    }
		    $go_on = network_configured();
		} else {
		    return 1;
		}
	    } else {
		return 0;
	    }
	}
    }

    # Do not try to start the network if it is not configured
    if (!network_configured()) { return 0 }

    # Second check: Is the network running?

    if (printer::detect::network_running()) { return 1 }

    # The network is configured now, start it.
    if (!start_network($in, $upNetwork) && 
	(!$dontconfigure || $::isInstall)) {
	$in->ask_warn(N("Warning"), 
($::isInstall ?
N("The network configuration done during the installation cannot be started now. Please check whether the network is accessible after booting your system and correct the configuration using the %s Control Center, section \"Network & Internet\"/\"Connection\", and afterwards set up the printer, also using the %s Control Center, section \"Hardware\"/\"Printer\"", $shortdistroname, $shortdistroname) :
N("The network access was not running and could not be started. Please check your configuration and your hardware. Then try to configure your remote printer again.")));
	return 0;
    }

    # Give a SIGHUP to the daemon and in case of CUPS do also the
    # automatic configuration of broadcasting/access permissions
    # The daemon is not really restarted but only SIGHUPped to not
    # interrupt print jobs.

    my $_w = $in->wait_message(N("Printerdrake"), 
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

#    $in->set_help('securityCheck') if $::isInstall;

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

This printing system runs a daemon (background process) which waits for print jobs and handles them. This daemon is also accessible by remote machines through the network and so it is a possible point for attacks. Therefore only a few selected daemons are started by default in this security level.

Do you really want to configure printing on this machine?",
			   $printer::data::spoolers{$spooler}{short_name},
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

#    $in->set_help('startSpoolerOnBoot') if $::isInstall;
    if (!services::starts_on_boot($service)) {
	if ($in->ask_yesorno(N("Starting the printing system at boot time"),
			     N("The printing system (%s) will not be started automatically when the machine is booted.

It is possible that the automatic starting was turned off by changing to a higher security level, because the printing system is a potential point for attacks.

Do you want to have the automatic starting of the printing system turned on again?",
		       $printer::data::spoolers{$printer->{SPOOLER}}{short_name}))) {
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
    # If the user refuses to install the spooler in high or paranoid
    # security level, exit.
    return 0 unless security_check($printer, $in, $spooler);
    return 1 if $spooler !~ /^(cups|lpd|lprng|pqd)$/; # should not happen
    my $w = $in->wait_message(N("Printerdrake"), N("Checking installed software..."));

    # "lpr" conflicts with "LPRng", remove either "LPRng" or remove "lpr"
    my $packages = $spoolers{$spooler}{packages2rm};
    if ($packages && files_exist($packages->[1])) {
	undef $w;
        $w = $in->wait_message(N("Printerdrake"), N("Removing %s ..."), $spoolers{$packages->[0]}{short_name});
        $in->do_pkgs->remove_nodeps($packages->[0])
	    or do {
		$in->ask_warn(N("Error"),
			      N("Could not remove the %s printing system!",
				$spoolers{$packages->[0]}{short_name}));
		return 0;
	    };
    }

    $packages = $spoolers{$spooler}{packages2add};
    if ($packages && !files_exist(@{$packages->[1]})) {
	undef $w;
        $w = $in->wait_message(N("Printerdrake"), N("Installing %s ..."), $spoolers{$spooler}{short_name});
        $in->do_pkgs->install(@{$packages->[0]})
	    or do {
		$in->ask_warn(N("Error"),
			      N("Could not install the %s printing system!",
				$spoolers{$spooler}{short_name}));
		return 0;
	    };
    }

    undef $w;
    
    # Start the network (especially during installation), so the
    # user can set up queues to remote printers.

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

sub assure_default_printer_is_set {
    my ($printer, $in) = @_;
    if (defined($printer->{SPOOLER}) && $printer->{SPOOLER} &&
	(!defined($printer->{DEFAULT}) || !$printer->{DEFAULT})) {
	my $_w = $in->wait_message(N("Printerdrake"),
				   N("Setting Default Printer..."));
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
}

sub setup_default_spooler {
    my ($printer, $in, $upNetwork) = @_;
    $printer->{SPOOLER} ||= 'cups';
    my $oldspooler = $printer->{SPOOLER};

    my $str_spooler = 
	$in->ask_from_listf_raw({ title => N("Select Printer Spooler"),
				  messages => N("Which printing system (spooler) do you want to use?"),
				  interactive_help_id => 'setupDefaultSpooler',
				},
				sub { translate($_[0]) },
			    [ printer::main::spooler() ],
			    $spoolers{$printer->{SPOOLER}}{long_name},
			    ) or return;
    $printer->{SPOOLER} = $spooler_inv{$str_spooler};
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
	assure_default_printer_is_set($printer, $in);
	# Configure the current printer queues in applications
	my $_w =
	    $in->wait_message(N("Printerdrake"),
			      N("Configuring applications..."));
	printer::main::configureapplications($printer);
    }
    # Save spooler choice
    printer::default::set_spooler($printer);
    return $printer->{SPOOLER};
}

sub configure_queue {
    my ($printer, $in) = @_;
    my $_w = $in->wait_message(N("Printerdrake"),
			       N("Configuring printer \"%s\"...",
				 $printer->{currentqueue}{queue}))
	if !$printer->{noninteractive};
    $printer->{complete} = 1;
    my $retval = printer::main::configure_queue($printer);
    $printer->{complete} = 0;
    if (!$retval) {
	local $::isWizard = 0;
	$in->ask_warn(N("Printerdrake"),
		      N("Failed to configure printer \"%s\"!",
			$printer->{currentqueue}{queue}));
    }
    return $retval;
}

sub install_foomatic {
    my ($in) = @_;
    if (!$::testing &&
	!files_exist(qw(/usr/bin/foomatic-configure 
			/usr/bin/foomatic-rip
			/usr/share/foomatic/db/source/driver/ljet4.xml))) {
	my $_w = $in->wait_message(N("Printerdrake"),
				   N("Installing Foomatic..."));
	$in->do_pkgs->install('foomatic-db-engine',
			      'foomatic-filters',
			      'foomatic-db') 
	    or do {
		$in->ask_warn(N("Error"),
			      N("Could not install %s packages, %s cannot be started!",
				"Foomatic", "printerdrake"));
		exit 1;
	    };
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
    my ($printer, $in, $install_step, $upNetwork) = @_;
    # $install_step is only made use of during the installation. It is
    # 0 when this function is called during the preparation of the "Summary"
    # screen and 1 when the user clicks on "Configure" on the "Summary" 
    # screen

    # Initialization of Printerdrake and queue auto-installation:
    # During installation we do this step only once, when we prepare
    # the "Summary" screen in case of detected local printers or when
    # the "Configure" button in the "Printer" entry of the "Summary"
    # screen is clicked. If the button is clicked after an automatic
    # installation of local printers or if it is clicked for the
    # second time, these steps are not repeated.
    if (!$::isInstall || !$::printerdrake_initialized) {
	init($printer, $in, $upNetwork) or return;
    }

    # Main loop: During installation we only enter it when the user has
    # clicked on the "Configure" button in the "Summary" step. We do not
    # call it during the preparation of the "Summary" screen.
    if (!$::isInstall || $install_step == 1) {
	# Ask for a spooler when none is defined yet
	$printer->{SPOOLER} ||= 
	    setup_default_spooler($printer, $in, $upNetwork) || return;
    
	# Save the default spooler
	printer::default::set_spooler($printer);

	mainwindow_interactive($printer, $in, $upNetwork);
    }
    # In the installation we call the clean-up manually when we leave 
    # the "Summary" step
    if (!$::isInstall) {
	final_cleanup($printer);
    }
}

sub init {
    my ($printer, $in, $upNetwork) = @_;

    # Initialization of Printerdrake and queue auto-installation

    # Save the user mode, so that the same one is used on the next start
    # of Printerdrake
    printer::main::set_usermode($printer->{expert});
    
    # printerdrake does not work without foomatic, and for more
    # convenience we install some more stuff
    {
	my $_w = $in->wait_message(N("Printerdrake"),
				   N("Checking installed software..."));
	if (!$::testing &&
	    !files_exist(qw(/usr/bin/foomatic-configure
			    /usr/lib/perl5/vendor_perl/5.8.0/Foomatic/DB.pm
			    /usr/bin/foomatic-rip
			    /usr/share/foomatic/db/source/driver/ljet4.xml
			    /usr/bin/escputil
			    /usr/share/printer-testpages/testprint.ps
			    /usr/bin/nmap
			    /usr/bin/scli
			    ),
			 if_(files_exist("/usr/bin/gimp"),
			     "/usr/lib/gimp/1.2/plug-ins/print")
			 )) {
	    $in->do_pkgs->install('foomatic-db-engine', 'foomatic-filters',
				  'foomatic-db', 'printer-utils',
				  'printer-testpages', 'nmap', 'scli',
				  if_($in->do_pkgs->is_installed('gimp'),
				      'gimpprint'))
		or do {
		    $in->ask_warn(N("Error"),
				  N("Could not install necessary packages, %s cannot be started!",
				    "printerdrake"));
		    exit 1;
		};
	}
	
	# only experts should be asked for the spooler
	$printer->{SPOOLER} ||= 'cups' if !$printer->{expert};
	
    }
    
    # If we have chosen a spooler, install it and mark it as default 
    # spooler
    if ($printer->{SPOOLER}) {
	return 0 unless install_spooler($printer, $in, $upNetwork);
	printer::default::set_spooler($printer);
    }
    
    # Get the default printer (Done before non-interactive queue setup,
    # so that former default is not lost)
    assure_default_printer_is_set($printer, $in);
    my $nodefault = !$printer->{DEFAULT};
    
    # Non-interactive setup of newly detected printers (This is done
    # only when not in expert mode, so we always have a spooler defined
    # here)
    configure_new_printers($printer, $in, $upNetwork);
    
    # Make sure that default printer is registered
    if ($nodefault && $printer->{DEFAULT}) {
	printer::default::set_printer($printer);
    }

    # Configure the current printer queues in applications
    my $w =
	$in->wait_message(N("Printerdrake"),
			  N("Configuring applications..."));
    printer::main::configureapplications($printer);
    undef $w;
    
    # Turn on printer autodetection by default
    $printer->{AUTODETECT} = 1;
    $printer->{AUTODETECTLOCAL} = 1;
    $printer->{AUTODETECTNETWORK} = 1;
    $printer->{AUTODETECTSMB} = 1;
    
    # Mark this part as done, it should not be done a second time.
    if ($::isInstall) {
	$::printerdrake_initialized = 1;
    }

    return 1;
}

sub mainwindow_interactive {

    my ($printer, $in, $upNetwork) = @_;

    # Control variables for the main loop
    my ($menuchoice, $cursorpos) = ('', '::');

    while (1) {
	my ($queue, $newcursorpos) = ('', 0);
	# If networking is configured, start it, but don't ask the
	# user to configure networking. We want to know whether we
	# have a local network to suppress some buttons when there is
	# no network
	my $havelocalnetworks =
	    check_network($printer, $in, $upNetwork, 1) && 
	    printer::detect::getIPsInLocalNetworks() != ();
	my $havelocalnetworks_or_expert =
	    $printer->{expert} || $havelocalnetworks;
#	$in->set_help('mainMenu') if $::isInstall;
	# Initialize the cursor position
	if ($cursorpos eq "::" && 
	    $printer->{DEFAULT} &&
	    $printer->{DEFAULT} ne "") {
	    if (defined($printer->{configured}{$printer->{DEFAULT}})) {
		$cursorpos = 
		    $printer->{configured}{$printer->{DEFAULT}}{queuedata}{menuentry} . N(" (Default)");
	    } elsif ($printer->{SPOOLER} eq "cups") {
		$cursorpos = find { /!$printer->{DEFAULT}:[^!]*$/ } printer::cups::get_formatted_remote_queues($printer);
	    }
	}
	# Generate the list of available printers
	my @printerlist = 
	    (sort(map { $printer->{configured}{$_}{queuedata}{menuentry} 
			. ($_ eq $printer->{DEFAULT} ?
			   N(" (Default)") : "") }
		  keys(%{$printer->{configured}
			 || {}})),
	     ($printer->{SPOOLER} eq "cups" ?
	      sort(printer::cups::get_formatted_remote_queues($printer)) :
	      ()));
	my $noprinters = $#printerlist < 0;
	# Position the cursor where it was before (in case
	# a button was pressed).
	$menuchoice = $cursorpos;
	# Show the main dialog
	$in->ask_from_({ 
	    title => N("Printerdrake"),
	    messages => if_(!$noprinters, N("The following printers are configured. Double-click on a printer to change its settings; to make it the default printer; or to view information about it. ")) .
		        if_(!$havelocalnetworks, N("\nWARNING: No local network connection active, remote printers can neither be detected nor tested!")),
	    cancel => (""),
	    ok => ("") },
	    # List the queues
	    [ if_(!$noprinters,
		  { val => \$menuchoice, format => \&translate,
		    sort => 0, separator => "!", tree_expanded => 1,
		    quit_if_double_click => 1, allow_empty_list => 1,
		    list => \@printerlist }),
	      { clicked_may_quit =>
		    sub { 
			# Save the cursor position
			$cursorpos = $menuchoice;
			$menuchoice = '@addprinter';
			1; 
		    },
		val => N("Add a new printer") },
	      ($printer->{SPOOLER} eq "cups" &&
	       $havelocalnetworks ?
	       ({ clicked_may_quit =>
		      sub { 
			  # Save the cursor position
			  $cursorpos = $menuchoice;
			  $menuchoice = '@refresh';
			  1;
		      },
		  val => ($noprinters ?
			  N("Display all available remote CUPS printers") :
			  N("Refresh printer list (to display all available remote CUPS printers)")) }) : ()),
	      ($printer->{SPOOLER} eq "cups" &&
	       $havelocalnetworks_or_expert ?
	       ({ clicked_may_quit =>
		      sub { 
			  # Save the cursor position
			  $cursorpos = $menuchoice;
			  $menuchoice = '@cupsconfig';
			  1;
		      },
		  val => N("CUPS configuration") }) : ()),
	      ($printer->{expert} && 
	       (files_exist(qw(/usr/bin/pdq)) ||
		files_exist(qw(/usr/lib/filters/lpf 
			       /usr/sbin/lpd))) ?
	       { clicked_may_quit =>
		     sub {
			 # Save the cursor position
			 $cursorpos = $menuchoice;
			 $menuchoice = '@spooler';
			 1;
		     },
		 val => N("Change the printing system") } :
	       ()),
	      { clicked_may_quit =>
		    sub {
			# Save the cursor position
			$cursorpos = $menuchoice;
			$menuchoice = '@usermode';
			1 
			},
			    val => ($printer->{expert} ? N("Normal Mode") :
				    N("Expert Mode")) },
	      { clicked_may_quit =>
		    sub { $menuchoice = '@quit'; 1 },
		    val => ($::isEmbedded || $::isInstall ?
			    N("Done") : N("Quit")) },
	      ]);
	# Toggle expert mode and standard mode
	if ($menuchoice eq '@usermode') {
	    $printer->{expert} = printer::main::set_usermode(!$printer->{expert});
	    # Read printer database for the new user mode
	    %printer::main::thedb = ();
	    # Modify menu entries to switch the tree
	    # structure between expert/normal mode.
	    my $spooler =
		$spoolers{$printer->{SPOOLER}}{short_name};
	    if ($printer->{expert}) {
		foreach (keys(%{$printer->{configured}})) { 
		    $printer->{configured}{$_}{queuedata}{menuentry} =~ 
			s/^/$spooler!/;
		}
		$cursorpos =~ s/^/$spooler!/;
	    } else {
		foreach (keys(%{$printer->{configured}})) { 
		    $printer->{configured}{$_}{queuedata}{menuentry} =~ 
			s/^$spooler!//;
		}
		$cursorpos =~ s/^$spooler!//;
	    }
	    next;
	}
	# Refresh printer list
	next if $menuchoice eq '@refresh';
	# Configure CUPS
	if ($menuchoice eq '@cupsconfig') {
	    config_cups($printer, $in, $upNetwork);
	    next;
	}
	# Call function to switch to another spooler
	if ($menuchoice eq '@spooler') {
	    $printer->{SPOOLER} = setup_default_spooler($printer, $in, $upNetwork) || $printer->{SPOOLER};
	    next;
	}
	# Add a new print queue
	if ($menuchoice eq '@addprinter') {
	    $newcursorpos = add_printer($printer, $in, $upNetwork);
	}
	# Edit an existing print queue
	if ($menuchoice =~ /!([^\s!:]+):[^!]*$/) {
	    # Rip the queue name out of the chosen menu entry
	    $queue = $1;
	    # Save the cursor position
	    $cursorpos = $menuchoice;
	    # Edit the queue
	    edit_printer($printer, $in, $upNetwork, $queue);
	    $newcursorpos = 1;
	}
	#- Close printerdrake
	$menuchoice eq '@quit' and last;

	if ($newcursorpos) {
	    # Set the cursor onto the current menu entry
	    $queue = $printer->{QUEUE};
	    if ($queue) {
		# Make sure that the cursor is still at the same position
		# in the main menu when one has modified something on the
		# current printer
		if (!$printer->{configured}{$printer->{QUEUE}}) {
		    my $s1 = N(" (Default)");
		    my $s2 = $s1;
		    $s2 =~ s/\(/\\(/;
		    $s2 =~ s/\)/\\)/;
		    $cursorpos .= $s1
			if $printer->{QUEUE} eq
			$printer->{DEFAULT} && $cursorpos !~ /$s2/;
		} else {
		    $cursorpos =
			$printer->{configured}{$queue}{queuedata}{menuentry} .
			($queue eq $printer->{DEFAULT} ?
			 N(" (Default)") : '');
		}
	    } else {
		$cursorpos = "::";
	    }
	} else {
	    delete($printer->{QUEUE});
	}
    }
}

sub add_printer {

    my ($printer, $in, $upNetwork) = @_;

    # The add-printer wizard of printerdrake, adds a queue for a local
    # or remote printer interactively

    # Tell subroutines that we add a new printer
    $printer->{NEW} = 1;

    # Default printer name, we do not use "lp" so that one can
    # switch the default printer under LPD without needing to
    # rename another printer.  Under LPD the alias "lp" will be
    # given to the default printer.
    my $defaultprname = N("Printer");
    
    # Determine a default name for a new printer queue
    my %queues; 
    @queues{map { split '\|', $_ } keys %{$printer->{configured}}} = ();
    my $i = '';
    while ($i < 99999) { 
	last unless exists $queues{"$defaultprname$i"};
	$i ++;
    }
    my $queue = "$defaultprname$i";

    #- Set default values for a new queue
    $printer_type_inv{$printer->{TYPE}} or 
	$printer->{TYPE} = printer::default::printer_type();
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
    #if (!$::isEmbedded && !$::isInstall &&
    if ((!$::isInstall) &&
	$in->isa('interactive::gtk')) {
	# Enter wizard mode
	$::Wizard_pix_up = "printerdrake.png";
	$::Wizard_title = N("Add a new printer");
	$::isWizard = 1;
	# Wizard welcome screen
	$::Wizard_no_previous = 1;
	undef $::Wizard_no_cancel; undef $::Wizard_finished;
	wizard_welcome($printer, $in, $upNetwork) or do {
	    wizard_close($in, 0);
	    return 0;
	};
	undef $::Wizard_no_previous;
	eval {
	    #do {
	    # eval to catch wizard cancel. The wizard stuff 
	    # should be in a separate function with steps. see 
	    # drakgw.
	    $printer->{expert} or $printer->{TYPE} = "LOCAL";
	  step_1:
	    !$printer->{expert} or choose_printer_type($printer, $in, $upNetwork) or
		goto step_0;
	  step_2:
	    setup_printer_connection($printer, $in, $upNetwork) or 
		do {
		    goto step_1 if $printer->{expert};
		    goto step_0;
		};
	  step_3:
	    if ($printer->{expert} || $printer->{MANUAL} ||
		$printer->{MORETHANONE}) {
		choose_printer_name($printer, $in) or
		    goto step_2;
	    }
	    get_db_entry($printer, $in);
	  step_3_9:
	    if (!$printer->{expert} && !$printer->{MANUAL}) {
		is_model_correct($printer, $in) or do {
		    goto step_3 if $printer->{MORETHANONE};
		    goto step_2;
		}
	    }
	  step_4:
	    # Remember DB entry for "Previous" button in wizard
	    my $dbentry = $printer->{DBENTRY};
	    if ($printer->{expert} || $printer->{MANUAL} ||
		$printer->{MANUALMODEL}) { 
		choose_model($printer, $in) or do {
		    # Restore DB entry
		    $printer->{DBENTRY} = $dbentry;
		    goto step_3_9 if $printer->{MANUALMODEL};
		    goto step_3;
		};
	    }
	    get_printer_info($printer, $in) or return 0;
	  step_5:
	    setup_options($printer, $in) or
		goto step_4;
	    configure_queue($printer, $in) or die 'wizcancel';
	    undef $printer->{MANUAL} if $printer->{MANUAL};
	    $::Wizard_no_previous = 1;
	    setasdefault($printer, $in);
	    my $_w = $in->wait_message(N("Printerdrake"),
				       N("Configuring applications..."));
	    printer::main::configureapplications($printer);
	    undef $_w;
	    my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
	    if ($testpages == 1) {
		# User was content with test pages
		# Leave wizard mode with congratulations screen
		wizard_close($in, 1);
	    } elsif ($testpages == 2) {
		# User was not content with test pages
		# Leave wizard mode without congratulations
		# screen
		wizard_close($in, 0);
		$queue = $printer->{QUEUE};
		edit_printer($printer, $in, $upNetwork, $queue);
		return 1;
	    }
	};
	wizard_close($in, 0) if $@ =~ /wizcancel/;
    } else {
	$printer->{expert} or $printer->{TYPE} = "LOCAL";
	wizard_welcome($printer, $in, $upNetwork) or return 0;
	!$printer->{expert} or choose_printer_type($printer, $in, $upNetwork) or return 0;
	setup_printer_connection($printer, $in, $upNetwork) or return 0;
	if ($printer->{expert} || $printer->{MANUAL} ||
	    $printer->{MORETHANONE}) {
	    choose_printer_name($printer, $in) or return 0;
	}
	get_db_entry($printer, $in);
	if (!$printer->{expert} && !$printer->{MANUAL}) {
	    is_model_correct($printer, $in) or return 0;
	}
	if ($printer->{expert} || $printer->{MANUAL} ||
	    $printer->{MANUALMODEL}) { 
	    choose_model($printer, $in) or return 0;
	}
	get_printer_info($printer, $in) or return 0;
	setup_options($printer, $in) or return 0;
	configure_queue($printer, $in) or return 0;
	undef $printer->{MANUAL} if $printer->{MANUAL};
	setasdefault($printer, $in);
	# Configure the current printer queue in applications
	my $_w = $in->wait_message(N("Printerdrake"),
				   N("Configuring applications..."));
	printer::main::configureapplications($printer);
	undef $_w;
	my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
	if ($testpages == 2) {
	    # User was not content with test pages
	    $queue = $printer->{QUEUE};
	    edit_printer($printer, $in, $upNetwork, $queue);
	    return 1;
	}
    };

    # Delete some variables
    cleanup($printer);

    return 1;
}

sub edit_printer {

    my ($printer, $in, $upNetwork, $queue) = @_;

    # The menu for doing modifications on an existing print queue

    # If one, we have to update the application configuration (GIMP,
    # StarOffice, ...)
    my $configapps = 0;

    # Cursor position in queue modification window
    my $modify = N("Printer options");

    # Tell subroutines that we modify the printer
    $printer->{NEW} = 0;

    while (defined($printer->{QUEUE}) || 
	   defined($queue)) {  # Do not when current queue
	                       # is deleted
	# Modify a queue, ask which part should be modified
#	$in->set_help('modifyPrinterMenu') if $::isInstall;
	# Get some info to display
	my $infoline;
	if ($printer->{configured}{$queue}) {
	    # Here we must regenerate the menu entry, because the
	    # parameters can be changed.
	    printer::main::make_menuentry($printer,$queue);
	    if ($printer->{configured}{$queue}{queuedata}{menuentry} =~
		/!([^!]+)$/) {
		$infoline = $1 .
		    ($queue eq $printer->{DEFAULT} ? N(" (Default)") : '') .
		    ($printer->{configured}{$queue}{queuedata}{desc} ?
		     ", Descr.: $printer->{configured}{$queue}{queuedata}{desc}" : '') .
		     ($printer->{configured}{$queue}{queuedata}{loc} ?
		      ", Loc.: $printer->{configured}{$queue}{queuedata}{loc}" : '') .
		      ($printer->{expert} ?
		       ", Driver: $printer->{configured}{$queue}{queuedata}{driver}" : '');
	    }
	} else {
	    # Extract the entry for a remote CUPS queue from the menu entry
	    # for it.
	    my $menuentry = find { /!$queue:[^!]*$/ } printer::cups::get_formatted_remote_queues($printer);
	    $infoline = $1 if $menuentry =~ /!([^!]+)$/;
	}
	# Mark the printer queue which we edit
	$printer->{QUEUE} = $queue;
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
			    ($printer->{expert} ?
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
			  N("Learn how to use this printer"),
			  if_($printer->{configured}{$queue}, N("Remove printer")) ] } ])) {

	    #- Copy the queue data and work on the copy
	    $printer->{currentqueue} = {};
	    my $driver;
	    if ($printer->{configured}{$queue}) {
		printer::main::copy_printer_params($printer->{configured}{$queue}{queuedata}, $printer->{currentqueue});
		#- Keep in mind the printer driver which was
		#- used, so it can be determined whether the
		#- driver is only available in expert and so
		#- for setting the options for the driver in
		#- recommended mode a special treatment has
		#- to be applied.
		$driver = $printer->{currentqueue}{driver};
	    }
	    #- keep in mind old name of queue (in case of changing)
	    $printer->{OLD_QUEUE} = $printer->{QUEUE} = $queue;
	    #- Reset some variables
	    $printer->{OLD_CHOICE} = undef;
	    $printer->{DBENTRY} = undef;
	    #- Which printer type did we have before (check 
	    #- beginning of URI)
	    if ($printer->{configured}{$queue}) {
		if ($printer->{currentqueue}{connect} =~ m!^ptal://?hpjd!) {
		    $printer->{TYPE} = "socket";
		} else {
		    foreach my $type (qw(file parallel serial usb ptal
					 mtink lpd socket smb ncp
					 postpipe)) {
			if ($printer->{currentqueue}{connect} =~
			    /^$type:/) {
			    $printer->{TYPE} = 
				($type =~ 
				 /(file|parallel|serial|usb|ptal|mtink)/ ? 
				 'LOCAL' : uc($type));
			    last;
			}
		    }
		}
	    }

	    # Do the chosen task
	    if ($modify eq N("Printer connection type")) {
		choose_printer_type($printer, $in, $upNetwork) &&
		    setup_printer_connection($printer, $in, $upNetwork) &&
		    configure_queue($printer, $in);
	    } elsif ($modify eq N("Printer name, description, location")) {
		choose_printer_name($printer, $in) &&
		    configure_queue($printer, $in) &&
		    ($configapps = 1);
		# Delete old queue when it was renamed
		if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
		    my $_w = $in->wait_message
			(N("Printerdrake"),
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
		    configure_queue($printer, $in) &&
		    ($configapps = 1);
	    } elsif ($modify eq N("Printer options")) {
		get_printer_info($printer, $in) &&
		    setup_options($printer, $in) &&
		    configure_queue($printer, $in);
	    } elsif ($modify eq N("Set this printer as the default")) {
		default_printer($printer, $in, $queue);
		$configapps = 1;
		# The "Set this printer as the default" menu entry will
		# disappear if the printer is the default, so go back to the
		# default entry
		$modify = N("Printer options");
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
	    } elsif ($modify eq N("Learn how to use this printer")) {
		printer_help($printer, $in);
	    } elsif ($modify eq N("Remove printer")) {
		if (remove_printer($printer, $in, $queue)) {
		    $configapps = 1;
		    # Let the main menu cursor go to the default
		    # position
		    delete $printer->{QUEUE};
		    undef $queue;
		}
	    }

	    # Configure the current printer queue in applications
	    if ($configapps) {
		my $_w = 
		    $in->wait_message(N("Printerdrake"),
				      N("Configuring applications..."));
		printer::main::configureapplications($printer);
	    }
	    # Delete some variables
	    cleanup($printer);
	} else {
	    # User closed the dialog

	    # Delete some variables
	    cleanup($printer);

	    last;
	}
    }
}

sub remove_printer {

    my ($printer, $in, $queue) = @_;

    # Asks the user whether he really wants to remove the selected printer
    # and, if yes, removes it. The default printer will be reassigned if
    # needed.

    if ($in->ask_yesorno
	(N("Warning"), N("Do you really want to remove the printer \"%s\"?", $queue),
	 1)) {
	my $_w = $in->wait_message
	    (N("Printerdrake"),
	     N("Removing printer \"%s\"...", $queue));
	if (printer::main::remove_queue($printer, $queue)) { 
	    # Define a new default printer if we have
	    # removed the default one
	    if ($queue eq $printer->{DEFAULT}) {
		my @k = sort(keys %{$printer->{configured}});
		$printer->{DEFAULT} = $k[0];
		printer::default::set_printer($printer) if @k;
	    }
	    return 1;
	}
    }
    return 0;
}

sub default_printer {

    my ($printer, $in, $queue) = @_;

    # Makes the given queue the default queue and gives an information
    # message

    $printer->{DEFAULT} = $queue;
    printer::default::set_printer($printer);
    $in->ask_warn(N("Default printer"),
		  N("The printer \"%s\" is set as the default printer now.",
		    $queue));
    return 1;
}

sub cleanup {
    my ($printer) = @_;
    # Clean up the $printer data structure after printer manipulations
    foreach (qw(OLD_QUEUE TYPE str_type DBENTRY ARGS 
		OLD_CHOICE MANUAL)) {
	delete($printer->{$_});
    }
    $printer->{currentqueue} = {};
    $printer->{complete} = 0;
}

sub final_cleanup {
    my ($printer) = @_;
    # Clean up the $printer data structure for auto-install log
    foreach my $queue (keys %{$printer->{configured}}) {
	foreach my $item (keys %{$printer->{configured}{$queue}}) {
	    delete($printer->{configured}{$queue}{$item}) if $item ne "queuedata";
	}
	delete($printer->{configured}{$queue}{queuedata}{menuentry});
    }
    foreach (qw(Old_queue OLD_QUEUE QUEUE TYPE str_type currentqueue DBENTRY ARGS complete OLD_CHOICE NEW MORETHANONE MANUALMODEL AUTODETECT AUTODETECTLOCAL AUTODETECTNETWORK AUTODETECTSMB noninteractive expert))
    { delete $printer->{$_} };
}

