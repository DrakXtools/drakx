package network::adsl; # $Id$

use common;
use run_program;
use network::tools;
use network::ethernet;
use modules;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_conf_backend);


sub get_wizard {
    my ($wiz) = @_;
    my $netc = $wiz->{var}{netc};

    my %l = (
	     'pppoe' =>  N("use PPPoE"),
	     'pptp'  =>  N("use PPTP"),
	     'dhcp'  =>  N("use DHCP"),
	     'speedtouch' => N("Alcatel Speedtouch USB") . if_($netc->{autodetect}{adsl}{speedtouch}, N(" - detected")),
	     'sagem' =>  N("Sagem (using PPPoA) USB") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
	     'sagem_dhcp' =>  N("Sagem (using DHCP) USB") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
          # 'eci' => N("ECI Hi-Focus"), # this one needs eci agreement
	    );
    
    $wiz->{var}{adsl} = {
                         connection_list => \%l,
                         type => "",
                        };
    add2hash($wiz->{pages},
             {
              adsl_old => {
                       name => N("Connect to the Internet") . "\n\n" .
                       N("The most common way to connect with adsl is pppoe.
Some connections use PPTP, a few use DHCP.
If you do not know, choose 'use PPPoE'"),
                       data =>  [
                                 {
                                  label => N("ADSL connection type:"), val => \$wiz->{var}{adsl}{type}, list => [ sort values %l ] },
                                ],
                       pre => sub {
                           $wiz->{var}{adsl}{type} = $l{sagem}; # debug
                           $wiz->{var}{adsl}{type} ||= find { $netc->{autodetect}{adsl}{$_} } keys %l;
                           print "\n\ntype is «$wiz->{var}{adsl}{type}»\n\n";
                       },
                       post => sub {
                           $wiz->{var}{adsl}{type} = find { $l{$_} eq $wiz->{var}{adsl}{type} } keys %l;
                           my $adsl   = $wiz->{var}{adsl}{connection};
                           my $type   = $wiz->{var}{adsl}{type};
                           my $netcnx = $wiz->{var}{netcnx};
                           $netcnx->{type} = "adsl_$type";
                                         
                           $netcnx->{"adsl_$type"} = {};
                           $netcnx->{"adsl_$type"}{vpivci} = '' if $type =~ /eci|speedtouch/;
                           return 'ethernet' if $type eq 'dhcp';
                           adsl_probe_info($adsl, $netc, $type);
                           # my ($adsl, $netc, $intf, $adsl_type) = @_;
                           # ask_info2($adsl, $netc);
                           return "hw_account";
                       },
                      },
             });
}

sub adsl_probe_info {
    my ($adsl, $netc, $adsl_type, $o_adsl_modem) = @_;
    my $pppoe_file = "$::prefix/etc/ppp/pppoe.conf";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (! defined $adsl_type || $adsl_type eq 'pppoe') && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/ppp0 /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+"([^"]+)"/, $1) } cat_("$::prefix/$_") if !$login && -r "$::prefix/$_";
    }
    my $passwd = passwd_by_login($login);
    if (!$netc->{vpi} && !$netc->{vci} && member($o_adsl_modem, qw(eci speedtouch))) {
      ($netc->{vpi}, $netc->{vci}) = 
	(map { if_(/^.*-vpi\s+(\d+)\s+-vci\s+(\d+)/, map { sprintf("%x", $_) } $1, $2) } cat_("$::prefix/etc/ppp/peers/ppp0"));
    }
    $pppoe_conf{DNS1} ||= '';
    $pppoe_conf{DNS2} ||= '';
    add2hash($netc, { dnsServer2 => $pppoe_conf{DNS1}, dnsServer3 => $pppoe_conf{DNS2}, DOMAINNAME2 => '' });
    add2hash($adsl, { login => $login, passwd => $passwd, passwd2 => '' });
}

sub adsl_detect() {
    my $adsl = {};
    require detect_devices;
    @{$adsl->{bewan}} = detect_devices::getBewan();
    @{$adsl->{speedtouch}} = detect_devices::getSpeedtouch();
    @{$adsl->{sagem}} = detect_devices::getSagem();
    @{$adsl->{eci}} = detect_devices::getECI();
    return $adsl;
}

sub sagem_set_parameters {
    my ($netc) = @_;
    my %l = map { $_ => sprintf("%08s", $netc->{$_}) } qw(vci vpi Encapsulation);
    foreach my $cfg_file (qw(/etc/analog/adiusbadsl.conf /etc/eagle-usb/eagle-usb.conf)) {
        substInFile {
            s/Linetype=.*\n/Linetype=0000000A\n/; #- use CMVs
            s/VCI=.*\n/VCI=$l{vci}\n/;
            s/VPI=.*\n/VPI=$l{vpi}\n/;
            s/Encapsulation=.*\n/Encapsulation=$l{Encapsulation}\n/;
            s/STATIC_IP=.*\n//;
            s!</eaglectrl>!STATIC_IP=$netc->{static_ip}\n</eaglectrl>! if $netc->{static_ip};
        } "$::prefix$cfg_file";
    }
    #- create CMV symlinks for both POTS and ISDN lines
    foreach my $type (qw(p i)) {
        my $cmv;
        $cmv = "$::prefix/etc/eagle-usb/CMVe${type}$netc->{provider_id}.txt" if $netc->{provider_id};
        -f $cmv or $cmv = "$::prefix/etc/eagle-usb/CMVe${type}WO.txt";
        symlinkf($cmv, "$::prefix/etc/eagle-usb/CMVe${type}.txt");
    }
    #- remove this otherwise eaglectrl won't start
    unlink("$::prefix/etc/eagle-usb/eagle-usb_must_be_configured");
}

sub adsl_conf_backend {
    my ($in, $modules_conf, $adsl, $netc, $intf, $adsl_device, $adsl_type, $o_netcnx) = @_;
    # FIXME: should not be needed:
    defined $o_netcnx and $netc->{adsltype} = $o_netcnx->{type};
    $netc->{adsltype} ||= "adsl_$adsl_type";
    $adsl_type eq 'pptp' and $adsl_device = 'pptp_modem';
    $adsl_type eq 'capi' and $adsl_device = 'capi_modem';
    my $bewan_module;
    $bewan_module = $o_netcnx->{bus} eq 'PCI' ? 'unicorn_pci_atm' : 'unicorn_usb_atm' if $adsl_device eq "bewan";  

    # all supported modems came with their own pppoa module, so no need for "plugin pppoatm.so"
    my %modems = (
                  bewan => {
                  start => qq(
modprobe pppoatm
#  ActivationMode=1
modprobe $bewan_module
# wait for the modem to be set up:
sleep 10
),
                  stop => qq(modprobe -r $bewan_module),
                  plugin => {
                             pppoa => "pppoatm.so " . join('.', hex($netc->{vpi}), hex($netc->{vci}))
                            },
                  ppp_options => qq(
lock 
ipparam ppp0 
default-asyncmap 
hide-password 
noaccomp 
nobsdcomp 
nodeflate 
novj novjccomp 
lcp-echo-interval 20 
lcp-echo-failure 3 
sync 
),
                  },

                  speedtouch =>
                  {
                   modules => [ qw(speedtch) ],
                   start => '/usr/bin/speedtouch-start --nocall',
                   overide_script => 1,
                   server => {
                              pppoa => qq("/usr/sbin/pppoa3 -c")
                             },
                   plugin => {
                              pppoa => "pppoatm.so " . join('.', hex($netc->{vpi}), hex($netc->{vci})),
                             },
                   ppp_options => qq(
sync
noaccomp),
                   aliases => [
                               ['char-major-108', 'ppp_generic'],
                               ['tty-ldisc-3', 'ppp_async'],
                               ['tty-ldisc-13', 'n_hdlc'],
                               ['tty-ldisc-14', 'ppp_synctty'],
                               ['ppp-compress-21', 'bsd_comp'],
                               ['ppp-compress-24', 'ppp_deflate'],
                               ['ppp-compress-26', 'ppp_deflate']
                              ],
                  },
                  sagem =>
                  {
                   modules => [ qw(eagle-usb) ],
                   start => '/sbin/eaglectrl -d',
                   stop =>  "/usr/bin/killall pppoa",
                   get_intf => '/sbin/eaglectrl -i',
                   server => {
                              pppoa => q("/usr/sbin/fctStartAdsl -t 1 -i"),
                             },
                   ppp_options => qq(
mru 1492
mtu 1492
nobsdcomp
nodeflate
noaccomp -am
novjccomp),
                   aliases => [
                               ['char-major-108', 'ppp_generic'],
                               ['tty-ldisc-3', 'ppp_async'],
                               ['tty-ldisc-13', 'n_hdlc'],
                               ['tty-ldisc-14', 'ppp_synctty']
                              ],
                  },
                  eci =>
                  {
                   start => '/usr/bin/startmodem',
                   server => {
                              pppoe => qq("/usr/bin/pppoeci -v 1 -vpi $netc->{vpi} -vci $netc->{vci}"),
                             },
                   ppp_options => qq(
noipdefault
sync
noaccomp
linkname eciadsl
noauth
lcp-echo-interval 0)
                  },
                  pptp_modem =>
                  {
                   server => {
                              pptp => qq("/usr/sbin/pptp 10.0.0.138 --nolaunchpppd"),
                             },
                  },
                  capi_modem =>
                  {
                   ppp_options => qq(
connect /bin/true
ipcp-accept-remote
ipcp-accept-local

sync
noauth
lcp-echo-interval 5
lcp-echo-failure 3
lcp-max-configure 50
lcp-max-terminate 2

noccp
noipx
mru 1492
mtu 1492),
                   plugin => {
                              capi => qq(capiplugin.so
avmadsl)
                             },
                  },
                 );


    if ($adsl_type =~ /^pp|^capi$/) {
        mkdir_p("$::prefix/etc/ppp");
        $in->do_pkgs->install('ppp') if !$>;
        my %packages = (
                        pppoa => [ qw(ppp-pppoatm) ],
                        pppoe => [ qw(ppp-pppoe rp-pppoe) ],
                        pptp  => [ qw(pptp-linux) ],
                        capi => [ qw(isdn4k-utils) ], #- capi4linux service
                       );
        $in->do_pkgs->install(@{$packages{$adsl_type}}) if !$>;
        output("$::prefix/etc/ppp/options",
               $adsl_device eq "bewan" ?
               qq(lock
ipparam ppp0
noipdefault
noauth
default-asyncmap
defaultroute
hide-password
noaccomp
noccp
nobsdcomp
nodeflate
nopcomp
novj novjccomp
lcp-echo-interval 20
lcp-echo-failure 3
sync
persist
user $adsl->{login}
name $adsl->{login}
usepeerdns
)
               :
               qq(lock
noipdefault
persist
noauth
usepeerdns
defaultroute)
              );
        
	my $pty_option = $modems{$adsl_device}{server}{$adsl_type} && "pty $modems{$adsl_device}{server}{$adsl_type}";
	my $plugin = $modems{$adsl_device}{plugin}{$adsl_type} && "plugin $modems{$adsl_device}{plugin}{$adsl_type}";
	my $noipdefault = $adsl_type eq 'pptp' ? '' : 'noipdefault';
	output("$::prefix/etc/ppp/peers/ppp0",
qq(noauth
$noipdefault
$modems{$adsl_device}{ppp_options}
kdebug 1
nopcomp
noccp
novj
holdoff 4
maxfail 25
persist
usepeerdns
defaultroute
$pty_option
$plugin
user "$adsl->{login}"
));

        write_secret_backend($adsl->{login}, $adsl->{passwd});

        if ($netc->{NET_DEVICE} =~ /^eth/) {
            my $net_device = $netc->{NET_DEVICE};
            $intf->{$net_device} = {
                                   DEVICE => $net_device,
                                   BOOTPROTO => 'none',
                                   NETMASK => '255.255.255.0',
                                   NETWORK => '10.0.0.0',
                                   BROADCAST => '10.0.0.255',
                                   ONBOOT => 'yes',
                                  };
        }

        if ($adsl_type eq 'pppoe') {
            if (-f "$::prefix/etc/ppp/pppoe.conf") {
                my $net_device = $modems{$adsl_device}{get_intf} ? "`$modems{$adsl_device}{get_intf}`" : $netc->{NET_DEVICE};
                substInFile {
                    s/ETH=.*\n/ETH=$net_device\n/;
                    s/USER=.*\n/USER=$adsl->{login}\n/;
                    s/DNS1=.*\n/DNS1=$netc->{dnsServer2}\n/;
                    s/DNS2=.*\n/DNS2=$netc->{dnsServer3}\n/;
                } "$::prefix/etc/ppp/pppoe.conf";
            } else {
                log::l("can not find pppoe.conf, make sure the rp-pppoe package is installed");
            }
        }

#            pppoe => {
#                      # we do not call directly pppd, rp-pppoe take care of "plugin rp-pppoe.so" peers option and the like
#                      connect => "LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C /usr/sbin/adsl-start",
#                      disconnect => qq(/usr/sbin/adsl-stop
# /usr/bin/killall pppoe pppd\n),
#                     },

    }

    #- FIXME: 
    #-   ppp0 and ippp0 are hardcoded
    my $kind = $adsl_type eq 'pppoe' ? 'xDSL' : 'ADSL';
    my $metric = network::tools::get_default_metric("adsl"); #- FIXME, do not override if already set
    output_with_perm("$::prefix/etc/sysconfig/network-scripts/ifcfg-ppp0", 0705, qq(DEVICE=ppp0
ONBOOT=no
TYPE=$kind
METRIC=$metric
)) unless member($adsl_type, qw(manual dhcp));

    #- remove file used with sagem for dhcp/static connections
    unlink("$::prefix/etc/sysconfig/network-scripts/ifcfg-sagem");

    #- set vpi, vci and encapsulation parameters for sagem
    if ($adsl_device eq 'sagem') {
	$netc->{static_ip} = $intf->{sagem}{IPADDR} if $adsl_type eq 'manual';
	sagem_set_parameters($netc);
    }

    #- set aliases
    if (exists $modems{$adsl_device}{aliases}) {
        $modules_conf->set_alias($_->[0], $_->[1]) foreach @{$modems{$adsl_device}{aliases}};
        $::isStandalone and $modules_conf->write;
    }
    #- remove the "speedtch off" alias that was written by Mandrakelinux 10.0
    $adsl_device eq 'speedtouch' and $modules_conf->remove_alias('speedtch');

    if ($adsl_type eq "capi") {
        require network::isdn;
        network::isdn::setup_capi_conf($adsl->{capi});
        services::stop("isdn4linux");
        services::do_not_start_service_on_boot("isdn4linux");
        services::start_service_on_boot("capi4linux");
        services::start("capi4linux");

        #- install and run drdsl for dsl connections, once capi driver is loaded
        $in->do_pkgs->ensure_is_installed_if_available("drdsl", "/usr/sbin/drdsl");
        run_program::rooted($::prefix, "/usr/sbin/drdsl");
    }

    #- load modules and run modem-specific start programs
    #- useful during install, or in case the packages have been installed after the device has been plugged
    my @modules = (@{$modems{$adsl_device}{modules}}, map { $_->[1] } @{$modems{$adsl_device}{aliases}});
    @modules or @modules = qw(ppp_synctty ppp_async ppp_generic n_hdlc); #- required for pppoe/pptp connections
    @modules && eval { modules::load(@modules) }
      or log::l("failed to load " . join(',', @modules), " modules: $@");
    $modems{$adsl_device}{start} and run_program::rooted($::prefix, $modems{$adsl_device}{start});
}

1;
