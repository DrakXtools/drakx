package tmp::compssUsers;

use common;
use ugtk2 qw(:helpers :wrappers :create);

my $h = {

("Discovery") => 
[
  { label => ("Discovery"),
    descr => (""),
    flags => [ qw(OFFICE SPELLCHECK PUBLISHING PIM ARCHIVING PRINTER AUDIO VIDEO GRAPHICS NETWORKING_WWW NETWORKING_MAIL NETWORKING_NEWS COMMUNICATIONS NETWORKING_CHAT NETWORKING_FILE_TRANSFER NETWORKING_IRC NETWORKING_INSTANT_MESSAGING NETWORKING_DNS CONFIG TERMINALS TEXT_TOOLS SHELLS FILE_TOOLS KDE X BOOKS) ], 
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
				    '',
				    $entries_in_path->('Development'),
				   ),
			 0, gtkpack(Gtk2::VBox->new(0, 0), 
				    $entries_in_path->('Server'),
				    '',
				    $entries_in_path->('Graphical Environment'),
				   ),
			),
	    );
};

$compssUsers, $gtk_display_compssUsers;
