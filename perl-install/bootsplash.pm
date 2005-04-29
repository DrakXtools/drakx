package bootsplash;

use common;

my $themes_dir = "$::prefix/usr/share/bootsplash/themes/";
my $sysconfig_file = '$::prefix/etc/sysconfig/bootsplash';
my $default_theme = 'Mandrivalinux';
our $default_thumbnail = '/usr/share/libDrakX/pixmaps/nosplash_thumb.png';

sub read_theme_config {
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
            /^THEME=(.*)/ && -f get_theme_image($1, $res) and $theme{name} = $1;
            /^LOGO_CONSOLE=(.*)/ and $theme{keep_logo} = $1 ne "no";
        }
    }
    \%theme;
}

sub get_theme_image {
    my ($theme, $res) = @_;
    $themes_dir . $theme . '/images/bootsplash-' . $res . ".jpg";
}

sub list_themes {
    my ($res) = @_;
    grep {
        !/^\./ && -d $themes_dir . $_ && -f get_theme_image($_, $res);
    } sort(all($themes_dir));
}

sub switch_theme {
    my ($theme) = @_;
    if ($::testing) {
        print "enabling bootsplash theme $theme\n";
    } else {
        #- theme scripts will update SPLASH value in sysconfig file
        system("$::prefix/usr/share/bootsplash/scripts/switch-themes", $theme);
    }
}

sub remove_theme() {
    if ($::testing) {
        print "disabling bootplash theme\n";
    } else {
        system("$::prefix/usr/share/bootsplash/scripts/remove-theme");
    }
}

sub set_logo_console {
    my ($keep_logo) = @_;
    my $logo_console = $keep_logo ? 'theme' : 'no';
    substInFile { s/^LOGO_CONSOLE=.*/LOGO_CONSOLE=$logo_console/ } $sysconfig_file;
}

1;
