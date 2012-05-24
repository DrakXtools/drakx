package services; # $Id$



#-######################################################################################
#- misc imports
#-######################################################################################

use strict;
use common;
use run_program;

use File::Basename;

sub description {
    my %services = (
acpid => N_("Listen and dispatch ACPI events from the kernel"),	    
alsa => N_("Launch the ALSA (Advanced Linux Sound Architecture) sound system"),
anacron => N_("Anacron is a periodic command scheduler."),
apmd => N_("apmd is used for monitoring battery status and logging it via syslog.
It can also be used for shutting down the machine when the battery is low."),
atd => N_("Runs commands scheduled by the at command at the time specified when
at was run, and runs batch commands when the load average is low enough."),
'avahi-deamon' => N_("Avahi is a ZeroConf daemon which implements an mDNS stack"),
cpufreq => N_("Set CPU frequency settings"),
crond => N_("cron is a standard UNIX program that runs user-specified programs
at periodic scheduled times. vixie cron adds a number of features to the basic
UNIX cron, including better security and more powerful configuration options."),
cups => N_("Common UNIX Printing System (CUPS) is an advanced printer spooling system"),
dm => N_("Launches the graphical display manager"),
fam => N_("FAM is a file monitoring daemon. It is used to get reports when files change.
It is used by GNOME and KDE"),
g15daemon => N_("G15Daemon allows users access to all extra keys by decoding them and 
pushing them back into the kernel via the linux UINPUT driver. This driver must be loaded 
before g15daemon can be used for keyboard access. The G15 LCD is also supported. By default, 
with no other clients active, g15daemon will display a clock. Client applications and 
scripts can access the LCD via a simple API."),
gpm => N_("GPM adds mouse support to text-based Linux applications such the
Midnight Commander. It also allows mouse-based console cut-and-paste operations,
and includes support for pop-up menus on the console."),
haldaemon => N_("HAL is a daemon that collects and maintains information about hardware"),
harddrake => N_("HardDrake runs a hardware probe, and optionally configures
new/changed hardware."),
httpd => N_("Apache is a World Wide Web server. It is used to serve HTML files and CGI."),
inet => N_("The internet superserver daemon (commonly called inetd) starts a
variety of other internet services as needed. It is responsible for starting
many services, including telnet, ftp, rsh, and rlogin. Disabling inetd disables
all of the services it is responsible for."),
ip6tables => N_("Automates a packet filtering firewall with ip6tables"),
iptables => N_("Automates a packet filtering firewall with iptables"),
ipchains => N_("Launch packet filtering for Linux kernel 2.2 series, to set
up a firewall to protect your machine from network attacks."),
irqbalance => N_("Evenly distributes IRQ load across multiple CPUs for enhanced performance"),
keytable => N_("This package loads the selected keyboard map as set in
/etc/sysconfig/keyboard.  This can be selected using the kbdconfig utility.
You should leave this enabled for most machines."),
kheader => N_("Automatic regeneration of kernel header in /boot for
/usr/include/linux/{autoconf,version}.h"),
kudzu => N_("Automatic detection and configuration of hardware at boot."),
'laptop-mode' => N_("Tweaks system behavior to extend battery life"),
linuxconf => N_("Linuxconf will sometimes arrange to perform various tasks
at boot-time to maintain the system configuration."),
lpd => N_("lpd is the print daemon required for lpr to work properly. It is
basically a server that arbitrates print jobs to printer(s)."),
lvs => N_("Linux Virtual Server, used to build a high-performance and highly
available server."),
mandi => N_("Monitors the network (Interactive Firewall and wireless"),
mdadm => N_("Software RAID monitoring and management"),
messagebus => N_("DBUS is a daemon which broadcasts notifications of system events and other messages"),
msec => N_("Enables MSEC security policy on system startup"),
named => N_("named (BIND) is a Domain Name Server (DNS) that is used to resolve host names to IP addresses."),
netconsole => N_("Initializes network console logging"),
netfs => N_("Mounts and unmounts all Network File System (NFS), SMB (Lan
Manager/Windows), and NCP (NetWare) mount points."),
network => N_("Activates/Deactivates all network interfaces configured to start
at boot time."),
'network-auth' => N_("Requires network to be up if enabled"),
'network-up' => N_("Wait for the hotplugged network to be up"),
nfs => N_("NFS is a popular protocol for file sharing across TCP/IP networks.
This service provides NFS server functionality, which is configured via the
/etc/exports file."),
nfslock => N_("NFS is a popular protocol for file sharing across TCP/IP
networks. This service provides NFS file locking functionality."),
ntpd => N_("Synchronizes system time using the Network Time Protocol (NTP)"),
numlock => N_("Automatically switch on numlock key locker under console
and Xorg at boot."),
oki4daemon => N_("Support the OKI 4w and compatible winprinters."),
partmon => N_("Checks if a partition is close to full up"),
pcmcia => N_("PCMCIA support is usually to support things like ethernet and
modems in laptops.  It will not get started unless configured so it is safe to have
it installed on machines that do not need it."),
portmap => N_("The portmapper manages RPC connections, which are used by
protocols such as NFS and NIS. The portmap server must be running on machines
which act as servers for protocols which make use of the RPC mechanism."),
portreserve => N_("Reserves some TCP ports"),
postfix => N_("Postfix is a Mail Transport Agent, which is the program that moves mail from one machine to another."),
random => N_("Saves and restores system entropy pool for higher quality random
number generation."),
rawdevices => N_("Assign raw devices to block devices (such as hard disk drive
partitions), for the use of applications such as Oracle or DVD players"),
resolvconf => N_("Nameserver information manager"),
routed => N_("The routed daemon allows for automatic IP router table updated via
the RIP protocol. While RIP is widely used on small networks, more complex
routing protocols are needed for complex networks."),
rstatd => N_("The rstat protocol allows users on a network to retrieve
performance metrics for any machine on that network."),
rsyslog => N_("Syslog is the facility by which many daemons use to log messages to various system log files.  It is a good idea to always run rsyslog."),
rusersd => N_("The rusers protocol allows users on a network to identify who is
logged in on other responding machines."),
rwhod => N_("The rwho protocol lets remote users get a list of all of the users
logged into a machine running the rwho daemon (similar to finger)."),
saned => N_("SANE (Scanner Access Now Easy) enables to access scanners, video cameras, ..."),
shorewall => N_("Packet filtering firewall"),
smb => N_("The SMB/CIFS protocol enables to share access to files & printers and also integrates with a Windows Server domain"),
sound => N_("Launch the sound system on your machine"),
'speech-dispatcherd' => N_("layer for speech analysis"),
sshd => N_("Secure Shell is a network protocol that allows data to be exchanged over a secure channel between two computers"),
syslog => N_("Syslog is the facility by which many daemons use to log messages
to various system log files.  It is a good idea to always run syslog."),
'udev-post' => N_("Moves the generated persistent udev rules to /etc/udev/rules.d"),
usb => N_("Load the drivers for your usb devices."),
vnStat => N_("A lightweight network traffic monitor"),
xfs => N_("Starts the X Font Server."),
xinetd => N_("Starts other deamons on demand."),
    );
    my ($name) = @_;
    my $s = $services{$name};
    if ($s) {
	$s = translate($s);
    } else {
	my $file = "$::prefix/lib/systemd/system/$name.service";
	if (-e $file) {
		$s = cat_($file);
		$s = $s =~ /^Description=(.*)/mg ? $1 : '';
	} else {
		$file = find { -e $_ } map { "$::prefix$_/$name" } '/etc/rc.d/init.d', '/etc/init.d', '/etc/xinetd.d';
		$s = cat_($file);
		$s =~ s/\\\s*\n#\s*//mg;
		$s =
			$s =~ /^#\s+(?:Short-)?[dD]escription:\s+(.*?)^(?:[^#]|# {0,2}\S)/sm ? $1 :
			$s =~ /^#\s*(.*?)^[^#]/sm ? $1 : '';

		$s =~ s/#\s*//mg;
	}
    }
    $s =~ s/\n/ /gm; $s =~ s/\s+$//;
    $s;
}

sub ask_ {
    my ($in) = @_;
    my %root_services = (
			 N("Printing") => [ qw(cups cupslpd cups-lpd hpoj lpd lpr oki4daemon) ],
                         
			 # FIXME: split part of 'Internet' into 'Security' or 'Firewall'?
			 N("Internet") => [ qw(adsl boa cddbp ftp httpd ibod ip6tables ippl iptables iptoip ipvsadm
                                               isdn4linux jabber jabber-icq jail.init junkbuster mandi nessusd pftp portsentry 
                                               prelude proftpd proftpd-xinetd pure-ftpd ipsec radvd roxen shorewall squid
                                               tftp) ],

			 N("_: Keep these entry short\nNetworking") => [ qw(network network-auth network-up resolvconf) ],

			 N("System") => [ qw(acon acpid alsa anacron apcupsd apmd atd bpowerd bpowerfail crond cvs dm fcron functions
                                             gpm halt harddrake inetd irda jserver keytable kheader killall mageia_everytime
                                             mageia_firstime mdadm medusa-init messagebus microcode_ctl mosix netconsole numlock partmon
                                             pcmcia portmap powertweak.init psacct
                                             random rawdevices rpcbind sensors single sound syslog syslog-ng ups usb usbd wine xfs xinetd) ],

			 N("Remote Administration") => [ qw(cfd drakxtools_http heartbeat iplog ldirectord mon netsaint olympusd rexec
                                                            rlogin rsh sshd telnet telnetd vncserver webmin) ],

#			 N("Network Client") => [ qw(arpwatch diald dnrd_rc fetchmail nscd rsync ypbind) ],
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
    my ($l, $on_services) = services();
    my %services;
    $services{$_} = 0 foreach @{$l || []};
    $services{$_} = 1 foreach @{$on_services || []};

    $in->ask_browse_tree_info(N("Services"), N("Choose which services should be automatically started at boot time"),
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
				   N("%d activated for %d registered", 
				     scalar(grep { $_ } values %services),
				     scalar(values %services));
			       },
			       get_info => sub { formatLines(description($_[0])) },
                               interactive_help => sub { 
                                   interactive::gtk::display_help($in,
                                                               { interactive_help_id => 
                                                                   'misc-params#drakxid-configureServices' }, $::main_window) },
			      }) or return $l, $on_services; #- no change on cancel.
    [ grep { $services{$_} } @$l ];
}

sub ask_standalone_gtk {
    my ($_in) = @_;
    my ($l, $on_services) = services();
    my @xinetd_services = map { $_->[0] } xinetd_services();

    require ugtk2;
    ugtk2->import(qw(:wrappers :create));

    my $W = ugtk2->new(N("Services"));
    my ($x, $y, $w_popup);
    my $nopop = sub { $w_popup and $w_popup->destroy; undef $w_popup };
    my $display = sub { 
	my ($text) = @_;
	$nopop->(); 
	gtkshow(gtkadd($w_popup = Gtk2::Window->new('popup'),
		       gtksignal_connect(gtkadd(Gtk2::EventBox->new,
						gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'etched_out'),
						       gtkset_justify(Gtk2::Label->new($text), 'left'))),
					 button_press_event => sub { $nopop->() }
					)))->move($x, $y) if $text;
    };
    my $update_service = sub {
	my ($service, $label) = @_;
	my $started = is_service_running($service);
	$label->set_label($started ? N("running") : N("stopped"));
    };
    my $b = Gtk2::EventBox->new;
    $b->set_events('pointer_motion_mask');
    gtkadd($W->{window}, gtkadd($b, gtkpack_($W->create_box_with_title,
	0, mygtk2::gtknew('Title1', label => N("Services and daemons")),
	1, gtkset_size_request(create_scrolled_window(create_packtable({ col_spacings => 10, row_spacings => 3 },
	    map {
                my $service = $_;
		my $is_xinetd_service = member($service, @xinetd_services);
        	my $infos = warp_text(description($_), 40);
                $infos ||= N("No additional information\nabout this service, sorry.");
		my $label = gtkset_justify(Gtk2::Label->new, 'left');
                $update_service->($service, $label) if !$is_xinetd_service;
		[ gtkpack__(Gtk2::HBox->new(0,0), $_),
		  gtkpack__(Gtk2::HBox->new(0,0), $label),
		  gtkpack__(Gtk2::HBox->new(0,0), gtksignal_connect(Gtk2::Button->new(N("Info")), clicked => sub { $display->($infos) })),

                  gtkpack__(Gtk2::HBox->new(0,0), gtkset_active(gtksignal_connect(
                          Gtk2::CheckButton->new($is_xinetd_service ? N("Start when requested") : N("On boot")),
                          clicked => sub { if ($_[0]->get_active) {
                                               push @$on_services, $service if !member($service, @$on_services);
                                           } else {
                                               @$on_services = grep { $_ ne $service } @$on_services;
                                        } }), member($service, @$on_services))),
		  map { 
		      my $a = $_;
		      gtkpack__(Gtk2::HBox->new(0,0), gtksignal_connect(Gtk2::Button->new(translate($a)),
                          clicked => sub { 
			      my $action = $a eq "Start" ? 'restart' : 'stop'; 
			      log::explanations(qq(GP_LANG="UTF-8" service $service $action));
			      # as we need the output in UTF-8, force it
			      local $_ = `GP_LANG="UTF-8" service $service $action 2>&1`; s/\033\[[^mG]*[mG]//g;
			      c::set_tagged_utf8($_);
			      $update_service->($service, $label);
			      $display->($_);
			  })) if !$is_xinetd_service;
		  } (N_("Start"), N_("Stop"))
		];
	    }
            @$l), [ $::isEmbedded ? 'automatic' : 'never', 'automatic' ]), -1, $::isEmbedded ? -1 : 400),
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
    my ($in) = @_;
    !$::isInstall && $in->isa('interactive::gtk') ? &ask_standalone_gtk : &ask_;
}

sub _set_service {
    my ($service, $enable) = @_;
    
    my @xinetd_services = map { $_->[0] } xinetd_services();

    if (member($service, @xinetd_services)) {
        run_program::rooted($::prefix, "chkconfig", $enable ? "--add" : "--del", $service);
    } elsif (running_systemd() or has_systemd()) {
        # systemctl rejects any symlinked units. You have to enabled the real file
        if (-l "/lib/systemd/system/$service.service") {
            $service = basename(readlink("/lib/systemd/system/$service.service"));
        } else {
            $service = $service.".service";
        }
        run_program::rooted($::prefix, "/bin/systemctl", $enable ? "enable" : "disable", $service);
    } else {
        my $script = "/etc/rc.d/init.d/$service";
        run_program::rooted($::prefix, "chkconfig", $enable ? "--add" : "--del", $service);
        #- FIXME: handle services with no chkconfig line and with no Default-Start levels in LSB header
        if ($enable && cat_("$::prefix$script") =~ /^#\s+chkconfig:\s+-/m) {
            run_program::rooted($::prefix, "chkconfig", "--level", "35", $service, "on");
        }
    }
}

sub _run_action {
    my ($service, $action) = @_;
    if (running_systemd()) {
        run_program::rooted($::prefix, '/bin/systemctl', $action, "$service.service");
    } else {
        run_program::rooted($::prefix, "/etc/rc.d/init.d/$service", $action);
    }
}

sub doit {
    my ($in, $on_services) = @_;
    my ($l, $was_on_services) = services();

    foreach (@$l) {
	my $before = member($_, @$was_on_services);
	my $after = member($_, @$on_services);
	if ($before != $after) {
	    _set_service($_, $after);
	    if (!$after && !$::isInstall && !$in->isa('interactive::gtk')) {
		#- only done after install AND when not using the gtk frontend (since it allows one to start/stop services)
		#- this allows to skip stopping service "dm"
		_run_action($_, "stop");
	    }
	}
    }
}

sub running_systemd() {
    run_program::rooted($::prefix, '/bin/mountpoint', '-q', '/sys/fs/cgroup/systemd');
}

sub has_systemd() {
    run_program::rooted($::prefix, '/bin/rpm', '-q', 'systemd-sysvinit');
}

sub xinetd_services() {
    local $ENV{LANGUAGE} = 'C';
    my @xinetd_services;
    foreach (run_program::rooted_get_stdout($::prefix, '/sbin/chkconfig', '--list', '--type', 'xinetd')) {
        if (my ($xinetd_name, $on_off) = m!^\t(\S+):\s*(on|off)!) {
            push @xinetd_services, [ $xinetd_name, $on_off eq 'on' ];
        }
    }
    @xinetd_services;
}

sub services_raw() {
    local $ENV{LANGUAGE} = 'C';
    my (@services, @xinetd_services);
    foreach (run_program::rooted_get_stdout($::prefix, '/sbin/chkconfig', '--list')) {
	if (my ($xinetd_name, $on_off) = m!^\t(\S+):\s*(on|off)!) {
	    push @xinetd_services, [ $xinetd_name, $on_off eq 'on' ];
	} elsif (my ($name, $l) = m!^(\S+)\s+(0:(on|off).*)!) {
	    push @services, [ $name, [ $l =~ /(\d+):on/g ] ];
	}
    }
    \@services, \@xinetd_services;
}

#- returns: 
#--- the listref of installed services
#--- the listref of "on" services
sub services() {
    my ($services, $xinetd_services) = services_raw();
    my @l = @$xinetd_services;
    if ($::isInstall) {
        push @l, map { [ $_->[0], @{$_->[1]} > 0 ] } @$services;
    } else {
        my $runlevel = (split " ", `/sbin/runlevel`)[1];
        push @l, map { [ $_->[0], member($runlevel, @{$_->[1]}) ] } @$services;
    }
    @l = sort { $a->[0] cmp $b->[0] } @l;
    [ map { $_->[0] } @l ], [ map { $_->[0] } grep { $_->[1] } @l ];
}






sub service_exists {
    my ($service) = @_;
    -x "$::prefix/etc/rc.d/init.d/$service" or -e "$::prefix/lib/systemd/system/$service.service" or -l "$::prefix/lib/systemd/system/$service.service";
}

sub restart ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    _run_action($service, "restart");
}

sub restart_or_start ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    _run_action($service, is_service_running($service) ? "restart" : "start");
}

sub start ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    _run_action($service, "start");
}

sub start_not_running_service ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    is_service_running($service) || _run_action($service, "start");
}

sub stop ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    _run_action($service, "stop");
}

sub is_service_running ($) {
    my ($service) = @_;
    # Exit silently if the service is not installed
    service_exists($service) or return 1;
    if (running_systemd()) {
        run_program::rooted($::prefix, '/bin/systemctl', '--quiet', 'is-active', "$service.service");
    } else {
        run_program::rooted($::prefix, '/sbin/service', $service, 'status');
    }
}

sub starts_on_boot {
    my ($service) = @_;
    my (undef, $on_services) = services();
    member($service, @$on_services);
}

sub start_service_on_boot ($) {
    my ($service) = @_;
    _set_service($service, 1);
}

sub do_not_start_service_on_boot ($) {
    my ($service) = @_;
    _set_service($service, 0);
}

sub enable {
    my ($service, $o_dont_apply) = @_;
    start_service_on_boot($service);
    restart_or_start($service) unless $o_dont_apply;
}

sub disable {
    my ($service, $o_dont_apply) = @_;
    do_not_start_service_on_boot($service);
    stop($service) unless $o_dont_apply;
}

sub set_status {
    my ($service, $enable, $o_dont_apply) = @_;
    if ($enable) {
	enable($service, $o_dont_apply);
    } else {
	disable($service, $o_dont_apply);
    }
}

1;
