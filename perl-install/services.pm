package services; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional :system :file);
use commands;
use run_program;
use my_gtk qw(:helpers :wrappers);
use Data::Dumper;

sub description {
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
Midnight Commander. It also allows mouse-based console cut-and-paste operations,
and includes support for pop-up menus on the console."),
httpd => __("Apache is a World Wide Web server.  It is used to serve HTML files
and CGI."),
inet => __("The internet superserver daemon (commonly called inetd) starts a
variety of other internet services as needed. It is responsible for starting
many services, including telnet, ftp, rsh, and rlogin. Disabling inetd disables
all of the services it is responsible for."),
keytable => __("This package loads the selected keyboard map as set in
/etc/sysconfig/keyboard.  This can be selected using the kbdconfig utility.
You should leave this enabled for most machines."),
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
routing protocols are needed for complex networks."),
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
    my ($name, $prefix) = @_;
    my $s = $services{$name};
    if ($s) {
	$s = translate($s);
    } else {
	($s = cat_("$prefix/etc/rc.d/init.d/$_")) =~ s/\\\s*\n#\s*//mg;
	($s) = $s =~ /^# description:\s+(.*?)^(?:[^#]|# {0,2}\S)/sm;
	$s =~ s/^#\s*//m;
    }
    $s =~ s/\n/ /gm; $s =~ s/\s+$//;
    $s;
}

#- returns: 
#--- the listref of installed services
#--- the listref of "on" services
sub services {
    my ($prefix) = @_;
    my $cmd = $prefix ? "chroot $prefix" : "";
    my @l = map { [ /([^\s:]+)/, /\bon\b/ ] } grep { !/:$/ } sort `LANGUAGE=C $cmd chkconfig --list`;
    [ map { $_->[0] } @l ], [ mapgrep { $_->[1], $_->[0] } @l ];
}

sub ask {
    my ($in, $prefix) = @_;
    my ($l, $on_services) = services($prefix);
    ref($in) !~ /gtk/ and return $in->ask_many_from_list("drakxservices",
			    _("Choose which services should be automatically started at boot time"),
			    {
			     list => $l,
			     help => sub { description($_, $prefix) },
			     values => $on_services,
			     sort => 1,
			    });
    my $W = my_gtk->new(_("Resolution"));
    my ($x, $y, $w_popup);
    gtkadd($W->{window}, gtkadd(my $b = new Gtk::EventBox(), gtkpack_($W->create_box_with_title(_("Services and deamons")),
	1, gtkset_usize(createScrolledWindow(create_packtable({ col_spacings => 10, row_spacings => 3 },
	    map {
        	my $infos_old = description($_, $prefix);
		my $infos;
		while ($infos_old =~ s/(.{40})//) {
                    $1 =~ /(.*) ([^ ]*)/;
		    $infos .= "$1\n$2";
                }
                $infos .= $infos_old;
                $infos ||= "No additionnal information\n about this service, sorry.";
        	my $stopped = `service $_ status` =~ /stop/;
		my $started = `service $_ status` =~ /running/;
		my $state; $started && -e "/var/lock/subsys/$_" and $state="running";
		$stopped and $state="running";
		$state ||= "unknown";
		my $w;
		[ gtkpack__(new Gtk::HBox(0,0), $_),
		  gtkpack__(new Gtk::HBox(0,0), $state),
		  gtkpack__(new Gtk::HBox(0,0), gtksignal_connect(new Gtk::Button("Infos"), clicked => sub {
                          $w_popup and $w_popup->destroy;
			  gtkmove(gtkshow(gtkadd($w_popup=new Gtk::Window (-popup),
        				       gtksignal_connect(gtkadd(new Gtk::EventBox(),
        				           gtkadd(gtkset_shadow_type(new Gtk::Frame, 'etched_out'),
        					   gtkset_justify(new Gtk::Label($infos), 0))),
        					   button_press_event => sub { $w_popup->destroy; }
		      ))), $x, $y);}))
		]
	    }
            @$l)), 450, 400)))
	  );
    $b->set_events(["pointer_motion_mask"]);
    $b->signal_connect( motion_notify_event => sub { my ($w, $e) = @_;
                                                               my ($ox, $oy) = $w->window->get_deskrelative_origin;
                                                               $x = $e->{'x'}+$ox; $y = $e->{'y'}+$oy; });
    $b->signal_connect( button_press_event => sub { $w_popup and $w_popup->destroy;});
    $W->main or return;
}

sub doit {
    my ($in, $on_services, $prefix) = @_;
    my ($l, $was_on_services) = services($prefix);

    foreach (@$l) {
	my $before = member($_, @$was_on_services);
	my $after = member($_, @$on_services);
	if ($before != $after) {
	    my $script = "/etc/rc.d/init.d/$_";
	    run_program::rooted($prefix, "chkconfig", $after ? "--add" : "--del", $_);
	    if ($after && cat_("$prefix$script") =~ /^#\s+chkconfig:\s+-/m) {
		run_program::rooted($prefix, "chkconfig", "--level", "35", $_, "on");
	    }
	    if (!$after && $::isStandalone) {
		run_program::rooted($prefix, $script, "stop");
	    }
	}
    }
}


1;
