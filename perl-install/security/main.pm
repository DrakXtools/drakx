package security::main;

use strict;

use standalone;
use MDK::Common;
use my_gtk qw(:helpers :wrappers :ask);

use security::msec;

sub myexit { my_gtk->exit(@_) }

# factorize this with rpmdrake and harddrake2
sub wait_msg {
    my $mainw = my_gtk->new('wait');
    my $label = new Gtk::Label($_[0]);
    $mainw->{window}->add(gtkpack(gtkadd(create_vbox(), $label)));
    $mainw->{window}->show_all;
    $mainw->{window}->realize;
    $label->signal_connect(expose_event => sub { $mainw->{displayed} = 1 });
    $mainw->sync until $mainw->{displayed};
    $mainw->show;
    gtkset_mousecursor_wait($mainw->{rwindow}->window);
    $mainw->flush;
    $mainw;
}

sub remove_wait_msg { $_[0]->destroy }

#sub show_msec_help { my $command = $_[0] }

sub basic_seclevel_explanations {
	my $text = new Gtk::Text(undef, undef);
	$text->set_editable(0);
	$text->insert(undef, $text->style->black, undef,
			    N("Standard: This is the standard security recommended for a computer that will be used to connect
               to the Internet as a client.

High:       There are already some restrictions, and more automatic checks are run every night.

Higher:    The security is now high enough to use the system as a server which can accept
              connections from many clients. If your machine is only a client on the Internet, you
	      should choose a lower level.

Paranoid:  This is similar to the previous level, but the system is entirely closed and security
                features are at their maximum

Security Administrator:
               If the 'Security Alerts' option is set, security alerts will be sent to this user (username or
	       email)"));

	gtkpack_(gtkshow(new Gtk::HBox(0, 0)), 1, $text);
}

sub basic_seclevel_option {
	my ($seclevel_entry, $msec) = @_;
	my @sec_levels = $msec->get_seclevel_list();
	my $current_level = $msec->get_secure_level();

	push(@sec_levels, $current_level) if ($current_level eq "Dangerous" || $current_level eq "Poor");

	$$seclevel_entry->entry->set_editable(0);
	$$seclevel_entry->set_popdown_strings(@sec_levels);
	$$seclevel_entry->entry->set_text($current_level);

	new Gtk::Label(N("Security Level:")), $$seclevel_entry;
}

sub draksec_main {
	my $msec = new security::msec;
	my $w = my_gtk->new('draksec');
	my $window = $w->{window};

	############################ MAIN WINDOW ###################################
	# Set different options to Gtk::Window
	unless ($::isEmbedded) {
	  $w->{rwindow}->set_policy(1, 1, 1);
	  $w->{rwindow}->set_position(1);
	  $w->{rwindow}->set_title("DrakSec");
	  $window->set_usize(598, 590);
	}

	# Connect the signals
	$window->signal_connect('delete_event', sub { $window->destroy(); });
	$window->signal_connect('destroy', sub { my_gtk->exit(); });

	$window->add(my $vbox = gtkshow(new Gtk::VBox(0, 0)));

	# Create the notebook (for bookmarks at the top)
	my $notebook = create_notebook();
	$notebook->set_tab_pos('top');

	######################## BASIC OPTIONS PAGE ################################
	my $seclevel_entry = new Gtk::Combo();

	$notebook->append_page(gtkpack__(gtkshow(my $basic_page = new Gtk::VBox(0, 0)),
							   basic_seclevel_explanations($msec),
							   create_packtable ({ col_spacings => 10, row_spacings => 5 },
											 [ basic_seclevel_option(\$seclevel_entry, $msec) ],
											 [ new Gtk::Label(N("Security Alerts:")), 
											   my $secadmin_check = new Gtk::CheckButton ],
											 [ new Gtk::Label(N("Security Administrator:")),
											   my $secadmin_entry = new Gtk::Entry ])),
					   new Gtk::Label(N("Basic")));

	$secadmin_entry->set_text($msec->get_check_value("MAIL_USER"));
	$secadmin_check->set_active(1) if $msec->get_check_value("MAIL_WARN") eq "yes";

	######################### NETWORK & SYSTEM OPTIONS #########################
	my @yesno_choices    = qw(yes no default ignore);
	my @alllocal_choices = qw(ALL LOCAL NONE default);
	my @all_choices = (@yesno_choices, @alllocal_choices);
	my %options_values;

	foreach ( [ 'network', N("Network Options") ], [ 'system', N("System Options") ] ) {
	    my ($domain, $label) = @$_;
	    my %values;
	    
	    $notebook->append_page(gtkshow(createScrolledWindow(gtkpack(new Gtk::VBox(0, 0),
		   new Gtk::Label(N("The following options can be set to customize your\nsystem security. If you need explanations, click on Help.\n")),
		   create_packtable({ col_spacings => 10, row_spacings => 5 },
						   map {
		   my $i = $_;
		   my $default = $msec->get_function_default($i);
		   if (member($default, @all_choices)) {
			  $values{$i} = new Gtk::Combo();
			  $values{$i}->entry->set_editable(0);
			  if (member($default, @yesno_choices)) {
				 $values{$i}->set_popdown_strings(@yesno_choices);
			  } elsif (member($default, @alllocal_choices)) {
				 $values{$i}->set_popdown_strings(@alllocal_choices);
			  }
			  $values{$i}->entry->set_text($msec->get_function_value($i));
		   } else {
			  $values{$i} = new Gtk::Entry();
			  $values{$i}->set_text($msec->get_function_value($i));
		   }
		   [ new Gtk::Label($i . N(" (default: %s)", $default)), $values{$i} ];
		   # , gtksignal_connect(new Gtk::Button(N("Help")), 'clicked' => sub { show_msec_help($_) } ) ]
	 } $msec->get_functions($domain))))),
						  new Gtk::Label($label));
	 $options_values{$domain} = \%values;
 }

	######################## PERIODIC CHECKS ###################################
	my %security_checks_value;

	$notebook->append_page(gtkshow(createScrolledWindow(gtkpack(new Gtk::VBox(0, 0),
		   new Gtk::Label(N("The following options can be set to customize your\nsystem security. If you need explanations, click on Help.\n")),
		   create_packtable({ col_spacings => 10, row_spacings => 5 },
						map {
						    my $i = $_;
						    if (!member(qw(MAIL_WARN MAIL_USER), $i)) {
							   $security_checks_value{$i} = new Gtk::Combo();
							   $security_checks_value{$i}->entry->set_editable(0);
							   $security_checks_value{$i}->set_popdown_strings(qw(yes no default));
							   $security_checks_value{$i}->entry->set_text($msec->get_check_value($i));
							   [ gtkshow(new Gtk::Label(translate($i))), $security_checks_value{$i} ];
							   # , gtksignal_connect(new Gtk::Button(N("Help")), 'clicked' => sub { show_msec_help($i) } ) ]
							   }
						} ($msec->get_default_checks))))),
					   new Gtk::Label(N("Periodic Checks")));


	####################### OK CANCEL BUTTONS ##################################
	my $bok = gtksignal_connect(new Gtk::Button(N("Ok")),
						   'clicked' => sub {
                  my $seclevel_value = $seclevel_entry->entry->get_text();
		  my $secadmin_check_value = $secadmin_check->get_active();
		  my $secadmin_value = $secadmin_entry->get_text();
		  my $w;

		  standalone::explanations("Configuring msec");

		  if ($seclevel_value ne $msec->get_secure_level()) {
		      $w = wait_msg(N("Please wait, setting security level..."));
		      standalone::explanations("Setting security level");
		      $msec->set_secure_level($seclevel_value);
		      remove_wait_msg($w);
		  }

		  $w = wait_msg(N("Please wait, setting security options..."));
		  standalone::explanations("Setting security administrator option");
		  $msec->config_check('MAIL_WARN', $secadmin_check_value == 1 ? 'yes' : 'no');

		  standalone::explanations("Setting security administrator contact");
		  if ($secadmin_value ne $msec->get_check_value('MAIL_USER') && $secadmin_check_value) {
		      $msec->config_check('MAIL_USER', $secadmin_value);
		  }

		  standalone::explanations("Setting security periodic checks");
		  foreach my $key (keys %security_checks_value) {
		      if ($security_checks_value{$key}->entry->get_text() ne $msec->get_check_value($key)) {
			  $msec->config_check($key, $security_checks_value{$key}->entry->get_text());
		      }
		  }

		  foreach my $domain (keys %options_values) {
			 standalone::explanations("Setting msec functions related to $domain");
			   foreach my $key (keys %{$options_values{$domain}}) {
				  my $opt = $options_values{$domain}{$key};
				  $msec->config_function($key, $opt =~ /Combo/ ? $opt->entry->get_text() : $opt->get_text());
			   }
		  }
		  standalone::explanations("Applying msec changes");
		  system "/usr/sbin/msec";

			   

		  remove_wait_msg($w);

		  my_gtk->exit(0);
		  });

	my $bcancel = gtksignal_connect(new Gtk::Button(N("Cancel")),
							  'clicked' => sub { my_gtk->exit(0) });
	gtkpack_($vbox,
		    1, gtkshow($notebook),
		    0, gtkadd(gtkadd(gtkshow(new Gtk::HBox(0, 0)),
						 $bok),
				    $bcancel));
	$bcancel->can_default(1);
	$bcancel->grab_default();

	$w->main;
	my_gtk->exit(0);

}

1;
