package network::tools;

use common;
use run_program;
use vars qw(@ISA @EXPORT);
use MDK::Common::Globals "network", qw($in $prefix $disconnect_file $connect_prog $connect_file $disconnect_file);

@ISA = qw(Exporter);
@EXPORT = qw(write_cnx_script write_secret_backend write_initscript ask_connect_now connect_backend disconnect_backend read_providers_backend ask_info2 type2interface connected disconnected);
@EXPORT_OK = qw($in);

sub write_cnx_script {
    my ($netc, $type, $up, $down, $type2) = @_;
    if ($type) {
	$netc->{internet_cnx}{$type}{$_->[0]}=$_->[1] foreach ([$connect_file, $up], [$disconnect_file, $down]);
	$netc->{internet_cnx}{$type}{type} = $type2;
    } else {
	foreach ($connect_file, $disconnect_file) {
	    output ("$prefix$_",
'#!/bin/bash
' . if_(!$netc->{at_boot}, 'if [ "x$1" == "x--boot_time" ]; then exit; fi
') . $netc->{internet_cnx}{$netc->{internet_cnx_choice}}{$_});
	chmod 0755, "$prefix" . $_;
	}
    }
}

sub write_secret_backend {
    my ($a, $b) = @_;
    foreach my $i ("pap-secrets", "chap-secrets") {
	substInFile { s/^'$a'.*\n//; $_ .= "\n'$a' * '$b' * \n" if eof  } "$prefix/etc/ppp/$i";
    }
}

sub ask_connect_now {
    $::Wizard_no_previous=1;
    #- FIXME : code the exception to be generated by ask_yesorno, to be able to remove the $::Wizard_no_previous=1;
    if ($in->ask_yesorno(_("Internet configuration"),
			 _("Do you want to try to connect to the Internet now?")
			)) {
	my $up;
	{
	    my $w = $in->wait_message('', _("Testing your connection..."), 1);
	    connect_backend();
	    sleep 5;
	    my $netc = {};
	    $up=connected();
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
    undef $::Wizard_no_previous;
    1;
}

sub connect_backend { run_program::rooted($prefix, "$connect_prog &") }

sub disconnect_backend { run_program::rooted($prefix, "$disconnect_file &") }

sub read_providers_backend { my ($file) = @_; map { /(.*?)=>/ } catMaybeCompressed($file) }

sub ask_info2 {
    my ($cnx, $netc) = @_;
    $::isInstall and $in->set_help('configureNetworkDNS');
    $in->ask_from(_("Connection Configuration"),
		  _("Please fill or check the field below"),
		  [
		   if__($cnx->{irq}, { label => _("Card IRQ"), val => \$cnx->{irq} })  ,
		   if__($cnx->{mem}, { label => _("Card mem (DMA)"), val => \$cnx->{mem} }),
		   if__($cnx->{io}, { label => _("Card IO"), val => \$cnx->{io} }),
		   if__($cnx->{io0}, { label => _("Card IO_0"), val => \$cnx->{io0} }),
		   if__($cnx->{io1}, { label => _("Card IO_1"), val => \$cnx->{io1} }),
		   if__($cnx->{phone_in}, { label => _("Your personal phone number"), val => \$cnx->{phone_in} }),
		   if__($netc->{DOMAINNAME2}, { label => _("Provider name (ex provider.net)"), val => \$netc->{DOMAINNAME2} }),
		   if__($cnx->{phone_out}, { label => _("Provider phone number"), val => \$cnx->{phone_out} }),
		   if__($netc->{dnsServer2}, { label => _("Provider dns 1 (optional)"), val => \$netc->{dnsServer2} }),
		   if__($netc->{dnsServer3}, { label => _("Provider dns 2 (optional)"), val => \$netc->{dnsServer3} }),
		   if__($cnx->{vpivci}, { label => _("Choose your country"), val => \$netc->{vpivci}, list => ['Netherlands', 'France', 'Belgium', 'Italy', 'UK'] }),
		   if__($cnx->{dialing_mode}, { label => _("Dialing mode"), val => \$cnx->{dialing_mode},list=>["auto","manual"]}),
		   if__($cnx->{speed}, { label => _("Connection speed"), val => \$cnx->{speed}, list => ["64 Kb/s", "128 Kb/s"]}),
		   if__($cnx->{huptimeout}, { label => _("Connection timeout (in sec)"), val => \$cnx->{huptimeout} }),
		   if__($cnx->{login}, { label => _("Account Login (user name)"), val => \$cnx->{login} }),
		   if__($cnx->{passwd}, { label => _("Account Password"),  val => \$cnx->{passwd} }),
		  ]
		 ) or return;
    if ($netc->{vpivci}) {
	foreach (['Netherlands', '8_48'], ['France', '8_35'], ['Belgium', '8_35'], ['Italy', '8_35'], ['UK', '0_38']) {
	    $netc->{vpivci} eq $_->[0] and $netc->{vpivci} = $_->[1];
	}
    }
    1;
}

sub type2interface {
    my ($i) = @_;
    $i=~/$_->[0]/ and return $_->[1] foreach (
					      [ modem => 'ppp'],
					      [ isdn_internal => 'ippp'],
					      [ isdn_external => 'ppp'],
					      [ adsl => 'ppp'],
					      [ cable => 'eth'],
					      [ lan => 'eth']);
}

sub connected { gethostbyname("www.mandrakesoft.com") ? 1 : 0 }

sub disconnected { }


sub write_initscript {
    output ("$prefix/etc/rc.d/init.d/internet",
	    q{
#!/bin/bash
#
# internet       Bring up/down internet connection
#
# chkconfig: 2345 11 89
# description: Activates/Deactivates the internet interfaces
#
# dam's (damien@mandrakesoft.com)

# Source function library.
. /etc/rc.d/init.d/functions

	case "$1" in
		start)
                if [ -e } . $connect_file . q{ ]; then
			action "Checking internet connections to start at boot" "} . "$connect_file --boot_time" . q{"
		else
			action "No connection to start" "true"
		fi
		touch /var/lock/subsys/internet
		;;
	stop)
                if [ -e } . $disconnect_file . q{ ]; then
			action "Stopping internet connection if needed: " "} . "$disconnect_file --boot_time" . q{"
		else
			action "No connection to stop" "true"
		fi
		rm -f /var/lock/subsys/internet
		;;
	restart)
		$0 stop
		echo "Waiting 10 sec before restarting the internet connection."
		sleep 10
		$0 start
		;;
	status)
		;;
	*)
	echo "Usage: internet {start|stop|status|restart}"
	exit 1
esac
exit 0
 });
    chmod 0755, "$prefix/etc/rc.d/init.d/internet";
    $::isStandalone ? system("/sbin/chkconfig --add internet") : do {
	symlinkf ("../init.d/internet", "$prefix/etc/rc.d/rc$_") foreach
	  '0.d/K11internet', '1.d/K11internet', '2.d/K11internet', '3.d/S89internet', '5.d/S89internet', '6.d/K11internet';
    };
}
