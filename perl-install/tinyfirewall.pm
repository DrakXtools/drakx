package tinyfirewall;

use diagnostics;
use strict;
use common qw(:common :functional :system :file);
use commands;
use run_program;
use netconnect;
use network;
use my_gtk qw(:helpers :wrappers);

my @messages = (_("tinyfirewall configurator

This configures a personal firewall for this Linux Mandrake machine.
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
accessed by this machine, you can safely answer NO here."),
_("Are you running a name server on this machine? If you didn't set one
up to give away IP and zone information to the whole Internet, please
answer no."),
_("Do you want to allow incoming Secure Shell (ssh) connections? This
is a telnet-replacement that you might use to login. If you're using
telnet now, you should definitely switch to ssh. telnet is not
encrypted -- so some attackers can steal your password if you use
it. ssh is encrypted and doesn't allow for this eavesdropping."),
_("Do you want to allow incoming telnet connections?
This is horribly unsafe, as we explained in the previous screen. We
strongly recommend answering No here and using ssh in place of
telnet."),
_("Are you running an FTP server here that you need accessible to the
Internet? If you are, we strongly recommend that you only use it for
Anonymous transfers. Any passwords sent by FTP can be stolen by some
attackers, since FTP also uses no encryption for transferring passwords."),
_("Are you running a mail server here? If you're sending you 
messages through pine, mutt or any other text-based mail client,
you probably are.  Otherwise, you should firewall this off."),
_("Are you running a POP or IMAP server here? This would
be used to host non-web-based mail accounts for people via 
this machine."),
_("You appear to be running a 2.2 kernel.  If your network IP
is automatically set by a computer in your home or office 
(dynamically assigned), we need to allow for this.  Is
this the case?"),
_("Is your computer getting time syncronized to another computer?
Mostly, this is used by medium-large Unix/Linux organizations
to synchronize time for logging and such.  If you're not part
of a larger office and haven't heard of this, you probably 
aren't."),
_("Configuration complete.  May we write these changes to disk?")
);

my %settings;
#sub ReadConfig {
my $config_file = "/etc/Bastille/bastille-firewall.cfg";
my $default_config_file = "/usr/share/Bastille/bastille-firewall.cfg"; # set this later
sub ReadConfig
##############################
## Reads the default values from $config_file
{
	## if $config_file doesn't exist, move the
	## $default_config_file to $config_file

	system ("/bin/cp $default_config_file $config_file")
	       	if !( -e $config_file);


	open CONFIGFILE, $config_file
		or die "Can't open $config_file: $!\n";

	while (my $line = <CONFIGFILE>)
	{
		$line =~ s/\#.*$//;  # remove comments
		$line =~ s/^\s+//;   # remove leading whitespace
		$line =~ s/\s+$//;   # remove tailing whitespace	
		$line =~ s/\s+/ /;   # remove extra whitespace	


		## what's left will be useful stuff, so
		## get the values

		$line =~ m/^(.+)\s*\=\s*\"(.*)\"\s*$/;
		my ($variable, $value) = ($1, $2);


		## set the proper value in the hash
		
		$settings{$variable} = $value
			if ($variable);
	}

	close CONFIGFILE;
	return;
    my ($config_file, $default_config_file)=@_;
    $config_file ||= "/etc/Bastille/bastille-firewall.cfg";
    $default_config_file ||= "/usr/share/Bastille/bastille-firewall.cfg";
    -e $config_file or cp($default_config_file, $config_file);
    add2hash(\%settings, { getVarsFromSh("$config_file") });
}

my $GetNetworkInfo = sub {
    $settings{DNS_SERVERS} = join(' ', uniq(split(' ', $settings{DNS_SERVERS}),
            @{network::read_resolv_conf("/etc/resolv.conf")}{'dnsServer', 'dnsServer2', 'dnsServer3'}));
    open NETSTAT, "/bin/netstat -in |" or die "Can't pipe from /bin/netstat: $!\n"; <NETSTAT>; <NETSTAT>;
    my @interfaces = map { (split / /)[0]; } (<NETSTAT>); close NETSTAT;
    open ROUTE, "/sbin/route -n |" or die "Can't pipe from /sbin/route: $!\n"; <ROUTE>; <ROUTE>;
    my $defaultgw;
    my $iface;
    while (<ROUTE>) {
	my @parts = split /\s+/;
	($parts[0] eq "0.0.0.0") and $defaultgw = $parts[1], $iface = $parts[7];
    } close ROUTE;
    my $fulliface = $iface;
    $fulliface =~ s/[0-9]+/\\\+/;    # so we can match eth0 against eth+, for example
    $settings{PUBLIC_INTERFACES} = join(' ', uniq(split(' ', $settings{PUBLIC_INTERFACES}), $iface));
    $settings{PUBLIC_INTERFACES} =~ $fulliface and $settings{PUBLIC_INTERFACES} =~ s/$iface *//;
    $settings{INTERNAL_IFACES} = join(' ', uniq(split(' ', $settings{INTERNAL_IFACES}),
            map { my $i=$_; my $f=$i; $f=~s/[0-9]+/\\\+/;
		  if_(and_( map {$settings{$_} !~ /$i/ and $settings{$_} !~ /$f/ } ('TRUSTED_IFACES', 'PUBLIC_IFACES', 'INTERNAL_IFACES')), $i)
	      } (@interfaces) ));
};

sub DoInterface {
    my ($in)=@_;
    $::isWizard=1;
    my $popimapno = sub { $_[0] or return; mapn { $settings{$_->[0]} = $_->[1] } (
[ qw(FORCE_PASV_FTP TCP_BLOCKED_SERVICES UDP_BLOCKED_SERVICES ICMP_ALLOWED_TYPES ENABLE_SRC_ADDR_VERIFY IP_MASQ_NETWORK IP_MASQ_MODULES REJECT_METHOD) ] ,
[ "N", "6000:6020", "2049", "destination-unreachable echo-reply time-exceeded" , "Y", "", "", "DENY"; ]); }
    my @struct = (
		  [$GetNetworkInfo],
		  [],
		  [undef , undef, undef, undef, ["tcp", "80"], ["tcp", "443"]],
		  [undef , undef, undef, undef, ["tcp", "53"], ["udp", "53"]],
		  [undef , undef, undef, undef, ["tcp", "22"]],
		  [undef , undef, undef, undef, ["tcp", "23"]],
		  [undef , undef, undef, undef, ["tcp", "20"],["tcp", "21"]],
		  [undef , undef, undef, undef, ["tcp", "25"]],
		  [undef , undef, undef, $popimapno, ["tcp", "109"], ["tcp", "110"], ["tcp", "143"]],
		  [undef , _("No I don't need DHCP"), _("Yes I need DHCP"), , [$settings{DHCP_IFACES}]],
		  [undef , _("No I don't need NTP"), _("Yes I need NTP"), , ]
		  [undef , _("Don't Save"), _("Save & Quit"), , , ]
		 );
    !Kernel22() and pop @struct, pop @struct;
    for (my $i=0;$i<@struct;$i++) {
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
	if (my $e = $in->ask_from_list(_("Firewall Configuration Wizard"),
				       $messages[$i],
				       [ $yes, $no ], or_( map { if_($_, CheckService($_->[0], $_->[1])) } (@$l[4..6])) ? $yes : $no
				      )) {
	    map { if_($_, Service ($e=~/Yes/, $_->[0], $_->[1]) } (@$struct[$i][4..6]);
	    $struct[$i][3] and $struct[$i][3]->($e=~/Yes/);
	} else {
	  prev:
	    $i = $i-2 >= -1 ? $i-2 : -1;
	}
    }
}


sub Service {
    my ($add, $protocol, $port) = @_;
    if ($add) {
	map { $_ eq $port and return } (split (' ', $settings{uc($protocol) . "_PUBLIC_SERVICES"}));
	$settings{uc($protocol) . "_PUBLIC_SERVICES"} .= " " . $port;
    } else {
	$settings{uc($protocol) . "_PUBLIC_SERVICES"} =
	  join( ' ', map { if_($service ne $port, $service)} (split (' ', $settings{uc($protocol) . "_PUBLIC_SERVICES"})) );
    }
}

sub AddService
#######################
## adds a port to [TCP|UDP]_PUBLIC_SERVICES if it's not already there
{

	my @old_services;


	foreach my $service (@old_services)
	{
		$port_active = 1 if ($service eq $port);
	}

	$settings{TCP_PUBLIC_SERVICES} .= " "
		if ($settings{TCP_PUBLIC_SERVICES} and ($protocol eq "tcp") and (!$port_active));

	$settings{UDP_PUBLIC_SERVICES} .= " "
		if ($settings{UDP_PUBLIC_SERVICES} and ($protocol eq "udp") and (!$port_active));

	$settings{TCP_PUBLIC_SERVICES} .= $port
		if (!$port_active and ($protocol eq "tcp"));

	$settings{UDP_PUBLIC_SERVICES} .= $port
		if (!$port_active and ($protocol eq "udp"));		
}

sub WidgetHandler {
    my ($i, $e)=@_;

	if ($data eq "save no")
	{
		Gtk->exit (0);
	}
	elsif ($data eq "save yes")
	{
		CloseWindow();
	}
	elsif ($data eq "quit no")
	{
		DestroyStep();
		$curstep = $previous_step;
		DoInterface();
		return 0;
	}

		  [undef , _("No I don't need DHCP"), _("Yes I need DHCP"), "dhcp no", "dhcp yes", [$settings{DHCP_IFACES}]],
		  [undef , _("No I don't need NTP"), _("Yes I need NTP"), "ntp no", "ntp yes", ]
		  [undef , _("Don't Save"), _("Save & Quit"), , , ]

		elsif ($data eq "dhcp yes")
		{
			return if $settings{DHCP_IFACES};  # variable already has something
			
			## Get a list of network interfaces

			open NETSTAT, "/bin/netstat -in |"
				or die "Can't pipe from /bin/netstat: $!\n";

			<NETSTAT>; <NETSTAT>;   # get rid of first 2 lines
	
			my @interfaces;
		
			while (<NETSTAT>)
			{
				$settings{DHCP_IFACES} .= (split / /)[0] . " ";
			}	

			close NETSTAT;	

			chop $settings{DHCP_IFACES}
		}
		elsif ($data eq "dhcp no")
		{
			$settings{DHCP_IFACES} = "";
		}
		elsif ($data eq "ntp yes")
		{
			$settings{ICMP_OUTBOUND_DISABLED_TYPES} = "";
			$settings{LOG_FAILURES} = "N";
		}


				
	}
}

sub CheckService {
    my ($protocol, $port) = @_;
    my @services;

    @services = split / /, $settings{uc($protocol) . "_PUBLIC_SERVICES"};
    map { $_ eq $port and return 1 } @services;
}

sub Kernel22
{
    my ($major, $minor, $patchlevel) = (cat_("/proc/version"))[0] =~ m/^Linux version ([0-9]+)\.([0-9]+)\.([0-9]+)/;
    $major eq "2" && $minor eq "2";
}

sub main {
    my ($in)=@_;
    ReadConfig;
    DoInterface($in);
}
