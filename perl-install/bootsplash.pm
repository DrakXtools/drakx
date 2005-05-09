package bootsplash;

use common;
use Xconfig::resolution_and_depth;

my $themes_dir = "$::prefix/usr/share/bootsplash/themes";
my $themes_config_dir = "$::prefix/etc/bootsplash/themes";
my $sysconfig_file = "$::prefix/etc/sysconfig/bootsplash";
my $bootsplash_scripts = "$::prefix/usr/share/bootsplash/scripts";
my $default_theme = 'Mandrivalinux';
our $default_thumbnail = '/usr/share/libDrakX/pixmaps/nosplash_thumb.png';
our @resolutions = uniq(map { "$_->{X}x$_->{Y}" } Xconfig::resolution_and_depth::bios_vga_modes());

sub get_framebuffer_resolution {
    require bootloader;
    my $bootloader = bootloader::read();
    my $x_res = Xconfig::resolution_and_depth::from_bios($bootloader->{default_vga});
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
    if (-r $sysconfig_file) {
        local $_;
        foreach (cat_($sysconfig_file)) {
            /^SPLASH=no/ and $theme{enabled} = 0;
            /^THEME=(.*)/ && -f theme_get_image_for_resolution($1, $res) and $theme{name} = $1;
            /^LOGO_CONSOLE=(.*)/ and $theme{keep_logo} = $1 ne "no";
        }
    }
    \%theme;
}

sub theme_get_image_for_resolution {
    my ($theme, $res) = @_;
    $themes_dir . '/' . $theme . '/images/bootsplash-' . $res . ".jpg";
}

sub theme_get_config_for_resolution {
    my ($theme, $res) = @_;
    $themes_config_dir . '/' . $theme . '/config/bootsplash-' . $res . ".cfg";
}

sub theme_exists_for_resolution {
    my ($theme, $res) = @_;
    -f theme_get_image_for_resolution($theme, $res) && -f theme_get_config_for_resolution($theme, $res);
}

sub themes_list() {
    grep { !/^\./ && -d $themes_dir } sort(all($themes_dir));
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
        system($bootsplash_scripts . '/switch-themes', $theme);
    }
}

sub remove() {
    if ($::testing) {
        print "disabling bootsplash theme\n";
    } else {
        system($bootsplash_scripts . '/remove-theme');
    }
}

sub set_logo_console {
    my ($keep_logo) = @_;
    my $logo_console = $keep_logo ? 'theme' : 'no';
    substInFile { s/^LOGO_CONSOLE=.*/LOGO_CONSOLE=$logo_console/ } $sysconfig_file;
}

sub create_path {
    my ($file) = @_;
    require File::Basename;
    my $dir = File::Basename::dirname($file);
    -d $dir or mkdir_p($dir);
}

sub theme_set_image_for_resolution {
    my ($name, $res, $source_image) = @_;
    my $dest_image = theme_get_image_for_resolution($name, $res);
    create_path($dest_image);
    #- Append an exclamation point to the geometry to force the image size to exactly the size you specify.
    system('convert', '-geometry', $res . '!', $source_image, $dest_image);
    system($bootsplash_scripts . '/rewritejpeg',  $dest_image);
}

sub theme_read_config_for_resolution {
    my ($theme, $res) = @_;
    +{ getVarsFromSh(theme_get_config_for_resolution($theme, $res)) };
}

sub theme_write_config_for_resolution {
    my ($name, $res, $conf) = @_;

    my $config = theme_get_config_for_resolution($name, $res);
    create_path($config);
    my $jpeg = theme_get_image_for_resolution($name, $res);
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
fgcolor=7
bgcolor=0

# (tx, ty) are the (x, y) coordinates of the text window in pixels.
# tw/th is the width/height of the text window in pixels.
tx=$conf->{tx}
ty=$conf->{ty}
tw=$conf->{tw}
th=$conf->{th}

# name of the picture file (full path recommended)
jpeg=$jpeg
silentjpeg=$jpeg

progress_enable=1

overpaintok=1

LOGO_CONSOLE=$conf->{LOGO_CONSOLE}
));
}

1;
