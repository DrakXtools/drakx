use install_steps;
package install_steps;

my $old_afterInstallPackages = \&afterInstallPackages;
undef *afterInstallPackages;
*afterInstallPackages = sub {
    &$old_afterInstallPackages;

    my ($o) = @_;

    #- update oem lilo image if it exists.
    if (-s "$o->{prefix}/boot/oem-message-graphic") {
	rename "$o->{prefix}/boot/message-graphic", "$o->{prefix}/boot/message-graphic.mdkgiorig";
	rename "$o->{prefix}/boot/oem-message-graphic", "$o->{prefix}/boot/message-graphic";
    }

    #- update background image if it exists for common environment.
    if (-s "$o->{prefix}/usr/share/mdk/oem-background.png") {
	if (-e "$o->{prefix}/usr/share/mdk/backgrounds/default.png") {
	    rename "$o->{prefix}/usr/share/mdk/backgrounds/default.png",
	           "$o->{prefix}/usr/share/mdk/backgrounds/default.png.mdkgiorig";
	    rename "$o->{prefix}/usr/share/mdk/oem-background.png", "$o->{prefix}/usr/share/mdk/backgrounds/default.png";
	} else {
	    #- KDE desktop background.
	    if (-e "$o->{prefix}/usr/share/config/kdesktoprc") {
		update_gnomekderc("$o->{prefix}/usr/share/config/kdesktoprc", "Desktop0",
				  MultiWallpaperMode => "NoMulti",
				  Wallpaper => "/usr/share/mdk/oem-background.png",
				  WallpaperMode => "Scaled",
				 );
	    }
	    #- GNOME desktop background.
	    if (-e "$o->{prefix}/etc/gnome/config/Background") {
		update_gnomekderc("$o->{prefix}/etc/gnome/config/Background", "Default",
				  wallpaper => "/usr/share/mdk/oem-background.png",
				  wallpaperAlign => "3",
				 );
	    }
	}
    }

    #- try to workaround nforce stuff.
    foreach (keys %{$o->{packages}{provides}{kernel}}) {
	my $p = $o->{packages}{depslist}[$_];
	my ($ext, $version, $release) = $p->name =~ /^kernel-([^\d\-]*)-?([^\-]*)\.([^\-\.]*)$/ or next;
	-s "$o->{prefix}/lib/modules/$version-$release$ext/kernel/drivers/sound/nvaudio.o.gz" and
	  run_program::rooted($o->{prefix}, "cp -f /lib/modules/$version-$release$ext/kernel/drivers/sound/nvaudio.o.gz /lib/modules/$version-$release$ext/kernel/drivers/sound/i810_audio.o.gz");
    }

    #- try to check if pcitable and others have been built correctly.
    -e "$o->{prefix}/usr/share/ldetect-lst/pcitable" or run_program::rooted($o->{prefix}, "/usr/sbin/update-ldetect-lst");
};
