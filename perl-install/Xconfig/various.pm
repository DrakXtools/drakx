package Xconfig::various; # $Id$

use diagnostics;
use strict;

use Xconfig::card;
use Xconfig::default;
use Xconfig::resolution_and_depth;
use common;


sub info {
    my ($raw_X, $card) = @_;
    my $info;
    my $xf_ver = Xconfig::card::using_xf4($card) ? Xconfig::card::xfree4_version() : Xconfig::card::xfree3_version();
    my $title = $card->{use_DRI_GLX} || $card->{use_UTAH_GLX} ?
		 N("XFree %s with 3D hardware acceleration", $xf_ver) : N("XFree %s", $xf_ver);
    my $keyboard = eval { $raw_X->get_keyboard } || {};
    my $monitor = eval { $raw_X->get_monitor } || {};
    my $device = eval { $raw_X->get_device } || {};
    my $mouse = eval { first($raw_X->get_mice) } || {};

    $info .= N("Keyboard layout: %s\n", $keyboard->{XkbLayout});
    $info .= N("Mouse type: %s\n", $mouse->{Protocol});
    $info .= N("Mouse device: %s\n", $mouse->{Device}) if $::expert;
    $info .= N("Monitor: %s\n", $monitor->{ModelName});
    $info .= N("Monitor HorizSync: %s\n", $monitor->{HorizSync}) if $::expert;
    $info .= N("Monitor VertRefresh: %s\n", $monitor->{VertRefresh}) if $::expert;
    $info .= N("Graphics card: %s\n", $device->{VendorName} . ' ' . $device->{BoardName});
    $info .= N("Graphics memory: %s kB\n", $device->{VideoRam}) if $device->{VideoRam};
    if (my $resolution = eval { $raw_X->get_resolution }) {
	$info .= N("Color depth: %s\n", translate($Xconfig::resolution_and_depth::depth2text{$resolution->{Depth}}));
	$info .= N("Resolution: %s\n", join('x', @$resolution{'X', 'Y'}));
    }
    $info .= N("XFree86 server: %s\n", $card->{server}) if $card->{server};
    $info .= N("XFree86 driver: %s\n", $device->{Driver}) if $device->{Driver};
    "$title\n\n$info";
}

sub various {
    my ($in, $card, $options, $auto) = @_;

    tvout($in, $card, $options) if !$auto;
    choose_xdm($in, $auto);
    1;
}

sub runlevel {
    my ($runlevel) = @_;
    my $f = "$::prefix/etc/inittab";
    -r $f or log::l("missing inittab!!!"), return;
    if ($runlevel) {
	substInFile { s/^id:\d:initdefault:\s*$/id:$runlevel:initdefault:\n/ } $f if !$::testing;
    } else {
	cat_($f) =~ /^id:(\d):initdefault:\s*$/ && $1;
    }
}

sub choose_xdm {
    my ($in, $auto) = @_;
    my $xdm = $::isStandalone ? runlevel() == 5 : 1;

    if (!$auto || $::isStandalone) {
	$in->set_help('configureXxdm') if !$::isStandalone;

	$xdm = $in->ask_yesorno(N("Graphical interface at startup"),
N("I can setup your computer to automatically start the graphical interface (XFree) upon booting.
Would you like XFree to start when you reboot?"), $xdm) or return;
    }
    runlevel($xdm ? 5 : 3);
}

sub tvout {
    my ($in, $card, $options) = @_;

    $card->{FB_TVOUT} && Xconfig::card::using_xf4($card) && $options->{allowFB} or return;

    $in->ask_yesorno('', N("Your graphic card seems to have a TV-OUT connector.
It can be configured to work using frame-buffer.

For this you have to plug your graphic card to your TV before booting your computer.
Then choose the \"TVout\" entry in the bootloader

Do you have this feature?")) or return;
    
    #- rough default value (rationale: http://download.nvidia.com/XFree86_40/1.0-2960/README.txt)
    require timezone;
    my $norm = timezone::read()->{timezone} =~ /America/ ? 'NTSC' : 'PAL';

    $norm = $in->ask_from_list('', N("What norm is your TV using?"), [ 'NTSC', 'PAL' ], $norm) or return;

    configure_FB_TVOUT({ norm => $norm });
}

sub configure_FB_TVOUT {
    my ($use_FB_TVOUT) = @_;

    my $raw_X = Xconfig::default::configure();
    my $xfree4 = $raw_X->{xfree4};

    $xfree4->set_monitors({ HorizSync => '30-50', VertRefresh => ($use_FB_TVOUT->{norm} eq 'NTSC' ? 60 : 50) });
    first($xfree4->get_monitor_sections)->{ModeLine} = [ 
	{ val => '"640x480"   29.50       640 675 678 944  480 530 535 625', pre_comment => "# PAL\n" },
	{ val => '"800x600"   36.00       800 818 820 960  600 653 655 750' },
	{ val => '"640x480"  28.195793   640 656 658 784  480 520 525 600', pre_comment => "# NTSC\n" },
	{ val => '"800x600"  38.769241   800 812 814 880  600 646 649 735' },
    ];
    $xfree4->set_devices({ Driver => 'fbdev' });

    my ($device) = $xfree4->get_devices;
    my ($monitor) = $xfree4->get_monitors;
    $xfree4->set_screens({ Device => $device->{Identifier}, Monitor => $monitor->{Identifier} });

    my $Screen = $xfree4->get_default_screen;
    $Screen->{Display} = [ map { { l => { Depth => { val => $_ } } } } 8, 16 ];

    $xfree4->write("$::prefix/etc/X11/XF86Config-4.tvout");

    check_XF86Config_symlink();

    {
	require bootloader;
	require fsedit;
	require detect_devices;
	my ($bootloader, $all_hds) =
	  $::isInstall ? ($::o->{bootloader}, $::o->{all_hds}) : 
	    (bootloader::read(), fsedit::get_hds());
	
	if (my $tvout = bootloader::duplicate_kernel_entry($bootloader, 'TVout')) {
	    $tvout->{append} .= " XFree=tvout";
	    bootloader::install($bootloader, [ fsedit::get_all_fstab($all_hds) ], $all_hds->{hds});
	}
    }
}

sub check_XF86Config_symlink {
    my $f = "$::prefix/etc/X11/XF86Config-4";
    if (!-l $f && -e "$f.tvout") {
	rename $f, "$f.standard";
	symlink "XF86Config-4.standard", $f;
    }
}

1;
