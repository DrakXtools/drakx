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
	     'pppoe' =>  N("use pppoe"),
	     'pptp'  =>  N("use pptp"),
	     'dhcp'  =>  N("use dhcp"),
	     'speedtouch' => N("Alcatel speedtouch usb") . if_($netc->{autodetect}{adsl}{speedtouch}, N(" - detected")),
	     'sagem' =>  N("Sagem (using pppoa) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
	     'sagem_dhcp' =>  N("Sagem (using dhcp) usb") . if_($netc->{autodetect}{adsl}{sagem}, N(" - detected")),
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
Some connections use pptp, a few use dhcp.
If you don't know, choose 'use pppoe'"),
                       data =>  [
                                 {
                                  label => N("ADSL connection type :"), val => \$wiz->{var}{adsl}{type}, list => [ sort values %l ] },
                                ],
                       pre => sub {
                           $wiz->{var}{adsl}{type} = $l{sagem}; # debug
                           $wiz->{var}{adsl}{type} ||= find { $netc->{autodetect}{adsl}{$_} } keys %l;
                           print "\n\ntype is �$wiz->{var}{adsl}{type}�\n\n";
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
};

sub adsl_probe_info {
    my ($adsl, $netc, $adsl_type, $adsl_modem) = @_;
    my $pppoe_file = "$::prefix/etc/ppp/pppoe.conf";
    my $pptp_file = "$::prefix/etc/sysconfig/network-scripts/net_cnx_up";
    my %pppoe_conf; %pppoe_conf = getVarsFromSh($pppoe_file) if (! defined $adsl_type || $adsl_type eq 'pppoe') && -f $pppoe_file;
    my $login = $pppoe_conf{USER};
    foreach (qw(/etc/ppp/peers/adsl /etc/ppp/options /etc/ppp/options.adsl)) {
	($login) = map { if_(/^user\s+"([^"]+)"/, $1) } cat_("$::prefix/$_") if !$login && -r "$::prefix/$_";
    }
    ($login) = map { if_(/\sname\s+([^ \n]+)/, $1) } cat_($pptp_file) if (! defined $adsl_type || $adsl_type eq 'pptp') && -r $pptp_file;
    my $passwd = passwd_by_login($login);
    ($netc->{vpi}, $netc->{vci}) ||= 
      map { if_(/^.*-vpi\s+(\d+)\s+-vci\s+(\d+)/, $1, $2) } cat_("$::prefix/etc/ppp/peers/adsl") if member($adsl_modem, qw(eci speedtouch));
    $pppoe_conf{DNS1} ||= '';
    $pppoe_conf{DNS2} ||= '';
    add2hash($netc, { dnsServer2 => $pppoe_conf{DNS1}, dnsServer3 => $pppoe_conf{DNS2}, DOMAINNAME2 => '' });
    add2hash($adsl, { login => $login, passwd => $passwd, passwd2 => '' });
}

sub adsl_detect() {
    my $adsl = {};
    require detect_devices;
    ($adsl->{bewan}) = detect_devices::getBewan();
    ($adsl->{speedtouch}) = detect_devices::getSpeedtouch();
    ($adsl->{sagem}) = detect_devices::getSagem();
    ($adsl->{eci}) = detect_devices::getECI();
    return $adsl;
}

sub adsl_conf_backend {
    my ($in, $adsl, $netc, $adsl_device, $adsl_type, $o_netcnx) = @_;
    # FIXME: should not be needed:
    defined $o_netcnx and $netc->{adsltype} = $o_netcnx->{type};
    $netc->{adsltype} ||= "adsl_$adsl_type";

    # all supported modems came with their own pppoa module, so no need for "plugin pppoatm.so"
    my %modems = (
                  speedtouch =>
                  {
                   start => '/usr/sbin/modem_run -v 0 -f /usr/share/speedtouch/mgmt.o',
                   overide_script => 1,
                   server => {
                              pppoa => '"/usr/sbin/pppoa3 -e 1 -c -vpi ' . hex($netc->{vpi}) . " -vci " . hex($netc->{vci}) . '"',
                             },
                   ppp_options => qq(
sync
noaccomp),
                   aliases => [
                               ['speedtch', 'off'], # disable kernel driver, we use userland stuff but for firmware upload
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
                   start => "/usr/sbin/eaglectrl -w",
                   get_intf => "/usr/sbin/eaglectrl -i",
                   server => {
                              pppoa => qq("/usr/sbin/pppoa -I `/usr/sbin/eaglectrl -s; /usr/sbin/eaglectrl -i`"),
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
                               ['tty-ldisc-14', 'ppp_synctty'],
                               ['tty-ldisc-13', 'n_hdlc']
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
                 );


    if ($adsl_type =~ /^pp/) {
        mkdir_p("$::prefix/etc/ppp");
        $in->do_pkgs->install('ppp') if !$>;
        my %packages = (
                        pppoa => [ qw(ppp-pppoatm) ],
                        pppoe => [ qw(ppp-pppoe rp-pppoe) ],
                        pptp  => [ qw(pptp-linux pptp-adsl) ],
                       );
        $in->do_pkgs->install(@{$packages{$adsl_type}}) if !$>;
        output("$::prefix/etc/ppp/options",
               qq(lock
noipdefault
persist
noauth
usepeerdns
defaultroute)
              );
        
	output("$::prefix/etc/ppp/peers/adsl",
qq(noauth
noipdefault
pty $modems{$adsl_device}{server}{$adsl_type}
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
user "$adsl->{login}"
));

        write_secret_backend($adsl->{login}, $adsl->{passwd});
        
        if ($adsl_type eq 'pppoe') {
            substInFile {
                s/ETH=.*\n/ETH=$netc->{NET_DEVICE}\n/;
                s/USER=.*\n/USER=$adsl->{login}\n/;
                s/DNS1=.*\n/DNS1=$netc->{dnsServer2}\n/;
                s/DNS2=.*\n/DNS2=$netc->{dnsServer3}\n/;
            } "$::prefix/etc/ppp/pppoe.conf";
        }

        my %ppp_options = 
          (
           pptp => {
                    connect => "/usr/bin/pptp 10.0.0.138 name $adsl->{login}",
                    disconnect => "/usr/bin/killall pptp pppd\n",
                   },

           pppoe => {
                     # we do not call directly pppd, rp-pppoe take care of "plugin rp-pppoe.so" peers option and the like
                     connect => "LC_ALL=C LANG=C LANGUAGE=C LC_MESSAGES=C /usr/sbin/adsl-start $netc->{NET_DEVICE} $adsl->{login}",
                     disconnect => qq(/usr/sbin/adsl-stop
/usr/bin/killall pppoe pppd\n),
                    },

           pppoa => {
                     disconnect => qq(/usr/sbin/adsl-stop
/usr/bin/killall pppoe pppd\n),
                    },
          );
        set_cnx_script($netc, "adsl", join("\n",
                                             "/sbin/route del default",
                                             $modems{$adsl_device}{start},
                                             # /usr/sbin/pppd call adsl
                                             #$modems{$adsl_device}{server}{$adsl_type} ||
					     "/usr/sbin/pppd file /etc/ppp/peers/adsl",
                                             $ppp_options{$adsl_type}{connect}
                                            ),
                         $ppp_options{$adsl_type}{disconnect},
                         $netc->{adsltype}
                        );

    } elsif ($adsl_type eq 'dhcp') {
        set_cnx_script($netc, 'adsl',
                         qq(
/sbin/route del default
#$modems{$adsl_device}{start}
INTERFACE=`$modems{$adsl_device}{get_intf}`
/sbin/dhcpcd \$INTERFACE
#/sbin/ifconfig \$INTERFACE 192.168.60.30 netmask 255.255.255.0 up
/usr/sbin/pppd file /etc/ppp/peers/adsl\n),
                         qq(
INTERFACE=`$modems{$adsl_device}{get_intf}`
/sbin/ifdown \$INTERFACE\n"),
                         $netc->{adsltype});
    } elsif ($adsl_type eq 'static') {
        # TODO: handle manually configured (new feature)
        set_cnx_script($netc, 'adsl',
                         qq(
/sbin/route del default
#$modems{$adsl_device}{start}
INTERFACE=`$modems{$adsl_device}{get_intf}`
/sbin/ifconfig \$INTERFACE 192.168.60.30 netmask 255.255.255.0 up
/usr/sbin/pppd file /etc/ppp/peers/adsl\n),
                         qq(
INTERFACE=`$modems{$adsl_device}{get_intf}`
/sbin/ifdown \$INTERFACE\n"),
                         $netc->{adsltype});
    }


    # sagem specific stuff
    if ($adsl_device eq 'sagem') {
        my %l = map { $_ => sprintf("%08s", $netc->{$_}) } qw(vci vpi Encapsulation);
        # set vpi and vci parameters for sagem
        foreach my $cfg_file (qw(/etc/analog/adiusbadsl.conf /etc/eagle-usb/eagle-usb.conf)) {
            substInFile {
                s/VCI=.*\n/VCI=$l{vci}\n/;
                s/VPI=.*\n/VPI=$l{vpi}\n/;
                s/Encapsulation=.*\n/Encapsulation=$l{Encapsulation}\n/;
            } "$::prefix$cfg_file";
        }
    } elsif ($adsl_device eq 'speedtouch') {
        # speedtouch really is used only with pppoa, let its own script handle firmware upload and the like:
        set_cnx_script($netc, 'adsl', 
                         qq(/sbin/route del default
/usr/share/speedtouch/speedtouch.sh start\n),
                         "/usr/share/speedtouch/speedtouch.sh stop\n",
                         $netc->{adsltype});
    }


    # set aliases:
    if (exists $modems{$adsl_device}{aliases}) {
        modules::add_alias($_->[0], $_->[1]) foreach @{$modems{$adsl_device}{aliases}};
        $::isStandalone and modules::write_conf();
    }

    $netc->{NET_INTERFACE} = 'ppp0';
    write_cnx_script($netc);
}

1;
