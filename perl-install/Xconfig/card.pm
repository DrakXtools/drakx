package Xconfig::card; # $Id$

use diagnostics;
use strict;

use detect_devices;
use modules;
use common;
use log;


my $force_xf4 = arch() =~ /ppc|ia64/;


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

our %serversdriver = arch() =~ /^sparc/ ? (
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
my @allbutfbservers = grep { arch() =~ /^sparc/ || $serversdriver{$_} ne "fbdev" } keys(%serversdriver);
my @allservers = keys(%serversdriver);

my @xfree4_Drivers = ((arch() =~ /^sparc/ ? qw(sunbw2 suncg14 suncg3 suncg6 sunffb sunleo suntcx) :
		    qw(apm ark chips cirrus cyrix glide i128 i740 i810 imstt 
                       mga neomagic newport nv rendition r128 radeon vesa
                       s3 s3virge savage siliconmotion sis tdfx tga trident tseng vmware)), 
		    qw(ati glint vga fbdev));


#- using XF4 if {Driver} && !{prefer_xf3} otherwise using XF3
#- error if $force_xf4 && !{Driver} || !{Driver} && !{server}
#- internal error if $force_xf4 && {prefer_xf3} || {prefer_xf3} && !{server}

sub using_xf4 {
    my ($card) = @_;
    $card->{Driver} && !$card->{prefer_xf3};
}

sub server_binary {
    my ($card) = @_;
    "/usr/X11R6/bin/" . 
      (using_xf4($card) ? 'XFree86' : 
       $card->{server} =~ /Sun(.*)/ ? "Xsun$1" : 
       $card->{server} eq 'Xpmac' ? 'Xpmac' :
       "XF86_$card->{server}");
}

sub from_raw_X {
    my ($raw_X) = @_;

    my $device = $raw_X->get_device or die "no card configured";

    my ($xfree3_server) = readlink("$::prefix/etc/X11/X") =~ /XF86_(.*)/;

    my $card = {
	use_UTAH_GLX => (any { /glx/ } $raw_X->{xfree3}->get_modules),
	use_DRI_GLX  => (any { /dri/ } $raw_X->{xfree4}->get_modules),
	server => $xfree3_server,
	prefer_xf3 => $xfree3_server && !$force_xf4,
	%$device,
    };
    add_to_card__using_Cards($card, $card->{BoardName});
    $card->{prog} = server_binary($card);
    $card;
}

sub to_raw_X {
    my ($card, $raw_X) = @_;

    $raw_X->set_devices($card, @{$card->{cards} || []});

    $raw_X->{xfree4}->get_ServerLayout->{Xinerama} = { commented => !$card->{Xinerama}, Option => 1 }
      if defined $card->{Xinerama};

    $raw_X->{xfree3}->set_load_module('glx-3.so', $card->{use_UTAH_GLX}); #- glx.so may clash with server version 4.

    $raw_X->{xfree4}->set_load_module('glx', !$card->{DRI_GLX_SPECIAL}); #- glx for everyone, except proprietary nvidia
    $raw_X->{xfree4}->set_load_module('dri', $card->{use_DRI_GLX} && !$card->{DRI_GLX_SPECIAL});

    # This loads the NVIDIA GLX extension module.
    # IT IS IMPORTANT TO KEEP NAME AS FULL PATH TO libglx.so ELSE
    # IT WILL LOAD XFree86 glx module and the server will crash.
    $raw_X->{xfree4}->set_load_module('/usr/X11R6/lib/modules/extensions/libglx.so', $card->{DRI_GLX_SPECIAL}); 

    $raw_X->{xfree4}->remove_Section('DRI');
    $raw_X->{xfree4}->add_Section('DRI', { Mode => { val => '0666' } }) if $card->{use_DRI_GLX};

    $raw_X->{xfree4}->remove_load_module('v4l') if $card->{use_DRI_GLX} && $card->{Driver} eq 'r128';
}

sub probe() {
#-for Pixel tests
#-    my @c = { driver => 'Card:Matrox Millennium G400 DualHead', description => 'Matrox|Millennium G400 Dual HeadCard' };
    my @c = grep { $_->{driver} =~ /(Card|Server|Driver):/ } detect_devices::probeall();

    my @cards = map {
	my @l = $_->{description} =~ /(.*?)\|(.*)/;
	my $card = { 
	    description => $_->{description},
	    VendorName => $l[0], BoardName => $l[1],
	    BusID => "PCI:$_->{pci_bus}:$_->{pci_device}:$_->{pci_function}",
	};
	if    ($_->{driver} =~ /Card:(.*)/)   { $card->{BoardName} = $1; add_to_card__using_Cards($card, $1) }
	elsif ($_->{driver} =~ /Server:(.*)/) { $card->{server} = $1 }
	elsif ($_->{driver} =~ /Driver:(.*)/) { $card->{Driver} = $1 }
	else { internal_error() }

	$_->{VideoRam} = 4096 if $_->{Driver} eq 'i810';
	$_->{Options_xfree4}{UseFBDev} = undef if arch() =~ /ppc/ && $_->{Driver} eq 'r128';

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

    my @xf3 = $options->{allowFB} ? @allservers : @allbutfbservers;
    my @xf4 = grep { $options->{allowFB} || $_ ne 'fbdev' } @xfree4_Drivers;
    my @list = (
	(map { 'Vendor|' . $_ } keys %$cards),
        if_(!$force_xf4, map { 'XFree 3|' . $_ } @xf3), 
	(map { 'XFree 4|' . $_ } @xf4),
    );

    my $r = exists $cards->{$card->{BoardName}} ? "Vendor|$card->{BoardName}" : 'XFree 4|vesa';
    $in->ask_from_({ title => N("X server"), 
		     messages => N("Choose an X server"),
		     interactive_help_id => 'configureX_card_list',
		   },
		   [ { val => \$r, separator => '|', list => \@list, sort => 1,
		       format => sub { $_[0] =~ /^Vendor\|($vendors_regexp)\s*-?(.*)/ ? "Vendor|$1|$2" : 
				       $_[0] =~ /^Vendor\|(.*)/ ? "Vendor|Other|$1" : $_[0] } } ]) or return;

    log::l("Xconfig::card: $r manually chosen");

    $r eq "Vendor|$card->{BoardName}" and return 1; #- it is unchanged, don't modify $card

    my ($kind, $s) = $r =~ /(.*?)\|(.*)/;

    %$card = ();
    if ($kind eq 'Vendor') {
	add_to_card__using_Cards($card, $s);
    } elsif ($kind eq 'XFree 3') {
	$card->{server} = $s;
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
    if (!$auto) {
	$tc = $in->ask_from_listf(N("Multi-head configuration"),
				  N("Your system supports multiple head configuration.
What do you want to do?"), sub { $_[0]{text} }, \@choices) or return;
    }
    $tc->{code} or die internal_error();
    return $tc->{code}();
}

sub configure_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;

    {
	my $card = $old_X->{card} || {};
	if ($card->{card_name}) {
	    #- try to get info from given card_name
	    add_to_card__using_Cards($card, $card->{card_name});
	    undef $card->{card_name} if !$card->{server} && !$card->{Driver}; #- bad card_name as we can't find the server
	}
	return if $card->{server} || $card->{Driver};
    }

    my @cards = probe();
    my ($choice) = multi_head_choices($old_X->{Xinerama}, @cards) or log::l('no graphic card probed, try providing one using $o->{card}{Driver} or $o->{card}{server} or $o->{card}{card_name}'), return;
    my $card = $choice->{code}();

    my ($glx_choice) = xfree_and_glx_choices($card);
    log::l("Using $glx_choice->{text}");
    $glx_choice->{code}();
    set_glx_restrictions($card);

    $card->{prog} = install_server($card, $options, $do_pkgs);
    if ($card->{needVideoRam} && !$card->{VideoRam}) {
	$card->{VideoRam} = $options->{VideoRam_probed} || 4096;
	log::l("argh, I need to know VideoRam! Taking " . ($options->{probed_VideoRam} ? "the probed" : "a default") . " value: VideoRam = $card->{VideoRam}");
    }
    to_raw_X($card, $raw_X);
    $card;
}

sub configure {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;

    my @cards = probe();
    @cards or @cards = {};

    if (!$cards[0]{server} && !$cards[0]{Driver}) {
	if ($options->{allowFB}) {
	    $cards[0]{Driver} = 'fbdev';
	} elsif ($auto) {
	    log::l("Xconfig::card: auto failed (unknown card and no allowFB)");
	    return 0;
	}
    }
    if (!$auto) {
	card_config__not_listed($in, $cards[0], $options) or return;
    }

    my $card = multi_head_choose($in, $auto, @cards) or return;

    xfree_and_glx_choose($in, $card, $auto) or return;

    if ($card->{card_name} eq 'Intel 865') {
	$raw_X->{xfree4}->get_Section('ServerFlags')->{DontVTSwitch} = [ { val => 'yes', Option => 1 } ];
    }

    $card->{prog} = install_server($card, $options, $do_pkgs);
    
    if ($card->{needVideoRam} && !$card->{VideoRam}) {
	if ($auto) {
	    log::l("Xconfig::card: auto failed (needVideoRam)");
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

    my $prog = server_binary($card);

    my @packages;
    push @packages, using_xf4($card) ? 'XFree86-server' : "XFree86-$card->{server}" if ! -x "$::prefix$prog";

    #- additional packages to install according available card.
    #- add XFree86-libs-DRI here if using DRI (future split of XFree86 TODO)
    if ($card->{use_DRI_GLX}) {
	push @packages, 'Glide_V5' if $card->{card_name} eq 'Voodoo5 (generic)';
	push @packages, 'Glide_V3-DRI' if member($card->{card_name}, 'Voodoo3 (generic)', 'Voodoo Banshee (generic)');
	push @packages, 'XFree86-glide-module' if $card->{card_name} =~ /Voodoo/;
    }
    if ($card->{use_UTAH_GLX}) {
	push @packages, 'Mesa';
    }
    #- 3D acceleration configuration for XFree 4 using NVIDIA driver (TNT, TN2 and GeForce cards only).
    push @packages, @{$options->{allowNVIDIA_rpms}} if $card->{Driver2} eq 'nvidia' && $options->{allowNVIDIA_rpms};

    $do_pkgs->install(@packages) if @packages;
    -x "$::prefix$prog" or die "server $card->{server} is not available (should be in $::prefix$prog)";

    #- make sure everything is correct at this point, packages have really been installed
    #- and driver and GLX extension is present.
    if ($card->{Driver2} eq 'nvidia' &&
	-e "$::prefix/usr/X11R6/lib/modules/drivers/nvidia_drv.o" &&
	-e "$::prefix/usr/X11R6/lib/modules/extensions/libglx.so") {
	log::l("Using specific NVIDIA driver and GLX extensions");
	$card->{Driver} = 'nvidia';
	$card->{DRI_GLX_SPECIAL} = 1;
    }

    if ($card->{need_MATROX_HAL}) {
	require Xconfig::proprietary;
	Xconfig::proprietary::install_matrox_hal($::prefix);
    }

    $prog;
}

sub xfree_and_glx_choose {
    my ($in, $card, $auto) = @_;

    my @choices = xfree_and_glx_choices($card);

    my $tc = 
      $auto ? $choices[0] :
	$in->ask_from_listf_raw({ title => N("XFree configuration"), 
				  messages => formatAlaTeX(join("\n\n\n", (grep { $_ } map { $_->{more_messages} } @choices),
								N("Which configuration of XFree do you want to have?"))), 
				  interactive_help_id => 'configureX_xfree_and_glx',
				},
				sub { $_[0]{text} }, \@choices) or return;
    log::l("Using $tc->{text}");
    $tc->{code}();
    set_glx_restrictions($card);
    1;
}

sub multi_head_choices {
    my ($want_Xinerama, @cards) = @_;
    my @choices;

    my $has_multi_head = @cards > 1 || @cards && $cards[0]{MULTI_HEAD} > 1;
    my $disable_multi_head = any { 
	$_->{Driver} or log::l("found card $_->{description} not supported by XF4, disabling multi-head support");
	!$_->{Driver};
    } @cards;

    if ($has_multi_head && !$disable_multi_head) {
	my $configure_multi_head = sub {

	    #- special case for multi head card using only one BusID.
	    @cards = map {
		map_index { { Screen => $::i, %$_ } } ($_) x ($_->{MULTI_HEAD} || 1);
	    } @cards;

	    delete $_->{server} foreach @cards; #- XFree 3 doesn't handle multi head (?)
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

#- XFree version available, it would be better to parse available package and get version from it.
sub xfree4_version { '4.3' }
sub xfree3_version { '3.3.6' }

sub xfree_and_glx_choices {
    my ($card) = @_;

    my $xf3 = if_($card->{server}, { text => N("XFree %s", xfree3_version()), code => sub { $card->{prefer_xf3} = 1 } });
    my $xf4 = if_($card->{Driver}, { text => N("XFree %s", xfree4_version()), code => sub { $card->{prefer_xf3} = 0 } });

    #- no XFree3 with multi-head
    my @choices = grep { $_ } ($card->{cards} ? $xf4 : $card->{prefer_xf3} ? ($xf3, $xf4) : ($xf4, $xf3));

    #- no GLX with Xinerama
    return @choices if $card->{Xinerama};

    #- try to figure if 3D acceleration is supported
    #- by XFree 3.3 but not XFree 4 then ask user to keep XFree 3.3 ?
    if ($card->{UTAH_GLX}) {
	my $e = { text => N("XFree %s with 3D hardware acceleration", xfree3_version()),
			    code => sub { $card->{prefer_xf3} = 1; $card->{use_UTAH_GLX} = 1 },
			    more_messages => ($card->{Driver} && !$card->{DRI_GLX} ?
N("Your card can have 3D hardware acceleration support but only with XFree %s.
Your card is supported by XFree %s which may have a better support in 2D.", xfree3_version(), xfree4_version()) :
N("Your card can have 3D hardware acceleration support with XFree %s.", xfree3_version())),
			  };
	$card->{prefer_xf3} ? unshift(@choices, $e) : push(@choices, $e);
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration, currenlty
    #- this is with Utah GLX and so, it can provide a way of testing.
    if ($card->{UTAH_GLX_EXPERIMENTAL} && $::expert) {
	push @choices, { text => N("XFree %s with EXPERIMENTAL 3D hardware acceleration", xfree3_version()),
			 code => sub { $card->{prefer_xf3} = 1; $card->{use_UTAH_GLX} = 1 },
			 more_messages => (using_xf4($card) && !$card->{DRI_GLX} ?
N("Your card can have 3D hardware acceleration support but only with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.
Your card is supported by XFree %s which may have a better support in 2D.", xfree3_version(), xfree4_version()) :
N("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", xfree3_version())),
		       };
    }

    #- ask the expert or any user on second pass user to enable or not hardware acceleration support.
    if ($card->{DRI_GLX}) {
	unshift @choices, { text => N("XFree %s with 3D hardware acceleration", xfree4_version()),
			    code => sub { $card->{prefer_xf3} = 0; $card->{use_DRI_GLX} = 1 },
			    more_messages => N("Your card can have 3D hardware acceleration support with XFree %s.", xfree4_version()),
			  };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration.
    if ($card->{DRI_GLX_EXPERIMENTAL} && $::expert) {
	push @choices, { text => N("XFree %s with EXPERIMENTAL 3D hardware acceleration", xfree4_version()),
			 code => sub { $card->{prefer_xf3} = 0; $card->{use_DRI_GLX} = 1 },
			 more_messages => N("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", xfree4_version()),
		       };
    }

    if (arch() =~ /ppc/ && $ENV{DISPLAY}) {
	push @choices, { text => N("Xpmac (installation display driver)"), code => sub { 
			     #- HACK: re-allowing XFree 3
			     $::force_xf4 = 0;
			     $card->{server} = "Xpmac";
			     $card->{prefer_xf3} = 1;
			 } };
    }
    @choices;
}

sub set_glx_restrictions {
    my ($card) = @_;

    #- hack for ATI Mach64 cards where two options should be used if using Utah-GLX.
    if (member($card->{card_name}, 'ATI Mach64 Utah', 'ATI Rage Mobility')) {
	$card->{Options_xfree3}{no_font_cache} = undef if $card->{use_UTAH_GLX};
	$card->{Options_xfree3}{no_pixmap_cache} = undef if $card->{use_UTAH_GLX};
    }
    #- hack for SiS cards where an option should be used if using Utah-GLX.
    if (member($card->{card_name}, 'SiS 6326', 'SiS 630')) {
	$card->{Options_xfree3}{no_pixmap_cache} = undef if $card->{use_UTAH_GLX};
    }

    #- 3D acceleration configuration for XFree 4 using DRI, this is enabled by default
    #- but for some there is a need to specify VideoRam (else it won't run).
    if ($card->{use_DRI_GLX}) {
	$card->{needVideoRam} = 1 if $card->{description} =~ /Matrox.* G[245][05]0/;
	($card->{needVideoRam}, $card->{VideoRam}) = (1, 16384)
	  if member($card->{card_name}, 'Intel 810', 'Intel 815');

	#- hack for ATI Rage 128 card using a bttv or peripheral with PCI bus mastering exchange
	#- AND using DRI at the same time.
	if (member($card->{card_name}, 'ATI Rage 128', 'ATI Rage 128 TVout', 'ATI Rage 128 Mobility')) {
	    $card->{Options_xfree4}{UseCCEFor2D} = bool2text(modules::probe_category('multimedia/tv'));
	}
    }

    #- check for Matrox G200 PCI cards, disable AGP in such cases, causes black screen else.
    if (member($card->{card_name}, 'Matrox Millennium 200', 'Matrox Millennium 200', 'Matrox Mystique') && $card->{description} !~ /AGP/) {
	log::l("disabling AGP mode for Matrox card, as it seems to be a PCI card");
	log::l("this is only used for XFree 3.3.6, see /etc/X11/glx.conf");
	substInFile { s/^\s*#*\s*mga_dma\s*=\s*\d+\s*$/mga_dma = 0\n/ } "$::prefix/etc/X11/glx.conf";
    }
}

sub add_to_card__using_Cards {
    my ($card, $name) = @_;
    my $cards = readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");
    add2hash($card, $cards->{$name});
    $card->{BoardName} = $card->{card_name};

    delete @$card{'server'} if $force_xf4;

    delete @$card{'UTAH_GLX', 'UTAH_GLX_EXPERIMENTAL'} 
      if $force_xf4 || availableRamMB() > 800; #- no Utah GLX if more than 800 Mb (server, or kernel-enterprise, Utha GLX does not work with latest).

    $card;
}

#- needed for bad cards not restoring cleanly framebuffer, according to which version of XFree are used.
sub check_bad_card {
    my ($card) = @_;
    my $bad_card = using_xf4($card) ? $card->{BAD_FB_RESTORE} : $card->{BAD_FB_RESTORE_XF3};
    $bad_card ||= $card->{Driver} eq 'i810' || $card->{Driver} eq 'fbdev';
    $bad_card ||= $card->{Driver} eq 's3virge' if $::live;
    $bad_card ||= $card->{Driver} eq 'nvidia' if !$::isStandalone; #- avoid testing during install at any price.
    $bad_card ||= $card->{server} =~ /FBDev|Sun/ if !using_xf4($card);

    log::l("the graphics card does not like X in framebuffer") if $bad_card;

    !$bad_card;
}

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = openFileMaybeCompressed($file);

    my ($lineno, $cmd, $val) = 0;
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
	SERVER => sub { $card->{server} = $val },
	DRIVER => sub { $card->{Driver} = $val },
	DRIVER2 => sub { $card->{Driver2} = $val },
	NEEDVIDEORAM => sub { $card->{needVideoRam} = 1 },
	DRI_GLX => sub { $card->{DRI_GLX} = 1 if $card->{Driver} },
	UTAH_GLX => sub { $card->{UTAH_GLX} = 1 if $card->{server} },
	DRI_GLX_EXPERIMENTAL => sub { $card->{DRI_GLX_EXPERIMENTAL} = 1 if $card->{Driver} },
	UTAH_GLX_EXPERIMENTAL => sub { $card->{UTAH_GLX_EXPERIMENTAL} = 1 if $card->{server} },
	MULTI_HEAD => sub { $card->{MULTI_HEAD} = $val if $card->{Driver} },
	BAD_FB_RESTORE => sub { $card->{BAD_FB_RESTORE} = 1 },
	BAD_FB_RESTORE_XF3 => sub { $card->{BAD_FB_RESTORE_XF3} = 1 },
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
1;
