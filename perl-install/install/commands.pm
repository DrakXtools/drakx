package install::commands; # $Id$

#-########################################################################
#- This file implements a few shell commands...
#-########################################################################

use diagnostics;
use strict;
use vars qw($printable_chars *ROUTE *DF *PS);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;

sub lspcidrake {
    require detect_devices;
    print join "\n", detect_devices::stringlist($_[0] eq '-v'), '';
}

sub bug {
    my ($h) = getopts(\@_, "h");
    my ($o_part_device) = @_;
    $h and die "usage: bug [device]\nput file report.bug on a floppy or usb key\n";

    require any;
    require modules;
    list_modules::load_default_moddeps();

    my $part;
    if ($o_part_device) {
	$part = { device => $o_part_device };
    } else {
	require interactive::stdio;
	my $in = interactive::stdio->new;

	require install::any;
	$part = $in->ask_from_listf('', "Which device?", \&partition_table::description, 
				    [ install::any::removable_media__early_in_install() ]) or return;
    }

    warn "putting file report.bug on $part->{device}\n";
    my $fs_type = fs::type::fs_type_from_magic($part) or die "unknown fs type\n";

    fs::mount::mount(devices::make($part->{device}), '/fd', $fs_type);

    require install::any;
    output('/fd/report.bug', install::any::report_bug());
    fs::mount::umount('/fd');
    common::sync();
}

sub loadkeys {
    my ($h) = getopts(\@_, "h");
    $h || @_ != 1 and die "usage: loadkeys <keyboard>\n";

    require keyboard;
    keyboard::setup_install({ KEYBOARD => $_[0] });
}

1;
