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
@EXPORT = qw(pppConfig);

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

1;
