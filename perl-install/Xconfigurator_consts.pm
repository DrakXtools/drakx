package Xconfigurator; # $Id$

use common;

%depths = (
      8 => __("256 colors (8 bits)"),
     15 => __("32 thousand colors (15 bits)"),
     16 => __("65 thousand colors (16 bits)"),
     24 => __("16 million colors (24 bits)"),
     32 => __("4 billion colors (32 bits)"),
);
@depths = ikeys(%depths);

@resolutions = qw(640x480 800x600 1024x768 1152x864 1280x1024 1400x1050 1600x1200 1920x1440 2048x1536);

%serversdriver = arch() =~ /^sparc/ ? (
    'Mach64'    => "accel",
    '3DLabs'    => "accel",
    'Sun'       => "fbdev",
    'Sun24'     => "fbdev",
    'SunMono'   => "fbdev",
    'VGA16'     => "vga16",
    'FBDev'     => "fbdev",
) : (
    'SVGA'      => "svga",
#-    'Rage128'   => "svga",
#-    '3dfx'      => "svga",
    'S3'        => "accel",
    'Mach32'    => "accel",
    'Mach8'     => "accel",
    '8514'      => "accel",
    'P9000'     => "accel",
    'AGX'       => "accel",
    'W32'       => "accel",
    'Mach64'    => "accel",
    'I128'      => "accel",
    'S3V'       => "accel",
    '3DLabs'    => "accel",
    'Mono'      => "vga2",
    'VGA16'     => "vga16",
    'FBDev'     => "fbdev",
);
@svgaservers = grep { $serversdriver{$_} eq "svga" } keys(%serversdriver);
@accelservers = grep { $serversdriver{$_} eq "accel" } keys(%serversdriver);
@allbutfbservers = grep { arch() =~ /^sparc/ || $serversdriver{$_} ne "fbdev" } keys(%serversdriver);
@allservers = keys(%serversdriver);

@allbutfbdrivers = ((arch() =~ /^sparc/ ? qw(sunbw2 suncg14 suncg3 suncg6 sunffb sunleo suntcx) :
		    qw(apm ark chips cirrus cyrix glide i128 i740 i810 imstt mga neomagic newport nv rendition
                       s3 s3virge savage siliconmotion sis tdfx tga trident tseng vmware)), qw(ati glint vga));
@alldrivers = (@allbutfbdrivers, 'fbdev', 'vesa');

%vgamodes = (
    '640xx8'       => 769,
    '640x480x8'    => 769,
    '800xx8'       => 771,
    '800x600x8'    => 771,
    '1024xx8'      => 773,
    '1024x768x8'   => 773,
    '1280xx8'      => 775,
    '1280x1024x8'  => 775,
    '640xx15'      => 784,
    '640x480x15'   => 784,
    '800xx15'      => 787,
    '800x600x15'   => 787,
    '1024xx15'     => 790,
    '1024x768x15'  => 790,
    '1280xx15'     => 793,
    '1280x1024x15' => 793,
    '640xx16'      => 785,
    '640x480x16'   => 785,
    '800xx16'      => 788,
    '800x600x16'   => 788,
    '1024xx16'     => 791,
    '1024x768x16'  => 791,
    '1280xx16'     => 794,
    '1280x1024x16' => 794,
#-    '640xx24'      => 786, #- there is a problem with these resolutions since the BIOS may take 24 or 32 planes.
#-    '640x480x24'   => 786,
#-    '800xx24'      => 789,
#-    '800x600x24'   => 789,
#-    '1024xx24'     => 792,
#-    '1024x768x24'  => 792,
#-    '1280xx24'     => 795,
#-    '1280x1024x24' => 795,
);

{ #- @monitorSize2resolution
    my %l = my @l = ( #- size in inch
	13 => "640x480",
	14 => "800x600",
	15 => "800x600",
	16 => "1024x768",
	17 => "1024x768",
	18 => "1024x768",
	19 => "1280x1024",
	20 => "1280x1024",
        21 => "1600x1200",
    );
    for (my $i = 0; $i < $l[0]; $i++) {
	$monitorSize2resolution[$i] = $l[1];
    }
    while (my ($s, $r) = each %l) {
	$monitorSize2resolution[$s] = $r;
    }
}

%videomemory = (
    __("256 kB") => 256,
    __("512 kB") => 512,
    __("1 MB") => 1024,
    __("2 MB") => 2048,
    __("4 MB") => 4096,
    __("8 MB") => 8192,
    __("16 MB") => 16384,
    __("32 MB") => 32768,
    __("64 MB or more") => 65536,
);

$good_default_monitor = arch !~ /ppc/ ? "High Frequency SVGA, 1024x768 at 70 Hz" : 
    detect_devices::get_mac_model =~ /^iBook/ ? "iBook 800x600" : "iMac/PowerBook 1024x768";
$low_default_monitor = "Super VGA, 800x600 at 56 Hz";

%standard_monitors = (
  __("Standard VGA, 640x480 at 60 Hz")                             => [ '640x480@60',      "31.5"            , "60" ],
  __("Super VGA, 800x600 at 56 Hz") 				   => [ '800x600@56',      "31.5-35.1"       , "55-60" ],
  __("8514 Compatible, 1024x768 at 87 Hz interlaced (no 800x600)") => [ '8514 compatible', "31.5,35.5"       , "60,70,87" ],
  __("Super VGA, 1024x768 at 87 Hz interlaced, 800x600 at 56 Hz")  => [ '1024x768@87i',    "31.5,35.15,35.5" , "55-90" ],
  __("Extended Super VGA, 800x600 at 60 Hz, 640x480 at 72 Hz")     => [ '800x600@60',      "31.5-37.9"       , "55-90" ],
  __("Non-Interlaced SVGA, 1024x768 at 60 Hz, 800x600 at 72 Hz")   => [ '1024x768@60',     "31.5-48.5"       , "55-90" ],
  __("High Frequency SVGA, 1024x768 at 70 Hz") 		           => [ '1024x768@70',     "31.5-57.0"       , "50-90" ],
  __("Multi-frequency that can do 1280x1024 at 60 Hz") 	           => [ '1280x1024@60',    "31.5-64.3"       , "50-90" ],
  __("Multi-frequency that can do 1280x1024 at 74 Hz") 	           => [ '1280x1024@74',    "31.5-79.0"       , "50-100" ],
  __("Multi-frequency that can do 1280x1024 at 76 Hz") 	           => [ '1280x1024@76',    "31.5-82.0"       , "40-100" ],
  __("Monitor that can do 1600x1200 at 70 Hz")                     => [ '1600x1200@70',    "31.5-88.0"       , "50-120" ],
  __("Monitor that can do 1600x1200 at 76 Hz")		           => [ '1600x1200@76',    "31.5-94.0"       , "50-160" ],
);

@vsyncranges = ("50-70", "50-90", "50-100", "40-150");

@hsyncranges = (
	"31.5",
	"31.5-35.1",
	"31.5, 35.5",
	"31.5, 35.15, 35.5",
	"31.5-37.9",
	"31.5-48.5",
	"31.5-57.0",
	"31.5-64.3",
	"31.5-79.0",
	"31.5-82.0",
	"31.5-88.0",
	"31.5-94.0",
);

%min_hsync4wres = (
	 640 => 31.5,
	 800 => 35.1,
	1024 => 35.5,
	1152 => 44.0,
	1280 => 51.0,
	1400 => 65.5,
	1600 => 75.0,
	1920 => 90.0,
	2048 => 136.5,
);


%lines = (
#-    'Cirrus Logic|GD 5446' => [ '	Option "no_bitblt"' ],
      'Silicon Integrated Systems [SiS]|86C326' => [ qq(	Option "noaccel") ],
      'Neomagic Corporation|NM2160 [MagicGraph 128XD]' => [ 'Option "XaaNoScanlineImageWriteRect"', 'Option "XaaNoScanlineCPUToScreenColorExpandFill' ],
      'Neomagic Corporation|[MagicMedia 256XL+]' => [ '    Option "sw_cursor"' ],

#-      'Trident Microsystems|Cyber 9525' => [ '	Option "noaccel"' ],
#-      'S3 Inc.|86c368 [Trio 3D/2X]' => [ '	ChipID  0x8a10' ],
);

#- most usefull XFree86-4.0.1 server options. Default values is the first ones.
@options_serverflags = (
			'NoTrapSignals'           => [ "Off", "On" ],
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

#- most usefull server options have to be accessible at the beginning, since
#- no more than a small set of options will be available for the user, maybe ?
@options = (
	    [ 'DPMS',              'XFree86',     '.*' ],
	    [ 'SyncOnGreen',       'XFree86',     '.*' ],
	    [ 'power_saver',       'Mono',        '.*' ],
	    [ 'hibit_low',         'VGA16',       'Tseng.*ET4000' ],
	    [ 'hibit_high',        'VGA16',       'Tseng.*ET4000' ],
	    [ 'power_saver',       'VGA16',       '.*' ],
	    [ 'noaccel',           'SVGA',        'Cirrus|C&T|SiS|Oak|Western Digital|Alliance|Trident|Tseng' ],
	    [ 'no_accel',          'SVGA',        'ARK|MGA|i740|Oak|ET6000|W32|Media.*GX|Neomagic' ],
	    [ 'linear',            'SVGA',        'Cirrus|ET6000|ET4000/W32p rev [CD]|Oak|Neomagic|Triden|Tseng' ],
	    [ 'nolinear',          'SVGA',        'Cirrus|C&T|Trident' ],
	    [ 'no_linear',         'SVGA',        'ARK|SiS|Neomagic|Tseng' ],
	    [ 'no_bitblt',         'SVGA',        'Cirrus|C&T|SiS' ],
	    [ 'no_imageblt',       'SVGA',        'Cirrus|C&T|SiS' ],
	    [ 'sw_cursor',         'SVGA',        '.*' ],
	    [ 'slow_dram',         'SVGA',        'Cirrus|Trident|ET6000|W32|Western Digital|Tseng' ],
	    [ 'mga_sdram',         'SVGA',        'MGA' ],
	    [ 'no_pixmap_cache',   'SVGA',        'ARK|Cirrus|C&T|MGA|SiS|Trident.*9440|Trident.*9680|Tseng' ],
	    [ 'no_mmio',           'SVGA',        'Cirrus|Neomagic|Trident' ],
	    [ 'pci_burst_off',     'SVGA',        'ET6000|W32|Trident|Tseng' ],
	    [ 'hw_clocks',         'SVGA',        'SiS|C&T' ],
	    [ 'use_modeline',      'SVGA',        'C&T' ],
	    [ 'enable_bitblt',     'SVGA',        'Oak' ],
	    [ 'w32_interleave_off', 'SVGA',       'ET6000|W32|Tseng' ],
	    [ 'fifo_conservative', 'SVGA',        'Cirrus|ARK|SiS|Oak' ],
	    [ 'fifo_moderate',     'SVGA',        'Cirrus|ARK|SiS' ],
	    [ 'all_wait',          'SVGA',        'Oak' ],
	    [ 'one_wait',          'SVGA',        'Oak' ],
	    [ 'first_wait',        'SVGA',        'Oak' ],
	    [ 'first_wwait',       'SVGA',        'Oak' ],
	    [ 'write_wait',        'SVGA',        'Oak' ],
	    [ 'read_wait',         'SVGA',        'Oak' ],
	    [ 'clgd6225_lcd',      'SVGA',        'Cirrus' ],
	    [ 'fix_panel_size',    'SVGA',        'C&T' ],
	    [ 'lcd_center',        'SVGA',        'C&T|Neomagic|Trident' ],
	    [ 'cyber_shadow',      'SVGA',        'Trident' ],
	    [ 'STN',               'SVGA',        'C&T' ],
	    [ 'no_stretch',        'SVGA',        'C&T|Cirrus|Neomagic|Trident' ],
	    [ 'no_prog_lcd_mode_regs', 'SVGA',    'Neomagic' ],
	    [ 'prog_lcd_mode_stretch', 'SVGA',    'Neomagic' ],
	    [ 'suspend_hack',      'SVGA',        'C&T' ],
	    [ 'use_18bit_bus',     'SVGA',        'C&T' ],
	    [ 'hibit_low',         'SVGA',        'Tseng.*ET4000' ],
	    [ 'hibit_high',        'SVGA',        'Tseng.*ET4000' ],
	    [ 'probe_clocks',      'SVGA',        'Cirrus' ],
	    [ 'power_saver',       'SVGA',        '.*' ],
	    [ 'use_vlck1',         'SVGA',        'C&T' ],
	    [ 'sgram',             'SVGA',        'i740' ],
	    [ 'sdram',             'SVGA',        'i740' ],
	    [ 'no_2mb_banksel',    'SVGA',        'Cirrus' ],
	    [ 'tgui_pci_read_on',  'SVGA',        'Trident' ],
	    [ 'tgui_pci_write_on', 'SVGA',        'Trident' ],
	    [ 'no_program_clocks', 'SVGA',        'Trident' ],
	    [ 'mmio',              'SVGA',        'Cirrus|C&T|Neomagic' ],
	    [ 'sync_on_green',     'SVGA',        'C&T|MGA' ],
	    [ 'pci_retry',         'SVGA',        'Tseng|MGA|Cirrus' ],
	    [ 'hw_cursor',         'SVGA',        'C&T|SiS|ARK|ET6000|i740|Tseng' ],
	    [ 'xaa_no_color_exp',  'SVGA',        'C&T|Cirrus|Trident|Tseng' ],
	    [ 'xaa_benchmarks',    'SVGA',        'C&T' ],
	    [ 'pci_burst_on',      'SVGA',        'Trident|Tseng' ],
	    [ 'prog_lcd_mode_regs', 'SVGA',       'Neomagic' ],
	    [ 'no_prog_lcd_mode_stretch', 'SVGA', 'Neomagic' ],
	    [ 'no_wait',           'SVGA',        'Oak' ],
	    #- [ 'med_dram',          'SVGA',        'Cirrus|Trident|Western Digital' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'fast_dram',         'SVGA',        'C&T|Cirrus|ET[46]000|Trident|Western Digital' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'fast_vram',         'SVGA',        'SiS' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'clock_50',          'SVGA',        'Oak' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'clock_66',          'SVGA',        'Oak' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'fifo_aggressive',   'SVGA',        'Cirrus|ARK|SiS|Oak' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'override_validate_mode', 'SVGA',   'Neomagic' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'tgui_mclk_66',      'SVGA',        'Trident' ], #- WARNING, MAY DAMAGE CARD
	    #- [ 'favour_bitblt',     'SVGA',        'Cirrus' ], #- OBSELETE
	    [ 'sw_cursor',         '3DLabs',      '.*' ],
	    [ 'no_pixmap_cache',   '3DLabs',      '.*' ],
	    [ 'no_accel',          '3DLabs',      '.*' ],
	    [ 'firegl_3000',       '3DLabs',      '.*' ],
	    [ 'sync_on_green',     '3DLabs',      '.*' ],
	    [ 'pci_retry',         '3DLabs',      '.*' ],
	    #- [ 'overclock_mem',     '3DLabs',      '.*' ], #- WARNING, MAY DAMAGE CARD
	    [ 'dac_8_bit',         'I128',        '.*' ],
	    [ 'no_accel',          'I128',        '.*' ],
	    [ 'sync_on_green',     'I128',        '.*' ],
	    [ 'composite',         'Mach32',      '.*' ],
	    [ 'sw_cursor',         'Mach32',      '.*' ],
	    [ 'dac_8_bit',         'Mach32',      '.*' ],
	    [ 'ast_mach32',        'Mach32',      '.*' ],
	    [ 'intel_gx',          'Mach32',      '.*' ],
	    [ 'no_linear',         'Mach32',      '.*' ],
	    [ 'sw_cursor',         'Mach64',      '.*' ],
	    [ 'nolinear',          'Mach64',      '.*' ],
	    [ 'no_block_write',    'Mach64',      '.*' ],
	    [ 'block_write',       'Mach64',      '.*' ],
	    [ 'fifo_conservative', 'Mach64',      '.*' ],
	    [ 'no_font_cache',     'Mach64',      '.*' ],
	    [ 'no_pixmap_cache',   'Mach64',      '.*' ],
	    [ 'composite',         'Mach64',      '.*' ],
	    [ 'power_saver',       'Mach64',      '.*' ],
	    [ 'no_program_clocks', 'Mach64',      '.*' ],
	    [ 'no_bios_clocks',    'Mach64',      '.*' ],
	    [ 'dac_6_bit',         'Mach64',      '.*' ],
	    [ 'dac_8_bit',         'Mach64',      '.*' ],
	    [ 'hw_cursor',         'Mach64',      '.*' ],
	    #- [ 'override_bios',     'Mach64',      '.*' ], #- WARNING, MAY DAMAGE CARD
	    [ 'sw_cursor',         'P9000',       '.*' ],
	    [ 'noaccel',           'P9000',       '.*' ],
	    [ 'sync_on_green',     'P9000',       '.*' ],
	    [ 'vram_128',          'P9000',       '.*' ],
	    [ 'nolinear',          'S3',          '.*' ],
	    [ 'dac_8_bit',         'S3',          '.*' ],
	    [ 'slow_vram',         'S3',          'S3.*964' ],
	    [ 'stb_pegasus',       'S3',          'S3.*928' ],
	    [ 'SPEA_Mercury',      'S3',          'S3.*(928|964)' ],
	    [ 'number_nine',       'S3',          'S3.*(864|928)' ],
	    [ 'lcd_center',        'S3',          'S3.*Aurora64V' ],
	    [ 'noaccel',           'S3V',         '.*' ],
	    [ 'slow_edodram',      'S3V',         '.*' ],
	    [ 'pci_burst_on',      'S3V',         '.*' ],
	    [ 'early_ras_precharge', 'S3V',       '.*' ],
	    [ 'late_ras_precharge', 'S3V',        '.*' ],
	    [ 'fifo_conservative', 'S3V',         '.*' ],
	    [ 'fifo_aggressive',   'S3V',         '.*' ],
	    [ 'fifo_moderate',     'S3V',         '.*' ],
	    [ 'lcd_center',        'S3V',         'S3.*ViRGE\/MX' ],
	    [ 'hw_cursor',         'S3V',         '.*' ],
	    [ 'pci_retry',         'S3V',         '.*' ],
	    [ 'dac_6_bit',         'AGX',         '.*' ],
	    [ 'dac_8_bit',         'AGX',         '.*' ],
	    [ 'sync_on_green',     'AGX',         '.*' ],
	    [ '8_bit_bus',         'AGX',         '.*' ],
	    [ 'wait_state',        'AGX',         '.*' ],
	    [ 'no_wait_state',     'AGX',         '.*' ],
	    [ 'noaccel',           'AGX',         '.*' ],
	    [ 'crtc_delay',        'AGX',         '.*' ],
	    [ 'fifo_conserv',      'AGX',         '.*' ],
	    [ 'fifo_aggressive',   'AGX',         '.*' ],
	    [ 'fifo_moderate',     'AGX',         '.*' ],
	    [ 'vram_delay_latch',  'AGX',         '.*' ],
	    [ 'vram_delay_ras',    'AGX',         '.*' ],
	    [ 'vram_extend_ras',   'AGX',         '.*' ],
	    [ 'slow_dram',         'AGX',         '.*' ],
	    [ 'slow_vram',         'AGX',         '.*' ],
	    [ 'med_dram',          'AGX',         '.*' ],
	    [ 'med_vram',          'AGX',         '.*' ],
	    [ 'fast_dram',         'AGX',         '.*' ],
	    [ 'fast_vram',         'AGX',         '.*' ],
	    [ 'engine_delay',      'AGX',         '.*' ],
	    [ 'vram_128',          'AGX',         '.*' ],
	    [ 'vram_256',          'AGX',         '.*' ],
	    [ 'refresh_20',        'AGX',         '.*' ],
	    [ 'refresh_25',        'AGX',         '.*' ],
	    [ 'screen_refresh',    'AGX',         '.*' ],
	    [ 'vlb_a',             'AGX',         '.*' ],
	    [ 'vlb_b',             'AGX',         '.*' ],
	    [ 'slow_dram',         'W32',         '.*' ],
	    [ 'pci_burst_off',     'W32',         '.*' ],
	    [ 'w32_interleave_off', 'W32',        '.*' ],
	    [ 'no_accel',          'W32',         '.*' ],
	    [ 'nolinear',          '8514',        '.*' ],
	    [ 'sw_cursor',         '8514',        '.*' ],
	    [ 'no_block_write',    '8514',        '.*' ],
	    [ 'block_write',       '8514',        '.*' ],
	    [ 'fifo_conservative', '8514',        '.*' ],
	    [ 'no_font_cache',     '8514',        '.*' ],
	    [ 'no_pixmap_cache',   '8514',        '.*' ],
	    [ 'composite',         '8514',        '.*' ],
	    [ 'power_saver',       '8514',        '.*' ],
	    [ 'power_saver',       'FBDev',       '.*' ],
);

%xkb_options = (
    'ru(winkeys)' => [ 'XkbOptions "grp:caps_toggle"' ],
    'jp' => [ 'XkbModel "jp106"' ], 
);

$XF86firstchunk_text = q(
# File generated by XFdrake.

# **********************************************************************
# Refer to the XF86Config(4/5) man page for details about the format of
# this file.
# **********************************************************************

Section "Files"

    RgbPath	"/usr/X11R6/lib/X11/rgb"

# Multiple FontPath entries are allowed (they are concatenated together)
# By default, Mandrake 6.0 and later now use a font server independent of
# the X server to render fonts.

    FontPath   "unix/:-1"

EndSection

# **********************************************************************
# Server flags section.
# **********************************************************************

Section "ServerFlags"

    # Uncomment this to cause a core dump at the spot where a signal is
    # received.  This may leave the console in an unusable state, but may
    # provide a better stack trace in the core dump to aid in debugging
    #NoTrapSignals

    # Uncomment this to disable the <Crtl><Alt><BS> server abort sequence
    # This allows clients to receive this key event.
    #DontZap

    # Uncomment this to disable the <Crtl><Alt><KP_+>/<KP_-> mode switching
    # sequences.  This allows clients to receive these key events.
    #DontZoom

    # This  allows  the  server  to start up even if the
    # mouse device can't be opened/initialised.
    AllowMouseOpenFail

EndSection

# **********************************************************************
# Input devices
# **********************************************************************
);

$keyboardsection_start = '
# **********************************************************************
# Keyboard section
# **********************************************************************

Section "Keyboard"

    Protocol    "Standard"

    # when using XQUEUE, comment out the above line, and uncomment the
    # following line
    #Protocol   "Xqueue"

    AutoRepeat  250 30

    # Let the server do the NumLock processing.  This should only be
    # required when using pre-R6 clients
    #ServerNumLock

    # Specify which keyboard LEDs can be user-controlled (eg, with xset(1))
    #Xleds      "1 2 3"

    #To set the LeftAlt to Meta, RightAlt key to ModeShift,
    #RightCtl key to Compose, and ScrollLock key to ModeLock:

    LeftAlt        Meta
    RightAlt       Meta
    ScrollLock     Compose
    RightCtl       Control

# To disable the XKEYBOARD extension, uncomment XkbDisable.

#    XkbDisable
';

$keyboardsection_start_v4 = '
# **********************************************************************
# Keyboard section
# **********************************************************************

Section "InputDevice"

    Identifier "Keyboard1"
    Driver      "Keyboard"
    Option "AutoRepeat"  "250 30"
';

if (arch() =~ /^sparc/) {
    $keyboardsection_part3 = '
# To customise the XKB settings to suit your keyboard, modify the
# lines below (which are the defaults).  For example:
#    XkbModel    "type6"
# If you have a SUN keyboard, you may use:
#    XkbModel    "sun"
#
# Then to change the language, change the Layout setting.
# For example, a german layout can be obtained with:
#    XkbLayout   "de"
# or:
#    XkbLayout   "de"
#    XkbVariant  "nodeadkeys"
#
# If you\'d like to switch the positions of your capslock and
# control keys, use:
#    XkbOptions  "ctrl:swapcaps"

# These are the default XKB settings for XFree86 on SUN:
#    XkbRules    "sun"
#    XkbModel    "type5_unix"
#    XkbLayout   "us"
#    XkbCompat   "compat/complete"
#    XkbTypes    "types/complete"
#    XkbKeycodes "sun(type5)"
#    XkbGeometry "sun(type5)"
#    XkbSymbols  "sun/us(sun5)"

    XkbRules    "sun"
    XkbLayout   "us"
    XkbCompat   "compat/complete"
    XkbTypes    "types/complete"
    XkbKeycodes "sun(type5)"
    XkbGeometry "sun(type5)"
    XkbSymbols  "sun/us(sun5)"
';
$keyboardsection_part3_v4 = '
    Option "XkbRules"    "sun"
    Option "XkbLayout"   "us"
    Option "XkbCompat"   "compat/complete"
    Option "XkbTypes"    "types/complete"
    Option "XkbKeycodes" "sun(type5)"
    Option "XkbGeometry" "sun(type5)"
    Option "XkbSymbols"  "sun/us(sun5)"
';
} else {
$keyboardsection_part3 = '
# To customise the XKB settings to suit your keyboard, modify the
# lines below (which are the defaults).  For example, for a non-U.S.
# keyboard, you will probably want to use:
#    XkbModel    "pc102"
# If you have a US Microsoft Natural keyboard, you can use:
#    XkbModel    "microsoft"
#
# Then to change the language, change the Layout setting.
# For example, a german layout can be obtained with:
#    XkbLayout   "de"
# or:
#    XkbLayout   "de"
#    XkbVariant  "nodeadkeys"
#
# If you\'d like to switch the positions of your capslock and
# control keys, use:
#    XkbOptions  "ctrl:swapcaps"

# These are the default XKB settings for XFree86
#    XkbRules    "xfree86"
#    XkbModel    "pc101"
#    XkbLayout   "us"
#    XkbVariant  ""
#    XkbOptions  ""

    XkbKeycodes     "xfree86"
    XkbTypes        "default"
    XkbCompat       "default"
    XkbSymbols      "us(pc105)"
    XkbGeometry     "pc"
    XkbRules        "xfree86"
';

$keyboardsection_part3_v4 = '
    Option "XkbRules" "xfree86"
';
}

$keyboardsection_end = '
EndSection
';

$pointersection_text = '
# **********************************************************************
# Pointer section
# **********************************************************************

';

$monitorsection_text1 = '
# **********************************************************************
# Monitor section
# **********************************************************************

# Any number of monitor sections may be present

Section "Monitor"
';

$monitorsection_text2 = '
# HorizSync is in kHz unless units are specified.
# HorizSync may be a comma separated list of discrete values, or a
# comma separated list of ranges of values.
# NOTE: THE VALUES HERE ARE EXAMPLES ONLY.  REFER TO YOUR MONITOR\'S
# USER MANUAL FOR THE CORRECT NUMBERS.
';

$monitorsection_text3 = '
# VertRefresh is in Hz unless units are specified.
# VertRefresh may be a comma separated list of discrete values, or a
# comma separated list of ranges of values.
# NOTE: THE VALUES HERE ARE EXAMPLES ONLY.  REFER TO YOUR MONITOR\'S
# USER MANUAL FOR THE CORRECT NUMBERS.
';

$monitorsection_text4 = '
# Modes can be specified in two formats.  A compact one-line format, or
# a multi-line format.

# These two are equivalent

#    ModeLine "1024x768i" 45 1024 1048 1208 1264 768 776 784 817 Interlace

#    Mode "1024x768i"
#        DotClock	45
#        HTimings	1024 1048 1208 1264
#        VTimings	768 776 784 817
#        Flags		"Interlace"
#    EndMode
';

$modelines_text_Trident_TG_96xx = '
# This is a set of standard mode timings. Modes that are out of monitor spec
# are automatically deleted by the server (provided the HorizSync and
# VertRefresh lines are correct), so there\'s no immediate need to
# delete mode timings (unless particular mode timings don\'t work on your
# monitor). With these modes, the best standard mode that your monitor
# and video card can support for a given resolution is automatically
# used.

# These are special modelines for Trident Providia 9685. It is for VA Linux
# systems only.
# 640x480 @ 72 Hz, 36.5 kHz hsync
Modeline "640x480"     31.5   640  680  720  864   480  488  491  521
# 800x600 @ 72 Hz, 48.0 kHz hsync
Modeline "800x600"     50     800  856  976 1040   600  637  643  666 +hsync +vsync
# 1024x768 @ 60 Hz, 48.4 kHz hsync
#Modeline "1024x768"    65    1024 1032 1176 1344   768  771  777  806 -hsync -vsync
# 1024x768 @ 70 Hz, 56.5 kHz hsync
Modeline "1024x768"    75    1024 1048 1184 1328   768  771  777  806 -hsync -vsync
';
$modelines_text_ext = '
# This is a set of extended mode timings typically used for laptop,
# TV fullscreen mode or DVD fullscreen output.
# These are available along with standard mode timings.

# Sony Vaio C1(X,XS,VE,VN)?
# 1024x480 @ 85.6 Hz, 48 kHz hsync
ModeLine "1024x480"    65.00 1024 1032 1176 1344   480  488  494  563 -hsync -vsync

# 768x576 @ 79 Hz, 50 kHz hsync
ModeLine "768x576"     50.00  768  832  846 1000   576  590  595  630
# 768x576 @ 100 Hz, 61.6 kHz hsync
ModeLine "768x576"     63.07  768  800  960 1024   576  578  590  616

';
$modelines_text_apple = '
Section "Modes"
    Identifier "Mac Modes"    
    # Apple iMac modes
    Modeline "1024x768"   78.525 1024 1049 1145 1312   768  769  772  800 +hsync +vsync
    Modeline "800x600"    62.357  800  821  901 1040   600  601  604  632 +hsync +vsync
    Modeline "640x480"    49.886  640  661  725  832   480  481  484  514 +hsync +vsync
    # Apple monitors tend to do 832x624
    Modeline "832x624"    57      832  876  940 1152   624  625  628  667 -hsync -vsync
    # Apple PowerBook G3
    Modeline "800x600"    100     800  816  824  840   600  616  624  640 -hsync -vsync
    # Apple TI Powerbook 
    Modeline "1152x768"   78.741 1152 1173 1269 1440   768  769  772  800 +vsync +vsync
    # Pismo Firewire G3   
    Modeline "1024x768"   65     1024 1032 1176 1344   768  771  777  806 -hsync -vsync
    # iBook2
    Modeline "1024x768"   65     1024 1048 1184 1344   768  771  777  806 -hsync -vsync
    # 17" Apple Studio Display
    Modeline "1024x768"   112.62 1024 1076 1248 1420 768 768 780 808 +hsync +vsync
    # HiRes Apple Studio Display
    Modeline "1280x1024"  135    1280 1288 1392 1664  1024 1027 1030 1064
    # Another variation
    Modeline "1280x1024"  134.989 1280 1317 1429 1688  1024 1025 1028 1066 +hsync +vsync
EndSection
';
$modelines_text = '
# This is a set of standard mode timings. Modes that are out of monitor spec
# are automatically deleted by the server (provided the HorizSync and
# VertRefresh lines are correct), so there\'s no immediate need to
# delete mode timings (unless particular mode timings don\'t work on your
# monitor). With these modes, the best standard mode that your monitor
# and video card can support for a given resolution is automatically
# used.

# 640x400 @ 70 Hz, 31.5 kHz hsync
Modeline "640x400"     25.175 640  664  760  800   400  409  411  450
# 640x480 @ 60 Hz, 31.5 kHz hsync
Modeline "640x480"     25.175 640  664  760  800   480  491  493  525
# 800x600 @ 56 Hz, 35.15 kHz hsync
ModeLine "800x600"     36     800  824  896 1024   600  601  603  625
# 1024x768 @ 87 Hz interlaced, 35.5 kHz hsync
Modeline "1024x768"    44.9  1024 1048 1208 1264   768  776  784  817 Interlace

# 640x400 @ 85 Hz, 37.86 kHz hsync
Modeline "640x400"     31.5   640  672 736   832   400  401  404  445 -HSync +VSync
# 640x480 @ 72 Hz, 36.5 kHz hsync
Modeline "640x480"     31.5   640  680  720  864   480  488  491  521
# 640x480 @ 75 Hz, 37.50 kHz hsync
ModeLine  "640x480"    31.5   640  656  720  840   480  481  484  500 -HSync -VSync
# 800x600 @ 60 Hz, 37.8 kHz hsync
Modeline "800x600"     40     800  840  968 1056   600  601  605  628 +hsync +vsync

# 640x480 @ 85 Hz, 43.27 kHz hsync
Modeline "640x480"     36     640  696  752  832   480  481  484  509 -HSync -VSync
# 1152x864 @ 89 Hz interlaced, 44 kHz hsync
ModeLine "1152x864"    65    1152 1168 1384 1480   864  865  875  985 Interlace

# 800x600 @ 72 Hz, 48.0 kHz hsync
Modeline "800x600"     50     800  856  976 1040   600  637  643  666 +hsync +vsync
# 1024x768 @ 60 Hz, 48.4 kHz hsync
Modeline "1024x768"    65    1024 1032 1176 1344   768  771  777  806 -hsync -vsync

# 640x480 @ 100 Hz, 53.01 kHz hsync
Modeline "640x480"     45.8   640  672  768  864   480  488  494  530 -HSync -VSync
# 1152x864 @ 60 Hz, 53.5 kHz hsync
Modeline  "1152x864"   89.9  1152 1216 1472 1680   864  868  876  892 -HSync -VSync
# 800x600 @ 85 Hz, 55.84 kHz hsync
Modeline  "800x600"    60.75  800  864  928 1088   600  616  621  657 -HSync -VSync

# 1024x768 @ 70 Hz, 56.5 kHz hsync
Modeline "1024x768"    75    1024 1048 1184 1328   768  771  777  806 -hsync -vsync
# 1280x1024 @ 87 Hz interlaced, 51 kHz hsync
Modeline "1280x1024"   80    1280 1296 1512 1568  1024 1025 1037 1165 Interlace

# 800x600 @ 100 Hz, 64.02 kHz hsync
Modeline  "800x600"    69.65  800  864  928 1088   600  604  610  640 -HSync -VSync
# 1024x768 @ 76 Hz, 62.5 kHz hsync
Modeline "1024x768"    85    1024 1032 1152 1360   768  784  787  823
# 1152x864 @ 70 Hz, 62.4 kHz hsync
Modeline  "1152x864"   92    1152 1208 1368 1474   864  865  875  895
# 1280x1024 @ 61 Hz, 64.2 kHz hsync
Modeline "1280x1024"  110    1280 1328 1512 1712  1024 1025 1028 1054
# 1400x1050 @ 60 Hz, 65.5 kHz
ModeLine "1400x1050" 122.0 1400 1488 1640 1880   1050 1052 1064 1082 +HSync +VSync

# 1024x768 @ 85 Hz, 70.24 kHz hsync
Modeline "1024x768"   98.9  1024 1056 1216 1408   768 782 788 822 -HSync -VSync
# 1152x864 @ 78 Hz, 70.8 kHz hsync
Modeline "1152x864"   110   1152 1240 1324 1552   864  864  876  908

# 1280x1024 @ 70 Hz, 74.59 kHz hsync
Modeline "1280x1024"  126.5 1280 1312 1472 1696  1024 1032 1040 1068 -HSync -VSync
# 1600x1200 @ 60Hz, 75.00 kHz hsync
Modeline "1600x1200"  162   1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
# 1152x864 @ 84 Hz, 76.0 kHz hsync
Modeline "1152x864"   135    1152 1464 1592 1776   864  864  876  908

# 1280x1024 @ 74 Hz, 78.85 kHz hsync
Modeline "1280x1024"  135    1280 1312 1456 1712  1024 1027 1030 1064

# 1024x768 @ 100Hz, 80.21 kHz hsync
Modeline "1024x768"   115.5  1024 1056 1248 1440  768  771  781  802 -HSync -VSync
# 1280x1024 @ 76 Hz, 81.13 kHz hsync
Modeline "1280x1024"  135    1280 1312 1416 1664  1024 1027 1030 1064
# 1400x1050 @ 75 Hz, 82.2 kHz hsync
ModeLine "1400x1050" 155.8   1400 1464 1784 1912  1050 1052 1064 1090 +HSync +VSync

# 1600x1200 @ 70 Hz, 87.50 kHz hsync
Modeline "1600x1200"  189    1600 1664 1856 2160  1200 1201 1204 1250 -HSync -VSync
# 1152x864 @ 100 Hz, 89.62 kHz hsync
Modeline "1152x864"   137.65 1152 1184 1312 1536   864  866  885  902 -HSync -VSync
# 1280x1024 @ 85 Hz, 91.15 kHz hsync
Modeline "1280x1024"  157.5  1280 1344 1504 1728  1024 1025 1028 1072 +HSync +VSync
# 1600x1200 @ 75 Hz, 93.75 kHz hsync
Modeline "1600x1200"  202.5  1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
# 1600x1200 @ 85 Hz, 105.77 kHz hsync
Modeline "1600x1200"  220    1600 1616 1808 2080  1200 1204 1207 1244 +HSync +VSync
# 1600x1200 @ 85 Hz, 106.3 kHz hsync
ModeLine "1600x1200" 229.5   1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
# 1280x1024 @ 100 Hz, 107.16 kHz hsync
Modeline "1280x1024"  181.75 1280 1312 1440 1696  1024 1031 1046 1072 -HSync -VSync

# 1800x1440 @ 64Hz, 96.15 kHz hsync
ModeLine "1800X1440"  230    1800 1896 2088 2392 1440 1441 1444 1490 +HSync +VSync
# 1800x1440 @ 70Hz, 104.52 kHz hsync
ModeLine "1800X1440"  250    1800 1896 2088 2392 1440 1441 1444 1490 +HSync +VSync

# 1920x1440 @ 60 Hz, 90.0 kHz hsync
ModeLine "1920x1440"  234.0  1920 2048 2256 2600 1440 1441 1444 1500 -HSync +VSync
# 1920x1440 @ 75 Hz, 112.5kHz hsync
ModeLine "1920x1440"  297.0  1920 2064 2288 2640 1440 1441 1444 1500 -HSync +VSync

# 512x384 @ 78 Hz, 31.50 kHz hsync
Modeline "512x384"    20.160 512  528  592  640   384  385  388  404 -HSync -VSync
# 512x384 @ 85 Hz, 34.38 kHz hsync
Modeline "512x384"    22     512  528  592  640   384  385  388  404 -HSync -VSync


# Low-res Doublescan modes
# If your chipset does not support doublescan, you get a \'squashed\'
# resolution like 320x400.

# 320x200 @ 70 Hz, 31.5 kHz hsync, 8:5 aspect ratio
Modeline "320x200"     12.588 320  336  384  400   200  204  205  225 Doublescan
# 320x240 @ 60 Hz, 31.5 kHz hsync, 4:3 aspect ratio
Modeline "320x240"     12.588 320  336  384  400   240  245  246  262 Doublescan
# 320x240 @ 72 Hz, 36.5 kHz hsync
Modeline "320x240"     15.750 320  336  384  400   240  244  246  262 Doublescan
# 400x300 @ 56 Hz, 35.2 kHz hsync, 4:3 aspect ratio
ModeLine "400x300"     18     400  416  448  512   300  301  302  312 Doublescan
# 400x300 @ 60 Hz, 37.8 kHz hsync
Modeline "400x300"     20     400  416  480  528   300  301  303  314 Doublescan
# 400x300 @ 72 Hz, 48.0 kHz hsync
Modeline "400x300"     25     400  424  488  520   300  319  322  333 Doublescan
# 480x300 @ 56 Hz, 35.2 kHz hsync, 8:5 aspect ratio
ModeLine "480x300"     21.656 480  496  536  616   300  301  302  312 Doublescan
# 480x300 @ 60 Hz, 37.8 kHz hsync
Modeline "480x300"     23.890 480  496  576  632   300  301  303  314 Doublescan
# 480x300 @ 63 Hz, 39.6 kHz hsync
Modeline "480x300"     25     480  496  576  632   300  301  303  314 Doublescan
# 480x300 @ 72 Hz, 48.0 kHz hsync
Modeline "480x300"     29.952 480  504  584  624   300  319  322  333 Doublescan

';

$devicesection_text = '
# **********************************************************************
# Graphics device section
# **********************************************************************

Section "Device"
    Identifier "Generic VGA"
    Chipset   "generic"
EndSection

';

$devicesection_text_v4 = '
# **********************************************************************
# Graphics device section
# **********************************************************************

Section "Device"
    Identifier "Generic VGA"
    Driver     "vga"
EndSection

';

$screensection_text1 = '
# **********************************************************************
# Screen sections
# **********************************************************************
';

