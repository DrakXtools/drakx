package tinyfirewall;

use diagnostics;
use strict;
use common qw(:common :functional :system :file);
use commands;
use run_program;
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
sub ReadConfig {
    my ($config_file, $default_config_file)=@_;
    $config_file ||= "/etc/Bastille/bastille-firewall.cfg";
    $default_config_file ||= "/usr/share/Bastille/bastille-firewall.cfg"; # set this later
    -e $config_file or cp($default_config_file, $config_file);
    add2hash(\%settings, { getVarsFromSh("$config_file") })
}

my $GetNetworkInfo = sub { print "in int! :=\n"};

sub DoInterface {
    my ($in)=@_;
    $::isWizard=1;
    my @struct = (
		  [$GetNetworkInfo],
		  [],
		  [undef , undef, undef, "http no", "http yes", ["tcp", "80"], ["tcp", "443"]],
		  [undef , undef, undef, "dns no", "dns yes", ["tcp", "53"], ["udp", "53"]],
		  [undef , undef, undef, "ssh no", "ssh yes", ["tcp", "22"]],
		  [undef , undef, undef, "telnet no", "telnet yes", ["tcp", "23"]],
		  [undef , undef, undef, "ftp no", "ftp yes", ["tcp", "20"],["tcp", "21"]],
		  [undef , undef, undef, "smtp no", "smtp yes", ["tcp", "25"]],
		  [undef , undef, undef, "popimap no", "popimap yes", ["tcp", "109"], ["tcp", "110"], ["tcp", "143"]],
		  [undef , _("No I don't need DHCP"), "Yes I need DHCP", "dhcp no", "dhcp yes", [$settings{DHCP_IFACES}]],
		  [undef , _("No I don't need NTP"), "Yes I need NTP", "ntp no", "ntp yes", ]
		 );
    my $totalsteps = @struct;
    $totalsteps -= 2 if !Kernel22();
    #   $curstep=0;
    #   my $step = "Step " . ($curstep eq $num_steps && !Kernel22() ? $curstep - 2 : $curstep) . " / $totalsteps\n\n";

    foreach (0..@struct) {
	my $l = $struct[$_];
	my $size=@$l;
	$size or next;
	print "### $size ###\n";
	$size == 1 and ($l->[0])->();
	my $no = $l->[1] ? $l->[1] : _("No (firewall this off from the internet)");
	my $yes = $l->[2] ? $l->[2] : _("Yes (allow this through the firewall)");
	print "Y : $yes\n";
	print "N : $no\n";
	if ($in->ask_from_list(_("Firewall Configuration Wizard"),
			       $messages[$_],
			       [ $yes, $no ], or_( map { if_($_, CheckService($_->[0], $_->[1])) } (@$l[5..7])) ? $yes : $no
			      )) {
	    print "EEEEEEEEEEEEEEEEE\n";
	} else {
	    print "NNNNNNNNNNN\n";
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
