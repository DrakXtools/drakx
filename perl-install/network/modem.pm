package network::modem;

use common;
use any;
use modules;
use detect_devices;
use mouse;
use network::tools;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix);
use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(pppConfig);

sub configure {
    my ($netcnx, $mouse, $netc, $intf) = @_;
    $netcnx->{type} = 'modem';
#    $netcnx->{$netcnx->{type}} = {};
#    $netcnx->{modem}{device} = $netc->{autodetect}{modem};
#  modem_step_1:
    $netcnx->{$netcnx->{type}}{login} = ($netcnx->{$netcnx->{type}}{auth} eq 'PAP' || $netcnx->{$netcnx->{type}}{auth} eq 'CHAP') && $intf->{ppp0}{PAPNAME};
    pppConfig($netcnx->{$netcnx->{type}}, $mouse, $netc, $intf) or return;
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
    my ($modem, $mouse, $netc, $intf) = @_;

    $mouse ||= {};
    $mouse->{device} ||= readlink "$prefix/dev/mouse";
    $::isInstall and $in->set_help('selectSerialPort');
    $modem->{device} ||= $in->ask_from_listf('', N("Please choose which serial port your modem is connected to."),
					     \&mouse::serial_port2text,
					     [ grep { $_ ne $mouse->{device} } (mouse::serial_ports(), if_(-e '/dev/modem', '/dev/modem')) ]) || return;

    $::isStandalone || $in->set_help('configureNetworkISP');
    $in->ask_from('', N("Dialup options"), [
{ label => N("Connection name"), val => \$modem->{connection} },
{ label => N("Phone number"), val => \$modem->{phone} },
{ label => N("Login ID"), val => \$modem->{login} },
{ label => N("Password"), val => \$modem->{passwd}, hidden => 1 },
{ label => N("Authentication"), val => \$modem->{auth}, list => [ N_("PAP"), N_("Terminal-based"), N_("Script-based"), N_("CHAP") ] },
{ label => N("Domain name"), val => \$modem->{domain} },
{ label => N("First DNS Server (optional)"), val => \$modem->{dns1} },
{ label => N("Second DNS Server (optional)"), val => \$modem->{dns2} },
    ]) or return;
    $netc->{DOMAINNAME2} = $modem->{domain};
    any::pppConfig($in, $modem, $prefix);
    $netc->{$_} = 'ppp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
    1;
}

#- TODO: add choice between hcf/hsf
sub winmodemConfigure {
    my ($netc) = @_;
    my $type;
    
    foreach (keys %{$netc->{autodetect}{winmodem}}) {
    	my $temp;
    	/Hcf/ and $temp = "hcf";
    	/Hsf/ and $temp = "hsf";
    	$temp and $in->do_pkgs->what_provides("${temp}linmodem") and $type = "${temp}linmodem";
    }
    
    $type || $in->ask_warn(N("Warning"), N("Your modem isn't supported by the system.
Take a look at http://www.linmodems.org")) && return 1;
    my $e = $in->ask_from_list(N("Title"), N("\"%s\" based winmodem detected, do you want to install needed software ?", $type), [N("Install rpm"), N("Do nothing")]) or return 0;
    $e =~ /rpm/ ? $in->do_pkgs->install($type) : return 1;
    1;
}

1;
