use modules;
package modules;
my $old_load_raw = \&load_raw;
undef *load_raw;
*load_raw = sub {
    &$old_load_raw;

    my @l = map { my ($i, @i) = @$_; [ $i, \@i ] } grep { $_->[0] !~ /ignore/ } @_;
    foreach (@l) {
	if ($_->[0] eq 'ehci-hcd') {
	    add_alias('usb-interface1', $_->[0]);
	}
    }

    if (get_alias("usb-interface") || get_alias("usb-interface1")) {
	unless (-e "/proc/bus/usb/devices") {
	    require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
	    #- ensure keyboard is working, the kernel must do the job the BIOS was doing
	    sleep 4;
	    load_multi("usbkbd", "keybdev") if detect_devices::usbKeyboards();
	}
    }
};

my $old_load = \&load;
undef *load;
*load = sub {
    &$old_load;

    #- hack to get back usb-interface (even if already loaded by stage1)
    #- NOTE load_multi is not used for that so not overloaded to fix that too.
    if ($_[0] =~ /usb-[uo]hci/ && !get_alias("usb-interface")) {
	add_alias('usb-interface', $_[0]);
    } elsif ($_[0] eq 'ehci-hcd' && !get_alias("usb-interface1")) {
	add_alias('usb-interface1', $_[0]);
    }

    if (get_alias("usb-interface") || get_alias("usb-interface1")) {
	unless (-e "/proc/bus/usb/devices") {
	    require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
	    #- ensure keyboard is working, the kernel must do the job the BIOS was doing
	    sleep 4;
	    load_multi("usbkbd", "keybdev") if detect_devices::usbKeyboards();
	}
    }
};

#- ensure it is loaded using this patch.
$::noauto or modules::load_thiskind("usb"); 
sleep 2;

use install_steps;
package install_steps;

my $old_beforeInstallPackages = \&beforeInstallPackages;
undef *beforeInstallPackages;
*beforeInstallPackages = sub {
    &$old_beforeInstallPackages;

    my ($o) = @_;
    mkdir "$o->{prefix}$_" foreach qw(/boot /usr /usr/share /usr/share/mdk);
    install_any::getAndSaveFile("Mandrake/base/oem-message-graphic", "$o->{prefix}/boot/oem-message-graphic");
    install_any::getAndSaveFile("Mandrake/base/oem-background.png", "$o->{prefix}/usr/share/mdk/oem-background.png");
};

my $old_afterInstallPackages = \&afterInstallPackages;
undef *afterInstallPackages;
*afterInstallPackages = sub {
    &$old_afterInstallPackages;

    my ($o) = @_;

    #- lilo image.
    rename "$o->{prefix}/boot/lilo-graphic/message", "$o->{prefix}/boot/lilo-graphic/message.orig";
    system "chroot", $o->{prefix}, "cp", "-f", "/boot/oem-message-graphic", "/boot/lilo-graphic/message";

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

    #- make sure no error can be forwarded, test staroffice installed and OpenOffice.org,
    #- remove the first if the second is installed.
    eval {
	if (!$o->{isUpgrade} && -e "$o->{prefix}/usr/lib/openoffice/program/soffice.bin" && grep { -e "$o->{prefix}/usr/lib/office60_$_/program/soffice.bin" } qw(de en es fr it)) {
	    require run_program;
	    log::l("removing OpenOffice.org as staroffice is installed");
	    run_program::rooted($o->{prefix}, "rpm", "-e", "OpenOffice.org");
	}
    };
};

use install_any;
package install_any;

undef *copy_advertising;
*copy_advertising = sub {
    my ($o) = @_;

    return if $::rootwidth < 800;

    my $f;
    my $source_dir = "Mandrake/share/advertising";
    foreach ("." . $o->{lang}, "." . substr($o->{lang},0,2), '') {
	$f = getFile("$source_dir$_/list") or next;
	$source_dir = "$source_dir$_";
    }
    if (my @files = <$f>) {
	my $dir = "$o->{prefix}/tmp/drakx-images";
	mkdir $dir;
	unlink glob_("$dir/*");
	foreach (@files) {
	    chomp;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/\.png/\.pl/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/\.pl/_icon\.png/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/_icon\.png/\.png/;
	}
	@advertising_images = map { $_ && -e "$dir/$_" ? ("$dir/$_") : () } @files;
    }
};

#undef *allowNVIDIA_rpms;
#*allowNVIDIA_rpms = sub {
#    my ($packages) = @_;
#    require pkgs;
#    if (pkgs::packageByName($packages, "NVIDIA_GLX")) {
#	#- at this point, we can allow using NVIDIA 3D acceleration packages.
#	my @rpms;
#	foreach (keys %{$packages->{names}}) {
#	    my ($ext, $version, $release) = /kernel[^-]*(-smp|-enterprise|-secure)?(?:-(\d.*?)\.(\d+\.\d+mdk))?$/ or next;
#	    my $p = pkgs::packageByName($packages, $_);
#	    pkgs::packageSelectedOrInstalled($p) or next;
#	    $version or ($version, $release) = (pkgs::packageVersion($p), pkgs::packageRelease($p));
#	    my $name = "NVIDIA_kernel-$version-$release$ext";
#	    pkgs::packageByName($packages, $name) or return;
#	    push @rpms, $name;
#	}
#	@rpms > 0 or return;
#	return [ @rpms, "NVIDIA_GLX" ];
#    }
#};

use detect_devices;
package detect_devices;

undef *usbMice;
*usbMice = sub { grep { ($_->{media_type} =~ /\|Mouse/ || $_->{driver} =~ /Mouse:USB/) &&
			  $_->{driver} !~ /Tablet:wacom/} usb_probe() };

use Xconfigurator;
package Xconfigurator;

undef *cardConfigurationAuto;
*cardConfigurationAuto = sub {
    my @cards;
    if (my @c = grep { $_->{driver} =~ /(Card|Server):/ } detect_devices::probeall()) {
	@c >= 2 && $c[0]{description} eq $c[1]{description} && $c[0]{description} =~ /82830 CGC/ and shift @c;
	foreach my $i (0..$#c) {
	    local $_ = $c[$i]->{driver};
	    my $card = { identifier => ($c[$i]{description} . (@c > 1 && " $i")) };
	    $card->{type} = $1 if /Card:(.*)/;
	    $card->{server} = $1 if /Server:(.*)/;
	    $card->{driver} = $1 if /Driver:(.*)/;
	    $card->{flags}{needVideoRam} = /86c368|S3 Inc|Tseng.*ET6\d00/;
	    $card->{busid} = "PCI:$c[$i]{pci_bus}:$c[$i]{pci_device}:$c[$i]{pci_function}";
	    push @{$card->{lines}}, @{$lines{$card->{identifier}} || []};
	    push @cards, $card;
	}
    }
    #- take a default on sparc if nothing has been found.
    if (arch() =~ /^sparc/ && !@cards) {
        log::l("Using probe with /proc/fb as nothing has been found!");
	local $_ = cat_("/proc/fb");
	if (/Mach64/) { push @cards, { server => "Mach64" } }
	elsif (/Permedia2/) { push @cards, { server => "3DLabs" } }
	else { push @cards, { server => "Sun24" } }
    }
    #- special case for dual head card using only one busid.
    @cards = map { my $dup = $_->{identifier} =~ /MGA G[45]50/ ? 2 : 1;
		   if ($dup > 1) {
		       my @result;
		       my $orig = $_;
		       foreach (1..$dup) {
			   my $card = {};
			   add2hash($card, $orig);
			   push @result, $card;
		       }
		       @result;
		   } else {
		       ($_);
		   }
	       } @cards;
    #- make sure no type are already used, duplicate both screen
    #- and rename type (because used as id).
    if (@cards > 1) {
	my $card = 1;
	foreach (@cards) {
	    updateCardAccordingName($_, $_->{type}) if $_->{type};
	    $_->{type} = "$_->{type} $card";
	    $card++;
	}
    }
    #- in case of only one cards, remove all busid reference, this will avoid
    #- need of change of it if the card is moved.
    #- on many PPC machines, card is on-board, busid is important, leave?
    @cards == 1 and delete $cards[0]{busid} if arch() !~ /ppc/;
    @cards;
};

use mouse;
package mouse;
undef *detect;
*detect = sub {
    if (arch() =~ /^sparc/) {
	return fullname2mouse("sunmouse|Sun - Mouse");
    }
    if (arch() eq "ppc") {
        return fullname2mouse(detect_devices::hasMousePS2("usbmouse") ? 
			      "USB|1 button" :
			      #- No need to search for an ADB mouse.  If I did, the PPC kernel would
			      #- find one whether or not I had one installed!  So..  default to it.
			      "busmouse|1 button");
    }

    my @wacom;
    my $fast_mouse_probe = sub {
	my $auxmouse = detect_devices::hasMousePS2("psaux") && fullname2mouse("PS/2|Standard", unsafe => 1);

	if (modules::get_alias("usb-interface")) {
	    if (my (@l) = detect_devices::usbMice()) {
		log::l("found usb mouse $_->{driver} $_->{description} ($_->{type})") foreach @l;
		eval { modules::load($_) foreach qw(hid mousedev usbmouse) };
		if (!$@ && detect_devices::tryOpen("usbmouse")) {
		    my $mouse = fullname2mouse($l[0]{driver} =~ /Mouse:(.*)/ ? $1 : "USB|Generic");
		    $auxmouse and $mouse->{auxmouse} = $auxmouse; #- for laptop, we kept the PS/2 as secondary (symbolic).
		    return $mouse;
		}
		eval { modules::unload($_) foreach qw(usbmouse mousedev hid) };
	    }
	}
	$auxmouse;
    };

    if (modules::get_alias("usb-interface")) {
	my $keep_mouse;
	if (my (@l) = detect_devices::usbWacom()) {
	    log::l("found usb wacom $_->{driver} $_->{description} ($_->{type})") foreach @l;
	    eval { modules::load("wacom"); modules::load("evdev"); };
	    unless ($@) {
		foreach (0..$#l) {
		    detect_devices::tryOpen("input/event$_") and $keep_mouse = 1, push @wacom, "input/event$_";
		}
	    }
	    $keep_mouse or eval { modules::unload("evdev"); modules::unload("wacom"); };
	}
    }

    #- at this level, not all possible mice are detected so avoid invoking serial_probe
    #- which takes a while for its probe.
    if ($::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$mouse and return ($mouse, @wacom);
    }

    #- probe serial device to make sure a wacom has been detected.
    eval { modules::load("serial") };
    my ($r, @serial_wacom) = mouseconfig(); push @wacom, @serial_wacom;

    if (!$::isStandalone) {
	my $mouse = $fast_mouse_probe->();
	$r && $mouse and $r->{auxmouse} = $mouse; #- we kept the auxilliary mouse as PS/2.
	$r and return ($r, @wacom);
	$mouse and return ($mouse, @wacom);
    } else {
	$r and return ($r, @wacom);
    }

    #- in case only a wacom has been found, assume an inexistant mouse (necessary).
    @wacom and return { CLASS      => 'MOUSE',
			nbuttons   => 2,
			device     => "nothing",
			MOUSETYPE  => "Microsoft",
			XMOUSETYPE => "Microsoft"}, @wacom;

    if (!modules::get_alias("usb-interface") && detect_devices::is_a_recent_computer() && $::isInstall && !$::noauto) {
	#- special case for non detected usb interface on a box with no mouse.
	#- we *must* find out if there really is no usb, otherwise the box may
	#- not be accessible via the keyboard (if the keyboard is USB)
	#- the only way to know this is to make a full pci probe
	modules::load_thiskind("usb", '', 'unsafe'); 
	if (my $mouse = $fast_mouse_probe->()) {
	    return $mouse;
	}
    }

    if (modules::get_alias("usb-interface")) {
	eval { modules::load($_) foreach qw(hid mousedev usbmouse) };
	sleep 1;
	if (!$@ && detect_devices::tryOpen("usbmouse")) {
	    #- defaults to generic USB mouse on usbmouse.
	    log::l("defaulting to usb generic mouse");
	    return fullname2mouse("USB|Generic", unsafe => 1);
	}
    }

    #- defaults to generic serial mouse on ttyS0.
    #- Oops? using return let return a hash ref, if not using it, it return a list directly :-)
    return fullname2mouse("serial|Generic 2 Button Mouse", unsafe => 1);
};
