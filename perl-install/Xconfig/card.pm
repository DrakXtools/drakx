package Xconfig::card; # $Id$

use diagnostics;
use strict;

use detect_devices;
use modules;
use common;
use log;


my %VideoRams = (
     256 => N_("256 kB"),
     512 => N_("512 kB"),
    1024 => N_("1 MB"),
    2048 => N_("2 MB"),
    4096 => N_("4 MB"),
    8192 => N_("8 MB"),
   16384 => N_("16 MB"),
   32768 => N_("32 MB"),
   65536 => N_("64 MB or more"),
);

my $lib = arch() =~ /x86_64/ ? "lib64" : "lib";
 
my @xfree4_Drivers = ((arch() =~ /^sparc/ ? qw(sunbw2 suncg14 suncg3 suncg6 sunffb sunleo suntcx) :
		    qw(apm ark chips cirrus cyrix glide i128 i740 i810 imstt 
                       mga neomagic newport nv rendition r128 radeon vesa
                       s3 s3virge savage siliconmotion sis tdfx tga trident tseng vmware)), 
		    qw(ati glint vga fbdev));

sub from_raw_X {
    my ($raw_X) = @_;

    my $device = $raw_X->get_device or die "no card configured";

    my $card = {
	use_DRI_GLX  => eval { any { /dri/ } $raw_X->get_modules },
	%$device,
    };
    add_to_card__using_Cards($card, $card->{BoardName});
    $card;
}

sub to_raw_X {
    my ($card, $raw_X) = @_;

    my @cards = ($card, @{$card->{cards} || []});

    foreach (@cards) {
	#- Specific ATI fglrx driver default options
	if ($_->{Driver} eq 'fglrx') {
	    # $default_ATI_fglrx_config need to be move in proprietary ?
	    $_->{raw_LINES} ||= default_ATI_fglrx_config();
	}
	if (arch() =~ /ppc/ && ($_->{Driver} eq 'r128' || $_->{Driver} eq 'radeon')) {
	    $_->{UseFBDev} = 1;
	}
    }

    $raw_X->set_devices(@cards);

    $raw_X->get_ServerLayout->{Xinerama} = { commented => !$card->{Xinerama}, Option => 1 }
      if defined $card->{Xinerama};

    $raw_X->set_load_module('glx', !$card->{DRI_GLX_SPECIAL}); #- glx for everyone, except proprietary nvidia
    $raw_X->set_load_module('dri', $card->{use_DRI_GLX} && !$card->{DRI_GLX_SPECIAL});

    # This loads the NVIDIA GLX extension module.
    # IT IS IMPORTANT TO KEEP NAME AS FULL PATH TO libglx.so ELSE
    # IT WILL LOAD XFree86 glx module and the server will crash.
    $raw_X->set_load_module($card->{DRI_GLX_SPECIAL}, to_bool($card->{DRI_GLX_SPECIAL})); 
    $raw_X->remove_Section('DRI');

    $raw_X->remove_load_module('v4l') if $card->{use_DRI_GLX} && $card->{Driver} eq 'r128';
}

sub default_ATI_fglrx_config() { our $default_ATI_fglrx_config }

sub probe() {
#-for Pixel tests
#-    my @c = { driver => 'Card:Matrox Millennium G400 DualHead', description => 'Matrox|Millennium G400 Dual HeadCard' };
    my @c = detect_devices::matching_driver__regexp('^(Card|Server|Driver):');

    my @cards = map {
	my @l = $_->{description} =~ /(.*?)\|(.*)/;
	my $card = { 
	    description => $_->{description},
	    VendorName => $l[0], BoardName => $l[1],
	    BusID => "PCI:$_->{pci_bus}:$_->{pci_device}:$_->{pci_function}",
	};
	if    ($_->{driver} =~ /Card:(.*)/)   { $card->{BoardName} = $1; add_to_card__using_Cards($card, $1) }
	elsif ($_->{driver} =~ /Driver:(.*)/) { $card->{Driver} = $1 }
	else { internal_error() }

	$card;
    } @c;

    if (@cards >= 2 && $cards[0]{card_name} eq $cards[1]{card_name} && $cards[0]{card_name} eq 'Intel 830') {
	shift @cards;
    }
    #- take a default on sparc if nothing has been found.
    if (arch() =~ /^sparc/ && !@cards) {
        log::l("Using probe with /proc/fb as nothing has been found!");
	my $s = cat_("/proc/fb");
	@cards = { server => $s =~ /Mach64/ ? "Mach64" : $s =~ /Permedia2/ ? "3DLabs" : "Sun24" };
    }

    #- disabling MULTI_HEAD when not available
    foreach (@cards) { 
	$_->{MULTI_HEAD} && $_->{card_name} =~ /G[24]00/ or next;
	if ($ENV{MATROX_HAL}) {
	    $_->{need_MATROX_HAL} = 1;
	} else {
	    delete $_->{MULTI_HEAD};
	}
    }

    #- in case of only one cards, remove all BusID reference, this will avoid
    #- need of change of it if the card is moved.
    #- on many PPC machines, card is on-board, BusID is important, leave?
    if (@cards == 1 && !$cards[0]{MULTI_HEAD} && arch() !~ /ppc/) {
	delete $cards[0]{BusID};
    }

    @cards;
}

sub card_config__not_listed {
    my ($in, $card, $options) = @_;

    my $vendors_regexp = join '|', map { quotemeta } (
        '3Dlabs',
        'AOpen', 'ASUS', 'ATI', 'Ark Logic', 'Avance Logic',
        'Cardex', 'Chaintech', 'Chips & Technologies', 'Cirrus Logic', 'Compaq', 'Creative Labs',
        'Dell', 'Diamond', 'Digital',
        'ET', 'Elsa',
        'Genoa', 'Guillemot', 'Hercules', 'Intel', 'Leadtek',
        'Matrox', 'Miro', 'NVIDIA', 'NeoMagic', 'Number Nine',
        'Oak', 'Orchid',
        'RIVA', 'Rendition Verite',
        'S3', 'Silicon Motion', 'STB', 'SiS', 'Sun',
        'Toshiba', 'Trident',
        'VideoLogic',
    );
    my $cards = readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");

    my @xf4 = grep { $options->{allowFB} || $_ ne 'fbdev' } @xfree4_Drivers;
    my @list = (
	(map { 'Vendor|' . $_ } keys %$cards),
	(map { 'Xorg|' . $_ } @xf4),
    );

    my $r = exists $cards->{$card->{BoardName}} ? "Vendor|$card->{BoardName}" : 'Xorg|vesa';
    $in->ask_from_({ title => N("X server"), 
		     messages => N("Choose an X server"),
		     interactive_help_id => 'configureX_card_list',
		   },
		   [ { val => \$r, separator => '|', list => \@list, sort => 1,
		       format => sub { $_[0] =~ /^Vendor\|($vendors_regexp)\s*-?(.*)/ ? "Vendor|$1|$2" : 
				       $_[0] =~ /^Vendor\|(.*)/ ? "Vendor|Other|$1" : $_[0] } } ]) or return;

    log::explanations("Xconfig::card: $r manually chosen");

    $r eq "Vendor|$card->{BoardName}" and return 1; #- it is unchanged, do not modify $card

    my ($kind, $s) = $r =~ /(.*?)\|(.*)/;

    %$card = ();
    if ($kind eq 'Vendor') {
	add_to_card__using_Cards($card, $s);
    } else {
	$card->{Driver} = $s;
    }
    $card->{manually_chosen} = 1;
    1;
}

sub multi_head_choose {
    my ($in, $auto, @cards) = @_;

    my @choices = multi_head_choices('', @cards);

    my $tc = $choices[0];
    if ($auto) {
	@choices == 1 or return;
    } else {
	$tc = $in->ask_from_listf(N("Multi-head configuration"),
				  N("Your system supports multiple head configuration.
What do you want to do?"), sub { $_[0]{text} }, \@choices) or return;
    }
    $tc->{code} or die internal_error();
    return $tc->{code}();
}

sub configure_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;

    my $card = $old_X->{card} || {};

    if ($card->{card_name}) {
	#- try to get info from given card_name
	add_to_card__using_Cards($card, $card->{card_name});
	if (!$card->{Driver}) {
	    log::l("bad card_name $card->{card_name}, using probe");
	    undef $card->{card_name};
	}
    }

    if (!$card->{Driver}) {
	my @cards = probe();
	my ($choice) = multi_head_choices($old_X->{Xinerama}, @cards);
	$card = $choice ? $choice->{code}() : do {
	    log::explanations('no graphic card probed, try providing one using $o->{card}{Driver} or $o->{card}{card_name}. Defaulting...');
	    { Driver => $options->{allowFB} ? 'fbdev' : 'vesa' };
	};
    }

    my ($glx_choice) = xfree_and_glx_choices($card);
    log::explanations("Using $glx_choice->{text}");
    $glx_choice->{code}();
    set_glx_restrictions($card);

    install_server($card, $options, $do_pkgs);
    if ($card->{needVideoRam} && !$card->{VideoRam}) {
	$card->{VideoRam} = $options->{VideoRam_probed} || 4096;
	log::explanations("argh, I need to know VideoRam! Taking " . ($options->{probed_VideoRam} ? "the probed" : "a default") . " value: VideoRam = $card->{VideoRam}");
    }
    to_raw_X($card, $raw_X);
    $card;
}

sub configure {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;

    my @cards = probe();
    @cards or @cards = {};

    if (!$cards[0]{Driver}) {
	if ($options->{allowFB}) {
	    $cards[0]{Driver} = 'fbdev';
	} elsif ($auto) {
	    log::explanations("Xconfig::card: auto failed (unknown card and no allowFB)");
	    return 0;
	}
    }
    if (!$auto) {
      card_config__not_listed:
	card_config__not_listed($in, $cards[0], $options) or return;
    }

    my $card = multi_head_choose($in, $auto, @cards) or return;

    xfree_and_glx_choose($in, $card, $auto) or return;

    eval { install_server($card, $options, $do_pkgs) };
    if ($@) {
	$in->ask_warn('', N("Can not install Xorg package: %s", $@));
	goto card_config__not_listed;
    }
    
    if ($card->{needVideoRam} && !$card->{VideoRam}) {
	if ($auto) {
	    log::explanations("Xconfig::card: auto failed (needVideoRam)");
	    return;
	}
	$card->{VideoRam} = (find { $_ <= $options->{VideoRam_probed} } reverse ikeys %VideoRams) || 4096;
	$in->ask_from('', N("Select the memory size of your graphics card"),
		      [ { val => \$card->{VideoRam},
			  type => 'list',
			  list => [ ikeys %VideoRams ],
			  format => sub { translate($VideoRams{$_[0]}) },
			  not_edit => !$::expert } ]) or return;
    }

    to_raw_X($card, $raw_X);
    $card;
}

sub install_server {
    my ($card, $options, $do_pkgs) = @_;

    my $prog = "$::prefix/usr/X11R6/bin/Xorg";

    my @packages;
    push @packages, 'xorg-x11-server' if ! -x $prog;

    #- additional packages to install according available card.
    #- add XFree86-libs-DRI here if using DRI (future split of XFree86 TODO)
    if ($card->{use_DRI_GLX}) {
	push @packages, 'Glide_V5' if $card->{card_name} eq 'Voodoo5 (generic)';
	push @packages, 'Glide_V3-DRI' if member($card->{card_name}, 'Voodoo3 (generic)', 'Voodoo Banshee (generic)');
	push @packages, 'xorg-x11-glide-module' if $card->{card_name} =~ /Voodoo/;
    }

    if ($options->{freedriver}) {
	delete $card->{Driver2};
    }

    my %proprietary_Driver2 = (
	nvidia => [ 'nvidia-kernel', 'nvidia' ], #- using NVIDIA driver (TNT, TN2 and GeForce cards only).
	fglrx => [ 'ati-kernel', 'ati' ], #- using ATI fglrx driver (Radeon, Fire GL cards only).
    );
    if (my $rpms_needed = $proprietary_Driver2{$card->{Driver2}}) {
	if (my $proprietary_packages = $do_pkgs->check_kernel_module_packages($rpms_needed->[0], $rpms_needed->[1])) {
	    push @packages, @$proprietary_packages;
	}
    }

    $do_pkgs->install(@packages) if @packages;
    -x $prog or die "server not available (should be in $prog)";

    my $modules_dir = "/usr/X11R6/$lib/modules";
    #- make sure everything is correct at this point, packages have really been installed
    #- and driver and GLX extension is present.
    if ($card->{Driver2} eq 'nvidia' &&
	-e "$::prefix$modules_dir/drivers/nvidia_drv.o") {
	#- when there is extensions/libglx.a, it means extensions/libglx.so is not xorg's libglx, so it may be nvidia's
	#- new nvidia packages have libglx.so in extensions/nvidia instead of simply extensions/
	my $libglx_a = -e "$::prefix$modules_dir/extensions/libglx.a";
	my $libglx = find { -l "$::prefix$_" } "$modules_dir/extensions/nvidia/libglx.so", if_($libglx_a, "$modules_dir/extensions/libglx.so");
	if ($libglx) {
	    log::explanations("Using specific NVIDIA driver and GLX extensions");
	    $card->{Driver} = 'nvidia';
	    $card->{DRI_GLX_SPECIAL} = $libglx;
	    $card->{Options}{IgnoreEDID} = 1;
	}
    }
    if ($card->{Driver2} eq 'fglrx' &&
	-e "$::prefix$modules_dir/dri/fglrx_dri.so" &&
	(-e "$::prefix$modules_dir/drivers/fglrx_drv.o" || -e "$::prefix$modules_dir/drivers/fglrx_drv.so")) {
	log::explanations("Using specific ATI fglrx and DRI drivers");
	$card->{Driver} = 'fglrx';
    }

    libgl_config($card->{Driver});

    if ($card->{need_MATROX_HAL}) {
	require Xconfig::proprietary;
	Xconfig::proprietary::install_matrox_hal($::prefix);
    }
}

sub xfree_and_glx_choose {
    my ($in, $card, $auto) = @_;

    my @choices = xfree_and_glx_choices($card);

    my $tc = 
      $auto ? $choices[0] :
	$in->ask_from_listf_raw({ title => N("Xorg configuration"), 
				  messages => formatAlaTeX(join("\n\n\n", (grep { $_ } map { $_->{more_messages} } @choices),
								N("Which configuration of Xorg do you want to have?"))), 
				  interactive_help_id => 'configureX_xfree_and_glx',
				},
				sub { $_[0]{text} }, \@choices) or return;
    log::explanations("Using $tc->{text}");
    $tc->{code}();
    set_glx_restrictions($card);
    1;
}

sub multi_head_choices {
    my ($want_Xinerama, @cards) = @_;
    my @choices;

    my $has_multi_head = @cards > 1 || @cards && $cards[0]{MULTI_HEAD} > 1;
    my $disable_multi_head = any { 
	$_->{Driver} or log::explanations("found card $_->{description} not supported by XF4, disabling multi-head support");
	!$_->{Driver};
    } @cards;

    if ($has_multi_head && !$disable_multi_head) {
	my $configure_multi_head = sub {

	    #- special case for multi head card using only one BusID.
	    @cards = map {
		map_index { { Screen => $::i, %$_ } } ($_) x ($_->{MULTI_HEAD} || 1);
	    } @cards;

	    my $card = shift @cards; #- assume good default.
	    $card->{cards} = \@cards;
	    $card->{Xinerama} = $_[0];
	    $card;
	};
	my $independent = { text => N("Configure all heads independently"), code => sub { $configure_multi_head->('') } };
	my $xinerama    = { text => N("Use Xinerama extension"),            code => sub { $configure_multi_head->(1) } };
	push @choices, $want_Xinerama ? ($xinerama, $independent) : ($independent, $xinerama);
    }

    foreach my $c (@cards) {
	push @choices, { text => N("Configure only card \"%s\"%s", $c->{description}, $c->{BusID} && " ($c->{BusID})"),
			 code => sub { $c } };
    }
    @choices;
}

#- Xorg version available, it would be better to parse available package and get version from it.
sub xorg_version() { '6.8.2' }

sub xfree_and_glx_choices {
    my ($card) = @_;

    my @choices = if_($card->{Driver}, { text => N("Xorg %s", xorg_version()), code => sub {} });

    #- no GLX with Xinerama
    return @choices if $card->{Xinerama};

    #- ask the expert or any user on second pass user to enable or not hardware acceleration support.
    if ($card->{DRI_GLX}) {
	unshift @choices, { text => N("Xorg %s with 3D hardware acceleration", xorg_version()),
			    code => sub { $card->{use_DRI_GLX} = 1 },
			    more_messages => N("Your card can have 3D hardware acceleration support with Xorg %s.", xorg_version()),
			  };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration.
    if ($card->{DRI_GLX_EXPERIMENTAL} && $::expert) {
	push @choices, { text => N("Xorg %s with EXPERIMENTAL 3D hardware acceleration", xorg_version()),
			 code => sub { $card->{use_DRI_GLX} = 1 },
			 more_messages => N("Your card can have 3D hardware acceleration support with Xorg %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", xorg_version()),
		       };
    }
    @choices;
}

sub set_glx_restrictions {
    my ($card) = @_;

    #- 3D acceleration configuration for XFree 4 using DRI, this is enabled by default
    #- but for some there is a need to specify VideoRam (else it will not run).
    if ($card->{use_DRI_GLX}) {
	$card->{needVideoRam} = 1 if $card->{description} =~ /Matrox.* G[245][05]0/;
	($card->{needVideoRam}, $card->{VideoRam}) = (1, 16384)
	  if member($card->{card_name}, 'Intel 810', 'Intel 815');

	#- hack for ATI Rage 128 card using a bttv or peripheral with PCI bus mastering exchange
	#- AND using DRI at the same time.
	if (member($card->{card_name}, 'ATI Rage 128', 'ATI Rage 128 TVout', 'ATI Rage 128 Mobility')) {
	    $card->{Options}{UseCCEFor2D} = bool2text(modules::probe_category('multimedia/tv'));
	}
    }

    #- check for Matrox G200 PCI cards, disable AGP in such cases, causes black screen else.
    if (member($card->{card_name}, 'Matrox Millennium 200', 'Matrox Millennium 200', 'Matrox Mystique') && $card->{description} !~ /AGP/) {
	log::explanations("disabling AGP mode for Matrox card, as it seems to be a PCI card");
	log::explanations("this is only used for XFree 3.3.6, see /etc/X11/glx.conf");
	substInFile { s/^\s*#*\s*mga_dma\s*=\s*\d+\s*$/mga_dma = 0\n/ } "$::prefix/etc/X11/glx.conf";
    }
}

sub libgl_config {
    my ($Driver) = @_;

    my $dir = "$::prefix/etc/ld.so.conf.d/";

    my %driver_to_libgl_config = (
	nvidia => '.nvidia.conf',
	fglrx => '.ati.conf',
    );
    my $need_to_run_ldconfig;
    my $link = "$dir/GL.conf";
    if (my $file = $driver_to_libgl_config{$Driver}) {
        if (-e "$dir/$file" && readlink($link) ne $file) {
            symlinkf($file, "$dir/GL.conf");
            $need_to_run_ldconfig = 1;
            log::explanations("ldconfig will be run because the GL library was enabled");
        }
    } elsif (-e $link) {
	eval { rm_rf($link) };
        $need_to_run_ldconfig = 2;
        log::explanations("ldconfig will be run because the GL library was disabled");

    }
    system("/sbin/ldconfig") if $::isStandalone && $need_to_run_ldconfig;
}

sub add_to_card__using_Cards {
    my ($card, $name) = @_;
    my $cards = readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");
    add2hash($card, $cards->{$name});
    $card->{BoardName} = $card->{card_name};

    $card;
}

#- needed for bad cards not restoring cleanly framebuffer, according to which version of Xorg are used.
sub check_bad_card {
    my ($card) = @_;
    my $bad_card = $card->{BAD_FB_RESTORE};
    $bad_card ||= $card->{Driver} eq 'i810' || $card->{Driver} eq 'fbdev';
    $bad_card ||= member($card->{Driver}, 'nvidia', 'vmware') if !$::isStandalone; #- avoid testing during install at any price.

    log::explanations("the graphics card does not like X in framebuffer") if $bad_card;

    !$bad_card;
}

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = openFileMaybeCompressed($file);

    my $lineno = 0;
    my ($cmd, $val);
    my $fs = {
	NAME => sub {
	    $cards{$card->{card_name}} = $card if $card;
	    $card = { card_name => $val };
	},
	SEE => sub {
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";
	    add2hash($card, $c);
	},
        LINE => sub { $val =~ s/^\s*//; $card->{raw_LINES} .= "$val\n" },
	CHIPSET => sub { $card->{Chipset} = $val },
	DRIVER => sub { $card->{Driver} = $val },
	DRIVER2 => sub { $card->{Driver2} = $val },
	NEEDVIDEORAM => sub { $card->{needVideoRam} = 1 },
	DRI_GLX => sub { $card->{DRI_GLX} = 1 if $card->{Driver} },
	DRI_GLX_EXPERIMENTAL => sub { $card->{DRI_GLX_EXPERIMENTAL} = 1 if $card->{Driver} },
	MULTI_HEAD => sub { $card->{MULTI_HEAD} = $val if $card->{Driver} },
	BAD_FB_RESTORE => sub { $card->{BAD_FB_RESTORE} = 1 },
	FB_TVOUT => sub { $card->{FB_TVOUT} = 1 },
	UNSUPPORTED => sub { delete $card->{Driver} },

	COMMENT => sub {},
    };

    local $_;
    while (<$F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and do { $cards{$card->{card_name}} = $card if $card; last };

	($cmd, $val) = /(\S+)\s*(.*)/ or next;

	my $f = $fs->{$cmd};

	$f ? $f->() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
}

our $default_ATI_fglrx_config = <<'END';
# === disable PnP Monitor  ===
#Option                              "NoDDC"
# === disable/enable XAA/DRI ===
Option "no_accel"                   "no"
Option "no_dri"                     "no"
# === FireGL DDX driver module specific settings ===
# === Screen Management ===
Option "DesktopSetup"               "0x00000000" 
Option "MonitorLayout"              "AUTO, AUTO"
Option "IgnoreEDID"                 "off"
Option "HSync2"                     "unspecified" 
Option "VRefresh2"                  "unspecified" 
Option "ScreenOverlap"              "0" 
# === TV-out Management ===
Option "NoTV"                       "yes"     
Option "TVStandard"                 "NTSC-M"     
Option "TVHSizeAdj"                 "0"     
Option "TVVSizeAdj"                 "0"     
Option "TVHPosAdj"                  "0"     
Option "TVVPosAdj"                  "0"     
Option "TVHStartAdj"                "0"     
Option "TVColorAdj"                 "0"     
Option "GammaCorrectionI"           "0x00000000"
Option "GammaCorrectionII"          "0x00000000"
# === OpenGL specific profiles/settings ===
Option "Capabilities"               "0x00000000"
# === Video Overlay for the Xv extension ===
Option "VideoOverlay"               "on"
# === OpenGL Overlay ===
# Note: When OpenGL Overlay is enabled, Video Overlay
#       will be disabled automatically
Option "OpenGLOverlay"              "off"
Option "CenterMode"                 "off"
# === QBS Support ===
Option "Stereo"                     "off"
Option "StereoSyncEnable"           "1"
# === Misc Options ===
Option "UseFastTLS"                 "0"
Option "BlockSignalsOnLock"         "on"
Option "UseInternalAGPGART"         "no"
Option "ForceGenericCPU"            "no"
# === FSAA ===
Option "FSAAScale"                  "1"
Option "FSAADisableGamma"           "no"
Option "FSAACustomizeMSPos"         "no"
Option "FSAAMSPosX0"                "0.000000"
Option "FSAAMSPosY0"                "0.000000"
Option "FSAAMSPosX1"                "0.000000"
Option "FSAAMSPosY1"                "0.000000"
Option "FSAAMSPosX2"                "0.000000"
Option "FSAAMSPosY2"                "0.000000"
Option "FSAAMSPosX3"                "0.000000"
Option "FSAAMSPosY3"                "0.000000"
Option "FSAAMSPosX4"                "0.000000"
Option "FSAAMSPosY4"                "0.000000"
Option "FSAAMSPosX5"                "0.000000"
Option "FSAAMSPosY5"                "0.000000"
END

1;

