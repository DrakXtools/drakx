package Xconfig::xfree3; # $Id$

use diagnostics;
use strict;

use common;
use Xconfig::parse;
use Xconfig::xfreeX;

our @ISA = 'Xconfig::xfreeX';

sub name { 'xfree3' }
sub config_file { '/etc/X11/XF86Config' }


sub get_keyboard_section {
    my ($raw_X) = @_;
    return $raw_X->get_Section('Keyboard') or die "no keyboard section";
}
sub new_keyboard_section {
    my ($raw_X) = @_;
    return $raw_X->add_Section('Keyboard', { Protocol => { val => 'Standard' } });
}

sub get_mouse_sections {
    my ($raw_X) = @_;
    my $main = $raw_X->get_Section('Pointer') or die "no mouse section";
    my $XInput = $raw_X->get_Section('XInput');    
    $main, if_($XInput, map { $_->{l} } @{$XInput->{Mouse} || []}); 
}

sub new_mouse_sections {
    my ($raw_X, $nb_new) = @_;

    $raw_X->remove_Section('Pointer');
    my $XInput = $raw_X->get_Section('XInput');
    delete $XInput->{Mouse} if $XInput;
    $raw_X->remove_Section('XInput') if $nb_new <= 1 && $XInput && !%$XInput;

    $nb_new or return;

    my $main = $raw_X->add_Section('Pointer', {});
    
    if ($nb_new == 1) {
	$main;
    } else {
	my @l = map { { AlwaysCore => {} } } (2 .. $nb_new);
	$XInput ||= $raw_X->add_Section('XInput', {});
	$XInput->{Mouse} = [ map { { l => $_ } } @l ];
	$main, @l;
    }
}

sub set_wacoms {
    my ($raw_X, @wacoms) = @_;

    my %Modes = (Stylus => 'Absolute', Erasor => 'Absolute', Cursor => 'Relative');

    my $XInput = $raw_X->get_Section('XInput');
    if ($XInput) {
	delete $XInput->{"Wacom$_"} foreach keys %Modes;
	$raw_X->remove_Section('XInput') if !@wacoms && $XInput && !%$XInput;
    }
    #- only wacom is handled in XFree 3
    my ($wacom) = @wacoms or return;

    $XInput ||= $raw_X->add_Section('XInput', {});
    foreach (keys %Modes) {
	$XInput->{"Wacom$_"} = [ { l => { Port => { val => qq("$wacom->{Device}") }, 
					  Mode => { val => $Modes{$_} },
					  if_($wacom->{USB}, USB => {}),
					  AlwaysCore => {} } } ];
    }
}

sub depths { 8, 15, 16, 24, 32 }
sub set_resolution {
    my ($raw_X, $resolution, $Screen) = @_;
    $Screen ||= $raw_X->get_default_screen or return {};

    $resolution = +{ %$resolution };

    #- use framebuffer if Screen is
    $resolution->{fbdev} = 1 if val($Screen->{Driver}) eq 'fbdev';

    $raw_X->SUPER::set_resolution($resolution, $Screen);
}

sub get_device_section_fields {
    qw(VendorName BoardName Chipset VideoRam); #-);
}

sub default_ModeLine {
    my ($raw_X) = @_;
    $raw_X->SUPER::default_ModeLine . our $default_ModeLine;
}

sub new_device_sections {
    my ($raw_X, $nb_new) = @_;
    my @l = $raw_X->SUPER::new_device_sections($nb_new);
    $_->{power_saver} = { Option => 1 } foreach @l;
    @l;
}

sub set_Option {}


sub val {
    my ($ref) = @_;
    $ref && $ref->{val};
}

our $default_ModeLine = <<'END';
    # This is a set of standard mode timings. Modes that are out of monitor spec
    # are automatically deleted by the server (provided the HorizSync and
    # VertRefresh lines are correct), so there's no immediate need to
    # delete mode timings (unless particular mode timings don't work on your
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
    # If your chipset does not support doublescan, you get a 'squashed'
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
END

1;
