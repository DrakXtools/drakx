package network::modem;

use common;
use any;
use modules;
use detect_devices;
use mouse;
use network::tools;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix);

@ISA = qw(Exporter);
@EXPORT = qw(pppConfig modem_detect_backend);

sub configure{
    my ($netcnx, $mouse, $netc) = @_;
    $netcnx->{type}='modem';
    $netcnx->{$netcnx->{type}}={};
    $netcnx->{modem}{device}=$netc->{autodetect}{modem};
  modem_step_1:
    pppConfig($netcnx->{$netcnx->{type}}, $mouse, $netc) or return;
    write_cnx_script($netc, "modem",
q(
/sbin/route del default
ifup ppp0
),
q(ifdown ppp0
killall pppd
), $netcnx->{type});
    1;
}

sub pppConfig {
    my ($modem, $mouse, $netc) = @_;

    $mouse ||={};
    $mouse->{device} ||= readlink "$prefix/dev/mouse";
    $::isInstall and $in->set_help('selectSerialPort');
    $modem->{device} ||= $in->ask_from_listf('', _("Please choose which serial port your modem is connected to."),
					     \&mouse::serial_port2text,
					     [ grep { $_ ne $mouse->{device} } (mouse::serial_ports, if_(-e '/dev/modem', '/dev/modem')) ]) || return;

    $::isStandalone || $in->set_help('configureNetworkISP');
    $in->ask_from('', _("Dialup options"), [
{ label => _("Connection name"), val => \$modem->{connection} },
{ label => _("Phone number"), val => \$modem->{phone} },
{ label => _("Login ID"), val => \$modem->{login} },
{ label => _("Password"), val => \$modem->{passwd}, hidden => 1 },
{ label => _("Authentication"), val => \$modem->{auth}, list => [ __("PAP"), __("Terminal-based"), __("Script-based"), __("CHAP") ] },
{ label => _("Domain name"), val => \$modem->{domain} },
{ label => _("First DNS Server (optional)"), val => \$modem->{dns1} },
{ label => _("Second DNS Server (optional)"), val => \$modem->{dns2} },
    ]) or return;
    $netc->{DOMAINNAME2} = $modem->{domain};
    any::pppConfig($in, $modem, $prefix);
    $netc->{$_}='ppp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
    1;
}
#-AT&F&O2B40
#- DialString=ATDT0231389595((

#- modem_detect_backend : detects modem on serial ports and fills the infos in $modem : detects only one card
#- input
#-  $modem
#-  $mouse : facultative, hash containing device to exclude not to test mouse port : ( device => /ttyS[0-9]/ )
#- output:
#-  $modem->{device} : device where the modem were detected
sub modem_detect_backend {
    my ($modem, $mouse) = @_;
    $mouse ||={};
    $mouse->{device} ||= readlink "/dev/mouse";
    my $serdev = arch() =~ /ppc/ ? "macserial" : "serial";
    eval { modules::load($serdev) };

    detect_devices::probeSerialDevices();
    foreach ('modem', map { "ttyS$_" } (0..7)) {
	next if $mouse->{device} =~ /$_/;
	next unless -e "/dev/$_";
	detect_devices::hasModem("/dev/$_") and $modem->{device} = $_, last;
    }

    #- add an alias for macserial on PPC
    modules::add_alias('serial', $serdev) if (arch() =~ /ppc/ && $modem->{device});
    my @devs = detect_devices::pcmcia_probe();
    foreach (@devs) {
	$_->{type} =~ /serial/ and $modem->{device} = $_->{device};
    }

}

1;
