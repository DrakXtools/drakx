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
use MDK::Common::Globals "network", qw($in $prefix $connect_file $disconnect_file $connect_prog);

my %conf;

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
                 $auto_detect->{lan} = { map { $_->[0] => $_->[1] } network::ethernet::conf_network_card_backend() };
             },
             adsl => sub {
                 require network::adsl;
                 $auto_detect->{adsl} = network::adsl::adsl_detect();
             },
             modem => sub {
                 my ($modem, @pci_modems) = detect_devices::getModem();
                 $modem->{device} and $auto_detect->{modem} = $modem->{device};
                 @pci_modems and $auto_detect->{winmodem}{$_->{driver}} = $_->{description} foreach @pci_modems;
             },
            );
    $l{$_}->() foreach ($o_class || (keys %l));
    return;
}

sub init_globals {
    my ($in, $prefix) = @_;
    MDK::Common::Globals::init(
			       in => $in,
			       prefix => $prefix,
			       connect_file => "/etc/sysconfig/network-scripts/net_cnx_up",
			       disconnect_file => "/etc/sysconfig/network-scripts/net_cnx_down",
			       connect_prog => "/etc/sysconfig/network-scripts/net_cnx_pg");
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


# configuring all network devices
  sub main {
      my ($_prefix, $netcnx, $in, $o_netc, $o_mouse, $o_intf, $o_first_time, $o_noauto) = @_;
      my $netc  = $o_netc  || {};
      my $mouse = $o_mouse || {};
      my $intf  = $o_intf  || {};
      my $first_time = $o_first_time || 0;
      my ($network_configured, $direct_net_install, $cnx_type, $type, $interface, @cards, @all_cards, @devices);
      my (%connection_steps, %connections, %rconnections, @connection_list);
      my ($ntf_name, $ipadr, $netadr, $gateway_ex, $up, $modem, $isdn, $isdn_type, $adsl_type, $need_restart_network);
      my ($module, $text, $auto_ip, $net_device, $onboot, $needhostname, $hotplug, $track_network_id, @fields); # lan config
      my $success = 1;
      my $ethntf = {};
      use Data::Dumper;

      my %wireless_mode = (N("Ad-hoc") => "Ad-hoc", 
                           N("Managed") => "Managed", 
                           N("Master") => "Master",
                           N("Repeater") => "Repeater",
                           N("Secondary") => "Secondary",
                           N("Auto") => "Auto",
                          );
      my %l10n_lan_protocols = (
                               static => N("Manual configuration"),
                               dhcp   => N("Automatic IP (BOOTP/DHCP/Zeroconf)"),
                              );


      init_globals($in, $::prefix);
      $netc->{NET_DEVICE} = $netcnx->{NET_DEVICE} if $netcnx->{NET_DEVICE}; # REDONDANCE with read_conf. FIXME
      $netc->{NET_INTERFACE} = $netcnx->{NET_INTERFACE} if $netcnx->{NET_INTERFACE}; # REDONDANCE with read_conf. FIXME
      network::network::read_all_conf($::prefix, $netc, $intf);

      modules::mergein_conf("$::prefix/etc/modules.conf");

      $netc->{autodetection} = 0;
      $netc->{autodetect} = {};

      my $next_cnx_step = sub {
          my $next = $connection_steps{$cnx_type};
          # FIXME: we want this in standalone mode too:
          $need_restart_network = 1 if $next =~ /lan|cable/;
          if ($next eq "multiple_internet_cnx") {
              return 1 < scalar(keys %{$netc->{internet_cnx}}) ? "multiple_internet_cnx" : $connection_steps{multiple_internet_cnx};
          }
          return $next;
      };

      my $ppp_first_step = sub {
          $mouse ||= {};
          $mouse->{device} ||= readlink "$::prefix/dev/mouse";
          write_cnx_script($netc, "modem", join("\n", if_($::testing, "/sbin/route del default"), "ifup ppp0"),
                           q(ifdown ppp0
killall pppd
), $netcnx->{type});
          my $need_to_ask = $modem->{device} || !$netc->{autodetect}{winmodem};
          return $need_to_ask ? "ppp_choose" : "ppp_choose2";
      };

      my $handle_multiple_cnx = sub {
          my $nb = keys %{$netc->{internet_cnx}};
          if (1 < $nb) {
          } else {
              $netc->{internet_cnx_choice} = (keys %{$netc->{internet_cnx}})[0] if $nb == 1;
              return $::isInstall ? "network_on_boot" : "apply_settings"
          }
      };
    
      # main wizard:
      my $wiz;
      $wiz =
        {
         defaultimage => "wiz_drakconnect.png",
         name => N("Network & Internet Configuration"),
         pages => {
                   install => 
                   {
                    if_($::isInstall, no_back => 1),
                    name => N("Welcome to The Network Configuration Wizard.

We are about to configure your internet/network connection.
If you don't want to use the auto detection, deselect the checkbox.
"),
                    interactive_help_id => 'configureNetwork',
                    data => [
                             { text => N("Use auto detection"), val => \$netc->{autodetection}, type => 'bool' },
                             { text => N("Expert Mode"), val => \$::expert, type => 'bool' },
                            ],
                    post => sub {
                        if ($netc->{autodetection}) {
                            my $_w = $in->wait_message(N("Network Configuration Wizard"), N("Detecting devices..."));
                            detect($netc->{autodetect});
                        }
                        
                        $conf{$_} = values %{$netc->{autodetect}{$_}} ? 1 : 0 foreach 'lan';
                        $conf{$_} = $netc->{autodetect}{$_} ? 1 : 0 foreach qw(adsl cable modem winmodem);
                        $conf{isdn} = any { $_->{driver} } values %{$netc->{autodetect}{isdn}};
                        return "connection";
                    },
                   },

                   connection => 
                   {
                    pre => sub {
                        if (!$::isInstall) {
                            $conf{$_} = 0 foreach qw(adsl cable isdn lan modem winmodem);
                        }
                        my @connections = 
                          (
                           [ #-PO: here, "(detected)" string will be appended to eg "ADSL connection"
                            N("Normal modem connection"), N("(detected on port %s)", $netc->{autodetect}{modem}), "modem" ],
                           [ N("Winmodem connection"), N("(detected)"), "winmodem" ],
                           [ N("ISDN connection"),  N("(detected %s)", join(', ', map { $_->{description} } values %{$netc->{autodetect}{isdn}})), "isdn" ],
                           [ N("ADSL connection"),  N("(detected)"), "adsl" ],
                           [ N("Cable connection"), N("(detected)"), "cable" ],
                           [ N("LAN connection"),   N("(detected)"), "lan" ],
                           # if we ever want to split out wireless connection, we'd to split out modules between network/main and network/wlan:
                           if_(0, [ N("Wireless connection"),   N("(detected)"), "lan" ]),
                          );
                        
                        foreach (@connections) {
                            my ($str, $extra_str, $type) = @$_;
                            my $string = join('', $str, if_($conf{$type}, " - ", $extra_str));
                            $connections{$string} = $type;
                        }
                        %rconnections = reverse %connections;
                        if ($::isInstall) {
                            @connection_list = map {
                                my (undef, undef, $type) = @$_;
                                +{ text => $rconnections{$type}, val => \$conf{$type}, type => 'bool' }
                            } @connections;
                        } else {
                            @connection_list = ({ val => \$type, type => 'list', list => [ map { $_->[0] } @connections ], });
                        }
                    },
                    if_(!$::isInstall, no_back => 1),
                    name => N("Choose the connection you want to configure"),
                    interactive_help_id => 'configureNetwork',
                    data => \@connection_list,
                    changed => sub {
                        return if !$netc->{autodetection};
                        my $c = 0;
                        #-      $conf{adsl} and $c++;
                        $conf{cable} and $c++;
                        my $a = keys(%{$netc->{autodetect}{lan}});
                        0 < $a && $a <= $c and $conf{lan} = undef;
                    },
                    complete => sub {
                        # at least one connection type must be choosen
                        return 0 if !$::isInstall;
                        return !any { $conf{$_} } keys %conf;
                    },
                    post => sub {
                        load_conf($netcnx, $netc, $intf) if $::isInstall;  # :-(
                        # while in installer, we need to link connections steps depending of which connections the user selected
                        my @l;
                        if ($::isInstall) {
                            @l = grep { $conf{$_} } keys %conf;
                        } else {
                            $type = $connections{$type};
                            @l = ($type);
                        }
                        my $first = shift @l;
                        my @steps = (@l, "multiple_internet_cnx", "apply_settings");
                        foreach my $cnx ($first, @l) {
                            $connection_steps{$cnx} = shift @steps;
                        }
                        #
                        # FIXME: get rid of all bugs by just sharing the same paths between standalone and install mode (anyway
                        #        old "all cnx in one pass" was not very wizard-friendly....
                        #
                        return $type;
                    },
                   },

                   prepare_detection => 
                   {
                    name => N("We are now going to configure the %s connection.\n\n\nPress \"%s\" to continue.",
                              translate($type), N("Next")),
                    post => $next_cnx_step,
                   },

                 
                   hw_account => 
                   { # ask_info2
                    #my ($cnx, $netc) = @_;
                    
                    name => N("Connection Configuration") . "\n\n" .
                    N("Please fill or check the field below"),
                    data => [ 
                             (map {
                                 my ($dstruct, $field, $item) = @$_;
                                 $item->{val} = \$wiz->{var}{$dstruct}{$field};
                                 if__($wiz->{var}{$dstruct}{$field}, $item);
                             } ([ "cnx",  "irq", { label => N("Card IRQ") } ],
                                [ "cnx",  "mem", { label => N("Card mem (DMA)") } ],
                                [ "cnx",  "io",  { label => N("Card IO") } ],
                                [ "cnx",  "io0", { label => N("Card IO_0") } ],
                                [ "cnx",  "io1", { label => N("Card IO_1") } ],
                                [ "cnx",  "phone_in",     { label => N("Your personal phone number") } ],
                                [ "netc", "DOMAINNAME2",  { label => N("Provider name (ex provider.net)") } ],
                                [ "cnx",  "phone_out",    { label => N("Provider phone number") } ],
                                [ "netc", "dnsServer2",   { label => N("Provider dns 1 (optional)") } ],
                                [ "netc", "dnsServer3",   { label => N("Provider dns 2 (optional)") } ],
                                [ "cnx",  "vpivci",       { label => N("Choose your country"), list => detect_timezone() } ],
                                [ "cnx",  "dialing_mode", { label => N("Dialing mode"),  list => ["auto", "manual"] } ],
                                [ "cnx",  "speed",        { label => N("Connection speed"), list => ["64 Kb/s", "128 Kb/s"] } ],
                                [ "cnx",  "huptimeout",   { label => N("Connection timeout (in sec)") } ],
                               )
                             ),
                             ({ label => N("Account Login (user name)"), val => \$wiz->{var}{cnx}{login} },
                              { label => N("Account Password"),  val => \$wiz->{var}{cnx}{passwd}, hidden => 1 },
                             )
                            ],
                    post => sub {
                        my $netc = $wiz->{var}{netc};
                        if ($netc->{vpivci}) {
                            my %h = (N("Belgium") => '8_35' ,
                                     N("France")  => '8_35'  ,
                                     N("Italy")   => '8_35' ,
                                     N("Netherlands")    => '8_48' ,
                                     N("United Kingdom") => '0_38' ,
                                     N("United States")  => '8_35',
                                    );
                            $netc->{vpivci} = $h{$netc->{vpivci}};
                        }
                    },
                   },
                   
                   cable => 
                   {
                    name => N("Connect to the Internet") . "\n\n" .
                    N("Which dhcp client do you want to use ? (default is dhcp-client)"),
                    data =>
                    [ { val => \$netcnx->{dhcp_client}, list => ["dhcp-client", "dhcpcd", "dhcpxd"] } ],
                    
                    post => sub {
                        $netcnx->{type} = $type = 'cable';
                        $in->do_pkgs->install($netcnx->{dhcp_client});
                                 write_cnx_script($netc, "cable", qq(
/sbin/ifup $netc->{NET_DEVICE}
),
                                                  qq(
/sbin/ifdown $netc->{NET_DEVICE}
), $netcnx->{type});
                        return "go_ethernet";
                    },
                            },
                   
                   go_ethernet => 
                   {
                    pre => sub {
                        # my ($netc, $intf, $type, $ipadr, $netadr, $first_time) = @_;
                        conf_network_card($netc, $intf, $type, $ipadr, $netadr) or return;
                        $netc->{NET_INTERFACE} = $netc->{NET_DEVICE};
                        configureNetwork($netc, $intf, $first_time) or return;
                    },
                   },

                   isdn =>
                   {
                    pre=> sub {
                        detect($netc->{autodetect}, 'isdn') if !$::isInstall && !$netc->{autodetection};
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
                            $netc->{isdntype} = 'isdn_external';
                            $netcnx->{isdn_external}{device} = $netc->{autodetect}{modem};
                            $netcnx->{isdn_external} = isdn_read_config($netcnx->{isdn_external});
                            $netcnx->{isdn_external}{special_command} = 'AT&F&O2B40';
                            require network::modem;
                            $modem = $netcnx->{isdn_external};
                            return &$ppp_first_step->();
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

                   winmodem => 
                   {
                    pre => sub {
                        my ($in, $netcnx, $mouse, $netc) = @_;
                        my %relocations = (ltmodem => $in->do_pkgs->check_kernel_module_packages('ltmodem'));
                        my $type;
                        
                        detect($netc->{autodetect}, 'lan') if !$::isInstall && !$netc->{autodetection};
                        $netc->{autodetect}{winmodem} or ($in->ask_warn(N("Warning"), N("You don't have any winmodem")) ? return 1 : $in->exit(0));
                        
                        foreach (keys %{$netc->{autodetect}{winmodem}}) {
                            /Hcf/ and $type = "hcfpcimodem";
                            /Hsf/ and $type = "hsflinmodem";
                            /LT/  and $type = "ltmodem";
                            $relocations{$type} || $type && $in->do_pkgs->what_provides($type) or $type = undef;
                        }
                        
                        $type or ($in->ask_warn(N("Warning"), N("Your modem isn't supported by the system.
Take a look at http://www.linmodems.org")) ? return 1 : $in->exit(0));
                        my $e = $in->ask_from_list(N("Title"), N("\"%s\" based winmodem detected, do you want to install needed software ?", $type), [N("Install rpm"), N("Do nothing")]) or return 0;
                        if ($e =~ /rpm/) {
                            if ($in->do_pkgs->install($relocations{$type} ? @{$relocations{$type}} : $type)) {
                                unless ($::isInstall) {
		#- fallback to modem configuration (beware to never allow test it).
                                    $netcnx->{type} = 'modem';
                                    #$type eq 'ltmodem' and $netc->{autodetect}{modem} = '/dev/ttyS14';
                                    return configure($in, $netcnx, $mouse, $netc);
                                }
                            } else {
                                return 0;
                            }
                        }
                        return 1;
                    },
                   },

                   no_winmodem =>
                   {
                    name => N("Warning") . "\n\n" . N("You don't have any winmodem"),
                   },

                   no_supported_winmodem =>
                   {
                    name => N("Warning") . "\n\n" . N("Your modem isn't supported by the system.
Take a look at http://www.linmodems.org")
                   },




                   modem =>
                   {
                    pre => sub {
                        $netcnx->{type} = 'modem';
                        my $modem = $netcnx->{$netcnx->{type}};
                        $modem->{device} = $netc->{autodetect}{modem};
                        my %l = getVarsFromSh("$::prefix/usr/share/config/kppprc");
                        $modem->{connection} = $l{Name};
                        $modem->{domain} = $l{Domain};
                        ($modem->{dns1}, $modem->{dns2}) = split(',', $l{DNS});

                        foreach (cat_("/etc/sysconfig/network-scripts/chat-ppp0")) {
                            /.*ATDT(\d*)/ and $modem->{phone} = $1;
                        }
                        foreach (cat_("/etc/sysconfig/network-scripts/ifcfg-ppp0")) {
                            /NAME=(['"]?)(.*)\1/ and $modem->{login} = $2;
                        }
                        my $secret = network::tools::read_secret_backend();
                        foreach (@$secret) {
                            $modem->{passwd} = $_->{passwd} if $_->{login} eq $modem->{login};
                        }
                        
                        return $ppp_first_step->();
                    },
                   },

                   # FIXME: only if $need_to_ask
                   ppp_choose =>
                   {
                    pre => sub {
                        $mouse ||= {};
                        $mouse->{device} ||= readlink "$::prefix/dev/mouse";
                        write_cnx_script($netc, "modem", join("\n", if_($::testing, "/sbin/route del default"), "ifup ppp0"),
                                         q(ifdown ppp0
killall pppd
), $netcnx->{type});
                        my $need_to_ask = $modem->{device} || !$netc->{autodetect}{winmodem};
                    },
                    
                    name => N("Please choose which serial port your modem is connected to."),
                    interactive_help_id => 'selectSerialPort',
                    data => [ { var => \$modem->{device}, format => \&mouse::serial_port2text, type => "list",
                                list => [ grep { $_ ne $o_mouse->{device} } (if_(-e '/dev/modem', '/dev/modem'), mouse::serial_ports()) ] } ],
                        
                    next => "ppp_choose2",
                   },

                   ppp_choose2 =>
                   {
                    pre => sub {
                        #my $secret = network::tools::read_secret_backend();
                        #my @cnx_list = map { $_->{server} } @$secret;
                    },
                    name => N("Dialup options"), 
                    data => [
                             { label => N("Connection name"), val => \$modem->{connection} },
                             { label => N("Phone number"), val => \$modem->{phone} },
                             { label => N("Login ID"), val => \$modem->{login} },
                             { label => N("Password"), val => \$modem->{passwd}, hidden => 1 },
                             { label => N("Authentication"), val => \$modem->{auth}, list => [ N_("PAP"), N_("Terminal-based"), N_("Script-based"), N_("CHAP") ] },
                             { label => N("Domain name"), val => \$modem->{domain} },
                                                                { label => N("First DNS Server (optional)"), val => \$modem->{dns1} },
                             { label => N("Second DNS Server (optional)"), val => \$modem->{dns2} },
                            ],
                    post => sub {
                        network::modem::ppp_configure($in, $netc, $modem);
                        $netc->{$_} = 'ppp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
                        &$next_cnx_step->();
                    },
                   },
         
         
                   lan => 
                   {
                    pre => sub {
                        detect($netc->{autodetect}, 'lan') if !$::isInstall;
                        modules::interactive::load_category($in, 'network/main|gigabit|usb|pcmcia', !$::expert, 1);
                        @all_cards = network::ethernet::conf_network_card_backend($netc, $intf);
                        @cards = map { $_->[0] } @all_cards;
                        foreach my $card (@all_cards) {
                            modules::remove_alias($card->[1]);
                            modules::add_alias($card->[0], $card->[1]);
                        }
                    },
                    name => N("Select the network interface to configure:"),
                    data =>  [ { label => N("Net Device"), type => "list", val => \$ntf_name, list => [ detect_devices::getNet() ], allow_empty_list => 1 } ],
                    post => sub {
                        delete $ethntf->{$_} foreach keys %$ethntf;
                        add2hash($ethntf, $intf->{$ntf_name});
                        $net_device = $netc->{NET_DEVICE};
                        if ($::isInstall && $net_device eq $ethntf->{DEVICE}) {
                            return 'lan_alrd_cfg';
                        } else {
                            return 'lan_protocol';
                        }
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
                        $module ||= (find { $_->[0] eq $ethntf->{DEVICE} } @all_cards)->[1];
                        $auto_ip = $l10n_lan_protocols{defined $auto_ip ? ($auto_ip ? 'dhcp' : 'static') :$ethntf->{BOOTPROTO}} || 0;
                    },
                    name => sub { 
                        N("Configuring network device %s (driver %s)", $ethntf->{DEVICE}, $module) . "\n\n" .
                          N("The following protocols can be used to configure an ethernet connection. Please choose the one you want to use")
                    },
                    data => sub {
                        [ { val => \$auto_ip, type => "list", list => [ values %l10n_lan_protocols ] } ];
                    },
                    post => sub {
                        $auto_ip = $auto_ip eq N("Automatic IP (BOOTP/DHCP/Zeroconf)") || 0;
                        return 'lan_intf';
                    },
                   },
                   

                   # FIXME: is_install: no return for each card "last step" because of manual popping
                   # better construct an hash of { current_netintf => next_step } which next_step = last_card ? next_eth_step : next_card ?
                   lan_intf => 
                   {
                    pre => sub  {
                        $net_device = $netc->{NET_DEVICE};
                        $onboot = $ethntf->{ONBOOT} ? $ethntf->{ONBOOT} =~ /yes/ : bool2yesno(!member($ethntf->{DEVICE}, 
                                                                                                      map { $_->{device} } detect_devices::pcmcia_probe()));
                        $needhostname = $ethntf->{NEEDHOSTNAME} !~ /no/; 
                        $hotplug = $::isStandalone && !$ethntf->{MII_NOT_SUPPORTED} || 1;
                        $track_network_id = $::isStandalone && $ethntf->{HWADDR} || detect_devices::isLaptop();
                        delete $ethntf->{NETWORK};
                        delete $ethntf->{BROADCAST};
                        @fields = qw(IPADDR NETMASK);
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
                           { text => N("Assign host name from DHCP address"), val => \$needhostname, type => "bool", disabled => sub { ! $auto_ip } },
                           { label => N("DHCP host name"), val => \$ethntf->{DHCP_HOSTNAME}, disabled => sub { ! ($auto_ip && $needhostname) } },
                          )
                          :
                          (
                           { label => N("IP address"), val => \$ethntf->{IPADDR}, disabled => sub { $auto_ip } },
                           { label => N("Netmask"), val => \$ethntf->{NETMASK}, disabled => sub { $auto_ip } },
                          ),
                          { text => N("Track network card id (useful for laptops)"), val => \$track_network_id, type => "bool" },
                          { text => N("Network Hotplugging"), val => \$hotplug, type => "bool" },
                          { text => N("Start at boot"), val => \$onboot, type => "bool" },
                        ],
                    },
                    complete => sub {
                        $ethntf->{BOOTPROTO} = $auto_ip ? "dhcp" : "static";
                        $netc->{DHCP} = $auto_ip;
                        return 0 if $auto_ip;
                        if (my @bad = map_index { if_(!is_ip($ethntf->{$_}), $::i) } @fields) {
                            $in->ask_warn('', N("IP address should be in format 1.2.3.4"));
                            return 1, $bad[0];
                        }
                        $in->ask_warn('', N("Warning : IP address %s is usually reserved !", $ethntf->{IPADDR})) if is_ip_forbidden($ethntf->{IPADDR});
                    },
                    focus_out => sub {
                        $ethntf->{NETMASK} ||= netmask($ethntf->{IPADDR}) unless $_[0]
                    },
                    post => sub {
                        $ethntf->{ONBOOT} = bool2yesno($onboot);
                        $ethntf->{NEEDHOSTNAME} = bool2yesno($needhostname);
                        $ethntf->{MII_NOT_SUPPORTED} = bool2yesno(!$hotplug);
                        $ethntf->{HWADDR} = $track_network_id or delete $ethntf->{HWADDR};

                        #FIXME "wireless" if $ethntf->{wireless_eth};
                        # FIXME: only ask for zeroconf if no dynamic host *AND* no adsl/isdn/modem (aka type being lan|wireless)
                        return is_dynamic_ip($intf) ?
                          (is_dynamic_host($ethntf) ? "dhcp_hostname" : "zeroconf") 
                            : "static_hostname";
                    },
                   },
                   
                   wireless =>
                   {
                    pre => sub {
                        if (is_wireless_intf($module)) {
                            $ethntf->{wireless_eth} = 1;
                            $netc->{wireless_eth} = 1;
                            $ethntf->{WIRELESS_MODE} = "Managed";
                            $ethntf->{WIRELESS_ESSID} = "any";
                        }
                    },
                    name => N("Please enter the wireless parameters for this card:"),
                    data => [
                             { label => N("Operating Mode"), val => \$ethntf->{WIRELESS_MODE}, 
                               list => [ keys %wireless_mode ] },
                             { label => N("Netwok name (ESSID)"), val => \$ethntf->{WIRELESS_ESSID} },
                             { label => N("Network ID"), val => \$ethntf->{WIRELESS_NWID} },
                             { label => N("Operating frequency"), val => \$ethntf->{WIRELESS_FREQ} },
                             { label => N("Sensitivity threshold"), val => \$ethntf->{WIRELESS_SENS} },
                             { label => N("Bitrate (in b/s)"), val => \$ethntf->{WIRELESS_RATE} },
                             { label => N("Encryption key"), val => \$ethntf->{WIRELESS_ENC_KEY} },
                             { label => N("RTS/CTS"), val => \$ethntf->{WIRELESS_RTS},
                               help => N("RTS/CTS adds a handshake before each packet transmission to make sure that the
channel is clear. This adds overhead, but increase performance in case of hidden
nodes or large number of active nodes. This parameters set the size of the
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
                             { label => N("Iwspy command extra arguments"), val => \$ethntf->{WIRELESS_IWSPY}, advanced => 1,
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
                            ],
                    complete => sub {
                        if ($ethntf->{WIRELESS_FREQ} !~ /[0-9.]*[kGM]/) {
                            $in->ask_warn('', N("Freq should have the suffix k, M or G (for example, \"2.46G\" for 2.46 GHz frequency), or add enough '0' (zeroes)."));
                            return 1, 6;
                        }
                        if ($ethntf->{WIRELESS_RATE} !~ /[0-9.]*[kGM]/) {
                            $in->ask_warn('', N("Rate should have the suffix k, M or G (for example, \"11M\" for 11M), or add enough '0' (zeroes)."));
                            return 1, 8;
                        }
                    },
                    post => sub {
                        # untranslate parameters
                        $ethntf->{WIRELESS_MODE} = $wireless_mode{$ethntf->{WIRELESS_MODE}};
                    },
                   },
                   
                   conf_network_card => 
                   {
                    pre => sub {
                        # my ($netc, $intf, $type, $ipadr, $o_netadr) = @_;
                        #-type =static or dhcp
                        modules::interactive::load_category($in, 'network/main|gigabit|usb', !$::expert, 1);
                        @all_cards = conf_network_card_backend($netc, $intf, $type, undef, $ipadr, $netadr) or 
                          # FIXME: fix this
                          $in->ask_warn('', N("No ethernet network adapter has been detected on your system.
I cannot set up this connection type.")), return;
                        
                                         },
                    name => N("Choose the network interface") . "\n\n" .
                    N("Please choose which network adapter you want to use to connect to Internet."),
                    data => [ { var => \$interface, type => "list", list => \@all_cards, } ],
                    format => sub { my ($e) = @_; $e->[0] . ($e->[1] ? " (using module $e->[1])" : "") },
                    
                    post => sub {
                        modules::write_conf() if $::isStandalone;
                        my $_device = conf_network_card_backend($netc, $intf, $type, $interface->[0], $ipadr, $netadr);
                        return "lan";
                    },
                   },
                   
                   static_hostname => 
                   {
                    pre => sub {
                        
                        $netc->{dnsServer} ||= dns($intf->{IPADDR});
                        $gateway_ex = gateway($intf->{IPADDR});
                        #-    $netc->{GATEWAY}   ||= gateway($intf->{IPADDR});
                    },
                    name => N("Please enter your host name.
Your host name should be a fully-qualified host name,
such as ``mybox.mylab.myco.com''.
You may also enter the IP address of the gateway if you have one."),
                    data =>
                    [ { label => N("Host name"), val => \$netc->{HOSTNAME} },
                      { label => N("DNS server 1"),  val => \$netc->{dnsServer} },
                      { label => N("DNS server 2"),  val => \$netc->{dnsServer2} },
                      { label => N("DNS server 3"),  val => \$netc->{dnsServer3} },
                      { label => N("Search domain"), val => \$netc->{DOMAINNAME}, 
                        help => N("By default search domain will be set from the fully-qualified host name") },
                      { label => N("Gateway (e.g. %s)", $gateway_ex), val => \$netc->{GATEWAY} },
                      if_(@devices > 1,
                          { label => N("Gateway device"), val => \$netc->{GATEWAYDEV}, list => \@devices },
                         ),
                    ],
                    complete => sub {
                        if ($netc->{dnsServer} && !is_ip($netc->{dnsServer})) {
                            $in->ask_warn('', N("DNS server address should be in format 1.2.3.4"));
                            return 1;
                        }
                        if ($netc->{GATEWAY} && !is_ip($netc->{GATEWAY})) {
                            $in->ask_warn('', N("Gateway address should be in format 1.2.3.4"));
                            return 1;
                        }
                    },
                    post => $handle_multiple_cnx,
                   },
                   
                   dhcp_hostname => 
                   {
                   },
                   
                   zeroconf => 
                   {
                    name => N("Enter a Zeroconf host name which will be the one that your machine will get back to other machines on the network:"),
                    data => [ { label => N("Zeroconf Host name"), val => \$netc->{ZEROCONF_HOSTNAME} } ],
                    complete => sub {
                        if ($netc->{ZEROCONF_HOSTNAME} =~ /\./) {
                            $in->ask_warn('', N("Zeroconf host name must not contain a ."));
                            return 1;
                        }
                    },
                    post => $handle_multiple_cnx,
                   },
                   
                   multiple_internet_cnx => 
                   {
                    name => N("You have configured multiple ways to connect to the Internet.\nChoose the one you want to use.\n\n") . if_(!$::isStandalone, "You may want to configure some profiles after the installation, in the Mandrake Control Center"),
                    data => [ { label => N("Internet connection"), val => \$netc->{internet_cnx_choice}, 
                                list => [ keys %{$netc->{internet_cnx}} ] } ],
                    post => sub { $::isInstall ? "network_on_boot" : "apply_settings" },
                   },
                   
                   apply_settings => 
                   {
                    name => N("Configuration is complete, do you want to apply settings ?"),
                    type => "yesorno",
                    next => "network_on_boot",
                   },
                   
                   network_on_boot => 
                   {
                    pre => sub {
                        # condition is :
                        member($netc->{internet_cnx_choice}, ('adsl', 'isdn')); # and $netc->{at_boot} = $in->ask_yesorno(N("Network Configuration Wizard"), N("Do you want to start the connection at boot?"));
                    },
                    name => N("Do you want to start the connection at boot?"),
                    type => "yesorno",
                    post => sub {
                        my ($res) = @_;
                        $netc->{at_boot} = $res;
                        if ($netc->{internet_cnx_choice}) {
                            write_cnx_script($netc);
                            $netcnx->{type} = $netc->{internet_cnx}{$netc->{internet_cnx_choice}}{type};
                        } else {
                            unlink "$::prefix/etc/sysconfig/network-scripts/net_cnx_up";
                            unlink "$::prefix/etc/sysconfig/network-scripts/net_cnx_down";
                            undef $netc->{NET_DEVICE};
                        }
                        
                        network::network::configureNetwork2($in, $::prefix, $netc, $intf);
                        $network_configured = 1;
                        $::isInstall ? "restart" : "ask_connect_now";
                    },
                   },

                   restart => 
                   {
                    # FIXME: condition is "if ($netconnect::need_restart_network && $::isStandalone && (!$::expert || $in->ask_yesorno(..."
                               name => N("The network needs to be restarted. Do you want to restart it ?"),
                    # data => [ { label => N("Connection:"), val => \$type, type => 'list', list => [ sort values %l ] }, ],
                    post => sub {
                        if (!$::testing && !run_program::rooted($::prefix, "/etc/rc.d/init.d/network restart")) {
                            $success = 0;
                            $in->ask_okcancel(N("Network Configuration"), 
                                              N("A problem occured while restarting the network: \n\n%s", `/etc/rc.d/init.d/network restart`), 0);
                        }
                        write_initscript();
                        return $::isStandalone && member($netc->{internet_cnx_choice}, qw(modem adsl isdn)) ? "ask_connect_now" : "end";
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
                    output_with_perm("$::prefix$connect_file", 0755, qq(ifup eth0
));
                    output("$::prefix$disconnect_file", 0755, qq(
ifdown eth0
));
                    $direct_net_install = 1;
                    $use_wizard = 0;
                };
          } else {
              $wiz->{pages}{welcome} = $wiz->{pages}{install};
        }
      } else {
          $wiz->{pages}{welcome} = $wiz->{pages}{connection};
      };
      
      if ($use_wizard) {
          require wizards;
          $wiz->{var} = {
                         netc  => $o_netc  || {},
                         mouse => $o_mouse || {},
                         intf  => $o_intf  || {},
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
	$connect_file
fi
);
    } elsif ($netcnx->{type}) {
	$connect_cmd = qq(
#!/bin/bash
if [ -n "\$DISPLAY" ]; then
	/usr/sbin/net_monitor --connect
else
	$connect_file
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
	$connect_file
fi
);
    }
    output_with_perm("$prefix$connect_prog", 0755, $connect_cmd) if $connect_cmd;
    $netcnx->{$_} = $netc->{$_} foreach qw(NET_DEVICE NET_INTERFACE);
    $netcnx->{type} =~ /adsl/ or system("/sbin/chkconfig --del adsl 2> /dev/null");

    if ($::isInstall && $::o->{security} >= 3) {
	require network::drakfirewall;
	network::drakfirewall::main($in, $::o->{security} <= 3);
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
    my $current = { getVarsFromSh("$prefix/etc/netprofile/current") };
    
    $netcnx->{PROFILE} = $current->{PROFILE} || 'default';
    network::network::read_all_conf($prefix, $netc, $intf);
}

sub get_net_device() {
    my $connect_file = "/etc/sysconfig/network-scripts/net_cnx_up";
    my $network_file = "/etc/sysconfig/network";
		if (cat_("$prefix$connect_file") =~ /ifup/) {
  		if_(cat_($connect_file) =~ /^\s*ifup\s+(.*)/m, split(' ', $1))
		} elsif (cat_("$prefix$connect_file") =~ /network/) {
			${{ getVarsFromSh("$prefix$network_file") }}{GATEWAYDEV};
    } elsif (cat_("$prefix$connect_file") =~ /isdn/) {
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
    init_globals($o, $o->{prefix});
    #- give a chance for module to be loaded using kernel-BOOT modules...
    $::isStandalone or modules::load_category('network/main|gigabit|usb');
    run_program::rooted($prefix, $connect_file);
}

sub stop_internet {
    my ($o) = @_;
    init_globals($o, $o->{prefix});
    run_program::rooted($prefix, $disconnect_file);
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
