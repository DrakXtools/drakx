package tmp::compssUsers;

use common;
use ugtk2 qw(:helpers :wrappers :create);

my $h = {

N_("Workstation") => 
[
  { label => N_("Office Workstation"),
    descr => N_("Office programs: wordprocessors (OpenOffice.org Writer, Kword), spreadsheets (OpenOffice.org Calc, Kspread), PDF viewers, etc"),
    flags => [ qw(OFFICE SPELLCHECK PUBLISHING PIM ARCHIVING PRINTER) ],
    default_selected => 1,
  },
  { label => N_("Internet station"),
    descr => N_("Set of tools to read and send mail and news (mutt, tin..) and to browse the Web"),
    flags => [ qw(NETWORKING_WWW NETWORKING_MAIL NETWORKING_NEWS COMMUNICATIONS NETWORKING_CHAT NETWORKING_FILE_TRANSFER NETWORKING_IRC NETWORKING_INSTANT_MESSAGING NETWORKING_DNS) ],
    default_selected => 1,
  },
],

N_("Server") =>
[
  { label => N_("Web Server"),
    descr => N_("Apache"),
    flags => [ qw(NETWORKING_WWW_SERVER) ],
  },
  { label => N_("Groupware"),
    descr => N_("Kolab Server"),
    flags => [ qw(NETWORKING_GROUPWARE_SERVER) ],
  },
  { label => N_("Firewall/Router"),
    descr => N_("Internet gateway"),
    flags => [ qw(NETWORKING_FIREWALLING_SERVER) ],
  },
  { label => N_("Mail/News"),
    descr => N_("Postfix mail server, Inn news server"),
    flags => [ qw(NETWORKING_MAIL_SERVER NETWORKING_NEWS_SERVER) ],
  },
  { label => N_("Directory Server"),
    descr => N_("LDAP Server"),
    flags => [ qw(NETWORKING_LDAP_SERVER) ],
  },
  { label => N_("FTP Server"),
    descr => N_("ProFTPd"),
    flags => [ qw(NETWORKING_FILE_TRANSFER_SERVER) ],
  },
  { label => N_("DNS/NIS"),
    descr => N_("Domain Name and Network Information Server"),
    flags => [ qw(NIS_SERVER NETWORKING_DNS_SERVER) ],
  },
  { label => N_("File and Printer Sharing Server"),
    descr => N_("NFS Server, Samba server"),
    flags => [ qw(NETWORKING_FILE_SERVER PRINTER) ],
  },
  { label => N_("Database"),
    descr => N_("PostgreSQL and MySQL Database Server"),
    flags => [ qw(DATABASES DATABASES_SERVER) ],
  },
],

N_("Graphical Environment") =>
[
  { label => N_("KDE Workstation"),
    descr => N_("The K Desktop Environment, the basic graphical environment with a collection of accompanying tools"),
    flags => [ qw(KDE X ACCESSIBILITY) ],
    default_selected => 1,
  },
  { label => N_("GNOME Workstation"),
    descr => N_("A graphical environment with user-friendly set of applications and desktop tools"),
    flags => [ qw(GNOME X ACCESSIBILITY) ],
  },
  { label => N_("Other Graphical Desktops"),
    descr => N_("Icewm, Window Maker, Enlightenment, Fvwm, etc"),
    flags => [ qw(GRAPHICAL_DESKTOP X ACCESSIBILITY) ],
  },
],
  
N_("Development") =>
[ 
  { label => N_("Development"),
    descr => N_("C and C++ development libraries, programs and include files"),
    flags => [ qw(DEVELOPMENT EDITORS) ],
    default_selected => 1,
  },
  { label => N_("Documentation"),
    descr => N_("Books and Howto's on Linux and Free Software"),
    flags => [ qw(BOOKS) ],
  },
  { label => N_("LSB"),
    descr => N_("Linux Standard Base. Third party applications support"),
    flags => [ qw(LSB) ],
  },
],

N_("Utilities") =>
[
  { label => N_("SSH Server"),
    descr => N_("SSH Server"),
    flags => [ qw(NETWORKING_REMOTE_ACCESS_SERVER) ],
    default_selected => 1,
  },
  { label => N_("Webmin"),
    descr => N_("Webmin Remote Configuration Server"),
    flags => [ qw(WEBMIN) ],
    default_selected => 1,
  },
  { label => N_("Network Utilities/Monitoring"),
    descr => N_("Monitoring tools, processes accounting, tcpdump, nmap, ..."),
    flags => [ qw(MONITORING NETWORKING_FILE) ],
    default_selected => 1,
  },
  { label => N_("MandrakeSoft Wizards"),
    descr => N_("Wizards to configure server"),
    flags => [ qw(WIZARDS) ],
    default_selected => 1,
  },
],
};

foreach my $path (keys %$h) {
    foreach (@{$h->{$path}}) {
	$_->{path} = $path;
	$_->{uid} = join('|', $path, $_->{label});
    }
}

my $compssUsers = [ map { @$_ } values %$h ];

my $gtk_display_compssUsers = sub {
    my ($entry) = @_;

    my $entries_in_path = sub {
	my ($path) = @_;
	translate($path), map { $entry->($_) } @{$h->{$path}};
    };

    gtkpack_(Gtk2::VBox->new(0, 0),
	     1, gtkpack_(Gtk2::HBox->new(0, 0),
			 1, gtkpack(Gtk2::VBox->new(0, 0), 
				    $entries_in_path->('Workstation'),
				    $entries_in_path->('Server'),
				   ),
			 0, gtkpack(Gtk2::VBox->new(0, 0), 
				    $entries_in_path->('Graphical Environment'),
				    $entries_in_path->('Development'),
				    $entries_in_path->('Utilities'),
				   ),
			),
	    );
};

$compssUsers, $gtk_display_compssUsers;
