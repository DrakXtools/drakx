package services;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional :system :file);
use commands;
use run_program;

my %services = (
anacron => __("Anacron a periodic command scheduler."),
apmd => __("apmd is used for monitoring batery status and logging it via syslog.
It can also be used for shutting down the machine when the battery is low."),
atd => __("Runs commands scheduled by the at command at the time specified when
at was run, and runs batch commands when the load average is low enough."),
crond => __("cron is a standard UNIX program that runs user-specified programs
at periodic scheduled times. vixie cron adds a number of features to the basic
UNIX cron, including better security and more powerful configuration options."),
gpm => __("GPM adds mouse support to text-based Linux applications such the
Midnight Commander. Is also allows mouse-based console cut-and-paste operations,
and includes support for pop-up menus on the console."),
httpd => __("Apache is a World Wide Web server.  It is used to serve HTML files
and CGI."),
inet => __("The internet superserver daemon (commonly called inetd) starts a
variety of other internet services as needed. It is responsible for starting
many services, including telnet, ftp, rsh, and rlogin. Disabling inetd disables
all of the services it is responsible for."),
keytable => __("This package loads the selected keyboard map as set in
/etc/sysconfig/keyboard.  This can be selected using the kbdconfig utility.  You
should leave this enabled for most machines."),
lpd => __("lpd is the print daemon required for lpr to work properly. It is
basically a server that arbitrates print jobs to printer(s)."),
named => __("named (BIND) is a Domain Name Server (DNS) that is used to resolve
host names to IP addresses."),
netfs => __("Mounts and unmounts all Network File System (NFS), SMB (Lan
Manager/Windows), and NCP (NetWare) mount points."),
network => __("Activates/Deactivates all network interfaces configured to start
at boot time."),
nfs => __("NFS is a popular protocol for file sharing across TCP/IP networks.
This service provides NFS server functionality, which is configured via the
/etc/exports file."),
nfslock => __("NFS is a popular protocol for file sharing across TCP/IP
networks. This service provides NFS file locking functionality."),
pcmcia => __("PCMCIA support is usually to support things like ethernet and
modems in laptops.  It won't get started unless configured so it is safe to have
it installed on machines that don't need it."),
portmap => __("The portmapper manages RPC connections, which are used by
protocols such as NFS and NIS. The portmap server must be running on machines
which act as servers for protocols which make use of the RPC mechanism."),
postfix => __("Postfix is a Mail Transport Agent, which is the program that
moves mail from one machine to another."),
random => __("Saves and restores system entropy pool for higher quality random
number generation."),
routed => __("The routed daemon allows for automatic IP router table updated via
the RIP protocol. While RIP is widely used on small networks, more complex
routing protocls are needed for complex networks."),
rstatd => __("The rstat protocol allows users on a network to retrieve
performance metrics for any machine on that network."),
rusersd => __("The rusers protocol allows users on a network to identify who is
logged in on other responding machines."),
rwhod => __("The rwho protocol lets remote users get a list of all of the users
logged into a machine running the rwho daemon (similiar to finger)."),
syslog => __("Syslog is the facility by which many daemons use to log messages
to various system log files.  It is a good idea to always run syslog."),
usb => __("This startup script try to load your modules for your usb mouse."),
xfs => __("Starts and stops the X Font Server at boot time and shutdown."),
);

sub drakxservices {
    my ($in, $prefix) = @_;
    my $cmd = $prefix ? "chroot $prefix" : "";
    my @services = map { [/(\S+)/, /:on/ ] } sort `$cmd chkconfig --list`;
    my @l      = map { $_->[0] } @services;
    my @before = map { $_->[1] } @services;
    my @descr  = map {
	my $s = $services{$_};
	if ($s) {
	    $s = translate($s);
	} else {
	    ($s = cat_("$prefix/etc/rc.d/init.d/$_")) =~ s/\\\s*\n#\s*//mg;
	    ($s) = $s =~ /^# description:\s+(.*?)^(?:[^#]|# {0,2}\S)/sm;
	    $s =~ s/^#\s*//m;
	}
	$s =~ s/\n/ /gm; $s =~ s/\s+$//;
	$s;
    } @l;

    my $after = $in->ask_many_from_list_with_help("drakxservices",
						  _("Choose which services should be automatically started at boot time"),
						  \@l, \@descr, \@before) or return;

    mapn { 
	my ($name, $before, $after) = @_;
	if ($before != $after) {
	    run_program::rooted($prefix, "chkconfig", $after ? "--add" : "--del", $name);
	    if ($after && cat_("$prefix/etc/rc.d/init.d/$name") =~ /^#\s+chkconfig:\s+-/m) {
		#- `/sbin/runlevel` =~ /\s(\d+)/ or die "bad runlevel";
		#- $1 == 3 || $1 == 5 or log::l("strange runlevel: ``$1'' (neither 3 nor 5)");
		run_program::rooted($prefix, "chkconfig", "--level", "35", $name, "on");
	    }
	}
    } \@l, \@before, $after;
}
