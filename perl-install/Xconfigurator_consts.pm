package Xconfigurator_consts; # $Id$

use common;

%depths = (
      8 => __("256 colors (8 bits)"),
     15 => __("32 thousand colors (15 bits)"),
     16 => __("65 thousand colors (16 bits)"),
     24 => __("16 million colors (24 bits)"),
     32 => __("4 billion colors (32 bits)"),
);
@depths = ikeys(%depths);

@resolutions = ('640x480', '800x600', '1024x768', (arch() =~ /ppc/ ? '1152x864' : '1152x768'), '1280x1024', '1400x1050', '1600x1200', '1920x1440', '2048x1536');

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
    'VGA16'     => "vga16",
    'FBDev'     => "fbdev",
);
@allbutfbservers = grep { arch() =~ /^sparc/ || $serversdriver{$_} ne "fbdev" } keys(%serversdriver);
@allservers = keys(%serversdriver);

@allbutfbdrivers = ((arch() =~ /^sparc/ ? qw(sunbw2 suncg14 suncg3 suncg6 sunffb sunleo suntcx) :
		    qw(apm ark chips cirrus cyrix glide i128 i740 i810 imstt mga neomagic newport nv rendition
                       s3 s3virge savage siliconmotion sis tdfx tga trident tseng vmware)), qw(ati glint vga));
@alldrivers = (@allbutfbdrivers, 'fbdev', 'vesa');

%bios_vga_modes = (
    769 => [  640,  480,  8 ],
    771 => [  800,  600,  8 ],
    773 => [ 1024,  768,  8 ],
    775 => [ 1280, 1024,  8 ],
    784 => [  640,  480, 15 ],
    787 => [  800,  600, 15 ],
    790 => [ 1024,  768, 15 ],
    793 => [ 1280, 1024, 15 ],
    785 => [  640,  480, 16 ],
    788 => [  800,  600, 16 ],
    791 => [ 1024,  768, 16 ],
    794 => [ 1280, 1024, 16 ],
);
sub bios_vga_modes {
    my ($xres, $depth) = @_;
    foreach (keys %bios_vga_modes) {
	my $l = $bios_vga_modes{$_};
	return ($_, @$l) if $xres == $l->[0] && $depth == $l->[2];
    }
    ();
}

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

%VideoRams = (
     256 => __("256 kB"),
     512 => __("512 kB"),
    1024 => __("1 MB"),
    2048 => __("2 MB"),
    4096 => __("4 MB"),
    8192 => __("8 MB"),
   16384 => __("16 MB"),
   32768 => __("32 MB"),
   65536 => __("64 MB or more"),
);

$good_default_monitor = arch() !~ /ppc/ ? "High Frequency SVGA, 1024x768 at 70 Hz" : 
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

%min_hsync4x_res = (
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


#- most usefull XFree86-4.0.1 server options. Default values is the first ones.
@options_serverflags = (
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
);

%XkbOptions = (
    'ru(winkeys)' => [ 'XkbOptions "grp:caps_toggle"' ],
);

$XF86firstchunk_text = q(
# File generated by XFdrake.

# **********************************************************************
# Refer to the XF86Config man page for details about the format of
# this file.
# **********************************************************************

Section "Files"
    # Multiple FontPath entries are allowed (they are concatenated together)
    # By default, Mandrake 6.0 and later now use a font server independent of
    # the X server to render fonts.
    FontPath   "unix/:-1"

EndSection


Section "ServerFlags"

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

);

$ModeLines_text_ext = 
  arch() =~ /ppc/ ? '
    # Apple iMac modes
    ModeLine "1024x768"   78.525 1024 1049 1145 1312   768  769  772  800 +hsync +vsync
    ModeLine "800x600"    62.357  800  821  901 1040   600  601  604  632 +hsync +vsync
    ModeLine "640x480"    49.886  640  661  725  832   480  481  484  514 +hsync +vsync
    # Apple monitors tend to do 832x624
    ModeLine "832x624"    57      832  876  940 1152   624  625  628  667 -hsync -vsync
    # Apple PowerBook G3
    ModeLine "800x600"    100     800  816  824  840   600  616  624  640 -hsync -vsync
    # Apple TI Powerbook 
    ModeLine "1152x768"   78.741 1152 1173 1269 1440   768  769  772  800 +vsync +vsync
    # Pismo Firewire G3   
    ModeLine "1024x768"   65     1024 1032 1176 1344   768  771  777  806 -hsync -vsync
    # iBook2
    ModeLine "1024x768"   65     1024 1048 1184 1344   768  771  777  806 -hsync -vsync
    # 17" Apple Studio Display
    ModeLine "1024x768"   112.62 1024 1076 1248 1420 768 768 780 808 +hsync +vsync
    # HiRes Apple Studio Display
    ModeLine "1280x1024"  135    1280 1288 1392 1664  1024 1027 1030 1064
    # Another variation
    ModeLine "1280x1024"  134.989 1280 1317 1429 1688  1024 1025 1028 1066 +hsync +vsync
' : '
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

$ModeLines_text_standard = '
    # This is a set of standard mode timings. Modes that are out of monitor spec
    # are automatically deleted by the server (provided the HorizSync and
    # VertRefresh lines are correct), so there\'s no immediate need to
    # delete mode timings (unless particular mode timings don\'t work on your
    # monitor). With these modes, the best standard mode that your monitor
    # and video card can support for a given resolution is automatically
    # used.
    
    # 640x400 @ 70 Hz, 31.5 kHz hsync
    ModeLine "640x400"     25.175 640  664  760  800   400  409  411  450
    # 640x480 @ 60 Hz, 31.5 kHz hsync
    ModeLine "640x480"     25.175 640  664  760  800   480  491  493  525
    # 800x600 @ 56 Hz, 35.15 kHz hsync
    ModeLine "800x600"     36     800  824  896 1024   600  601  603  625
    # 1024x768 @ 87 Hz interlaced, 35.5 kHz hsync
    ModeLine "1024x768"    44.9  1024 1048 1208 1264   768  776  784  817 Interlace
    
    # 640x400 @ 85 Hz, 37.86 kHz hsync
    ModeLine "640x400"     31.5   640  672 736   832   400  401  404  445 -HSync +VSync
    # 640x480 @ 75 Hz, 37.50 kHz hsync
    ModeLine  "640x480"    31.5   640  656  720  840   480  481  484  500 -HSync -VSync
    # 800x600 @ 60 Hz, 37.8 kHz hsync
    ModeLine "800x600"     40     800  840  968 1056   600  601  605  628 +hsync +vsync
    
    # 640x480 @ 85 Hz, 43.27 kHz hsync
    ModeLine "640x480"     36     640  696  752  832   480  481  484  509 -HSync -VSync
    # 1152x864 @ 89 Hz interlaced, 44 kHz hsync
    ModeLine "1152x864"    65    1152 1168 1384 1480   864  865  875  985 Interlace
    
    # 800x600 @ 72 Hz, 48.0 kHz hsync
    ModeLine "800x600"     50     800  856  976 1040   600  637  643  666 +hsync +vsync
    # 1024x768 @ 60 Hz, 48.4 kHz hsync
    ModeLine "1024x768"    65    1024 1032 1176 1344   768  771  777  806 -hsync -vsync
    
    # 640x480 @ 100 Hz, 53.01 kHz hsync
    ModeLine "640x480"     45.8   640  672  768  864   480  488  494  530 -HSync -VSync
    # 1152x864 @ 60 Hz, 53.5 kHz hsync
    ModeLine  "1152x864"   89.9  1152 1216 1472 1680   864  868  876  892 -HSync -VSync
    # 800x600 @ 85 Hz, 55.84 kHz hsync
    ModeLine  "800x600"    60.75  800  864  928 1088   600  616  621  657 -HSync -VSync
    
    # 1024x768 @ 70 Hz, 56.5 kHz hsync
    ModeLine "1024x768"    75    1024 1048 1184 1328   768  771  777  806 -hsync -vsync
    # 1280x1024 @ 87 Hz interlaced, 51 kHz hsync
    ModeLine "1280x1024"   80    1280 1296 1512 1568  1024 1025 1037 1165 Interlace
    
    # 800x600 @ 100 Hz, 64.02 kHz hsync
    ModeLine  "800x600"    69.65  800  864  928 1088   600  604  610  640 -HSync -VSync
    # 1024x768 @ 76 Hz, 62.5 kHz hsync
    ModeLine "1024x768"    85    1024 1032 1152 1360   768  784  787  823
    # 1152x864 @ 70 Hz, 62.4 kHz hsync
    ModeLine  "1152x864"   92    1152 1208 1368 1474   864  865  875  895
    # 1280x1024 @ 61 Hz, 64.2 kHz hsync
    ModeLine "1280x1024"  110    1280 1328 1512 1712  1024 1025 1028 1054
    # 1400x1050 @ 60 Hz, 65.5 kHz
    ModeLine "1400x1050" 122.0 1400 1488 1640 1880   1050 1052 1064 1082 +HSync +VSync
    
    # 1024x768 @ 85 Hz, 70.24 kHz hsync
    ModeLine "1024x768"   98.9  1024 1056 1216 1408   768 782 788 822 -HSync -VSync
    # 1152x864 @ 78 Hz, 70.8 kHz hsync
    ModeLine "1152x864"   110   1152 1240 1324 1552   864  864  876  908
    
    # 1280x1024 @ 70 Hz, 74.59 kHz hsync
    ModeLine "1280x1024"  126.5 1280 1312 1472 1696  1024 1032 1040 1068 -HSync -VSync
    # 1600x1200 @ 60Hz, 75.00 kHz hsync
    ModeLine "1600x1200"  162   1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
    # 1152x864 @ 84 Hz, 76.0 kHz hsync
    ModeLine "1152x864"   135    1152 1464 1592 1776   864  864  876  908
    
    # 1280x1024 @ 75 Hz, 79.98 kHz hsync
    ModeLine "1280x1024"  135    1280 1296 1440 1688 1024 1025 1028 1066 +HSync +VSync
    
    # 1024x768 @ 100Hz, 80.21 kHz hsync
    ModeLine "1024x768"   115.5  1024 1056 1248 1440  768  771  781  802 -HSync -VSync
    # 1400x1050 @ 75 Hz, 82.2 kHz hsync
    ModeLine "1400x1050" 155.8   1400 1464 1784 1912  1050 1052 1064 1090 +HSync +VSync
    
    # 1600x1200 @ 70 Hz, 87.50 kHz hsync
    ModeLine "1600x1200"  189    1600 1664 1856 2160  1200 1201 1204 1250 -HSync -VSync
    # 1152x864 @ 100 Hz, 89.62 kHz hsync
    ModeLine "1152x864"   137.65 1152 1184 1312 1536   864  866  885  902 -HSync -VSync
    # 1280x1024 @ 85 Hz, 91.15 kHz hsync
    ModeLine "1280x1024"  157.5  1280 1344 1504 1728  1024 1025 1028 1072 +HSync +VSync
    # 1600x1200 @ 75 Hz, 93.75 kHz hsync
    ModeLine "1600x1200"  202.5  1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
    # 1600x1200 @ 85 Hz, 105.77 kHz hsync
    ModeLine "1600x1200"  220    1600 1616 1808 2080  1200 1204 1207 1244 +HSync +VSync
    # 1600x1200 @ 85 Hz, 106.3 kHz hsync
    ModeLine "1600x1200" 229.5   1600 1664 1856 2160  1200 1201 1204 1250 +HSync +VSync
    # 1280x1024 @ 100 Hz, 107.16 kHz hsync
    ModeLine "1280x1024"  181.75 1280 1312 1440 1696  1024 1031 1046 1072 -HSync -VSync
    
    # 1800x1440 @ 64Hz, 96.15 kHz hsync
    ModeLine "1800X1440"  230    1800 1896 2088 2392 1440 1441 1444 1490 +HSync +VSync
    # 1800x1440 @ 70Hz, 104.52 kHz hsync
    ModeLine "1800X1440"  250    1800 1896 2088 2392 1440 1441 1444 1490 +HSync +VSync
    
    # 1920x1440 @ 60 Hz, 90.0 kHz hsync
    ModeLine "1920x1440"  234.0  1920 2048 2256 2600 1440 1441 1444 1500 -HSync +VSync
    # 1920x1440 @ 75 Hz, 112.5kHz hsync
    ModeLine "1920x1440"  297.0  1920 2064 2288 2640 1440 1441 1444 1500 -HSync +VSync
    
    # 512x384 @ 78 Hz, 31.50 kHz hsync
    ModeLine "512x384"    20.160 512  528  592  640   384  385  388  404 -HSync -VSync
    # 512x384 @ 85 Hz, 34.38 kHz hsync
    ModeLine "512x384"    22     512  528  592  640   384  385  388  404 -HSync -VSync
    
    
    # Low-res Doublescan modes
    # If your chipset does not support doublescan, you get a \'squashed\'
    # resolution like 320x400.
    
    # 320x200 @ 70 Hz, 31.5 kHz hsync, 8:5 aspect ratio
    ModeLine "320x200"     12.588 320  336  384  400   200  204  205  225 Doublescan
    # 320x240 @ 60 Hz, 31.5 kHz hsync, 4:3 aspect ratio
    ModeLine "320x240"     12.588 320  336  384  400   240  245  246  262 Doublescan
    # 320x240 @ 72 Hz, 36.5 kHz hsync
    ModeLine "320x240"     15.750 320  336  384  400   240  244  246  262 Doublescan
    # 400x300 @ 56 Hz, 35.2 kHz hsync, 4:3 aspect ratio
    ModeLine "400x300"     18     400  416  448  512   300  301  302  312 Doublescan
    # 400x300 @ 60 Hz, 37.8 kHz hsync
    ModeLine "400x300"     20     400  416  480  528   300  301  303  314 Doublescan
    # 400x300 @ 72 Hz, 48.0 kHz hsync
    ModeLine "400x300"     25     400  424  488  520   300  319  322  333 Doublescan
    # 480x300 @ 56 Hz, 35.2 kHz hsync, 8:5 aspect ratio
    ModeLine "480x300"     21.656 480  496  536  616   300  301  302  312 Doublescan
    # 480x300 @ 60 Hz, 37.8 kHz hsync
    ModeLine "480x300"     23.890 480  496  576  632   300  301  303  314 Doublescan
    # 480x300 @ 63 Hz, 39.6 kHz hsync
    ModeLine "480x300"     25     480  496  576  632   300  301  303  314 Doublescan
    # 480x300 @ 72 Hz, 48.0 kHz hsync
    ModeLine "480x300"     29.952 480  504  584  624   300  319  322  333 Doublescan

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
