package printerdrake;
# $Id$
use diagnostics;
use strict;


use common;
use detect_devices;
use modules;
use network;
use log;
use printer;

1;

sub choose_printer_type {
    my ($printer, $in) = @_;
    $in->set_help('configurePrinterConnected') if $::isInstall;
    my $queue = $printer->{OLD_QUEUE};
    $printer->{str_type} = $printer::printer_type_inv{$printer->{TYPE}};
    my $autodetect = 0;
    $autodetect = 1 if ($printer->{AUTODETECT});
    my @printertypes = printer::printer_type($printer);
    $in->ask_from_(
		   { title => _("Select Printer Connection"),
		     messages => _("How is the printer connected?") .
			 ($printer->{SPOOLER} eq "cups" ?
			  _("
Printers on remote CUPS servers you do not have to configure here; these printers will be automatically detected.") : ())
		     },
		   [
		    { val => \$printer->{str_type},
		      list => \@printertypes, 
		      not_edit => 1, sort => 0,
		      type => 'list' },
		    { text => _("Printer auto-detection (Local, TCP/Socket, and SMB printers)"),
		      type => 'bool', val => \$autodetect }
		    ]
		   ) or return 0;
    if ($autodetect) {
	$printer->{AUTODETECT} = 1;
    } else {
	undef $printer->{AUTODETECT};
    }
    $printer->{TYPE} = $printer::printer_type{$printer->{str_type}};
    1;
}

sub config_cups {
    my ($printer, $in, $upNetwork) = @_;

    local $::isWizard = 0;
    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('configureRemoteCUPSServer') if $::isInstall;
    my $queue = $printer->{OLD_QUEUE};
    #- hack to handle cups remote server printing,
    #- first read /etc/cups/cupsd.conf for variable BrowsePoll address:port
    my ($server, $port, $default, $autoconf);
    # Return value: 0 when nothing was changed ("Apply" never pressed), 1
    # when "Apply" was at least pressed once.
    my $retvalue = 0;
    # Read CUPS config file
    my @cupsd_conf = printer::read_cupsd_conf();
    foreach (@cupsd_conf) {
	/^\s*BrowsePoll\s+(\S+)/ and $server = $1, last;
    }
    $server =~ /([^:]*):(.*)/ and ($server, $port) = ($1, $2);
    #- Did we have automatic or manual configuration mode for CUPS
    $autoconf = printer::get_cups_autoconf();
    #- Remember the server/port/autoconf settings to check whether the user
    #- has changed them.
    my $oldserver = $server;
    my $oldport = $port;
    my $oldautoconf = $autoconf;
    
    #- then ask user for this combination and rewrite /etc/cups/cupsd.conf
    #- according to new settings. There are no other point where such
    #- information is written in this file.
    
    if ($in->ask_from_
	({ title => ($::expert ? _("CUPS configuration") :
		     _("Specify CUPS server")),
	   messages => _("To get access to printers on remote CUPS servers in your local network you do not have to configure anything; the CUPS servers inform your machine automatically about their printers. All printers currently known to your machine are listed in the \"Remote printers\" section in the main window of Printerdrake. When your CUPS server is not in your local network, you have to enter the CUPS server IP address and optionally the port number to get the printer information from the server, otherwise leave these fields blank.") .
	       ($::expert ? "\n" . _("
Normally, CUPS is automatically configured according to your network environment, so that you can access the printers on the CUPS servers in your local network. If this does not work correctly, turn off \"Automatic CUPS configuration\" and edit your file /etc/cups/cupsd.conf manually. Do not forget to restart CUPS afterwards (command: \"service cups restart\").") : ()),
	   callbacks => { complete => sub {
	       unless (!$server || network::is_ip($server)) {
		   $in->ask_warn('', _("The IP address should look like 192.168.1.20"));
		   return (1,0);
	       }
	       if ($port !~ /^\d*$/) {
		   $in->ask_warn('', _("The port number should be an integer!"));
		   return (1,1);
	       }
	       return 0;
	   } }
       },
	 [	
		{ label => _("CUPS server IP"), val => \$server },
		{ label => _("Port"), val => \$port },
		($::expert ?
		 { text => _("Automatic CUPS configuration"), type => 'bool',
		   val => \$autoconf } : ()),
	 ]
	 )) {
	# We have clicked "OK"
	$retvalue = 1;
	# Set BrowsePoll line
	if (($server ne $oldserver) || ($port ne $oldport)) {
	    $server && $port and $server = "$server:$port";
	    if ($server) {
		@cupsd_conf = 
		    map { $server and 
			      s/^\s*BrowsePoll\s+(\S+)/BrowsePoll $server/ and
			      $server = '';
			  $_ } @cupsd_conf;
		$server and push @cupsd_conf, "\nBrowsePoll $server\n";
	    } else {
		@cupsd_conf = 
		    map { s/^\s*BrowsePoll\s+(\S+)/\#BrowsePoll $1/;
			  $_ } @cupsd_conf;
	    }
	    printer::write_cupsd_conf(@cupsd_conf);
	}
	# Set auto-configuration state
	if ($autoconf != $oldautoconf) {
	    printer::set_cups_autoconf($autoconf);
	}
	# Save user settings for auto-install
	$printer->{BROWSEPOLLADDR} = $server;
	$printer->{BROWSEPOLLPORT} = $port;
	$printer->{MANUALCUPSCONFIG} = 1 - $autoconf;
    }
    return $retvalue;
}

sub setup_printer_connection {
    my ($printer, $in, $upNetwork) = @_;
    # Choose the appropriate connection config dialog
    my $done = 1;
    for ($printer->{TYPE}) {
	/LOCAL/     and setup_local_autoscan ($printer, $in, $upNetwork)
	    and last;
	/LPD/       and setup_lpd      ($printer, $in, $upNetwork) and last;
	/SOCKET/    and setup_socket   ($printer, $in, $upNetwork) and last;
	/SMB/       and setup_smb      ($printer, $in, $upNetwork) and last;
	/NCP/       and setup_ncp      ($printer, $in, $upNetwork) and last;
	/URI/       and setup_uri      ($printer, $in, $upNetwork) and last;
	/POSTPIPE/  and setup_postpipe ($printer, $in) and last;
	$done = 0; last;
    }
    return $done;
}

sub auto_detect {
    my ($local, $network, $smb) = @_;
    if ($local) {
	modules::get_probeall("usb-interface") and eval { modules::load("printer") };
	eval { modules::unload(qw(lp parport_pc parport_probe parport)) }; #- on kernel 2.4 parport has to be unloaded to probe again
	eval { modules::load(qw(parport_pc lp parport_probe)) }; #- take care as not available on 2.4 kernel (silent error).
    }
    my $b = before_leaving { eval { modules::unload("parport_probe") } }
    if $local;
    my @res = (($local ? detect_devices::whatPrinter() : ()), 
	       ($network || $smb ? printer::whatNetPrinter($network,$smb) : ()));
    @res;
}

sub first_time_dialog {
    my ($printer, $in, $upNetwork) = @_;
    return 1 if (printer::get_default_spooler () or $::isInstall);

    # Wait message
    my $w = $in->wait_message(_("Printerdrake"), 
			      _("Checking your system..."));

    # Auto-detect local printers
    my @autodetected = auto_detect (1, 0, 0);
    my @printerlist;
    my $localprinterspresent;
    if (@autodetected == ()) {
	$localprinterspresent = 0;
	push (@printerlist, _("There are no printers found which are directly connected to your machine"));
    } else {
	$localprinterspresent = 1;
	for my $printer (@autodetected) {
	    my $entry = $printer->{val}{DESCRIPTION};
	    if ($entry) {push (@printerlist, "  -  $entry\n");}
	}
	my $morethanoneprinters = ($#printerlist > 0);
	my $unknown_printers = $#autodetected - $#printerlist;
	if (@printerlist != ()) {
	    unshift (@printerlist, 
		     ($morethanoneprinters ?
		      _("The following printers\n\n") :
		      _("The following printer\n\n")));
	    if ($unknown_printers == 1) {
		push (@printerlist, _("\nand one unknown printer are "));
	    } elsif ($unknown_printers > 1) {
		push (@printerlist, _("\nand %d unknown printers are ",
				      $unknown_printers));
	    } else {
		push (@printerlist, ($morethanoneprinters ? 
				     _("\nare ") :
				     _("\nis ")));
	    }
	    push (@printerlist, _("directly connected to your system"));
	} else {
	    if ($unknown_printers == 1) {
		push (@printerlist, _("\nThere is one unknown printer directly connected to your system"));
	    } elsif ($unknown_printers > 1) {
		push (@printerlist, _("\nThere are %d unknown printers directly connected to your system",
				      $unknown_printers));
	    }
	}
    }
    push (@printerlist,
	  _(" (Make sure that all your printers are connected and turned on).\n"));
    my $localprinters = join('', @printerlist);

    # Do we have a local network?

    # If networking is configured, start it, but don't ask the user to
    # configure networking.
    my $havelocalnetworks = 
	 (check_network($printer, $in, $upNetwork, 1) && 
	  (printer::getIPsInLocalNetworks() != ()));

    # Finish building the dialog text
    my $question = ($havelocalnetworks ?
		    ($localprinterspresent ?
		     _("Do you want to enable printing on the printers mentioned above or on printers in the local network?\n") :
		     _("Do you want to enable printing on printers in the local network?\n")) :
		    ($localprinterspresent ?
		     _("Do you want to enable printing on the printers mentioned above?\n") :
		     _("Are you sure that you want to set up printing on this machine?\n")));
    my $warning = _("NOTE: Depending on the printer model and the printing system up to %d MB of additional software will be installed.", 80);
    my $dialogtext = "$localprinters\n$question\n$warning";

    # Close wait message
    undef $w;

    # Show dialog
    $in->ask_yesorno(_("Printerdrake"), $dialogtext, 0);
}

sub wizard_welcome {
    my ($printer, $in, $upNetwork) = @_;
    my $ret;
    my $autodetectlocal = 0;
    my $autodetectnetwork = 0;
    my $autodetectsmb = 0;
    # If networking is configured, start it, but don't ask the user to
    # configure networking.
    if (!check_network($printer, $in, $upNetwork, 1)) { return 0 };
    my $havelocalnetworks = (printer::getIPsInLocalNetworks() != ());
    $autodetectlocal = 1 if ($printer->{AUTODETECTLOCAL});
    $autodetectnetwork = 1 if ($printer->{AUTODETECTNETWORK} &&
			       $havelocalnetworks);
    $autodetectsmb = 1 if ($printer->{AUTODETECTSMB} &&
			   $havelocalnetworks);
    if ($in) {
	eval {
	    if ($::expert) {
		$ret = $in->ask_okcancel
		    (_("Add a new printer"),
		     _("
Welcome to the Printer Setup Wizard

This wizard allows you to install local or remote printers to be used from this machine and also from other machines in the network.

It asks you for all necessary information to set up the printer and gives you access to all available printer drivers, driver options, and printer connection types."));
	    } else {
		$ret = $in->ask_from_
		    ({title => _("Add a new printer"),
		      messages => ($printer->{SPOOLER} ne "pdq" ? 
				   ($havelocalnetworks ? _("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer, connected directly to the network or to a remote Windows machine.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected. Also your network printer(s) and you Windows machines must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network and/or Windows-hosted printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.") : _("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.")) : 
				   ($havelocalnetworks ? _("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer or connected directly to the network.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected. Also your network printer(s) must be connected and turned on.

Note that auto-detecting printers on the network takes longer than the auto-detection of only the printers connected to this machine. So turn off the auto-detection of network printers when you don't need it.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.") : _("
Welcome to the Printer Setup Wizard

This wizard will help you to install your printer(s) connected to this computer.

If you have printer(s) connected to this machine, Please plug it/them in on this computer and turn it/them on so that it/they can be auto-detected.

 Click on \"Next\" when you are ready, and on \"Cancel\" when you do not want to set up your printer(s) now.")))},
		     [
		      { text => _("Auto-detect printers connected to this machine"), type => 'bool',
			val => \$autodetectlocal},
		      ($havelocalnetworks ?
		       ({ text => _("Auto-detect printers connected directly to the local network"), type => 'bool',
			  val => \$autodetectnetwork},
			($printer->{SPOOLER} ne "pdq" ?
			 { text => _("Auto-detect printers connected to machines running Microsoft Windows"), type => 'bool',
			   val => \$autodetectsmb } : ())) : ())
		      ]);
		if ($autodetectlocal) {
		    $printer->{AUTODETECTLOCAL} = 1;
		} else {
		    undef $printer->{AUTODETECTLOCAL};
		}
		if ($autodetectnetwork) {
		    $printer->{AUTODETECTNETWORK} = 1;
		} else {
		    undef $printer->{AUTODETECTNETWORK};
		}
		if ($autodetectsmb && ($printer->{SPOOLER} ne "pdq")) {
		    $printer->{AUTODETECTSMB} = 1;
		} else {
		    undef $printer->{AUTODETECTSMB};
		}
	    }
	};
	return ($@ =~ /wizcancel/) ? 0 : $ret;
    }
}

sub wizard_congratulations {
    my ($in) = @_;
    if ($in) {
	$in->ask_okcancel(_("Local Printer"),
			  _("
Congratulations, your printer is now installed and configured!

You can print using the \"Print\" command of your application (usually in the \"File\" menu).

If you want to add, remove, or rename a printer, or if you want to change the default option settings (paper input tray, printout quality, ...), select \"Printer\" in the \"Hardware\" section of the Mandrake Control Center."))
    }
}

sub setup_local_autoscan {
    my ($printer, $in, $upNetwork) = @_;
    my (@port, @str, $device);
    my $queue = $printer->{OLD_QUEUE};
    my $expert_or_modify = ($::expert || !$printer->{NEW});
    my $do_auto_detect = 
	(($expert_or_modify &&
	  $printer->{AUTODETECT}) ||
	 (!$expert_or_modify &&
	  ($printer->{AUTODETECTLOCAL} ||
	   $printer->{AUTODETECTNETWORK} ||
	   $printer->{AUTODETECTSMB})));

    # If the user requested auto-detection of remote printers, check
    # whether the network functionality is configured and running
    if ($printer->{AUTODETECTNETWORK} || $printer->{AUTODETECTSMB}) {
	if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };
    }

    my @autodetected;
    my $menuentries = {};
    $in->set_help('setupLocal') if $::isInstall;
    if ($do_auto_detect) {
	if ((!$::testing) &&
	    (!$expert_or_modify) && ($printer->{AUTODETECTSMB}) &&
	    (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	    $in->do_pkgs->install('samba-client');
	}
	my $w = $in->wait_message(_("Printer auto-detection"), _("Detecting devices..."));
	# When HPOJ is running, it blocks the printer ports on which it is
	# configured, so we stop it here. If it is not installed or not 
	# configured, this command has no effect.
	printer::stop_service("hpoj");
	@autodetected = auto_detect($expert_or_modify ||
				    $printer->{AUTODETECTLOCAL},
				    !$expert_or_modify && 
				    $printer->{AUTODETECTNETWORK},
				    !$expert_or_modify && 
				    $printer->{AUTODETECTSMB});
	# We have more than one printer, so we must ask the user for a queue
	# name in the fully automatic printer configuration.
	$printer->{MORETHANONE} = ($#autodetected > 0);
	for my $p (@autodetected) {
	    if ($p->{val}{DESCRIPTION}) {
		my $menustr = $p->{val}{DESCRIPTION};
		if ($p->{port} =~ m!^/dev/lp(\d+)$!) {
		    $menustr .= _(" on parallel port \#%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr .= _(", USB printer \#%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= _(", network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= _(", printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
		if ($::expert) {
		    $menustr .= " ($p->{port})";
		}
		$menuentries->{$menustr} = $p->{port};
		push @str, _("Detected %s", $menustr);
	    } else {
		my $menustr;
		if ($p->{port} =~ m!^/dev/lp(\d+)$!) {
		    $menustr = _("Printer on parallel port \#%s", $1);
		} elsif ($p->{port} =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = _("USB printer \#%s", $1);
		} elsif ($p->{port} =~ m!^socket://([^:]+):(\d+)$!) {
		    $menustr .= _("Network printer \"%s\", port %s", $1, $2);
		} elsif ($p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!) {
		    $menustr .= _("Printer \"%s\" on SMB/Windows server \"%s\"", $2, $1);
		}
		if ($::expert) {
		    $menustr .= " ($p->{port})";
		}
		$menuentries->{$menustr} = $p->{port};
	    }
	}
	if ($::expert) {
	    @port = detect_devices::whatPrinterPort();
	    for my $q (@port) {
		if (@str) {
		    my $alreadyfound = 0;
		    for my $p (@autodetected) {
			if ($p->{port} eq $q) {
			    $alreadyfound = 1;
			    last;
			}
		    }
		    if ($alreadyfound) {
			next;
		    }
		}
		my $menustr;
		if ($q =~ m!^/dev/lp(\d+)$!) {
		    $menustr = _("Printer on parallel port \#%s", $1);
		} elsif ($q =~ m!^/dev/usb/lp(\d+)$!) {
		    $menustr = _("USB printer \#%s", $1);
		}
		if ($::expert) {
		    $menustr .= " ($q)";
		}
		$menuentries->{$menustr} = $q;
	    }
	}
	# We are ready with auto-detection, so we restart HPOJ here. If it 
	# is not installed or not configured, this command has no effect.
	printer::start_service("hpoj");
    } else {
	# Always ask for queue name in recommended mode when no auto-
	# detection was done
	$printer->{MORETHANONE} = ($#autodetected > 0);
	my $m;
	for ($m = 0; $m <= 2; $m++) {
	    my $menustr = _("Printer on parallel port \#%s", $m);
	    if ($::expert) {
		$menustr .= " (/dev/lp$m)";
	    }
	    $menuentries->{$menustr} = "/dev/lp$m";
	    $menustr = _("USB printer \#%s", $m);
	    if ($::expert) {
		$menustr .= " (/dev/usb/lp$m)";
	    }
	    $menuentries->{$menustr} = "/dev/usb/lp$m";
	}
    }
    my @menuentrieslist = sort { 
	my @prefixes = ("/dev/lp", "/dev/usb/lp", "/dev/", "socket:", "smb:");
	my $first = $menuentries->{$a};
	my $second = $menuentries->{$b};
	for (my $i = 0; $i <= $#prefixes; $i++) {
	    my $firstinlist = ($first =~ m!^$prefixes[$i]!);
	    my $secondinlist = ($second =~ m!^$prefixes[$i]!);
	    if (($firstinlist) && (!$secondinlist)) {return -1};
	    if (($secondinlist) && (!$firstinlist)) {return 1};
	}
	return $first cmp $second;
    } keys(%{$menuentries});
    my $menuchoice = "";
    my $oldmenuchoice = "";
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m/^file:/)) {
	# Non-HP or HP print-only device (HPOJ not used)
	$device = $printer->{currentqueue}{connect};
	$device =~ s/^file://;
	for my $p (keys %{$menuentries}) {
	    if ($device eq $menuentries->{$p}) {
		$menuchoice = $p;
		last;
	    }
	}
    } elsif (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m!^ptal:/mlc:!)) {
	# HP multi-function device (controlled by HPOJ)
	my $ptaldevice = $printer->{currentqueue}{connect};
	$ptaldevice =~ s!^ptal:/mlc:!!;
	if ($ptaldevice =~ /^par:(\d+)$/) {
	    $device = "/dev/lp$1";
	    for my $p (keys %{$menuentries}) {
		if ($device eq $menuentries->{$p}) {
		    $menuchoice = $p;
		    last;
		}
	    }
	} else {
	    my $make = lc($printer->{currentqueue}{make});
	    my $model = lc($printer->{currentqueue}{model});
	    $device = "";
	    for my $p (keys %{$menuentries}) {
		my $menumakemodel = lc($p);
		if (($menumakemodel =~ /$make/) && 
		    ($menumakemodel =~ /$model/)) {
		    $menuchoice = $p;
		    $device = $menuentries->{$p};
		    last;
		}
	    }
	}
    } elsif (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m!^(socket|smb):/!)) {
	# Ethernet-(TCP/Socket)-connected printer or printer on Windows server
	$device = $printer->{currentqueue}{connect};
	for my $p (keys %{$menuentries}) {
	    if ($device eq $menuentries->{$p}) {
		$menuchoice = $p;
		last;
	    }
	}
    } else {
	$device = "";
    }
    if (($menuchoice eq "") && (@menuentrieslist > -1)) {
	$menuchoice = $menuentrieslist[0];
	$oldmenuchoice = $menuchoice;
	if ($device eq "") {
	    $device = $menuentries->{$menuchoice};
	}
    }
    if ($in) {
	$::expert or $in->set_help('configurePrinterDev') if $::isInstall;
	if ($#menuentrieslist < 0) { # No menu entry
	    # auto-detection has failed, we must do all manually
	    $do_auto_detect = 0;
	    $printer->{MANUAL} = 1;
	    if ($::expert) {
		$device = $in->ask_from_entry
		    (_("Local Printer"),
		     _("No local printer found! To manually install a printer enter a device name/file name in the input line (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...)."),
		     { 
			 complete => sub {
			     unless ($menuchoice ne "") {
				 $in->ask_warn('', _("You must enter a device or file name!"));
				 return (1,0);
			     }
			     return 0;
			 }
		     });
		if ($device eq "") {
		    return 0;
		}
	    } else {
		$in->ask_warn(_("Printer auto-detection"),
			      _("No printer found!"));
		return 0;
	    }
	} else {
	    my $manualconf = 0;
	    $manualconf = 1 if (($printer->{MANUAL}) || (!$do_auto_detect));
	    if (!$in->ask_from_
		(
		 { title => ($expert_or_modify ?
			     _("Local Printer") :
			     _("Available printers")),
		   messages => (($do_auto_detect ?
				 ($::expert ?
				  (($#menuentrieslist == 0) ?
				   _("The following printer was auto-detected, if it is not the one you want to configure, enter a device name/file name in the input line") :
				   _("Here is a list of all auto-detected printers. Please choose the printer you want to set up or enter a device name/file name in the input line")) :
				  (($#menuentrieslist == 0) ?
				   _("The following printer was auto-detected. The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\".") :
				   _("Here is a list of all auto-detected printers. Please choose the printer you want to set up. The configuration of the printer will work fully automatically. If your printer was not correctly detected or if you prefer a customized printer configuration, turn on \"Manual configuration\"."))) :
				 ($::expert ?
				  _("Please choose the port where your printer is connected to or enter a device name/file name in the input line") :
				  _("Please choose the port where your printer is connected to."))) .
				($::expert ?
				 _(" (Parallel Ports: /dev/lp0, /dev/lp1, ..., equivalent to LPT1:, LPT2:, ..., 1st USB printer: /dev/usb/lp0, 2nd USB printer: /dev/usb/lp1, ...).") :
				 ())), 
				 callbacks => {
				     complete => sub {
					 unless ($menuchoice ne "") {
					     $in->ask_warn('', _("You must choose/enter a printer/device!"));
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
				 }},
		 [
		  ($::expert ? 
		   { val => \$device } : ()),
		  { val => \$menuchoice, list => \@menuentrieslist, 
		    not_edit => !$::expert, format => \&translate, sort => 0,
		    allow_empty_list => 1, type => 'list' },
		  (((!$::expert) && ($do_auto_detect) && ($printer->{NEW})) ? 
		   { text => _("Manual configuration"), type => 'bool',
		     val => \$manualconf } : ()),
		  ]
		 )) {
		return 0;
	    }
	    if ($device ne $menuentries->{$menuchoice}) {
		$menuchoice = "";
		$do_auto_detect = 0;
	    }
	    if ($manualconf) {
		$printer->{MANUAL} = 1;
	    } else {
		undef $printer->{MANUAL};
	    }
	}
    }

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if ((($printer->{SPOOLER} eq 'lpd') || ($printer->{SPOOLER} eq 'lprng')) &&
        (!$::testing) && ($device =~ /^socket:/) &&
        (!printer::files_exist((qw(/usr/bin/nc))))) {
        $in->do_pkgs->install('nc');
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common ($printer, $in, $menuchoice, $device, $do_auto_detect,
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
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m/^lpd:/)) {
	$uri = $printer->{currentqueue}{connect};
	$uri =~ m!^\s*lpd://([^/]+)/([^/]+)/?\s*$!;
	$remotehost = $1;
	$remotequeue = $2;
    } else {
	$remotehost = "";
	$remotequeue = "lp";
    }

    return if !$in->ask_from(_("Remote lpd Printer Options"),
_("To use a remote lpd printer, you need to supply the hostname of the printer server and the printer name on that server."), [
{ label => _("Remote host name"), val => \$remotehost },
{ label => _("Remote printer name"), val => \$remotequeue } ],
complete => sub {
    unless ($remotehost ne "") {
	$in->ask_warn('', _("Remote host name missing!"));
	return (1,0);
    }
    unless ($remotequeue ne "") {
	$in->ask_warn('', _("Remote printer name missing!"));
	return (1,1);
    }
    return 0;
}
			      );
    #- make the DeviceURI from user input.
    $printer->{currentqueue}{connect} = 
        "lpd://$remotehost/$remotequeue";

    #- LPD does not support filtered queues to a remote LPD server by itself
    #- It needs an additional program as "rlpr"
    if (($printer->{SPOOLER} eq 'lpd') && (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/rlpr))))) {
        $in->do_pkgs->install('rlpr');
    }

    # Auto-detect printer model (works if host is an ethernet-connected
    # printer)
    my $modelinfo = detect_devices::getSNMPModel ($remotehost);
    my $auto_hpoj;
    if ((defined($modelinfo)) && ($modelinfo->{MANUFACTURER} ne "")) {
        $in->ask_warn('', _("Detected model: %s %s",
                            $modelinfo->{MANUFACTURER}, $modelinfo->{MODEL}));
        $auto_hpoj = 1;
    } else {
	$auto_hpoj = 0;
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common ($printer, $in,
		  "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		  $printer->{currentqueue}{connect}, $auto_hpoj,
                  ({port => $printer->{currentqueue}{connect},
                    val => $modelinfo}));

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
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m/^smb:/)) {
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
	if ((!$::testing) &&
	    (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	    $in->do_pkgs->install('samba-client');
	}
	my $w = $in->wait_message(_("Printer auto-detection"), _("Scanning network..."));
	@autodetected = auto_detect(0, 0, 1);
	for my $p (@autodetected) {
	    my $menustr;
	    $p->{port} =~ m!^smb://([^/:]+)/([^/:]+)$!;
	    my $server = $1;
	    my $share = $2;
	    if ($p->{val}{DESCRIPTION}) {
		$menustr = $p->{val}{DESCRIPTION};
		$menustr .= _(", printer \"%s\" on server \"%s\"",
			      $share, $server);
	    } else {
		$menustr = _("Printer \"%s\" on server \"%s\"",
			     $share, $server);
	    }
	    $menuentries->{$menustr} = $p->{port};
	    if (($server eq $smbserver) &&
		($share eq $smbshare)) {
		$menuchoice = $menustr;
	    }
	}
	@menuentrieslist = sort {
	    $menuentries->{$a} cmp $menuentries->{$b};
	} keys(%{$menuentries});
	if (($printer->{configured}{$queue}) &&
	    ($printer->{currentqueue}{connect} =~ m/^smb:/) &&
	    ($menuchoice eq "")) {
	    my $menustr;
	    if ($printer->{currentqueue}{make}) {
		$menustr = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
		$menustr .= _(", printer \"%s\" on server \"%s\"",
			      $smbshare, $smbserver);
	    } else {
		$menustr = _("Printer \"%s\" on server \"%s\"",
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

    return 0 if !$in->ask_from
	(_("SMB (Windows 9x/NT) Printer Options"),
	 _("To print to a SMB printer, you need to provide the SMB host name (Note! It may be different from its TCP/IP hostname!) and possibly the IP address of the print server, as well as the share name for the printer you wish to access and any applicable user name, password, and workgroup information.") .
	 ($autodetect ? _(" If the desired printer was auto-detected, simply choose it from the list and then add user name, password, and/or workgroup if needed.") : ""),
	 [{ label => _("SMB server host"), val => \$smbserver },
	  { label => _("SMB server IP"), val => \$smbserverip },
	  { label => _("Share name"), val => \$smbshare },
	  { label => _("User name"), val => \$smbuser },
	  { label => _("Password"), val => \$smbpassword, hidden => 1 },
	  { label => _("Workgroup"), val => \$workgroup },
	  ($autodetect ?
	   { label => _("Auto-detected"),
	     val => \$menuchoice, list => \@menuentrieslist, 
	     not_edit => 0, format => \&translate, sort => 0,
	     allow_empty_list => 1, type => 'combo' }
	   : ()) ],
	 complete => sub {
	     unless ((network::is_ip($smbserverip)) || ($smbserverip eq "")) {
		 $in->ask_warn('', _("IP address should be in format 1.2.3.4"));
		 return (1,1);
	     }
	     unless (($smbserver ne "") || ($smbserverip ne "")) {
		 $in->ask_warn('', _("Either the server name or the server's IP must be given!"));
		 return (1,0);
	     }
	     unless ($smbshare ne "") {
		 $in->ask_warn('', _("Samba share name missing!"));
		 return (1,2);
	     }
	     unless ($smbpassword eq "") {
		 local $::isWizard = 0;
		 my $yes = $in->ask_yesorno
		     (_("SECURITY WARNING!"),
		      _("You are about to set up printing to a Windows account with password. Due to a fault in the architecture of the Samba client software the password is put in clear text into the command line of the Samba client used to transmit the print job to the Windows server. So it is possible for every user on this machine to display the password on the screen by issuing commands as \"ps auxwww\".

We recommend to make use of one of the following alternatives (in all cases you have to make sure that only machines from your local network have access to your Windows server, for example by means of a firewall):

Use a password-less account on your Windows server, as the \"GUEST\" account or a special account dedicated for printing. Do not remove the password protection from a personal account or the administrator account.

Set up your Windows server to make the printer available under the LPD protocol. Then set up printing from this machine with the \"%s\" connection type in Printerdrake.

", _("Printer on remote lpd server")) .
		      ($::expert ? 
		       _("Set up your Windows server to make the printer available under the IPP protocol and set up printing from this machine with the \"%s\" connection type in Printerdrake.

", _("Enter a printer device URI")) : "") .
_("Connect your printer to a Linux server and let your Windows machine(s) connect to it as a client.

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
    ($smbpassword && ":$smbpassword") . "@")), ($workgroup && ("$workgroup/")),
    ($smbserver || $smbserverip), "/$smbshare");

    if ((!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	$in->do_pkgs->install('samba-client');
    }
    $printer->{SPOOLER} eq 'cups' and printer::restart_queue($printer);
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
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m/^ncp:/)) {
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

    return 0 if !$in->ask_from(_("NetWare Printer Options"),
_("To print on a NetWare printer, you need to provide the NetWare print server name (Note! it may be different from its TCP/IP hostname!) as well as the print queue name for the printer you wish to access and any applicable user name and password."), [
{ label => _("Printer Server"), val => \$ncpserver },
{ label => _("Print Queue Name"), val => \$ncpqueue },
{ label => _("User name"), val => \$ncpuser },
{ label => _("Password"), val => \$ncppassword, hidden => 1 } ],
complete => sub {
    unless ($ncpserver ne "") {
	$in->ask_warn('', _("NCP server name missing!"));
	return (1,0);
    }
    unless ($ncpqueue ne "") {
	$in->ask_warn('', _("NCP queue name missing!"));
	return (1,1);
    }
    return 0;
}
					);
    # Generate the Foomatic URI
    $printer->{currentqueue}{connect} =
    join '', ("ncp://", ($ncpuser && ($ncpuser . 
    ($ncppassword && ":$ncppassword") . "@")),
    "$ncpserver/$ncpqueue");

    if ((!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nprint))))) {
	$in->do_pkgs->install('ncpfs');
    }

    1;
}

sub setup_socket {
    my ($printer, $in, $upNetwork) = @_;

    # Check whether the network functionality is configured and
    # running
    if (!check_network($printer, $in, $upNetwork, 0)) { return 0 };

    $in->set_help('setupSocket') if $::isInstall;

    my ($hostname, $port, $uri, $remotehost,$remoteport);
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~  m!^(socket:|ptal:/hpjd:)!)) {
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
	my $w = $in->wait_message(_("Printer auto-detection"), _("Scanning network..."));
	@autodetected = auto_detect(0, 1, 0);
	for my $p (@autodetected) {
	    my $menustr;
	    $p->{port} =~ m!^socket://([^:]+):(\d+)$!;
	    my $host = $1;
	    my $port = $2;
	    if ($p->{val}{DESCRIPTION}) {
		$menustr = $p->{val}{DESCRIPTION};
		$menustr .= _(", host \"%s\", port %s",
			      $host, $port);
	    } else {
		$menustr = _("Host \"%s\", port %s", $host, $port);
	    }
	    $menuentries->{$menustr} = $p->{port};
	    if (($host eq $remotehost) &&
		($host eq $remotehost)) {
		$menuchoice = $menustr;
	    }
	}
	@menuentrieslist = sort { 
	    $menuentries->{$a} cmp $menuentries->{$b};
	} keys(%{$menuentries});
	if (($printer->{configured}{$queue}) &&
	    ($printer->{currentqueue}{connect} =~ m!^(socket:|ptal:/hpjd:)!) &&
	    ($menuchoice eq "")) {
	    my $menustr;
	    if ($printer->{currentqueue}{make}) {
		$menustr = "$printer->{currentqueue}{make} $printer->{currentqueue}{model}";
		$menustr .= _(", host \"%s\", port %s",
			      $remotehost, $remoteport);
	    } else {
		$menustr = _("Host \"%s\", port %s",
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

    return 0 if !$in->ask_from_
	({
	     title => _("TCP/Socket Printer Options"),
	     messages => ($autodetect ?
			  _("Choose one of the auto-detected printers from the list or enter the hostname or IP and the optional port number (default is 9100) into the input fields.") :
			  _("To print to a TCP or socket printer, you need to provide the host name or IP of the printer and optionally the port number (default is 9100). On HP JetDirect servers the port number is usually 9100, on other servers it can vary. See the manual of your hardware.")),
		 callbacks => {
		 complete => sub {
		     unless ($remotehost ne "") {
			 $in->ask_warn
			     ('', _("Printer host name or IP missing!"));
			 return (1,0);
		     }
		     unless ($remoteport =~ /^[0-9]+$/) {
			 $in->ask_warn('', _("The port number should be an integer!"));
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
	  { label => ($autodetect ? "" : _("Printer host name or IP")),
	    val => \$remotehost },
	  { label => ($autodetect ? "" : _("Port")), val => \$remoteport },
	  ($autodetect ?
	   { val => \$menuchoice, list => \@menuentrieslist, 
	     not_edit => 0, format => \&translate, sort => 0,
	     allow_empty_list => 1, type => 'list' }
	   : ())
	  ]
	 );
    
    #- make the Foomatic URI
    $printer->{currentqueue}{connect} = 
	join '', ("socket://$remotehost", $remoteport ? (":$remoteport") : ());

    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if ((($printer->{SPOOLER} eq 'lpd') || ($printer->{SPOOLER} eq 'lprng'))&& 
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nc))))) {
        $in->do_pkgs->install('nc');
    }

    # Auto-detect printer model (works if host is an ethernet-connected
    # printer)
    my $modelinfo = undef;
    if ($printer->{AUTODETECT}) {
	$modelinfo = detect_devices::getSNMPModel ($remotehost);
    }
    my $auto_hpoj;
    if ((defined($modelinfo)) && ($modelinfo->{MANUFACTURER} ne "")) {
        $auto_hpoj = 1;
    } else {
	$auto_hpoj = 0;
    }

    # Do configuration of multi-function devices and look up model name
    # in the printer database
    setup_common ($printer, $in,
		  "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		  $printer->{currentqueue}{connect}, $auto_hpoj,
                  ({port => $printer->{currentqueue}{connect},
                    val => $modelinfo}));
    1;
}

sub setup_uri {
    my ($printer, $in, $upNetwork) = @_;

    $in->set_help('setupURI') if $::isInstall;
    return if !$in->ask_from(_("Printer Device URI"),
_("You can specify directly the URI to access the printer. The URI must fulfill either the CUPS or the Foomatic specifications. Note that not all URI types are supported by all the spoolers."), [
{ label => _("Printer Device URI"),
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
	$in->ask_warn('', _("A valid URI must be entered!"));
	return (1,0);
    }
    return 0;
}
    );

    # Non-local printer, check network and abort if no network available
    if (($printer->{currentqueue}{connect} !~ m!^(file|ptal):/!) &&
        (!check_network($printer, $in, $upNetwork, 0))) { return 0 };

    # If the chosen protocol needs additional software, install it.

    # LPD does not support filtered queues to a remote LPD server by itself
    # It needs an additional program as "rlpr"
    if (($printer->{currentqueue}{connect} =~ /^lpd:/) &&
	($printer->{SPOOLER} eq 'lpd') && (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/rlpr))))) {
        $in->do_pkgs->install('rlpr');
    }
    if (($printer->{currentqueue}{connect} =~ /^smb:/) &&
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/smbclient))))) {
	$in->do_pkgs->install('samba-client');
    }
    if (($printer->{currentqueue}{connect} =~ /^ncp:/) &&
	(!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nprint))))) {
	$in->do_pkgs->install('ncpfs');
    }
    #- LPD and LPRng need netcat ('nc') to access to socket printers
    if (($printer->{currentqueue}{connect} =~ /^socket:/) &&
	(($printer->{SPOOLER} eq 'lpd') || ($printer->{SPOOLER} eq 'lprng')) &&
        (!$::testing) &&
        (!printer::files_exist((qw(/usr/bin/nc))))) {
        $in->do_pkgs->install('nc');
    }

    if (($printer->{currentqueue}{connect} =~ m!^socket://([^:/]+)!) ||
        ($printer->{currentqueue}{connect} =~ m!^lpd://([^:/]+)!) ||
        ($printer->{currentqueue}{connect} =~ m!^http://([^:/]+)!) ||
        ($printer->{currentqueue}{connect} =~ m!^ipp://([^:/]+)!)) {
	
	# Auto-detect printer model (works if host is an ethernet-connected
	# printer)
	my $remotehost = $1;
	my $modelinfo = detect_devices::getSNMPModel ($remotehost);
        my $auto_hpoj;
        if ((defined($modelinfo)) && ($modelinfo->{MANUFACTURER} ne "")) {
            $in->ask_warn('', _("Detected model: %s %s",
                                $modelinfo->{MANUFACTURER},
				$modelinfo->{MODEL}));
            $auto_hpoj = 1;
        } else {
	    $auto_hpoj = 0;
        }

        # Do configuration of multi-function devices and look up model name
        # in the printer database
        setup_common ($printer, $in,
		      "$modelinfo->{MANUFACTURER} $modelinfo->{MODEL}", 
		      $printer->{currentqueue}{connect}, $auto_hpoj,
                      ({port => $printer->{currentqueue}{connect},
                        val => $modelinfo}));
    }

    1;
}

sub setup_postpipe {
    my ($printer, $in) = @_;

    $in->set_help('setupPostpipe') if $::isInstall;
    my $uri;
    my $commandline;
    my $queue = $printer->{OLD_QUEUE};
    if (($printer->{configured}{$queue}) &&
	($printer->{currentqueue}{connect} =~ m/^postpipe:/)) {
	$uri = $printer->{currentqueue}{connect};
	$uri =~ m!^\s*postpipe:\"(.*)\"$!;
	$commandline = $1;
    } else {
	$commandline = "";
    }

    return if !$in->ask_from(_("Pipe into command"),
_("Here you can specify any arbitrary command line into which the job should be piped instead of being sent directly to a printer."), [
{ label => _("Command line"),
val => \$commandline }, ],
complete => sub {
    unless ($commandline ne "") {
	$in->ask_warn('', _("A command line must be entered!"));
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

    my ($printer, $in, $makemodel, $device, $do_auto_detect,
	@autodetected) = @_;

    #- Check whether the printer is an HP multi-function device and 
    #- configure HPOJ if it is one

    my $ptaldevice = "";
    my $isHPOJ = 0;
    if (($device =~ /^\/dev\//) || ($device =~ /^socket:\/\//)) {
	# Ask user whether he has a multi-function device when he didn't
	# do auto-detection or when auto-detection failed
	my $searchunknown = _("Unknown model");
	if ((!$do_auto_detect) ||
	    ($makemodel =~ /$searchunknown/i) ||
	    ($makemodel =~ /^\s*$/)) {
	    local $::isWizard = 0;
	    $isHPOJ = $in->ask_yesorno(_("Local Printer"),
				       _("Is your printer a multi-function device from HP or Sony (OfficeJet, PSC, LaserJet 1100/1200/1220/3200/3300 with scanner, Sony IJP-V100), an HP PhotoSmart or an HP LaserJet 2200?"), 0);
	}
	if (($makemodel =~ /HP\s+OfficeJet/i) ||
	    ($makemodel =~ /HP\s+PSC/i) ||
	    ($makemodel =~ /HP\s+PhotoSmart/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+1100/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+1200/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+1220/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+2200/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+3200/i) ||
	    ($makemodel =~ /HP\s+LaserJet\s+33.0/i) ||
	    ($makemodel =~ /Sony\s+IJP[\s\-]+V[\s\-]+100/i) ||
	    ($isHPOJ)) {
	    # Install HPOJ package
	    if ((!$::testing) &&
		(!printer::files_exist((qw(/usr/sbin/ptal-mlcd
					   /usr/sbin/ptal-init
					   /usr/bin/xojpanel))))) {
		my $w = $in->wait_message(_("Printerdrake"),
					  _("Installing HPOJ package..."));
		$in->do_pkgs->install('hpoj', 'xojpanel');
	    }
	    # Configure and start HPOJ
	    my $w = $in->wait_message
		(_("Printerdrake"),
		 _("Checking device and configuring HPOJ..."));
	    $ptaldevice = printer::configure_hpoj($device, @autodetected);
	    
	    if ($ptaldevice) {
		# Configure scanning with SANE on the MF device
		if (($makemodel !~ /HP\s+PhotoSmart/i) &&
		    ($makemodel !~ /HP\s+LaserJet\s+2200/i)) {
		    # Install SANE
		    if ((!$::testing) &&
			(!printer::files_exist((qw(/usr/bin/scanimage
						   /usr/bin/xscanimage
						   /usr/bin/xsane
						   /etc/sane.d/dll.conf
						   /usr/lib/libsane-hpoj.so.1),
						(printer::files_exist
						 ('/usr/bin/gimp') ? 
						 '/usr/bin/xsane-gimp' : 
						 ()))))) {
			my $w = $in->wait_message
			    (_("Printerdrake"),
			     _("Installing SANE packages..."));
			$in->do_pkgs->install('sane-backends',
					      'sane-frontends',
					      'xsane', 'libsane-hpoj0',
					      if_($in->do_pkgs->is_installed
						  ('gimp'),'xsane-gimp'));
		    }
		    # Configure the HPOJ SANE backend
		    printer::config_sane();
		}
		# Configure photo card access with mtools and MToolsFM
		if ((($makemodel =~ /HP\s+PhotoSmart/i) ||
		     ($makemodel =~ /HP\s+PSC\s*9[05]0/i) ||
		     ($makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i)) &&
		    ($makemodel !~ /HP\s+PhotoSmart\s+7150/i)) {
		    # Install mtools and MToolsFM
		    if ((!$::testing) &&
			(!printer::files_exist(qw(/usr/bin/mdir
						  /usr/bin/mcopy
						  /usr/bin/MToolsFM
						  )))) {
			my $w = $in->wait_message
			    (_("Printerdrake"),
			     _("Installing mtools packages..."));
			$in->do_pkgs->install('mtools', 'mtoolsfm');
		    }
		    # Configure mtools/MToolsFM for photo card access
		    printer::config_photocard();
		}
		
		my $text = "";
		# Inform user about how to scan with his MF device
		$text = scanner_help($makemodel, "ptal:/$ptaldevice");
		if ($text) {
		    $in->ask_warn
			(_("Scanning on your HP multi-function device"),
			 $text);
		}
		# Inform user about how to access photo cards with his MF
		# device
		$text = photocard_help($makemodel, "ptal:/$ptaldevice");
		if ($text) {
		    $in->ask_warn(_("Photo memory card access on your HP multi-function device"),
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
    if (($printer->{SPOOLER} eq "cups") &&
	($device !~ /^lpd:/) &&
	($device !~ /^smb:/) &&
	($device !~ /^socket:/) &&
	($device !~ /^http:/) &&
	($device !~ /^ipp:/)) {
	my $w = $in->wait_message
	    ('_("Printerdrake")',
	     _("Making printer port available for CUPS..."));
	if ($ptaldevice eq "") {
	    printer::assure_device_is_available_for_cups($device);
	} else {
	    printer::assure_device_is_available_for_cups($ptaldevice);
	}
    }

    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Reading printer database..."));
        printer::read_printer_db($printer->{SPOOLER});
    }

    #- Search the database entry which matches the detected printer best
    my $descr = "";
    foreach (@autodetected) {
	$device eq $_->{port} or next;
	if (($_->{val}{MANUFACTURER}) && ($_->{val}{MODEL})) {
	    $descr = "$_->{val}{MANUFACTURER} $_->{val}{MODEL}";
	} else {
	    $descr = $_->{val}{DESCRIPTION};
	}
	# Clean up the description from noise which makes the best match
	# difficult
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
	for my $entry (keys(%printer::thedb)) {
	    if ($entry =~ m!$descr!i) {
		$printer->{DBENTRY} = $entry;
		last;
	    }
	}
	if (!$printer->{DBENTRY}) {
	    $printer->{DBENTRY} =
		bestMatchSentence ($descr, keys %printer::thedb);
	}
        # If the manufacturer was not guessed correctly, discard the
        # guess.
        $printer->{DBENTRY} =~ /^([^\|]+)\|/;
        my $guessedmake = lc($1);
        if (($descr !~ /$guessedmake/i) &&
            (($guessedmake ne "hp") ||
             ($descr !~ /Hewlett[\s-]+Packard/i)))
            { $printer->{DBENTRY} = "" };
    }

    #- Pre-fill the "Description" field with the printer's model name
    if ((!$printer->{currentqueue}{desc}) && ($descr)) {
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
    $in->ask_from_
	(
	 { title => _("Enter Printer Name and Comments"),
	   #cancel => !$printer->{configured}{$queue} ? '' : _("Remove queue"),
	   callbacks => { complete => sub {
	       unless ($printer->{currentqueue}{queue} =~ /^\w+$/) {
		   $in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
		   return (1,0);
	       }
	       local $::isWizard = 0;
	       if (($printer->{configured}{$printer->{currentqueue}{queue}})
		   && ($printer->{currentqueue}{queue} ne $default) && 
		   (!$in->ask_yesorno('', _("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
					    $printer->{currentqueue}{queue}),
				      0))) {
		   return (1,0); # Let the user correct the name
	       }
	       return 0;
	   },
		      },
	   messages =>
_("Every printer needs a name (for example \"printer\"). The Description and Location fields do not need to be filled in. They are comments for the users.") }, 
	 [ { label => _("Name of printer"), val => \$printer->{currentqueue}{queue} },
	   { label => _("Description"), val => \$printer->{currentqueue}{desc} },
	   { label => _("Location"), val => \$printer->{currentqueue}{loc} },
	 ]) or return 0;

    $printer->{QUEUE} = $printer->{currentqueue}{queue};
    1;
}

sub get_db_entry {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Reading printer database..."));
        printer::read_printer_db($printer->{SPOOLER});
    }
    my $w = $in->wait_message(_("Printerdrake"),
			      _("Preparing printer database..."));
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
		if (!member($printer->{DBENTRY}, keys(%printer::thedb))) {
		    $printer->{DBENTRY} .= " (recommended)";
		}
	    } else {
		$printer->{DBENTRY} = "$make|$model";
	    }
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} elsif (($printer->{SPOOLER} eq "cups") && ($::expert) &&
		 ($printer->{configured}{$queue}{queuedata}{ppd})) {
	    # Do we have a native CUPS driver or a PostScript PPD file?
	    $printer->{DBENTRY} = printer::get_descr_from_ppd($printer) || $printer->{DBENTRY};
	    $printer->{OLD_CHOICE} = $printer->{DBENTRY};
	} else {
	    # Point the list cursor at least to manufacturer and model of the
	    # printer
	    $printer->{DBENTRY} = "";
	    my $make = uc($printer->{configured}{$queue}{queuedata}{make});
	    my $model = $printer->{configured}{$queue}{queuedata}{model};
	    my $key;
	    for $key (keys %printer::thedb) {
		if ((($::expert) && ($key =~ /^$make\|$model\|.*\(recommended\)$/)) ||
		    ((!$::expert) && ($key =~ /^$make\|$model$/))) {
		    $printer->{DBENTRY} = $key;
		}
	    }
	    if ($printer->{DBENTRY} eq "") {
		# Exact match of make and model did not work, try to clean
		# up the model name
		$model =~ s/PS//;
		$model =~ s/PostScript//;
		$model =~ s/Series//;
		for $key (keys %printer::thedb) {
		    if ((($::expert) && ($key =~ /^$make\|$model\|.*\(recommended\)$/)) ||
			((!$::expert) && ($key =~ /^$make\|$model$/))) {
			$printer->{DBENTRY} = $key;
		    }
		}
	    }
	    if (($printer->{DBENTRY} eq "") && ($make ne "")) {
		# Exact match with cleaned-up model did not work, try a best match
		my $matchstr = "$make|$model";
		$printer->{DBENTRY} = bestMatchSentence($matchstr, keys %printer::thedb);
		# If the manufacturer was not guessed correctly, discard the
		# guess.
		$printer->{DBENTRY} =~ /^([^\|]+)\|/;
		my $guessedmake = lc($1);
		if (($matchstr !~ /$guessedmake/i) &&
		    (($guessedmake ne "hp") ||
		     ($matchstr !~ /Hewlett[\s-]+Packard/i)))
		{ $printer->{DBENTRY} = "" };
	    }
	    # Set the OLD_CHOICE to a non-existing value
	    $printer->{OLD_CHOICE} = "XXX";
	}
    } else {
	if (($::expert) && ($printer->{DBENTRY} !~ /(recommended)/)) {
	    my ($make, $model) = $printer->{DBENTRY} =~ /^([^\|]+)\|([^\|]+)\|/;
	    for my $key (keys %printer::thedb) {
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
    my $res = $in->ask_from_list_
	    (_("Your printer model"),
	     _("Printerdrake has compared the model name resulting from the printer auto-detection with the models listed in its printer database to find the best match. This choice can be wrong, especially when your printer is not listed at all in the database. So check whether the choice is correct and click \"The model is correct\" if so and if not, click \"Select model manually\" so that you can choose your printer model manually on the next screen.

For your printer Printerdrake has found:

%s", $dbentry),
	     [_("The model is correct"),
	      _("Select model manually")],
	     ($printer->{MANUALMODEL} ? _("Select model manually") : 
	      _("The model is correct")));
    return 0 if !$res;
    $printer->{MANUALMODEL} = ($res eq _("Select model manually"));
    1;
}

sub choose_model {
    my ($printer, $in) = @_;
    $in->set_help('chooseModel') if $::isInstall;
    #- Read the printer driver database if necessary
    if ((keys %printer::thedb) == 0) {
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Reading printer database..."));
        printer::read_printer_db($printer->{SPOOLER});
    }
    if (!member($printer->{DBENTRY}, keys(%printer::thedb))) {
	$printer->{DBENTRY} = _("Raw printer (No driver)");
    }
    # Choose the printer/driver from the list
    return ($printer->{DBENTRY} = $in->ask_from_treelist(_("Printer model selection"),
							 _("Which printer model do you have?") .
							 _("

Please check whether Printerdrake did the auto-detection of your printer model correctly. Search the correct model in the list when the cursor is standing on a wrong model or on \"Raw printer\".") . " " .
_("If your printer is not listed, choose a compatible (see printer manual) or a similar one."), '|',
							 [ keys %printer::thedb ], $printer->{DBENTRY}));

}

sub get_printer_info {
    my ($printer, $in) = @_;
    #- Read the printer driver database if necessary
    #if ((keys %printer::thedb) == 0) {
    #    my $w = $in->wait_message(_("Printerdrake"), 
    #                              _("Reading printer database..."));
    #    printer::read_printer_db($printer->{SPOOLER});
    #}
    my $queue = $printer->{OLD_QUEUE};
    my $oldchoice = $printer->{OLD_CHOICE};
    my $newdriver = 0;
    if ((!$printer->{configured}{$queue}) ||      # New queue  or
	(($oldchoice) && ($printer->{DBENTRY}) && # make/model/driver changed
	 (($oldchoice ne $printer->{DBENTRY}) ||
	  ($printer->{currentqueue}{driver} ne 
	   $printer::thedb{$printer->{DBENTRY}}{driver})))) {
	delete($printer->{currentqueue}{printer});
	delete($printer->{currentqueue}{ppd});
	$printer->{currentqueue}{foomatic} = 0;
	# Read info from printer database
	foreach (qw(printer ppd driver make model)) { #- copy some parameter, shorter that way...
	    $printer->{currentqueue}{$_} = $printer::thedb{$printer->{DBENTRY}}{$_};
	}
	$newdriver = 1;
    }
    # Use the "printer" and not the "foomatic" field to identify a Foomatic
    # queue because in a new queue "foomatic" is not set yet.
    if (($printer->{currentqueue}{printer}) || # We have a Foomatic queue
	($printer->{currentqueue}{ppd})) { # We have a CUPS+PPD queue
	if ($printer->{currentqueue}{printer}) { # Foomatic queue?
	    # In case of a new queue "foomatic" was not set yet
	    $printer->{currentqueue}{foomatic} = 1;
	    # Now get the options for this printer/driver combo
	    if (($printer->{configured}{$queue}) && ($printer->{configured}{$queue}{queuedata}{foomatic})) {
		# The queue was already configured with Foomatic ...
		if (!$newdriver) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = $printer->{configured}{$queue}{args};
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::read_foomatic_options($printer);
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
		    if (($pagesize =~ /^en_CA/) ||
			($pagesize =~ /^fr_CA/) || 
			($pagesize =~ /^en_US/)) {
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
			$in->ask_warn(_("OKI winprinter configuration"),
				      _("You are configuring an OKI laser winprinter. These printers\nuse a very special communication protocol and therefore they work only when connected to the first parallel port. When your printer is connected to another port or to a print server box please connect the printer to the first parallel port before you print a test page. Otherwise the printer will not work. Your connection type setting will be ignored by the driver."));
		    }
		    $printer->{currentqueue}{connect} = 'file:/dev/null';
		    # Start the oki4daemon
		    printer::start_service_on_boot('oki4daemon');
		    printer::start_service('oki4daemon');
		    # Set permissions
		    if ($printer->{SPOOLER} eq 'cups') {
			printer::set_permissions('/dev/oki4drv', '660', 'lp',
						 'sys');
		    } elsif ($printer->{SPOOLER} eq 'pdq') {
			printer::set_permissions('/dev/oki4drv', '666');
		    } else {
			printer::set_permissions('/dev/oki4drv', '660', 'lp',
						 'lp');
		    }
		} elsif ($printer->{currentqueue}{driver} eq 'lexmarkinkjet') {
		    # Set "Port" option
		    if ($printer->{currentqueue}{connect} eq 
			'file:/dev/lp0') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort1";
		    } elsif ($printer->{currentqueue}{connect} eq 
			'file:/dev/lp1') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort2";
		    } elsif ($printer->{currentqueue}{connect} eq 
			'file:/dev/lp2') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=ParPort3";
		    } elsif ($printer->{currentqueue}{connect} eq 
			'file:/dev/usb/lp0') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB1";
		    } elsif ($printer->{currentqueue}{connect} eq 
			'file:/dev/usb/lp1') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB2";
		    } elsif ($printer->{currentqueue}{connect} eq 
			'file:/dev/usb/lp2') {
			$printer->{SPECIAL_OPTIONS} .= 
			    " -o Port=USB3";
		    } else {
			$in->ask_warn(_("Lexmark inkjet configuration"),
				      _("The inkjet printer drivers provided by Lexmark only support local printers, no printers on remote machines or print server boxes. Please connect your printer to a local port or configure it on the machine where it is connected to."));
			return 0;
		    }
		    # Set device permissions
		    $printer->{currentqueue}{connect} =~ /^\s*file:(\S*)\s*$/;
		    if ($printer->{SPOOLER} eq 'cups') {
			printer::set_permissions($1, '660', 'lp', 'sys');
		    } elsif ($printer->{SPOOLER} eq 'pdq') {
			printer::set_permissions($1, '666');
		    } else {
			printer::set_permissions($1, '660', 'lp', 'lp');
		    }
		    # This is needed to have the device not blocked by the
		    # spooler backend.
		    $printer->{currentqueue}{connect} = 'file:/dev/null';
		    #install packages
		    my $drivertype = $printer->{currentqueue}{model};
		    if ($drivertype eq 'Z22') { $drivertype = 'Z32' }
		    if ($drivertype eq 'Z23') { $drivertype = 'Z33' }
		    $drivertype = lc($drivertype);
		    if (!printer::files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			eval { $in->do_pkgs->install("lexmark-drivers-$drivertype") };
		    }
		    if (!printer::files_exist("/usr/local/lexmark/$drivertype/$drivertype")) {
			# Driver installation failed, probably we do not have
			# the commercial CDs
			$in->ask_warn(_("Lexmark inkjet configuration"),
				      _("To be able to print with your Lexmark inkjet and this configuration, you need the inkjet printer drivers provided by Lexmark (http://www.lexmark.com/). Go to the US site and click on the \"Drivers\" button. Then choose your model and afterwards \"Linux\" as operating system. The drivers come as RPM packages or shell scripts with interactive graphical installation. You do not need to do this configuration by the graphical frontends. Cancel directly after the license agreement. Then print printhead alignment pages with \"lexmarkmaintain\" and adjust the head alignment settings with this program."));
		    }
		}
		$printer->{ARGS} = printer::read_foomatic_options($printer);
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
		if ((!$printer->{DBENTRY}) || (!$oldchoice) ||
		    ($printer->{DBENTRY} eq $oldchoice)) {
		    # ... and the user didn't change the printer/driver
		    $printer->{ARGS} = printer::read_cups_options($queue);
		} else {
		    # ... and the user has chosen another printer/driver
		    $printer->{ARGS} = printer::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
		}
	    } else {
		# The queue was not configured before
		$printer->{ARGS} = printer::read_cups_options("/usr/share/cups/model/$printer->{currentqueue}{ppd}");
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
    if (($printer->{currentqueue}{printer}) || # We have a Foomatic queue
	($printer->{currentqueue}{ppd})) { # We have a CUPS+PPD queue
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
		my $choice;
		for $choice (@{$printer->{ARGS}[$i]{vals}}) {
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
			$driver = printer::get_descr_from_ppd($printer);
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
	if ((!$printer->{NEW}) or ($::expert) or ($printer->{MANUAL})) {
	    return 0 if !$in->ask_from
		($windowtitle,
		 _("Printer default settings

You should make sure that the page size and the ink type/printing mode (if available) and also the hardware configuration of laser printers (memory, duplex unit, extra trays) are set correctly. Note that with a very high printout quality/resolution printing can get substantially slower."),
		 \@widgets,
		 complete => sub {
		     my $i;
		     for ($i = 0; $i <= $#{$printer->{ARGS}}; $i++) {
			 if (($printer->{ARGS}[$i]{type} eq 'int') || ($printer->{ARGS}[$i]{type} eq 'float')) {
			     unless (($printer->{ARGS}[$i]{type} ne 'int') || ($userinputs[$i] =~ /^[\-\+]?[0-9]+$/)) {
				 $in->ask_warn('', _("Option %s must be an integer number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     unless (($printer->{ARGS}[$i]{type} ne 'float') || ($userinputs[$i] =~ /^[\-\+]?[0-9\.]+$/)) {
				 $in->ask_warn('', _("Option %s must be a number!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			     unless (($userinputs[$i] >= $printer->{ARGS}[$i]{min}) &&
				     ($userinputs[$i] <= $printer->{ARGS}[$i]{max})) {
				 $in->ask_warn('', _("Option %s out of range!", $printer->{ARGS}[$i]{comment}));
				 return (1, $i);
			     }
			 }
		     }
		     return (0);
		 } );
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
			push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{name} . "=". $shortchoicelists[$i][$j]);
		    }
		}
	    } elsif ($printer->{ARGS}[$i]{type} eq 'bool') {
		# boolean option
		push(@{$printer->{currentqueue}{options}}, $printer->{ARGS}[$i]{name} . "=".
		     (($choicelists[$i][0] eq $userinputs[$i]) ? "1" : "0"));
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
    if (($printer->{DEFAULT} eq '') || # We have no default printer,
	                               # so set the current one as default
	($in->ask_yesorno('', _("Do you want to set this printer (\"%s\")\nas the default printer?", $printer->{QUEUE}), 0))) { # Ask the user
	$printer->{DEFAULT} = $printer->{QUEUE};
        printer::set_default_printer($printer);
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
    my $res1 = $in->ask_from_
	({ title => _("Test pages"),
	   messages => _("Please select the test pages you want to print.
Note: the photo test page can take a rather long time to get printed and on laser printers with too low memory it can even not come out. In most cases it is enough to print the standard test page."),
	   cancel => ((!$printer->{NEW}) ?
		       _("Cancel") : ($::isWizard ? _("<- Previous") : 
				      _("No test pages"))),
	   ok => ($::isWizard ? _("Next ->") : _("Print")),
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
	   }},
	 [
	  { text => _("Standard test page"), type => 'bool',
	    val => \$standard },
	  ($::expert ?
	   { text => _("Alternative test page (Letter)"), type => 'bool', 
	     val => \$altletter } : ()),
	  ($::expert ?
	   { text => _("Alternative test page (A4)"), type => 'bool', 
	     val => \$alta4 } : ()), 
	  { text => _("Photo test page"), type => 'bool', val => \$photo },
	  #{ text => _("Plain text test page"), type => 'bool',
	  #  val => \$ascii }
	  ($::isWizard ?
	   { text => _("Do not print any test page"), type => 'bool', 
	     val => \$res2 } : ())
	  ]);
    $res2 = 1 if (!($standard || $altletter || $alta4 || $photo ||
		    $ascii));
    if ($res1 && !$res2) {
	my @lpq_output;
	{
	    my $w = $in->wait_message(_("Printerdrake"),
				      _("Printing test page(s)..."));
	    
	    $upNetwork and do { &$upNetwork(); undef $upNetwork; sleep(1) };
	    my $stdtestpage = "/usr/share/printer-testpages/testprint.ps";
	    my $altlttestpage = "/usr/share/printer-testpages/testpage.ps";
	    my $alta4testpage = "/usr/share/printer-testpages/testpage-a4.ps";
	    my $phototestpage = "/usr/share/printer-testpages/photo-testpage.jpg";
	    my $asciitestpage = "/usr/share/printer-testpages/testpage.asc";
	    my @testpages;
	    # Install the filter to convert the photo test page to PS
	    if (($printer->{SPOOLER} ne "cups") && ($photo) && (!$::testing) &&
		(!printer::files_exist((qw(/usr/bin/convert))))) {
		$in->do_pkgs->install('ImageMagick');
	    }
	    # set up list of pages to print
	    $standard && push (@testpages, $stdtestpage);
	    $altletter && push (@testpages, $altlttestpage);
	    $alta4 && push (@testpages, $alta4testpage);
	    $photo && push (@testpages, $phototestpage);
	    $ascii && push (@testpages, $asciitestpage);
	    # print the stuff
	    @lpq_output = printer::print_pages($printer, @testpages);
	}
	my $dialogtext;
	if (@lpq_output) {
	    $dialogtext = _("Test page(s) have been sent to the printer.
It may take some time before the printer starts.
Printing status:\n%s\n\n", @lpq_output);
	} else {
	    $dialogtext = _("Test page(s) have been sent to the printer.
It may take some time before the printer starts.\n");
	}
	if ($printer->{NEW} == 0) {
	    $in->ask_warn('',$dialogtext);
	    return 1;
	} else {
	    $in->ask_yesorno('',$dialogtext . _("Did it work properly?"), 1) 
		and return 1;
	}
    } else {
	return ($::isWizard ? $res1 : 1) ;
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
	if (($printer->{configured}{$queue}{queuedata}{model} eq
	     _("Unknown model")) ||
	    ($printer->{configured}{$queue}{queuedata}{model} eq
	     _("Raw printer"))) {
	    $raw = 1;
	}
	# Information about scanning with HP's multi-function devices
	$scanning = scanner_help
	    ($printer->{configured}{$queue}{queuedata}{make} . " " .
	     $printer->{configured}{$queue}{queuedata}{model}, 
	     $printer->{configured}{$queue}{queuedata}{connect});
	if ($scanning) {
	    $scanning = "\n\n$scanning\n\n";
	}
	# Information about photo card access with HP's multi-function devices
	$photocard = photocard_help
	    ($printer->{configured}{$queue}{queuedata}{make} . " " .
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
_("To print a file from the command line (terminal window) you can either use the command \"%s <file>\" or a graphical printing tool: \"xpp <file>\" or \"kprinter <file>\". The graphical tools allow you to choose the printer and to modify the option settings easily.
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("These commands you can also use in the \"Printing command\" field of the printing dialogs of many applications, but here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
(!$cupsremote ?
 _("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s

", $scanning, $photocard) . printer::lphelp_output($printer) : 
 $scanning . $photocard .
 _("Here is a list of the available printing options for the current printer:

") . printer::lphelp_output($printer)) : $scanning . $photocard);
    } elsif ($spooler eq "lprng") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) . 
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -Z option=setting -Z switch" : "lpr -Z option=setting -Z switch")) .
_("To get a list of the options available for the current printer click on the \"Print option list\" button." . $scanning . $photocard) : $scanning . $photocard);
    } elsif ($spooler eq "lpd") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\".
", ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
(!$raw ?
_("
The \"%s\" command also allows to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\". ", "lpr", ($queue ne $default ? "lpr -P $queue -o option=setting -o switch" : "lpr -o option=setting -o switch")) .
_("To get a list of the options available for the current printer click on the \"Print option list\" button." . $scanning . $photocard) : $scanning . $photocard);
    } elsif ($spooler eq "pdq") {
	$dialogtext =
_("To print a file from the command line (terminal window) use the command \"%s <file>\" or \"%s <file>\".
", ($queue ne $default ? "pdq -P $queue" : "pdq"), ($queue ne $default ? "lpr -P $queue" : "lpr")) .
_("This command you can also use in the \"Printing command\" field of the printing dialogs of many applications. But here do not supply the file name because the file to print is provided by the application.
") .
_("You can also use the graphical interface \"xpdq\" for setting options and handling printing jobs.
If you are using KDE as desktop environment you have a \"panic button\", an icon on the desktop, labeled with \"STOP Printer!\", which stops all print jobs immediately when you click it. This is for example useful for paper jams.
") .
(!$raw ?
_("
The \"%s\" and \"%s\" commands also allow to modify the option settings for a particular printing job. Simply add the desired settings to the command line, e. g. \"%s <file>\".
", "pdq", "lpr", ($queue ne $default ? "pdq -P $queue -aoption=setting -oswitch" : "pdq -aoption=setting -oswitch")) .
_("To know about the options available for the current printer read either the list shown below or click on the \"Print option list\" button.%s%s

", $scanning, $photocard) . printer::pdqhelp_output($printer) :
 $scanning . $photocard);
    }
    my $windowtitle = ($scanning ?
                       ($photocard ?
			_("Printing/Scanning/Photo Cards on \"%s\"", $queue) :
			_("Printing/Scanning on \"%s\"", $queue)) :
                       ($photocard ?
			_("Printing/Photo Card Access on \"%s\"", $queue) :
			_("Printing on the printer \"%s\"", $queue)));
    if (!$raw && !$cupsremote) {
        my $choice;
        while ($choice ne _("Close")) {
	    $choice = $in->ask_from_list_
	        ($windowtitle, $dialogtext,
		 [ _("Print option list"), _("Close") ],
		 _("Close"));
	    if ($choice ne _("Close")) {
		my $w = $in->wait_message(_("Printerdrake"),
					  _("Printing test page(s)..."));
	        printer::print_optionlist($printer);
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
	if (($makemodel !~ /HP\s+PhotoSmart/i) &&
	    ($makemodel !~ /HP\s+LaserJet\s+2200/i)) {
	    # Models with built-in scanner
	    return _("Your multi-function device was configured automatically to be able to scan. Now you can scan with \"scanimage\" (\"scanimage -d hp:%s\" to specify the scanner when you have more than one) from the command line or with the graphical interfaces \"xscanimage\" or \"xsane\". If you are using the GIMP, you can also scan by choosing the appropriate point in the \"File\"/\"Acquire\" menu. Call also \"man scanimage\" on the command line to get more information.

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
	if ((($makemodel =~ /HP\s+PhotoSmart/i) ||
	     ($makemodel =~ /HP\s+PSC\s*9[05]0/i) ||
	     ($makemodel =~ /HP\s+OfficeJet\s+D\s*1[45]5/i)) &&
	    ($makemodel !~ /HP\s+PhotoSmart\s+7150/i)) {
	    # Models with built-in photo card drives
	    return _("Your printer was configured automatically to give you access to the photo card drives from your PC. Now you can access your photo cards using the graphical program \"MtoolsFM\" (Menu: \"Applications\" -> \"File tools\" -> \"MTools File Manager\") or the command line utilities \"mtools\" (enter \"man mtools\" on the command line for more info). You find the card's file system under the drive letter \"p:\", or subsequent drive letters when you have more than one HP printer with photo card drives. In \"MtoolsFM\" you can switch between drive letters with the field at the upper-right corners of the file lists.",
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
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Reading printer data..."));
	@oldqueues = printer::get_copiable_queues($oldspooler, $newspooler);
	@oldqueues = sort(@oldqueues);
	$newspoolerstr = $printer::shortspooler_inv{$newspooler};
	$oldspoolerstr = $printer::shortspooler_inv{$oldspooler};
	for (@oldqueues) {
	    push (@queuesselected, 1);
	    push (@queueentries, { text => $_, type => 'bool', 
				   val => \$queuesselected[$#queuesselected] });
	}
	# LPRng and LPD use the same config files, therefore one sees the 
	# queues of LPD when one uses LPRng and vice versa, but these queues
	# do not work. So automatically transfer all queues when switching
	# between LPD and LPRng.
	if (($oldspooler =~ /^lp/) && ($newspooler =~ /^lp/)) {
	    $noninteractive = 1;
	}
    }
    if ($noninteractive ||
	$in->ask_from_
	({ title => _("Transfer printer configuration"),
	   messages => _("You can copy the printer configuration which you have done for the spooler %s to %s, your current spooler. All the configuration data (printer name, description, location, connection type, and default option settings) is overtaken, but jobs will not be transferred.
Not all queues can be transferred due to the following reasons:
", $oldspoolerstr, $newspoolerstr) .
($newspooler eq "cups" ? _("CUPS does not support printers on Novell servers or printers sending the data into a free-formed command.
") :
 ($newspooler eq "pdq" ? _("PDQ only supports local printers, remote LPD printers, and Socket/TCP printers.
") :
  _("LPD and LPRng do not support IPP printers.
"))) .
_("In addition, queues not created with this program or \"foomatic-configure\" cannot be transferred.") .
($oldspooler eq "cups" ? _("
Also printers configured with the PPD files provided by their manufacturers or with native CUPS drivers cannot be transferred.") : ()) . _("
Mark the printers which you want to transfer and click 
\"Transfer\"."),
	   cancel => _("Do not transfer printers"),
           ok => _("Transfer")
	 },
         \@queueentries
      )) {
	my $queuecopied = 0;
	for (@oldqueues) {
	    if (shift(@queuesselected)) {
                my $oldqueue = $_;
                my $newqueue = $_;
                if ((!$printer->{configured}{$newqueue}) ||
		    ($noninteractive) ||
		    ($in->ask_from_
	             ({ title => _("Transfer printer configuration"),
	                messages => _("A printer named \"%s\" already exists under %s. 
Click \"Transfer\" to overwrite it.
You can also type a new name or skip this printer.", 
				      $newqueue, $newspoolerstr),
                        ok => _("Transfer"),
                        cancel => _("Skip"),
		        callbacks => { complete => sub {
	                    unless ($newqueue =~ /^\w+$/) {
				$in->ask_warn('', _("Name of printer should contain only letters, numbers and the underscore"));
				return (1,0);
			    }
			    if (($printer->{configured}{$newqueue})
				&& ($newqueue ne $oldqueue) && 
				(!$in->ask_yesorno('', _("The printer \"%s\" already exists,\ndo you really want to overwrite its configuration?",
							 $newqueue),
						   0))) {
				return (1,0); # Let the user correct the name
			    }
			    return 0;
			}}
		    },
		      [{label => _("New printer name"),val => \$newqueue}]))) {
		    {
			my $w = $in->wait_message(_("Printerdrake"), 
			   _("Transferring %s...", $oldqueue));
		        printer::copy_foomatic_queue($printer, $oldqueue,
						   $oldspooler, $newqueue) and
							 $queuecopied = 1;
		    }
		    if ($oldqueue eq $printer->{DEFAULT}) {
			# Make the former default printer the new default
			# printer if the user does not reject
			if (($noninteractive) ||
			    ($in->ask_yesorno
			     (_("Transfer printer configuration"),
			      _("You have transferred your former default printer (\"%s\"), Should it be also the default printer under the new printing system %s?", $oldqueue, $newspoolerstr), 1))) {
			    $printer->{DEFAULT} = $newqueue;
			    printer::set_default_printer($printer);
			}
		    }
		}
            }
	}
        if ($queuecopied) {
	    my $w = $in->wait_message(_("Printerdrake"),
                                      _("Refreshing printer data..."));
	    printer::read_configured_queues($printer);
        }
    }
}

sub start_network {
    my ($in, $upNetwork) = @_;
    my $w = $in->wait_message(_("Configuration of a remote printer"), 
			      _("Starting network..."));
    if ($::isInstall) {
	return ($upNetwork and 
		do { my $ret = &$upNetwork(); 
		     undef $upNetwork; 
		     sleep(1);
		     $ret});
    } else {
	return printer::start_service("network");
    }
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

    if ((!printer::files_exist("/etc/sysconfig/network-scripts/drakconnect_conf")) &&
	(!$dontconfigure)) {
	my $go_on = 0;
	while (!$go_on) {
	    my $choice = _("Configure the network now");
	    if ($in->ask_from(_("Network functionality not configured"),
			      _("You are going to configure a remote printer. This needs working network access, but your network is not configured yet. If you go on without network configuration, you will not be able to use the printer which you are configuring now. How do you want to proceed?"),
			      [ { val => \$choice, type => 'list',
				  list => [ _("Configure the network now"),
					    _("Go on without configuring the network") ]} ] )) {
		if ($choice eq _("Configure the network now")){
		    if ($::isInstall) {
			require network::netconnect;
		        network::netconnect::main
			    ($in->{prefix}, $in->{netcnx} ||= {}, 
			     $in->{netc}, $in->{mouse}, $in, 
			     $in->{intf}, 0,
			     $in->{lang} eq "fr_FR" && 
			     $in->{keyboard}{KEYBOARD} eq "fr", 0);
		    } else {
			system("/usr/sbin/drakconnect");
		    }
		    if (printer::files_exist("/etc/sysconfig/network-scripts/drakconnect_conf")) {
			$go_on = 1;
		    }
		} else {
		    return 1;
		}
	    } else {
		return 0;
	    }
	}
    }

    # Second check: Is the network running?

    if (printer::network_running()) { return 1 }

    # The network is configured now, start it.
    if ((!start_network($in, $upNetwork)) && (!$dontconfigure)) {
	$in->ask_warn(_("Configuration of a remote printer"), 
($::isInstall ?
_("The network configuration done during the installation cannot be started now. Please check whether the network gets accessable after booting your system and correct the configuration using the Mandrake Control Center, section \"Network & Internet\"/\"Connection\", and afterwards set up the printer, also using the Mandrake Control Center, section \"Hardware\"/\"Printer\"") :
_("The network access was not running and could not be started. Please check your configuration and your hardware. Then try to configure your remote printer again.")));
	return 0;
    }

    # Give a SIGHUP to the daemon and in case of CUPS do also the
    # automatic configuration of broadcasting/access permissions
    # The daemon is not really restarted but only SIGHUPped to not
    # interrupt print jobs.

    my $w = $in->wait_message(_("Configuration of a remote printer"), 
			      _("Restarting printing system..."));

    return printer::SIGHUP_daemon($printer->{SPOOLER});

}

sub security_check {
    # Check the security mode and when in "high" or "paranoid" mode ask the
    # user whether he really wants to configure printing.
    my ($printer, $in, $spooler) = @_;

    # Any additional dialogs caused by this subroutine should appear as
    # extra windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    $in->set_help('securityCheck') if $::isInstall;

    # Get security level
    my $security;
    if ($::isInstall) {
	$security = $in->{security};
    } else {
	$security = any::get_secure_level();
    }

    # Exit silently if the spooler is PDQ
    if ($spooler eq "pdq") { return 1 }

    # Exit silently in medium or lower security levels
    if ((!$security) || ($security < 4)) { return 1 }
    
    # Exit silently if the current spooler is already activated for the current
    # security level
    if (printer::spooler_in_security_level($spooler, $security)) { return 1 }

    # Tell user in which security mode he is and ask him whether he really
    # wants to activate the spooler in the given security mode. Stop the
    # operation of installing the spooler if he disagrees.
    my $securitystr = ($security == 4 ? _("high") : _("paranoid"));
    if ($in->ask_yesorno(_("Installing a printing system in the %s security level", $securitystr),
			 _("You are about to install the printing system %s on a system running in the %s security level.

This printing system runs a daemon (background process) which waits for print jobs and handles them. This daemon is also accessable by remote machines through the network and so it is a possible point for attacks. Therefore only a few selected daemons are started by default in this security level.

Do you really want to configure printing on this machine?",
			   $printer::shortspooler_inv{$spooler},
			   $securitystr))) {
        printer::add_spooler_to_security_level($spooler, $security);
	my $service;
	if (($spooler eq "lpr") || ($spooler eq "lprng")) {
	    $service = "lpd";
	} else {
	    $service = $spooler;
	}
        printer::start_service_on_boot($service);
	return 1;
    } else {
	return 0;
    }
}

sub start_spooler_on_boot {
    # Checks whether the spooler will be started at boot time and if not,
    # ask the user whether he wants to start the spooler at boot time.
    my ($printer, $in, $service) = @_;

    # Any additional dialogs caused by this subroutine should appear as
    # extra windows and not embedded in the "Add printer" wizard.
    local $::isWizard = 0;

    $in->set_help('startSpoolerOnBoot') if $::isInstall;
    if (!printer::service_starts_on_boot($service)) {
	if ($in->ask_yesorno(_("Starting the printing system at boot time"),
			     _("The printing system (%s) will not be started automatically when the machine is booted.

It is possible that the automatic starting was turned off by changing to a higher security level, because the printing system is a potential point for attacks.

Do you want to have the automatic starting of the printing system turned on again?",
		       $printer::shortspooler_inv{$printer->{SPOOLER}}))) {
	    printer::start_service_on_boot($service);
	}
    }
    1;
}

sub install_spooler {
    # installs the default spooler and start its daemon
    my ($printer, $in, $upNetwork) = @_;
    if (!$::testing) {
	# If the user refuses to install the spooler in high or paranoid
	# security level, exit.
	if (!security_check($printer, $in, $printer->{SPOOLER})) {
	    return 0;
	}
	if ($printer->{SPOOLER} eq "cups") {
	    {
		my $w = $in->wait_message(_("Printerdrake"),
					  _("Checking installed software..."));
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/lib/cups/cgi-bin/printers.cgi
					       /sbin/ifconfig
					       /usr/bin/xpp
					       /usr/bin/curl),
					    ($::expert ? 
					     "/usr/share/cups/model/postscript.ppd.gz" : ())
					    )))) {
		    $in->do_pkgs->install(('cups', 'net-tools', 'xpp',
					   'curl',
					   ($::expert ? 'cups-drivers' : ())));
		}
		# Try to start the network when CUPS is the spooler, so that
		# remote CUPS printers get displayed (especially during
		# installation)
		$upNetwork and do {
		    &$upNetwork(); 
		    undef $upNetwork; 
		    sleep(1);
		};
		# Start daemon
		# Avoid unnecessary restarting of CUPS, this blocks the
		# startup of printerdrake for several seconds.
		printer::start_not_running_service("cups");
		# Set the CUPS tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-cups");
	        printer::set_alternative("lpq","/usr/bin/lpq-cups");
	        printer::set_alternative("lprm","/usr/bin/lprm-cups");
	        printer::set_alternative("lp","/usr/bin/lp-cups");
	        printer::set_alternative("cancel","/usr/bin/cancel-cups");
	        printer::set_alternative("lpstat","/usr/bin/lpstat-cups");
	        printer::set_alternative("lpc","/usr/sbin/lpc-cups");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "cups");
	} elsif ($printer->{SPOOLER} eq "lpd") {
	    {
		my $w = $in->wait_message(_("Printerdrake"), 
					  _("Checking installed software..."));
		# "lpr" conflicts with "LPRng", remove "LPRng"
		if ((!$::testing) &&
		    (printer::files_exist((qw(/usr/lib/filters/lpf))))) {
		    my $w = $in->wait_message(_("Printerdrake"),
					      _("Removing LPRng..."));
		    $in->do_pkgs->remove_nodeps('LPRng');
		}
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/sbin/lpf
					       /usr/sbin/lpd
					       /sbin/ifconfig
					       /usr/bin/gpr
					       /usr/bin/a2ps
					       /usr/bin/convert))))) {
		    $in->do_pkgs->install(('lpr', 'net-tools', 'gpr', 'a2ps', 'ImageMagick'));
		}
		# Start the network (especially during installation), so the
		# user can set up queues to remote printers.
		$upNetwork and do {
		    &$upNetwork(); 
		    undef $upNetwork; 
		    sleep(1);
		};
		# Start daemon
	        printer::restart_service("lpd");
		# Set the LPD tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-lpd");
	        printer::set_alternative("lpq","/usr/bin/lpq-lpd");
	        printer::set_alternative("lprm","/usr/bin/lprm-lpd");
	        printer::set_alternative("lpc","/usr/sbin/lpc-lpd");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "lpd");
	} elsif ($printer->{SPOOLER} eq "lprng") {
	    {
		my $w = $in->wait_message(_("Printerdrake"),
					  _("Checking installed software..."));
		# "LPRng" conflicts with "lpr", remove "lpr"
		if ((!$::testing) &&
		    (printer::files_exist((qw(/usr/sbin/lpf))))) {
		    my $w = $in->wait_message(_("Printerdrake"),
					      _("Removing LPD..."));
		    $in->do_pkgs->remove_nodeps('lpr');
		}
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/lib/filters/lpf
					       /usr/sbin/lpd
					       /sbin/ifconfig
					       /usr/bin/gpr
					       /usr/bin/a2ps
					       /usr/bin/convert))))) {
		    $in->do_pkgs->install('LPRng', 'net-tools', 'gpr', 'a2ps', 'ImageMagick');
		}
		# Start the network (especially during installation), so the
		# user can set up queues to remote printers.
		$upNetwork and do {
		    &$upNetwork(); 
		    undef $upNetwork; 
		    sleep(1);
		};
		# Start daemon
	        printer::restart_service("lpd");
		# Set the LPRng tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-lpd");
	        printer::set_alternative("lpq","/usr/bin/lpq-lpd");
	        printer::set_alternative("lprm","/usr/bin/lprm-lpd");
	        printer::set_alternative("lp","/usr/bin/lp-lpd");
	        printer::set_alternative("cancel","/usr/bin/cancel-lpd");
	        printer::set_alternative("lpstat","/usr/bin/lpstat-lpd");
	        printer::set_alternative("lpc","/usr/sbin/lpc-lpd");
		# Remove PDQ panic buttons from the user's KDE Desktops
	        printer::pdq_panic_button("remove");
	    }
	    # Should it be started at boot time?
	    start_spooler_on_boot($printer, $in, "lpd");
	} elsif ($printer->{SPOOLER} eq "pdq") {
	    {
		my $w = $in->wait_message(_("Printerdrake"),
					  _("Checking installed software..."));
		if ((!$::testing) &&
		    (!printer::files_exist((qw(/usr/bin/pdq
					       /usr/X11R6/bin/xpdq))))) {
		    $in->do_pkgs->install('pdq');
		}
		# Start the network (especially during installation), so the
		# user can set up queues to remote printers.
		$upNetwork and do {
		    &$upNetwork(); 
		    undef $upNetwork; 
		    sleep(1);
		};
		# PDQ has no daemon, so nothing needs to be started
		
		# Set the PDQ tools as defaults for "lpr", "lpq", "lprm", ...
	        printer::set_alternative("lpr","/usr/bin/lpr-pdq");
	        printer::set_alternative("lpq","/usr/bin/lpq-foomatic");
	        printer::set_alternative("lprm","/usr/bin/lprm-foomatic");
		# Add PDQ panic buttons to the user's KDE Desktops
	        printer::pdq_panic_button("add");
	    }
	}
	# Give a SIGHUP to the devfsd daemon to correct the permissions
	# for the /dev/... files according to the spooler
	printer::SIGHUP_daemon("devfs");
    }
    1;
}

sub setup_default_spooler {
    my ($printer, $in, $upNetwork) = @_;
    $in->set_help('setupDefaultSpooler') if $::isInstall;
    $printer->{SPOOLER} ||= 'cups';
    my $oldspooler = $printer->{SPOOLER};
    my $str_spooler = 
	$in->ask_from_list_(_("Select Printer Spooler"),
			    _("Which printing system (spooler) do you want to use?"),
			    [ printer::spooler() ],
			    $printer::spooler_inv{$printer->{SPOOLER}},
			    ) or return;
    $printer->{SPOOLER} = $printer::spooler{$str_spooler};
    # Install the spooler if not done yet
    if (!install_spooler($printer, $in, $upNetwork)) {
	$printer->{SPOOLER} = $oldspooler;
	return;
    }
    if ($printer->{SPOOLER} ne $oldspooler) {
	# Remove the local printers from Star Office/OpenOffice.org
	printer::removelocalprintersfromapplications($printer);
	# Get the queues of this spooler
	{
	    my $w = $in->wait_message(_("Printerdrake"),
				      _("Reading printer data..."));
	    printer::read_configured_queues($printer);
	}
	# Copy queues from former spooler
	copy_queues_from($printer, $in, $oldspooler);
	# Re-read the printer database (CUPS has additional drivers, PDQ
	# has no raw queue)
	%printer::thedb = ();
	#my $w = $in->wait_message(_("Printerdrake"),
	#                          _("Reading printer database..."));
	#printer::read_printer_db($printer->{SPOOLER});
    }
    # Save spooler choice
    printer::set_default_spooler($printer);
    return $printer->{SPOOLER};
}

sub configure_queue {
    my ($printer, $in) = @_;
    my $w = $in->wait_message(_("Printerdrake"),
			      _("Configuring printer \"%s\"...",
				$printer->{currentqueue}{queue}));
    $printer->{complete} = 1;
    printer::configure_queue($printer);
    $printer->{complete} = 0;
}

sub install_foomatic {
    my ($in) = @_;
    if ((!$::testing) &&
	(!printer::files_exist((qw(/usr/bin/foomatic-configure
				       /usr/lib/perl5/vendor_perl/5.8.0/Foomatic/DB.pm)
				    )))) {
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Installing Foomatic..."));
	$in->do_pkgs->install('foomatic');
    }
}

sub wizard_close {
    my ($in, $mode) = @_;
    # Leave wizard mode with congratulations screen if $mode = 1
    $::Wizard_no_previous = 1;
    $::Wizard_no_cancel = 1;
    $::Wizard_finished = 1;
    wizard_congratulations($in) if ($mode == 1);
    undef $::isWizard;
    $::WizardWindow->destroy if defined $::WizardWindow;
    undef $::WizardWindow;
};

#- Program entry point for configuration of the printing system.
sub main {
    my ($printer, $in, $ask_multiple_printer, $upNetwork) = @_;

    # Default printer name, we do not use "lp" so that one can switch the
    # default printer under LPD without needing to rename another printer.
    # Under LPD the alias "lp" will be given to the default printer.
    my $defaultprname = _("Printer");

    # printerdrake does not work without foomatic, and for more convenience
    # we install some more stuff
    {
	my $w = $in->wait_message(_("Printerdrake"),
				  _("Checking installed software..."));
	if ((!$::testing) &&
	    (!printer::files_exist((qw(/usr/bin/foomatic-configure
				       /usr/lib/perl5/vendor_perl/5.8.0/Foomatic/DB.pm
				       /usr/bin/escputil
				       /usr/share/printer-testpages/testprint.ps
				       /usr/bin/nmap
				       /usr/bin/scli
				       ),
				    (printer::files_exist("/usr/bin/gimp") ?
				     "/usr/lib/gimp/1.2/plug-ins/print" : ())
				    )))) {
	    $in->do_pkgs->install('foomatic','printer-utils','printer-testpages','nmap','scli',
				  if_($in->do_pkgs->is_installed('gimp'), 'gimpprint'));
	}

	# only experts should be asked for the spooler
	!$::expert and $printer->{SPOOLER} ||= 'cups';

    }

    # If we have chosen a spooler, install it and mark it as default spooler
    if (($printer->{SPOOLER}) && ($printer->{SPOOLER} ne '')) {
	if (!install_spooler($printer, $in, $upNetwork)) { return }
        printer::set_default_spooler($printer);
    }

    # Turn on printer autodetection by default
    $printer->{AUTODETECT} = 1;
    $printer->{AUTODETECTLOCAL} = 1;
    $printer->{AUTODETECTNETWORK} = 1;
    $printer->{AUTODETECTSMB} = 1;

    # Control variables for the main loop
    my ($menuchoice, $cursorpos, $queue, $continue, $newqueue, $editqueue, $expertswitch, $menushown) = ('', '::', $defaultprname, 1, 0, 0, 0, 0);
    # Cursor position in queue modification window
    my $modify = _("Printer options");
    while ($continue) {
	$newqueue = 0;
	# When the queue list is not shown, cancelling the printer type
	# dialog should leave the program
	$continue = 0;
	# Get the default printer
	if (defined($printer->{SPOOLER}) && ($printer->{SPOOLER} ne '') &&
	    ((!defined($printer->{DEFAULT})) || ($printer->{DEFAULT} eq ''))) {
	    my $w = $in->wait_message(_("Printerdrake"),
				      _("Preparing Printerdrake..."));
	    $printer->{DEFAULT} = printer::get_default_printer($printer);
	    if ($printer->{DEFAULT}) {
		# If a CUPS system has only remote printers and no default
		# printer defined, it defines the first printer whose
		# broadcast signal appeared after the start of the CUPS
		# daemon, so on every start another printer gets the default
		# printer. To avoid this, make sure that the default printer
		# is defined.
		printer::set_default_printer($printer);
	    } else {
		$printer->{DEFAULT} = '';
	    }
	}

	# Configure the current printer queues in applications
	{
	    my $w = $in->wait_message(_("Printerdrake"),
				      _("Configuring applications..."));
	    printer::configureapplications($printer);
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
	    $modify = _("Printer options");
	    if (!$ask_multiple_printer && 
		%{$printer->{configured} || {}} == ()) {
		$in->set_help('doYouWantToPrint') if $::isInstall;
		$newqueue = 1;
		$menuchoice = $printer->{want} || 
		    $in->ask_yesorno(_("Printer"),
				    _("Would you like to configure printing?"),
				    0) ? "\@addprinter" : "\@quit";
		if ($menuchoice ne "\@quit") {
		    $printer->{SPOOLER} ||= 
			setup_default_spooler ($printer, $in, $upNetwork) ||
			    return;
		}
	    } else {
		# Ask for a spooler when none is defined
		$printer->{SPOOLER} ||=  setup_default_spooler ($printer, $in, $upNetwork) || return;
		# This entry and the check for this entry have to use
		# the same translation to work properly
		my $spoolerentry = _("Printing system: ");
		# Show a queue list window when there is at least one queue,
		# when we are in expert mode, or when we are not in the
		# installation.
		unless ((!%{$printer->{configured} || {}}) && 
			(!$::expert) && ($::isInstall)) {
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
		    if (($cursorpos eq "::") && 
			($printer->{DEFAULT}) &&
			($printer->{DEFAULT} ne "")) {
			if ($printer->{configured}{$printer->{DEFAULT}}) {
			    $cursorpos = 
				$printer->{configured}{$printer->{DEFAULT}}{queuedata}{menuentry} . _(" (Default)");
			} elsif ($printer->{SPOOLER} eq "cups") {
			    ($cursorpos) = 
				grep { /!$printer->{DEFAULT}:[^!]*$/ }
			    printer::get_cups_remote_queues($printer);
			}
		    }
		    # Generate the list of available printers
		    my @printerlist = 
			((sort((map { $printer->{configured}{$_}{queuedata}{menuentry} 
				      . ($_ eq $printer->{DEFAULT} ?
					 _(" (Default)") : (""))}
				 keys(%{$printer->{configured}
					|| {}})),
				($printer->{SPOOLER} eq "cups" ?
				 printer::get_cups_remote_queues($printer)
				 : ())))
			  );
		    my $noprinters = ($#printerlist < 0);
		    # Position the cursor where it were before (in case
		    # a button was pressed).
		    $menuchoice = $cursorpos;
		    # Show the main dialog
		    $in->ask_from_(
			{ title => _("Printerdrake"),
			 messages =>
			     ($noprinters ? "" :
			      (($printer->{SPOOLER} eq "cups") ?
			       _("The following printers are configured. Double-click on a printer to change its settings; to make it the default printer; to view information about it; or to make a printer on a remote CUPS server available for Star Office/OpenOffice.org.") :
			       _("The following printers are configured. Double-click on a printer to change its settings; to make it the default printer; or to view information about it."))),
			 cancel => (""),
			 ok => (""),
			},
			# List the queues
			[ ($noprinters ? () :
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
			    val => _("Add a new printer") },
			  ($printer->{SPOOLER} eq "cups" ?
			    ({ clicked_may_quit =>
				   sub { 
				       # Save the cursor position
				       $cursorpos = $menuchoice;
				       $menuchoice = "\@refresh";
				       1;
				   },
			       val => _("Refresh printer list (to display all available remote CUPS printers)") },
			     { clicked_may_quit =>
				   sub { 
				       # Save the cursor position
				       $cursorpos = $menuchoice;
				       $menuchoice = "\@cupsconfig";
				       1;
				   },
			       val => ($::expert ? _("CUPS configuration") :
				       _("Specify CUPS server")) }) : ()),
			  ($::expert ?
			    { clicked_may_quit =>
				  sub {
				      # Save the cursor position
				      $cursorpos = $menuchoice;
				      $menuchoice = "\@spooler";
				      1;
				  },
				  val => _("Change the printing system") } :
			    ()),
			  (!$::isInstall ?
			    { clicked_may_quit =>
				  sub { $menuchoice = "\@usermode"; 1 },
				  val => ($::expert ? _("Normal Mode") :
					  _("Expert Mode")) } : ()),
			  { clicked_may_quit =>
			    sub { $menuchoice = "\@quit"; 1 },
			    val => ($::isEmbedded || $::isInstall ?
				    _("Done") : _("Quit")) },
			  ]
		    );
		    # Toggle expert mode and standard mode
		    if ($menuchoice eq "\@usermode") {
			$::expert = !$::expert;
			# Read printer database for the new user mode
			%printer::thedb = ();
			#my $w = $in->wait_message(_("Printerdrake"), 
			#                   _("Reading printer database..."));
		        #printer::read_printer_db($printer->{SPOOLER});
			# Re-read printer queues to switch the tree
			# structure between expert/normal mode.
			my $w = $in->wait_message
			    (_("Printerdrake"), 
			     _("Reading printer data..."));
			printer::read_configured_queues($printer);
			$cursorpos = "::";
			next;
		    }
		} else {
		    #- as there are no printer already configured, Add one
		    #- automatically.
		    $menuchoice = "\@addprinter"; 
		}
		# Refresh printer list
		if ($menuchoice eq "\@refresh") {
		    next;
		}
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
		    $printer->{SPOOLER} = setup_default_spooler ($printer, $in, $upNetwork) || $printer->{SPOOLER};
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
	    printer::set_default_spooler($printer);
	    #- Close printerdrake
	    $menuchoice eq "\@quit" and last;
	}
	if ($newqueue) {
	    $printer->{NEW} = 1;
	    #- Set default values for a new queue
	    $printer::printer_type_inv{$printer->{TYPE}} or 
		$printer->{TYPE} = printer::default_printer_type($printer);
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
	    if ((!$::isEmbedded) && (!$::isInstall) &&
	    #if ((!$::isInstall) &&
		($in->isa('interactive::gtk'))) {
		$continue = 1;
		# Enter wizard mode
		$::Wizard_pix_up = "wiz_printerdrake.png";
		$::Wizard_title = _("Add a new printer");
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
		    if (($::expert) or ($printer->{MANUAL}) or
			($printer->{MORETHANONE})) {
			choose_printer_name($printer, $in) or
			    goto step_2;
		    }
		    get_db_entry($printer, $in);
		  step_3_9:
		    if ((!$::expert) and (!$printer->{MANUAL})) {
			is_model_correct($printer, $in) or do {
			    goto step_3 if $printer->{MORETHANONE};
			    goto step_2;
			}
		    }
		  step_4:
		    # Remember DB entry for "Previous" button in wizard
		    my $dbentry = $printer->{DBENTRY};
		    if (($::expert) or ($printer->{MANUAL}) or
			($printer->{MANUALMODEL})) { 
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
			($printer->{QUEUE} eq $printer->{DEFAULT} ?
			 _(" (Default)") : ());
		    my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
		    if ($testpages == 1) {
			# User was content with test pages
			# Leave wizard mode with congratulations screen
			wizard_close($in, 1);
			$continue = ($::expert || !$::isInstall || $menushown ||
				     $in->ask_yesorno('',_("Do you want to configure another printer?")));
		    } elsif ($testpages == 2) {
			# User was not content with test pages
			# Leave wizard mode without congratulations
			# screen
			wizard_close($in, 0);
			$editqueue = 1;
			$queue = $printer->{QUEUE};
		    }
		};
		wizard_close($in, 0) if ($@ =~ /wizcancel/);
	    } else {
		$::expert or $printer->{TYPE} = "LOCAL";
		$::expert or wizard_welcome($printer, $in, $upNetwork) or next;
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
		if (($::expert) or ($printer->{MANUAL}) or
		    ($printer->{MORETHANONE})) {
		    choose_printer_name($printer, $in) or next;
		}
		get_db_entry($printer, $in);
		if ((!$::expert) and (!$printer->{MANUAL})) {
		    is_model_correct($printer, $in) or next;
		}
		if (($::expert) or ($printer->{MANUAL}) or
		    ($printer->{MANUALMODEL})) { 
		    choose_model($printer, $in) or next;
		}
		get_printer_info($printer, $in) or next;
		setup_options($printer, $in) or next;
		configure_queue($printer, $in);
		undef $printer->{MANUAL} if $printer->{MANUAL};
		setasdefault($printer, $in);
		$cursorpos = 
		    $printer->{configured}{$printer->{QUEUE}}{queuedata}{menuentry} .
		    ($printer->{QUEUE} eq $printer->{DEFAULT} ?
		     _(" (Default)") : ());
		my $testpages = print_testpages($printer, $in, $printer->{TYPE} !~ /LOCAL/ && $upNetwork);
		if ($testpages == 1) {
		    # User was content with test pages
		    $continue = ($::expert || !$::isInstall || $menushown ||
				 $in->ask_yesorno('',_("Do you want to configure another printer?")));
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
		printer::make_menuentry($printer,$queue);
		$printer->{configured}{$queue}{queuedata}{menuentry} =~
		    /!([^!]+)$/;
		$infoline = $1 .
		    ($queue eq $printer->{DEFAULT} ? _(" (Default)") : ()) .
		    ($printer->{configured}{$queue}{queuedata}{desc} ?
		     ", Descr.: $printer->{configured}{$queue}{queuedata}{desc}" : ()) .
		    ($printer->{configured}{$queue}{queuedata}{loc} ?
		     ", Loc.: $printer->{configured}{$queue}{queuedata}{loc}" : ()) .
		    ($::expert ?
		     ", Driver: $printer->{configured}{$queue}{queuedata}{driver}" : ());
	    } else {
		# The parameters of a remote CUPS queue cannot be changed,
		# so we can simply take the menu entry.
		$cursorpos =~ /!([^!]+)$/;
		$infoline = $1;
	    }
	    if ($in->ask_from_
		   ({ title => _("Modify printer configuration"),
		      messages => 
			   _("Printer %s
What do you want to modify on this printer?",
			     $infoline),
		     cancel => _("Close"),
		     ok => _("Do it!")
		     },
		    [ { val => \$modify, format => \&translate, 
			type => 'list',
			list => [ ($printer->{configured}{$queue} ?
				   (_("Printer connection type"),
				    _("Printer name, description, location"),
				    ($::expert ?
				     _("Printer manufacturer, model, driver") :
				     _("Printer manufacturer, model")),
				    (($printer->{configured}{$queue}{queuedata}{make} ne
				      "") &&
				     (($printer->{configured}{$queue}{queuedata}{model} ne
				       _("Unknown model")) &&
				      ($printer->{configured}{$queue}{queuedata}{model} ne
				       _("Raw printer"))) ?
				     _("Printer options") : ())) : ()),
				   (($queue ne $printer->{DEFAULT}) ?
				    _("Set this printer as the default") : ()),
				   ($printer->{configured}{$queue} ? () :
				    (_("Add this printer to Star Office/OpenOffice.org"),
				     _("Remove this printer from Star Office/OpenOffice.org"))),
				   _("Print test pages"),
				   _("Know how to use this printer"),
				   ($printer->{configured}{$queue} ?
				    _("Remove printer") : ()) ] } ] ) ) {
		# Stay in the queue edit window until the user clicks "Close"
		# or deletes the queue
		$editqueue = 1; 
		#- Copy the queue data and work on the copy
		$printer->{currentqueue} = {};
		my $driver;
		if ($printer->{configured}{$queue}) {
		    printer::copy_printer_params($printer->{configured}{$queue}{queuedata}, $printer->{currentqueue});
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
		my $type;
		if ($printer->{configured}{$queue}) {
		    for $type (qw(file lpd socket smb ncp postpipe)) {
			if ($printer->{currentqueue}{connect}
			    =~ /^$type:/) {
			    $printer->{TYPE} = 
				($type eq 'file' ? 'LOCAL' : uc($type));
			    last;
			}
		    }
		}
		# Do the chosen task
		if ($modify eq _("Printer connection type")) {
		    choose_printer_type($printer, $in) &&
			setup_printer_connection($printer, $in, $upNetwork) &&
		            configure_queue($printer, $in);
		} elsif ($modify eq _("Printer name, description, location")) {
		    choose_printer_name($printer, $in) &&
			configure_queue($printer, $in);
		    # Delete old queue when it was renamed
		    if (lc($printer->{QUEUE}) ne lc($printer->{OLD_QUEUE})) {
			my $w = $in->wait_message
			    (_("Printerdrake"),
			     _("Removing old printer \"%s\"...",
			       $printer->{OLD_QUEUE}));
		        printer::remove_queue($printer, $printer->{OLD_QUEUE});
			# If the default printer was renamed, correct the
			# the default printer setting of the spooler
			if ($queue eq $printer->{DEFAULT}) {
			    $printer->{DEFAULT} = $printer->{QUEUE};
			    printer::set_default_printer($printer);
			}
			$queue = $printer->{QUEUE};
		    }
		} elsif (($modify eq _("Printer manufacturer, model, driver")) ||
			 ($modify eq _("Printer manufacturer, model"))) {
		    get_db_entry($printer, $in);
		    choose_model($printer, $in) &&
			get_printer_info($printer, $in) &&
			setup_options($printer, $in) &&
			configure_queue($printer, $in);
		} elsif ($modify eq _("Printer options")) {
		    get_printer_info($printer, $in) &&
			setup_options($printer, $in) &&
			configure_queue($printer, $in);
		} elsif ($modify eq _("Set this printer as the default")) {
		    $printer->{DEFAULT} = $queue;
		    printer::set_default_printer($printer);
		    $in->ask_warn(_("Default printer"),
				  _("The printer \"%s\" is set as the default printer now.", $queue));
		} elsif ($modify eq _("Add this printer to Star Office/OpenOffice.org")) {
		    if (printer::addcupsremotetoapplications
			($printer, $queue)) {
			$in->ask_warn(_("Adding printer to Star Office/OpenOffice.org"),
				      _("The printer \"%s\" was successfully added to Star Office/OpenOffice.org.", $queue));
		    } else {
			$in->ask_warn(_("Adding printer to Star Office/OpenOffice.org"),
				      _("Failed to add the printer \"%s\" to Star Office/OpenOffice.org.", $queue));
		    }
		} elsif ($modify eq _("Remove this printer from Star Office/OpenOffice.org")) {
		    if (printer::removeprinterfromapplications
			($printer, $queue)) {
			$in->ask_warn(_("Removing printer from Star Office/OpenOffice.org"),
				      _("The printer \"%s\" was successfully removed from Star Office/OpenOffice.org.", $queue));
		    } else {
			$in->ask_warn(_("Removing printer from Star Office/OpenOffice.org"),
				      _("Failed to remove the printer \"%s\" from Star Office/OpenOffice.org.", $queue));
		    }
		} elsif ($modify eq _("Print test pages")) {
		    print_testpages($printer, $in, $upNetwork);
		} elsif ($modify eq _("Know how to use this printer")) {
		    printer_help($printer, $in);
		} elsif ($modify eq _("Remove printer")) {
		    if ($in->ask_yesorno('',
           _("Do you really want to remove the printer \"%s\"?", $queue), 1)) {
			{
			    my $w = $in->wait_message
				(_("Printerdrake"),
				 _("Removing printer \"%s\"...", $queue));
			    if (printer::remove_queue($printer, $queue)) { 
				$editqueue = 0;
				# Define a new default printer if we have
				# removed the default one
				if ($queue eq $printer->{DEFAULT}) {
				    my @k = sort(keys(%{$printer->{configured}}));
				    if (@k) {
					$printer->{DEFAULT} = $k[0];
				        printer::set_default_printer($printer);
				    } else {
					$printer->{DEFAULT} = "";
				    }
				}
				# Let the main menu cursor go to the default
				# position
				$cursorpos = "::";
			    }
			}
		    }		
		}
		# Make sure that the cursor is still at the same position
		# in the main menu when one has modified something on the
		# current printer
		if (($printer->{QUEUE}) && ($printer->{QUEUE} ne "")) {
		    if ($printer->{configured}{$printer->{QUEUE}}) {
			$cursorpos = 
			    $printer->{configured}{$printer->{QUEUE}}{queuedata}{menuentry} . 
			    ($printer->{QUEUE} eq $printer->{DEFAULT} ? 
			     _(" (Default)") : ());
		    } else {
			my $s1 = _(" (Default)");
			my $s2 = $s1;
			$s2 =~ s/\(/\\\(/;
			$s2 =~ s/\)/\\\)/;
			if (($printer->{QUEUE} eq $printer->{DEFAULT}) &&
			    ($cursorpos !~ /$s2/)) {
			    $cursorpos .= $s1;
			}
		    }
		}
	    } else {
		$editqueue = 0;
	    }
	    $continue = ($editqueue || $::expert || !$::isInstall || 
			 $menushown ||
			 $in->ask_yesorno('',_("Do you want to configure another printer?")));
	}

	# Configure the current printer queue in applications when main menu
	# will not be shown (During installation in "Recommended" mode)
	if ($::isInstall && !$::expert && !$menushown && !$continue) {
	    my $w = $in->wait_message(_("Printerdrake"),
				      _("Configuring applications..."));
	    printer::configureapplications($printer);
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
    for my $queue (keys %{$printer->{configured}}) {
	for my $item (keys %{$printer->{configured}{$queue}}) {
	    if ($item ne "queuedata") {
		delete($printer->{configured}{$queue}{$item});
	    }
	}
	if ($printer->{configured}{$queue}{queuedata}{menuentry}) {
	    delete($printer->{configured}{$queue}{queuedata}{menuentry});
	}
    }
    foreach (qw(Old_queue QUEUE TYPE str_type currentqueue DBENTRY ARGS complete OLD_CHOICE NEW MORETHANONE MANUALMODEL AUTODETECT AUTODETECTLOCAL AUTODETECTNETWORK AUTODETECTSMB))
    { delete $printer->{$_} };
}

