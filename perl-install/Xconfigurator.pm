package Xconfigurator; # $Id$

use diagnostics;
use strict;
use vars qw($in $do_pkgs);

use common;
use log;
use detect_devices;
use run_program;
use Xconfigurator_consts;
use Xconfig;
use any;
use modules;

my $tmpconfig = "/tmp/Xconfig";
my $force_xf4 = arch() =~ /ppc|ia64/;


sub xtest {
    my ($display) = @_;
    $::isStandalone ? 
      system("DISPLAY=$display /usr/X11R6/bin/xtest") == 0 : 
      c::Xtest($display);    
}

sub using_xf4 {
    my ($card) = @_;
    $card->{driver} && !$card->{prefer_xf3};
}

sub readCardsNames {
    my $file = "$ENV{SHARE_PATH}/ldetect-lst/CardsNames";
    map { (split '=>')[0] } grep { !/^#/ } catMaybeCompressed($file);
}
sub cardName2RealName {
    my ($name) = @_;
    my $file = "$ENV{SHARE_PATH}/ldetect-lst/CardsNames";
    foreach (catMaybeCompressed($file)) {
	chop;
	next if /^#/;
	my ($name_, $real) = split '=>';
	return $real if $name eq $name_;
    }
    $name;
}
sub realName2CardName {
    my ($real) = @_;
    my $file = "$ENV{SHARE_PATH}/ldetect-lst/CardsNames";
    foreach (catMaybeCompressed($file)) {
	chop;
	next if /^#/;
	my ($name, $real_) = split '=>';
	return $name if $real eq $real_;
    }
    return;
}
sub updateCardAccordingName {
    my ($card, $name) = @_;
    my $cards = Xconfig::readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");
    Xconfig::add2card($card, $cards->{$name});

    delete @$card{'server'} if $force_xf4;

    delete @$card{'UTAH_GLX', 'UTAH_GLX_EXPERIMENTAL'} 
      if $force_xf4 || availableRamMB() > 800; #- no Utah GLX if more than 800 Mb (server, or kernel-enterprise, Utha GLX does not work with latest).

    $card->{prefer_xf3} = 1 if $card->{driver} eq 'neomagic' && !$force_xf4;

    $card;
}

sub readMonitorsDB {
    my ($file) = @_;

    my (%monitors, %standard_monitors);

    my $F = common::openFileMaybeCompressed($file);
    local $_;
    my $lineno = 0; while (<$F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(VendorName ModelName EISA_ID hsyncrange vsyncrange dpms);
	my @l = split /\s*;\s*/;

	my %l; @l{@fields} = @l;
	if ($monitors{$l{ModelName}}) {
	    my $i; for ($i = 0; $monitors{"$l{ModelName} ($i)"}; $i++) {}
	    $l{ModelName} = "$l{ModelName} ($i)";
	}
	$monitors{"$l{VendorName}|$l{ModelName}"} = \%l;
    }
    \%monitors;
}

sub keepOnlyLegalModes {
    my ($card, $monitor) = @_;
    my $mem = 1024 * ($card->{VideoRam} || ($card->{server} eq 'FBDev' ? 2048 : 32768)); #- limit to 2048x1536x64
    my $hsync = max(split(/[,-]/, $monitor->{hsyncrange}));

    while (my ($depth, $res) = each %{$card->{depth}}) {
	@$res = grep {
	    $mem >= product(@$_, $depth / 8) &&
	    $hsync >= ($Xconfigurator_consts::min_hsync4x_res{$_->[0]} || 0) &&
	    ($card->{server} ne 'FBDev' || (Xconfigurator_consts::bios_vga_modes($_->[0], $depth))[2] == $_->[1])
	} @$res;
	delete $card->{depth}{$depth} if @$res == 0;
    }
}

sub cardConfigurationAuto() {
#-for Pixel tests
#-    my @c = { driver => 'Card:Matrox Millennium G400 DualHead', description => 'Matrox|Millennium G400 Dual HeadCard' };
    my @c = grep { $_->{driver} =~ /(Card|Server|Driver):/ } detect_devices::probeall();

    my @cards = map {
	my @l = $_->{description} =~ /(.*?)\|(.*)/;
	my $card = { 
	    description => $_->{description},
	    VendorName => $l[0], BoardName => $l[1],
	    busid => "PCI:$_->{pci_bus}:$_->{pci_device}:$_->{pci_function}",
	};
	if    ($_->{driver} =~ /Card:(.*)/)   { updateCardAccordingName($card, $1) }
	elsif ($_->{driver} =~ /Server:(.*)/) { $card->{server} = $1 }
	elsif ($_->{driver} =~ /Driver:(.*)/) { $card->{driver} = $1 }
	else { internal_error() }
	
	$card;
    } @c;

    if (@cards >= 2 && $cards[0]{card_name} eq $cards[1]{card_name} && $cards[0]{card_name} eq 'Intel 830') {
	shift @cards;
    }
    #- take a default on sparc if nothing has been found.
    if (arch() =~ /^sparc/ && !@cards) {
        log::l("Using probe with /proc/fb as nothing has been found!");
	local $_ = cat_("/proc/fb");
	@cards = { server => /Mach64/ ? "Mach64" : /Permedia2/ ? "3DLabs" : "Sun24" };
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

    #- in case of only one cards, remove all busid reference, this will avoid
    #- need of change of it if the card is moved.
    #- on many PPC machines, card is on-board, busid is important, leave?
    if (@cards == 1 && arch() !~ /ppc/) {
	delete $cards[0]{busid};
    }

    @cards;
}

sub install_server {
    my ($card, $cardOptions) = @_;

    my $prog = "/usr/X11R6/bin/" . 
      (using_xf4($card) ? 'XFree86' : 
       $card->{server} =~ /Sun(.*)/ ? "Xsun$1" : 
       $card->{server} eq 'Xpmac' ? 'Xpmac' :
       "XF86_$card->{server}");

    my @packages = ();
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
    push @packages, @{$cardOptions->{allowNVIDIA_rpms}} if $card->{driver2} eq 'nvidia' && $cardOptions->{allowNVIDIA_rpms};

    $do_pkgs->install(@packages) if @packages;
    -x "$::prefix$prog" or die "server $card->{server} is not available (should be in $::prefix$prog)";

    #- make sure everything is correct at this point, packages have really been installed
    #- and driver and GLX extension is present.
    if ($card->{driver2} eq 'nvidia' &&
	-e "$::prefix/usr/X11R6/lib/modules/drivers/nvidia_drv.o" &&
	-e "$::prefix/usr/X11R6/lib/modules/extensions/libglx.so") {
	log::l("Using specific NVIDIA driver and GLX extensions");
	$card->{driver} = 'nvidia';
    }

    Xconfig::install_matrox_proprietary_hal($::prefix) if $card->{need_MATROX_HAL};

    $prog;
}

sub multi_head_config {
    my ($noauto, @cards) = @_;

    @cards > 1 || $cards[0]{MULTI_HEAD} > 1 or return $cards[0];

    my @choices;

    my $disable_multi_head = grep { 
	$_->{driver} or log::l("found card $_->{description} not supported by XF4, disabling multi-head support");
	!$_->{driver};
    } @cards;
    if (!$disable_multi_head) {
	my $configure_multi_head = sub {

	    #- special case for multi head card using only one busid.
	    @cards = map {
		map_index { { screen => $::i, %$_ } } ($_) x ($_->{MULTI_HEAD} || 1);
	    } @cards;

	    delete $_->{server} foreach @cards; #- XFree 3 doesn't handle multi head (?)
	    my $card = shift @cards; #- assume good default.
	    $card->{cards} = \@cards;
	    $card->{Xinerama} = $_[0];
	    $card;
	};
	push @choices, { text => _("Configure all heads independently"), code => sub { $configure_multi_head->('') } };
	push @choices, { text => _("Use Xinerama extension"), code => sub { $configure_multi_head->(1) } };
    }

    foreach my $c (@cards) {
	push @choices, { text => _("Configure only card \"%s\"%s", $c->{description}, $c->{busid} && " ($c->{busid})"),
			 code => sub { $c } };
    }
    my $tc = $in->ask_from_listf(_("Multi-head configuration"),
				 _("Your system support multiple head configuration.
What do you want to do?"), sub { $_[0]{text} }, \@choices) or return; #- no more die, CHECK with auto that return ''!

    $tc->{code} or die internal_error();
    return $tc->{code}();
}

sub xfree_and_glx_choices {
    my ($card) = @_;

    $card->{use_UTAH_GLX} = $card->{use_DRI_GLX} = 0;

    #- XFree version available, better to parse available package and get version from it.
    my ($xf4_ver, $xf3_ver) = ('4.2.0', '3.3.6');

    my @choices = do {
	#- basic installation, use of XFree 4.2 or XFree 3.3.
	my $xf3 = { text => _("XFree %s", $xf4_ver), code => sub { $card->{prefer_xf3} = 0 } };
	my $xf4 = { text => _("XFree %s", $xf3_ver), code => sub { $card->{prefer_xf3} = 1 } };
	$card->{prefer_xf3} ? ($xf3, $xf4) : ($xf4, $xf3);
    };

    #- try to figure if 3D acceleration is supported
    #- by XFree 3.3 but not XFree 4 then ask user to keep XFree 3.3 ?
    if ($card->{UTAH_GLX}) {
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf3_ver),
			    code => sub { $card->{prefer_xf3} = 1; $card->{use_UTAH_GLX} = 1 },
			    more_messages => ($card->{driver} && !$card->{DRI_GLX} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s.", $xf3_ver)),
			  };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration, currenlty
    #- this is with Utah GLX and so, it can provide a way of testing.
    if ($card->{UTAH_GLX_EXPERIMENTAL} && $::expert) {
	push @choices, { text => _("XFree %s with EXPERIMENTAL 3D hardware acceleration", $xf3_ver),
			 code => sub { $card->{prefer_xf3} = 1; $card->{use_UTAH_GLX} = 1 },
			 more_messages => (using_xf4($card) && !$card->{DRI_GLX} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", $xf3_ver)),
		       };
    }

    #- ask the expert or any user on second pass user to enable or not hardware acceleration support.
    if ($card->{DRI_GLX} && !$card->{Xinerama}) {
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf4_ver),
			    code => sub { $card->{prefer_xf3} = 0; $card->{use_DRI_GLX} = 1 },
			    more_messages => _("Your card can have 3D hardware acceleration support with XFree %s.", $xf4_ver),
			  };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration.
    if ($card->{DRI_GLX_EXPERIMENTAL} && !$card->{Xinerama} && $::expert) {
	push @choices, { text => _("XFree %s with EXPERIMENTAL 3D hardware acceleration", $xf4_ver),
			 code => sub { $card->{prefer_xf3} = 0; $card->{use_DRI_GLX} = 1 },
			 more_messages => _("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", $xf4_ver),
		       };
    }

    if (arch() =~ /ppc/ && $ENV{DISPLAY}) {
	push @choices, { text => _("Xpmac (installation display driver)"), code => sub { 
			     #- HACK: re-allowing XFree 3
			     $::force_xf4 = 0;
			     $card->{server} = "Xpmac";
			     $card->{prefer_xf3} = 1;
			 }};
    }
    @choices;
}
sub xfree_and_glx_choose {
    my ($card, $noauto) = @_;

    my @choices = xfree_and_glx_choices($card);

    @choices = $choices[0] if !$::expert && !$noauto;

    my $msg = join("\n\n\n", 
		   (grep {$_} map { $_->{more_messages} } @choices),
		   _("Which configuration of XFree do you want to have?"));
    #- examine choice of user, beware the list MUST NOT BE REORDERED AS the first item should be the
    #- proposed one by DrakX.
    my $tc = $in->ask_from_listf(_("XFree configuration"), formatAlaTeX($msg), sub { $_[0]{text} }, \@choices) or return;
    #- in case of class discarding, this can help ...
    $tc or $tc = $choices[0];
    log::l("Using $tc->{text}");
    $tc->{code} and $tc->{code}();
}

sub cardConfiguration {
    my ($card, $noauto, $cardOptions) = @_;

    #- using XF4 if {driver} && !{prefer_xf3} otherwise using XF3
    #- error if $force_xf4 && !{driver} || !{driver} && !{server}
    #- internal error if $force_xf4 && {prefer_xf3} || {prefer_xf3} && !{server}

    if ($card->{card_name}) {
	#- try to get info from given card_name
	updateCardAccordingName($card, $card->{card_name});
	undef $card->{card_name} if !$card->{server} && !$card->{driver}; #- bad card_name as we can't find the server
    }

    if (!$card->{server} && !$card->{driver} && !$noauto) {
	my @cards = cardConfigurationAuto();

	my $card_ = multi_head_config($noauto, @cards);
	put_in_hash($card, $card_);

	$card->{server} = 'FBDev' if $cardOptions->{allowFB} && !$card->{server} && !$card->{driver};
    }

    #- take into account current environment in standalone to keep
    #- the XFree86 version.
    if ($::isStandalone) {
	readlink("$::prefix/etc/X11/X") =~ /XFree86/ and $card->{prefer_xf3} = 0;
	readlink("$::prefix/etc/X11/X") =~ /XF86_/ and $card->{prefer_xf3} = !$force_xf4;
    }

    #- manage X 3.3.6 or above 4.2.0 specific server or driver.
    if (!$card->{server} && !$card->{driver} || $noauto) {
	undef $card->{card_name};

	my @xf3 = $cardOptions->{allowFB} ? @Xconfigurator_consts::allservers : @Xconfigurator_consts::allbutfbservers;
	my @xf4 = $cardOptions->{allowFB} ? @Xconfigurator_consts::alldrivers : @Xconfigurator_consts::allbutfbdrivers;
	my @list = (if_(!$force_xf4, map { 'XFree 3|' . $_ } @xf3), map { 'XFree 4|' . $_ } @xf4);

	my $default = $card->{prefer_xf3} ? 'XFree 3|' . $card->{server} : 'XFree 4|' . ($card->{driver} || 'fbdev');

	my $r = $in->ask_from_treelist(_("X server"), _("Choose a X server"), '|', \@list, $default) or return;

	my ($kind, $s) = split '\|', $r;

	if ($kind eq 'XFree 3') {
	    delete $card->{driver};
	    $card->{server} = $s;
	} else {
	    delete $card->{server};
	    $card->{driver} = $s;
	}
	$card->{prefer_xf3} = $kind eq 'XFree 3';
    }

    foreach ($card, @{$card->{cards} || []}) {
	$_->{VideoRam} = 4096,  delete $_->{depth} if $_->{driver} eq 'i810';
	$_->{VideoRam} = 16384, delete $_->{depth} if $_->{Chipset} =~ /PERMEDIA/ && $_->{VideoRam} <= 1024;
    }

    xfree_and_glx_choose($card, $noauto);

    $card->{prog} = install_server($card);

    #- check for Matrox G200 PCI cards, disable AGP in such cases, causes black screen else.
    if (member($card->{card_name}, 'Matrox Millennium 200', 'Matrox Millennium 200', 'Matrox Mystique') && $card->{description} !~ /AGP/) {
	log::l("disabling AGP mode for Matrox card, as it seems to be a PCI card");
	log::l("this is only used for XFree 3.3.6, see /etc/X11/glx.conf");
	substInFile { s/^\s*#*\s*mga_dma\s*=\s*\d+\s*$/mga_dma = 0\n/ } "$::prefix/etc/X11/glx.conf";
    }

    delete $card->{depth}{32} if $card->{card_name} =~ /S3 Trio3D|SiS/;
    $card->{options}{sw_cursor} = 1 if $card->{card_name} =~ /S3 Trio3D|SiS 6326/;
    $card->{options_xf3}{power_saver} = 1;
    $card->{options_xf4}{DPMS} = 'on';

    #- hack for ATI Mach64 cards where two options should be used if using Utah-GLX.
    if (member($card->{card_name}, 'ATI Mach64 Utah', 'ATI Rage Mobility')) {
	$card->{options_xf3}{no_font_cache} = $card->{use_UTAH_GLX};
	$card->{options_xf3}{no_pixmap_cache} = $card->{use_UTAH_GLX};
    }
    #- hack for SiS cards where an option should be used if using Utah-GLX.
    if (member($card->{card_name}, 'SiS 6326', 'SiS 630')) {
	$card->{options_xf3}{no_pixmap_cache} = $card->{use_UTAH_GLX};
    }

    #- 3D acceleration configuration for XFree 4 using DRI, this is enabled by default
    #- but for some there is a need to specify VideoRam (else it won't run).
    if ($card->{use_DRI_GLX}) {
	$card->{needVideoRam} = 1 if $card->{description} =~ /Matrox.* G[245][05]0/;
	($card->{needVideoRam}, $card->{VideoRam}) = (1, 16384)
	  if member($card->{card_name}, 'Intel 810', 'Intel 815');
	#- always enable (as a reminder for people using a better AGP mode to change it at their own risk).
	$card->{options_xf4}{AGPMode} = '1';
	#- hack for ATI Rage 128 card using a bttv or peripheral with PCI bus mastering exchange
	#- AND using DRI at the same time.
	if (member($card->{card_name}, 'ATI Rage 128', 'ATI Rage 128 Mobility')) {
	    $card->{options_xf4}{UseCCEFor2D} = (detect_devices::matching_desc('Bt8[47][89]') ||
						 detect_devices::matching_desc('TV') ||
						 detect_devices::matching_desc('AG GMV1')) ? 'true' : 'false';
	}
    }

    
    $in->ask_from('', _("Select the memory size of your graphics card"),
		  [ { val => \$card->{VideoRam},
		      list => [ sort keys %Xconfigurator_consts::VideoRams ],
		      format => sub { translate($Xconfigurator_consts::VideoRams{$_[0]}) },
		      not_edit => !$::expert } ]) or return
			if $card->{needVideoRam} && !$card->{VideoRam};


    1;
}

sub optionsConfiguration($) {
    my ($X) = @_;
    my @l;
    my %l;

    foreach (@Xconfigurator_consts::options) {
	if ($X->{card}{server} eq $_->[1] && $X->{card}{description} =~ /$_->[2]/) {
	    my $options = 'options_' . ($X->{card}{server} eq 'XFree86' ? 'xf4' : 'xf3');
	    $X->{card}{$options}{$_->[0]} ||= 0;
	    if (!$l{$_->[0]}) {
		push @l, { label => $_->[0], val => \$X->{card}{$options}{$_->[0]}, type => 'bool' };
		$l{$_->[0]} = 1;
	    }
	}
    }
    @l = @l[0..9] if @l > 9; #- reduce list size to 10 for display

    $in->ask_from('', _("Choose options for server"), \@l);
}

sub monitorConfiguration {
    my ($monitor, $noauto) = @_;

    my $monitors = readMonitorsDB("$ENV{SHARE_PATH}/ldetect-lst/MonitorsDB");

    if ($monitor->{EISA_ID}) {
	log::l("EISA_ID: $monitor->{EISA_ID}");
	if (my ($mon) = grep { lc($_->{EISA_ID}) eq $monitor->{EISA_ID} } values %$monitors) {
	    add2hash($monitor, $mon);
	    log::l("EISA_ID corresponds to: $monitor->{ModelName}");
	}
    }
    my $merged_name = $monitor->{VendorName} . '|' . $monitor->{ModelName};

    $merged_name = $Xconfigurator_consts::low_default_monitor
      if $::auto_install && !exists $monitors->{$merged_name};

    put_in_hash($monitor, $monitors->{$merged_name});

    if ($monitor->{hsyncrange} && $monitor->{vsyncrange} && !$noauto) {
	return 1;
    }

    #- below is interactive stuff

    if (!exists $monitors->{$merged_name}) {
	$merged_name = $monitor->{hsyncrange} ? 'Custom' : $Xconfigurator_consts::good_default_monitor;
    }

    $merged_name = $in->ask_from_treelistf(_("Monitor"), _("Choose a monitor"), '|', 
					   sub { $_[0] eq 'Custom' ? _("Custom") : $_[0] =~ /^Generic\|(.*)/ ? _("Generic") . "|$1" :  _("Vendor") . "|$_[0]" },
					   ['Custom', keys %$monitors], $merged_name) or return;

    if ($merged_name ne 'Custom') {
	put_in_hash($monitor, $monitors->{$merged_name});
    } else {
	$in->ask_from('',
_("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
		      [ { val => \$monitor->{hsyncrange}, list => \@Xconfigurator_consts::hsyncranges, label => _("Horizontal refresh rate"), not_edit => 0 },
			{ val => \$monitor->{vsyncrange}, list => \@Xconfigurator_consts::vsyncranges, label => _("Vertical refresh rate"), not_edit => 0 } ]) or return;
	delete @$monitor{'VendorName', 'ModelName', 'EISA_ID'};
    }
    1;
}

sub finalize_config {
    my ($X) = @_;

    $X->{monitor}{ModeLines_xf3} .= $Xconfigurator_consts::ModeLines_text_standard;
    $X->{monitor}{ModeLines_xf3} .= $Xconfigurator_consts::ModeLines_text_ext;
    $X->{monitor}{ModeLines}     .= $Xconfigurator_consts::ModeLines_text_ext;

    #- clean up duplicated ModeLines
    foreach ($X->{monitor}{ModeLines}, $X->{monitor}{ModeLines_xf3}) {
	s/Modeline/ModeLine/g; #- normalize
	my @l = reverse split "\n";
	my %seen;
	@l = grep {
	    !/^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+(.*)/ || !$seen{"$1 $2"}++;
	} @l;
	$_ = join("\n", reverse @l);
	s/^\n*/\n/; s/\n*$/\n/; #- have exactly one CR at beginning and end
    }

    $X->{keyboard}{XkbModel} ||= 
      arch() =~ /sparc/ ? 'sun' :
      $X->{keyboard}{XkbLayout} eq 'jp' ? 'jp106' : 
      $X->{keyboard}{XkbLayout} eq 'br' ? 'abnt2' : 'pc105';

}

sub check_config {
    my ($X) = @_;

    finalize_config($X);

    $X->{monitor}{hsyncrange} && $X->{monitor}{vsyncrange} or die _("Monitor not configured") . "\n";
    $X->{card}{server} || $X->{card}{driver} or die _("Graphics card not configured yet") . "\n";
    $X->{card}{depth} or die _("Resolutions not chosen yet") . "\n";
}

#- needed for bad cards not restoring cleanly framebuffer, according to which version of XFree are used.
sub check_bad_card {
    my ($card) = @_;
    my $bad_card = using_xf4($card) ? $card->{BAD_FB_RESTORE} : $card->{BAD_FB_RESTORE_XF3};
    $bad_card ||= $card->{driver} eq 'i810' || $card->{driver} eq 'fbdev';
    $bad_card ||= $card->{description} =~ /S3.*ViRGE/ if $::live;
    $bad_card ||= $card->{driver} eq 'nvidia' if !$::isStandalone; #- avoid testing during install at any price.

    log::l("the graphics card does not like X in framebuffer") if $bad_card;

    !$bad_card;
}

sub testFinalConfig {
    my ($X, $auto, $skiptest, $skip_badcard) = @_;

    my $f = "/etc/X11/XF86Config.test";
    
    eval { write_XF86Config($X, $::testing ? $tmpconfig : "$::prefix/$f") };
    if (my $err = $@) {
	$in->ask_warn('', $err);
	return;
    }

    $skiptest || $X->{card}{server} =~ 'FBDev|Sun' and return 1; #- avoid testing with these.

    check_bad_card($X->{card}) or return 1;

    $in->ask_yesorno(_("Test of the configuration"), _("Do you want to test the configuration?"), 1) or return 1 if !$auto;

    unlink "$::prefix/tmp/.X9-lock";

    #- create a link from the non-prefixed /tmp/.X11-unix/X9 to the prefixed one
    #- that way, you can talk to :9 without doing a chroot
    #- but take care of non X11 install :-)
    if (-d "/tmp/.X11-unix") {
	symlinkf "$::prefix/tmp/.X11-unix/X9", "/tmp/.X11-unix/X9" if $::prefix;
    } else {
	symlinkf "$::prefix/tmp/.X11-unix", "/tmp/.X11-unix" if $::prefix;
    }
    #- restart_xfs;

    my $f_err = "$::prefix/tmp/Xoutput";
    my $pid;
    unless ($pid = fork) {
	system("xauth add :9 . `mcookie`");
	open STDERR, ">$f_err";
	chroot $::prefix if $::prefix;
	exec $X->{card}{prog}, 
	  if_($X->{card}{prog} !~ /Xsun/, "-xf86config", ($::testing ? $tmpconfig : $f) . (using_xf4($X->{card}) && "-4")),
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until xtest(":9") || waitpid($pid, c::WNOHANG());

    my $b = before_leaving { unlink $f_err };

    if (!xtest(":9")) {
	local $_;
	local *F; open F, $f_err;
      i: while (<F>) {
	    if (using_xf4($X->{card})) {
		if (/^\(EE\)/ && !/Disabling/ || /^Fatal\b/) {
		    my @msg = !/error/ && $_ ;
		    while (<F>) {
			/reporting a problem/ and last;
			push @msg, $_;
			$in->ask_warn('', [ _("An error occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
			return 0;
		    }
		}
	    } else {
		if (/\b(error|not supported)\b/i) {
		    my @msg = !/error/ && $_ ;
		    while (<F>) {
			/not fatal/ and last i;
			/^$/ and last;
			push @msg, $_;
		    }
		    $in->ask_warn('', [ _("An error occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
		    return 0;
		}
	    }
	}
    }

    $::noShadow = 1;
    local *F;
    open F, "|perl 2>/dev/null" or die '';
    print F "use lib qw(", join(' ', @INC), ");\n";
    print F q{
        require lang;
	use interactive_gtk;
        use my_gtk qw(:wrappers);

        $::isStandalone = 1;

        lang::bindtextdomain();

	$ENV{DISPLAY} = ":9";

        gtkset_background(200 * 257, 210 * 257, 210 * 257);
        my ($h, $w) = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW)->get_size;
        $my_gtk::force_position = [ $w / 3, $h / 2.4 ];
	$my_gtk::force_focus = 1;
        my $text = Gtk::Label->new;
        my $time = 8;
        Gtk->timeout_add(1000, sub {
	    $text->set(_("Leaving in %d seconds", $time));
	    $time-- or Gtk->main_quit;
            1;
	});

        my $background = "/usr/share/pixmaps/backgrounds/linux-mandrake/XFdrake-image-test.jpg";
        my $qiv = "/usr/bin/qiv";
        -r "} . $::prefix . q{/$background" && -x "} . $::prefix . q{/$qiv" and
            system(($::testing ? "} . $::prefix . q{" : "chroot } . $::prefix . q{/ ") . "$qiv -y $background");

        my $in = interactive_gtk->new;
	$in->exit($in->ask_yesorno('', [ _("Is this the correct setting?"), $text ], 0) ? 0 : 222);
    };
    my $rc = close F;
    my $err = $?;

    unlink "/tmp/.X11-unix/X9" if $::prefix;
    kill 2, $pid;
    $::noShadow = 0;

    $rc || $err == 222 << 8 or $in->ask_warn('', _("An error occurred, try to change some parameters"));
    $rc;
}

sub allowedDepth($) {
    my ($card) = @_;
    my %allowed_depth;

    if ($card->{use_UTAH_GLX} || $card->{use_DRI_GLX}) {
	$allowed_depth{16} = 1; #- this is the default.
	$card->{description} =~ /Voodoo 5/ and $allowed_depth{24} = undef;
	$card->{description} =~ /Matrox.* G[245][05]0/ and $allowed_depth{24} = undef;
	$card->{description} =~ /Rage 128/ and $allowed_depth{24} = undef;
	$card->{description} =~ /Radeon/ and $allowed_depth{24} = undef;
    }
    
    for ($card->{server}) {
	#- this should work by default, FBDev is allowed only if install currently uses it at 16bpp.
	/FBDev/   and $allowed_depth{16} = 1;

	#- Sun servers, Sun24 handles 24,8,2; Sun only 8 and 2; and SunMono only 2.
	/^Sun24$/   and @allowed_depth{qw(24 8 2)} = (1);
	/^Sun$/     and @allowed_depth{qw(8 2)} = (1);
	/^SunMono$/ and @allowed_depth{qw(2)} = (1);
    }

    return %allowed_depth && \%allowed_depth; #- no restriction if false is returned.
}

sub autoDefaultDepth($$) {
    my ($card, $x_res_wanted) = @_;
    my ($best, $depth);

    #- check for forced depth according to current environment.
    my $allowed_depth = allowedDepth($card);
    if ($allowed_depth) {
	foreach (keys %$allowed_depth) {
	    $allowed_depth->{$_} and return $_; #- a default depth is given.
	}
    }

    while (my ($d, $r) = each %{$card->{depth}}) {
	$allowed_depth && ! exists $allowed_depth->{$d} and next; #- reject depth.
	$depth = max($depth || 0, $d);

	#- try to have resolution_wanted
	$best = max($best || 0, $d) if $r->[0][0] >= $x_res_wanted;
	$best = $card->{suggest_depth}, last if ($card->{suggest_depth} &&
						 $card->{suggest_x_res} && $r->[0][0] >= $card->{suggest_x_res});
    }
    $best || $depth or die "no valid modes";
}

sub autoDefaultResolution {
    #    return "1024x768" if detect_devices::hasPCMCIA;

    if (arch() =~ /ppc/) {
	return "1024x768" if detect_devices::get_mac_model =~ /^PowerBook|^iMac/;
    }
	
    my ($size) = @_;
    $Xconfigurator_consts::monitorSize2resolution[round($size || 14)] || #- assume a small monitor (size is in inch)
    $Xconfigurator_consts::monitorSize2resolution[-1]; #- no corresponding resolution for this size. It means a big monitor, take biggest we have
}

sub chooseResolutionsGtk($$;$) {
    my ($card, $chosen_depth, $chosen_w) = @_;

    require my_gtk;
    my_gtk->import(qw(:helpers :wrappers));

    my $W = my_gtk->new(_("Resolution"));
    my %txt2depth = reverse %Xconfigurator_consts::depths;
    my ($r, $depth_combo, %w2depth, %w2h, %w2widget, $pix_monitor, $pix_colors, $w2_combo);
    $w2_combo = new Gtk::Combo;
    my $best_w;
    my $allowed_depth = allowedDepth($card);
    my %allowed_depth;
    while (my ($depth, $res) = each %{$card->{depth}}) {
	$allowed_depth && ! exists $allowed_depth->{$depth} and next; #- reject depth.
	foreach (@$res) {
	    ++$allowed_depth{$depth};
	    $w2h{$_->[0]} = $_->[1];
	    push @{$w2depth{$_->[0]}}, $depth;

	    $best_w = max($_->[0], $best_w) if $_->[0] <= $chosen_w;
	}
    }
    $chosen_w = $best_w;
    $chosen_w ||= 640; #- safe guard ?

    my $set_depth = sub { $depth_combo->entry->set_text(translate($Xconfigurator_consts::depths{$chosen_depth})) };

    #- the set function is usefull to toggle the CheckButton with the callback being ignored
    my $ignore;
    my $no_human; # is the w2_combo->entry changed by a human?
    my $set = sub { $ignore = 1; $_[0] and $_[0]->set_active(1); $ignore = 0 };

    my %monitor;
    $monitor{$_} = [ gtkcreate_png("monitor-" . $_ . ".png") ] foreach (640, 800, 1024, 1280);
    $monitor{$_} = [ gtkcreate_png("monitor-" . 1024 . ".png") ] foreach (1152);
    #- add default icons for resolutions not taken into account (assume largest image available).
    $monitor{$_} ||= [ gtkcreate_png("monitor-" . 1280 . ".png") ] foreach map { (split 'x', $_)[0] } @Xconfigurator_consts::resolutions;

    my $pixmap_mo = new Gtk::Pixmap( $monitor{$chosen_w}[0]  , $monitor{$chosen_w}[1] );

    while (my ($w, $h) = each %w2h) {
	my $V = $w . "x" . $h;
	$w2widget{$w} = $r = new Gtk::RadioButton($r ? ($V, $r) : $V);
	if ($chosen_w == $w) {
	    &$set($r);
	}
	$r->signal_connect("clicked" => sub {
			       $ignore and return;
			       $chosen_w = $w;
			       $no_human=1;
			       $w2_combo->entry->set_text($w . "x" . $w2h{$w});
			       if (!member($chosen_depth, @{$w2depth{$w}})) {
				   $chosen_depth = max(@{$w2depth{$w}});
				   &$set_depth();
			       }
			   });
    }
    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(_("Choose the resolution and the color depth"),
					      "(" . ($card->{card_name} ? 
						     _("Graphics card: %s", $card->{card_name}) :
						     _("XFree86 server: %s", $card->{server})) . ")"
					     ),
		    1, gtkpack2(new Gtk::VBox(0,0),
				gtkpack2__(new Gtk::VBox(0, $::isEmbedded ? 15 : 0),
					   if_($::isEmbedded, $pixmap_mo),
					   if_(!$::isEmbedded, map {$w2widget{$_} } ikeys(%w2widget)),
					   gtkpack2(new Gtk::HBox(0,0),
						    create_packtable({ col_spacings => 5, row_spacings => 5},
	     [ if_($::isEmbedded,$w2_combo) , new Gtk::Label("")],
	     [ $depth_combo = new Gtk::Combo, gtkadd(gtkset_shadow_type(new Gtk::Frame, 'etched_out'), $pix_colors = gtkpng ("colors")) ],
							     ),
						   ),
					  ),
			       ),
		    0, gtkadd($W->create_okcancel(_("Ok"), _("More")),
			      $::isEmbedded ?
			      gtksignal_connect(new Gtk::Button(_("Expert Mode")), clicked => sub { system ("XFdrake --expert") }) :
			      gtksignal_connect(new Gtk::Button(_("Show all")), clicked => sub { $W->{retval} = 1; $chosen_w = 0; Gtk->main_quit })),
		    ));
    $depth_combo->disable_activate;
    $depth_combo->set_use_arrows_always(1);
    $depth_combo->entry->set_editable(0);
    $depth_combo->set_popdown_strings(map { translate($Xconfigurator_consts::depths{$_}) } grep { $Xconfigurator_consts::allowed_depth{$_} } ikeys(%{$card->{depth}}));
    $depth_combo->entry->signal_connect(changed => sub {
        $chosen_depth = $txt2depth{untranslate($depth_combo->entry->get_text, keys %txt2depth)};
        my $w = $card->{depth}{$chosen_depth}[0][0];
        $chosen_w > $w and &$set($w2widget{$chosen_w = $w});
	$pix_colors->set(gtkcreate_png(
               $chosen_depth >= 24 ? "colors.png" :
	       $chosen_depth >= 15 ? "colors16.png" :
	                             "colors8.png"));
    });
    if ($::isEmbedded) {
	$w2_combo->disable_activate;
	$w2_combo->set_use_arrows_always(1);
	$w2_combo->entry->set_editable(0);
	$w2_combo->set_popdown_strings(map { $_ . "x" . $w2h{$_} } keys %w2h);
	$w2_combo->entry->signal_connect(changed => sub {
	    ($chosen_w) = $w2_combo->entry->get_text =~ /([^x]*)x.*/;
	    $no_human ? $no_human=0 : $w2widget{$chosen_w}->set_active(1);
	    $pixmap_mo->set($monitor{$chosen_w}[0], $monitor{$chosen_w}[1]);
	});
    }
    &$set_depth();
    $W->{ok}->grab_focus;

    if ($::isEmbedded) {
	$no_human=1;
	$w2_combo->entry->set_text($chosen_w . "x" . $w2h{$chosen_w});
    }
    $W->main or return;
    ($chosen_depth, $chosen_w);
}

sub chooseResolutions($$;$) {
    goto &chooseResolutionsGtk if $in->isa('interactive_gtk');

    my ($card, $chosen_depth, $chosen_w) = @_;

    my $best_w;
    my $allowed_depth = allowedDepth($card);

    local $_ = $in->ask_from_list(_("Resolutions"), "", 
				  [ map_each { if_(!$allowed_depth || exists $allowed_depth->{$::a},
						   map { "$_->[0]x$_->[1] ${main::a}bpp" } @$::b) } %{$card->{depth}} ])
      or return;
    reverse /(\d+)x\S+ (\d+)/;
}


sub resolutionsConfiguration {
    my ($X, $auto) = @_;
    my $card = $X->{card};

    #- For the vga16 server, no further configuration is required.
    if ($card->{server} eq "VGA16") {
	$card->{depth}{8} = [[ 640, 480 ]];
	return;
    } elsif ($card->{server} =~ /Sun/) {
	$card->{depth}{2} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono)$/;
	$card->{depth}{8} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun)$/;
	$card->{depth}{24} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun|Sun24)$/;
	$card->{default_x_res} = 1152;
	$X->{default_depth} = max(keys %{$card->{depth}});
	return 1; #- aka we cannot test, assumed as good (should be).
    }
    if (is_empty_hash_ref($card->{depth})) {
	$card->{depth}{$_} = [ map { [ split "x" ] } @Xconfigurator_consts::resolutions ]
	  foreach @Xconfigurator_consts::depths;
    }
    #- sort resolutions in each depth
    foreach (values %{$card->{depth}}) {
	my $i = 0;
	@$_ = grep { first($i != $_->[0], $i = $_->[0]) }
	  sort { $b->[0] <=> $a->[0] } @$_;
    }

    #- remove unusable resolutions (based on the video memory size and the monitor hsync rate)
    keepOnlyLegalModes($card, $X->{monitor});

    my $res = $X->{resolution_wanted} || $card->{suggest_x_res} || autoDefaultResolution($X->{monitor}{size});
    my $x_res = first(split 'x', $res);

    #- take the first available resolution <= the wanted resolution
    eval { $x_res = max map { first(grep { $_->[0] <= $x_res } @$_)->[0] } values %{$card->{depth}} };
    my $depth = eval { $X->{default_depth} || autoDefaultDepth($card, $x_res) };

    $auto or ($depth, $x_res) = chooseResolutions($card, $depth, $x_res) or return;

    #- if nothing has been found for x_res,
    #- try to find if memory used by mode found match the memory available
    #- card, if this is the case for a relatively low resolution ( < 1024 ),
    #- there could be a problem.
    #- memory in KB is approximated by $x_res*$dpeth/14 which is little less
    #- than memory really used, (correct factor is 13.65333 for w/h ratio of 1.33333).
    if (!$x_res || $auto && ref($in) !~ /class_discard/ && ($x_res < 1024 && ($card->{VideoRam} / ($x_res * $depth / 14)) > 2)) {
	delete $card->{depth};
	return resolutionsConfiguration($X);
    }

    #- needed in auto mode when all has been provided by the user
    $card->{depth}{$depth} or die "you selected an unusable depth";

    #- remove all biggest resolution (keep the small ones for ctl-alt-+)
    #- otherwise there'll be a virtual screen :(
    $_ = [ grep { $_->[0] <= $x_res } @$_ ] foreach values %{$card->{depth}};
    $card->{default_x_res} = $x_res;
    $card->{bios_vga_mode} = (Xconfigurator_consts::bios_vga_modes($x_res, $depth))[0]; #- for use with frame buffer.
    $X->{default_depth} = $depth;
    1;
}

#- Create the XF86Config file.
sub write_XF86Config {
    my ($X, $file) = @_;
    my $O;

    check_config($X);

    $::g_auto_install and return;

    local (*F, *G);
    open F, ">$file"   or die "can't write XF86Config in $file: $!";
    open G, ">$file-4" or die "can't write XF86Config in $file-4: $!";

    print F $Xconfigurator_consts::XF86firstchunk_text;
    print G $Xconfigurator_consts::XF86firstchunk_text;

    #- Write keyboard section.
    $O = $X->{keyboard};

    print F '
Section "Keyboard"
    Protocol "Standard"
';
    print G '
Section "InputDevice"
    Identifier "Keyboard1"
    Driver "Keyboard"
';

    print F qq(    XkbDisable\n) if !$O->{XkbLayout};
    print G qq(    Option "XkbDisable"\n) if !$O->{XkbLayout};

    print F qq(    XkbModel "$O->{XkbModel}"\n);
    print G qq(    Option "XkbModel" "$O->{XkbModel}"\n);
    print F qq(    XkbLayout "$O->{XkbLayout}"\n);
    print G qq(    Option "XkbLayout" "$O->{XkbLayout}"\n);
    print F join '', map { "    $_\n" } @{$Xconfigurator_consts::XkbOptions{$O->{XkbLayout}} || []};
    print G join '', map { /(\S+)(.*)/; qq(    Option "$1" $2\n) } @{$Xconfigurator_consts::XkbOptions{$O->{XkbLayout}} || []};
    print F "EndSection\n";
    print G "EndSection\n";

    #- Write pointer section.
    my $pointer = sub {
	my ($O, $id) = @_;
	print F $id > 1 ? qq(\nSection "XInput"\n) : qq(\nSection "Pointer"\n);
	$id > 1 and print F qq(    SubSection "Mouse"\n);
	print G qq(\nSection "InputDevice"\n);
	$id > 1 and print F qq(        DeviceName "Mouse$id"\n);
	print G qq(    Identifier "Mouse$id"\n);
	print G qq(    Driver "mouse"\n);
	print F ($id > 1 && "    ") . qq(    Protocol "$O->{XMOUSETYPE}"\n);
	print G qq(    Option "Protocol" "$O->{XMOUSETYPE}"\n);
	print F ($id > 1 && "    ") . qq(    Device "/dev/$O->{device}"\n);
	print G qq(    Option "Device" "/dev/$O->{device}"\n);
	print F "        AlwaysCore\n" if $id > 1;
	#- this will enable the "wheel" or "knob" functionality if the mouse supports it
	print F ($id > 1 && "    ") . "    ZAxisMapping 4 5\n" if $O->{nbuttons} > 3;
	print F ($id > 1 && "    ") . "    ZAxisMapping 6 7\n" if $O->{nbuttons} > 5;
	print G qq(    Option "ZAxisMapping" "4 5"\n) if $O->{nbuttons} > 3;
	print G qq(    Option "ZAxisMapping" "6 7"\n) if $O->{nbuttons} > 5;

	print F "#" if $O->{nbuttons} >= 3;
	print G "#" if $O->{nbuttons} >= 3;
	print F ($id > 1 && "    ") . qq(    Emulate3Buttons\n);
	print G qq(    Option "Emulate3Buttons"\n);
	print F "#" if $O->{nbuttons} >= 3;
	print G "#" if $O->{nbuttons} >= 3;
	print F ($id > 1 && "    ") . qq(    Emulate3Timeout 50\n);
	print G qq(    Option "Emulate3Timeout" "50"\n);
	$id > 1 and print F qq(    EndSubSection\n);
	print F "EndSection\n";
	print G "EndSection\n";
    };
    $pointer->($X->{mouse}, 1);
    $pointer->($X->{mouse}{auxmouse}, 2) if $X->{mouse}{auxmouse};

    #- write module section for version 3.
    if (@{$X->{wacom}} || $X->{card}{use_UTAH_GLX}) {
	print F qq(\nSection "Module"\n);
	print F qq(    Load "xf86Wacom.so"\n) if @{$X->{wacom}};
	print F qq(    Load "glx-3.so"\n) if $X->{card}{use_UTAH_GLX}; #- glx.so may clash with server version 4.
	print F qq(EndSection\n);
    }

    #- write wacom device support.
    foreach (1 .. @{$X->{wacom}}) {
	my $dev = "/dev/" . $X->{wacom}[$_-1];
	print F $dev =~ /input\/event/ ? qq(
Section "XInput"
    SubSection "WacomStylus"
        Port "$dev"
        DeviceName "Stylus$_"
        USB
        AlwaysCore
        Mode Absolute
    EndSubSection
    SubSection "WacomCursor"
        Port "$dev"
        DeviceName "Cursor$_"
        USB
        AlwaysCore
        Mode Relative
    EndSubSection
    SubSection "WacomEraser"
        Port "$dev"
        DeviceName "Eraser$_"
        USB
        AlwaysCore
        Mode Absolute
    EndSubSection
EndSection
) : qq(
Section "XInput"
    SubSection "WacomStylus"
        Port "$dev"
        DeviceName "Stylus$_"
        AlwaysCore
        Mode Absolute
    EndSubSection
    SubSection "WacomCursor"
        Port "$dev"
        DeviceName "Sursor$_"
        AlwaysCore
        Mode Relative
    EndSubSection
    SubSection "WacomEraser"
        Port "$dev"
        DeviceName "Eraser$_"
        AlwaysCore
        Mode Absolute
    EndSubSection
EndSection
);
    }

    foreach (1..@{$X->{wacom}}) {
	my $dev = "/dev/" . $X->{wacom}[$_-1];
	print G $dev =~ m|input/event| ? qq(
Section "InputDevice"
    Identifier "Stylus$_"
    Driver "wacom"
    Option "Type" "stylus"
    Option "Device" "$dev"
    Option "Mode" "Absolute"
    Option "USB" "on"
EndSection
Section "InputDevice"
    Identifier "Eraser$_"
    Driver "wacom"
    Option "Type" "eraser"
    Option "Device" "$dev"
    Option "Mode" "Absolute"
    Option "USB" "on"
EndSection
Section "InputDevice"
    Identifier "Cursor$_"
    Driver "wacom"
    Option "Type" "cursor"
    Option "Device" "$dev"
    Option "Mode" "Relative"
    Option "USB" "on"
EndSection
) : qq(
Section "InputDevice"
    Identifier "Stylus$_"
    Driver "wacom"
    Option "Type" "stylus"
    Option "Device" "$dev"
    Option "Mode" "Absolute"
EndSection
Section "InputDevice"
    Identifier "Eraser$_"
    Driver "wacom"
    Option "Type" "eraser"
    Option "Device" "$dev"
    Option "Mode" "Absolute"
EndSection
Section "InputDevice"
    Identifier "Cursor$_"
    Driver "wacom"
    Option "Type" "cursor"
    Option "Device" "$dev"
    Option "Mode" "Relative"
EndSection
);
    }

    #- write modules section for version 4.
    print G qq(\nSection "Module"\n);
    print G qq(    Load "dbe" # Double-Buffering Extension\n);
    print G qq(    Load "v4l" # Video for Linux\n) if !($X->{card}{use_DRI_GLX} && $X->{card}{driver} eq 'r128');

    #- For example, this loads the NVIDIA GLX extension module.
    #- When DRI_GLX_SPECIAL is set, use_DRI_GLX is also set
    if ($X->{card}{DRI_GLX_SPECIAL}) {
	print G $X->{card}{DRI_GLX_SPECIAL};
    } elsif ($X->{card}{use_DRI_GLX}) {
	print G qq(    Load "dri" # direct rendering\n);
	print G qq(    Load "glx" # 3D layer\n);
    }
    print G qq(    Load "type1"\n);
    print G qq(    Load "freetype"\n);

    print G qq(EndSection\n);

    print G qq(
Section "DRI"
    Mode 0666
EndSection
) if $X->{card}{use_DRI_GLX};

    #- Write monitor section.
    $O = $X->{monitor};
    print F qq(\nSection "Monitor"\n);
    print G qq(\nSection "Monitor"\n);
    print F qq(    Identifier "monitor1"\n);
    print G qq(    Identifier "monitor1"\n);
    print F qq(    VendorName "$O->{VendorName}"\n) if $O->{VendorName};
    print G qq(    VendorName "$O->{VendorName}"\n) if $O->{VendorName};
    print F qq(    ModelName "$O->{ModelName}"\n) if $O->{ModelName};
    print G qq(    ModelName "$O->{ModelName}"\n) if $O->{ModelName};
    print F qq(    HorizSync $O->{hsyncrange}\n);
    print G qq(    HorizSync $O->{hsyncrange}\n);
    print F qq(    VertRefresh $O->{vsyncrange}\n);
    print G qq(    VertRefresh $O->{vsyncrange}\n);
    print F $O->{ModeLines_xf3} if $O->{ModeLines_xf3};
    print G $O->{ModeLines} if $O->{ModeLines};
    print F "EndSection\n";
    print G "EndSection\n";
    foreach (1..@{$X->{card}{cards} || []}) {
	print G qq(\nSection "Monitor"\n);
	print G qq(    Identifier "monitor), $_+1, qq("\n);
	print G qq(    HorizSync $O->{hsyncrange}\n);
	print G qq(    VertRefresh $O->{vsyncrange}\n);
	print G qq(EndSection\n);
    }

    #- Write Device section.
    $O = $X->{card};
    print F $Xconfigurator_consts::devicesection_text;
    print F qq(\nSection "Device"\n);
    print F qq(    Identifier "device1"\n);
    print F qq(    VendorName "$O->{VendorName}"\n) if $O->{VendorName};
    print F qq(    BoardName "$O->{BoardName}"\n) if $O->{BoardName};
    print F qq(    Chipset "$O->{Chipset}"\n) if $O->{Chipset};

    print F "#" if $O->{VideoRam} && !$O->{needVideoRam};
    print F "    VideoRam $O->{VideoRam}\n" if $O->{VideoRam};
    print F "\n";

    print F map { "    $_\n" } @{$O->{lines} || []};

    print F qq(    #Option "sw_cursor" # Uncomment following option if you see a big white block instead of the cursor!\n);

    my $p_xf3 = sub {
	my $l = $O->{$_[0]};
	map { (!$l->{$_} && '#') . qq(    Option "$_"\n) } keys %{$l || {}};
    };
    my $p_xf4 = sub {
	my $l = $O->{$_[0]};
	map { (! defined $l->{$_} && '#') . qq(    Option "$_" "$l->{$_}"\n) } keys %{$l || {}};
    };
    print F $p_xf3->('options');
    print F $p_xf3->('options_xf3');
    print F "EndSection\n";

    #- configure all drivers here!
    each_index {
	print G qq(\nSection "Device"\n);
	print G qq(    Identifier "device), $::i+1, qq("\n);
	print G qq(    VendorName "$_->{VendorName}"\n) if $_->{VendorName};
	print G qq(    BoardName "$_->{BoardName}"\n) if $_->{BoardName};
	print G qq(    Driver "$_->{driver}"\n);
	print G "#" if $_->{VideoRam} && !$_->{needVideoRam};
	print G "    VideoRam $_->{VideoRam}\n" if $_->{VideoRam};
	print G "\n";
	print G map { "    $_\n" } @{$_->{lines} || []};

	print G qq(    #Option "sw_cursor" # Uncomment following option if you see a big white block instead of the cursor!\n);

	print G $p_xf3->('options'); #- keep $O for these!
	print G $p_xf4->('options_xf4'); #- keep $O for these!
	print G qq(    Screen $_->{screen}\n) if defined $_->{screen};
	print G qq(    BusID "$_->{busid}"\n) if $_->{busid};
        if ((arch =~ /ppc/) && ($_->{driver} eq "r128")) {
            print G qq(    Option "UseFBDev"\n);
        }
	print G "EndSection\n";
    } $O, @{$O->{cards} || []};

    my $subscreen = sub {
	my ($f, $server, $defdepth, $depths) = @_;
	print $f "    DefaultColorDepth $defdepth\n" if $defdepth;

        foreach (ikeys(%$depths)) {
	    my $m = $server ne "fbdev" ? join(" ", map { qq("$_->[0]x$_->[1]") } @{$depths->{$_}}) : qq("default"); #-"
	    print $f qq(\n);
	    print $f qq(    Subsection "Display"\n);
	    print $f qq(        Depth $_\n) if $_;
	    print $f qq(        Modes $m\n);
	    print $f qq(    EndSubsection\n);
	}
	print $f "EndSection\n";
    };

    my $screen = sub {
	my ($server, $defdepth, $device, $depths) = @_;
	print F qq(
Section "Screen"
    Driver "$server"
    Device "$device"
    Monitor "monitor1"
); #-"
	$subscreen->(*F, $server, $defdepth, $depths);
    };

    &$screen("svga", $X->{default_depth}, 'device1', $O->{depth}) 
      if $O->{server} eq 'SVGA';

    &$screen("accel", $X->{default_depth}, 'device1', $O->{depth})
      if $Xconfigurator_consts::serversdriver{$O->{server}} eq 'accel';

    &$screen("fbdev", $X->{default_depth}, 'device1', $O->{depth});

    &$screen("vga16", '', "Generic VGA", { '' => [[ 640, 480 ], [ 800, 600 ]]});

    foreach (1 .. 1 + @{$O->{cards} || []}) {
	print G qq(
Section "Screen"
    Identifier "screen$_"
    Device "device$_"
    Monitor "monitor$_"
);
	#- bpp 32 not handled by XF4
	$subscreen->(*G, "svga", min($X->{default_depth}, 24), $O->{depth});
    }

    print G qq(
Section "ServerLayout"
    Identifier "layout1"
    Screen "screen1"
);
    foreach (1..@{$O->{cards} || []}) {
	my ($curr, $prev) = ($_ + 1, $_);
	print G qq(    Screen "screen$curr" RightOf "screen$prev"\n);
    }
    print G '#' if defined $O->{Xinerama} && !$O->{Xinerama};
    print G qq(    Option "Xinerama" "on"\n) if defined $O->{Xinerama};

    print G qq(    InputDevice "Mouse1" "CorePointer"\n);
    print G qq(    InputDevice "Mouse2" "SendCoreEvents"\n) if $X->{mouse}{auxmouse};

    foreach (1..@{$X->{wacom}}) {
	print G qq(
    InputDevice "Stylus$_" "AlwaysCore"
    InputDevice "Eraser$_" "AlwaysCore"
    InputDevice "Cursor$_" "AlwaysCore"
);
    }
    print G qq(    InputDevice "Keyboard1" "CoreKeyboard"\n);
    print G "EndSection\n";

    close F;
    close G;
}

sub show_info {
    my ($X) = @_;
    $in->ask_warn('', Xconfig::info($X));
}

#- Program entry point.
sub main {
    (my $X, $in, $do_pkgs, my $cardOptions) = @_;
    $X ||= {};

    Xconfig::XF86check_link($::prefix, '');
    Xconfig::XF86check_link($::prefix, '-4');

    my $ok = 1;
    {
	my $w = $in->wait_message('', _("Preparing X-Window configuration"), 1);

	$ok &&= cardConfiguration($X->{card} ||= {}, $::noauto, $cardOptions);

	$ok &&= monitorConfiguration($X->{monitor} ||= {}, $::noauto);
    }
    $ok &&= resolutionsConfiguration($X, $::auto);

    $ok &&= testFinalConfig($X, $::auto, $X->{skiptest}, $::auto);

    my $quit;
    until ($ok || $quit) {
	ref($in) =~ /discard/ and die "automatic X configuration failed, ensure you give hsyncrange and vsyncrange with non-DDC aware videocards/monitors";

	$in->set_help('configureXmain') if !$::isStandalone;

	my $f;
	$in->ask_from_(
		{ 
		 title => 'XFdrake',
		 messages => _("What do you want to do?"),
		 cancel => '',
		}, [
		    { format => sub { $_[0][0] }, val => \$f,
		      list => [
	   [ _("Change Monitor") => sub { monitorConfiguration($X->{monitor}, 'noauto') } ],
           [ _("Change Graphics card") => sub { cardConfiguration($X->{card}, 'noauto', $cardOptions) } ],
                    if_($::expert, 
           [ _("Change Server options") => sub { optionsConfiguration($X) } ]),
	   [ _("Change Resolution") => sub { resolutionsConfiguration($X) } ],
	   [ _("Show information") => sub { show_info($X) } ],
	   [ _("Test again") => sub { $ok = testFinalConfig($X, 1) } ],
	   [ _("Quit") => sub { $quit = 1 } ],
			       ],
		    }
		   ]);
	$f->[1]->();
	$in->kill;
    }
    if (!$ok) {
	$ok = $in->ask_yesorno('', _("Keep the changes?
The current configuration is:

%s", Xconfig::info($X)));
    }
    if ($ok) {
	if (!$::testing) {
	    my $f = "$::prefix/etc/X11/XF86Config";
	    if (-e "$f.test") {
		rename $f, "$f.old" or die "unable to make a backup of XF86Config";
		rename "$f-4", "$f-4.old";
		rename "$f.test", $f if $X->{card}{server};
		rename "$f.test-4", "$f-4" if $X->{card}{driver};
		symlinkf "../..$X->{card}{prog}", "$::prefix/etc/X11/X" if $X->{card}{server} !~ /Xpmac/;
	    }
	}

	if (!$::isStandalone || $0 !~ /Xdrakres/) {
	    $in->set_help('configureXxdm') if !$::isStandalone;
	    my $run = exists $X->{xdm} ? $X->{xdm} : $::auto || $in->ask_yesorno(_("Graphical interface at startup"),
_("I can setup your computer to automatically start the graphical interface (XFree) upon booting.
Would you like XFree to start when you reboot?"), 1);
	    any::runlevel($::prefix, $run ? 5 : 3) if !$::testing;
	}
	if ($::isStandalone && $in->isa('interactive_gtk')) {
	    if (my $wm = any::running_window_manager()) {
		if ($in->ask_okcancel('', _("Please relog into %s to activate the changes", ucfirst (lc $wm)), 1)) {
		    fork and $in->exit;
		    any::ask_window_manager_to_logout($wm);

		    open STDIN, "</dev/zero";
		    open STDOUT, ">/dev/null";
		    open STDERR, ">&STDERR";
		    c::setsid();
		    exec qw(perl -e), q{
                        my $wm = shift;
  		        for (my $nb = 30; $nb && `pidof "$wm"` > 0; $nb--) { sleep 1 }
  		        system("killall X ; killall -15 xdm gdm kdm prefdm") if !(`pidof "$wm"` > 0);
  		    }, $wm;
		}
	    } else {
		$in->ask_warn('', _("Please log out and then use Ctrl-Alt-BackSpace"));
	    }
	} 
    }
}

1;
