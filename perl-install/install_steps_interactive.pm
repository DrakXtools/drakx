package install_steps_interactive;


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

use common qw(:common);
use partition_table qw(:types);
use install_steps;
use detect_devices;
use network;
use modules;
use lang;
use fs;
use log;

1;

sub errorInStep($$) {
    my ($o, $err) = @_;
    $o->ask_warn(_("Error"), [ _("An error occured"), $err ]);
}


sub chooseLanguage($) {
    my ($o) = @_;
    lang::text2lang($o->ask_from_list("Language",
				      __("Which language do you want?"), # the translation may be used for the help
				      [ lang::list() ], lang::lang2text($o->default("lang"))));
}

sub selectInstallOrUpgrade($) {
    my ($o) = @_;
    $o->ask_from_list_(_("Install/Upgrade"), 
		       _("Is it an install or an updgrade?"),
		       [ __("Install"), __("Upgrade") ], 
		       $o->default("isUpgrade") ? "Upgrade" : "Install") eq "Upgrade";
}

sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    $o->ask_from_list_(_("Install Class"),
		       _("What type of user will you have?"),
		       [ @classes ], $o->default("installClass"));
}

sub setupSCSI {
    my ($o, $auto) = @_;
    my $w;
    my @l = modules::load_thiskind('scsi', sub { 
        $w = $o->wait_message('', 
			      [ _("Installing driver for scsi card %s", $_->[0]),
				$o->{installClass} ne "beginner" ? _("(module %s)", $_->[1]) : () 
			      ]);
    });
    undef $w; # kill wait_message

    return if $auto;
    while (1) {
	@l ?
	  $o->ask_yesorno('', 
			  [ _("Found ") . join(", ", map { $_->[0] } @l) . _(" scsi interfaces"),
			    _("Do you have another one?") ], "No") :
	  $o->ask_yesorno('', _("Do you have an scsi interface?"), "No") or return;

	my $l = $o->ask_from_list('', _("What scsi card have you?"), [ modules::text_of_type('scsi') ]) or return;
	my $m = modules::text2driver($l);
	modules::load($m);
	push @l, [ $l, $m ];
    }
}

sub rebootNeeded($) {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));
    $o->SUPER::rebootNeeded;
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    $o->SUPER::choosePartitionsToFormat($fstab) if $o->{steps}{$o->{step}}{entered} == 1;

    my @l = grep { $_->{mntpoint} && isExt2($_) || isSwap($_) } @$fstab;
    my @r = $o->ask_many_from_list_ref('', _("Choose the partitions you want to format"), 
				       [ map { $_->{mntpoint} || type2name($_->{type}) . " ($_->{device})" } @l ],
				       [ map { \$_->{toFormat} } @l ]);
    defined @r or die "cancel";
}

sub formatPartitions {
    my $o = shift;
    my $w = $o->wait_message('', '');
    foreach (@_) {
	if ($_->{toFormat}) {
	    $w->set(_("Formatting partition %s", $_->{device}));
	    fs::format_part($_);
	}
    }
}

sub configureNetwork($) {
    my ($o, $first_time) = @_;
    my $r = '';

    if ($o->{intf}) {
	if ($first_time) {
	    my @l = (
		     __("Keep the current IP configuration"),
		     __("Reconfigure network now"),
		     __("Don't set up networking"),
		    );
	    $r = $o->ask_from_list_(_("Network Configuration"), 
				    _("LAN networking has already been configured. Do you want to:"),
				    [ @l ]);
	    !$r || $r =~ /^Don't/ and return;
	}
    } else {
	$o->ask_yesorno(_("Network Configuration"),
			_("Do you want to configure LAN (not dialup) networking for your installed system?")) or return;
    }
    
    if ($r !~ /^Keep/) {
	my @l = first(network::getNet());
	@l = ($l[0]) unless $::expert; # keep only one

	$o->configureNetworkIntf(network::findIntf($o->{intf}, $_)) foreach @l;
	$o->configureNetworkNet($o->{netc} ||= {});
    }
    $o->SUPER::configureNetwork;
}
	


sub createBootdisk {
    my ($o, $first_time) = @_;
    my @l = detect_devices::floppies();
 
    if ($first_time || @l == 1) {
	$o->ask_yesorno('',
 _("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
lilo on your system, or another operating system removes lilo, or lilo doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?"), !$o->default("mkbootdisk")) or return;

	$o->{mkbootdisk} = $o->default("mkbootdisk") || 1;
    } else {
	@l or die _("Sorry, no floppy drive available");

	$o->{mkbootdisk} = $o->ask_from_list('', 
_("Choose the floppy drive you want to use to make the bootdisk"), 
					     \@l, $o->default("mkbootdisk"));
    }

    $o->ask_warn('', _("Insert a floppy in floppy drive %s", $o->{mkbootdisk}));
    my $w = $o->wait_message('', _("Creating bootdisk"));
    $o->SUPER::createBootdisk;
}

sub setupBootloader($) {
    my ($o) = @_;
    my @l = (__("First sector of drive"), __("First sector of boot partition"));

    $o->{bootloader}{onmbr} = 
      $o->ask_from_list_(_("Lilo Installation"), 
			 _("Where do you want to install the bootloader?"), 
			 \@l, 
			 $l[!$o->default("bootloader")->{onmbr}]
			) eq $l[0];
    $o->SUPER::setupBootloader;
}

sub exitInstall { 
    my ($o) = @_;
    $o->ask_warn('',
_("Congratulations, installation is complete.
Remove the boot media and press return to reboot.
For information on fixes which are available for this release of Linux Mandrake,
consult the Errata available from http://www.linux-mandrake.com/.
Information on configuring your system is available in the post
install chapter of the Official Linux Mandrake User's Guide."));
}

=cut
