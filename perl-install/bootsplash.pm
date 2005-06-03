package bootsplash;

use common;
use Xconfig::resolution_and_depth;
use vars qw(@ISA %EXPORT_TAGS);

@ISA = qw(Exporter);
%EXPORT_TAGS = (drawing => [qw(rectangle2xywh xywh2rectangle distance farthest nearest)]);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

my $themes_dir = "$::prefix/usr/share/bootsplash/themes";
my $themes_config_dir = "$::prefix/etc/bootsplash/themes";
my $sysconfig_file = "$::prefix/etc/sysconfig/bootsplash";
my $bootsplash_scripts = "$::prefix/usr/share/bootsplash/scripts";
my $default_theme = 'Mandrivalinux';
our $default_thumbnail = '/usr/share/libDrakX/pixmaps/nosplash_thumb.png';
our @resolutions = uniq(map { "$_->{X}x$_->{Y}" } Xconfig::resolution_and_depth::bios_vga_modes());

sub get_framebuffer_resolution {
    require bootloader;
    require fsedit;
    my $bootloader = bootloader::read(fsedit::get_hds());
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
    mkdir_p(dirname($file));
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
    [ { X => $x, Y => $y }, { X => $x+$w, Y => $y+$w } ];
}

sub distance {
    my ($p1, $p2) = @_;
    sqr($p1->{X} - $p2->{X}) + sqr($p1->{Y} - $p2->{Y});
}

sub farthest {
    my ($point, @others) = @_;
    my $i = 0;
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
    my $i = 0;
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
