package network::isdn; # $Id$

use strict;
use network::isdn_consts;
use common;
use any;
use modules;
use run_program;
use log;
use network::tools;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in);
use MDK::Common::File;


@ISA = qw(Exporter);
@EXPORT = qw(isdn_write_config isdn_write_config_backend get_info_providers_backend isdn_ask_info isdn_ask_protocol isdn_ask isdn_detect_backend isdn_get_list isdn_get_info);


sub isdn_write_config {
    my ($isdn, $netc) = @_;
    $in->do_pkgs->install('isdn4net', if_($isdn->{speed} =~ /128/, 'ibod'), 'isdn4k-utils');
    isdn_write_config_backend($isdn, $netc);
    1;
}

sub isdn_write_config_backend {
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

    set_cnx_script($netc, "isdn",
"#/sbin/route del default
#/sbin/ifup ippp0
/usr/sbin/isdnctrl dial ippp0
" . if_($isdn->{speed} =~ /128/, "service ibod restart
"),
"/usr/sbin/isdnctrl hangup ippp0
#/sbin/ifdown ippp0
"  . if_($isdn->{speed} =~ /128/, "service ibod stop
"), $netc->{isdntype});
    1;
}

sub isdn_read_config {
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
	    $isdn->{$match{$_}} = $conf{$_} if $match{$_};
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
	    @$isdn{qw(user_name phone_out DOMAINNAME2 dnsServer3 dnsServer2)} =
	               ((split(/\|/, $name_))[2], $phone, $real, $dns1, $dns2);
	}
    }
}

sub isdn_ask_info {
    my ($isdn, $netc) = @_;
    my $f = "$ENV{SHARE_PATH}/ldetect-lst/isdn.db";
    $f = "$::prefix$f" if !-e $f;
  isdn_ask_info_step1:
    my $str = $in->ask_from_treelist(N("ISDN Configuration"), N("Select your provider.\nIf it isn't listed, choose Unlisted."),
				     '|', ['Unlisted - edit manually',
					   read_providers_backend($f)], 'Unlisted - edit manually')
      or return;
    get_info_providers_backend($isdn, $netc, $str || 'Unlisted - edit manually', $f);
    $isdn->{huptimeout} = 180;
    $isdn->{$_} ||= '' foreach qw(phone_in phone_out dialing_mode login passwd passwd2 idl speed);
    add2hash($netc, { dnsServer2 => '', dnsServer3 => '', DOMAINNAME2 => '' });
    ask_info2($isdn, $netc) or goto isdn_ask_info_step1;
}

sub isdn_ask_protocol() {
    my @toto = (
	      { description => $::expert ? N("European protocol (EDSS1)") : N("European protocol"),
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
				[ N_("ISA / PCMCIA"), N_("PCI"), N_("USB"), N_("I don't know") ]
			       ) or return;
 isdn_ask_step_1b:
    if ($e =~ /PCI/) {
	$isdn->{card_type} = 'pci';
    } elsif ($e =~ /USB/) {
	$isdn->{card_type} = 'usb';
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
			     [ grep { $_->{card} eq $isdn->{card_type} } @isdndata ]) or goto($isdn->{card_type} =~ /usb|pci/ ? 'isdn_ask_step_1' : 'isdn_ask_step_1b');
    $e->{$_} and $isdn->{$_} = $e->{$_} foreach qw(driver type mem io io0 io1 irq firmware);

  isdn_ask_step_3:
    $isdn->{protocol} = isdn_ask_protocol() or goto isdn_ask_step_2;
  isdn_ask_step_4:
    isdn_ask_info($isdn, $netc) or goto isdn_ask_step_3;
    isdn_write_config($isdn, $netc) or goto isdn_ask_step_4;
    1;
}

sub isdn_detect_backend() {
    my $isdn = { };
    require detect_devices;
     each_index {
 	my $c = $_;
 	$isdn->{$::i} = { map { $_ => $c->{$_} } qw(description vendor id driver card_type type) };
 	my $isdn = $isdn->{$::i};
        $isdn->{intf_id} = $::i;
	$isdn->{$_} = sprintf("%0x", $isdn->{$_}) foreach 'vendor', 'id';
	$isdn->{card_type} = $c->{bus} eq 'USB' ? 'usb' : 'pci';
	($isdn->{type}) = $isdn->{options} =~ /type=(\d+)/;
        $isdn->{description} =~ s/.*\|//;
#	$c->{options} !~ /id=HiSax/ && $isdn->{driver} eq "hisax" and $c->{options} .= " id=HiSax";
	if ($c->{options} !~ /protocol=/ && $isdn->{protocol} =~ /\d/) {
	    modules::set_options($c->{driver}, $c->{options} . " protocol=" . $isdn->{protocol});
	}
	$c->{options} =~ /protocol=(\d)/ and $isdn->{protocol} = $1;
    } modules::probe_category('network/isdn'), grep { $_->{driver} =~ /^ISDN:/ } detect_devices::probeall();
    $isdn;
}

sub isdn_get_list() {
    map { $_->{description} } @isdndata;
}

sub isdn_get_info {
    my ($desc) = @_;
    find { $_->{description} eq $desc } @isdndata;
}

1;
