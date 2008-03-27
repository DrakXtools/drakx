package bootsplash;

use common;
use Xconfig::resolution_and_depth;


my $themes_dir = "/usr/share/bootsplash/themes";
my $themes_config_dir = "/etc/bootsplash/themes";
my $sysconfig_file = "/etc/sysconfig/bootsplash";
my $bootsplash_scripts = "/usr/share/bootsplash/scripts";
my $default_theme = 'Mandrivalinux';
our $default_thumbnail = '/usr/share/libDrakX/pixmaps/nosplash_thumb.png';
our @resolutions = uniq(map { "$_->{X}x$_->{Y}" } Xconfig::resolution_and_depth::bios_vga_modes());

sub get_framebuffer_resolution() {
    require bootloader;
    require fsedit;
    my $all_hds = fsedit::get_hds();
    fs::get_info_from_fstab($all_hds);
    my $bootloader = bootloader::read($all_hds);
    my $x_res = Xconfig::resolution_and_depth::from_bios($bootloader->{default_options}{vga});
    $x_res ?
      ($x_res->{X} . 'x' . $x_res->{Y}, 1) :
      (first(@resolutions), 0);
}

sub themes_read_sysconfig {
    my ($res) = @_;
    my %theme = (
                 name => $default_theme,
                 enabled => 1,
                 keep_logo => 1
                );
    if (-r $::prefix . $sysconfig_file) {
        local $_;
        foreach (cat_($::prefix . $sysconfig_file)) {
            /^SPLASH=no/ and $theme{enabled} = 0;
            /^THEME=(.*)/ && -f theme_get_image_for_resolution($1, $res) and $theme{name} = $1;
            /^LOGO_CONSOLE=(.*)/ and $theme{keep_logo} = $1 ne "no";
        }
    }
    \%theme;
}

sub theme_get_image_for_resolution {
    my ($theme, $res) = @_;
    $::prefix . $themes_dir . '/' . $theme . '/images/bootsplash-' . $res . ".jpg";
}

sub theme_get_config_for_resolution {
    my ($theme, $res) = @_;
    $::prefix . $themes_config_dir . '/' . $theme . '/config/bootsplash-' . $res . ".cfg";
}

sub theme_exists_for_resolution {
    my ($theme, $res) = @_;
    -f theme_get_image_for_resolution($theme, $res) && -f theme_get_config_for_resolution($theme, $res);
}

sub themes_list() {
    grep { !/^\./ && -d $::prefix . $themes_dir . '/' . $_ } sort(all($::prefix . $themes_dir));
}

sub themes_list_for_resolution {
    my ($res) = @_;
    grep { theme_exists_for_resolution($_, $res) } themes_list();
}

sub switch {
    my ($theme) = @_;
    if ($::testing) {
        print "enabling bootsplash theme $theme\n";
    } else {
        #- theme scripts will update SPLASH value in sysconfig file
        system($::prefix . $bootsplash_scripts . '/switch-themes', $theme);
    }
}

sub remove() {
    if ($::testing) {
        print "disabling bootsplash theme\n";
    } else {
        system($::prefix . $bootsplash_scripts . '/remove-theme');
    }
}

sub set_logo_console {
    my ($keep_logo) = @_;
    my $logo_console = $keep_logo ? 'theme' : 'no';
    substInFile { s/^LOGO_CONSOLE=.*/LOGO_CONSOLE=$logo_console/ } $::prefix . $sysconfig_file;
}

sub create_path {
    my ($file) = @_;
    mkdir_p(dirname($file));
}

sub theme_set_image_for_resolution {
    my ($name, $res, $source_image) = @_;
    my $dest_image = theme_get_image_for_resolution($name, $res);
    create_path($dest_image);
    #- Append an exclamation point to the geometry to force the image size to exactly the size you specify.
    system('convert', '-geometry', $res . '!', $source_image, $dest_image);
    system($::prefix . $bootsplash_scripts . '/rewritejpeg',  $dest_image);
}

sub theme_read_config_for_resolution {
    my ($theme, $res) = @_;
    my $file = theme_get_config_for_resolution($theme, $res);
    my $contents = cat_($file);
    my ($pb_x1, $pb_y1, $pb_x2, $pb_y2, $pbg_c, $ptransp) = $contents =~ /^box\s+silent\s+noover\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(#\w{6})(\w{2})/m;
    my ($tb_x1, $tb_y1, $tb_x2, $tb_y2, $tc, $transp) = $contents =~ /^box\s+noover\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(#\w{6})(\w{2})/m;
    my ($pc1, $pc2, $pc3, $_pc4) = $contents =~ /^box\s+silent\s+inter\s+\d+\s+\d+\s+\d+\s+\d+\s+(#\w+)\s+(#\w+)\s+(#\w+)\s+(#\w+)/m;
    my ($text_color) = $contents =~ /^text_color=0x(\w+)/m;
    my $gradient;
    if ($pc1 eq $pc2) {
	$gradient = 'vertical';
	$pc2 = $pc3;
    }
    { pc1 => $pc1, pc2 => $pc2, gradient => $gradient,  transp => hex $transp, ptransp => hex $ptransp, 
      tb_x => $tb_x1, tb_y => $tb_y1, tb_w => $tb_x2 - $tb_x1, tb_h => $tb_y2 - $tb_y1, tc => $tc, pbg_c => $pbg_c, 
      px => $pb_x1, pw => $pb_x2 - $pb_x1, py => $pb_y1, ph => $pb_y2 - $pb_y1, 
      getVarsFromSh($file), text_color => "#$text_color" };
}

sub theme_write_config_for_resolution {
    my ($name, $res, $conf) = @_;

    my $config = theme_get_config_for_resolution($name, $res);
    create_path($config);
    my $jpeg = theme_get_image_for_resolution($name, $res);

    # progress/text rectangles border/inter coordinates
    my ($pb_x1, $pb_x2, $pb_y1, $pb_y2) = ($conf->{px}, $conf->{px} + $conf->{pw}, $conf->{py}, $conf->{py} + $conf->{ph});
    my ($pi_y1, $pi_y2) = ($pb_y1 + 1, $pb_y2 - 1);
    my ($tb_x1, $tb_y1, $tb_x2, $tb_y2) = ($conf->{tb_x}, $conf->{tb_y}, $conf->{tb_x} + $conf->{tb_w}, $conf->{tb_y} + $conf->{tb_h});
    my ($tx, $ty, $tw, $th) = ($tb_x1 + 10, $tb_y1 + 5, $conf->{tb_w} - 20 , $conf->{tb_h} - 10);
    my ($ti_x1, $ti_x2, $ti_y1, $ti_y2) = ($tb_x1 - 1, $tb_x2 + 1, $tb_y1 + 1, $tb_y2 + 1);
    my ($pc1, $pc2, $pc3, $pc4);
    if ($conf->{gradient} eq 'vertical') {
	($pc1, $pc2, $pc3, $pc4) = ($conf->{pc1}, $conf->{pc1}, $conf->{pc2}, $conf->{pc2});
    } else { 
	($pc1, $pc2, $pc3, $pc4) = ($conf->{pc1}, $conf->{pc2}, $conf->{pc1}, $conf->{pc2});
    }
    if (!$pc1) { ($pc1, $pc2, $pc3, $pc4) = ('#ffffff', '#ffffff', '#000000', '#000000') }
    my $ptransp = sprintf '%02x', $conf->{ptransp};
    my $transp = sprintf '%02x', $conf->{transp};
    $conf->{pbg_c} ||= '#aaaaaa';
    $conf->{tc} ||= '#ffffff';
    my $text_color = $conf->{text_color} ? "0x$conf->{text_color}" : '0xaaaaaa';
    $text_color =~ s/#//;
    output($config,
	   qq(# This is the configuration file for the $res bootsplash picture
# this file is necessary to specify the coordinates of the text box on the
# splash screen.

# config file version
version=3

# should the picture be displayed?
state=1

# fgcolor is the text forground color.
# bgcolor is the text background (i.e. transparent) color.
fgcolor=$conf->{fgcolor}
bgcolor=$conf->{bgcolor}

# (tx, ty) are the (x, y) coordinates of the text window in pixels.
# tw/th is the width/height of the text window in pixels.
tx=$tx
ty=$ty
tw=$tw
th=$th

# ttf message output parameters
text_x=$conf->{text_x}
text_y=$conf->{text_y}
text_size=$conf->{text_size}
text_color=$text_color

# name of the picture file (full path recommended)
jpeg=$jpeg
silentjpeg=$jpeg

progress_enable=1

# background
# b(order) or i(nter)
box silent noover $pb_x1 $pb_y1 $pb_x2 $pb_y2 $conf->{pbg_c}$ptransp
# progress bar
box silent inter  $pb_x1 $pi_y1 $pb_x1 $pi_y2 $pc1 $pc2 $pc3 $pc4
box silent        $pb_x1 $pi_y1 $pb_x2 $pi_y2 $pc1 $pc2 $pc3 $pc4
# black border (top, bottom, left, right)
box silent        $pb_x1 $pb_y1 $pb_x2 $pb_y1 #313234
box silent        $pb_x1 $pb_y2 $pb_x2 $pb_y2 #889499
box silent        $pb_x1 $pb_y1 $pb_x1 $pb_y2 #313234
box silent        $pb_x2 $pb_y1 $pb_x2 $pb_y2 #889499

# text box
box noover        $tb_x1 $tb_y1 $tb_x2 $tb_y2 $conf->{tc}$transp
# black border (top, bottom, left, right)
box               $ti_x1 $tb_y1 $ti_x1 $ti_y2 #313234
box               $tb_x1 $tb_y1 $ti_x2 $tb_y1 #313234
box               $ti_x2 $ti_y1 $ti_x2 $ti_y2 #889499
box               $tb_x1 $ti_y2 $ti_x2 $ti_y2 #889499

overpaintok=1

LOGO_CONSOLE=$conf->{LOGO_CONSOLE}
));
}

sub rectangle2xywh {
    my ($rect) = @_;

    my $x = min($rect->[0]{X} , $rect->[1]{X});
    my $y = min($rect->[0]{Y} , $rect->[1]{Y});
    my $w = abs($rect->[0]{X} - $rect->[1]{X});
    my $h = abs($rect->[0]{Y} - $rect->[1]{Y});
    ($x, $y, $w, $h);
}

sub xywh2rectangle {
    my ($x, $y, $w, $h) = @_;
    [ { X => $x, Y => $y }, { X => $x+$w, Y => $y+$h } ];
}

sub distance {
    my ($p1, $p2) = @_;
    sqr($p1->{X} - $p2->{X}) + sqr($p1->{Y} - $p2->{Y});
}

sub farthest {
    my ($point, @others) = @_;
    my $dist = 0;
    my $farthest;
    foreach (@others) {
	my $d = distance($point, $_);
	if ($d >= $dist) {
	    $dist = $d;
	    $farthest = $_;
	}
    }
    $farthest;
}

sub nearest {
    my ($point, @others) = @_;
    my $dist;
    my $nearest;
    foreach (@others) {
	my $d = distance($point, $_);
	if (! defined $dist || $d < $dist) {
	    $dist = $d;
	    $nearest = $_;
	}
    }
    $nearest;
}

1;
