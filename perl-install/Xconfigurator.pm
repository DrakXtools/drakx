package Xconfigurator;

use diagnostics;
use strict;
use vars qw($in $install $isLaptop $resolution_wanted @window_managers @depths @monitorSize2resolution @hsyncranges %min_hsync4wres @vsyncranges %depths @resolutions %serversdriver @svgaservers @accelservers @allbutfbservers @allservers %vgamodes %videomemory @ramdac_name @ramdac_id @clockchip_name @clockchip_id %keymap_translate %standard_monitors $intro_text $finalcomment_text $s3_comment $cirrus_comment $probeonlywarning_text $monitorintro_text $hsyncintro_text $vsyncintro_text $XF86firstchunk_text $keyboardsection_start $keyboardsection_part2 $keyboardsection_part3 $keyboardsection_end $pointersection_text1 $pointersection_text2 $monitorsection_text1 $monitorsection_text2 $monitorsection_text3 $monitorsection_text4 $modelines_text_Trident_TG_96xx $modelines_text $devicesection_text $screensection_text1 %lines @options %xkb_options $default_monitor);

use pci_probing::main;
use common qw(:common :file :functional :system);
use log;
use run_program;
use Xconfigurator_consts;
use my_gtk qw(:wrappers);

my $tmpconfig = "/tmp/Xconfig";

my ($prefix, %monitors);

1;

sub getVGAMode($) { $_[0]->{card}{vga_mode} || $vgamodes{"640x480x16"}; }

sub setVirtual($) {
    my $vt = '';
    local *C;
    sysopen C, "/dev/console", 2 or die "failed to open /dev/console: $!";
    ioctl(C, c::VT_GETSTATE(), $vt) or die "ioctl VT_GETSTATE failed";
    ioctl(C, c::VT_ACTIVATE(), $_[0]) or die "ioctl VT_ACTIVATE failed";
    ioctl(C, c::VT_WAITACTIVE(), $_[0]) or die "ioctl VT_WAITACTIVE failed";
    unpack "S", $vt;
}

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    local *F;
    open F, $file or die "file $file not found";

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
	    $card->{flags}{needVideoRam} = 1 if member($val, qw(mgag10 mgag200 RIVA128));
	},
	SERVER => sub { $card->{server} = $val; },
	RAMDAC => sub { $card->{ramdac} = $val; },
	DACSPEED => sub { $card->{dacspeed} = $val; },
	CLOCKCHIP => sub { $card->{clockchip} = $val; $card->{flags}{noclockprobe} = 1; },
	NOCLOCKPROBE => sub { $card->{flags}{noclockprobe} = 1 },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	COMMENT => sub {},
    };

    foreach (<F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and last;

	($cmd, $val) = /(\S+)\s*(.*)/ or next; #log::l("bad line $lineno ($_)"), next;

	my $f = $fs->{$cmd};

	$f ? &$f() : log::l("unknown line $lineno ($_)");
    }
    push @{$cards{S3}{lines}}, $s3_comment;
    push @{$cards{'CL-GD'}{lines}}, $cirrus_comment;

    #- this entry is broken in X11R6 cards db
    $cards{I128}{flags}{noclockprobe} = 1;
    \%cards;
}
sub readCardsNames {
    my $file = "$prefix/usr/X11R6/lib/X11/CardsNames";
    local *F; open F, $file or die "can't find $file\n";
    map { (split '=>')[0] } <F>;
}
sub cardName2RealName {
    my $file = "$prefix/usr/X11R6/lib/X11/CardsNames";
    my ($name) = @_;
    local *F; open F, $file or die "can't find $file\n";
    foreach (<F>) { chop;
	my ($name_, $real) = split '=>';
	return $real if $name eq $name_;
    }
    $name;
}
sub cardName2card {
    my ($name) = @_;
    readCardsDB("$prefix/usr/X11R6/lib/X11/Cards")->{$name};
}

sub readMonitorsDB {
    my ($file) = @_;

    %monitors and return;

    local *F;
    open F, $file or die "can't open monitors database ($file): $!";
    my $lineno = 0; foreach (<F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(type bandwidth hsyncrange vsyncrange);
	my @l = split /\s*;\s*/;
	@l == @fields or log::l("bad line $lineno ($_)"), next;

	my %l; @l{@fields} = @l;
	if ($monitors{$l{type}}) {
	    my $i; for ($i = 0; $monitors{"$l{type} ($i)"}; $i++) {}
	    $l{type} = "$l{type} ($i)";
	}
	$monitors{$l{type}} = \%l;
    }
    while (my ($k, $v) = each %standard_monitors) {
	$monitors{_("Generic") . "|" . translate($k)} =
	    { hsyncrange => $v->[1], vsyncrange => $v->[2] };
    }
}

sub rewriteInittab {
    my ($runlevel) = @_;
    my $f = "$prefix/etc/inittab";
    -r $f or log::l("missing inittab!!!"), return;
    substInFile { s/^(id:)[35](:initdefault:)\s*$/$1$runlevel$2\n/ } $f;
}

sub keepOnlyLegalModes {
    my ($card, $monitor) = @_;
    my $mem = 1024 * ($card->{memory} || ($card->{server} eq 'FBDev' ? 2048 : 99999));
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
    my $card;
    if (my ($c) = pci_probing::main::probe("DISPLAY")) {
	local $_;
	($card->{identifier}, $_) = @$c;
	$card->{type} = $1 if /Card:(.*)/;
	$card->{server} = $1 if /Server:(.*)/;
	$card->{flags}{needVideoRam} &&= /86c368/;
	push @{$card->{lines}}, @{$lines{$card->{identifier}} || []};
    }
    $card;
}

sub cardConfiguration(;$$$) {
    my ($card, $noauto, $allowFB) = @_;
    $card ||= {};

    add2hash($card, cardName2card($card->{type})) if $card->{type}; #- try to get info from given type
    undef $card->{type} unless $card->{server}; #- bad type as we can't find the server
    add2hash($card, cardConfigurationAuto()) unless $card->{server} || $noauto;
    $card->{server} = 'FBDev' unless !$allowFB || $card->{server} || $card->{type} || $noauto;
    $card->{type} = cardName2RealName($in->ask_from_treelist(_("Graphic card"), _("Select a graphic card"), '|', ['Unlisted', readCardsNames()])) unless $card->{type} || $card->{server};
    undef $card->{type}, $card->{server} = $in->ask_from_list(_("X server"), _("Choose a X server"), $allowFB ? \@allservers : \@allbutfbservers ) if $card->{type} eq "Unlisted";

    add2hash($card, cardName2card($card->{type})) if $card->{type};
    add2hash($card, { vendor => "Unknown", board => "Unknown" });

    $card->{prog} = "/usr/X11R6/bin/XF86_$card->{server}";

    -x "$prefix$card->{prog}" or $install && do {
	$in->suspend;
	&$install($card->{server});
	$in->resume;
    };
    -x "$prefix$card->{prog}" or die "server $card->{server} is not available (should be in $prefix$card->{prog})";

    unless ($card->{type}) {
	$card->{flags}{noclockprobe} = member($card->{server}, qw(I128 S3 S3V Mach64));
    }
    $card->{options}{power_saver} = 1;

    $card->{flags}{needVideoRam} and
      $card->{memory} ||=
	$videomemory{$in->ask_from_list_('',
					 _("Select the memory size of your graphic card"),
					 [ sort { $videomemory{$a} <=> $videomemory{$b} }
					   keys %videomemory])};
    $card;
}

sub optionsConfiguration($) {
    my ($o) = @_;
    my @l;
    my %l;

    foreach (@options) {
	if ($o->{card}{server} eq $_->[1] && $o->{card}{identifier} =~ /$_->[2]/) {
	    $o->{card}{options}{$_->[0]} ||= 0;
	    unless ($l{$_->[0]}) {
		push @l, $_->[0], { val => \$o->{card}{options}{$_->[0]}, type => 'bool' };
		$l{$_->[0]} = 1;
	    }
	}
    }
    @l = @l[0..19] if @l > 19; #- reduce list size to 10 for display (it's a hash).

    $in->ask_from_entries_refH('', _("Choose options for server"), \@l);
}

sub monitorConfiguration(;$$) {
    my $monitor = shift || {};
    my $useFB = shift || 0;

    if ($useFB) {
	#- use smallest values for monitor configuration since FB is used,
	#- BIOS initialize graphics, current X server will not refuse that.
	$monitor->{hsyncrange} ||= $hsyncranges[0];
	$monitor->{vsyncrange} ||= $vsyncranges[0];
	add2hash($monitor, { type => "Unknown", vendor => "Unknown", model => "Unknown" });
    } else {
	$monitor->{hsyncrange} && $monitor->{vsyncrange} and return $monitor;

	readMonitorsDB("/usr/X11R6/lib/X11/MonitorsDB");

	add2hash($monitor, { type => $in->ask_from_treelist(_("Monitor"), _("Choose a monitor"), '|', ['Unlisted', keys %monitors], _("Generic") . '|' . translate($default_monitor)) }) unless $monitor->{type};
	if ($monitor->{type} eq 'Unlisted') {
	    $in->ask_from_entries_ref('',
_("The two critical parameters are the vertical refresh rate, which is the rate
at which the whole screen is refreshed, and most importantly the horizontal
sync rate, which is the rate at which scanlines are displayed.

It is VERY IMPORTANT that you do not specify a monitor type with a sync range
that is beyond the capabilities of your monitor: you may damage your monitor.
 If in doubt, choose a conservative setting."),
				      [ _("Horizontal refresh rate"), _("Vertical refresh rate") ],
				      [ { val => \$monitor->{hsyncrange}, list => \@hsyncranges },
					{ val => \$monitor->{vsyncrange}, list => \@vsyncranges }, ]);
	} else {
	    add2hash($monitor, $monitors{$monitor->{type}});
	}
	add2hash($monitor, { type => "Unknown", vendor => "Unknown", model => "Unknown" });
    }

    $monitor;
}

sub testConfig($) {
    my ($o) = @_;
    my ($resolutions, $clocklines);

    write_XF86Config($o, $tmpconfig);

    unlink "/tmp/.X9-lock";
    #- restart_xfs;

    local *F;
    open F, "$prefix$o->{card}{prog} :9 -probeonly -pn -xf86config $tmpconfig 2>&1 |";
    foreach (<F>) {
	$o->{card}{memory} ||= $2 if /(videoram|Video RAM):\s*(\d*)/;

	# look for clocks
	push @$clocklines, $1 if /clocks: (.*)/ && !/(pixel |num)clocks:/;

	push @$resolutions, [ $1, $2 ] if /: Mode "(\d+)x(\d+)": mode clock/;
	print;
    }
    close F or die "X probeonly failed";

    ($resolutions, $clocklines);
}

sub testFinalConfig($;$$) {
    my ($o, $auto, $skiptest) = @_;

    $o->{monitor}{hsyncrange} && $o->{monitor}{vsyncrange} or
      $in->ask_warn('', _("Monitor not configured")), return;

    $o->{card}{server} or
      $in->ask_warn('', _("Graphic card not configured yet")), return;

    $o->{card}{depth} or
      $in->ask_warn('', _("Resolutions not chosen yet")), return;

    my $f = "/etc/X11/XF86Config.test";
    write_XF86Config($o, $::testing ? $tmpconfig : "$prefix/$f");

    $skiptest || $o->{card}{server} eq 'FBDev' and return 1; #- avoid testing since untestable without reboot.

    #- needed for bad cards not restoring cleanly framebuffer
    my $bad_card = $o->{card}{identifier} =~ /i740|ViRGE/;
    log::l("the graphic card does not like X in framebuffer") if $bad_card;

    my $mesg = _("Do you want to test the configuration?");
    my $def = 1;
    if ($bad_card && !$::isStandalone) {
	!$::expert || $auto and return 1;
	$mesg = $mesg . "\n" . _("Warning: testing is dangerous on this graphic card");
	$def = 0;
    }
    $auto && $def or $in->ask_yesorno(_("Test configuration"), $mesg, $def) or return 1;

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
	open STDERR, ">$f_err";
	chroot $prefix if $prefix;
	exec $o->{card}{prog}, 
	  "-xf86config", $::testing ? $tmpconfig : $f, 
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until c::Xtest(":9") || waitpid($pid, c::WNOHANG());

    my $b = before_leaving { unlink $f_err };

    unless (c::Xtest(":9")) {
	local $_;
	local *F; open F, $f_err;
      i: while (<F>) {
	    if (/\b(error|not supported)\b/i) {
		my @msg = !/error/ && $_ ;
		while (<F>) {
		    /not fatal/ and last i;
		    /^$/ and last;
		    push @msg, $_;
		}
		$in->ask_warn('', [ _("An error occurred:"), " ", @msg, _("\ntry changing some parameters") ]);
		return 0;
	    }
	}
    }

    local *F;
    open F, "|perl" or die '';
    print F "use lib qw(", join(' ', @INC), ");\n";
    print F q{
	use interactive_gtk;
        use my_gtk qw(:wrappers);

	$ENV{DISPLAY} = ":9";

        gtkset_mousecursor(68);
        gtkset_background(200 * 256, 210 * 256, 210 * 256);
        my ($h, $w) = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW)->get_size;
        $my_gtk::force_position = [ $w / 3, $h / 2.4 ];
	$my_gtk::force_focus = 1;
        my $text = Gtk::Label->new;
        my $time = 8;
        Gtk->timeout_add(1000, sub {
	    $text->set(_("(leaving in %d seconds)", $time));
	    $time-- or Gtk->main_quit;
	});

	exit (interactive_gtk->new->ask_yesorno('', [ _("Is this correct?"), $text ], 0) ? 0 : 222);
    };
    my $rc = close F;
    my $err = $?;

    unlink "/tmp/.X11-unix/X9" if $prefix;
    kill 2, $pid;

    $rc || $err == 222 << 8 or $in->ask_warn('', _("An error occurred, try changing some parameters"));
    $rc;
}

sub autoResolutions($;$) {
    my ($o, $nowarning) = @_;
    my $card = $o->{card};

    $nowarning || $in->ask_okcancel(_("Automatic resolutions"),
_("To find the available resolutions I will try different ones.
Your screen will blink...
You can switch if off if you want, you'll hear a beep when it's over"), 1) or return;

    #- swith to virtual console 1 (hopefully not X :)
    my $vt = setVirtual(1);

    #- Configure the modes order.
    my ($ok, $best);
    foreach (reverse @depths) {
	local $card->{default_depth} = $_;

	my ($resolutions, $clocklines) = eval { testConfig($o) };
	if ($@ || !$resolutions) {
	    delete $card->{depth}{$_};
	} else {
	    $card->{clocklines} ||= $clocklines unless $card->{flags}{noclockprobe};
	    $card->{depth}{$_} = [ @$resolutions ];
	}
    }

    #- restore the virtual console
    setVirtual($vt);
    print "\a"; #- beeeep!
}

sub autoDefaultDepth($$) {
    my ($card, $wres_wanted) = @_;
    my ($best, $depth);

    return 24 if $card->{identifier} =~ /SiS/;

    if ($card->{server} eq 'FBDev') {
	return 16; #- this should work by default, FBDev is allowed only if install currently uses it at 16bpp.
    }

    while (my ($d, $r) = each %{$card->{depth}}) {
	$depth = max($depth || 0, $d);

	#- try to have $resolution_wanted
	$best = max($best || 0, $d) if $r->[0][0] >= $wres_wanted;
    }
    $best || $depth or die "no valid modes";
}

sub autoDefaultResolution {
    return "1024x768" if $isLaptop;

    my ($size) = @_;
    $monitorSize2resolution[round($size || 14)] || #- assume a small monitor (size is in inch)
      $monitorSize2resolution[-1]; #- no corresponding resolution for this size. It means a big monitor, take biggest we have
}

sub chooseResolutionsGtk($$;$) {
    my ($card, $chosen_depth, $chosen_w) = @_;
    my $W = my_gtk->new(_("Resolution"));
    my %txt2depth = reverse %depths;
    my ($r, $depth_combo, %w2depth, %w2h, %w2widget);

    my $best_w;
    while (my ($depth, $res) = each %{$card->{depth}}) {
	foreach (@$res) {
	    $w2h{$_->[0]} = $_->[1];
	    push @{$w2depth{$_->[0]}}, $depth;

	    $best_w = max($_->[0], $best_w) if $_->[0] <= $chosen_w;
	}
    }
    $chosen_w = $best_w;

    my $set_depth = sub { $depth_combo->entry->set_text(translate($depths{$chosen_depth})) };

    #- the set function is usefull to toggle the CheckButton with the callback being ignored
    my $ignore;
    my $set = sub { $ignore = 1; $_[0]->set_active(1); $ignore = 0; };

    while (my ($w, $h) = each %w2h) {
	my $V = $w . "x" . $h;
	$w2widget{$w} = $r = new Gtk::RadioButton($r ? ($V, $r) : $V);
	&$set($r) if $chosen_w == $w;
	$r->signal_connect("clicked" => sub {
			       $ignore and return;
			       $chosen_w = $w;
			       unless (member($chosen_depth, @{$w2depth{$w}})) {
				   $chosen_depth = max(@{$w2depth{$w}});
				   &$set_depth();
			       }
			   });
    }
    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(_("Choose resolution and color depth"),
					      "(" . ($card->{type} ? 
						     _("Graphic card: %s", $card->{type}) :
						     _("XFree86 server: %s", $card->{server})) . ")"
					     ),
		    1, gtkpack(new Gtk::HBox(0,20),
			       $depth_combo = new Gtk::Combo,
			       gtkpack_(new Gtk::VBox(0,0),
					map {; 0, $w2widget{$_} } ikeys(%w2widget),
					),
			       ),
		    0, gtkadd($W->create_okcancel,
			      gtksignal_connect(new Gtk::Button(_("Show all")), clicked => sub { $W->{retval} = 1; $chosen_w = 0; Gtk->main_quit })),
		    ));
    $depth_combo->disable_activate;
    $depth_combo->set_use_arrows_always(1);
    $depth_combo->entry->set_editable(0);
    $depth_combo->set_popdown_strings(map { translate($depths{$_}) } ikeys(%{$card->{depth}}));
    $depth_combo->entry->signal_connect(changed => sub {
       $chosen_depth = $txt2depth{untranslate($depth_combo->entry->get_text, keys %txt2depth)};
       my $w = $card->{depth}{$chosen_depth}[0][0];
       $chosen_w > $w and &$set($w2widget{$chosen_w = $w});
    });
    &$set_depth();
    $W->{ok}->grab_focus;

    $W->main or return;
    ($chosen_depth, $chosen_w);
}

sub chooseResolutions($$;$) {
    goto &chooseResolutionsGtk if ref($in) =~ /gtk/;

    my ($card, $chosen_depth, $chosen_w) = @_;

    my $best_w;
    local $_ = $in->ask_from_list(_("Resolutions"), "", 
				  [ map_each { map { "$_->[0]x$_->[1] ${main::a}bpp" } @$::b } %{$card->{depth}} ]) or return;
    reverse /(\d+)x\S+ (\d+)/;
}


sub resolutionsConfiguration($%) {
    my ($o, %options) = @_;
    my $card = $o->{card};

    #- For the mono and vga16 server, no further configuration is required.
    if (member($card->{server}, "Mono", "VGA16")) {
	$card->{depth}{8} = [[ 640, 480 ]];
	return;
    }

    #- some of these guys hate to be poked
    #- if we dont know then its at the user's discretion
    #-my $manual ||=
    #-	$card->{server} =~ /^(TGA|Mach32)/ ||
    #-	$card->{name} =~ /^Riva 128/ ||
    #-	$card->{chipset} =~ /^(RIVA128|mgag)/ ||
    #-	$::expert;
    #-
    #-my $unknown =
    #-	member($card->{server}, qw(S3 S3V I128 Mach64)) ||
    #-	member($card->{type},
    #-	       "Matrox Millennium (MGA)",
    #-	       "Matrox Millennium II",
    #-	       "Matrox Millennium II AGP",
    #-	       "Matrox Mystique",
    #-	       "Matrox Mystique",
    #-	       "S3",
    #-	       "S3V",
    #-	       "I128",
    #-	      ) ||
    #-	$card->{type} =~ /S3 ViRGE/;
    #-
    #-$unknown and $manual ||= !$in->ask_okcancel('', [ _("I can try to autodetect information about graphic card, but it may freeze :("),
    #-							_("Do you want to try?") ]);

    if (is_empty_hash_ref($card->{depth})) {
	$card->{depth}{$_} = [ map { [ split "x" ] } @resolutions ]
	  foreach @depths;

	unless ($options{noauto}) {
	    if ($options{nowarning} || $in->ask_okcancel(_("Automatic resolutions"),
_("I can try to find the available resolutions (eg: 800x600).
Sometimes, though, it may hang the machine.
Do you want to try?"), 1)) {
		autoResolutions($o, $options{nowarning});
		is_empty_hash_ref($card->{depth}) and $in->ask_warn('',
_("No valid modes found
Try with another video card or monitor")), return;
	    }
	}
    }

    #- sort resolutions in each depth
    foreach (values %{$card->{depth}}) {
	my $i = 0;
	@$_ = grep { first($i != $_->[0], $i = $_->[0]) }
	  sort { $b->[0] <=> $a->[0] } @$_;
    }

    #- remove unusable resolutions (based on the video memory size and the monitor hsync rate)
    keepOnlyLegalModes($card, $o->{monitor});

    my $res = $o->{resolution_wanted} || autoDefaultResolution($o->{monitor}{size});
    my $wres = first(split 'x', $res);

    #- take the first available resolution <= the wanted resolution
    $wres = max map { first(grep { $_->[0] <= $wres } @$_)->[0] } values %{$card->{depth}};
    my $depth = eval { $card->{default_depth} || autoDefaultDepth($card, $wres) };

    $options{auto} or ($depth, $wres) = chooseResolutions($card, $depth, $wres) or return;

    unless ($wres) {
	delete $card->{depth};
	return resolutionsConfiguration($o, noauto => 1);
    }

    #- needed in auto mode when all has been provided by the user
    $card->{depth}{$depth} or die "you selected an unusable depth";

    #- remove all biggest resolution (keep the small ones for ctl-alt-+)
    #- otherwise there'll be a virtual screen :(
    $card->{depth}{$depth} = [ grep { $_->[0] <= $wres } @{$card->{depth}{$depth}} ];
    $card->{default_depth} = $depth;
    $card->{default_wres} = $wres;
    $card->{vga_mode} = $vgamodes{"${wres}xx$depth"} || $vgamodes{"${res}x$depth"}; #- for use with frame buffer.
    1;
}


#- Create the XF86Config file.
sub write_XF86Config {
    my ($o, $file) = @_;
    my $O;

    local *F;
    open F, ">$file" or die "can't write XF86Config in $file: $!";

    print F $XF86firstchunk_text;

    #- Write keyboard section.
    $O = $o->{keyboard};
    print F $keyboardsection_start;

    print F "    RightAlt        ", ($O->{altmeta} ? "ModeShift" : "Meta"), "\n";
    print F $keyboardsection_part2;
    print F "    XkbDisable\n" unless $O->{xkb_keymap};
    print F $keyboardsection_part3;
    print F qq(    XkbLayout       "$O->{xkb_keymap}"\n);
    print F join '', map { "    $_\n" } @{$xkb_options{$O->{xkb_keymap}} || []};
    print F $keyboardsection_end;

    #- Write pointer section.
    $O = $o->{mouse};
    print F $pointersection_text1;
    print F qq(    Protocol    "$O->{XMOUSETYPE}"\n);
    print F qq(    Device      "/dev/$O->{device}"\n);
    #- this will enable the "wheel" or "knob" functionality if the mouse supports it
    print F "    ZAxisMapping 4 5\n" if
      member($O->{XMOUSETYPE}, qw(IntelliMouse IMPS/2 ThinkingMousePS/2 NetScrollPS/2 NetMousePS/2 MouseManPlusPS/2));

    print F $pointersection_text2;
    print F "#" unless $O->{XEMU3};
    print F "    Emulate3Buttons\n";
    print F "#" unless $O->{XEMU3};
    print F "    Emulate3Timeout    50\n\n";
    print F "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
    print F "#" unless $O->{chordmiddle};
    print F "    ChordMiddle\n\n";
    print F "    ClearDTR\n" if $O->{cleardtrrts};
    print F "    ClearRTS\n\n"  if $O->{cleardtrrts};
    print F "EndSection\n\n\n";

    print F qq(
Section "Module"
   Load "xf86Wacom.so"
EndSection
     
Section "XInput"
    SubSection "WacomStylus"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
    SubSection "WacomCursor"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
    SubSection "WacomEraser"
        Port "/dev/$o->{wacom}"
        AlwaysCore
    EndSubSection
EndSection

) if $o->{wacom};

    #- Write monitor section.
    $O = $o->{monitor};
    print F $monitorsection_text1;
    print F qq(    Identifier "$O->{type}"\n);
    print F qq(    VendorName "$O->{vendor}"\n);
    print F qq(    ModelName  "$O->{model}"\n);
    print F "\n";
    print F $monitorsection_text2;
    print F qq(    HorizSync  $O->{hsyncrange}\n);
    print F "\n";
    print F $monitorsection_text3;
    print F qq(    VertRefresh $O->{vsyncrange}\n);
    print F "\n";
    print F $monitorsection_text4;
    print F ($O->{modelines} || '') . ($o->{card}{type} eq "TG 96" ? $modelines_text_Trident_TG_96xx : $modelines_text);
    print F "\nEndSection\n\n\n";

    #- Write Device section.
    $O = $o->{card};
    print F $devicesection_text;
    print F qq(Section "Device"\n);
    print F qq(    Identifier  "$O->{type}"\n);
    print F qq(    VendorName  "$O->{vendor}"\n);
    print F qq(    BoardName   "$O->{board}"\n);

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

    print F "\n";
    print F map { (!$O->{options}{$_} && '#') . qq(    Option      "$_"\n) } keys %{$O->{options} || {}};
    print F "EndSection\n\n\n";

    #- Write Screen sections.
    print F $screensection_text1;

    my $screen = sub {
	my ($server, $defdepth, $device, $depths) = @_;
	print F qq(

Section "Screen"
    Driver "$server"
    Device      "$device"
    Monitor     "$o->{monitor}{type}"
);
	print F "    DefaultColorDepth $defdepth\n" if $defdepth;

        foreach (ikeys(%$depths)) {
	    my $m = $server ne "fbdev" ? join(" ", map { qq("$_->[0]x$_->[1]") } @{$depths->{$_}}) : qq("default");
	    print F qq(    Subsection "Display"\n);
	    print F qq(        Depth       $_\n) if $_;
	    print F qq(        Modes       $m\n);
	    print F qq(        ViewPort    0 0\n);
	    print F qq(    EndSubsection\n);
	}
	print F "EndSection\n";
    }; #-"

    #- SVGA screen section.
    print F qq(
# The Colour SVGA server
);

    if (member($O->{server}, @svgaservers)) {
	&$screen("svga", $O->{default_depth}, $O->{type}, $O->{depth});
    } else {
	&$screen("svga", '', "Generic VGA", { 8 => [[ 320, 200 ]] });
    }

    &$screen("vga16", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("vga2", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"),
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("accel", $O->{default_depth}, $O->{type}, $O->{depth});

    &$screen("fbdev", $O->{default_depth}, $O->{type}, $O->{depth});
}

sub XF86check_link {
    my ($void) = @_;

    my $f = "$prefix/etc/X11/XF86Config";
    touch($f);

    my $l = "$prefix/usr/X11R6/lib/X11/XF86Config";

    if (-e $l && (stat($f))[1] != (stat($l))[1]) { #- compare the inode, must be the sames
	-e $l and unlink($l) || die "can't remove bad $l";
	symlinkf "../../../../etc/X11/XF86Config", $l;
    }
}

sub show_info {
    my ($o) = @_;
    my $info;

    $info .= _("Keyboard layout: %s\n", $o->{keyboard}{xkb_keymap});
    $info .= _("Mouse type: %s\n", $o->{mouse}{XMOUSETYPE});
    $info .= _("Mouse device: %s\n", $o->{mouse}{device}) if $::expert;
    $info .= _("Monitor: %s\n", $o->{monitor}{type});
    $info .= _("Monitor HorizSync: %s\n", $o->{monitor}{hsyncrange}) if $::expert;
    $info .= _("Monitor VertRefresh: %s\n", $o->{monitor}{vsyncrange}) if $::expert;
    $info .= _("Graphic card: %s\n", $o->{card}{type});
    $info .= _("Graphic memory: %s kB\n", $o->{card}{memory}) if $o->{card}{memory};
    $info .= _("XFree86 server: %s\n", $o->{card}{server});

    $in->ask_warn('', $info);
}

#- Program entry point.
sub main {
    my ($o, $allowFB);
    ($prefix, $o, $in, $allowFB, $isLaptop, $install) = @_;
    $o ||= {};
    
    XF86check_link();

    {
	my $w = $in->wait_message('', _("Preparing X-Window configuration"), 1);

	$o->{card} = cardConfiguration($o->{card}, $::noauto, $allowFB);

	$o->{monitor} = monitorConfiguration($o->{monitor}, $o->{card}{server} eq 'FBDev');
    }
    my $ok = resolutionsConfiguration($o, auto => $::auto, noauto => $::noauto);

    $ok &&= testFinalConfig($o, $::auto, $::skiptest);

    my $quit;
    until ($ok || $quit) {

	my %c = my @c = (
	   __("Change Monitor") => sub { $o->{monitor} = monitorConfiguration() },
           __("Change Graphic card") => sub { $o->{card} = cardConfiguration('', 'noauto', $allowFB) },
           ($::expert ? (__("Change Server options") => sub { optionsConfiguration($o) }) : ()),
	   __("Change Resolution") => sub { resolutionsConfiguration($o, noauto => 1) },
	   __("Automatical resolutions search") => sub {
	       delete $o->{card}{depth};
	       resolutionsConfiguration($o, nowarning => 1);
	   },
	   __("Show information") => sub { show_info($o) },
	   __("Test again") => sub { $ok = testFinalConfig($o, 1) },
	   __("Quit") => sub { $quit = 1 },
        );
	$in->set_help('configureXmain') unless $::isStandalone;
	my $f = $in->ask_from_list_(['XFdrake'],
				 _("What do you want to do?"),
				 [ grep { !ref } @c ]);
	eval { &{$c{$f}} };
	!$@ || $@ =~ /ask_from_list cancel/ or die;
	$in->kill;
    }
    if (!$ok) {
	$ok = !$in->ask_yesorno('', _("Forget the changes?"), 1);
    }
    if ($ok) {
	unless ($::testing) {
	    my $f = "$prefix/etc/X11/XF86Config";
	    if (-e "$f.test") {
		rename $f, "$f.old" or die "unable to make a backup of XF86Config";
		rename "$f.test", $f;
		symlinkf "../..$o->{card}{prog}", "$prefix/etc/X11/X";
	    }
	}

	if ($::isStandalone && $0 =~ /Xdrakres/) {
	    my $found;
	    foreach (@window_managers) {
		if (`pidof $_` > 0) {
		    if ($in->ask_okcancel('', _("Please relog into %s to activate the changes", ucfirst $_), 1)) {
			system("kwmcom logout") if /kwm/;

			open STDIN, "</dev/zero";
			open STDOUT, ">/dev/null";
			open STDERR, ">&STDERR";
			c::setsid();
		        exec qw(perl -e), q{
                          my $wm = shift;
  		          for (my $nb = 30; $nb && `pidof $wm` > 0; $nb--) { sleep 1 }
  		          system("killall X") unless `pidof $wm` > 0;
  		        }, $_;
		    }
		    $found = 1; last;
		}
	    }
	    $in->ask_warn('', _("Please log out and then use Ctrl-Alt-BackSpace")) unless $found;
	} else {
	    $in->set_help('configureXxdm') unless $::isStandalone;
	    my $run = $o->{xdm} || $::auto || $in->ask_yesorno(_("X at startup"),
_("I can set up your computer to automatically start X upon booting.
Would you like X to start when you reboot?"), 1);

	    rewriteInittab($run ? 5 : 3) unless $::testing;
	}
	run_program::rooted($prefix, "chkconfig", "--del", "gpm") if $o->{mouse}{device} =~ /ttyS/ && !$::isStandalone;
    }
}
