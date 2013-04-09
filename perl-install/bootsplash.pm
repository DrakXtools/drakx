package bootsplash;

use common;
use Xconfig::resolution_and_depth;


my $themes_dir = "/usr/share/bootsplash/themes";
my $themes_config_dir = "/etc/bootsplash/themes";
my $sysconfig_file = "/etc/sysconfig/bootsplash";
my $bootsplash_scripts = "/usr/share/bootsplash/scripts";
my $default_theme = 'Moondrake';
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
                );
    if (-r $::prefix . $sysconfig_file) {
        local $_;
        foreach (cat_($::prefix . $sysconfig_file)) {
            /^SPLASH=no/ and $theme{enabled} = 0;
            /^THEME=(.*)/ && -f theme_get_image_for_resolution($1, $res) and $theme{name} = $1;
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

1;
