package Xconfig::main; # $Id$

use diagnostics;
use strict;

use Xconfig::monitor;
use Xconfig::card;
use Xconfig::resolution_and_depth;
use Xconfig::various;
use Xconfig::screen;
use Xconfig::test;
use common;
use any;


sub configure_monitor {
    my ($in, $raw_X) = @_;

    Xconfig::monitor::configure($in, $raw_X) or return;
    $raw_X->write;
    'config_changed';
}

sub configure_resolution {
    my ($in, $raw_X) = @_;

    my $card = Xconfig::card::from_raw_X($raw_X);
    my $monitor = Xconfig::monitor::from_raw_X($raw_X);
    Xconfig::resolution_and_depth::configure($in, $raw_X, $card, $monitor) or return;
    $raw_X->write;
    'config_changed';
}


sub configure_everything_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;
    
    my $card = Xconfig::card::configure_auto_install($raw_X, $do_pkgs, $old_X, $options) or return;
    my $monitor = Xconfig::monitor::configure_auto_install($raw_X, $old_X) or return;
    Xconfig::screen::configure($raw_X, $card) or return;
    my $resolution = Xconfig::resolution_and_depth::configure_auto_install($raw_X, $card, $monitor, $old_X);

    export_to_install_X($card, $monitor, $resolution);
    $raw_X->write;
    symlinkf "../..$card->{prog}", "$::prefix/etc/X11/X" if $card->{server} !~ /Xpmac/;

    any::runlevel($::prefix, $old_X->{xdm} ? 5 : 3);
}

sub configure_everything {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;

    my $ok = 1;
    $ok &&= my $card = Xconfig::card::configure($in, $raw_X, $do_pkgs, $auto, $options);
    $ok &&= my $monitor = Xconfig::monitor::configure($in, $raw_X, $auto);
    $ok &&= Xconfig::screen::configure($raw_X, $card);
    $ok &&= my $resolution = Xconfig::resolution_and_depth::configure($in, $raw_X, $card, $monitor, $auto);
    $ok &&= Xconfig::test::test($in, $raw_X, $card, $auto);

    $ok ||= $in->ask_yesorno('', _("Keep the changes?
The current configuration is:

%s", Xconfig::various::info($raw_X, $card)));

    if ($ok) {
	export_to_install_X($card, $monitor, $resolution);
	$raw_X->write;
	symlinkf "../..$card->{prog}", "$::prefix/etc/X11/X" if $card->{server} !~ /Xpmac/;
    }
    Xconfig::various::choose_xdm($in, $auto);
    
    $ok && 'config_changed';
}


sub export_to_install_X {
    my ($card, $monitor, $resolution) = @_;

    $::isInstall or return;

    $::o->{X}{resolution_wanted} = $resolution->{X};
    $::o->{X}{default_depth} = $resolution->{Depth};
    $::o->{X}{bios_vga_mode} = $resolution->{bios};
    $::o->{X}{monitor} = $monitor if $monitor->{manually_chosen};
    $::o->{X}{card} = $monitor if $card->{manually_chosen};
}


#- most usefull XFree86-4.0.1 server options. Default values is the first ones.
our @options_serverflags = (
			'DontZap'                 => [ "Off", "On" ],
			'DontZoom'                => [ "Off", "On" ],
			'DisableVidModeExtension' => [ "Off", "On" ],
			'AllowNonLocalXvidtune'   => [ "Off", "On" ],
			'DisableModInDev'         => [ "Off", "On" ],
			'AllowNonLocalModInDev'   => [ "Off", "On" ],
			'AllowMouseOpenFail'      => [ "False", "True" ],
			'VTSysReq'                => [ "Off", "On" ],
			'BlankTime'               => [ "10", "5", "3", "15", "30" ],
			'StandByTime'             => [ "20", "10", "6", "30", "60" ],
			'SuspendTime'             => [ "30", "15", "9", "45", "90" ],
			'OffTime'                 => [ "40", "20", "12", "60", "120" ],
			'Pixmap'                  => [ "32", "24" ],
			'PC98'                    => [ "auto-detected", "False", "True" ],
			'NoPM'                    => [ "False", "True" ],
);

1;
