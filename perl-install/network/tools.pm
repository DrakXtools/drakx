package network::tools;

use common;
use run_program;
use vars qw(@ISA @EXPORT);
use globals "network", qw($in $prefix $install $disconnect_file $connect_prog);

@ISA = qw(Exporter);
@EXPORT = qw(write_secret_backend ask_connect_now connect_backend disconnect_backend read_providers_backend ask_info2 connected disconnected);
@EXPORT_OK = qw($in);

sub write_secret_backend {
    my ($a, $b) = @_;
    foreach my $i ("pap-secrets", "chap-secrets") {
	substInFile { s/^$a.*\n//; $_ .= "\n'$a' * '$b' * \n" if eof  } "$prefix/etc/ppp/$i";
    }
}

sub ask_connect_now {
    my ($cnx, $inter) = @_;
    if ($in->ask_yesorno(_("Internet configuration"),
			 _("Do you want to try to connect to the Internet now?")
			)) {
	my $up;
	{
	    my $w = $in->wait_message('', _("Testing your connection..."), 1);
	    connect_backend();
	    sleep 5;
	    my $netc = {};
	    $up=connected($netc);
	}
	my $m = $up ? (_("The system is now connected to Internet.") .
		     if_($::isInstall, _("For Security reason, it will be disconnected now.")) ) :
		       _("The system doesn't seem to be connected to internet.
Try to reconfigure your connection.");
	if ($::isWizard) {
	    $::Wizard_no_previous=1;
	    $::Wizard_finished=1;
	    $in->ask_okcancel(_("Network Configuration"), $m, 1);
	    undef $::Wizard_no_previous;
	    undef $::Wizard_finished;
	} else {  $in->ask_warn('', $m ); }
	$::isInstall and disconnect_backend();
    }
    1;
}

sub connect_backend { run_program::rooted($prefix, "$connect_prog &") }

sub disconnect_backend { run_program::rooted($prefix, "$disconnect_file &") }

sub read_providers_backend { my ($file) = @_; map { /(.*?)=>/ } catMaybeCompressed($file) }

sub ask_info2 {
    my ($cnx, $netc) = @_;
    $::isInstall and $in->set_help('configureNetworkDNS');
    $in->ask_from_entries_refH(_("Connection Configuration"),
			       _("Please fill or check the field below"),
			       [
				if__ ($cnx->{irq}, { label => _("Card IRQ"), val => \$cnx->{irq} })  ,
				if__ ($cnx->{mem}, { label => _("Card mem (DMA)"), val => \$cnx->{mem} }),
				if__ ($cnx->{io}, { label => _("Card IO"), val => \$cnx->{io} }),
				if__ ($cnx->{io0}, { label => _("Card IO_0"), val => \$cnx->{io0} }),
				if__ ($cnx->{io1}, { label => _("Card IO_1"), val => \$cnx->{io1} }),
				if__ ($cnx->{phone_in}, { label => _("Your personal phone number"), val => \$cnx->{phone_in} }),
				if__ ($netc->{DOMAINNAME2}, { label => _("Provider name (ex provider.net)"), val => \$netc->{DOMAINNAME2} }),
				if__ ($cnx->{phone_out}, { label => _("Provider phone number"), val => \$cnx->{phone_out} }),
				if__ ($netc->{dnsServer2}, { label => _("Provider dns 1 (optional)"), val => \$netc->{dnsServer2} }),
				if__ ($netc->{dnsServer3}, { label => _("Provider dns 2 (optional)"), val => \$netc->{dnsServer3} }),
				if__ ($cnx->{dialing_mode}, { label => _("Dialing mode"), val => \$cnx->{dialing_mode}, list => [ "auto", "manual"] }),
				if__ ($cnx->{login}, { label => _("Account Login (user name)"), val => \$cnx->{login} }),
				if__ ($cnx->{passwd}, { label => _("Account Password"),  val => \$cnx->{passwd} }),
			      ]
			     ) or return;
    1;
}

sub connected { gethostbyname("www.mandrakesoft.com") ? 1 : 0; }

sub disconnected { }
