package services; # $Id$




#-######################################################################################
#- misc imports
#-######################################################################################

use strict;
use common;
use run_program;

use common;
use run_program;

sub description {
    my %services = (
alsa => N_("Launch the ALSA (Advanced Linux Sound Architecture) sound system"),
anacron => N_("Anacron is a periodic command scheduler."),
apmd => N_("apmd is used for monitoring battery status and logging it via syslog.
It can also be used for shutting down the machine when the battery is low."),
atd => N_("Runs commands scheduled by the at command at the time specified when
at was run, and runs batch commands when the load average is low enough."),
crond => N_("cron is a standard UNIX program that runs user-specified programs
at periodic scheduled times. vixie cron adds a number of features to the basic
UNIX cron, including better security and more powerful configuration options."),
gpm => N_("GPM adds mouse support to text-based Linux applications such the
Midnight Commander. It also allows mouse-based console cut-and-paste operations,
and includes support for pop-up menus on the console."),
harddrake => N_("HardDrake runs a hardware probe, and optionally configures
new/changed hardware."),
httpd => N_("Apache is a World Wide Web server. It is used to serve HTML files and CGI."),
inet => N_("The internet superserver daemon (commonly called inetd) starts a
variety of other internet services as needed. It is responsible for starting
many services, including telnet, ftp, rsh, and rlogin. Disabling inetd disables
all of the services it is responsible for."),
ipchains => N_("Launch packet filtering for Linux kernel 2.2 series, to set
up a firewall to protect your machine from network attacks."),
keytable => N_("This package loads the selected keyboard map as set in
/etc/sysconfig/keyboard.  This can be selected using the kbdconfig utility.
You should leave this enabled for most machines."),
kheader => N_("Automatic regeneration of kernel header in /boot for
/usr/include/linux/{autoconf,version}.h"),
kudzu => N_("Automatic detection and configuration of hardware at boot."),
linuxconf => N_("Linuxconf will sometimes arrange to perform various tasks
at boot-time to maintain the system configuration."),
lpd => N_("lpd is the print daemon required for lpr to work properly. It is
basically a server that arbitrates print jobs to printer(s)."),
lvs => N_("Linux Virtual Server, used to build a high-performance and highly
available server."),
named => N_("named (BIND) is a Domain Name Server (DNS) that is used to resolve host names to IP addresses."),
netfs => N_("Mounts and unmounts all Network File System (NFS), SMB (Lan
Manager/Windows), and NCP (NetWare) mount points."),
network => N_("Activates/Deactivates all network interfaces configured to start
at boot time."),
nfs => N_("NFS is a popular protocol for file sharing across TCP/IP networks.
This service provides NFS server functionality, which is configured via the
/etc/exports file."),
nfslock => N_("NFS is a popular protocol for file sharing across TCP/IP
networks. This service provides NFS file locking functionality."),
numlock => N_("Automatically switch on numlock key locker under console
and XFree at boot."),
oki4daemon => N_("Support the OKI 4w and compatible winprinters."),
pcmcia => N_("PCMCIA support is usually to support things like ethernet and
modems in laptops.  It won't get started unless configured so it is safe to have
it installed on machines that don't need it."),
portmap => N_("The portmapper manages RPC connections, which are used by
protocols such as NFS and NIS. The portmap server must be running on machines
which act as servers for protocols which make use of the RPC mechanism."),
postfix => N_("Postfix is a Mail Transport Agent, which is the program that moves mail from one machine to another."),
random => N_("Saves and restores system entropy pool for higher quality random
number generation."),
rawdevices => N_("Assign raw devices to block devices (such as hard drive
partitions), for the use of applications such as Oracle"),
routed => N_("The routed daemon allows for automatic IP router table updated via
the RIP protocol. While RIP is widely used on small networks, more complex
routing protocols are needed for complex networks."),
rstatd => N_("The rstat protocol allows users on a network to retrieve
performance metrics for any machine on that network."),
rusersd => N_("The rusers protocol allows users on a network to identify who is
logged in on other responding machines."),
rwhod => N_("The rwho protocol lets remote users get a list of all of the users
logged into a machine running the rwho daemon (similiar to finger)."),
sound => N_("Launch the sound system on your machine"),
syslog => N_("Syslog is the facility by which many daemons use to log messages
to various system log files.  It is a good idea to always run syslog."),
usb => N_("Load the drivers for your usb devices."),
xfs => N_("Starts the X Font Server (this is mandatory for XFree to run)."),
    );
    my ($name, $prefix) = @_;
    my $s = $services{$name};
    if ($s) {
	$s = translate($s);
    } else {
	$s = -e "$prefix/etc/rc.d/init.d/$name" && cat_("$prefix/etc/rc.d/init.d/$name");
	$s ||= -e "$prefix/etc/init.d/$name" && cat_("$prefix/etc/init.d/$name");
	$s ||= -e "$prefix/etc/xinetd.d/$name" && cat_("$prefix/etc/xinetd.d/$name");
	$s =~ s/\\\s*\n#\s*//mg;
	if ($s =~ /^# description:\s+\S/sm) {
	    ($s) = $s =~ /^# description:\s+(.*?)^(?:[^#]|# {0,2}\S)/sm;
	} else {
	    ($s) = $s =~ /^#\s*(.*?)^[^#]/sm;
	}
	$s =~ s/#\s*//mg;
    }
    $s =~ s/\n/ /gm; $s =~ s/\s+$//;
    $s;
}

sub ask_install_simple {
    my ($in, $prefix) = @_;
    my ($l, $on_services) = services($prefix);
    $in->ask_many_from_list("drakxservices",
			    N("Choose which services should be automatically started at boot time"),
			    {
			     list => $l,
			     help => sub { description($_[0], $prefix) },
			     values => $on_services,
			     sort => 1,
			    });
}

sub ask_install {
    my ($in, $prefix) = @_;
    my %root_services = (
			 N("Printing") => [ qw(cups cupslpd lpr lpd oki4daemon hpoj cups-lpd) ],
			 N("Internet") => [ qw(httpd boa tux roxen ftp pftp tftp proftpd wu-ftpd pure-ftpdipsec proftpd-xinetd
                                               ipchains iptables ipvsadm isdn4linux ibod jabber jabber-icq adsl squid
                                               portsentry prelude nessusd junkbuster radvd cddbp ippl iptoip jail.init) ],
			 N("File sharing") => [ qw(nfs nfslock smb nettalk netfs mcserv autofs amd
                                                   venus.init auth2.init codasrv.init update.init swat) ],
			 N("System") => [ qw(usb usbd pcmcia irda xinetd inetd kudzu harddrake apmd sound network xfs
                                             alsa functions halt kheader killall mandrake_everytime mandrake_firstime
                                             random rawdevices single keytable syslog crond medusa-init portmap acon
                                             anacron atd gpm psacct wine acpid numlock jserver sensors mosix bpowerd bpowerfail
                                             fcron powertweak.init ups syslog-ng cvs apcupsd) ],
			 N("Remote Administration") => [ qw(sshd telnetd telnet rsh rlogin rexec webmin cfd heartbeat ldirectord
                                                            iplog mon vncserver netsaint olympusd drakxtools_http) ],
#			 N("Network Client") => [ qw(ypbind nscd arpwatch fetchmail dnrd_rc diald rsync) ],
#			 N("Network Server") => [ qw(named bootparamd ntpd xntpd chronyd postfix sendmail
#                                                     imap imaps ipop2 ipop3 pop3s routed yppasswdd ypserv ldap dhcpd dhcrelay
#                                                     hylafax innd identd rstatd rusersd rwalld rwhod gated
#                                                     kadmin kprop krb524 krb5kdc krb5server hldsld bayonne sockd dhsd gnu-pop3d
#                                                     gdips pptpd.conf vrrpd crossfire bnetd pvmd ircd sympa finger ntalk talk) ],
			 N("Database Server") => [ qw(mysql postgresql) ],
			);
    my %services_root;
    foreach my $root (keys %root_services) {
	$services_root{$_} = $root foreach @{$root_services{$root}};
    }
    my ($l, $on_services) = services($prefix);
    my %services;
    $services{$_} = 0 foreach @{$l || []};
    $services{$_} = 1 foreach @{$on_services || []};

    $in->ask_browse_tree_info('drakxservices', N("Choose which services should be automatically started at boot time"),
			      {
			       node_state => sub { $services{$_[0]} ? 'selected' : 'unselected' },
			       build_tree => sub {
				   my ($add_node, $flat) = @_;
				   $add_node->($_, !$flat && ($services_root{$_} || N("Other")))
				     foreach sort keys %services;
			       },
			       grep_unselected => sub { grep { !$services{$_} } @_ },
			       toggle_nodes => sub {
				   my ($set_state, @nodes) = @_;
				   my $new_state = !$services{$nodes[0]};
				   foreach (@nodes) {
				       $set_state->($_, $new_state ? 'selected' : 'unselected');
				       $services{$_} = $new_state;
				   }
			       },
			       get_status => sub {
				   N("Services: %d activated for %d registered", 
				     scalar(grep { $_ } values %services),
				     scalar(values %services));
			       },
			       get_info => sub { formatLines(description($_[0], $prefix)) },
			      }) or return ($l, $on_services); #- no change on cancel.
    [ grep { $services{$_} } @$l ];
}

sub ask_standalone_gtk {
    my ($_in, $prefix) = @_;
    my ($l, $on_services) = services($prefix);

    require ugtk2;
    ugtk2->import(qw(:wrappers :create));

    my $W = ugtk2->new(N("Services"));
    my ($x, $y, $w_popup);
    my $nopop = sub { $w_popup and $w_popup->destroy };
    my $display = sub { $nopop->(); $_[0] and gtkshow(gtkadd($w_popup = Gtk2::Window->new('popup'),
        				       gtksignal_connect(gtkadd(Gtk2::EventBox->new,
        				           gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'etched_out'),
        					   gtkset_justify(Gtk2::Label->new($_[0]), 'left'))),
        					   button_press_event => sub { $nopop->() }
		      )))->move($x, $y) };
    my $update_service = sub {
		my $started = -e "/var/lock/subsys/$_[0]";
                my $action = $started ? "stop" : "start";
                $_[1]->set($started ? N("running") : N("stopped"));
                $started, $action;
    };
    my $b = Gtk2::EventBox->new;
    $b->set_events('pointer_motion_mask');
    gtkadd($W->{window}, gtkadd($b, gtkpack_($W->create_box_with_title(N("Services and deamons")),
	1, gtkset_size_request(create_scrolled_window(create_packtable({ col_spacings => 10, row_spacings => 3 },
	    map {
                my $service = $_;
        	my $infos = warp_text(description($_, $prefix), 40);
                $infos ||= N("No additional information\nabout this service, sorry.");
		my $l = Gtk2::Label->new;
                my ($started, $action) = $update_service->($service, gtkset_justify($l, 'left'));
		[ gtkpack__(Gtk2::HBox->new(0,0), $_),
		  gtkpack__(Gtk2::HBox->new(0,0), $l),
		  gtkpack__(Gtk2::HBox->new(0,0), gtksignal_connect(Gtk2::Button->new(N("Info")), clicked => sub { $display->($infos) })),
                  gtkpack__(Gtk2::HBox->new(0,0), gtkset_active(gtksignal_connect(
                          Gtk2::CheckButton->new(N("On boot")),
                          clicked => sub { if ($_[0]->active) {
                                               push @$on_services, $service if !member($service, @$on_services);
                                           } else {
                                               @$on_services = grep { $_ ne $service } @$on_services;
                                        } }), member($service, @$on_services))),
		  map { my $a = $_;
                      gtkpack__(Gtk2::HBox->new(0,0), gtksignal_connect(Gtk2::Button->new(translate($a)),
                          clicked => sub { my $c = "service $service " . (lc($a) eq "start" ? "restart" : lc($a)) . " 2>&1"; local $_ = `$c`; s/\033\[[^mG]*[mG]//g;
                                           ($started, $action) = $update_service->($service, $l);
                                           $display->($_);
                                         }
                      )) } (N_("Start"), N_("Stop"))
		]
	    }
            @$l)), 500, 400),
            0, gtkpack(gtkset_border_width(Gtk2::HBox->new(0,0),5), $W->create_okcancel)
            ))
	  );
    $b->signal_connect(motion_notify_event => sub { my ($w, $e) = @_;
						    my ($ox, $oy) = $w->window->get_origin;
						    $x = $e->x+$ox; $y = $e->y+$oy });
    $b->signal_connect(button_press_event => sub { $nopop->() });
    $::isEmbedded and gtkflush();
    $W->main or return;
    $on_services;
}

sub ask {    
    my ($in, $_prefix) = @_;
    !$::isInstall && $in->isa('interactive::gtk') ? &ask_standalone_gtk : &ask_install;
}

sub doit {
    my ($_in, $on_services, $prefix) = @_;
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

#- returns: 
#--- the listref of installed services
#--- the listref of "on" services
sub services {
    my ($prefix) = @_;
    local $ENV{LANGUAGE} = 'C';
    my @raw_l = run_program::rooted_get_stdout($prefix, '/sbin/chkconfig', '--list');
    my @l = sort { $a->[0] cmp $b->[0] } map { [ /([^\s:]+)/, /\bon\b/ ] } grep { !/:$/ } @raw_l;
    [ map { $_->[0] } @l ], [ map { $_->[0] } grep { $_->[1] } @l ];
}






# the following functions are mostly by printer related modules


sub restart ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    return 1 if !(-x "$::prefix/etc/rc.d/init.d/$service");
    run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "restart");
}

sub start ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    return 1 if !(-x "$::prefix/etc/rc.d/init.d/$service");
    run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "start");
    return (($? >> 8) != 0) ? 0 : 1;
}

sub start_not_running_service ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    return 1 if !(-x "$::prefix/etc/rc.d/init.d/$service");
    run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "status");
    return (($? >> 8) != 0) ? 0 : 1;
}

sub stop ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    return 1 if !(-x "$::prefix/etc/rc.d/init.d/$service");
    run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "stop");
    return (($? >> 8) != 0) ? 0 : 1;
}

sub is_service_running ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    return 0 if !(-x "$::prefix/etc/rc.d/init.d/$service");
    run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", "status");
    # The exit status is not zero when the service is not running
    return (($? >> 8) != 0) ? 0 : 1;
}

sub starts_on_boot {
    my ($service) = @_;
    my (undef, $on_services) = services($::prefix);
    member($service, @$on_services);
}

sub start_service_on_boot ($) {
    my ($service) = @_;
    run_program::rooted($::prefix, "/sbin/chkconfig", "--add", $service) ? 1 : 0;
}

sub do_not_start_service_on_boot ($) {
    my ($service) = @_;
    run_program::rooted($::prefix, "/sbin/chkconfig", "--del", $service) ? 1 : 0;
}

1;
