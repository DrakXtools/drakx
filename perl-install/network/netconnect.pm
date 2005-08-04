package network::netconnect; # $Id$

use strict;
use common;
use log;
use detect_devices;
use list_modules;
use modules;
use mouse;
use services;
use network::network;
use network::tools;
use network::thirdparty;

sub detect {
    my ($modules_conf, $auto_detect, $o_class) = @_;
    my %l = (
             isdn => sub {
                 require network::isdn;
                 $auto_detect->{isdn} = network::isdn::detect_backend($modules_conf);
             },
             lan => sub { # ethernet
                 require network::ethernet;
                 modules::load_category($modules_conf, list_modules::ethernet_categories());
                 $auto_detect->{lan} = { map { $_->[0] => $_->[1] } network::ethernet::get_eth_cards($modules_conf) };
             },
             adsl => sub {
                 require network::adsl;
                 $auto_detect->{adsl} = network::adsl::adsl_detect();
             },
             modem => sub {
                 $auto_detect->{modem} = { map { $_->{description} || "$_->{MANUFACTURER}|$_->{DESCRIPTION} ($_->{device})" => $_ } detect_devices::getModem($modules_conf) };
             },
            );
    $l{$_}->() foreach $o_class || keys %l;
    return;
}

sub detect_timezone() {
    my %tmz2country = ( 
		       'Europe/Paris' => N("France"),
		       'Europe/Amsterdam' => N("Netherlands"),
		       'Europe/Rome' => N("Italy"),
		       'Europe/Brussels' => N("Belgium"),
		       'America/New_York' => N("United States"),
		       'Europe/London' => N("United Kingdom")
		      );
    my %tm_parse = MDK::Common::System::getVarsFromSh("$::prefix/etc/sysconfig/clock");
    my @country;
    foreach (keys %tmz2country) {
	if ($_ eq $tm_parse{ZONE}) {
	    unshift @country, $tmz2country{$_};
	} else { push @country, $tmz2country{$_} }
    }
    \@country;
}

sub real_main {
      my ($net, $in, $modules_conf) = @_;
      #- network configuration should have been already read in $net at this point
      my $mouse = $::o->{mouse} || {};
      my ($cnx_type, @all_cards, %eth_intf, %all_eth_intf);
      my (%connections, @connection_list);
      my ($modem, $modem_name, $modem_dyn_dns, $modem_dyn_ip);
      my $cable_no_auth;
      my (@adsl_devices, %adsl_cards, %adsl_data, $adsl_data, $adsl_provider, $adsl_old_provider, $adsl_vpi, $adsl_vci);
      my ($ntf_name, $gateway_ex, $up);
      my ($isdn, $isdn_name, $isdn_type, %isdn_cards, @isdn_dial_methods);
      my $my_isdn = join('', N("Manual choice"), " (", N("Internal ISDN card"), ")");
      my (@ndiswrapper_drivers, $ndiswrapper_driver, $ndiswrapper_device);
      my ($is_wireless, $wireless_enc_mode, $wireless_enc_key, $need_rt2x00_iwpriv);
      my ($dvb_adapter, $dvb_ad, $dvb_net, $dvb_pid);
      my ($module, $auto_ip, $protocol, $onboot, $needhostname, $peerdns, $peeryp, $peerntpd, $ifplugd, $track_network_id); # lan config
      my $success = 1;
      my $ethntf = {};
      my $db_path = "/usr/share/apps/kppp/Provider";
      my (%countries, @isp, $country, $provider, $old_provider);

      my %l10n_lan_protocols = (
                               static => N("Manual configuration"),
                               dhcp   => N("Automatic IP (BOOTP/DHCP)"),
                               if_(0,
                               dhcp_zeroconf   => N("Automatic IP (BOOTP/DHCP/Zeroconf)"),
                                  )
                              );
      my $_w = N("Protocol for the rest of the world");
      my %isdn_protocols = (
                            2 => N("European protocol (EDSS1)"),
                            3 => N("Protocol for the rest of the world\nNo D-Channel (leased lines)"),
                           );

      $net->{autodetect} = {};

      my $lan_detect = sub {
          detect($modules_conf, $net->{autodetect}, 'lan');
          @all_cards = network::ethernet::get_eth_cards($modules_conf);
          %all_eth_intf = network::ethernet::get_eth_cards_names(@all_cards); #- needed not to loose GATEWAYDEV
          %eth_intf = map { $_->[0] => join(': ', $_->[0], $_->[2]) }
            grep { to_bool($is_wireless) == detect_devices::is_wireless_interface($_->[0]) } @all_cards;
      };

      my $is_dvb_interface = sub { $_[0]{DEVICE} =~ /^dvb\d+_\d+/ };

      my $find_lan_module = sub {
          if (my $dev = find { $_->{device} eq $ethntf->{DEVICE} } detect_devices::pcmcia_probe()) { # PCMCIA case
              $module = $dev->{driver};
          } elsif ($dev = find { $_->[0] eq $ethntf->{DEVICE} } @all_cards) {
              $module = $dev->[1];
	  } elsif ($is_dvb_interface->($ethntf)) {
	      $module = $dvb_adapter->{driver};
          } else { $module = "" }
      };

      my $is_ifplugd_blacklisted = sub {
          bool2yesno(member($module, qw(b44 forcedeth madwifi_pci via-velocity)) ||
                     $is_wireless ||
                     find { $_->{device} eq $ntf_name } detect_devices::pcmcia_probe());
      };

      my %adsl_descriptions = (
                          speedtouch => N("Alcatel speedtouch USB modem"),
                          sagem => N("Sagem USB modem"),
                          bewan => N("Bewan modem"),
                          eci       => N("ECI Hi-Focus modem"), # this one needs eci agreement
                         );

      my %adsl_types = (
                        dhcp   => N("Dynamic Host Configuration Protocol (DHCP)"),
                        static => N("Manual TCP/IP configuration"),
                        pptp  => N("Point to Point Tunneling Protocol (PPTP)"),
                        pppoe  => N("PPP over Ethernet (PPPoE)"),
                        pppoa  => N("PPP over ATM (PPPoA)"),
                        capi  => N("DSL over CAPI"),
                       );

      my %encapsulations = (
                            1 => N("Bridged Ethernet LLC"), 
                            2 => N("Bridged Ethernet VC"), 
                            3 => N("Routed IP LLC"), 
                            4 => N("Routed IP VC"),
                            5 => N("PPPoA LLC"), 
                            6 => N("PPPoA VC"),
                           );

      my %ppp_auth_methods = (
                              0 => N("Script-based"),
                              1 => N("PAP"),
                              2 => N("Terminal-based"),
                              3 => N("CHAP"),
                              4 => N("PAP/CHAP"),
                             );

      my %wireless_enc_modes = (
                                none => N("None"),
                                open => N("Open WEP"),
                                restricted => N("Restricted WEP"),
                                'wpa-psk' => N("WPA Pre-Shared Key"),
                               );

      my $offer_to_connect = sub {
	  if ($net->{type} eq 'adsl' && !member($net->{adsl}{method}, qw(static dhcp)) ||
	      member($net->{type}, qw(modem isdn isdn_external))) {
	      return "ask_connect_now";
	  } else {
	      network::tools::stop_net_interface($net, 0);
	      network::tools::start_net_interface($net, 0);
	  }
          return "end";
      };

      my $after_lan_intf_selection = sub { $is_wireless ? 'wireless' : 'lan_protocol' };

      my $after_start_on_boot_step = sub {
	  #- can't be done in adsl_account step because of static/dhcp adsl methods
	  #- we need to write sagem specific parameters and load corresponding modules/programs (sagem/speedtouch)
	  $net->{type} eq 'adsl' and network::adsl::adsl_conf_backend($in, $modules_conf, $net);

          network::network::configure_network($net, $in, $modules_conf);
          return $offer_to_connect->();
      };

      my $goto_start_on_boot_ifneeded = sub {
          return $after_start_on_boot_step->() if $net->{type} eq "lan";
          return "isdn_dial_on_boot" if  $net->{type} eq 'isdn';
          return "network_on_boot";
      };

      my $delete_gateway_settings = sub {
          my ($device) = @_;
          #- delete gateway settings if gateway device is invalid or matches the reconfigured device
          if (!$net->{network}{GATEWAYDEV} || !exists $eth_intf{$net->{network}{GATEWAYDEV}} || $net->{network}{GATEWAYDEV} eq $device) {
              delete $net->{network}{GATEWAY};
              delete $net->{network}{GATEWAYDEV};
          }
      };

      my $ndiswrapper_do_device_selection = sub {
          $ntf_name = network::ndiswrapper::setup_device($in, $ndiswrapper_device);
          unless ($ntf_name) {
              undef $ndiswrapper_device;
              return;
          }

          #- redetect interfaces (so that the ndiswrapper module can be detected)
          $lan_detect->();

          $ethntf = $net->{ifcfg}{$ntf_name} ||= { DEVICE => $ntf_name };

          1;
      };

      my $ndiswrapper_do_driver_selection = sub {
          my @devices = network::ndiswrapper::get_devices($in, $ndiswrapper_driver);

          if (!@devices) {
              undef $ndiswrapper_driver;
              return;
          } elsif (@devices == 1) {
              #- only one device matches installed driver
              $ndiswrapper_device = $devices[0];
              return $ndiswrapper_do_device_selection->();
          }

          1;
      };

      my $ndiswrapper_next_step = sub {
          return $ndiswrapper_device ? $after_lan_intf_selection->() :
                 $ndiswrapper_driver ? 'ndiswrapper_select_device' :
                 'ndiswrapper_select_driver';
      };

      use locale;
      set_l10n_sort();

      # main wizard:
      my $wiz;
      $wiz =
        {
         defaultimage => "drakconnect.png",
         name => N("Network & Internet Configuration"),
         pages => {
                   welcome =>
                   {
                    pre => sub {
                        my @connections = (
                                          [ N("LAN connection"),    "lan"   ],
                                          [ N("Wireless connection"), "lan" ],
                                          [ N("ADSL connection"),   "adsl"  ],
                                          [ N("Cable connection"),  "cable" ],
                                          [ N("ISDN connection"),   "isdn"  ],
                                          [ N("Modem connection"),  "modem" ],
                                          [ N("DVB connection"), "dvb" ],
                                         );

                        foreach (@connections) {
                            my ($string, $type) = @$_;
                            $connections{$string} = $type;
                        }
                        @connection_list = { val => \$cnx_type, type => 'list', list => [ map { $_->[0] } @connections ], };
                    },
                    if_(!$::isInstall, no_back => 1),
                    name => N("Choose the connection you want to configure"),
                    interactive_help_id => 'configureNetwork',
                    data => \@connection_list,
                    post => sub {
                        $is_wireless = $cnx_type eq N("Wireless connection");
                        return $net->{type} = $connections{$cnx_type};
                    },
                   },

                   isdn_account =>
                   {
                    pre => sub {
                        network::isdn::get_info_providers_backend($isdn, $provider);
                        $isdn->{huptimeout} ||= 180;
                    },
                    name => N("Connection Configuration") . "\n\n" . N("Please fill or check the field below"),
                    data => sub {
			[
			 { label => N("Your personal phone number"), val => \$isdn->{phone_in} },
			 { label => N("Provider name (ex provider.net)"), val => \$net->{resolv}{DOMAINNAME2} },
			 { label => N("Provider phone number"), val => \$isdn->{phone_out} },
			 { label => N("Provider DNS 1 (optional)"), val => \$net->{resolv}{dnsServer2} },
			 { label => N("Provider DNS 2 (optional)"), val => \$net->{resolv}{dnsServer3} },
			 { label => N("Dialing mode"),  list => ["auto", "manual"], val => \$isdn->{dialing_mode} },
			 { label => N("Connection speed"), list => ["64 Kb/s", "128 Kb/s"], val => \$isdn->{speed} },
			 { label => N("Connection timeout (in sec)"), val => \$isdn->{huptimeout} },
			 { label => N("Account Login (user name)"), val => \$isdn->{login} },
			 { label => N("Account Password"),  val => \$isdn->{passwd}, hidden => 1 },
			 { label => N("Card IRQ"), val => \$isdn->{irq}, advanced => 1 },
			 { label => N("Card mem (DMA)"), val => \$isdn->{mem}, advanced => 1 },
			 { label => N("Card IO"), val => \$isdn->{io}, advanced => 1 },
			 { label => N("Card IO_0"), val => \$isdn->{io0}, advanced => 1 },
			 { label => N("Card IO_1"), val => \$isdn->{io1}, advanced => 1 },
			];
		    },
                    post => sub {
                        network::isdn::write_config($in, $isdn);
                        $net->{net_interface} = 'ippp0';
                        "allow_user_ctl";
                    },
                   },

                   cable =>
                   {
                    pre => sub {
                        $cable_no_auth = sub { $net->{cable}{bpalogin} eq N("None") };
                    },
                    name => N("Cable: account options"),
                    data => sub {
                        [
                            { label => N("Authentication"), type => "list", val => \$net->{cable}{bpalogin}, list => [ N("None"), N("Use BPALogin (needed for Telstra)") ] },
                            { label => N("Account Login (user name)"), val => \$net->{cable}{login}, disabled => $cable_no_auth },
                            { label => N("Account Password"),  val => \$net->{cable}{passwd}, hidden => 1, disabled => $cable_no_auth },
                        ];
                    },
                    post => sub {
			my $use_bpalogin = !$cable_no_auth->();
			if ($in->do_pkgs->install("bpalogin")) {
			    substInFile {
				s/username\s+.*\n/username $net->{cable}{login}\n/;
				s/password\s+.*\n/password $net->{cable}{passwd}\n/;
			    } "$::prefix/etc/bpalogin.conf";
			}
			services::set_status("bpalogin", $use_bpalogin);
                        $auto_ip = 1;
                        return "lan";
                    }
                   },

                   isdn =>
                   {
                    pre=> sub {
                        detect($modules_conf, $net->{autodetect}, 'isdn');
                        %isdn_cards = map { $_->{description} => $_ } @{$net->{autodetect}{isdn}};
                    },
                    name => N("Select the network interface to configure:"),
                    data =>  sub {
                        [ { label => N("Net Device"), type => "list", val => \$isdn_name, allow_empty_list => 1,
                            list => [ $my_isdn, N("External ISDN modem"), keys %isdn_cards ] } ];
                    },
                    post => sub {
                        if ($isdn_name eq $my_isdn) {
                            return "isdn_ask";
                        } elsif ($isdn_name eq N("External ISDN modem")) {
                            $net->{type} = 'isdn_external';
                            return "modem";
                        }

                        # FIXME: some of these should be taken from isdn db
                        $isdn = { map { $_ => $isdn_cards{$isdn_name}{$_} } qw(description vendor id card_type driver type mem io io0 io1 irq firmware) };

                        if ($isdn->{id}) {
                            log::explanations("found isdn card : $isdn->{description}; vendor : $isdn->{vendor}; id : $isdn->{id}; driver : $isdn->{driver}\n");
                            $isdn->{description} =~ s/\|/ -- /;
                        }

                        network::isdn::read_config($isdn);
                        $isdn->{driver} = $isdn_cards{$isdn_name}{driver}; #- do not let config overwrite default driver

                        #- let the user choose hisax or capidrv if both are available
                        $isdn->{driver} ne "capidrv" && network::isdn::get_capi_card($in, $isdn) and return "isdn_driver";
                        return "isdn_protocol";
                    },
                   },


                   isdn_ask =>
                   {
                    pre => sub {
                        %isdn_cards = network::isdn::get_cards();
                    },
                    name => N("Select a device!"),
                    data => sub { [ { label => N("Net Device"), val => \$isdn_name, type => 'list', separator => '|', list => [ keys %isdn_cards ], allow_empty_list => 1 } ] },
                    pre2 => sub {
                        my ($label) = @_;

                        #- ISDN card already detected
                        goto isdn_ask_step_3;

                      isdn_ask_step_1:
                        my $e = $in->ask_from_list_(N("ISDN Configuration"),
                                                    $label . "\n" . N("What kind of card do you have?"),
                                                    [ N_("ISA / PCMCIA"), N_("PCI"), N_("USB"), N_("I do not know") ]
                                                   ) or return;
                      isdn_ask_step_1b:
                        if ($e =~ /PCI/) {
                            $isdn->{card_type} = 'pci';
                        } elsif ($e =~ /USB/) {
                            $isdn->{card_type} = 'usb';
                        } else {
                            $in->ask_from_list_(N("ISDN Configuration"),
                                                N("
If you have an ISA card, the values on the next screen should be right.\n
If you have a PCMCIA card, you have to know the \"irq\" and \"io\" of your card.
"),
                                                [ N_("Continue"), N_("Abort") ]) eq 'Continue' or goto isdn_ask_step_1;
                            $isdn->{card_type} = 'isa';
                        }

                      isdn_ask_step_2:
                        $e = $in->ask_from_listf(N("ISDN Configuration"),
                                                 N("Which of the following is your ISDN card?"),
                                                 sub { $_[0]{description} },
                                                 [ network::isdn::get_cards_by_type($isdn->{card_type}) ]) or goto($isdn->{card_type} =~ /usb|pci/ ? 'isdn_ask_step_1' : 'isdn_ask_step_1b');
                        $e->{$_} and $isdn->{$_} = $e->{$_} foreach qw(driver type mem io io0 io1 irq firmware);

                        },
                    post => sub {
                        $isdn = $isdn_cards{$isdn_name};
                        return "isdn_protocol";
                    }
                   },


                   isdn_driver =>
                   {
                    pre => sub {
                        $isdn_name = "capidrv";
                    },
                    name => N("A CAPI driver is available for this modem. This CAPI driver can offer more capabilities than the free driver (like sending faxes). Which driver do you want to use?"),
                    data => sub { [
                                   { label => N("Driver"), type => "list", val => \$isdn_name,
                                     list => [ $isdn->{driver}, "capidrv" ] }
                                  ] },
                    post => sub {
                        $isdn->{driver} = $isdn_name;
                        return "isdn_protocol";
                    }
                   },


                   isdn_protocol =>
                   {
                    name => N("ISDN Configuration") . "\n\n" . N("Which protocol do you want to use?"),
                    data => [
                             { label => N("Protocol"), type => "list", val => \$isdn_type,
                               list => [ keys %isdn_protocols ], format => sub { $isdn_protocols{$_[0]} } }
                            ],
                    post => sub { 
                        $isdn->{protocol} = $isdn_type;
                        return "isdn_db";
                    }
                   },


                   isdn_db =>
                   {
                    name => N("ISDN Configuration") . "\n\n" . N("Select your provider.\nIf it is not listed, choose Unlisted."),
                    data => sub {
                        [ { label => N("Provider:"), type => "list", val => \$provider, separator => '|',
                            list => [ N("Unlisted - edit manually"), network::isdn::read_providers_backend() ] } ];
                    },
		    next => "isdn_account",
                   },


                   no_supported_winmodem =>
                   {
                    name => N("Warning") . "\n\n" . N("Your modem is not supported by the system.
Take a look at http://www.linmodems.org"),
                    end => 1,
                   },


                   modem =>
                   {
                    pre => sub {
			require network::modem;
			detect($modules_conf, $net->{autodetect}, 'modem');
			$modem = {};
			if ($net->{type} eq 'isdn_external') {
			    #- FIXME: seems to be specific to ZyXEL Adapter Omni.net/TA 128/Elite 2846i
			    #- it does not even work with TA 128 modems
			    #- http://bugs.mandrakelinux.com/query.php?bug=1033
			    $modem->{special_command} = 'AT&F&O2B40';
			}
                    },
                    name => N("Select the modem to configure:"),
                    data => sub {
                        [ { label => N("Modem"), type => "list", val => \$modem_name, allow_empty_list => 1,
                            list => [ keys %{$net->{autodetect}{modem}}, N("Manual choice") ], } ];
                    },
		    complete => sub {
			my $driver = $net->{autodetect}{modem}{$modem_name}{driver} or return 0;
			!network::thirdparty::setup_device($in, 'rtc', $driver, $modem, qw(device));
		    },
                    post => sub {
                        return 'choose_serial_port' if $modem_name eq N("Manual choice");
			if (exists $net->{autodetect}{modem}{$modem_name}{device}) {
			    #- this is a serial probed modem
			    $modem->{device} = $net->{autodetect}{modem}{$modem_name}{device};
			}
			if (exists $modem->{device}) {
			    return "ppp_provider";
			} else {
			    #- driver exists but device field hasn't been filled by network::thirdparty::setup_device
			    return "no_supported_winmodem";
			}
		    },
		   },


                   choose_serial_port =>
                   {
                    pre => sub {
                        $modem->{device} ||= readlink "$::prefix/dev/modem";
                    },
                    name => N("Please choose which serial port your modem is connected to."),
                    interactive_help_id => 'selectSerialPort',
                    data => sub {
                        [ { val => \$modem->{device}, format => \&mouse::serial_port2text, type => "list",
                            list => [ grep { $_ ne $mouse->{device} } (mouse::serial_ports(), grep { -e $_ } '/dev/modem', '/dev/ttySL0', '/dev/ttyS14',) ] } ];
                        },
                    post => sub {
                        return 'ppp_provider';
                    },
                   },


                   ppp_provider =>
                   {
                    pre => sub {
                        add2hash($modem, network::modem::ppp_read_conf());
                        $in->do_pkgs->ensure_is_installed('kdenetwork-kppp-provider', $db_path);
                        my $p_db_path = "$::prefix$db_path";
                        @isp = map {
                            my $country = $_;
                            map { 
                                s!$p_db_path/$country!!;
                                s/%([0-9]{3})/chr(int($1))/eg;
                                $countries{$country} ||= translate($country);
                                join('', $countries{$country}, $_);
                            } grep { !/.directory$/ } glob_("$p_db_path/$country/*");
                        } map { s!$p_db_path/!!o; s!_! !g; $_ } glob_("$p_db_path/*");
                        $old_provider = $provider;
                    },
                    name => N("Select your provider:"),
                    data => sub {
                        [ { label => N("Provider:"), type => "list", val => \$provider, separator => '/',
                            list => [ N("Unlisted - edit manually"), @isp ] } ];
                    },
                    post => sub {
                        if ($provider ne N("Unlisted - edit manually")) {
                            ($country, $provider) = split('/', $provider);
                            $country = { reverse %countries }->{$country};
                            my %l = getVarsFromSh("$::prefix$db_path/$country/$provider");
                            if (defined $old_provider && $old_provider ne $provider) {
                                $modem->{connection} = $l{Name};
                                $modem->{phone} = $l{Phonenumber};
                                $modem->{$_} = $l{$_} foreach qw(Authentication AutoName Domain Gateway IPAddr SubnetMask);
                                ($modem->{dns1}, $modem->{dns2}) = split(',', $l{DNS});
                            }
                        }
                        return "ppp_account";
                    },
                   },


                   ppp_account =>
                   {
                    name => N("Dialup: account options"),
                    data => sub {
                            [
                             { label => N("Connection name"), val => \$modem->{connection} },
                             { label => N("Phone number"), val => \$modem->{phone} },
                             { label => N("Login ID"), val => \$modem->{login} },
                             { label => N("Password"), val => \$modem->{passwd}, hidden => 1 },
                             { label => N("Authentication"), val => \$modem->{Authentication},
                               list => [ sort keys %ppp_auth_methods ], format => sub { $ppp_auth_methods{$_[0]} } },
                            ];
                        },
                    next => "ppp_ip",
                   },


                   ppp_ip =>
                   {
                    pre => sub {
                        $modem_dyn_ip = sub { $modem->{auto_ip} eq N("Automatic") };
                    },
                    name => N("Dialup: IP parameters"),
                    data => sub {
                        [
                         { label => N("IP parameters"), type => "list", val => \$modem->{auto_ip}, list => [ N("Automatic"), N("Manual") ] },
                         { label => N("IP address"), val => \$modem->{IPAddr}, disabled => $modem_dyn_ip },
                         { label => N("Subnet mask"), val => \$modem->{SubnetMask}, disabled => $modem_dyn_ip },
                        ];
                    },
                    next => "ppp_dns",
                   },


                   ppp_dns =>
                   {
                    pre => sub {
                        $modem_dyn_dns = sub { $modem->{auto_dns} eq N("Automatic") };
                    },
                    name => N("Dialup: DNS parameters"),
                    data => sub {
                        [
                         { label => N("DNS"), type => "list", val => \$modem->{auto_dns}, list => [ N("Automatic"), N("Manual") ] },
                         { label => N("Domain name"), val => \$modem->{domain}, disabled => $modem_dyn_dns },
                         { label => N("First DNS Server (optional)"), val => \$modem->{dns1}, disabled => $modem_dyn_dns },
                         { label => N("Second DNS Server (optional)"), val => \$modem->{dns2}, disabled => $modem_dyn_dns },
                         { text => N("Set hostname from IP"), val => \$modem->{AutoName}, type => 'bool', disabled => $modem_dyn_dns },
                        ];
                    },
                    next => "ppp_gateway",
                   },


                   ppp_gateway =>
                   {
                    name => N("Dialup: IP parameters"),
                    data => sub {
                        [
                         { label => N("Gateway"), type => "list", val => \$modem->{auto_gateway}, list => [ N("Automatic"), N("Manual") ] },
                         { label => N("Gateway IP address"), val => \$modem->{Gateway},
                           disabled => sub { $modem->{auto_gateway} eq N("Automatic") } },
                        ];
                        },
                    post => sub {
                        network::modem::ppp_configure($in, $modem);
                        $net->{net_interface} = 'ppp0';
                        "allow_user_ctl";
                    },
                   },


                   adsl =>
                   {
                    pre => sub {
                        $lan_detect->();
                        @adsl_devices = keys %eth_intf;

                        detect($modules_conf, $net->{autodetect}, 'adsl');
                        %adsl_cards = ();
                        foreach my $modem_type (keys %{$net->{autodetect}{adsl}}) {
                            foreach my $modem (@{$net->{autodetect}{adsl}{$modem_type}}) {
                                my $name = join(': ', $adsl_descriptions{$modem_type}, $modem->{description});
                                $adsl_cards{$name} = [ $modem_type, $modem ];
                            }
                        }
                        push @adsl_devices, keys %adsl_cards;

                        detect($modules_conf, $net->{autodetect}, 'isdn');
                        if (my @isdn_modems = @{$net->{autodetect}{isdn}}) {
                            require network::isdn;
                            %isdn_cards = map { $_->{description} => $_ } grep { $_->{driver} =~ /dsl/i } map { network::isdn::get_capi_card($in, $_) } @isdn_modems;
                            push @adsl_devices, keys %isdn_cards;
                        }
                    },
                    name => N("ADSL configuration") . "\n\n" . N("Select the network interface to configure:"),
                    data =>  [ { label => N("Net Device"), type => "list", val => \$ntf_name, allow_empty_list => 1,
                               list => \@adsl_devices, format => sub { $eth_intf{$_[0]} || $_[0] } } ],
		    complete => sub {
			exists $adsl_cards{$ntf_name} && !network::thirdparty::setup_device($in, 'dsl', $adsl_cards{$ntf_name}[0]);
		    },
                    post => sub {
                        if (exists $adsl_cards{$ntf_name}) {
                            my $modem;
                            ($ntf_name, $modem) = @{$adsl_cards{$ntf_name}};
                            $net->{adsl}{bus} = $modem->{bus} if $ntf_name eq 'bewan';
                        }
                        if (exists($isdn_cards{$ntf_name})) {
                            require network::isdn;
                            $net->{adsl}{capi_card} = $isdn_cards{$ntf_name};
                            $net->{adsl}{method} = "capi";
                            return 'adsl_account';
                        }
                        return 'adsl_provider';
                    },
                   },


                   adsl_provider =>
                   {
                    pre => sub {
                        require network::adsl_consts;
                        %adsl_data = %network::adsl_consts::adsl_data;
                        $adsl_old_provider = $adsl_provider;
                    },
                    name => N("Please choose your ADSL provider"),
                    data => sub {
                        [ { label => N("Provider:"), type => "list", val => \$adsl_provider, separator => '|',
                            list => [ sort(N("Unlisted - edit manually"), keys %adsl_data) ], sort => 0 } ];
                    },
                    post => sub {
                        $net->{adsl}{method} = 'pppoa' if member($ntf_name, qw(bewan speedtouch));
                        if ($adsl_provider ne N("Unlisted - edit manually")) {
                            $adsl_data = $adsl_data{$adsl_provider};
                            if ($adsl_provider ne $adsl_old_provider) {
                                $net->{adsl}{$_} = $adsl_data->{$_} foreach qw(Encapsulation vpi vci provider_id method);
				$net->{resolv}{$_} = $adsl_data->{$_} foreach qw(DOMAINNAME2);
                            }
                        }
                        return 'adsl_protocol';
                    },
                   },


                   adsl_protocol =>
                   {
                    pre => sub {
                        # preselect right protocol for ethernet though connections:
                        if (!exists $adsl_descriptions{$ntf_name}) {
                            $ethntf = $net->{ifcfg}{$ntf_name} ||= { DEVICE => $ntf_name };
                            $net->{adsl}{method} ||= $ethntf->{BOOTPROTO} || "dhcp";
                            #- pppoa shouldn't be selected by default for ethernet devices, fallback on pppoe
                            $net->{adsl}{method} = "pppoe" if $net->{adsl}{method} eq "pppoa";
                        }
                    },
                    name => N("Connect to the Internet") . "\n\n" .
                    N("The most common way to connect with adsl is pppoe.
Some connections use PPTP, a few use DHCP.
If you do not know, choose 'use PPPoE'"),
                    data =>  [
                              { text => N("ADSL connection type:"), val => \$net->{adsl}{method}, type => "list",
                                list => [ sort { $adsl_types{$a} cmp $adsl_types{$b} } keys %adsl_types ],
                                format => sub { $adsl_types{$_[0]} },
                              },
                             ],
                    post => sub {
                        my $real_interface = $ntf_name;
                        $net->{type} = 'adsl';
                        # blacklist bogus driver, enable ifplugd support else:
                        $find_lan_module->();
                        $ethntf->{MII_NOT_SUPPORTED} ||= $is_ifplugd_blacklisted->();
                        if ($ntf_name eq "sagem"  && member($net->{adsl}{method}, qw(static dhcp))) {
                            #- "fctStartAdsl -i" builds ifcfg-ethX from ifcfg-sagem and echoes ethX
                            #- it auto-detects dhcp/static modes thanks to encapsulation setting
                            $ethntf = $net->{ifcfg}{sagem} ||= {};
                            $ethntf->{DEVICE} = "`/usr/sbin/fctStartAdsl -i`";
                            $ethntf->{MII_NOT_SUPPORTED} = "yes";
                        }
                        if ($ntf_name eq "speedtouch"  && member($net->{adsl}{method}, qw(static dhcp))) {
                            #- use ATMARP with the atm0 interface
                            $real_interface = "atm0";
                            $ethntf = $net->{ifcfg}{$real_interface} ||= {};
                            $ethntf->{DEVICE} = $real_interface;
                            $ethntf->{ATM_ADDR} = undef;
                            $ethntf->{MII_NOT_SUPPORTED} = "yes";
                        }
                        #- delete gateway settings if gateway device is invalid or if reconfiguring the gateway interface
                        exists $net->{ifcfg}{$real_interface} and $delete_gateway_settings->($real_interface);
                        # process static/dhcp ethernet devices:
                        if (exists($net->{ifcfg}{$real_interface}) && member($net->{adsl}{method}, qw(static dhcp))) {
                            $ethntf->{TYPE} = "ADSL";
                            $auto_ip = $net->{adsl}{method} eq 'dhcp';
                            return 'lan_intf';
                        }
                        return 'adsl_account';
                    },
                   },


                   adsl_account =>
                   {
                    pre => sub {
                        network::adsl::adsl_probe_info($net);
                        member($net->{adsl}{method}, qw(pppoe pptp)) and $net->{adsl}{ethernet_device} = $ntf_name;
                        $net->{net_interface} = 'ppp0';
                        ($adsl_vpi, $adsl_vci) = (hex($net->{adsl}{vpi}), hex($net->{adsl}{vci}));
                    },
                    name => N("Connection Configuration") . "\n\n" .
                    N("Please fill or check the field below"),
                    data => sub {
                        [ 
                         if_(0, { label => N("Provider name (ex provider.net)"), val => \$net->{resolv}{DOMAINNAME2} }),
                         { label => N("First DNS Server (optional)"), val => \$net->{resolv}{dnsServer2} },
                         { label => N("Second DNS Server (optional)"), val => \$net->{resolv}{dnsServer3} },
                         { label => N("Account Login (user name)"), val => \$net->{adsl}{login} },
                         { label => N("Account Password"),  val => \$net->{adsl}{passwd}, hidden => 1 },
                         if_($net->{adsl}{method} ne "capi",
                             { label => N("Virtual Path ID (VPI):"), val => \$adsl_vpi, advanced => 1 },
                             { label => N("Virtual Circuit ID (VCI):"), val => \$adsl_vci, advanced => 1 }
                            ),
                         if_($ntf_name eq "sagem",
                             { label => N("Encapsulation:"), val => \$net->{adsl}{Encapsulation}, list => [ keys %encapsulations ],
                               format => sub { $encapsulations{$_[0]} }, advanced => 1,
                             },
                            ),
                        ];
                    },
                    post => sub {
                        #- update ATM_ADDR for ATMARP connections
                        exists $ethntf->{ATM_ADDR} and $ethntf->{ATM_ADDR} = join('.', $adsl_vpi, $adsl_vci);
                        #- convert VPI/VCI back to hex
                        ($net->{adsl}{vpi}, $net->{adsl}{vci}) = map { sprintf("%x", $_) } ($adsl_vpi, $adsl_vci);

			$net->{adsl}{device} =
			  $net->{adsl}{method} eq 'pptp' ? 'pptp_modem' :
			  $net->{adsl}{method} eq 'capi' ? 'capi_modem' :
			  $ntf_name;
                        network::adsl::adsl_conf_backend($in, $modules_conf, $net);
                        "allow_user_ctl";
                    },
                   },


                   lan =>
                   {
                    pre => $lan_detect,
                    name => N("Select the network interface to configure:"),
                    data =>  sub {
                        [ { label => N("Net Device"), type => "list", val => \$ntf_name, list => [ (sort keys %eth_intf), N_("Manually load a driver"), if_($is_wireless, N_("Use a Windows driver (with ndiswrapper)")) ], 
                            allow_empty_list => 1, format => sub { translate($eth_intf{$_[0]} || $_[0]) } } ];
                    },
                    complete => sub {
                        if ($ntf_name eq "Use a Windows driver (with ndiswrapper)") {
                            require network::ndiswrapper;
                            unless ($in->do_pkgs->ensure_is_installed('ndiswrapper', '/usr/sbin/ndiswrapper')) {
                                $in->ask_warn(N("Error"), N("Could not install the %s package!", 'ndiswrapper'));
                                return 1;
                            }
                            undef $ndiswrapper_driver;
                            undef $ndiswrapper_device;
                            unless (network::ndiswrapper::installed_drivers()) {
                                $ndiswrapper_driver = network::ndiswrapper::ask_driver($in) or return 1;
                                return !$ndiswrapper_do_driver_selection->();
                            }
                        }
                        0;
                    },
                    post => sub {
                        if ($ntf_name eq "Manually load a driver") {
			    require modules::interactive;
                            modules::interactive::load_category__prompt($in, $modules_conf, list_modules::ethernet_categories());
                            return 'lan';
                        } elsif ($ntf_name eq "Use a Windows driver (with ndiswrapper)") {
                            return $ndiswrapper_next_step->();
                        }
                        $ethntf = $net->{ifcfg}{$ntf_name} ||= { DEVICE => $ntf_name };
                        return $after_lan_intf_selection->();
                    },
                   },


                   lan_protocol =>
                   {
                    pre => sub  {
                        $find_lan_module->();
                        my $intf_type = member($module, list_modules::category2modules('network/gigabit')) ? "ethernet_gigabit" : "ethernet";
                        defined($ethntf->{METRIC}) or $ethntf->{METRIC} = network::tools::get_default_metric($intf_type);

                        $protocol = $l10n_lan_protocols{defined $auto_ip ? ($auto_ip ? 'dhcp' : 'static') : $ethntf->{BOOTPROTO}} || 0;
                    },
                    name => sub { 
                        my $_msg = N("Zeroconf hostname resolution");
                        N("Configuring network device %s (driver %s)", $ethntf->{DEVICE}, $module) . "\n\n" .
                          N("The following protocols can be used to configure a LAN connection. Please choose the one you want to use");
                    },
                    data => sub {
                        [ { val => \$protocol, type => "list", list => [ sort values %l10n_lan_protocols ] } ];
                    },
                    post => sub {
                        $auto_ip = $protocol ne $l10n_lan_protocols{static} || 0;
                        return 'lan_intf';
                    },
                   },


                   lan_intf =>
                   {
                    pre => sub  {
                        $onboot = $ethntf->{ONBOOT} ? $ethntf->{ONBOOT} =~ /yes/ : bool2yesno(!member($ethntf->{DEVICE},
                                                                                                      map { $_->{device} } detect_devices::pcmcia_probe()));
                        $needhostname = $ethntf->{NEEDHOSTNAME} !~ /no/;
                        $peerdns = $ethntf->{PEERDNS} !~ /no/;
                        $peeryp = $ethntf->{PEERYP} =~ /yes/;
                        $peerntpd = $ethntf->{PEERNTPD} =~ /yes/;
                        # blacklist bogus driver, enable ifplugd support else:
                        $ethntf->{MII_NOT_SUPPORTED} ||= $is_ifplugd_blacklisted->();
                        $ifplugd = !text2bool($ethntf->{MII_NOT_SUPPORTED});
                        $track_network_id = $::isStandalone && $ethntf->{HWADDR} || detect_devices::isLaptop();
                        delete $ethntf->{TYPE} if $net->{type} ne 'adsl' || !member($net->{adsl}{method}, qw(static dhcp));
                        $ethntf->{DHCP_CLIENT} ||= (find { -x "$::prefix/sbin/$_" } qw(dhclient dhcpcd pump dhcpxd));
                    },
                    name => sub { join('', 
                                       N("Configuring network device %s (driver %s)", $ethntf->{DEVICE}, $module),
                                       if_(!$auto_ip, "\n\n" . N("Please enter the IP configuration for this machine.
Each item should be entered as an IP address in dotted-decimal
notation (for example, 1.2.3.4).")),
                                      )  },
                    data => sub {
                        [ $auto_ip ? 
                          (
                           { text => N("Assign host name from DHCP address"), val => \$needhostname, type => "bool" },
                           { label => N("DHCP host name"), val => \$ethntf->{DHCP_HOSTNAME} },
                          )
                          :
                          (
                           { label => N("IP address"), val => \$ethntf->{IPADDR}, disabled => sub { $auto_ip } },
                           { label => N("Netmask"), val => \$ethntf->{NETMASK}, disabled => sub { $auto_ip } },
                          ),
                          { text => N("Track network card id (useful for laptops)"), val => \$track_network_id, type => "bool" },
                          if_(!$is_wireless,
                              { text => N("Network Hotplugging"), val => \$ifplugd, type => "bool" }),
                          if_($net->{type} eq "lan",
                              { text => N("Start at boot"), val => \$onboot, type => "bool" },
                             ),
                          { label => N("Metric"), val => \$ethntf->{METRIC}, advanced => 1 },
                          if_($auto_ip,
                              { label => N("DHCP client"), val => \$ethntf->{DHCP_CLIENT},
                                list => \@network::ethernet::dhcp_clients, advanced => 1 },
                              { label => N("DHCP timeout (in seconds)"), val => \$ethntf->{DHCP_TIMEOUT}, advanced => 1 },
                              { text => N("Get DNS servers from DHCP"), val => \$peerdns, type => "bool", advanced => 1 },
                              { text => N("Get YP servers from DHCP"), val => \$peeryp, type => "bool", advanced => 1 },
                              { text => N("Get NTPD servers from DHCP"), val => \$peerntpd, type => "bool", advanced => 1 },
                             ),
                        ];
                    },
                    complete => sub {
                        $ethntf->{BOOTPROTO} = $auto_ip ? "dhcp" : "static";
                        return 0 if $auto_ip;
                        if (!is_ip($ethntf->{IPADDR})) {
                            $in->ask_warn(N("Error"), N("IP address should be in format 1.2.3.4"));
                            return 1, 0;
                        }
                        if (!is_ip($ethntf->{NETMASK})) {
                            $in->ask_warn(N("Error"), N("Netmask should be in format 255.255.224.0"));
                            return 1, 1;
                        }
                        if (is_ip_forbidden($ethntf->{IPADDR})) {
                          $in->ask_warn(N("Error"), N("Warning: IP address %s is usually reserved!", $ethntf->{IPADDR}));
                          return 1, 0;
                        }
                        #- test if IP address is already used (do not test for sagem DSL devices since it may use many ifcfg files)
                        if ($ntf_name ne "sagem" && find { $_->{DEVICE} ne $ethntf->{DEVICE} && $_->{IPADDR} eq $ethntf->{IPADDR} } values %{$net->{ifcfg}}) {
                          $in->ask_warn(N("Error"), N("%s already in use\n", $ethntf->{IPADDR}));
                          return 1, 0;
                        }
                    },
                    focus_out => sub {
                        $ethntf->{NETMASK} ||= netmask($ethntf->{IPADDR}) unless $ethntf->{NETMASK};
                    },
                    post => sub {
                        $ethntf->{ONBOOT} = bool2yesno($onboot);
                        $ethntf->{NEEDHOSTNAME} = bool2yesno($needhostname);
                        $ethntf->{PEERDNS} = bool2yesno($peerdns);
                        $ethntf->{PEERYP} = bool2yesno($peeryp);
                        $ethntf->{PEERNTPD} = bool2yesno($peerntpd);
                        $ethntf->{MII_NOT_SUPPORTED} = bool2yesno(!$ifplugd);
                        $ethntf->{HWADDR} = $track_network_id or delete $ethntf->{HWADDR};
                        #- FIXME: special case for sagem where $ethntf->{DEVICE} is the result of a command
                        #- we can't always use $ntf_name because of some USB DSL modems
                        $net->{net_interface} = $ntf_name eq "sagem" ? "sagem" : $ethntf->{DEVICE};
                        if ($auto_ip) {
                            #- delete gateway settings if gateway device is invalid or if reconfiguring the gateway interface to dhcp
                            $delete_gateway_settings->($ntf_name);
                        }
                        return "static_hostname";
                    },
                   },

                   ndiswrapper_select_driver =>
                   {
                    pre => sub {
                        @ndiswrapper_drivers = network::ndiswrapper::installed_drivers();
                        $ndiswrapper_driver ||= first(@ndiswrapper_drivers);
                    },
                    data => sub {
                        [ { label => N("Choose an ndiswrapper driver"), type => "list", val => \$ndiswrapper_driver, allow_empty_list => 1,
                            list => [ undef, @ndiswrapper_drivers ],
                            format => sub { defined $_[0] ? N("Use the ndiswrapper driver %s", $_[0]) : N("Install a new driver") } } ];
                    },
                    complete => sub {
                        $ndiswrapper_driver ||= network::ndiswrapper::ask_driver($in) or return 1;
                        !$ndiswrapper_do_driver_selection->();
                    },
                    post => $ndiswrapper_next_step,
                   },

                   ndiswrapper_select_device =>
                   {
                    data => sub {
                        [ { label => N("Select a device:"), type => "list", val => \$ndiswrapper_device, allow_empty_list => 1,
                            list => [ network::ndiswrapper::present_devices($ndiswrapper_driver) ],
                            format => sub { $_[0]{description} } } ];
                    },
                    complete => sub {
                        !$ndiswrapper_do_device_selection->();
                    },
                    post => $ndiswrapper_next_step,
                   },

                   wireless =>
                   {
                    pre => sub {
                        require network::wireless;
                        $ethntf->{WIRELESS_MODE} ||= "Managed";
                        $ethntf->{WIRELESS_ESSID} ||= "any";
                        ($wireless_enc_key, my $restricted) = network::wireless::get_wep_key_from_iwconfig($ethntf->{WIRELESS_ENC_KEY});
                        $wireless_enc_mode =
                          $ethntf->{WIRELESS_WPA_DRIVER} || $ethntf->{WIRELESS_IWPRIV} =~ /WPAPSK/ ? 'wpa-psk' :
                          !$wireless_enc_key ? 'none' :
                          $restricted ? 'restricted' :
                          'open';
                        $find_lan_module->();
                        $need_rt2x00_iwpriv = member($module, "rt2400", "rt2500");
                    },
                    name => N("Please enter the wireless parameters for this card:"),
                    data => sub {
                            [
                             { label => N("Operating Mode"), val => \$ethntf->{WIRELESS_MODE},
                               list => [ N_("Ad-hoc"), N_("Managed"), N_("Master"), N_("Repeater"), N_("Secondary"), N_("Auto") ],
                               format => \&translate },
                             { label => N("Network name (ESSID)"), val => \$ethntf->{WIRELESS_ESSID} },
                             { label => N("Network ID"), val => \$ethntf->{WIRELESS_NWID}, advanced => 1 },
                             { label => N("Operating frequency"), val => \$ethntf->{WIRELESS_FREQ}, advanced => 1 },
                             { label => N("Sensitivity threshold"), val => \$ethntf->{WIRELESS_SENS}, advanced => 1 },
                             { label => N("Bitrate (in b/s)"), val => \$ethntf->{WIRELESS_RATE}, advanced => 1 },
                             { label => N("Encryption mode"), val => \$wireless_enc_mode,
                               list => [ sort { $wireless_enc_modes{$a} cmp $wireless_enc_modes{$b} } keys %wireless_enc_modes ],
                               format => sub { $wireless_enc_modes{$_[0]} } },
                             { label => N("Encryption key"), val => \$wireless_enc_key, disabled => sub { $wireless_enc_mode eq 'none' } },
                             { label => N("RTS/CTS"), val => \$ethntf->{WIRELESS_RTS}, advanced => 1,
                               help => N("RTS/CTS adds a handshake before each packet transmission to make sure that the
channel is clear. This adds overhead, but increase performance in case of hidden
nodes or large number of active nodes. This parameter sets the size of the
smallest packet for which the node sends RTS, a value equal to the maximum
packet size disable the scheme. You may also set this parameter to auto, fixed
or off.")
                             },
                             { label => N("Fragmentation"), val => \$ethntf->{WIRELESS_FRAG}, advanced => 1 },
                             { label => N("Iwconfig command extra arguments"), val => \$ethntf->{WIRELESS_IWCONFIG}, advanced => 1,
                               help => N("Here, one can configure some extra wireless parameters such as:
ap, channel, commit, enc, power, retry, sens, txpower (nick is already set as the hostname).

See iwconfig(8) man page for further information."),
                             },
                             { label =>
                               #-PO: split the "xyz command extra argument" translated string into two lines if it's bigger than the english one
                               N("Iwspy command extra arguments"), val => \$ethntf->{WIRELESS_IWSPY}, advanced => 1,
                               help => N("Iwspy is used to set a list of addresses in a wireless network
interface and to read back quality of link information for each of those.

This information is the same as the one available in /proc/net/wireless :
quality of the link, signal strength and noise level.

See iwpspy(8) man page for further information."),
 },
                             if_(!$need_rt2x00_iwpriv,
                                 { label => N("Iwpriv command extra arguments"), val => \$ethntf->{WIRELESS_IWPRIV}, advanced => 1,
                                   help => N("Iwpriv enable to set up optionals (private) parameters of a wireless network
interface.

Iwpriv deals with parameters and setting specific to each driver (as opposed to
iwconfig which deals with generic ones).

In theory, the documentation of each device driver should indicate how to use
those interface specific commands and their effect.

See iwpriv(8) man page for further information."),
                                 })
                            ];
                    },
                    complete => sub {
                        if ($ethntf->{WIRELESS_FREQ} && $ethntf->{WIRELESS_FREQ} !~ /[0-9.]*[kGM]/) {
                            $in->ask_warn(N("Error"), N("Freq should have the suffix k, M or G (for example, \"2.46G\" for 2.46 GHz frequency), or add enough '0' (zeroes)."));
                            return 1, 6;
                        }
                        if ($ethntf->{WIRELESS_RATE} && $ethntf->{WIRELESS_RATE} !~ /[0-9.]*[kGM]/) {
                            $in->ask_warn(N("Error"), N("Rate should have the suffix k, M or G (for example, \"11M\" for 11M), or add enough '0' (zeroes)."));
                            return 1, 8;
                        }
                        if (network::wireless::wlan_ng_needed($module) && !$in->do_pkgs->ensure_is_installed('prism2-utils', '/sbin/wlanctl-ng')) {
                            $in->ask_warn(N("Error"), N("Could not install the %s package!", 'prism2-utils'));
                            return 1;
                        }
                        if ($wireless_enc_mode eq 'wpa-psk' && !$need_rt2x00_iwpriv && !$in->do_pkgs->ensure_is_installed('wpa_supplicant', '/usr/sbin/wpa_supplicant')) {
                            $in->ask_warn(N("Error"), N("Could not install the %s package!", 'wpa_supplicant'));
                            return 1;
                        }
			!network::thirdparty::setup_device($in, 'wireless', $module);
                    },
                    post => sub {
                        delete $ethntf->{WIRELESS_ENC_KEY};
                        delete $ethntf->{WIRELESS_WPA_DRIVER};
                        if ($wireless_enc_mode ne 'none') {
                            #- keep the key even for WPA, so that drakconnect remembers it
                            $ethntf->{WIRELESS_ENC_KEY} = network::wireless::convert_wep_key_for_iwconfig($wireless_enc_key, $wireless_enc_mode eq 'restricted');
                        }
                        if ($need_rt2x00_iwpriv) {
                            #- use iwpriv for WPA with rt2x00 drivers, they don't plan to support wpa_supplicant
                            $ethntf->{WIRELESS_IWPRIV} = $wireless_enc_mode eq 'wpa-psk' && qq(set AuthMode=WPAPSK
set EncrypType=TKIP
set WPAPSK="$wireless_enc_key"
set TxRate=0);
                        } else {
                            if ($wireless_enc_mode eq 'wpa-psk') {
                                $ethntf->{WIRELESS_WPA_DRIVER} = network::wireless::wpa_supplicant_get_driver($module);
                                network::wireless::wpa_supplicant_add_network_simple($ethntf->{WIRELESS_ESSID}, $wireless_enc_key);
                            }
                        }
                        network::wireless::wlan_ng_needed($module) and network::wireless::wlan_ng_configure($ethntf->{WIRELESS_ESSID}, $wireless_enc_key, $ethntf->{DEVICE}, $module);
                        return "lan_protocol";
                    },
                   },


		   dvb =>
		   {
                    name => N("DVB configuration") . "\n\n" . N("Select the network interface to configure:"),
                    data => [ { label => N("DVB Adapter"), type => "list", val => \$dvb_adapter, allow_empty_list => 1,
				list => [ modules::probe_category("multimedia/dvb") ], format => sub { $_[0]{description} } } ],
                    next => "dvb_adapter",
		   },


		   dvb_adapter =>
		   {
		    pre => sub {
			my $previous_ethntf = find { $is_dvb_interface->($_) } values %{$net->{ifcfg}};
			$dvb_ad = $previous_ethntf->{DVB_ADAPTER_ID};
			$dvb_net = $previous_ethntf->{DVB_NETWORK_DEMUX};
			$dvb_pid = $previous_ethntf->{DVB_NETWORK_PID};
			if (my $device = find { sysopen(undef, $_, c::O_RDWR() | c::O_NONBLOCK()) } glob("/dev/dvb/adapter*/net*")) {
			    ($dvb_ad, $dvb_net) = $device =~ m,/dev/dvb/adapter(\d+)/net(\d+),;
			}
		    },
		    name => N("DVB adapter settings"),
		    data => sub {
                            [
			     { label => N("Adapter card"), val => \$dvb_ad },
                             { label => N("Net demux"), val => \$dvb_net },
                             { label => N("PID"), val => \$dvb_pid },
			    ];
			},
		    post => sub {
			$ntf_name = 'dvb' . $dvb_ad . '_' . $dvb_net;
			$ethntf = $net->{ifcfg}{$ntf_name} ||= {};
			$ethntf->{DEVICE} = $ntf_name;
			$ethntf->{DVB_ADAPTER_ID} = qq("$dvb_ad");
			$ethntf->{DVB_NETWORK_DEMUX} = qq("$dvb_net");
			$ethntf->{DVB_NETWORK_PID} = qq("$dvb_pid");
			return "lan_protocol";
		    },
		   },

                   static_hostname =>
                   {
                    pre => sub {
                        if ($ethntf->{IPADDR}) {
                            $net->{resolv}{dnsServer} ||= dns($ethntf->{IPADDR});
                            $gateway_ex = gateway($ethntf->{IPADDR});
                            # $net->{network}{GATEWAY} ||= gateway($ethntf->{IPADDR});
                            if ($ntf_name eq "sagem") {
                              my @sagem_ip = split(/\./, $ethntf->{IPADDR});
                              $sagem_ip[3] = 254;
                              $net->{network}{GATEWAY} = join(".", @sagem_ip);
                            }
                        }
                    },
                    name => N("Please enter your host name.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''.
You may also enter the IP address of the gateway if you have one.") .
 " " . # better looking text (to be merged into texts since some languages (eg: ja) doesn't need it
N("Last but not least you can also type in your DNS server IP addresses."),
                    data => sub {
                        [ { label => $auto_ip ? N("Host name (optional)") : N("Host name"), val => \$net->{network}{HOSTNAME} },
                          if_(!$auto_ip, 
                              { label => N("DNS server 1"),  val => \$net->{resolv}{dnsServer} },
                              { label => N("DNS server 2"),  val => \$net->{resolv}{dnsServer2} },
                              { label => N("DNS server 3"),  val => \$net->{resolv}{dnsServer3} },
                              { label => N("Search domain"), val => \$net->{resolv}{DOMAINNAME}, 
                                help => N("By default search domain will be set from the fully-qualified host name") },
                              { label => N("Gateway (e.g. %s)", $gateway_ex), val => \$net->{network}{GATEWAY} },
                              if_(@all_cards > 1,
                                  { label => N("Gateway device"), val => \$net->{network}{GATEWAYDEV}, list => [ N_("None"), sort keys %all_eth_intf ],
                                    format => sub { $all_eth_intf{$_[0]} || translate($_[0]) } },
                                 ),
                             ),
                        ];
                    },
                    complete => sub {
                        foreach my $dns (qw(dnsServer dnsServer2 dnsServer3)) {
                            if ($net->{resolv}{$dns} && !is_ip($net->{resolv}{$dns})) {
                                $in->ask_warn(N("Error"), N("DNS server address should be in format 1.2.3.4"));
                                return 1;
                            }
                        }
                        if ($net->{network}{GATEWAY} && !is_ip($net->{network}{GATEWAY})) {
                            $in->ask_warn(N("Error"), N("Gateway address should be in format 1.2.3.4"));
                            return 1;
                        }
                    },
                    post => sub {
                        $net->{network}{GATEWAYDEV} eq "None" and delete $net->{network}{GATEWAYDEV};
                        return "zeroconf";
                    }
                   },


                   zeroconf =>
                   {
                    name => N("If desired, enter a Zeroconf hostname.
This is the name your machine will use to advertise any of
its shared resources that are not managed by the network.
It is not necessary on most networks."),
                    data => [ { label => N("Zeroconf Host name"), val => \$net->{zeroconf}{hostname} } ],
                    complete => sub {
                        if ($net->{zeroconf}{hostname} =~ /\./) {
                            $in->ask_warn(N("Error"), N("Zeroconf host name must not contain a ."));
                            return 1;
                        }
                    },
                    next => "allow_user_ctl",
                   },


                   allow_user_ctl =>
                   {
                    name => N("Do you want to allow users to start the connection?"),
                    type => "yesorno",
                    default => sub { bool2yesno(text2bool($net->{ifcfg}{$net->{net_interface}}{USERCTL})) },
                    post => sub {
                        my ($res) = @_;
                        $net->{ifcfg}{$net->{net_interface}}{USERCTL} = bool2yesno($res);
                        return $goto_start_on_boot_ifneeded->();
                    },
                   },


                   network_on_boot =>
                   {
                    name => N("Do you want to start the connection at boot?"),
                    type => "yesorno",
                    default => sub { ($net->{type} eq 'modem' ? 'no' : 'yes') },
                    post => sub {
                        my ($res) = @_;
			$net->{ifcfg}{$net->{net_interface}}{ONBOOT} = bool2yesno($res);
                        return $after_start_on_boot_step->();
                    },
                   },


                   isdn_dial_on_boot =>
                   {
                    pre => sub {
                        $net->{ifcfg}{ippp0} ||= { DEVICE => "ippp0" }; # we want the ifcfg-ippp0 file to be written
                        @isdn_dial_methods = ({ name => N("Automatically at boot"),
                                                ONBOOT => 1, DIAL_ON_IFUP => 1 },
                                              { name => N("By using Net Applet in the system tray"),
                                                ONBOOT => 0, DIAL_ON_IFUP => 1 },
                                              { name => N("Manually (the interface would still be activated at boot)"),
                                               ONBOOT => 1, DIAL_ON_IFUP => 0 });
                        my $method =  find {
                            $_->{ONBOOT} eq text2bool($net->{ifcfg}{ippp0}{ONBOOT}) &&
                              $_->{DIAL_ON_IFUP} eq text2bool($net->{ifcfg}{ippp0}{DIAL_ON_IFUP});
                        } @isdn_dial_methods;
                        #- use net_applet by default
                        $isdn->{dial_method} = $method->{name} || $isdn_dial_methods[1]{name};
                    },
                    name => N("How do you want to dial this connection?"),
                    data => sub {
                        [ { type => "list", val => \$isdn->{dial_method}, list => [ map { $_->{name} } @isdn_dial_methods ] } ];
                    },
                    post => sub {
                        my $method = find { $_->{name} eq $isdn->{dial_method} } @isdn_dial_methods;
                        $net->{ifcfg}{ippp0}{$_} = bool2yesno($method->{$_}) foreach qw(ONBOOT DIAL_ON_IFUP);
                        return $after_start_on_boot_step->();
                    },
                   },

                   ask_connect_now =>
                   {
                    name => N("Do you want to try to connect to the Internet now?"),
                    type => "yesorno",
                    post => sub {
                        my ($a) = @_;
                        my $type = $net->{type};
                        $up = 1;
                        if ($a) {
                            # local $::isWizard = 0;
                            my $_w = $in->wait_message('', N("Testing your connection..."), 1);
                            network::tools::stop_net_interface($net, 0);
                            sleep 1;
                            network::tools::start_net_interface($net, 1);
                            my $s = 30;
                            $type =~ /modem/ and $s = 50;
                            $type =~ /adsl/ and $s = 35;
                            $type =~ /isdn/ and $s = 20;
                            sleep $s;
                            $up = network::tools::connected();
                        }
                        $success = $up;
                        return $a ? "disconnect" : "end";
                    }
                   },


                   disconnect =>
                   {
                    name => sub {
                        $up ? N("The system is now connected to the Internet.") .
                          if_($::isInstall, N("For security reasons, it will be disconnected now.")) :
                            N("The system does not seem to be connected to the Internet.
Try to reconfigure your connection.");
                    },
                    no_back => 1,
                    end => 1,
                    post => sub {
                        $::isInstall and network::tools::stop_net_interface($net, 0);
                        return "end";
                    },
                   },


                   end =>
                   {
                    name => sub {
                        return $success ? join('', N("Congratulations, the network and Internet configuration is finished.

"), if_($::isStandalone && $in->isa('interactive::gtk'),
        N("After this is done, we recommend that you restart your X environment to avoid any hostname-related problems."))) :
          N("Problems occurred during configuration.
Test your connection via net_monitor or mcc. If your connection does not work, you might want to relaunch the configuration.");
                    },
                           end => 1,
                   },
                  },
        };

      #- keeping the translations in case someone want to restore these texts
      if_(0,
	  # keep b/c of translations in case they can be reused somewhere else:
	  N("(detected on port %s)", 'toto'),
	  #-PO: here, "(detected)" string will be appended to eg "ADSL connection"
	  N("(detected %s)", 'toto'), N("(detected)"),
	  N("Network Configuration"),
	  N("Because you are doing a network installation, your network is already configured.
Click on Ok to keep your configuration, or cancel to reconfigure your Internet & Network connection.
"),
	  N("The network needs to be restarted. Do you want to restart it?"),
	  N("A problem occurred while restarting the network: \n\n%s", 'foo'),
	  N("We are now going to configure the %s connection.\n\n\nPress \"%s\" to continue.", 'a', 'b'),
	  N("Configuration is complete, do you want to apply settings?"),
	  N("You have configured multiple ways to connect to the Internet.\nChoose the one you want to use.\n\n"),
	  N("Internet connection"),
	  );

      require wizards;
      wizards->new->process($wiz, $in);
}

sub safe_main {
    my ($net, $in, $modules_conf) = @_;
    eval { real_main($net, $in, $modules_conf) };
    my $err = $@;
    if ($err) { # && $in->isa('interactive::gtk')
	$err =~ /wizcancel/ and $in->exit(0);

	local $::isEmbedded = 0; # to prevent sub window embedding
        local $::isWizard = 0 if !$::isInstall; # to prevent sub window embedding
        #err_dialog(N("Error"), N("An unexpected error has happened:\n%s", $err));
        $in->ask_warn(N("Error"), N("An unexpected error has happened:\n%s", $err));
    }
}

sub start_internet {
    my ($o) = @_;
    #- give a chance for module to be loaded using kernel-BOOT modules...
    #- FIXME, this has nothing to do there
    $::isStandalone or modules::load_category($o->{modules_conf}, 'network/*');
    network::tools::start_net_interface($o->{net}, 1);
}

sub stop_internet {
    my ($o) = @_;
    network::tools::stop_net_interface($o->{net}, 1);
}

1;

=head1 network::netconnect::detect()

=head2 example of usage

use lib qw(/usr/lib/libDrakX);
use network::netconnect;
use modules;
use Data::Dumper;

my %i;
my $modules_conf = modules::any_conf->read;
network::netconnect::detect($modules_conf, \%i);
print Dumper(\%i),"\n";

=cut
