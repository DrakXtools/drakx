package network::isdn;

use common qw(:common :file);
use any;
use modules;
use log;
use network::tools;
use vars qw(@ISA @EXPORT);
use globals "network", qw($in $prefix $install);

@ISA = qw(Exporter);
@EXPORT = qw(isdn_write_config isdn_write_config_backend get_info_providers_backend isdn_ask_info isdn_ask_protocol isdn_ask isdn_detect isdn_detect_backend isdn_get_list isdn_get_info);

sub configure {
    my ($netcnx, $netc) = @_;
  isdn_step_1:
    defined $netc->{autodetect}{isdn}{id} and goto intern_pci;
    $::isInstall and $in->set_help('configureNetworkISDN');
    my $e = $in->ask_from_list_(_("Network Configuration Wizard"),
				_("What kind is your ISDN connection?"), [ __("Internal ISDN card"), __("External ISDN modem")]
			       ) or return;
    if ($e =~ /card/) {
      intern_pci:
	$netcnx->{type}='isdn_internal';
	$netcnx->{isdn_internal}={};
	$netcnx->{isdn_internal}{$_} = $netc->{autodetect}{isdn}{$_} foreach ('description', 'vendor', 'id', 'driver', 'card_type', 'type');
	isdn_detect($netcnx->{isdn_internal}, $netc) or return;
    } else {
	$netcnx->{type}='isdn_external';
	$netcnx->{isdn_external}={};
	$netcnx->{isdn_external}{device}=$netc->{autodetect}{modem};
	$netcnx->{isdn_external}{special_command}='AT&F&O2B40';
	require network::modem;
	network::modem::pppConfig($netcnx->{isdn_external}, $mouse, $netc) or goto isdn_step_1;
    }
    1;
}

sub isdn_write_config {
    my ($isdn) = @_;
  isdn_write_config_step_1:
    my $e = $in->ask_from_list_(_("Network Configuration Wizard"),
				    _("Which ISDN configuration do you prefer?

* The full configuration uses isdn4net. It contains powerfull tools, but is tricky to configure for a newbie, and not standard.

* The light configuration is easier to understand, more standard, but with less tools.

We recommand the light configuration.

"), [ __("Light configuration"), __("Full configuration (isdn4net)")]
				   ) or return;
    $install->($e =~ /Light/ ? 'isdn-light' : 'isdn4net', 'isdn4k-utils');
    isdn_write_config_backend($isdn, $e =~ /Light/);
    $::isStandalone and ask_connect_now($isdn, 'ippp0');
    1;
}

#- isdn_write_config_backend : write isdn info, only for ippp0 -> ask_connect_now
#- input :
#-  $isdn
#-  $light : boolean : if yes : uses the isdn-light package, if not, isdn4net
#- $isdn input:
#-  $isdn->{login} $isdn->{passwd} $isdn->{phone_in} $isdn->{phone_out} $isdn->{dialing_mode}
#-  $isdn->{driver} $isdn->{type} $isdn->{irq} $isdn->{mem} $isdn->{io} $isdn->{io0} $isdn->{io1}
sub isdn_write_config_backend {
    my ($isdn, $light) = @_;
    if ($light) {
	any::setup_thiskind($in, 'isdn', !$::expert, 1);
	foreach my $f ('ioptions1B', 'ioptions2B') {
	    substInFile { s/^name .*\n//; $_ .= "name $isdn->{login}\n" if eof  } "$prefix/etc/ppp/$f";
	    chmod 0600, $f;
	}
	foreach my $f ('isdn1B.conf', 'isdn2B.conf') {
	    substInFile {
		s/EAZ = .*\n/EAZ = $isdn->{phone_in}/;
		s/PHONE_OUT = .*\n/PHONE_OUT = $isdn->{phone_out}/;
	    } "$prefix/etc/isdn/$f";
	    chmod 0600, $f;
	}
    } else {
	my $f = "$prefix/etc/isdn/profile/link/myisp";
	output $f,
	  qq(
I4L_USERNAME="$isdn->{login}"
I4L_SYSNAME=""
I4L_LOCALMSN="$isdn->{phone_in}"
I4L_REMOTE_OUT="$isdn->{phone_out}"
I4L_DIALMODE="$isdn->{dialing_mode}"
);
	chmod 0600, $f;

	output "$prefix/etc/isdn/profile/card/mycard",
	  qq(
I4L_MODULE="$isdn->{driver}"
I4L_TYPE="$isdn->{type}"
I4L_IRQ="$isdn->{irq}"
I4L_MEMBASE="$isdn->{mem}"
I4L_PORT="$isdn->{io}"
I4L_IO0="$isdn->{io0}"
I4L_IO1="$isdn->{io1}"
);

	output "$prefix/etc/ppp/ioptions",
	  "lock
usepeerdns
defaultroute
";
	system "$prefix/etc/rc.d/init.d/isdn4linux restart";
    }
    write_secret_backend($isdn->{login}, $isdn->{passwd});

    output "$prefix$connect_file",
      "#!/bin/bash
/sbin/route del default
/sbin/ifup ippp0
/sbin/isdnctrl dial ippp0
";

    output "$prefix$disconnect_file",
      "#!/bin/bash
/sbin/isdnctrl hangup ippp0
/sbin/ifdown ippp0
";
    chmod 0755, "$prefix$disconnect_file";
    chmod 0755, "$prefix$connect_file";
    1;
}

sub get_info_providers_backend {
    my ($isdn, $netc, $name, $file) = @_;
    $name eq 'Unlisted - edit manually' and return;
    foreach (catMaybeCompressed($file)) {
	chop;
	my ($name_, $phone, $real, $dns1, $dns2) = split '=>';
	if ($name eq $name_) {
	    @{$isdn}{qw(user_name phone_out DOMAINNAME2 dnsServer3 dnsServer2)} =
	               ((split(/\|/, $name_))[2], $phone, $real, $dns1, $dns2);
	}
    }
}

sub isdn_ask_info {
    my ($isdn, $netc) = @_;
    my $f = "$ENV{SHARE_PATH}/ldetect-lst/isdn.db";
    $f = "$prefix$f" if !-e $f;
    my $str= $in->ask_from_treelist( _("ISDN Configuration"), _("Select your provider.\n If it's not in the list, choose Unlisted"),
				     '|', ['Unlisted - edit manually',
					   read_providers_backend($f)], 'Unlisted - edit manually')
      or return;
    get_info_providers_backend($isdn, $netc, $str || 'Unlisted - edit manually', $f);
    $isdn->{$_} ||= '' foreach qw(phone_in phone_out dialing_mode login passwd passwd2 idl);
    add2hash($netc, { dnsServer2 => '', dnsServer3 => '', DOMAINNAME2 => '' });
    ask_info2($isdn, $netc);
}

sub isdn_ask_protocol {
    my @toto=(
	      { description => $::expert ? _("Europe (EDSS1)") : _("Europe"),
		protokol => 2},
	      { description => $::expert ? _("Rest of the world \n no D-Channel (leased lines)") : _("Rest of the world"),
		protokol => 3}
	     );
    my $e = $in->ask_from_listf(_("ISDN Configuration"),
				_("Which protocol do you want to use ?"),
				sub { $_[0]{description} },
				\@toto ) or return 0;
    $e->{protokol};
}

sub isdn_ask {
    my ($isdn, $netc, $label) = @_;
  isdn_ask_step_1:
    my $e = $in->ask_from_list_(_("ISDN Configuration"),
				$label . "\n" . _("What kind of card do you have?"),
				[ __("ISA / PCMCIA"), __("PCI"), __("I don't know") ]
			       ) or return;
    if ($e =~ /PCI/) {
	$isdn->{card_type} = 'pci';
    } else {
	$in->ask_from_list_(_("ISDN Configuration"),
			    _("
If you have an ISA card, the values on the next screen should be right.\n
If you have a PCMCIA card, you have to know the irq and io of your card.
"),
			    [ __("Continue"), __("Abort") ]) eq 'Continue' or goto isdn_ask_step_1;
	$isdn->{card_type} = 'isa';
    }

  isdn_ask_step_2:
    $e = $in->ask_from_listf(_("ISDN Configuration"),
				    _("Which is your ISDN card ?"),
				    sub { $_[0]{description} },
				    [ grep {$_->{card} eq $isdn->{card_type}; } @isdndata ] ) or goto isdn_ask_step_1;
    $isdn->{driver}='hisax';
    $e->{$_} and $isdn->{$_} = $e->{$_} foreach qw(type mem io io0 io1 irq);

  isdn_ask_step_3:
    $isdn->{protocol} = isdn_ask_protocol() or goto isdn_ask_step_2;
  isdn_ask_step_4:
    isdn_ask_info($isdn, $netc) or goto isdn_ask_step_3;
    isdn_write_config($isdn) or goto isdn_ask_step_4;
    1;
}

sub isdn_detect {
    my ($isdn, $netc) = @_;
    if ($isdn->{id}) {
  	log::l("found isdn card : $isdn->{description}; vendor : $isdn->{vendor};id : $isdn->{id}; driver : $isdn->{driver}\n");
	$isdn->{description} =~ s/\|/ -- /;
	if ($isdn->{type} eq '') {
	    isdn_ask($isdn, $netc, _("I have detected an ISDN PCI Card, but I don't know the type. Please select one PCI card on the next screen.")) or return;
	} else {
	  isdn_detect_step_1:
	    $isdn->{protocol}=isdn_ask_protocol() or return;
	  isdn_detect_step_2:
	    isdn_ask_info($isdn, $netc) or goto isdn_detect_step_1;
	    isdn_write_config($isdn) or goto isdn_detect_step_2;
	}
    } else {
	isdn_ask($isdn, $netc, _("No ISDN PCI card found. Please select one on the next screen.")) or return;
    }
    $netc->{$_}='ippp0' foreach 'NET_DEVICE', 'NET_INTERFACE';
    1;
}

#- isdn_detect_backend : detects isdn pci card and fills the infos in $isdn : only detects one card
#- input
#-  $isdn
#- $isdn output:
#-  $isdn->{description} $isdn->{vendor} $isdn->{id} $isdn->{driver} $isdn->{card_type} $isdn->{type}

sub isdn_detect_backend {
    my ($isdn) = @_;
    if (my ($c) = (modules::get_that_type('isdn'))) {
  	$isdn->{$_} = $c->{$_} foreach qw(description vendor id driver options);
	$isdn->{$_} = sprintf("%0x", $isdn->{$_}) foreach ('vendor', 'id');
	$isdn->{card_type} = 'pci';
	$isdn->{type} = $isdnid2type{$isdn->{vendor} . $isdn->{id}}; #If the card is not listed, type is void. You have to ask it then.
    }
}

#- isdn_get_list : return isdn cards descriptions list. This function is not use internally.
#- output : descriptions : list of strings

sub isdn_get_list {
    map { $_->{description} } @isdndata;
}

#- isdn_get_info : return isdn card infos. This function is not use internally.
#- input : the description of the card (see isdn_get_list)
#- output : a reference on the decription of the card. : ref on a hash(description,type,irq,mem,io,io0,io1card,)

sub isdn_get_info {
    my ($desc) = @_;
    foreach (@isdndata) {
	return $_ if ($_->{description} eq $desc);
    }
}

1;
