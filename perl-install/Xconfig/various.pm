package Xconfig::various; # $Id$

use diagnostics;
use strict;

use Xconfig::card;
use Xconfig::default;
use Xconfig::resolution_and_depth;
use common;


sub to_string {
    my ($raw_X) = @_;

    $raw_X->is_fbdev ? 'frame-buffer' : Xconfig::resolution_and_depth::to_string($raw_X->get_resolution);
}

sub info {
    my ($raw_X, $card) = @_;
    my $info;
    my $xf_ver = Xconfig::card::xorg_version();
    my $title = $card->{use_DRI_GLX} ? N("Xorg %s with 3D hardware acceleration", $xf_ver) : 
                                       N("Xorg %s", $xf_ver);
    my $keyboard = eval { $raw_X->get_keyboard } || {};
    my @monitors = eval { $raw_X->get_monitors };
    my $device = eval { $raw_X->get_device } || {};
    my $mouse = eval { first($raw_X->get_mice) } || {};

    $info .= N("Keyboard layout: %s\n", $keyboard->{XkbLayout});
    $info .= N("Mouse type: %s\n", $mouse->{Protocol});
    $info .= N("Mouse device: %s\n", $mouse->{Device}) if $::expert;
    foreach my $monitor (@monitors) {
	$info .= N("Monitor: %s\n", $monitor->{ModelName});
	$info .= N("Monitor HorizSync: %s\n", $monitor->{HorizSync}) if $::expert;
	$info .= N("Monitor VertRefresh: %s\n", $monitor->{VertRefresh}) if $::expert;
    }
    $info .= N("Graphics card: %s\n", $device->{VendorName} . ' ' . $device->{BoardName});
    $info .= N("Graphics memory: %s kB\n", $device->{VideoRam}) if $device->{VideoRam};
    if (my $resolution = eval { $raw_X->get_resolution }) {
	$info .= N("Color depth: %s\n", translate($Xconfig::resolution_and_depth::depth2text{$resolution->{Depth}}));
	$info .= N("Resolution: %s\n", join('x', @$resolution{'X', 'Y'}));
    }
    $info .= N("Xorg driver: %s\n", $device->{Driver}) if $device->{Driver};
    "$title\n\n$info";
}

sub various {
    my ($in, $card, $options, $b_auto) = @_;

    tvout($in, $card, $options) if !$b_auto;
    choose_xdm($in, $b_auto);
    1;
}

sub runlevel {
    my ($o_runlevel) = @_;
    my $f = "$::prefix/etc/inittab";
    -r $f or log::l("missing inittab!!!"), return;
    if ($o_runlevel) {
	substInFile { s/^id:\d:initdefault:\s*$/id:$o_runlevel:initdefault:\n/ } $f if !$::testing;
    } else {
	cat_($f) =~ /^id:(\d):initdefault:\s*$/m && $1;
    }
}

sub choose_xdm {
    my ($in, $b_auto) = @_;
    my $xdm = $::isStandalone ? runlevel() == 5 : 1;

    if (!$b_auto) {
	$xdm = $in->ask_yesorno_({ 
				  title => N("Graphical interface at startup"),
				  messages =>
N("I can setup your computer to automatically start the graphical interface (Xorg) upon booting.
Would you like Xorg to start when you reboot?"),
				  interactive_help_id => 'configureXxdm',
				 }, $xdm);
    }
    runlevel($xdm ? 5 : 3);
}

sub tvout {
    my ($in, $card, $options) = @_;

    $card->{FB_TVOUT} && $options->{allowFB} or return;

    $in->ask_yesorno('', N("Your graphic card seems to have a TV-OUT connector.
It can be configured to work using frame-buffer.

For this you have to plug your graphic card to your TV before booting your computer.
Then choose the \"TVout\" entry in the bootloader

Do you have this feature?")) or return;
    
    #- rough default value (rationale: http://download.nvidia.com/XFree86_40/1.0-2960/README.txt)
    require timezone;
    my $norm = timezone::read()->{timezone} =~ /America/ ? 'NTSC' : 'PAL';

    $norm = $in->ask_from_list('', N("What norm is your TV using?"), [ 'NTSC', 'PAL' ], $norm) or return;

    configure_FB_TVOUT($in->do_pkgs, { norm => $norm });
}

sub configure_FB_TVOUT {
    my ($do_pkgs, $use_FB_TVOUT) = @_;

    my $raw_X = Xconfig::default::configure($do_pkgs);
    return if is_empty_array_ref($raw_X);

    $raw_X->set_monitors({ HorizSync => '30-50', VertRefresh => ($use_FB_TVOUT->{norm} eq 'NTSC' ? 60 : 50),
			   ModeLine => [ 
	{ val => '"640x480"   29.50       640 675 678 944  480 530 535 625', pre_comment => "# PAL\n" },
	{ val => '"800x600"   36.00       800 818 820 960  600 653 655 750' },
	{ val => '"640x480"  28.195793   640 656 658 784  480 520 525 600', pre_comment => "# NTSC\n" },
	{ val => '"800x600"  38.769241   800 812 814 880  600 646 649 735' },
    ] });
    $raw_X->set_devices({ Driver => 'fbdev' });

    my ($device) = $raw_X->get_devices;
    my ($monitor) = $raw_X->get_monitors;
    $raw_X->set_screens({ Device => $device->{Identifier}, Monitor => $monitor->{Identifier} });

    my $Screen = $raw_X->get_default_screen;
    $Screen->{Display} = [ map { { l => { Depth => { val => $_ } } } } 8, 16 ];

    $raw_X->write("$::prefix/etc/X11/XF86Config.tvout");

    check_XF86Config_symlink();

    {
	require bootloader;
	require fsedit;
	require detect_devices;
	my $all_hds = $::isInstall ? $::o->{all_hds} : fsedit::get_hds();
	my $bootloader = $::isInstall ? $::o->{bootloader} : bootloader::read($all_hds);
	
	if (my $tvout = bootloader::duplicate_kernel_entry($bootloader, 'TVout')) {
	    $tvout->{append} .= " XFree=tvout";
	    bootloader::install($bootloader, $all_hds);
	}
    }
}

sub check_XF86Config_symlink() {
    my $f = "$::prefix/etc/X11/XF86Config";
    if (!-l $f && -e "$f.tvout") {
	rename $f, "$f.standard";
	symlink "XF86Config.standard", $f;
    }
}

sub setupFB {
    my ($bios_vga_mode) = @_;

    require bootloader;
    my ($bootloader, $all_hds);

    if ($::isInstall && !$::globetrotter) {
	($bootloader, $all_hds) = ($::o->{bootloader}, $::o->{all_hds});
    } else {
	require fsedit;
	require fs;
	require bootloader;
	$all_hds = fsedit::get_hds();
	fs::get_info_from_fstab($all_hds);

	$bootloader = bootloader::read($all_hds) or return;
    }

    foreach (@{$bootloader->{entries}}) {
	$_->{vga} = $bios_vga_mode if $_->{vga}; #- replace existing vga= with
    }

    bootloader::action($bootloader, 'write', $all_hds);
    bootloader::action($bootloader, 'when_config_changed');
}

1;
