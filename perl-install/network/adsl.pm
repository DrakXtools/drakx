package network::adsl; # $Id$

use common;
use run_program;
use network::tools;
use modules;
use vars qw(@ISA @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(adsl_conf_backend);

sub adsl_probe_info {
    my ($net) = @_;
    my $pppoe_file = "$::prefix/etc/ppp/pppoe.conf";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (!exists $net->{adsl}{method} || $net->{adsl}{method} eq 'pppoe') && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/ppp0 /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+"([^"]+)"/, $1) } cat_("$::prefix/$_") if !$login && -r "$::prefix/$_";
    }
    my $passwd = network::tools::passwd_by_login($login);
    if (!$net->{adsl}{vpi} && !$net->{adsl}{vci}) {
      ($net->{adsl}{vpi}, $net->{adsl}{vci}) =
	(map { if_(/^.*-vpi\s+(\d+)\s+-vci\s+(\d+)/, map { sprintf("%x", $_) } $1, $2) } cat_("$::prefix/etc/ppp/peers/ppp0"));
    }
    $pppoe_conf{DNS1} ||= '';
    $pppoe_conf{DNS2} ||= '';
    add2hash($net->{resolv}, { dnsServer2 => $pppoe_conf{DNS1}, dnsServer3 => $pppoe_conf{DNS2}, DOMAINNAME2 => '' });
    add2hash($net->{adsl}, { login => $login, passwd => $passwd });
}

sub adsl_detect() {
    require list_modules;
    require detect_devices;
    my @modules = list_modules::category2modules('network/usb_dsl');
    # return an hash compatible with what drakconnect expect us to return:
    my %compat = (
                  'speedtch'  => 'speedtouch',
                  'eagle-usb' => 'sagem',
                 );

    return {
            bewan => [ detect_devices::getBewan() ],
            eci   => [ detect_devices::getECI() ],
            map { $compat{$_} || $_ => [ detect_devices::matching_driver($_) ] } @modules,
        };
}

sub sagem_set_parameters {
    my ($net) = @_;
    my %l = map { $_ => sprintf("%08s", $net->{adsl}{$_}) } qw(vci vpi Encapsulation);

    my $static_ip =  $net->{adsl}{method} eq 'static' && $net->{ifcfg}{sagem}{IPADDR};
    foreach my $cfg_file (qw(/etc/analog/adiusbadsl.conf /etc/eagle-usb/eagle-usb.conf)) {
        substInFile {
            s/Linetype=.*\n/Linetype=0000000A\n/; #- use CMVs
            s/VCI=.*\n/VCI=$l{vci}\n/;
            s/VPI=.*\n/VPI=$l{vpi}\n/;
            s/Encapsulation=.*\n/Encapsulation=$l{Encapsulation}\n/;
            s/ISP=.*\n/ISP=$net->{adsl}{provider_id}\n/;
            s/STATIC_IP=.*\n//;
            s!</eaglectrl>!STATIC_IP=$static_ip\n</eaglectrl>! if $static_ip;
        } "$::prefix$cfg_file";
    }
    #- create CMV symlinks for both POTS and ISDN lines
    foreach my $type (qw(p i)) {
        my $cmv;
        my ($country) = $net->{adsl}{provider_id} =~ /^([a-zA-Z]+)\d+$/;
        #- try to find a CMV for this specific ISP
        $cmv = "$::prefix/etc/eagle-usb/CMVe${type}$net->{adsl}{provider_id}.txt" if $net->{adsl}{provider_id};
        #- if not found, try to found a CMV for the country
        -f $cmv or $cmv = "$::prefix/etc/eagle-usb/CMVe${type}${country}.txt";
        #- fallback on the generic CMV if no other matched
        -f $cmv or $cmv = "$::prefix/etc/eagle-usb/CMVe${type}WO.txt";
        symlinkf($cmv, "$::prefix/etc/eagle-usb/CMVe${type}.txt");
    }
    #- remove this otherwise eaglectrl won't start
    unlink("$::prefix/etc/eagle-usb/eagle-usb_must_be_configured");
}

sub adsl_conf_backend {
    my ($in, $modules_conf, $net) = @_;

    my $bewan_module;
    $bewan_module = $net->{adsl}{bus} eq 'PCI' ? 'unicorn_pci_atm' : 'unicorn_usb_atm' if $net->{adsl}{device} eq "bewan";

    my $adsl_type = $net->{adsl}{method};
    my $adsl_device = $net->{adsl}{device};

    # all supported modems came with their own pppoa module, so no need for "plugin pppoatm.so"
    my %modems =
      (
       bewan =>
       {
        start => qq(
#  ActivationMode=1
modprobe $bewan_module
# wait for the modem to be set up:
sleep 10
),
        stop => qq(modprobe -r $bewan_module),
        plugin => {
                             pppoa => "pppoatm.so " . join('.', hex($net->{adsl}{vpi}), hex($net->{adsl}{vci}))
                  },
        ppp_options => qq(
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
                   pppoa => "pppoatm.so " . join('.', hex($net->{adsl}{vpi}), hex($net->{adsl}{vci})),
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
        start => 'grep -qs eagle-usb /var/run/usb/* || /sbin/eaglectrl -d',
        stop =>  "/usr/bin/killall pppoa",
        get_intf => '/sbin/eaglectrl -i',
        server => {
                   pppoa => q("/sbin/fctStartAdsl -t 1 -i"),
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
                   pppoe => qq("/usr/bin/pppoeci -v 1 -vpi $net->{adsl}{vpi} -vci $net->{adsl}{vci}"),
                  },
        ppp_options => qq(
noipdefault
sync
noaccomp
linkname eciadsl
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

    my %generic =
      (
       pppoe =>
       {
        server => '"pppoe -I ' . ($modems{$adsl_device}{get_intf} ? "`$modems{$adsl_device}{get_intf}`" : $net->{adsl}{ethernet_device}) . '"',
        ppp_options => qq(default-asyncmap
mru 1492
mtu 1492
noaccomp
noccp
nobsdcomp
novjccomp
nodeflate
lcp-echo-interval 20
lcp-echo-failure 3
),
       }
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

	my $pty_option =
          exists $modems{$adsl_device}{server}{$adsl_type} ? "pty $modems{$adsl_device}{server}{$adsl_type}" :
          exists $generic{$adsl_type}{server} ? "pty $generic{$adsl_type}{server}" :
          "";
	my $plugin = exists $modems{$adsl_device}{plugin}{$adsl_type} && "plugin $modems{$adsl_device}{plugin}{$adsl_type}";
	my $noipdefault = $adsl_type eq 'pptp' ? '' : 'noipdefault';
	my $ppp_options =
          exists $modems{$adsl_device}{ppp_options} ? $modems{$adsl_device}{ppp_options} :
          exists $generic{$adsl_type}{ppp_options} ? $generic{$adsl_type}{ppp_options} :
          "";
	output("$::prefix/etc/ppp/peers/ppp0",
qq(lock
persist
noauth
usepeerdns
defaultroute
$noipdefault
$ppp_options
kdebug 1
nopcomp
noccp
novj
holdoff 4
maxfail 25
$pty_option
$plugin
user "$net->{adsl}{login}"
));

        network::tools::write_secret_backend($net->{adsl}{login}, $net->{adsl}{passwd});

	my $ethernet_device = $net->{adsl}{ethernet_device};
	if ($ethernet_device =~ /^eth/) {
            $net->{ifcfg}{$ethernet_device} = {
                                   DEVICE => $ethernet_device,
                                   BOOTPROTO => 'none',
                                   NETMASK => '255.255.255.0',
                                   NETWORK => '10.0.0.0',
                                   BROADCAST => '10.0.0.255',
                                   ONBOOT => 'yes',
                                  };
        }
    }

    #- FIXME: ppp0 and ippp0 are hardcoded
    my $metric = network::tools::get_default_metric("adsl"); #- FIXME, do not override if already set
    put_in_hash($net->{ifcfg}{ppp0}, {
				      DEVICE => 'ppp0',
				      TYPE => 'ADSL',
				      METRIC => $metric,
				     }) unless member($adsl_type, qw(static dhcp));

    #- remove file used with sagem for dhcp/static connections
    unlink("$::prefix/etc/sysconfig/network-scripts/ifcfg-sagem");

    #- set vpi, vci and encapsulation parameters for sagem
    $adsl_device eq 'sagem' and sagem_set_parameters($net);

    #- set aliases
    if (exists $modems{$adsl_device}{aliases}) {
        $modules_conf->set_alias($_->[0], $_->[1]) foreach @{$modems{$adsl_device}{aliases}};
        $::isStandalone and $modules_conf->write;
    }
    #- remove the "speedtch off" alias that was written by Mandrakelinux 10.0
    $adsl_device eq 'speedtouch' and $modules_conf->remove_alias('speedtch');

    if ($adsl_type eq "capi") {
        require network::isdn;
        network::isdn::setup_capi_conf($in, $net->{adsl}{capi_card});
        services::disable('isdn4linux');
        services::enable('capi4linux');

        #- install and run drdsl for dsl connections, once capi driver is loaded
        $in->do_pkgs->ensure_is_installed_if_available("drdsl", "/usr/sbin/drdsl");
        run_program::rooted($::prefix, "/usr/sbin/drdsl");
    }

    #- load modules and run modem-specific start programs
    #- useful during install, or in case the packages have been installed after the device has been plugged
    my @modules = (@{$modems{$adsl_device}{modules}}, map { $_->[1] } @{$modems{$adsl_device}{aliases}});
    @modules or @modules = qw(ppp_synctty ppp_async ppp_generic n_hdlc); #- required for pppoe/pptp connections
    #- pppoa connections need the pppoatm module
    #- pppd should run "modprobe pppoatm", but it will fail during install
    push @modules, 'pppoatm' if $adsl_type = 'pppoa';
    foreach (@modules) {
        eval { modules::load($_) } or log::l("failed to load $_ module: $@");
    }
    $modems{$adsl_device}{start} and run_program::rooted($::prefix, $modems{$adsl_device}{start});
}

1;
