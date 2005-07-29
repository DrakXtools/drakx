package tmp::compssUsers;

use common;
use ugtk2 qw(:helpers :wrappers :create);

my $low_resources = availableRamMB() < 100 || detect_devices::ix86_cpu_frequency() < 350;
my $meta_class = $::o->{meta_class};
my $desktop = $meta_class eq 'desktop';
my $powerpack = $meta_class eq 'powerpack';
my $server = $meta_class eq 'server';

my $h = {

$desktop ? (
"Discovery" => 
[
  { label => ("Discovery"),
    descr => (""),
    flags => [ qw(OFFICE SPELLCHECK PUBLISHING PIM ARCHIVING PRINTER AUDIO VIDEO GRAPHICS NETWORKING_WWW NETWORKING_MAIL NETWORKING_NEWS COMMUNICATIONS NETWORKING_CHAT NETWORKING_FILE_TRANSFER NETWORKING_IRC NETWORKING_INSTANT_MESSAGING NETWORKING_DNS CONFIG TERMINALS TEXT_TOOLS SHELLS FILE_TOOLS KDE X BOOKS) ], 
    default_selected => 1,
  },
],
) : (
N_("Workstation") => 
[
  { label => N_("Office Workstation"),
    descr => $server 
        ? N_("Office programs: wordprocessors (OpenOffice.org Writer, Kword), spreadsheets (OpenOffice.org Calc, Kspread), PDF viewers, etc")
        : N_("Office programs: wordprocessors (kword, abiword), spreadsheets (kspread, gnumeric), pdf viewers, etc"),
    flags => [ qw(OFFICE SPELLCHECK PUBLISHING PIM ARCHIVING PRINTER) ],
    default_selected => 1,
  },
  if_(!$server,
  { label => N_("Game station"),
    descr => N_("Amusement programs: arcade, boards, strategy, etc"),
    flags => [ qw(GAMES) ], 
  },
  { label => N_("Multimedia station"),
    descr => N_("Sound and video playing/editing programs"),
    flags => [ qw(AUDIO VIDEO GRAPHICS) ],
    default_selected => 1,
  },
  ),
  { label => N_("Internet station"),
    descr => N_("Set of tools to read and send mail and news (mutt, tin..) and to browse the Web"),
    flags => [ qw(NETWORKING_WWW NETWORKING_MAIL NETWORKING_NEWS COMMUNICATIONS NETWORKING_CHAT NETWORKING_FILE_TRANSFER NETWORKING_IRC NETWORKING_INSTANT_MESSAGING NETWORKING_DNS) ],
    default_selected => 1,
  },
  if_(!$server,
  { label => N_("Network Computer (client)"),
    descr => N_("Clients for different protocols including ssh"),
    flags => [ qw(NETWORKING_REMOTE_ACCESS NETWORKING_FILE) ], 
    default_selected => $powerpack,
  },
  { label => N_("Configuration"),
    descr => N_("Tools to ease the configuration of your computer"),
    flags => [ qw(CONFIG) ],
    default_selected => 1,
  },
  { label => N_("Console Tools"),
    descr => N_("Editors, shells, file tools, terminals"),
    flags => [ qw(EDITORS TERMINALS TEXT_TOOLS SHELLS FILE_TOOLS) ],
    default_selected => 1,
  },
  { label => N_("Development"),
    descr => N_("C and C++ development libraries, programs and include files"),
    flags => [ qw(DEVELOPMENT EDITORS) ],
    default_selected => $powerpack,
  },
  { label => N_("Documentation"),
    descr => N_("Books and Howto's on Linux and Free Software"),
    flags => [ qw(BOOKS) ],
    default_selected => $powerpack,
  },
  { label => N_("LSB"),
    descr => N_("Linux Standard Base. Third party applications support"),
    flags => [ qw(LSB) ],
  },
  ),
],

N_("Server") =>
[
  $server ? (
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
  ) : (
  { label => N_("Web/FTP"),
    descr => N_("Apache, Pro-ftpd"),
    flags => [ qw(NETWORKING_WWW_SERVER NETWORKING_FILE_TRANSFER_SERVER) ],
  },
  { label => N_("Mail"),
    descr => N_("Postfix mail server"),
    flags => [ qw(NETWORKING_MAIL_SERVER) ],
  },
  { label => N_("Database"),
    descr => N_("PostgreSQL or MySQL database server"),
    flags => [ qw(DATABASES DATABASES_SERVER) ],
  },
  { label => N_("Firewall/Router"),
    descr => N_("Internet gateway"),
    flags => [ qw(NETWORKING_FIREWALLING_SERVER) ],
  },
  { label => N_("Network Computer server"),
    descr => N_("NFS server, SMB server, Proxy server, ssh server"),
    flags => [ qw(NETWORKING_FILE_SERVER NETWORKING_REMOTE_ACCESS_SERVER) ],
  },
  ),
],

N_("Graphical Environment") => 
[
  { label => N_("KDE Workstation"),
    descr => N_("The K Desktop Environment, the basic graphical environment with a collection of accompanying tools"),
    flags => [ qw(KDE X ACCESSIBILITY THEMES) ],
    default_selected => !$low_resources,
  },
  { label => N_("GNOME Workstation"),
    descr => N_("A graphical environment with user-friendly set of applications and desktop tools"),
    flags => [ qw(GNOME X ACCESSIBILITY THEMES) ], 
  },
  { label => N_("IceWm Desktop"),
    flags => [ qw(ICEWM X ACCESSIBILITY) ], 
    default_selected => $low_resources,
  },
  { label => N_("Other Graphical Desktops"),
    descr => N_("Window Maker, Enlightenment, Fvwm, etc"),
    flags => [ qw(GRAPHICAL_DESKTOP X ACCESSIBILITY) ], 
  },
],

if_($server,
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
  { label => N_("Mandriva Wizards"),
    descr => N_("Wizards to configure server"),
    flags => [ qw(WIZARDS) ],
    default_selected => 1,
  },
],
),
),
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
				    $server ? $entries_in_path->('Server') : (),
				   ),
			 0, gtkpack(Gtk2::VBox->new(0, 0),
				    $server ? (
				      $entries_in_path->('Graphical Environment'),
				      $entries_in_path->('Development'),
				      $entries_in_path->('Utilities'),
				    ) : (
				      $entries_in_path->('Server'),
				      '',
				      $entries_in_path->('Graphical Environment'),
                                    ),
				   ),
			),
	    );
};

$compssUsers, $gtk_display_compssUsers;
