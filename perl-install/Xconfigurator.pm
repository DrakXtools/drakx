package Xconfigurator; # $Id$

use diagnostics;
use strict;
use vars qw($in $do_pkgs @window_managers @depths @monitorSize2resolution @hsyncranges %min_hsync4wres @vsyncranges %depths @resolutions %serversdriver @svgaservers @accelservers @allbutfbservers @allservers @allbutfbdrivers @alldrivers %vgamodes %videomemory @ramdac_name @ramdac_id @clockchip_name @clockchip_id %keymap_translate %standard_monitors $XF86firstchunk_text $keyboardsection_start $keyboardsection_start_v4 $keyboardsection_part2 $keyboardsection_part3 $keyboardsection_part3_v4 $keyboardsection_end $pointersection_text $monitorsection_text1 $monitorsection_text2 $monitorsection_text3 $monitorsection_text4 $modelines_text_Trident_TG_96xx $modelines_text_ext $modelines_text $devicesection_text $devicesection_text_v4 $screensection_text1 %lines @options %xkb_options $good_default_monitor $low_default_monitor $layoutsection_v4 $modelines_text_apple);

use common;
use log;
use detect_devices;
use run_program;
use Xconfigurator_consts;
use any;
use modules;

my $tmpconfig = "/tmp/Xconfig";

my ($prefix, %monitors, %standard_monitors_);


sub xtest {
    my ($display) = @_;
    $::isStandalone ? 
      system("DISPLAY=$display /usr/X11R6/bin/xtest") == 0 : 
      c::Xtest($display);    
}

sub getVGAMode($) { $_[0]->{card}{vga_mode} || $vgamodes{"640x480x16"}; }

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = common::openFileMaybeCompressed($file);

    my ($lineno, $cmd, $val) = 0;
    my $fs = {
        LINE => sub { push @{$card->{lines}}, $val unless $val eq "VideoRam" },
	NAME => sub {
	    $cards{$card->{type}} = $card if $card;
	    $card = { type => $val };
	},
	SEE => sub {
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";

	    push @{$card->{lines}}, @{$c->{lines} || []};
	    add2hash($card->{flags}, $c->{flags});
	    add2hash($card, $c);
	},
	CHIPSET => sub {
	    $card->{chipset} = $val;
	    $card->{flags}{needChipset} = 1 if $val eq 'GeForce DDR';
	    $card->{flags}{needVideoRam} = 1 if member($val, qw(mgag10 mgag200 RIVA128 SiS6326));
	},
	SERVER => sub { $card->{server} = $val; },
	DRIVER => sub { $card->{driver} = $val; },
	RAMDAC => sub { $card->{ramdac} = $val; },
	DACSPEED => sub { $card->{dacspeed} = $val; },
	CLOCKCHIP => sub { $card->{clockchip} = $val; $card->{flags}{noclockprobe} = 1; },
	NOCLOCKPROBE => sub { $card->{flags}{noclockprobe} = 1 },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	COMMENT => sub {},
    };

    local $_;
    while (<$F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and do { $cards{$card->{type}} = $card if $card; last };

	($cmd, $val) = /(\S+)\s*(.*)/ or next; #log::l("bad line $lineno ($_)"), next;

	my $f = $fs->{$cmd};

	$f ? $f->() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
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
    my $cards = readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");

    add2hash($card->{flags}, $cards->{$name}{flags});
    add2hash($card, $cards->{$name});
    $card;
}

sub readMonitorsDB {
    my ($file) = @_;

    %monitors and return;

    my $F = common::openFileMaybeCompressed($file);
    local $_;
    my $lineno = 0; while (<$F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(vendor type eisa hsyncrange vsyncrange dpms);
	my @l = split /\s*;\s*/;

	my %l; @l{@fields} = @l;
	if ($monitors{$l{type}}) {
	    my $i; for ($i = 0; $monitors{"$l{type} ($i)"}; $i++) {}
	    $l{type} = "$l{type} ($i)";
	}
	$monitors{"$l{vendor}|$l{type}"} = \%l;
    }
    while (my ($k, $v) = each %standard_monitors) {
	$monitors{'Generic|' . translate($k)} = $standard_monitors_{$k} = 
	  { hsyncrange => $v->[1], vsyncrange => $v->[2] };
    }
}

sub keepOnlyLegalModes {
    my ($card, $monitor) = @_;
    my $mem = 1024 * ($card->{memory} || ($card->{server} eq 'FBDev' ? 2048 : 32768)); #- limit to 2048x1536x64
    my $hsync = max(split(/[,-]/, $monitor->{hsyncrange}));

    while (my ($depth, $res) = each %{$card->{depth}}) {
	@$res = grep {
	    $mem >= product(@$_, $depth / 8) &&
	    $hsync >= ($min_hsync4wres{$_->[0]} || 0) &&
	    ($card->{server} ne 'FBDev' || $vgamodes{"$_->[0]x$_->[1]x$depth"})
	} @$res;
	delete $card->{depth}{$depth} if @$res == 0;
    }
}

sub cardConfigurationAuto() {
    my @cards;
    if (my @c = grep { $_->{driver} =~ /(Card|Server):/ } detect_devices::probeall()) {
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
}

sub cardConfiguration(;$$$) {
    my ($card, $noauto, $cardOptions) = @_;
    $card ||= {};

    updateCardAccordingName($card, $card->{type}) if $card->{type}; #- try to get info from given type
    undef $card->{type} unless $card->{server} || $card->{driver}; #- bad type as we can't find the server
    my @cards = cardConfigurationAuto();
    if (@cards > 1 && ($noauto || !$card->{server})) {#} && !$::isEmbedded) {
	my (%single_heads, @choices, $tc);
	my $configure_multi_head = sub {
	    add2hash($card, $cards[0]); #- assume good default.
	    delete $card->{cards} if $noauto;
	    $card->{cards} or $card->{cards} = \@cards;
	    $card->{force_xf4} = 1; #- force XF4 in such case.
	    $card->{Xinerama} = $_[0];
	};
	foreach (@cards) {
	    unless ($_->{driver} && !$_->{flags}{unsupported}) {
		log::l("found card \"$_->{identifier}\" not supported by XF4, disabling mutli-head support");
		$configure_multi_head = undef;
	    }
	    #- if more than one card use the same BusID, we have to use screen.
	    if ($single_heads{$_->{busid}}) {
		$single_heads{$_->{busid}}{screen} ||= 0;
		$_->{screen} = $single_heads{$_->{busid}}{screen} + 1;
	    }
	    $single_heads{$_->{busid}} = $_;
	}
	if ($configure_multi_head) {
	    push @choices, { text => _("Configure all heads independently"), code => sub { $configure_multi_head->('') } };
	    push @choices, { text => _("Use Xinerama extension"), code => sub { $configure_multi_head->(1) } };
	}
	foreach my $e (values %single_heads) {
	    push @choices, { text => _("Configure only card \"%s\" (%s)", $e->{identifier}, $e->{busid}),
			     code => sub { add2hash($card, $e); foreach (qw(cards screen Xinerama)) { delete $card->{$_} } } };
	}
	$tc = $in->ask_from_listf(_("Multi-head configuration"),
_("Your system support multiple head configuration.
What do you want to do?"), sub { translate($_[0]{text}) }, \@choices) or return; #- no more die, CHECK with auto that return ''!
	$tc->{code} and $tc->{code}();
    } else {
	#- only one head found, configure it as before.
	add2hash($card, $cards[0]) unless $noauto;
	delete $card->{cards}; delete $card->{Xinerama};
    }
    $card->{server} = 'FBDev' unless !$cardOptions->{allowFB} || $card->{server} || $card->{driver} || $card->{type} || $noauto;

    my $currentRealName = realName2CardName($card->{type} || $cards[0]{type}) || 'Other|Unlisted';
    $card->{type} = cardName2RealName($in->ask_from_treelist(_("Graphic card"),
							     _("Select a graphic card"), '|', ['Other|Unlisted', readCardsNames()],
							     $currentRealName))
      or return unless $card->{type} || $card->{server} || $card->{driver};

    updateCardAccordingName($card, $card->{type}) if $card->{type};
    add2hash($card, { vendor => "Unknown", board => "Unknown" });

    #- check to use XFree 4 or XFree 3.3.
    $card->{use_xf4} = $card->{driver} && !$card->{flags}{unsupported};
    $card->{force_xf4} ||= arch() =~ /ppc|ia64/; #- try to figure out ugly hack for PPC (recommend XF4 always so...)
    $card->{prefer_xf3} = !$card->{force_xf4} && ($card->{type} =~ /NeoMagic /);
    #- take into account current environment in standalone to keep
    #- the XFree86 version.
    if ($::isStandalone) {
	readlink("$prefix/etc/X11/X") =~ /XFree86/ and $card->{prefer_xf3} = 0;
	readlink("$prefix/etc/X11/X") =~ /XF86_/ and $card->{prefer_xf3} = !$card->{force_xf4};
    }

    #- manage X 3.3.6 or above 4.2.0 specific server or driver.
    if ($card->{type} eq 'Other|Unlisted') {
	undef $card->{type};

	my @list = ('server', $cardOptions->{allowFB} ? @allservers : @allbutfbservers);
	my $default_server = if_(!$card->{use_xf4} || $card->{prefer_xf3}, $card->{server} || $cards[0]{server}) || 'server';
	$card->{server} = $in->ask_from_list(_("X server"), _("Choose a X server"), \@list, $default_server) or return;

	if ($card->{server} eq 'server') {
	    my $fake_card = {};
	    updateCardAccordingName($fake_card, $cards[0]{type}) if $cards[0]{type};
	    $card->{server} = $card->{prefer_xf3} = undef;
	    $card->{use_xf4} = $card->{force_xf4} = 1;
	    $card->{driver} = $in->ask_from_list(_("X driver"), _("Choose a X driver"),
						 ($cardOptions->{allowFB} ? \@alldrivers : \@allbutfbdrivers),
						 $card->{driver} || $fake_card->{driver} || $cards[0]{driver}) or return;
	} else {
	    $card->{driver} = $card->{use_xf4} = $card->{force_xf4} = undef;
	    $card->{prefer_xf3} = 1;
	}
    }

    foreach ($card, @{$card->{cards} || []}) {
	$_->{memory} = 4096,  delete $_->{depth} if $_->{driver} eq 'i810';
	$_->{memory} = 16384, delete $_->{depth} if $_->{chipset} =~ /PERMEDIA/ && $_->{memory} <= 1024;
    }
    #- 3D acceleration configuration for XFree 3.3 using Utah-GLX.
    $card->{Utah_glx} = ($card->{identifier} =~ /Matrox.* G[24]00/ || #- 8bpp does not work.
			 $card->{identifier} =~ /Rage X[CL]/ ||
			 $card->{identifier} =~ /3D Rage (?:LT|Pro)/);
                         #- NOT WORKING $card->{type} =~ /Intel 810/);
    $card->{Utah_glx} = '' if arch() =~ /ppc/; #- No 3D XFree 3.3 for PPC
    #- 3D acceleration configuration for XFree 3.3 using Utah-GLX but EXPERIMENTAL that may freeze the machine (FOR INFO NOT USED).
    $card->{Utah_glx_EXPERIMENTAL} = ($card->{identifier} =~ /[nN]Vidia.*T[nN]T2?/ || #- all RIVA/GeForce comes from NVIDIA ...
				      $card->{identifier} =~ /[nN]Vidia.*NV[56]/ ||   #- and may freeze (gltron).
				      $card->{identifier} =~ /[nN]Vidia.*Vanta/ ||
				      $card->{identifier} =~ /[nN]Vidia.*GeForce/ ||
				      $card->{identifier} =~ /[nN]Vidia.*NV1[15]/ ||
				      $card->{identifier} =~ /[nN]Vidia.*Quadro/ ||
				      $card->{identifier} =~ /Riva.*128/ || # moved here as not working correctly enough
				      $card->{identifier} =~ /S3.*Savage.*3D/ || #- only this one is evoluting.
				      $card->{identifier} =~ /Rage Mobility [PL]/ ||
				      $card->{identifier} =~ /SiS.*6C?326/ || #- prefer 16bit, other ?
				      $card->{identifier} =~ /SiS.*6C?236/ ||
				      $card->{identifier} =~ /SiS.*630/);
    #- 3D acceleration configuration for XFree 4 using DRI.
    $card->{DRI_glx} = ($card->{identifier} =~ /Voodoo [35]|Voodoo Banshee/ || #- 16bit only
			$card->{identifier} =~ /Matrox.* G[245][05]0/ || #- prefer 16bit with AGP only
			$card->{identifier} =~ /8281[05].* CGC/ || #- 16bits (Intel 810 & 815).
			$card->{identifier} =~ /Radeon / || #- 16bits preferable ?
			$card->{identifier} =~ /Rage 128|Rage Mobility M/) && #- 16 and 32 bits, prefer 16bit as no DMA.
			  !($card->{identifier} =~ /Radeon 8500/); #- remove Radeon 8500 wich doesn't work with DRI (4.2).
    #- 3D acceleration configuration for XFree 4 using DRI but EXPERIMENTAL that may freeze the machine (FOR INFO NOT USED).
    $card->{DRI_glx_EXPERIMENTAL} = ($card->{identifier} =~ /SiS.*6C?326/ || #- prefer 16bit, other ?
				     $card->{identifier} =~ /SiS.*6C?236/ ||
				     $card->{identifier} =~ /SiS.*630/);
    #- 3D acceleration configuration for XFree 4 using NVIDIA driver (TNT, TN2 and GeForce cards only).
    $card->{NVIDIA_glx} = $cardOptions->{allowNVIDIA_rpms} && ($card->{identifier} =~ /[nN]Vidia.*T[nN]T2/ || #- TNT2 cards
							       $card->{identifier} =~ /[nN]Vidia.*NV[56]/ ||
							       $card->{identifier} =~ /[nN]Vidia.*Vanta/ ||
							       $card->{identifier} =~ /[nN]Vidia.*GeForce/ || #- GeForce cards
							       $card->{identifier} =~ /[nN]Vidia.*NV1[15]/ ||
							       $card->{identifier} =~ /[nN]Vidia.*Quadro/);

    #- hack for SiS 640 for laptop.
    if ($card->{identifier} =~ /SiS.*640/ and detect_devices::isLaptop()) {
	$card->{use_xf4} = $card->{force_xf4} = '';
	$card->{prefer_xf3} = 1;
	$card->{server} = 'FBDev';
    }

    #- XFree version available, better to parse available package and get version from it.
    my ($xf4_ver, $xf3_ver) = ("4.2.0", "3.3.6");
    #- basic installation, use of XFree 4.2 or XFree 3.3.
    my $xf3_tc = { text => _("XFree %s", $xf3_ver),
		   code => sub { $card->{Utah_glx} = $card->{DRI_glx} = $card->{NVIDIA_glx} = ''; $card->{use_xf4} = '';
				 log::l("Using XFree $xf3_ver") } };
    my $msg = _("Which configuration of XFree do you want to have?");
    my @choices = $card->{use_xf4} ? (if_($card->{prefer_xf3}, $xf3_tc),
				      if_(!$card->{prefer_xf3} || $::expert || $noauto, 
					  { text => _("XFree %s", $xf4_ver),
					    code => sub { $card->{Utah_glx} = $card->{DRI_glx} = $card->{NVIDIA_glx} = '';
							  log::l("Using XFree $xf4_ver") } }),
				      if_(!$card->{prefer_xf3} && !$card->{force_xf4} && ($::expert || $noauto), $xf3_tc)) : $xf3_tc;
    #- try to figure if 3D acceleration is supported
    #- by XFree 3.3 but not XFree 4 then ask user to keep XFree 3.3 ?
    if ($card->{Utah_glx} && !$card->{force_xf4}) {
	$msg = ($card->{use_xf4} && !($card->{DRI_glx} || $card->{NVIDIA_glx}) && !$card->{prefer_xf3} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s.", $xf3_ver)) . "\n\n\n" . $msg;
	$::expert || $noauto or @choices = (); #- keep it by default here as it is the only choice available.
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf3_ver),
			    code => sub { $card->{use_xf4} = '';
					  log::l("Using XFree $xf3_ver with 3D hardware acceleration") } };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration.
    if ($::expert && $card->{use_xf4} && $card->{DRI_glx_EXPERIMENTAL} && !$card->{Xinerama}) {
	$msg =
_("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", $xf4_ver) . "\n\n\n" . $msg;
	push @choices, { text => _("XFree %s with EXPERIMENTAL 3D hardware acceleration", $xf4_ver),
			 code => sub { $card->{DRI_glx} = 'EXPERIMENTAL';
				       log::l("Using XFree $xf4_ver with EXPERIMENTAL 3D hardware acceleration") } };
    }

    #- an expert user may want to try to use an EXPERIMENTAL 3D acceleration, currenlty
    #- this is with Utah GLX and so, it can provide a way of testing.
    if ($::expert && $card->{Utah_glx_EXPERIMENTAL} && !$card->{force_xf4}) {
	$msg = ($card->{use_xf4} && !($card->{DRI_glx} || $card->{NVIDIA_glx}) && !$card->{prefer_xf3} ?
_("Your card can have 3D hardware acceleration support but only with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.
Your card is supported by XFree %s which may have a better support in 2D.", $xf3_ver, $xf4_ver) :
_("Your card can have 3D hardware acceleration support with XFree %s,
NOTE THIS IS EXPERIMENTAL SUPPORT AND MAY FREEZE YOUR COMPUTER.", $xf3_ver)) . "\n\n\n" . $msg;
	push @choices, { text => _("XFree %s with EXPERIMENTAL 3D hardware acceleration", $xf3_ver),
			 code => sub { $card->{use_xf4} = ''; $card->{Utah_glx} = 'EXPERIMENTAL';
				       log::l("Using XFree $xf3_ver with EXPERIMENTAL 3D hardware acceleration") } };
    }

    #- ask the expert or any user on second pass user to enable or not hardware acceleration support.
    if ($card->{use_xf4} && ($card->{DRI_glx} || $card->{NVIDIA_glx}) && !$card->{Xinerama}) {
	$msg = _("Your card can have 3D hardware acceleration support with XFree %s.", $xf4_ver) . "\n\n\n" . $msg;
	$::expert || $noauto or @choices = (); #- keep all user by default with XFree 4 including 3D acceleration.
	unshift @choices, { text => _("XFree %s with 3D hardware acceleration", $xf4_ver),
			    code => sub { log::l("Using XFree $xf4_ver with 3D hardware acceleration") } };
    }
    if (arch() =~ /ppc/) {
	#- not much choice for PPC - we only have XF4, and Xpmac from the installer   
	@choices = { text => _("XFree %s", $xf4_ver), code => sub { $card->{xpmac} = ''; log::l("Using XFree $xf4_ver") } };
	push @choices, { text => _("Xpmac (installation display driver)"), code => sub { $card->{xpmac} = 1 }} if ($ENV{DISPLAY});
    }
    #- examine choice of user, beware the list MUST NOT BE REORDERED AS the first item should be the
    #- proposed one by DrakX.
    my $tc = $in->ask_from_listf(_("XFree configuration"), formatAlaTeX($msg), sub { translate($_[0]{text}) }, \@choices) or return;
    #- in case of class discarding, this can help ...
    $tc or $tc = $choices[0];
    $tc->{code} and $tc->{code}();
    
    if ($card->{xpmac} eq "1") {
	log::l("Use Xpmac - great...");
	#- define this stuff just so XF86Config isn't empty - we don't need it for Xpmac
	$card->{type} = "Xpmac Frame Buffer Driver";
	$card->{vendor} = $card->{board} = "None";
	$card->{driver} = $card->{server} = "Xpmac";
    }
    	
    $card->{prog} = "/usr/X11R6/bin/" . ($card->{use_xf4} ? 'XFree86' : $card->{server} =~ /Sun(.*)/ ?
					 "Xsun$1" : "XF86_$card->{server}");

    #- additional packages to install according available card.
    #- add XFree86-libs-DRI here if using DRI (future split of XFree86 TODO)
    my @l = ();
    if ($card->{DRI_glx}) {
	push @l, 'Glide_V5' if $card->{identifier} =~ /Voodoo 5/;
	push @l, 'Glide_V3-DRI' if $card->{identifier} =~ /Voodoo (3|Banshee)/;
	push @l, 'XFree86-glide-module' if $card->{identifier} =~ /Voodoo/;
    } elsif ($card->{NVIDIA_glx}) {
	push @l, @{$cardOptions->{allowNVIDIA_rpms}};
    }
    if ($card->{Utah_glx}) {
	push @l, 'Mesa' if !$card->{use_xf4};
    }
    if ($card->{xpmac} eq "1") {
	push @l, 'XFree86-Xpmac';
	$card->{use_xf4} = '';
	$card->{prog} = "/usr/X11R6/bin/Xpmac";
	$card->{server} = 'Xpmac';
    }

    unless ($::g_auto_install) {
	-x "$prefix$card->{prog}" or $do_pkgs->install($card->{use_xf4} ? 'XFree86-server' : "XFree86-$card->{server}", @l);
	-x "$prefix$card->{prog}" or die "server $card->{server} is not available (should be in $prefix$card->{prog})";
    }

    #- check for Matrox G200 PCI cards, disable AGP in such cases, causes black screen else.
    if ($card->{identifier} =~ /Matrox.* G[24]00/ && $card->{identifier} !~ /AGP/) {
	log::l("disabling AGP mode for Matrox card, as it seems to be a PCI card");
	log::l("this is only used for XFree 3.3.6, see /etc/X11/glx.conf");
	substInFile { s/^\s*#*\s*mga_dma\s*=\s*\d+\s*$/mga_dma = 0\n/ } "$prefix/etc/X11/glx.conf";
    }
    #- make sure everything is correct at this point, packages have really been installed
    #- and driver and GLX extension is present.
    if ($card->{NVIDIA_glx} && !$card->{DRI_glx} && (-e "$prefix/usr/X11R6/lib/modules/drivers/nvidia_drv.o" &&
						     -e "$prefix/usr/X11R6/lib/modules/extensions/libglx.so")) {
	log::l("Using specific NVIDIA driver and GLX extensions");
	$card->{driver} = 'nvidia';
	foreach (@{$cardOptions->{allowNVIDIA_rpms}}) { #- hack as NVIDIA_kernel package does not do it actually (8.1 OEM).
	    if (/NVIDIA_kernel-([^\-]*)-([^\-]*)(?:-(.*))?/ && -e "$prefix/boot/System.map-$1-$2$3") {
		run_program::rooted($prefix, "/sbin/depmod", "-a", "-F", "/boot/System.map-$1-$2$3", "$1-$2$3");
	    }
	}
    } else {
	$card->{NVIDIA_glx} = '';
    }

    delete $card->{depth}{32} if $card->{type} =~ /S3 Trio3D|SiS/;
    $card->{options}{sw_cursor} = 1 if $card->{type} =~ /S3 Trio3D|SiS 6326/;
    unless ($card->{type}) {
	$card->{flags}{noclockprobe} = member($card->{server}, qw(I128 S3 S3V Mach64));
    }
    $card->{options_xf3}{power_saver} = 1;
    $card->{options_xf4}{DPMS} = 'on';

    $card->{flags}{needVideoRam} and
      $card->{memory} ||= $videomemory{$in->ask_from_list_('', _("Select the memory size of your graphic card"),
							   [ sort { $videomemory{$a} <=> $videomemory{$b} }
							     keys %videomemory]) || return};

    #- hack for ATI Mach64 cards where two options should be used if using Utah-GLX.
    if ($card->{identifier} =~ /Rage X[CL]/ ||
	$card->{identifier} =~ /Rage Mobility [PL]/ ||
	$card->{identifier} =~ /3D Rage (?:LT|Pro)/) {
	$card->{options_xf3}{no_font_cache} = $card->{Utah_glx};
	$card->{options_xf3}{no_pixmap_cache} = $card->{Utah_glx};
    }
    #- hack for SiS cards where an option should be used if using Utah-GLX.
    if ($card->{identifier} =~ /SiS.*6C?326/ ||
	$card->{identifier} =~ /SiS.*6C?236/ ||
	$card->{identifier} =~ /SiS.*630/) {
	$card->{options_xf3}{no_pixmap_cache} = $card->{Utah_glx};
    }

    #- 3D acceleration configuration for XFree 4 using DRI, this is enabled by default
    #- but for some there is a need to specify VideoRam (else it won't run).
    if ($card->{DRI_glx}) {
	$card->{identifier} =~ /Matrox.* G[245][05]0/ and $card->{flags}{needVideoRam} = 'fakeVideoRam';
	$card->{identifier} =~ /8281[05].* CGC/ and ($card->{flags}{needVideoRam}, $card->{memory}) = ('fakeVideoRam', 16384);
	#- always enable (as a reminder for people using a better AGP mode to change it at their own risk).
	$card->{options_xf4}{AGPMode} = '1';
	#- hack for ATI Rage 128 card using a bttv or peripheral with PCI bus mastering exchange
	#- AND using DRI at the same time.
	if ($card->{identifier} =~ /Rage 128|Rage Mobility M/) {
	    $card->{options_xf4}{UseCCEFor2D} = (detect_devices::matching_desc('Bt8[47][89]') ||
						 detect_devices::matching_desc('TV') ||
						 detect_devices::matching_desc('AG GMV1')) ? 'true' : 'false';
	}
    }

    $card;
}

sub optionsConfiguration($) {
    my ($o) = @_;
    my @l;
    my %l;

    foreach (@options) {
	if ($o->{card}{server} eq $_->[1] && $o->{card}{identifier} =~ /$_->[2]/) {
	    my $options = 'options_' . ($o->{card}{server} eq 'XFree86' ? 'xf4' : 'xf3');
	    $o->{card}{$options}{$_->[0]} ||= 0;
	    unless ($l{$_->[0]}) {
		push @l, { label => $_->[0], val => \$o->{card}{$options}{$_->[0]}, type => 'bool' };
		$l{$_->[0]} = 1;
	    }
	}
    }
    @l = @l[0..9] if @l > 9; #- reduce list size to 10 for display

    $in->ask_from('', _("Choose options for server"), \@l);
}

sub monitorConfiguration(;$$) {
    my $monitor = shift || {};
    my $useFB = shift || 0;

    readMonitorsDB("$ENV{SHARE_PATH}/ldetect-lst/MonitorsDB");

    if ($monitor->{EISA_ID}) {
	log::l("EISA_ID: $monitor->{EISA_ID}");
	if (my ($mon) = grep { lc($_->{eisa}) eq $monitor->{EISA_ID} } values %monitors) {
	    add2hash($monitor, $mon);
	    log::l("EISA_ID corresponds to: $monitor->{type}");
	}
    }
    if ($monitor->{hsyncrange} && $monitor->{vsyncrange}) {
	add2hash($monitor, { type => "monitor1", vendor => "Unknown", model => "Unknown" });
	return $monitor;
    }

    my $good_default = (arch() =~ /ppc/ ? 'Apple|' : 'Generic|') . translate($good_default_monitor);
    $monitor->{type} ||=
      ($::auto_install ? $low_default_monitor :
       $in->ask_from_treelist(_("Monitor"), _("Choose a monitor"), '|', ['Custom', keys %monitors], $good_default));
    if ($monitor->{type} eq 'Custom') {
	$in->ask_from('',
_("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
				  [ { val => \$monitor->{hsyncrange}, list => \@hsyncranges, label => _("Horizontal refresh rate"), not_edit => 0 },
				    { val => \$monitor->{vsyncrange}, list => \@vsyncranges, label => _("Vertical refresh rate"), not_edit => 0 } ]);
    } else {
	add2hash($monitor, $monitors{$monitor->{type}} || $standard_monitors_{$monitor->{type}});
    }
    add2hash($monitor, { type => "Unknown", vendor => "Unknown", model => "Unknown", manual => 1 });
}

sub testConfig($) {
    my ($o) = @_;
    my ($resolutions, $clocklines);

    write_XF86Config($o, $tmpconfig);

    unlink "/tmp/.X9-lock";
    #- restart_xfs;

    my $f = $tmpconfig . ($o->{card}{use_xf4} && "-4");
    local *F; open F, "$prefix$o->{card}{prog} :9 -probeonly -pn -xf86config $f 2>&1 |";
    local $_;
    while (<F>) {
	$o->{card}{memory} ||= $2 if /(videoram|Video RAM):\s*(\d*)/;

	# look for clocks
	push @$clocklines, $1 if /clocks: (.*)/ && !/(pixel |num)clocks:/;

	push @$resolutions, [ $1, $2 ] if /: Mode "(\d+)x(\d+)": mode clock/;
	print;
    }
    close F or die "X probeonly failed";

    ($resolutions, $clocklines);
}

sub testFinalConfig {
    my ($o, $auto, $skiptest, $skip_badcard) = @_;

    $o->{monitor}{hsyncrange} && $o->{monitor}{vsyncrange} or
      $in->ask_warn('', _("Monitor not configured")), return;

    $o->{card}{server} || $o->{card}{driver} or
      $in->ask_warn('', _("Graphic card not configured yet")), return;

    $o->{card}{depth} or
      $in->ask_warn('', _("Resolutions not chosen yet")), return;

    my $f = "/etc/X11/XF86Config.test";
    write_XF86Config($o, $::testing ? $tmpconfig : "$prefix/$f");

    $skiptest || $o->{card}{server} =~ 'FBDev|Sun' and return 1; #- avoid testing with these.

    #- needed for bad cards not restoring cleanly framebuffer, according to which version of XFree are used.
    my $bad_card = ($o->{card}{use_xf4} ?
		    $o->{card}{identifier} =~ /Matrox|SiS.*SG86C2.5|SiS.*559[78]|SiS.*300|SiS.*540|SiS.*6C?326|SiS.*6C?236|Tseng.*ET6\d00|Riva.*128/ :
		    $o->{card}{identifier} =~ /i740|Rage Mobility [PL]|3D Rage LT|Rage 128/);
    $::live and $bad_card ||= $o->{card}{identifier} =~ /S3.*ViRGE/;
    log::l("the graphic card does not like X in framebuffer") if $bad_card;

    my $verybad_card = $o->{card}{driver} eq 'i810' || $o->{card}{driver} eq 'fbdev';
    $verybad_card ||= $o->{card}{driver} eq 'nvidia' && !$::isStandalone; #- avoid testing during install at any price.
    $bad_card || $verybad_card and return 1; #- deactivating bad_card test too.

    my $mesg = _("Do you want to test the configuration?");
    my $def = 1;
    if ($bad_card && !$::isStandalone) {
	$skip_badcard and return 1;
	$mesg = $mesg . "\n" . _("Warning: testing this graphic card may freeze your computer");
	$def = 0;
    }
    $auto && $def or $in->ask_yesorno(_("Test of the configuration"), $mesg, $def) or return 1;

    unlink "$prefix/tmp/.X9-lock";

    #- create a link from the non-prefixed /tmp/.X11-unix/X9 to the prefixed one
    #- that way, you can talk to :9 without doing a chroot
    #- but take care of non X11 install :-)
    if (-d "/tmp/.X11-unix") {
	symlinkf "$prefix/tmp/.X11-unix/X9", "/tmp/.X11-unix/X9" if $prefix;
    } else {
	symlinkf "$prefix/tmp/.X11-unix", "/tmp/.X11-unix" if $prefix;
    }
    #- restart_xfs;

    my $f_err = "$prefix/tmp/Xoutput";
    my $pid;
    unless ($pid = fork) {
	system("xauth add :9 . `mcookie`");
	open STDERR, ">$f_err";
	chroot $prefix if $prefix;
	exec $o->{card}{prog}, 
	  if_($o->{card}{prog} !~ /Xsun/, "-xf86config", ($::testing ? $tmpconfig : $f) . ($o->{card}{use_xf4} && "-4")),
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until xtest(":9") || waitpid($pid, c::WNOHANG());

    my $b = before_leaving { unlink $f_err };

    unless (xtest(":9")) {
	local $_;
	local *F; open F, $f_err;
      i: while (<F>) {
	    if ($o->{card}{use_xf4}) {
		if (/^\(EE\)/ && $_ !~ /Disabling/ || /^Fatal\b/) {
		    my @msg = !/error/ && $_ ;
		    while (<F>) {
			/reporting a problem/ and last;
			push @msg, $_;
			$in->ask_warn('', [ _("An error has occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
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
		    $in->ask_warn('', [ _("An error has occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
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
        -r "} . $prefix . q{/$background" && -x "} . $prefix . q{/$qiv" and
            system(($::testing ? "} . $prefix . q{" : "chroot } . $prefix . q{/ ") . "$qiv -y $background");

        my $in = interactive_gtk->new;
	$in->exit($in->ask_yesorno('', [ _("Is this the correct setting?"), $text ], 0) ? 0 : 222);
    };
    my $rc = close F;
    my $err = $?;

    unlink "/tmp/.X11-unix/X9" if $prefix;
    kill 2, $pid;
    $::noShadow = 0;

    $rc || $err == 222 << 8 or $in->ask_warn('', _("An error has occurred, try to change some parameters"));
    $rc;
}

sub allowedDepth($) {
    my ($card) = @_;
    my %allowed_depth;

    if ($card->{Utah_glx} || $card->{DRI_glx}) {
	$allowed_depth{16} = 1; #- this is the default.
	$card->{identifier} =~ /Voodoo 5/ and $allowed_depth{24} = undef;
	$card->{identifier} =~ /Matrox.* G[245][05]0/ and $allowed_depth{24} = undef;
	$card->{identifier} =~ /Rage 128/ and $allowed_depth{24} = undef;
	$card->{identifier} =~ /Radeon/ and $allowed_depth{24} = undef;
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
    my ($card, $wres_wanted) = @_;
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
	$best = max($best || 0, $d) if $r->[0][0] >= $wres_wanted;
	$best = $card->{suggest_depth}, last if ($card->{suggest_depth} &&
						 $card->{suggest_wres} && $r->[0][0] >= $card->{suggest_wres});
    }
    $best || $depth or die "no valid modes";
}

sub autoDefaultResolution {
    #    return "1024x768" if detect_devices::hasPCMCIA;

    if (arch() =~ /ppc/) {
	return "1024x768" if detect_devices::get_mac_model =~ /^PowerBook|^iMac/;
    }
	
    my ($size) = @_;
    $monitorSize2resolution[round($size || 14)] || #- assume a small monitor (size is in inch)
    $monitorSize2resolution[-1]; #- no corresponding resolution for this size. It means a big monitor, take biggest we have
}

sub chooseResolutionsGtk($$;$) {
    my ($card, $chosen_depth, $chosen_w) = @_;

    require my_gtk;
    my_gtk->import(qw(:helpers :wrappers));

    my $W = my_gtk->new(_("Resolution"));
    my %txt2depth = reverse %depths;
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

    my $set_depth = sub { $depth_combo->entry->set_text(translate($depths{$chosen_depth})) };

    #- the set function is usefull to toggle the CheckButton with the callback being ignored
    my $ignore;
    my $no_human; # is the w2_combo->entry changed by a human?
    my $set = sub { $ignore = 1; $_[0] and $_[0]->set_active(1); $ignore = 0; };

    my %monitor;
    $monitor{$_} = [ gtkcreate_png("monitor-" . $_ . ".png") ] foreach (640, 800, 1024, 1280);
    $monitor{1152} = [ gtkcreate_png("monitor-" . 1024 . ".png") ];
    $monitor{1600} = [ gtkcreate_png("monitor-" . 1280 . ".png") ];

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
			       unless (member($chosen_depth, @{$w2depth{$w}})) {
				   $chosen_depth = max(@{$w2depth{$w}});
				   &$set_depth();
			       }
			   });
    }
    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(_("Choose the resolution and the color depth"),
					      "(" . ($card->{type} ? 
						     _("Graphic card: %s", $card->{type}) :
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
			      gtksignal_connect(new Gtk::Button(_("Expert Mode")), clicked => sub { system ("XFdrake --expert"); }) :
			      gtksignal_connect(new Gtk::Button(_("Show all")), clicked => sub { $W->{retval} = 1; $chosen_w = 0; Gtk->main_quit })),
		    ));
    $depth_combo->disable_activate;
    $depth_combo->set_use_arrows_always(1);
    $depth_combo->entry->set_editable(0);
    $depth_combo->set_popdown_strings(map { translate($depths{$_}) } grep { $allowed_depth{$_} } ikeys(%{$card->{depth}}));
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
    my ($o, $auto) = @_;
    my $card = $o->{card};

    #- For the mono and vga16 server, no further configuration is required.
    if (member($card->{server}, "Mono", "VGA16")) {
	$card->{depth}{8} = [[ 640, 480 ]];
	return;
    } elsif ($card->{server} =~ /Sun/) {
	$card->{depth}{2} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono)$/;
	$card->{depth}{8} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun)$/;
	$card->{depth}{24} = [[ 1152, 864 ]] if $card->{server} =~ /^(SunMono|Sun|Sun24)$/;
	$card->{default_wres} = 1152;
	$o->{default_depth} = max(keys %{$card->{depth}});
	return 1; #- aka we cannot test, assumed as good (should be).
    }
    if (is_empty_hash_ref($card->{depth})) {
	$card->{depth}{$_} = [ map { [ split "x" ] } @resolutions ]
	  foreach @depths;
    }
    #- sort resolutions in each depth
    foreach (values %{$card->{depth}}) {
	my $i = 0;
	@$_ = grep { first($i != $_->[0], $i = $_->[0]) }
	  sort { $b->[0] <=> $a->[0] } @$_;
    }

    #- remove unusable resolutions (based on the video memory size and the monitor hsync rate)
    keepOnlyLegalModes($card, $o->{monitor});

    my $res = $o->{resolution_wanted} || $card->{suggest_wres} || autoDefaultResolution($o->{monitor}{size});
    my $wres = first(split 'x', $res);

    #- take the first available resolution <= the wanted resolution
    eval { $wres = max map { first(grep { $_->[0] <= $wres } @$_)->[0] } values %{$card->{depth}} };
    my $depth = eval { $o->{default_depth} || autoDefaultDepth($card, $wres) };

    $auto or ($depth, $wres) = chooseResolutions($card, $depth, $wres) or return;

    #- if nothing has been found for wres,
    #- try to find if memory used by mode found match the memory available
    #- card, if this is the case for a relatively low resolution ( < 1024 ),
    #- there could be a problem.
    #- memory in KB is approximated by $wres*$dpeth/14 which is little less
    #- than memory really used, (correct factor is 13.65333 for w/h ratio of 1.33333).
    if (!$wres || $auto && ref($in) !~ /class_discard/ && ($wres < 1024 && ($card->{memory} / ($wres * $depth / 14)) > 2)) {
	delete $card->{depth};
	return resolutionsConfiguration($o);
    }

    #- needed in auto mode when all has been provided by the user
    $card->{depth}{$depth} or die "you selected an unusable depth";

    #- remove all biggest resolution (keep the small ones for ctl-alt-+)
    #- otherwise there'll be a virtual screen :(
    $_ = [ grep { $_->[0] <= $wres } @$_ ] foreach values %{$card->{depth}};
    $card->{default_wres} = $wres;
    $card->{vga_mode} = $vgamodes{"${wres}xx$depth"} || $vgamodes{"${res}x$depth"}; #- for use with frame buffer.
    $o->{default_depth} = $depth;
    1;
}


#- Create the XF86Config file.
sub write_XF86Config {
    my ($o, $file) = @_;
    my $O;

    $::g_auto_install and return;

    local (*F, *G);
    open F, ">$file"   or die "can't write XF86Config in $file: $!";
    open G, ">$file-4" or die "can't write XF86Config in $file-4: $!";

    print F $XF86firstchunk_text;
    print G $XF86firstchunk_text;

    #- Write keyboard section.
    $O = $o->{keyboard};
    print F $keyboardsection_start;
    print G $keyboardsection_start_v4;
    print F qq(    XkbDisable\n) unless $O->{xkb_keymap};
    print G qq(    Option "XkbDisable"\n) unless $O->{xkb_keymap};
    print F $keyboardsection_part3;
    print G $keyboardsection_part3_v4;

    $O->{xkb_model} ||= 
      arch() =~ /sparc/ ? 'sun' :
      $O->{xkb_keymap} eq 'jp' ? 'jp106' : 
      $O->{xkb_keymap} eq 'br' ? 'abnt2' : 'pc105';
    print F qq(    XkbModel        "$O->{xkb_model}"\n);
    print G qq(    Option "XkbModel" "$O->{xkb_model}"\n);

    print F qq(    XkbLayout       "$O->{xkb_keymap}"\n);
    print G qq(    Option "XkbLayout" "$O->{xkb_keymap}"\n);
    print F join '', map { "    $_\n" } @{$xkb_options{$O->{xkb_keymap}} || []};
    print G join '', map { /(\S+)(.*)/; qq(    Option "$1" $2\n) } @{$xkb_options{$O->{xkb_keymap}} || []};
    print F $keyboardsection_end;
    print G $keyboardsection_end;

    #- Write pointer section.
    my $pointer = sub {
	my ($O, $id) = @_;
	print F $id > 1 ? qq(Section "XInput"\n) : qq(Section "Pointer"\n);
	$id > 1 and print F qq(    SubSection "Mouse"\n);
	print G qq(Section "InputDevice"\n\n);
	$id > 1 and print F qq(        DeviceName "Mouse$id"\n);
	print G qq(    Identifier  "Mouse$id"\n);
	print G qq(    Driver      "mouse"\n);
	print F ($id > 1 && "    ") . qq(    Protocol    "$O->{XMOUSETYPE}"\n);
	print G qq(    Option "Protocol"    "$O->{XMOUSETYPE}"\n);
	print F ($id > 1 && "    ") . qq(    Device      "/dev/$O->{device}"\n);
	print G qq(    Option "Device"      "/dev/$O->{device}"\n);
	print F "        AlwaysCore\n" if $id > 1;
	#- this will enable the "wheel" or "knob" functionality if the mouse supports it
	print F ($id > 1 && "    ") . "    ZAxisMapping 4 5\n" if $O->{nbuttons} > 3;
	print F ($id > 1 && "    ") . "    ZAxisMapping 6 7\n" if $O->{nbuttons} > 5;
	print G qq(    Option "ZAxisMapping" "4 5"\n) if $O->{nbuttons} > 3;
	print G qq(    Option "ZAxisMapping" "6 7"\n) if $O->{nbuttons} > 5;

	print F "#" unless $O->{nbuttons} < 3;
	print G "#" unless $O->{nbuttons} < 3;
	print F ($id > 1 && "    ") . qq(    Emulate3Buttons\n);
	print G qq(    Option "Emulate3Buttons"\n);
	print F "#" unless $O->{nbuttons} < 3;
	print G "#" unless $O->{nbuttons} < 3;
	print F ($id > 1 && "    ") . qq(    Emulate3Timeout    50\n\n);
	print G qq(    Option "Emulate3Timeout"    "50"\n\n);
	print F "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
	print G "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
	print F "#" unless $O->{chordmiddle};
	print G "#" unless $O->{chordmiddle};
	print F ($id > 1 && "    ") . qq(    ChordMiddle\n\n);
	print G qq(    Option "ChordMiddle"\n\n);
	print F ($id > 1 && "    ") . "    ClearDTR\n" if $O->{cleardtrrts};
	print F ($id > 1 && "    ") . "    ClearRTS\n\n"  if $O->{cleardtrrts};
	$id > 1 and print F qq(    EndSubSection\n);
	print F "EndSection\n\n\n";
	print G "EndSection\n\n\n";
    };
    print F $pointersection_text;
    print G $pointersection_text;
    $pointer->($o->{mouse}, 1);
    $o->{mouse}{auxmouse} and $pointer->($o->{mouse}{auxmouse}, 2);

    #- write module section for version 3.
    if (@{$o->{wacom}} || $o->{card}{Utah_glx}) {
	print F qq(Section "Module"
);
	print F qq(    Load "xf86Wacom.so"\n) if @{$o->{wacom}};
	print F qq(    Load "glx-3.so"\n) if $o->{card}{Utah_glx}; #- glx.so may clash with server version 4.
	print F qq(EndSection

);
    }

    #- write wacom device support.
    foreach (1 .. @{$o->{wacom}}) {
	my $dev = "/dev/" . $o->{wacom}[$_-1];
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

    foreach (1..@{$o->{wacom}}) {
	my $dev = "/dev/" . $o->{wacom}[$_-1];
	print G $dev =~ /input\/event/ ? qq(
Section "InputDevice"
    Identifier	"Stylus$_"
    Driver	"wacom"
    Option	"Type" "stylus"
    Option	"Device" "$dev"
    Option	"Mode" "Absolute"
    Option	"USB" "on"
EndSection
Section "InputDevice"
    Identifier	"Eraser$_"
    Driver	"wacom"
    Option	"Type" "eraser"
    Option	"Device" "$dev"
    Option	"Mode" "Absolute"
    Option	"USB" "on"
EndSection
Section "InputDevice"
    Identifier	"Cursor$_"
    Driver	"wacom"
    Option	"Type" "cursor"
    Option	"Device" "$dev"
    Option	"Mode" "Relative"
    Option	"USB" "on"
EndSection
) : qq(
Section "InputDevice"
    Identifier	"Stylus$_"
    Driver	"wacom"
    Option	"Type" "stylus"
    Option	"Device" "$dev"
    Option	"Mode" "Absolute"
EndSection
Section "InputDevice"
    Identifier	"Eraser$_"
    Driver	"wacom"
    Option	"Type" "eraser"
    Option	"Device" "$dev"
    Option	"Mode" "Absolute"
EndSection
Section "InputDevice"
    Identifier	"Cursor$_"
    Driver	"wacom"
    Option	"Type" "cursor"
    Option	"Device" "$dev"
    Option	"Mode" "Relative"
EndSection
);
    }

    #- write modules section for version 4.
    print G qq(
Section "Module"

# This loads the DBE extension module.
    Load	"dbe"

# This loads the Video for Linux module.
    Load        "v4l"
);
    if ($o->{card}{DRI_glx}) {
	print G qq(
    Load	"glx"
    Load	"dri"
);
    } elsif ($o->{card}{NVIDIA_glx}) {
	print G qq(
# This loads the NVIDIA GLX extension module.
# IT IS IMPORTANT TO KEEP NAME AS FULL PATH TO libglx.so ELSE
# IT WILL LOAD XFree86 glx module and the server will crash.

    Load        "/usr/X11R6/lib/modules/extensions/libglx.so"
);
    }
    print G qq(

# This loads the miscellaneous extensions module, and disables
# initialisation of the XFree86-DGA extension within that module.

    SubSection	"extmod"
	#Option	"omit xfree86-dga"
    EndSubSection

# This loads the Type1 and FreeType font modules

    Load	"type1"
    Load	"freetype"
EndSection
);
    print G qq(

Section "DRI"
    Mode	0666
EndSection

) if $o->{card}{DRI_glx};

    #- Write monitor section.
    $O = $o->{monitor};
    print F $monitorsection_text1;
    print G $monitorsection_text1;
    print F qq(    Identifier "$O->{type}"\n);
    print G qq(    Identifier "$O->{type}"\n);
    print G qq(    UseModes   "Mac Modes"\n) if arch() =~ /ppc/;
    print F qq(    VendorName "$O->{vendor}"\n);
    print G qq(    VendorName "$O->{vendor}"\n);
    print F qq(    ModelName  "$O->{model}"\n\n);
    print G qq(    ModelName  "$O->{model}"\n\n);
    print F $monitorsection_text2;
    print G $monitorsection_text2;
    print F qq(    HorizSync  $O->{hsyncrange}\n\n);
    print G qq(    HorizSync  $O->{hsyncrange}\n\n);
    print F $monitorsection_text3;
    print G $monitorsection_text3;
    print F qq(    VertRefresh $O->{vsyncrange}\n\n);
    print G qq(    VertRefresh $O->{vsyncrange}\n\n);
    print F $monitorsection_text4;
    print F ($O->{modelines} || '') . ($o->{card}{type} eq "TG 96" ?
				       $modelines_text_Trident_TG_96xx : "$modelines_text$modelines_text_ext");
    print G $modelines_text_ext;
    print F "\nEndSection\n\n\n";
    print G "\nEndSection\n\n\n";
    print G $modelines_text_apple if arch() =~ /ppc/;
    foreach (2..@{$o->{card}{cards} || []}) {
	print G qq(Section "Monitor"\n);
	print G qq(    Identifier "monitor$_"\n);
	print G qq(    VendorName "$O->{vendor}"\n);
	print G qq(    ModelName  "$O->{model}"\n\n);
	print G qq(    HorizSync   $O->{hsyncrange}\n);
	print G qq(    VertRefresh $O->{vsyncrange}\n);
	print G qq(EndSection\n\n\n);
    }

    #- Write Device section.
    $O = $o->{card};
    print F $devicesection_text;
    print G $devicesection_text_v4;
    print F qq(Section "Device"\n);
    print F qq(    Identifier  "$O->{type}"\n);
    print F qq(    VendorName  "$O->{vendor}"\n);
    print F qq(    BoardName   "$O->{board}"\n);

    print F "#" if $O->{chipset} && !$O->{flags}{needChipset};
    print F qq(    Chipset     "$O->{chipset}"\n) if $O->{chipset};

    print F "#" if $O->{memory} && !$O->{flags}{needVideoRam};
    print F "    VideoRam    $O->{memory}\n" if $O->{memory};

    print F map { "    $_\n" } @{$O->{lines} || []};

    print F qq(    Ramdac      "$O->{ramdac}"\n) if $O->{ramdac};
    print F qq(    Dacspeed    "$O->{dacspeed}"\n) if $O->{dacspeed};

    if ($O->{clockchip}) {
	print F qq(    Clockchip   "$O->{clockchip}"\n);
    } else {
	print F "    # Clock lines\n";
	print F "    Clocks $_\n" foreach (@{$O->{clocklines}});
    }
    print F qq(

    # Uncomment following option if you see a big white block        
    # instead of the cursor!                                          
    #    Option      "sw_cursor"

);
    my $p_xf3 = sub {
	my $l = $O->{$_[0]};
	map { (!$l->{$_} && '#') . qq(    Option      "$_"\n) } keys %{$l || {}};
    };
    my $p_xf4 = sub {
	my $l = $O->{$_[0]};
	map { (! defined $l->{$_} && '#') . qq(    Option      "$_"  "$l->{$_}"\n) } keys %{$l || {}};
    };
    print F $p_xf3->('options');
    print F $p_xf3->('options_xf3');
    print F "EndSection\n\n\n";

    #- configure all drivers here!
    foreach (@{$O->{cards} || [ $O ]}) {
	print G qq(Section "Device"\n);
	print G qq(    Identifier  "$_->{type}"\n);
	print G qq(    VendorName  "$_->{vendor}"\n);
	print G qq(    BoardName   "$_->{board}"\n);
	print G qq(    Driver      "$_->{driver}"\n);
	print G "#" if $_->{memory} && !$_->{flags}{needVideoRam};
	print G "    VideoRam    $_->{memory}\n" if $_->{memory};
	print G map { "    $_\n" } @{$_->{lines} || []};
	print G qq(    Ramdac      "$_->{ramdac}"\n) if $_->{ramdac};
	print G qq(    Dacspeed    "$_->{dacspeed}"\n) if $_->{dacspeed};
	if ($_->{clockchip}) {
	    print G qq(    Clockchip   "$_->{clockchip}"\n);
	} else {
	    print G "    # Clock lines\n";
	    print G "    Clocks $_\n" foreach (@{$_->{clocklines}});
	}
	print G qq(

    # Uncomment following option if you see a big white block        
    # instead of the cursor!                                          
    #    Option      "sw_cursor"

);
	print G $p_xf3->('options'); #- keep $O for these!
	print G $p_xf4->('options_xf4'); #- keep $O for these!
	print G qq(    Screen $_->{screen}\n) if defined $_->{screen};
	print G qq(    BusID       "$_->{busid}"\n) if $_->{busid};
        if ((arch =~ /ppc/) && ($_->{driver} eq "r128")) {
            print G qq(    Option    "UseFBDev"\n);
        }
	print G "EndSection\n\n\n";
    }

    #- Write Screen sections.
    print F $screensection_text1, "\n";
    print G $screensection_text1, "\n";

    my $subscreen = sub {
	my ($f, $server, $defdepth, $depths) = @_;
	print $f "    DefaultColorDepth $defdepth\n" if $defdepth;

        foreach (ikeys(%$depths)) {
	    my $m = $server ne "fbdev" ? join(" ", map { qq("$_->[0]x$_->[1]") } @{$depths->{$_}}) : qq("default"); #-"
	    print $f qq(    Subsection "Display"\n);
	    print $f qq(        Depth       $_\n) if $_;
	    print $f qq(        Modes       $m\n);
	    print $f qq(        ViewPort    0 0\n);
	    print $f qq(    EndSubsection\n);
	}
	print $f "EndSection\n";
    };

    my $screen = sub {
	my ($server, $defdepth, $device, $depths) = @_;
	print F qq(
Section "Screen"
    Driver "$server"
    Device      "$device"
    Monitor     "$o->{monitor}{type}"
); #-"
	$subscreen->(*F, $server, $defdepth, $depths);
    };

    #- SVGA screen section.
    print F qq(
# The Colour SVGA server
);

    if (member($O->{server}, @svgaservers)) {
	&$screen("svga", $o->{default_depth}, $O->{type}, $O->{depth});
    } else {
	&$screen("svga", '', "Generic VGA", { 8 => [[ 320, 200 ]] });
    }

    &$screen("vga16", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("vga2", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("accel", $o->{default_depth}, $O->{type}, $O->{depth});

    &$screen("fbdev", $o->{default_depth}, $O->{type}, $O->{depth});

    print G qq(
Section "Screen"
    Identifier "screen1"
    Device      "$O->{type}"
    Monitor     "$o->{monitor}{type}"
);
    #- hack for DRI with Matrox card at 24 bpp, need another command.
    $O->{DRI_glx} && $O->{identifier} =~ /Matrox.* G[245][05]0/ && $o->{default_depth} == 24 and
      print G "    DefaultFbBpp      32\n";
    #- bpp 32 not handled by XF4
    $subscreen->(*G, "svga", min($o->{default_depth}, 24), $O->{depth});
    foreach (2..@{$O->{cards} || []}) {
	my $device = $O->{cards}[$_ - 1]{type};
	print G qq(
Section "Screen"
    Identifier "screen$_"
    Device      "$device"
    Monitor     "monitor$_"
);
	#- hack for DRI with Matrox card at 24 bpp, need another command.
	$O->{DRI_glx} && $O->{identifier} =~ /Matrox.* G[245][05]0/ && $o->{default_depth} == 24 and
	  print G "    DefaultFbBpp      32\n";
	#- bpp 32 not handled by XF4
	$subscreen->(*G, "svga", min($o->{default_depth}, 24), $O->{depth});
    }

    print G qq(

Section "ServerLayout"
    Identifier "layout1"
    Screen     "screen1"
);
    foreach (2..@{$O->{cards} || []}) {
	my ($curr, $prev) = ($_, $_ - 1);
	print G qq(    Screen     "screen$curr" RightOf "screen$prev"\n);
    }
    print G '#' if defined $O->{Xinerama} && !$O->{Xinerama};
    print G qq(    Option     "Xinerama" "on"\n) if defined $O->{Xinerama};

    print G '
    InputDevice "Mouse1" "CorePointer"
';
    $o->{mouse}{auxmouse} and print G '
    InputDevice "Mouse2" "SendCoreEvents"
';
    foreach (1..@{$o->{wacom}}) {
	print G qq(
    InputDevice "Stylus$_" "AlwaysCore"
    InputDevice "Eraser$_" "AlwaysCore"
    InputDevice "Cursor$_" "AlwaysCore"
);
    }
    print G '
    InputDevice "Keyboard1" "CoreKeyboard"
EndSection
'; #-"

    close F;
    close G;
}

sub XF86check_link {
    my ($ext) = @_;

    my $f = "$prefix/etc/X11/XF86Config$ext";
    touch($f);

    my $l = "$prefix/usr/X11R6/lib/X11/XF86Config$ext";

    if (-e $l && (stat($f))[1] != (stat($l))[1]) { #- compare the inode, must be the sames
	-e $l and unlink($l) || die "can't remove bad $l";
	symlinkf "../../../../etc/X11/XF86Config$ext", $l;
    }
}

sub info {
    my ($o) = @_;
    my $info;
    my $xf_ver = $o->{card}{use_xf4} ? "4.2.0" : "3.3.6";
    my $title = ($o->{card}{DRI_glx} || $o->{card}{NVIDIA_glx} || $o->{Utah_glx} ?
		 _("XFree %s with 3D hardware acceleration", $xf_ver) : _("XFree %s", $xf_ver));

    $info .= _("Keyboard layout: %s\n", $o->{keyboard}{xkb_keymap});
    $info .= _("Mouse type: %s\n", $o->{mouse}{XMOUSETYPE});
    $info .= _("Mouse device: %s\n", $o->{mouse}{device}) if $::expert;
    $info .= _("Monitor: %s\n", $o->{monitor}{type});
    $info .= _("Monitor HorizSync: %s\n", $o->{monitor}{hsyncrange}) if $::expert;
    $info .= _("Monitor VertRefresh: %s\n", $o->{monitor}{vsyncrange}) if $::expert;
    $info .= _("Graphic card: %s\n", $o->{card}{type});
    $info .= _("Graphic card identification: %s\n", $o->{card}{identifier}) if $::expert;
    $info .= _("Graphic memory: %s kB\n", $o->{card}{memory}) if $o->{card}{memory};
    if ($o->{default_depth} and my $depth = $o->{card}{depth}{$o->{default_depth}}) {
	$info .= _("Color depth: %s\n", translate($depths{$o->{default_depth}}));
	$info .= _("Resolution: %s\n", join "x", @{$depth->[0]}) if $depth && !is_empty_array_ref($depth->[0]);
    }
    $info .= _("XFree86 server: %s\n", $o->{card}{server}) if $o->{card}{server};
    $info .= _("XFree86 driver: %s\n", $o->{card}{driver}) if $o->{card}{driver};
    "$title\n\n$info";
}

sub show_info {
    my ($o) = @_;
    $in->ask_warn('', info($o));
}

#- Program entry point.
sub main {
    ($prefix, my $o, $in, $do_pkgs, my $cardOptions) = @_;
    $o ||= {};

    XF86check_link('');
    XF86check_link('-4');

    {
	my $w = $in->wait_message('', _("Preparing X-Window configuration"), 1);

	$o->{card} = cardConfiguration($o->{card}, $::noauto, $cardOptions);

	$o->{monitor} = monitorConfiguration($o->{monitor}, $o->{card}{server} eq 'FBDev');
    }
    my $ok = resolutionsConfiguration($o, $::auto);

    $ok &&= testFinalConfig($o, $::auto, $o->{skiptest}, $::auto);

    my $quit;
    until ($ok || $quit) {
	ref($in) =~ /discard/ and die "automatic X configuration failed, ensure you give hsyncrange and vsyncrange with non-DDC aware videocards/monitors";

	$in->set_help('configureXmain') unless $::isStandalone;

	my $f;
	$in->ask_from_(
		{ 
		 title => 'XFdrake',
		 messages => _("What do you want to do?"),
		 cancel => '',
		}, [
		    { format => sub { $_[0][0] }, val => \$f,
		      list => [
	   [ _("Change Monitor") => sub { $o->{monitor} = monitorConfiguration() } ],
           [ _("Change Graphic card") => sub { my $card = cardConfiguration('', 'noauto', $cardOptions);
					       $card and $o->{card} = $card } ],
                    if_($::expert, 
           [ _("Change Server options") => sub { optionsConfiguration($o) } ]),
	   [ _("Change Resolution") => sub { resolutionsConfiguration($o) } ],
	   [ _("Show information") => sub { show_info($o) } ],
	   [ _("Test again") => sub { $ok = testFinalConfig($o, 1) } ],
	   [ _("Quit") => sub { $quit = 1 } ],
			       ],
		    }
		   ]);
	$f->[1]->();
	$in->kill;
    }
    if (!$ok) {
	$ok = $in->ask_yesorno('', _("Keep the changes?
Current configuration is:

%s", info($o)));
    }
    if ($ok) {
	unless ($::testing) {
	    my $f = "$prefix/etc/X11/XF86Config";
	    if (-e "$f.test") {
		rename $f, "$f.old" or die "unable to make a backup of XF86Config";
		rename "$f-4", "$f-4.old";
		rename "$f.test", $f;
		rename "$f.test-4", "$f-4";
		if ($o->{card}{server} !~ /Xpmac/) {
		    symlinkf "../..$o->{card}{prog}", "$prefix/etc/X11/X";
		}
	    }
	}

	if (!$::isStandalone || $0 !~ /Xdrakres/) {
	    $in->set_help('configureXxdm') unless $::isStandalone;
	    my $run = exists $o->{xdm} ? $o->{xdm} : $::auto || $in->ask_yesorno(_("X at startup"),
_("I can set up your computer to automatically start X upon booting.
Would you like X to start when you reboot?"), 1);
	    any::runlevel($prefix, $run ? 5 : 3) unless $::testing;
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
  		        system("killall X ; killall -15 xdm gdm kdm prefdm") unless `pidof "$wm"` > 0;
  		    }, $wm;
		}
	    } else {
		$in->ask_warn('', _("Please log out and then use Ctrl-Alt-BackSpace"));
	    }
	} 
    }
}

1;
