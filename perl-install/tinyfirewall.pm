package tinyfirewall;
use diagnostics;
use strict;
use run_program;
use network::netconnect;
use network;
use POSIX qw(tmpnam);
use MDK::Common;
my @messages = (_("tinyfirewall configurator

This configures a personal firewall for this Mandrake Linux machine.
For a powerful dedicated firewall solution, please look to the
specialized MandrakeSecurity Firewall distribution."),
_("We'll now ask you questions about which services you'd like to allow
the Internet to connect to.  Please think carefully about these
questions, as your computer's security is important.

Please, if you're not currently using one of these services, firewall
it off.  You can change this configuration anytime you like by
re-running this application!"),
_("Are you running a web server on this machine that you need the whole
Internet to see? If you are running a webserver that only needs to be
accessed by this machine, you can safely answer NO here.

"),
_("Are you running a name server on this machine? If you didn't set one
up to give away IP and zone information to the whole Internet, please
answer no.

"),
_("Do you want to allow incoming Secure Shell (ssh) connections? This
is a telnet-replacement that you might use to login. If you're using
telnet now, you should definitely switch to ssh. telnet is not
encrypted -- so some attackers can steal your password if you use
it. ssh is encrypted and doesn't allow for this eavesdropping."),
_("Do you want to allow incoming telnet connections?
This is horribly unsafe, as we explained in the previous screen. We
strongly recommend answering No here and using ssh in place of
telnet.
"),
_("Are you running an FTP server here that you need accessible to the
Internet? If you are, we strongly recommend that you only use it for
Anonymous transfers. Any passwords sent by FTP can be stolen by some
attackers, since FTP also uses no encryption for transferring passwords.
"),
_("Are you running a mail server here? If you're sending you 
messages through pine, mutt or any other text-based mail client,
you probably are.  Otherwise, you should firewall this off.

"),
_("Are you running a POP or IMAP server here? This would
be used to host non-web-based mail accounts for people via 
this machine.

"),
_("You appear to be running a 2.2 kernel.  If your network IP
is automatically set by a computer in your home or office 
(dynamically assigned), we need to allow for this.  Is
this the case?
"),
_("Is your computer getting time syncronized to another computer?
Mostly, this is used by medium-large Unix/Linux organizations
to synchronize time for logging and such.  If you're not part
of a larger office and haven't heard of this, you probably 
aren't."),
_("Configuration complete.  May we write these changes to disk?



")
);
my %settings;
my $config_file = "/etc/Bastille/bastille-firewall.cfg";
my $default_config_file = "/usr/share/Bastille/bastille-firewall.cfg"; # set this later
sub ReadConfig {
    -e $config_file or cp_af($default_config_file, $config_file);
    add2hash(\%settings, { getVarsFromSh("$config_file") });
}
sub SaveConfig {
	my $tmp_file = tmpnam();
	open CONFIGFILE, "$config_file"
		or die _("Can't open %s: %s\n", $config_file, $!);
	open TMPFILE, ">$tmp_file"
		or die _("Can't open %s for writing: %s\n", $tmp_file, $!);
	while (my $line = <CONFIGFILE>)
	{
		if ($line =~ m/^(.+)\s*\=\s*"(.*)"/)
		{
			my ($variable, $value) = ($1, $2);
			my $newvalue = $settings{$variable};
			$line =~ s/".*"/"$newvalue"/
				if (exists $settings{$variable});
		}
		print TMPFILE $line;
	}
	close CONFIGFILE;
	close TMPFILE;
	rename ($config_file, $config_file . ".orig");
	system ("/bin/cp $tmp_file $config_file");
	system ("/bin/rm $tmp_file");
}
sub DoInterface {
    my ($in)=@_;
    $::isWizard=1;
    my $GetNetworkInfo = sub {
	$settings{DNS_SERVERS} = join(' ', uniq(split(' ', $settings{DNS_SERVERS}),
            @{network::read_resolv_conf("/etc/resolv.conf")}{'dnsServer', 'dnsServer2', 'dnsServer3'}));
	my (undef, undef, @netstat) = `/bin/netstat -in`;
	my @interfaces =  map { /(\S+)/ } @netstat;
	my (@route, undef, undef) = `/sbin/route -n`;
	my $defaultgw;
	my $iface;
	foreach (@route) { my @parts = split /\s+/; $parts[0] eq "0.0.0.0" and $defaultgw = $parts[1], $iface = $parts[7] }
	my $fulliface = $iface;
	$fulliface =~ s/[0-9]+/\\\+/;
	$settings{PUBLIC_INTERFACES} = join(' ', uniq(split(' ', $settings{PUBLIC_INTERFACES}), $iface));
	$settings{PUBLIC_INTERFACES} =~ $fulliface and $settings{PUBLIC_INTERFACES} =~ s/$iface *//;
	$settings{INTERNAL_IFACES} = join(' ', uniq(split(' ', $settings{INTERNAL_IFACES}),
            map { my $i = $_; my $f = $i; $f =~ s/[0-9]+/\\\+/;
		  if_(and_(map { $settings{$_} !~ /$i/ and $settings{$_} !~ /$f/ } ('TRUSTED_IFACES', 'PUBLIC_IFACES', 'INTERNAL_IFACES')), $i)
	    } @interfaces));
    };
#    my $popimap = sub {	$_[0] or return; $settings{FORCE_PASV_FTP} = 11;  mapn {$settings{"$_[0]"} = "$_[1]"; }
#[ qw(FORCE_PASV_FTP TCP_BLOCKED_SERVICES UDP_BLOCKED_SERVICES ICMP_ALLOWED_TYPES ENABLE_SRC_ADDR_VERIFY IP_MASQ_NETWORK IP_MASQ_MODULES REJECT_METHOD) ] ,
#[ "N", "6000:6020", "2049", "destination-unreachable echo-reply time-exceeded" , "Y", "", "", "DENY" ]; };
    my $popimap = sub {
	$_[0] or return;
	$settings{'FORCE_PASV_FTP'} = "N";
	$settings{TCP_BLOCKED_SERVICES}= "6000:6020";
	$settings{UDP_BLOCKED_SERVICES}= "2049";
	$settings{ICMP_ALLOWED_TYPES}= "destination-unreachable echo-reply time-exceeded";
	$settings{ENABLE_SRC_ADDR_VEIFY}= "Y";
	$settings{IP_MASQ_NETWORK}= "";
	$settings{IP_MASQ_MODULES}= "";
	$settings{REJECT_METHOD}= "DENY";
    };
    #    my $ntp = sub { $_[0] or return; mapn { $settings{$_[0]} = $_[1] } ['ICMP_OUTBOUND_DISABLED_TYPES}', 'LOG_FAILURES'], [ "", "N"] };
    my $ntp = sub { $_[0] or return;
		    $settings{'ICMP_OUTBOUND_DISABLED_TYPES}'} = "";
		    $settings{'LOG_FAILURES'} = "N";
		};
    my $dhcp = sub { if ($_[0]) {
	$settings{DHCP_IFACES} and return;
	my (undef, undef, @netstat) = `/bin/netstat -in`;
	$settings{DHCP_IFACES} = join(' ', split(' ', $settings{DHCP_IFACES}), map { /(\S+)/ } @netstat);
    } else { $settings{DHCP_IFACES} = "" } };
    my $quit = sub {
	$_[0] or $in->exit(0);
	SaveConfig();
	system($_) foreach ("/bin/cp /usr/share/Bastille/bastille-ipchains /usr/share/Bastille/bastille-netfilter /sbin",
			    "/bin/cp /usr/share/Bastille/bastille-firewall /etc/rc.d/init.d/",
			    "/bin/chmod 0700 /etc/rc.d/init.d/bastille-firewall", "/bin/chmod 0700 /sbin/bastille-ipchains",
			    "/bin/chmod 0700 /sbin/bastille-netfilter", "/sbin/chkconfig bastille-firewall on",
			    "/etc/rc.d/init.d/bastille-firewall stop", "/etc/rc.d/init.d/bastille-firewall start");
	$in->exit(0);
	return;
	$_[0] or $in->exit(0);
	cp_af($config_file, $config_file . ".orig");
	substInFile {
	    if (/^(.+)\s*\=/) {
		$a = $settings{ $1 };
		s/".*"/"$a"/;
	    }
	} $config_file;
	system($_) foreach ("/bin/cp /usr/share/Bastille/bastille-ipchains /usr/share/Bastille/bastille-netfilter /sbin",
			    "/bin/cp /usr/share/Bastille/bastille-firewall /etc/rc.d/init.d/",
			    "/bin/chmod 0700 /etc/rc.d/init.d/bastille-firewall", "/bin/chmod 0700 /sbin/bastille-ipchains",
			    "/bin/chmod 0700 /sbin/bastille-netfilter", "/sbin/chkconfig bastille-firewall on",
			    "/etc/rc.d/init.d/bastille-firewall stop", "/etc/rc.d/init.d/bastille-firewall start") };
    my @struct = (
		  [$GetNetworkInfo],
		  [],
		  [undef , undef, undef, undef, ["tcp", "80"], ["tcp", "443"]],
		  [undef , undef, undef, undef, ["tcp", "53"], ["udp", "53"]],
		  [undef , undef, undef, undef, ["tcp", "22"]],
		  [undef , undef, undef, undef, ["tcp", "23"]],
		  [undef , undef, undef, undef, ["tcp", "20"],["tcp", "21"]],
		  [undef , undef, undef, undef, ["tcp", "25"]],
		  [undef , undef, undef, $popimap, ["tcp", "109"], ["tcp", "110"], ["tcp", "143"]],
		  [undef , _("No I don't need DHCP"), _("Yes I need DHCP"), $dhcp],
		  [undef , _("No I don't need NTP"), _("Yes I need NTP"), $ntp ],
		  [undef , _("Don't Save"), _("Save & Quit"), $quit ]
		 );
    if (!Kernel22()) { 
	pop @struct; pop @struct; pop @struct;
	@struct = (@struct, [undef , _("Don't Save"), _("Save & Quit"), $quit ]);
	$messages[9]=$messages[11];
    }
    for (my $i = 0; $i<@struct; $i++) {
	$::Wizard_no_previous = $i == 0;
	$::Wizard_finished = $i == $#struct;
	my $l = $struct[$i];
	@$l or goto ask;
	if (@$l == 1) {
	    ($l->[0])->();
	  ask:
	    $in->ask_okcancel(_("Firewall Configuration Wizard"), $messages[$i],1) ? next : goto prev;
	}
	my $no = $l->[1] ? $l->[1] : _("No (firewall this off from the internet)");
	my $yes = $l->[2] ? $l->[2] : _("Yes (allow this through the firewall)");
	if (my $e = $in->ask_from_list_(_("Firewall Configuration Wizard"),
				       $messages[$i],
				       [ $yes, $no ], or_(map { $_ && CheckService($_->[0], $_->[1]) } (@$l[4..6])) ? $yes : $no
				      )) {
	    map { $_ and Service($e=~/Yes/, $_->[0], $_->[1]) } (@{$struct[$i]}[4..6]);
	    $struct[$i][3] and $struct[$i][3]->($e=~/Yes/ || $e eq _("Save & Quit"));
	} else {
	  prev:
	    $i = $i-2 >= -1 ? $i-2 : -1;
	}
    }
}
sub unbox_service {
    split ' ', $settings{uc($_[0]) . "_PUBLIC_SERVICES"}
}
sub Service {
    my ($add, $protocol, $port) = @_;
    my @l = unbox_service($protocol);
    @l = uniq($add ? (@l, $port) : grep { $_ ne $port } @l);
    $settings{uc($protocol) . "_PUBLIC_SERVICES"} = join(' ', @l);
}
sub CheckService { member($_[1], unbox_service($_[0])) }
sub Kernel22 {
    my ($major, $minor, $patchlevel) = (cat_("/proc/version"))[0] =~ m/^Linux version ([0-9]+)\.([0-9]+)\.([0-9]+)/;
    $major eq "2" && $minor eq "2";
}
sub main {
    my ($in)=@_;
    my $dialog = new Gtk::Dialog();
    $dialog->set_position(1);
    $dialog->vbox->set_border_width(10);
    my $label = new Gtk::Label(_("Please Wait... Verifying installed packages"));
    $dialog->signal_connect (delete_event => sub { Gtk->main_quit() });
    $dialog->vbox->pack_start($label,1,1,20);
    $dialog->show_all;
    Gtk->main_iteration while Gtk->events_pending;
    if (!$in->do_pkgs->install(Kernel22() ? "ipchains" : "iptables", "Bastille")) {
	$in->ask_warn('', _("Failure installing the needed packages : %s and Bastille.
 Try to install them manually.", Kernel22() ? "ipchains" : "iptables") );
	$dialog->destroy;
	$in->exit(0);
    }
    ReadConfig;
    DoInterface($in);
}
