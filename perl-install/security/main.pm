use strict;

use standalone;
use MDK::Common;
use my_gtk qw(:helpers :wrappers :ask);
use log;

use security::libsafe;
use security::msec;

sub myexit { my_gtk::exit @_ }

sub wait_msg {
    my $mainw = my_gtk->new('wait');
    my $label = new Gtk::Label($_[0]);
    gtkadd($mainw->{window}, gtkpack(gtkadd(create_vbox(), $label)));
    $label->signal_connect(expose_event => sub { $mainw->{displayed} = 1 });
    $mainw->sync until $mainw->{displayed};
    gtkset_mousecursor_wait($mainw->{rwindow}->window);
    $mainw->flush;
    $mainw;
}

sub remove_wait_msg { $_[0]->destroy }

sub show_msec_help {
	my $command = $_[0];
}

sub basic_seclevel_explanations {
	my $text = new Gtk::Text(undef, undef);
	$text->set_editable(0);
	$text->insert(undef, $text->style->black, undef,
			    _("Standard: This is the standard security recommended for a computer that will be used to connect
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

	my $hbox = new Gtk::HBox(0, 0);
	new Gtk::Label(_("Security Level:")), $$seclevel_entry;
}

sub basic_secadmin_check {
	my ($secadmin_check, $msec) = @_;

	$$secadmin_check->set_active(1) if ($msec->get_check_value('', "MAIL_WARN") eq "yes");

	new Gtk::Label(_("Security Alerts:")), $$secadmin_check;
}

sub basic_secadmin_entry {
	my ($secadmin_entry, $msec) = @_;

	$$secadmin_entry->set_text($msec->get_check_value('', "MAIL_USER"));

	my $hbox = new Gtk::HBox(0, 0);
	new Gtk::Label(_("Security Administrator:")), $$secadmin_entry;
}

sub network_generate_page {
	my ($rsecurity_net_hash, $msec) = @_;
	my @network_options = $msec->get_functions('', "network");
        my @yesno_choices = qw(yes no default ignore);
	my @alllocal_choices = qw(ALL LOCAL NONE default);

	my @items;

	foreach my $tmp (@network_options) {
#		my $hbutton = gtksignal_connect(new Gtk::Button(_("Help")),
#								  'clicked' => sub { show_msec_help($tmp) } );
		my $default = $msec->get_function_default('', $tmp);
		if (member($default, @yesno_choices) || member($default, @alllocal_choices)) {
			$$rsecurity_net_hash{$tmp} = new Gtk::Combo();
			$$rsecurity_net_hash{$tmp}->entry->set_editable(0);
		}
		else {
			$$rsecurity_net_hash{$tmp} = new Gtk::Entry();
			$$rsecurity_net_hash{$tmp}->set_text($msec->get_check_value('', $tmp));
		}
		if (member($default, @yesno_choices)) {
			$$rsecurity_net_hash{$tmp}->set_popdown_strings(@yesno_choices);
			$$rsecurity_net_hash{$tmp}->entry->set_text($msec->get_check_value('', $tmp));
		}
		elsif (member($default, @alllocal_choices)) {
			$$rsecurity_net_hash{$tmp}->set_popdown_strings(@alllocal_choices);
			$$rsecurity_net_hash{$tmp}->entry->set_text($msec->get_check_value('', $tmp));
		}
		push @items, [ new Gtk::Label($tmp._(" (default: %s)",$default)), $$rsecurity_net_hash{$tmp} ]; #, $hbutton];
	}

	gtkpack(new Gtk::VBox(0, 0),
		   new Gtk::Label(_("The following options can be set to customize your\nsystem security. If you need explanations, click on Help.\n")),
		   create_packtable({ col_spacings => 10, row_spacings => 5 }, @items));
}

sub system_generate_page {
	my ($rsecurity_system_hash, $msec) = @_;
	my @system_options = $msec->get_functions('', "system");
        my @yesno_choices = qw(yes no default ignore);
	my @alllocal_choices = qw(ALL LOCAL NONE default);

	my @items;

	foreach my $tmp (@system_options) {
#		my $hbutton = gtksignal_connect(new Gtk::Button(_("Help")),
#								  'clicked' => sub { show_msec_help($tmp) } );
		my $default = $msec->get_function_default('', $tmp);
		my $item_hbox = new Gtk::HBox(0, 0);
		if (member($default, @yesno_choices) || member($default, @alllocal_choices)) {
			$$rsecurity_system_hash{$tmp} = new Gtk::Combo();
			$$rsecurity_system_hash{$tmp}->entry->set_editable(0);
		} else {
			$$rsecurity_system_hash{$tmp} = new Gtk::Entry();
			$$rsecurity_system_hash{$tmp}->set_text($msec->get_check_value('', $tmp));
		}
		if (member($default, @yesno_choices)) {
			$$rsecurity_system_hash{$tmp}->set_popdown_strings(@yesno_choices);
			$$rsecurity_system_hash{$tmp}->entry->set_text($msec->get_check_value('', $tmp));
		}
		elsif (member($default, @alllocal_choices)) {
			$$rsecurity_system_hash{$tmp}->set_popdown_strings(@alllocal_choices);
			$$rsecurity_system_hash{$tmp}->entry->set_text($msec->get_check_value('', $tmp));
		}
		push @items, [ new Gtk::Label($tmp._(" (default: %s)",$default)), $$rsecurity_system_hash{$tmp} ]; #, $hbutton ];
	}

	createScrolledWindow(gtkpack(new Gtk::VBox(0, 0),
		   new Gtk::Label(_("The following options can be set to customize your\nsystem security. If you need explanations, click on Help.\n")),
		   create_packtable({ col_spacings => 10, row_spacings => 5 }, @items)));
}

# TODO: Format label & entry in a table to make it nice to see
sub checks_generate_page {
	my ($rsecurity_checks_hash, $msec) = @_;
	my @security_checks = $msec->get_checks('');
	my @choices = qw(yes no default);
	my @ignore_list = qw(MAIL_WARN MAIL_USER);

	my @items;
	foreach my $tmp (@security_checks) {
		if (!member(@ignore_list, $tmp)) {
#		     my $hbutton = gtksignal_connect(new Gtk::Button(_("Help")),
#								  'clicked' => sub { show_msec_help($tmp) } );
			$$rsecurity_checks_hash{$tmp} = new Gtk::Combo();
			$$rsecurity_checks_hash{$tmp}->entry->set_editable(0);
			$$rsecurity_checks_hash{$tmp}->set_popdown_strings(@choices);
			$$rsecurity_checks_hash{$tmp}->entry->set_text($msec->get_check_value('', $tmp));
			push @items, [ new Gtk::Label(_($tmp)), $$rsecurity_checks_hash{$tmp} ]; #, $hbutton ];
		}
	}

	createScrolledWindow(gtkpack(new Gtk::VBox(0, 0),
		   new Gtk::Label(_("The following options can be set to customize your\nsystem security. If you need explanations, click on Help.\n")),
		   create_packtable({ col_spacings => 10, row_spacings => 5 }, @items)));
}

sub draksec_main {
	# Variable Declarations
	my $msec = new security::msec;
	my $w = my_gtk->new('draksec');
	my $window = $w->{window};

	############################ MAIN WINDOW ###################################
	# Set different options to Gtk::Window
	unless ($::isEmbedded) {
	  $w->{rwindow}->set_policy(1,1,1);
	  $w->{rwindow}->set_position(1);
	  $w->{rwindow}->set_title("DrakSec");
	  $window->set_usize( 598,490);
	}

	# Connect the signals
	$window->signal_connect('delete_event', sub { $window->destroy(); } );
	$window->signal_connect('destroy', sub { my_gtk->exit(); } );
	$window->realize();

	$window->add(my $vbox = gtkshow(new Gtk::VBox(0, 0)));

	# Create the notebook (for bookmarks at the top)
	my $notebook = create_notebook();
	$notebook->set_tab_pos('top');

	######################## BASIC OPTIONS PAGE ################################
	my $seclevel_entry = new Gtk::Combo();
	my $secadmin_check = new Gtk::CheckButton();
	my $secadmin_entry = new Gtk::Entry();

	$notebook->append_page(gtkpack__(gtkshow(my $basic_page = new Gtk::VBox(0, 0)),
							   basic_seclevel_explanations($msec),
							   create_packtable ({ col_spacings => 10, row_spacings => 5 },
											 [ basic_seclevel_option(\$seclevel_entry, $msec) ],
											 [ basic_secadmin_check(\$secadmin_check, $msec) ],
											 [ basic_secadmin_entry(\$secadmin_entry, $msec) ] )),
					   gtkshow(new Gtk::Label(_("Basic"))));

	######################### NETWORK OPTIONS ##################################
	my %network_options_value;
	$notebook->append_page(gtkpack__(gtkshow(new Gtk::VBox(0, 0)),
							   network_generate_page(\%network_options_value, $msec)),
					   gtkshow(new Gtk::Label(_("Network Options"))));


	########################## SYSTEM OPTIONS ##################################
	my %system_options_value;

	$notebook->append_page(gtkpack_(
							  gtkshow(new Gtk::VBox(0, 0)),
							  1, system_generate_page(\%system_options_value, $msec)),
					   gtkshow(new Gtk::Label(_("System Options"))));

	######################## PERIODIC CHECKS ###################################
	my %security_checks_value;

	$notebook->append_page(gtkpack(gtkshow(new Gtk::VBox(0, 0)),
							 checks_generate_page(\%security_checks_value, $msec)),
					   gtkshow(new Gtk::Label(_("Periodic Checks"))));


	####################### OK CANCEL BUTTONS ##################################
	my $bok = gtksignal_connect(new Gtk::Button(_("Ok")),
						   'clicked' => sub {
                  my $seclevel_value = $seclevel_entry->entry->get_text();
		  my $secadmin_check_value = $secadmin_check->get_active();
		  my $secadmin_value = $secadmin_entry->get_text();
		  my $w;

		  standalone::explanations("Configuring msec");

		  if($seclevel_value ne $msec->get_secure_level()) {
		      $w = wait_msg(_("Please wait, setting security level..."));
		      standalone::explanations("Setting security level");
		      $msec->set_secure_level($seclevel_value);
		      remove_wait_msg($w);
		  }

		  $w = wait_msg(_("Please wait, setting security options..."));
		  standalone::explanations("Setting security administrator option");
		  if($secadmin_check_value == 1) { $msec->config_check('', 'MAIL_WARN', 'yes') }
		  else { $msec->config_check('', 'MAIL_WARN', 'no') }

		  standalone::explanations("Setting security administrator contact");
		  if($secadmin_value ne $msec->get_check_value('', 'MAIL_USER') && $secadmin_check_value) {
		      $msec->config_check('', 'MAIL_USER', $secadmin_value);
		  }

		  standalone::explanations("Setting security periodic checks");
		  foreach my $key (keys %security_checks_value) {
		      if ($security_checks_value{$key}->entry->get_text() ne $msec->get_check_value('', $key)) {
			  $msec->config_check('', $key, $security_checks_value{$key}->entry->get_text());
		      }
		  }

		  standalone::explanations("Setting msec functions related to networking");
		  foreach my $key (keys %network_options_value) {
		      if($network_options_value{$key} =~ /Combo/) { $msec->config_function('', $key, $network_options_value{$key}->entry->get_text()) }
		      else { $msec->config_function('', $key, $network_options_value{$key}->get_text()) }
		  }

		  standalone::explanations("Setting msec functions related to the system");
		  foreach my $key (keys %system_options_value) {
		      if($system_options_value{$key} =~ /Combo/) { $msec->config_function('', $key, $system_options_value{$key}->entry->get_text()) }
		      else { $msec->config_function('', $key, $system_options_value{$key}->get_text()) }
		  }
		  remove_wait_msg($w);

		  my_gtk->exit(0);
		  } );

	my $bcancel = gtksignal_connect(new Gtk::Button(_("Cancel")),
							  'clicked' => sub { my_gtk->exit(0) } );
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
