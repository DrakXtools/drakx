package network::isdn;

use network::isdn_consts;
use common;
use any;
use modules;
use run_program;
use log;
use network::tools;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix);
use MDK::Common::File;
@ISA = qw(Exporter);
@EXPORT = qw(isdn_write_config isdn_write_config_backend get_info_providers_backend isdn_ask_info isdn_ask_protocol isdn_ask isdn_detect isdn_detect_backend isdn_get_list isdn_get_info);

sub configure {
    my ($netcnx, $netc, $isdn) = @_;
  isdn_step_1:
    defined $netc->{autodetect}{isdn}{id} and goto intern_pci;
    $::isInstall and $in->set_help('configureNetworkISDN');
    my $e = $in->ask_from_list_(N("Network Configuration Wizard"),
				N("Which ISDN configuration do you prefer?

* The Old configuration uses isdn4net. It contains powerful
  tools, but is tricky to configure, and not standard.

* The New configuration is easier to understand, more
  standard, but with less tools.

We recommand the light configuration.
"), [ N_("New configuration (isdn-light)"), N_("Old configuration (isdn4net)") ]
			       ) or return;
    $netc->{autodetect}{isdn}{is_light} = $e =~ /light/ ? 1 : undef;
    $e = $in->ask_from_list_(N("Network Configuration Wizard"),
			     N("What kind is your ISDN connection?"), [ N_("Internal ISDN card"), N_("External ISDN modem") ]
			    ) or return;
    
    if ($e =~ /card/) {
      intern_pci:
	$netc->{isdntype} = 'isdn_internal';
	$netcnx->{isdn_internal} = isdn_read_config($isdn);
	$netcnx->{isdn_internal}{$_} = $netc->{autodetect}{isdn}{$_} foreach 'description', 'vendor', 'id', 'driver', 'card_type', 'type', 'is_light';
	isdn_detect($netcnx->{isdn_internal}, $netc) or return;
    } else {
	$netc->{isdntype} = 'isdn_external';
	$netcnx->{isdn_external} = isdn_read_config($isdn);
	$netcnx->{isdn_external}{device} = $netc->{autodetect}{modem};
	$netcnx->{isdn_external}{is_light} = $netc->{autodetect}{isdn}{is_light};
	$netcnx->{isdn_external}{special_command} = 'AT&F&O2B40';
	require network::modem;
	network::modem::ppp_choose($in, $netc, $netcnx->{isdn_external}) or goto isdn_step_1;
    }
    1;
}

sub isdn_write_config {
    my ($isdn, $netc) = @_;
  isdn_write_config_step_1:
    my ($rmpackage, $instpackage) = $isdn->{is_light} ? ('isdn4net', 'isdn-light') : ('isdn-light', 'isdn4net');
    if (!$::isStandalone) {
	require pkgs;
	my $p = pkgs::packageByName($in->{packages}, $rmpackage);
	$p && $p->flag_selected and pkgs::unselectPackage($in->{packages}, $p);
    }
    run_program::rooted($prefix, "rpm", "-e", $rmpackage);
    $in->do_pkgs->install($instpackage, if_($isdn->{speed} =~ /128/, 'ibod'), 'isdn4k-utils');
    isdn_write_config_backend($isdn, $netc);
    1;
}

sub isdn_write_config_backend {
    my ($isdn, $netc, $netcnx) = @_;
    defined $netcnx and $netc->{isdntype} = $netcnx->{type};
    if ($isdn->{is_light}) {
	modules::mergein_conf("$prefix/etc/modules.conf");
	if ($isdn->{id}) {
	    isdn_detect_backend($isdn);
	} else {
	    my $a = "";
	    defined $isdn->{$_} and $a .= "$_=" . $isdn->{$_} . " " foreach qw(type protocol mem io io0 io1 irq);
	    $isdn->{driver} eq "hisax" and $a .= "id=HiSax";
	    modules::set_options($isdn->{driver}, $a);
	}
	modules::add_alias("ippp0", $isdn->{driver});
	$::isStandalone and modules::write_conf($prefix);
	foreach my $f ('ioptions1B', 'ioptions2B') {
	    substInFile { s/^name .*\n//; $_ .= "name $isdn->{login}\n" if eof  } "$prefix/etc/ppp/$f";
	    chmod 0600, $f;
	}
	foreach my $f ('isdn1B.conf', 'isdn2B.conf') {
	    substInFile {
		s/EAZ =.*/EAZ = $isdn->{phone_in}/;
		s/PHONE_OUT =.*/PHONE_OUT = $isdn->{phone_out}/;
		if (/NAME = ippp0/ .. /PPPBIND = 0/) {
		    s/HUPTIMEOUT =.*/HUPTIMEOUT = $isdn->{huptimeout}/;
		}
	    } "$prefix/etc/isdn/$f";
	    chmod 0600, $f;
	}
	my $bundle = $isdn->{speed} =~ /64/ ? "1B" : "2B";
	symlinkf("isdn" . $bundle . ".conf", "$prefix/etc/isdn/isdnctrl.conf");
	symlinkf("ioptions" . $bundle, "$prefix/etc/ppp/ioptions");
    } else {
	output_with_perm("$prefix/etc/isdn/profile/link/myisp", 0600,
	  qq(
I4L_USERNAME="$isdn->{login}"
I4L_SYSNAME=""
I4L_LOCALMSN="$isdn->{phone_in}"
I4L_REMOTE_OUT="$isdn->{phone_out}"
I4L_DIALMODE="$isdn->{dialing_mode}"
) . if_($isdn->{speed} =~ /128/, 'SLAVE="ippp1"
'));
	output "$prefix/etc/isdn/profile/card/mycard",
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
);

	output "$prefix/etc/ppp/ioptions",
	  "lock
usepeerdns
defaultroute
";
	system "$prefix/etc/rc.d/init.d/isdn4linux restart";
    }

    substInFile { s/^FIRMWARE.*\n//; $_ .= qq(FIRMWARE="$isdn->{firmware}"\n) if eof  } "$prefix/etc/sysconfig/network-scripts/ifcfg-ippp0";

    write_secret_backend($isdn->{login}, $isdn->{passwd});

    write_cnx_script($netc, "isdn",
"/sbin/route del default
/sbin/ifup ippp0
/sbin/isdnctrl dial ippp0
" . if_($isdn->{speed} =~ /128/, "service ibod restart
"),
"/sbin/isdnctrl hangup ippp0
/sbin/ifdown ippp0
"  . if_($isdn->{speed} =~ /128/, "service ibod stop
"), $netc->{isdntype});
    1;
}

sub isdn_read_config {
    my ($isdn) = @_;
    
    if ($isdn->{is_light}) {
	my $c = modules::read_conf("/etc/modules.conf");
	$isdn->{driver} = $c->{ippp0}{alias};
	#- 'type' 'protocol' 'mem' 'io' 'io0' 'io1' 'irq'  'id'
	foreach (split(' ', $c->{$isdn->{driver}}{options})) {
	    /(.*)=(.*)/;
	    $isdn->{$1} = $2;
	}
	foreach my $f ('ioptions1B', 'ioptions2B') {
	    foreach (cat_("$prefix/etc/ppp/$f")) {
		if (/^\s*name\s*(.*)/) {
		    $isdn->{login} = $1;
		    goto NEXT;
		}
	    }
	}
	NEXT:
	foreach my $f ('isdn1B.conf', 'isdn2B.conf') {
	    foreach (cat_("$prefix/etc/isdn/$f")) {
		/^\s*EAZ\s*=\s*(.*)/ and $isdn->{phone_in} = $1;
		/^\s*PHONE_OUT\s*=\s*(.*)/ and $isdn->{phone_out} = $1;
		if (/^\s*NAME\s*=\s*ippp0/ .. /PPPBIND\s*=\s*0/) {
		    /^\s*HUPTIMEOUT\s*=\s*(.*)/ and $isdn->{huptimeout} = $1;
		}
	    }
	}
    } else {
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
	    my %conf = getVarsFromSh("$prefix/etc/isdn/profile/$_");
	    foreach (keys %conf) {	 
		$isdn->{$match{$_}} = $conf{$_} if $match{$_};
	    }
	}
    }
    $isdn->{passwd} = network::tools::passwd_by_login($isdn->{login});
    #$isdn->{description} = '';
    #$isdn->{vendor} = '';
    #$isdn->{passwd2} = '';
    $isdn;
}

sub get_info_providers_backend {
    my ($isdn, $_netc, $name, $file) = @_;
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
    my $str = $in->ask_from_treelist(N("ISDN Configuration"), N("Select your provider.\nIf it isn't listed, choose Unlisted."),
				     '|', ['Unlisted - edit manually',
					   read_providers_backend($f)], 'Unlisted - edit manually')
      or return;
    get_info_providers_backend($isdn, $netc, $str || 'Unlisted - edit manually', $f);
    $isdn->{huptimeout} = 180;
    $isdn->{$_} ||= '' foreach qw(phone_in phone_out dialing_mode login passwd passwd2 idl speed);
    add2hash($netc, { dnsServer2 => '', dnsServer3 => '', DOMAINNAME2 => '' });
    ask_info2($isdn, $netc);
}

sub isdn_ask_protocol {
    my @toto = (
	      { description => $::expert ? N("European protocol (EDSS1)") : N("Europe protocol"),
		protokol => 2 },
	      { description => $::expert ? N("Protocol for the rest of the world\nNo D-Channel (leased lines)") : N("Protocol for the rest of the world"),
		protokol => 3 }
	     );
    my $e = $in->ask_from_listf(N("ISDN Configuration"),
				N("Which protocol do you want to use?"),
				sub { $_[0]{description} },
				\@toto) or return 0;
    $e->{protokol};
}

sub isdn_ask {
    my ($isdn, $netc, $label) = @_;
    
    #- ISDN card already detected
    if (!$::expert && defined $netc->{autodetect}{isdn}{card_type}) {
	$in->ask_yesorno(N("ISDN Configuration"), N("Found \"%s\" interface do you want to use it ?", $netc->{autodetect}{isdn}{description}), 1) or return;
	$isdn->{$_} = $netc->{autodetect}{isdn}{$_} foreach qw(description vendor id card_type driver type mem io io0 io1 irq firmware);
	goto isdn_ask_step_3;
    }

 isdn_ask_step_1:
    my $e = $in->ask_from_list_(N("ISDN Configuration"),
				$label . "\n" . N("What kind of card do you have?"),
				[ N_("ISA / PCMCIA"), N_("PCI"), N_("I don't know") ]
			       ) or return;
    if ($e =~ /PCI/) {
	$isdn->{card_type} = 'pci';
    } else {
	$in->ask_from_list_(N("ISDN Configuration"),
			    N("
If you have an ISA card, the values on the next screen should be right.\n
If you have a PCMCIA card, you have to know the \"irq\" and \"io\" of your card.
"),
			    [ N_("Continue"), N_("Abort") ]) eq 'Continue' or goto isdn_ask_step_1;
	$isdn->{card_type} = 'isa';
    }

  isdn_ask_step_2:
    $e = $in->ask_from_listf(N("ISDN Configuration"),
			     N("Which of the following is your ISDN card?"),
			     sub { $_[0]{description} },
			     [ grep { $_->{card} eq $isdn->{card_type} } @isdndata ]) or goto isdn_ask_step_1;
    $e->{$_} and $isdn->{$_} = $e->{$_} foreach qw(driver type mem io io0 io1 irq firmware);

  isdn_ask_step_3:
    $isdn->{protocol} = isdn_ask_protocol() or goto isdn_ask_step_2;
  isdn_ask_step_4:
    isdn_ask_info($isdn, $netc) or goto isdn_ask_step_3;
    isdn_write_config($isdn, $netc) or goto isdn_ask_step_4;
    1;
}

sub isdn_detect {
    my ($isdn, $netc) = @_;
    if ($isdn->{id}) {
  	log::l("found isdn card : $isdn->{description}; vendor : $isdn->{vendor}; id : $isdn->{id}; driver : $isdn->{driver}\n");
	$isdn->{description} =~ s/\|/ -- /;
	if ($isdn->{type} eq '') {
	    isdn_ask($isdn, $netc, N("I have detected an ISDN PCI card, but I don't know its type. Please select a PCI card on the next screen.")) or return;
	} else {
	  isdn_detect_step_1:
	    $isdn->{protocol} = isdn_ask_protocol() or return;
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

sub isdn_detect_backend {
    my ($isdn) = @_;
    if (my ($c) = modules::probe_category('network/isdn')) {
  	$isdn->{$_} = $c->{$_} foreach qw(description vendor id driver options firmware);
	$isdn->{$_} = sprintf("%0x", $isdn->{$_}) foreach 'vendor', 'id';
	$isdn->{card_type} = 'pci';
	($isdn->{type}) = $isdn->{options} =~ /type=(\d+)/;
#	$c->{options} !~ /id=HiSax/ && $isdn->{driver} eq "hisax" and $c->{options} .= " id=HiSax";
	if ($c->{options} !~ /protocol=/ && $isdn->{protocol} =~ /\d/) {
	    modules::set_options($c->{driver}, $c->{options} . " protocol=" . $isdn->{protocol});
	}
	$c->{options} =~ /protocol=(\d)/ and $isdn->{protocol} = $1;
    }
}

sub isdn_get_list {
    map { $_->{description} } @isdndata;
}

sub isdn_get_info {
    my ($desc) = @_;
    foreach (@isdndata) {
	return $_ if $_->{description} eq $desc;
    }
}

1;
