package network::netconnect; # $Id$

use strict;
use common;
use log;
use detect_devices;
use run_program;
use modules;
use any;
use mouse;
use network::network;
use network::tools;
use MDK::Common::Globals "network", qw($in);

sub detect {
    my ($auto_detect, $o_class) = @_;
    my %l = (
             isdn => sub {
                 require network::isdn;
                 $auto_detect->{isdn} = network::isdn::isdn_detect_backend();
             },
             lan => sub { # ethernet
                 modules::load_category('network/main|gigabit|usb');
                 require network::ethernet;
                 $auto_detect->{lan} = { map { $_->[0] => $_->[1] } network::ethernet::get_eth_cards() };
             },
             adsl => sub {
                 require network::adsl;
                 $auto_detect->{adsl} = network::adsl::adsl_detect();
             },
             modem => sub {
                 $auto_detect->{modem} = { map { ($_->{description} || "$_->{MANUFACTURER}|$_->{DESCRIPTION} ($_->{device})") => $_ } detect_devices::getModem() };
             },
            );
    $l{$_}->() foreach ($o_class || (keys %l));
    return;
}

sub init_globals {
    my ($in) = @_;
    MDK::Common::Globals::init(in => $in);
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
    my %tm_parse = MDK::Common::System::getVarsFromSh('/etc/sysconfig/clock');
    my @country;
    foreach (keys %tmz2country) {
	if ($_ eq $tm_parse{ZONE}) {
	    unshift @country, $tmz2country{$_};
	} else { push @country, $tmz2country{$_} };
    }
    \@country;
}

# load sub category's wizard pages into main wizard data structure
sub get_subwizard {
    my ($wiz, $type) = @_;
    my %net_conf_callbacks = (adsl => sub { require network::adsl; &network::adsl::get_wizard },
                              cable => sub { require network::ethernet; &network::ethernet::get_wizard },
                              isdn => sub { require network::isdn; &network::isdn::get_wizard },
                              lan => sub { require network::ethernet; &network::ethernet::get_wizard },
                              modem => sub { require network::modem; &network::modem::get_wizard },
                             );
    $net_conf_callbacks{$type}->($wiz);
}

# configuring all network devices
sub real_main {
      my ($_prefix, $netcnx, $in, $o_netc, $o_mouse, $o_intf, $o_first_time, $o_noauto) = @_;
      my $netc  = $o_netc  ||= {};
      my $mouse = $o_mouse ||= {};
      my $intf  = $o_intf  ||= {};
      my $first_time = $o_first_time || 0;
      my ($network_configured, $direct_net_install, $cnx_type, $type, $interface, @all_cards, %eth_intf);
      my (%connections, @connection_list, $is_wireless);
      my ($modem, $modem_name, $modem_conf_read, $modem_dyn_dns, $modem_dyn_ip);
      my ($adsl_type, @adsl_devices, $adsl_failed, $adsl_answer, %adsl_data, $adsl_data, $adsl_provider, $adsl_old_provider);
      my ($ntf_name, $ipadr, $netadr, $gateway_ex, $up, $isdn, $isdn_type, $need_restart_network);
      my ($module, $auto_ip, $onboot, $needhostname, $hotplug, $track_network_id, @fields); # lan config
      my $success = 1;
      my $ethntf = {};
      my $db_path = "/usr/share/apps/kppp/Provider";
      my (%countries, @isp, $country, $provider, $old_provider);
      my $config = {};
      eval(cat_('/etc/sysconfig/drakconnect'));

      my %wireless_mode = (N("Ad-hoc") => "Ad-hoc", 
                           N("Managed") => "Managed", 
                           N("Master") => "Master",
                           N("Repeater") => "Repeater",
                           N("Secondary") => "Secondary",
                           N("Auto") => "Auto",
                          );
      my %l10n_lan_protocols = (
                               static => N("Manual configuration"),
                               dhcp   => N("Automatic IP (BOOTP/DHCP)"),
                               if_(0,
                               dhcp_zeroconf   => N("Automatic IP (BOOTP/DHCP/Zeroconf)"),
                                  )
                              );


      init_globals($in);
      $netc->{NET_DEVICE} = $netcnx->{NET_DEVICE} if $netcnx->{NET_DEVICE}; # REDONDANCE with read_conf. FIXME
      $netc->{NET_INTERFACE} = $netcnx->{NET_INTERFACE} if $netcnx->{NET_INTERFACE}; # REDONDANCE with read_conf. FIXME
      network::network::read_all_conf($::prefix, $netc, $intf);

      modules::mergein_conf("$::prefix/etc/modules.conf");

      $netc->{autodetect} = {};


      my $handle_multiple_cnx = sub {
          $need_restart_network = 1 if $netcnx->{type} =~ /lan|cable/;
          my $nb = keys %{$netc->{internet_cnx}};
          if (1 < $nb) {
              return "multiple_internet_cnx";
          } else {
              $netc->{internet_cnx_choice} = (keys %{$netc->{internet_cnx}})[0] if $nb == 1;
              return "network_on_boot";
          }
      };

      my $lan_detect = sub {
          detect($netc->{autodetect}, 'lan');
          modules::interactive::load_category($in, 'network/main|gigabit|pcmcia|usb|wireless', !$::expert, 1);
          @all_cards = network::ethernet::get_eth_cards();
	  %eth_intf = network::ethernet::get_eth_cards_names(@all_cards);
          if ($is_wireless) {
              require list_modules;
              my @wmodules = list_modules::category2modules('network/wireless');
              %eth_intf = map { $_->[0] => join(': ', $_->[0], $_->[2]) } grep { member($_->[1], @wmodules) } @all_cards;
          } else {
              %eth_intf = map { $_->[0] => join(': ', $_->[0], $_->[2]) } @all_cards;
          }
      };

      my $find_lan_module = sub { 
          if (my $dev = find { $_->{device} eq $ethntf->{DEVICE} } detect_devices::pcmcia_probe()) { # PCMCIA case
              $module = $dev->{driver};
          } elsif (my $dev = find { $_->[0] eq $ethntf->{DEVICE} } @all_cards) {
              $module = $dev->[1];
          } else { $module = "" }
      };

      my %adsl_devices = (
                          speedtouch => N("Alcatel speedtouch USB modem"),
                          sagem => N("Sagem USB modem"),
                          bewan_usb => N("Bewan USB modem"),
                          bewan_pci => N("Bewan PCI modem"),
                          eci       => N("ECI Hi-Focus modem"), # this one needs eci agreement
                         );

      my %adsl_types = (
                        dhcp   => N("Dynamic Host Configuration Protocol (DHCP)"),
                        manual => N("Manual TCP/IP configuration"),
                        pptp  => N("Point to Point Tunneling Protocol (PPTP)"),
                        pppoe  => N("PPP over Ethernet (PPPoE)"),
                        pppoa  => N("PPP over ATM (PPPoA)"),
                       );

      my %encapsulations = (
                            1 => N("Bridged Ethernet LLC"), 
                            2 => N("Bridged Ethernet VC"), 
                            3 => N("Routed IP LLC"), 
                            4 => N("Routed IP VC"),
                            5 => N("PPPOA LLC"), 
                            6 => N("PPPOA VC"),
                           );

      my %ppp_auth_methods = (
                              0 => N("Script-based"),
                              1 => N("PAP"),
                              2 => N("Terminal-based"),
                              3 => N("CHAP"),
                              4 => N("PAP/CHAP"),
                             );
      
      my $offer_to_connect = sub {
          return "ask_connect_now" if $netc->{internet_cnx_choice} eq 'adsl' && $adsl_devices{$ntf_name};
          return "ask_connect_now" if member($netc->{internet_cnx_choice}, qw(modem isdn));
          return "end";
      };
    
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
                        # keep b/c of translations in case they can be reused somewhere else:
                        my @_a = (N("(detected on port %s)", 'toto'), 
                          #-PO: here, "(detected)" string will be appended to eg "ADSL connection"
                          N("(detected %s)", 'toto'), N("(detected)"));
                        my @connections = 
                          ([ N("Modem connection"),  "modem" ],
                           [ N("ISDN connection"),   "isdn"  ],
                           [ N("ADSL connection"),   "adsl"  ],
                           [ N("Cable connection"),  "cable" ],
                           [ N("LAN connection"),    "lan"   ],
                           [ N("Wireless connection"), "lan" ],
                          );
                        
                        foreach (@connections) {
                            my ($string, $type) = @$_;
                            $connections{$string} = $type;
                        }
                        @connection_list = ({ val => \$cnx_type, type => 'list', list => [ map { $_->[0] } @connections ], });
                    },
                    if_(!$::isInstall, no_back => 1),
                    name => N("Choose the connection you want to configure"),
                    interactive_help_id => 'configureNetwork',
                    data => \@connection_list,
                    post => sub {
                        $is_wireless = $cnx_type eq N("Wireless connection");
                        load_conf($netcnx, $netc, $intf) if $::isInstall;  # :-(
                        $type = $netcnx->{type} = $connections{$cnx_type};
                        if ($type eq 'cable') {
                            $auto_ip = 1;
                            return "lan";
                        }
                        return $type;
                    },
                   },

                   prepare_detection => 
                   {
                    name => N("We are now going to configure the %s connection.\n\n\nPress \"%s\" to continue.",
                              translate($type), N("Next")),
                    post => $handle_multiple_cnx,
                   },

                 
                   hw_account => 
                   {
                    name => N("Connection Configuration") . "\n\n" .
                    N("Please fill or check the field below"),
                    data => [ 
                             (map {
                                 my ($dstruct, $field, $item) = @$_;
                                 $item->{val} = \$dstruct->{$field};
                                 if__($dstruct->{$field}, $item);
                             } ([ $netcnx, "irq", { label => N("Card IRQ") } ],
                                [ $netcnx, "mem", { label => N("Card mem (DMA)") } ],
                                [ $netcnx, "io",  { label => N("Card IO") } ],
                                [ $netcnx, "io0", { label => N("Card IO_0") } ],
                                [ $netcnx, "io1", { label => N("Card IO_1") } ],
                                [ $netcnx, "phone_in",     { label => N("Your personal phone number") } ],
                                [ $netc,   "DOMAINNAME2",  { label => N("Provider name (ex provider.net)") } ],
                                [ $netcnx, "phone_out",    { label => N("Provider phone number") } ],
                                [ $netc,   "dnsServer2",   { label => N("Provider DNS 1 (optional)") } ],
                                [ $netc,   "dnsServer3",   { label => N("Provider DNS 2 (optional)") } ],
                                [ $netcnx, "dialing_mode", { label => N("Dialing mode"),  list => ["auto", "manual"] } ],
                                [ $netcnx, "speed",        { label => N("Connection speed"), list => ["64 Kb/s", "128 Kb/s"] } ],
                                [ $netcnx, "huptimeout",   { label => N("Connection timeout (in sec)") } ],
                               )
                             ),
                             ({ label => N("Account Login (user name)"), val => \$netcnx->{login} },
                              { label => N("Account Password"),  val => \$netcnx->{passwd}, hidden => 1 },
                             )
                            ],
                    post => sub {
                        $handle_multiple_cnx->();
                    },
                   },
                   
                   
                   go_ethernet => 
                   {
                    pre => sub {
                        conf_network_card($netc, $intf, $type, $ipadr, $netadr) or return;
                        $netc->{NET_INTERFACE} = $netc->{NET_DEVICE};
                        configureNetwork($netc, $intf, $first_time) or return;
                    },
                   },

                   isdn =>
                   {
                    name => N("ISDN configuration has not yet be ported to new wizard layer"),
                    end => 1,
                   },

                   
                   isdn_real =>
                   {
                    pre=> sub {
                        detect($netc->{autodetect}, 'isdn');
                        # FIXME: offer to pick any card from values %{$netc->{autodetect}{isdn}}
                        $isdn = top(values %{$netc->{autodetect}{isdn}});
                      isdn_step_1:
                        defined $isdn->{id} and goto intern_pci;
                    },
                    # !intern_pci:
                        name => N("What kind is your ISDN connection?"),
                    data => [ { val => \$isdn_type, type => "list", list => [ N_("Internal ISDN card"), N_("External ISDN modem") ], } ],
                    post => sub {
                        if ($isdn_type =~ /card/) {
                          intern_pci:
                            $netc->{isdntype} = 'isdn_internal';
                            $netcnx->{isdn_internal} = $isdn;
                            $netcnx->{isdn_internal} = isdn_read_config($netcnx->{isdn_internal});
                            isdn_detect($netcnx->{isdn_internal}, $netc) or goto isdn_step_1;
                        } else {
                            detect($netc->{autodetect}, 'modem');
                            $netc->{isdntype} = 'isdn_external';
                            $netcnx->{isdn_external}{device} = modem::first_modem($netc);
                            $netcnx->{isdn_external} = isdn_read_config($netcnx->{isdn_external});
                            $netcnx->{isdn_external}{special_command} = 'AT&F&O2B40';
                            require network::modem;
                            $modem = $netcnx->{isdn_external};
                            return "ppp_account";
                        };

                    },
                   },
                   
                   isdn_detect => 
                   {
                    pre => sub  {
                        my ($isdn, $netc) = @_;
                        if ($isdn->{id}) {
                            log::explanations("found isdn card : $isdn->{description}; vendor : $isdn->{vendor}; id : $isdn->{id}; driver : $isdn->{driver}\n");
                            $isdn->{description} =~ s/\|/ -- /;
                            
                          isdn_detect_step_0:
                            defined $isdn->{type} and my $new = $in->ask_yesorno(N("ISDN Configuration"), N("Do you want to start a new configuration ?"), 1);
                            
                            if ($isdn->{type} eq '' || $new) {
                                isdn_ask($isdn, $netc, N("I have detected an ISDN PCI card, but I don't know its type. Please select a PCI card on the next screen.")) or goto isdn_detect_step_0;
                            } else {
                              isdn_detect_step_1:
                                $isdn->{protocol} = isdn_ask_protocol() or goto isdn_detect_step_0;
                              isdn_detect_step_2:
                                isdn_ask_info($isdn, $netc) or goto isdn_detect_step_1;
                                isdn_write_config($isdn, $netc) or goto isdn_detect_step_2;
                            }
                        } else {
                            isdn_ask($isdn, $netc, N("No ISDN PCI card found. Please select one on the next screen.")) or return;
                        }
                        $netc->{$_} = 'ippp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
                        1;
                    }
                   },

                   no_supported_winmodem =>
                   {
                    name => N("Warning") . "\n\n" . N("Your modem isn't supported by the system.
Take a look at http://www.linmodems.org"),
                    end => 1,
                   },


                   modem =>
                   {
                    pre => sub {
                        detect($netc->{autodetect}, 'modem');
                    },
                    name => N("Select the modem to configure:"),
                    data => sub {
                        [ { label => N("Modem"), type => "list", val => \$modem_name, allow_empty_list => 1,
                            list => [ keys %{$netc->{autodetect}{modem}}, N("Manual choice") ], } ],
                    },
                    post => sub {
                        $modem ||= $netcnx->{modem} ||= {};;
                        return 'choose_serial_port' if $modem_name eq N("Manual choice");
                        $ntf_name = $netc->{autodetect}{modem}{$modem_name}{device} || $netc->{autodetect}{modem}{$modem_name}{description};

                        return "ppp_provider" if $ntf_name =~ m!^/dev/!;
                        return "choose_serial_port" if !$ntf_name;

                        my %relocations = (ltmodem => $in->do_pkgs->check_kernel_module_packages('ltmodem'));
                        my $type;
                        
                        foreach (map { $_->{driver} } values %{$netc->{autodetect}{modem}}) {
                            /^Hcf:/ and $type = "hcfpcimodem";
                            /^Hsf:/ and $type = "hsflinmodem";
                            /^LT:/  and $type = "ltmodem";
                            $relocations{$type} || $type && $in->do_pkgs->what_provides($type) or $type = undef;
                        }
                        
                        return "no_supported_winmodem" if !$type;

                        $in->do_pkgs->install($relocations{$type} ? @{$relocations{$type}} : $type);

                        #$type eq 'ltmodem' and $netc->{autodetect}{modem} = '/dev/ttyS14';

                        #- fallback to modem configuration (beware to never allow test it).
                        return "ppp_provider";
                    },
                   },

                   
                   choose_serial_port =>
                   {
                    name => N("Please choose which serial port your modem is connected to."),
                    interactive_help_id => 'selectSerialPort',
                    data => sub {
                        [ { val => \$modem->{device}, format => \&mouse::serial_port2text, type => "list",
                            list => [ grep { $_ ne $o_mouse->{device} } (if_(-e '/dev/modem', '/dev/modem'), mouse::serial_ports()) ] } ],
                        },
                    post => sub {
                        $ntf_name = $modem->{device};
                        return 'ppp_provider';
                    },
                   },


                   ppp_provider =>
                   {
                    pre => sub {
                        network::modem::ppp_read_conf($netcnx, $netc) if !$modem_conf_read;
                        $modem_conf_read = 1;
                        @isp = map {
                            my $country = $_;
                            map { 
                                s!$db_path/$country!!;
                                s/%([0-9]{3})/chr(int($1))/eg;
                                $countries{$country} ||= translate($country);
                                join('', $countries{$country}, $_);
                            } grep { !/.directory$/ } glob_("$db_path/$country/*")
                        } map { s!$db_path/!!o; s!_! !g; $_ } glob_("$db_path/*");
                        $old_provider = $provider;
                    },
                    name => N("Select your provider:"),
                    data => sub {
                        [ { label => N("Provider:"), type => "list", val => \$provider, separator => '/', list => \@isp } ]
                    },
                    post => sub {
                        ($country, $provider) = split('/', $provider);
                        $country = { reverse %countries }->{$country};
                        my %l = getVarsFromSh("$db_path/$country/$provider");
                        if (defined $old_provider && $old_provider ne $provider) {
                            $modem->{connection} = $l{Name};
                            $modem->{phone} = $l{Phonenumber};
                            $modem->{$_} = $l{$_} foreach qw(Authentication AutoName Domain Gateway IPAddr SubnetMask);
                            ($modem->{dns1}, $modem->{dns2}) = split(',', $l{DNS});
                        }
                        return "ppp_account";
                    },
                   },


                   ppp_account =>
                   {
                    pre => sub {
                        $mouse ||= {};
                        $mouse->{device} ||= readlink "$::prefix/dev/mouse";
                        set_cnx_script($netc, "modem", join("\n", if_($::testing, "/sbin/route del default"), "ifup ppp0"),
                                         q(ifdown ppp0
killall pppd
), $netcnx->{type});
                    },
                    name => N("Dialup: account options"), 
                    data => sub {
                            [
                             { label => N("Connection name"), val => \$modem->{connection} },
                             { label => N("Phone number"), val => \$modem->{phone} },
                             { label => N("Login ID"), val => \$modem->{login} },
                             { label => N("Password"), val => \$modem->{passwd}, hidden => 1 },
                             { label => N("Authentication"), val => \$modem->{Authentication}, 
                               list => [ sort keys %ppp_auth_methods ], format => sub { $ppp_auth_methods{$_[0]} } },
                            ],
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
                        $netc->{$_} = 'ppp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
                        $in->do_pkgs->install('kdenetwork-kppp') if !-e '/usr/bin/kppp';
                        $handle_multiple_cnx->();
                    },
                   },


                   adsl => 
                   {
                    pre => sub {
                        get_subwizard($wiz, 'adsl');
                        $lan_detect->();
                        detect($netc->{autodetect}, 'adsl');
                        # FIXME: we still need to detect bewan modems
                        @adsl_devices = keys %eth_intf;
                        foreach my $modem (keys %adsl_devices) {
                            push @adsl_devices, $modem if $netc->{autodetect}{adsl}{$modem};
                        }
                    },
                    name => N("ADSL configuration") . "\n\n" . N("Select the network interface to configure:"),
                    data =>  [ { label => N("Net Device"), type => "list", val => \$ntf_name, allow_empty_list => 1,
                               list => \@adsl_devices, format => sub { $eth_intf{$_[0]} || $adsl_devices{$_[0]} } } ],
                    post => sub {
                        my %packages = (
                                        'eci'        => [ 'eciadsl', 'missing' ],
                                        'sagem'      => [ 'eagle-usb',  '/usr/sbin/eaglectrl' ],
                                        'speedtouch' => [ 'speedtouch', '/usr/share/speedtouch/speedtouch.sh' ],
                                       );
                        return 'adsl_unsupported_eci' if $ntf_name eq 'eci';
                        $need_restart_network = member($ntf_name, qw(speedtouch eci));
                        $in->do_pkgs->install($packages{$ntf_name}->[0]) if $packages{$ntf_name} && !-e $packages{$ntf_name}->[1];
                        if ($ntf_name eq 'speedtouch' && ! -r '$::prefix/usr/share/speedtouch/mgmt.o' && !$::testing) {
                            $in->do_pkgs->what_provides("speedtouch_mgmt") and 
                              $in->do_pkgs->install('speedtouch_mgmt');
                            return 'adsl_speedtouch_firmware' if ! -e "$::prefix/usr/share/speedtouch/mgmt.o";
                        }
                        return 'adsl_provider' if $adsl_devices{$ntf_name};
                        return 'adsl_protocol';
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
                        [ { label => N("Provider:"), type => "list", val => \$adsl_provider, separator => '|', list => [ keys %adsl_data ] } ];
                    },
                    post => sub {
                        $adsl_data = $adsl_data{$adsl_provider};
                        $adsl_type = 'pppoa' if $ntf_name eq 'speedtouch';
                        if ($adsl_provider ne $adsl_old_provider) {
                            $netc->{$_} = $adsl_data->{$_} foreach qw(dnsServer2 dnsServer3 DOMAINNAME2 Encapsulation vpi vci);
                              $adsl_type ||= $adsl_data->{method};
                        }
                        return 'adsl_protocol';
                    },
                   },


                   adsl_speedtouch_firmware =>
                   {
                    name => N("You need the Alcatel microcode.
You can provide it now via a floppy or your windows partition,
or skip and do it later."),
                    data => [ { label => "", val => \$adsl_answer, type => "list",
                                list => [ N("Use a floppy"), N("Use my Windows partition"), N("Do it later") ], }
                            ],
                    post => sub {
                        my $destination = "$::prefix/usr/share/speedtouch/";
                        my ($file, $source, $mounted);
                        if ($adsl_answer eq N("Use a floppy")) {
                            $mounted = 1;
                            $file = 'mgmt.o';
                            ($source, $adsl_failed) = network::tools::use_floppy($in, $file);
                        } elsif ($adsl_answer eq N("Use my Windows partition")) {
                            $file = 'alcaudsl.sys';
                            ($source, $adsl_failed) = network::tools::use_windows();
                        }
                        return "adsl_no_firmawre" if $adsl_answer eq N("Do it later");

                        my $_b = before_leaving { fs::umount('/mnt') } if $mounted;
                        if (!$adsl_failed) {
                            if (-e "$source/$file") { 
                                cp_af("$source/$file", $destination) if !$::testing;
                            } else {
                                $adsl_failed = N("Firmware copy failed, file %s not found", $file);
                            }
                        }
                        log::explanations($adsl_failed || "Firmware copy $file in $destination succeeded");
                        -e "$destination/alcaudsl.sys" and rename "$destination/alcaudsl.sys", "$destination/mgmt.o";

                        # kept translations b/c we may want to reuse it later:
                        my $_msg = N("Firmware copy succeeded");
                        return $adsl_failed ? 'adsl_copy_firmware_failled' : 'adsl_provider';
                    },
                   },


                   adsl_copy_firmware_failled =>
                   {
                    name => sub { $adsl_failed },
                    next => 'adsl_provider',
                   },

                   
                   "adsl_no_firmawre" =>
                   {
                    name => N("You need the Alcatel microcode.
Download it at:
%s
and copy the mgmt.o in /usr/share/speedtouch", 'http://prdownloads.sourceforge.net/speedtouch/speedtouch-20011007.tar.bz2'),
                    next => "adsl_provider",
                   },
         

                   adsl_protocol =>
                   {
                    pre => sub {
                        # preselect right protocol for ethernet though connections:
                        if (!exists $adsl_devices{$ntf_name}) {
                            $ethntf = $intf->{$ntf_name} ||= { DEVICE => $ntf_name };
                            $adsl_type = $ethntf->{BOOTPROTO} || "dhcp";
                        }
                    },
                    name => N("Connect to the Internet") . "\n\n" .
                    N("The most common way to connect with adsl is pppoe.
Some connections use pptp, a few use dhcp.
If you don't know, choose 'use pppoe'"),
                    data =>  [
                              { text => N("ADSL connection type :"), val => \$adsl_type, type => "list",
                                list => [ sort { $adsl_types{$a} cmp $adsl_types{$b} } keys %adsl_types ],
                                format => sub { $adsl_types{$_[0]} },
                              },
                             ],
                    post => sub {
                        $netcnx->{type} = 'adsl';
                        # process static/dhcp ethernet devices:
                        if (!exists $adsl_devices{$ntf_name} && member($adsl_type, qw(manual dhcp))) {
                            $auto_ip = $adsl_type eq 'dhcp';
                            $find_lan_module->();
                            return 'lan_intf';
                        }
                        network::adsl::adsl_probe_info($netcnx, $netc, $adsl_type, $ntf_name);
                        $netc->{NET_DEVICE} = $ntf_name if $adsl_type eq 'pppoe';
                        return 'adsl_account';
                    },
                   },
                    

                   adsl_account => 
                   {
                    pre => sub {
                        $netc->{dnsServer2} ||= $adsl_data->{dns1};
                        $netc->{dnsServer3} ||= $adsl_data->{dns2};
                    },
                    name => N("Connection Configuration") . "\n\n" .
                    N("Please fill or check the field below"),
                    data => sub {
                        [ 
                         { label => N("Provider name (ex provider.net)"), val => \$netc->{DOMAINNAME2} },
                         { label => N("First DNS Server (optional)"), val => \$netc->{dnsServer2} },
                         { label => N("Second DNS Server (optional)"), val => \$netc->{dnsServer3} },
                         { label => N("Account Login (user name)"), val => \$netcnx->{login} },
                         { label => N("Account Password"),  val => \$netcnx->{passwd}, hidden => 1 },
                         { label => N("Virtual Path ID (VPI):"), val => \$netc->{vpi}, advanced => 1 },
                         { label => N("Virtual Circuit ID (VCI):"), val => \$netc->{vci}, advanced => 1 },
                         { label => N("Encapsulation :"), val => \$netc->{Encapsulation}, list => [ keys %encapsulations ],
                           format => sub { $encapsulations{$_[0]} }, advanced => 1,
                         },
                        ],
                    },
                    post => sub {
                        $netc->{internet_cnx_choice} = 'adsl';
                        network::adsl::adsl_conf_backend($in, $netcnx, $netc, $ntf_name, $adsl_type); #FIXME
                        $config->{adsl} = { kind => "$ntf_name", protocol => $adsl_type };
                        $handle_multiple_cnx->();
                    },
                   },


                    adsl_unsupported_eci => 
                    {
                     name => N("The ECI Hi-Focus modem cannot be supported due to binary driver distribution problem.

You can find a driver on http://eciadsl.flashtux.org/"),
                     end => 1,
                    },
         

                   lan => 
                   {
                    pre => $lan_detect,
                    name => N("Select the network interface to configure:"),
                    data =>  sub {
                        [ { label => N("Net Device"), type => "list", val => \$ntf_name, list => [ N("Manual choice"), sort keys %eth_intf ], 
                            allow_empty_list => 1, format => sub { $eth_intf{$_[0]} || $_[0]} } ];
                    },
                    post => sub {
                        $ethntf = $intf->{$ntf_name} ||= { DEVICE => $ntf_name };
                        if ($ntf_name eq N("Manual choice")) {
                            modules::interactive::load_category__prompt($in, 'network/main|gigabit|pcmcia|usb|wireless');
                            return 'lan';
                        }
                        $::isInstall && $netc->{NET_DEVICE} eq $ethntf->{DEVICE} ? 'lan_alrd_cfg' : 'lan_protocol';
                    },
                   },

                   lan_alrd_cfg =>
                   {
                    name => N("WARNING: this device has been previously configured to connect to the Internet.
Simply accept to keep this device configured.
Modifying the fields below will override this configuration."),
                    type => "yesorno",
                    post => sub {
                        my ($res) = @_;
                        die 'wizcancel' if !$res;
                        return "lan_protocol";
                    }
                   },

                   lan_protocol =>
                   {
                    pre => sub  {
                        $find_lan_module->();
                        $auto_ip = $l10n_lan_protocols{defined $auto_ip ? ($auto_ip ? 'dhcp' : 'static') : $ethntf->{BOOTPROTO}} || 0;
                    },
                    name => sub { 
                        my $_msg = N("Zeroconf hostname resolution");
                        N("Configuring network device %s (driver %s)", $ethntf->{DEVICE}, $module) . "\n\n" .
                          N("The following protocols can be used to configure an ethernet connection. Please choose the one you want to use")
                    },
                    data => sub {
                        [ { val => \$auto_ip, type => "list", list => [ sort values %l10n_lan_protocols ] } ];
                    },
                    post => sub {
                        $auto_ip = $auto_ip ne $l10n_lan_protocols{static} || 0;
                        return 'lan_intf';
                    },
                   },
                   

                   # FIXME: is_install: no return for each card "last step" because of manual popping
                   # better construct an hash of { current_netintf => next_step } which next_step = last_card ? next_eth_step : next_card ?
                   lan_intf => 
                   {
                    pre => sub  {
                        $onboot = $ethntf->{ONBOOT} ? $ethntf->{ONBOOT} =~ /yes/ : bool2yesno(!member($ethntf->{DEVICE}, 
                                                                                                      map { $_->{device} } detect_devices::pcmcia_probe()));
                        $needhostname = $ethntf->{NEEDHOSTNAME} !~ /no/; 
                        # blacklist bogus driver, enable ifplugd support else:
                        my @devs = detect_devices::pcmcia_probe();
                        $ethntf->{MII_NOT_SUPPORTED} ||= bool2yesno($is_wireless || member($module, qw(forcedeth))
                                                                    || find { $_->{device} eq $ntf_name } @devs);
                        $hotplug = !text2bool($ethntf->{MII_NOT_SUPPORTED});
                        $track_network_id = $::isStandalone && $ethntf->{HWADDR} || detect_devices::isLaptop();
                        delete $ethntf->{NETWORK};
                        delete $ethntf->{BROADCAST};
                        @fields = qw(IPADDR NETMASK);
                        $netc->{dhcp_client} ||= "dhcp-client";
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
                           { label => N("DHCP host name"), val => \$ethntf->{DHCP_HOSTNAME}, disabled => sub { !$needhostname } },
                          )
                          :
                          (
                           { label => N("IP address"), val => \$ethntf->{IPADDR}, disabled => sub { $auto_ip } },
                           { label => N("Netmask"), val => \$ethntf->{NETMASK}, disabled => sub { $auto_ip } },
                          ),
                          { text => N("Track network card id (useful for laptops)"), val => \$track_network_id, type => "bool" },
                          { text => N("Network Hotplugging"), val => \$hotplug, type => "bool" },
                          { text => N("Start at boot"), val => \$onboot, type => "bool" },
                          if_($auto_ip, 
                              { label => N("DHCP client"), val => \$netc->{dhcp_client}, 
                                list => [ "dhcp-client", "dhcpcd", "dhcpxd" ], advanced => 1 },
                             ),
                        ],
                    },
                    complete => sub {
                        $ethntf->{BOOTPROTO} = $auto_ip ? "dhcp" : "static";
                        $netc->{DHCP} = $auto_ip;
                        return 0 if $auto_ip;
                        if (my @bad = map_index { if_(!is_ip($ethntf->{$_}), $::i) } @fields) {
                            $in->ask_warn(N("Error"), N("IP address should be in format 1.2.3.4"));
                            return 1, $bad[0];
                        }
                        $in->ask_warn(N("Error"), N("Warning : IP address %s is usually reserved !", $ethntf->{IPADDR})) if is_ip_forbidden($ethntf->{IPADDR});
                    },
                    focus_out => sub {
                        $ethntf->{NETMASK} ||= netmask($ethntf->{IPADDR}) unless $_[0]
                    },
                    post => sub {
                        $ethntf->{ONBOOT} = bool2yesno($onboot);
                        $ethntf->{NEEDHOSTNAME} = bool2yesno($needhostname);
                        $ethntf->{MII_NOT_SUPPORTED} = bool2yesno(!$hotplug);
                        $ethntf->{HWADDR} = $track_network_id or delete $ethntf->{HWADDR};
                        $in->do_pkgs->install($netc->{dhcp_client}) if $auto_ip;
                        set_cnx_script($netc, "cable", qq(
/sbin/ifup $netc->{NET_DEVICE}
),
                                                  qq(
/sbin/ifdown $netc->{NET_DEVICE}
), $netcnx->{type}) if $netcnx->{type} eq 'cable';

                        return $is_wireless ? "wireless" : "static_hostname";
                    },
                   },
                   
                   wireless =>
                   {
                    pre => sub {
                        $ethntf->{wireless_eth} = 1;
                        $netc->{wireless_eth} = 1;
                        $ethntf->{WIRELESS_MODE} ||= "Managed";
                        $ethntf->{WIRELESS_ESSID} ||= "any";
                    },
                    name => N("Please enter the wireless parameters for this card:"),
                    data => sub {
                            [
                             { label => N("Operating Mode"), val => \$ethntf->{WIRELESS_MODE}, 
                               list => [ keys %wireless_mode ] },
                             { label => N("Network name (ESSID)"), val => \$ethntf->{WIRELESS_ESSID} },
                             { label => N("Network ID"), val => \$ethntf->{WIRELESS_NWID}, advanced => 1 },
                             { label => N("Operating frequency"), val => \$ethntf->{WIRELESS_FREQ}, advanced => 1 },
                             { label => N("Sensitivity threshold"), val => \$ethntf->{WIRELESS_SENS}, advanced => 1 },
                             { label => N("Bitrate (in b/s)"), val => \$ethntf->{WIRELESS_RATE}, advanced => 1 },
                             { label => N("Encryption key"), val => \$ethntf->{WIRELESS_ENC_KEY} },
                            ],
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
                    },
                    next => "wireless2",
                   },


                   wireless2 =>
                   {
                    name => N("Please enter the wireless parameters for this card:"),
                    data => sub {
                        [
                             { label => N("RTS/CTS"), val => \$ethntf->{WIRELESS_RTS},
                               help => N("RTS/CTS adds a handshake before each packet transmission to make sure that the
channel is clear. This adds overhead, but increase performance in case of hidden
nodes or large number of active nodes. This parameter sets the size of the
smallest packet for which the node sends RTS, a value equal to the maximum
packet size disable the scheme. You may also set this parameter to auto, fixed
or off.")
                             },
                             { label => N("Fragmentation"), val => \$ethntf->{WIRELESS_FRAG} },
                             { label => N("Iwconfig command extra arguments"), val => \$ethntf->{WIRELESS_IWCONFIG}, advanced => 1,
                               help => N("Here, one can configure some extra wireless parameters such as:
ap, channel, commit, enc, power, retry, sens, txpower (nick is already set as the hostname).

See iwpconfig(8) man page for further information."),
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
                             { label => N("Iwpriv command extra arguments"), val => \$ethntf->{WIRELESS_IWPRIV}, advanced => 1,
                               help => N("Iwpriv enable to set up optionals (private) parameters of a wireless network
interface.

Iwpriv deals with parameters and setting specific to each driver (as opposed to
iwconfig which deals with generic ones).

In theory, the documentation of each device driver should indicate how to use
those interface specific commands and their effect.

See iwpriv(8) man page for further information."),
                             }
                         ]
                    },
                    post => sub {
                        # untranslate parameters
                        $ethntf->{WIRELESS_MODE} = $wireless_mode{$ethntf->{WIRELESS_MODE}};
                        return "static_hostname";
                    },
                   },
                   
                   conf_network_card => 
                   {
                    pre => sub {
                        #-type =static or dhcp
                        modules::interactive::load_category($in, 'network/main|gigabit|usb', !$::expert, 1);
                        @all_cards = network::ethernet::get_eth_cards() or 
                          # FIXME: fix this
                          $in->ask_warn(N("Error"), N("No ethernet network adapter has been detected on your system.
I cannot set up this connection type.")), return;
                        
                                         },
                    name => N("Choose the network interface") . "\n\n" .
                    N("Please choose which network adapter you want to use to connect to Internet."),
                    data => [ { val => \$interface, type => "list", list => \@all_cards, } ],
                    format => sub { my ($e) = @_; $e->[0] . ($e->[1] ? " (using module $e->[1])" : "") },
                    
                    post => sub {
                        write_ether_conf();
                        modules::write_conf() if $::isStandalone;
                        my $_device = conf_network_card_backend($netc, $intf, $type, $interface->[0], $ipadr, $netadr);
                        return "lan";
                    },
                   },
                   
                   static_hostname => 
                   {
                    pre => sub {
                        network::ethernet::write_ether_conf($in, $netcnx, $netc, $intf) if $netcnx->{type} eq 'lan';
                        if ($ethntf->{IPADDR}) {
                            $netc->{dnsServer} ||= dns($ethntf->{IPADDR});
                            $gateway_ex = gateway($ethntf->{IPADDR});
                            # $netc->{GATEWAY} ||= gateway($ethntf->{IPADDR});
                        }
                    },
                    name => N("Please enter your host name.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''.
You may also enter the IP address of the gateway if you have one.") .
N("Last but not least you can also type in your DNS server IP addresses."),
                    data => sub {
                        [ { label => $auto_ip ? N("Host name (optional)") : N("Host name"), val => \$netc->{HOSTNAME}, advanced => $auto_ip },
                          { label => N("DNS server 1"),  val => \$netc->{dnsServer} },
                          { label => N("DNS server 2"),  val => \$netc->{dnsServer2} },
                          { label => N("DNS server 3"),  val => \$netc->{dnsServer3} },
                          { label => N("Search domain"), val => \$netc->{DOMAINNAME}, 
                            help => N("By default search domain will be set from the fully-qualified host name") },
                          if_(!$auto_ip, { label => N("Gateway (e.g. %s)", $gateway_ex), val => \$netc->{GATEWAY} },
                              if_(@all_cards > 1,
                                  { label => N("Gateway device"), val => \$netc->{GATEWAYDEV}, list => [ sort keys %eth_intf ], 
                                    format => sub { $eth_intf{$_[0]} } },
                                 ),
                             ),
                        ],
                    },
                    complete => sub {
                        foreach my $dns (qw(dnsServer dnsServer2 dnsServer3)) {
                            if ($netc->{$dns} && !is_ip($netc->{$dns})) {
                                $in->ask_warn(N("Error"), N("DNS server address should be in format 1.2.3.4"));
                                return 1;
                            }
                        }
                        if ($netc->{GATEWAY} && !is_ip($netc->{GATEWAY})) {
                            $in->ask_warn(N("Error"), N("Gateway address should be in format 1.2.3.4"));
                            return 1;
                        }
                    },
                    #post => $handle_multiple_cnx,
                    next => "zeroconf",
                   },
                   
                   
                   zeroconf => 
                   {
                    name => N("Enter a Zeroconf host name which will be the one that your machine will get back to other machines on the network:"),
                    data => [ { label => N("Zeroconf Host name"), val => \$netc->{ZEROCONF_HOSTNAME} } ],
                    complete => sub {
                        if ($netc->{ZEROCONF_HOSTNAME} =~ /\./) {
                            $in->ask_warn(N("Error"), N("Zeroconf host name must not contain a ."));
                            return 1;
                        }
                    },
                    post => $handle_multiple_cnx,
                   },
                   
                   
                   multiple_internet_cnx => 
                   {
                    name => N("You have configured multiple ways to connect to the Internet.\nChoose the one you want to use.\n\n") . if_(!$::isStandalone, "You may want to configure some profiles after the installation, in the Mandrake Control Center"),
                    data => sub {
                        [ { label => N("Internet connection"), val => \$netc->{internet_cnx_choice}, 
                            list => [ keys %{$netc->{internet_cnx}} ] } ];
                    },
                    post => sub {
                        if (keys %$config) {
                            require Data::Dumper;
                            output('/etc/sysconfig/drakconnect', Data::Dumper->Dump([$config], ['$p']));
                        }
                        return "network_on_boot";
                    },
                   },
                   
                   apply_settings => 
                   {
                    name => N("Configuration is complete, do you want to apply settings ?"),
                    type => "yesorno",
                   },
                   
                   network_on_boot => 
                   {
                    pre => sub {
                        # condition is :
                        member($netc->{internet_cnx_choice}, ('adsl', 'isdn')); # and $netc->{at_boot} = $in->ask_yesorno(N("Network Configuration Wizard"), N("Do you want to start the connection at boot?"));
                    },
                    name => N("Do you want to start the connection at boot?"),
                    type => "yesorno",
                    default => sub { ($type eq 'modem' ? 'no' : 'yes') },
                    post => sub {
                        my ($res) = @_;
                        $netc->{at_boot} = $res;
                        if ($res) {
                            write_cnx_script($netc);
                            $netcnx->{type} = $netc->{internet_cnx}{$netc->{internet_cnx_choice}}{type} if $netc->{internet_cnx_choice};
                            write_initscript();
                        } else {
                            undef $netc->{NET_DEVICE};
                        }
                        
                        network::network::configureNetwork2($in, $::prefix, $netc, $intf);
                        $network_configured = 1;
                        return "restart" if $need_restart_network && $::isStandalone && !$::expert;
                        return $offer_to_connect->();
                    },
                   },

                   restart => 
                   {
                    name => N("The network needs to be restarted. Do you want to restart it ?"),
                    type => "yesorno",
                    post => sub {
                        my ($a) = @_;
                        if ($a && !$::testing && !run_program::rooted($::prefix, "/etc/rc.d/init.d/network restart")) {
                            $success = 0;
                            $in->ask_okcancel(N("Network Configuration"), 
                                              N("A problem occured while restarting the network: \n\n%s", `/etc/rc.d/init.d/network restart`), 0);
                        }
                        return $offer_to_connect->();
                    },
                   },
                   
                   ask_connect_now => 
                   {
                    name => N("Do you want to try to connect to the Internet now?"),
                    type => "yesorno",
                    post => sub {
                        my ($a) = @_;
                        my ($type) = $netc->{internet_cnx_choice};
                        $up = 1;
                        if ($a) {
                            # local $::isWizard = 0;
                            my $_w = $in->wait_message('', N("Testing your connection..."), 1);
                            connect_backend();
                            my $s = 30;
                            $type =~ /modem/ and $s = 50;
                            $type =~ /adsl/ and $s = 35;
                            $type =~ /isdn/ and $s = 20;
                            sleep $s;
                            $up = connected();
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
                            N("The system doesn't seem to be connected to the Internet.
Try to reconfigure your connection.");
                    },
                    no_back => 1,
                    end => 1,
                    post => sub {
                        $::isInstall and disconnect_backend();
                        return "end";
                    },
                   },

                   end => 
                   {
                    name => sub {
                        return $success ? join('', N("Congratulations, the network and Internet configuration is finished.

"), if_($::isStandalone && $in->isa('interactive::gtk'),
        N("After this is done, we recommend that you restart your X environment to avoid any hostname-related problems."))) : 
          N("Problems occured during configuration.
Test your connection via net_monitor or mcc. If your connection doesn't work, you might want to relaunch the configuration.");
                    },
                           end => 1,
                   },
                  },
        };
      
      my $use_wizard = 1;
      if ($::isInstall) {
          if ($first_time && $in->{method} =~ /^(ftp|http|nfs)$/) {
              !$::expert && !$o_noauto || $in->ask_okcancel(N("Network Configuration"),
                                                            N("Because you are doing a network installation, your network is already configured.
Click on Ok to keep your configuration, or cancel to reconfigure your Internet & Network connection.
"), 1) 
                and do {
                    $netcnx->{type} = 'lan';
                    # should use write_cnx_file:
                    output_with_perm("$::prefix$network::tools::connect_file", 0755, qq(ifup eth0
));
                    output("$::prefix$network::tools::disconnect_file", 0755, qq(
ifdown eth0
));
                    $direct_net_install = 1;
                    $use_wizard = 0;
                };
        }
      };
      
      if ($use_wizard) {
          require wizards;
          $wiz->{var} = {
                         netc  => $netc,
                         mouse => $mouse,
                         intf  => $intf,
                        };
          wizards->new->safe_process($wiz, $in);
      }

    # install needed packages:
    $network_configured or network::network::configureNetwork2($in, $::prefix, $netc, $intf);

    my $connect_cmd;
    if ($netcnx->{type} =~ /modem/ || $netcnx->{type} =~ /isdn_external/) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
	if [ -e /usr/bin/kppp ]; then
		/sbin/route del default
		/usr/bin/kppp &
	else
		/usr/sbin/net_monitor --connect
	fi
	else
	$network::tools::connect_file
fi
);
    } elsif ($netcnx->{type}) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
	/usr/sbin/net_monitor --connect
else
	$network::tools::connect_file
fi
);
    } else {
	$connect_cmd = qq(
#!/bin/bash
/usr/sbin/drakconnect
);
    }
    if ($direct_net_install) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
	/usr/sbin/net_monitor --connect
else
	$network::tools::connect_file
fi
);
    }
    output_with_perm("$::prefix$network::tools::connect_prog", 0755, $connect_cmd) if $connect_cmd;
    $netcnx->{$_} = $netc->{$_} foreach qw(NET_DEVICE NET_INTERFACE);
    $netcnx->{type} =~ /adsl/ or system("/sbin/chkconfig --del adsl 2> /dev/null");

    if ($::isInstall && $::o->{security} >= 3) {
	require network::drakfirewall;
	network::drakfirewall::main($in, $::o->{security} <= 3);
    }
}

sub main {
    my ($_prefix, $netcnx, $in, $o_netc, $o_mouse, $o_intf, $o_first_time, $o_noauto) = @_;
    eval { real_main('', , $netcnx, $in, $o_netc, $o_mouse, $o_intf, $o_first_time, $o_noauto) };
    my $err = $@;
    if ($err) { # && $in->isa('interactive::gtk')
        local $::isEmbedded = 0; # to prevent sub window embedding
        local $::isWizard = 0 if !$::isInstall; # to prevent sub window embedding
        #err_dialog(N("Error"), N("An unexpected error has happened:\n%s", $err));
        $in->ask_warn(N("Error"), N("An unexpected error has happened:\n%s", $err));
    }
}

sub set_profile {
    my ($netcnx) = @_;
    system(qq(/sbin/set-netprofile "$netcnx->{PROFILE}"));
    log::explanations(qq(Switching to "$netcnx->{PROFILE}" profile));
}

sub save_profile {
    my ($netcnx) = @_;
    system(qq(/sbin/save-netprofile "$netcnx->{PROFILE}"));
    log::explanations(qq(Saving "$netcnx->{PROFILE}" profile));
}

sub del_profile {
    my ($profile) = @_;
    return if !$profile || $profile eq "default";
    rm_rf("$::prefix/etc/netprofile/profiles/$profile");
    log::explanations(qq(Deleting "$profile" profile));
}

sub add_profile {
    my ($netcnx, $profile) = @_;
    return if !$profile || $profile eq "default" || member($profile, get_profiles());
    system(qq(/sbin/clone-netprofile "$netcnx->{PROFILE}" "$profile"));
    log::explanations(qq("Creating "$profile" profile));
}

sub get_profiles() {
    map { if_(m!([^/]*)/$!, $1) } glob("$::prefix/etc/netprofile/profiles/*/");
}

sub load_conf {
    my ($netcnx, $netc, $intf) = @_;
    my $current = { getVarsFromSh("$::prefix/etc/netprofile/current") };
    
    $netcnx->{PROFILE} = $current->{PROFILE} || 'default';
    network::network::read_all_conf($::prefix, $netc, $intf);
}

sub get_net_device() {
    my $connect_file = $network::tools::connect_file;
    my $network_file = "/etc/sysconfig/network";
		if (cat_("$::prefix$connect_file") =~ /ifup/) {
  		if_(cat_($connect_file) =~ /^\s*ifup\s+(.*)/m, split(' ', $1))
		} elsif (cat_("$::prefix$connect_file") =~ /network/) {
			${{ getVarsFromSh("$::prefix$network_file") }}{GATEWAYDEV};
    } elsif (cat_("$::prefix$connect_file") =~ /isdn/) {
			"ippp+"; 
    } else {
			"ppp+";
    };
}

sub read_net_conf {
    my ($_prefix, $netcnx, $netc) = @_;
    $netc->{$_} = $netcnx->{$_} foreach 'NET_DEVICE', 'NET_INTERFACE';
    $netcnx->{$netcnx->{type}} ||= {};
}

sub start_internet {
    my ($o) = @_;
    init_globals($o);
    #- give a chance for module to be loaded using kernel-BOOT modules...
    $::isStandalone or modules::load_category('network/main|gigabit|usb');
    run_program::rooted($::prefix, $network::tools::connect_file);
}

sub stop_internet {
    my ($o) = @_;
    init_globals($o);
    run_program::rooted($::prefix, $network::tools::disconnect_file);
}

1;

=head1 network::netconnect::detect()

=head2 example of usage

use lib qw(/usr/lib/libDrakX);
use network::netconnect;
use Data::Dumper;

use class_discard;

local $in = class_discard->new;

network::netconnect::init_globals($in);
my %i;
&network::netconnect::detect(\%i);
print Dumper(\%i),"\n";

=cut
