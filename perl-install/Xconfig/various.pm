package Xconfig::various; # $Id$

use diagnostics;
use strict;

use Xconfig::card;
use Xconfig::resolution_and_depth;
use common;
use any;


sub show_info {
    my ($in, $X) = @_;
    $in->ask_warn('', info($X));
}

sub info {
    my ($raw_X, $card) = @_;
    my $info;
    my $xf_ver = Xconfig::card::using_xf4($card) ? "4.2.0" : "3.3.6";
    my $title = $card->{use_DRI_GLX} || $card->{use_UTAH_GLX} ?
		 _("XFree %s with 3D hardware acceleration", $xf_ver) : _("XFree %s", $xf_ver);
    my $keyboard = eval { $raw_X->get_keyboard } || {};
    my $monitor = eval { $raw_X->get_monitor } || {};
    my $device = eval { $raw_X->get_device } || {};
    my $mouse = eval { first($raw_X->get_mice) } || {};

    $info .= _("Keyboard layout: %s\n", $keyboard->{XkbLayout});
    $info .= _("Mouse type: %s\n", $mouse->{Protocol});
    $info .= _("Mouse device: %s\n", $mouse->{Device}) if $::expert;
    $info .= _("Monitor: %s\n", $monitor->{ModelName});
    $info .= _("Monitor HorizSync: %s\n", $monitor->{HorizSync}) if $::expert;
    $info .= _("Monitor VertRefresh: %s\n", $monitor->{VertRefresh}) if $::expert;
    $info .= _("Graphics card: %s\n", $device->{VendorName} . ' '. $device->{BoardName});
    $info .= _("Graphics memory: %s kB\n", $device->{VideoRam}) if $device->{VideoRam};
    if (my $resolution = eval { $raw_X->get_resolution }) {
	$info .= _("Color depth: %s\n", translate($Xconfig::resolution_and_depth::depth2text{$resolution->{Depth}}));
	$info .= _("Resolution: %s\n", join('x', @$resolution{'X', 'Y'}));
    }
    $info .= _("XFree86 server: %s\n", $card->{server}) if $card->{server};
    $info .= _("XFree86 driver: %s\n", $device->{Driver}) if $device->{Driver};
    "$title\n\n$info";
}

sub choose_xdm {
    my ($in, $auto) = @_;
    my $xdm = $::isStandalone ? any::runlevel($::prefix) : 1;

    if (!$auto || $::isStandalone) {
	$in->set_help('configureXxdm') if !$::isStandalone;

	$xdm = $in->ask_yesorno(_("Graphical interface at startup"),
_("I can setup your computer to automatically start the graphical interface (XFree) upon booting.
Would you like XFree to start when you reboot?"), $xdm) or return
    }
    any::runlevel($::prefix, $xdm ? 5 : 3);
}

1;
