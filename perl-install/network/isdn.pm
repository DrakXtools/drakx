package network::isdn; # $Id$

use strict;
use network::isdn_consts;
use common;
use any;
use modules;
use run_program;
use log;
use network::tools;
use MDK::Common::Globals "network", qw($in);
use MDK::Common::File;


sub write_config {
    my ($isdn, $netc) = @_;
    $in->do_pkgs->install('isdn4net', if_($isdn->{speed} =~ /128/, 'ibod'), 'isdn4k-utils');
    write_config_backend($isdn, $netc);
    1;
}

sub write_config_backend {
    my ($isdn, $netc, $o_netcnx) = @_;
    defined $o_netcnx and $netc->{isdntype} = $o_netcnx->{type};

    output_with_perm("$::prefix/etc/isdn/profile/link/myisp", 0600,
	  qq(
I4L_USERNAME="$isdn->{login}"
I4L_SYSNAME=""
I4L_LOCALMSN="$isdn->{phone_in}"
I4L_REMOTE_OUT="$isdn->{phone_out}"
I4L_DIALMODE="$isdn->{dialing_mode}"
) . if_($isdn->{speed} =~ /128/, 'SLAVE="ippp1"
'));
	output "$::prefix/etc/isdn/profile/card/mycard",
	  qq(
I4L_MODULE="$isdn->{driver}"
I4L_TYPE="$isdn->{type}"
I4L_IRQ="$isdn->{irq}"
I4L_MEMBASE="$isdn->{mem}"
I4L_PORT="$isdn->{io}"
I4L_IO0="$isdn->{io0}"
I4L_IO1="$isdn->{io1}"
I4L_ID="HiSax"
I4L_FIRMWARE="$isdn->{firmware}"
I4L_PROTOCOL="$isdn->{protocol}"
);

	output "$::prefix/etc/ppp/ioptions",
	  "lock
usepeerdns
defaultroute
";
	system "$::prefix/etc/rc.d/init.d/isdn4linux restart";

    substInFile { s/^FIRMWARE.*\n//; $_ .= qq(FIRMWARE="$isdn->{firmware}"\n) if eof  } "$::prefix/etc/sysconfig/network-scripts/ifcfg-ippp0";

    # we start the virtual interface at boot (we dial only on demand.
    substInFile { s/^ONBOOT.*\n//; $_ .= qq(ONBOOT=yes\n) if eof  } "$::prefix/etc/sysconfig/network-scripts/ifcfg-ippp$isdn->{intf_id}";

    write_secret_backend($isdn->{login}, $isdn->{passwd});

    set_cnx_script($netc, "isdn", join('',
"/sbin/route del default
modprobe $isdn->{driver}", if_($isdn->{type}, " type=$isdn->{type}"),
"
/usr/sbin/isdnctrl dial ippp0
", if_($isdn->{speed} =~ /128/, "service ibod restart
")),
"/usr/sbin/isdnctrl hangup ippp0
"  . if_($isdn->{speed} =~ /128/, "service ibod stop
"), $netc->{isdntype});
    1;
}

sub read_config {
    my ($isdn) = @_;
    
    my %match = (I4L_USERNAME => 'login',
		 I4L_LOCALMSN => 'phone_in',
		 I4L_REMOTE_OUT => 'phone_out',
		 I4L_DIALMODE => 'dialing_mode',
		 I4L_MODULE => 'driver',
		 I4L_TYPE => 'type',
		 I4L_IRQ => 'irq',
		 I4L_MEMBASE => 'mem',
		 I4L_PORT => 'io',
		 I4L_IO0 => 'io0',
		 I4L_IO1 => 'io1',
		 I4L_FIRMWARE => 'firmware');
    foreach ('link/myisp', 'card/mycard') {
	my %conf = getVarsFromSh("$::prefix/etc/isdn/profile/$_");
	foreach (keys %conf) {	 
	    $isdn->{$match{$_}} = $conf{$_} if $match{$_} && $conf{$_};
	}
    }

    $isdn->{passwd} = network::tools::passwd_by_login($isdn->{login});
    #$isdn->{description} = '';
    #$isdn->{vendor} = '';
    #$isdn->{passwd2} = '';
}

my $file = "$ENV{SHARE_PATH}/ldetect-lst/isdn.db";
$file = "$::prefix$file" if !-e $file;

sub get_info_providers_backend {
    my ($isdn, $_netc, $name) = @_;
    $name eq N("Unlisted - edit manually") and return;
    foreach (catMaybeCompressed($file)) {
	chop;
	my ($name_, $phone, $real, $dns1, $dns2) = split '=>';
	if ($name eq $name_) {
	    @$isdn{qw(user_name phone_out DOMAINNAME2 dnsServer3 dnsServer2)} =
	               ((split(/\|/, $name_))[2], $phone, $real, $dns1, $dns2);
	}
    }
}

sub read_providers_backend() { map { /(.*?)=>/ } catMaybeCompressed($file) }


sub detect_backend {
    my ($modules_conf) = @_;
    my @isdn;
    require detect_devices;
     each_index {
 	my $c = $_;
 	my $isdn = { map { $_ => $c->{$_} } qw(description vendor id driver card_type type) };
        $isdn->{intf_id} = $::i;
	$isdn->{$_} = sprintf("%0x", $isdn->{$_}) foreach 'vendor', 'id';
	$isdn->{card_type} = $c->{bus} eq 'USB' ? 'usb' : 'pci';
        $isdn->{description} =~ s/.*\|//;
#	$c->{options} !~ /id=HiSax/ && $isdn->{driver} eq "hisax" and $c->{options} .= " id=HiSax";
	if ($c->{options} !~ /protocol=/ && $isdn->{protocol} =~ /\d/) {
	    $modules_conf->set_options($c->{driver}, $c->{options} . " protocol=" . $isdn->{protocol});
	}
	$c->{options} =~ /protocol=(\d)/ and $isdn->{protocol} = $1;
	push @isdn, $isdn;
    } modules::probe_category('network/isdn');
    \@isdn;
}

sub get_cards_by_type {
    my ($isdn_type) = @_;
    grep { $_->{card} eq $isdn_type } @isdndata;
}


sub get_cards() {
    my %buses = (
                 isa => N("ISA / PCMCIA") . "/" . N("I don't know"),
                 pci => N("PCI"),
                 usb => N("USB"),
                );
    # pmcia alias (we should really split up pcmcia from isa in isdn db): 
    $buses{pcmcia} = $buses{isa};

    map { $buses{$_->{card}} . "|" . $_->{description} => $_ } @isdndata;
}


1;
