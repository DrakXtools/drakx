package install_steps_interactive;

# heritate from this class and you'll get all made interactivity for same steps.
# for this you need to provide 
# - ask_from_listW(o, title, messages, arrayref, default) returns one string of arrayref
# - ask_many_from_listW(o, title, messages, arrayref, arrayref2) returns one string of arrayref
#
# where
# - o is the object
# - title is a string
# - messages is an refarray of strings
# - default is an optional string (default is in arrayref)
# - arrayref is an arrayref of strings
# - arrayref2 contains booleans telling the default state, 
#
# ask_from_list and ask_from_list_ are wrappers around ask_from_biglist and ask_from_smalllist
#
# ask_from_list_ just translate arrayref before calling ask_from_list and untranslate the result
#
# ask_from_listW should handle differently small lists and big ones.


use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps);

use common qw(:common);
use partition_table qw(:types);
use install_steps;
use lang;
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
				      [ lang::list() ]));
}

sub selectInstallOrUpgrade($) {
    my ($o) = @_;
    $o->ask_from_list_(_("Install/Upgrade"), 
		       _("Is it an install or an updgrade?"),
		       [ __("Install"), __("Upgrade") ], 
		       "Install") eq "Upgrade";
}

sub selectInstallClass($@) {
    my ($o, @classes) = @_;
    $o->ask_from_list_(_("Install Class"),
		       _("What type of user will you have?"),
		       [ @classes ]);
}

sub rebootNeeded($) {
    my ($o) = @_;
    $o->ask_warn('', _("You need to reboot for the partition table modifications to take place"));
    $o->SUPER::rebootNeeded;
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;
    my @l = grep { $_->{mntpoint} && (isExt2($_) || isSwap($_)) } @$fstab;
    my @r = $o->ask_many_from_list('', _("Choose the partitions you want to format"), 
				   [ map { $_->{mntpoint} } @l ], 
				   [ map { $_->{notFormatted} } @l ]);
    for (my $i = 0; $i < @l; $i++) {
	$l[$i]->{toFormat} = $r[$i];
    }
}

sub createBootdisk($) {
    my ($o) = @_;
    
    $o->{default}->{mkbootdisk} = $o->ask_yesorno('',
 _("A custom bootdisk provides a way of booting into your Linux system without
depending on the normal bootloader. This is useful if you don't want to install
lilo on your system, or another operating system removes lilo, or lilo doesn't
work with your hardware configuration. A custom bootdisk can also be used with
the Mandrake rescue image, making it much easier to recover from severe system
failures. Would you like to create a bootdisk for your system?"));

    $o->ask_warn('',
_("Insert a floppy in drive fd0 (aka A:)"));

    $o->SUPER::createBootdisk;
}

sub setupBootloader($) {
    my ($o) = @_;

    my $where = $o->ask_from_list(_("Lilo Installation"), _("Where do you want to install the bootloader?"), [ _("First sector of drive"), _("First sector of boot partition") ]);
    $o->{default}->{bootloader}->{onmbr} = $where eq _("First sector of drive");
    
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
